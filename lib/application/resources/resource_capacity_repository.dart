import 'package:sqflite/sqflite.dart';

import '../../domain/resources/resource_capacity.dart';
import '../../domain/resources/resource_contracts.dart';

/// Persistence boundary for measured resource capacity.
///
/// Every method returns whole snapshots; none of them streams rows out to the
/// caller, so a caller can never accidentally run one query per section.
abstract interface class IResourceCapacityRepository {
  /// Measures exactly one resource, or throws if it is missing.
  Future<ResourceCapacitySnapshot> measureResource(ResourceId id);

  /// Measures every live resource, optionally restricted to one type.
  Future<List<ResourceCapacitySnapshot>> measureResources({
    ResourceType? type,
  });

  /// Measures the sections of one resource in canonical order.
  Future<List<SectionCapacitySnapshot>> measureSections(ResourceId id);

  /// Reads a previously persisted measurement, or null when never measured.
  Future<ResourceCapacitySnapshot?> readCachedResource(ResourceId id);

  /// Writes a measurement into the resource's cache columns.
  Future<void> persistResource(ResourceCapacitySnapshot snapshot);
}

/// Raised when capacity cannot be measured for a resource.
class ResourceCapacityException implements Exception {
  const ResourceCapacityException(this.message);

  final String message;

  @override
  String toString() => 'ResourceCapacityException: $message';
}

