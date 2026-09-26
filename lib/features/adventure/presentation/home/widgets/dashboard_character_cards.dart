import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_dimensions.dart';
import '../../../../../core/theme/app_radius.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/widgets/app_card.dart';
import '../../../../../core/widgets/app_empty_state.dart';
import '../../../../../models/character_card_entry.dart';
import '../../../../../providers/riverpod_providers.dart';
import '../../../../../l10n/generated/app_localizations.dart';
import '../../../../../l10n/generated/app_localizations_zh.dart';

AppLocalizations _l10n(BuildContext context) =>
    AppLocalizations.of(context) ?? AppLocalizationsZh();

/// 首页“我的角色卡档案”流 (联动资料库 · 零预设白板)
class DashboardCharacterCards extends ConsumerStatefulWidget {
  final VoidCallback? onCreateCharacter;
  final ValueChanged<CharacterCardEntry> onSelectCharacter;

  const DashboardCharacterCards({
    super.key,
    this.onCreateCharacter,
    required this.onSelectCharacter,
  });

  @override
  ConsumerState<DashboardCharacterCards> createState() =>
      _DashboardCharacterCardsState();
}

class _DashboardCharacterCardsState
    extends ConsumerState<DashboardCharacterCards> {
  List<CharacterCardEntry> _cards = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadCards();
    });
  }

  Future<void> _loadCards() async {
    try {
      final setupController = ref.read(adventureSetupControllerProvider);
      await setupController.loadInitialData();
      if (mounted) {
        setState(() {
          _cards = setupController.characterCardEntries;
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
              Icons.badge_outlined,
              size: 18,
              color: scheme.primary,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                l10n.dashboardMyCharacterCards,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (_cards.isNotEmpty && widget.onCreateCharacter != null)
              TextButton.icon(
                onPressed: widget.onCreateCharacter,
                icon: const Icon(Icons.add, size: 15),
                label: Text(l10n.characterCardCreateTitle),
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
        else if (_cards.isEmpty)
          AppCard(
            padding: const EdgeInsets.symmetric(
              vertical: AppSpacing.lg,
              horizontal: AppSpacing.md,
            ),
            child: AppEmptyState(
              icon: Icons.person_off_outlined,
              title: l10n.dashboardNoCharacterCardsTitle,
              description: l10n.dashboardNoCharacterCardsDesc,
              actionLabel: widget.onCreateCharacter != null
                  ? l10n.dashboardGoToCharacterLibrary
                  : null,
              onAction: widget.onCreateCharacter,
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
                children: List.generate(_cards.length, (index) {
                  final card = _cards[index];
                  final name = card.name.isNotEmpty
                      ? card.name
                      : l10n.characterCardUnnamed;
                  final profession = card.profession.isNotEmpty
                      ? card.profession
                      : l10n.dashboardDefaultProfession;
                  final personality = card.personality.isNotEmpty
                      ? card.personality
                      : (card.background.isNotEmpty
                          ? card.background
                          : l10n.dashboardNoBackgroundDesc);

                  return SizedBox(
                    width: cardWidth,
                    child: AppCard(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 15,
                                backgroundColor: scheme.surfaceContainerHigh,
                                child: Text(
                                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: scheme.onSurface,
                                  ),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style:
                                          theme.textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      profession,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: scheme.primary,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (card.gender.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: scheme.surfaceContainerHighest,
                                    borderRadius:
                                        BorderRadius.circular(AppRadius.xs),
                                  ),
                                  child: Text(
                                    card.gender,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: scheme.onSurfaceVariant,
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
                              personality,
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
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                minHeight: AppDimensions.controlHeightSm,
                              ),
                              child: FilledButton.tonalIcon(
                                onPressed: () => widget.onSelectCharacter(card),
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
                                label: Text(l10n.dashboardStartWithCharacter),
                              ),
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
