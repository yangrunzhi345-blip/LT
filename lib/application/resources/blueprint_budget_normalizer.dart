import '../../domain/resources/resource_blueprint.dart';
import '../../domain/resources/resource_limits.dart';
import 'blueprint_validator.dart';

/// Reconciles model-proposed Part budgets with the user's generation target.
///
/// This changes only planning metadata. It never truncates generated content,
/// changes the blueprint DAG, or changes resource capacity policy.
abstract final class BlueprintBudgetNormalizer {
  /// Returns [blueprint] unchanged when it is already within [targetCharacters].
  ///
  /// For an over-target plan, preserves Section/Part order and distributes the
  /// target by the model's original proportions. Largest remainders use the
  /// original Part order as a deterministic tie-breaker.
  static ResourceBlueprint normalizeToGenerationTarget(
    ResourceBlueprint blueprint, {
    required int targetCharacters,
  }) {
    final parts = blueprint.allParts;
    final total = blueprint.totalEstimatedLength;
    if (total <= targetCharacters) return blueprint;

    const minimum = BlueprintValidator.minPartEstimatedLength;
    final minimumTotal = parts.length * minimum;
    if (targetCharacters < minimumTotal) {
      throw BlueprintBudgetExceededException(
        '本次生成目标预算 ($targetCharacters 字) 无法容纳 ${parts.length} 个 Part '
        '的最小预计长度（至少 $minimumTotal 字）',
        plannedLength: total,
        budgetLimit: targetCharacters,
      );
    }
    for (final part in parts) {
      if (part.estimatedLength < minimum) {
        throw BlueprintValidationException(
          'Part [${part.id}] 预计长度必须大于等于 $minimum 字符',
          field: 'parts.estimatedLength',
        );
      }
    }

    final normalizedLengths = _allocate(
      parts.map((part) => part.estimatedLength).toList(growable: false),
      targetCharacters: targetCharacters,
      minimum: minimum,
      maximum: ResourceLimits.maxPartCharacters,
    );
    var index = 0;
    return blueprint.copyWith(
      targetCapacity: targetCharacters,
      sections: [
        for (final section in blueprint.sections)
          section.copyWith(
            parts: [
              for (final part in section.parts)
                part.copyWith(estimatedLength: normalizedLengths[index++]),
            ],
          ),
      ],
    );
  }

  static List<int> _allocate(
    List<int> original, {
    required int targetCharacters,
    required int minimum,
    required int maximum,
  }) {
    final allocation = List<int>.filled(original.length, minimum);
    var remaining = targetCharacters - (minimum * original.length);
    final weights = [for (final length in original) length - minimum];
    final active = <int>{
      for (var index = 0; index < original.length; index++)
        if (allocation[index] < maximum) index,
    };

    while (remaining > 0 && active.isNotEmpty) {
      final totalWeight =
          active.fold<int>(0, (sum, index) => sum + weights[index]);
      final ranked = active.map((index) {
        final numerator = totalWeight == 0 ? 1 : weights[index];
        final quotient = totalWeight == 0
            ? remaining ~/ active.length
            : (remaining * numerator) ~/ totalWeight;
        final remainder =
            totalWeight == 0 ? 0 : (remaining * numerator) % totalWeight;
        return (index: index, quotient: quotient, remainder: remainder);
      }).toList()
        ..sort((left, right) {
          final byRemainder = right.remainder.compareTo(left.remainder);
          return byRemainder != 0
              ? byRemainder
              : left.index.compareTo(right.index);
        });

      var assigned = 0;
      for (final item in ranked) {
        final capacity = maximum - allocation[item.index];
        final increment = item.quotient.clamp(0, capacity).toInt();
        allocation[item.index] += increment;
        assigned += increment;
      }
      remaining -= assigned;

      for (final item in ranked) {
        if (remaining == 0) break;
        if (allocation[item.index] < maximum) {
          allocation[item.index]++;
          remaining--;
        }
      }
      active.removeWhere((index) => allocation[index] >= maximum);
    }
    return allocation;
  }
}
