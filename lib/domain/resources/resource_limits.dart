import 'resource_contracts.dart';

/// The single source of truth for resource content capacity.
///
/// Frozen in Phase 0 and consumed by every later phase: pages, prompts,
/// coordinators and business classes must read these values instead of
/// repeating the numbers, so there is exactly one place to change a budget.
///
/// Semantics (ADR-0001):
/// - `nominal` is the normal operating budget.
/// - Between `nominal` and `absolute` the resource is [CapacityStatus.elastic].
/// - Above `absolute` it is [CapacityStatus.overflow].
/// - Overflow content is still persisted in full. No capacity state authorizes
///   truncating user content; overflow only decides whether compression and a
///   new assembly revision are required.
abstract final class ResourceLimits {
  static const int worldviewNominalCharacters = 50000;
  static const int worldviewAbsoluteCharacters = 60000;

  static const int characterNominalCharacters = 5000;
  static const int characterAbsoluteCharacters = 6000;

  /// NPC cards share the character-card budget.
  static const int npcNominalCharacters = characterNominalCharacters;
  static const int npcAbsoluteCharacters = characterAbsoluteCharacters;

  /// Maximum permitted characters for a single Part prose generation.
  static const int maxPartCharacters = 8000;

  static const ResourceCapacityPolicy worldview = ResourceCapacityPolicy(
    nominalCharacters: worldviewNominalCharacters,
    absoluteCharacters: worldviewAbsoluteCharacters,
  );

  static const ResourceCapacityPolicy character = ResourceCapacityPolicy(
    nominalCharacters: characterNominalCharacters,
    absoluteCharacters: characterAbsoluteCharacters,
  );

  static const ResourceCapacityPolicy npc = ResourceCapacityPolicy(
    nominalCharacters: npcNominalCharacters,
    absoluteCharacters: npcAbsoluteCharacters,
  );

  /// The policy for [type]. Every capacity decision must go through here.
  static ResourceCapacityPolicy policyFor(ResourceType type) => switch (type) {
        ResourceType.worldview => worldview,
        ResourceType.character => character,
        ResourceType.npc => npc,
      };
}

/// Nominal/absolute character budgets for one resource type.
final class ResourceCapacityPolicy {
  const ResourceCapacityPolicy({
    required this.nominalCharacters,
    required this.absoluteCharacters,
  }) : assert(
          nominalCharacters <= absoluteCharacters,
          'nominal budget must not exceed the absolute budget',
        );

  final int nominalCharacters;
  final int absoluteCharacters;

  /// Classifies an already measured character count.
  ///
  /// Boundaries are inclusive on the lower band: exactly `nominal` is still
  /// [CapacityStatus.normal] and exactly `absolute` is still
  /// [CapacityStatus.elastic].
  CapacityStatus statusFor(int characterCount) {
    if (characterCount < 0) {
      throw ArgumentError.value(
        characterCount,
        'characterCount',
        'character count must not be negative',
      );
    }
    if (characterCount <= nominalCharacters) return CapacityStatus.normal;
    if (characterCount <= absoluteCharacters) return CapacityStatus.elastic;
    return CapacityStatus.overflow;
  }
}
