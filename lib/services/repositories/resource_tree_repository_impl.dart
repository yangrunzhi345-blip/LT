import 'package:sqflite/sqflite.dart';

import '../../domain/resources/resource_contracts.dart';
import '../../domain/resources/resource_repository.dart';
import 'resource_metadata_policy.dart';
import 'resource_tree_repository.dart';
import 'resource_tree_row_mapper.dart';

/// SQLite implementation of the unified Resource → Section → Part tree.
///
/// Design rules frozen by Phase 0/1:
/// - Section rows only point at a resource and part rows only point at a
///   section, so the three levels cannot be short-circuited or nested.
/// - Long body text only ever reaches `resource_parts.content`; there is no
///   whole-resource JSON column, and tree reads assemble per-node rows.
/// - Every multi-statement operation runs in one transaction, so a failure
///   never leaves half a tree or a half-applied ordering behind.
/// - Updates that can race require an explicit `expectedUpdatedAt` token and
///   raise [ResourceTreeConflictException] instead of silently overwriting.
final class ResourceTreeRepositoryImpl implements IResourceTreeRepository {
  ResourceTreeRepositoryImpl({
    required Future<Database> Function() getDb,
    ResourceMetadataPolicy metadataPolicy = const ResourceMetadataPolicy(),
  })  : _getDb = getDb,
        _metadataPolicy = metadataPolicy;

  final Future<Database> Function() _getDb;
  final ResourceMetadataPolicy _metadataPolicy;

  /// Monotonic suffix so ids created in the same microsecond stay unique.
  int _idSequence = 0;

  static const String _resources = 'resources';
  static const String _sections = 'resource_sections';
  static const String _parts = 'resource_parts';

  // ─── Creation ───

  @override
  Future<Resource> createResource({
    required ResourceType type,
    required String name,
    CreationMethod method = CreationMethod.manual,
    String summary = '',
    Map<String, Object?> metadata = const <String, Object?>{},
  }) async {
    final enriched = _withProvenance(method: method, metadata: metadata);
    _metadataPolicy.validate(type: type, metadata: enriched);

    final db = await _getDb();
    final id = ResourceId(_newId('res'));
    final now = _now();
    await db.insert(_resources, {
      'id': id.value,
      'type': type.storageValue,
      'name': name,
      'summary': summary,
      'status': NodeStatus.draft.storageValue,
      'metadata_json': ResourceTreeRowMapper.encodeMetadata(enriched),
      'schema_version': ResourceTreeSchema.currentResourceSchemaVersion,
      'created_at': now,
      'updated_at': now,
    });

    return Resource(
      id: id,
      type: type,
      name: name,
      summary: summary,
      metadata: enriched,
    );
  }

  @override
  Future<ResourceId> createResourceTree(ResourceTreeDraft draft) async {
    final db = await _getDb();
    await db.transaction((txn) => createResourceTreeInTransaction(txn, draft));
    return draft.id;
  }

  /// Runs creation-pipeline work at the same SQLite commit boundary as a tree.
  Future<T> runInTransaction<T>(
      Future<T> Function(Transaction txn) action) async {
    final db = await _getDb();
    return db.transaction(action);
  }

  Future<void> createResourceTreeInTransaction(
    DatabaseExecutor txn,
    ResourceTreeDraft draft,
  ) async {
    _metadataPolicy.validate(type: draft.type, metadata: draft.metadata);
    final now = _now();
    await txn.insert(_resources, {
      'id': draft.id.value,
      'type': draft.type.storageValue,
      'name': draft.name,
      'summary': draft.summary,
      'status': draft.status.storageValue,
      'metadata_json': ResourceTreeRowMapper.encodeMetadata(draft.metadata),
      'schema_version': ResourceTreeSchema.currentResourceSchemaVersion,
      'created_at': now,
      'updated_at': now,
    });
    await _insertTree(txn, draft, now);
  }

  @override
  Future<void> updateResourceTree(ResourceTreeDraft draft) async {
    final db = await _getDb();
    await db.transaction((txn) => updateResourceTreeInTransaction(txn, draft));
  }

