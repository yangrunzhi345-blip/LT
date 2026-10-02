import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../l10n/generated/app_localizations_zh.dart';
import 'app_picker.dart';
import 'app_svg_icon.dart';

AppLocalizations _l10n(BuildContext context) =>
    AppLocalizations.of(context) ?? AppLocalizationsZh();

/// Shared metrics for every LT menu surface (select / action / multi-select).
///
/// There is exactly one menu visual kernel in the app. `AppSelect`,
/// `AppActionMenu` and `AppMultiSelectDropdown` only describe *semantics*; the
/// surface, item rendering, dimensions, state colours and responsive policy
/// all come from here. Feature code must never re-declare these numbers.
abstract final class AppMenuMetrics {
  AppMenuMetrics._();

  /// Menu panel corner radius (compact control radius).
  static const double radius = 6;

  /// Per-item corner radius.
  static const double itemRadius = 4;

  /// Minimum height of a plain menu row.
  static const double itemMinHeight = 36;

  /// Minimum height of a row that carries a subtitle.
  static const double itemMinHeightWithSubtitle = 52;

  /// Minimum touch target for a BottomSheet row.
  static const double sheetItemMinHeight = 48;

  /// Horizontal padding inside a desktop menu row.
  static const double itemHorizontalPadding = 10;

  /// Vertical padding inside a desktop menu row.
  static const double itemVerticalPadding = 6;

  /// Leading icon size.
  static const double iconSize = 18;

  /// Gap between a leading icon and the label.
  static const double iconGap = 10;

  /// Selected check glyph size.
  static const double checkSize = 18;

  /// Distance between the trigger and the menu.
  static const double triggerGap = 4;

  /// Outer padding of the menu panel.
  static const double outerPadding = 4;

  /// Maximum menu height before it scrolls.
  static const double maxHeight = 380;

  /// Maximum BottomSheet height.
  static const double sheetMaxHeight = 420;

  /// Minimum menu width.
  static const double minWidth = 200;

  /// Preferred maximum menu width for narrow triggers.
  static const double preferredMaxWidth = 320;

  /// Horizontal viewport safety margin.
  static const double viewportMargin = 16;

  /// BottomSheet height factor of the viewport.
  static const double sheetHeightFactor = 0.7;
}

/// Resolves a menu width from the trigger geometry, the viewport and an
/// optional explicit request. Callers must not hard-code page-level widths.
double resolveAppMenuWidth({
  required double? triggerWidth,
  required double overlayWidth,
  double? requested,
}) {
  final available =
      math.max(0.0, overlayWidth - 2 * AppMenuMetrics.viewportMargin);
  if (requested != null && requested > 0) return math.min(requested, available);
  final resolved = triggerWidth;
  if (resolved == null || resolved <= 0) {
    return math.min(AppMenuMetrics.minWidth, available);
  }
  final double width;
  if (resolved <= AppMenuMetrics.minWidth) {
    width = AppMenuMetrics.minWidth;
  } else {
    width = math.min(
      resolved,
      math.max(resolved, AppMenuMetrics.preferredMaxWidth),
    );
  }
  return math.min(width, available);
}

/// One entry of any LT menu.
///
/// This is the single item model shared by select, action and multi-select
/// menus. It deliberately stays close to data — value, label, state flags —
/// rather than embedding business widget trees.
@immutable
class AppMenuItem<T> {
  const AppMenuItem({
    required this.value,
    required this.label,
    this.subtitle,
    this.icon,
    this.leading,
    this.trailing,
    this.enabled = true,
    this.selected = false,
    this.destructive = false,
    this.dividerBefore = false,
    this.semanticLabel,
    this.contentOverride,
  });

  final T value;
  final String label;
  final String? subtitle;
  final String? icon;
  final Widget? leading;
  final Widget? trailing;
  final bool enabled;
  final bool selected;
  final bool destructive;
  final bool dividerBefore;
  final String? semanticLabel;

  /// Compatibility escape hatch for the legacy `AppSelectItem.customWidget`
  /// API. No production caller uses it; the kernel renders it in place of the
  /// label/subtitle stack when present.
  final Widget? contentOverride;

  bool get hasSubtitle => subtitle != null && subtitle!.trim().isNotEmpty;
}

/// Builds a trigger and hands it the callback that opens the shared menu.
typedef AppMenuTriggerBuilder = Widget Function(
  BuildContext context,
  VoidCallback open,
);

/// The single desktop/BottomSheet menu host.
///
/// `AppSelect`, `AppActionMenu` and `AppMultiSelectDropdown` all delegate here;
/// none of them build their own surface, item row, sheet or placement.
class AppMenuAnchor<T> extends StatefulWidget {
  const AppMenuAnchor({
    super.key,
    required this.triggerBuilder,
    required this.items,
    this.onActivated,
    this.selectedValues,
    this.onToggle,
    this.pickerStyle = AppSelectPickerStyle.auto,
    this.menuWidth,
    this.menuMaxHeight = AppMenuMetrics.maxHeight,
    this.sheetTitle,
  }) : assert(
          (onActivated != null && onToggle == null) ||
              (onActivated == null && onToggle != null),
          'AppMenuAnchor needs exactly one of onActivated / onToggle',
        );

