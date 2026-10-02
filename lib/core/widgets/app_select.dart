import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import '../../l10n/generated/app_localizations.dart';
import 'app_menu.dart';
import 'app_picker.dart';
import 'app_svg_icon.dart';

// The placement policy enum lives in the shared picker foundation so every menu
// (select / action / multi) honours the exact same responsive rule.
export 'app_picker.dart' show AppSelectPickerStyle;

/// 统一选择组件选项定义 [AppSelectItem]
class AppSelectItem<T> {
  final T? value;
  final String label;
  final String? subtitle;
  final Widget? leading;
  final String? icon;
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

/// Visual density used by [AppSelect].
enum AppSelectDensity { standard, compact }

/// The trigger shape a select presents.
///
/// Both presentations share the same menu kernel; only the trigger differs.
enum AppSelectPresentation {
  /// Bordered form field used by settings, forms and pickers.
  field,

  /// Quiet inline label used in toolbars (`Status: All`).
  toolbar,
}

/// 全局统一全平台选择组件 [AppSelect]
///
/// 遵循 R02 规范，替代旧版自定义 overlay 选择器导致的层级与滚动冲突：
/// - 泛型支持 [T]
/// - 移动端优先使用轻量、易触控、自适应 320px 的 BottomSheet
/// - 桌面端与宽屏使用锚定弹出菜单 (shared [AppMenuAnchor] kernel)
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
  final AppSelectPresentation presentation;
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
    this.menuMaxHeight = AppMenuMetrics.maxHeight,
    this.tooltip,
    this.semanticLabel,
    this.presentation = AppSelectPresentation.field,
    this.selectedBuilder,
    this.itemBuilder,
  });

  /// Toolbar presentation: quiet inline `label: value` control.
  const AppSelect.toolbar({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.label,
    this.hintText,
    this.enabled = true,
    this.sheetTitle,
    this.pickerStyle = AppSelectPickerStyle.auto,
    this.menuWidth,
    this.menuMaxHeight = AppMenuMetrics.maxHeight,
    this.tooltip,
    this.semanticLabel,
    this.selectedBuilder,
    this.itemBuilder,
  })  : errorText = null,
        validator = null,
        prefix = null,
        expanded = false,
        contentPadding = null,
        density = AppSelectDensity.compact,
        triggerHeight = 32,
        showArrow = true,
        presentation = AppSelectPresentation.toolbar;

  @override
  Widget build(BuildContext context) {
    if (validator != null) {
      return FormField<T>(
        initialValue: value,
        validator: validator,
        builder: (fieldState) {
          final effectiveError = errorText ?? fieldState.errorText;
          return _buildSelect(
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
    return _buildSelect(
      context,
      effectiveError: errorText,
      onSelect: onChanged,
    );
  }

  AppSelectItem<T>? get _selectedItem {
    for (final item in items) {
      if (item.value == value) return item;
    }
    return null;
  }

  Widget _buildSelect(
    BuildContext context, {
    required String? effectiveError,
    required ValueChanged<T?>? onSelect,
  }) {
    final isInteractive = enabled && onSelect != null;
    final kernelItems = <AppMenuItem<T?>>[
      for (final item in items)
        AppMenuItem<T?>(
          value: item.value,
          label: item.label,
          subtitle: item.subtitle,
          icon: item.icon,
          leading: item.leading,
          enabled: item.enabled,
          dividerBefore: item.dividerBefore,
          selected: item.value == value,
          contentOverride: itemBuilder?.call(item) ?? item.customWidget,
          trailing: item.onAction != null
              ? IconButton(
                  tooltip: item.actionTooltip,
                  visualDensity: VisualDensity.compact,
                  icon: const AppSvgIcon('delete', size: 18),
                  onPressed: item.onAction,
                )
              : null,
        ),
    ];

    return AppMenuAnchor<T?>(
      items: kernelItems,
      menuWidth: menuWidth,
      menuMaxHeight: menuMaxHeight,
      pickerStyle: pickerStyle,
      sheetTitle: sheetTitle,
      triggerBuilder: (context, open) {
        final trigger = switch (presentation) {
          AppSelectPresentation.field => _buildFieldTrigger(
              context,
              effectiveError,
              isInteractive ? open : null,
            ),
          AppSelectPresentation.toolbar => _buildToolbarTrigger(
              context,
              isInteractive ? open : null,
            ),
        };
        Widget result = Semantics(
          button: true,
          enabled: isInteractive,
          label: semanticLabel ?? label ?? hintText,
          child: trigger,
        );
        if (tooltip case final message?) {
          result = Tooltip(message: message, child: result);
        }
        return result;
      },
      onActivated: (selected) => onSelect?.call(selected),
    );
  }

  /// Field presentation shares the existing input/control token.
  Widget _buildFieldTrigger(
    BuildContext context,
    String? effectiveError,
    VoidCallback? onTap,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final selectedItem = _selectedItem;
    final l10n = AppLocalizations.of(context);

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
          selectedItem?.label ??
              hintText ??
              (l10n?.selectPrompt ?? 'Please select'),
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
        onTap: onTap,
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
                AppSvgIcon(
                  selectedItem!.icon!,
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
                Flexible(child: selectedContent),
              if (showArrow)
                AppSvgIcon(
                  'chevron_down',
                  size: 20,
                  color: enabled
                      ? colorScheme.onSurfaceVariant
                      : colorScheme.onSurfaceVariant.withValues(alpha: 0.38),
                ),
            ],
          ),
        ),
      ),
    );

    return Column(
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
  }

  /// Toolbar presentation: transparent `label: value ˅`, no filled pill.
  Widget _buildToolbarTrigger(BuildContext context, VoidCallback? onTap) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final selectedItem = _selectedItem;
    final l10n = AppLocalizations.of(context);
    final selectedLabel = selectedItem?.label ??
        hintText ??
        (l10n?.selectPrompt ?? 'Please select');
    final prefixText = (label != null && label!.isNotEmpty) ? '$label: ' : '';
    final Color textColor = enabled
        ? colorScheme.onSurfaceVariant
        : colorScheme.onSurfaceVariant.withValues(alpha: 0.38);

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        hoverColor: colorScheme.onSurface.withValues(alpha: 0.04),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 240),
          child: Container(
            height: triggerHeight ?? 32,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (prefixText.isNotEmpty)
                  Text(
                    prefixText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                        color: textColor, fontWeight: FontWeight.w500),
                  ),
                Flexible(
                  child: Text(
                    selectedLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        theme.textTheme.labelLarge?.copyWith(color: textColor),
                  ),
                ),
                if (showArrow) ...[
                  const SizedBox(width: 4),
                  AppSvgIcon('chevron_down', size: 15, color: textColor),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
