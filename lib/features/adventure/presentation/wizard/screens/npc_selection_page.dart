import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/utils/worldview_character_scope_policy.dart';
import '../../../../../providers/riverpod_providers.dart';
import 'resource_selection_page.dart';
import '../../../../../l10n/generated/app_localizations.dart';
import '../../../../../l10n/generated/app_localizations_zh.dart';

AppLocalizations _l10n(BuildContext context) =>
    AppLocalizations.of(context) ?? AppLocalizationsZh();

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
    final l10n = _l10n(context);
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
      final name = npc['name']?.toString() ?? l10n.unnamedNpc;
      final comp = WorldviewCharacterScopePolicy.compatibility(
        npc['matching_worldview_id'],
        widget.selectedWorldviewId,
      );

      final tag = switch (comp) {
        CharacterWorldviewCompatibility.native => l10n.characterCompatNative,
        CharacterWorldviewCompatibility.unbound => l10n.characterCompatUnbound,
        CharacterWorldviewCompatibility.crossWorld =>
          l10n.characterCompatCrossWorld,
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
      title: l10n.npcSelectionTitle,
      subtitle: l10n.npcSelectionSubtitle,
      searchHint: l10n.npcSelectionSearchHint,
      items: items,
      initialSelectedIds: widget.initialSelectedIds,
      isMultiSelect: true,
      filterCategories: [
        l10n.characterCompatNative,
        l10n.characterCompatUnbound,
        l10n.characterCompatCrossWorld,
      ],
      categoryExtractor: (npc) {
        final comp = WorldviewCharacterScopePolicy.compatibility(
          npc['matching_worldview_id'],
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
      isLoading: isLoading && orderedNpcs.isEmpty,
      errorMessage: error,
      onRetry: () =>
          ref.read(adventureSetupControllerProvider).loadInitialData(),
      emptyTitle: l10n.npcSelectionEmptyTitle,
      emptyDescription: l10n.npcSelectionEmptyDesc,
      onConfirm: (selectedList) {
        final selectedIds =
            selectedList.map((n) => n['id']?.toString() ?? '').toSet();
        Navigator.of(context).pop(selectedIds);
      },
    );
  }
}
