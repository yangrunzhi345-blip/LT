import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/utils/worldview_character_scope_policy.dart';
import '../../../../../providers/riverpod_providers.dart';
import 'resource_selection_page.dart';

/// 专用于 NPC 设定的全屏选择页面 (NPC Selection Page)
class NpcSelectionPage extends ConsumerStatefulWidget {
  final String? selectedWorldviewId;
  final Set<String> initialSelectedIds;

  const NpcSelectionPage({
    super.key,
    this.selectedWorldviewId,
    this.initialSelectedIds = const {},
  });

  @override
  ConsumerState<NpcSelectionPage> createState() => _NpcSelectionPageState();
}

class _NpcSelectionPageState extends ConsumerState<NpcSelectionPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = ref.read(adventureSetupControllerProvider);
      if (controller.npcCards.isEmpty && !controller.loading) {
        controller.loadInitialData();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final setupController = ref.watch(adventureSetupControllerProvider);
    final npcCards = setupController.npcCards;
    final isLoading = setupController.loading;
    final error = setupController.npcError;

    final orderedNpcs =
        WorldviewCharacterScopePolicy.orderByOriginCompatibility(
      npcCards,
      widget.selectedWorldviewId,
    );

    final items = orderedNpcs.map((npc) {
      final id = npc['id']?.toString() ?? '';
      final name = npc['name']?.toString() ?? '未命名 NPC';
      final comp = WorldviewCharacterScopePolicy.compatibility(
        npc['matching_worldview_id'],
        widget.selectedWorldviewId,
      );

      final tag = switch (comp) {
        CharacterWorldviewCompatibility.native => '当前世界',
        CharacterWorldviewCompatibility.unbound => '未绑定',
        CharacterWorldviewCompatibility.crossWorld => '来自其他世界',
      };

      final details = [
        if (npc['gender'] != null && npc['gender'].toString().isNotEmpty)
          npc['gender'].toString(),
        if (npc['role'] != null && npc['role'].toString().isNotEmpty)
          npc['role'].toString(),
      ].join(' · ');

      final desc = npc['description']?.toString() ??
          npc['personality']?.toString() ??
          '';

      return ResourceSelectionItem<Map<String, dynamic>>(
        id: id,
        title: name,
        subtitle: details.isNotEmpty ? details : null,
        description: desc.isNotEmpty ? desc : null,
        tag: tag,
        icon: Icons.record_voice_over_rounded,
        data: npc,
      );
    }).toList();

    return ResourceSelectionPage<Map<String, dynamic>>(
      title: '选择初始 NPC',
      subtitle: '挑选本次冒险登场的常驻 NPC（资料将独立冻结至当前冒险快照）',
      searchHint: '搜索 NPC 姓名、身份或简述...',
      items: items,
      initialSelectedIds: widget.initialSelectedIds,
      isMultiSelect: true,
      filterCategories: const ['全部', '当前世界', '未绑定', '来自其他世界'],
      categoryExtractor: (npc) {
        final comp = WorldviewCharacterScopePolicy.compatibility(
          npc['matching_worldview_id'],
          widget.selectedWorldviewId,
        );
        return switch (comp) {
          CharacterWorldviewCompatibility.native => '当前世界',
          CharacterWorldviewCompatibility.unbound => '未绑定',
          CharacterWorldviewCompatibility.crossWorld => '来自其他世界',
        };
      },
      isLoading: isLoading && orderedNpcs.isEmpty,
      errorMessage: error,
      onRetry: () =>
          ref.read(adventureSetupControllerProvider).loadInitialData(),
      emptyTitle: '资料库暂无 NPC',
      emptyDescription: '可在资料库中添加 NPC，或直接跳过此步骤',
      onConfirm: (selectedList) {
        final selectedIds =
            selectedList.map((n) => n['id']?.toString() ?? '').toSet();
        Navigator.of(context).pop(selectedIds);
      },
    );
  }
}
