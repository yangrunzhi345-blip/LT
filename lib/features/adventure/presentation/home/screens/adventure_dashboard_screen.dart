import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/refresh/page_refresh_scope.dart';
import '../../../../../core/router/app_router.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../models/adventure_config.dart';
import '../../../../../models/app_section.dart';
import '../../../../../models/resource_library_mode.dart';
import '../../../../../providers/riverpod_providers.dart';
import '../../../../../widgets/app_dialogs.dart';
import '../../templates/screens/preset_scenes_screen.dart';
import '../../wizard/screens/adventure_wizard_screen.dart';
import '../widgets/dashboard_action_cards.dart';
import '../widgets/dashboard_character_cards.dart';
import '../widgets/dashboard_featured_worlds.dart';
import '../widgets/dashboard_hero_header.dart';
import '../widgets/dashboard_recent_saves.dart';

/// 现代化全新冒险大厅 / 探索工坊主屏
class AdventureDashboardScreen extends ConsumerWidget {
  final Future<void> Function(AdventureConfig config, {String? difficulty})
      onStartAdventure;
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
      pageBuilder: (_) => AdventureWizardScreen(
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
              child: AppRefreshIndicator(
                child: ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xl,
                    vertical: AppSpacing.xl,
                  ),
                  children: [
                    // 核心启动卡片组
                    DashboardActionCards(
                      onOpenWizard: () => _handleOpenWizard(context),
                      onOpenPresetScenes: () =>
                          _handleOpenPresetScenes(context),
                      onOpenLibrary: () => _handleOpenLibrary(ref),
                      onOpenSettings: () => _handleOpenSettings(ref),
                    ),
                    const SizedBox(height: AppSpacing.xl),

                    // 继续未尽的场景记录
                    const DashboardRecentSaves(),
                    const SizedBox(height: AppSpacing.xl),

                    // 我的世界设定流 (零预设/纯净白板 · 联动资料库)
                    DashboardFeaturedWorlds(
                      onCreateWorld: () => _handleOpenLibrary(ref),
                      onSelectWorld: (config) {
                        final chat = ref.read(chatProvider);
                        if (!chat.isKeyConfigured) {
                          showApiSettings(context);
                          return;
                        }
                        _handleOpenWizard(context, initialConfig: config);
                      },
                    ),
                    const SizedBox(height: AppSpacing.xl),

                    // 我的角色卡档案流 (零预设/纯净白板 · 联动资料库)
                    DashboardCharacterCards(
                      onCreateCharacter: () => _handleOpenLibrary(ref),
                      onSelectCharacter: (card) {
                        final chat = ref.read(chatProvider);
                        if (!chat.isKeyConfigured) {
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
                            protagonistBackground: card.background,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
