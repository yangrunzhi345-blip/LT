import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lt_dialogue/application/llm/llm_gateway.dart';
import 'package:lt_dialogue/application/resources/part_generation_coordinator.dart';
import 'package:lt_dialogue/application/resources/resource_blueprint_repository.dart';
import 'package:lt_dialogue/application/resources/resource_creation_contracts.dart';
import 'package:lt_dialogue/application/resources/resource_creation_pipeline.dart';
import 'package:lt_dialogue/application/resources/resource_generation_task_repository.dart';
import 'package:lt_dialogue/application/resources/resource_revision_repository.dart';
import 'package:lt_dialogue/application/resources/resource_revision_service.dart';
import 'package:lt_dialogue/application/resources/streaming_generation_session_repository.dart';
import 'package:lt_dialogue/application/resources/streaming_resource_generation_service.dart';
import 'package:lt_dialogue/controllers/streaming_resource_generation_controller.dart';
import 'package:lt_dialogue/core/debug/generation_diagnostics.dart';
import 'package:lt_dialogue/domain/resources/resource_blueprint.dart';
import 'package:lt_dialogue/domain/resources/resource_generation_protocol.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/streaming_generation_runtime_contracts.dart';
import 'package:lt_dialogue/features/resource_studio/application/use_cases/resource_studio_runtime.dart';
import 'package:lt_dialogue/features/resource_studio/presentation/controllers/resource_studio_controller.dart';
import 'package:lt_dialogue/models/generation_mode.dart';
import 'package:lt_dialogue/models/llm_task.dart';
import 'package:lt_dialogue/models/scene_batch_candidate.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/llm_service.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository_impl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// P0 freeze investigation: production-like soak tests.
///
/// The real production chain runs end-to-end in ONE Dart process per test:
/// real SQLite repositories, real [ResourceCreationPipeline], real
/// [PartGenerationCoordinator], real [StreamingResourceGenerationService],
/// real [StreamingResourceGenerationController] and the real
/// [ResourceStudioController] event consumption. Only the LLM transport is
/// replaced — by a streaming gateway that emits the same chunk shapes that
/// froze real devices: 1-3 character shards, normal chunks, one giant burst
/// and chunks that split NDJSON lines mid-line.
///
/// No test ever restarts the process: a resource goes 0% → 100% continuously,
/// and the third suite runs three resources back-to-back in the same process.
///
/// After every Part (and after the whole generation) the transient per-part
/// structures must return to zero: preview buffers, dirty Parts, the flush
/// timer, presentation queue depth, service run/task-handle maps.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  setUpAll(() {
    GenerationDiagnostics.printingEnabled = false;
  });

  tearDownAll(() {
    GenerationDiagnostics.printingEnabled = true;
  });

  late Directory tempDir;

  setUp(() async {
    GenerationDiagnostics.instance.resetForTesting();
    tempDir = await Directory.systemTemp.createTemp('lt_soak_test_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test(
    'SOAK 1: 7 sections / 17 parts / 500 patches per part, one process 0→100%',
    () async {
      final rig = await _SoakRig.build(
        name: 'SOAK 十七段连续生成',
        partsPerSection: const [3, 2, 3, 2, 3, 2, 2],
        patchesPerPart: 500,
      );

      await rig.studioController.load();
      await rig.studioController.start();
      await _settlePreviewTimers();

      await rig.expectGenerationCompleted();
      await rig.expectTransientStructuresReleased();

      // Presentation-plane boundedness: the queue must never exceed the
      // coalescing bound and every enqueued callback must be drained or
      // explicitly dropped (never leaked).
      expect(rig.coordinator.presentationMaxQueueDepth, lessThanOrEqualTo(4));
      expect(
        rig.coordinator.presentationDrained +
            rig.coordinator.presentationDropped,
        rig.coordinator.presentationEnqueued,
      );
      // The burst/tiniest-chunk parts necessarily overflow the bound; the
      // coalescing must have dropped stale snapshots instead of growing.
      expect(rig.coordinator.presentationDropped, greaterThan(0));

      // Protocol plane stayed full-rate: every patch was decoded.
      expect(rig.gateway.patchLinesDispatched, 17 * (500 + 2));

      rig.dispose();
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'SOAK 2: 10 sections / 50 parts / 200 patches per part, one process',
    () async {
      final rig = await _SoakRig.build(
        name: 'SOAK 五十段长跑',
        partsPerSection: const [5, 5, 5, 5, 5, 5, 5, 5, 5, 5],
        patchesPerPart: 200,
      );

      await rig.studioController.load();
      await rig.studioController.start();
      await _settlePreviewTimers();

      await rig.expectGenerationCompleted();
      await rig.expectTransientStructuresReleased();

      expect(
        rig.coordinator.presentationMaxQueueDepth,
        lessThanOrEqualTo(4),
      );

      rig.dispose();
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'SOAK 3: three 17-part resources back-to-back in the same process',
    () async {
      for (var round = 1; round <= 3; round++) {
        final rig = await _SoakRig.build(
          name: 'SOAK 连续资源 $round',
          partsPerSection: const [3, 2, 3, 2, 3, 2, 2],
          patchesPerPart: 120,
        );

        await rig.studioController.load();
        await rig.studioController.start();
        await _settlePreviewTimers();

        await rig.expectGenerationCompleted();
        await rig.expectTransientStructuresReleased();

        // Same-process accumulation check: the presentation queue of a
        // finished resource leaves nothing behind for the next one.
        expect(
            rig.coordinator.presentationDropped +
                rig.coordinator.presentationDrained,
            rig.coordinator.presentationEnqueued);

        rig.dispose();
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'SOAK 6: revision commit cost curve as history grows to 50, '
    'head always replays to live',
    () async {
      final rig = await _SoakRig.build(
        name: 'SOAK 修订成本曲线',
        partsPerSection: const [1],
        patchesPerPart: 10,
      );

      await rig.studioController.load();
      await rig.studioController.start();
      await _settlePreviewTimers();
      await rig.expectGenerationCompleted();

      final curve = <int, double>{};
      for (var round = 1; round <= 50; round++) {
        final duration = await rig.commitPartRound('修订曲线内容第 $round 段。' * 10);
        curve[round] = duration.inMicroseconds / 1000.0;
        // ignore: avoid_print
        print('revision-history=$round commitMs=${curve[round]}');
      }

      // The revision invariant must hold after 50 sequential commits.
      await rig.expectHeadRevisionReplaysLive();

      // Absolute bound: a local SQLite commit + revision capture must never
      // approach a perceptible freeze (the reported freeze was permanent).
      final slowest = curve.values.reduce((a, b) => a > b ? a : b);
      expect(slowest, lessThan(1000),
          reason: 'commit at history<=50 must stay well under a second; '
              'slowest=${slowest}ms');

      rig.dispose();
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'SOAK 7: malformed NDJSON mixed into a full DAG run — retries recover, '
    'and a permanently broken Part fails without spinning',
    () async {
      // Section 1 is healthy; section 2's root Part is permanently malformed.
      // The healthy branch must finish, the broken branch must fail closed,
      // and the whole run must terminate instead of spinning.
      final rig = await _SoakRig.build(
        name: 'SOAK 畸形 NDJSON',
        partsPerSection: const [3, 2],
        patchesPerPart: 40,
      );

      // Corrupt one Part in every fourth attempt of the healthy chain, so the
      // automatic retry path is exercised repeatedly, plus corrupt the whole
      // second section's root permanently.
      rig.gateway.malformedPartSuffixes = const {'part_4'};
      rig.gateway.malformedEveryNthCall = 4;

      await rig.studioController.load();
      await rig.studioController.start();
      await _settlePreviewTimers();

      final tasks =
          await rig.taskRepository.findTasksForResource(rig.resourceId.value);
      expect(tasks, isNotEmpty);

      final session = await rig.sessionRepository.findSession(rig.sessionId);
      expect(session, isNotNull);
      // A permanently malformed required Part means the run cannot succeed,
      // but it must reach a terminal state.
      expect(session!.status, StreamingLifecycleStatus.failed);
      expect(session.status, isNot(StreamingLifecycleStatus.completed));

      // The healthy branch completes and keeps its content.
      final healthy = tasks.where((t) => t.partId.endsWith('part_1')).single;
      expect(healthy.status, PartTaskStatus.completed.storageValue);

      // The broken root is terminal failed with a bounded dispatch count.
      final broken = tasks.where((t) => t.partId.endsWith('part_4')).single;
      expect(broken.status, PartTaskStatus.failed.storageValue);
      expect(
        rig.coordinator.dispatchCountSnapshot()[broken.taskId],
        lessThanOrEqualTo(3),
        reason: 'the malformed Part must never spin past its budget',
      );

      // No lease may survive the run.
      expect(rig.service.activeRunCount, 0);
      expect(rig.coordinator.inFlightCount(), 0);

      rig.dispose();
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'SOAK 4: scheduler stall watchdog dumps diagnostics without mutating data',
    () async {
      final rig = await _SoakRig.build(
        name: 'SOAK 停滞看门狗',
        partsPerSection: const [2],
        patchesPerPart: 20,
        stallWatchdogThreshold: const Duration(milliseconds: 60),
      );
      rig.gateway.holdFirstPart = true;

      await rig.studioController.load();
      final runFuture = rig.studioController.start();

      // Wait for the stall watchdog to fire while the first Part hangs.
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (GenerationDiagnostics.instance.dumpReasons.isEmpty) {
        if (DateTime.now().isAfter(deadline)) {
          fail('stall watchdog never dumped a diagnostic snapshot');
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      final reason = GenerationDiagnostics.instance.dumpReasons.last;
      expect(reason, contains('PART_TRANSITION_STALL'));
      expect(reason, contains('lastTransition='));

      // Release the held Part: the watchdog must not have mutated anything
      // and generation must run to completion normally.
      rig.gateway.releaseHeldPart();
      await runFuture;
      await _settlePreviewTimers();
      await rig.expectGenerationCompleted();

      rig.dispose();
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'SOAK 5: real LLMService SSE gate survives a 500-line provider burst '
    'and 1-3 character shard chunks',
    () async {
      // Scenario A: one single burst of 500 SSE lines in one socket event.
      {
        final gate = StreamController<List<int>>();
        final client = _FakeStreamedClient((request) async {
          unawaited(() async {
            const delta = '{"choices":[{"delta":{"content":"甲"}}]}';
            final burst = List.generate(500, (_) => 'data: $delta\n').join();
            gate.add(utf8.encode(burst));
            gate.add(utf8.encode(
              'data: {"choices":[{"delta":{},"finish_reason":"stop"}]}\n',
            ));
            gate.add(utf8.encode('data: [DONE]\n'));
            await gate.close();
          }());
          return http.StreamedResponse(gate.stream, 200);
        });
        final service = LLMService(
          const LLMConfig(
            provider: LLMProvider.deepseek,
            apiKey: 'k',
            baseUrl: 'https://example.invalid',
            model: 'test-model',
          ),
          clientFactory: () => client,
        );
        final chunks = <String>[];
        final result = await service.sendMessageStreamDetailed(
          const [
            {'role': 'user', 'content': 'hi'},
          ],
          chunks.add,
          () {},
        );
        expect(result.responseCompleted, isTrue);
        expect(chunks.join(), '甲' * 500);
        expect(result.content, '甲' * 500);
        // SSE gate accounting: every received line was consumed, and the
        // burst left a measurable (but bounded) pending backlog.
        final diagnostics = GenerationDiagnostics.instance;
        expect(diagnostics.counterValue('sse.received'), 502);
        expect(diagnostics.counterValue('sse.processed'), 502);
        expect(diagnostics.counterValue('sse.maxPending'), greaterThan(0));
        client.close();
      }

      // Scenario B: shard chunks of 1-3 bytes that split SSE lines (and the
      // NDJSON payload inside them) across many socket events.
      {
        final gate = StreamController<List<int>>();
        final client = _FakeStreamedClient((request) async {
          unawaited(() async {
            const delta = '{"choices":[{"delta":{"content":"内容"}}]}';
            final payload =
                '${List.generate(60, (_) => 'data: $delta\n').join()}'
                'data: {"choices":[{"delta":{},"finish_reason":"stop"}]}\n'
                'data: [DONE]\n';
            final bytes = utf8.encode(payload);
            // 1-3 byte shards.
            for (var i = 0; i < bytes.length; i += 1 + (i % 3)) {
              final end = (i + 1 + (i % 3)).clamp(i + 1, bytes.length);
              gate.add(bytes.sublist(i, end));
            }
            await gate.close();
          }());
          return http.StreamedResponse(gate.stream, 200);
        });
        final service = LLMService(
          const LLMConfig(
            provider: LLMProvider.deepseek,
            apiKey: 'k',
            baseUrl: 'https://example.invalid',
            model: 'test-model',
          ),
          clientFactory: () => client,
        );
        final chunks = <String>[];
        final result = await service.sendMessageStreamDetailed(
          const [
            {'role': 'user', 'content': 'hi'},
          ],
          chunks.add,
          () {},
        );
        expect(result.responseCompleted, isTrue);
        expect(chunks.join(), '内容' * 60);
        client.close();
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

Future<void> _settlePreviewTimers() async {
  // The Studio's preview flush timer runs on real time (180ms throttle);
  // let the last pending flush and the committed-tree refresh land.
  await Future<void>.delayed(const Duration(milliseconds: 300));
}

/// Streaming gateway emitting real NDJSON patch streams with the four
/// production-relevant chunk shapes. Lines may be split across chunks at
/// arbitrary byte offsets — the coordinator's line assembler must reassemble
/// them exactly.
final class _SoakStreamingGateway
    implements LlmGateway, PartGenerationStreamingGateway {
  @override
  bool get isConfigured => true;

  Never _unused() => throw UnimplementedError('not used in soak tests');

  int patchLinesDispatched = 0;
  bool holdFirstPart = false;

  /// Part id suffixes (e.g. `part_4`) whose stream is always corrupt.
  Set<String> malformedPartSuffixes = const <String>{};

  /// Every Nth overall call is corrupt as well, exercising the automatic
  /// retry path on otherwise healthy Parts. 0 disables it.
  int malformedEveryNthCall = 0;
  int _calls = 0;

  Completer<void>? _heldPartGate;
  final Map<String, String> expectedContent = <String, String>{};

  void releaseHeldPart() {
    _heldPartGate?.complete();
    _heldPartGate = null;
  }

  @override
  Future<void> streamPartGeneration({
    required String systemPrompt,
    required String instruction,
    required LlmTask task,
    required void Function(String chunk) onChunk,
    GenerationTaskHandle? taskHandle,
  }) async {
    String id(String field) =>
        RegExp('"$field": "(.*?)"').firstMatch(systemPrompt)?.group(1) ?? '';
    final generationId = id('generation_id');
    final resourceId = id('resource_id');
    final sectionId = id('section_id');
    final partId = id('part_id');
    final attemptId = id('attempt_id');

    final deltaShards = <String>[];
    final content = StringBuffer();
    for (var seq = 1; seq <= patchesPerPart; seq++) {
      // 4 chars per patch keeps 500 patches under the 3000-char Part limit.
      final delta = '${seq.toString().padLeft(3, '0')}甲';
      deltaShards.add(delta);
      content.write(delta);
    }
    expectedContent[partId] = content.toString();

    final lines = <String>[
      jsonEncode({
        'protocol_version': 1,
        'generation_id': generationId,
        'resource_id': resourceId,
        'section_id': sectionId,
        'part_id': partId,
        'attempt_id': attemptId,
        'sequence': 0,
        'op': 'start_part',
      }),
      for (var seq = 1; seq <= patchesPerPart; seq++)
        jsonEncode({
          'protocol_version': 1,
          'generation_id': generationId,
          'resource_id': resourceId,
          'section_id': sectionId,
          'part_id': partId,
          'attempt_id': attemptId,
          'sequence': seq,
          'op': 'append_text',
          'text_delta': deltaShards[seq - 1],
        }),
      jsonEncode({
        'protocol_version': 1,
        'generation_id': generationId,
        'resource_id': resourceId,
        'section_id': sectionId,
        'part_id': partId,
        'attempt_id': attemptId,
        'sequence': patchesPerPart + 1,
        'op': 'complete_part',
        'summary': 'SOAK 摘要 $partId',
      }),
    ];
    patchLinesDispatched += lines.length;
    var ndjson = lines.join('\n');

    // Malformed-NDJSON injection (P0 spin regression): reproduce the real
    // device corruption where the model closed its JSON string and then
    // emitted one extra `"` before the line ended.
    _calls++;
    final isPermanentlyMalformed =
        malformedPartSuffixes.any((suffix) => partId.endsWith(suffix));
    final isPeriodicallyMalformed =
        malformedEveryNthCall > 0 && _calls % malformedEveryNthCall == 0;
    if (isPermanentlyMalformed || isPeriodicallyMalformed) {
      ndjson = '$ndjson"';
    }

    if (holdFirstPart && _heldPartGate == null && partOrdinal == 0) {
      _heldPartGate = Completer<void>();
      await _heldPartGate!.future;
    }
    partOrdinal++;

    // Chunk-shape rotation: shards / normal / burst / line-crossing.
    final mode = partOrdinal % 4;
    final chunks = <String>[];
    switch (mode) {
      case 0:
        // 1-3 character shards.
        for (var i = 0; i < ndjson.length; i += 1 + (i % 3)) {
          final end = (i + 1 + (i % 3)).clamp(i + 1, ndjson.length);
          chunks.add(ndjson.substring(i, end));
        }
      case 1:
        // Normal 20-100 char chunks.
        for (var i = 0; i < ndjson.length; i += 60) {
          chunks.add(ndjson.substring(i, (i + 60).clamp(0, ndjson.length)));
        }
      case 2:
        // One burst.
        chunks.add(ndjson);
      default:
        // 7-char chunks guaranteed to cut lines mid-JSON.
        for (var i = 0; i < ndjson.length; i += 7) {
          chunks.add(ndjson.substring(i, (i + 7).clamp(0, ndjson.length)));
        }
    }

    for (final chunk in chunks) {
      onChunk(chunk);
      // Yield so the presentation queue drains concurrently with production,
      // the way real socket events interleave with microtask delivery.
      await Future<void>.delayed(Duration.zero);
    }
  }

  int partOrdinal = 0;
  int patchesPerPart = 0;

  // ─── LlmGateway members unused by the soak rig ───

  @override
  Future<Map<String, String>> generateConversationCharacter(String source) =>
      _unused();

  @override
  Future<Map<String, String>> generateResourceCharacter({
    required String source,
    required String worldview,
    required List<Map<String, String>> associatedCharacters,
    LlmGenerationMode? generationMode,
  }) =>
      _unused();

  @override
  Future<Map<String, dynamic>> generateDetailedResourceCharacter({
    required String source,
    String worldview = '',
    List<Map<String, String>> associatedCharacters = const [],
    int? targetTotalCharacters,
    void Function(int currentStage, int totalStages, String stageName)?
        onProgress,
    LlmGenerationMode? generationMode,
  }) =>
      _unused();

  @override
  Future<List<Map<String, String>>> generateResourceNpcs({
    required String source,
    required String worldview,
    required List<Map<String, String>> associatedCharacters,
  }) =>
      _unused();

  @override
  Future<List<String>> identifyCharacterNames(String source) => _unused();

  @override
  Future<Map<String, dynamic>> generateSceneBatchCharacter({
    required String source,
    required String label,
    required String worldview,
    required List<Map<String, dynamic>> relatedCharacters,
    required SceneBatchCandidate candidate,
    required int minimumTotalLength,
    required int maximumTotalLength,
    required String detailInstruction,
  }) =>
      _unused();

  @override
  Future<Map<String, String>> generateWorldview(
    String source, {
    LlmGenerationMode? generationMode,
  }) =>
      _unused();

  @override
  Future<Map<String, dynamic>> generateDetailedWorldview(
    String source, {
    int? targetTotalCharacters,
    void Function(WorldviewGenerationProgress progress)? onProgress,
    LlmGenerationMode? generationMode,
  }) =>
      _unused();

  @override
  Future<Map<String, String>> imageToWorldview(String base64Image) => _unused();

  @override
  Future<Map<String, String>> imageToCharacterCard(
    String base64Image, {
    String worldview = '',
  }) =>
      _unused();

  @override
  Future<List<Map<String, String>>> textToNpcs({
    required String userPrompt,
    String worldview = '',
    String protagonistName = '',
    String protagonistRole = '',
    String protagonistPersonality = '',
    String protagonistBackground = '',
    String protagonistBodyDescription = '',
    String protagonistAppearance = '',
    List<Map<String, String>> selectedCharacters = const [],
    List<Map<String, String>> associatedCharacters = const [],
    List<Map<String, String>> existingNpcs = const [],
    List<Map<String, String>> characterRelationships = const [],
  }) =>
      _unused();

  @override
  Future<Map<String, String>> textToOpening({
    required String userPrompt,
    String worldview = '',
    String protagonistName = '',
    String protagonistRole = '',
    String protagonistPersonality = '',
    String protagonistBackground = '',
    String protagonistBodyDescription = '',
    String protagonistAppearance = '',
    List<Map<String, String>> selectedCharacters = const [],
    List<Map<String, String>> associatedCharacters = const [],
    List<Map<String, String>> existingNpcs = const [],
    List<Map<String, String>> characterRelationships = const [],
    List<Map<String, String>> npcs = const [],
  }) =>
      _unused();

  @override
  Future<String> rawCompletion({
    required String systemPrompt,
    required String instruction,
    int maximumOutputTokens = 4096,
    double temperature = .7,
    LlmTask task = LlmTask.structuredExtraction,
    GenerationTaskHandle? taskHandle,
  }) =>
      _unused();

  @override
  Future<Map<String, dynamic>> textToCreationWorld(String userPrompt) =>
      _unused();

  @override
  Future<Map<String, dynamic>> textToCreationCharacter(
    String userPrompt, {
    String worldview = '',
    List<Map<String, dynamic>> associatedCharacters = const [],
    GenerationTaskHandle? taskHandle,
    int maximumOutputTokens = 8192,
  }) =>
      _unused();

  @override
  Future<List<Map<String, dynamic>>> textToCreationNpcs(
    String userPrompt, {
    String worldview = '',
    List<Map<String, dynamic>> associatedCharacters = const [],
  }) =>
      _unused();
}

/// Production runtime adapter: every member the Studio controller exercises
/// during a soak run delegates to the REAL shared streaming controller and
/// the REAL repositories.
final class _SoakStudioRuntime implements ResourceStudioRuntime {
  _SoakStudioRuntime({
    required StreamingResourceGenerationController streamingController,
    required StreamingGenerationSessionRepositoryImpl sessionRepository,
    required ResourceTreeRepositoryImpl treeRepository,
  })  : _streamingController = streamingController,
        _sessionRepository = sessionRepository,
        _treeRepository = treeRepository;

  final StreamingResourceGenerationController _streamingController;
  final StreamingGenerationSessionRepositoryImpl _sessionRepository;
  final ResourceTreeRepositoryImpl _treeRepository;

  @override
  Stream<GenerationRuntimeEvent> get events => _streamingController.events;

  @override
  Future<ResourceTree?> readTree(ResourceId resourceId) =>
      _treeRepository.readTree(resourceId);

  @override
  Future<StreamingGenerationSession?> getSession(String sessionId) =>
      _streamingController.getSession(sessionId);

  @override
  Future<StreamingGenerationSession?> getLatestSessionForResource(
    String resourceId,
  ) =>
      _sessionRepository.findLatestSessionForResource(resourceId);

  @override
  Future<StreamingGenerationSession?> ensureSession(ResourceId resourceId) =>
      getLatestSessionForResource(resourceId.value);

  @override
  Future<List<StreamingGenerationSession>> findActiveSessions() =>
      _sessionRepository.findActiveSessions();

  @override
  Future<List<ResourceCreationSession>> pendingPlanningSessions() async =>
      const <ResourceCreationSession>[];

  @override
  Future<List<Resource>> listResources() async {
    final resources = <Resource>[];
    for (final type in ResourceType.values) {
      resources.addAll(await _treeRepository.listResources(type: type));
    }
    return resources;
  }

  @override
  Future<bool> start(String sessionId) =>
      _streamingController.start(sessionId: sessionId);

  @override
  Future<void> pause(String sessionId) =>
      _streamingController.pause(sessionId: sessionId);

  @override
  Future<bool> resume(String sessionId) =>
      _streamingController.resume(sessionId: sessionId);

  @override
  Future<void> cancel(String sessionId) =>
      _streamingController.cancel(sessionId: sessionId);

  @override
  Future<bool> retryPart(String sessionId, String partId) =>
      _streamingController.retryPart(sessionId: sessionId, partId: partId);

  @override
  Future<bool> recover(String sessionId) =>
      _streamingController.recover(sessionId: sessionId);

  @override
  Future<StreamingGenerationSession> createAndStart({
    required ResourceType resourceType,
    required String name,
    required ReferenceSource referenceSource,
    required int targetCharacters,
    String origin = 'resource-studio',
    String libraryMode = 'adventure',
    String? idempotencyKey,
    ResourceId? targetResourceId,
    String? originWorldviewId,
  }) =>
      throw UnimplementedError('not used in soak tests');

  @override
  Future<ResourceAiCreationPlan> createAndPlan(
    ResourceStudioCreationDraft draft,
  ) =>
      throw UnimplementedError('not used in soak tests');

  @override
  Future<ResourceAiCreationIdentity> confirmAndStart(
    String creationSessionId, {
    Set<String>? selectedPartIds,
  }) =>
      throw UnimplementedError('not used in soak tests');

  @override
  Future<Resource> createManual({
    required ResourceType resourceType,
    required String name,
    required String summary,
    required String libraryMode,
  }) =>
      throw UnimplementedError('not used in soak tests');

  @override
  void dispose() {}
}

final class _SoakRig {
  _SoakRig._({
    required this.gateway,
    required this.coordinator,
    required this.service,
    required this.studioController,
    required this.taskRepository,
    required this.sessionRepository,
    required this.treeRepository,
    required this.revisionRepository,
    required this.resourceId,
    required this.sessionId,
    required this.events,
  });

  static Future<_SoakRig> build({
    required String name,
    required List<int> partsPerSection,
    required int patchesPerPart,
    Duration stallWatchdogThreshold = const Duration(seconds: 10),
  }) async {
    Future<Database> getDb() => DatabaseService.database;
    final treeRepository = ResourceTreeRepositoryImpl(getDb: getDb);
    final revisionRepository = ResourceRevisionRepositoryImpl(getDb: getDb);
    final revisionCapture = RevisionCaptureEngine(
      revisionRepository: revisionRepository,
      treeBoundary: treeRepository,
    );
    final blueprintRepository = ResourceBlueprintRepositoryImpl(
      getDb: getDb,
      treeRepository: treeRepository,
      revisionCapture: revisionCapture,
    );
    final taskRepository = PartGenerationTaskRepositoryImpl(
      getDb: getDb,
      revisionBoundary: revisionCapture,
    );
    final pipeline = ResourceCreationPipeline(
      getDb: getDb,
      hasAiCredentials: () => true,
      treeRepository: treeRepository,
      blueprintRepository: blueprintRepository,
      generationTaskRepository: taskRepository,
      revisionCapture: revisionCapture,
    );
    final sessionRepository =
        StreamingGenerationSessionRepositoryImpl(getDb: getDb);

    final creation = await pipeline.create(ResourceCreationRequest(
      resourceType: ResourceType.worldview,
      method: CreationMethod.aiReference,
      name: name,
      idempotencyKey: 'soak_${DateTime.now().microsecondsSinceEpoch}',
      referenceSource: ReferenceSource.text('SOAK 参考材料。' * 20),
    ));

    var partCounter = 0;
    String? lastPartOfPreviousSection;
    final bpSections = <BlueprintSection>[];
    for (var s = 0; s < partsPerSection.length; s++) {
      final bpParts = <BlueprintPart>[];
      String? previous;
      for (var p = 0; p < partsPerSection[s]; p++) {
        partCounter++;
        final partId = 'part_$partCounter';
        bpParts.add(BlueprintPart(
          id: partId,
          sectionId: 'sec_${s + 1}',
          title: '第${s + 1}章第${p + 1}节',
          generationGoal: '生成 $partId 正文',
          estimatedLength: 500,
          dependencies: previous != null
              ? [previous]
              : (lastPartOfPreviousSection != null
                  ? [lastPartOfPreviousSection]
                  : const <String>[]),
        ));
        previous = partId;
      }
      lastPartOfPreviousSection = previous;
      bpSections.add(BlueprintSection(
        id: 'sec_${s + 1}',
        title: '第${s + 1}章',
        parts: bpParts,
      ));
    }

    final blueprint = ResourceBlueprint(
      blueprintId: 'bp_soak_${DateTime.now().microsecondsSinceEpoch}',
      sessionId: creation.sessionId!,
      resourceType: ResourceType.worldview,
      suggestedName: name,
      summary: 'SOAK 资源',
      sections: bpSections,
    );
    await blueprintRepository.saveBlueprint(blueprint);
    final confirmation = await blueprintRepository.confirmBlueprint(
      blueprintId: blueprint.blueprintId,
    );
    final resourceId = confirmation.resourceId;

    final gateway = _SoakStreamingGateway()..patchesPerPart = patchesPerPart;
    final coordinator = PartGenerationCoordinator(
      taskRepository: taskRepository,
      blueprintRepository: blueprintRepository,
      pipeline: pipeline,
      gateway: gateway,
      maxConcurrency: 1,
      previewThrottleInterval: Duration.zero,
      stallWatchdogThreshold: stallWatchdogThreshold,
    );
    final service = StreamingResourceGenerationService(
      sessionRepository: sessionRepository,
      taskRepository: taskRepository,
      blueprintRepository: blueprintRepository,
      pipeline: pipeline,
      coordinator: coordinator,
    );
    final streamingController = StreamingResourceGenerationController(
      service: service,
      sessionRepository: sessionRepository,
      ownsService: false,
    );
    final runtime = _SoakStudioRuntime(
      streamingController: streamingController,
      sessionRepository: sessionRepository,
      treeRepository: treeRepository,
    );

    final session = await service.createSession(
      resourceId: resourceId.value,
      blueprintId: blueprint.blueprintId,
      creationSessionId: creation.sessionId!,
    );

    final studioController = ResourceStudioController(
      runtime: runtime,
      sessionId: session.sessionId,
    );

    final events = <GenerationRuntimeEvent>[];
    final eventsSub = service.eventStream.listen(events.add);

    return _SoakRig._(
      gateway: gateway,
      coordinator: coordinator,
      service: service,
      studioController: studioController,
      taskRepository: taskRepository,
      sessionRepository: sessionRepository,
      treeRepository: treeRepository,
      revisionRepository: revisionRepository,
      resourceId: resourceId,
      sessionId: session.sessionId,
      events: events,
    ).._eventsSub = eventsSub;
  }

  final _SoakStreamingGateway gateway;
  final PartGenerationCoordinator coordinator;
  final StreamingResourceGenerationService service;
  final ResourceStudioController studioController;
  final PartGenerationTaskRepositoryImpl taskRepository;
  final ResourceTreeRepositoryImpl treeRepository;
  final ResourceRevisionRepositoryImpl revisionRepository;
  final StreamingGenerationSessionRepositoryImpl sessionRepository;
  final ResourceId resourceId;
  final String sessionId;
  final List<GenerationRuntimeEvent> events;
  StreamSubscription<GenerationRuntimeEvent>? _eventsSub;

  /// Verifies 100% completion: session completed, every task completed in
  /// SQLite, committed content matches the gateway's expected text exactly.
  Future<void> expectGenerationCompleted() async {
    final tasks = await taskRepository.findTasksForResource(resourceId.value);
    expect(tasks, isNotEmpty);
    for (final task in tasks) {
      expect(task.status, PartTaskStatus.completed.storageValue,
          reason: 'task ${task.taskId} must be completed');
    }

    final session = await sessionRepository.findSession(sessionId);
    expect(session, isNotNull);
    expect(session!.status, StreamingLifecycleStatus.completed);
    expect(session.completedPartsCount, tasks.length);

    expect(events.whereType<GenerationCompleted>().length, 1);
    expect(events.whereType<GenerationFailed>().length, 0);
    expect(events.whereType<PartCompleted>().length, tasks.length);

    // Committed content is the authority and must match the gateway stream
    // byte for byte (NDJSON reassembly survived every chunk shape).
    final partIds = tasks.map((t) => t.partId).toList();
    final partsContent = await taskRepository.getPartsContent(partIds);
    for (final entry in partsContent.entries) {
      expect(
        entry.value.content,
        gateway.expectedContent[entry.key],
        reason: 'committed content of ${entry.key} must match the stream',
      );
    }

    // The Studio preview notifiers converge on the committed content.
    await _settlePreviewTimers();
    for (final entry in partsContent.entries) {
      expect(
        studioController.partPreview(PartId(entry.key)).value,
        entry.value.content,
        reason: 'preview of ${entry.key} must equal committed content',
      );
    }
  }

  /// Runs one production `commitPartContent` round for the first task and
  /// returns its wall-clock duration. Used to measure the commit/revision
  /// cost curve while revision history grows (P0 report item 9) without ever
  /// bypassing the revision invariant.
  Future<Duration> commitPartRound(String content) async {
    final tasks = await taskRepository.findTasksForResource(resourceId.value);
    final task = tasks.first;
    // Reopen the completed task the way restore/compression publish does
    // (the production-sanctioned completed -> ready transition).
    final db = await DatabaseService.database;
    await db.transaction((txn) async {
      await taskRepository.reopenCompletedTasksInTransaction(
        txn,
        partIds: [task.partId],
        now: DateTime.now().toIso8601String(),
      );
    });
    final attempt = await taskRepository.startAttempt(
      taskId: task.taskId,
      generationId: 'curve_${DateTime.now().microsecondsSinceEpoch}',
      attemptNumber: 1,
    );
    final response = PartGenerationResponse(
      protocolVersion: 1,
      generationId: 'curve',
      resourceId: resourceId,
      sectionId: SectionId(task.sectionId),
      partId: PartId(task.partId),
      attemptId: attempt.attemptId,
      content: content,
      summary: 'curve',
      status: 'completed',
    );
    final watch = Stopwatch()..start();
    await taskRepository.commitPartContent(
      response: response,
      taskId: task.taskId,
      attemptId: attempt.attemptId,
      expectedSourceToken: attempt.sourceToken,
    );
    watch.stop();
    return watch.elapsed;
  }

  /// The revision invariant: the head revision must replay to exactly the
  /// live tree contents.
  Future<void> expectHeadRevisionReplaysLive() async {
    final head = await revisionRepository.readHead(
      resourceId,
      ResourceRevisionKind.latestHead,
    );
    expect(head, isNotNull, reason: 'a committed resource must have a head');
    final state = await revisionRepository.readState(head!.revisionId);
    final tree = await treeRepository.readTree(resourceId);
    expect(tree, isNotNull);
    for (final part in tree!.parts) {
      expect(
        state.nodes[part.id.value]?.content,
        part.content,
        reason: 'head revision must replay to the live content of '
            '${part.id.value}',
      );
    }
  }

  /// Verifies every session-local transient structure returned to zero after
  /// the generation finished — the process can run the next resource with a
  /// clean slate.
  Future<void> expectTransientStructuresReleased() async {
    expect(service.activeRunCount, 0, reason: 'no run may stay in flight');
    expect(service.activeTaskHandleCount, 0,
        reason: 'task handles must be cleaned up');
    expect(service.pendingStopCount, 0);

    expect(studioController.bufferCount, 0,
        reason: 'preview buffers must be released after PartCompleted');
    expect(studioController.dirtyPartCount, 0);
    expect(studioController.isPatchFlushTimerActive, isFalse,
        reason: 'the preview flush timer must not outlive the generation');

    // Presentation queue fully drained at the end of the run.
    expect(coordinator.presentationMaxQueueDepth, lessThanOrEqualTo(4));
  }

  void dispose() {
    _eventsSub?.cancel();
    studioController.dispose();
    service.dispose();
  }
}

final class _FakeStreamedClient extends http.BaseClient {
  _FakeStreamedClient(this.handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest request)
      handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handler(request);

  @override
  void close() {}
}
