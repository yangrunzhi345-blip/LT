import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/utils/worldview_character_scope_policy.dart';
import '../../../../../models/character_card_entry.dart';
import '../../../../../providers/riverpod_providers.dart';
import 'resource_selection_page.dart';
import '../../../../../l10n/generated/app_localizations.dart';
import '../../../../../l10n/generated/app_localizations_zh.dart';

AppLocalizations _l10n(BuildContext context) =>
    AppLocalizations.of(context) ?? AppLocalizationsZh();

/// 专用于角色卡档案的全屏选择页面 (Character Selection Page)
class CharacterSelectionPage extends ConsumerStatefulWidget {
  final String? selectedWorldviewId;
  final Set<String> initialSelectedIds;
  final bool isMultiSelect;

  const CharacterSelectionPage({
    super.key,
    this.selectedWorldviewId,
    this.initialSelectedIds = const {},
    this.isMultiSelect = true,
  });

  @override
  ConsumerState<CharacterSelectionPage> createState() =>
      _CharacterSelectionPageState();
}

class _CharacterSelectionPageState
    extends ConsumerState<CharacterSelectionPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = ref.read(adventureSetupControllerProvider);
      if (controller.characterCards.isEmpty && !controller.loading) {
        controller.loadInitialData();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n(context);
    final setupController = ref.watch(adventureSetupControllerProvider);
    final cardEntries = setupController.characterCardEntries;
    final isLoading = setupController.loading;
    final error = setupController.characterError;

    // 过滤掉数据损坏的卡片
    final validCards = cardEntries.where((c) => !c.hasParseError).toList()
      ..sort((left, right) {
        final leftRank = WorldviewCharacterScopePolicy.compatibility(
          left.matchingWorldviewId,
          widget.selectedWorldviewId,
        ).index;
        final rightRank = WorldviewCharacterScopePolicy.compatibility(
          right.matchingWorldviewId,
          widget.selectedWorldviewId,
        ).index;
        return leftRank.compareTo(rightRank);
      });

    final items = validCards.map((card) {
      final comp = WorldviewCharacterScopePolicy.compatibility(
        card.matchingWorldviewId,
        widget.selectedWorldviewId,
      );

      final tag = switch (comp) {
        CharacterWorldviewCompatibility.native => l10n.characterCompatNative,
        CharacterWorldviewCompatibility.unbound => l10n.characterCompatUnbound,
        CharacterWorldviewCompatibility.crossWorld =>
          l10n.characterCompatCrossWorld,
      };

      final details = [
        if (card.gender.isNotEmpty) card.gender,
        if (card.age.isNotEmpty) l10n.characterAgeYears(card.age),
        if (card.profession.isNotEmpty) card.profession,
      ].join(' · ');

      final descParts = [
        if (card.personality.isNotEmpty)
          l10n.characterPersonalityPrefix(card.personality),
        if (card.background.isNotEmpty) card.background,
      ];

      return ResourceSelectionItem<CharacterCardEntry>(
        id: card.id,
        title: card.name,
        subtitle: details.isNotEmpty ? details : null,
        description: descParts.isNotEmpty ? descParts.join('\n') : null,
        tag: tag,
        tagColor: comp == CharacterWorldviewCompatibility.native
            ? Colors.teal
            : (comp == CharacterWorldviewCompatibility.unbound
                ? Colors.blueGrey
                : Colors.deepPurple),
        icon: Icons.person_rounded,
        data: card,
      );
    }).toList();

    return ResourceSelectionPage<CharacterCardEntry>(
      title: l10n.characterSelectionTitle,
      subtitle: l10n.characterSelectionSubtitle,
      searchHint: l10n.characterSelectionSearchHint,
      items: items,
      initialSelectedIds: widget.initialSelectedIds,
      isMultiSelect: widget.isMultiSelect,
      filterCategories: [
        l10n.characterCompatNative,
        l10n.characterCompatUnbound,
        l10n.characterCompatCrossWorld,
      ],
      categoryExtractor: (card) {
        final comp = WorldviewCharacterScopePolicy.compatibility(
          card.matchingWorldviewId,
          widget.selectedWorldviewId,
        );
        return switch (comp) {
          CharacterWorldviewCompatibility.native => l10n.characterCompatNative,
          CharacterWorldviewCompatibility.unbound =>
            l10n.characterCompatUnbound,
          CharacterWorldviewCompatibility.crossWorld =>
            l10n.characterCompatCrossWorld,
        };
      },
      isLoading: isLoading && validCards.isEmpty,
      errorMessage: error,
      onRetry: () =>
          ref.read(adventureSetupControllerProvider).loadInitialData(),
      emptyTitle: l10n.characterSelectionEmptyTitle,
      emptyDescription: l10n.characterSelectionEmptyDesc,
      onConfirm: (selectedList) {
        Navigator.of(context).pop(selectedList);
      },
    );
  }
}
