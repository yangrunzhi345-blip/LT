/// Pure, ID-based character scope rules for scene resources in adventure flows.
///
/// The policy deliberately never falls back to names. A missing selected
/// worldview therefore produces no library candidates rather than leaking the
/// whole library into a scoped flow.
class WorldviewCharacterScopePolicy {
  const WorldviewCharacterScopePolicy._();

  static String? stableId(Object? value) {
    if (value is! String && value is! num) return null;
    final id = value.toString().trim();
    return id.isEmpty ? null : id;
  }

  static Set<String> normalizedIds(Iterable<Object?> values) => {
        for (final value in values)
          if (stableId(value) case final id?) id,
      };

  static bool sceneResourceMatchesWorldview(
    Map<String, dynamic> resource,
    String? selectedWorldviewId,
  ) {
    final selectedId = stableId(selectedWorldviewId);
    if (selectedId == null) return false;
    return stableId(resource['matching_worldview_id']) == selectedId;
  }

  static List<Map<String, dynamic>> filterSceneResources(
    Iterable<Map<String, dynamic>> resources,
    String? selectedWorldviewId,
  ) =>
      resources
          .where((resource) =>
              sceneResourceMatchesWorldview(resource, selectedWorldviewId))
          .toList(growable: false);

  static Set<String> reconcileSelectedCharacterIds(
    Iterable<String> selectedIds,
    Iterable<String> allowedIds,
  ) {
    final allowed = normalizedIds(allowedIds);
    return {
      for (final id in selectedIds)
        if (stableId(id) case final normalized?)
          if (allowed.contains(normalized)) normalized,
    };
  }
}
