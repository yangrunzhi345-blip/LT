import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/widgets/app_confirm_dialog.dart';
import '../../../../../core/widgets/app_svg_icon.dart';
import '../../../../../providers/riverpod_providers.dart';
import '../../../../../l10n/generated/app_localizations.dart';
import '../../../../../l10n/generated/app_localizations_zh.dart';

/// Page-level actions. Generation and character tools live in the workbench.
class SessionAppBar extends ConsumerWidget implements PreferredSizeWidget {
  const SessionAppBar(
      {super.key,
      this.onMenuPressed,
      this.onFocusReading,
      this.isFocusReading = false,
      this.onInspector});
  final VoidCallback? onMenuPressed;
  final VoidCallback? onFocusReading;
  final VoidCallback? onInspector;
  final bool isFocusReading;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = ref.watch(chatProvider);
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();
    return AppBar(
      elevation: 0,
      scrolledUnderElevation: 0,
      leading: IconButton(
          tooltip: l10n.backToLobby,
          icon: const AppSvgIcon('back'),
          onPressed: provider.navigateToAdventureHome),
      titleSpacing: 0,
      title: ValueListenableBuilder<int>(
          valueListenable: provider.titleBarVersion,
          builder: (context, _, __) {
            final title = provider.currentTitle.isEmpty
                ? l10n.textAdventureTitle
                : provider.currentTitle;
            return Tooltip(
                message: title,
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium));
          }),
      actions: [
        if (!isFocusReading &&
            onMenuPressed != null &&
            MediaQuery.sizeOf(context).width >= 600)
          IconButton(
              tooltip: l10n.historyAndSidebarAction,
              onPressed: onMenuPressed,
              icon: const AppSvgIcon('panel')),
        if (!isFocusReading)
          IconButton(
              tooltip: l10n.searchConversationAction,
              onPressed: provider.toggleSearch,
              icon: const AppSvgIcon('search')),
        if (onFocusReading != null)
          IconButton(
              key: const Key('session-focus-reading'),
              tooltip: isFocusReading
                  ? l10n.workbenchExitFocusReading
                  : l10n.workbenchFocusReading,
              onPressed: onFocusReading,
              icon: const AppSvgIcon('focus')),
        if (!isFocusReading && onInspector != null)
          IconButton(
              key: const Key('session-inspector-toggle'),
              tooltip: l10n.workbenchInspector,
              onPressed: onInspector,
              icon: const AppSvgIcon('settings')),
        if (!isFocusReading)
          PopupMenuButton<String>(
            tooltip: l10n.moreOptionsAction,
            icon: const AppSvgIcon('more'),
            itemBuilder: (_) => [
              PopupMenuItem(
                  value: 'restart', child: Text(l10n.restartAdventureAction))
            ],
            onSelected: (_) async {
              final confirmed = await AppConfirmDialog.show(
                  context: context,
                  title: l10n.restartAdventureTitle,
                  message: l10n.restartAdventureMessage,
                  confirmLabel: l10n.restartAdventureAction,
                  isDanger: true);
              if (confirmed && context.mounted) provider.restartAdventure();
            },
          ),
      ],
    );
  }
}
