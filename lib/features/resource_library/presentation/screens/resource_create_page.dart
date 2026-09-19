import 'package:flutter/material.dart';

import '../../../../../domain/resources/resource_contracts.dart';
import '../../../../core/theme/app_borders.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/ui_foundation.dart';
import '../../domain/models/resource_library_view_state.dart';
import '../widgets/resource_creation_flow.dart';
import 'resource_ai_create_page.dart';
import 'resource_manual_create_page.dart';

/// 资料库新建资源导航枢纽页面 [ResourceCreatePage]
///
/// 遵循 R02 导航优先设计原则，彻底替换旧版 BottomSheet 弹窗选择：
/// - 统一路由入口，支持 Deep Link
/// - 资源类型统一选择器 (AppSelect)
/// - 直观卡片式创建方式选择（AI 智能创建 / 手动空白创建）
/// - 深度适配桌面与移动端 (320px+) 响应式体验
class ResourceCreatePage extends StatefulWidget {
  const ResourceCreatePage({
    super.key,
    this.initialType = ResourceType.worldview,
    this.resources = const [],
  });

  final ResourceType initialType;
  final List<ResourceLibraryItem> resources;

  @override
  State<ResourceCreatePage> createState() => _ResourceCreatePageState();
}

class _ResourceCreatePageState extends State<ResourceCreatePage> {
  late ResourceType _selectedType;

  @override
  void initState() {
    super.initState();
    _selectedType = widget.initialType;
  }

  Future<void> _openAiCreation() async {
    final result = await Navigator.of(context).push<Object?>(
      MaterialPageRoute(
        builder: (_) => ResourceAiCreatePage(
          initialType: _selectedType,
          resources: widget.resources,
        ),
      ),
    );
    if (!mounted || result == null) return;
    Navigator.of(context).pop(result);
  }

  Future<void> _openManualCreation() async {
    final result = await Navigator.of(context).push<Object?>(
      MaterialPageRoute(
        builder: (_) => ResourceManualCreatePage(
          initialType: _selectedType,
        ),
      ),
    );
    if (!mounted || result == null) return;
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final typeItems = [
      for (final type in ResourceType.values)
        AppSelectItem<ResourceType>(
          value: type,
          label: resourceTypeLabel(type),
        ),
    ];

    return AppPageScaffold(
      title: '新建资源',
      maxWidth: 640,
      scrollable: true,
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppFormSection(
              title: '资源类型',
              description: '选择所要构建的内容载体类型',
              child: AppSelect<ResourceType>(
                key: const Key('resource-create-type-select'),
                label: '预选类型',
                value: _selectedType,
                items: typeItems,
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _selectedType = val);
                  }
                },
              ),
            ),
            const SizedBox(height: 12),
            AppFormSection(
              title: '创建方式',
              description: '根据创作需要选择由 AI 辅助推演或手动纯文本编写',
              children: [
                _buildActionCard(
                  key: const Key('create-choice-ai'),
                  icon: Icons.auto_awesome_rounded,
                  iconColor: colorScheme.primary,
                  iconBgColor:
                      colorScheme.primaryContainer.withValues(alpha: 0.5),
                  title: 'AI 创建',
                  description: '基于参考资料、小说文本或现有资产，由 AI 自动推演章节大纲与正文内容。',
                  badge: '推荐',
                  isDark: isDark,
                  onTap: _openAiCreation,
                ),
                const SizedBox(height: AppSpacing.md),
                _buildActionCard(
                  key: const Key('create-choice-manual'),
                  icon: Icons.edit_note_rounded,
                  iconColor: colorScheme.secondary,
                  iconBgColor:
                      colorScheme.secondaryContainer.withValues(alpha: 0.5),
                  title: '手动创建',
                  description: '自定义名称与简介，建立空白资源后自由编排章节与内容。',
                  isDark: isDark,
                  onTap: _openManualCreation,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionCard({
    required Key key,
    required IconData icon,
    required Color iconColor,
    required Color iconBgColor,
    required String title,
    required String description,
    String? badge,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: key,
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurface : AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppBorders.defaultColor(context)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconBgColor,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (badge != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              badge,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
