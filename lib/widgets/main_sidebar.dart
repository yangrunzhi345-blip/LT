import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider;

import '../core/feedback/app_feedback.dart';
import '../core/theme/app_radius.dart';
import '../core/theme/app_spacing.dart';
import '../models/app_section.dart';
import '../models/resource_library_mode.dart';
import '../models/sidebar_destination.dart';
import '../providers/riverpod_providers.dart';

Widget buildMainSidebar(
  BuildContext context,
  GlobalKey<ScaffoldState> scaffoldKey, {
  bool permanent = false,
}) {
  return MainSidebar(scaffoldKey: scaffoldKey, permanent: permanent);
}

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
  static const _expandedWidth = 288.0;
  static const _collapsedWidth = 72.0;

  final ScrollController _scrollController = ScrollController();
  Timer? _pendingAdventureOpen;
  bool _coreExpanded = true;
  bool _recentExpanded = true;

  @override
  void initState() {
    super.initState();
    unawaited(ref.read(chatProvider).loadMainSidebarPreference());
  }

  void _closeDrawer() => widget.scaffoldKey.currentState?.closeDrawer();

  void _onPrimaryTap(AppSection section) {
    final cp = ref.read(chatProvider);
    if (section == AppSection.adventure) {
      cp.navigateToAdventureHome();
    } else if (section == AppSection.resources) {
      cp.openResourceLibrary(ResourceLibraryMode.adventure);
    } else {
      cp.setCurrentSection(section);
    }
    _closeDrawer();
  }

  void _onAdventureTap(int id) {
    _pendingAdventureOpen?.cancel();
    _closeDrawer();
    _pendingAdventureOpen = Timer(const Duration(milliseconds: 120), () {
      _pendingAdventureOpen = null;
      if (mounted) unawaited(ref.read(chatProvider).openAdventure(id));
    });
  }

  void _toggleCore() => setState(() => _coreExpanded = !_coreExpanded);

  void _toggleRecent() => setState(() => _recentExpanded = !_recentExpanded);

  Future<void> _refreshCurrentPage() async {
    final result = await ref.read(pageRefreshControllerProvider).refresh();
    if (!mounted || result.isSuccess) return;
    AppFeedback.error(context, result.error ?? '刷新失败，请稍后重试');
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
    final adventures = ref.watch(
      chatProvider.select((cp) => cp.adventureList),
    );
    final refresh = ref.watch(pageRefreshControllerProvider);

    final content = _SidebarSurface(
      isExpanded: isExpanded,
      permanent: widget.permanent,
      onToggle: ref.read(chatProvider).toggleMainSidebarExpanded,
      onRefresh: _refreshCurrentPage,
      refreshAvailable: refresh.isAvailable,
      refreshing: refresh.isRefreshing,
      currentSection: currentSection,
      adventures: adventures,
      coreExpanded: _coreExpanded,
      recentExpanded: _recentExpanded,
      scrollController: _scrollController,
      onPrimaryTap: _onPrimaryTap,
      onAdventureTap: _onAdventureTap,
      onToggleCore: _toggleCore,
      onToggleRecent: _toggleRecent,
      onManagementTap: _showGlobalManagement,
    );

    if (widget.permanent) {
      return AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        width: isExpanded ? _expandedWidth : _collapsedWidth,
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(
          border: Border(
            right: BorderSide(
              color: Theme.of(context).dividerColor.withValues(alpha: .5),
            ),
          ),
        ),
        child: content,
      );
    }
    return Drawer(child: content);
  }

  Future<void> _showGlobalManagement() async {
    final adventures = ref.read(chatProvider).adventureList;
    final items = <({String key, String kind, String title})>[
      ...adventures.where((item) => item['id'] is int).map(
            (item) => (
              key: 'adventure:${item['id']}',
              kind: '场景',
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
}

class _SidebarSurface extends StatelessWidget {
  const _SidebarSurface({
    required this.isExpanded,
    required this.permanent,
    required this.onToggle,
    required this.onRefresh,
    required this.refreshAvailable,
    required this.refreshing,
    required this.currentSection,
    required this.adventures,
    required this.coreExpanded,
    required this.recentExpanded,
    required this.scrollController,
    required this.onPrimaryTap,
    required this.onAdventureTap,
    required this.onToggleCore,
    required this.onToggleRecent,
    required this.onManagementTap,
  });

  final bool isExpanded;
  final bool permanent;
  final VoidCallback onToggle;
  final Future<dynamic> Function() onRefresh;
  final bool refreshAvailable;
  final bool refreshing;
  final AppSection currentSection;
  final List<Map<String, dynamic>> adventures;
  final bool coreExpanded;
  final bool recentExpanded;
  final ScrollController scrollController;
  final ValueChanged<AppSection> onPrimaryTap;
  final ValueChanged<int> onAdventureTap;
  final VoidCallback onToggleCore;
  final VoidCallback onToggleRecent;
  final VoidCallback onManagementTap;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return Material(
      color: surface,
      child: SafeArea(
        child: Column(
          children: [
            _SidebarHeader(isExpanded: isExpanded, onToggle: onToggle),
            _SidebarToolbar(
              isExpanded: isExpanded,
              refreshAvailable: refreshAvailable,
              refreshing: refreshing,
              onRefresh: onRefresh,
              onManagementTap: onManagementTap,
            ),
            Expanded(
              child: Scrollbar(
                controller: scrollController,
                thumbVisibility: false,
                interactive: true,
                child: ListView(
                  controller: scrollController,
                  primary: false,
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.sm,
                    AppSpacing.sm,
                    AppSpacing.sm,
                    AppSpacing.lg,
                  ),
                  children: [
                    _SidebarSectionHeader(
                      title: '功能导航',
                      isExpanded: isExpanded,
                      expanded: coreExpanded,
                      onToggle: onToggleCore,
                    ),
                    if (!isExpanded || coreExpanded) ...[
                      for (final destination in sidebarPrimaryDestinations)
                        SidebarNavigationItem(
                          destination: destination,
                          selected: destination.section == currentSection,
                          collapsed: !isExpanded,
                          onTap: () => onPrimaryTap(destination.section),
                        ),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    _SidebarSectionHeader(
                      title: '最近场景',
                      isExpanded: isExpanded,
                      expanded: recentExpanded,
                      onToggle: onToggleRecent,
                    ),
                    if (!isExpanded || recentExpanded) ...[
                      ..._recentAdventureItems(isExpanded),
                      if (adventures.isEmpty)
                        _CompactEmptyRecent(
                          collapsed: !isExpanded,
                          message: '暂无最近场景',
                        ),
                    ],
                  ],
                ),
              ),
            ),
            _SidebarFooter(isExpanded: isExpanded, onToggle: onToggle),
          ],
        ),
      ),
    );
  }

  List<Widget> _recentAdventureItems(bool expanded) {
    return adventures.take(8).map((item) {
      final id = item['id'] as int?;
      if (id == null) return const SizedBox.shrink();
      return SidebarRecentItem(
        icon: Icons.explore_outlined,
        title: item['title'] as String? ?? '未命名场景',
        subtitle: '场景对话',
        collapsed: !expanded,
        onTap: () => onAdventureTap(id),
      );
    }).toList();
  }
}

class _SidebarHeader extends StatelessWidget {
  const _SidebarHeader({required this.isExpanded, required this.onToggle});

  final bool isExpanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Icon(
            Icons.auto_awesome,
            size: 20,
            color: theme.colorScheme.onPrimaryContainer,
          ),
        ),
        if (isExpanded) ...[
          const SizedBox(width: AppSpacing.sm),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('LT 灵境',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                Text('AI 场景沉浸对话平台', style: TextStyle(fontSize: 11)),
              ],
            ),
          ),
        ],
      ],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.md, AppSpacing.sm, AppSpacing.sm),
      child: Row(
        children: [
          Expanded(child: Center(child: content)),
          if (isExpanded)
            Tooltip(
              message: '收起侧边栏',
              child: IconButton(
                onPressed: onToggle,
                icon: const Icon(Icons.menu_open_rounded),
                tooltip: null,
              ),
            ),
        ],
      ),
    );
  }
}

