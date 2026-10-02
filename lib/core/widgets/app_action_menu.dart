import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import 'app_menu.dart';
import 'app_picker.dart';
import 'app_svg_icon.dart';

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
  final String? icon;
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
/// Follows the shared [AppMenuAnchor] kernel: compact viewports (< 600) open a
/// touch-friendly BottomSheet, wider viewports open an anchored menu next to
/// the trigger. Feature code must not build its own raw popup menu.
class AppActionMenu<T> extends StatelessWidget {
  const AppActionMenu({
    super.key,
    required this.items,
    required this.onSelected,
    this.icon = 'more',
    this.iconSize = 20,
    this.iconColor,
    this.tooltip,
    this.semanticLabel,
    this.enabled = true,
    this.pickerStyle = AppSelectPickerStyle.auto,
    this.sheetTitle,
    this.menuMaxHeight = AppMenuMetrics.maxHeight,
    this.padding = EdgeInsets.zero,
  });

  final List<AppActionMenuItem<T>> items;
  final ValueChanged<T> onSelected;
  final String icon;
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
    final l10n = AppLocalizations.of(context);

    return AppMenuAnchor<T>(
      items: [
        for (final item in items)
          AppMenuItem<T>(
            value: item.value,
            label: item.label,
            subtitle: item.subtitle,
            icon: item.icon,
            enabled: item.enabled,
            destructive: item.destructive,
            dividerBefore: item.dividerBefore,
          ),
      ],
      pickerStyle: pickerStyle,
      menuMaxHeight: menuMaxHeight,
      sheetTitle: sheetTitle,
      onActivated: onSelected,
      triggerBuilder: (context, open) => Semantics(
        button: true,
        enabled: isInteractive,
        label: semanticLabel ??
            tooltip ??
            (l10n?.actionMenuSemanticLabel ?? 'Action menu'),
        child: IconButton(
          icon: AppSvgIcon(icon, size: iconSize, color: iconColor),
          tooltip: tooltip,
          padding: padding,
          visualDensity: VisualDensity.compact,
          onPressed: isInteractive ? open : null,
        ),
      ),
    );
  }
}
