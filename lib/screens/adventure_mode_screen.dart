import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/router/app_router.dart';
import '../core/theme/app_colors.dart';
import '../core/widgets/form_sub_page_scaffold.dart';
import '../core/widgets/narr_aitor_dropdown.dart';
import '../providers/chat_provider.dart';
import '../providers/riverpod_providers.dart';
import '../models/llm_provider.dart';
import '../widgets/app_dialogs.dart';
import '../core/refresh/page_refresh_scope.dart';
import 'chat_screen.dart';
import 'prompt_settings_screen.dart';
import 'settings_center_screen.dart';

@visibleForTesting
bool usesCompactAdventureHeader(Size screenSize) =>
    screenSize.width < 700 || screenSize.shortestSide < 600;

class AdventureModeScreen extends ConsumerStatefulWidget {
  final VoidCallback? onMenuPressed;
  final String? initialMessageId;

  const AdventureModeScreen({
    super.key,
    this.onMenuPressed,
    this.initialMessageId,
  });

  @override
  ConsumerState<AdventureModeScreen> createState() =>
      _AdventureModeScreenState();
}

class _AdventureModeScreenState extends ConsumerState<AdventureModeScreen> {
  Future<void> _showCustomModelDialog(
    BuildContext context,
    ChatProvider provider,
  ) async {
    final ctrl = TextEditingController();
    final result = await showFormSubPage<String>(
      context: context,
      title: '自定义模型',
      maxWidth: 640,
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

  @override
  Widget build(BuildContext context) {
    return PageRefreshScope(
      onRefresh: () async {
        final refreshed =
            await ref.read(chatProvider).refreshCurrentAdventure();
        return refreshed
            ? const PageRefreshResult.success()
            : const PageRefreshResult.failure('生成中或场景不可用，暂不能刷新');
      },
      child: Scaffold(
        appBar: _buildAppBar(context),
        body: AppRefreshIndicator(
            child: EmbeddedAdventureScreen(
                initialMessageId: widget.initialMessageId)),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    final provider = ref.read(chatProvider);
    final screenSize = MediaQuery.sizeOf(context);
    final isCompact = usesCompactAdventureHeader(screenSize);
    return AppBar(
      toolbarHeight: 48,
      leading: IconButton(
        icon: const Icon(Icons.menu, size: 18),
        onPressed: widget.onMenuPressed,
        tooltip: '菜单',
        visualDensity: VisualDensity.compact,
      ),
      title: ValueListenableBuilder<int>(
        valueListenable: provider.titleBarVersion,
        builder: (context, _, __) {
          final p = ref.read(chatProvider);
          final title = p.currentTitle.isNotEmpty ? p.currentTitle : '文字冒险';
          return Text(
            title,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          );
        },
      ),
      centerTitle: true,
      elevation: 0,
      actions: isCompact
          ? _buildCompactAppBarActions(context)
          : _buildAppBarActions(context),
      bottom: isCompact
          ? PreferredSize(
              preferredSize: const Size.fromHeight(48),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: _buildModelDropdown(provider, expand: true),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: _buildProviderDropdown(context, provider),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildModelDropdown(ChatProvider provider, {bool expand = false}) {
    return ValueListenableBuilder<int>(
      valueListenable: provider.titleBarVersion,
      builder: (context, _, __) {
        final p = ref.read(chatProvider);
        return SizedBox(
          width: expand ? double.infinity : 200,
          child: NarrAItorDropdown<String>(
            key: const ValueKey('model_select'),
            triggerHeight: 30,
            triggerPadding: const EdgeInsets.symmetric(horizontal: 10),
            value: p.modelName,
            options: [
              ...p.settingsProvider.recentModels.map(
                (model) => NarrAItorDropdownOption(
                  value: model,
                  label: model,
                  subtitle: '最近使用',
                  leading: const Icon(Icons.history, size: 16),
                ),
              ),
              ...p.providerType.availableModels.map(
                (model) => NarrAItorDropdownOption(
                  value: model,
                  label: model,
                  subtitle:
                      model == p.providerType.defaultModel ? '推荐模型' : null,
                  leading: Icon(
                    model == p.providerType.defaultModel
                        ? Icons.star_outline
                        : Icons.memory,
                    size: 16,
                  ),
                ),
              ),
              const NarrAItorDropdownOption(
                value: '__custom__',
                label: '自定义模型...',
                leading: Icon(Icons.add_circle_outline, size: 16),
              ),
            ],
            selectedBuilder: (value) => Text(
              value == null || value.length <= 22
                  ? value ?? '选择模型'
                  : '${value.substring(0, 22)}...',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.primary,
              ),
            ),
            onChanged: (model) {
              if (model == null) return;
              if (model == '__custom__') {
                _showCustomModelDialog(context, p);
              } else {
                p.setModel(model);
              }
            },
          ),
        );
      },
    );
  }

  Widget _buildProviderDropdown(
    BuildContext context,
    ChatProvider provider,
  ) {
    return NarrAItorDropdown<LLMProvider>(
      key: const ValueKey('provider_select'),
      triggerHeight: 30,
      triggerPadding: const EdgeInsets.symmetric(horizontal: 10),
      value: provider.providerType,
      options: LLMProvider.values
          .map((item) => NarrAItorDropdownOption(
                value: item,
                label: item.displayName,
                subtitle: item.defaultModel,
                leading: providerBrandIcon(item, size: 22),
              ))
          .toList(),
      selectedBuilder: (value) => Row(
        children: [
          const Icon(Icons.swap_horiz, size: 17),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              value?.displayName ?? '服务商',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11),
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
              content: Text('当前 ${next.displayName} 密钥未配置，无法使用该提供商的模型'),
              action: SnackBarAction(
                label: '配置',
                onPressed: () => Navigator.of(context).push(
                  AppRouter.slide(
                    pageBuilder: (_) => const SettingsCenterScreen(),
                  ),
                ),
              ),
              duration: const Duration(seconds: 6),
            ),
          );
        }
      },
    );
  }

  Future<void> _confirmRestartAdventure(
      BuildContext context, ChatProvider provider) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('确认重开冒险'),
        content: const Text('将重置当前冒险并返回主页，重新开始新的冒险。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true), child: const Text('重开')),
        ],
      ),
    );
    if (confirm == true) {
      provider.restartAdventure();
    }
  }

