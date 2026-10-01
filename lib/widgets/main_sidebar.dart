import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/responsive/app_breakpoints.dart';
import '../core/router/app_router.dart';
import '../core/theme/app_spacing.dart';
import '../core/widgets/app_confirm_dialog.dart';
import '../core/widgets/app_svg_icon.dart';
import '../features/adventure/presentation/session/screens/conversation_manage_page.dart';
import '../l10n/generated/app_localizations.dart';
import '../l10n/generated/app_localizations_zh.dart';
import '../models/app_section.dart';
import '../models/resource_library_mode.dart';
import '../providers/chat_provider.dart';
import '../providers/riverpod_providers.dart';

Widget buildMainSidebar(
  BuildContext context,
  GlobalKey<ScaffoldState> scaffoldKey, {
  bool permanent = false,
}) =>
    MainSidebar(scaffoldKey: scaffoldKey, permanent: permanent);

/// Persistent workspace navigation, with contextual links to the active story.
///
/// Visual rules (Editorial Workbench): readable text destinations on desktop,
/// a 32 px row with a quiet accent tint and a 2 px leading indicator for the
/// selected item — never a full-width filled block or a circular icon button.
class MainSidebar extends ConsumerStatefulWidget {
  const MainSidebar(
      {super.key, required this.scaffoldKey, this.permanent = false});

  final GlobalKey<ScaffoldState> scaffoldKey;
  final bool permanent;

  @override
  ConsumerState<MainSidebar> createState() => _MainSidebarState();
}

class _MainSidebarState extends ConsumerState<MainSidebar> {
  static const double _railWidth = 56;
  static const double _compactWidth = 208;
  static const double _fullWidth = 232;

  @override
  void initState() {
    super.initState();
    unawaited(ref.read(chatProvider).loadMainSidebarPreference());
  }

  void _navigate(VoidCallback action) {
    widget.scaffoldKey.currentState?.closeDrawer();
    action();
  }

  Future<void> _delete(int id, String title) async {
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();
    final confirmed = await AppConfirmDialog.show(
      context: context,
      title: l10n.sidebarDeleteDialogTitle,
      message: l10n.sidebarDeleteDialogMessage(title),
      confirmLabel: l10n.deleteAction,
      isDanger: true,
    );
    if (confirmed && mounted) await ref.read(chatProvider).deleteAdventure(id);
  }

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(chatProvider);
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final mode = widget.permanent
        ? AppBreakpoints.sidebarMode(
            MediaQuery.sizeOf(context).width,
            collapsed: !chat.isMainSidebarExpanded,
          )
        : WorkbenchSidebarMode.full;
    final expanded = mode != WorkbenchSidebarMode.rail;
    final showRecents = mode == WorkbenchSidebarMode.full;

