import 'dart:convert';

import '../../domain/resources/resource_contracts.dart';
import '../../domain/resources/resource_repository.dart';
import '../../domain/resources/resource_revision.dart';
import '../../models/worldview_details.dart';
import 'resource_adventure_view.dart';
import '../../services/worldview_snapshot_service.dart';
import 'assembly_readiness_repository.dart';
import 'resource_revision_repository.dart';

/// Thrown when a revision cannot be assembled into runtime output.
class ResourceAssemblyException implements Exception {
  const ResourceAssemblyException(this.message);

  final String message;

  @override
  String toString() => 'ResourceAssemblyException: $message';
}

/// Everything one immutable revision assembles into (Phase 10).
final class ResourceAssemblyBuildResult {
  const ResourceAssemblyBuildResult({
    required this.snapshot,
    required this.resourceType,
    this.worldviewPayload,
    this.cardRow,
    this.indexDocs = const <AssemblyIndexDoc>[],
  });

  /// Fragment view of the revision; canon flags follow the frozen node status.
  final ResourceAssemblySnapshot snapshot;

  final ResourceType resourceType;

  /// `WorldviewSnapshotService.snapshot`-shaped payload for worldview
  /// resources, with `content_hash` pinned to the revision's content hash so
  /// snapshot provenance and revision provenance cannot drift apart.
  final Map<String, dynamic>? worldviewPayload;

  /// `character_cards` / `npc_cards` row shape (with `json_data`) for card
  /// resources, projected from the revision only.
  final Map<String, Object?>? cardRow;

  /// Revision-bound semantic index documents (worldview only).
  final List<AssemblyIndexDoc> indexDocs;
}

