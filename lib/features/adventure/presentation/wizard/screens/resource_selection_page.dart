import 'package:flutter/material.dart';

import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/theme/app_radius.dart';
import '../../../../../core/widgets/ui_foundation.dart';

/// 资源选择项通用模型
class ResourceSelectionItem<T> {
  final String id;
  final String title;
  final String? subtitle;
  final String? description;
  final String? tag;
  final Color? tagColor;
  final IconData? icon;
  final T data;

  const ResourceSelectionItem({
    required this.id,
    required this.title,
    this.subtitle,
    this.description,
    this.tag,
    this.tagColor,
    this.icon,
    required this.data,
  });
}

/// 通用全屏资源选择页面 (Navigation-first Resource Selection Page)
///
/// 解决旧架构在 Dialog / BottomSheet 内滚长列表、搜索与多选挤压的问题。
/// 支持单选与多选、实时搜索过滤、分类标签切换、空态与加载态渲染、320px 移动端零溢出。
class ResourceSelectionPage<T> extends StatefulWidget {
  final String title;
  final String? subtitle;
  final List<ResourceSelectionItem<T>> items;
  final Set<String> initialSelectedIds;
  final bool isMultiSelect;
  final String searchHint;
  final List<String>? filterCategories;
  final String Function(T item)? categoryExtractor;
  final Widget? extraAction;
  final String emptyTitle;
  final String emptyDescription;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback? onRetry;
  final ValueChanged<List<T>>? onConfirm;

  const ResourceSelectionPage({
    super.key,
    required this.title,
    this.subtitle,
    required this.items,
    this.initialSelectedIds = const {},
    this.isMultiSelect = false,
    this.searchHint = '搜索资源名称或描述...',
    this.filterCategories,
    this.categoryExtractor,
    this.extraAction,
    this.emptyTitle = '暂无匹配资源',
    this.emptyDescription = '尝试输入其他搜索词或清除筛选条件',
    this.isLoading = false,
    this.errorMessage,
    this.onRetry,
    this.onConfirm,
  });

  @override
  State<ResourceSelectionPage<T>> createState() =>
      _ResourceSelectionPageState<T>();
}

class _ResourceSelectionPageState<T> extends State<ResourceSelectionPage<T>> {
  late final TextEditingController _searchCtrl;
  late final Set<String> _selectedIds;
  String _selectedCategory = '全部';
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController();
    _selectedIds = Set<String>.from(widget.initialSelectedIds);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _toggleSelection(ResourceSelectionItem<T> item) {
    setState(() {
      if (widget.isMultiSelect) {
        if (_selectedIds.contains(item.id)) {
          _selectedIds.remove(item.id);
        } else {
          _selectedIds.add(item.id);
        }
      } else {
        if (_selectedIds.contains(item.id)) {
          _selectedIds.clear();
        } else {
          _selectedIds
            ..clear()
            ..add(item.id);
        }
      }
    });
  }

  void _handleConfirm() {
    final selectedData = widget.items
        .where((item) => _selectedIds.contains(item.id))
        .map((item) => item.data)
        .toList();

    if (widget.onConfirm != null) {
      widget.onConfirm!(selectedData);
    } else {
      Navigator.of(context).pop(selectedData);
    }
  }

