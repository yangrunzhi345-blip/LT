import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Key of the Studio's main scroll view (`CustomScrollView` in `_buildMain`).
const Key resourceStudioMainScrollKey =
    ValueKey<String>('resource_studio_main');

/// Brings [finder] into view inside the Studio's main scroll view.
///
/// The Studio body renders its resource content through a lazy `SliverList`,
/// so widgets below the viewport's cache extent are never built and
/// [WidgetTester.ensureVisible] throws `Bad state: No element` on them.
/// [WidgetTester.scrollUntilVisible] drags until the widget is built, and the
/// trailing pump applies the resulting scroll offset to the render tree: without
/// it a following `tap` would still use the pre-scroll offset and miss.
Future<void> revealInStudio(WidgetTester tester, Finder finder) async {
  final scrollable = find
      .descendant(
        of: find.byKey(resourceStudioMainScrollKey),
        matching: find.byType(Scrollable),
      )
      .first;
  await tester.scrollUntilVisible(finder, 240, scrollable: scrollable);
  await tester.pump(const Duration(milliseconds: 50));
}
