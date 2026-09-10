import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../theme/app_radius.dart';

/// 下拉菜单选项项配置
class AppDropdownOption<T> {
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
}

/// 兼容别名
typedef AppDropdownItem<T> = AppDropdownOption<T>;

/// 下拉组件视觉形态
enum AppDropdownVariant {
  /// 紧凑型胶囊/徽章样式，适合卡片内嵌、身份标签、表格行内操作
  compact,

  /// 标准表单输入框样式，带圆角边框、聚焦高亮与统一内边距
  form,

  /// 强调型主色调样式
  tonal,

  /// 无边框极简文本样式
  borderless,
}

/// 下拉菜单弹出方向偏好
enum AppDropdownDirection {
  /// 默认始终向下弹出
  down,

  /// 向上弹出
  up,

  /// 智能自适应（仅当下部可用空间严重不足时向上翻折）
  auto,
}

/// 全局统一全端下拉选择控件 [AppDropdown]
///
/// 遵循 Material 3 设计语言，支持浅色/深色主题动态适配。
/// 浮层菜单默认始终向下弹出（支持配置方向偏好与剩余空间约束计算）、
/// 平滑大圆角、柔和微投影、动态滚动高度限制、选中项高亮背景与对勾标记。
class AppDropdown<T> extends StatefulWidget {
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
    this.menuMaxHeight = 280.0,
    this.showArrow = true,
    this.tooltip,
    this.semanticLabel,
    this.selectedBuilder,
    this.optionBuilder,
  });

  /// 紧凑胶囊样式构造器：适合身份定位、关系网等内嵌卡片场景，默认向下弹出
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
    this.triggerHeight = 32.0,
    this.triggerPadding =
        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    this.menuWidth,
    this.menuMaxHeight = 280.0,
    this.showArrow = true,
    this.tooltip,
    this.semanticLabel,
    this.selectedBuilder,
    this.optionBuilder,
  }) : variant = AppDropdownVariant.compact;

  /// 标准表单样式构造器：适合设置中心、模型选择、属性配置等表单场景，默认向下弹出
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
    this.triggerHeight = 46.0,
    this.triggerPadding =
        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    this.menuWidth,
    this.menuMaxHeight = 300.0,
    this.showArrow = true,
    this.tooltip,
    this.semanticLabel,
    this.selectedBuilder,
    this.optionBuilder,
  }) : variant = AppDropdownVariant.form;

  /// 色彩调性样式构造器：适合高亮选项、过滤器，默认向下弹出
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
    this.triggerHeight = 32.0,
    this.triggerPadding =
        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    this.menuWidth,
    this.menuMaxHeight = 280.0,
    this.showArrow = true,
    this.tooltip,
    this.semanticLabel,
    this.selectedBuilder,
    this.optionBuilder,
  }) : variant = AppDropdownVariant.tonal;

  @override
  State<AppDropdown<T>> createState() => _AppDropdownState<T>();
}

class _AppDropdownState<T> extends State<AppDropdown<T>> {
  final _targetKey = GlobalKey();
  final _layerLink = LayerLink();
  OverlayEntry? _entry;
  bool _open = false;
  bool _isHovered = false;

  AppDropdownOption<T>? get _selected {
    for (final option in widget.options) {
      if (option.value == widget.value) return option;
    }
    return null;
  }