/// Builds runtime output from one immutable revision (Phase 10).
///
/// The builder never reads the live tree: its only content source is
/// [IResourceRevisionRepository.readState] for the revision it was handed, so
/// the output is reproducible and cannot pick up edits that happened after the
/// head was captured.
///
/// Canon policy (frozen node status of the revision):
/// - `confirmed` fragments may enter canon (`isCanon = true`).
/// - `draft` fragments are carried but must not be injected as facts
///   (`isCanon = false`); they are excluded from worldview payloads and index
///   documents, matching `WorldviewDetails.confirmedModules`.
/// - `archived` content is excluded entirely.
///
/// Character/NPC runtime core fields (`first_mes`, `system_prompt`, ...) are
/// read through the established production projection
/// [ResourceAdventureView.toCardRow] over the revision-derived tree; no field
/// name is invented here and no value is filled in from the live tree.
///
/// Type resolution note: `ResourceRevisionState.toResourceTree()` expects the
/// resource type inside the root metadata, but the production tree writer
/// stores `type` as a column and `metadata_json` never carries it, so that
/// helper throws for every standard state (latent Phase 9 defect, first hit by
/// this builder). The builder therefore reconstructs the tree itself and
/// resolves the type through [typeResolver]. Resource *type* is an immutable
/// identity attribute — no production path can change it after creation — so
/// resolving it outside the revision cannot leak mutable content into the
/// snapshot. Content itself still comes exclusively from the revision.
final class ResourceAssemblyBuilder
    implements ResourceAssemblySnapshotProvider {
  ResourceAssemblyBuilder({
    required IResourceRevisionRepository revisionRepository,
    Future<ResourceType?> Function(ResourceId resourceId)? typeResolver,
  })  : _revisions = revisionRepository,
        _typeResolver = typeResolver;

  final IResourceRevisionRepository _revisions;
  final Future<ResourceType?> Function(ResourceId resourceId)? _typeResolver;

  @override
  Future<ResourceAssemblySnapshot?> readSnapshot({
    required ResourceId resourceId,
    required ResourceRevisionId revisionId,
  }) async {
    final revision = await _revisions.readRevision(revisionId);
    if (revision == null || revision.resourceId != resourceId) return null;
    try {
      final result = await build(
        resourceId: resourceId,
        revisionId: revisionId,
      );
      return result.snapshot;
    } on ResourceAssemblyException {
      return null;
    }
  }

  /// Assembles [revisionId] into runtime output.
  ///
  /// [expectedContentHash] (when provided) must match the revision's stored
  /// hash; a mismatch means the caller captured a head that no longer
  /// corresponds to what is on disk and the build is refused.
  Future<ResourceAssemblyBuildResult> build({
    required ResourceId resourceId,
    required ResourceRevisionId revisionId,
    String expectedContentHash = '',
  }) async {
    final revision = await _revisions.readRevision(revisionId);
    if (revision == null) {
      throw ResourceAssemblyException('revision 不存在：${revisionId.value}');
    }
    if (revision.resourceId != resourceId) {
      throw ResourceAssemblyException(
        'revision ${revisionId.value} 不属于资源 ${resourceId.value}',
      );
    }
    if (expectedContentHash.isNotEmpty &&
        expectedContentHash != revision.contentHash) {
      throw ResourceAssemblyException(
        'revision ${revisionId.value} 内容哈希不一致（期望 $expectedContentHash，'
        '实际 ${revision.contentHash}），拒绝组装',
      );
    }

    final state = await _revisions.readState(revisionId);
    if (state.contentHash != revision.contentHash) {
      throw ResourceAssemblyException(
        'revision ${revisionId.value} 状态重建哈希校验失败，数据可能已损坏',
      );
    }

    final tree = await _treeFromState(resourceId, state);
    tree.validate();

    final fragments = _fragments(tree);
    final snapshot = ResourceAssemblySnapshot(
      resourceId: resourceId,
      revisionId: revisionId,
      readiness: ReadinessState.ready,
      contentHash: revision.contentHash,
      fragments: fragments,
    );

    final view = _CanonFilteredView(tree);
    switch (tree.resource.type) {
      case ResourceType.worldview:
        final payload = _worldviewPayload(view, revision.contentHash);
        return ResourceAssemblyBuildResult(
          snapshot: snapshot,
          resourceType: tree.resource.type,
          worldviewPayload: payload,
          indexDocs: _indexDocs(resourceId, revisionId, payload),
        );
      case ResourceType.character:
      case ResourceType.npc:
        return ResourceAssemblyBuildResult(
          snapshot: snapshot,
          resourceType: tree.resource.type,
          cardRow: view.toCardRow(mode: 'adventure'),
        );
    }
  }

  /// Canonical-order fragments of the whole tree.
  /// Reconstructs the frozen tree from the revision state, resolving the
  /// resource type through metadata first and the injected type resolver
  /// second (see the class-level type resolution note).
  Future<ResourceTree> _treeFromState(
    ResourceId resourceId,
    ResourceRevisionState state,
  ) async {
    final root = state.nodes.values
        .where((node) => node.kind == RevisionNodeKind.resource)
        .firstOrNull;
    if (root == null) {
      throw ResourceAssemblyException(
        'revision ${state.revisionId.value} 没有资源根节点，无法组装',
      );
    }

    ResourceType? type;
    final metadataType = root.metadata['type']?.toString();
    if (metadataType != null && metadataType.isNotEmpty) {
      type = ResourceType.fromStorageValue(metadataType);
    } else {
      type = await _typeResolver?.call(resourceId);
    }
    if (type == null) {
      throw ResourceAssemblyException(
        '无法确定资源 ${resourceId.value} 的类型，拒绝组装',
      );
    }

    final resource = Resource(
      id: ResourceId(root.nodeId),
      type: type,
      name: root.title,
      summary: root.summary,
      metadata: root.metadata,
      status: root.status,
    );
    final sections = state.nodes.values
        .where((node) =>
            node.kind == RevisionNodeKind.section &&
            node.parentNodeId == root.nodeId)
        .map((node) => ResourceSection(
              id: SectionId(node.nodeId),
              resourceId: resource.id,
              title: node.title,
              summary: node.summary,
              sortOrder: node.sortOrder,
              status: node.status,
            ))
        .toList();
    final parts = state.nodes.values
        .where((node) => node.kind == RevisionNodeKind.part)
        .map((node) => ResourcePart(
              id: PartId(node.nodeId),
              sectionId: SectionId(node.parentNodeId),
              title: node.title,
              content: node.content,
              sortOrder: node.sortOrder,
              status: node.status,
              contentHash: node.contentHash,
            ))
        .toList();
    return ResourceTree(
      resource: resource,
      sections: sections,
      parts: parts,
    );
  }

  static List<ResourceAssemblyFragment> _fragments(ResourceTree tree) {
    final fragments = <ResourceAssemblyFragment>[];
    for (final section in tree.orderedSections) {
      if (section.status == NodeStatus.archived) continue;
      final sectionText = tree
          .orderedPartsOf(section.id)
          .where((part) => part.status != NodeStatus.archived)
          // A confirmed section must not promote an unconfirmed child to canon.
          .where((part) =>
              section.status != NodeStatus.confirmed ||
              part.status == NodeStatus.confirmed)
          .map((part) => part.content.trim())
          .where((text) => text.isNotEmpty)
          .join('\n');
      if (sectionText.isNotEmpty) {
        fragments.add(ResourceAssemblyFragment(
          sourceNodeId: section.id,
          text: sectionText,
          sortOrder: section.sortOrder,
          isCanon: section.status == NodeStatus.confirmed,
        ));
      }
      for (final part in tree.orderedPartsOf(section.id)) {
        if (part.status == NodeStatus.archived) continue;
        final text = part.content.trim();
        if (text.isEmpty) continue;
        fragments.add(ResourceAssemblyFragment(
          sourceNodeId: part.id,
          text: text,
          sortOrder: part.sortOrder,
          isCanon: part.status == NodeStatus.confirmed,
        ));
      }
    }
    return List.unmodifiable(fragments);
  }

  /// Snapshot payload shaped like [WorldviewSnapshotService.snapshot], but the
  /// `content_hash` is the *revision* hash so that world entries, embeddings
  /// and the Adventure binding all point at the same version.
  Map<String, dynamic> _worldviewPayload(
    _CanonFilteredView view,
    String contentHash,
  ) {
    final row = view.toWorldviewRow(mode: 'adventure');
    Map<String, dynamic>? details;
    final raw = row['detail_json'];
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) details = decoded;
      } on FormatException {
        throw const ResourceAssemblyException('worldview detail_json 解析失败');
      }
    }
    return <String, dynamic>{
      'source_id': row['id'],
      'name': row['name'],
      'description': row['description'],
      'format_version': WorldviewDetails.currentFormatVersion,
      'detail_json': details ?? const <String, dynamic>{},
      'created_at': DateTime.now().toIso8601String(),
      'content_hash': contentHash,
      'source_revision_bound': true,
    };
  }

  /// Index documents derived deterministically from the frozen payload with
  /// the same rules Adventure creation uses, so the persisted index and the
  /// runtime entries can never disagree.
  List<AssemblyIndexDoc> _indexDocs(
    ResourceId resourceId,
    ResourceRevisionId revisionId,
    Map<String, dynamic> payload,
  ) {
    final entries = WorldviewSnapshotService.buildManagedEntries(
      0,
      payload,
      sourceRevisionId: revisionId.value,
    );
    var i = 0;
    return entries
        .map((entry) => AssemblyIndexDoc(
              docId: 'asmd_${revisionId.value}_${i++}',
              keys: List<String>.unmodifiable(entry.keys),
              content: entry.content,
              insertionOrder: entry.insertionOrder,
              sticky: entry.sticky,
            ))
        .toList(growable: false);
  }
}

