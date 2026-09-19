import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/utils/worldview_character_scope_policy.dart';
import '../../../../../models/character_card_entry.dart';
import '../../../../../providers/riverpod_providers.dart';
import 'resource_selection_page.dart';

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
        CharacterWorldviewCompatibility.native => '当前世界',
        CharacterWorldviewCompatibility.unbound => '未绑定',
        CharacterWorldviewCompatibility.crossWorld => '来自其他世界',
      };

      final details = [
        if (card.gender.isNotEmpty) card.gender,
        if (card.age.isNotEmpty) '${card.age}岁',
        if (card.profession.isNotEmpty) card.profession,
      ].join(' · ');

      final descParts = [
        if (card.personality.isNotEmpty) '性格: ${card.personality}',
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
      title: '选择冒险角色',
      subtitle: '从资料库角色档案中挑选主角与队伍同伴',
      searchHint: '搜索角色姓名、职业、性格或背景...',
      items: items,
      initialSelectedIds: widget.initialSelectedIds,
      isMultiSelect: widget.isMultiSelect,
      filterCategories: const ['全部', '当前世界', '未绑定', '来自其他世界'],
      categoryExtractor: (card) {
        final comp = WorldviewCharacterScopePolicy.compatibility(
          card.matchingWorldviewId,
          widget.selectedWorldviewId,
        );
        return switch (comp) {
          CharacterWorldviewCompatibility.native => '当前世界',
          CharacterWorldviewCompatibility.unbound => '未绑定',
          CharacterWorldviewCompatibility.crossWorld => '来自其他世界',
        };
      },
      isLoading: isLoading && validCards.isEmpty,
      errorMessage: error,
      onRetry: () =>
          ref.read(adventureSetupControllerProvider).loadInitialData(),
      emptyTitle: '暂无可用的角色档案',
      emptyDescription: '可在资料库中创建新角色，或在向导中使用 AI 自动构思',
      onConfirm: (selectedList) {
        Navigator.of(context).pop(selectedList);
      },
    );
  }
}