  @override
  void dispose() {
    _entry?.remove();
    _entry = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        final selected = _selected;

        final isCompact = widget.variant == AppDropdownVariant.compact;
        final isTonal = widget.variant == AppDropdownVariant.tonal;
        final isBorderless = widget.variant == AppDropdownVariant.borderless;

        final fillsAvailableWidth =
            widget.expanded && constraints.hasBoundedWidth;
        final fillsTightCompactWidth =
            !widget.expanded && constraints.hasTightWidth;
        final fillsTriggerWidth = fillsAvailableWidth || fillsTightCompactWidth;

        // 背景颜色与边框样式根据模式和主题动态计算
        Color background;
        Color borderColor;
        BorderRadius borderRadius;

        if (isBorderless) {
          background = Colors.transparent;
          borderColor = Colors.transparent;
          borderRadius = BorderRadius.circular(AppRadius.sm);
        } else if (isTonal) {
          background = scheme.primaryContainer.withValues(alpha: 0.35);
          borderColor = _open
              ? scheme.primary
              : (_isHovered
                  ? scheme.primary.withValues(alpha: 0.5)
                  : scheme.primary.withValues(alpha: 0.2));
          borderRadius = BorderRadius.circular(AppRadius.full);
        } else if (isCompact) {
          background = scheme.surfaceContainerHighest.withValues(alpha: 0.35);
          borderColor = widget.errorText != null
              ? scheme.error
              : (_open
                  ? scheme.primary
                  : (_isHovered
                      ? scheme.primary.withValues(alpha: 0.6)
                      : scheme.outlineVariant.withValues(alpha: 0.5)));
          borderRadius = BorderRadius.circular(AppRadius.sm);
        } else {
          // form 默认形态
          background = scheme.surfaceContainerLow;
          borderColor = widget.errorText != null
              ? scheme.error
              : (_open
                  ? scheme.primary
                  : (_isHovered
                      ? scheme.primary.withValues(alpha: 0.5)
                      : scheme.outlineVariant.withValues(alpha: 0.4)));
          borderRadius = BorderRadius.circular(AppRadius.lg);
        }

        final height = widget.triggerHeight ?? (isCompact ? 32.0 : 46.0);
        final padding = widget.triggerPadding ??
            (isCompact
                ? const EdgeInsets.symmetric(horizontal: 10, vertical: 4)
                : const EdgeInsets.symmetric(horizontal: 14, vertical: 8));

        final selectedChild = widget.selectedBuilder?.call(widget.value) ??
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selected?.leading != null) ...[
                  selected!.leading!,
                  const SizedBox(width: 6),
                ] else if (selected?.icon != null) ...[
                  Icon(
                    selected!.icon,
                    size: isCompact ? 14 : 16,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(
                    selected?.label ?? widget.hintText ?? '请选择',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: isCompact ? 12 : 13,
                      fontWeight:
                          isCompact ? FontWeight.w500 : FontWeight.normal,
                      color: selected == null
                          ? theme.hintColor
                          : (isTonal ? scheme.primary : scheme.onSurface),
                    ),
                  ),
                ),
              ],
            );

        Widget trigger = CompositedTransformTarget(
          link: _layerLink,
          child: MouseRegion(
            onEnter: (_) {
              if (widget.enabled && !_isHovered) {
                setState(() => _isHovered = true);
              }
            },
            onExit: (_) {
              if (_isHovered) {
                setState(() => _isHovered = false);
              }
            },
            child: InkWell(
              key: _targetKey,
              onTap: widget.enabled ? _toggle : null,
              borderRadius: borderRadius,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                height: height,
                padding: padding,
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: borderRadius,
                  border: Border.all(color: borderColor),
                  boxShadow: _open && !isBorderless
                      ? [
                          BoxShadow(
                            color: scheme.primary.withValues(alpha: 0.12),
                            blurRadius: 0,
                            spreadRadius: 2,
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisSize:
                      fillsTriggerWidth ? MainAxisSize.max : MainAxisSize.min,
                  children: [
                    if (widget.prefix != null) ...[
                      widget.prefix!,
                      const SizedBox(width: 8),
                    ],
                    if (fillsTriggerWidth)
                      Expanded(child: selectedChild)
                    else
                      selectedChild,
                    if (widget.showArrow) ...[
                      const SizedBox(width: 4),
                      AnimatedRotation(
                        turns: _open ? 0.5 : 0,
                        duration: const Duration(milliseconds: 180),
                        child: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: isCompact ? 16 : 18,
                          color: _open
                              ? scheme.primary
                              : (_isHovered
                                  ? scheme.onSurface
                                  : theme.hintColor),
                        ),
                      ),
                    ],
                  ],
                ),
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
          opacity: widget.enabled ? 1.0 : 0.45,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.label != null)
                Padding(
                  padding: const EdgeInsets.only(left: 2, bottom: 6),
                  child: Text(
                    widget.label!,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: theme.textTheme.bodyMedium?.color,
                    ),
                  ),
                ),
              trigger,
              if (widget.errorText != null)
                Padding(
                  padding: const EdgeInsets.only(left: 4, top: 4),
                  child: Text(
                    widget.errorText!,
                    style: TextStyle(fontSize: 11, color: scheme.error),
                  ),
                ),
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
    final isCompact = widget.variant == AppDropdownVariant.compact;
    final triggerOffset = renderBox.localToGlobal(Offset.zero);
    final screenSize = MediaQuery.of(context).size;

    // 智能计算浮层宽度：紧凑模式保证最小宽度不挤占内容
    final calculatedMinWidth =
        isCompact ? math.max(size.width, 140.0) : size.width;
    final menuWidth = widget.menuWidth ?? calculatedMinWidth;

    // 预估菜单自然高度
    final optionsCount = widget.options.length;
    final estimatedHeight = math.min(
      widget.menuMaxHeight,
      optionsCount * (isCompact ? 38.0 : 42.0) + 12.0,
    );

    final spaceBelow = screenSize.height - (triggerOffset.dy + size.height);

    // 默认始终向下弹出：仅在明确设置为 up，或在 auto 且下方空间严重不足（<100px）时才向上
    final bool opensUpward;
    switch (widget.direction) {
      case AppDropdownDirection.down:
        opensUpward = false;
        break;
      case AppDropdownDirection.up:
        opensUpward = true;
        break;
      case AppDropdownDirection.auto:
        opensUpward = spaceBelow < 100.0 && triggerOffset.dy > spaceBelow;
        break;
    }

    // 计算实际允许的最大菜单高度（留出 16px 屏幕安全边距）
    final availableHeight = opensUpward
        ? math.max(120.0, triggerOffset.dy - 16.0)
        : math.max(120.0, spaceBelow - 16.0);
    final effectiveHeight = math.min(
      widget.menuMaxHeight,
      math.min(estimatedHeight, availableHeight),
    );

    // 水平方向防超出屏幕
    final opensLeft = triggerOffset.dx + menuWidth > screenSize.width;
    final horizontalOffset = opensLeft ? size.width - menuWidth : 0.0;

    final options = List<AppDropdownOption<T>>.from(widget.options);
    final selectedValue = widget.value;
    final onChanged = widget.onChanged;
    final optionBuilder = widget.optionBuilder;

    _entry = OverlayEntry(
      builder: (overlayContext) {
        final theme = Theme.of(overlayContext);
        final scheme = theme.colorScheme;
        final dark = theme.brightness == Brightness.dark;

        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _close,
              ),
            ),
            CompositedTransformFollower(
              link: _layerLink,
              showWhenUnlinked: false,
              offset: Offset(
                horizontalOffset,
                opensUpward ? -effectiveHeight - 6 : size.height + 6,
              ),
              child: Material(
                color: Colors.transparent,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: menuWidth,
                    maxWidth: math.max(menuWidth, 280.0),
                    maxHeight: effectiveHeight,
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      border: Border.all(
                        color: scheme.outlineVariant.withValues(alpha: 0.35),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black
                              .withValues(alpha: dark ? 0.35 : 0.12),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      child: ListView(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        shrinkWrap: true,
                        children: options
                            .map((option) => _buildOptionItem(
                                  overlayContext,
                                  option,
                                  selectedValue,
                                  onChanged,
                                  optionBuilder,
                                  isCompact,
                                ))
                            .toList(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    overlay.insert(_entry!);
    setState(() => _open = true);
  }

  Widget _buildOptionItem(
    BuildContext menuContext,
    AppDropdownOption<T> option,
    T? selectedValue,
    ValueChanged<T?>? onChanged,
    Widget Function(AppDropdownOption<T> option)? optionBuilder,
    bool isCompact,
  ) {
    final theme = Theme.of(menuContext);
    final scheme = theme.colorScheme;
    final selected = option.value == selectedValue;

    final tile = InkWell(
      onTap: option.enabled
          ? () {
              _close();
              onChanged?.call(option.value);
            }
          : null,
      hoverColor: scheme.onSurface.withValues(alpha: 0.06),
      child: Container(
        constraints: BoxConstraints(minHeight: isCompact ? 36 : 40),
        padding: EdgeInsets.symmetric(
          horizontal: isCompact ? 10 : 14,
          vertical: isCompact ? 6 : 8,
        ),
        color: selected
            ? scheme.primary.withValues(alpha: 0.12)
            : Colors.transparent,
        child: optionBuilder?.call(option) ??
            Row(
              children: [
                if (option.leading != null) ...[
                  option.leading!,
                  const SizedBox(width: 8),
                ] else if (option.icon != null) ...[
                  Icon(
                    option.icon,
                    size: isCompact ? 14 : 16,
                    color: selected ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        option.label,
                        style: TextStyle(
                          fontSize: isCompact ? 12 : 13,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.normal,
                          color: !option.enabled
                              ? theme.disabledColor
                              : (selected ? scheme.primary : scheme.onSurface),
                        ),
                      ),
                      if (option.subtitle != null) ...[
                        const SizedBox(height: 1),
                        Text(
                          option.subtitle!,
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (option.onAction != null)
                  IconButton(
                    tooltip: option.actionTooltip,
                    icon: const Icon(Icons.delete_outline),
                    iconSize: 16,
                    color: scheme.error,
                    onPressed: () {
                      option.onAction!.call();
                      _close();
                    },
                  ),
                if (selected) ...[
                  const SizedBox(width: 6),
                  Icon(
                    Icons.check_rounded,
                    size: 16,
                    color: scheme.primary,
                  ),
                ],
              ],
            ),
      ),
    );

    if (!option.dividerBefore) return tile;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Divider(
          height: 1,
          color: scheme.outlineVariant.withValues(alpha: 0.3),
        ),
        tile,
      ],
    );
  }

  void _close() {
    _entry?.remove();
    _entry = null;
    if (_open && mounted) setState(() => _open = false);
  }
}

/// 全局统一全端多选下拉控件 [AppMultiSelectDropdown]
class AppMultiSelectDropdown<T> extends StatefulWidget {
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
    this.triggerHeight = 46.0,
    this.triggerPadding =
        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    this.showArrow = true,
    this.menuWidth,
    this.tooltip,
    this.semanticLabel,
    this.emptyText,
    this.selectedBuilder,
  });

  @override
  State<AppMultiSelectDropdown<T>> createState() =>
      _AppMultiSelectDropdownState<T>();
}

class _AppMultiSelectDropdownState<T> extends State<AppMultiSelectDropdown<T>> {
  final _targetKey = GlobalKey();
  final _layerLink = LayerLink();
  OverlayEntry? _entry;
  bool _open = false;
  bool _isHovered = false;

  @override
  void dispose() {
    _entry?.remove();
    _entry = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        final fillsAvailableWidth =
            widget.expanded && constraints.hasBoundedWidth;

        final selectedText = widget.selectedBuilder?.call(widget.values) ??
            (widget.values.isEmpty
                ? widget.hintText ?? '不指定'
                : '已选 ${widget.values.length} 项');

        final borderColor = _open
            ? scheme.primary
            : (_isHovered
                ? scheme.primary.withValues(alpha: 0.5)
                : scheme.outlineVariant.withValues(alpha: 0.4));

        Widget trigger = CompositedTransformTarget(
          link: _layerLink,
          child: MouseRegion(
            onEnter: (_) => setState(() => _isHovered = true),
            onExit: (_) => setState(() => _isHovered = false),
            child: InkWell(
              key: _targetKey,
              onTap: widget.enabled ? _toggle : null,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                height: widget.triggerHeight,
                padding: widget.triggerPadding,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(color: borderColor),
                  boxShadow: _open
                      ? [
                          BoxShadow(
                            color: scheme.primary.withValues(alpha: 0.12),
                            blurRadius: 0,
                            spreadRadius: 2,
                          ),
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
                        child: Text(
                          selectedText,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: widget.values.isEmpty
                                ? theme.hintColor
                                : scheme.onSurface,
                          ),
                        ),
                      )
                    else
                      Text(
                        selectedText,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                    if (widget.showArrow) ...[
                      const SizedBox(width: 4),
                      AnimatedRotation(
                        turns: _open ? 0.5 : 0,
                        duration: const Duration(milliseconds: 180),
                        child: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 18,
                          color: _open ? scheme.primary : theme.hintColor,
                        ),
                      ),
                    ],
                  ],
                ),
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
          opacity: widget.enabled ? 1.0 : 0.45,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.label != null)
                Padding(
                  padding: const EdgeInsets.only(left: 2, bottom: 6),
                  child: Text(
                    widget.label!,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: theme.textTheme.bodyMedium?.color,
                    ),
                  ),
                ),
              trigger,
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
    final screenSize = MediaQuery.of(context).size;

    final options = List<AppDropdownOption<T>>.from(widget.options);
    final estimatedHeight = math.min(
      300.0,
      options.length * 44.0 + 16.0,
    );

    final spaceBelow = screenSize.height - (triggerOffset.dy + size.height);

    // 默认始终向下弹出：仅在明确设置为 up，或在 auto 且下方空间严重不足（<100px）时才向上
    final bool opensUpward;
    switch (widget.direction) {
      case AppDropdownDirection.down:
        opensUpward = false;
        break;
      case AppDropdownDirection.up:
        opensUpward = true;
        break;
      case AppDropdownDirection.auto:
        opensUpward = spaceBelow < 100.0 && triggerOffset.dy > spaceBelow;
        break;
    }

    final availableHeight = opensUpward
        ? math.max(120.0, triggerOffset.dy - 16.0)
        : math.max(120.0, spaceBelow - 16.0);
    final effectiveHeight = math.min(
      300.0,
      math.min(estimatedHeight, availableHeight),
    );

    final opensLeft = triggerOffset.dx + menuWidth > screenSize.width;
    final horizontalOffset = opensLeft ? size.width - menuWidth : 0.0;

    var selectedValues = Set<T>.from(widget.values);

    _entry = OverlayEntry(
      builder: (overlayContext) {
        final theme = Theme.of(overlayContext);
        final scheme = theme.colorScheme;
        final dark = theme.brightness == Brightness.dark;

        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _close,
              ),
            ),
            CompositedTransformFollower(
              link: _layerLink,
              showWhenUnlinked: false,
              offset: Offset(
                horizontalOffset,
                opensUpward ? -effectiveHeight - 6 : size.height + 6,
              ),
              child: Material(
                color: Colors.transparent,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: menuWidth,
                    maxWidth: math.max(menuWidth, 280.0),
                    maxHeight: effectiveHeight,
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      border: Border.all(
                        color: scheme.outlineVariant.withValues(alpha: 0.35),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black
                              .withValues(alpha: dark ? 0.35 : 0.12),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: StatefulBuilder(
                      builder: (context, setOverlayState) {
                        if (options.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              widget.emptyText ?? '暂无可选项',
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.hintColor,
                              ),
                            ),
                          );
                        }
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadius.lg),
                          child: ListView(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            shrinkWrap: true,
                            children: options
                                .map((option) => _buildOption(
                                      context,
                                      option,
                                      selectedValues,
                                      () {
                                        final optionValue = option.value;
                                        if (optionValue == null) return;
                                        setOverlayState(() {
                                          if (selectedValues
                                              .contains(optionValue)) {
                                            selectedValues.remove(optionValue);
                                          } else {
                                            selectedValues.add(optionValue);
                                          }
                                        });
                                        widget.onChanged?.call(
                                          Set<T>.from(selectedValues),
                                        );
                                      },
                                    ))
                                .toList(),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    overlay.insert(_entry!);
    setState(() => _open = true);
  }

  Widget _buildOption(
    BuildContext context,
    AppDropdownOption<T> option,
    Set<T> selectedValues,
    VoidCallback onToggle,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selected = selectedValues.contains(option.value);

    final tile = InkWell(
      onTap: option.enabled ? onToggle : null,
      hoverColor: scheme.onSurface.withValues(alpha: 0.06),
      child: Container(
        constraints: const BoxConstraints(minHeight: 40),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        color: selected
            ? scheme.primary.withValues(alpha: 0.12)
            : Colors.transparent,
        child: Row(
          children: [
            Checkbox(
              value: selected,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: option.enabled ? (_) => onToggle() : null,
            ),
            const SizedBox(width: 6),
            if (option.leading != null) ...[
              option.leading!,
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    option.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.normal,
                      color: option.enabled
                          ? scheme.onSurface
                          : theme.disabledColor,
                    ),
                  ),
                  if (option.subtitle != null)
                    Text(
                      option.subtitle!,
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (!option.dividerBefore) return tile;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Divider(
          height: 1,
          color: scheme.outlineVariant.withValues(alpha: 0.3),
        ),
        tile,
      ],
    );
  }

  void _close() {
    _entry?.remove();
    _entry = null;
    if (_open && mounted) setState(() => _open = false);
  }
}
