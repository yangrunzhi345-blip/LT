import '../../../../../application/resources/resource_lifecycle_projection.dart';
import '../../../../../domain/resources/resource_contracts.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../presentation/resolvers/resource_presentation_resolver.dart';

enum ResourceLibraryStatus { loading, ready, error }

enum ResourceLibraryFilter { all, worldview, character, npc }

enum ResourceLibraryError { loadFailed, createFailed }

enum ResourceDisplayStatus {
  generating,
  saved,
  optimizationSuggested,
  optimizing,
  ready,
  optimizationFailed,
}

extension ResourceDisplayStatusLabel on ResourceDisplayStatus {
  String get label => localizedLabel();

  String localizedLabel([AppLocalizations? l10n]) => switch (this) {
        ResourceDisplayStatus.generating =>
          l10n?.resourceStatusGenerating ?? '生成中',
        ResourceDisplayStatus.saved => l10n?.resourceStatusSaved ?? '已保存',
        ResourceDisplayStatus.optimizationSuggested =>
          l10n?.resourceStatusOptimizationSuggested ?? '建议优化',
        ResourceDisplayStatus.optimizing =>
          l10n?.resourceStatusOptimizing ?? '正在优化',
        ResourceDisplayStatus.ready => l10n?.resourceStatusReady ?? '已准备完成',
        ResourceDisplayStatus.optimizationFailed =>
          l10n?.resourceStatusOptimizationFailed ?? '优化失败',
      };
}

final class ResourceLibraryItem {
  const ResourceLibraryItem({
    required this.id,
    required this.type,
    required this.name,
    required this.summary,
    required this.updatedAt,
    required this.status,
    required this.isStudioAvailable,
    this.isConsumable = false,
    this.lifecycleState,
  });

  final String id;
  final ResourceType type;
  final String name;
  final String summary;
  final String updatedAt;
  final ResourceDisplayStatus status;
  final bool isStudioAvailable;
  final bool isConsumable;
  final ResourceLifecycleState? lifecycleState;

  String localizedName(AppLocalizations l10n) =>
      name.trim().isEmpty ? l10n.resourceUnnamed : name;

  String get typeLabel => localizedTypeLabel();

  String localizedTypeLabel([AppLocalizations? l10n]) => switch (type) {
        ResourceType.worldview => l10n?.resourceTypeWorldview ?? '世界观',
        ResourceType.character => l10n?.resourceTypeCharacter ?? '角色',
        ResourceType.npc => l10n?.resourceTypeNpc ?? 'NPC',
      };
}

final class ResourceLibraryViewState {
  const ResourceLibraryViewState({
    required this.status,
    this.items = const <ResourceLibraryItem>[],
    this.query = '',
    this.filter = ResourceLibraryFilter.all,
    this.statusFilter = ResourceStatusFilter.all,
    this.sortOption = ResourceSortOption.updatedDesc,
    this.page = 1,
    this.pageSize = 12,
    this.error,
  });

  const ResourceLibraryViewState.loading()
      : this(status: ResourceLibraryStatus.loading);

  final ResourceLibraryStatus status;
  final List<ResourceLibraryItem> items;
  final String query;
  final ResourceLibraryFilter filter;
  final ResourceStatusFilter statusFilter;
  final ResourceSortOption sortOption;
  final int page;
  final int pageSize;
  final ResourceLibraryError? error;

  int get totalCount => visibleItems.length;
  int get totalPages => (totalCount / pageSize).ceil().clamp(1, 999999);
  int get currentPage => page.clamp(1, totalPages);

  List<ResourceLibraryItem> get pagedItems {
    final list = visibleItems;
    if (list.isEmpty) return const <ResourceLibraryItem>[];
    final start = (currentPage - 1) * pageSize;
    if (start >= list.length) return const <ResourceLibraryItem>[];
    final end = (start + pageSize).clamp(0, list.length);
    return list.sublist(start, end);
  }

  List<ResourceLibraryItem> get visibleItems {
    final normalizedQuery = query.trim().toLowerCase();
    final filtered = items.where((item) {
      final matchesFilter = switch (filter) {
        ResourceLibraryFilter.all => true,
        ResourceLibraryFilter.worldview => item.type == ResourceType.worldview,
        ResourceLibraryFilter.character => item.type == ResourceType.character,
        ResourceLibraryFilter.npc => item.type == ResourceType.npc,
      };
      if (!matchesFilter) return false;

      final matchesStatus = switch (statusFilter) {
        ResourceStatusFilter.all => true,
        ResourceStatusFilter.ready => item.isConsumable ||
            item.status == ResourceDisplayStatus.ready ||
            item.lifecycleState == ResourceLifecycleState.ready,
        ResourceStatusFilter.inProgress =>
          item.status == ResourceDisplayStatus.generating ||
              item.status == ResourceDisplayStatus.optimizing ||
              item.lifecycleState == ResourceLifecycleState.generating ||
              item.lifecycleState == ResourceLifecycleState.validating ||
              item.lifecycleState == ResourceLifecycleState.recovering ||
              item.lifecycleState == ResourceLifecycleState.planning,
        ResourceStatusFilter.draft =>
          (item.status == ResourceDisplayStatus.saved && !item.isConsumable) ||
              item.lifecycleState == ResourceLifecycleState.draft,
        ResourceStatusFilter.failed =>
          item.status == ResourceDisplayStatus.optimizationFailed ||
              item.lifecycleState == ResourceLifecycleState.failed ||
              item.lifecycleState == ResourceLifecycleState.paused,
      };
      if (!matchesStatus) return false;

      if (normalizedQuery.isEmpty) return true;
      return '${item.name}\n${item.summary}\n${item.typeLabel}'
          .toLowerCase()
          .contains(normalizedQuery);
    }).toList(growable: true);

    switch (sortOption) {
      case ResourceSortOption.updatedDesc:
        filtered.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      case ResourceSortOption.updatedAsc:
        filtered.sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
      case ResourceSortOption.nameAsc:
        filtered.sort((a, b) => a.name.compareTo(b.name));
      case ResourceSortOption.nameDesc:
        filtered.sort((a, b) => b.name.compareTo(a.name));
    }

    return List<ResourceLibraryItem>.unmodifiable(filtered);
  }

  ResourceLibraryViewState copyWith({
    ResourceLibraryStatus? status,
    List<ResourceLibraryItem>? items,
    String? query,
    ResourceLibraryFilter? filter,
    ResourceStatusFilter? statusFilter,
    ResourceSortOption? sortOption,
    int? page,
    int? pageSize,
    ResourceLibraryError? error,
    bool clearError = false,
  }) =>
      ResourceLibraryViewState(
        status: status ?? this.status,
        items: items ?? this.items,
        query: query ?? this.query,
        filter: filter ?? this.filter,
        statusFilter: statusFilter ?? this.statusFilter,
        sortOption: sortOption ?? this.sortOption,
        page: page ?? this.page,
        pageSize: pageSize ?? this.pageSize,
        error: clearError ? null : (error ?? this.error),
      );
}
