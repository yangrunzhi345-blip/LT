import '../../../../../l10n/generated/app_localizations.dart';
import '../../../../../models/adventure_config.dart';
import '../../../../../models/adventure_response.dart';
import '../../../../../models/adventure_runtime_state.dart';
import '../../../../../models/custom_attribute_item.dart';
import '../../../../../models/message.dart';
import '../../../../../models/turn_state_history.dart';

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

  static Map<String, String> resolveKnownNames({
    AdventureConfig? config,
    Iterable<AdventureSelectedCharacter> dynamicCharacters = const [],
  }) {
    final names = <String, String>{};
    if (config != null) {
      if (config.protagonistCharacter != null &&
          config.protagonistCharacter!.characterName.trim().isNotEmpty) {
        names[config.protagonistCharacter!.characterId] =
            config.protagonistCharacter!.characterName.trim();
      }
      for (final character in config.supportingCharacters) {
        if (character.name.trim().isNotEmpty) {
          names[character.id] = character.name.trim();
        }
      }
      for (final character in config.selectedCharacters) {
        if (character.characterName.trim().isNotEmpty) {
          names[character.characterId] = character.characterName.trim();
        }
      }
      for (final npc in config.npcSnapshots) {
        if (npc.name.trim().isNotEmpty) {
          names[npc.assetId] = npc.name.trim();
        }
      }
    }
    for (final character in dynamicCharacters) {
      if (character.characterName.trim().isNotEmpty) {
        names[character.characterId] = character.characterName.trim();
      }
    }
    return names;
  }

  static String resolveCause(String causeType, AppLocalizations l10n) =>
      switch (causeType) {
        'scene_dialogue' => l10n.runtimeStateCauseDialogue,
        'user_edit' => l10n.runtimeStateCauseUserEdit,
        'system_rule' => l10n.runtimeStateCauseSystem,
        'restore' || 'revert' => l10n.runtimeStateCauseRestore,
        'resource_import' => l10n.runtimeStateCauseImport,
        _ => l10n.runtimeStateHistoricalChange,
      };

  static String sourceLabel(
    String? causeType,
    RuntimeEventSource? source,
    AppLocalizations l10n,
  ) {
    if (source != null) {
      return switch (source) {
        RuntimeEventSource.userEdit => l10n.runtimeStateCauseUserEdit,
        RuntimeEventSource.aiProposal => l10n.runtimeStateCauseDialogue,
        RuntimeEventSource.systemRule => l10n.runtimeStateCauseSystem,
        RuntimeEventSource.resourceImport => l10n.runtimeStateCauseImport,
      };
    }
    if (causeType != null && causeType.isNotEmpty) {
      return resolveCause(causeType, l10n);
    }
    return l10n.runtimeStateHistoricalChange;
  }

  static String timelineTitle(int changeCount, AppLocalizations l10n) =>
      l10n.runtimeStateChangedFields(changeCount);

  static String formatDiff(
    String path,
    Object? before,
    Object? after,
    AppLocalizations l10n,
  ) {
    final beforeText = valueLabel(path, before, l10n);
    final afterText = valueLabel(path, after, l10n);
    return '$beforeText → $afterText';
  }

  static String turnSummary(
    TurnStateChangeGroup turn,
    AppLocalizations l10n, {
    Map<String, String> entityNames = const {},
  }) {
    if (!turn.hasChanges) {
      return l10n.runtimeStateNoVisibleChanges;
    }
    final labels = turnAffectedEntityLabels(
      turn,
      l10n,
      entityNames: entityNames,
    );
    if (labels.isEmpty) {
      return l10n.runtimeStateChangeCount(turn.changeCount);
    }
    if (labels.length == 1) {
      return '${labels.first} · ${l10n.runtimeStateChangeCount(turn.changeCount)}';
    }
    return '${labels.take(2).join('、')} · ${l10n.runtimeStateChangeCount(turn.changeCount)}';
  }

  static List<String> turnAffectedEntityLabels(
    TurnStateChangeGroup turn,
    AppLocalizations l10n, {
    Map<String, String> entityNames = const {},
  }) {
    final seen = <String>{};
    final result = <String>[];
    for (final change in turn.changes) {
      final label = entityLabel(
        change.entityType,
        entityNames[change.entityId],
        l10n,
      );
      if (seen.add(label)) {
        result.add(label);
      }
    }
    return result;
  }

  static final _forbiddenPattern = RegExp(
    r'(?:---\s*json\s*---|entity[_-]?id|commit[_-]?id|revision|cause[_-]?type|runtime[_-]?state|branch[_-]?id|request[_-]?id|attribute[_-]?id|state[_-]?path|runtime[_-]?id|res_cre_|char_internal|custom_attributes|detected_|[a-f0-9]{16,}|\b(?:select|insert|update|delete|drop|alter)\b\s+|file:///|/(?:home|tmp|usr|var)/|[a-zA-Z]:[/\\]|\bexception\b(?::|\s*)|stacktrace|\berror\b:\s*|{\s*"|\[\s*")',
    caseSensitive: false,
  );

  static String valueLabel(
    String path,
    Object? value,
    AppLocalizations l10n,
  ) {
    if (value == null) return '—';
    if (value is bool) {
      return value ? l10n.runtimeStateTrue : l10n.runtimeStateFalse;
    }
    if (path == 'faction_id' ||
        path == 'former_faction_id' ||
        path == 'controller_id' ||
        path == 'relationship') {
      return l10n.runtimeStateConfigured;
    }
    if (value is Map || value is List) {
      return l10n.runtimeStateConfigured;
    }
    final text = value.toString().trim();
    if (text.startsWith('{') || text.startsWith('[')) {
      return l10n.runtimeStateConfigured;
    }
    if (_forbiddenPattern.hasMatch(text)) {
      return l10n.runtimeStateConfigured;
    }
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
    return !_forbiddenPattern.hasMatch(text);
  }

  /// Sanitizes dialogue messages shown in turn state detail to ensure
  /// technical protocols, settlement JSON, SQL, paths, and exceptions
  /// are completely stripped while preserving narrative copy.
  static String? safeDialogueMessageText(Message message) {
    if (message.isError) return null;
    if (message.isUser) {
      final userText = message.content.trim();
      if (userText.isEmpty) return null;
      if (_forbiddenPattern.hasMatch(userText)) {
        final safeLines = userText
            .split('\n')
            .where((line) =>
                line.trim().isNotEmpty && !_forbiddenPattern.hasMatch(line))
            .join('\n')
            .trim();
        return safeLines.isEmpty ? null : safeLines;
      }
      return userText;
    }

    // Assistant message:
    // 1. Strip settlement payload and `---JSON---` section via streamingDisplayText
    var rawText =
        AdventureResponse.streamingDisplayText(message.content).trim();
    if (rawText.isEmpty) return null;

    // 2. Remove markdown json code blocks if present
    rawText = AdventureResponse.cleanJsonBlock(rawText);

    // Also strip any trailing ---JSON--- in case of format variations
    final jsonMarkerMatch =
        RegExp(r'\n?\s*---\s*json\s*---', caseSensitive: false)
            .firstMatch(rawText);
    if (jsonMarkerMatch != null) {
      rawText = rawText.substring(0, jsonMarkerMatch.start).trim();
    }

    if (rawText.isEmpty) return null;

    // 3. Process line by line to remove technical or json lines
    final lines = rawText.split('\n');
    final safeLines = <String>[];
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      // Skip raw JSON lines, objects, arrays or markdown backticks
      if (trimmed.startsWith('{') ||
          trimmed.startsWith('}') ||
          trimmed.startsWith('[') ||
          trimmed.startsWith(']') ||
          trimmed.startsWith('```')) {
        continue;
      }
      // Skip lines containing forbidden technical patterns
      if (_forbiddenPattern.hasMatch(trimmed)) {
        continue;
      }
      safeLines.add(line);
    }

    final sanitized = safeLines.join('\n').trim();
    return sanitized.isEmpty ? null : sanitized;
  }
}
