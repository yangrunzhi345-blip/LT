import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lt_dialogue/core/theme/app_theme.dart';
import 'package:lt_dialogue/features/adventure/presentation/home/screens/adventure_dashboard_screen.dart';
import 'package:lt_dialogue/features/adventure/presentation/home/widgets/dashboard_section.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';
import 'package:lt_dialogue/services/database_service.dart';

import '../helpers/responsive_test_helper.dart';

/// The dashboard is an information hierarchy, not a flat list of identical
/// sections. These tests pin the four regions, the single-primary-action rule
/// and the macro-vs-micro spacing scale so the page cannot silently flatten
/// back into "title / divider / content / AppSpacing.lg".
void main() {
  const Key startGroup = Key('dashboard-group-start');
  const Key libraryGroup = Key('dashboard-group-library');
  const Key runtimeGroup = Key('dashboard-group-runtime');
  const Key worldsSub = Key('dashboard-subsection-worlds');
  const Key charactersSub = Key('dashboard-subsection-characters');
  const Key continueGroup = Key('dashboard-group-continue');
  const Key wizardKey = Key('dashboard-new-adventure');

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('lt_dashboard_hierarchy_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    DatabaseService.customDbDir = null;
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  Future<ProviderContainer> mountDashboard(
    WidgetTester tester, {
    required Size size,
    bool withSave = false,
    ThemeMode themeMode = ThemeMode.light,
    double textScale = 1.0,
  }) async {
    setViewport(tester, width: size.width, height: size.height);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    if (withSave) {
      container.read(chatProvider).adventureProvider.adventureList.add({
        'id': 101,
        'title': '暮色边境 · 永夜高塔',
        'updated_at': '2026-09-26 15:30',
      });
    }
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: themeMode,
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(textScale)),
              child: AdventureDashboardScreen(
                  onStartAdventure: (_, {difficulty}) async {}),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    return container;
  }

  // A tall viewport keeps the whole list laid out so titles are all mounted
  // and their geometry can be compared without scrolling disposing them.
  const Size tallViewport = Size(1000, 1600);

  group('Empty dashboard information architecture', () {
    testWidgets('shows the four regions exactly once', (tester) async {
      await mountDashboard(tester, size: tallViewport);

      expect(find.text('冒险'), findsOneWidget);
      expect(find.byKey(startGroup), findsOneWidget);
      expect(find.byKey(libraryGroup), findsOneWidget);
      expect(find.byKey(worldsSub), findsOneWidget);
      expect(find.byKey(charactersSub), findsOneWidget);
      expect(find.byKey(runtimeGroup), findsOneWidget);

      expect(find.text('开始你的第一个冒险'), findsOneWidget);
      expect(find.text('你的资料'), findsOneWidget);
      expect(find.text('我的世界设定'), findsOneWidget);
      expect(find.text('我的角色卡档案'), findsOneWidget);
      expect(find.text('当前状态'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('has exactly one start onboarding and one primary CTA',
        (tester) async {
      await mountDashboard(tester, size: tallViewport);

      // No duplicate empty start section.
      expect(find.text('尚未开始任何场景冒险'), findsNothing);
      expect(find.byKey(wizardKey), findsOneWidget);
      expect(find.text('启动向导'), findsOneWidget);
      expect(find.text('预存场景工坊'), findsOneWidget);
      expect(find.text('资料库'), findsOneWidget);

      // Exactly one dominant filled action on the page.
      expect(find.byType(FilledButton), findsOneWidget);
      expect(
        find.descendant(
            of: find.byKey(startGroup), matching: find.byType(FilledButton)),
        findsOneWidget,
      );
    });

    testWidgets('orders start before library before runtime', (tester) async {
      await mountDashboard(tester, size: tallViewport);

      final startTop = tester.getTopLeft(find.byKey(startGroup)).dy;
      final libraryTop = tester.getTopLeft(find.byKey(libraryGroup)).dy;
      final runtimeTop = tester.getTopLeft(find.byKey(runtimeGroup)).dy;

      expect(startTop, lessThan(libraryTop));
      expect(libraryTop, lessThan(runtimeTop));
      expect(tester.takeException(), isNull);
    });
  });

  group('Existing story leads the page', () {
    testWidgets('continue precedes start and owns the primary action',
        (tester) async {
      await mountDashboard(tester, size: tallViewport, withSave: true);

      expect(find.byKey(continueGroup), findsOneWidget);
      expect(find.text('继续未尽的冒险'), findsOneWidget);
      // Start becomes a quiet "new adventure" group, not a second CTA.
      expect(find.text('开始新的冒险'), findsOneWidget);
      expect(find.text('尚未开始任何场景冒险'), findsNothing);

      final continueTop = tester.getTopLeft(find.byKey(continueGroup)).dy;
      final startTop = tester.getTopLeft(find.byKey(startGroup)).dy;
      expect(continueTop, lessThan(startTop));

      // Exactly one filled action, and it is the continue button.
      expect(find.byType(FilledButton), findsOneWidget);
      expect(
        find.descendant(
            of: find.byKey(continueGroup), matching: find.byType(FilledButton)),
        findsOneWidget,
      );
      expect(
        find.descendant(
            of: find.byKey(startGroup), matching: find.byType(FilledButton)),
        findsNothing,
      );
      // The wizard entry still exists, just quiet.
      expect(find.byKey(wizardKey), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Macro spacing exceeds micro spacing', () {
    testWidgets('group gap is larger than subsection gap', (tester) async {
      await mountDashboard(tester, size: tallViewport);

      final libraryTop = tester.getTopLeft(find.byKey(libraryGroup)).dy;
      final runtimeTop = tester.getTopLeft(find.byKey(runtimeGroup)).dy;
      final worldsTop = tester.getTopLeft(find.byKey(worldsSub)).dy;
      final charactersTop = tester.getTopLeft(find.byKey(charactersSub)).dy;

      final majorGap = runtimeTop - libraryTop;
      final minorGap = charactersTop - worldsTop;

      expect(majorGap, greaterThan(minorGap),
          reason: 'major groups must be separated more than subsections');
      expect(majorGap, greaterThan(DashboardMetrics.groupGap));
      expect(tester.takeException(), isNull);
    });
  });

  group('Responsive and theming remain sound', () {
    for (final size in const <Size>[
      Size(320, 568),
      Size(375, 812),
      Size(600, 900),
      Size(960, 900),
      Size(1280, 900),
      Size(1440, 900),
    ]) {
      testWidgets('no overflow at ${size.width}px', (tester) async {
        await mountDashboard(tester, size: size);
        expect(find.byKey(startGroup), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    for (final scale in const <double>[1.0, 1.5, 2.0]) {
      testWidgets('empty onboarding holds up at ${scale}x text scale',
          (tester) async {
        await mountDashboard(tester,
            size: const Size(320, 568), textScale: scale);
        expect(find.byKey(wizardKey), findsOneWidget);
        expect(find.text('你的资料'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    for (final scale in const <double>[1.0, 1.5, 2.0]) {
      testWidgets('story dashboard holds up at ${scale}x text scale',
          (tester) async {
        await mountDashboard(tester,
            size: const Size(390, 844), withSave: true, textScale: scale);
        expect(find.byKey(continueGroup), findsOneWidget);
        expect(find.byType(FilledButton), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('dark theme keeps the hierarchy intact', (tester) async {
      await mountDashboard(tester,
          size: tallViewport, themeMode: ThemeMode.dark, withSave: true);
      expect(find.byKey(continueGroup), findsOneWidget);
      expect(find.byKey(libraryGroup), findsOneWidget);
      expect(find.byKey(runtimeGroup), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
