import 'package:sqflite/sqflite.dart';

import '../../domain/resources/resource_contracts.dart';
import '../../models/adventure_config.dart';
import '../../models/character_card_entry.dart';
import '../../models/supporting_character.dart';
import '../resources/assembly_readiness_coordinator.dart';
import '../resources/assembly_readiness_repository.dart';
import '../resources/resource_assembly_builder.dart';
import '../resources/resource_revision_repository.dart';
import '../resources/resource_revision_service.dart';
import '../../services/repositories/resource_tree_repository_impl.dart';
import '../../domain/resources/resource_revision.dart';
import '../../domain/errors/app_error.dart';
import '../../domain/errors/diagnostic_envelope.dart';

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

/// Stable reason for a readiness result. The legacy [message] remains only
/// for reading old callers and persisted diagnostics.
enum AdventureReadinessIssueCode {
  notManaged,
  noSavedRevision,
  preparing,
  preparationFailed,
  ready,
  noAssemblyRevision,
  staleWithPreviousReady,
}

/// Typed readiness of one asset.
///
/// [message] remains only for legacy callers. New application paths leave it
/// empty and presentation maps [issueCode] and [parameters] to localizations.
final class AdventureAssetReadiness {
  const AdventureAssetReadiness({
    required this.assetId,
    required this.status,
    this.message = '',
    this.issueCode,
    this.parameters = const <String, Object?>{},
    this.assemblyRevisionId = '',
    this.assemblyContentHash = '',
  });

  final String assetId;
  final AdventureAssetGateStatus status;
  @Deprecated('Use issueCode and parameters in presentation.')
  final String message;
  final AdventureReadinessIssueCode? issueCode;
  final Map<String, Object?> parameters;

  /// The consumable (or previously ready) assembly revision, when one exists.
  final String assemblyRevisionId;
  final String assemblyContentHash;

  bool get isManaged => status != AdventureAssetGateStatus.notManaged;

  AdventureReadinessIssueCode get effectiveIssueCode =>
      issueCode ??
      switch (status) {
        AdventureAssetGateStatus.notManaged =>
          AdventureReadinessIssueCode.notManaged,
        AdventureAssetGateStatus.noReadyRevision =>
          AdventureReadinessIssueCode.noSavedRevision,
        AdventureAssetGateStatus.preparing =>
          AdventureReadinessIssueCode.preparing,
        AdventureAssetGateStatus.failed =>
          AdventureReadinessIssueCode.preparationFailed,
        AdventureAssetGateStatus.ready => AdventureReadinessIssueCode.ready,
        AdventureAssetGateStatus.staleWithPreviousReady =>
          AdventureReadinessIssueCode.staleWithPreviousReady,
      };
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
  AdventureReadinessGateException({
    this.messages = const [],
    this.issues = const [],
    this.error,
  });

