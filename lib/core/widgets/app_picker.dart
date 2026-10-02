import 'package:flutter/material.dart';

import '../responsive/app_breakpoints.dart';

/// Responsive placement policy shared by every control-level popup picker.
///
/// `AppSelect`, `AppActionMenu` and `AppMultiSelectDropdown` all offer the same
/// three-way placement choice, so the enum lives here instead of inside any one
/// control. Sharing it (and [appPickerUsesBottomSheet]) is what stops the
/// pickers from drifting apart as their bodies evolve.
enum AppSelectPickerStyle {
  /// Auto: mobile / compact (< 600) uses a BottomSheet, wider uses a menu.
  auto,

  /// Always use a BottomSheet.
  bottomSheet,

  /// Always use an anchored popup menu.
  menu,
}

/// Whether [style] resolves to a compact BottomSheet for [context].
bool appPickerUsesBottomSheet(
  BuildContext context,
  AppSelectPickerStyle style,
) {
  return switch (style) {
    AppSelectPickerStyle.bottomSheet => true,
    AppSelectPickerStyle.menu => false,
    AppSelectPickerStyle.auto => AppBreakpoints.isCompact(context),
  };
}