  final AppMenuTriggerBuilder triggerBuilder;
  final List<AppMenuItem<T>> items;

  /// Single-select / action: called once when an item is activated.
  final ValueChanged<T>? onActivated;

  /// Multi-select: the current selection and the toggle callback.
  final Set<T>? selectedValues;
  final ValueChanged<T>? onToggle;

  final AppSelectPickerStyle pickerStyle;
  final double? menuWidth;
  final double menuMaxHeight;
  final String? sheetTitle;

  bool get _isMulti => onToggle != null;

  @override
  State<AppMenuAnchor<T>> createState() => _AppMenuAnchorState<T>();
}

class _AppMenuAnchorState<T> extends State<AppMenuAnchor<T>> {
  final MenuController _controller = MenuController();
  final GlobalKey _anchorKey = GlobalKey();

  /// Trigger width, captured after layout. Reading `RenderBox.size` during
  /// build is illegal, so the width policy uses the previous frame's value; by
  /// the time a menu can be opened the trigger has already been laid out.
  double? _triggerWidth;

  bool _isSelected(AppMenuItem<T> item) => widget._isMulti
      ? (widget.selectedValues?.contains(item.value) ?? false)
      : item.selected;

  void _activate(AppMenuItem<T> item) {
    if (!item.enabled) return;
    if (widget._isMulti) {
      widget.onToggle!(item.value);
    } else {
      widget.onActivated!(item.value);
    }
  }

  void _syncTriggerWidth() {
    if (!mounted) return;
    final width = _anchorKey.currentContext?.size?.width;
    if (width == null) return;
    if (_triggerWidth == null || (width - _triggerWidth!).abs() > 0.5) {
      setState(() => _triggerWidth = width);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return widget.triggerBuilder(context, () {});
    }
    if (appPickerUsesBottomSheet(context, widget.pickerStyle)) {
      return widget.triggerBuilder(context, () => _openSheet(context));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncTriggerWidth());
    final width = resolveAppMenuWidth(
      triggerWidth: _triggerWidth,
      overlayWidth: MediaQuery.sizeOf(context).width,
      requested: widget.menuWidth,
    );
    return MenuAnchor(
      controller: _controller,
      animated: false,
      alignmentOffset: const Offset(0, AppMenuMetrics.triggerGap),
      style: _menuPanelStyle(
        context,
        width: width,
        maxHeight: widget.menuMaxHeight,
      ),
      menuChildren: _buildMenuChildren(context),
      builder: (context, controller, child) => KeyedSubtree(
        key: _anchorKey,
        child: widget.triggerBuilder(
          context,
          () => controller.isOpen ? controller.close() : controller.open(),
        ),
      ),
    );
  }

  List<Widget> _buildMenuChildren(BuildContext context) {
    final children = <Widget>[];
    for (final item in widget.items) {
      if (item.dividerBefore) children.add(const Divider(height: 1));
      final selected = _isSelected(item);
      children.add(
        MenuItemButton(
          closeOnActivate: !widget._isMulti,
          onPressed: item.enabled ? () => _activate(item) : null,
          style: _menuItemButtonStyle(
            context,
            selected: selected,
            hasSubtitle: item.hasSubtitle,
          ),
          child: _AppMenuItemView<T>(item: item, selected: selected),
        ),
      );
    }
    return children;
  }

  Future<void> _openSheet(BuildContext context) async {
    FocusScope.of(context).unfocus();
    final l10n = _l10n(context);
    final title = widget.sheetTitle ??
        (widget._isMulti ? l10n.selectPrompt : l10n.actionMenuTitle);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _sheetBackground(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        if (widget._isMulti) {
          return StatefulBuilder(
            builder: (context, setSheetState) => _AppMenuSheet(
              title: title,
              children: [
                for (final item in widget.items)
                  _AppSheetRow<T>(
                    item: item,
                    selected: _isSelected(item),
                    onTap: item.enabled
                        ? () {
                            _activate(item);
                            setSheetState(() {});
                          }
                        : null,
                  ),
              ],
            ),
          );
        }
        return _AppMenuSheet(
          title: title,
          children: [
            for (final item in widget.items)
              _AppSheetRow<T>(
                item: item,
                selected: _isSelected(item),
                onTap: item.enabled
                    ? () {
                        Navigator.of(sheetContext).pop();
                        _activate(item);
                      }
                    : null,
              ),
          ],
        );
      },
    );
  }
}

/// The shared menu panel style: compact radius, single subtle border, a quiet
/// raised surface and a soft shadow.
MenuStyle _menuPanelStyle(
  BuildContext context, {
  required double width,
  required double maxHeight,
}) {
  final scheme = Theme.of(context).colorScheme;
  return MenuStyle(
    backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainerHigh),
    surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
    shadowColor: WidgetStatePropertyAll(
      Colors.black.withValues(alpha: 0.18),
    ),
    elevation: const WidgetStatePropertyAll(6),
    padding: const WidgetStatePropertyAll(
      EdgeInsets.all(AppMenuMetrics.outerPadding),
    ),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppMenuMetrics.radius),
        side: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: 0.8),
        ),
      ),
    ),
    minimumSize: WidgetStatePropertyAll(Size(width, 0)),
    maximumSize: WidgetStatePropertyAll(Size(width, maxHeight)),
  );
}

