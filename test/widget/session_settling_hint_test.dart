import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/core/theme/app_theme.dart';
import 'package:lt_dialogue/features/adventure/presentation/session/widgets/session_settling_hint.dart';

import '../helpers/responsive_test_helper.dart';

void main() {
  testWidgets('renders the hint without overflow at every required viewport',
      (tester) async {
    for (final viewport in requiredUiViewports) {
      setViewport(tester, width: viewport.width, height: viewport.height);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: SizedBox(width: 320, child: SessionSettlingHint()),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull, reason: '$viewport');
      expect(find.text(SessionSettlingHint.message), findsOneWidget,
          reason: '$viewport');
      expect(tester.takeException(), isNull, reason: '$viewport');
    }
  });

  testWidgets('survives a large text scale at the 320 px minimum',
      (tester) async {
    setViewport(tester, width: 320, height: 568);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(2.0)),
          child: Scaffold(
            body: SizedBox(width: 320, child: SessionSettlingHint()),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text(SessionSettlingHint.message), findsOneWidget);
  });

  testWidgets('never renders raw settlement JSON', (tester) async {
    setViewport(tester, width: 390, height: 844);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SessionSettlingHint())),
    );
    await tester.pump();

    expect(find.textContaining('options'), findsNothing);
    expect(find.textContaining('{'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
