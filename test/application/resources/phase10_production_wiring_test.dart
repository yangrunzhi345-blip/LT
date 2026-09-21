import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/adventure/adventure_readiness_gate.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/application/resources/resource_creation_contracts.dart';
import 'package:lt_dialogue/models/worldview_details.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/domain/resources/resource_revision.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository_impl.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository.dart';
import 'package:lt_dialogue/services/worldview_snapshot_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Phase 10 production wiring: a real `ProviderContainer` with **no
/// overrides and no hand-built repositories** must reach readiness →
/// coordinator → revision → Adventure start boundary end to end
/// (Phase 9 R2-B1 regression class).
void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  late Directory tempDir;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('lt_phase10_wiring_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
    container = ProviderContainer();
  });

  tearDown(() async {
    container.dispose();
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('all Phase 10 providers resolve from the production graph', () async {
    final readinessRepo = container.read(assemblyReadinessRepositoryProvider);
    final builder = container.read(resourceAssemblyBuilderProvider);
    final coordinator = container.read(assemblyReadinessCoordinatorProvider);
    final gate = container.read(adventureReadinessGateProvider);
    expect(readinessRepo, isNotNull);
    expect(builder, isNotNull);
    expect(coordinator, isNotNull);
    expect(gate, isNotNull);
  });

  test(
      'compression infrastructure attaches to the coordinator without a '
      'provider cycle', () async {
    // Reading the link provider must not throw (it reads the compression
    // coordinator + worker lazily) and must leave the coordinator able to
    // enqueue OVERFLOW work.
    container.read(assemblyReadinessCompressionLinkProvider);
    expect(
      container.read(assemblyReadinessCoordinatorProvider),
      same(container.read(assemblyReadinessCoordinatorProvider)),
    );
  });

  test('end to end: create → capture → prepare → ready → gate freeze',
      () async {
    final coordinator = container.read(assemblyReadinessCoordinatorProvider);
    final gate = container.read(adventureReadinessGateProvider);
    final revisionService = container.read(resourceRevisionServiceProvider);
    final treeRepository = ResourceTreeRepositoryImpl(
      getDb: () => DatabaseService.database,
    );

    // 1. Create a resource through the production writer.
    final resourceId = await treeRepository.createResourceTree(
      const ResourceTreeDraft(
        id: ResourceId('wiring_wv_1'),
        type: ResourceType.worldview,
        name: '接线测试世界观',
        summary: '接线测试概览',
        sections: [
          ResourceTreeSectionDraft(
            title: '概览',
            parts: [
              ResourceTreePartDraft(
                title: '部件0',
                content: '接线测试的正文内容。',
              ),
            ],
          ),
        ],
      ),
    );

    // 2. Capture the latest head through the production revision service.
    await revisionService.captureRevision(
      resourceId,
      cause: RevisionCause.manualSave,
    );

    // 3. Prepare via the production coordinator.
    final outcome = await coordinator.prepare(resourceId);
    expect(outcome.record.state, ReadinessState.ready);
    expect(outcome.published, isTrue);

    // 4. The gate freezes the config from the assembly revision.
    final config = AdventureConfig(
      name: '接线冒险',
      worldview: '接线测试世界观',
      worldviewSnapshot: <String, dynamic>{
        'source_id': resourceId.value,
        'name': '接线测试世界观',
        'description': '本地描述',
        'format_version': WorldviewDetails.currentFormatVersion,
        'detail_json': <String, dynamic>{},
      },
    );
    final frozen = await gate.enforceAndFreeze(config);
    expect(frozen.resourceBindings, hasLength(1));
    expect(
      frozen.worldviewSnapshot!['content_hash'],
      outcome.record.assemblyContentHash,
    );
    // The binding names the published assembly revision.
    final assemblyHead = await container
        .read(resourceRevisionRepositoryProvider)
        .readHead(resourceId, ResourceRevisionKind.assembly);
    expect(assemblyHead, isNotNull);
    expect(
      frozen.resourceBindings.first.revisionId,
      assemblyHead!.revisionId.value,
    );

    // 5. Managed entries derived from the frozen snapshot carry the assembly
    //    revision provenance (the world_entries.source_revision_id column is
    //    declared in the v42 schema and round-trips through toDbMap).
    final entries = WorldviewSnapshotService.buildManagedEntries(
      0,
      frozen.worldviewSnapshot!,
      sourceRevisionId: frozen.resourceBindings.first.revisionId,
    );
    expect(entries, isNotEmpty);
    expect(
      entries.every((entry) =>
          entry.sourceRevisionId == frozen.resourceBindings.first.revisionId),
      isTrue,
    );
    expect(
      entries.every((entry) =>
          entry.sourceSnapshotHash ==
          frozen.worldviewSnapshot!['content_hash']),
      isTrue,
    );
  });

  test(
      'production creation prepares a character before Adventure readiness is '
      'resolved', () async {
    final pipeline = container.read(resourceCreationPipelineProvider);
    final gate = container.read(adventureReadinessGateProvider);

    final created = await pipeline.createBatch([
      const ResourceCreationRequest(
        resourceType: ResourceType.character,
        method: CreationMethod.manual,
        name: '新建主角',
        idempotencyKey: 'phase10-created-protagonist',
        resourceId: 'phase10-created-protagonist',
        origin: 'phase10-test',
        initialSections: [
          ResourceTreeSectionDraft(
            title: '剧情',
            parts: [
              ResourceTreePartDraft(title: '开场白', content: '你好，冒险者。'),
            ],
          ),
          ResourceTreeSectionDraft(
            title: '行为指令',
            parts: [
              ResourceTreePartDraft(title: '系统提示', content: '保持角色设定。'),
            ],
          ),
        ],
      ),
      const ResourceCreationRequest(
        resourceType: ResourceType.character,
        method: CreationMethod.manual,
        name: '新建同行者',
        idempotencyKey: 'phase10-created-companion',
        resourceId: 'phase10-created-companion',
        origin: 'phase10-test',
        initialSections: [
          ResourceTreeSectionDraft(
            title: '剧情',
            parts: [
              ResourceTreePartDraft(title: '开场白', content: '同行吧。'),
            ],
          ),
          ResourceTreeSectionDraft(
            title: '行为指令',
            parts: [
              ResourceTreePartDraft(title: '系统提示', content: '协助主角。'),
            ],
          ),
        ],
      ),
    ]);

    final resourceId = created.first.resourceId!;
    final companionId = created.last.resourceId!;
    final readinessRepository =
        container.read(assemblyReadinessRepositoryProvider);
    for (final id in [resourceId, companionId]) {
      final record = await readinessRepository.read(id.value);
      expect(record?.state, ReadinessState.ready);
      expect(record?.assemblyRevisionId, isNotEmpty);
    }

    final config = AdventureConfig(
      name: '创建链路冒险',
      selectedCharacters: [
        AdventureSelectedCharacter(
          id: resourceId.value,
          characterId: resourceId.value,
          characterName: '新建主角',
          isProtagonist: true,
        ),
        AdventureSelectedCharacter(
          id: companionId.value,
          characterId: companionId.value,
          characterName: '新建同行者',
          narrativeRole: AdventureCharacterRole.companion,
        ),
      ],
    );
    final statuses = await gate.resolveConfig(config);
    expect(statuses[resourceId.value]!.status, AdventureAssetGateStatus.ready);
    expect(
      statuses[companionId.value]!.status,
      AdventureAssetGateStatus.ready,
    );
    final frozen = await gate.enforceAndFreeze(config);
    expect(
      frozen.selectedCharacters.every((item) => item.characterCardJson != null),
      isTrue,
    );
  });
}
