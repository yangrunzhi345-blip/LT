import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class NarrAItorDropdownOption<T> {
  final T? value;
  final String label;
  final Widget? leading;
  final String? subtitle;
  final String? actionTooltip;
  final VoidCallback? onAction;
  final bool enabled;
  final bool dividerBefore;

  const NarrAItorDropdownOption({
    required this.value,
    required this.label,
    this.leading,
    this.subtitle,
    this.actionTooltip,
    this.onAction,
    this.enabled = true,
    this.dividerBefore = false,
  });
}

/// NarrAItor 统一选择控件，复刻参考资料库的标签、触发器、浮层菜单和选中状态。
class NarrAItorDropdown<T> extends StatefulWidget {
  final String? label;
  final String? hintText;
  final T? value;
  final List<NarrAItorDropdownOption<T>> options;
  final ValueChanged<T?>? onChanged;
  final String? errorText;
  final bool enabled;
  final bool expanded;
  final Widget? prefix;
  final double triggerHeight;
  final EdgeInsetsGeometry triggerPadding;
  final bool showArrow;
  final String? tooltip;
  final String? semanticLabel;

  /// 浮层菜单宽度；未指定时与触发器同宽。
  final double? menuWidth;
  final Widget Function(T? value)? selectedBuilder;
  final Widget Function(NarrAItorDropdownOption<T> option)? optionBuilder;

  const NarrAItorDropdown({
    super.key,
    this.label,
    this.hintText,
    required this.value,
    required this.options,
    required this.onChanged,
    this.errorText,
    this.enabled = true,
    this.expanded = true,
    this.prefix,
    this.triggerHeight = 45,
    this.triggerPadding = const EdgeInsets.symmetric(horizontal: 14),
    this.showArrow = true,
    this.tooltip,
    this.semanticLabel,
    this.menuWidth,
    this.selectedBuilder,
    this.optionBuilder,
  });

  @override
  State<NarrAItorDropdown<T>> createState() => _NarrAItorDropdownState<T>();
}

class _NarrAItorDropdownState<T> extends State<NarrAItorDropdown<T>> {
  final _targetKey = GlobalKey();
  final _layerLink = LayerLink();
  OverlayEntry? _entry;
  bool _open = false;

  NarrAItorDropdownOption<T>? get _selected {
    for (final option in widget.options) {
      if (option.value == widget.value) return option;
    }
    return null;
  }

