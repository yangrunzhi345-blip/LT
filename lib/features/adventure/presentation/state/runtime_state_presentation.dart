import '../../../../../l10n/generated/app_localizations.dart';
import '../../../../../models/adventure_runtime_state.dart';
import '../../../../../models/custom_attribute_item.dart';

/// Converts runtime protocol data into copy suitable for ordinary state UI.
/// Runtime identifiers and schema paths deliberately have no fallback here.
final class RuntimeStatePresentation {
  const RuntimeStatePresentation._();

  static String entityLabel(
    RuntimeEntityType type,
    String? knownName,
    AppLocalizations l10n,
  ) {
    final name = knownName?.trim();
    if (name != null && name.isNotEmpty) return name;
    return switch (type) {
      RuntimeEntityType.character ||
      RuntimeEntityType.npc =>
        l10n.characterStatusTitle,
      RuntimeEntityType.location ||
      RuntimeEntityType.faction ||
      RuntimeEntityType.world =>
        l10n.worldviewModuleState,
      RuntimeEntityType.relationship => l10n.runtimeStateRelationships,
    };
  }

  static String fieldLabel(String path, AppLocalizations l10n) {
    if (RuntimeStateChangeProposal.customAttributeIdFromPath(path) != null) {
      return l10n.runtimeStateChangedState;
    }
    return switch (path) {
      'hp' => l10n.runtimeStateFieldHp,
      'mp' => l10n.runtimeStateFieldMp,
      'energy' => l10n.runtimeStateFieldEnergy,
      'experience' => l10n.runtimeStateFieldExperience,
      'level' => l10n.runtimeStateFieldLevel,
      'base_atk' => l10n.runtimeStateFieldBaseAtk,
      'base_def' => l10n.runtimeStateFieldBaseDef,
      'base_speed' => l10n.runtimeStateFieldBaseSpeed,
      'affinity' => l10n.runtimeStateFieldAffinity,
      'life_status' => l10n.runtimeStateFieldLifeStatus,
      'lifecycle_status' => l10n.runtimeStateFieldLifecycleStatus,
      'global_flag' => l10n.runtimeStateFieldGlobalFlag,
      'faction_id' => l10n.runtimeStateFieldFactionId,
      'former_faction_id' => l10n.runtimeStateFieldFormerFactionId,
      'controller_id' => l10n.runtimeStateFieldControllerId,
      'relationship' => l10n.runtimeStateFieldRelationship,
      'goal' => l10n.runtimeStateFieldGoal,
      'status' => l10n.runtimeStateFieldStatus,
      'control' => l10n.runtimeStateFieldControl,
      'environment' => l10n.runtimeStateFieldEnvironment,
      'condition' => l10n.runtimeStateFieldCondition,
      'influence' => l10n.runtimeStateFieldInfluence,
      'time' => l10n.runtimeStateFieldTime,
      _ => l10n.runtimeStateFieldUnknown,
    };
  }

  static String fieldLabelWithMetadata(
    String path,
    AppLocalizations l10n, {
    Map<String, String> customAttributeLabels = const {},
  }) {
    final attributeId =
        RuntimeStateChangeProposal.customAttributeIdFromPath(path);
    final label =
        attributeId == null ? null : customAttributeLabels[attributeId];
    if (label != null && label.trim().isNotEmpty) return label.trim();
    if (attributeId != null) return l10n.runtimeStateChangedState;
    return fieldLabel(path, l10n);
  }

  static Map<String, String> customAttributeLabels(
    Iterable<CustomAttributeItem> attributes,
  ) =>
      {
        for (final attribute in attributes)
          if (attribute.id.trim().isNotEmpty &&
              attribute.name.trim().isNotEmpty)
            attribute.id: attribute.name.trim(),
      };

  static String resolveCause(String causeType, AppLocalizations l10n) =>
      switch (causeType) {
        'scene_dialogue' => l10n.runtimeStateCauseDialogue,
        'user_edit' => l10n.runtimeStateCauseUserEdit,
        'system_rule' => l10n.runtimeStateCauseSystem,
        'restore' || 'revert' => l10n.runtimeStateCauseRestore,
        'resource_import' => l10n.runtimeStateCauseImport,
        _ => l10n.runtimeStateHistoricalChange,
      };

  static String timelineTitle(int changeCount, AppLocalizations l10n) =>
      l10n.runtimeStateChangedFields(changeCount);

  static String valueLabel(
    String path,
    Object? value,
    AppLocalizations l10n,
  ) {
    if (value == null) return '—';
    if (path == 'faction_id' ||
        path == 'former_faction_id' ||
        path == 'controller_id' ||
        path == 'relationship') {
      return l10n.runtimeStateConfigured;
    }
    final text = value.toString();
    return switch (text) {
      'alive' => l10n.runtimeStateAlive,
      'dead' => l10n.runtimeStateDead,
      'active' => l10n.runtimeStateActive,
      'inactive' => l10n.runtimeStateInactive,
      'destroyed' => l10n.runtimeStateDestroyed,
      _ => text,
    };
  }

  static bool isSafeReason(String reason) {
    final text = reason.trim();
    if (text.isEmpty) return false;
    return !RegExp(
      r'(?:entity[_-]?id|commit[_-]?id|revision|cause[_-]?type|runtime[_-]?state|[a-f0-9]{16,})',
      caseSensitive: false,
    ).hasMatch(text);
  }
}
