import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../../models/world_entry.dart';
import 'world_entry_repository.dart';

enum PersistedRowErrorCategory { identity, optionalField, decode }

class PersistedRowDiagnostic {
  final String table;
  final Object? rowId;
  final PersistedRowErrorCategory category;

  const PersistedRowDiagnostic({
    required this.table,
    required this.rowId,
    required this.category,
  });
}

class WorldEntryLoadResult {
  final List<WorldEntry> entries;
  final List<PersistedRowDiagnostic> diagnostics;
  final int sourceRowCount;

  const WorldEntryLoadResult({
    required this.entries,
    required this.diagnostics,
    required this.sourceRowCount,
  });

  bool get isGenuinelyEmpty => sourceRowCount == 0;
  bool get hasCorruptRows => diagnostics.isNotEmpty;
}

WorldEntryLoadResult decodeWorldEntryRows(
  List<Map<String, Object?>> rows, {
  void Function(PersistedRowDiagnostic diagnostic)? onDiagnostic,
}) {
  final entries = <WorldEntry>[];
  final diagnostics = <PersistedRowDiagnostic>[];
  for (final row in rows) {
    final rowId = row['id'];
    try {
      final entry = WorldEntry.fromJson(
        row,
        requirePersistedIdentity: true,
        onOptionalFallback: (_) {
          diagnostics.add(PersistedRowDiagnostic(
            table: 'world_entries',
            rowId: rowId,
            category: PersistedRowErrorCategory.optionalField,
          ));
        },
      );
      entries.add(entry);
    } on FormatException catch (error) {
      diagnostics.add(PersistedRowDiagnostic(
        table: 'world_entries',
        rowId: rowId,
        category: error.message == 'invalid persisted identity'
            ? PersistedRowErrorCategory.identity
            : PersistedRowErrorCategory.decode,
      ));
    } on TypeError {
      diagnostics.add(PersistedRowDiagnostic(
        table: 'world_entries',
        rowId: rowId,
        category: PersistedRowErrorCategory.decode,
      ));
    } on RangeError {
      diagnostics.add(PersistedRowDiagnostic(
        table: 'world_entries',
        rowId: rowId,
        category: PersistedRowErrorCategory.decode,
      ));
    }
  }
  for (final diagnostic in diagnostics) {
    onDiagnostic?.call(diagnostic);
  }
  return WorldEntryLoadResult(
    entries: List.unmodifiable(entries),
    diagnostics: List.unmodifiable(diagnostics),
    sourceRowCount: rows.length,
  );
}

class WorldEntryRepositoryImpl implements IWorldEntryRepository {
  final Future<Database> Function() _getDb;

  WorldEntryRepositoryImpl({required Future<Database> Function() getDb})
      : _getDb = getDb;

  @override
  Future<int> insertWorldEntry(WorldEntry entry) async {
    final db = await _getDb();
    final id = await db.insert('world_entries', entry.toDbMap());
    return id;
  }

  @override
  Future<List<WorldEntry>> getWorldEntries(int adventureId) async {
    return List<WorldEntry>.of(
      (await loadWorldEntries(adventureId)).entries,
    );
  }

  Future<WorldEntryLoadResult> loadWorldEntries(int adventureId) async {
    final db = await _getDb();
    final rows = await db.query('world_entries',
        where: 'adventure_id = ?',
        whereArgs: [adventureId],
        orderBy: 'insertion_order ASC');
    return _decodeRows(rows);
  }

  @override
  Future<void> updateWorldEntry(WorldEntry entry) async {
    final db = await _getDb();
    await db.update('world_entries', entry.toDbMap(),
        where: 'id = ?', whereArgs: [entry.id]);
  }

  @override
  Future<void> deleteWorldEntry(int id) async {
    final db = await _getDb();
    await db.delete('world_entries', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> deleteWorldEntriesByAdventure(int adventureId) async {
    final db = await _getDb();
    await db.delete('world_entries',
        where: 'adventure_id = ?', whereArgs: [adventureId]);
  }

  @override
  Future<List<WorldEntry>> getGlobalWorldEntries() async {
    final db = await _getDb();
    final rows = await db.query('world_entries',
        where: 'adventure_id = 0', orderBy: 'insertion_order ASC');
    return List<WorldEntry>.of(_decodeRows(rows).entries);
  }

  WorldEntryLoadResult _decodeRows(List<Map<String, Object?>> rows) {
    return decodeWorldEntryRows(rows, onDiagnostic: (diagnostic) {
      debugPrint(
        '[PersistenceDecode] table=${diagnostic.table} '
        'row=${diagnostic.rowId} category=${diagnostic.category.name}',
      );
    });
  }
}