  @override
  void dispose() {
    _close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final theme = Theme.of(context);
        final dark = theme.brightness == Brightness.dark;
        final selected = _selected;
        final fillsAvailableWidth =
            widget.expanded && constraints.hasBoundedWidth;
        final fillsTightCompactWidth =
            !widget.expanded && constraints.hasTightWidth;
        final fillsTriggerWidth = fillsAvailableWidth || fillsTightCompactWidth;
        final borderColor = widget.errorText != null
            ? theme.colorScheme.error
            : _open
                ? theme.colorScheme.primary.withValues(alpha: .65)
                : Colors.transparent;
        final background =
            dark ? AppColors.darkSurface : const Color(0xffedebe7);
        final selectedChild = widget.selectedBuilder?.call(widget.value) ??
            Text(
              selected?.label ?? widget.hintText ?? '请选择',
              overflow: TextOverflow.ellipsis,
              style:
                  TextStyle(color: selected == null ? theme.hintColor : null),
            );
        Widget trigger = CompositedTransformTarget(
          link: _layerLink,
          child: GestureDetector(
            key: _targetKey,
            onTap: widget.enabled ? _toggle : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: widget.triggerHeight,
              padding: widget.triggerPadding,
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: borderColor),
                boxShadow: _open
                    ? [
                        BoxShadow(
                            color: theme.colorScheme.primary
                                .withValues(alpha: .12),
                            blurRadius: 0,
                            spreadRadius: 2)
                      ]
                    : null,
              ),
              child: Row(
                mainAxisSize:
                    fillsTriggerWidth ? MainAxisSize.max : MainAxisSize.min,
                children: [
                  if (widget.prefix != null) ...[
                    widget.prefix!,
                    const SizedBox(width: 8)
                  ],
                  if (fillsTriggerWidth)
                    Expanded(child: selectedChild)
                  else
                    selectedChild,
                  if (widget.showArrow)
                    AnimatedRotation(
                        turns: _open ? .5 : 0,
                        duration: const Duration(milliseconds: 150),
                        child: Icon(Icons.keyboard_arrow_down_rounded,
                            color: theme.hintColor)),
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
        if (widget.tooltip != null) {
          trigger = Tooltip(message: widget.tooltip!, child: trigger);
        }
        return Opacity(
          opacity: widget.enabled ? 1 : .55,
          child: Column(
            mainAxisSize:
                fillsAvailableWidth ? MainAxisSize.max : MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.label != null)
                Padding(
                  padding: const EdgeInsets.only(left: 3, bottom: 6),
                  child: Text(widget.label!,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: theme.textTheme.bodyMedium?.color)),
                ),
              trigger,
              if (widget.errorText != null)
                Padding(
                    padding: const EdgeInsets.only(left: 3, top: 5),
                    child: Text(widget.errorText!,
                        style: TextStyle(
                            fontSize: 11, color: theme.colorScheme.error))),
            ],
          ),
        );
      },
    );
  }

  void _toggle() => _open ? _close() : _openMenu();

  void _openMenu() {
    final overlay = Overlay.of(context);
    final renderBox =
        _targetKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final size = renderBox.size;
    final menuWidth = widget.menuWidth ?? size.width;
    final triggerOffset = renderBox.localToGlobal(Offset.zero);
    final opensLeft =
        widget.menuWidth != null && triggerOffset.dx + size.width >= menuWidth;
    final screenHeight = MediaQuery.of(context).size.height;
    const menuHeight = 310.0;
    final opensUpward =
        triggerOffset.dy + size.height + menuHeight > screenHeight;
    final options = List<NarrAItorDropdownOption<T>>.from(widget.options);
    final selectedValue = widget.value;
    final onChanged = widget.onChanged;
    final optionBuilder = widget.optionBuilder;
    _entry = OverlayEntry(builder: (overlayContext) {
      final theme = Theme.of(overlayContext);
      final dark = theme.brightness == Brightness.dark;
      return Stack(children: [
        Positioned.fill(
            child: GestureDetector(
                behavior: HitTestBehavior.translucent, onTap: _close)),
        CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: Offset(
            opensLeft ? size.width - menuWidth : 0,
            opensUpward ? -menuHeight - 7 : size.height + 7,
          ),
          child: Material(
            color: Colors.transparent,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                  minWidth: menuWidth, maxWidth: menuWidth, maxHeight: 310),
              child: DecoratedBox(
                decoration: BoxDecoration(
                    color: dark ? AppColors.darkSurface : Colors.white,
                    borderRadius: BorderRadius.circular(13),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: .14),
                          blurRadius: 18,
                          offset: const Offset(0, 8))
                    ]),
                child: ClipRRect(
                    borderRadius: BorderRadius.circular(13),
                    child: ListView(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        shrinkWrap: true,
                        children: options
                            .map((option) => _option(overlayContext, option,
                                selectedValue, onChanged, optionBuilder))
                            .toList())),
              ),
            ),
          ),
        ),
      ]);
    });
    overlay.insert(_entry!);
    setState(() => _open = true);
  }

  Widget _option(
    BuildContext menuContext,
    NarrAItorDropdownOption<T> option,
    T? selectedValue,
    ValueChanged<T?>? onChanged,
    Widget Function(NarrAItorDropdownOption<T> option)? optionBuilder,
  ) {
    final theme = Theme.of(menuContext);
    final selected = option.value == selectedValue;
    final tile = InkWell(
      onTap: option.enabled
          ? () {
              _close();
              onChanged?.call(option.value);
            }
          : null,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        color: selected
            ? theme.colorScheme.primary.withValues(alpha: .1)
            : Colors.transparent,
        child: optionBuilder?.call(option) ??
            Row(children: [
              if (option.leading != null) ...[
                option.leading!,
                const SizedBox(width: 9)
              ],
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                    Text(option.label,
                        style: TextStyle(
                            color:
                                option.enabled ? null : theme.disabledColor)),
                    if (option.subtitle != null)
                      Text(option.subtitle!,
                          style:
                              TextStyle(fontSize: 11, color: theme.hintColor))
                  ])),
              if (option.onAction != null)
                IconButton(
                  tooltip: option.actionTooltip,
                  icon: const Icon(Icons.delete_outline),
                  iconSize: 18,
                  color: theme.colorScheme.error,
                  onPressed: () {
                    option.onAction!.call();
                    _close();
                  },
                ),
              if (selected)
                Icon(Icons.check_rounded,
                    size: 18, color: theme.colorScheme.primary),
            ]),
      ),
    );
    if (!option.dividerBefore) return tile;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Divider(height: 1, color: theme.dividerColor),
      tile,
    ]);
  }

  void _close() {
    _entry?.remove();
    _entry = null;
    if (_open && mounted) setState(() => _open = false);
  }
}

