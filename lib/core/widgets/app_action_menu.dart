import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'app_picker.dart';

/// One selectable entry of an [AppActionMenu].
///
/// An *action* menu entry is a command, not a value being chosen, so it carries
/// no `selected` state. That is the semantic difference from `AppSelectItem`.
@immutable
class AppActionMenuItem<T> {
  const AppActionMenuItem({
    required this.value,
    required this.label,
    this.icon,
    this.subtitle,
    this.enabled = true,
    this.destructive = false,
    this.dividerBefore = false,
  });

  final T value;
  final String label;
  final IconData? icon;
  final String? subtitle;

  /// Disabled entries are greyed out and cannot be activated.
  final bool enabled;

  /// Renders the entry with the theme error color. Used for delete / discard.
  final bool destructive;

  /// Draws a separator above this entry, grouping it apart from the entries
  /// above (for example separating "delete" from the safe actions).
  final bool dividerBefore;
}

/// Unified action / context menu for every three-dot, card and context menu.
///
/// Follows the R02 UI Foundation placement policy shared with
/// [AppSelectPickerStyle]: compact viewports (< 600) open a touch-friendly
/// BottomSheet, wider viewports open an anchored menu next to the trigger.
/// Feature code must not build its own `PopupMenuButton` / overlay menu.
class AppActionMenu<T> extends StatelessWidget {
  const AppActionMenu({
    super.key,
    required this.items,
    required this.onSelected,
    this.icon = Icons.more_vert_rounded,
    this.iconSize = 20,
    this.iconColor,
    this.tooltip,
    this.semanticLabel,
    this.enabled = true,
    this.pickerStyle = AppSelectPickerStyle.auto,
    this.sheetTitle,
    this.menuMaxHeight = 380,
    this.padding = EdgeInsets.zero,
  });

  final List<AppActionMenuItem<T>> items;
  final ValueChanged<T> onSelected;
  final IconData icon;
  final double iconSize;
  final Color? iconColor;
  final String? tooltip;
  final String? semanticLabel;
  final bool enabled;
  final AppSelectPickerStyle pickerStyle;
  final String? sheetTitle;
  final double menuMaxHeight;
  final EdgeInsetsGeometry padding;

  /// Whether any entry can actually be activated; an all-disabled menu is a
  /// dead control and is rendered as such instead of opening an empty list.
  bool get _hasEnabledItem => items.any((item) => item.enabled);

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final isInteractive = enabled && _hasEnabledItem;

    Widget trigger = Builder(
      builder: (triggerContext) => IconButton(
        icon: Icon(icon, size: iconSize, color: iconColor),
        tooltip: tooltip,
        padding: padding,
        visualDensity: VisualDensity.compact,
        onPressed: isInteractive ? () => _open(triggerContext) : null,
      ),
    );
    trigger = Semantics(
      button: true,
      enabled: isInteractive,
      label: semanticLabel ?? tooltip ?? '操作菜单',
      child: trigger,
    );
    return trigger;
  }

  Future<void> _open(BuildContext context) async {
    FocusScope.of(context).unfocus();
    if (appPickerUsesBottomSheet(context, pickerStyle)) {
      await _openBottomSheet(context);
      return;
    }
    final anchor = appPickerAnchor(context);
    if (anchor == null) {
      await _openBottomSheet(context);
      return;
    }
    await _openMenu(context, anchor);
  }

  Future<void> _openMenu(BuildContext context, AppPickerAnchor anchor) async {
    final availableWidth = math.max(0.0, anchor.overlaySize.width - 16);
    final minimumWidth =
        math.min(math.max(anchor.triggerSize.width, 220.0), availableWidth);
    final maximumWidth =
        math.min(math.max(anchor.triggerSize.width, 320.0), availableWidth);

    final selected = await showMenu<_ActionMenuResult<T>>(
      context: context,
      position: anchor.position,
      popUpAnimationStyle: AnimationStyle.noAnimation,
      constraints: BoxConstraints(
        minWidth: minimumWidth,
        maxWidth: maximumWidth,
        maxHeight: menuMaxHeight,
      ),
      items: [
        for (final item in items) ...[
          if (item.dividerBefore) const PopupMenuDivider(),
          PopupMenuItem<_ActionMenuResult<T>>(
            value: _ActionMenuResult<T>(item.value),
            enabled: item.enabled,
            child: _ActionMenuRow<T>(item: item),
          ),
        ],
      ],
    );

    if (selected case _ActionMenuResult<T>(:final value)) {
      onSelected(value);
    }
  }

  Future<void> _openBottomSheet(BuildContext context) async {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final selected = await showModalBottomSheet<_ActionMenuResult<T>>(
      context: context,
      isScrollControlled: true,
      backgroundColor:
          isDark ? AppColors.darkSurface : AppColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
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
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
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
                        sheetTitle ?? '操作',
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
                  itemBuilder: (_, index) {
                    final item = items[index];
                    final tile = ListTile(
                      dense: true,
                      enabled: item.enabled,
                      onTap: item.enabled
                          ? () => Navigator.of(sheetContext)
                              .pop(_ActionMenuResult<T>(item.value))
                          : null,
                      title: _ActionMenuRow<T>(item: item, dense: true),
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
      ),
    );

    if (selected case _ActionMenuResult<T>(:final value)) {
      onSelected(value);
    }
  }
}

/// Row content shared by both the anchored menu and the BottomSheet.
class _ActionMenuRow<T> extends StatelessWidget {
  const _ActionMenuRow({required this.item, this.dense = false});

  final AppActionMenuItem<T> item;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final Color color = !item.enabled
        ? colorScheme.onSurface.withValues(alpha: 0.38)
        : item.destructive
            ? colorScheme.error
            : colorScheme.onSurface;

    return Row(
      children: [
        if (item.icon != null) ...[
          Icon(
            item.icon,
            size: dense ? 20 : 18,
            color: color,
          ),
          SizedBox(width: dense ? 12 : 10),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                item.label,
                overflow: TextOverflow.ellipsis,
                style: (dense
                        ? theme.textTheme.bodyLarge
                        : theme.textTheme.bodyMedium)
                    ?.copyWith(color: color),
              ),
              if (item.subtitle case final subtitle?)
                Text(
                  subtitle,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: item.enabled
                        ? colorScheme.onSurfaceVariant
                        : colorScheme.onSurface.withValues(alpha: 0.38),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Wraps a chosen value so a genuine `null` value is never mistaken for a
/// dismissed picker (`showMenu` / `showModalBottomSheet` return null on
/// dismissal).
final class _ActionMenuResult<T> {
  const _ActionMenuResult(this.value);

  final T value;
}
