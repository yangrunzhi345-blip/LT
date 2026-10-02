import '../../../../domain/resources/resource_contracts.dart';
import '../../../../models/tracked_state_definition.dart';
import '../../presentation/resolvers/resource_presentation_resolver.dart';

enum CharacterStatusLibraryStatus { loading, ready, error }

/// Which owner resource types the derived Character Status surface shows.
///
/// Restricted to the two resource types that can declare monitoring
/// definitions. Worldview definitions are intentionally excluded: this is the
/// **character** status surface, and world monitors stay on the worldview.
enum CharacterStatusOwnerFilter {
  all,
  character,
  npc;

  bool matches(ResourceType type) => switch (this) {
        CharacterStatusOwnerFilter.all => true,
        CharacterStatusOwnerFilter.character => type == ResourceType.character,
        CharacterStatusOwnerFilter.npc => type == ResourceType.npc,
      };
}

/// One owner resource and the monitoring **definitions** it declares.
///
/// Definitions only: a resource never stores a current value, so nothing here
/// may be a runtime number. This is a read-only projection over the existing
/// character / NPC resource payloads — there is no second authority.
final class CharacterStatusLibraryEntry {
  const CharacterStatusLibraryEntry({
    required this.resourceId,
    required this.ownerType,
    required this.ownerName,
    required this.updatedAt,
    required this.definitions,
  });

  final String resourceId;
  final ResourceType ownerType;
  final String ownerName;
  final String updatedAt;
  final List<TrackedStateDefinition> definitions;
}

/// View state of the Character Status surface: owner-grouped, owner-paged.
///
/// Paging is per owner, never per definition, so a single character's monitors
/// are never split across pages.
final class CharacterStatusLibraryViewState {
  const CharacterStatusLibraryViewState({
    this.status = CharacterStatusLibraryStatus.loading,
    this.entries = const <CharacterStatusLibraryEntry>[],
    this.query = '',
    this.ownerFilter = CharacterStatusOwnerFilter.all,
    this.sortOption = ResourceSortOption.updatedDesc,
    this.page = 1,
    this.pageSize = 12,
  });

  final CharacterStatusLibraryStatus status;
  final List<CharacterStatusLibraryEntry> entries;
  final String query;
  final CharacterStatusOwnerFilter ownerFilter;
  final ResourceSortOption sortOption;
  final int page;
  final int pageSize;

  int get totalOwners => visibleEntries.length;
  int get totalPages => (totalOwners / pageSize).ceil().clamp(1, 999999);
  int get currentPage => page.clamp(1, totalPages);
  int get visibleDefinitionCount =>
      visibleEntries.fold(0, (sum, entry) => sum + entry.definitions.length);

  List<CharacterStatusLibraryEntry> get visibleEntries {
    final normalized = query.trim().toLowerCase();
    final filtered = entries.where((entry) {
      if (!ownerFilter.matches(entry.ownerType)) return false;
      // Owners without definitions are never shown as empty cards.
      if (entry.definitions.isEmpty) return false;
      if (normalized.isEmpty) return true;
      final haystack = <String>[
        entry.ownerName,
        for (final definition in entry.definitions) ...[
          definition.name,
          definition.description,
          definition.importance.name,
          definition.valueKind.name,
        ],
      ].join('\n').toLowerCase();
      return haystack.contains(normalized);
    }).toList(growable: true);

    switch (sortOption) {
      case ResourceSortOption.updatedDesc:
        filtered.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      case ResourceSortOption.updatedAsc:
        filtered.sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
      case ResourceSortOption.nameAsc:
        filtered.sort((a, b) => a.ownerName.compareTo(b.ownerName));
      case ResourceSortOption.nameDesc:
        filtered.sort((a, b) => b.ownerName.compareTo(a.ownerName));
    }

    return List<CharacterStatusLibraryEntry>.unmodifiable(filtered);
  }

  List<CharacterStatusLibraryEntry> get pagedEntries {
    final list = visibleEntries;
    if (list.isEmpty) return const <CharacterStatusLibraryEntry>[];
    final start = (currentPage - 1) * pageSize;
    if (start >= list.length) return const <CharacterStatusLibraryEntry>[];
    final end = (start + pageSize).clamp(0, list.length);
    return list.sublist(start, end);
  }

  CharacterStatusLibraryViewState copyWith({
    CharacterStatusLibraryStatus? status,
    List<CharacterStatusLibraryEntry>? entries,
    String? query,
    CharacterStatusOwnerFilter? ownerFilter,
    ResourceSortOption? sortOption,
    int? page,
    int? pageSize,
  }) =>
      CharacterStatusLibraryViewState(
        status: status ?? this.status,
        entries: entries ?? this.entries,
        query: query ?? this.query,
        ownerFilter: ownerFilter ?? this.ownerFilter,
        sortOption: sortOption ?? this.sortOption,
        page: page ?? this.page,
        pageSize: pageSize ?? this.pageSize,
      );
}
