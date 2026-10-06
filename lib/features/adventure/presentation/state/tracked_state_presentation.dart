import '../../../../application/adventure/adventure_character_identity.dart';
import '../../../../application/adventure/adventure_tracked_state_registry.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../models/adventure_config.dart';
import '../../../../models/adventure_runtime_state.dart';
import '../../../../models/supporting_character.dart';
import '../../../../models/tracked_state_definition.dart';
import '../../../../models/typed_runtime_state.dart';

/// One monitored field projected for display.
///
/// [value] is the raw runtime overlay value, or `null` when the story has not
/// triggered it yet. A null value is a real, first-class state — it must never
/// be collapsed into a fabricated `0`, `false` or hidden row. The projection
/// below is deliberately the single place that makes that decision, so the HUD,
/// the Inspector, the overview panel and the runtime hub can never disagree
/// (e.g. HUD showing `18` while the hub shows「Not triggered」).
final class TrackedStateSummary {
  final TrackedStateDefinition definition;
  final Object? value;

  const TrackedStateSummary({required this.definition, required this.value});

  String get name => definition.name;

  bool get isTriggered => value != null;
}

/// The entity a session is currently focused on: a stable `(entityType, id)`
/// pair plus a display name for presentation only.
final class TrackedStateEntityRef {
  final RuntimeEntityType entityType;
  final String entityId;
  final String name;
  final bool isProtagonist;

  const TrackedStateEntityRef({
    required this.entityType,
    required this.entityId,
    required this.name,
    required this.isProtagonist,
  });

  String get key => '${entityType.name}:$entityId';
}

/// Read-only projection from frozen tracking definitions + runtime overlays to
/// the copy every state surface shows.
///
/// This is a **presentation** layer, not an authority: it has no writers and no
/// persistence. The authority chain stays
/// `Resource → AdventureConfig.trackedStateDefinitions → AdventureTrackedStateRegistry → RuntimeEntityState.overlay`,
/// and this class simply reads the last two links through the registry.
final class TrackedStatePresentation {
  const TrackedStatePresentation._();

  /// The runtime overlay for one entity, or `const {}` when it has no row yet.
  static Map<String, Object?> overlayFor(
    Iterable<RuntimeEntityState> entities,
    RuntimeEntityType entityType,
    String entityId,
  ) {
    for (final entity in entities) {
      if (entity.entityType == entityType && entity.entityId == entityId) {
        return entity.overlay;
      }
    }
    return const {};
  }

  /// The raw current value of [definition] in [overlay], looked up by the same
  /// `custom_attributes.<id>` path the settlement layer writes.
  static Object? rawValue(
    TrackedStateDefinition definition,
    Map<String, Object?> overlay,
  ) =>
      overlay[RuntimeStateChangeProposal.customAttributePath(
        definition.effectiveId,
      )];

  /// Every monitored field bound to one entity, in definition order.
  ///
  /// Definitions are read from the registry (never from `customAttributes`), so
  /// a definition with no runtime value still appears — as an untriggered
  /// summary rather than a missing row.
  static List<TrackedStateSummary> summaries({
    required AdventureConfig? config,
    required Iterable<RuntimeEntityState> entities,
    required RuntimeEntityType entityType,
    required String entityId,
    int? limit,
  }) {
    final registry = AdventureTrackedStateRegistry.fromConfig(config);
    final bindings = registry.forEntity(entityType, entityId);
    if (bindings.isEmpty) return const [];
    final overlay = overlayFor(entities, entityType, entityId);
    final result = <TrackedStateSummary>[
      for (final binding in bindings)
        TrackedStateSummary(
          definition: binding.definition,
          value: rawValue(binding.definition, overlay),
        ),
    ];
    if (limit != null && limit >= 0 && result.length > limit) {
      return List.unmodifiable(result.take(limit));
    }
    return List.unmodifiable(result);
  }

  /// Whether the current adventure carries any frozen tracking definition at
  /// all. This distinguishes "adventure has no monitored fields" (unconfigured)
  /// from "a definition exists but has not triggered yet".
  static bool hasAnyDefinition(AdventureConfig? config) =>
      AdventureTrackedStateRegistry.fromConfig(config).isNotEmpty;

