import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/router/app_router.dart';
import '../../../../../core/widgets/app_confirm_dialog.dart';
import '../../../../../providers/chat_provider.dart';
import '../../../../../providers/riverpod_providers.dart';
import '../../../../../screens/prompt_settings_screen.dart';
import '../../../../../screens/settings_center_screen.dart';
import '../screens/model_select_page.dart';
import '../../../../../l10n/generated/app_localizations.dart';
import '../../../../../l10n/generated/app_localizations_zh.dart';

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
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();
    final confirm = await AppConfirmDialog.show(
      context: context,
      title: l10n.restartAdventureTitle,
      message: l10n.restartAdventureMessage,
      confirmLabel: l10n.restartAdventureAction,
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
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();

    return AppBar(
      elevation: 0,
      scrolledUnderElevation: 0.5,
      backgroundColor: colorScheme.surface,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded, size: 20),
        onPressed: () => ref.read(chatProvider).navigateToAdventureHome(),
        tooltip: l10n.backToLobby,
        visualDensity: VisualDensity.compact,
      ),
      titleSpacing: 0,
      title: ValueListenableBuilder<int>(
        valueListenable: provider.titleBarVersion,
        builder: (context, _, __) {
          final title = provider.currentTitle.isNotEmpty
              ? provider.currentTitle
              : l10n.textAdventureTitle;
          return Tooltip(
            message: title,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
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
            ),
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
              tooltip: l10n.inventoryTitle,
              visualDensity: VisualDensity.compact,
              onPressed: onShowInventory,
            ),
        ],

        // 对话搜索按钮
        IconButton(
          icon: const Icon(Icons.search_rounded, size: 20),
          tooltip: l10n.searchConversationAction,
          visualDensity: VisualDensity.compact,
          onPressed: () => provider.toggleSearch(),
        ),

        // 历史与侧边抽屉入口（若提供了 onMenuPressed）
        if (onMenuPressed != null)
          IconButton(
            icon: const Icon(Icons.history_rounded, size: 20),
            tooltip: l10n.historyAndSidebarAction,
            visualDensity: VisualDensity.compact,
            onPressed: onMenuPressed,
          ),

        // 更多沉浸式操作与系统设置
        PopupMenuButton<String>(
          tooltip: l10n.moreOptionsAction,
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
              PopupMenuItem(
                value: 'character',
                child: Row(
                  children: [
                    const Icon(Icons.badge_outlined, size: 18),
                    const SizedBox(width: 10),
                    Text(l10n.characterStatusTitle),
                  ],
                ),
              ),
            if (onShowInventory != null)
              PopupMenuItem(
                value: 'inventory',
                child: Row(
                  children: [
                    const Icon(Icons.backpack_outlined, size: 18),
                    const SizedBox(width: 10),
                    Text(l10n.inventoryTitle),
                  ],
                ),
              ),
            if (onShowWordCount != null)
              PopupMenuItem(
                value: 'word_count',
                child: Row(
                  children: [
                    const Icon(Icons.format_size_rounded, size: 18),
                    const SizedBox(width: 10),
                    Text(l10n.replyLengthSetting),
                  ],
                ),
              ),
            const PopupMenuDivider(),
            PopupMenuItem(
              value: 'model',
              child: Row(
                children: [
                  const Icon(Icons.memory_rounded, size: 18),
                  const SizedBox(width: 10),
                  Text(l10n.switchModelAction),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'prompt',
              child: Row(
                children: [
                  const Icon(Icons.tune_rounded, size: 18),
                  const SizedBox(width: 10),
                  Text(l10n.promptSettingsAction),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'restart',
              child: Row(
                children: [
                  const Icon(Icons.restart_alt_rounded, size: 18),
                  const SizedBox(width: 10),
                  Text(l10n.restartAdventureAction),
                ],
              ),
            ),
            const PopupMenuDivider(),
            PopupMenuItem(
              value: 'settings',
              child: Row(
                children: [
                  const Icon(Icons.settings_outlined, size: 18),
                  const SizedBox(width: 10),
                  Text(l10n.settingsCenter),
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
