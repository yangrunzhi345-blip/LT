import '../../../../../domain/resources/resource_contracts.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../l10n/generated/app_localizations_zh.dart';

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
String resourceTypeLabel(ResourceType type, [AppLocalizations? l10n]) {
  final strings = l10n ?? AppLocalizationsZh();
  return switch (type) {
    ResourceType.worldview => strings.resourceTypeWorldview,
    ResourceType.character => strings.resourceTypeCharacter,
    ResourceType.npc => strings.resourceTypeNpc,
  };
}