/// 与 [NarrAItorDropdown] 使用相同触发器和悬浮样式的多选下拉。
///
/// 选项切换会立即通过 [onChanged] 返回新集合，菜单保持打开以便连续勾选。
class NarrAItorMultiSelectDropdown<T> extends StatefulWidget {
  final String? label;
  final String? hintText;
  final Set<T> values;
  final List<NarrAItorDropdownOption<T>> options;
  final ValueChanged<Set<T>>? onChanged;
  final bool enabled;
  final bool expanded;
  final Widget? prefix;
  final double triggerHeight;
  final EdgeInsetsGeometry triggerPadding;
  final bool showArrow;
  final double? menuWidth;
  final String? tooltip;
  final String? semanticLabel;
  final String? emptyText;
  final String Function(Set<T> values)? selectedBuilder;

  const NarrAItorMultiSelectDropdown({
    super.key,
    this.label,
    this.hintText,
    required this.values,
    required this.options,
    required this.onChanged,
    this.enabled = true,
    this.expanded = true,
    this.prefix,
    this.triggerHeight = 45,
    this.triggerPadding = const EdgeInsets.symmetric(horizontal: 14),
    this.showArrow = true,
    this.menuWidth,
    this.tooltip,
    this.semanticLabel,
    this.emptyText,
    this.selectedBuilder,
  });

  @override
  State<NarrAItorMultiSelectDropdown<T>> createState() =>
      _NarrAItorMultiSelectDropdownState<T>();
}