  List<ResourceSelectionItem<T>> get _filteredItems {
    return widget.items.where((item) {
      // 分类筛选
      if (widget.filterCategories != null &&
          widget.categoryExtractor != null &&
          _selectedCategory != '全部') {
        final cat = widget.categoryExtractor!(item.data);
        if (cat != _selectedCategory) return false;
      }

      // 文本搜索
      if (_searchQuery.isEmpty) return true;
      final query = _searchQuery.toLowerCase();
      final titleMatch = item.title.toLowerCase().contains(query);
      final subtitleMatch =
          item.subtitle?.toLowerCase().contains(query) ?? false;
      final descMatch =
          item.description?.toLowerCase().contains(query) ?? false;
      final tagMatch = item.tag?.toLowerCase().contains(query) ?? false;

      return titleMatch || subtitleMatch || descMatch || tagMatch;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final filtered = _filteredItems;

    return AppPageScaffold(
      title: widget.title,
      titleWidget: widget.subtitle != null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.title, style: theme.textTheme.titleMedium),
                Text(
                  widget.subtitle!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            )
          : null,
      actions: widget.extraAction != null ? [widget.extraAction!] : null,
      bottomBar: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          border: Border(
            top: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.isMultiSelect
                      ? '已选择 ${_selectedIds.length} 项'
                      : (_selectedIds.isEmpty ? '未选择任何项' : '已选定 1 项'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              AppPrimaryButton(
                key: const Key('resource-selection-confirm-button'),
                label: widget.isMultiSelect ? '确认选择' : '完成选定',
                onPressed: _selectedIds.isEmpty && !widget.isMultiSelect
                    ? null
                    : _handleConfirm,
              ),
            ],
          ),
        ),
      ),
      body: widget.isLoading
          ? const AppLoadingView(message: '正在加载可用资源...')
          : widget.errorMessage != null
              ? AppErrorView(
                  message: widget.errorMessage!,
                  onRetry: widget.onRetry,
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 搜索与过滤工具栏
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md,
                        AppSpacing.sm,
                        AppSpacing.md,
                        AppSpacing.xs,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AppTextField(
                            key: const Key('resource-selection-search-input'),
                            controller: _searchCtrl,
                            hintText: widget.searchHint,
                            prefixIcon: const Icon(Icons.search, size: 20),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 18),
                                    onPressed: () {
                                      _searchCtrl.clear();
                                      setState(() => _searchQuery = '');
                                    },
                                  )
                                : null,
                            onChanged: (val) =>
                                setState(() => _searchQuery = val.trim()),
                          ),
                          if (widget.filterCategories != null &&
                              widget.filterCategories!.isNotEmpty) ...[
                            const SizedBox(height: AppSpacing.sm),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  ChoiceChip(
                                    label: const Text('全部'),
                                    selected: _selectedCategory == '全部',
                                    onSelected: (selected) {
                                      if (selected) {
                                        setState(
                                            () => _selectedCategory = '全部');
                                      }
                                    },
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  const SizedBox(width: AppSpacing.xs),
                                  ...widget.filterCategories!.map((cat) {
                                    return Padding(
                                      padding: const EdgeInsets.only(
                                          right: AppSpacing.xs),
                                      child: ChoiceChip(
                                        label: Text(cat),
                                        selected: _selectedCategory == cat,
                                        onSelected: (selected) {
                                          if (selected) {
                                            setState(
                                                () => _selectedCategory = cat);
                                          }
                                        },
                                        visualDensity: VisualDensity.compact,
                                      ),
                                    );
                                  }),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    // 列表展示或空态
                    Expanded(
                      child: filtered.isEmpty
                          ? AppEmptyView(
                              title: widget.emptyTitle,
                              description: _searchQuery.isNotEmpty
                                  ? '未找到包含「$_searchQuery」的资源'
                                  : widget.emptyDescription,
                              actionLabel:
                                  _searchQuery.isNotEmpty ? '清空搜索' : null,
                              onAction: _searchQuery.isNotEmpty
                                  ? () {
                                      _searchCtrl.clear();
                                      setState(() => _searchQuery = '');
                                    }
                                  : null,
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.all(AppSpacing.md),
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                final item = filtered[index];
                                final isSelected =
                                    _selectedIds.contains(item.id);

                                return Padding(
                                  padding: const EdgeInsets.only(
                                      bottom: AppSpacing.sm),
                                  child: Material(
                                    color: isSelected
                                        ? colorScheme.primaryContainer
                                            .withValues(alpha: 0.25)
                                        : colorScheme.surfaceContainerLow,
                                    borderRadius:
                                        BorderRadius.circular(AppRadius.md),
                                    clipBehavior: Clip.antiAlias,
                                    child: InkWell(
                                      key: Key(
                                          'resource-selection-item-${item.id}'),
                                      onTap: () => _toggleSelection(item),
                                      child: Container(
                                        padding:
                                            const EdgeInsets.all(AppSpacing.md),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                              AppRadius.md),
                                          border: Border.all(
                                            color: isSelected
                                                ? colorScheme.primary
                                                : colorScheme.outlineVariant
                                                    .withValues(alpha: 0.6),
                                            width: isSelected ? 1.5 : 1.0,
                                          ),
                                        ),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            // 选择状态标识图标
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                  top: 2, right: AppSpacing.sm),
                                              child: widget.isMultiSelect
                                                  ? Icon(
                                                      isSelected
                                                          ? Icons
                                                              .check_box_rounded
                                                          : Icons
                                                              .check_box_outline_blank_rounded,
                                                      color: isSelected
                                                          ? colorScheme.primary
                                                          : colorScheme
                                                              .onSurfaceVariant,
                                                      size: 20,
                                                    )
                                                  : Icon(
                                                      isSelected
                                                          ? Icons
                                                              .radio_button_checked_rounded
                                                          : Icons
                                                              .radio_button_unchecked_rounded,
                                                      color: isSelected
                                                          ? colorScheme.primary
                                                          : colorScheme
                                                              .onSurfaceVariant,
                                                      size: 20,
                                                    ),
                                            ),

                                            // 资源主体信息
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      if (item.icon !=
                                                          null) ...[
                                                        Icon(
                                                          item.icon,
                                                          size: 16,
                                                          color: colorScheme
                                                              .primary,
                                                        ),
                                                        const SizedBox(
                                                            width: 6),
                                                      ],
                                                      Flexible(
                                                        child: Text(
                                                          item.title,
                                                          style: theme.textTheme
                                                              .titleSmall
                                                              ?.copyWith(
                                                            fontWeight:
                                                                FontWeight.w600,
                                                          ),
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        ),
                                                      ),
                                                      if (item.tag != null &&
                                                          item.tag!
                                                              .isNotEmpty) ...[
                                                        const SizedBox(
                                                            width: 8),
                                                        Container(
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                            horizontal: 6,
                                                            vertical: 1.5,
                                                          ),
                                                          decoration:
                                                              BoxDecoration(
                                                            color: (item.tagColor ??
                                                                    colorScheme
                                                                        .primary)
                                                                .withValues(
                                                                    alpha:
                                                                        0.12),
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        4),
                                                          ),
                                                          child: Text(
                                                            item.tag!,
                                                            style: TextStyle(
                                                              fontSize: 11,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                              color: item
                                                                      .tagColor ??
                                                                  colorScheme
                                                                      .primary,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ],
                                                  ),
                                                  if (item.subtitle != null &&
                                                      item.subtitle!
                                                          .isNotEmpty) ...[
                                                    const SizedBox(height: 3),
                                                    Text(
                                                      item.subtitle!,
                                                      style: theme
                                                          .textTheme.bodySmall
                                                          ?.copyWith(
                                                        color: colorScheme
                                                            .onSurfaceVariant,
                                                      ),
                                                    ),
                                                  ],
                                                  if (item.description !=
                                                          null &&
                                                      item.description!
                                                          .isNotEmpty) ...[
                                                    const SizedBox(height: 6),
                                                    Text(
                                                      item.description!,
                                                      maxLines: 3,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: theme
                                                          .textTheme.bodySmall
                                                          ?.copyWith(
                                                        color: colorScheme
                                                            .onSurfaceVariant
                                                            .withValues(
                                                                alpha: 0.85),
                                                        height: 1.3,
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
    );
  }
}
