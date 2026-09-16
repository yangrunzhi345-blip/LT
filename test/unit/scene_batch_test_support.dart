import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lt_dialogue/application/llm/llm_gateway.dart';
import 'package:lt_dialogue/application/resource_library/import_models.dart';
import 'package:lt_dialogue/application/resources/legacy_creation_bridge.dart';
import 'package:lt_dialogue/application/resources/resource_creation_contracts.dart';
import 'package:lt_dialogue/application/resources/resource_creation_pipeline.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/models/resource_provenance.dart';
import 'package:lt_dialogue/models/scene_batch_candidate.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository_impl.dart';

/// One card an entry handed to the unified creation pipeline.
class SceneBatchSavedCard {
  const SceneBatchSavedCard({
    required this.id,
    required this.name,
    required this.jsonData,
  });

  final String id;
  final String name;
  final String jsonData;
}

/// Records what a scene batch entry saved *and* exposes the tree it wrote.
///
/// Scene batch now saves through [LegacyCreationBridge], so the cards are
/// captured at that seam instead of at a repository mock.
class SceneBatchSaveSpy {
  SceneBatchSaveSpy(this._bridge);

  final RecordingCreationBridge _bridge;

  List<SceneBatchSavedCard> get calls => _bridge.saved
      .map((entry) => SceneBatchSavedCard(
            id: entry['id']!,
            name: entry['name']!,
            jsonData: entry['jsonData']!,
          ))
      .toList(growable: false);

  bool get wasCalled => calls.isNotEmpty;

  List<SceneBatchSavedCard> get last => calls;
}

/// A bridge that records every save before delegating to the real pipeline.
class RecordingCreationBridge extends LegacyCreationBridge {
  RecordingCreationBridge(super.pipeline);

  final List<Map<String, String>> saved = [];

  @override
  Future<ResourceCreationResult> saveCard({
    required ResourceType type,
    required String id,
    required String name,
    required String jsonData,
    required String mode,
    String authoringMethod = 'manual',
    String aiGenerationDepth = '',
    String source = '',
    String matchingWorldviewId = '',
    Map<String, Object?> extraMetadata = const <String, Object?>{},
    required String origin,
    String? operationId,
  }) {
    saved.add({'id': id, 'name': name, 'jsonData': jsonData});
    return super.saveCard(
      type: type,
      id: id,
      name: name,
      jsonData: jsonData,
      mode: mode,
      authoringMethod: authoringMethod,
      aiGenerationDepth: aiGenerationDepth,
      source: source,
      matchingWorldviewId: matchingWorldviewId,
      extraMetadata: extraMetadata,
      origin: origin,
      operationId: operationId,
    );
  }

  @override
  Future<List<ResourceCreationResult>> saveCards(
    List<LegacyCardSave> cards,
  ) {
    for (final card in cards) {
      saved.add({
        'id': card.id,
        'name': card.name,
        'jsonData': card.jsonData,
      });
    }
    return super.saveCards(cards);
  }
}

/// Real persistence for scene batch tests: a temp database plus the tree reader
/// they assert against.
final class SceneBatchTreeHarness {
  SceneBatchTreeHarness({
    required this.tempDir,
    required this.treeRepository,
    required this.bridge,
  });

  final Directory tempDir;
  final IResourceTreeRepository treeRepository;
  final RecordingCreationBridge bridge;

  Future<int> resourceCount() async {
    final db = await DatabaseService.database;
    final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM resources');
    return (rows.first['c'] as num).toInt();
  }

  Future<List<String>> resourceNames() async {
    final db = await DatabaseService.database;
    final rows = await db.query('resources', orderBy: 'created_at ASC');
    return rows.map((row) => row['name'].toString()).toList();
  }

  Future<void> dispose() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  }
}

/// Boots a temp database for scene batch tests.
Future<SceneBatchTreeHarness> setUpSceneBatchTree() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;
  final tempDir = await Directory.systemTemp.createTemp('lt_scene_batch_');
  DatabaseService.customDbDir = tempDir.path;
  await DatabaseService.resetDatabase();
  final bridge = RecordingCreationBridge(ResourceCreationPipeline(
    getDb: () => DatabaseService.database,
    hasAiCredentials: () => true,
  ));
  return SceneBatchTreeHarness(
    tempDir: tempDir,
    treeRepository:
        ResourceTreeRepositoryImpl(getDb: () => DatabaseService.database),
    bridge: bridge,
  );
}

SceneBatchImportRequest buildSceneBatchRequest({
  String kind = 'character',
  List<Map<String, dynamic>> related = const [],
  int minimumTotalLength = 1000,
  int maximumTotalLength = 5000,
}) =>
    SceneBatchImportRequest(
      source: '林月与玄霜门的故事。',
      kind: kind,
      detailInstruction: '详细模式',
      aiDepth: AiGenerationDepth.detailed,
      minimumTotalLength: minimumTotalLength,
      maximumTotalLength: maximumTotalLength,
      relatedCharacters: related,
    );

/// 按候选 sourceId 返回固定生成结果；未配置的候选抛出异常。
void stubSceneBatchCharacterGeneration(
  LlmGateway gateway,
  Map<String, Map<String, dynamic>> bySourceId,
) {
  when(
    () => gateway.generateSceneBatchCharacter(
      source: any(named: 'source'),
      label: any(named: 'label'),
      worldview: any(named: 'worldview'),
      relatedCharacters: any(named: 'relatedCharacters'),
      candidate: any(named: 'candidate'),
      minimumTotalLength: any(named: 'minimumTotalLength'),
      maximumTotalLength: any(named: 'maximumTotalLength'),
      detailInstruction: any(named: 'detailInstruction'),
    ),
  ).thenAnswer((invocation) async {
    final candidate =
        invocation.namedArguments[#candidate] as SceneBatchCandidate;
    final item = bySourceId[candidate.sourceId];
    if (item == null) {
      throw StateError('no stubbed generation for ${candidate.sourceId}');
    }
    return Map<String, dynamic>.from(item);
  });
}

/// 让连续多次调用可返回不同的生成结果（用于单候选重试/失败隔离测试）。
void stubSceneBatchCharacterAttempts(
  LlmGateway gateway,
  Map<String, List<Map<String, dynamic> Function()>> bySourceId,
) {
  final counters = <String, int>{};
  when(
    () => gateway.generateSceneBatchCharacter(
      source: any(named: 'source'),
      label: any(named: 'label'),
      worldview: any(named: 'worldview'),
      relatedCharacters: any(named: 'relatedCharacters'),
      candidate: any(named: 'candidate'),
      minimumTotalLength: any(named: 'minimumTotalLength'),
      maximumTotalLength: any(named: 'maximumTotalLength'),
      detailInstruction: any(named: 'detailInstruction'),
    ),
  ).thenAnswer((invocation) async {
    final candidate =
        invocation.namedArguments[#candidate] as SceneBatchCandidate;
    final attempts = bySourceId[candidate.sourceId];
    if (attempts == null || attempts.isEmpty) {
      throw StateError('no stubbed attempts for ${candidate.sourceId}');
    }
    final index = counters.update(
      candidate.sourceId,
      (value) => value + 1,
      ifAbsent: () => 1,
    );
    final attempt = attempts[(index - 1).clamp(0, attempts.length - 1)];
    return attempt();
  });
}

/// Asserts the entry persisted nothing, at the pipeline seam and in the tree.
Future<void> verifyNoSceneBatchSave(
  SceneBatchSaveSpy spy,
  SceneBatchTreeHarness harness,
) async {
  expect(spy.calls, isEmpty);
  expect(await harness.resourceCount(), 0);
}
