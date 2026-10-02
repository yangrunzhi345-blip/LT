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
import '../../../../../widgets/app_dialogs.dart';
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

  void _handleOpenWizard(
    BuildContext context, {
    AdventureConfig? initialConfig,
    String? initialWorldviewId,
    String? initialCharacterId,
  }) {
    AppRouter.push<void>(
      context,
      pageBuilder: (_) => AssemblyCreatePage(
        onStartAdventure: onStartAdventure,
        initialConfig: initialConfig,
        initialWorldviewId: initialWorldviewId,
        initialCharacterId: initialCharacterId,
      ),
    );
  }

  void _handleOpenLibrary(WidgetRef ref) {
    ref.read(chatProvider).openResourceLibrary(ResourceLibraryMode.adventure);
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
                              onOpenLibrary: () => _handleOpenLibrary(ref),
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
                                    onCreateWorld: () =>
                                        _handleOpenLibrary(ref),
                                    onSelectWorld: (config) {
                                      final chatInstance =
                                          ref.read(chatProvider);
                                      if (!chatInstance.isKeyConfigured) {
                                        showApiSettings(context);
                                        return;
                                      }
                                      _handleOpenWizard(
                                        context,
                                        initialConfig: config,
                                      );
                                    },
                                  ),
                                  const SizedBox(
                                      height: DashboardMetrics.subsectionGap),
                                  DashboardCharacterCards(
                                    onCreateCharacter: () =>
                                        _handleOpenLibrary(ref),
                                    onSelectCharacter: (card) {
                                      final chatInstance =
                                          ref.read(chatProvider);
                                      if (!chatInstance.isKeyConfigured) {
                                        showApiSettings(context);
                                        return;
                                      }
                                      _handleOpenWizard(
                                        context,
                                        initialCharacterId: card.id,
                                        initialConfig: AdventureConfig(
                                          name: card.name,
                                          gender: card.gender,
                                          age: card.age,
                                          protagonistClass: card.profession,
                                          personality: card.personality,
                                          protagonistBackground:
                                              card.background,
                                        ),
                                      );
                                    },
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
