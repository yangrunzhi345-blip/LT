import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../l10n/generated/app_localizations_zh.dart';
import 'app_menu.dart';
import 'app_select.dart';
import 'app_svg_icon.dart';

/// An option accepted by the legacy dropdown facade.
class AppDropdownOption<T> {
  const AppDropdownOption({
    required this.value,
    required this.label,
    this.leading,
    this.icon,
    this.subtitle,
    this.actionTooltip,
    this.onAction,
    this.enabled = true,
    this.dividerBefore = false,
    this.customWidget,
  });

  final T? value;
  final String label;
  final Widget? leading;
  final String? icon;
  final String? subtitle;
  final String? actionTooltip;
  final VoidCallback? onAction;
  final bool enabled;
  final bool dividerBefore;
  final Widget? customWidget;

  AppSelectItem<T> toSelectItem() => AppSelectItem<T>(
        value: value,
        label: label,
        leading: leading,
        icon: icon,
        subtitle: subtitle,
        actionTooltip: actionTooltip,
        onAction: onAction,
        enabled: enabled,
        dividerBefore: dividerBefore,
        customWidget: customWidget,
      );
}

typedef AppDropdownItem<T> = AppDropdownOption<T>;

enum AppDropdownVariant { compact, form, tonal, borderless }

/// Source-compatible placement preference for legacy callers.
///
/// Placement is now owned by the shared menu kernel rather than a custom
/// overlay. The value is retained so callers can migrate independently.
enum AppDropdownDirection { down, up, auto }

/// Compatibility facade backed by the R02 [AppSelect] implementation.
///
/// Compact viewports use a bounded bottom sheet. Wider viewports use the shared
/// anchored menu kernel. This widget no longer creates or owns an overlay.
class AppDropdown<T> extends StatelessWidget {
  const AppDropdown({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.label,
    this.hintText,
    this.errorText,
    this.enabled = true,
    this.expanded = true,
    this.prefix,
    this.variant = AppDropdownVariant.form,
    this.direction = AppDropdownDirection.down,
    this.triggerHeight,
    this.triggerPadding,
    this.menuWidth,
    this.menuMaxHeight = 280,
    this.showArrow = true,
    this.tooltip,
    this.semanticLabel,
    this.selectedBuilder,
    this.optionBuilder,
  });

  const AppDropdown.compact({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.label,
    this.hintText,
    this.errorText,
    this.enabled = true,
    this.expanded = false,
    this.prefix,
    this.direction = AppDropdownDirection.down,
    this.triggerHeight = 32,
    this.triggerPadding =
        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    this.menuWidth,
    this.menuMaxHeight = 280,
    this.showArrow = true,
    this.tooltip,
    this.semanticLabel,
    this.selectedBuilder,
    this.optionBuilder,
  }) : variant = AppDropdownVariant.compact;

  const AppDropdown.form({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.label,
    this.hintText,
    this.errorText,
    this.enabled = true,
    this.expanded = true,
    this.prefix,
    this.direction = AppDropdownDirection.down,
    this.triggerHeight = 46,
    this.triggerPadding =
        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    this.menuWidth,
    this.menuMaxHeight = 300,
    this.showArrow = true,
    this.tooltip,
    this.semanticLabel,
    this.selectedBuilder,
    this.optionBuilder,
  }) : variant = AppDropdownVariant.form;

  const AppDropdown.tonal({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.label,
    this.hintText,
    this.errorText,
    this.enabled = true,
    this.expanded = false,
    this.prefix,
    this.direction = AppDropdownDirection.down,
    this.triggerHeight = 32,
    this.triggerPadding =
        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    this.menuWidth,
    this.menuMaxHeight = 280,
    this.showArrow = true,
    this.tooltip,
    this.semanticLabel,
    this.selectedBuilder,
    this.optionBuilder,
  }) : variant = AppDropdownVariant.tonal;

  final T? value;
  final List<AppDropdownOption<T>> options;
  final ValueChanged<T?>? onChanged;
  final String? label;
  final String? hintText;
  final String? errorText;
  final bool enabled;
  final bool expanded;
  final Widget? prefix;
  final AppDropdownVariant variant;
  final AppDropdownDirection direction;
  final double? triggerHeight;
  final EdgeInsetsGeometry? triggerPadding;
  final double? menuWidth;
  final double menuMaxHeight;
  final bool showArrow;
  final String? tooltip;
  final String? semanticLabel;
  final Widget Function(T? value)? selectedBuilder;
  final Widget Function(AppDropdownOption<T> option)? optionBuilder;

