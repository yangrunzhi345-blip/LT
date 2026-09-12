import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/core/theme/app_theme.dart';
import '../support/viewport_test_helper.dart';

void main() {
  group('AppTheme Editorial Tokens Test', () {
    testWidgets('AppTheme light and dark have clean flat card themes',
        (tester) async {
      final light = AppTheme.light();
      final dark = AppTheme.dark();

      expect(light.cardTheme.elevation, 0);
      expect(dark.cardTheme.elevation, 0);
      expect(light.cardTheme.shadowColor, Colors.transparent);
      expect(dark.cardTheme.shadowColor, Colors.transparent);

      final lightCardShape = light.cardTheme.shape as RoundedRectangleBorder;
      final darkCardShape = dark.cardTheme.shape as RoundedRectangleBorder;

      // Ensure no excessive 20px+ radius
      expect(lightCardShape.borderRadius, BorderRadius.circular(14.0));
      expect(darkCardShape.borderRadius, BorderRadius.circular(14.0));
    });

    testWidgets('AppTheme Chip theme uses compact radius rather than 20px',
        (tester) async {
      final light = AppTheme.light();
      final dark = AppTheme.dark();

      final lightChipShape = light.chipTheme.shape as RoundedRectangleBorder;
      final darkChipShape = dark.chipTheme.shape as RoundedRectangleBorder;

      expect(lightChipShape.borderRadius, BorderRadius.circular(6.0));
      expect(darkChipShape.borderRadius, BorderRadius.circular(6.0));
    });

    testWidgets('AppTheme Dialog and BottomSheet use 14px radius',
        (tester) async {
      final light = AppTheme.light();
      final dialogShape = light.dialogTheme.shape as RoundedRectangleBorder;
      expect(dialogShape.borderRadius, BorderRadius.circular(14.0));

      final sheetShape = light.bottomSheetTheme.shape as RoundedRectangleBorder;
      expect(sheetShape.borderRadius,
          const BorderRadius.vertical(top: Radius.circular(14.0)));
    });

    testWidgets('Card and Chip render cleanly on 320px without overflow',
        (tester) async {
      setTestViewport(tester, size: TestViewports.mobile320);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: Center(
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Chip(label: Text('Tag')),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Editorial card title that wraps properly on small screens',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });
  });
}
