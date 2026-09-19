import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/refresh/page_refresh_scope.dart';
import '../../../../../core/responsive/responsive.dart';
import '../../../../../core/router/app_router.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../models/adventure_config.dart';
import '../../../../../models/app_section.dart';
import '../../../../../models/resource_library_mode.dart';
import '../../../../../providers/riverpod_providers.dart';
import '../../../../../widgets/app_dialogs.dart';
import '../../templates/screens/preset_scenes_screen.dart';
import '../../wizard/screens/assembly_create_page.dart';
import '../widgets/dashboard_action_cards.dart';
import '../widgets/dashboard_character_cards.dart';
import '../widgets/dashboard_featured_worlds.dart';
import '../widgets/dashboard_hero_header.dart';
import '../widgets/dashboard_recent_saves.dart';

/// 现代化全新冒险大厅 / 探索工坊主屏
/// 遵循 Editorial 版式设计，内容优先，大屏居中受控，320px 零溢出
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                          maxWidth: AppBreakpoints.contentMaxWidth,
                        ),
                        child: ListView(
                          padding: EdgeInsets.symmetric(
                            horizontal: horizontalPadding,
                            vertical: AppSpacing.lg,
                          ),
                          children: [
                            // 当有未尽冒险时，“继续故事”置顶优先呈现
                            if (hasSaves) ...[
                              const DashboardRecentSaves(),
                              const SizedBox(height: AppSpacing.lg),
                            ],

                            // 核心启动卡片组 (向导、预存剧本、资料库、设置)
                            DashboardActionCards(
                              onOpenWizard: () => _handleOpenWizard(context),
                              onOpenPresetScenes: () =>
                                  _handleOpenPresetScenes(context),
                              onOpenLibrary: () => _handleOpenLibrary(ref),
                              onOpenSettings: () => _handleOpenSettings(ref),
                            ),
                            const SizedBox(height: AppSpacing.lg),

                            // 无存档时，显示空状态引导
                            if (!hasSaves) ...[
                              const DashboardRecentSaves(),
                              const SizedBox(height: AppSpacing.lg),
                            ],

                            // 我的世界设定流 (零预设/纯净白板 · 联动资料库)
                            DashboardFeaturedWorlds(
                              onCreateWorld: () => _handleOpenLibrary(ref),
                              onSelectWorld: (config) {
                                final chatInstance = ref.read(chatProvider);
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
                            const SizedBox(height: AppSpacing.lg),

                            // 我的角色卡档案流 (零预设/纯净白板 · 联动资料库)
                            DashboardCharacterCards(
                              onCreateCharacter: () => _handleOpenLibrary(ref),
                              onSelectCharacter: (card) {
                                final chatInstance = ref.read(chatProvider);
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
                                    protagonistBackground: card.background,
                                  ),
                                );
                              },
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
