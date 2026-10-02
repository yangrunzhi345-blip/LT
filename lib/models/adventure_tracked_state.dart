import 'package:equatable/equatable.dart';

import 'adventure_runtime_state.dart';
import 'tracked_state_definition.dart';

/// Stable, adventure-local entity ids for runtime identity.
///
/// The runtime layer keys every overlay on `(entityType, entityId)`. Characters
/// derive their id from [AdventureCharacterIdentity.effectiveId]; the single
/// world entity uses the constant below so prompt, repository and UI never
/// invent three different world ids.
final class AdventureRuntimeEntityIds {
  const AdventureRuntimeEntityIds._();

  static const String world = 'world';
}

/// A [TrackedStateDefinition] bound to the entity it belongs to inside one
/// adventure.
///
/// The definition itself knows *what* to monitor; the binding knows *whose* it
/// is. Keeping them separate is what lets a character, an NPC and the world all
/// share one definition codec/editor/validator. Identity is always the stable
/// `entityId`, never the display name, so two characters called 艾莉丝 with ids
/// `alice-a` / `alice-b` can never share state.
final class AdventureTrackedStateDefinition with Equatable {
  final RuntimeEntityType entityType;
  final String entityId;
  final TrackedStateDefinition definition;

  const AdventureTrackedStateDefinition({
    required this.entityType,
    required this.entityId,
    required this.definition,
  });

  /// Dedupe / lookup key: stable identity triple, never the display name.
  String get key => '${entityType.name}:$entityId:${definition.effectiveId}';

  String get definitionId => definition.effectiveId;

  @override
  List<Object?> get props => [entityType, entityId, definition];

  AdventureTrackedStateDefinition copyWith({
    RuntimeEntityType? entityType,
    String? entityId,
    TrackedStateDefinition? definition,
  }) =>
      AdventureTrackedStateDefinition(
        entityType: entityType ?? this.entityType,
        entityId: entityId ?? this.entityId,
        definition: definition ?? this.definition,
      );

  Map<String, dynamic> toJson() => {
        'entity_type': entityType.name,
        'entity_id': entityId,
        'definition': definition.toJson(),
      };

  factory AdventureTrackedStateDefinition.fromJson(Map<String, dynamic> json) {
    final rawType = json['entity_type'] ?? json['entityType'];
    final entityType = RuntimeEntityType.values
            .where((candidate) => candidate.name == rawType?.toString())
            .firstOrNull ??
        RuntimeEntityType.character;
    final rawDefinition =
        json['definition'] ?? json['tracked_state_definition'];
    final definition = rawDefinition is Map
        ? TrackedStateDefinition.fromJson(
            Map<String, dynamic>.from(rawDefinition))
        : TrackedStateDefinition.fromJson(json);
    return AdventureTrackedStateDefinition(
      entityType: entityType,
      entityId: (json['entity_id'] ?? json['entityId'] ?? '').toString().trim(),
      definition: definition,
    );
  }

  /// Parses a persisted list, skipping malformed entries and de-duplicating on
  /// [key].
  static List<AdventureTrackedStateDefinition> parseList(
    Object? raw, {
    List<String>? diagnostics,
  }) {
    if (raw == null) return const [];
    if (raw is! List) {
      diagnostics?.add('adventure_tracked_state_definitions:type');
      return const [];
    }
    final result = <AdventureTrackedStateDefinition>[];
    final seen = <String>{};
    for (final item in raw) {
      if (item is! Map) {
        diagnostics?.add('adventure_tracked_state_definitions:item');
        continue;
      }
      final binding = AdventureTrackedStateDefinition.fromJson(
          Map<String, dynamic>.from(item));
      if (binding.entityId.isEmpty || binding.definition.effectiveId.isEmpty) {
        diagnostics?.add('adventure_tracked_state_definitions:invalid');
        continue;
      }
      if (!seen.add(binding.key)) {
        diagnostics?.add('adventure_tracked_state_definitions:duplicate');
        continue;
      }
      result.add(binding);
    }
    return List.unmodifiable(result);
  }
}
