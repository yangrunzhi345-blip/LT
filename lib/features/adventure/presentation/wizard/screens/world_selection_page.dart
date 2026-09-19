import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../providers/riverpod_providers.dart';
import 'resource_selection_page.dart';

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
    final setupController = ref.watch(adventureSetupControllerProvider);
    final worldviews = setupController.worldviewPresets;
    final isLoading = setupController.loading;
    final error = setupController.worldviewError;

    final items = worldviews.map((w) {
      final id = w['id']?.toString() ?? '';
      final name = w['name']?.toString() ?? '未命名世界';
      final desc = w['description']?.toString() ?? '';

      return ResourceSelectionItem<Map<String, dynamic>>(
        id: id,
        title: name,
        description: desc.isNotEmpty ? desc : '暂无详细背景描述',
        icon: Icons.public_rounded,
        tag: '世界设定',
        data: w,
      );
    }).toList();

    return ResourceSelectionPage<Map<String, dynamic>>(
      title: '选择世界观设定',
      subtitle: '从资料库已构想的世界中挑选本次冒险的世界法则与背景设定',
      searchHint: '搜索世界观名称、地理风貌或设定规则...',
      items: items,
      initialSelectedIds:
          widget.initialSelectedId != null ? {widget.initialSelectedId!} : {},
      isMultiSelect: false,
      isLoading: isLoading && worldviews.isEmpty,
      errorMessage: error,
      onRetry: () =>
          ref.read(adventureSetupControllerProvider).loadInitialData(),
      emptyTitle: '暂无保存的世界观',
      emptyDescription: '可在资料库中创建或在向导中直接输入自定义世界观',
      onConfirm: (selectedList) {
        final selected = selectedList.isNotEmpty ? selectedList.first : null;
        Navigator.of(context).pop(selected);
      },
    );
  }
}
