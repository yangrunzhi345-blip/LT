import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/providers/adventure_provider.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/repositories/adventure_repository_impl.dart';
import 'package:lt_dialogue/services/repositories/library_repository_impl.dart';
import 'package:lt_dialogue/services/repositories/world_entry_repository.dart';
import 'package:lt_dialogue/services/repositories/world_entry_repository_impl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  late Directory tempDir;
  late Database db;
  late IWorldEntryRepository worldEntries;
  late AdventureProvider provider;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lt_r06_adventure_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
    db = await DatabaseService.database;
    await db.insert('adventures', {
      'id': 0,
      'title': 'Global world entries',
      'created_at': '2026-09-19T00:00:00.000',
    });
    await db.insert('adventures', {
      'id': 7,
      'title': 'R06 production load fixture',
      'created_at': '2026-09-19T00:00:00.000',
    });
    worldEntries = WorldEntryRepositoryImpl(getDb: () async => db);
    provider = AdventureProvider(
      adventureRepo: AdventureRepositoryImpl(getDb: () async => db),
      worldEntryRepo: worldEntries,
      libraryRepo: LibraryRepositoryImpl(getDb: () async => db),
    );
  });

  tearDown(() async {
    provider.dispose();
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  Future<void> insertEntry({
    required int id,
    required int adventureId,
    required String content,
    int insertPosition = 1,
  }) async {
    await db.insert('world_entries', {
      'id': id,
      'adventure_id': adventureId,
      'keys': '["key-$id"]',
      'content': content,
      'insertion_order': id,
      'insert_position': insertPosition,
      'enabled': 1,
    });
  }

  group('AdventureProvider world-entry loading', () {
    test('P1 should accept a genuinely empty world-entry collection', () async {
      await provider.loadAdventure(7);

      expect(provider.inGame, isTrue);
      expect(provider.worldEntries, isEmpty);
    });

    test('P2 should fail closed when every local row is corrupt', () async {
      await insertEntry(
        id: 1,
        adventureId: 7,
        content: 'corrupt local',
        insertPosition: 999,
      );

      await provider.loadAdventure(7);

      expect(provider.inGame, isFalse);
      expect(provider.worldEntries, isEmpty);
    });

    test('P3 should retain valid local siblings around a corrupt row',
        () async {
      await insertEntry(id: 1, adventureId: 7, content: 'first');
      await insertEntry(
        id: 2,
        adventureId: 7,
        content: 'corrupt',
        insertPosition: 999,
      );
      await insertEntry(id: 3, adventureId: 7, content: 'third');

      await provider.loadAdventure(7);

      expect(provider.inGame, isTrue);
      expect(provider.worldEntries.map((entry) => entry.content), [
        'first',
        'third',
      ]);
    });

    test('P4 should fail closed when every global row is corrupt', () async {
      await insertEntry(
        id: 1,
        adventureId: 0,
        content: 'corrupt global',
        insertPosition: 999,
      );

      await provider.loadAdventure(7);

      expect(provider.inGame, isFalse);
      expect(provider.worldEntries, isEmpty);
    });

    test('P5 should retain valid global siblings around a corrupt row',
        () async {
      await insertEntry(id: 1, adventureId: 0, content: 'first global');
      await insertEntry(
        id: 2,
        adventureId: 0,
        content: 'corrupt',
        insertPosition: 999,
      );
      await insertEntry(id: 3, adventureId: 0, content: 'third global');

      await provider.loadAdventure(7);

      expect(provider.inGame, isTrue);
      expect(provider.worldEntries.map((entry) => entry.content), [
        'first global',
        'third global',
      ]);
    });

    test('P6 should expose typed results through the repository interface',
        () async {
      await insertEntry(
        id: 1,
        adventureId: 7,
        content: 'corrupt local',
        insertPosition: 999,
      );

      final result = await worldEntries.loadWorldEntries(7);

      expect(result.sourceRowCount, 1);
      expect(result.isAllCorrupt, isTrue);
      expect(result.isGenuinelyEmpty, isFalse);
    });
  });
}
