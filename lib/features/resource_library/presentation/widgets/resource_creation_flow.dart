import '../../../../../domain/resources/resource_contracts.dart';
import '../../../../l10n/generated/app_localizations.dart';

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
String resourceTypeLabel(ResourceType type, [AppLocalizations? l10n]) =>
    switch (type) {
      ResourceType.worldview => l10n?.resourceTypeWorldview ?? '世界观',
      ResourceType.character => l10n?.resourceTypeCharacter ?? '角色',
      ResourceType.npc => l10n?.resourceTypeNpc ?? 'NPC',
    };
