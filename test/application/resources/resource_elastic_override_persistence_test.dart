import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/resource_blueprint_repository.dart';
import 'package:lt_dialogue/application/resources/resource_creation_contracts.dart';
import 'package:lt_dialogue/application/resources/resource_creation_pipeline.dart';
import 'package:lt_dialogue/domain/resources/resource_blueprint.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository_impl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// BUG-11 回归：既有资源重新规划的 confirm 事务不得静默抹除
/// `resources.metadata_json.generationElasticPercent`（ADR-0003 资源级弹性覆盖）。
///
/// 真实 SQLite / 真实 Pipeline / 真实 Repository / 真实 confirm 事务；不替换模型
/// （本用例不触发任何网络调用）。同时守护：显式清除覆盖后不得被"复活"、其他无关
/// metadata 不得丢失、已冻结的 blueprint 弹性不受后续配置影响、会话级覆盖不得改写
/// 持久化的资源级设置。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  late Directory tempDir;
  late ResourceTreeRepositoryImpl treeRepo;
  late ResourceCreationPipeline pipeline;
  late ResourceBlueprintRepositoryImpl blueprintRepo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lt_elastic_persist_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();

    treeRepo =
        ResourceTreeRepositoryImpl(getDb: () => DatabaseService.database);
    pipeline = ResourceCreationPipeline(
      getDb: () => DatabaseService.database,
      hasAiCredentials: () => true,
      treeRepository: treeRepo,
    );
    blueprintRepo = ResourceBlueprintRepositoryImpl(
      getDb: () => DatabaseService.database,
      treeRepository: treeRepo,
    );
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    DatabaseService.customDbDir = null;
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  Future<Map<String, Object?>> readMetadata(String resourceId) async {
    final rows = await (await DatabaseService.database).query('resources',
        columns: ['metadata_json'],
        where: 'id = ? AND deleted_at IS NULL',
        whereArgs: [resourceId],
        limit: 1);
    final raw = rows.single['metadata_json']?.toString() ?? '{}';
    return (jsonDecode(raw) as Map).cast<String, Object?>();
  }

  Future<int?> frozenPercent(String blueprintId) async {
    final rows = await (await DatabaseService.database).query(
      'resource_blueprints',
      columns: ['elastic_percent'],
      where: 'blueprint_id = ?',
      whereArgs: [blueprintId],
      limit: 1,
    );
    return (rows.single['elastic_percent'] as num?)?.toInt();
  }

  ResourceBlueprint makeBlueprint({
    required String sessionId,
    required String blueprintId,
    ResourceType type = ResourceType.character,
    int revision = 1,
  }) {
    return ResourceBlueprint(
      blueprintId: blueprintId,
      sessionId: sessionId,
      resourceType: type,
      suggestedName: '既有资源',
      summary: '既有资源的大纲',
      revision: revision,
      status: BlueprintStatus.draft,
      sections: [
        BlueprintSection(
          id: 'sec_1',
          title: '第一章',
          summary: '',
          sortOrder: 0,
          parts: const [
            BlueprintPart(
              id: 'part_1',
              sectionId: 'sec_1',
              title: '开篇',
              generationGoal: '描写开篇',
              estimatedLength: 800,
              sortOrder: 0,
            ),
            BlueprintPart(
              id: 'part_2',
              sectionId: 'sec_1',
              title: '展开',
              generationGoal: '描写展开',
              estimatedLength: 1000,
              sortOrder: 1,
            ),
          ],
        ),
      ],
    );
  }

  Future<ResourceCreationSession> newSession(
    ResourceType type, {
    int? sessionElasticPercent,
  }) async {
    final origin = ResourceCreationOriginEnvelope(
      origin: 'test',
      libraryMode: 'adventure',
      elasticPercent: sessionElasticPercent,
    ).encode();
    final result = await pipeline.create(ResourceCreationRequest(
      resourceType: type,
      method: CreationMethod.aiReference,
      name: '既有资源',
      idempotencyKey: 'idemp_${DateTime.now().microsecondsSinceEpoch}',
      referenceSource: ReferenceSource.text('一份用于回归的参考正文。'),
      origin: origin,
    ));
    return (await pipeline.findSession(result.sessionId!))!;
  }

  Future<({Resource resource, String token})> seedExistingResource({
    ResourceType type = ResourceType.character,
    Map<String, Object?> metadata = const <String, Object?>{},
    int? overridePercent,
  }) async {
    final resource = await treeRepo.createResource(
        type: type, name: '既有资源', metadata: metadata);
    if (overridePercent != null) {
      final t0 = (await treeRepo.readNodeState(resource.id))!.updatedAt;
      await treeRepo.updateGenerationElasticOverride(
          id: resource.id, expectedUpdatedAt: t0, percent: overridePercent);
    }
    final token = (await treeRepo.readNodeState(resource.id))!.updatedAt;
    return (resource: resource, token: token);
  }

  group('BUG-11 资源级弹性覆盖跨 confirm 持久化', () {
    test('既有资源重新规划后仍保留 generationElasticPercent', () async {
      final seeded = await seedExistingResource(overridePercent: 50);
      final session = await newSession(ResourceType.character);
      final bp = makeBlueprint(
          sessionId: session.sessionId, blueprintId: 'bp_keep_override');
      await blueprintRepo.saveBlueprint(bp);

      final confirmed = await blueprintRepo.confirmBlueprint(
        blueprintId: bp.blueprintId,
        explicitResourceId: seeded.resource.id,
        expectedResourceUpdatedAt: seeded.token,
      );
      expect(confirmed.resourceId, seeded.resource.id);

      final meta = await readMetadata(seeded.resource.id.value);
      expect(meta[ResourceTreeSchema.metadataGenerationElasticPercentKey], 50,
          reason: '重新规划不得静默抹除资源级弹性覆盖');
      // 冻结值本身仍为该资源覆盖值。
      expect(await frozenPercent(bp.blueprintId), 50);
    });

    test('显式清除覆盖后重新规划不得将其复活', () async {
      final seeded = await seedExistingResource(overridePercent: 50);
      // 用户切回"继承全局"：键被移除。
      final clearToken =
          (await treeRepo.readNodeState(seeded.resource.id))!.updatedAt;
      await treeRepo.updateGenerationElasticOverride(
          id: seeded.resource.id, expectedUpdatedAt: clearToken, percent: null);
      final cleared = await readMetadata(seeded.resource.id.value);
      expect(
          cleared.containsKey(
              ResourceTreeSchema.metadataGenerationElasticPercentKey),
          isFalse);

      final session = await newSession(ResourceType.character);
      final bp = makeBlueprint(
          sessionId: session.sessionId, blueprintId: 'bp_cleared');
      await blueprintRepo.saveBlueprint(bp);
      final token =
          (await treeRepo.readNodeState(seeded.resource.id))!.updatedAt;
      await blueprintRepo.confirmBlueprint(
        blueprintId: bp.blueprintId,
        explicitResourceId: seeded.resource.id,
        expectedResourceUpdatedAt: token,
      );

      final meta = await readMetadata(seeded.resource.id.value);
      expect(
          meta.containsKey(
              ResourceTreeSchema.metadataGenerationElasticPercentKey),
          isFalse,
          reason: '缺失该键表示继承全局，不得被重新规划恢复成旧值');
    });

    test('重新规划保留其他无关 metadata 字段', () async {
      final seeded = await seedExistingResource(
        overridePercent: 50,
        metadata: const <String, Object?>{'user_note': '请保留我'},
      );
      final session = await newSession(ResourceType.character);
      final bp = makeBlueprint(
          sessionId: session.sessionId, blueprintId: 'bp_other_meta');
      await blueprintRepo.saveBlueprint(bp);
      await blueprintRepo.confirmBlueprint(
        blueprintId: bp.blueprintId,
        explicitResourceId: seeded.resource.id,
        expectedResourceUpdatedAt: seeded.token,
      );

      final meta = await readMetadata(seeded.resource.id.value);
      expect(meta['user_note'], '请保留我', reason: '无关 metadata 不应丢失');
      expect(meta[ResourceTreeSchema.metadataGenerationElasticPercentKey], 50);
      // confirm 自身权威字段仍需被刷新。
      expect(meta['confirmed_blueprint_id'], bp.blueprintId);
    });

    test('显式会话级覆盖不改写持久化的资源级设置', () async {
      final seeded = await seedExistingResource(overridePercent: 50);
      final session =
          await newSession(ResourceType.character, sessionElasticPercent: 35);
      final bp = makeBlueprint(
          sessionId: session.sessionId, blueprintId: 'bp_session_override');
      await blueprintRepo.saveBlueprint(bp);
      await blueprintRepo.confirmBlueprint(
        blueprintId: bp.blueprintId,
        explicitResourceId: seeded.resource.id,
        expectedResourceUpdatedAt: seeded.token,
      );

      // 冻结值为会话级 35（优先级最高）。
      expect(await frozenPercent(bp.blueprintId), 35);
      // 持久化的资源级覆盖保持 50，不被会话级设置改写。
      final meta = await readMetadata(seeded.resource.id.value);
      expect(meta[ResourceTreeSchema.metadataGenerationElasticPercentKey], 50);
    });

    test('新建资源 confirm 不写入弹性覆盖键（保持原行为）', () async {
      final session = await newSession(ResourceType.character);
      final bp = makeBlueprint(
          sessionId: session.sessionId, blueprintId: 'bp_new_resource');
      await blueprintRepo.saveBlueprint(bp);

      final confirmed =
          await blueprintRepo.confirmBlueprint(blueprintId: bp.blueprintId);
      final meta = await readMetadata(confirmed.resourceId.value);
      expect(
          meta.containsKey(
              ResourceTreeSchema.metadataGenerationElasticPercentKey),
          isFalse,
          reason: '新资源未设置覆盖时不应凭空写入该键');
      expect(meta['confirmed_blueprint_id'], bp.blueprintId);
    });
  });
}