  Future<void> updateResourceTreeInTransaction(
    DatabaseExecutor txn,
    ResourceTreeDraft draft,
  ) async {
    _metadataPolicy.validate(type: draft.type, metadata: draft.metadata);
    final now = _now();
    final existing = await _liveRow(txn, _resources, draft.id.value);
    if (existing == null) {
      throw ResourceTreeNotFoundException(
        '资源不存在或已删除：${draft.id.value}',
      );
    }

    await txn.update(
      _resources,
      {
        'name': draft.name,
        'summary': draft.summary,
        'status': draft.status.storageValue,
        'metadata_json': ResourceTreeRowMapper.encodeMetadata(draft.metadata),
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [draft.id.value],
    );

    // The tree is replaced wholesale, still inside this transaction, so a
    // failure restores the previous sections and parts.
    await txn.delete(
      _parts,
      where: 'section_id IN '
          '(SELECT id FROM $_sections WHERE resource_id = ?)',
      whereArgs: [draft.id.value],
    );
    await txn.delete(
      _sections,
      where: 'resource_id = ?',
      whereArgs: [draft.id.value],
    );
    await _insertTree(txn, draft, now);
  }

  /// Writes a draft's sections and parts for an existing resource row.
  Future<void> _insertTree(
    DatabaseExecutor txn,
    ResourceTreeDraft draft,
    String now,
  ) async {
    for (var sectionIndex = 0;
        sectionIndex < draft.sections.length;
        sectionIndex++) {
      final section = draft.sections[sectionIndex];
      final sectionId = section.id ?? SectionId(_newId('sec'));
      await txn.insert(_sections, {
        'id': sectionId.value,
        'resource_id': draft.id.value,
        'title': section.title,
        'summary': section.summary,
        'sort_order': sectionIndex,
        'status': section.status.storageValue,
        'created_at': now,
        'updated_at': now,
      });

      for (var partIndex = 0; partIndex < section.parts.length; partIndex++) {
        final part = section.parts[partIndex];
        await txn.insert(_parts, {
          'id': (part.id ?? PartId(_newId('part'))).value,
          'section_id': sectionId.value,
          'title': part.title,
          'content': part.content,
          'sort_order': partIndex,
          'status': part.status.storageValue,
          'content_hash': ResourceTreeRowMapper.contentHashFor(part.content),
          'created_at': now,
          'updated_at': now,
        });
      }
    }
  }

  @override
  Future<ResourceCreationSession> begin({
    required ResourceType type,
    required String name,
    CreationMethod method = CreationMethod.manual,
    String summary = '',
  }) async {
    return _BufferedCreationSession(
      repository: this,
      resourceId: ResourceId(_newId('res')),
      type: type,
      name: name,
      summary: summary,
      creationMethod: method,
    );
  }

  // ─── Reads ───

  @override
  Future<Resource?> findResource(ResourceId id) async {
    final db = await _getDb();
    final row = await _liveRow(db, _resources, id.value);
    if (row == null) return null;
    return ResourceTreeRowMapper.resourceFromRow(row);
  }

  @override
  Future<List<Resource>> listResources({
    required ResourceType type,
    bool includeArchived = false,
  }) async {
    final db = await _getDb();
    final rows = await db.query(
      _resources,
      where: 'type = ? AND deleted_at IS NULL'
          '${includeArchived ? '' : " AND status != 'archived'"}',
      whereArgs: [type.storageValue],
      orderBy: 'updated_at DESC, id ASC',
    );
    return rows.map(ResourceTreeRowMapper.resourceFromRow).toList();
  }

  @override
  Future<List<ResourceSection>> readSections(ResourceId resourceId) async {
    final db = await _getDb();
    return _readSections(db, resourceId.value);
  }

  @override
  Future<List<ResourcePart>> readParts(SectionId sectionId) async {
    final db = await _getDb();
    final rows = await db.query(
      _parts,
      where: 'section_id = ? AND deleted_at IS NULL',
      whereArgs: [sectionId.value],
      orderBy: 'sort_order ASC, id ASC',
    );
    return rows.map(ResourceTreeRowMapper.partFromRow).toList();
  }

  @override
  Future<ResourceTree?> readTree(ResourceId resourceId) async {
    final db = await _getDb();
    final row = await _liveRow(db, _resources, resourceId.value);
    if (row == null) return null;

    final sections = await _readSections(db, resourceId.value);
    final parts = sections.isEmpty
        ? const <ResourcePart>[]
        : await _readPartsOfSections(
            db,
            sections.map((section) => section.id.value).toList(),
          );

    final tree = ResourceTree(
      resource: ResourceTreeRowMapper.resourceFromRow(row),
      sections: sections,
      parts: parts,
    );
    // Contract invariants are re-checked on assembly so a corrupted row set can
    // never be handed out as a valid tree.
    tree.validate();
    return tree;
  }

  @override
  Future<ResourceNodeState?> readNodeState(NodeId id) async {
    final states = await readNodeStates([id]);
    return states.isEmpty ? null : states.first;
  }

  @override
  Future<List<ResourceNodeState>> readNodeStates(Iterable<NodeId> ids) async {
    final grouped = <String, List<String>>{};
    for (final id in ids) {
      grouped.putIfAbsent(_tableOf(id), () => <String>[]).add(id.value);
    }
    if (grouped.isEmpty) return const <ResourceNodeState>[];

    final db = await _getDb();
    final states = <ResourceNodeState>[];
    for (final entry in grouped.entries) {
      final rows = await _queryByIds(db, entry.key, entry.value);
      for (final row in rows) {
        states.add(ResourceNodeState(
          id: _nodeIdOf(entry.key, row['id'].toString()),
          updatedAt: row['updated_at']?.toString() ?? '',
          deletedAt: row['deleted_at']?.toString(),
          contentHash: row['content_hash']?.toString() ?? '',
        ));
      }
    }
    return states;
  }

  // ─── Updates ───

  @override
  Future<void> updateResource({
    required ResourceId id,
    required String expectedUpdatedAt,
    String? name,
    String? summary,
    Map<String, Object?>? metadata,
  }) async {
    final db = await _getDb();
    final row = await _requireLiveRow(db, _resources, id.value, label: '资源');
    final type = ResourceTreeRowMapper.resourceTypeFromStorage(row['type']);

    final values = <String, Object?>{'updated_at': _now()};
    if (name != null) values['name'] = name;
    if (summary != null) values['summary'] = summary;
    if (metadata != null) {
      final merged = _preserveProvenance(
        existing: ResourceTreeRowMapper.decodeMetadata(row['metadata_json']),
        incoming: metadata,
      );
      _metadataPolicy.validate(type: type, metadata: merged);
      values['metadata_json'] = ResourceTreeRowMapper.encodeMetadata(merged);
    }

    await _applyGuardedUpdate(
      db,
      table: _resources,
      id: id.value,
      expectedUpdatedAt: expectedUpdatedAt,
      values: values,
      label: '资源 ${id.value}',
    );
  }

  @override
  Future<void> updateSection({
    required SectionId id,
    required String expectedUpdatedAt,
    String? title,
    String? summary,
    NodeStatus? status,
  }) async {
    final db = await _getDb();
    final row =
        await _requireLiveRow(db, _sections, id.value, label: 'Section');

    final now = _now();
    final values = <String, Object?>{'updated_at': now};
    if (title != null) values['title'] = title;
    if (summary != null) values['summary'] = summary;
    if (status != null) {
      // The transition table is the only authority; no local status logic.
      ResourceStateMachines.advanceNodeStatus(
        ResourceTreeRowMapper.nodeStatusFromStorage(row['status']),
        status,
      );
      values['status'] = status.storageValue;
    }

    await db.transaction((txn) async {
      await _applyGuardedUpdate(
        txn,
        table: _sections,
        id: id.value,
        expectedUpdatedAt: expectedUpdatedAt,
        values: values,
        label: 'Section ${id.value}',
      );
      final resourceId = row['resource_id']?.toString();
      if (resourceId != null) {
        await _bumpResource(txn, resourceId, now);
      }
    });
  }

  @override
  Future<void> updatePart({
    required PartId id,
    required String expectedUpdatedAt,
    String? title,
    String? content,
    NodeStatus? status,
  }) async {
    final db = await _getDb();
    final row = await _requireLiveRow(db, _parts, id.value, label: 'Part');

    // Only this part's row is written: sibling parts are never touched.
    final now = _now();
    final values = <String, Object?>{'updated_at': now};
    if (title != null) values['title'] = title;
    if (content != null) {
      values['content'] = content;
      values['content_hash'] = ResourceTreeRowMapper.contentHashFor(content);
    }
    if (status != null) {
      ResourceStateMachines.advanceNodeStatus(
        ResourceTreeRowMapper.nodeStatusFromStorage(row['status']),
        status,
      );
      values['status'] = status.storageValue;
    }

    await db.transaction((txn) async {
      await _applyGuardedUpdate(
        txn,
        table: _parts,
        id: id.value,
        expectedUpdatedAt: expectedUpdatedAt,
        values: values,
        label: 'Part ${id.value}',
      );
      final sectionId = row['section_id']?.toString();
      await _bumpSection(txn, sectionId, now);
      final resourceId = await _resourceIdOfSection(txn, sectionId);
      if (resourceId != null) {
        await _bumpResource(txn, resourceId, now);
      }
    });
  }

  @override
  Future<void> softDeleteNode({
    required NodeId id,
    required String expectedUpdatedAt,
  }) async {
    final db = await _getDb();
    await db.transaction((txn) async {
      final now = _now();
      final values = <String, Object?>{'deleted_at': now, 'updated_at': now};

      switch (id) {
        case ResourceId():
          await _applyGuardedUpdate(
            txn,
            table: _resources,
            id: id.value,
            expectedUpdatedAt: expectedUpdatedAt,
            values: values,
            label: '资源 ${id.value}',
          );
          // Descendants are marked in the same transaction so a live tree can
          // never expose children of a deleted parent.
          final sections = await txn.query(
            _sections,
            columns: ['id'],
            where: 'resource_id = ?',
            whereArgs: [id.value],
          );
          await txn.update(
            _sections,
            values,
            where: 'resource_id = ? AND deleted_at IS NULL',
            whereArgs: [id.value],
          );
          final sectionIds =
              sections.map((row) => row['id'].toString()).toList();
          if (sectionIds.isNotEmpty) {
            await txn.update(
              _parts,
              values,
              where: '${_placeholders('section_id', sectionIds.length)}'
                  ' AND deleted_at IS NULL',
              whereArgs: sectionIds,
            );
          }
        case SectionId():
          await _applyGuardedUpdate(
            txn,
            table: _sections,
            id: id.value,
            expectedUpdatedAt: expectedUpdatedAt,
            values: values,
            label: 'Section ${id.value}',
          );
          await txn.update(
            _parts,
            values,
            where: 'section_id = ? AND deleted_at IS NULL',
            whereArgs: [id.value],
          );
          final resourceId = await _resourceIdOfSection(txn, id.value);
          if (resourceId != null) await _bumpResource(txn, resourceId, now);
        case PartId():
          // The owning section is read before the guarded update so its token
          // can be refreshed afterwards; the guarded update still owns the
          // "part missing / stale token" conflict semantics.
          final sectionId = await _sectionIdOfPart(txn, id.value);
          await _applyGuardedUpdate(
            txn,
            table: _parts,
            id: id.value,
            expectedUpdatedAt: expectedUpdatedAt,
            values: values,
            label: 'Part ${id.value}',
          );
          await _bumpSection(txn, sectionId, now);
          final resourceId = await _resourceIdOfSection(txn, sectionId);
          if (resourceId != null) await _bumpResource(txn, resourceId, now);
      }
    });
  }

  @override
  Future<void> reorderSections({
    required ResourceId resourceId,
    required List<SectionId> orderedIds,
  }) async {
    final db = await _getDb();
    await db.transaction((txn) async {
      await _reorder(
        txn,
        table: _sections,
        parentColumn: 'resource_id',
        parentValue: resourceId.value,
        orderedIds: orderedIds.map((id) => id.value).toList(),
      );
      await _bumpResource(txn, resourceId.value, _now());
    });
  }

  @override
  Future<void> reorderParts({
    required SectionId sectionId,
    required List<PartId> orderedIds,
  }) async {
    final db = await _getDb();
    await db.transaction((txn) async {
      await _reorder(
        txn,
        table: _parts,
        parentColumn: 'section_id',
        parentValue: sectionId.value,
        orderedIds: orderedIds.map((id) => id.value).toList(),
      );
      final now = _now();
      await _bumpSection(txn, sectionId.value, now);
      final resourceId = await _resourceIdOfSection(txn, sectionId.value);
      if (resourceId != null) await _bumpResource(txn, resourceId, now);
    });
  }

  // ─── Node mounts ───

  @override
  Future<ResourceMountResult> mount(ResourceNodePatch patch) async {
    return switch (patch) {
      AppendSectionPatch() => _appendSection(patch),
      AppendPartPatch() => _appendPart(patch),
      UpdatePartContentPatch() => _updatePartContent(patch),
      RenameNodePatch() => _renameNode(patch),
      ReorderNodePatch() => _reorderNode(patch),
      ArchiveNodePatch() => _archiveNode(patch),
    };
  }

  Future<ResourceMountResult> _appendSection(AppendSectionPatch patch) async {
    final db = await _getDb();
    return db.transaction((txn) async {
      await _requireLiveRow(
        txn,
        _resources,
        patch.resourceId.value,
        label: '资源',
      );
      final order = await _nextSortOrder(
        txn,
        _sections,
        'resource_id',
        patch.resourceId.value,
      );
      final id = SectionId(_newId('sec'));
      final now = _now();
      await txn.insert(_sections, {
        'id': id.value,
        'resource_id': patch.resourceId.value,
        'title': patch.title,
        'summary': patch.summary,
        'sort_order': order,
        'status': NodeStatus.draft.storageValue,
        'created_at': now,
        'updated_at': now,
      });
      await _bumpResource(txn, patch.resourceId.value, now);
      return ResourceMountResult(nodeId: id, sortOrder: order);
    });
  }

  Future<ResourceMountResult> _appendPart(AppendPartPatch patch) async {
    final db = await _getDb();
    return db.transaction((txn) async {
      final section = await _requireLiveRow(
        txn,
        _sections,
        patch.sectionId.value,
        label: 'Section',
      );
      final order = await _nextSortOrder(
        txn,
        _parts,
        'section_id',
        patch.sectionId.value,
      );
      final id = PartId(_newId('part'));
      final now = _now();
      await txn.insert(_parts, {
        'id': id.value,
        'section_id': patch.sectionId.value,
        'title': patch.title,
        'content': patch.content,
        'sort_order': order,
        'status': NodeStatus.draft.storageValue,
        'content_hash': ResourceTreeRowMapper.contentHashFor(patch.content),
        'created_at': now,
        'updated_at': now,
      });
      final resourceId = section['resource_id']?.toString();
      await _bumpSection(txn, patch.sectionId.value, now);
      if (resourceId != null) await _bumpResource(txn, resourceId, now);
      return ResourceMountResult(nodeId: id, sortOrder: order);
    });
  }

  Future<ResourceMountResult> _updatePartContent(
    UpdatePartContentPatch patch,
  ) async {
    final db = await _getDb();
    return db.transaction((txn) async {
      final row = await _requireLiveRow(
        txn,
        _parts,
        patch.partId.value,
        label: 'Part',
      );
      final now = _now();
      final hash = ResourceTreeRowMapper.contentHashFor(patch.content);
      await txn.update(
        _parts,
        {
          'content': patch.content,
          'content_hash': hash,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [patch.partId.value],
      );
      final sectionId = row['section_id']?.toString();
      await _bumpSection(txn, sectionId, now);
      final resourceId = await _resourceIdOfSection(txn, sectionId);
      if (resourceId != null) await _bumpResource(txn, resourceId, now);
      return ResourceMountResult(
        nodeId: patch.partId,
        sortOrder: _intOf(row['sort_order']),
      );
    });
  }

  Future<ResourceMountResult> _renameNode(RenameNodePatch patch) async {
    final db = await _getDb();
    return db.transaction((txn) async {
      final table = _tableOf(patch.nodeId);
      final column = table == _resources ? 'name' : 'title';
      final row = await _requireLiveRow(txn, table, patch.nodeId.value);
      final now = _now();
      await txn.update(
        table,
        {column: patch.title, 'updated_at': now},
        where: 'id = ?',
        whereArgs: [patch.nodeId.value],
      );
      await _bumpOwnerOf(txn, table, row, now);
      return ResourceMountResult(
        nodeId: patch.nodeId,
        sortOrder: _intOf(row['sort_order']),
      );
    });
  }

  Future<ResourceMountResult> _reorderNode(ReorderNodePatch patch) async {
    final db = await _getDb();
    return db.transaction((txn) async {
      final table = _tableOf(patch.nodeId);
      if (table == _resources) {
        throw ResourceTreeConflictException(
          '资源根节点没有同级顺序：${patch.nodeId.value}',
        );
      }
      final row = await _requireLiveRow(txn, table, patch.nodeId.value);
      await txn.update(
        table,
        {'sort_order': patch.sortOrder, 'updated_at': _now()},
        where: 'id = ?',
        whereArgs: [patch.nodeId.value],
      );
      if (table == _parts) {
        // Reordering Parts changes how the section reads: its token must move.
        await _bumpSection(txn, row['section_id']?.toString(), _now());
      }
      return ResourceMountResult(
        nodeId: patch.nodeId,
        sortOrder: patch.sortOrder,
      );
    });
  }

  Future<ResourceMountResult> _archiveNode(ArchiveNodePatch patch) async {
    final db = await _getDb();
    return db.transaction((txn) async {
      final table = _tableOf(patch.nodeId);
      final row = await _requireLiveRow(txn, table, patch.nodeId.value);
      // Illegal transitions (for example nothing in this table forbids it yet)
      // are rejected by the frozen table rather than by ad-hoc checks.
      ResourceStateMachines.advanceNodeStatus(
        ResourceTreeRowMapper.nodeStatusFromStorage(row['status']),
        NodeStatus.archived,
      );
      final now = _now();
      await txn.update(
        table,
        {'status': NodeStatus.archived.storageValue, 'updated_at': now},
        where: 'id = ?',
        whereArgs: [patch.nodeId.value],
      );
      await _bumpOwnerOf(txn, table, row, now);
      return ResourceMountResult(
        nodeId: patch.nodeId,
        sortOrder: _intOf(row['sort_order']),
      );
    });
  }

  // ─── Internal helpers ───

  Future<List<ResourceSection>> _readSections(
    DatabaseExecutor db,
    String resourceId,
  ) async {
    final rows = await db.query(
      _sections,
      where: 'resource_id = ? AND deleted_at IS NULL',
      whereArgs: [resourceId],
      orderBy: 'sort_order ASC, id ASC',
    );
    return rows.map(ResourceTreeRowMapper.sectionFromRow).toList();
  }

  Future<List<ResourcePart>> _readPartsOfSections(
    DatabaseExecutor db,
    List<String> sectionIds,
  ) async {
    final rows = await db.query(
      _parts,
      where: '${_placeholders('section_id', sectionIds.length)}'
          ' AND deleted_at IS NULL',
      whereArgs: sectionIds,
      orderBy: 'section_id ASC, sort_order ASC, id ASC',
    );
    return rows.map(ResourceTreeRowMapper.partFromRow).toList();
  }

  Future<List<Map<String, Object?>>> _queryByIds(
    DatabaseExecutor db,
    String table,
    List<String> ids,
  ) {
    return db.query(
      table,
      where: _placeholders('id', ids.length),
      whereArgs: ids,
    );
  }

  Future<Map<String, Object?>?> _liveRow(
    DatabaseExecutor db,
    String table,
    String id,
  ) async {
    final rows = await db.query(
      table,
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<Map<String, Object?>> _requireLiveRow(
    DatabaseExecutor db,
    String table,
    String id, {
    String? label,
  }) async {
    final row = await _liveRow(db, table, id);
    if (row == null) {
      throw ResourceTreeNotFoundException(
        '${label ?? table} 不存在或已删除：$id',
      );
    }
    return row;
  }

  /// Reads the owning section id of one Part row, or null when unknown.
  ///
  /// Returns the id (not the section row): callers need to know which section
  /// to refresh, and reading the section row here previously made
  /// `row['section_id']` permanently null.
  Future<String?> _sectionIdOfPart(
    DatabaseExecutor db,
    String partId,
  ) async {
    final parts = await db.query(
      _parts,
      columns: ['section_id'],
      where: 'id = ?',
      whereArgs: [partId],
      limit: 1,
    );
    if (parts.isEmpty) return null;
    return parts.first['section_id']?.toString();
  }

  Future<String?> _resourceIdOfSection(
    DatabaseExecutor db,
    String? sectionId,
  ) async {
    if (sectionId == null || sectionId.isEmpty) return null;
    final rows = await db.query(
      _sections,
      columns: ['resource_id'],
      where: 'id = ?',
      whereArgs: [sectionId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['resource_id']?.toString();
  }

  Future<int> _nextSortOrder(
    DatabaseExecutor db,
    String table,
    String parentColumn,
    String parentId,
  ) async {
    final rows = await db.rawQuery(
      'SELECT MAX(sort_order) AS max_order FROM $table '
      'WHERE $parentColumn = ? AND deleted_at IS NULL',
      [parentId],
    );
    final maxOrder = rows.isEmpty ? null : rows.first['max_order'];
    // MAX() is NULL for the first child, which must start at position 0.
    if (maxOrder == null) return 0;
    return _intOf(maxOrder) + 1;
  }

  Future<void> _reorder(
    DatabaseExecutor db, {
    required String table,
    required String parentColumn,
    required String parentValue,
    required List<String> orderedIds,
  }) async {
    if (orderedIds.toSet().length != orderedIds.length) {
      throw ResourceTreeConflictException('排序列表存在重复节点：$orderedIds');
    }

    final existing = await db.query(
      table,
      columns: ['id'],
      where: '$parentColumn = ? AND deleted_at IS NULL',
      whereArgs: [parentValue],
    );
    final existingIds = existing.map((row) => row['id'].toString()).toList();
    if (existingIds.length != orderedIds.length) {
      throw ResourceTreeConflictException(
        '排序列表与当前子节点数量不一致（期望 ${existingIds.length}，'
        '实际 ${orderedIds.length}），可能已被并发修改',
      );
    }

    // Position is stored explicitly. A stale id makes the loop fail after some
    // rows were written, which the surrounding transaction rolls back.
    for (var index = 0; index < orderedIds.length; index++) {
      final updated = await db.update(
        table,
        {'sort_order': index, 'updated_at': _now()},
        where: 'id = ? AND $parentColumn = ? AND deleted_at IS NULL',
        whereArgs: [orderedIds[index], parentValue],
      );
      if (updated == 0) {
        throw ResourceTreeConflictException(
          '节点 ${orderedIds[index]} 不属于 $parentValue，排序已回滚',
        );
      }
    }
  }

  Future<void> _applyGuardedUpdate(
    DatabaseExecutor db, {
    required String table,
    required String id,
    required String expectedUpdatedAt,
    required Map<String, Object?> values,
    required String label,
  }) async {
    final updated = await db.update(
      table,
      values,
      where: 'id = ? AND updated_at = ? AND deleted_at IS NULL',
      whereArgs: [id, expectedUpdatedAt],
    );
    if (updated == 0) {
      throw ResourceTreeConflictException(
        '$label 已被并发修改（期望 updated_at=$expectedUpdatedAt），写入被拒绝',
      );
    }
  }

  Future<void> _bumpResource(
    DatabaseExecutor db,
    String resourceId,
    String now,
  ) async {
    await db.update(
      _resources,
      {'updated_at': now},
      where: 'id = ?',
      whereArgs: [resourceId],
    );
  }

  /// Refreshes a section's `updated_at` after any change to its Parts.
  ///
  /// The section token is what guards section-level writes (validation verdict,
  /// rename, delete, regenerate). Without this bump a Part edit would be
  /// invisible to those guards, so a write based on a stale section read could
  /// land on top of newer Part content. Bumping here — in the repository, not
  /// in each caller — is what makes the rule hold for every Part path.
  Future<void> _bumpSection(
    DatabaseExecutor db,
    String? sectionId,
    String now,
  ) async {
    if (sectionId == null || sectionId.isEmpty) return;
    await db.update(
      _sections,
      {'updated_at': now},
      where: 'id = ?',
      whereArgs: [sectionId],
    );
  }

  /// Refreshes the owning resource's `updated_at` after a node edit.
  ///
  /// Deliberately explicit: editing one node writes that node's row (and, when
  /// the node is a section or part, the single resource freshness marker). It
  /// never rewrites sibling nodes.
  ///
  /// A Part edit additionally refreshes its owning section: the section token
  /// guards section-level writes, so it must move whenever the section's
  /// content moves.
  Future<void> _bumpOwnerOf(
    DatabaseExecutor db,
    String table,
    Map<String, Object?> row,
    String now,
  ) async {
    if (table == _resources) return;
    if (table == _sections) {
      final resourceId = row['resource_id']?.toString();
      if (resourceId != null) await _bumpResource(db, resourceId, now);
      return;
    }
    final sectionId = row['section_id']?.toString();
    await _bumpSection(db, sectionId, now);
    final resourceId = await _resourceIdOfSection(db, sectionId);
    if (resourceId != null) await _bumpResource(db, resourceId, now);
  }

  Map<String, Object?> _withProvenance({
    required CreationMethod method,
    required Map<String, Object?> metadata,
  }) {
    return <String, Object?>{
      ...metadata,
      ResourceTreeSchema.metadataAuthoringMethodKey: method.storageValue,
    };
  }

  Map<String, Object?> _preserveProvenance({
    required Map<String, Object?> existing,
    required Map<String, Object?> incoming,
  }) {
    final merged = <String, Object?>{...incoming};
    for (final key in const [
      ResourceTreeSchema.metadataAuthoringMethodKey,
      ResourceTreeSchema.metadataAiGenerationDepthKey,
    ]) {
      final value = existing[key];
      if (value != null && !merged.containsKey(key)) merged[key] = value;
    }
    return merged;
  }

  String _tableOf(NodeId id) => switch (id) {
        ResourceId() => _resources,
        SectionId() => _sections,
        PartId() => _parts,
      };

  NodeId _nodeIdOf(String table, String value) {
    if (table == _resources) return ResourceId(value);
    if (table == _sections) return SectionId(value);
    return PartId(value);
  }

  String _placeholders(String column, int count) =>
      '$column IN (${List.filled(count, '?').join(', ')})';

  String _now() => DateTime.now().toIso8601String();

  String _newId(String prefix) =>
      '${prefix}_${DateTime.now().microsecondsSinceEpoch}_${++_idSequence}';

  int _intOf(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '') ?? 0;
  }
}

/// Buffers a creation flow and publishes it as one transaction on commit.
///
/// Buffering is what makes "nothing is published until commit" true: an
/// abandoned session leaves no partial resource behind, and a commit writes the
/// resource, all sections and all parts atomically.
final class _BufferedCreationSession implements ResourceCreationSession {
  _BufferedCreationSession({
    required ResourceTreeRepositoryImpl repository,
    required this.resourceId,
    required this.type,
    required this.name,
    required this.summary,
    required this.creationMethod,
  }) : _repository = repository;

  final ResourceTreeRepositoryImpl _repository;

  @override
  final ResourceId resourceId;

  @override
  final ResourceType type;

  @override
  final CreationMethod creationMethod;

  final String name;
  final String summary;

  final List<_PendingSection> _sections = <_PendingSection>[];
  bool _finished = false;

  @override
  Future<SectionId> appendSection({
    required String title,
    String summary = '',
  }) async {
    _ensureOpen();
    final id = SectionId(_repository._newId('sec'));
    _sections.add(_PendingSection(id: id, title: title, summary: summary));
    return id;
  }

  @override
  Future<PartId> appendPart({
    required SectionId sectionId,
    required String title,
    required String content,
  }) async {
    _ensureOpen();
    _PendingSection? section;
    for (final candidate in _sections) {
      if (candidate.id == sectionId) {
        section = candidate;
        break;
      }
    }
    if (section == null) {
      throw ResourceTreeNotFoundException(
        'Section $sectionId 不属于当前创建会话',
      );
    }
    final id = PartId(_repository._newId('part'));
    section.parts.add(_PendingPart(
      id: id,
      title: title,
      content: content,
    ));
    return id;
  }

  @override
  Future<void> commit() async {
    _ensureOpen();
    _finished = true;

    final db = await _repository._getDb();
    final now = _repository._now();
    final metadata = _repository._withProvenance(
      method: creationMethod,
      metadata: const <String, Object?>{},
    );
    _repository._metadataPolicy.validate(type: type, metadata: metadata);

    await db.transaction((txn) async {
      await txn.insert(ResourceTreeRepositoryImpl._resources, {
        'id': resourceId.value,
        'type': type.storageValue,
        'name': name,
        'summary': summary,
        'status': NodeStatus.draft.storageValue,
        'metadata_json': ResourceTreeRowMapper.encodeMetadata(metadata),
        'schema_version': ResourceTreeSchema.currentResourceSchemaVersion,
        'created_at': now,
        'updated_at': now,
      });

      for (var sectionIndex = 0;
          sectionIndex < _sections.length;
          sectionIndex++) {
        final section = _sections[sectionIndex];
        await txn.insert(ResourceTreeRepositoryImpl._sections, {
          'id': section.id.value,
          'resource_id': resourceId.value,
          'title': section.title,
          'summary': section.summary,
          'sort_order': sectionIndex,
          'status': NodeStatus.draft.storageValue,
          'created_at': now,
          'updated_at': now,
        });

        for (var partIndex = 0; partIndex < section.parts.length; partIndex++) {
          final part = section.parts[partIndex];
          await txn.insert(ResourceTreeRepositoryImpl._parts, {
            'id': part.id.value,
            'section_id': section.id.value,
            'title': part.title,
            'content': part.content,
            'sort_order': partIndex,
            'status': NodeStatus.draft.storageValue,
            'content_hash': ResourceTreeRowMapper.contentHashFor(part.content),
            'created_at': now,
            'updated_at': now,
          });
        }
      }
    });
  }

  @override
  Future<void> abandon() async {
    _ensureOpen();
    _finished = true;
  }

  void _ensureOpen() {
    if (_finished) {
      throw ResourceTreeConflictException('创建会话已结束：${resourceId.value}');
    }
  }
}

final class _PendingSection {
  _PendingSection({
    required this.id,
    required this.title,
    required this.summary,
  });

  final SectionId id;
  final String title;
  final String summary;
  final List<_PendingPart> parts = <_PendingPart>[];
}

final class _PendingPart {
  _PendingPart({
    required this.id,
    required this.title,
    required this.content,
  });

  final PartId id;
  final String title;
  final String content;
}
