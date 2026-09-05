import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider;

import '../core/theme/app_radius.dart';
import '../core/theme/app_spacing.dart';
import '../models/app_section.dart';
import '../providers/riverpod_providers.dart';

Widget buildMainSidebar(
  BuildContext context,
  GlobalKey<ScaffoldState> scaffoldKey, {
  bool permanent = false,
}) {
  return MainSidebar(scaffoldKey: scaffoldKey, permanent: permanent);
}

/// 现代化极简 AI 侧边栏（参考主流 AI 对话平台 ChatGPT / Claude 规范）
/// 仅保留：
/// 1. 顶部：探索工坊大厅（首页返回）与开启新冒险 (+ New Chat) 按钮
/// 2. 中间：过去的对话 (历史会话列表，支持交互悬浮、选中高亮与删除)
/// 3. 底部：常驻系统设置 (展示当前选定模型、连接状态与齿轮设置入口)
class MainSidebar extends ConsumerStatefulWidget {
  final GlobalKey<ScaffoldState> scaffoldKey;
  final bool permanent;

  const MainSidebar({
    super.key,
    required this.scaffoldKey,
    this.permanent = false,
  });

  @override
  ConsumerState<MainSidebar> createState() => _MainSidebarState();
}

class _MainSidebarState extends ConsumerState<MainSidebar> {
  static const _expandedWidth = 268.0;
  static const _collapsedWidth = 64.0;

  final ScrollController _scrollController = ScrollController();
  Timer? _pendingAdventureOpen;

  @override
  void initState() {
    super.initState();
    unawaited(ref.read(chatProvider).loadMainSidebarPreference());
  }

  void _closeDrawer() => widget.scaffoldKey.currentState?.closeDrawer();

  void _onNewAdventure() {
    _closeDrawer();
    ref.read(chatProvider).navigateToAdventureHome();
  }

  void _onAdventureTap(int id) {
    _pendingAdventureOpen?.cancel();
    _closeDrawer();
    _pendingAdventureOpen = Timer(const Duration(milliseconds: 100), () {
      _pendingAdventureOpen = null;
      if (mounted) unawaited(ref.read(chatProvider).openAdventure(id));
    });
  }

  void _onSettingsTap() {
    _closeDrawer();
    ref.read(chatProvider).setCurrentSection(AppSection.settings);
  }

  Future<void> _onDeleteAdventure(int id, String title) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除场景对话'),
        content: Text('确定删除「$title」吗？\n删除后历史对话与演变剧情将无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await ref.read(chatProvider).deleteAdventure(id);
    }
  }

  Future<void> _showGlobalManagement() async {
    final adventures = ref.read(chatProvider).adventureList;
    final items = <({String key, String kind, String title})>[
      ...adventures.where((item) => item['id'] is int).map(
            (item) => (
              key: 'adventure:${item['id']}',
              kind: '场景对话',
              title: item['title'] as String? ?? '未命名场景',
            ),
          ),
    ];
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _ManagementDialog(
        items: items,
        onDelete: (selected) async {
          final cp = ref.read(chatProvider);
          for (final item in items) {
            if (!selected.contains(item.key)) continue;
            final id = int.tryParse(item.key.split(':').last);
            if (id == null) continue;
            await cp.deleteAdventure(id);
          }
        },
      ),
    );
  }

  @override
  void dispose() {
    _pendingAdventureOpen?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isExpanded = ref.watch(
      chatProvider.select((cp) => cp.isMainSidebarExpanded),
    );
    final currentSection = ref.watch(
      chatProvider.select((cp) => cp.currentSection),
    );
    final currentAdventureId = ref.watch(
      chatProvider.select((cp) => cp.currentAdventureId),
    );
    final isAdventureChatOpen = ref.watch(
      chatProvider.select((cp) => cp.isAdventureChatOpen),
    );
    final adventures = ref.watch(
      chatProvider.select((cp) => cp.adventureList),
    );
    final chat = ref.watch(chatProvider);

    final isHomeActive =
        currentSection == AppSection.adventure && !isAdventureChatOpen;

    final content = _SidebarSurface(
      isExpanded: isExpanded,
      currentSection: currentSection,
      currentAdventureId: currentAdventureId,
      isAdventureChatOpen: isAdventureChatOpen,
      isHomeActive: isHomeActive,
      adventures: adventures,
      isConfigured: chat.isKeyConfigured,
      providerName: chat.providerType.displayName,
      modelName: chat.modelName.isNotEmpty
          ? chat.modelName
          : chat.providerType.defaultModel,
      scrollController: _scrollController,
      onToggle: ref.read(chatProvider).toggleMainSidebarExpanded,
      onReturnHome: _onNewAdventure,
      onNewAdventure: _onNewAdventure,
      onAdventureTap: _onAdventureTap,
      onDeleteAdventure: _onDeleteAdventure,
      onSettingsTap: _onSettingsTap,
      onManagementTap: _showGlobalManagement,
    );

    if (widget.permanent) {
      return AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        width: isExpanded ? _expandedWidth : _collapsedWidth,
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(
          border: Border(
            right: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.35),
            ),
          ),
        ),
        child: OverflowBox(
          minWidth: isExpanded ? _expandedWidth : _collapsedWidth,
          maxWidth: isExpanded ? _expandedWidth : _collapsedWidth,
          alignment: Alignment.topLeft,
          child: content,
        ),
      );
    }
    return Drawer(child: content);
  }
}

