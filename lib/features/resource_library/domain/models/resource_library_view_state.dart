import '../../../../../domain/resources/resource_contracts.dart';

enum ResourceLibraryStatus { loading, ready, error }

enum ResourceLibraryFilter { all, worldview, character, npc }

enum ResourceDisplayStatus {
  generating,
  saved,
  optimizationSuggested,
  optimizing,
  ready,
  optimizationFailed,
}

extension ResourceDisplayStatusLabel on ResourceDisplayStatus {
  String get label => switch (this) {
        ResourceDisplayStatus.generating => '生成中',
        ResourceDisplayStatus.saved => '已保存',
        ResourceDisplayStatus.optimizationSuggested => '建议优化',
        ResourceDisplayStatus.optimizing => '正在优化',
        ResourceDisplayStatus.ready => '已准备完成',
        ResourceDisplayStatus.optimizationFailed => '优化失败',
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

  String get typeLabel => switch (type) {
        ResourceType.worldview => '世界观',
        ResourceType.character => '角色',
        ResourceType.npc => 'NPC',
      };
}

final class ResourceLibraryViewState {
  const ResourceLibraryViewState({
    required this.status,
    this.items = const <ResourceLibraryItem>[],
    this.query = '',
    this.filter = ResourceLibraryFilter.all,
    this.errorMessage = '',
  });

  const ResourceLibraryViewState.loading()
      : this(status: ResourceLibraryStatus.loading);

  final ResourceLibraryStatus status;
  final List<ResourceLibraryItem> items;
  final String query;
  final ResourceLibraryFilter filter;
  final String errorMessage;

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
    String? errorMessage,
  }) =>
      ResourceLibraryViewState(
        status: status ?? this.status,
        items: items ?? this.items,
        query: query ?? this.query,
        filter: filter ?? this.filter,
        errorMessage: errorMessage ?? this.errorMessage,
      );
}
