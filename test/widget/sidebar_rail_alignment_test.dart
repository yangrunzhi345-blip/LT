import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lt_dialogue/core/theme/app_theme.dart';
import 'package:lt_dialogue/core/widgets/app_svg_icon.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';
import 'package:lt_dialogue/models/app_section.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';
import 'package:lt_dialogue/widgets/main_sidebar.dart';

import '../helpers/responsive_test_helper.dart';

/// The collapsed rail has one horizontal authority: `railWidth / 2`. Every
/// control — the brand toggle, the main navigation icons and the bottom
/// actions — must share that centerline within half a logical pixel. This is a
/// geometry contract, not a visual approximation.
void main() {
  const double tolerance = 0.5;
  const double railWidth = 56;
  const double railCenter = railWidth / 2;

  const List<Key> railControlKeys = <Key>[
    Key('sidebar-toggle'),
    Key('sidebar-nav-adventure'),
    Key('sidebar-nav-resources'),
    Key('sidebar-nav-trash'),
    Key('sidebar-nav-runtime'),
    Key('sidebar-nav-new-adventure'),
    Key('sidebar-nav-settings'),
  ];

  Future<ProviderContainer> pumpSidebar(
    WidgetTester tester, {
    required double width,
    bool expanded = true,
    bool dark = false,
    double textScale = 1.0,
  }) async {
    setViewport(tester, width: width, height: 800);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final scaffoldKey = GlobalKey<ScaffoldState>();
    final container = ProviderContainer();
    addTearDown(container.dispose);
    // Default expanded state is true; collapse explicitly so the preference
    // load (which sees no stored value) never overrides the intent.
    if (!expanded) container.read(chatProvider).toggleMainSidebarExpanded();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: dark ? AppTheme.dark() : AppTheme.light(),
          builder: textScale == 1.0
              ? null
              : (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(textScale)),
                    child: child!,
                  ),
          home: Scaffold(
            key: scaffoldKey,
            body: Row(
              children: [
                MainSidebar(scaffoldKey: scaffoldKey, permanent: true),
                const Expanded(child: Center(child: Text('Content'))),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    return container;
  }

  double controlCenterX(WidgetTester tester, Key key) =>
      tester.getCenter(find.byKey(key)).dx;

  double iconCenterX(WidgetTester tester, Key key) => tester
      .getCenter(find.descendant(
        of: find.byKey(key),
        matching: find.byType(AppSvgIcon),
      ))
      .dx;

  void expectRailAligned(WidgetTester tester, {String? reason}) {
    final sidebarRect = tester.getRect(find.byType(MainSidebar));
    expect(sidebarRect.width, railWidth,
        reason: 'rail must be $railWidth px wide');
    final expectedCenter = sidebarRect.left + sidebarRect.width / 2;

    for (final key in railControlKeys) {
      expect(
        (controlCenterX(tester, key) - expectedCenter).abs(),
        lessThanOrEqualTo(tolerance),
        reason: '$key item center must sit on the rail centerline '
            '${reason ?? ''}',
      );
      expect(
        (iconCenterX(tester, key) - expectedCenter).abs(),
        lessThanOrEqualTo(tolerance),
        reason: '$key icon center must sit on the rail centerline '
            '${reason ?? ''}',
      );
    }
    expect(expectedCenter, railCenter);
  }

  group('Rail alignment at desktop viewports', () {
    for (final width in const <double>[600, 768, 960, 1100, 1280, 1440]) {
      testWidgets('all rail controls share one centerline at ${width}px',
          (tester) async {
        await pumpSidebar(tester, width: width, expanded: false);
        expect(find.byKey(const Key('sidebar-toggle')), findsOneWidget);
        expectRailAligned(tester, reason: 'at ${width}px');
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Selection does not move the rail axis', () {
    testWidgets('selected and unselected items keep the same icon center',
        (tester) async {
      final container = await pumpSidebar(tester, width: 1280, expanded: false);
      final chat = container.read(chatProvider);

      // Library selected.
      chat.openResourceLibrary(
          container.read(chatProvider).resourceLibraryMode);
      chat.setCurrentSection(AppSection.resources);
      await tester.pump();
      final selectedLibrary =
          iconCenterX(tester, const Key('sidebar-nav-resources'));
      final unselectedAdventure =
          iconCenterX(tester, const Key('sidebar-nav-adventure'));
      expect((selectedLibrary - unselectedAdventure).abs(),
          lessThanOrEqualTo(tolerance));
      expectRailAligned(tester, reason: 'with resources selected');

      // Adventure selected.
      chat.navigateToAdventureHome();
      await tester.pump();
      final selectedAdventure =
          iconCenterX(tester, const Key('sidebar-nav-adventure'));
      final unselectedLibrary =
          iconCenterX(tester, const Key('sidebar-nav-resources'));
      expect((selectedAdventure - unselectedLibrary).abs(),
          lessThanOrEqualTo(tolerance));
      expectRailAligned(tester, reason: 'with adventure selected');
    });
  });

  group('Themes and text scale keep the rail aligned', () {
    testWidgets('light and dark share the rail centerline', (tester) async {
      for (final dark in <bool>[false, true]) {
        await pumpSidebar(tester, width: 1280, expanded: false, dark: dark);
        expectRailAligned(tester, reason: dark ? 'dark' : 'light');
      }
    });

    for (final scale in const <double>[1.0, 1.5, 2.0]) {
      testWidgets('rail stays aligned and overflow-free at ${scale}x',
          (tester) async {
        await pumpSidebar(
          tester,
          width: 1280,
          expanded: false,
          textScale: scale,
        );
        expectRailAligned(tester, reason: 'at ${scale}x');
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Expanded sidebar geometry is preserved', () {
    testWidgets('full width 232 with right-aligned toggle and labels',
        (tester) async {
      await pumpSidebar(tester, width: 1280, expanded: true);

      expect(tester.getSize(find.byType(MainSidebar)).width, 232);
      expect(find.text('LT 灵境'), findsOneWidget);
      expect(find.text('探索'), findsOneWidget);

      final sidebarRect = tester.getRect(find.byType(MainSidebar));
      final toggleCenter =
          tester.getCenter(find.byKey(const Key('sidebar-toggle'))).dx;
      // Expanded keeps the toggle on the right, not on the rail centerline.
      expect(
          toggleCenter, greaterThan(sidebarRect.left + sidebarRect.width / 2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('compact width 208 with labels and no overflow',
        (tester) async {
      await pumpSidebar(tester, width: 960, expanded: true);

      expect(tester.getSize(find.byType(MainSidebar)).width, 208);
      expect(find.text('LT 灵境'), findsOneWidget);
      expect(find.text('探索'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('expanded survives 2.0x text scale without overflow',
        (tester) async {
      await pumpSidebar(tester, width: 1280, expanded: true, textScale: 2.0);
      expect(find.text('LT 灵境'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
