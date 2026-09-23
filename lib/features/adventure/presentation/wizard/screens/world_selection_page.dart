import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../providers/riverpod_providers.dart';
import 'resource_selection_page.dart';
import '../../../../../l10n/generated/app_localizations.dart';
import '../../../../../l10n/generated/app_localizations_zh.dart';

AppLocalizations _l10n(BuildContext context) =>
    AppLocalizations.of(context) ?? AppLocalizationsZh();

/// 专用于世界观设定的全屏选择页面 (World Selection Page)
class WorldSelectionPage extends ConsumerStatefulWidget {
  final String? initialSelectedId;

  const WorldSelectionPage({
    super.key,
    this.initialSelectedId,
  });

  @override
  ConsumerState<WorldSelectionPage> createState() => _WorldSelectionPageState();
}

class _WorldSelectionPageState extends ConsumerState<WorldSelectionPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = ref.read(adventureSetupControllerProvider);
      if (controller.worldviewPresets.isEmpty && !controller.loading) {
        controller.loadInitialData();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n(context);
    final setupController = ref.watch(adventureSetupControllerProvider);
    final worldviews = setupController.worldviewPresets;
    final isLoading = setupController.loading;
    final error = setupController.worldviewError;

    final items = worldviews.map((w) {
      final id = w['id']?.toString() ?? '';
      final name = w['name']?.toString() ?? l10n.unnamedWorldview;
      final desc = w['description']?.toString() ?? '';

      return ResourceSelectionItem<Map<String, dynamic>>(
        id: id,
        title: name,
        description: desc.isNotEmpty ? desc : l10n.worldSelectionNoDesc,
        icon: Icons.public_rounded,
        tag: l10n.worldSelectionTag,
        data: w,
      );
    }).toList();

    return ResourceSelectionPage<Map<String, dynamic>>(
      title: l10n.worldSelectionTitle,
      subtitle: l10n.worldSelectionSubtitle,
      searchHint: l10n.worldSelectionSearchHint,
      items: items,
      initialSelectedIds:
          widget.initialSelectedId != null ? {widget.initialSelectedId!} : {},
      isMultiSelect: false,
      isLoading: isLoading && worldviews.isEmpty,
      errorMessage: error,
      onRetry: () =>
          ref.read(adventureSetupControllerProvider).loadInitialData(),
      emptyTitle: l10n.worldSelectionEmptyTitle,
      emptyDescription: l10n.worldSelectionEmptyDesc,
      onConfirm: (selectedList) {
        final selected = selectedList.isNotEmpty ? selectedList.first : null;
        Navigator.of(context).pop(selected);
      },
    );
  }
}
