import '../../../../../domain/resources/resource_contracts.dart';
import '../../../../l10n/generated/app_localizations.dart';

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
  });

  final String id;
  final ResourceType type;
  final String name;
  final String summary;
  final String updatedAt;
  final ResourceDisplayStatus status;
  final bool isStudioAvailable;

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
    this.error,
  });

  const ResourceLibraryViewState.loading()
      : this(status: ResourceLibraryStatus.loading);

  final ResourceLibraryStatus status;
  final List<ResourceLibraryItem> items;
  final String query;
  final ResourceLibraryFilter filter;
  final ResourceLibraryError? error;

  List<ResourceLibraryItem> get visibleItems {
    final normalizedQuery = query.trim().toLowerCase();
    return items.where((item) {
      final matchesFilter = switch (filter) {
        ResourceLibraryFilter.all => true,
        ResourceLibraryFilter.worldview => item.type == ResourceType.worldview,
        ResourceLibraryFilter.character => item.type == ResourceType.character,
        ResourceLibraryFilter.npc => item.type == ResourceType.npc,
      };
      if (!matchesFilter) return false;
      if (normalizedQuery.isEmpty) return true;
      return '${item.name}\n${item.summary}\n${item.typeLabel}'
          .toLowerCase()
          .contains(normalizedQuery);
    }).toList(growable: false);
  }

  ResourceLibraryViewState copyWith({
    ResourceLibraryStatus? status,
    List<ResourceLibraryItem>? items,
    String? query,
    ResourceLibraryFilter? filter,
    ResourceLibraryError? error,
    bool clearError = false,
  }) =>
      ResourceLibraryViewState(
        status: status ?? this.status,
        items: items ?? this.items,
        query: query ?? this.query,
        filter: filter ?? this.filter,
        error: clearError ? null : (error ?? this.error),
      );
}
