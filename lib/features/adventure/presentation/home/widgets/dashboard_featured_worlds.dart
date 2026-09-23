import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_radius.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/widgets/app_card.dart';
import '../../../../../core/widgets/app_empty_state.dart';
import '../../../../../models/adventure_config.dart';
import '../../../../../providers/riverpod_providers.dart';
import '../../../../../l10n/generated/app_localizations.dart';
import '../../../../../l10n/generated/app_localizations_zh.dart';

AppLocalizations _l10n(BuildContext context) =>
    AppLocalizations.of(context) ?? AppLocalizationsZh();

/// 用户自定义世界设定流 (遵循零预设 · 纯净白板准则)
class DashboardFeaturedWorlds extends ConsumerStatefulWidget {
  final ValueChanged<AdventureConfig> onSelectWorld;
  final VoidCallback? onCreateWorld;

  const DashboardFeaturedWorlds({
    super.key,
    required this.onSelectWorld,
    this.onCreateWorld,
  });

  @override
  ConsumerState<DashboardFeaturedWorlds> createState() =>
      _DashboardFeaturedWorldsState();
}

class _DashboardFeaturedWorldsState
    extends ConsumerState<DashboardFeaturedWorlds> {
  List<Map<String, dynamic>> _userWorlds = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadUserWorlds();
    });
  }

  Future<void> _loadUserWorlds() async {
    try {
      final setupController = ref.read(adventureSetupControllerProvider);
      await setupController.loadInitialData();
      if (mounted) {
        setState(() {
          _userWorlds = setupController.worldviewPresets;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.public_rounded,
              size: 18,
              color: scheme.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l10n.dashboardMyWorldSettings,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (_userWorlds.isNotEmpty && widget.onCreateWorld != null)
              TextButton.icon(
                onPressed: widget.onCreateWorld,
                icon: const Icon(Icons.add, size: 15),
                label: Text(l10n.worldviewCreateAction),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (_userWorlds.isEmpty)
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: AppEmptyState(
              icon: Icons.public_off_outlined,
              title: l10n.dashboardNoCustomWorldsTitle,
              description: l10n.dashboardNoCustomWorldsDesc,
              actionLabel: widget.onCreateWorld != null
                  ? l10n.dashboardGoToLibrary
                  : null,
              onAction: widget.onCreateWorld,
              iconSize: 36,
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final isDesktop = constraints.maxWidth >= 640;
              final crossAxisCount = isDesktop ? 2 : 1;

              final cardWidth = (constraints.maxWidth -
                      AppSpacing.md * (crossAxisCount - 1)) /
                  crossAxisCount;

              return Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.sm,
                children: List.generate(_userWorlds.length, (index) {
                  final wv = _userWorlds[index];
                  final name = wv['name'] as String? ?? l10n.unnamedWorldview;
                  final desc =
                      wv['description'] as String? ?? l10n.dashboardNoWorldDesc;

                  return SizedBox(
                    width: cardWidth,
                    child: AppCard(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(5),
                                decoration: BoxDecoration(
                                  color: scheme.primaryContainer,
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.xs),
                                ),
                                child: Icon(
                                  Icons.public_outlined,
                                  size: 15,
                                  color: scheme.onPrimaryContainer,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Padding(
                            padding:
                                const EdgeInsets.only(bottom: AppSpacing.sm),
                            child: Text(
                              desc,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                                fontSize: 11,
                                height: 1.35,
                              ),
                            ),
                          ),
                          Align(
                            alignment: Alignment.bottomRight,
                            child: FilledButton.tonalIcon(
                              onPressed: () {
                                widget.onSelectWorld(
                                  AdventureConfig(
                                    worldview: name,
                                    worldviewSnapshot: {
                                      'name': name,
                                      'description': desc,
                                    },
                                  ),
                                );
                              },
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                visualDensity: VisualDensity.compact,
                              ),
                              icon: const Icon(
                                Icons.play_arrow_rounded,
                                size: 14,
                              ),
                              label: Text(l10n.dashboardStartWithWorld),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              );
            },
          ),
      ],
    );
  }
}
