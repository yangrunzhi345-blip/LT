import 'package:sqflite/sqflite.dart';

import '../../domain/resources/resource_contracts.dart';
import '../../domain/resources/section_control.dart';
import '../../domain/resources/section_control_repository.dart';
import 'resource_tree_repository.dart';
import 'resource_tree_row_mapper.dart';

/// SQLite implementation of [ISectionControlRepository].
///
/// Reads stay bounded on purpose:
/// - the section list is a `LIMIT`/`OFFSET` query, never a full-tree assembly;
/// - Part aggregates for a page are one grouped-in-Dart query over just that
///   page's sections;
/// - full Part content is only ever read for a single section during
///   validation.
///
/// Writing validation state goes through a guarded `updated_at` comparison, so
/// a section that changed since the caller read it rejects the write instead of
/// silently overwriting newer content. Validation itself does not bump
/// `updated_at`: it records history, it is not a content edit, and bumping the
/// token would invalidate an unrelated in-flight edit.
final class SectionControlRepositoryImpl implements ISectionControlRepository {
  SectionControlRepositoryImpl({
    required Future<Database> Function() getDb,
    this.previewCharacters = defaultPreviewCharacters,
  }) : _getDb = getDb;

  /// How much body text a list row may carry. A section preview is a hint, not
  /// content: the full body is only loaded for the section being read or
  /// validated.
  static const int defaultPreviewCharacters = 400;

  static const String sectionsTable = 'resource_sections';
  static const String partsTable = 'resource_parts';
  static const String tasksTable = 'resource_generation_tasks';

  final Future<Database> Function() _getDb;
  final int previewCharacters;

  @override
  Future<SectionControlPageData> readSectionPage({
    required ResourceId resourceId,
    required int limit,
    required int offset,
  }) async {
    if (limit <= 0) {
      throw ResourceTreeConflictException('Section 分页 limit 必须大于零：$limit');
    }
    if (offset < 0) {
      throw ResourceTreeConflictException('Section 分页 offset 不能为负：$offset');
    }

    final db = await _getDb();
    final rows = await db.query(
      sectionsTable,
      columns: _sectionColumns,
      where: 'resource_id = ? AND deleted_at IS NULL',
      whereArgs: [resourceId.value],
      orderBy: 'sort_order ASC, id ASC',
      limit: limit,
      offset: offset,
    );
    final totalRows = await db.rawQuery(
      'SELECT COUNT(*) AS total FROM $sectionsTable '
      'WHERE resource_id = ? AND deleted_at IS NULL',
      [resourceId.value],
    );
    final total = _intOf(totalRows.isEmpty ? null : totalRows.first['total']);

    return SectionControlPageData(
      rows: rows.map(_rowFromMap).toList(),
      totalCount: total,
      offset: offset,
    );
  }

  @override
  Future<SectionControlRow?> findSectionControlRow(SectionId id) async {
    final db = await _getDb();
    final rows = await db.query(
      sectionsTable,
      columns: _sectionColumns,
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id.value],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _rowFromMap(rows.first);
  }

  @override
  Future<Map<String, SectionPartSummary>> readPartSummaries(
    Iterable<SectionId> sectionIds,
  ) async {
    final ids = _distinctIds(sectionIds);
    if (ids.isEmpty) return const <String, SectionPartSummary>{};

    final db = await _getDb();
    final rows = await db.query(
      partsTable,
      columns: ['section_id', 'content'],
      where:
          '${_placeholders('section_id', ids.length)} AND deleted_at IS NULL',
      whereArgs: ids,
      orderBy: 'section_id ASC, sort_order ASC, id ASC',
    );

    final counts = <String, int>{};
    final lengths = <String, int>{};
    final previews = <String, StringBuffer>{};
    for (final row in rows) {
      final sectionId = row['section_id'].toString();
      final content = row['content']?.toString() ?? '';
      counts[sectionId] = (counts[sectionId] ?? 0) + 1;
      lengths[sectionId] = (lengths[sectionId] ?? 0) + content.length;
      final buffer = previews.putIfAbsent(sectionId, StringBuffer.new);
      if (buffer.length < previewCharacters) {
        buffer.write(content);
      }
    }

    return {
      for (final id in ids)
        id: SectionPartSummary(
          partCount: counts[id] ?? 0,
          characterCount: lengths[id] ?? 0,
          preview: _truncate(previews[id]?.toString() ?? ''),
        ),
    };
  }