class _SidebarSurface extends StatelessWidget {
  const _SidebarSurface({
    required this.isExpanded,
    required this.currentSection,
    required this.currentAdventureId,
    required this.isAdventureChatOpen,
    required this.isHomeActive,
    required this.adventures,
    required this.isConfigured,
    required this.providerName,
    required this.modelName,
    required this.scrollController,
    required this.onToggle,
    required this.onReturnHome,
    required this.onNewAdventure,
    required this.onAdventureTap,
    required this.onDeleteAdventure,
    required this.onSettingsTap,
    required this.onManagementTap,
  });

  final bool isExpanded;
  final AppSection currentSection;
  final int? currentAdventureId;
  final bool isAdventureChatOpen;
  final bool isHomeActive;
  final List<Map<String, dynamic>> adventures;
  final bool isConfigured;
  final String providerName;
  final String modelName;
  final ScrollController scrollController;
  final VoidCallback onToggle;
  final VoidCallback onReturnHome;
  final VoidCallback onNewAdventure;
  final ValueChanged<int> onAdventureTap;
  final Future<void> Function(int id, String title) onDeleteAdventure;
  final VoidCallback onSettingsTap;
  final VoidCallback onManagementTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      color: scheme.surfaceContainerLowest,
      child: SafeArea(
        child: Column(
          children: [
            // 1. 顶部 Header (点击品牌直达探索大厅)
            _SidebarHeader(
              isExpanded: isExpanded,
              onToggle: onToggle,
              onReturnHome: onReturnHome,
            ),

            // 2. 探索大厅与开启新冒险主操作组
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isExpanded ? AppSpacing.md : AppSpacing.xs,
                vertical: AppSpacing.xs,
              ),
              child: Column(
                children: [
                  _SidebarHomeButton(
                    isExpanded: isExpanded,
                    isSelected: isHomeActive,
                    onPressed: onReturnHome,
                  ),
                  const SizedBox(height: 6),
                  _NewAdventureButton(
                    isExpanded: isExpanded,
                    onPressed: onNewAdventure,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xs),

            // 3. 过去的对话标题栏 (带批量管理入口)
            _SidebarPastConversationsHeader(
              isExpanded: isExpanded,
              count: adventures.length,
              onManagementTap: onManagementTap,
            ),

            // 4. 过去的对话历史列表
            Expanded(
              child: adventures.isEmpty
                  ? _EmptyConversationsView(isExpanded: isExpanded)
                  : Scrollbar(
                      controller: scrollController,
                      thumbVisibility: false,
                      child: ListView.builder(
                        controller: scrollController,
                        primary: false,
                        padding: EdgeInsets.symmetric(
                          horizontal: isExpanded ? AppSpacing.sm : AppSpacing.xs,
                          vertical: 2,
                        ),
                        itemCount: adventures.length,
                        itemBuilder: (context, index) {
                          final item = adventures[index];
                          final id = item['id'] as int? ?? -1;
                          final title =
                              item['title'] as String? ?? '未命名场景';
                          final isSelected =
                              currentSection == AppSection.adventure &&
                                  isAdventureChatOpen &&
                                  currentAdventureId == id;

                          return _PastConversationTile(
                            key: ValueKey(id),
                            id: id,
                            title: title,
                            isSelected: isSelected,
                            isExpanded: isExpanded,
                            onTap: () => onAdventureTap(id),
                            onDelete: () => onDeleteAdventure(id, title),
                          );
                        },
                      ),
                    ),
            ),

            // 5. 底部常驻设置入口与模型状态栏
            _SidebarSettingsBar(
              isExpanded: isExpanded,
              isSelected: currentSection == AppSection.settings,
              isConfigured: isConfigured,
              providerName: providerName,
              modelName: modelName,
              onSettingsTap: onSettingsTap,
              onToggle: onToggle,
            ),
          ],
        ),
      ),
    );
  }
}

