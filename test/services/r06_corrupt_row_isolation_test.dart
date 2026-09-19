import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/models/world_entry.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/repositories/world_entry_repository_impl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  late Directory tempDir;
  late Database db;
  late WorldEntryRepositoryImpl repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lt_r06_rows_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
    db = await DatabaseService.database;
    await db.insert('adventures', {
      'id': 7,
      'title': 'R06 corrupt-row fixture',
      'created_at': '2026-09-19T00:00:00.000',
    });
    repository = WorldEntryRepositoryImpl(getDb: () async => db);
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  Future<void> insertRow({
    required Object id,
    Object adventureId = 7,
    Object keys = '[]',
    Object content = '',
    Object insertionOrder = 0,
    Object insertPosition = 1,
  }) async {
    await db.rawInsert(
      'INSERT INTO world_entries '
      '(id, adventure_id, keys, content, insertion_order, insert_position, '
      'enabled) VALUES (?, ?, ?, ?, ?, ?, 1)',
      [id, adventureId, keys, content, insertionOrder, insertPosition],
    );
  }

  group('WorldEntryRepository corrupt-row isolation', () {
    test('B1 keeps valid rows around a corrupt row', () async {
      await insertRow(id: 1, keys: '["first"]');
      await insertRow(id: 2, insertPosition: 999);
      await insertRow(id: 3, keys: '["third"]');

      final result = await repository.loadWorldEntries(7);

      expect(result.entries.map((entry) => entry.id), [1, 3]);
      expect(result.diagnostics, hasLength(1));
    });

    test('B2 reports corrupt JSON without logging its payload', () async {
      await insertRow(id: 4, keys: '{sensitive-payload');

      final result = await repository.loadWorldEntries(7);

      expect(
        result.diagnostics.single.category,
        PersistedRowErrorCategory.optionalField,
      );
      expect(result.diagnostics.single.table, 'world_entries');
      expect(result.diagnostics.single.rowId, 4);
      expect(
          result.diagnostics.single.toString(), isNot(contains('sensitive')));
    });

    test('B3 rejects a row with corrupt identity', () async {
      final result = decodeWorldEntryRows([
        <String, Object?>{
          'id': 'not-an-integer',
          'adventure_id': 7,
          'keys': '[]',
          'content': '',
        },
      ]);
      expect(result.entries, isEmpty);
      expect(
        result.diagnostics.single.category,
        PersistedRowErrorCategory.identity,
      );
    });

    test('B4 applies the documented fallback for malformed optional fields',
        () async {
      await insertRow(id: 6, insertionOrder: 'invalid-order');

      final result = await repository.loadWorldEntries(7);

      expect(result.entries.single.insertionOrder, 0);
      expect(
        result.diagnostics.single.category,
        PersistedRowErrorCategory.optionalField,
      );
    });

    test('B5 distinguishes all corrupt rows from a genuinely empty query',
        () async {
      await insertRow(id: 7);
      await db.update(
        'world_entries',
        {'insert_position': 999},
        where: 'id = ?',
        whereArgs: [7],
      );
      final corrupt = await repository.loadWorldEntries(7);
      final empty = await repository.loadWorldEntries(999);

      expect(corrupt.isGenuinelyEmpty, isFalse);
      expect(corrupt.hasCorruptRows, isTrue);
      expect(corrupt.entries, isEmpty);
      expect(empty.isGenuinelyEmpty, isTrue);
      expect(empty.hasCorruptRows, isFalse);
    });

    test('B6 legacy repository list APIs remain mutable', () async {
      await insertRow(id: 8);

      final adventureEntries = await repository.getWorldEntries(7);
      final globalEntries = await repository.getGlobalWorldEntries();

      expect(
        () => adventureEntries.add(WorldEntry(adventureId: 7)),
        returnsNormally,
      );
      expect(
        () => globalEntries.add(WorldEntry()),
        returnsNormally,
      );
    });
  });
}