  @override
  Future<List<SectionTaskRow>> readSectionTasks(
    Iterable<SectionId> sectionIds,
  ) async {
    final ids = _distinctIds(sectionIds);
    if (ids.isEmpty) return const <SectionTaskRow>[];

    final db = await _getDb();
    final rows = await db.query(
      tasksTable,
      columns: [
        'task_id',
        'blueprint_id',
        'resource_id',
        'section_id',
        'part_id',
        'status',
      ],
      where: _placeholders('section_id', ids.length),
      whereArgs: ids,
      orderBy: 'section_id ASC, sort_order ASC, task_id ASC',
    );

    return rows
        .map(
          (row) => SectionTaskRow(
            taskId: row['task_id'].toString(),
            blueprintId: row['blueprint_id']?.toString() ?? '',
            resourceId: row['resource_id']?.toString() ?? '',
            sectionId: SectionId(row['section_id'].toString()),
            partId: PartId(row['part_id'].toString()),
            status: row['status']?.toString() ?? '',
          ),
        )
        .toList();
  }

  @override
  Future<List<SectionPartRow>> readSectionParts(SectionId sectionId) async {
    final db = await _getDb();
    final rows = await db.query(
      partsTable,
      columns: ['id', 'section_id', 'title', 'content', 'sort_order'],
      where: 'section_id = ? AND deleted_at IS NULL',
      whereArgs: [sectionId.value],
      orderBy: 'sort_order ASC, id ASC',
    );
    return rows
        .map(
          (row) => SectionPartRow(
            id: PartId(row['id'].toString()),
            sectionId: SectionId(row['section_id'].toString()),
            title: row['title']?.toString() ?? '',
            content: row['content']?.toString() ?? '',
            orderIndex: _intOf(row['sort_order']),
          ),
        )
        .toList();
  }

  @override
  Future<void> updateSectionValidation({
    required SectionId id,
    required String expectedUpdatedAt,
    required SectionValidationState state,
    required String message,
    DateTime? validatedAt,
  }) async {
    final db = await _getDb();
    final values = <String, Object?>{
      'validation_state': state.storageValue,
      'validation_message': message,
    };
    if (validatedAt != null) {
      values['validated_at'] = validatedAt.toIso8601String();
    }

    final updated = await db.update(
      sectionsTable,
      values,
      where: 'id = ? AND updated_at = ? AND deleted_at IS NULL',
      whereArgs: [id.value, expectedUpdatedAt],
    );
    if (updated == 0) {
      throw ResourceTreeConflictException(
        'Section ${id.value} 已被并发修改（期望 updated_at=$expectedUpdatedAt），'
        '校验结果写入被拒绝',
      );
    }
  }

  static const List<String> _sectionColumns = [
    'id',
    'resource_id',
    'title',
    'summary',
    'sort_order',
    'status',
    'validation_state',
    'validation_message',
    'created_at',
    'updated_at',
    'validated_at',
  ];

  SectionControlRow _rowFromMap(Map<String, Object?> row) {
    return SectionControlRow(
      id: SectionId(row['id'].toString()),
      resourceId: ResourceId(row['resource_id'].toString()),
      title: row['title']?.toString() ?? '',
      summary: row['summary']?.toString() ?? '',
      orderIndex: _intOf(row['sort_order']),
      status: ResourceTreeRowMapper.nodeStatusFromStorage(row['status']),
      validationState: SectionValidationState.fromStorage(
          row['validation_state']?.toString()),
      validationMessage: row['validation_message']?.toString() ?? '',
      createdAt: row['created_at']?.toString() ?? '',
      updatedAt: row['updated_at']?.toString() ?? '',
      validatedAt: row['validated_at']?.toString(),
    );
  }

  List<String> _distinctIds(Iterable<SectionId> sectionIds) {
    final ids = <String>[];
    for (final id in sectionIds) {
      if (!ids.contains(id.value)) ids.add(id.value);
    }
    return ids;
  }

  String _truncate(String value) {
    if (value.length <= previewCharacters) return value;
    return value.substring(0, previewCharacters);
  }

  String _placeholders(String column, int count) =>
      '$column IN (${List.filled(count, '?').join(', ')})';

  int _intOf(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '') ?? 0;
  }
}