  /// The localized value text for [definition]:
  /// * `null` →「Not triggered」 (never a fabricated zero)
  /// * boolean → yes / no
  /// * numeric → `18` or `18 / 100`
  /// * enum / text → the stored value verbatim
  static String valueText(
    TrackedStateDefinition definition,
    Object? value,
    AppLocalizations? l10n,
  ) {
    if (value == null) return untriggeredText(l10n);
    if (definition.valueKind == RuntimeStateValueKind.boolean) {
      return boolText(value == true || value.toString() == 'true', l10n);
    }
    if (definition.isNumeric && value is num) {
      final max = definition.maximum;
      final current = formatNumber(value);
      return max == null ? current : '$current / ${formatNumber(max)}';
    }
    return value.toString();
  }

  static String untriggeredText(AppLocalizations? l10n) =>
      l10n?.trackedStateUntriggered ?? 'Not triggered';

  static String boolText(bool value, AppLocalizations? l10n) => value
      ? (l10n?.trackedStateBoolYes ?? 'Yes')
      : (l10n?.trackedStateBoolNo ?? 'No');

  /// Integer-looking numbers render without a trailing `.0`; other numbers keep
  /// their own representation.
  static String formatNumber(num value) => value == value.truncate()
      ? value.truncate().toString()
      : value.toString();

  /// Stable display names for every roster entity, keyed by stable id. Shared
  /// with the runtime hub so no surface invents a different name.
  static Map<String, String> entityNames(AdventureConfig? config) =>
      config == null
          ? const {}
          : AdventureTrackedStateRegistry.entityDisplayNames(config);

  /// Resolves which character the session is currently following and its
  /// **stable** identity.
  ///
  /// Follows the session selection (`selectedCharacterIndex`, an index into the
  /// legacy `supportingCharacters` roster that the CharacterSwitcher and scene
  /// presence already use). The index is mapped to a stable id through
  /// [AdventureCharacterIdentity] so identity never depends on a display name.
  /// Anything out of range falls back to the protagonist.
  static TrackedStateEntityRef resolveSelectedCharacter({
    required AdventureConfig? config,
    required int selectedCharacterIndex,
    String fallbackProtagonistName = '',
  }) {
    final names = entityNames(config);
    if (config == null) {
      return TrackedStateEntityRef(
        entityType: RuntimeEntityType.character,
        entityId: 'protagonist',
        name: fallbackProtagonistName,
        isProtagonist: true,
      );
    }

    final characters = config.supportingCharacters;
    if (selectedCharacterIndex >= 0 &&
        selectedCharacterIndex < characters.length) {
      final supporting = characters[selectedCharacterIndex];
      final id = _stableIdForSupporting(config, supporting);
      final known = names[id]?.trim();
      return TrackedStateEntityRef(
        entityType: RuntimeEntityType.character,
        entityId: id,
        name: (known != null && known.isNotEmpty)
            ? known
            : supporting.name.trim(),
        isProtagonist: false,
      );
    }

    final protagonistId =
        AdventureTrackedStateRegistry.protagonistEntityId(config);
    final known = names[protagonistId]?.trim();
    final fallback = config.name.trim().isNotEmpty
        ? config.name.trim()
        : fallbackProtagonistName;
    return TrackedStateEntityRef(
      entityType: RuntimeEntityType.character,
      entityId: protagonistId,
      name: (known != null && known.isNotEmpty) ? known : fallback,
      isProtagonist: true,
    );
  }

  /// Maps a legacy supporting row to the stable roster id when possible, so a
  /// character selected through the switcher reads the same overlay the
  /// assembly/seeding path keyed it on.
  static String _stableIdForSupporting(
    AdventureConfig config,
    SupportingCharacter supporting,
  ) {
    final legacyId = supporting.id.trim();
    if (legacyId.isEmpty) return legacyId;
    for (final selected in config.selectedCharacters) {
      if (AdventureCharacterIdentity.candidateIds(selected)
          .contains(legacyId)) {
        final effective = AdventureCharacterIdentity.effectiveId(selected);
        if (effective.isNotEmpty) return effective;
      }
    }
    return legacyId;
  }
}
