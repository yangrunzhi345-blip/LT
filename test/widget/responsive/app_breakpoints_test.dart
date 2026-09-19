import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/core/responsive/app_breakpoints.dart';
import 'package:lt_dialogue/core/responsive/adaptive_container.dart';
import '../../helpers/responsive_test_helper.dart';

void main() {
  group('AppBreakpoints Unit & Resolution Tests', () {
    test('resolves widths to correct breakpoint category', () {
      // 320 hard min -> compact
      expect(AppBreakpoints.fromWidth(320), ResponsiveBreakpoint.compact);
      expect(AppBreakpoints.fromWidth(599), ResponsiveBreakpoint.compact);

      // 600-899 -> medium
      expect(AppBreakpoints.fromWidth(600), ResponsiveBreakpoint.medium);
      expect(AppBreakpoints.fromWidth(768), ResponsiveBreakpoint.medium);
      expect(AppBreakpoints.fromWidth(899), ResponsiveBreakpoint.medium);

      // >= 900 -> expanded
      expect(AppBreakpoints.fromWidth(900), ResponsiveBreakpoint.expanded);
      expect(AppBreakpoints.fromWidth(1440), ResponsiveBreakpoint.expanded);
    });

    test('resolves constraints to correct breakpoint', () {
      expect(
        AppBreakpoints.fromConstraints(
            const BoxConstraints(maxWidth: 320, maxHeight: 600)),
        ResponsiveBreakpoint.compact,
      );
      expect(
        AppBreakpoints.fromConstraints(
            const BoxConstraints(maxWidth: 720, maxHeight: 600)),
        ResponsiveBreakpoint.medium,
      );
      expect(
        AppBreakpoints.fromConstraints(
            const BoxConstraints(maxWidth: 1024, maxHeight: 768)),
        ResponsiveBreakpoint.expanded,
      );
    });

    testWidgets('AppBreakpoints.of resolves correctly in widget tree',
        (tester) async {
      setViewport(tester, width: 320, height: 568);

      ResponsiveBreakpoint? resolved;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              resolved = AppBreakpoints.of(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(resolved, ResponsiveBreakpoint.compact);

      setViewport(tester, width: 1024, height: 768);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              resolved = AppBreakpoints.of(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(resolved, ResponsiveBreakpoint.expanded);
    });
  });

  group('AdaptiveContainer & ResponsivePadding Tests', () {
    testWidgets('AdaptiveContainer enforces reading maxWidth at 760',
        (tester) async {
      setViewport(tester, width: 1440, height: 900);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdaptiveContainer.reading(
              child: SizedBox(height: 100, child: Text('Reading')),
            ),
          ),
        ),
      );

      final box = tester.widget<ConstrainedBox>(find.descendant(
        of: find.byType(AdaptiveContainer),
        matching: find.byType(ConstrainedBox),
      ));
      expect(box.constraints.maxWidth, AppBreakpoints.narrativeMaxWidth);
      expect(box.constraints.maxWidth, 760.0);
    });

    testWidgets('AdaptiveContainer enforces form maxWidth at 640',
        (tester) async {
      setViewport(tester, width: 1440, height: 900);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdaptiveContainer.form(
              child: SizedBox(height: 100, child: Text('Form')),
            ),
          ),
        ),
      );

      final box = tester.widget<ConstrainedBox>(find.descendant(
        of: find.byType(AdaptiveContainer),
        matching: find.byType(ConstrainedBox),
      ));
      expect(box.constraints.maxWidth, AppBreakpoints.formMaxWidth);
      expect(box.constraints.maxWidth, 640.0);
    });

    testWidgets('AdaptiveContainer renders cleanly on 320px with zero overflow',
        (tester) async {
      setViewport(tester, width: 320, height: 568);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdaptiveContainer(
              child: Text(
                  'Long editorial story content that should wrap smoothly without any layout overflow errors in compact screens'),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });
  });
}