/// A read-only projection wrapper that removes archived content before the
/// legacy row shapes are produced, so archived nodes can never leak into a
/// runtime payload.
class _CanonFilteredView {
  _CanonFilteredView(ResourceTree sourceTree)
      : tree = _withoutArchived(sourceTree);

  final ResourceTree tree;

  Map<String, Object?> toWorldviewRow({required String mode}) =>
      ResourceAdventureView(ResourceTree(
        resource: tree.resource,
        sections: tree.sections,
        // Module status reflects the section, so filter each frozen part
        // before projection can merge its text into a confirmed module.
        parts: tree.parts
            .where((part) => part.status == NodeStatus.confirmed)
            .toList(),
      )).toWorldviewRow(mode: mode);

  Map<String, Object?> toCardRow({required String mode}) =>
      ResourceAdventureView(tree).toCardRow(mode: mode);

  static ResourceTree _withoutArchived(ResourceTree tree) {
    final archivedSections = tree.sections
        .where((section) => section.status == NodeStatus.archived)
        .map((section) => section.id.value)
        .toSet();
    final sections = tree.sections
        .where((section) => !archivedSections.contains(section.id.value))
        .toList();
    final parts = tree.parts
        .where((part) =>
            !archivedSections.contains(part.sectionId.value) &&
            part.status != NodeStatus.archived)
        .toList();
    if (sections.length == tree.sections.length &&
        parts.length == tree.parts.length) {
      return tree;
    }
    return ResourceTree(
      resource: tree.resource,
      sections: sections,
      parts: parts,
    );
  }
}
