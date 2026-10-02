import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/widgets/app_svg_icon.dart';
import '../../../../../core/widgets/workbench_chrome.dart';
import '../../../../../l10n/generated/app_localizations.dart';
import '../../../../../l10n/generated/app_localizations_zh.dart';
import '../../../../../models/app_section.dart';
import '../../../../../providers/riverpod_providers.dart';
import '../../../../../screens/chat/widgets/inventory_screen.dart';
import '../widgets/session_inspector.dart';
import 'model_select_page.dart';

/// The session Inspector as a real page.
///
/// Every viewport reaches inspection through `Navigator.push` — never a modal
/// bottom sheet, dialog, overlay or inline side pane. Returning the last
/// selected [SessionInspectorSection] through `Navigator.pop` lets the host
/// session restore it without this page reaching into the host's state.
class SessionInspectorPage extends ConsumerStatefulWidget {
  const SessionInspectorPage(
      {super.key, this.initialSection = SessionInspectorSection.scene});

  final SessionInspectorSection initialSection;

  @override
  ConsumerState<SessionInspectorPage> createState() =>
      _SessionInspectorPageState();
}

class _SessionInspectorPageState extends ConsumerState<SessionInspectorPage> {
  late SessionInspectorSection _section;

  @override
  void initState() {
    super.initState();
    _section = widget.initialSection;
  }

  void _back() => Navigator.of(context).pop(_section);

  /// Leaves the Inspector for a main-workspace section.
  ///
  /// The Inspector route is popped first so the workspace section is never
  /// covered by a stale route stacked on top of it.
  void _openMainSection(AppSection section) {
    final chat = ref.read(chatProvider);
    Navigator.of(context).pop(_section);
    chat.setCurrentSection(section);
  }

  /// Inventory and model selection are ordinary pushed routes; returning from
  /// them lands back on the Inspector.
  void _openInventory() {
    final chat = ref.read(chatProvider);
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => InventoryScreen(
        adventureId: chat.currentAdventureId,
        legacyInventory: chat.gameState.inventory,
      ),
    ));
  }

  void _openModel() {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => const ModelSelectPage(applyOnSelection: true)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();
    final theme = Theme.of(context);
    final labels = <SessionInspectorSection, String>{
      SessionInspectorSection.scene: l10n.workbenchScene,
      SessionInspectorSection.characters: l10n.charactersTab,
      SessionInspectorSection.state: l10n.runtimeStateCurrent,
      SessionInspectorSection.context: l10n.workbenchContext,
      SessionInspectorSection.generation: l10n.workbenchGeneration,
    };
    return PopScope<SessionInspectorSection>(
      // Return the active section even when leaving through the system back
      // gesture, so the host can restore it.
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.of(context).pop(_section);
      },
      child: Scaffold(
        key: const Key('session-inspector-page'),
        backgroundColor: theme.colorScheme.surface,
        appBar: AppBar(
          elevation: 0,
          scrolledUnderElevation: 0,
          toolbarHeight: 48,
          titleSpacing: 0,
          leading: IconButton(
            tooltip: l10n.backAction,
            icon: const AppSvgIcon('back'),
            onPressed: _back,
          ),
          title: Text(
            l10n.workbenchInspector,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium,
          ),
        ),
        body: Column(
          children: [
            WorkbenchToolbar(
              child: WorkbenchTabBar(
                children: [
                  for (final entry in labels.entries)
                    WorkbenchTabButton(
                      key: ValueKey('inspector-${entry.key.name}'),
                      label: entry.value,
                      selected: _section == entry.key,
                      onTap: () => setState(() => _section = entry.key),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SessionInspectorContent(
                section: _section,
                onCharacters: () =>
                    _openMainSection(AppSection.sceneCharacters),
                onState: () => _openMainSection(AppSection.runtimeState),
                onInventory: _openInventory,
                onModel: _openModel,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
