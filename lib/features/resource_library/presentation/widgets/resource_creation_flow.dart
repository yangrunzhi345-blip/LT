import '../../../../../domain/resources/resource_contracts.dart';

/// 手动资源创建草稿数据模型
final class ManualResourceDraft {
  const ManualResourceDraft({
    required this.type,
    required this.name,
    required this.summary,
  });

  final ResourceType type;
  final String name;
  final String summary;
}

/// 资源类型国际化/展示标签映射
String resourceTypeLabel(ResourceType type) => switch (type) {
      ResourceType.worldview => '世界观',
      ResourceType.character => '角色',
      ResourceType.npc => 'NPC',
    };
