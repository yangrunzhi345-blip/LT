import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../domain/setting_cards/setting_card.dart';
import '../../domain/setting_cards/setting_card_repository.dart';

/// SQLite-backed store for lightweight setting cards.
///
/// One row per card; the body is a single TEXT column. No tree tables, no
/// revision pointer and no trash bookkeeping participate here.
final class SettingCardRepositoryImpl implements SettingCardRepository {
  SettingCardRepositoryImpl({required Future<Database> Function() getDb})
      : _getDb = getDb;

  static const String table = 'setting_cards';

  /// Creates the card table. Idempotent so it can run both on fresh install and
  /// from a schema migration step.
  static Future<void> createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS setting_cards (
        id TEXT PRIMARY KEY,
        kind TEXT NOT NULL,
        name TEXT NOT NULL DEFAULT '',
        summary TEXT NOT NULL DEFAULT '',
        content TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'draft',
        origin TEXT NOT NULL DEFAULT 'native',
        mode TEXT NOT NULL DEFAULT '',
        origin_worldview_id TEXT NOT NULL DEFAULT '',
        metadata_json TEXT NOT NULL DEFAULT '{}',
        legacy_id TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT
      )
    ''');
    await db
        .execute('CREATE INDEX IF NOT EXISTS idx_setting_cards_kind_updated '
            'ON setting_cards(kind, updated_at DESC)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_setting_cards_legacy '
        'ON setting_cards(legacy_id)');
    // Single-row marker for the one-time tree merge. Lives here so a schema
    // creation and a schema upgrade always produce the same shape.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS setting_card_migration_state (
        id TEXT PRIMARY KEY,
        completed_at TEXT NOT NULL,
        version INTEGER NOT NULL
      )
    ''');
  }

  final Future<Database> Function() _getDb;

  @override
  Future<List<SettingCard>> list({
    SettingCardKind? kind,
    bool includeDeleted = false,
  }) async {
    final db = await _getDb();
    final where = <String>[
      if (kind != null) 'kind = ?',
      if (!includeDeleted) 'deleted_at IS NULL',
    ];
    final rows = await db.query(
      table,
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: <Object?>[if (kind != null) kind.storageValue],
      orderBy: 'updated_at DESC, id ASC',
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  @override
  Future<SettingCard?> findById(String id) async {
    if (id.isEmpty) return null;
    final db = await _getDb();
    final rows = await db.query(
      table,
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  @override
  Future<SettingCard?> findLegacyId(
    String legacyId, {
    SettingCardKind? kind,
  }) async {
    if (legacyId.isEmpty) return null;
    final db = await _getDb();
    final rows = await db.query(
      table,
      where: kind == null ? 'legacy_id = ?' : 'legacy_id = ? AND kind = ?',
      whereArgs: <Object?>[
        legacyId,
        if (kind != null) kind.storageValue,
      ],
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  @override
  Future<bool> exists(String id) async {
    if (id.isEmpty) return false;
    final db = await _getDb();
    final rows = await db.query(
      table,
      columns: const <String>['id'],
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  @override
  Future<bool> insertIfAbsent(SettingCard card) async {
    final db = await _getDb();
    final rowId = await db.insert(
      table,
      _toRow(card),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    // SQLite reports 0 when INSERT OR IGNORE skipped the row.
    return rowId != 0;
  }

  @override
  Future<void> save(SettingCard card) async {
    final db = await _getDb();
    await db.insert(
      table,
      _toRow(card),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> softDelete(String id, {required String deletedAt}) async {
    final db = await _getDb();
    await db.update(
      table,
      <String, Object?>{'deleted_at': deletedAt, 'updated_at': deletedAt},
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  static Map<String, Object?> _toRow(SettingCard card) => <String, Object?>{
        'id': card.id,
        'kind': card.kind.storageValue,
        'name': card.name,
        'summary': card.summary,
        'content': card.content,
        'status': card.status.storageValue,
        'origin': card.origin.storageValue,
        'mode': card.mode,
        'origin_worldview_id': card.originWorldviewId,
        'metadata_json': jsonEncode(card.metadata),
        'legacy_id': card.legacyId,
        'created_at': card.createdAt,
        'updated_at': card.updatedAt,
        'deleted_at': card.deletedAt,
      };

  static SettingCard _fromRow(Map<String, Object?> row) {
    return SettingCard(
      id: row['id']?.toString() ?? '',
      kind: SettingCardKind.fromStorageValue(row['kind']?.toString()),
      name: row['name']?.toString() ?? '',
      summary: row['summary']?.toString() ?? '',
      content: row['content']?.toString() ?? '',
      status: SettingCardStatus.fromStorageValue(row['status']?.toString()),
      origin: SettingCardOrigin.fromStorageValue(row['origin']?.toString()),
      mode: row['mode']?.toString() ?? '',
      originWorldviewId: row['origin_worldview_id']?.toString() ?? '',
      metadata: _decodeMetadata(row['metadata_json']),
      legacyId: row['legacy_id']?.toString(),
      createdAt: row['created_at']?.toString() ?? '',
      updatedAt: row['updated_at']?.toString() ?? '',
      deletedAt: row['deleted_at']?.toString(),
    );
  }

  /// Only our own writer produces this column. A damaged value degrades to an
  /// empty map so one corrupt row cannot hide the whole library; the body text
  /// (the part the user cares about) is still returned.
  static Map<String, Object?> _decodeMetadata(Object? raw) {
    if (raw is! String || raw.trim().isEmpty) return const <String, Object?>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return <String, Object?>{
          for (final entry in decoded.entries)
            entry.key.toString(): entry.value,
        };
      }
    } on FormatException {
      return const <String, Object?>{};
    }
    return const <String, Object?>{};
  }
}
