import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../responsive/app_breakpoints.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'app_select.dart';

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
  final IconData? icon;
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
/// Placement is now owned by Flutter's adaptive picker rather than a custom
/// overlay. The value is retained so callers can migrate independently.
enum AppDropdownDirection { down, up, auto }

/// Compatibility facade backed by the R02 [LtSelect] implementation.
///
/// Compact viewports use a bounded bottom sheet. Wider viewports use Flutter's
/// anchored popup route. This widget no longer creates or owns an overlay.
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

/// Adaptive multi-select facade sharing the R02 picker behavior.
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
  final MenuController _menuController = MenuController();
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

  void _toggle(T value, [StateSetter? setPickerState]) {
    setState(() {
      if (!_selected.remove(value)) _selected.add(value);
    });
    setPickerState?.call(() {});
    widget.onChanged?.call(Set<T>.unmodifiable(_selected));
  }

  Future<void> _openPicker() async {
    if (!widget.enabled || widget.onChanged == null) return;
    FocusScope.of(context).unfocus();
    if (AppBreakpoints.isCompact(context)) {
      await _openBottomSheet();
      return;
    }
    if (_menuController.isOpen) {
      _menuController.close();
    } else {
      _menuController.open();
    }
  }

  Future<void> _openBottomSheet() => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? AppColors.darkSurface
            : AppColors.surfaceElevated,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (sheetContext) => SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: math.min(
                420,
                MediaQuery.sizeOf(sheetContext).height * 0.7,
              ),
            ),
            child: StatefulBuilder(
              builder: (context, setSheetState) => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.label ?? widget.hintText ?? '请选择',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          tooltip: '关闭',
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Flexible(
                    child: widget.options.isEmpty
                        ? Center(child: Text(widget.emptyText ?? '暂无可选项'))
                        : ListView(
                            shrinkWrap: true,
                            children: [
                              for (final option in widget.options)
                                if (option.value case final value?)
                                  _MultiSelectOption<T>(
                                    option: option,
                                    selected: _selected.contains(value),
                                    onChanged: option.enabled
                                        ? (_) => _toggle(value, setSheetState)
                                        : null,
                                  ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final selectedText = widget.selectedBuilder?.call(_selected) ??
        (_selected.isEmpty
            ? widget.hintText ?? '不指定'
            : '已选 ${_selected.length} 项');

    Widget trigger = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.enabled && widget.onChanged != null ? _openPicker : null,
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
            mainAxisSize: widget.expanded ? MainAxisSize.max : MainAxisSize.min,
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
              if (widget.showArrow) const Icon(Icons.arrow_drop_down),
            ],
          ),
        ),
      ),
    );
    trigger = Semantics(
      button: true,
      label: widget.semanticLabel ?? widget.label ?? widget.hintText,
      child: trigger,
    );
    if (widget.tooltip case final message?) {
      trigger = Tooltip(message: message, child: trigger);
    }

    final menuChildren = <Widget>[
      if (widget.options.isEmpty)
        MenuItemButton(
          onPressed: null,
          child: Text(widget.emptyText ?? '暂无可选项'),
        ),
      for (final option in widget.options) ...[
        if (option.dividerBefore) const Divider(height: 1),
        if (option.value case final value?)
          CheckboxMenuButton(
            value: _selected.contains(value),
            closeOnActivate: false,
            onChanged: option.enabled ? (_) => _toggle(value) : null,
            child: _OptionContent<T>(option: option),
          ),
      ],
    ];

    final picker = MenuAnchor(
      controller: _menuController,
      style: widget.menuWidth == null
          ? null
          : MenuStyle(
              fixedSize: WidgetStatePropertyAll(
                Size.fromWidth(widget.menuWidth!),
              ),
            ),
      menuChildren: menuChildren,
      builder: (context, controller, child) => trigger,
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
          picker,
        ],
      ),
    );
  }
}

class _MultiSelectOption<T> extends StatelessWidget {
  const _MultiSelectOption({
    required this.option,
    required this.selected,
    required this.onChanged,
  });

  final AppDropdownOption<T> option;
  final bool selected;
  final ValueChanged<bool?>? onChanged;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (option.dividerBefore) const Divider(height: 1),
          CheckboxListTile(
            value: selected,
            enabled: option.enabled,
            onChanged: onChanged,
            title: _OptionContent<T>(option: option),
            controlAffinity: ListTileControlAffinity.leading,
          ),
        ],
      );
}

class _OptionContent<T> extends StatelessWidget {
  const _OptionContent({required this.option});

  final AppDropdownOption<T> option;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          if (option.leading != null) ...[
            option.leading!,
            const SizedBox(width: 8),
          ] else if (option.icon != null) ...[
            Icon(option.icon, size: 18),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                option.customWidget ?? Text(option.label),
                if (option.subtitle case final subtitle?)
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        ],
      );
}
