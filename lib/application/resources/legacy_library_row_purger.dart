import 'package:sqflite/sqflite.dart';

import '../../domain/resources/resource_trash.dart';
import 'resource_trash_service.dart';

/// The one place allowed to physically remove a legacy library row.
///
/// Phase 9 stopped deleting legacy rows on the normal delete path, so this is
/// reached exclusively from the recycle bin's explicit permanent delete (and,
/// later, from Phase 12 when the legacy tables are dropped). Keeping it separate
/// from [ResourceLibraryTrashBridge] also avoids a construction cycle: the trash
/// service needs this port, and the bridge needs the trash service.
final class LegacyLibraryRowPurger implements ILegacyLibraryRowPort {
  LegacyLibraryRowPurger({required Future<Database> Function() getDb})
      : _getDb = getDb;

  final Future<Database> Function() _getDb;

  /// Legacy tables that hold resource content.
  ///
  /// Doubles as the allowlist for the interpolated table name below: a tampered
  /// `metadata_json` must not be able to point the statement at another table.
  static const Set<String> legacyResourceTables = <String>{
    'worldview_presets',
    'character_cards',
    'npc_cards',
  };

  /// True when [table] holds resource content managed by the recycle bin.
  static bool isResourceTable(String table) =>
      legacyResourceTables.contains(table);

  @override
  Future<void> purgeLegacyRowInTransaction(
    DatabaseExecutor txn, {
    required String sourceTable,
    required String sourceId,
  }) async {
    if (!isResourceTable(sourceTable)) {
      throw const ResourceTrashException('拒绝从非资源库表永久删除');
    }
    if (sourceId.isEmpty) {
      throw const ResourceTrashException('永久删除缺少目标 id');
    }
    await txn
        .delete(sourceTable, where: 'id = ?', whereArgs: <Object?>[sourceId]);
  }

  /// Database accessor, exposed so a caller can run the purge without owning a
  /// transaction of its own.
  Future<Database> database() => _getDb();
}
