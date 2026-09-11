import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/router/app_router.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/widgets/form_sub_page_scaffold.dart';
import '../../../../../core/widgets/narr_aitor_dropdown.dart';
import '../../../../../models/llm_provider.dart';
import '../../../../../providers/chat_provider.dart';
import '../../../../../providers/riverpod_providers.dart';
import '../../../../../screens/prompt_settings_screen.dart';
import '../../../../../screens/settings_center_screen.dart';
import '../../../../../widgets/app_dialogs.dart';

/// 现代化场景会话顶栏
class SessionAppBar extends ConsumerWidget implements PreferredSizeWidget {
  final VoidCallback? onMenuPressed;

  const SessionAppBar({
    super.key,
    this.onMenuPressed,
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
                    borderRadius: BorderRadius.circular(10),
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
                  borderRadius: BorderRadius.circular(12),
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
        if (!compact) ...[
          // 模型选择胶囊
          _buildModelPill(context, provider),
          const SizedBox(width: 6),
          // 服务商选择胶囊
          _buildProviderPill(context, provider),
          const SizedBox(width: 8),
        ],
        // 对话搜索按钮
        IconButton(
          icon: const Icon(Icons.search_rounded, size: 20),
          tooltip: '搜索对话',
          onPressed: () => provider.toggleSearch(),
        ),
        // 提示词与预设设置
        if (compact)
          PopupMenuButton<String>(
            tooltip: '更多操作',
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (action) {
              switch (action) {
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
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'prompt', child: Text('提示词设置')),
              PopupMenuItem(value: 'restart', child: Text('重开冒险')),
              PopupMenuItem(value: 'settings', child: Text('设置中心')),
            ],
          ),
        if (!compact) ...[
          IconButton(
            icon: const Icon(Icons.tune_rounded, size: 20),
            tooltip: '提示词设置',
            onPressed: () => Navigator.of(context).push(
              AppRouter.slide(
                pageBuilder: (_) => const PromptSettingsScreen(),
              ),
            ),
          ),
          // 重开按钮
          IconButton(
            icon: const Icon(Icons.restart_alt_rounded, size: 20),
            tooltip: '重开冒险',
            onPressed: () => _confirmRestartAdventure(context, provider),
          ),
          // 设置中心
          IconButton(
            icon: const Icon(Icons.settings_outlined, size: 20),
            tooltip: '设置中心',
            onPressed: () => Navigator.of(context).push(
              AppRouter.slide(
                pageBuilder: (_) => const SettingsCenterScreen(),
              ),
            ),
          ),
        ],
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildModelPill(BuildContext context, ChatProvider provider) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ValueListenableBuilder<int>(
      valueListenable: provider.titleBarVersion,
      builder: (context, _, __) {
        final recents = provider.settingsProvider.recentModels;
        final recommended = provider.providerType.availableModels;
        final activeModel = provider.modelName;
        // Keep the active model selectable even when it is a hidden legacy
        // model that no longer appears in the recommended list.
        final hasActive = activeModel.isNotEmpty &&
            (recents.contains(activeModel) ||
                recommended.contains(activeModel));
        return SizedBox(
          width: 170,
          child: NarrAItorDropdown<String>(
            key: const ValueKey('session_model_select'),
            triggerHeight: 32,
            triggerPadding: const EdgeInsets.symmetric(horizontal: 10),
            value: provider.modelName,
            options: [
              ...recents.map(
                (model) => NarrAItorDropdownOption(
                  value: model,
                  label: model,
                  subtitle: '最近使用',
                  leading: const Icon(Icons.history_rounded, size: 15),
                ),
              ),
              ...recommended.map(
                (model) => NarrAItorDropdownOption(
                  value: model,
                  label: model,
                  subtitle: model == provider.providerType.defaultModel
                      ? '推荐模型'
                      : null,
                  leading: Icon(
                    model == provider.providerType.defaultModel
                        ? Icons.auto_awesome
                        : Icons.memory_rounded,
                    size: 15,
                  ),
                ),
              ),
              if (!hasActive)
                NarrAItorDropdownOption(
                  value: activeModel,
                  label: activeModel,
                  subtitle: '当前模型',
                  leading: const Icon(Icons.memory_rounded, size: 15),
                ),
              const NarrAItorDropdownOption(
                value: '__custom__',
                label: '自定义模型...',
                leading: Icon(Icons.add_circle_outline, size: 15),
              ),
            ],
            selectedBuilder: (value) => Text(
              value == null || value.length <= 16
                  ? (value ?? '选择模型')
                  : '${value.substring(0, 16)}...',
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.primary,
              ),
            ),
            onChanged: (model) {
              if (model == null) return;
              if (model == '__custom__') {
                _showCustomModelDialog(context, provider);
              } else {
                provider.setModel(model);
              }
            },
          ),
        );
      },
    );
  }

  Widget _buildProviderPill(BuildContext context, ChatProvider provider) {
    final theme = Theme.of(context);

    return SizedBox(
      width: 135,
      child: NarrAItorDropdown<LLMProvider>(
        key: const ValueKey('session_provider_select'),
        triggerHeight: 32,
        triggerPadding: const EdgeInsets.symmetric(horizontal: 10),
        value: provider.providerType,
        options: LLMProvider.values
            .map((item) => NarrAItorDropdownOption(
                  value: item,
                  label: item.displayName,
                  subtitle: item.defaultModel,
                  leading: providerBrandIcon(item, size: 20),
                ))
            .toList(),
        selectedBuilder: (value) => Row(
          children: [
            providerBrandIcon(value ?? provider.providerType, size: 16),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                value?.displayName ?? '服务商',
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        onChanged: (next) async {
          if (next == null) return;
          final hasKey = await provider.setProvider(next);
          if (!hasKey && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('当前 ${next.displayName} 密钥未配置'),
                action: SnackBarAction(
                  label: '前往配置',
                  onPressed: () => Navigator.of(context).push(
                    AppRouter.slide(
                      pageBuilder: (_) => const SettingsCenterScreen(),
                    ),
                  ),
                ),
                duration: const Duration(seconds: 5),
              ),
            );
          }
        },
      ),
    );
  }
}
