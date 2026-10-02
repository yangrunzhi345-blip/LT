import '../../models/adventure_runtime_state.dart';
import '../../models/adventure_tracked_state.dart';
import '../../models/tracked_state_definition.dart';
import 'adventure_tracked_state_registry.dart';

/// One monitoring definition proposed to the settlement request, together with
/// the entity's **current runtime value** (or `null` when the status has never
/// been triggered).
///
/// The current value comes from the branch-local runtime overlay, never from
/// the resource definition — a resource cannot know it.
final class TrackedStateCandidate {
  final AdventureTrackedStateDefinition binding;
  final String entityName;

  /// Runtime HEAD value for this path, or `null` for an untriggered status.
  final Object? currentValue;

  const TrackedStateCandidate({
    required this.binding,
    required this.entityName,
    this.currentValue,
  });

  RuntimeEntityType get entityType => binding.entityType;
  String get entityId => binding.entityId;
  String get definitionId => binding.definitionId;
  bool get isTriggered => currentValue != null;

  /// The prompt line for this candidate.
  ///
  /// Carries both the unified `entity_type`/`entity_id`/`monitor_id` identity
  /// and the legacy `character_id`/`attribute_id` aliases, so a model that only
  /// knows the older field names echoes the correct stable identity instead of
  /// a display name.
  String get promptLine {
    final definition = binding.definition;
    final buffer =
        StringBuffer('- entity_type=${entityType.name}, entity_id=$entityId, '
            'monitor_id=$definitionId, character_id=$entityId, '
            'attribute_id=$definitionId');
    if (entityName.trim().isNotEmpty) {
      buffer.write(', 角色=${entityName.trim()}, 实体=${entityName.trim()}');
    }
    buffer.write(', 状态=${definition.name}');
    buffer.write(', 类型=${definition.valueKind.name}');
    buffer.write(', 当前=${_currentDisplay(definition)}');
    if (definition.isNumeric) {
      final min = definition.minimum;
      final max = definition.maximum;
      if (min != null || max != null) {
        buffer.write(', 范围=${_formatNumber(min ?? '-∞')}..'
            '${_formatNumber(max ?? '∞')}');
      }
    }
    if (definition.enumValues.isNotEmpty) {
      buffer.write(', 允许值=${definition.enumValues.join('/')}');
    }
    buffer.write(', 重要程度=${definition.importance.label}');
    if (!isTriggered) {
      buffer.write('（尚未触发：首次有依据时必须用 operation=set 初始化，'
          '禁止填入整齐的默认值）');
    }
    final rule = definition.description.trim();
    if (rule.isNotEmpty) {
      buffer.write('\n  检测规则=$rule');
    }
    return buffer.toString();
  }

  String _currentDisplay(TrackedStateDefinition definition) {
    if (!isTriggered) return '无';
    final value = currentValue;
    if (definition.isNumeric && value is num && definition.maximum != null) {
      return '${_formatNumber(value)}/${_formatNumber(definition.maximum!)}';
    }
    return _formatNumber(value);
  }

  static String _formatNumber(Object? value) {
    if (value is num && value == value.truncate()) {
      return value.truncate().toString();
    }
    return value.toString();
  }
}

/// Fair, non-protagonist-first candidate selection.
///
/// The old settlement path added the protagonist first and then
/// `take(maximumEvaluationsPerTurn)`, so a protagonist with many monitors could
/// starve every other character. This planner round-robins across entities, so
/// a companion with a single `critical` monitor is always represented before a
/// protagonist can consume the whole budget.
final class TrackedStateCandidatePlanner {
  const TrackedStateCandidatePlanner();

  /// Upper bound on how many candidate monitors one settlement request sees.
  /// Truncation is reported, never silent.
  static const int defaultMaximumCandidates = 48;

  List<TrackedStateCandidate> plan({
    required AdventureTrackedStateRegistry registry,
    required Iterable<RuntimeEntityState> runtimeEntities,
    required Set<String> presentEntityIds,
    Set<String> mentionedEntityIds = const {},
    Map<String, String> entityNames = const {},

    /// Legacy baseline values keyed by `entityType:entityId:definitionId`.
    ///
    /// A resource definition carries no value, but a pre-definition adventure
    /// still holds the old `custom_attributes` baseline. Falling back to it
    /// keeps the current value visible for those adventures without ever
    /// writing it back into a resource.
    Map<String, Object?> baselineValues = const {},
    int maximumCandidates = defaultMaximumCandidates,
    List<String>? diagnostics,
  }) {
    if (registry.isEmpty) return const [];

    final overlayByEntity = <String, Map<String, Object?>>{
      for (final entity in runtimeEntities)
        '${entity.entityType.name}:${entity.entityId}': entity.overlay,
    };

    final relevant = <String>{...presentEntityIds, ...mentionedEntityIds};
    final grouped = <String, List<TrackedStateCandidate>>{};

    // Stable, neutral entity order: by entity type, then id. The planner must
    // not know or care who the protagonist is.
    final entityKeys = registry.entityKeys.toList()..sort();
    for (final key in entityKeys) {
      final separator = key.indexOf(':');
      final typeName = key.substring(0, separator);
      final entityId = key.substring(separator + 1);
      final entityType = RuntimeEntityType.values
          .where((candidate) => candidate.name == typeName)
          .firstOrNull;
      if (entityType == null) continue;

      final isWorld = entityType == RuntimeEntityType.world;
      final isRelevant =
          isWorld || relevant.contains(entityId) || relevant.contains(key);
      if (!isRelevant) continue;

      final overlay = overlayByEntity[key] ?? const {};
      final definitions = registry.forEntity(entityType, entityId).toList()
        ..sort((a, b) => b.definition.importance.index
            .compareTo(a.definition.importance.index));
      if (definitions.isEmpty) continue;

      grouped[key] = [
        for (final binding in definitions)
          TrackedStateCandidate(
            binding: binding,
            entityName: entityNames[entityId] ?? '',
            currentValue: overlay[
                    RuntimeStateChangeProposal.customAttributePath(
                        binding.definitionId)] ??
                baselineValues['$typeName:$entityId:${binding.definitionId}'],
          ),
      ];
    }

    final result = <TrackedStateCandidate>[];
    final total = grouped.values.fold<int>(0, (sum, list) => sum + list.length);
    var round = 0;
    while (result.length < maximumCandidates) {
      var added = false;
      for (final candidates in grouped.values) {
        if (round >= candidates.length) continue;
        result.add(candidates[round]);
        added = true;
        if (result.length >= maximumCandidates) break;
      }
      if (!added) break;
      round++;
    }

    if (result.length < total) {
      diagnostics?.add('monitor_candidates_truncated:entities=${grouped.length}'
          ':definitions=$total:shown=${result.length}');
    }
    return List.unmodifiable(result);
  }
}
