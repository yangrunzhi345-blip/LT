import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../domain/resources/resource_contracts.dart';
import '../../models/adventure_config.dart';
import '../resources/assembly_readiness_coordinator.dart';
import '../resources/resource_assembly_builder.dart';
import '../resources/resource_revision_repository.dart';
import '../resources/resource_revision_service.dart';
import '../../services/repositories/resource_tree_repository_impl.dart';
import '../../domain/resources/resource_revision.dart';

/// Gate status of one asset referenced by an Adventure (Phase 10).
enum AdventureAssetGateStatus {
  /// A ready assembly revision matching the latest head exists.
  ready,

  /// Preparation is running (or waiting for compression).
  preparing,

  /// The last preparation failed.
  failed,

  /// No assembly revision has ever been published.
  noReadyRevision,

  /// The resource changed after the last ready assembly; the previous ready
  /// revision still exists and may be chosen explicitly.
  staleWithPreviousReady,

  /// The id does not resolve to a unified content-tree resource (a pure
  /// legacy asset). Legacy projection convergence belongs to Phase 11, so
  /// such assets are not gated here.
  notManaged;

  bool get blocksStart =>
      this == preparing ||
      this == failed ||
      this == noReadyRevision ||
      this == staleWithPreviousReady;
}

/// UI-facing readiness of one asset, with a Chinese message for every branch.
final class AdventureAssetReadiness {
  const AdventureAssetReadiness({
    required this.assetId,
    required this.status,
    required this.message,
    this.assemblyRevisionId = '',
    this.assemblyContentHash = '',
  });

  final String assetId;
  final AdventureAssetGateStatus status;
  final String message;

  /// The consumable (or previously ready) assembly revision, when one exists.
  final String assemblyRevisionId;
  final String assemblyContentHash;

  bool get isManaged => status != AdventureAssetGateStatus.notManaged;
}

/// Interface of the Adventure start-boundary gate. Exists so UI/test layers
/// can substitute the production gate without touching SQLite.
abstract interface class IAdventureReadinessGate {
  Future<AssemblyPrepareOutcome> prepare(String assetId);

  Future<Map<String, AdventureAssetReadiness>> resolve(
    Iterable<String> assetIds,
  );

  Future<Map<String, AdventureAssetReadiness>> resolveConfig(
    AdventureConfig config,
  );

  Future<AdventureConfig> enforceAndFreeze(AdventureConfig config);
}

/// Thrown when an Adventure must not start (fail closed).
///
/// [messages] are user-presentable Chinese reasons, one per blocked asset.
class AdventureReadinessGateException implements Exception {
  AdventureReadinessGateException(this.messages);

  final List<String> messages;

  @override
  String toString() => messages.join('；');
}

/// Resolves per-asset assembly readiness and freezes the adopted resource
/// versions into an [AdventureConfig] before creation (Phase 10).
///
/// Fail-closed rules:
/// - a managed resource without a ready assembly blocks the start;
/// - a stale resource blocks the start unless the user explicitly bound the
///   previous ready revision via `AdventureResourceBinding(staleAllowed: true)`;
/// - runtime payloads (worldview snapshot, character card JSON, NPC JSON) are
///   rebuilt **from the frozen assembly revision**, so the created Adventure
///   never depends on the mutable live tree again.
final class AdventureReadinessGate implements IAdventureReadinessGate {
  AdventureReadinessGate({
    required Future<Database> Function() getDb,
    required ResourceTreeRepositoryImpl treeRepository,
    required IResourceRevisionRepository revisionRepository,
    required ResourceRevisionService revisionService,
    required AssemblyReadinessCoordinator coordinator,
    required ResourceAssemblyBuilder builder,
  })  : _tree = treeRepository,
        _revisions = revisionRepository,
        _revisionService = revisionService,
        _coordinator = coordinator,
        _builder = builder;

  final ResourceTreeRepositoryImpl _tree;
  final IResourceRevisionRepository _revisions;
  final ResourceRevisionService _revisionService;
  final AssemblyReadinessCoordinator _coordinator;
  final ResourceAssemblyBuilder _builder;

  /// Prepares the resource's current head (used by the Wizard's retry /
  /// wait-for-preparation action).
  @override
  Future<AssemblyPrepareOutcome> prepare(String assetId) =>
      _coordinator.prepare(ResourceId(assetId));