  @override
  Widget build(BuildContext context) => AppSelect<T>(
        value: value,
        items: [for (final option in options) option.toSelectItem()],
        onChanged: onChanged,
        label: label,
        hintText: hintText,
        errorText: errorText,
        enabled: enabled,
        expanded: expanded,
        prefix: prefix,
        density: variant == AppDropdownVariant.form
            ? AppSelectDensity.standard
            : AppSelectDensity.compact,
        triggerHeight: triggerHeight,
        contentPadding: triggerPadding,
        showArrow: showArrow,
        menuWidth: menuWidth,
        menuMaxHeight: menuMaxHeight,
        tooltip: tooltip,
        semanticLabel: semanticLabel,
        selectedBuilder: selectedBuilder,
        itemBuilder: optionBuilder == null
            ? null
            : (item) => optionBuilder!(
                  options.firstWhere((option) => option.value == item.value),
                ),
      );
}

/// Adaptive multi-select facade backed by the shared menu kernel.
///
/// The only differences from a single-select are semantic: tapping an item
/// toggles it without closing, the selection is a set and every selected row
/// shows a check. Surface, item rendering, dimensions and the mobile
/// BottomSheet are shared with [AppSelect] and [AppActionMenu].
class AppMultiSelectDropdown<T> extends StatefulWidget {
  const AppMultiSelectDropdown({
    super.key,
    this.label,
    this.hintText,
    required this.values,
    required this.options,
    required this.onChanged,
    this.enabled = true,
    this.expanded = true,
    this.prefix,
    this.direction = AppDropdownDirection.down,
    this.triggerHeight = 46,
    this.triggerPadding =
        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    this.showArrow = true,
    this.menuWidth,
    this.tooltip,
    this.semanticLabel,
    this.emptyText,
    this.selectedBuilder,
  });

  final String? label;
  final String? hintText;
  final Set<T> values;
  final List<AppDropdownOption<T>> options;
  final ValueChanged<Set<T>>? onChanged;
  final bool enabled;
  final bool expanded;
  final Widget? prefix;
  final AppDropdownDirection direction;
  final double triggerHeight;
  final EdgeInsetsGeometry triggerPadding;
  final bool showArrow;
  final double? menuWidth;
  final String? tooltip;
  final String? semanticLabel;
  final String? emptyText;
  final String Function(Set<T> values)? selectedBuilder;

  @override
  State<AppMultiSelectDropdown<T>> createState() =>
      _AppMultiSelectDropdownState<T>();
}

class _AppMultiSelectDropdownState<T> extends State<AppMultiSelectDropdown<T>> {
  late Set<T> _selected;

  @override
  void initState() {
    super.initState();
    _selected = Set<T>.from(widget.values);
  }

  @override
  void didUpdateWidget(covariant AppMultiSelectDropdown<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!setEquals(oldWidget.values, widget.values)) {
      _selected = Set<T>.from(widget.values);
    }
  }

  void _toggle(T value) {
    setState(() {
      if (!_selected.remove(value)) _selected.add(value);
    });
    widget.onChanged?.call(Set<T>.unmodifiable(_selected));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();
    final selectedText = widget.selectedBuilder?.call(_selected) ??
        (_selected.isEmpty
            ? widget.hintText ?? l10n.notSpecified
            : l10n.itemsSelectedCount(_selected.length));
    final isInteractive = widget.enabled && widget.onChanged != null;

    Widget trigger(BuildContext context, VoidCallback open) {
      Widget box = Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isInteractive ? open : null,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            height: widget.triggerHeight,
            padding: widget.triggerPadding,
            decoration: BoxDecoration(
              color: widget.enabled
                  ? colorScheme.surfaceContainerLow
                  : colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              mainAxisSize:
                  widget.expanded ? MainAxisSize.max : MainAxisSize.min,
              children: [
                if (widget.prefix != null) ...[
                  widget.prefix!,
                  const SizedBox(width: AppSpacing.sm),
                ],
                if (widget.expanded)
                  Expanded(
                    child: Text(
                      selectedText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  )
                else
                  Flexible(
                    child: Text(
                      selectedText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (widget.showArrow) const AppSvgIcon('chevron_down'),
              ],
            ),
          ),
        ),
      );
      box = Semantics(
        button: true,
        enabled: isInteractive,
        label: widget.semanticLabel ?? widget.label ?? widget.hintText,
        child: box,
      );
      if (widget.tooltip case final message?) {
        box = Tooltip(message: message, child: box);
      }
      return box;
    }

    final kernel = AppMenuAnchor<T>(
      items: [
        for (final option in widget.options)
          if (option.value case final value?)
            AppMenuItem<T>(
              value: value,
              label: option.label,
              subtitle: option.subtitle,
              icon: option.icon,
              leading: option.leading,
              enabled: option.enabled,
              dividerBefore: option.dividerBefore,
            ),
      ],
      selectedValues: _selected,
      onToggle: _toggle,
      menuWidth: widget.menuWidth,
      sheetTitle: widget.label ?? widget.hintText,
      triggerBuilder: trigger,
    );

    return Opacity(
      opacity: widget.enabled ? 1 : 0.45,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.label != null && widget.label!.isNotEmpty) ...[
            Text(
              widget.label!,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppSpacing.xs + 2),
          ],
          kernel,
        ],
      ),
    );
  }
}
