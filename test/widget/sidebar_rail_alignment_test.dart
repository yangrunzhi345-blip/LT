import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lt_dialogue/core/theme/app_theme.dart';
import 'package:lt_dialogue/core/widgets/app_svg_icon.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations_en.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations_zh.dart';
import 'package:lt_dialogue/models/app_section.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';
import 'package:lt_dialogue/widgets/main_sidebar.dart';

import '../helpers/responsive_test_helper.dart';

/// The collapsed rail has one horizontal authority: `railWidth / 2`. Every
/// control — the brand toggle, the main navigation icons and the bottom
/// actions — must share that centerline within half a logical pixel. This is a
/// geometry contract, not a visual approximation.
///
/// The rail is also strictly icon-only: a text section heading such as
/// "当前冒险" would wrap one glyph per line inside 56 px and distort the whole
/// column, so section headings must collapse to a quiet divider (or vanish).
void main() {
  const double tolerance = 0.5;
  const double railWidth = 56;
  const double railCenter = railWidth / 2;

  final l10n = AppLocalizationsZh();
  final l10nEn = AppLocalizationsEn();

  /// Controls that are always present in the rail.
  const List<Key> railBaseControlKeys = <Key>[
    Key('sidebar-toggle'),
    Key('sidebar-nav-adventure'),
    Key('sidebar-nav-resources'),
    Key('sidebar-nav-trash'),
    Key('sidebar-nav-runtime'),
    Key('sidebar-nav-new-adventure'),
    Key('sidebar-nav-settings'),
  ];

  /// Base controls plus the links that only exist while an adventure is open.
  const List<Key> railActiveAdventureKeys = <Key>[
    ...railBaseControlKeys,
    Key('sidebar-nav-story'),
    Key('sidebar-nav-characters'),
  ];

  Future<ProviderContainer> pumpSidebar(
    WidgetTester tester, {
    required double width,
    bool expanded = true,
    bool dark = false,
    double textScale = 1.0,
    bool activeAdventure = false,
    Locale locale = const Locale('zh'),
  }) async {
    setViewport(tester, width: width, height: 800);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final scaffoldKey = GlobalKey<ScaffoldState>();
    final container = ProviderContainer();
    addTearDown(container.dispose);
    // Default expanded state is true; collapse explicitly so the preference
    // load (which sees no stored value) never overrides the intent.
    if (!expanded) container.read(chatProvider).toggleMainSidebarExpanded();
    // Inject an active adventure without touching SQLite: the sidebar only
    // reads the id to render the current-adventure group.
    if (activeAdventure) {
      container.read(chatProvider).adventureProvider.currentAdventureId = 1;
    }

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: locale,
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

  void expectRailAligned(
    WidgetTester tester, {
    String? reason,
    List<Key> keys = railBaseControlKeys,
  }) {
    final sidebarRect = tester.getRect(find.byType(MainSidebar));
    expect(sidebarRect.width, railWidth,
        reason: 'rail must be $railWidth px wide');
    final expectedCenter = sidebarRect.left + sidebarRect.width / 2;

    for (final key in keys) {
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

  double dividerCenterX(WidgetTester tester) => tester
      .getRect(find.byKey(const Key('sidebar-current-adventure-divider')))
      .center
      .dx;

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

  group('Active adventure rail stays icon-only', () {
    for (final width in const <double>[600, 768, 960, 1100, 1280, 1440]) {
      testWidgets(
          'collapsed rail hides the current adventure heading at ${width}px',
          (tester) async {
        await pumpSidebar(tester,
            width: width, expanded: false, activeAdventure: true);

        expect(tester.getSize(find.byType(MainSidebar)).width, railWidth);
        // No text heading may survive in the rail — not workspace, not the
        // current adventure.
        expect(find.text(l10n.workbenchWorkspace), findsNothing);
        expect(find.text(l10n.workbenchCurrentAdventure), findsNothing);
        // The current-adventure group is still reachable via icon + divider.
        expect(find.byKey(const Key('sidebar-current-adventure-divider')),
            findsOneWidget);
        expect(find.byKey(const Key('sidebar-nav-story')), findsOneWidget);
        expect(find.byKey(const Key('sidebar-nav-characters')), findsOneWidget);
        expectRailAligned(tester,
            reason: 'active adventure at ${width}px',
            keys: railActiveAdventureKeys);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('rail section divider is centred on the rail axis',
        (tester) async {
      await pumpSidebar(tester,
          width: 1280, expanded: false, activeAdventure: true);
      final sidebarRect = tester.getRect(find.byType(MainSidebar));
      expect(
        (dividerCenterX(tester) - sidebarRect.center.dx).abs(),
        lessThanOrEqualTo(tolerance),
      );
      // A restrained 24 px rule, not a full-width bar across the rail.
      expect(
        tester
            .getRect(find.byKey(const Key('sidebar-current-adventure-divider')))
            .width,
        lessThan(sidebarRect.width),
      );
    });

    testWidgets('no divider or story links when no adventure is active',
        (tester) async {
      await pumpSidebar(tester, width: 1280, expanded: false);

      expect(find.byKey(const Key('sidebar-current-adventure-divider')),
          findsNothing);
      expect(find.byKey(const Key('sidebar-nav-story')), findsNothing);
      expect(find.byKey(const Key('sidebar-nav-characters')), findsNothing);
      expect(find.text(l10n.workbenchCurrentAdventure), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('expanded keeps headings and drops the rail divider',
        (tester) async {
      await pumpSidebar(tester,
          width: 1280, expanded: true, activeAdventure: true);

      expect(tester.getSize(find.byType(MainSidebar)).width, 232);
      expect(find.text(l10n.workbenchWorkspace), findsOneWidget);
      expect(find.text(l10n.workbenchCurrentAdventure), findsOneWidget);
      expect(find.byKey(const Key('sidebar-current-adventure-divider')),
          findsNothing);
      expect(find.byKey(const Key('sidebar-nav-story')), findsOneWidget);
      expect(find.byKey(const Key('sidebar-nav-characters')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('compact expanded still shows the current adventure heading',
        (tester) async {
      await pumpSidebar(tester,
          width: 960, expanded: true, activeAdventure: true);

      expect(tester.getSize(find.byType(MainSidebar)).width, 208);
      expect(find.text(l10n.workbenchWorkspace), findsOneWidget);
      expect(find.text(l10n.workbenchCurrentAdventure), findsOneWidget);
      expect(find.byKey(const Key('sidebar-current-adventure-divider')),
          findsNothing);
      expect(tester.takeException(), isNull);
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

    testWidgets('active adventure rail is overflow-free at 2.0x',
        (tester) async {
      await pumpSidebar(tester,
          width: 1280, expanded: false, activeAdventure: true, textScale: 2.0);
      expect(find.text(l10n.workbenchCurrentAdventure), findsNothing);
      expect(find.byKey(const Key('sidebar-current-adventure-divider')),
          findsOneWidget);
      expectRailAligned(tester,
          reason: 'active adventure at 2.0x', keys: railActiveAdventureKeys);
      expect(tester.takeException(), isNull);
    });

    testWidgets('light and dark keep the active-adventure divider centred',
        (tester) async {
      for (final dark in <bool>[false, true]) {
        await pumpSidebar(tester,
            width: 1280, expanded: false, dark: dark, activeAdventure: true);
        expect(
          (dividerCenterX(tester) -
                  tester.getRect(find.byType(MainSidebar)).center.dx)
              .abs(),
          lessThanOrEqualTo(tolerance),
          reason: dark ? 'dark divider' : 'light divider',
        );
        expectRailAligned(tester,
            reason: dark ? 'dark active' : 'light active',
            keys: railActiveAdventureKeys);
      }
    });
  });

  group('Rail locale regression', () {
    testWidgets('english rail never wraps the section heading', (tester) async {
      await pumpSidebar(tester,
          width: 1280,
          expanded: false,
          activeAdventure: true,
          locale: const Locale('en'));

      expect(find.text(l10nEn.workbenchWorkspace), findsNothing);
      expect(find.text(l10nEn.workbenchCurrentAdventure), findsNothing);
      expect(find.byKey(const Key('sidebar-current-adventure-divider')),
          findsOneWidget);
      expect(find.byKey(const Key('sidebar-nav-story')), findsOneWidget);
      expect(find.byKey(const Key('sidebar-nav-characters')), findsOneWidget);
      expectRailAligned(tester,
          reason: 'english active adventure', keys: railActiveAdventureKeys);
      expect(tester.takeException(), isNull);
    });

    testWidgets('english expanded restores the headings', (tester) async {
      await pumpSidebar(tester,
          width: 1440,
          expanded: true,
          activeAdventure: true,
          locale: const Locale('en'));

      expect(find.text(l10nEn.workbenchWorkspace), findsOneWidget);
      expect(find.text(l10nEn.workbenchCurrentAdventure), findsOneWidget);
      expect(find.byKey(const Key('sidebar-current-adventure-divider')),
          findsNothing);
      expect(tester.takeException(), isNull);
    });
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