  /// Legacy display strings retained for old persisted/caller compatibility.
  final List<String> messages;
  final List<AdventureAssetReadiness> issues;
  final AppDomainError? error;

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
        issueCode: AdventureReadinessIssueCode.notManaged,
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
        issueCode: AdventureReadinessIssueCode.noSavedRevision,
        parameters: {'name': resource.name},
      );
    }

    // Reconciles ready → stale when the head has moved on. A missing row is
    // legacy data (or a generation that predates the readiness hook), so use
    // the coordinator's formal prepare boundary to converge it lazily.
    final existingRecord = await _coordinator.refresh(resource.id);
    final AssemblyReadinessRecord record;
    if (existingRecord == null) {
      record = (await _coordinator.prepare(resource.id)).record;
    } else if (existingRecord.state == ReadinessState.failed &&
        _targetsDifferentHead(existingRecord, head)) {
      // Only retry failures tied to an obsolete/empty target. A failure for
      // the current head remains a real failure and is not retried forever on
      // every gate resolution.
      record = (await _coordinator.prepare(resource.id)).record;
    } else {
      record = existingRecord;
    }
    var resolvedRecord = record;
    if (resolvedRecord.state == ReadinessState.preparing) {
      // Keep the persisted state authoritative if a compression or another
      // asynchronous preparation is still in progress.
      resolvedRecord =
          await _coordinator.refresh(resource.id) ?? resolvedRecord;
    }
    final assemblyHead = await _revisions.readHead(
      resource.id,
      ResourceRevisionKind.assembly,
    );

    switch (resolvedRecord.state) {
      case ReadinessState.preparing:
        final diagnostic = DiagnosticEnvelope.tryDecode(
          resolvedRecord.validationMessage,
        );
        return AdventureAssetReadiness(
          assetId: assetId,
          status: AdventureAssetGateStatus.preparing,
          issueCode: AdventureReadinessIssueCode.preparing,
          parameters: {
            'name': resource.name,
            if (diagnostic != null) 'diagnosticCode': diagnostic.code,
            if (diagnostic != null) ...diagnostic.parameters,
            if (diagnostic == null &&
                resolvedRecord.validationMessage.isNotEmpty)
              'details': resolvedRecord.validationMessage,
          },
        );
      case ReadinessState.failed:
        final diagnostic = DiagnosticEnvelope.tryDecode(
          resolvedRecord.failureReason,
        );
        return AdventureAssetReadiness(
          assetId: assetId,
          status: AdventureAssetGateStatus.failed,
          issueCode: AdventureReadinessIssueCode.preparationFailed,
          parameters: {
            'name': resource.name,
            if (diagnostic != null) 'diagnosticCode': diagnostic.code,
            if (diagnostic != null) ...diagnostic.parameters,
            if (diagnostic == null && resolvedRecord.failureReason.isNotEmpty)
              'details': resolvedRecord.failureReason,
          },
        );
      case ReadinessState.ready:
        final fresh = assemblyHead != null &&
            resolvedRecord.assemblyRevisionId ==
                assemblyHead.revisionId.value &&
            head.contentHash == assemblyHead.contentHash;
        if (fresh) {
          return AdventureAssetReadiness(
            assetId: assetId,
            status: AdventureAssetGateStatus.ready,
            issueCode: AdventureReadinessIssueCode.ready,
            parameters: {'name': resource.name},
            assemblyRevisionId: assemblyHead.revisionId.value,
            assemblyContentHash: assemblyHead.contentHash,
          );
        }
        return _staleOrNone(resource, assemblyHead);
      case ReadinessState.stale:
        return _staleOrNone(resource, assemblyHead);
    }
  }

  bool _targetsDifferentHead(
    AssemblyReadinessRecord record,
    ResourceRevision head,
  ) =>
      record.targetRevisionId.isEmpty ||
      record.targetContentHash.isEmpty ||
      record.targetRevisionId != head.revisionId.value ||
      record.targetContentHash != head.contentHash;

  Future<AdventureAssetReadiness> _staleOrNone(
    Resource resource,
    ResourceRevision? assemblyHead,
  ) async {
    if (assemblyHead == null) {
      return AdventureAssetReadiness(
        assetId: resource.id.value,
        status: AdventureAssetGateStatus.noReadyRevision,
        issueCode: AdventureReadinessIssueCode.noAssemblyRevision,
        parameters: {'name': resource.name},
      );
    }
    return AdventureAssetReadiness(
      assetId: resource.id.value,
      status: AdventureAssetGateStatus.staleWithPreviousReady,
      issueCode: AdventureReadinessIssueCode.staleWithPreviousReady,
      parameters: {'name': resource.name},
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

    final blockedIssues = <AdventureAssetReadiness>[];
    for (final entry in statuses.entries) {
      final readiness = entry.value;
      if (!readiness.status.blocksStart) continue;
      if (readiness.status == AdventureAssetGateStatus.staleWithPreviousReady &&
          _explicitlyAllowed(config, entry.key, readiness.assemblyRevisionId)) {
        continue;
      }
      blockedIssues.add(readiness);
    }
    if (blockedIssues.isNotEmpty) {
      throw AdventureReadinessGateException(issues: blockedIssues);
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
          final card = _frozenCard(build);
          final selected = frozen.selectedCharacters
              .where((item) => item.characterId == entry.key)
              .toList();
          final supportingIds = selected.map((item) => item.id).toSet();
          final isProtagonist =
              frozen.protagonistCharacter?.characterId == entry.key;
          frozen = frozen.copyWith(
            selectedCharacters: frozen.selectedCharacters
                .map((item) => item.characterId == entry.key
                    ? item.copyWith(
                        characterName: card.name,
                        characterAvatar:
                            card.cardData['avatar']?.toString() ?? '',
                        characterCardJson: card.rawData,
                      )
                    : item)
                .toList(),
            supportingCharacters: frozen.supportingCharacters.map((item) {
              if (!supportingIds.contains(item.id) && item.id != entry.key) {
                return item;
              }
              final selection = selected
                      .where((candidate) => candidate.id == item.id)
                      .firstOrNull ??
                  selected.firstOrNull;
              // Relationship and narrative role are Adventure choices; all
              // resource-derived fields must come from this assembly alone.
              return SupportingCharacter(
                id: item.id,
                name: card.name,
                gender: card.gender,
                personality: card.personality,
                role: card.profession.isNotEmpty
                    ? card.profession
                    : selection?.effectiveRole ?? '',
                relation: item.relation,
                customAttributes: card.customAttributes,
              );
            }).toList(),
            characterCard: isProtagonist ? card.card : null,
            name: isProtagonist ? card.name : null,
            gender: isProtagonist ? card.gender : null,
            age: isProtagonist ? card.age : null,
            personality: isProtagonist ? card.personality : null,
            protagonistClass: isProtagonist
                ? (card.profession.isNotEmpty ? card.profession : '冒险者')
                : null,
            protagonistBackground: isProtagonist ? card.background : null,
          );
        case ResourceType.npc:
          final card = _frozenCard(build);
          final npc = _frozenNpc(card, entry.key);
          frozen = frozen.copyWith(
            npcSnapshots: frozen.npcSnapshots
                .map((snapshot) => snapshot.assetId == entry.key
                    ? AdventureNpcSnapshot(
                        assetId: snapshot.assetId,
                        name: card.name,
                        originWorldviewId: card.matchingWorldviewId ?? '',
                        npcJson: card.rawData,
                      )
                    : snapshot)
                .toList(),
            supportingCharacters: frozen.supportingCharacters
                .map((item) => item.id == entry.key ? npc : item)
                .toList(),
          );
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

  CharacterCardEntry _frozenCard(ResourceAssemblyBuildResult build) {
    final row = build.cardRow;
    if (row == null) {
      throw AdventureReadinessGateException(
        error: const AppDomainError(code: AppErrorCode.adventureAssetMissing),
      );
    }
    final card = CharacterCardEntry.fromRow(Map<String, dynamic>.from(row));
    if (card.hasParseError) {
      throw AdventureReadinessGateException(
        error: const AppDomainError(
          code: AppErrorCode.resourceValidationFailed,
        ),
      );
    }
    return card;
  }

  SupportingCharacter _frozenNpc(CharacterCardEntry card, String id) {
    final data = card.cardData;
    final extras = data['legacy_extra_fields'];
    // The tree projection preserves NPC-specific fields as named extra Parts.
    // Unwrap them here, without falling back to the live NPC carrier.
    final fields = <String, dynamic>{
      if (extras is Map<String, dynamic>) ...extras,
      ...data,
      'id': id,
      'name': card.name,
    };
    if (fields['affinity'] case final String value) {
      fields['affinity'] = int.parse(value);
    }
    if (fields['isAlive'] case final String value) {
      fields['isAlive'] = bool.parse(value);
    }
    return SupportingCharacter.fromJson(fields);
  }

  /// Exposed for the production wiring test: the whole chain must be
  /// constructible from the same repositories the app uses.
  ResourceRevisionService get revisionService => _revisionService;
}
