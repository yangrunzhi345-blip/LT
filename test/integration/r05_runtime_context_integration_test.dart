import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/narrative/narrative_context.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/engines/chat_engine_host.dart';
import 'package:lt_dialogue/engines/chat_engine_internals/summary_service.dart';
import 'package:lt_dialogue/models/completion_params.dart';
import 'package:lt_dialogue/models/message.dart';
import 'package:lt_dialogue/models/model_context_capability.dart';
import 'package:lt_dialogue/models/scene_state.dart';
import 'package:lt_dialogue/models/world_entry.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/llm_service.dart';
import 'package:lt_dialogue/services/repositories/adventure_repository_impl.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository_impl.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _MockLLMService extends Mock implements LLMService {}

class _MockChatEngineHost extends Mock implements ChatEngineHost {}

const _capability = ModelContextCapability(
  providerId: 'test',
  modelId: 'test',
  maximumContextTokens: 8192,
  maximumOutputTokens: 2048,
);

/// R05-E: cross-boundary integration matrix. The summary path runs against
/// the real AdventureRepositoryImpl over real SQLite, the context assembly
/// against the real orchestrator, and every resource identity comes from the
/// production ProviderContainer composition root. Only the LLM and the clock
/// are faked.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('lt_r05_integration_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
    registerFallbackValue(const CompletionParams());
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  /// Real adventure rows: summaries.adventure_id has a real FK, so the
  /// fixture creates the parents through the real database.
  Future<void> seedAdventures(List<int> ids) async {
    final db = await DatabaseService.database;
    for (final id in ids) {
      await db.insert('adventures', {
        'id': id,
        'title': '冒险\$id',
        'created_at': DateTime(2026).toIso8601String(),
      });
    }
  }

  /// Flushes microtasks until [condition] holds (the parked LLM call is
  /// reached purely via microtask scheduling — no wall-clock waits).
  Future<void> waitFor(bool Function() condition) async {
    for (var i = 0; i < 200 && !condition(); i++) {
      await pumpEventQueue();
    }
    expect(condition(), isTrue);
  }

  List<Message> seedMessages(int count) => [
        for (var i = 0; i < count; i++)
          Message(id: 'm$i', content: '消息$i', isUser: i.isEven),
      ];

  Future<int> summaryRowCount(int adventureId) async {
    final db = await DatabaseService.database;
    return db.query('summaries',
        where: 'adventure_id = ?',
        whereArgs: [adventureId]).then((r) => r.length);
  }

  test('E1 context work A, resource switch to B, late A cannot publish',
      () async {
    final barrier = Completer<void>();
    var llmCalled = false;
    final host = _MockChatEngineHost();
    final llm = _MockLLMService();
    when(() => host.currentAdventureId).thenReturn(1);
    when(() => host.currentBranchId).thenReturn(0);
    when(() => host.messages).thenReturn(seedMessages(20));
    when(() => host.llmService).thenReturn(llm);
    when(() => llm.config).thenReturn(const LLMConfig(
      provider: LLMProvider.deepseek,
      apiKey: 'test-key',
      baseUrl: 'https://api.deepseek.com',
      model: 'deepseek-flash',
    ));
    when(() => llm.sendMessageStream(
          any(),
          any(),
          any(),
          params: any(named: 'params'),
        )).thenAnswer((_) async {
      llmCalled = true;
      await barrier.future;
      return '时间线：测试摘要';
    });
    final repo = AdventureRepositoryImpl(getDb: () => DatabaseService.database);
    await seedAdventures([1]);

    // Mirrors ChatEngine._isSummaryCurrent: production ownership closure
    // against the live host state.
    var disposed = false;
    bool isCurrent(int adventureId, int branchId, int generation) =>
        !disposed &&
        generation == 1 &&
        host.currentAdventureId == adventureId &&
        host.currentBranchId == branchId;

    final service = SummaryService(adventureRepo: repo, host: host);
    service.maybeSummarize(
      host: host,
      messages: seedMessages(20),
      generation: 1,
      isCurrent: isCurrent,
      lastSummaryAt: 0,
      lastSummaryTime: null,
      onGenerate: (msgs, upTo, adventureId, branchId, generation, boundary) {
        return service.generateSummary(
          msgs: msgs,
          upToIndex: upTo,
          host: host,
          adventureId: adventureId,
          branchId: branchId,
          generation: generation,
          isCurrent: isCurrent,
          onSuccess: (_) {},
          onNotify: () {},
          boundaryMessageId: boundary,
        );
      },
    );
    await waitFor(() => llmCalled);

    // ── Resource/adventure switch: B becomes current. ──
    when(() => host.currentAdventureId).thenReturn(2);
    barrier.complete();
    for (var i = 0; i < 100; i++) {
      await pumpEventQueue();
    }

    // A finished late; the ownership check discarded it before any write.
    expect(await summaryRowCount(1), 0);
    expect(await summaryRowCount(2), 0);
  });

  test('E2 new dialogue during a summary is never claimed as covered',
      () async {
    final barrier = Completer<void>();
    var llmCalled = false;
    final host = _MockChatEngineHost();
    final llm = _MockLLMService();
    when(() => host.currentAdventureId).thenReturn(1);
    when(() => host.currentBranchId).thenReturn(0);
    final messages = seedMessages(20);
    when(() => host.messages).thenReturn(messages);
    when(() => host.llmService).thenReturn(llm);
    when(() => llm.config).thenReturn(const LLMConfig(
      provider: LLMProvider.deepseek,
      apiKey: 'test-key',
      baseUrl: 'https://api.deepseek.com',
      model: 'deepseek-flash',
    ));
    when(() => llm.sendMessageStream(
          any(),
          any(),
          any(),
          params: any(named: 'params'),
        )).thenAnswer((_) async {
      llmCalled = true;
      await barrier.future;
      return '时间线：测试摘要';
    });
    final repo = AdventureRepositoryImpl(getDb: () => DatabaseService.database);
    await seedAdventures([1]);

    final service = SummaryService(adventureRepo: repo, host: host);
    service.maybeSummarize(
      host: host,
      messages: messages,
      generation: 1,
      isCurrent: (_, __, ___) => true,
      lastSummaryAt: 0,
      lastSummaryTime: null,
      onGenerate: (msgs, upTo, adventureId, branchId, generation, boundary) {
        // New dialogue arrives while the summary LLM call is parked…
        messages.addAll([
          for (var i = 20; i < 24; i++)
            Message(id: 'm$i', content: '新对话$i', isUser: i.isEven),
        ]);
        // …and a regeneration deletes a message inside the summarized
        // range, shifting every later message one position down so the
        // boundary message m7 is no longer at index 7.
        messages.removeAt(5);
        return service.generateSummary(
          msgs: msgs,
          upToIndex: upTo,
          host: host,
          adventureId: adventureId,
          branchId: branchId,
          generation: generation,
          isCurrent: (_, __, ___) => true,
          onSuccess: (_) {},
          onNotify: () {},
          boundaryMessageId: boundary,
        );
      },
    );
    await waitFor(() => llmCalled);
    barrier.complete();
    await pumpEventQueue();

    // The stale boundary (m5 was rewritten) must not be committed: coverage
    // never advances across messages the summary did not see.
    expect(await summaryRowCount(1), 0);
  });

  test('E3 production container identity drives the real context assembler',
      () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final crud = container.read(resourceCrudControllerProvider);
    final saved = await crud.saveWorldviewPreset(
      id: 'wv_e3',
      name: 'E3 世界观',
      description: 'E3 描述文本。' * 40,
      entriesJson: '[]',
      now: DateTime(2026).toIso8601String(),
      detailJson: _validDetailJson('E3'),
    );
    expect(saved.success, isTrue, reason: saved.errorMessage);
    await pumpEventQueue();

    // The assembler consumes the authoritative tree from the same DB the
    // production pipeline wrote.
    final tree = await ResourceTreeRepositoryImpl(
      getDb: () => DatabaseService.database,
    ).readTree(const ResourceId('wv_e3'));
    expect(tree, isNotNull);

    final entries = [
      WorldEntry(
        id: 1,
        content: '【世界观/世界规则】${tree!.resource.name} 的铁律。',
        keys: const ['白港'],
        sticky: 1,
        sourceType: 'worldview_snapshot',
      ),
    ];
    final context = const ContextOrchestrator().build(
      rawInput: '我观察四周。',
      config: null,
      sceneState: const SceneState(location: '白港'),
      worldEntries: entries,
      messages: const [],
      summary: null,
      persona: null,
      capability: _capability,
      requestedResponseTokens: 1024,
    );
    expect(context.world.constraints, isNotEmpty);
    expect(
      context.world.constraints.first.content,
      contains('E3 世界观'),
    );
  });

  test('E4 CRUD rewrites are read authoritatively by the next assembly',
      () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final crud = container.read(resourceCrudControllerProvider);

    Future<String?> resourceBody(String id) async {
      final tree = await ResourceTreeRepositoryImpl(
        getDb: () => DatabaseService.database,
      ).readTree(ResourceId(id));
      return tree?.parts.map((p) => p.content).join('\n');
    }

    final first = await crud.saveWorldviewPreset(
      id: 'wv_e4',
      name: 'E4 世界观',
      description: 'E4 描述文本。' * 40,
      entriesJson: '[]',
      now: DateTime(2026).toIso8601String(),
      detailJson: _validDetailJson('初版内容'),
    );
    expect(first.success, isTrue, reason: first.errorMessage);
    await pumpEventQueue();
    final bodyV1 = await resourceBody('wv_e4');

    final second = await crud.saveWorldviewPreset(
      id: 'wv_e4',
      name: 'E4 世界观',
      description: 'E4 描述文本。' * 40,
      entriesJson: '[]',
      now: DateTime(2026).toIso8601String(),
      detailJson: _validDetailJson('修订后的内容'),
    );
    expect(second.success, isTrue, reason: second.errorMessage);
    await pumpEventQueue();
    final bodyV2 = await resourceBody('wv_e4');

    expect(bodyV1, isNot(bodyV2));
    // The latest authoritative state, not a cached stale source.
    expect(bodyV2, contains('修订后的内容'));

    // The assembler fed from the authoritative state reflects the rewrite.
    final context = const ContextOrchestrator().build(
      rawInput: 'E4 世界观 的铁律是什么？',
      config: null,
      sceneState: const SceneState(location: '白港'),
      worldEntries: [
        WorldEntry(
          id: 1,
          content: '【世界观/世界规则】${bodyV2!}',
          keys: const ['白港'],
          sticky: 1,
          sourceType: 'worldview_snapshot',
        ),
      ],
      messages: const [],
      summary: null,
      persona: null,
      capability: _capability,
      requestedResponseTokens: 1024,
    );
    expect(
      context.world.all.map((item) => item.content),
      isNot(contains(bodyV1)),
    );
  });

  test('E5 a disposed runtime discards a late summary result', () async {
    final barrier = Completer<void>();
    var llmCalled = false;
    final host = _MockChatEngineHost();
    final llm = _MockLLMService();
    when(() => host.currentAdventureId).thenReturn(1);
    when(() => host.currentBranchId).thenReturn(0);
    when(() => host.messages).thenReturn(seedMessages(20));
    when(() => host.llmService).thenReturn(llm);
    when(() => llm.config).thenReturn(const LLMConfig(
      provider: LLMProvider.deepseek,
      apiKey: 'test-key',
      baseUrl: 'https://api.deepseek.com',
      model: 'deepseek-flash',
    ));
    when(() => llm.sendMessageStream(
          any(),
          any(),
          any(),
          params: any(named: 'params'),
        )).thenAnswer((_) async {
      llmCalled = true;
      await barrier.future;
      return '时间线：测试摘要';
    });
    final repo = AdventureRepositoryImpl(getDb: () => DatabaseService.database);
    await seedAdventures([1]);

    // The ownership closure mirrors ChatEngine._isSummaryCurrent including
    // the disposed flag; the test flips it while the call is parked.
    var disposed = false;
    final service = SummaryService(adventureRepo: repo, host: host);
    service.maybeSummarize(
      host: host,
      messages: seedMessages(20),
      generation: 1,
      isCurrent: (adventureId, branchId, generation) =>
          !disposed && generation == 1,
      lastSummaryAt: 0,
      lastSummaryTime: null,
      onGenerate: (msgs, upTo, adventureId, branchId, generation, boundary) {
        return service.generateSummary(
          msgs: msgs,
          upToIndex: upTo,
          host: host,
          adventureId: adventureId,
          branchId: branchId,
          generation: generation,
          isCurrent: (id, branch, gen) => !disposed && gen == 1,
          onSuccess: (_) {},
          onNotify: () {},
          boundaryMessageId: boundary,
        );
      },
    );
    await waitFor(() => llmCalled);

    disposed = true; // runtime replacement / dispose while A is in flight
    barrier.complete();
    await pumpEventQueue();

    expect(await summaryRowCount(1), 0);
  });
}

/// A detailed worldview that satisfies the integrity validator.
String _validDetailJson(String seed) {
  const moduleKeys = <String>[
    'overview',
    'world_rules',
    'world_state',
    'locations',
    'factions',
    'customs_and_life',
    'timeline',
    'glossary',
    'creative_constraints',
  ];
  final modules = <String, Object?>{
    for (final key in moduleKeys)
      key: <String, Object?>{
        key == 'overview' ? 'summary' : 'content': '$key $seed ' * 8,
        'status': 'confirmed',
      },
  };
  return jsonEncode({'modules': modules});
}