  /// Resolves the gate status of every [assetId].
  @override
  Future<Map<String, AdventureAssetReadiness>> resolve(
    Iterable<String> assetIds,
  ) async {
    final result = <String, AdventureAssetReadiness>{};
    for (final id in assetIds) {
      result[id] = await _resolveOne(id);
    }
    return result;
  }

  /// Resolves the gate status of every managed resource referenced by
  /// [config] (worldview source, selected characters, NPC snapshots).
  @override
  Future<Map<String, AdventureAssetReadiness>> resolveConfig(
    AdventureConfig config,
  ) =>
      resolve(_referencedResourceIds(config));

  Future<AdventureAssetReadiness> _resolveOne(String assetId) async {
    final resource = await _tree.findResource(ResourceId(assetId));
    if (resource == null) {
      return AdventureAssetReadiness(
        assetId: assetId,
        status: AdventureAssetGateStatus.notManaged,
        message: '该资源不属于统一资源库，不参与版本就绪检查',
      );
    }

    final head = await _revisions.readHead(
      resource.id,
      ResourceRevisionKind.latestHead,
    );
    if (head == null) {
      return AdventureAssetReadiness(
        assetId: assetId,
        status: AdventureAssetGateStatus.noReadyRevision,
        message: '「${resource.name}」还没有已保存的版本，无法开始冒险',
      );
    }

    // Reconciles ready → stale when the head has moved on.
    final record = await _coordinator.refresh(resource.id);
    if (record == null) {
      return AdventureAssetReadiness(
        assetId: assetId,
        status: AdventureAssetGateStatus.noReadyRevision,
        message: '「${resource.name}」尚未进行组装准备，尚无可用版本，请先完成资源准备',
      );
    }
    final assemblyHead = await _revisions.readHead(
      resource.id,
      ResourceRevisionKind.assembly,
    );

    switch (record.state) {
      case ReadinessState.preparing:
        return AdventureAssetReadiness(
          assetId: assetId,
          status: AdventureAssetGateStatus.preparing,
          message: record.validationMessage.isNotEmpty
              ? '「${resource.name}」准备中：${record.validationMessage}'
              : '「${resource.name}」正在组装准备，请稍候',
        );
      case ReadinessState.failed:
        return AdventureAssetReadiness(
          assetId: assetId,
          status: AdventureAssetGateStatus.failed,
          message: '「${resource.name}」准备失败：'
              '${record.failureReason.isEmpty ? '未知原因' : record.failureReason}',
        );
      case ReadinessState.ready:
        final fresh = assemblyHead != null &&
            record.assemblyRevisionId == assemblyHead.revisionId.value &&
            head.contentHash == assemblyHead.contentHash;
        if (fresh) {
          return AdventureAssetReadiness(
            assetId: assetId,
            status: AdventureAssetGateStatus.ready,
            message: '「${resource.name}」已就绪',
            assemblyRevisionId: assemblyHead.revisionId.value,
            assemblyContentHash: assemblyHead.contentHash,
          );
        }
        return _staleOrNone(resource, assemblyHead);
      case ReadinessState.stale:
        return _staleOrNone(resource, assemblyHead);
    }
  }

  Future<AdventureAssetReadiness> _staleOrNone(
    Resource resource,
    ResourceRevision? assemblyHead,
  ) async {
    if (assemblyHead == null) {
      return AdventureAssetReadiness(
        assetId: resource.id.value,
        status: AdventureAssetGateStatus.noReadyRevision,
        message: '「${resource.name}」尚无可用版本，请先完成资源组装准备',
      );
    }
    return AdventureAssetReadiness(
      assetId: resource.id.value,
      status: AdventureAssetGateStatus.staleWithPreviousReady,
      message: '「${resource.name}」已修改，可使用上一个已就绪版本',
      assemblyRevisionId: assemblyHead.revisionId.value,
      assemblyContentHash: assemblyHead.contentHash,
    );
  }

