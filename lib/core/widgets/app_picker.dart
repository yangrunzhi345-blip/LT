import 'package:flutter/material.dart';

import '../responsive/app_breakpoints.dart';

/// Responsive placement policy shared by every control-level popup picker.
///
/// `AppSelect` and `AppActionMenu` both offer the same three-way placement
/// choice, so the enum lives here instead of inside either control. Sharing it
/// (and [appPickerUsesBottomSheet]) is what stops the two pickers from drifting
/// apart as their bodies evolve separately.
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

/// Overlay-relative anchor geometry for a popup menu opened from [context].
@immutable
class AppPickerAnchor {
  const AppPickerAnchor({
    required this.position,
    required this.triggerSize,
    required this.overlaySize,
  });

  final RelativeRect position;
  final Size triggerSize;
  final Size overlaySize;
}

/// Computes where a popup menu anchored to the trigger owned by [context]
/// should open.
///
/// Both pickers must anchor with overlay coordinates instead of raw global
/// offsets; otherwise the menu drifts when the trigger sits inside a scrolled
/// or transformed ancestor. Returns null when the trigger or the overlay has no
/// size yet, so callers fall back to the BottomSheet rather than opening an
/// unanchored menu.
AppPickerAnchor? appPickerAnchor(
  BuildContext context, {
  double gap = 4,
}) {
  final renderBox = context.findRenderObject() as RenderBox?;
  final overlayBox =
      Navigator.of(context).overlay?.context.findRenderObject() as RenderBox?;
  if (renderBox == null ||
      !renderBox.hasSize ||
      overlayBox == null ||
      !overlayBox.hasSize) {
    return null;
  }
  final translation =
      renderBox.localToGlobal(Offset.zero, ancestor: overlayBox);
  final size = renderBox.size;
  return AppPickerAnchor(
    position: RelativeRect.fromRect(
      Rect.fromLTWH(
        translation.dx,
        translation.dy + size.height + gap,
        size.width,
        0,
      ),
      Offset.zero & overlayBox.size,
    ),
    triggerSize: size,
    overlaySize: overlayBox.size,
  );
}
