import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Logical viewports every UI change must be checked against (AGENTS.md).
///
/// 320 px is the hard minimum; the rest cover common phones, a compact tablet
/// and a desktop window.
const List<Size> requiredUiViewports = <Size>[
  Size(320, 568),
  Size(360, 640),
  Size(390, 844),
  Size(412, 915),
  Size(768, 1024),
  Size(1280, 800),
];

/// Applies a logical viewport to [tester] and restores it automatically.
///
/// `devicePixelRatio` is pinned to 1 so logical and physical pixels match and
/// a failing assertion points at the real logical constraint.
void setViewport(
  WidgetTester tester, {
  required double width,
  required double height,
}) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}
