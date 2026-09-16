import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/llm/llm_gateway.dart';
import 'package:lt_dialogue/application/resource_library/import_models.dart';
import 'package:lt_dialogue/application/resource_library/import_use_cases.dart';
import 'package:lt_dialogue/application/resources/legacy_creation_bridge.dart';
import 'package:lt_dialogue/application/resources/resource_creation_contracts.dart';
import 'package:lt_dialogue/application/resources/resource_creation_pipeline.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/repositories/library_repository_impl.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository_impl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// These acceptance assertions describe the required behavior, not the current
// implementation. Failures are retained as reproducible review findings.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  late Directory tempDir;
  late Database db;
  late ResourceCreationPipeline pipeline;
  late ResourceTreeRepositoryImpl tree;
  late LibraryRepositoryImpl library;
  late LegacyCreationBridge bridge;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lt_phase3_acceptance_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
    db = await DatabaseService.database;
    tree = ResourceTreeRepositoryImpl(getDb: () async => db);
    library = LibraryRepositoryImpl(getDb: () async => db);
    pipeline = ResourceCreationPipeline(
      getDb: () async => db,
      hasAiCredentials: () => true,
      treeRepository: tree,
    );
    bridge = LegacyCreationBridge(pipeline);
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    DatabaseService.customDbDir = null;
    await tempDir.delete(recursive: true);
  });

  Future<ResourceCreationResult> saveCard(String content) => bridge.saveCard(
        type: ResourceType.character,
        id: 'review-card',
        name: 'Review card',
        jsonData: '{"name":"Review card","description":"$content"}',
        mode: 'adventure',
        origin: 'review',
      );

  group('Phase 3 independent acceptance', () {
    test('should reuse one identity when an import draft is saved again',
        () async {
      final useCase = ImportConversationCharacterUseCase(
        gateway: _UnusedGateway(),
        repository: library,
        bridge: bridge,
      );
      const draft = ConversationCharacterDraft({
        'name': 'Repeated import',
        'description': 'The same logical draft',
      });
      await useCase.save(draft);
      await useCase.save(draft);
      expect(await db.query('resources'), hasLength(1));
      expect(await db.query(ResourceCreationPipeline.table), hasLength(1));
    });

    test('should report a failed update instead of reconciling unrelated data',
        () async {
      await saveCard('original');
      final future = pipeline.create(const ResourceCreationRequest(
        resourceType: ResourceType.character,
        method: CreationMethod.manual,
        name: 'Review card',
        resourceId: 'review-card',
        idempotencyKey: 'failing-update',
        initialSections: [
          ResourceTreeSectionDraft(id: SectionId('duplicate'), title: 'A'),
          ResourceTreeSectionDraft(id: SectionId('duplicate'), title: 'B'),
        ],
      ));
      await expectLater(future, throwsA(isA<ResourceCreationException>()));
      expect((await pipeline.findByIdempotencyKey('failing-update'))!.status,
          CreationSessionStatus.failed);
    });

    test('should prevent a cancelled in-flight request from writing a tree',
        () async {
      final reachedWrite = Completer<void>();
      final releaseWrite = Completer<void>();
      final gatedTree = ResourceTreeRepositoryImpl(getDb: () async {
        if (!reachedWrite.isCompleted) reachedWrite.complete();
        await releaseWrite.future;
        return db;
      });
      final gatedPipeline = ResourceCreationPipeline(
        getDb: () async => db,
        hasAiCredentials: () => true,
        treeRepository: gatedTree,
      );
      Object? createError;
      final pending = gatedPipeline
          .create(const ResourceCreationRequest(
            resourceType: ResourceType.character,
            method: CreationMethod.manual,
            name: 'Cancelled request',
            idempotencyKey: 'cancel-during-write',
          ))
          .then<void>((_) {}, onError: (Object error) => createError = error);
      await reachedWrite.future;
      try {
        final cancelled =
            await gatedPipeline.cancel(idempotencyKey: 'cancel-during-write');
        expect(cancelled.status, CreationSessionStatus.cancelled);
      } finally {
        releaseWrite.complete();
        await pending;
      }
      expect(await db.query('resources'), isEmpty);
      expect(
        (await gatedPipeline.findByIdempotencyKey('cancel-during-write'))!
            .status,
        CreationSessionStatus.cancelled,
      );
      expect(createError, isA<ResourceCreationException>());
    });

    test('should persist a deliberate edit back to earlier content', () async {
      await saveCard('A');
      await saveCard('B');
      await saveCard('A');
      final snapshot = await tree.readTree(const ResourceId('review-card'));
      expect(snapshot!.parts.map((part) => part.content), contains('A'));
      expect(snapshot.parts.map((part) => part.content), isNot(contains('B')));
    });

    test('should expose a saved edit of a pre-existing legacy card', () async {
      await library.saveCharacterCard(
        id: 'review-card',
        name: 'Old name',
        jsonData: '{"name":"Old name","description":"old"}',
        source: 'fixture',
        now: DateTime.now().toIso8601String(),
      );
      await saveCard('new');
      final rows = await library.getCharacterCards();
      expect(rows.single['name'], 'Review card');
      expect(rows.single['json_data'], contains('new'));
    });

    test('should delete a card created through the pipeline from its library',
        () async {
      await saveCard('new');
      await library.deleteCharacterCard('review-card');
      expect(await library.getCharacterCards(), isEmpty);
    });

    test('should roll back resource insertion if its first section fails',
        () async {
      await db.execute('''
        CREATE TRIGGER reject_section BEFORE INSERT ON resource_sections
        BEGIN SELECT RAISE(ABORT, 'review section failure'); END
      ''');
      await expectLater(
        pipeline.create(const ResourceCreationRequest(
          resourceType: ResourceType.worldview,
          method: CreationMethod.manual,
          name: 'Rollback',
          idempotencyKey: 'rollback',
          createInitialEmptySection: true,
        )),
        throwsA(isA<ResourceCreationException>()),
      );
      expect(await db.query('resources'), isEmpty);
      expect(await db.query('resource_sections'), isEmpty);
      expect((await pipeline.findByIdempotencyKey('rollback'))!.status,
          CreationSessionStatus.failed);
    });
  });
}

class _UnusedGateway implements LlmGateway {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('This save must not invoke an LLM');
}
