import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/resource_creation_contracts.dart';
import 'package:lt_dialogue/application/resources/resource_creation_pipeline.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository_impl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Phase 3 core: one creation pipeline for every entry point.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  late Directory tempDir;
  late ResourceTreeRepositoryImpl treeRepository;
  late ResourceCreationPipeline pipeline;
  var aiReady = true;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lt_phase3_creation_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
    treeRepository =
        ResourceTreeRepositoryImpl(getDb: () => DatabaseService.database);
    aiReady = true;
    pipeline = ResourceCreationPipeline(
      getDb: () => DatabaseService.database,
      hasAiCredentials: () => aiReady,
      treeRepository: treeRepository,
    );
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  Future<Map<String, int>> treeCounts() async {
    final db = await DatabaseService.database;
    Future<int> count(String table) async {
      final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM $table');
      return (rows.first['c'] as num).toInt();
    }

    return {
      'resources': await count('resources'),
      'sections': await count('resource_sections'),
      'parts': await count('resource_parts'),
    };
  }

  Future<Map<String, int>> legacyCounts() async {
    final db = await DatabaseService.database;
    Future<int> count(String table) async {
      final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM $table');
      return (rows.first['c'] as num).toInt();
    }

    return {
      'worldview_presets': await count('worldview_presets'),
      'character_cards': await count('character_cards'),
      'npc_cards': await count('npc_cards'),
    };
  }

  ResourceCreationRequest request({
    String name = '银月大陆',
    CreationMethod method = CreationMethod.manual,
    String key = 'key-1',
    ReferenceSource reference = ReferenceSource.none,
    bool initialSection = false,
    List<ResourceTreeSectionDraft> sections = const [],
    ResourceType type = ResourceType.worldview,
    String origin = 'library',
  }) =>
      ResourceCreationRequest(
        resourceType: type,
        method: method,
        name: name,
        idempotencyKey: key,
        referenceSource: reference,
        createInitialEmptySection: initialSection,
        initialSections: sections,
        origin: origin,
      );

  group('request validation', () {
    test('rejects an empty name and a missing idempotency key', () async {
      await expectLater(
        pipeline.create(request(name: '   ')),
        throwsA(isA<ResourceCreationException>()),
      );
      await expectLater(
        pipeline.create(request(key: ' ')),
        throwsA(isA<ResourceCreationException>()),
      );
    });

    test('rejects an over-long name', () async {
      await expectLater(
        pipeline.create(
          request(
              name: 'x' * (ResourceCreationValidator.maximumNameLength + 1)),
        ),
        throwsA(isA<ResourceCreationException>()),
      );
    });

    test('AI creation requires credentials before anything is written',
        () async {
      aiReady = false;
      await expectLater(
        pipeline.create(request(method: CreationMethod.aiReference)),
        throwsA(isA<ResourceCreationException>()),
      );
      expect(await pipeline.findByIdempotencyKey('key-1'), isNull);
      expect((await treeCounts())['resources'], 0);
    });

    test('shared statuses keep their frozen names and restart rules', () {
      expect(ResourceCreationStateMachine.statusNamesMatchFrozen(), isTrue);
      expect(
        ResourceCreationStateMachine.terminalsOnlyExitThroughRetry(),
        isTrue,
      );
    });

    test('illegal session transitions are rejected', () {
      expect(
        () => ResourceCreationStateMachine.advance(
          CreationSessionStatus.completed,
          CreationSessionStatus.validating,
        ),
        throwsA(isA<ResourceCreationException>()),
      );
      expect(
        ResourceCreationStateMachine.canTransition(
          CreationSessionStatus.draft,
          CreationSessionStatus.persisted,
        ),
        isFalse,
      );
    });
  });

  group('manual creation', () {
    test('creates an empty content tree by default', () async {
      final result = await pipeline.create(request());

      expect(result.status, CreationSessionStatus.persisted);
      expect(result.resourceId, isNotNull);
      expect(result.reusedExisting, isFalse);

      final tree = await treeRepository.readTree(result.resourceId!);
      expect(tree!.resource.name, '银月大陆');
      expect(tree.resource.type, ResourceType.worldview);
      expect(tree.sections, isEmpty);
      expect(tree.parts, isEmpty);

      final session = await pipeline.findByIdempotencyKey('key-1');
      expect(session!.status, CreationSessionStatus.persisted);
      expect(session.resourceId, result.resourceId);
    });

    test('can create one initial empty section', () async {
      final result = await pipeline.create(request(initialSection: true));
      final tree = await treeRepository.readTree(result.resourceId!);
      expect(tree!.sections, hasLength(1));
      expect(tree.sections.single.title, '概览');
      expect(tree.parts, isEmpty);
    });

    test('writes content handed over by the entry point', () async {
      final result = await pipeline.create(request(
        sections: const [
          ResourceTreeSectionDraft(
            title: '概述',
            parts: [ResourceTreePartDraft(title: '概述', content: '正文内容')],
          ),
        ],
      ));
      final tree = await treeRepository.readTree(result.resourceId!);
      final section = tree!.sections.single;
      expect(tree.orderedPartsOf(section.id).single.content, '正文内容');
    });

    test('records only minimal provenance metadata', () async {
      final result = await pipeline.create(request(
        type: ResourceType.character,
        reference: ReferenceSource.text('参考材料正文' * 5, label: '粘贴文本'),
        origin: 'adventure-wizard',
      ));

      final tree = await treeRepository.readTree(result.resourceId!);
      final metadata = tree!.resource.metadata;
      expect(metadata['authoring_method'], CreationMethod.manual.storageValue);
      expect(
        metadata[ResourceCreationPipeline.metadataCreationOrigin],
        'adventure-wizard',
      );
      expect(
        metadata[ResourceCreationPipeline.metadataReferenceKind],
        ReferenceSourceKind.text.storageValue,
      );
      expect(
        metadata[ResourceCreationPipeline.metadataReferenceCharCount],
        '参考材料正文'.length * 5,
      );
      // The reference body must never be copied into the resource metadata.
      expect(metadata.values.join().contains('参考材料正文'), isFalse);
    });
  });

  group('AI creation only prepares planning', () {
    test('persists a planning session and generates nothing', () async {
      final result = await pipeline.create(request(
        method: CreationMethod.aiReference,
        reference: ReferenceSource.text('世界观核心材料'),
        key: 'ai-1',
      ));

      expect(result.status, CreationSessionStatus.planning);
      expect(result.sessionId, isNotNull);
      expect(result.resourceId, isNull, reason: 'AI path writes no resource');

      final counts = await treeCounts();
      expect(counts['resources'], 0);
      expect(counts['parts'], 0);

      final session = await pipeline.findSession(result.sessionId!);
      expect(session!.status, CreationSessionStatus.planning);
      expect(session.awaitsPlanning, isTrue);
      expect(session.referenceSource.body, '世界观核心材料');

      final pending = await pipeline.pendingPlanningSessions();
      expect(pending.map((item) => item.sessionId), [result.sessionId]);
    });

    test('does not touch the legacy resource tables', () async {
      await pipeline.create(request(key: 'manual-1'));
      await pipeline.create(
        request(method: CreationMethod.aiReference, key: 'ai-2'),
      );

      expect(await legacyCounts(), {
        'worldview_presets': 0,
        'character_cards': 0,
        'npc_cards': 0,
      });
    });
  });

  group('ReferenceSource kinds', () {
    test('text, file and existing resource are recorded as sources', () async {
      final text = await pipeline.create(request(
        key: 'ref-text',
        reference: ReferenceSource.text('粘贴正文'),
      ));
      await pipeline.create(request(
        key: 'ref-file',
        reference: ReferenceSource.file('文件正文', fileName: 'lore.txt'),
      ));
      final existing = await pipeline.create(request(
        key: 'ref-existing',
        reference: ReferenceSource.existingResource(
          text.resourceId!.value,
          label: '已有世界观',
        ),
      ));

      final fileSession = await pipeline.findByIdempotencyKey('ref-file');
      expect(fileSession!.referenceSource.kind, ReferenceSourceKind.file);
      expect(fileSession.referenceSource.fileName, 'lore.txt');

      final existingTree = await treeRepository.readTree(existing.resourceId!);
      expect(
        existingTree!
            .resource.metadata[ResourceCreationPipeline.metadataReferenceKind],
        ReferenceSourceKind.existingResource.storageValue,
      );
      expect(existingTree.resource.metadata[('reference_resource_id')],
          text.resourceId!.value);
    });

    test('diagnostics never expose the reference body', () {
      final source = ReferenceSource.text('机密参考资料正文');
      expect(source.diagnosticLabel.contains('机密'), isFalse);
      expect(source.toString().contains('机密'), isFalse);

      final req = request(reference: source);
      expect(req.diagnosticSummary.contains('机密'), isFalse);
    });
  });

  group('idempotency and duplicate submit', () {
    test('the same request submitted three times creates one resource',
        () async {
      final first = await pipeline.create(request(key: 'dup'));
      final second = await pipeline.create(request(key: 'dup'));
      final third = await pipeline.create(request(key: 'dup'));

      expect(first.reusedExisting, isFalse);
      expect(second.reusedExisting, isTrue);
      expect(third.reusedExisting, isTrue);
      expect(second.resourceId, first.resourceId);
      expect((await treeCounts())['resources'], 1);

      final db = await DatabaseService.database;
      final rows = await db.query('resource_creation_sessions');
      expect(rows, hasLength(1));
    });

    test('a repeated AI submit returns the same planning session', () async {
      final first = await pipeline.create(
        request(method: CreationMethod.aiReference, key: 'ai-dup'),
      );
      final second = await pipeline.create(
        request(method: CreationMethod.aiReference, key: 'ai-dup'),
      );

      expect(second.sessionId, first.sessionId);
      expect(second.status, CreationSessionStatus.planning);
      expect((await pipeline.pendingPlanningSessions()), hasLength(1));
    });

    test('reusing a key for a different request is rejected', () async {
      await pipeline.create(request(key: 'shared'));

      await expectLater(
        pipeline.create(request(key: 'shared', name: '另一个世界')),
        throwsA(isA<ResourceCreationIdempotencyConflict>()),
      );
      await expectLater(
        pipeline.create(request(key: 'shared', type: ResourceType.npc)),
        throwsA(isA<ResourceCreationIdempotencyConflict>()),
      );
      expect((await treeCounts())['resources'], 1);
    });
  });

  group('cancel and recovery', () {
    test('cancelling a planning session is terminal', () async {
      final created = await pipeline.create(
        request(method: CreationMethod.aiReference, key: 'ai-cancel'),
      );
      final cancelled = await pipeline.cancel(sessionId: created.sessionId);
      expect(cancelled.status, CreationSessionStatus.cancelled);

      await expectLater(
        pipeline.create(
          request(method: CreationMethod.aiReference, key: 'ai-cancel'),
        ),
        throwsA(isA<ResourceCreationException>()),
      );
      expect((await treeCounts())['resources'], 0);
    });

    test('a session interrupted after the tree write is reconciled', () async {
      final db = await DatabaseService.database;
      const sessionId = 'cre_interrupted';
      const key = 'interrupted-key';
      const resourceId = ResourceId('res_cre_interrupted');

      // Simulate: tree written, session still in `validating`.
      await treeRepository.createResourceTree(const ResourceTreeDraft(
        id: resourceId,
        type: ResourceType.worldview,
        name: '中断的世界',
      ));
      await db.insert(
        ResourceCreationPipeline.table,
        {
          'session_id': sessionId,
          'idempotency_key': key,
          'resource_type': ResourceType.worldview.storageValue,
          'method': CreationMethod.manual.storageValue,
          'name': '中断的世界',
          'status': CreationSessionStatus.validating.storageValue,
          'reference_kind': ReferenceSourceKind.none.storageValue,
          'reference_label': '',
          'reference_file_name': '',
          'reference_resource_id': '',
          'reference_body': '',
          'reference_char_count': 0,
          'origin': 'test',
          'error_message': '',
          'created_at': '2026-09-16T00:00:00.000',
          'updated_at': '2026-09-16T00:00:00.000',
        },
      );

      final result = await pipeline.create(request(key: key, name: '中断的世界'));

      expect(result.reusedExisting, isTrue);
      expect(result.resourceId, resourceId);
      expect((await treeCounts())['resources'], 1);
      final reconciled = await pipeline.findSession(sessionId);
      expect(reconciled!.status, CreationSessionStatus.persisted);
    });
  });

  group('persistence failure', () {
    test('leaves no orphan resource, section or part', () async {
      // Two sections sharing one explicit id: the second insert fails inside the
      // tree transaction, so the whole resource must roll back.
      await expectLater(
        pipeline.create(request(
          key: 'boom',
          sections: const [
            ResourceTreeSectionDraft(
              id: SectionId('sec_dup'),
              title: 'A',
              parts: [ResourceTreePartDraft(title: 'A', content: '1')],
            ),
            ResourceTreeSectionDraft(
              id: SectionId('sec_dup'),
              title: 'B',
              parts: [ResourceTreePartDraft(title: 'B', content: '2')],
            ),
          ],
        )),
        throwsA(isA<ResourceCreationException>()),
      );

      final counts = await treeCounts();
      expect(counts['resources'], 0);
      expect(counts['sections'], 0);
      expect(counts['parts'], 0);

      // The failure is recorded, not silently swallowed.
      final session = await pipeline.findByIdempotencyKey('boom');
      expect(session!.status, CreationSessionStatus.failed);
      expect(session.errorMessage, isNotEmpty);
      expect(session.resourceId, isNull);
    });

    test('a failed manual request can be retried with the same key', () async {
      await expectLater(
        pipeline.create(request(
          key: 'retry',
          sections: const [
            ResourceTreeSectionDraft(id: SectionId('sec_dup'), title: 'A'),
            ResourceTreeSectionDraft(id: SectionId('sec_dup'), title: 'B'),
          ],
        )),
        throwsA(isA<ResourceCreationException>()),
      );

      final retried = await pipeline.create(request(key: 'retry'));
      expect(retried.status, CreationSessionStatus.persisted);
      expect((await treeCounts())['resources'], 1);
    });
  });

  group('statistics', () {
    test('counters are read-only and carry no body text', () async {
      await pipeline.create(request(key: 's1'));
      await pipeline.create(
        request(method: CreationMethod.aiReference, key: 's2'),
      );

      final stats = await pipeline.stats();
      expect(stats.total, 2);
      expect(stats.completed, 1);
      expect(stats.awaitingPlanning, 1);
      expect(stats.toString().contains('银月'), isFalse);
    });
  });
}
