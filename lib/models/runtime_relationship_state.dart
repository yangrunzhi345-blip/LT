import 'adventure_config.dart';
import 'adventure_runtime_state.dart';

/// The effective value of one frozen Adventure relationship.
///
/// [snapshot] remains immutable. [runtimeEntity] is the branch-local typed
/// overlay, if one exists. Keeping both values together makes it impossible
/// for a prompt or inspector to accidentally treat a runtime value as the
/// resource authority.
final class RuntimeRelationshipState {
  final AdventureCharacterRelationship snapshot;
  final RuntimeEntityState? runtimeEntity;
  final int runtimeRevision;
  final String effectiveRelation;
  final num? effectiveStrength;
  final String effectiveNotes;

  const RuntimeRelationshipState({
    required this.snapshot,
    required this.runtimeEntity,
    required this.runtimeRevision,
    required this.effectiveRelation,
    required this.effectiveStrength,
    required this.effectiveNotes,
  });

  String get relationshipId => snapshot.id;
  String get sourceCharacterId => snapshot.sourceCharacterId;
  String get targetCharacterId => snapshot.targetCharacterId;
  String get baselineRelation => snapshot.effectiveRelation;
  bool get hasRuntimeOverlay => runtimeEntity?.overlay.isNotEmpty == true;
  bool get isChanged =>
      hasRuntimeOverlay &&
      (effectiveRelation != baselineRelation ||
          effectiveNotes != snapshot.description ||
          effectiveStrength != null);

  Map<String, Object?> toDiagnostics({String? selectionReason}) => {
        'relationship_id': relationshipId,
        'source_character_id': sourceCharacterId,
        'target_character_id': targetCharacterId,
        'baseline_relation': baselineRelation,
        'effective_relation': effectiveRelation,
        if (effectiveStrength != null) 'effective_strength': effectiveStrength,
        'runtime_revision': runtimeRevision,
        'runtime_changed': isChanged,
        if (selectionReason != null) 'selection_reason': selectionReason,
      };

  RuntimeRelationshipState copyWith({
    String? effectiveRelation,
    num? effectiveStrength,
    String? effectiveNotes,
  }) =>
      RuntimeRelationshipState(
        snapshot: snapshot,
        runtimeEntity: runtimeEntity,
        runtimeRevision: runtimeRevision,
        effectiveRelation: effectiveRelation ?? this.effectiveRelation,
        effectiveStrength: effectiveStrength ?? this.effectiveStrength,
        effectiveNotes: effectiveNotes ?? this.effectiveNotes,
      );
}

/// Projects an Adventure snapshot and existing typed runtime entities into a
/// branch-local relationship view. This is a pure read projection; it never
/// reads or writes the resource relationship repository.
final class RuntimeRelationshipProjection {
  const RuntimeRelationshipProjection._();

  static List<RuntimeRelationshipState> project({
    required Iterable<AdventureCharacterRelationship> snapshot,
    Iterable<RuntimeEntityState> runtimeEntities = const [],
    int runtimeRevision = 0,
  }) {
    final overlays = <String, RuntimeEntityState>{
      for (final entity in runtimeEntities)
        if (entity.entityType == RuntimeEntityType.relationship)
          entity.entityId: entity,
    };
    final projected = <RuntimeRelationshipState>[];
    for (final relationship in snapshot) {
      final entity = overlays[relationship.id];
      final overlay = entity?.overlay ?? const <String, Object?>{};
      final effectiveRelation = _firstText(overlay, const [
            'relationship',
            'relation_type',
            'relationship_type',
            'type',
            'status',
          ]) ??
          relationship.effectiveRelation;
      final strength = _firstNumber(overlay, const ['strength', 'affinity']);
      // An explicitly empty note clears snapshot prose; only absence falls
      // back to the frozen baseline.
      final notes = switch (overlay['notes']) {
        final String text => text,
        _ => switch (overlay['description']) {
            final String text => text,
            _ => relationship.description,
          },
      };
      projected.add(RuntimeRelationshipState(
        snapshot: relationship,
        runtimeEntity: entity,
        runtimeRevision: runtimeRevision,
        effectiveRelation: effectiveRelation,
        effectiveStrength: strength,
        effectiveNotes: notes,
      ));
    }
    projected.sort((a, b) => a.relationshipId.compareTo(b.relationshipId));
    return List.unmodifiable(projected);
  }

  static String? _firstText(Map<String, Object?> overlay, List<String> keys) {
    for (final key in keys) {
      final value = overlay[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  static num? _firstNumber(Map<String, Object?> overlay, List<String> keys) {
    for (final key in keys) {
      final value = overlay[key];
      if (value is num && value.isFinite) return value;
    }
    return null;
  }
}
