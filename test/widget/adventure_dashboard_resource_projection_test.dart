import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lt_dialogue/controllers/resource_crud_controller.dart';
import 'package:lt_dialogue/core/theme/app_theme.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/features/adventure/presentation/home/screens/adventure_dashboard_screen.dart';
import 'package:lt_dialogue/features/adventure/presentation/wizard/screens/assembly_create_page.dart';
import 'package:lt_dialogue/features/resource_library/application/use_cases/resource_library_runtime.dart';
import 'package:lt_dialogue/features/resource_library/domain/models/resource_library_view_state.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations_zh.dart';
import 'package:lt_dialogue/models/app_section.dart';
import 'package:lt_dialogue/models/resource_library_mode.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';
import 'package:lt_dialogue/services/database_service.dart';

import '../helpers/responsive_test_helper.dart';

/// Controllable fake of the Resource Library *authority*. It lets the tests
/// drive the loading → data transition explicitly (no real sleeps) and mutate
/// the authority between mounts to prove the homepage projection refreshes.
final class _FakeLibraryRuntime implements ResourceLibraryRuntime {
  _FakeLibraryRuntime(this.items, {this.defer = false});

  List<ResourceLibraryItem> items;
  bool defer;
  int loadCount = 0;
  Completer<List<ResourceLibraryItem>>? _pending;

  @override
  Future<List<ResourceLibraryItem>> load(ResourceLibraryMode mode) {
    loadCount++;
    if (defer) {
      _pending = Completer<List<ResourceLibraryItem>>();
      return _pending!.future;
    }
    return Future<List<ResourceLibraryItem>>.value(List.of(items));
  }

  /// Completes the most recent deferred [load] with the current [items].
  void completeLatest() => _pending?.complete(List.of(items));

  @override
  Future<ResourceOperationResult> moveToTrash({
    required ResourceLibraryItem item,
    required ResourceLibraryMode mode,
  }) async =>
      const ResourceOperationResult.success(message: '已移入回收站');

  @override
  Future<String> createManual({
    required ResourceType type,
    required String name,
    required String summary,
    required ResourceLibraryMode mode,
  }) async =>
      items.first.id;
}

const _worldview = ResourceLibraryItem(
  id: 'w1',
  type: ResourceType.worldview,
  name: '艾尔德兰世界观设定集',
  summary: '银月大陆与古老法则',
  updatedAt: '2026-10-01 10:00',
  status: ResourceDisplayStatus.ready,
  isStudioAvailable: true,
);

