import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../domain/resources/resource_contracts.dart';
import '../../domain/setting_cards/setting_card.dart';
import '../../domain/setting_cards/setting_card_repository.dart';
import '../../services/repositories/resource_tree_repository.dart';
import '../../services/repositories/setting_card_repository_impl.dart';
import '../resources/legacy_resource_mapper.dart';

/// Counters for the one-time compatibility migration.
///
/// Body text is never carried here, so the stats are safe to log.
final class SettingCardMigrationStats {
  const SettingCardMigrationStats({
    this.created = 0,
    this.skipped = 0,
    this.failed = 0,
  });

  final int created;
  final int skipped;
  final int failed;

  @override
  String toString() =>
      'SettingCardMigration(created: $created, skipped: $skipped, '
      'failed: $failed)';
}

typedef _RenderPart = ({String title, String content});
typedef _RenderSection = ({
  String title,
  String summary,
  List<_RenderPart> parts,
});

/// Merges the retired tree (and any un-migrated legacy row) into one card each.
///
/// Guarantees:
/// - Existing data is read only: the legacy tables and the resource tree are
///   never written or deleted here.
/// - Cards are inserted only when absent, so re-running never overwrites a card
///   the user has edited with the lightweight editor.
/// - A row that cannot be mapped still produces a card holding its raw payload,
///   so a compatibility migration cannot silently drop a user's setting.
/// - A completed run is recorded, so later launches pay one small query.
final class SettingCardMigrationService {
  SettingCardMigrationService({
    required Future<Database> Function() getDb,
    SettingCardRepository? cards,
    LegacyResourceMapper mapper = const LegacyResourceMapper(),
    String Function()? clock,
  })  : _getDb = getDb,
        _cards = cards,
        _mapper = mapper,
        _clock = clock ?? _defaultClock;

  /// Bump only when the merge semantics change; a bump re-evaluates every row.
  static const int migrationVersion = 1;

  /// Stores the single completion marker.
  static const String stateTable = 'setting_card_migration_state';

  static const String _stateId = 'legacy_trees';

  static String _defaultClock() => DateTime.now().toIso8601String();

  final Future<Database> Function() _getDb;
  final SettingCardRepository? _cards;
  final LegacyResourceMapper _mapper;
  final String Function() _clock;

  late final SettingCardRepository _store =
      _cards ?? SettingCardRepositoryImpl(getDb: _getDb);

  /// Whether a completed run for the current [migrationVersion] exists.
  Future<bool> isComplete() async {
    final db = await _getDb();
    try {
      final rows = await db.query(
        stateTable,
        columns: const <String>['version'],
        where: 'id = ?',
        whereArgs: const <Object?>[_stateId],
        limit: 1,
      );
      if (rows.isEmpty) return false;
      final version = rows.first['version'];
      return version is int && version >= migrationVersion;
    } catch (_) {
      // A database without the marker table has never run the migration.
      return false;
    }
  }

  /// Runs the merge unless [force] is set and a completed run exists.
  Future<SettingCardMigrationStats> run({bool force = false}) async {
    if (!force && await isComplete()) {
      return const SettingCardMigrationStats();
    }

    final db = await _getDb();
    var created = 0;
    var skipped = 0;
    var failed = 0;

    for (final source in const <({String table, SettingCardKind kind})>[
      (
        table: LegacySourceTables.worldviewPresets,
        kind: SettingCardKind.worldview
      ),
      (
        table: LegacySourceTables.characterCards,
        kind: SettingCardKind.character
      ),
      (table: LegacySourceTables.npcCards, kind: SettingCardKind.npc),
    ]) {
      final List<Map<String, Object?>> rows;
      try {
        rows = await db.query(source.table);
      } catch (_) {
        // A database without this legacy table simply has nothing to merge.
        continue;
      }
      for (final row in rows) {
        final legacyId = row['id']?.toString() ?? '';
        if (legacyId.isEmpty) {
          failed++;
          continue;
        }
        try {
          final card = await _cardFromLegacyRow(
            sourceTable: source.table,
            kind: source.kind,
            legacyId: legacyId,
            row: row,
          );
          if (await _store.insertIfAbsent(card)) {
            created++;
          } else {
            skipped++;
          }
        } catch (_) {
          failed++;
        }
      }
    }

    // Resources that only ever existed in the tree (created through the old
    // Studio) have no legacy row, so they are merged on their own.
    List<Map<String, Object?>> resourceRows;
    try {
      resourceRows = await db.query(
        'resources',
        where: "type IN ('worldview', 'character', 'npc') "
            "AND id NOT LIKE 'res_legacy_%' AND deleted_at IS NULL",
      );
    } catch (_) {
      resourceRows = const <Map<String, Object?>>[];
    }
    for (final row in resourceRows) {
      final id = row['id']?.toString() ?? '';
      if (id.isEmpty) {
        failed++;
        continue;
      }
      try {
        final card = await _cardFromTreeRow(row);
        if (card == null) {
          failed++;
          continue;
        }
        if (await _store.insertIfAbsent(card)) {
          created++;
        } else {
          skipped++;
        }
      } catch (_) {
        failed++;
      }
    }

    await _markComplete(db);
    return SettingCardMigrationStats(
      created: created,
      skipped: skipped,
      failed: failed,
    );
  }

