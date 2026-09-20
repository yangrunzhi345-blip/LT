import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../responsive/app_breakpoints.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// 统一选择组件选项定义 [AppSelectItem]
class AppSelectItem<T> {
  final T? value;
  final String label;
  final String? subtitle;
  final Widget? leading;
  final IconData? icon;
  final bool enabled;
  final bool dividerBefore;
  final String? actionTooltip;
  final VoidCallback? onAction;
  final Widget? customWidget;

  const AppSelectItem({
    required this.value,
    required this.label,
    this.subtitle,
    this.leading,
    this.icon,
    this.enabled = true,
    this.dividerBefore = false,
    this.actionTooltip,
    this.onAction,
    this.customWidget,
  });
}

/// 别名兼容
typedef AppSelectOption<T> = AppSelectItem<T>;
typedef LtSelect<T> = AppSelect<T>;

/// 选择组件展开交互样式
enum AppSelectPickerStyle {
  /// 自动：移动端 (< 600) BottomSheet，桌面/平板 (>= 600) 锚定弹出菜单
  auto,

  /// 始终使用 BottomSheet
  bottomSheet,

  /// 始终使用锚定弹出菜单
  menu,
}

/// Visual density used by [AppSelect].
enum AppSelectDensity { standard, compact }

final class _AppSelectResult<T> {
  const _AppSelectResult(this.value);

  final T? value;
}

/// 全局统一全平台选择组件 [AppSelect]
///
/// 遵循 R02 规范，替代旧版自定义 overlay 选择器导致的层级与滚动冲突：
/// - 泛型支持 [T]
/// - 移动端优先使用轻量、易触控、自适应 320px 的 BottomSheet
/// - 桌面端与宽屏使用原生锚定弹出菜单 (PopupRoute)
/// - 深度集成 Material 3 令牌与表单校验验证器 (validator)
/// - 针对超长文本自适应单行截断与底部弹窗全文本换行
/// - 完整支持 disabled、errorText、label 与自定义前缀
class AppSelect<T> extends StatelessWidget {
  final T? value;
  final List<AppSelectItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final String? label;
  final String? hintText;
  final String? errorText;
  final FormFieldValidator<T?>? validator;
  final bool enabled;
  final Widget? prefix;
  final bool expanded;
  final String? sheetTitle;
  final AppSelectPickerStyle pickerStyle;
  final EdgeInsetsGeometry? contentPadding;
  final AppSelectDensity density;
  final double? triggerHeight;
  final bool showArrow;
  final double? menuWidth;
  final double menuMaxHeight;
  final String? tooltip;
  final String? semanticLabel;
  final Widget Function(T? value)? selectedBuilder;
  final Widget Function(AppSelectItem<T> item)? itemBuilder;

  const AppSelect({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.label,
    this.hintText,
    this.errorText,
    this.validator,
    this.enabled = true,
    this.prefix,
    this.expanded = true,
    this.sheetTitle,
    this.pickerStyle = AppSelectPickerStyle.auto,
    this.contentPadding,
    this.density = AppSelectDensity.standard,
    this.triggerHeight,
    this.showArrow = true,
    this.menuWidth,
    this.menuMaxHeight = 380,
    this.tooltip,
    this.semanticLabel,
    this.selectedBuilder,
    this.itemBuilder,
  });

  @override
  Widget build(BuildContext context) {
    if (validator != null) {
      return FormField<T>(
        initialValue: value,
        validator: validator,
        builder: (fieldState) {
          final effectiveError = errorText ?? fieldState.errorText;
          return _buildTrigger(
            context,
            effectiveError: effectiveError,
            onSelect: (val) {
              fieldState.didChange(val);
              onChanged?.call(val);
            },
          );
        },
      );
    }
    return _buildTrigger(
      context,
      effectiveError: errorText,
      onSelect: onChanged,
    );
  }

