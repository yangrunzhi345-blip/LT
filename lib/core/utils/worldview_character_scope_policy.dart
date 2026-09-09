/// Describes a character asset's origin relative to the selected worldview.
enum CharacterWorldviewCompatibility { native, unbound, crossWorld }

/// Pure, ID-based character origin rules for resource and adventure flows.
///
/// `matching_worldview_id` is retained as a storage compatibility name. Its
/// business meaning is the character's native/origin worldview, never an
/// exclusive scope that forbids use in another worldview.
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

  static CharacterWorldviewCompatibility compatibility(
    Object? originWorldviewId,
    Object? selectedWorldviewId,
  ) {
    final originId = stableId(originWorldviewId);
    if (originId == null) return CharacterWorldviewCompatibility.unbound;
    final selectedId = stableId(selectedWorldviewId);
    return originId == selectedId
        ? CharacterWorldviewCompatibility.native
        : CharacterWorldviewCompatibility.crossWorld;
  }

  /// Returns every resource, ordered by native, unbound, then cross-world.
  static List<Map<String, dynamic>> orderByOriginCompatibility(
    Iterable<Map<String, dynamic>> resources,
    String? selectedWorldviewId,
  ) {
    final indexed = resources.indexed.toList(growable: false);
    indexed.sort((left, right) {
      final leftRank = compatibility(
        left.$2['matching_worldview_id'],
        selectedWorldviewId,
      ).index;
      final rightRank = compatibility(
        right.$2['matching_worldview_id'],
        selectedWorldviewId,
      ).index;
      final rankResult = leftRank.compareTo(rightRank);
      return rankResult != 0 ? rankResult : left.$1.compareTo(right.$1);
    });
    return indexed.map((entry) => entry.$2).toList(growable: false);
  }

  /// Compatibility wrapper for callers that still use the old "filter" name.
  ///
  /// Origin worldview is a recommendation signal, not an allow-list. Keep all
  /// resources selectable and only prioritize the ones native to the selected
  /// worldview.
  static List<Map<String, dynamic>> filterSceneResources(
    Iterable<Map<String, dynamic>> resources,
    String? selectedWorldviewId,
  ) =>
      orderByOriginCompatibility(resources, selectedWorldviewId);

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
