import '../../../../domain/resources/resource_contracts.dart';
import '../../../../models/tracked_state_definition.dart';
import '../../presentation/resolvers/resource_presentation_resolver.dart';

enum TrackedStateLibraryStatus { loading, ready, error }

/// Which owner resource types the derived「检测项目」surface shows.
///
/// Every resource type that can declare monitoring definitions participates:
/// character, NPC and worldview. No fourth owner type exists.
enum TrackedStateOwnerFilter {
  all,
  character,
  npc,
  worldview;

  bool matches(ResourceType type) => switch (this) {
        TrackedStateOwnerFilter.all => true,
        TrackedStateOwnerFilter.character => type == ResourceType.character,
        TrackedStateOwnerFilter.npc => type == ResourceType.npc,
        TrackedStateOwnerFilter.worldview => type == ResourceType.worldview,
      };
}

/// One owner resource and the monitoring **definitions** it declares.
///
/// Definitions only: a resource never stores a current value, so nothing here
/// may be a runtime number. This is a read-only projection over the existing
/// character / NPC / worldview resource payloads — there is no second
/// authority.
final class TrackedStateLibraryEntry {
  const TrackedStateLibraryEntry({
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

/// View state of the「检测项目」surface: owner-grouped, owner-paged.
///
/// Paging is per owner, never per definition, so a single character's monitors
/// are never split across pages.
final class TrackedStateLibraryViewState {
  const TrackedStateLibraryViewState({
    this.status = TrackedStateLibraryStatus.loading,
    this.entries = const <TrackedStateLibraryEntry>[],
    this.query = '',
    this.ownerFilter = TrackedStateOwnerFilter.all,
    this.sortOption = ResourceSortOption.updatedDesc,
    this.page = 1,
    this.pageSize = 12,
  });

  final TrackedStateLibraryStatus status;
  final List<TrackedStateLibraryEntry> entries;
  final String query;
  final TrackedStateOwnerFilter ownerFilter;
  final ResourceSortOption sortOption;
  final int page;
  final int pageSize;

  int get totalOwners => visibleEntries.length;
  int get totalPages => (totalOwners / pageSize).ceil().clamp(1, 999999);
  int get currentPage => page.clamp(1, totalPages);
  int get visibleDefinitionCount =>
      visibleEntries.fold(0, (sum, entry) => sum + entry.definitions.length);

  List<TrackedStateLibraryEntry> get visibleEntries {
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

    return List<TrackedStateLibraryEntry>.unmodifiable(filtered);
  }

  List<TrackedStateLibraryEntry> get pagedEntries {
    final list = visibleEntries;
    if (list.isEmpty) return const <TrackedStateLibraryEntry>[];
    final start = (currentPage - 1) * pageSize;
    if (start >= list.length) return const <TrackedStateLibraryEntry>[];
    final end = (start + pageSize).clamp(0, list.length);
    return list.sublist(start, end);
  }

  TrackedStateLibraryViewState copyWith({
    TrackedStateLibraryStatus? status,
    List<TrackedStateLibraryEntry>? entries,
    String? query,
    TrackedStateOwnerFilter? ownerFilter,
    ResourceSortOption? sortOption,
    int? page,
    int? pageSize,
  }) =>
      TrackedStateLibraryViewState(
        status: status ?? this.status,
        entries: entries ?? this.entries,
        query: query ?? this.query,
        ownerFilter: ownerFilter ?? this.ownerFilter,
        sortOption: sortOption ?? this.sortOption,
        page: page ?? this.page,
        pageSize: pageSize ?? this.pageSize,
      );
}
