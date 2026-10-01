import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/router/app_router.dart';
import '../core/theme/app_spacing.dart';
import '../core/widgets/app_confirm_dialog.dart';
import '../core/widgets/app_svg_icon.dart';
import '../features/adventure/presentation/session/screens/conversation_manage_page.dart';
import '../l10n/generated/app_localizations.dart';
import '../l10n/generated/app_localizations_zh.dart';
import '../models/app_section.dart';
import '../models/resource_library_mode.dart';
import '../providers/riverpod_providers.dart';

Widget buildMainSidebar(
  BuildContext context,
  GlobalKey<ScaffoldState> scaffoldKey, {
  bool permanent = false,
}) =>
    MainSidebar(scaffoldKey: scaffoldKey, permanent: permanent);

/// Persistent workspace navigation, with contextual links to the active story.
class MainSidebar extends ConsumerStatefulWidget {
  const MainSidebar(
      {super.key, required this.scaffoldKey, this.permanent = false});

  final GlobalKey<ScaffoldState> scaffoldKey;
  final bool permanent;

  @override
  ConsumerState<MainSidebar> createState() => _MainSidebarState();
}

class _MainSidebarState extends ConsumerState<MainSidebar> {
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
    final expanded = !widget.permanent || chat.isMainSidebarExpanded;
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();
    final content = Material(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Row(
                children: [
                  if (expanded)
                    Expanded(
                        child: Text(l10n.appTitle,
                            style: Theme.of(context).textTheme.titleMedium)),
                  if (widget.permanent)
                    IconButton(
                      key: const Key('sidebar-toggle'),
                      tooltip:
                          expanded ? l10n.sidebarCollapse : l10n.sidebarExpand,
                      onPressed: chat.toggleMainSidebarExpanded,
                      icon: const AppSvgIcon('panel'),
                    ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                children: [
                  if (expanded) _NavigationHeading(l10n.workbenchWorkspace),
                  _WorkspaceDestination(
                    name: 'adventure',
                    label: l10n.navExplore,
                    expanded: expanded,
                    selected: (chat.currentSection == AppSection.adventure &&
                            !chat.isAdventureChatOpen) ||
                        chat.currentSection == AppSection.home,
                    onTap: () => _navigate(chat.navigateToAdventureHome),
                  ),
                  _WorkspaceDestination(
                    name: 'resources',
                    label: l10n.navLibrary,
                    expanded: expanded,
                    selected: chat.currentSection == AppSection.resources,
                    onTap: () => _navigate(() => chat
                        .openResourceLibrary(ResourceLibraryMode.adventure)),
                  ),
                  _WorkspaceDestination(
                    name: 'state',
                    label: l10n.runtimeStateCurrent,
                    expanded: expanded,
                    selected: chat.currentSection == AppSection.runtimeState,
                    onTap: () => _navigate(
                        () => chat.setCurrentSection(AppSection.runtimeState)),
                  ),
                  if (chat.currentAdventureId case final adventureId?) ...[
                    if (expanded)
                      _NavigationHeading(l10n.workbenchCurrentAdventure),
                    _WorkspaceDestination(
                      name: 'adventure',
                      label: l10n.workbenchStory,
                      expanded: expanded,
                      selected: chat.currentSection == AppSection.adventure &&
                          chat.isAdventureChatOpen,
                      onTap: () => _navigate(
                          () => unawaited(chat.openAdventure(adventureId))),
                    ),
                    _WorkspaceDestination(
                      name: 'characters',
                      label: l10n.sceneCharactersTitle,
                      expanded: expanded,
                      selected:
                          chat.currentSection == AppSection.sceneCharacters,
                      onTap: () => _navigate(() =>
                          chat.setCurrentSection(AppSection.sceneCharacters)),
                    ),
                  ],
                  if (expanded) ...[
                    _NavigationHeading(l10n.workbenchRecentAdventures),
                    if (chat.adventureList.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        child: Text(l10n.noRecentAdventures,
                            style: Theme.of(context).textTheme.bodySmall),
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
                    Tooltip(
                        message: l10n.sidebarManageConversations,
                        child: TextButton(
                          onPressed: () => _navigate(() => unawaited(
                              AppRouter.push<void>(context,
                                  pageBuilder: (_) =>
                                      const ConversationManagePage()))),
                          child: Text(l10n.sidebarManageConversations),
                        )),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _WorkspaceDestination(
                    name: 'add',
                    label: l10n.sidebarNewAdventure,
                    expanded: expanded,
                    onTap: () => _navigate(chat.navigateToAdventureHome),
                  ),
                  if (expanded && !chat.isKeyConfigured)
                    Text(l10n.serviceNotConfigured,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  _WorkspaceDestination(
                    name: 'settings',
                    label: l10n.sidebarSystemSettings,
                    expanded: expanded,
                    selected: chat.currentSection == AppSection.settings,
                    onTap: () => _navigate(
                        () => chat.setCurrentSection(AppSection.settings)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (!widget.permanent) return Drawer(child: content);
    return SizedBox(
      width: expanded ? 244 : 64,
      child: DecoratedBox(
        decoration: BoxDecoration(
            border: Border(
                right: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant))),
        child: content,
      ),
    );
  }
}

class _NavigationHeading extends StatelessWidget {
  const _NavigationHeading(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 20, 8, 8),
        child: Text(title,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
}

class _WorkspaceDestination extends StatelessWidget {
  const _WorkspaceDestination(
      {required this.name,
      required this.label,
      required this.expanded,
      required this.onTap,
      this.selected = false});
  final String name;
  final String label;
  final bool expanded;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (!expanded) {
      return IconButton(
        tooltip: label,
        onPressed: onTap,
        icon: AppSvgIcon(name,
            color: selected ? scheme.primary : scheme.onSurfaceVariant),
        style: IconButton.styleFrom(
            backgroundColor: selected ? scheme.primaryContainer : null),
      );
    }
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      selected: selected,
      selectedTileColor: scheme.primaryContainer,
      title: Text(label),
      onTap: onTap,
    );
  }
}

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
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 8),
      selected: selected,
      selectedTileColor: Theme.of(context).colorScheme.primaryContainer,
      title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
      onTap: onTap,
      trailing: IconButton(
          tooltip: l10n.sidebarDeleteTooltip,
          onPressed: onDelete,
          icon: const AppSvgIcon('delete', size: 18)),
    );
  }
}