const _character = ResourceLibraryItem(
  id: 'c1',
  type: ResourceType.character,
  name: '艾莉丝 · 温斯特角色资源蓝图',
  summary: '游侠 · 冷静',
  updatedAt: '2026-09-30 10:00',
  status: ResourceDisplayStatus.saved,
  isStudioAvailable: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('lt_home_projection_');
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

  Widget shell(ProviderContainer container, {Widget? home}) =>
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.light(),
          home: home ?? const SizedBox.shrink(),
        ),
      );

  Widget dashboard() => AdventureDashboardScreen(
        onStartAdventure: (_, {difficulty}) async {},
      );

  ProviderContainer containerWith(ResourceLibraryRuntime runtime) {
    final container = ProviderContainer(
      overrides: [
        resourceLibraryRuntimeProvider.overrideWithValue(runtime),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// Renders the dashboard at a tall viewport so every library row is laid out.
  Future<void> mountDashboard(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    setViewport(tester, width: 1000, height: 1600);
    await tester.pumpWidget(shell(container, home: dashboard()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  final l10n = AppLocalizationsZh();

  Finder actionIn(String subsectionKey) => find.descendant(
        of: find.byKey(ValueKey(subsectionKey)),
        matching: find.text(l10n.dashboardGoToLibrary),
      );

  group('Home resource projection data stability', () {
    testWidgets('shows existing worldview and character from the authority',
        (tester) async {
      final container =
          containerWith(_FakeLibraryRuntime([_worldview, _character]));
      await mountDashboard(tester, container);

      expect(find.text(_worldview.name), findsOneWidget);
      expect(find.text(_character.name), findsOneWidget);
      expect(find.text(l10n.dashboardNoCustomWorldsTitle), findsNothing);
      expect(find.text(l10n.dashboardNoCharacterCardsTitle), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an in-flight load is rendered as loading, never as empty',
        (tester) async {
      final runtime =
          _FakeLibraryRuntime([_worldview, _character], defer: true);
      final container = containerWith(runtime);
      await mountDashboard(tester, container);

      // Still loading: show a spinner, never the "no data" copy.
      expect(
          find.byKey(const Key('dashboard-subsection-worlds')), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsWidgets);
      expect(find.text(l10n.dashboardNoCustomWorldsTitle), findsNothing);
      expect(find.text(l10n.dashboardNoCharacterCardsTitle), findsNothing);
    });

    testWidgets('loading → data updates in place', (tester) async {
      final runtime =
          _FakeLibraryRuntime([_worldview, _character], defer: true);
      final container = containerWith(runtime);
      await mountDashboard(tester, container);
      expect(find.byType(CircularProgressIndicator), findsWidgets);

      runtime.completeLatest();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text(_worldview.name), findsOneWidget);
      expect(find.text(_character.name), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a load error surfaces an error state, not empty',
        (tester) async {
      final container = containerWith(_FailingRuntime());
      await mountDashboard(tester, container);

      expect(find.text(l10n.pageLoadError), findsWidgets);
      expect(find.text(l10n.dashboardNoCustomWorldsTitle), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'dispose and re-enter re-reads the authority (create/delete sync)',
        (tester) async {
      final runtime = _FakeLibraryRuntime([_worldview]);
      final container = containerWith(runtime);
      await mountDashboard(tester, container);
      expect(find.text(_worldview.name), findsOneWidget);
      expect(find.text(_character.name), findsNothing);

      // Leave the home (library / creation), mutate the authority, come back.
      await tester.pumpWidget(shell(container));
      await tester.pump(const Duration(milliseconds: 50));

      runtime.items = [_worldview, _character];
      await mountDashboard(tester, container);

      expect(find.text(_character.name), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('rapid home → library → home never sticks on a stale empty',
        (tester) async {
      final runtime = _FakeLibraryRuntime([_worldview], defer: true);
      final container = containerWith(runtime);

      await mountDashboard(tester, container);
      // Leave before the first load resolves.
      await tester.pumpWidget(shell(container));
      await tester.pump(const Duration(milliseconds: 50));
      // Enter again immediately.
      await mountDashboard(tester, container);

      runtime.completeLatest();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text(_worldview.name), findsOneWidget);
      expect(find.text(l10n.dashboardNoCustomWorldsTitle), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('Home resource navigation semantics', () {
    testWidgets('"我的世界设定 → 前往资料库" opens the library on worldview',
        (tester) async {
      final container =
          containerWith(_FakeLibraryRuntime([_worldview, _character]));
      await mountDashboard(tester, container);

      await tester.tap(actionIn('dashboard-subsection-worlds'));
      await tester.pump();

      final chat = container.read(chatProvider);
      expect(chat.currentSection, AppSection.resources);
      expect(
          chat.resourceLibraryInitialFilter, ResourceLibraryFilter.worldview);
      expect(chat.resourceLibraryInitialResourceId, isNull);
    });

    testWidgets('"我的角色卡档案 → 前往资料库" opens the library on character',
        (tester) async {
      final container =
          containerWith(_FakeLibraryRuntime([_worldview, _character]));
      await mountDashboard(tester, container);

      await tester.tap(actionIn('dashboard-subsection-characters'));
      await tester.pump();

      final chat = container.read(chatProvider);
      expect(chat.currentSection, AppSection.resources);
      expect(
          chat.resourceLibraryInitialFilter, ResourceLibraryFilter.character);
      expect(chat.resourceLibraryInitialResourceId, isNull);
    });

    testWidgets('tapping a specific worldview opens that existing resource',
        (tester) async {
      final container =
          containerWith(_FakeLibraryRuntime([_worldview, _character]));
      await mountDashboard(tester, container);

      await tester.tap(find.byKey(const ValueKey('dashboard-world-w1')));
      await tester.pump();

      final chat = container.read(chatProvider);
      expect(chat.currentSection, AppSection.resources);
      expect(
          chat.resourceLibraryInitialFilter, ResourceLibraryFilter.worldview);
      expect(chat.resourceLibraryInitialResourceId, 'w1');
      // The existing-resource path must never launch the creation wizard.
      expect(find.byType(AssemblyCreatePage), findsNothing);
    });

    testWidgets('tapping a specific character opens that existing resource',
        (tester) async {
      final container =
          containerWith(_FakeLibraryRuntime([_worldview, _character]));
      await mountDashboard(tester, container);

      await tester.tap(find.byKey(const ValueKey('dashboard-character-c1')));
      await tester.pump();

      final chat = container.read(chatProvider);
      expect(chat.currentSection, AppSection.resources);
      expect(
          chat.resourceLibraryInitialFilter, ResourceLibraryFilter.character);
      expect(chat.resourceLibraryInitialResourceId, 'c1');
    });

    testWidgets('a plain library navigation clears the deep-link request',
        (tester) async {
      final container = containerWith(_FakeLibraryRuntime([_worldview]));
      await mountDashboard(tester, container);

      await tester.tap(find.byKey(const ValueKey('dashboard-world-w1')));
      await tester.pump();
      expect(
          container.read(chatProvider).resourceLibraryInitialResourceId, 'w1');

      // Sidebar / bottom-nav style entry has no specific target.
      container
          .read(chatProvider)
          .openResourceLibrary(ResourceLibraryMode.adventure);

      final chat = container.read(chatProvider);
      expect(chat.resourceLibraryInitialFilter, isNull);
      expect(chat.resourceLibraryInitialResourceId, isNull);
    });
  });
}

/// A runtime whose [load] always fails, to pin the error branch.
final class _FailingRuntime implements ResourceLibraryRuntime {
  @override
  Future<List<ResourceLibraryItem>> load(ResourceLibraryMode mode) async =>
      throw StateError('authority unavailable');

  @override
  Future<ResourceOperationResult> moveToTrash({
    required ResourceLibraryItem item,
    required ResourceLibraryMode mode,
  }) async =>
      const ResourceOperationResult.success();

  @override
  Future<String> createManual({
    required ResourceType type,
    required String name,
    required String summary,
    required ResourceLibraryMode mode,
  }) async =>
      '';
}
