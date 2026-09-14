import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/narrative/narrative_context.dart';
import 'package:lt_dialogue/application/narrative/world_semantic_retrieval.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/models/model_context_capability.dart';
import 'package:lt_dialogue/models/scene_state.dart';
import 'package:lt_dialogue/models/world_embedding.dart';
import 'package:lt_dialogue/models/world_entry.dart';
import 'package:lt_dialogue/services/embedding/semantic_embedding_service.dart';
import 'package:lt_dialogue/services/repositories/world_embedding_repository.dart';

/// Flaky/throwing embedding service for fault injection
class ThrowingEmbeddingService implements SemanticEmbeddingService {
  @override
  String get modelId => 'throwing-mock';

  @override
  int get dimensions => 64;

  @override
  Future<List<double>> embedText(String text) async {
    throw TimeoutException(
        'Simulated network timeout connecting to embedding provider');
  }

  @override
  Future<List<List<double>>> embedBatch(List<String> texts) async {
    throw Exception(
        'Simulated 500 internal server error from embedding provider');
  }
}

/// Slow embedding service that delays beyond reasonable timeout
class DelayedEmbeddingService implements SemanticEmbeddingService {
  final Duration delay;
  const DelayedEmbeddingService({this.delay = const Duration(seconds: 10)});

  @override
  String get modelId => 'delayed-mock';

  @override
  int get dimensions => 64;

  @override
  Future<List<double>> embedText(String text) async {
    await Future.delayed(delay);
    return List.filled(dimensions, 0.1);
  }

  @override
  Future<List<List<double>>> embedBatch(List<String> texts) async {
    await Future.delayed(delay);
    return texts.map((_) => List.filled(dimensions, 0.1)).toList();
  }
}

void main() {
  final testEntries = [
    WorldEntry(
      id: 1,
      keys: ['银月城'],
      content: '【世界观/locations】银月城是北境最大的魔法研究中心。',
      sourceType: 'location',
    ),
    WorldEntry(
      id: 2,
      keys: ['白港'],
      content: '【世界观/locations】白港是北海不冻港，往来商船繁多。',
      sourceType: 'location',
    ),
    WorldEntry(
      id: 3,
      keys: ['禁忌'],
      content: '【世界观/rules】严禁私自开启深渊之门。',
      sourceType: 'rule',
    ),
  ];

  group('P1.3 — Hybrid Retrieval Fallback & Fault Tolerance', () {
    test('Gracefully degrades to deterministic when embedding service throws',
        () async {
      final retriever = SemanticWorldRetriever(
        embeddingService: ThrowingEmbeddingService(),
      );
      final builder = WorldContextBuilder.hybrid(
        semanticRetriever: retriever,
      );

      // Build async with failing embedding service
      final context = await builder.buildAsync(
        entries: testEntries,
        query: '银月城有什么特色？',
        location: '银月城',
        characterNames: const [],
        tokenBudget: 1024,
      );

      // Must not throw; deterministic retrieval must still succeed
      expect(context.all, isNotEmpty);
      final recalledIds = context.all.map((e) => e.entryId).toSet();
      expect(recalledIds,
          contains(1)); // 银月城 matched by deterministic location/keys
      expect(recalledIds, contains(3)); // Rule constraint retained
      expect(recalledIds, isNot(contains(2))); // Irrelevant 白港 filtered
    });

    test('Isolated from corrupt or malformed cached embeddings', () async {
      // Mock repo returning corrupt dimension
      final mockRepo = _CorruptEmbeddingRepository();
      final retriever = SemanticWorldRetriever(
        embeddingService: const DeterministicFakeEmbeddingService(),
        repository: mockRepo,
      );
      final builder = WorldContextBuilder.hybrid(
        semanticRetriever: retriever,
      );

      final context = await builder.buildAsync(
        entries: testEntries,
        query: '银月城',
        location: '银月城',
        characterNames: const [],
        tokenBudget: 1024,
      );

      expect(context.all, isNotEmpty);
      expect(context.all.map((e) => e.entryId), contains(1));
    });

    test(
        'Authority model: Runtime HEAD, SceneState, and Baseline authority intact',
        () {
      // Create orchestrator with hybrid builder
      const builder = WorldContextBuilder.hybrid(
        semanticRetriever: SemanticWorldRetriever(
          embeddingService: DeterministicFakeEmbeddingService(),
        ),
      );
      const orchestrator = ContextOrchestrator(worldBuilder: builder);

      final promptContext = orchestrator.build(
        rawInput: '我要前往白港。',
        config: AdventureConfig(name: '主角'),
        sceneState: const SceneState(
          location: '银月城', // SceneState location authority
          time: '黄昏',
        ),
        worldEntries: testEntries,
        messages: const [],
        summary: null,
        persona: null,
        capability: const ModelContextCapability.conservative(),
        requestedResponseTokens: 1024,
      );

      // Verify SceneState authority is unchanged:
      expect(promptContext.sceneState.location, '银月城');
      expect(promptContext.sceneState.time, '黄昏');

      // Verify WorldContext kinds adhere to: constraint > fact > lore
      for (final item in promptContext.world.constraints) {
        expect(item.kind, WorldContextKind.constraint);
      }
      for (final item in promptContext.world.facts) {
        expect(item.kind, WorldContextKind.fact);
      }
      for (final item in promptContext.world.lore) {
        expect(item.kind, WorldContextKind.lore);
      }

      // Verify diagnostics audit integrity
      final diag = promptContext.trace.toDiagnostics();
      expect(diag['world_retrieval'], isNotNull);
      expect(diag['world_retrieval'], isA<List>());
    });
  });
}

class _CorruptEmbeddingRepository implements IWorldEmbeddingRepository {
  @override
  Future<int> insertEmbedding(WorldEntryEmbedding embedding) async => 1;

  @override
  Future<void> saveBatch(List<WorldEntryEmbedding> embeddings) async {}

  @override
  Future<WorldEntryEmbedding?> getEmbeddingForEntry(int entryId,
      {required String modelId, required String contentHash}) async {
    // Return wrong dimension to test resilience
    return WorldEntryEmbedding(
      entryId: entryId,
      modelId: modelId,
      contentHash: contentHash,
      dimensions: 3,
      vector: const [0.1, 0.2, 0.3], // Mismatched dimension (service uses 64)
      createdAt: DateTime.now(),
    );
  }

  @override
  Future<List<WorldEntryEmbedding>> getEmbeddingsForAdventure(
    int adventureId, {
    required String modelId,
  }) async {
    return const [];
  }

  @override
  Future<void> deleteByEntryId(int entryId) async {}

  @override
  Future<void> deleteByAdventureId(int adventureId) async {}
}
