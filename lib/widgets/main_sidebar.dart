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
                  _SidebarSectionBoundary(
                    title: l10n.workbenchWorkspace,
                    expanded: expanded,
                    showRailDivider: false,
                  ),
                  _NavItem(
                    key: const Key('sidebar-nav-adventure'),
                    icon: 'adventure',
                    label: l10n.navExplore,
                    expanded: expanded,
                    selected: (chat.currentSection == AppSection.adventure &&
                            !chat.isAdventureChatOpen) ||
                        chat.currentSection == AppSection.home,
                    onTap: () => _navigate(chat.navigateToAdventureHome),
                  ),
                  _NavItem(
                    key: const Key('sidebar-nav-resources'),
                    icon: 'resources',
                    label: l10n.navLibrary,
                    expanded: expanded,
                    selected: chat.currentSection == AppSection.resources,
                    onTap: () => _navigate(() => chat
                        .openResourceLibrary(ResourceLibraryMode.adventure)),
                  ),
                  _NavItem(
                    key: const Key('sidebar-nav-trash'),
                    icon: 'delete',
                    label: l10n.recycleBinTitle,
                    expanded: expanded,
                    selected: chat.currentSection == AppSection.trash,
                    onTap: () => _navigate(
                        () => chat.setCurrentSection(AppSection.trash)),
                  ),
                  _NavItem(
                    key: const Key('sidebar-nav-runtime'),
                    icon: 'state',
                    label: l10n.runtimeStateCurrent,
                    expanded: expanded,
                    selected: chat.currentSection == AppSection.runtimeState,
                    onTap: () => _navigate(
                        () => chat.setCurrentSection(AppSection.runtimeState)),
                  ),
                  if (chat.currentAdventureId case final adventureId?) ...[
                    _SidebarSectionBoundary(
                      title: l10n.workbenchCurrentAdventure,
                      expanded: expanded,
                      railDividerKey:
                          const Key('sidebar-current-adventure-divider'),
                    ),
                    _NavItem(
                      key: const Key('sidebar-nav-story'),
                      icon: 'book',
                      label: l10n.workbenchStory,
                      expanded: expanded,
                      selected: chat.currentSection == AppSection.adventure &&
                          chat.isAdventureChatOpen,
                      onTap: () => _navigate(
                          () => unawaited(chat.openAdventure(adventureId))),
                    ),
                    _NavItem(
                      key: const Key('sidebar-nav-characters'),
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
                    key: const Key('sidebar-nav-new-adventure'),
                    icon: 'add',
                    label: l10n.sidebarNewAdventure,
                    expanded: expanded,
                    onTap: () => _navigate(chat.navigateToAdventureHome),
                  ),
                  _NavItem(
                    key: const Key('sidebar-nav-settings'),
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
    final toggle = widget.permanent
        ? IconButton(
            key: const Key('sidebar-toggle'),
            tooltip: expanded ? l10n.sidebarCollapse : l10n.sidebarExpand,
            onPressed: chat.toggleMainSidebarExpanded,
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            icon: const AppSvgIcon('panel', size: 18),
          )
        : null;

    // Collapsed rail: the rail's centerline is the single horizontal
    // authority. Centring the toggle in a full-width slot keeps it on the same
    // axis as every navigation icon; reusing the expanded row's asymmetric
    // `fromLTRB(0, …, 6, …)` padding would push it ~8 px to the left.
    if (!expanded) {
      return Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 6),
        child: _SidebarRailSlot(child: toggle ?? const SizedBox.shrink()),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              l10n.appTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall,
            ),
          ),
          if (toggle != null) toggle,
        ],
      ),
    );
  }
}

/// A full-width, fixed-height slot that centres its child on the rail's
/// centerline.
///
/// The collapsed rail aligns every control — brand toggle, navigation icons and
/// bottom actions — through this one slot so they share `railWidth / 2`. The
/// slot must never carry asymmetric padding; that is what previously skewed the
/// toggle off the navigation axis.
class _SidebarRailSlot extends StatelessWidget {
  const _SidebarRailSlot({required this.child});

  final Widget child;

  static const double height = 34;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        height: height,
        child: Center(child: child),
      );
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

/// The single presentation policy for a navigation section header.
///
/// Expanded (compact/full) sidebars render the quiet text [title]; the 56 px
/// rail must never render a text heading — a narrow column would wrap
/// "当前冒险" one glyph per line and distort the whole rail. Instead the rail
/// shows either nothing (the first, top-most group) or a restrained divider
/// that separates the current-adventure group from the workspace group.
///
/// Keeping this decision in one widget means every group shares an explicit
/// policy rather than re-deriving `if (expanded)` at each call site.
class _SidebarSectionBoundary extends StatelessWidget {
  const _SidebarSectionBoundary({
    required this.title,
    required this.expanded,
    this.showRailDivider = true,
    this.railDividerKey,
  });

  final String title;
  final bool expanded;

  /// Whether the collapsed rail substitutes a divider for the heading. The
  /// first group (workspace) sits at the top and needs no separator.
  final bool showRailDivider;

  /// Identifies the rail divider for geometry regression tests.
  final Key? railDividerKey;

  @override
  Widget build(BuildContext context) {
    if (expanded) return _NavigationHeading(title);
    if (!showRailDivider) return const SizedBox.shrink();
    return _SidebarRailSectionDivider(key: railDividerKey);
  }
}

/// A very quiet horizontal separator between rail groups.
///
/// Centred on the rail centerline (a 24 px rule inside the full-width slot),
/// themed through [ColorScheme.outlineVariant] so light and dark share the
/// same contract. It is decorative, so it is excluded from semantics.
class _SidebarRailSectionDivider extends StatelessWidget {
  const _SidebarRailSectionDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: SizedBox(
        height: 14,
        width: double.infinity,
        child: Center(
          child: SizedBox(
            width: 24,
            child:
                Divider(height: 1, thickness: 1, color: scheme.outlineVariant),
          ),
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
    super.key,
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
      return Semantics(
        selected: selected,
        button: true,
        child: Padding(
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
                  child: Center(
                      child: AppSvgIcon(icon, size: 18, color: iconColor)),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Semantics(
      selected: selected,
      button: true,
      child: Padding(
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
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
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