/// 侧边栏顶部品牌标识与收缩开关
class _SidebarHeader extends StatelessWidget {
  const _SidebarHeader({
    required this.isExpanded,
    required this.onToggle,
    required this.onReturnHome,
  });

  final bool isExpanded;
  final VoidCallback onToggle;
  final VoidCallback onReturnHome;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (!isExpanded) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Tooltip(
          message: '返回探索大厅 / 展开',
          child: InkWell(
            onTap: onReturnHome,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [scheme.primary, scheme.tertiary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                size: 18,
                color: Colors.white,
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.xs,
      ),
      child: Row(
        children: [
          Expanded(
            child: Tooltip(
              message: '返回探索工坊大厅 (首页)',
              child: InkWell(
                onTap: onReturnHome,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [scheme.primary, scheme.tertiary],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        child: const Icon(
                          Icons.auto_awesome_rounded,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'LT 灵境',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.2,
                              ),
                            ),
                            Text(
                              'AI 场景沉浸对话',
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 10.5,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Tooltip(
            message: '收起侧边栏',
            child: IconButton(
              onPressed: onToggle,
              icon: const Icon(Icons.view_sidebar_outlined, size: 19),
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
    );
  }
}

/// 探索大厅 (返回首页) 快捷导航项
class _SidebarHomeButton extends StatefulWidget {
  const _SidebarHomeButton({
    required this.isExpanded,
    required this.isSelected,
    required this.onPressed,
  });

  final bool isExpanded;
  final bool isSelected;
  final VoidCallback onPressed;

  @override
  State<_SidebarHomeButton> createState() => _SidebarHomeButtonState();
}

class _SidebarHomeButtonState extends State<_SidebarHomeButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (!widget.isExpanded) {
      return Tooltip(
        message: '探索工坊大厅 (首页)',
        child: InkWell(
          onTap: widget.onPressed,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Container(
            width: 42,
            height: 40,
            decoration: BoxDecoration(
              color: widget.isSelected
                  ? scheme.primaryContainer.withValues(alpha: 0.8)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: widget.isSelected
                  ? Border.all(color: scheme.primary.withValues(alpha: 0.35))
                  : null,
            ),
            child: Icon(
              widget.isSelected
                  ? Icons.explore_rounded
                  : Icons.explore_outlined,
              color: widget.isSelected
                  ? scheme.primary
                  : scheme.onSurfaceVariant,
              size: 20,
            ),
          ),
        ),
      );
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onPressed,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            decoration: BoxDecoration(
              color: widget.isSelected
                  ? scheme.primaryContainer.withValues(alpha: 0.75)
                  : _isHovered
                      ? scheme.surfaceContainerHighest.withValues(alpha: 0.6)
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: widget.isSelected
                  ? Border.all(
                      color: scheme.primary.withValues(alpha: 0.35),
                      width: 1.2,
                    )
                  : null,
            ),
            child: Row(
              children: [
                Icon(
                  widget.isSelected
                      ? Icons.explore_rounded
                      : Icons.explore_outlined,
                  size: 18,
                  color: widget.isSelected
                      ? scheme.primary
                      : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    '探索工坊大厅',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: widget.isSelected
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: widget.isSelected
                          ? scheme.onPrimaryContainer
                          : scheme.onSurface,
                      fontSize: 13,
                    ),
                  ),
                ),
                if (widget.isSelected)
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: scheme.primary,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "+ 开启新冒险" 醒目主操作按钮（仿主流平台 New Chat 样式）
class _NewAdventureButton extends StatefulWidget {
  const _NewAdventureButton({
    required this.isExpanded,
    required this.onPressed,
  });

  final bool isExpanded;
  final VoidCallback onPressed;

  @override
  State<_NewAdventureButton> createState() => _NewAdventureButtonState();
}

class _NewAdventureButtonState extends State<_NewAdventureButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (!widget.isExpanded) {
      return Tooltip(
        message: '开启新冒险',
        child: InkWell(
          onTap: widget.onPressed,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Icon(
              Icons.add_rounded,
              color: scheme.primary,
              size: 22,
            ),
          ),
        ),
      );
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onPressed,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            decoration: BoxDecoration(
              color: _isHovered
                  ? scheme.surfaceContainerHighest
                  : scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: _isHovered
                    ? scheme.primary.withValues(alpha: 0.6)
                    : scheme.outlineVariant.withValues(alpha: 0.5),
                width: 1.2,
              ),
              boxShadow: _isHovered
                  ? [
                      BoxShadow(
                        color: scheme.primary.withValues(alpha: 0.08),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : [],
            ),
            child: Row(
              children: [
                Icon(
                  Icons.add_rounded,
                  size: 19,
                  color: scheme.primary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    '开启新冒险',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                      fontSize: 13,
                    ),
                  ),
                ),
                Icon(
                  Icons.auto_awesome_outlined,
                  size: 15,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "过去的对话" 栏目头
class _SidebarPastConversationsHeader extends StatelessWidget {
  const _SidebarPastConversationsHeader({
    required this.isExpanded,
    required this.count,
    required this.onManagementTap,
  });

  final bool isExpanded;
  final int count;
  final VoidCallback onManagementTap;

  @override
  Widget build(BuildContext context) {
    if (!isExpanded) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Divider(
          indent: 14,
          endIndent: 14,
          height: 1,
          color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      );
    }

    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.xs,
      ),
      child: Row(
        children: [
          Text(
            '过去的对话',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
          ),
          if (count > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
          const Spacer(),
          if (count > 0)
            Tooltip(
              message: '批量管理历史对话',
              child: IconButton(
                onPressed: onManagementTap,
                icon: const Icon(Icons.tune_rounded, size: 15),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
              ),
            ),
        ],
      ),
    );
  }
}

/// 历史对话空状态
class _EmptyConversationsView extends StatelessWidget {
  const _EmptyConversationsView({required this.isExpanded});

  final bool isExpanded;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (!isExpanded) {
      return Tooltip(
        message: '暂无历史对话',
        child: Center(
          child: Icon(
            Icons.chat_bubble_outline_rounded,
            size: 20,
            color: scheme.onSurfaceVariant.withValues(alpha: 0.35),
          ),
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat_bubble_outline_rounded,
              size: 28,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.35),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '暂无历史对话',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '点击上方按钮开启新冒险',
              style: TextStyle(
                fontSize: 11,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 历史会话项（参考主流 AI 平台单行微交互、悬浮删除）
class _PastConversationTile extends StatefulWidget {
  const _PastConversationTile({
    super.key,
    required this.id,
    required this.title,
    required this.isSelected,
    required this.isExpanded,
    required this.onTap,
    required this.onDelete,
  });

  final int id;
  final String title;
  final bool isSelected;
  final bool isExpanded;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  State<_PastConversationTile> createState() => _PastConversationTileState();
}

class _PastConversationTileState extends State<_PastConversationTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (!widget.isExpanded) {
      return Tooltip(
        message: widget.title,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: Container(
            height: 38,
            margin: const EdgeInsets.symmetric(vertical: 2),
            decoration: BoxDecoration(
              color: widget.isSelected
                  ? scheme.primaryContainer.withValues(alpha: 0.8)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Center(
              child: Icon(
                widget.isSelected
                    ? Icons.chat_bubble_rounded
                    : Icons.chat_bubble_outline_rounded,
                size: 17,
                color: widget.isSelected
                    ? scheme.primary
                    : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      );
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Container(
        height: 38,
        margin: const EdgeInsets.symmetric(vertical: 1.5),
        decoration: BoxDecoration(
          color: widget.isSelected
              ? scheme.primaryContainer.withValues(alpha: 0.75)
              : _isHovered
                  ? scheme.surfaceContainerHighest.withValues(alpha: 0.5)
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: widget.isSelected
              ? Border.all(
                  color: scheme.primary.withValues(alpha: 0.3),
                  width: 1,
                )
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: Padding(
              padding: const EdgeInsets.only(left: 10, right: 4),
              child: Row(
                children: [
                  Icon(
                    widget.isSelected
                        ? Icons.chat_bubble_rounded
                        : Icons.chat_bubble_outline_rounded,
                    size: 15,
                    color: widget.isSelected
                        ? scheme.primary
                        : scheme.onSurfaceVariant.withValues(alpha: 0.75),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: widget.isSelected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: widget.isSelected
                            ? scheme.onPrimaryContainer
                            : scheme.onSurface,
                      ),
                    ),
                  ),
                  if (_isHovered || widget.isSelected)
                    Tooltip(
                      message: '删除对话',
                      child: IconButton(
                        icon: Icon(
                          Icons.delete_outline_rounded,
                          size: 15,
                          color: scheme.error.withValues(alpha: 0.8),
                        ),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 26,
                          minHeight: 26,
                        ),
                        onPressed: widget.onDelete,
                      ),
                    )
                  else
                    const SizedBox(width: 6),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 底部常驻系统设置与模型指示栏 (ChatGPT / Claude 风格)
class _SidebarSettingsBar extends StatelessWidget {
  const _SidebarSettingsBar({
    required this.isExpanded,
    required this.isSelected,
    required this.isConfigured,
    required this.providerName,
    required this.modelName,
    required this.onSettingsTap,
    required this.onToggle,
  });

  final bool isExpanded;
  final bool isSelected;
  final bool isConfigured;
  final String providerName;
  final String modelName;
  final VoidCallback onSettingsTap;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        border: Border(
          top: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.35),
          ),
        ),
      ),
      padding: EdgeInsets.all(isExpanded ? AppSpacing.sm : AppSpacing.xs),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isExpanded) ...[
            Tooltip(
              message: '系统设置 · ${isConfigured ? "$providerName ($modelName)" : "未配置密钥"}',
              child: IconButton(
                onPressed: onSettingsTap,
                icon: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(
                      Icons.settings_outlined,
                      size: 20,
                      color: isSelected ? scheme.primary : scheme.onSurface,
                    ),
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isConfigured
                              ? const Color(0xFF22C55E)
                              : const Color(0xFFF59E0B),
                          border: Border.all(
                            color: scheme.surfaceContainerLowest,
                            width: 1.2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 2),
            Tooltip(
              message: '展开侧边栏',
              child: IconButton(
                onPressed: onToggle,
                icon: const Icon(Icons.chevron_right_rounded, size: 18),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ] else ...[
            Material(
              color: isSelected
                  ? scheme.primaryContainer.withValues(alpha: 0.7)
                  : scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: InkWell(
                onTap: onSettingsTap,
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHighest,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.tune_rounded,
                              size: 16,
                              color: scheme.onSurface,
                            ),
                          ),
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isConfigured
                                    ? const Color(0xFF22C55E)
                                    : const Color(0xFFF59E0B),
                                border: Border.all(
                                  color: scheme.surfaceContainerLowest,
                                  width: 1.5,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '系统设置',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              isConfigured
                                  ? '$providerName · $modelName'
                                  : '未配置 API 密钥',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10.5,
                                color: isConfigured
                                    ? scheme.onSurfaceVariant
                                    : scheme.error,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: scheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 历史对话批量管理对话框
class _ManagementDialog extends StatefulWidget {
  const _ManagementDialog({required this.items, required this.onDelete});

  final List<({String key, String kind, String title})> items;
  final Future<void> Function(Set<String> selected) onDelete;

  @override
  State<_ManagementDialog> createState() => _ManagementDialogState();
}

class _ManagementDialogState extends State<_ManagementDialog> {
  final Set<String> _selected = <String>{};

  @override
  Widget build(BuildContext context) {
    final allSelected =
        widget.items.isNotEmpty && _selected.length == widget.items.length;
    return AlertDialog(
      title: const Text('管理过去的对话'),
      content: SizedBox(
        width: 500,
        height: 400,
        child: widget.items.isEmpty
            ? const Center(child: Text('暂无可管理的场景对话'))
            : Column(
                children: [
                  CheckboxListTile(
                    value: allSelected,
                    tristate: true,
                    title: Text('全选（已选 ${_selected.length} 项）'),
                    onChanged: (_) => setState(() {
                      if (allSelected) {
                        _selected.clear();
                      } else {
                        _selected.addAll(widget.items.map((item) => item.key));
                      }
                    }),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.builder(
                      itemCount: widget.items.length,
                      itemBuilder: (_, index) {
                        final item = widget.items[index];
                        return CheckboxListTile(
                          value: _selected.contains(item.key),
                          dense: true,
                          title: Text(item.title),
                          subtitle: Text(item.kind),
                          onChanged: (value) => setState(() {
                            if (value == true) {
                              _selected.add(item.key);
                            } else {
                              _selected.remove(item.key);
                            }
                          }),
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
        FilledButton.tonal(
          onPressed: _selected.isEmpty
              ? null
              : () async {
                  final selected = Set<String>.from(_selected);
                  Navigator.pop(context);
                  await widget.onDelete(selected);
                },
          style: FilledButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          child: const Text('批量删除'),
        ),
      ],
    );
  }
}