  Widget _buildTrigger(
    BuildContext context, {
    required String? effectiveError,
    required ValueChanged<T?>? onSelect,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final selectedItem = items.cast<AppSelectItem<T>?>().firstWhere(
          (it) => it?.value == value,
          orElse: () => null,
        );

    final isInteractive = enabled && onSelect != null;

    final Color borderColor = effectiveError != null
        ? colorScheme.error
        : (!enabled
            ? colorScheme.outlineVariant.withValues(alpha: 0.2)
            : colorScheme.outlineVariant.withValues(alpha: 0.5));

    final Color fillColor = enabled
        ? colorScheme.surfaceContainerLow
        : colorScheme.surfaceContainerHighest.withValues(alpha: 0.3);

    final selectedContent = selectedBuilder?.call(value) ??
        Text(
          selectedItem?.label ?? hintText ?? '请选择',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: !enabled
                ? colorScheme.onSurface.withValues(alpha: 0.38)
                : (selectedItem != null
                    ? colorScheme.onSurface
                    : colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
          ),
        );

    Widget triggerBox = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isInteractive ? () => _openPicker(context, onSelect) : null,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: triggerHeight,
          padding: contentPadding ??
              (density == AppSelectDensity.compact
                  ? const EdgeInsets.symmetric(horizontal: 10, vertical: 4)
                  : const EdgeInsets.symmetric(horizontal: 14, vertical: 12)),
          decoration: BoxDecoration(
            color: fillColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: borderColor,
              width: effectiveError != null ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
            children: [
              if (prefix != null) ...[
                prefix!,
                const SizedBox(width: AppSpacing.sm),
              ],
              if (selectedBuilder == null && selectedItem?.leading != null) ...[
                selectedItem!.leading!,
                const SizedBox(width: AppSpacing.sm),
              ] else if (selectedBuilder == null &&
                  selectedItem?.icon != null) ...[
                Icon(
                  selectedItem!.icon,
                  size: 18,
                  color: enabled
                      ? colorScheme.onSurfaceVariant
                      : colorScheme.onSurfaceVariant.withValues(alpha: 0.38),
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              if (expanded)
                Expanded(child: selectedContent)
              else
                selectedContent,
              if (showArrow)
                Icon(
                  Icons.arrow_drop_down,
                  color: enabled
                      ? colorScheme.onSurfaceVariant
                      : colorScheme.onSurfaceVariant.withValues(alpha: 0.38),
                ),
            ],
          ),
        ),
      ),
    );

    triggerBox = Semantics(
      button: true,
      label: semanticLabel ?? label ?? hintText,
      child: triggerBox,
    );
    if (tooltip case final message?) {
      triggerBox = Tooltip(message: message, child: triggerBox);
    }

    final Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null && label!.isNotEmpty) ...[
          Text(
            label!,
            style: theme.textTheme.titleSmall?.copyWith(
              color: enabled
                  ? colorScheme.onSurface
                  : colorScheme.onSurface.withValues(alpha: 0.45),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xs + 2),
        ],
        triggerBox,
        if (effectiveError != null) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 14),
            child: Text(
              effectiveError,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.error,
              ),
            ),
          ),
        ],
      ],
    );

    return content;
  }

  void _openPicker(BuildContext context, ValueChanged<T?>? onSelect) async {
    if (!enabled || onSelect == null) return;
    FocusScope.of(context).unfocus();

    final isCompact = AppBreakpoints.isCompact(context);
    final useBottomSheet = switch (pickerStyle) {
      AppSelectPickerStyle.bottomSheet => true,
      AppSelectPickerStyle.menu => false,
      AppSelectPickerStyle.auto => isCompact,
    };

    if (useBottomSheet) {
      await _openBottomSheet(context, onSelect);
    } else {
      await _openMenuOrBottomSheet(context, onSelect);
    }
  }

  Future<void> _openBottomSheet(
    BuildContext context,
    ValueChanged<T?> onSelect,
  ) async {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final selected = await showModalBottomSheet<_AppSelectResult<T>>(
      context: context,
      isScrollControlled: true,
      backgroundColor:
          isDark ? AppColors.darkSurface : AppColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: math.min(
                menuMaxHeight,
                MediaQuery.sizeOf(sheetContext).height * 0.70,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 6),
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color:
                          colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          sheetTitle ?? label ?? '请选择',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        tooltip: '关闭',
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: items.length,
                    itemBuilder: (ctx, index) {
                      final item = items[index];
                      final isSelected = item.value == value;
                      final itemLeading = item.leading ??
                          (item.icon != null
                              ? Icon(item.icon, size: 20)
                              : null);

                      final tile = ListTile(
                        dense: true,
                        leading: itemLeading,
                        title: itemBuilder?.call(item) ??
                            item.customWidget ??
                            Text(
                              item.label,
                              style: TextStyle(
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                                color: isSelected ? colorScheme.primary : null,
                              ),
                            ),
                        subtitle:
                            item.subtitle != null ? Text(item.subtitle!) : null,
                        trailing: item.onAction != null
                            ? IconButton(
                                tooltip: item.actionTooltip,
                                icon: const Icon(Icons.delete_outline),
                                color: colorScheme.error,
                                onPressed: () {
                                  Navigator.of(sheetContext).pop();
                                  item.onAction!();
                                },
                              )
                            : (isSelected
                                ? Icon(Icons.check,
                                    color: colorScheme.primary, size: 20)
                                : null),
                        enabled: item.enabled,
                        onTap: () => Navigator.of(sheetContext)
                            .pop(_AppSelectResult<T>(item.value)),
                      );
                      if (!item.dividerBefore) return tile;
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [const Divider(height: 1), tile],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (selected case _AppSelectResult<T>(:final value)) {
      onSelect(value);
    }
  }

  Future<void> _openMenuOrBottomSheet(
    BuildContext context,
    ValueChanged<T?> onSelect,
  ) async {
    final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
    final RenderBox? overlayBox =
        Navigator.of(context).overlay?.context.findRenderObject() as RenderBox?;
    if (renderBox == null ||
        !renderBox.hasSize ||
        overlayBox == null ||
        !overlayBox.hasSize) {
      await _openBottomSheet(context, onSelect);
      return;
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final translation = renderBox.localToGlobal(
      Offset.zero,
      ancestor: overlayBox,
    );
    final size = renderBox.size;
    final position = RelativeRect.fromRect(
      Rect.fromLTWH(
        translation.dx,
        translation.dy + size.height + 4,
        size.width,
        0,
      ),
      Offset.zero & overlayBox.size,
    );
    final availableWidth = math.max(0.0, overlayBox.size.width - 16);
    final minimumWidth = math.min(menuWidth ?? size.width, availableWidth);
    final maximumWidth = menuWidth == null
        ? math.min(math.max(size.width, 360.0), availableWidth)
        : minimumWidth;

    final selected = await showMenu<_AppSelectResult<T>>(
      context: context,
      position: position,
      popUpAnimationStyle: AnimationStyle.noAnimation,
      constraints: BoxConstraints(
        minWidth: minimumWidth,
        maxWidth: maximumWidth,
        maxHeight: menuMaxHeight,
      ),
      items: [
        for (final item in items) ...[
          if (item.dividerBefore) const PopupMenuDivider(),
          PopupMenuItem<_AppSelectResult<T>>(
            value: _AppSelectResult<T>(item.value),
            enabled: item.enabled,
            child: Row(
              children: [
                if (item.leading != null) ...[
                  item.leading!,
                  const SizedBox(width: 8),
                ] else if (item.icon != null) ...[
                  Icon(item.icon, size: 18),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: itemBuilder?.call(item) ??
                      item.customWidget ??
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            item.label,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: item.value == value
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                              color: item.value == value
                                  ? colorScheme.primary
                                  : null,
                            ),
                          ),
                          if (item.subtitle != null)
                            Text(
                              item.subtitle!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                ),
                if (item.value == value)
                  Icon(Icons.check, size: 18, color: colorScheme.primary),
                if (item.onAction != null)
                  IconButton(
                    tooltip: item.actionTooltip,
                    icon: const Icon(Icons.delete_outline),
                    color: colorScheme.error,
                    onPressed: item.onAction,
                  ),
              ],
            ),
          ),
        ],
      ],
    );

    if (selected case _AppSelectResult<T>(:final value)) {
      onSelect(value);
    }
  }
}