/// Shared row style for [MenuItemButton]: 36 px plain / 52 px with subtitle,
/// quiet selected tint and a subtle hover overlay.
ButtonStyle _menuItemButtonStyle(
  BuildContext context, {
  required bool selected,
  required bool hasSubtitle,
}) {
  final scheme = Theme.of(context).colorScheme;
  return ButtonStyle(
    minimumSize: WidgetStatePropertyAll(
      Size(
        0,
        hasSubtitle
            ? AppMenuMetrics.itemMinHeightWithSubtitle
            : AppMenuMetrics.itemMinHeight,
      ),
    ),
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(
        horizontal: AppMenuMetrics.itemHorizontalPadding,
        vertical: AppMenuMetrics.itemVerticalPadding,
      ),
    ),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppMenuMetrics.itemRadius),
      ),
    ),
    backgroundColor: WidgetStatePropertyAll(
      selected ? scheme.primary.withValues(alpha: 0.08) : Colors.transparent,
    ),
    overlayColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.pressed)) {
        return scheme.onSurface.withValues(alpha: 0.08);
      }
      if (states.contains(WidgetState.hovered) ||
          states.contains(WidgetState.focused)) {
        return scheme.onSurface.withValues(alpha: 0.05);
      }
      return null;
    }),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    alignment: AlignmentDirectional.centerStart,
  );
}

Color _sheetBackground(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? AppColors.darkSurface
        : AppColors.surfaceElevated;

/// One row of a menu, shared by the desktop menu and the BottomSheet.
class _AppMenuItemView<T> extends StatelessWidget {
  const _AppMenuItemView({
    required this.item,
    required this.selected,
    this.dense = false,
  });

  final AppMenuItem<T> item;
  final bool selected;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final Color color = !item.enabled
        ? scheme.onSurface.withValues(alpha: 0.38)
        : item.destructive
            ? scheme.error
            : scheme.onSurface;
    final Color subtitleColor = !item.enabled
        ? scheme.onSurface.withValues(alpha: 0.38)
        : item.destructive
            ? scheme.error.withValues(alpha: 0.85)
            : scheme.onSurfaceVariant;
    final double iconSize = dense ? 20 : AppMenuMetrics.iconSize;

    Widget? leading;
    if (item.leading != null) {
      leading = item.leading;
    } else if (item.icon != null) {
      leading = AppSvgIcon(item.icon!, size: iconSize, color: color);
    }

    final children = <Widget>[
      if (leading != null) ...[
        leading,
        SizedBox(width: dense ? 12 : AppMenuMetrics.iconGap),
      ],
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (item.contentOverride != null)
              item.contentOverride!
            else
              Text(
                item.label,
                maxLines: dense ? 2 : 1,
                overflow: TextOverflow.ellipsis,
                style: (dense
                        ? theme.textTheme.bodyLarge
                        : theme.textTheme.bodyMedium)
                    ?.copyWith(
                  color: color,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            if (item.hasSubtitle)
              Text(
                item.subtitle!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style:
                    theme.textTheme.bodySmall?.copyWith(color: subtitleColor),
              ),
          ],
        ),
      ),
    ];

    final Widget? trailing = item.trailing ??
        (selected
            ? AppSvgIcon(
                'check',
                size: AppMenuMetrics.checkSize,
                color: item.enabled ? scheme.primary : color,
              )
            : null);
    if (trailing != null) {
      children.add(const SizedBox(width: AppMenuMetrics.iconGap));
      children.add(trailing);
    }

    return Semantics(
      selected: selected,
      enabled: item.enabled,
      label: item.semanticLabel ?? item.label,
      child: Row(children: children),
    );
  }
}

/// Unified BottomSheet chrome: drag handle, title row, close action and divider.
class _AppMenuSheet extends StatelessWidget {
  const _AppMenuSheet({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = _l10n(context);
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: math.min(
            AppMenuMetrics.sheetMaxHeight,
            MediaQuery.sizeOf(context).height *
                AppMenuMetrics.sheetHeightFactor,
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
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    icon: const AppSvgIcon('close', size: 20),
                    tooltip: l10n.closeAction,
                    onPressed: () => Navigator.of(context).pop(),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(child: ListView(shrinkWrap: true, children: children)),
          ],
        ),
      ),
    );
  }
}

/// One tappable row inside the BottomSheet.
class _AppSheetRow<T> extends StatelessWidget {
  const _AppSheetRow({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final AppMenuItem<T> item;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(
          minHeight: AppMenuMetrics.sheetItemMinHeight,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        alignment: AlignmentDirectional.centerStart,
        child: _AppMenuItemView<T>(item: item, selected: selected, dense: true),
      ),
    );
  }
}
