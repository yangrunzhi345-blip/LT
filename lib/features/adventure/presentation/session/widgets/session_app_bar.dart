import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/router/app_router.dart';
import '../../../../../core/widgets/app_confirm_dialog.dart';
import '../../../../../providers/chat_provider.dart';
import '../../../../../providers/riverpod_providers.dart';
import '../../../../../screens/prompt_settings_screen.dart';
import '../../../../../screens/settings_center_screen.dart';
import '../screens/model_select_page.dart';

/// 现代化场景会话顶栏
class SessionAppBar extends ConsumerWidget implements PreferredSizeWidget {
  final VoidCallback? onMenuPressed;
  final VoidCallback? onShowInventory;
  final VoidCallback? onShowCharacterSheet;
  final VoidCallback? onShowWordCount;

  const SessionAppBar({
    super.key,
    this.onMenuPressed,
    this.onShowInventory,
    this.onShowCharacterSheet,
    this.onShowWordCount,
  });

  static bool isCompact(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return size.width < 720 || size.shortestSide < 600;
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  Future<void> _showModelSelectionSheet(
    BuildContext context,
    ChatProvider provider,
  ) async {
    await AppRouter.push<ModelSelectionResult>(
      context,
      pageBuilder: (_) => const ModelSelectPage(),
    );
  }

  Future<void> _confirmRestartAdventure(
    BuildContext context,
    ChatProvider provider,
  ) async {
    final confirm = await AppConfirmDialog.show(
      context: context,
      title: '确认重开冒险',
      message: '将重置当前会话与冒险进度并返回主页。',
      confirmLabel: '重开',
      isDanger: true,
    );
    if (confirm) {
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
              case 'inventory':
                onShowInventory?.call();
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