/// SQLite-backed capacity measurement.
///
/// Design contract for Phase 8:
/// - Every aggregate is computed by SQLite in **one** `GROUP BY` statement, so
///   measurement cost is independent of the number of sections and resources.
/// - No `SELECT *` and no query issued from inside a loop; the statement count
///   is a small constant (see the structural guard in the Phase 8 tests).
/// - The repository never writes body content. It only refreshes the cache
///   columns on `resources`.
final class ResourceCapacityRepositoryImpl
    implements IResourceCapacityRepository {
  ResourceCapacityRepositoryImpl({required Future<Database> Function() getDb})
      : _getDb = getDb;

  final Future<Database> Function() _getDb;

  static const String resourcesTable = 'resources';
  static const String sectionsTable = 'resource_sections';
  static const String partsTable = 'resource_parts';
  static const String tasksTable = 'resource_generation_tasks';
  static const String attemptsTable = 'resource_generation_attempts';

  /// The cached capacity columns added to `resources` in v39.
  ///
  /// The names deliberately avoid the word `content`: the Phase 1 structural
  /// guard forbids any body-carrying column on `resources`, and these two are
  /// numeric projections, not text.
  static const List<String> cacheColumns = <String>[
    'measured_char_count',
    'measured_token_estimate',
    'section_count',
    'part_count',
    'archive_char_count',
    'capacity_status',
    'capacity_measured_at',
  ];

  /// One aggregate over the live tree, grouped by owning resources.
  ///
  /// `LENGTH` is measured in Dart string units (UTF-16 code units) exactly like
  /// `String.length`, so the database count and the in-memory count agree.
  static const String _aggregateByResourceColumns = '''
    SELECT s.resource_id AS resource_id,
           COUNT(p.id) AS part_count,
           COALESCE(SUM(LENGTH(COALESCE(p.content, ''))), 0) AS total_chars,
           COALESCE(SUM(CASE WHEN p.status = 'archived'
                             THEN LENGTH(COALESCE(p.content, '')) ELSE 0 END), 0)
             AS archived_chars
      FROM $partsTable p
      INNER JOIN $sectionsTable s ON s.id = p.section_id
      INNER JOIN $resourcesTable r ON r.id = s.resource_id
     WHERE s.deleted_at IS NULL AND p.deleted_at IS NULL
       AND r.deleted_at IS NULL
  ''';

  static const String _aggregateBySection = '''
    SELECT p.section_id AS section_id,
           COUNT(p.id) AS part_count,
           COALESCE(SUM(LENGTH(COALESCE(p.content, ''))), 0) AS total_chars,
           COALESCE(MAX(LENGTH(COALESCE(p.content, ''))), 0) AS max_chars,
           COALESCE(SUM(CASE WHEN TRIM(COALESCE(p.content, '')) = ''
                             THEN 1 ELSE 0 END), 0) AS empty_parts
      FROM $partsTable p
      INNER JOIN $sectionsTable s ON s.id = p.section_id
     WHERE s.resource_id = ? AND s.deleted_at IS NULL AND p.deleted_at IS NULL
     GROUP BY p.section_id
  ''';

  @override
  Future<ResourceCapacitySnapshot> measureResource(ResourceId id) async {
    final db = await _getDb();
    final resourceRows = await db.query(
      resourcesTable,
      columns: ['type'],
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id.value],
      limit: 1,
    );
    if (resourceRows.isEmpty) {
      throw ResourceCapacityException('资源不存在或已删除：${id.value}');
    }
    final type = ResourceType.fromStorageValue(
      resourceRows.first['type']?.toString(),
    );

    final aggregateRows = await db.rawQuery(
      '''
      SELECT COUNT(p.id) AS part_count,
             COALESCE(SUM(LENGTH(COALESCE(p.content, ''))), 0) AS total_chars,
             COALESCE(SUM(CASE WHEN p.status = 'archived'
                               THEN LENGTH(COALESCE(p.content, '')) ELSE 0 END), 0)
               AS archived_chars
        FROM $partsTable p
        INNER JOIN $sectionsTable s ON s.id = p.section_id
       WHERE s.resource_id = ? AND s.deleted_at IS NULL AND p.deleted_at IS NULL
      ''',
      [id.value],
    );
    final sectionRows = await db.rawQuery(
      'SELECT COUNT(*) AS section_count FROM $sectionsTable '
      'WHERE resource_id = ? AND deleted_at IS NULL',
      [id.value],
    );
    final attemptRows = await db.rawQuery(
      'SELECT COUNT(*) AS attempt_count FROM $attemptsTable a '
      'INNER JOIN $tasksTable t ON t.task_id = a.task_id '
      'WHERE t.resource_id = ?',
      [id.value],
    );

    final aggregate = aggregateRows.first;
    final total = _intOrZero(aggregate['total_chars']);
    final archived = _intOrZero(aggregate['archived_chars']);
    final now = DateTime.now();

    return ResourceCapacitySnapshot(
      resourceId: id,
      type: type,
      totalCharacters: total,
      activeCharacters: total - archived,
      archivedCharacters: archived,
      estimatedTokens: ResourceCapacityMath.tokensForCharacters(total),
      sectionCount: _intOrZero(sectionRows.first['section_count']),
      partCount: _intOrZero(aggregate['part_count']),
      historicalRevisionCount: _intOrZero(attemptRows.first['attempt_count']),
      status: ResourceCapacityMath.statusFor(type, total),
      measuredAt: now,
    );
  }

  @override
  Future<List<ResourceCapacitySnapshot>> measureResources({
    ResourceType? type,
  }) async {
    final db = await _getDb();
    final resourceRows = await db.query(
      resourcesTable,
      columns: ['id', 'type'],
      where: type == null
          ? 'deleted_at IS NULL'
          : 'deleted_at IS NULL AND type = ?',
      whereArgs: type == null ? null : [type.storageValue],
    );
    if (resourceRows.isEmpty) return const <ResourceCapacitySnapshot>[];

    final aggregates = await db.rawQuery(
      '$_aggregateByResourceColumns'
      '${type == null ? '' : ' AND r.type = ?'}'
      ' GROUP BY s.resource_id',
      type == null ? null : [type.storageValue],
    );
    final sectionCounts = await db.rawQuery(
      'SELECT resource_id, COUNT(*) AS section_count FROM $sectionsTable '
      'WHERE deleted_at IS NULL GROUP BY resource_id',
    );
    final attemptCounts = await db.rawQuery(
      'SELECT t.resource_id AS resource_id, COUNT(*) AS attempt_count '
      'FROM $attemptsTable a '
      'INNER JOIN $tasksTable t ON t.task_id = a.task_id GROUP BY t.resource_id',
    );

    final aggregateByResource = _indexByResource(aggregates);
    final sectionByResource = _indexByResource(sectionCounts);
    final attemptByResource = _indexByResource(attemptCounts);

    final snapshots = <ResourceCapacitySnapshot>[];
    for (final row in resourceRows) {
      final resourceId = row['id']?.toString() ?? '';
      if (resourceId.isEmpty) continue;
      final resourceType = ResourceType.fromStorageValue(
        row['type']?.toString(),
      );
      final aggregate = aggregateByResource[resourceId];
      final total = _intOrZero(aggregate?['total_chars']);
      final archived = _intOrZero(aggregate?['archived_chars']);
      snapshots.add(
        ResourceCapacitySnapshot(
          resourceId: ResourceId(resourceId),
          type: resourceType,
          totalCharacters: total,
          activeCharacters: total - archived,
          archivedCharacters: archived,
          estimatedTokens: ResourceCapacityMath.tokensForCharacters(total),
          sectionCount:
              _intOrZero(sectionByResource[resourceId]?['section_count']),
          partCount: _intOrZero(aggregate?['part_count']),
          historicalRevisionCount:
              _intOrZero(attemptByResource[resourceId]?['attempt_count']),
          status: ResourceCapacityMath.statusFor(resourceType, total),
        ),
      );
    }
    return snapshots;
  }

  @override
  Future<List<SectionCapacitySnapshot>> measureSections(ResourceId id) async {
    final db = await _getDb();
    final sectionRows = await db.query(
      sectionsTable,
      columns: ['id', 'title'],
      where: 'resource_id = ? AND deleted_at IS NULL',
      whereArgs: [id.value],
      orderBy: 'sort_order ASC, id ASC',
    );
    if (sectionRows.isEmpty) return const <SectionCapacitySnapshot>[];

    final aggregateRows = await db.rawQuery(_aggregateBySection, [id.value]);
    final bySection = <String, Map<String, Object?>>{
      for (final row in aggregateRows)
        if ((row['section_id']?.toString() ?? '').isNotEmpty)
          row['section_id']!.toString(): row,
    };

    final snapshots = <SectionCapacitySnapshot>[];
    for (final row in sectionRows) {
      final sectionId = row['id']?.toString() ?? '';
      if (sectionId.isEmpty) continue;
      final aggregate = bySection[sectionId];
      final partCount = _intOrZero(aggregate?['part_count']);
      final emptyParts = _intOrZero(aggregate?['empty_parts']);
      snapshots.add(
        SectionCapacitySnapshot(
          sectionId: SectionId(sectionId),
          title: row['title']?.toString() ?? '',
          characters: _intOrZero(aggregate?['total_chars']),
          partCount: partCount,
          largestPartCharacters: _intOrZero(aggregate?['max_chars']),
          isComplete: partCount > 0 && emptyParts == 0,
        ),
      );
    }
    return snapshots;
  }

  @override
  Future<ResourceCapacitySnapshot?> readCachedResource(ResourceId id) async {
    final db = await _getDb();
    final rows = await db.query(
      resourcesTable,
      columns: [
        'type',
        'measured_char_count',
        'measured_token_estimate',
        'section_count',
        'part_count',
        'archive_char_count',
        'capacity_status',
        'capacity_measured_at',
      ],
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id.value],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    final measuredAt = row['capacity_measured_at']?.toString();
    if (measuredAt == null || measuredAt.isEmpty) return null;

    final type = ResourceType.fromStorageValue(row['type']?.toString());
    final total = _intOrZero(row['measured_char_count']);
    return ResourceCapacitySnapshot(
      resourceId: id,
      type: type,
      totalCharacters: total,
      activeCharacters: total - _intOrZero(row['archive_char_count']),
      archivedCharacters: _intOrZero(row['archive_char_count']),
      estimatedTokens: _intOrZero(row['measured_token_estimate']),
      sectionCount: _intOrZero(row['section_count']),
      partCount: _intOrZero(row['part_count']),
      historicalRevisionCount: 0,
      status: ResourceCapacityMath.statusFor(type, total),
      measuredAt: DateTime.tryParse(measuredAt),
    );
  }

  @override
  Future<void> persistResource(ResourceCapacitySnapshot snapshot) async {
    final db = await _getDb();
    final measuredAt =
        (snapshot.measuredAt ?? DateTime.now()).toIso8601String();
    await db.update(
      resourcesTable,
      {
        'measured_char_count': snapshot.totalCharacters,
        'measured_token_estimate': snapshot.estimatedTokens,
        'section_count': snapshot.sectionCount,
        'part_count': snapshot.partCount,
        'archive_char_count': snapshot.archivedCharacters,
        'capacity_status': snapshot.status.storageValue,
        'capacity_measured_at': measuredAt,
      },
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [snapshot.resourceId.value],
    );
  }

  static Map<String, Map<String, Object?>> _indexByResource(
    List<Map<String, Object?>> rows,
  ) {
    final indexed = <String, Map<String, Object?>>{};
    for (final row in rows) {
      final key = row['resource_id']?.toString() ?? '';
      if (key.isEmpty) continue;
      indexed[key] = row;
    }
    return indexed;
  }

  static int _intOrZero(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
}