  Future<SettingCard> _cardFromLegacyRow({
    required String sourceTable,
    required SettingCardKind kind,
    required String legacyId,
    required Map<String, Object?> row,
  }) async {
    final resourceId =
        LegacyResourceMapper.resourceIdFor(sourceTable, legacyId);
    final db = await _getDb();
    final treeRow = await _readResourceRow(db, resourceId.value);

    if (treeRow != null) {
      return _buildCard(
        id: resourceId.value,
        kind: kind,
        name: treeRow['name']?.toString() ?? '',
        summary: treeRow['summary']?.toString() ?? '',
        content: _render(await _readSections(db, resourceId.value)),
        status: _nodeStatusOf(treeRow['status']),
        origin: SettingCardOrigin.legacyTree,
        metadata: _decodeMetadata(treeRow['metadata_json']),
        legacyId: legacyId,
        fallbackName: row['name']?.toString() ?? '',
        fallbackSummary: row['description']?.toString() ?? '',
        row: row,
      );
    }

    try {
      final draft = _mapLegacy(sourceTable: sourceTable, row: row);
      return _buildCard(
        id: resourceId.value,
        kind: kind,
        name: draft.name,
        summary: draft.summary,
        content: _render(_sectionsOfDraft(draft)),
        status: draft.status,
        origin: SettingCardOrigin.legacyRow,
        metadata: draft.metadata,
        legacyId: legacyId,
        fallbackName: row['name']?.toString() ?? '',
        fallbackSummary: row['description']?.toString() ?? '',
        row: row,
      );
    } on Object {
      // The row could not be mapped into the old tree. Preserve it verbatim
      // instead of dropping the user's setting.
      return _buildCard(
        id: resourceId.value,
        kind: kind,
        name: row['name']?.toString() ?? legacyId,
        summary: row['description']?.toString() ?? '',
        content: _rawLegacyContent(row),
        status: NodeStatus.draft,
        origin: SettingCardOrigin.legacyRow,
        metadata: const <String, Object?>{},
        legacyId: legacyId,
        fallbackName: legacyId,
        fallbackSummary: '',
        row: row,
      );
    }
  }

  Future<SettingCard?> _cardFromTreeRow(Map<String, Object?> row) async {
    final id = row['id']?.toString() ?? '';
    if (id.isEmpty) return null;
    final db = await _getDb();
    return _buildCard(
      id: id,
      kind: SettingCardKind.fromStorageValue(row['type']?.toString()),
      name: row['name']?.toString() ?? '',
      summary: row['summary']?.toString() ?? '',
      content: _render(await _readSections(db, id)),
      status: _nodeStatusOf(row['status']),
      origin: SettingCardOrigin.legacyTree,
      metadata: _decodeMetadata(row['metadata_json']),
      legacyId: null,
      fallbackName: row['name']?.toString() ?? '',
      fallbackSummary: row['summary']?.toString() ?? '',
      row: row,
    );
  }

