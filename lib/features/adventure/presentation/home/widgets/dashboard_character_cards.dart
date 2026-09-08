import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_radius.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/widgets/app_card.dart';
import '../../../../../core/widgets/app_empty_state.dart';
import '../../../../../models/character_card_entry.dart';
import '../../../../../providers/riverpod_providers.dart';

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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.badge_outlined,
              size: 20,
              color: scheme.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
                child: Text(
              '我的角色卡档案',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            )),
            if (_cards.isNotEmpty && widget.onCreateCharacter != null)
              TextButton.icon(
                onPressed: widget.onCreateCharacter,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('新建角色卡'),
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
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: AppEmptyState(
              icon: Icons.person_off_outlined,
              title: '暂无角色卡档案',
              description: '当前未创建任何角色。你可以在资料库中塑造你的主角或同伴人设，并在冒险时选择他们出战。',
              actionLabel: widget.onCreateCharacter != null ? '前往角色卡库' : null,
              onAction: widget.onCreateCharacter,
              iconSize: 44,
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final isDesktop = constraints.maxWidth >= 720;
              final crossAxisCount = isDesktop ? 2 : 1;

              final cardWidth = (constraints.maxWidth -
                      AppSpacing.md * (crossAxisCount - 1)) /
                  crossAxisCount;
              // Cards grow with text instead of imposing a fixed grid extent.
              return Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: List.generate(_cards.length, (index) {
                  final card = _cards[index];
                  final name = card.name.isNotEmpty ? card.name : '未命名角色';
                  final profession =
                      card.profession.isNotEmpty ? card.profession : '探险者';
                  final personality = card.personality.isNotEmpty
                      ? card.personality
                      : (card.background.isNotEmpty
                          ? card.background
                          : '暂无背景描述');

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
                                  radius: 16,
                                  backgroundColor: scheme.primaryContainer,
                                  child: Text(
                                    name.isNotEmpty
                                        ? name[0].toUpperCase()
                                        : '?',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: scheme.onPrimaryContainer,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        profession,
                                        style: TextStyle(
                                          fontSize: 12,
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
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: scheme.surfaceContainerHighest,
                                      borderRadius:
                                          BorderRadius.circular(AppRadius.xs),
                                    ),
                                    child: Text(
                                      card.gender,
                                      style: TextStyle(
                                        fontSize: 11,
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
                                style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.onSurfaceVariant,
                                  height: 1.4,
                                ),
                              ),
                            ),
                            Align(
                              alignment: Alignment.bottomRight,
                              child: FilledButton.tonalIcon(
                                onPressed: () => widget.onSelectCharacter(card),
                                icon: const Icon(Icons.play_arrow_rounded,
                                    size: 16),
                                label: const Text('以此角色启程'),
                              ),
                            ),
                          ],
                        ),
                      ));
                }),
              );
            },
          ),
      ],
    );
  }
}
