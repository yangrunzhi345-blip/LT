import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/domain/resources/resource_trash.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/repositories/adventure_repository_impl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _BarrierAdventureRepository extends AdventureRepositoryImpl {
  _BarrierAdventureRepository(
      {required super.getDb, required super.trashService});

  int? blockedId;
  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<void> moveAdventureToTrash(int id) async {
    if (id == blockedId) {
      started.complete();
      await release.future;
    }
    await super.moveAdventureToTrash(id);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  group('Production adventure trash restore wiring', () {
    late Directory directory;
    late ProviderContainer container;
    late _BarrierAdventureRepository repository;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      directory = await Directory.systemTemp.createTemp('lt_recent_restore_');
      DatabaseService.customDbDir = directory.path;
      await DatabaseService.resetDatabase();
      container = ProviderContainer();
    });

    tearDown(() async {
      container.dispose();
      await DatabaseService.resetDatabase();
      await directory.delete(recursive: true);
    });

    test('should immediately republish a restored adventure in the sole list',
        () async {
      final repository = container.read(adventureRepoProvider);
      final id = await repository.createAdventure('可恢复的冒险', AdventureConfig());
      final chat = container.read(chatProvider);
      await chat.loadApiKey();
      await chat.loadAdventureList();
      expect(chat.adventureList.map((item) => item['id']), contains(id));

      await repository.moveAdventureToTrash(id);
      await chat.loadAdventureList();
      expect(chat.adventureList.map((item) => item['id']), isNot(contains(id)));
      final entries = await container.read(resourceTrashServiceProvider).list();
      final marker = entries.singleWhere(
        (entry) =>
            entry.linkedSourceTable == 'adventures' &&
            entry.linkedSourceId == '$id',
      );

      final summary = await container
          .read(resourceTrashRuntimeProvider)
          .restore(marker.trashId);
      expect(summary.placement, TrashRestorePlacement.restoredToAdventures);
      // No manual reload here: the production runtime must notify the existing
      // AdventureProvider, otherwise the sidebar stays stale after restore.
      expect(chat.adventureList.map((item) => item['id']), contains(id));
    });

    test('should keep the newly opened adventure when an old trash completes',
        () async {
      container.dispose();
      container = ProviderContainer(overrides: [
        adventureRepoProvider.overrideWith((ref) {
          repository = _BarrierAdventureRepository(
            getDb: () => DatabaseService.database,
            trashService: ref.read(resourceTrashServiceProvider),
          );
          return repository;
        }),
      ]);
      final repo = container.read(adventureRepoProvider);
      final first = await repo.createAdventure('旧冒险', AdventureConfig());
      final second = await repo.createAdventure('新冒险', AdventureConfig());
      final chat = container.read(chatProvider);
      await chat.loadApiKey();
      await chat.openAdventure(first);
      repository.blockedId = first;

      final deleting = chat.moveAdventureToTrash(first);
      await repository.started.future;
      await chat.openAdventure(second);
      expect(chat.currentAdventureId, second);
      expect(chat.isAdventureChatOpen, isTrue);

      repository.release.complete();
      await deleting;
      expect(chat.currentAdventureId, second);
      expect(chat.isAdventureChatOpen, isTrue);
      expect(chat.currentTitle, '新冒险');
      expect(
          chat.adventureList.map((item) => item['id']), isNot(contains(first)));
      expect(await repo.getAdventureById(first), isNull);
    });
  });
}