  /// Reads one live resource row directly, or null when the id is not a tree
  /// resource. The retired tree repository is intentionally not involved.
  static Future<Map<String, Object?>?> _readResourceRow(
    Database db,
    String id,
  ) async {
    try {
      final rows = await db.query(
        'resources',
        where: 'id = ? AND deleted_at IS NULL',
        whereArgs: <Object?>[id],
        limit: 1,
      );
      return rows.isEmpty ? null : rows.first;
    } catch (_) {
      // A database without the tree tables has no resource to merge.
      return null;
    }
  }

  /// Reads sections then parts for [resourceId] in stable sort order and
  /// flattens them into the renderer's section shape.
  static Future<List<_RenderSection>> _readSections(
    Database db,
    String resourceId,
  ) async {
    final List<Map<String, Object?>> sectionRows;
    try {
      sectionRows = await db.query(
        'resource_sections',
        where: 'resource_id = ? AND deleted_at IS NULL',
        whereArgs: <Object?>[resourceId],
        orderBy: 'sort_order ASC, id ASC',
      );
    } catch (_) {
      return const <_RenderSection>[];
    }
    final sections = <_RenderSection>[];
    for (final sectionRow in sectionRows) {
      final sectionId = sectionRow['id']?.toString() ?? '';
      List<Map<String, Object?>> partRows;
      try {
        partRows = await db.query(
          'resource_parts',
          where: 'section_id = ? AND deleted_at IS NULL',
          whereArgs: <Object?>[sectionId],
          orderBy: 'sort_order ASC, id ASC',
        );
      } catch (_) {
        partRows = const <Map<String, Object?>>[];
      }
      sections.add((
        title: sectionRow['title']?.toString() ?? '',
        summary: sectionRow['summary']?.toString() ?? '',
        parts: <_RenderPart>[
          for (final partRow in partRows)
            (
              title: partRow['title']?.toString() ?? '',
              content: partRow['content']?.toString() ?? '',
            ),
        ],
      ));
    }
    return sections;
  }

  static NodeStatus _nodeStatusOf(Object? raw) {
    final value = raw?.toString();
    for (final status in NodeStatus.values) {
      if (status.storageValue == value) return status;
    }
    return NodeStatus.draft;
  }

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

  SettingCard _buildCard({
    required String id,
    required SettingCardKind kind,
    required String name,
    required String summary,
    required String content,
    required NodeStatus status,
    required SettingCardOrigin origin,
    required Map<String, Object?> metadata,
    required String? legacyId,
    required String fallbackName,
    required String fallbackSummary,
    required Map<String, Object?> row,
  }) {
    final kept = _smallMetadata(metadata);
    final mode = (row['mode']?.toString().trim().isNotEmpty ?? false)
        ? row['mode']!.toString()
        : kept['mode']?.toString() ?? '';
    final originWorldviewId =
        row['matching_worldview_id']?.toString().trim().isNotEmpty == true
            ? row['matching_worldview_id']!.toString()
            : kept['matching_worldview_id']?.toString() ?? '';
    final createdAt = row['created_at']?.toString() ?? '';
    final updatedAt = row['updated_at']?.toString() ?? '';
    final now = _clock();
    return SettingCard(
      id: id,
      kind: kind,
      name: name.trim().isEmpty ? fallbackName.trim() : name,
      summary: summary.trim().isEmpty ? fallbackSummary.trim() : summary,
      content: content,
      status: _statusOf(status),
      origin: origin,
      mode: mode,
      originWorldviewId: originWorldviewId,
      metadata: kept,
      legacyId: legacyId,
      createdAt: createdAt.isEmpty ? now : createdAt,
      updatedAt: updatedAt.isEmpty ? now : updatedAt,
    );
  }

  ResourceTreeDraft _mapLegacy({
    required String sourceTable,
    required Map<String, Object?> row,
  }) {
    if (sourceTable == LegacySourceTables.worldviewPresets) {
      return _mapper.mapWorldview(row);
    }
    if (sourceTable == LegacySourceTables.npcCards) {
      return _mapper.mapNpc(row);
    }
    return _mapper.mapCharacter(row);
  }

