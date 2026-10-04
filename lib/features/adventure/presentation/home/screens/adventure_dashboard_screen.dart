import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/refresh/page_refresh_scope.dart';
import '../../../../../core/responsive/responsive.dart';
import '../../../../../core/router/app_router.dart';
import '../../../../../core/theme/app_dimensions.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../models/adventure_config.dart';
import '../../../../../models/app_section.dart';
import '../../../../../models/resource_library_mode.dart';
import '../../../../../providers/riverpod_providers.dart';
import '../../../../resource_library/domain/models/resource_library_view_state.dart';
import '../../../../../l10n/generated/app_localizations.dart';
import '../../../../../l10n/generated/app_localizations_zh.dart';
import '../../templates/screens/preset_scenes_screen.dart';
import '../../wizard/screens/assembly_create_page.dart';
import '../widgets/dashboard_section.dart';
import '../widgets/dashboard_start_actions.dart';
import '../widgets/dashboard_character_cards.dart';
import '../widgets/dashboard_featured_worlds.dart';
import '../widgets/dashboard_hero_header.dart';
import '../widgets/dashboard_recent_saves.dart';
import '../widgets/dashboard_state_section.dart';

/// 现代化全新冒险大厅 / 探索工坊主屏
/// 遵循 Editorial 版式设计，内容优先，大屏居中受控，320px 零溢出
class AdventureDashboardScreen extends ConsumerWidget {
  final Future<void> Function(AdventureConfig config, {String? difficulty})
      onStartAdventure;

  /// Compact navigation drawer opener only. On desktop / medium the permanent
  /// [MainSidebar] owns collapse / expand, so this is never rendered there.
  final VoidCallback? onMenuPressed;

  const AdventureDashboardScreen({
    super.key,
    required this.onStartAdventure,
    this.onMenuPressed,
  });

  /// Launches the Adventure setup wizard. This is the *only* home entry that
  /// may start a new adventure; existing resources are browsed via the library.
  void _handleOpenWizard(BuildContext context) {
    AppRouter.push<void>(
      context,
      pageBuilder: (_) => AssemblyCreatePage(
        onStartAdventure: onStartAdventure,
      ),
    );
  }

  /// Opens the Resource Library on the given top-level view (e.g. 世界观 / 角色)
  /// for an *existing* resource. This is browsing, never creation.
  void _handleOpenLibrary(WidgetRef ref, ResourceLibraryFilter filter) {
    ref.read(chatProvider).openResourceLibrary(
          ResourceLibraryMode.adventure,
          initialFilter: filter,
        );
  }

  /// Opens an existing resource's detail page by deep-linking the Resource
  /// Library to that resource. Never starts a creation/assembly wizard.
  void _handleOpenResource(
    WidgetRef ref,
    ResourceLibraryItem resource,
    ResourceLibraryFilter filter,
  ) {
    ref.read(chatProvider).openResourceLibrary(
          ResourceLibraryMode.adventure,
          initialFilter: filter,
          initialResourceId: resource.id,
        );
  }

  void _handleOpenPresetScenes(BuildContext context) {
    AppRouter.push<void>(
      context,
      pageBuilder: (_) => PresetScenesScreen(
        onStartAdventure: onStartAdventure,
      ),
    );
  }

  void _handleOpenSettings(WidgetRef ref) {
    ref.read(chatProvider).setCurrentSection(AppSection.settings);
  }

  void _handleOpenStateHub(WidgetRef ref) {
    ref.read(chatProvider).setCurrentSection(AppSection.runtimeState);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();
    final chat = ref.watch(chatProvider);
    final hasSaves = chat.adventureList.isNotEmpty;

    return PageRefreshScope(
      onRefresh: () async {
        await ref.read(chatProvider).loadAdventureList();
        return const PageRefreshResult.success();
      },
      child: Scaffold(
        body: Column(
          children: [
            DashboardHeroHeader(
              onMenuPressed: onMenuPressed,
              onOpenSettings: () => _handleOpenSettings(ref),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isCompact =
                      constraints.maxWidth < AppBreakpoints.mediumMin;
                  final horizontalPadding =
                      isCompact ? AppSpacing.md : AppSpacing.xl;

                  return AppRefreshIndicator(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: AppDimensions.maxContentWidth,
                        ),
                        child: ListView(
                          padding: EdgeInsets.symmetric(
                            horizontal: horizontalPadding,
                            vertical: AppSpacing.lg,
                          ),
                          children: [
                            // A. STORY — only when the user has one. The most
                            // recent adventure leads as the primary continue
                            // action, ahead of any "start something new" entry.
                            if (hasSaves) ...[
                              const DashboardRecentSaves(),
                              const SizedBox(height: DashboardMetrics.groupGap),
                            ],

                            // B. START — onboarding when empty, a quiet "new"
                            // entry once a story exists (exactly one start
                            // onboarding, never a duplicate empty section).
                            DashboardStartActions(
                              hasAdventure: hasSaves,
                              onOpenWizard: () => _handleOpenWizard(context),
                              onOpenPresetScenes: () =>
                                  _handleOpenPresetScenes(context),
                              onOpenLibrary: () => _handleOpenLibrary(
                                  ref, ResourceLibraryFilter.all),
                            ),
                            const SizedBox(height: DashboardMetrics.groupGap),

                            // C. LIBRARY — worlds and characters are one
                            // "your library" region with two subsections.
                            DashboardGroup(
                              key: const Key('dashboard-group-library'),
                              title: l10n.dashboardYourLibrary,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  DashboardFeaturedWorlds(
                                    onOpenLibrary: () => _handleOpenLibrary(
                                        ref, ResourceLibraryFilter.worldview),
                                    onOpenResource: (resource) =>
                                        _handleOpenResource(
                                      ref,
                                      resource,
                                      ResourceLibraryFilter.worldview,
                                    ),
                                  ),
                                  const SizedBox(
                                      height: DashboardMetrics.subsectionGap),
                                  DashboardCharacterCards(
                                    onOpenLibrary: () => _handleOpenLibrary(
                                        ref, ResourceLibraryFilter.character),
                                    onOpenResource: (resource) =>
                                        _handleOpenResource(
                                      ref,
                                      resource,
                                      ResourceLibraryFilter.character,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: DashboardMetrics.groupGap),

                            // D. RUNTIME — state hub entry.
                            DashboardStateSection(
                              onOpenStateHub: () => _handleOpenStateHub(ref),
                            ),
                            const SizedBox(height: AppSpacing.xl),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
