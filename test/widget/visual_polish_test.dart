import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lt_dialogue/core/localization/app_date_formats.dart';
import 'package:lt_dialogue/core/responsive/app_breakpoints.dart';
import 'package:lt_dialogue/core/widgets/app_empty_state.dart';
import 'package:lt_dialogue/core/widgets/app_svg_icon.dart';
import 'package:lt_dialogue/core/widgets/workbench_chrome.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';
import 'package:lt_dialogue/core/theme/app_theme.dart';
import 'package:lt_dialogue/widgets/main_sidebar.dart';

import '../helpers/responsive_test_helper.dart';

void main() {
  group('AppBreakpoints.sidebarMode', () {
    test('keeps readable text navigation on desktop widths', () {
      // A ~950 px window must not collapse to an icon rail (the reported bug).
      expect(
        AppBreakpoints.sidebarMode(950, collapsed: false),
        WorkbenchSidebarMode.compact,
      );
      expect(
        AppBreakpoints.sidebarMode(1440, collapsed: false),
        WorkbenchSidebarMode.full,
      );
      expect(
        AppBreakpoints.sidebarMode(800, collapsed: false),
        WorkbenchSidebarMode.compact,
      );
    });

    test('uses the rail only when the user collapses or the layout is narrow',
        () {
      expect(
        AppBreakpoints.sidebarMode(1440, collapsed: true),
        WorkbenchSidebarMode.rail,
      );
      expect(
        AppBreakpoints.sidebarMode(420, collapsed: false),
        WorkbenchSidebarMode.rail,
      );
    });

    test('switches to the full sidebar only at the wide breakpoint', () {
      expect(AppBreakpoints.sidebarFullMin, greaterThanOrEqualTo(1000));
      expect(
        AppBreakpoints.sidebarMode(AppBreakpoints.sidebarFullMin - 1,
            collapsed: false),
        WorkbenchSidebarMode.compact,
      );
      expect(
        AppBreakpoints.sidebarMode(AppBreakpoints.sidebarFullMin,
            collapsed: false),
        WorkbenchSidebarMode.full,
      );
    });
  });

  group('AppDateFormats.compactTimestamp', () {
    setUpAll(() async {
      await initializeDateFormatting('zh');
      await initializeDateFormatting('en');
    });

    test('renders a compact locale-aware value, not the persisted string', () {
      final value = DateTime(2026, 9, 26, 12, 0);
      final reference = DateTime(2026, 10, 1);

      final en = AppDateFormats.compactTimestamp(value, 'en', now: reference);
      expect(en, contains('Sep 26'));
      expect(en, contains('12:00'));
      // Never the raw stored representation.
      expect(en, isNot(contains('T')));
      expect(en, isNot(contains('2026-09-26')));

      final zh = AppDateFormats.compactTimestamp(value, 'zh', now: reference);
      expect(zh, contains('26'));
      expect(zh, contains('12:00'));
    });

    test('adds the year only outside the current year', () {
      final reference = DateTime(2026, 10, 1);
      final sameYear = AppDateFormats.compactTimestamp(
          DateTime(2026, 1, 3, 9), 'en',
          now: reference);
      final otherYear = AppDateFormats.compactTimestamp(
          DateTime(2024, 1, 3, 9), 'en',
          now: reference);

      expect(sameYear, isNot(contains('2026')));
      expect(otherYear, contains('2024'));
    });

    test('parses persisted values and drops unusable ones', () {
      expect(AppDateFormats.tryParse('2026-09-21T18:27:27.765301'), isNotNull);
      expect(AppDateFormats.tryParse('2026-09-21 18:27'), isNotNull);
      expect(AppDateFormats.tryParse(''), isNull);
      expect(AppDateFormats.tryParse(null), isNull);
      expect(AppDateFormats.tryParse('not-a-date'), isNull);
      expect(AppDateFormats.formatPersisted('', 'en'), isNull);
    });
  });

  group('MainSidebar visual treatment', () {
    Future<void> pumpSidebar(WidgetTester tester, double width,
        {bool permanent = true}) async {
      setViewport(tester, width: width, height: 800);
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final scaffoldKey = GlobalKey<ScaffoldState>();
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: AppTheme.light(),
            home: Scaffold(
              key: scaffoldKey,
              body: Row(
                children: [
                  MainSidebar(scaffoldKey: scaffoldKey, permanent: permanent),
                  const Expanded(child: Center(child: Text('Content'))),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('shows text destinations at 950 px, not an icon rail',
        (tester) async {
      await pumpSidebar(tester, 950);

      // Readable navigation labels are present at a Medium-width desktop.
      expect(find.text('探索'), findsOneWidget);
      expect(find.text('新建冒险'), findsOneWidget);
      // No rail-only tooltip fallback.
      expect(find.byTooltip('探索'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows the full sidebar at 1280 px', (tester) async {
      await pumpSidebar(tester, 1280);

      expect(find.text('探索'), findsOneWidget);
      expect(find.text('LT 灵境'), findsOneWidget);
    });

    testWidgets('honours an explicit collapse to a rail', (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'main_sidebar_expanded': false,
      });
      setViewport(tester, width: 1440, height: 800);
      final scaffoldKey = GlobalKey<ScaffoldState>();
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: AppTheme.light(),
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

      // Collapsed: icon-only rail with tooltips for discoverability.
      expect(find.text('探索'), findsNothing);
      expect(find.byTooltip('探索'), findsOneWidget);
      expect(find.byKey(const Key('sidebar-toggle')), findsOneWidget);
    });
  });

  group('Workbench chrome', () {
    testWidgets('empty state is a small icon with no circle or card',
        (tester) async {
      setViewport(tester, width: 320, height: 568);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppEmptyState(
              icon: 'resources',
              title: 'No resources yet',
              description: 'Create a worldview, character, or NPC to start.',
              actionLabel: 'Create',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(AppEmptyState)).width,
          lessThanOrEqualTo(320));

      // A small glyph, not a 56 px illustration inside a circular backdrop.
      final glyph = tester.widget<AppSvgIcon>(find.byType(AppSvgIcon));
      expect(glyph.size, lessThanOrEqualTo(32));
    });

    testWidgets('page header stays compact and overflow-free at 320 px',
        (tester) async {
      setViewport(tester, width: 320, height: 568);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                WorkbenchPageHeader(
                  title: 'A very long page title that must truncate cleanly',
                  actions: const [Icon(Icons.more_horiz)],
                  bottom: WorkbenchToolbar(
                    child: WorkbenchTabBar(
                      children: [
                        for (final label in [
                          'All',
                          'World',
                          'Characters',
                          'NPC'
                        ])
                          WorkbenchTabButton(
                            label: label,
                            selected: label == 'All',
                            onTap: () {},
                          ),
                      ],
                    ),
                  ),
                ),
                const Expanded(child: SizedBox.shrink()),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('tab button exposes selection semantics', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                WorkbenchTabButton(label: 'All', selected: true, onTap: () {}),
                WorkbenchTabButton(
                    label: 'World', selected: false, onTap: () {}),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<WorkbenchTabButton>(find.byType(WorkbenchTabButton).first)
            .selected,
        isTrue,
      );

      final handle = tester.ensureSemantics();
      expect(
        tester.getSemantics(find.text('All')),
        isSemantics(isSelected: true),
      );
      handle.dispose();
    });
  });
}