  Future<void> _markComplete(Database db) async {
    try {
      await db.insert(
        stateTable,
        <String, Object?>{
          'id': _stateId,
          'completed_at': _clock(),
          'version': migrationVersion,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {
      // The marker is an optimisation. Without it the next launch retries the
      // merge, which stays idempotent thanks to insertIfAbsent.
    }
  }

  static SettingCardStatus _statusOf(NodeStatus status) => switch (status) {
        NodeStatus.draft => SettingCardStatus.draft,
        NodeStatus.confirmed => SettingCardStatus.confirmed,
        NodeStatus.archived => SettingCardStatus.archived,
      };

  /// Runtime metadata that actually helps the editor or Adventure snapshot.
  /// Long payloads (entries, node references, custom attributes) are already
  /// rendered into the body and must not be duplicated here.
  static const Set<String> _keptMetadataKeys = <String>{
    'mode',
    'source',
    'authoring_method',
    'ai_generation_depth',
    'character_version',
    'creator',
    'tags',
    'matching_worldview_id',
    'origin_worldview_id',
    'favorite',
    'is_favorite',
  };

  static Map<String, Object?> _smallMetadata(Map<String, Object?> source) {
    final kept = <String, Object?>{};
    for (final entry in source.entries) {
      if (!_keptMetadataKeys.contains(entry.key)) continue;
      final value = entry.value;
      if (value == null) continue;
      if (value is String || value is num || value is bool) {
        kept[entry.key] = value;
      } else if (value is List || value is Map) {
        kept[entry.key] = value;
      }
    }
    return kept;
  }

  static List<_RenderSection> _sectionsOfDraft(ResourceTreeDraft draft) =>
      <_RenderSection>[
        for (final section in draft.sections)
          (
            title: section.title,
            summary: section.summary,
            parts: <_RenderPart>[
              for (final part in section.parts)
                (title: part.title, content: part.content),
            ],
          ),
      ];

  /// Renders sections/parts into one markdown document.
  ///
  /// A part whose title equals its section title is not repeated as a heading.
  static String _render(List<_RenderSection> sections) {
    final buffer = StringBuffer();
    for (final section in sections) {
      final title = section.title.trim();
      final summary = section.summary.trim();
      final parts = section.parts.where((part) =>
          part.title.trim().isNotEmpty || part.content.trim().isNotEmpty);
      if (title.isEmpty && summary.isEmpty && parts.isEmpty) continue;
      if (title.isNotEmpty) _block(buffer, '## $title');
      if (summary.isNotEmpty) _block(buffer, summary);
      for (final part in parts) {
        final partTitle = part.title.trim();
        final content = part.content.trim();
        if (partTitle.isNotEmpty && partTitle != title) {
          _block(buffer, '### $partTitle');
        }
        if (content.isNotEmpty) _block(buffer, content);
      }
    }
    return buffer.toString().trim();
  }

  static void _block(StringBuffer buffer, String text) {
    if (buffer.isNotEmpty) buffer.writeln();
    buffer.writeln(text);
    buffer.writeln();
  }

  /// Lossless-enough fallback for a row the old mapper rejects: keep the prose
  /// column and the raw JSON payload as a fenced block instead of discarding it.
  static String _rawLegacyContent(Map<String, Object?> row) {
    final buffer = StringBuffer();
    final description = row['description']?.toString().trim() ?? '';
    if (description.isNotEmpty) buffer.writeln(description);
    for (final key in const <String>[
      'detail_json',
      'entries_json',
      'json_data',
    ]) {
      final raw = row[key]?.toString().trim() ?? '';
      if (raw.isEmpty || raw == '{}' || raw == '[]') continue;
      buffer.writeln();
      buffer.writeln('## $key');
      buffer.writeln();
      final pretty = _prettyJson(raw);
      if (pretty == null) {
        // Unparseable payload: keep it verbatim rather than dropping data.
        buffer.writeln(raw);
      } else {
        buffer.writeln('```json');
        buffer.writeln(pretty);
        buffer.writeln('```');
      }
    }
    return buffer.toString().trim();
  }

  static String? _prettyJson(String raw) {
    try {
      return const JsonEncoder.withIndent('  ').convert(jsonDecode(raw));
    } on FormatException {
      return null;
    }
  }
}
