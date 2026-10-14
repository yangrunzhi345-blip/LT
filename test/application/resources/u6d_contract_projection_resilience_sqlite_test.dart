import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lt_dialogue/application/llm/llm_gateway.dart';
import 'package:lt_dialogue/application/resources/resource_blueprint_repository.dart';
import 'package:lt_dialogue/application/resources/resource_creation_contracts.dart';
import 'package:lt_dialogue/controllers/streaming_resource_generation_controller.dart';
import 'package:lt_dialogue/domain/resources/content_requirements.dart';
import 'package:lt_dialogue/domain/resources/part_contract_status.dart';
import 'package:lt_dialogue/domain/resources/resource_blueprint.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/streaming_generation_runtime_contracts.dart';
import 'package:lt_dialogue/features/resource_studio/application/use_cases/resource_studio_runtime.dart';
import 'package:lt_dialogue/features/resource_studio/domain/models/resource_studio_state.dart';
import 'package:lt_dialogue/features/resource_studio/presentation/controllers/resource_studio_controller.dart';
import 'package:lt_dialogue/services/database_service.dart';
import '../../helpers/r01_streaming_fixture.dart';

/// P2 regression: the U6-D contract projection is OPTIONAL, read-only display
/// data. A malformed / incompatible stored blueprint must degrade that Part to
/// `unavailable` (never `legacyUnknownContract`) and must NOT block opening the
/// resource or swallow a genuine resource-tree read failure.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;
  late Directory directory;
  late R01StreamingFixture fixture;
  late StreamingResourceGenerationController controller;
  late StreamingResourceStudioRuntime runtime;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('lt_u6d_p2_');
    DatabaseService.customDbDir = directory.path;
    await DatabaseService.resetDatabase();
    await DatabaseService.database;
    fixture = R01StreamingFixture();
    controller = StreamingResourceGenerationController(
      service: fixture.buildService(r01Completer('文' * 1200)),
      sessionRepository: fixture.sessionRepository,
    );
    runtime = StreamingResourceStudioRuntime(
      controller: controller,
      sessionRepository: fixture.sessionRepository,
      treeRepository: fixture.treeRepository,
      blueprintRepository: fixture.blueprintRepository,
      pipeline: fixture.pipeline,
      gateway: _NoopGateway(),
    );
  });

  tearDown(() async {
    controller.dispose();
    await DatabaseService.resetDatabase();
    DatabaseService.customDbDir = null;
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  Future<({ResourceId id, String blueprintId})> seedAiResource({
    required String key,
    ContentRequirements? contract,
  }) async {
    final session = await fixture.pipeline.create(ResourceCreationRequest(
        resourceType: ResourceType.character,
        method: CreationMethod.aiReference,
        name: 'P2 $key',
        referenceSource: ReferenceSource.text('参考'),
        targetCharacters: 3000,
        idempotencyKey: 'p2_$key'));
    final blueprint = ResourceBlueprint(
        blueprintId: 'bp_$key',
        sessionId: session.sessionId!,
        resourceType: ResourceType.character,
        suggestedName: 'P2 $key',
        summary: '',
        targetCapacity: 3000,
        sections: [
          BlueprintSection(id: 's', title: '背景', parts: [
            BlueprintPart(
                id: 'p0',
                sectionId: 's',
                title: '背景',
                generationGoal: 'g',
                estimatedLength: 800,
                contentRequirements: contract),
          ])
        ]);
    final repo = ResourceBlueprintRepositoryImpl(
        getDb: () async => DatabaseService.database,
        treeRepository: fixture.treeRepository);
    await repo.saveBlueprint(blueprint);
    final confirmed = await repo.confirmBlueprint(blueprintId: 'bp_$key');
    return (id: confirmed.resourceId, blueprintId: 'bp_$key');
  }

  Future<void> corruptBlueprintJson(String blueprintId) async {
    await (await DatabaseService.database).update(
        'resource_blueprints', {'blueprint_json': '{not valid json'},
        where: 'blueprint_id = ?', whereArgs: [blueprintId]);
  }

  test('a malformed linked blueprint does not throw out of the projection',
      () async {
    final seeded = await seedAiResource(key: 'corrupt1');
    await corruptBlueprintJson(seeded.blueprintId);
    // Must not throw.
    final statuses = await runtime.blueprintPartContracts(seeded.id);
    expect(statuses.values, everyElement(PartContractStatus.unavailable),
        reason: '损坏蓝图必须降级为 unavailable，绝不伪造 legacyUnknownContract');
  });

  test('a malformed linked blueprint does not block Studio load', () async {
    final seeded = await seedAiResource(key: 'corrupt2');
    await corruptBlueprintJson(seeded.blueprintId);
    final studio =
        ResourceStudioController(runtime: runtime, resourceId: seeded.id.value);
    await studio.load();
    expect(studio.state.status, isNot(ResourceStudioStatus.failed),
        reason: '正文树有效时，附加契约投影失败不得使 Studio 整体失败');
    expect(studio.state.tree, isNotNull);
    expect(studio.partContractStatuses.values,
        everyElement(PartContractStatus.unavailable));
  });

  test('a valid legacy blueprint still classifies as legacyUnknownContract',
      () async {
    final seeded = await seedAiResource(key: 'legacy_ok');
    final statuses = await runtime.blueprintPartContracts(seeded.id);
    expect(statuses.values.single, PartContractStatus.legacyUnknownContract);
  });

  test('a valid contracted blueprint still classifies as confirmedContract',
      () async {
    final seeded = await seedAiResource(
        key: 'contracted',
        contract: ContentRequirements(
            kind: PartContentKind.narrative,
            minimumCharacters: 100,
            validationProfile: PartValidationProfile.narrativeSectionsV1));
    final statuses = await runtime.blueprintPartContracts(seeded.id);
    expect(statuses.values.single, PartContractStatus.confirmedContract);
  });

  test('a genuine resource-tree read failure is still surfaced, not swallowed',
      () async {
    final studio = ResourceStudioController(
        runtime: _ThrowingTreeRuntime(), resourceId: 'res_x');
    await studio.load();
    expect(studio.state.status, ResourceStudioStatus.failed,
        reason: '主体资源树读取失败必须仍按原错误处理');
  });

  test('the projection is read-only: history body/hash/revision are preserved',
      () async {
    final seeded = await seedAiResource(key: 'preserve');
    final tree0 = (await fixture.treeRepository.readTree(seeded.id))!;
    final partId = tree0.parts.single.id.value;
    await (await DatabaseService.database).update(
        'resource_parts', {'content': '荒', 'content_hash': 'h-legacy'},
        where: 'id = ?', whereArgs: [partId]);
    final revisionsBefore = (await (await DatabaseService.database).query(
            'resource_revisions',
            where: 'resource_id = ?',
            whereArgs: [seeded.id.value]))
        .length;

    await corruptBlueprintJson(seeded.blueprintId);
    await runtime.blueprintPartContracts(seeded.id);
    final studio =
        ResourceStudioController(runtime: runtime, resourceId: seeded.id.value);
    await studio.load();

    final after = (await fixture.treeRepository.readTree(seeded.id))!;
    expect(after.parts.single.content, '荒');
    expect(after.parts.single.contentHash, 'h-legacy');
    final revisionsAfter = (await (await DatabaseService.database).query(
            'resource_revisions',
            where: 'resource_id = ?',
            whereArgs: [seeded.id.value]))
        .length;
    expect(revisionsAfter, revisionsBefore, reason: '投影不得写入 revision');
  });
}

/// Minimal LlmGateway stand-in; the projection never calls it.
final class _NoopGateway implements LlmGateway {
  @override
  bool get isConfigured => true;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('$invocation');
}

final class _ThrowingTreeRuntime implements ResourceStudioRuntime {
  @override
  Future<ResourceTree?> readTree(ResourceId resourceId) async =>
      throw StateError('boom');

  @override
  Future<StreamingGenerationSession?> getLatestSessionForResource(
    String resourceId,
  ) async =>
      null;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('$invocation');
}
