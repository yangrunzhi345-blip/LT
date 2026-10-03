import '../../domain/tts/stable_hash.dart';
import '../../domain/tts/tts_voices.dart';

/// Deterministic, collision-aware assignment of voices to resource ids.
///
/// The same resource id always maps to the same voice for a given voice pool
/// (stable across processes and restarts). Within one speech plan, distinct
/// speakers are nudged to distinct voices when the pool is large enough.
///
/// Gender is never used: it is not a hard constraint on a voice.
class TtsVoiceAssignment {
  const TtsVoiceAssignment();

  /// Assigns voices to every resource id, avoiding collisions within the plan.
  ///
  /// The pool order must be deterministic (catalog order), which keeps the
  /// mapping stable across runs.
  Map<String, String> assignForPlan(
    Iterable<String> resourceIds,
    List<TtsVoiceDescriptor> pool, {
    Set<String> reservedVoiceIds = const <String>{},
  }) {
    final result = <String, String>{};
    if (pool.isEmpty) return result;
    final used = <int>{
      for (var i = 0; i < pool.length; i++)
        if (reservedVoiceIds.contains(pool[i].voiceId)) i,
    };
    for (final id in resourceIds) {
      if (result.containsKey(id)) continue;
      var index = stableHash32(id) % pool.length;
      var attempts = 0;
      while (used.contains(index) && attempts < pool.length) {
        index = (index + 1) % pool.length;
        attempts++;
      }
      used.add(index);
      result[id] = pool[index].voiceId;
    }
    return result;
  }

  /// Assigns a single resource id without collision avoidance.
  String? assign(String resourceId, List<TtsVoiceDescriptor> pool) {
    if (pool.isEmpty) return null;
    return pool[stableHash32(resourceId) % pool.length].voiceId;
  }
}