  List<Widget> _buildAppBarActions(BuildContext context) {
    final provider = ref.read(chatProvider);
    return [
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: _buildModelDropdown(provider),
      ),
      const SizedBox(width: 8),
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: SizedBox(
          width: 155,
          child: _buildProviderDropdown(context, provider),
        ),
      ),
      IconButton(
        icon: const Icon(Icons.search, size: 18),
        onPressed: () => provider.toggleSearch(),
        tooltip: '搜索对话',
        visualDensity: VisualDensity.compact,
      ),
      IconButton(
        icon: const Icon(Icons.tune_outlined, size: 18),
        onPressed: () => Navigator.of(context).push(
          AppRouter.slide(
            pageBuilder: (ctx) => const PromptSettingsScreen(),
          ),
        ),
        tooltip: '提示词设置',
        visualDensity: VisualDensity.compact,
      ),
      IconButton(
        icon: const Icon(Icons.restart_alt, size: 18),
        onPressed: () => _confirmRestartAdventure(context, provider),
        tooltip: '重开冒险',
        visualDensity: VisualDensity.compact,
      ),
      IconButton(
        icon: const Icon(Icons.settings_outlined, size: 18),
        onPressed: () => Navigator.of(context).push(
          AppRouter.slide(
            pageBuilder: (_) => const SettingsCenterScreen(),
          ),
        ),
        tooltip: '设置中心',
        visualDensity: VisualDensity.compact,
      ),
    ];
  }

  List<Widget> _buildCompactAppBarActions(BuildContext context) {
    final provider = ref.read(chatProvider);
    return [
      IconButton(
        icon: const Icon(Icons.search, size: 20),
        onPressed: () => provider.toggleSearch(),
        tooltip: '搜索对话',
        visualDensity: VisualDensity.compact,
      ),
      SizedBox(
          width: 36,
          height: 36,
          child: NarrAItorDropdown<String>(
            value: null,
            tooltip: '更多',
            expanded: false,
            showArrow: false,
            menuWidth: 200,
            triggerHeight: 36,
            triggerPadding: EdgeInsets.zero,
            selectedBuilder: (_) =>
                const Center(child: Icon(Icons.more_vert, size: 20)),
            onChanged: (value) {
              if (value == null) return;
              final page = value == 'prompt'
                  ? const PromptSettingsScreen()
                  : const SettingsCenterScreen();
              Navigator.of(context).push(
                AppRouter.slide(pageBuilder: (_) => page),
              );
            },
            options: const [
              NarrAItorDropdownOption(
                  value: 'prompt',
                  label: '提示词设置',
                  leading: Icon(Icons.tune_outlined)),
              NarrAItorDropdownOption(
                  value: 'settings',
                  label: '设置中心',
                  leading: Icon(Icons.settings_outlined)),
            ],
          )),
    ];
  }
}