    final content = Material(
      color: scheme.surfaceContainerLow,
      child: SafeArea(
        child: Column(
          children: [
            _buildBrandRow(context, l10n, chat, expanded),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                children: [
                  if (expanded) _NavigationHeading(l10n.workbenchWorkspace),
                  _NavItem(
                    icon: 'adventure',
                    label: l10n.navExplore,
                    expanded: expanded,
                    selected: (chat.currentSection == AppSection.adventure &&
                            !chat.isAdventureChatOpen) ||
                        chat.currentSection == AppSection.home,
                    onTap: () => _navigate(chat.navigateToAdventureHome),
                  ),
                  _NavItem(
                    icon: 'resources',
                    label: l10n.navLibrary,
                    expanded: expanded,
                    selected: chat.currentSection == AppSection.resources,
                    onTap: () => _navigate(() => chat
                        .openResourceLibrary(ResourceLibraryMode.adventure)),
                  ),
                  _NavItem(
                    icon: 'state',
                    label: l10n.runtimeStateCurrent,
                    expanded: expanded,
                    selected: chat.currentSection == AppSection.runtimeState,
                    onTap: () => _navigate(
                        () => chat.setCurrentSection(AppSection.runtimeState)),
                  ),
                  if (chat.currentAdventureId case final adventureId?) ...[
                    _NavigationHeading(l10n.workbenchCurrentAdventure),
                    _NavItem(
                      icon: 'book',
                      label: l10n.workbenchStory,
                      expanded: expanded,
                      selected: chat.currentSection == AppSection.adventure &&
                          chat.isAdventureChatOpen,
                      onTap: () => _navigate(
                          () => unawaited(chat.openAdventure(adventureId))),
                    ),
                    _NavItem(
                      icon: 'characters',
                      label: l10n.sceneCharactersTitle,
                      expanded: expanded,
                      selected:
                          chat.currentSection == AppSection.sceneCharacters,
                      onTap: () => _navigate(() =>
                          chat.setCurrentSection(AppSection.sceneCharacters)),
                    ),
                  ],
                  if (showRecents) ...[
                    _NavigationHeading(l10n.workbenchRecentAdventures),
                    if (chat.adventureList.isEmpty)
                      Padding(
                        padding:
                            const EdgeInsets.fromLTRB(8, 0, 8, AppSpacing.sm),
                        child: Text(l10n.noRecentAdventures,
                            style: theme.textTheme.bodySmall),
                      ),
                    for (final item in chat.adventureList)
                      if (item['id'] case final int id)
                        _RecentAdventureRow(
                          title: item['title'] as String? ??
                              l10n.sidebarUnnamedScene,
                          selected: chat.currentAdventureId == id &&
                              chat.currentSection == AppSection.adventure &&
                              chat.isAdventureChatOpen,
                          onTap: () => _navigate(
                              () => unawaited(chat.openAdventure(id))),
                          onDelete: () => _delete(
                              id,
                              item['title'] as String? ??
                                  l10n.sidebarUnnamedScene),
                        ),
                    if (chat.adventureList.isNotEmpty)
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton(
                          onPressed: () => _navigate(() => unawaited(
                              AppRouter.push<void>(context,
                                  pageBuilder: (_) =>
                                      const ConversationManagePage()))),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            minimumSize: const Size(0, 30),
                          ),
                          child: Text(
                            l10n.sidebarManageConversations,
                            style: theme.textTheme.labelMedium,
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
            Divider(height: 1, color: scheme.outlineVariant),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _NavItem(
                    icon: 'add',
                    label: l10n.sidebarNewAdventure,
                    expanded: expanded,
                    onTap: () => _navigate(chat.navigateToAdventureHome),
                  ),
                  _NavItem(
                    icon: 'settings',
                    label: l10n.sidebarSystemSettings,
                    expanded: expanded,
                    selected: chat.currentSection == AppSection.settings,
                    onTap: () => _navigate(
                        () => chat.setCurrentSection(AppSection.settings)),
                  ),
                  if (expanded && !chat.isKeyConfigured)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                      child: Text(l10n.serviceNotConfigured,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: scheme.error)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (!widget.permanent) return Drawer(child: content);
    final width = switch (mode) {
      WorkbenchSidebarMode.rail => _railWidth,
      WorkbenchSidebarMode.compact => _compactWidth,
      WorkbenchSidebarMode.full => _fullWidth,
    };
    return SizedBox(
      width: width,
      child: DecoratedBox(
        decoration: BoxDecoration(
            border: Border(right: BorderSide(color: scheme.outlineVariant))),
        child: content,
      ),
    );
  }

  Widget _buildBrandRow(
    BuildContext context,
    AppLocalizations l10n,
    ChatProvider chat,
    bool expanded,
  ) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(expanded ? 14 : 0, 10, 6, 6),
      child: Row(
        children: [
          if (expanded)
            Expanded(
              child: Text(
                l10n.appTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall,
              ),
            ),
          if (widget.permanent)
            IconButton(
              key: const Key('sidebar-toggle'),
              tooltip: expanded ? l10n.sidebarCollapse : l10n.sidebarExpand,
              onPressed: chat.toggleMainSidebarExpanded,
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              icon: const AppSvgIcon('panel', size: 18),
            ),
        ],
      ),
    );
  }
}

/// Quiet section heading inside the sidebar.
class _NavigationHeading extends StatelessWidget {
  const _NavigationHeading(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 14, 8, 4),
      child: Text(
        title,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

/// A workspace destination row.
///
/// Selected state: 10% accent tint + 2 px leading indicator + accent icon +
/// stronger label, at 32 px height and 6 px radius.
class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.expanded,
    required this.onTap,
    this.selected = false,
  });

  final String icon;
  final String label;
  final bool expanded;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final iconColor = selected ? scheme.primary : scheme.onSurfaceVariant;
    final labelColor = selected ? scheme.onSurface : scheme.onSurfaceVariant;

    if (!expanded) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Tooltip(
          message: label,
          child: Material(
            color: selected
                ? scheme.primary.withValues(alpha: 0.10)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(6),
              hoverColor: scheme.onSurface.withValues(alpha: 0.04),
              child: SizedBox(
                height: 34,
                child:
                    Center(child: AppSvgIcon(icon, size: 18, color: iconColor)),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: selected
            ? scheme.primary.withValues(alpha: 0.10)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          hoverColor: scheme.onSurface.withValues(alpha: 0.04),
          child: SizedBox(
            height: 32,
            child: Row(
              children: [
                SizedBox(
                  width: 2,
                  height: 16,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: selected ? scheme.primary : Colors.transparent,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                AppSvgIcon(icon, size: 16, color: iconColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: labelColor,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A saved adventure inside the sidebar's recent list.
class _RecentAdventureRow extends StatelessWidget {
  const _RecentAdventureRow(
      {required this.title,
      required this.selected,
      required this.onTap,
      required this.onDelete});
  final String title;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: selected
            ? scheme.primary.withValues(alpha: 0.10)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          hoverColor: scheme.onSurface.withValues(alpha: 0.04),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 2, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color:
                          selected ? scheme.onSurface : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                IconButton(
                    tooltip: l10n.sidebarDeleteTooltip,
                    onPressed: onDelete,
                    visualDensity: VisualDensity.compact,
                    iconSize: 16,
                    icon: const AppSvgIcon('delete', size: 16)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