class _SidebarToolbar extends StatelessWidget {
  const _SidebarToolbar({
    required this.isExpanded,
    required this.refreshAvailable,
    required this.refreshing,
    required this.onRefresh,
    required this.onManagementTap,
  });

  final bool isExpanded;
  final bool refreshAvailable;
  final bool refreshing;
  final Future<dynamic> Function() onRefresh;
  final VoidCallback onManagementTap;

  @override
  Widget build(BuildContext context) {
    final enabled = refreshAvailable && !refreshing;
    final message = refreshAvailable ? '刷新当前页面' : '当前页面无需刷新';
    final refreshButton = Tooltip(
      message: message,
      child: IconButton(
        onPressed: enabled ? () => unawaited(onRefresh()) : null,
        icon: refreshing
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.refresh_rounded),
        tooltip: null,
      ),
    );
    if (!isExpanded) {
      return SizedBox(
        height: 48,
        child: Center(child: refreshButton),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '当前工作区',
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          refreshButton,
          Tooltip(
            message: '管理最近访问',
            child: IconButton(
              onPressed: onManagementTap,
              icon: const Icon(Icons.tune_rounded),
              tooltip: null,
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarSectionHeader extends StatelessWidget {
  const _SidebarSectionHeader({
    required this.title,
    required this.isExpanded,
    this.expanded = true,
    this.onToggle,
  });

  final String title;
  final bool isExpanded;
  final bool expanded;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    if (!isExpanded) return const SizedBox(height: AppSpacing.sm);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.sm, AppSpacing.sm, AppSpacing.sm, AppSpacing.xs),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (onToggle != null)
                Icon(
                  expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class SidebarNavigationItem extends StatelessWidget {
  const SidebarNavigationItem({
    super.key,
    required this.destination,
    required this.selected,
    required this.collapsed,
    required this.onTap,
  });

  final SidebarDestination destination;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground = selected ? colors.primary : colors.onSurface;
    final item = Semantics(
      button: true,
      selected: selected,
      label: destination.tooltip,
      child: Material(
        color: selected
            ? colors.primary.withValues(alpha: .12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: SizedBox(
            height: 58,
            child: Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: collapsed ? 0 : AppSpacing.sm),
              child: Row(
                mainAxisAlignment: collapsed
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.start,
                children: [
                  Icon(destination.icon, color: foreground),
                  if (!collapsed) ...[
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(destination.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontWeight: selected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: foreground)),
                          Text(destination.subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: colors.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child:
          collapsed ? Tooltip(message: destination.tooltip, child: item) : item,
    );
  }
}

class SidebarRecentItem extends StatelessWidget {
  const SidebarRecentItem({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.collapsed,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (collapsed) {
      final compactItem = Semantics(
        button: true,
        label: subtitle == null ? title : '$title：$subtitle',
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 48,
            width: double.infinity,
            child: Center(child: Icon(icon, size: 20)),
          ),
        ),
      );
      return Tooltip(
        message: subtitle == null ? title : '$title：$subtitle',
        child: compactItem,
      );
    }
    final item = Semantics(
      button: true,
      label: subtitle == null ? title : '$title：$subtitle',
      child: ListTile(
        dense: true,
        contentPadding:
            EdgeInsets.symmetric(horizontal: collapsed ? 0 : AppSpacing.sm),
        minLeadingWidth: 0,
        leading: Icon(icon, size: 20),
        title: collapsed
            ? null
            : Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: collapsed || subtitle == null
            ? null
            : Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis),
        onTap: onTap,
      ),
    );
    return item;
  }
}

class _CompactEmptyRecent extends StatelessWidget {
  const _CompactEmptyRecent({
    required this.collapsed,
    this.message = '暂无最近访问',
  });

  final bool collapsed;
  final String message;

  @override
  Widget build(BuildContext context) {
    if (collapsed) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Text(
        message,
        style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 12),
      ),
    );
  }
}

class _SidebarFooter extends StatelessWidget {
  const _SidebarFooter({required this.isExpanded, required this.onToggle});

  final bool isExpanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Tooltip(
          message: isExpanded ? '收起侧边栏' : '展开侧边栏',
          child: OutlinedButton(
            onPressed: onToggle,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(48, 44),
              padding: EdgeInsets.zero,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(isExpanded
                    ? Icons.chevron_left_rounded
                    : Icons.chevron_right_rounded),
                if (isExpanded) const Text('收起侧边栏'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

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
      title: const Text('管理最近访问'),
      content: SizedBox(
        width: 520,
        height: 420,
        child: widget.items.isEmpty
            ? const Center(child: Text('暂无可管理的场景'))
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
            onPressed: () => Navigator.pop(context), child: const Text('关闭')),
        FilledButton.tonal(
          onPressed: _selected.isEmpty
              ? null
              : () async {
                  final selected = Set<String>.from(_selected);
                  Navigator.pop(context);
                  await widget.onDelete(selected);
                },
          child: const Text('批量删除'),
        ),
      ],
    );
  }
}
