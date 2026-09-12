import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/router/app_router.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_radius.dart';
import '../../../../../core/widgets/form_sub_page_scaffold.dart';
import '../../../../../providers/chat_provider.dart';
import '../../../../../providers/riverpod_providers.dart';
import '../../../../../screens/prompt_settings_screen.dart';
import '../../../../../screens/settings_center_screen.dart';

/// 现代化场景会话顶栏
class SessionAppBar extends ConsumerWidget implements PreferredSizeWidget {
  final VoidCallback? onMenuPressed;
  final VoidCallback? onShowQuests;
  final VoidCallback? onShowInventory;
  final VoidCallback? onShowCharacterSheet;
  final VoidCallback? onShowMap;
  final VoidCallback? onShowWordCount;

  const SessionAppBar({
    super.key,
    this.onMenuPressed,
    this.onShowQuests,
    this.onShowInventory,
    this.onShowCharacterSheet,
    this.onShowMap,
    this.onShowWordCount,
  });

  static bool isCompact(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return size.width < 720 || size.shortestSide < 600;
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  Future<void> _showCustomModelDialog(
    BuildContext context,
    ChatProvider provider,
  ) async {
    final ctrl = TextEditingController();
    final result = await showFormSubPage<String>(
      context: context,
      title: '自定义模型',
      maxWidth: 600,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: const Icon(Icons.add_circle_outline,
                      size: 18, color: AppColors.accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '为 ${provider.providerType.displayName} 输入模型名称',
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: InputDecoration(
                hintText: provider.providerType.defaultModel,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                isDense: true,
              ),
              onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                  child: const Text('使用'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
    if (result != null && result.isNotEmpty) {
      provider.setModel(result);
    }
  }

  Future<void> _showModelSelectionSheet(
    BuildContext context,
    ChatProvider provider,
  ) async {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final recents = provider.settingsProvider.recentModels;
    final recommended = provider.providerType.availableModels;
    final currentModel = provider.modelName;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: scheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '选择语言模型 (${provider.providerType.displayName})',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (recents.isNotEmpty) ...[
                Text(
                  '最近使用',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                ...recents.map(
                  (m) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.history_rounded, size: 18),
                    title: Text(m),
                    trailing: m == currentModel
                        ? Icon(Icons.check_rounded,
                            color: scheme.primary, size: 18)
                        : null,
                    onTap: () {
                      provider.setModel(m);
                      Navigator.pop(ctx);
                    },
                  ),
                ),
                const Divider(),
              ],
              Text(
                '推荐模型',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              ...recommended.map(
                (m) => ListTile(
                  dense: true,
                  leading: const Icon(Icons.memory_rounded, size: 18),
                  title: Text(m),
                  trailing: m == currentModel
                      ? Icon(Icons.check_rounded,
                          color: scheme.primary, size: 18)
                      : null,
                  onTap: () {
                    provider.setModel(m);
                    Navigator.pop(ctx);
                  },
                ),
              ),
              const Divider(),
              ListTile(
                dense: true,
                leading: const Icon(Icons.add_circle_outline_rounded, size: 18),
                title: const Text('自定义模型...'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showCustomModelDialog(context, provider);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmRestartAdventure(
    BuildContext context,
    ChatProvider provider,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('确认重开冒险'),
        content: const Text('将重置当前会话与冒险进度并返回主页。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('重开'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      provider.restartAdventure();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final provider = ref.watch(chatProvider);
    final compact = isCompact(context);

    return AppBar(
      elevation: 0,
      scrolledUnderElevation: 0.5,
      backgroundColor: colorScheme.surface,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded, size: 20),
        onPressed: () => ref.read(chatProvider).navigateToAdventureHome(),
        tooltip: '返回大厅',
      ),
      titleSpacing: 0,
      title: ValueListenableBuilder<int>(
        valueListenable: provider.titleBarVersion,
        builder: (context, _, __) {
          final title =
              provider.currentTitle.isNotEmpty ? provider.currentTitle : '文字冒险';
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (provider.isStreaming) ...[
                const SizedBox(width: 8),
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(colorScheme.primary),
                  ),
                ),
              ],
            ],
          );
        },
      ),
      centerTitle: false,
      actions: [
        // 宽屏模式下可直接展示常用沉浸式入口
        if (!compact) ...[
          if (onShowMap != null)
            IconButton(
              icon: const Icon(Icons.map_outlined, size: 20),
              tooltip: '世界地图',
              onPressed: onShowMap,
            ),
          if (onShowQuests != null)
            IconButton(
              icon: const Icon(Icons.assignment_outlined, size: 20),
              tooltip: '任务清单',
              onPressed: onShowQuests,
            ),
          if (onShowInventory != null)
            IconButton(
              icon: const Icon(Icons.backpack_outlined, size: 20),
              tooltip: '背包物品',
              onPressed: onShowInventory,
            ),
        ],

        // 对话搜索按钮
        IconButton(
          icon: const Icon(Icons.search_rounded, size: 20),
          tooltip: '搜索对话',
          onPressed: () => provider.toggleSearch(),
        ),

        // 历史与侧边抽屉入口（若提供了 onMenuPressed）
        if (onMenuPressed != null)
          IconButton(
            icon: const Icon(Icons.history_rounded, size: 20),
            tooltip: '历史场景与侧栏',
            onPressed: onMenuPressed,
          ),

        // 更多沉浸式操作与系统设置
        PopupMenuButton<String>(
          tooltip: '更多选项',
          icon: const Icon(Icons.more_vert_rounded),
          onSelected: (action) {
            switch (action) {
              case 'character':
                onShowCharacterSheet?.call();
                break;
              case 'quests':
                onShowQuests?.call();
                break;
              case 'inventory':
                onShowInventory?.call();
                break;
              case 'map':
                onShowMap?.call();
                break;
              case 'word_count':
                onShowWordCount?.call();
                break;
              case 'model':
                _showModelSelectionSheet(context, provider);
                break;
              case 'prompt':
                Navigator.of(context).push(AppRouter.slide(
                  pageBuilder: (_) => const PromptSettingsScreen(),
                ));
                break;
              case 'restart':
                _confirmRestartAdventure(context, provider);
                break;
              case 'settings':
                Navigator.of(context).push(AppRouter.slide(
                  pageBuilder: (_) => const SettingsCenterScreen(),
                ));
                break;
            }
          },
          itemBuilder: (_) => [
            if (onShowCharacterSheet != null)
              const PopupMenuItem(
                value: 'character',
                child: Row(
                  children: [
                    Icon(Icons.badge_outlined, size: 18),
                    SizedBox(width: 10),
                    Text('角色状态'),
                  ],
                ),
              ),
            if (onShowQuests != null)
              const PopupMenuItem(
                value: 'quests',
                child: Row(
                  children: [
                    Icon(Icons.assignment_outlined, size: 18),
                    SizedBox(width: 10),
                    Text('任务清单'),
                  ],
                ),
              ),
            if (onShowInventory != null)
              const PopupMenuItem(
                value: 'inventory',
                child: Row(
                  children: [
                    Icon(Icons.backpack_outlined, size: 18),
                    SizedBox(width: 10),
                    Text('背包物品'),
                  ],
                ),
              ),
            if (onShowMap != null)
              const PopupMenuItem(
                value: 'map',
                child: Row(
                  children: [
                    Icon(Icons.map_outlined, size: 18),
                    SizedBox(width: 10),
                    Text('世界地图'),
                  ],
                ),
              ),
            if (onShowWordCount != null)
              const PopupMenuItem(
                value: 'word_count',
                child: Row(
                  children: [
                    Icon(Icons.format_size_rounded, size: 18),
                    SizedBox(width: 10),
                    Text('回复长度'),
                  ],
                ),
              ),
            const PopupMenuDivider(),
            const PopupMenuItem(
              value: 'model',
              child: Row(
                children: [
                  Icon(Icons.memory_rounded, size: 18),
                  SizedBox(width: 10),
                  Text('切换模型'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'prompt',
              child: Row(
                children: [
                  Icon(Icons.tune_rounded, size: 18),
                  SizedBox(width: 10),
                  Text('提示词设置'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'restart',
              child: Row(
                children: [
                  Icon(Icons.restart_alt_rounded, size: 18),
                  SizedBox(width: 10),
                  Text('重开冒险'),
                ],
              ),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem(
              value: 'settings',
              child: Row(
                children: [
                  Icon(Icons.settings_outlined, size: 18),
                  SizedBox(width: 10),
                  Text('设置中心'),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}
