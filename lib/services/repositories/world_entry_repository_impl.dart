import 'package:sqflite/sqflite.dart';
import '../../models/world_entry.dart';
import 'world_entry_repository.dart';

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
    final db = await _getDb();
    final rows = await db.query('world_entries',
        where: 'adventure_id = ?',
        whereArgs: [adventureId],
        orderBy: 'insertion_order ASC');
    return rows.map((r) => WorldEntry.fromDbMap(r)).toList();
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
    return rows.map((r) => WorldEntry.fromDbMap(r)).toList();
  }
}