class _NarrAItorMultiSelectDropdownState<T>
    extends State<NarrAItorMultiSelectDropdown<T>> {
  final _targetKey = GlobalKey();
  final _layerLink = LayerLink();
  OverlayEntry? _entry;
  bool _open = false;

  @override
  void dispose() {
    _close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final theme = Theme.of(context);
      final dark = theme.brightness == Brightness.dark;
      final fillsAvailableWidth =
          widget.expanded && constraints.hasBoundedWidth;
      final selectedText = widget.selectedBuilder?.call(widget.values) ??
          (widget.values.isEmpty
              ? widget.hintText ?? '不指定'
              : '已选 ${widget.values.length} 项');
      final borderColor = _open
          ? theme.colorScheme.primary.withValues(alpha: .65)
          : Colors.transparent;
      Widget trigger = CompositedTransformTarget(
        link: _layerLink,
        child: GestureDetector(
          key: _targetKey,
          onTap: widget.enabled ? _toggle : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: widget.triggerHeight,
            padding: widget.triggerPadding,
            decoration: BoxDecoration(
              color: dark ? AppColors.darkSurface : const Color(0xffedebe7),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: borderColor),
              boxShadow: _open
                  ? [
                      BoxShadow(
                          color:
                              theme.colorScheme.primary.withValues(alpha: .12),
                          blurRadius: 0,
                          spreadRadius: 2)
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize:
                  fillsAvailableWidth ? MainAxisSize.max : MainAxisSize.min,
              children: [
                if (widget.prefix != null) ...[
                  widget.prefix!,
                  const SizedBox(width: 8),
                ],
                if (fillsAvailableWidth)
                  Expanded(
                    child: Text(selectedText,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: widget.values.isEmpty
                                ? theme.hintColor
                                : null)),
                  )
                else
                  Text(selectedText, overflow: TextOverflow.ellipsis),
                if (widget.showArrow)
                  AnimatedRotation(
                      turns: _open ? .5 : 0,
                      duration: const Duration(milliseconds: 150),
                      child: Icon(Icons.keyboard_arrow_down_rounded,
                          color: theme.hintColor)),
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
      if (widget.tooltip != null) {
        trigger = Tooltip(message: widget.tooltip!, child: trigger);
      }
      return Opacity(
        opacity: widget.enabled ? 1 : .55,
        child: Column(
          mainAxisSize:
              fillsAvailableWidth ? MainAxisSize.max : MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.label != null)
              Padding(
                padding: const EdgeInsets.only(left: 3, bottom: 6),
                child: Text(widget.label!,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: theme.textTheme.bodyMedium?.color)),
              ),
            trigger,
          ],
        ),
      );
    });
  }

  void _toggle() => _open ? _close() : _openMenu();

  void _openMenu() {
    final overlay = Overlay.of(context);
    final renderBox =
        _targetKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final size = renderBox.size;
    final menuWidth = widget.menuWidth ?? size.width;
    final triggerOffset = renderBox.localToGlobal(Offset.zero);
    final opensLeft =
        widget.menuWidth != null && triggerOffset.dx + size.width >= menuWidth;
    final screenHeight = MediaQuery.of(context).size.height;
    const menuHeight = 310.0;
    final opensUpward =
        triggerOffset.dy + size.height + menuHeight > screenHeight;
    final options = List<NarrAItorDropdownOption<T>>.from(widget.options);
    var selectedValues = Set<T>.from(widget.values);
    _entry = OverlayEntry(builder: (overlayContext) {
      final theme = Theme.of(overlayContext);
      final dark = theme.brightness == Brightness.dark;
      return Stack(children: [
        Positioned.fill(
            child: GestureDetector(
                behavior: HitTestBehavior.translucent, onTap: _close)),
        CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: Offset(
            opensLeft ? size.width - menuWidth : 0,
            opensUpward ? -menuHeight - 7 : size.height + 7,
          ),
          child: Material(
            color: Colors.transparent,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                  minWidth: menuWidth, maxWidth: menuWidth, maxHeight: 310),
              child: DecoratedBox(
                decoration: BoxDecoration(
                    color: dark ? AppColors.darkSurface : Colors.white,
                    borderRadius: BorderRadius.circular(13),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: .14),
                          blurRadius: 18,
                          offset: const Offset(0, 8))
                    ]),
                child: StatefulBuilder(builder: (context, setOverlayState) {
                  if (options.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(14),
                      child: Text(widget.emptyText ?? '暂无可选项',
                          style:
                              TextStyle(fontSize: 12, color: theme.hintColor)),
                    );
                  }
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(13),
                    child: ListView(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      shrinkWrap: true,
                      children: options
                          .map((option) => _option(
                                context,
                                option,
                                selectedValues,
                                () {
                                  final optionValue = option.value;
                                  if (optionValue == null) return;
                                  setOverlayState(() {
                                    if (selectedValues.contains(optionValue)) {
                                      selectedValues.remove(optionValue);
                                    } else {
                                      selectedValues.add(optionValue);
                                    }
                                  });
                                  widget.onChanged
                                      ?.call(Set<T>.from(selectedValues));
                                },
                              ))
                          .toList(),
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
      ]);
    });
    overlay.insert(_entry!);
    setState(() => _open = true);
  }

  Widget _option(
    BuildContext context,
    NarrAItorDropdownOption<T> option,
    Set<T> selectedValues,
    VoidCallback onToggle,
  ) {
    final theme = Theme.of(context);
    final selected = selectedValues.contains(option.value);
    final tile = InkWell(
      onTap: option.enabled ? onToggle : null,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        color: selected
            ? theme.colorScheme.primary.withValues(alpha: .1)
            : Colors.transparent,
        child: Row(children: [
          Checkbox(
              value: selected,
              onChanged: option.enabled ? (_) => onToggle() : null),
          const SizedBox(width: 4),
          if (option.leading != null) ...[
            option.leading!,
            const SizedBox(width: 9),
          ],
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                Text(option.label,
                    style: TextStyle(
                        color: option.enabled ? null : theme.disabledColor)),
                if (option.subtitle != null)
                  Text(option.subtitle!,
                      style: TextStyle(fontSize: 11, color: theme.hintColor)),
              ])),
        ]),
      ),
    );
    if (!option.dividerBefore) return tile;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Divider(height: 1, color: theme.dividerColor),
      tile,
    ]);
  }

  void _close() {
    _entry?.remove();
    _entry = null;
    if (_open && mounted) setState(() => _open = false);
  }
}