  /// Validates [config] against assembly readiness and freezes every managed
  /// resource version into it.
  ///
  /// Throws [AdventureReadinessGateException] when the start must be blocked.
  /// The returned config carries fresh [AdventureConfig.resourceBindings] and
  /// revision-derived payloads, so later edits to the library cannot change
  /// the Adventure.
  @override
  Future<AdventureConfig> enforceAndFreeze(AdventureConfig config) async {
    final referenced = _referencedResourceIds(config);
    final statuses = await resolve(referenced);

    final blocked = <String>[];
    for (final entry in statuses.entries) {
      final readiness = entry.value;
      if (!readiness.status.blocksStart) continue;
      if (readiness.status == AdventureAssetGateStatus.staleWithPreviousReady &&
          _explicitlyAllowed(config, entry.key, readiness.assemblyRevisionId)) {
        continue;
      }
      blocked.add(readiness.message);
    }
    if (blocked.isNotEmpty) {
      throw AdventureReadinessGateException(blocked);
    }

    // Freeze: rebuild every managed payload from the assembly revision.
    var frozen = config;
    final bindings = <AdventureResourceBinding>[];
    for (final entry in statuses.entries) {
      final readiness = entry.value;
      if (!readiness.isManaged) continue;
      if (readiness.assemblyRevisionId.isEmpty) continue;

      final resourceId = ResourceId(entry.key);
      final build = await _builder.build(
        resourceId: resourceId,
        revisionId: ResourceRevisionId(readiness.assemblyRevisionId),
        expectedContentHash: readiness.assemblyContentHash,
      );

      switch (build.resourceType) {
        case ResourceType.worldview:
          if (build.worldviewPayload != null) {
            frozen = frozen.copyWith(
              worldviewSnapshot: build.worldviewPayload,
            );
          }
        case ResourceType.character:
          final cardJson = _decodeCardJson(build.cardRow);
          if (cardJson != null) {
            frozen = frozen.copyWith(
              selectedCharacters: frozen.selectedCharacters
                  .map((selected) => selected.characterId == entry.key
                      ? selected.copyWith(characterCardJson: cardJson)
                      : selected)
                  .toList(),
            );
          }
          break;
        case ResourceType.npc:
          final npcJson = _decodeCardJson(build.cardRow);
          if (npcJson != null) {
            frozen = frozen.copyWith(
              npcSnapshots: frozen.npcSnapshots
                  .map((snapshot) => snapshot.assetId == entry.key
                      ? AdventureNpcSnapshot(
                          assetId: snapshot.assetId,
                          name: snapshot.name,
                          originWorldviewId: snapshot.originWorldviewId,
                          npcJson: npcJson,
                        )
                      : snapshot)
                  .toList(),
            );
          }
          break;
      }

      final previous = config.resourceBindings.where(
        (binding) => binding.resourceId == entry.key,
      );
      bindings.add(AdventureResourceBinding(
        resourceId: entry.key,
        revisionId: readiness.assemblyRevisionId,
        contentHash: readiness.assemblyContentHash,
        staleAllowed: previous.isNotEmpty &&
            previous.first.staleAllowed &&
            previous.first.revisionId == readiness.assemblyRevisionId,
      ));
    }

    return frozen.copyWith(resourceBindings: bindings);
  }

  /// every managed resource id referenced by [config], in a stable order.
  List<String> _referencedResourceIds(AdventureConfig config) {
    final ids = <String>[];
    final worldviewId =
        config.worldviewSnapshot?['source_id']?.toString() ?? '';
    if (worldviewId.isNotEmpty) ids.add(worldviewId);
    for (final selected in config.selectedCharacters) {
      final id = selected.characterId.trim();
      if (id.isNotEmpty && !ids.contains(id)) ids.add(id);
    }
    for (final npc in config.npcSnapshots) {
      final id = npc.assetId.trim();
      if (id.isNotEmpty && !ids.contains(id)) ids.add(id);
    }
    return ids;
  }

  bool _explicitlyAllowed(
          AdventureConfig config, String resourceId, String revisionId) =>
      config.resourceBindings.any((binding) =>
          binding.resourceId == resourceId &&
          binding.staleAllowed &&
          binding.revisionId == revisionId);

  Map<String, dynamic>? _decodeCardJson(Map<String, Object?>? cardRow) {
    final raw = cardRow?['json_data'];
    if (raw is! String || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      return null;
    }
    return null;
  }

  /// Exposed for the production wiring test: the whole chain must be
  /// constructible from the same repositories the app uses.
  ResourceRevisionService get revisionService => _revisionService;
}
