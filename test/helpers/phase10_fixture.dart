import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/adventure/adventure_readiness_gate.dart';
import 'package:lt_dialogue/application/resources/assembly_readiness_coordinator.dart';
import 'package:lt_dialogue/application/resources/assembly_readiness_repository.dart';
import 'package:lt_dialogue/application/resources/resource_assembly_builder.dart';
import 'package:lt_dialogue/application/resources/resource_revision_repository.dart';
import 'package:lt_dialogue/application/resources/resource_revision_service.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_revision.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository_impl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Full Phase 10 stack assembled exactly like the production composition root
/// (`riverpod_providers.dart`), on a real SQLite file.
class Phase10Fixture {
  late Directory tempDir;
  late Database db;
  late ResourceTreeRepositoryImpl treeRepository;
  late ResourceRevisionRepositoryImpl revisionRepository;
  late ResourceRevisionService revisionService;
  late ResourceAssemblyBuilder builder;
  late AssemblyReadinessRepositoryImpl readinessRepository;
  late AssemblyReadinessCoordinator coordinator;
  late AdventureReadinessGate gate;

  Future<void> setUp({String prefix = 'lt_phase10_'}) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    tempDir = await Directory.systemTemp.createTemp(prefix);
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
    db = await DatabaseService.database;

    treeRepository = ResourceTreeRepositoryImpl(getDb: () async => db);
    revisionRepository = ResourceRevisionRepositoryImpl(getDb: () async => db);
    final captureEngine = RevisionCaptureEngine(
      revisionRepository: revisionRepository,
      treeBoundary: treeRepository,
    );
    revisionService = ResourceRevisionService(
      revisionRepository: revisionRepository,
      captureEngine: captureEngine,
      treeBoundary: treeRepository,
      getDb: () async => db,
    );
    builder = ResourceAssemblyBuilder(
      revisionRepository: revisionRepository,
      typeResolver: (id) async => (await treeRepository.findResource(id))?.type,
    );
    readinessRepository =
        AssemblyReadinessRepositoryImpl(getDb: () async => db);
    coordinator = AssemblyReadinessCoordinator(
      getDb: () async => db,
      readinessRepository: readinessRepository,
      revisionRepository: revisionRepository,
      revisionService: revisionService,
      builder: builder,
      typeResolver: (id) async => (await treeRepository.findResource(id))?.type,
    );
    gate = AdventureReadinessGate(
      getDb: () async => db,
      treeRepository: treeRepository,
      revisionRepository: revisionRepository,
      revisionService: revisionService,
      coordinator: coordinator,
      builder: builder,
    );
  }

  Future<void> tearDown() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  }

  /// Creates a worldview resource with [sectionBodies] and records it as the
  /// latest head. Sections use canonical worldview module titles so the
  /// legacy projection maps them into `detail_json` modules.
  Future<ResourceId> createWorldview(
    String id,
    List<List<String>> sections, {
    String summary = '',
    String name = '测试世界观',
    bool confirmed = false,
  }) async {
    const moduleTitles = <String>['概览', '规则与边界', '地点与地理'];
    final resourceId = await treeRepository.createResourceTree(
      ResourceTreeDraft(
        id: ResourceId(id),
        type: ResourceType.worldview,
        name: name,
        summary: summary,
        sections: [
          for (var s = 0; s < sections.length; s++)
            ResourceTreeSectionDraft(
              title: moduleTitles[s % moduleTitles.length],
              parts: [
                for (var p = 0; p < sections[s].length; p++)
                  ResourceTreePartDraft(
                    title: '部件$p',
                    content: sections[s][p],
                  ),
              ],
            ),
        ],
      ),
    );
    if (confirmed) {
      await _confirmAll(resourceId);
    }
    await revisionService.captureRevision(
      resourceId,
      cause: RevisionCause.manualSave,
    );
    return resourceId;
  }

  /// Confirms every section and part of the resource (editor "publish" flow).
  Future<void> _confirmAll(ResourceId resourceId) async {
    final sections = await treeRepository.readSections(resourceId);
    for (final section in sections) {
      for (final part in await treeRepository.readParts(section.id)) {
        await treeRepository.updatePart(
          id: part.id,
          expectedUpdatedAt: await readNodeUpdatedAt(part.id.value),
          status: NodeStatus.confirmed,
        );
      }
      await treeRepository.updateSection(
        id: section.id,
        expectedUpdatedAt: await readNodeUpdatedAt(section.id.value),
        status: NodeStatus.confirmed,
      );
    }
  }

  /// Creates a character resource whose prose parts are confirmed (the shape
  /// the legacy mapper produces): part titles use the canonical mapper titles
  /// so the runtime projection maps them to `first_mes` / `system_prompt`.
  Future<ResourceId> createCharacter(
    String id, {
    String firstMessage = '你好，冒险者。',
    String systemPrompt = '你是这个世界的叙事者。',
  }) async {
    final resourceId = await treeRepository.createResourceTree(
      ResourceTreeDraft(
        id: ResourceId(id),
        type: ResourceType.character,
        name: '测试角色',
        summary: '角色摘要',
        sections: [
          ResourceTreeSectionDraft(
            title: '剧情',
            parts: [
              ResourceTreePartDraft(
                title: '开场白',
                content: firstMessage,
              ),
            ],
          ),
          ResourceTreeSectionDraft(
            title: '行为指令',
            parts: [
              ResourceTreePartDraft(
                title: '系统提示',
                content: systemPrompt,
              ),
            ],
          ),
        ],
      ),
    );
    // Confirm the prose parts so they qualify as canon, mirroring the
    // production mapper (`LegacyResourceMapper` writes confirmed prose).
    final sections = await treeRepository.readSections(resourceId);
    for (final section in sections) {
      final parts = await treeRepository.readParts(section.id);
      for (final part in parts) {
        await treeRepository.updatePart(
          id: part.id,
          expectedUpdatedAt: await readNodeUpdatedAt(part.id.value),
          status: NodeStatus.confirmed,
        );
      }
    }
    await revisionService.captureRevision(
      resourceId,
      cause: RevisionCause.manualSave,
    );
    return resourceId;
  }

  /// Current `updated_at` of a node row — the optimistic token the writer
  /// expects.
  Future<String> readNodeUpdatedAt(String nodeId) async {
    for (final table in const [
      'resource_parts',
      'resource_sections',
      'resources',
    ]) {
      final rows = await db.query(
        table,
        where: 'id = ?',
        whereArgs: <Object?>[nodeId],
        limit: 1,
      );
      if (rows.isNotEmpty) return rows.first['updated_at'].toString();
    }
    throw StateError('node $nodeId not found');
  }

  /// A second coordinator sharing the same repositories — models another
  /// process/worker so tests can create genuine interleavings beyond the
  /// single-flight guard.
  AssemblyReadinessCoordinator secondCoordinator() =>
      AssemblyReadinessCoordinator(
        getDb: () async => db,
        readinessRepository: readinessRepository,
        revisionRepository: revisionRepository,
        revisionService: revisionService,
        builder: builder,
        typeResolver: (id) async =>
            (await treeRepository.findResource(id))?.type,
      );

  /// Full latest-head revision (id + content hash).
  Future<ResourceRevision> latestHeadRevision(ResourceId id) async {
    final head =
        await revisionRepository.readHead(id, ResourceRevisionKind.latestHead);
    if (head == null) {
      throw StateError('resource ${id.value} has no latest head');
    }
    return head;
  }

  /// Appends an extra confirmed part body edit: updates a part's content and
  /// records the new head, i.e. "the user edited the resource".
  Future<void> editResourceBody(
      ResourceId resourceId, String newContent) async {
    final sections = await treeRepository.readSections(resourceId);
    final parts = await treeRepository.readParts(sections.first.id);
    await treeRepository.updatePart(
      id: parts.first.id,
      expectedUpdatedAt: await readNodeUpdatedAt(parts.first.id.value),
      content: newContent,
      status: NodeStatus.confirmed,
    );
    await treeRepository.updateSection(
      id: sections.first.id,
      expectedUpdatedAt: await readNodeUpdatedAt(sections.first.id.value),
      status: NodeStatus.confirmed,
    );
    await revisionService.captureRevision(
      resourceId,
      cause: RevisionCause.manualSave,
    );
  }
}
