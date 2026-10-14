import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lt_dialogue/application/llm/llm_gateway.dart';
import 'package:lt_dialogue/application/resource_library/import_models.dart';
import 'package:lt_dialogue/application/resources/resource_creation_contracts.dart';
import 'package:lt_dialogue/core/router/app_router.dart';
import 'package:lt_dialogue/core/widgets/app_select.dart';
import 'package:lt_dialogue/core/widgets/app_text_field.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_limits.dart';
import 'package:lt_dialogue/features/resource_library/presentation/screens/resource_ai_create_page.dart';
import 'package:lt_dialogue/features/resource_library/presentation/screens/resource_library_screen.dart';
import 'package:lt_dialogue/features/resource_studio/presentation/pages/resource_studio_page.dart';
import 'package:lt_dialogue/models/llm_task.dart';
import 'package:lt_dialogue/models/resource_library_mode.dart';
import 'package:lt_dialogue/models/resource_provenance.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';
import 'package:lt_dialogue/screens/resource_library/resource_card_ai_import_page.dart';
import 'package:lt_dialogue/screens/resource_library/worldview_ai_import_page.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/llm_service.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';

import '../helpers/responsive_test_helper.dart';
import '../helpers/localization_test_helper.dart';
import '../helpers/studio_scroll_helper.dart';

Finder _fieldByLabel(String label) => find.descendant(
      of: find.widgetWithText(AppTextField, label),
      matching: find.byType(TextField),
    );

/// Scrolls the submit button into view (it sits below the fold at 320 px) and
/// activates it. [secondTapWithoutPump] reproduces a double tap in one frame.
Future<void> _submitAiCreate(
  WidgetTester tester, {
  bool secondTapWithoutPump = false,
}) async {
  final submit = find.byKey(const Key('ai-create-submit-button'));
  // The form is taller than small viewports and `ensureVisible` alone can
  // leave the button below the fold in this nested scroll structure, so drag
  // until the whole button is on screen (bounded loop keeps failures honest).
  final viewportHeight =
      tester.view.physicalSize.height / tester.view.devicePixelRatio;
  for (var i = 0; i < 8; i++) {
    await tester.ensureVisible(submit);
    await tester.pumpAndSettle();
    final rect = tester.getRect(submit);
    if (rect.top >= 0 && rect.bottom <= viewportHeight) break;
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -100));
    await tester.pumpAndSettle();
  }
  await tester.tap(submit);
  if (secondTapWithoutPump) {
    await tester.tap(submit, warnIfMissed: false);
  }
}

/// End-to-end: ResourceLibrary -> AI create -> create task -> Resource Studio.
///
/// Uses production providers, controllers, repositories, pipeline and SQLite;
/// only the external model response is controlled.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;
  late Directory directory;

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel(
                'dev.fluttercommunity.plus/connectivity_status'),
            (_) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('dev.fluttercommunity.plus/connectivity'),
            (_) async => ['wifi']);
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('lt_ai_nav_');
    DatabaseService.customDbDir = directory.path;
    await DatabaseService.resetDatabase();
    await DatabaseService.database;
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    DatabaseService.customDbDir = null;
    await directory.delete(recursive: true);
  });

  group('AI create page elastic selection (ADR-0003)', () {
    testWidgets('inherit keeps the global ceiling; independent re-freezes it',
        (tester) async {
      setViewport(tester, width: 390, height: 844);
      final container = ProviderContainer();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
      });
      await tester.runAsync(() => container
          .read(settingsProvider)
          .setApiKey('test-only-not-a-real-key'));

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          initialRoute: '/library',
          onGenerateRoute: AppRouter.onGenerateRoute,
        ),
      ));
      await _waitFor(tester, find.text('还没有资源'));
      await tester.tap(find.byKey(const Key('resource-create-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('AI 创建'));
      await tester.pumpAndSettle();
      expect(find.byType(ResourceAiCreatePage), findsOneWidget);

      expect(find.byKey(const Key('ai-create-elastic-mode-segmented')),
          findsOneWidget);

      // Bring the target below nominal first: at the nominal default the
      // ceiling already sits on the absolute capacity, which would mask the
      // elasticity. Target 10000 → C(20%) = 12000.
      final targetInput =
          find.byKey(const ValueKey('ai_creation_target_words_input'));
      await tester.ensureVisible(targetInput);
      await tester.pumpAndSettle();
      await tester.enterText(targetInput, '10000');
      await tester
          .tap(find.byKey(const ValueKey('ai_creation_target_words_confirm')));
      await tester.pumpAndSettle();
      const worldNominal = 10000;
      final ceilingText = tester
          .widget<Text>(
              find.byKey(const Key('ai-create-elastic-ceiling-value')))
          .data!;
      final uiCeiling =
          int.parse(ceilingText.replaceAll(RegExp(r'[^0-9]'), ''));
      expect(uiCeiling, (worldNominal * 120) ~/ 100);

      // Switch to independent 50%: the live ceiling re-computes.
      await tester.ensureVisible(
          find.byKey(const Key('ai-create-elastic-mode-segmented')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('独立设置'));
      await tester.pumpAndSettle();
      final dropdown =
          find.byKey(const Key('ai-create-elastic-percent-dropdown'));
      await tester.ensureVisible(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(dropdown, warnIfMissed: false);
      await tester.pumpAndSettle();
      // The unified AppSelect opens the shared picker sheet whose lazy list
      // must be scrolled before the trailing entries are built.
      await tester.dragUntilVisible(
        find.text('50%'),
        find.byType(ListView).last,
        const Offset(0, -80),
      );
      await tester.pumpAndSettle();
      final item = find.text('50%').last;
      await tester.ensureVisible(item);
      await tester.pumpAndSettle();
      await tester.tap(item, warnIfMissed: false);
      await tester.pumpAndSettle();
      final newCeiling = tester
          .widget<Text>(
              find.byKey(const Key('ai-create-elastic-ceiling-value')))
          .data!;
      expect(int.parse(newCeiling.replaceAll(RegExp(r'[^0-9]'), '')),
          (worldNominal * 150) ~/ 100);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'the unified picker exposes all eleven percents inside a '
        'height-capped scrollable sheet', (tester) async {
      setViewport(tester, width: 320, height: 568);
      final container = ProviderContainer();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
      });
      await tester.runAsync(() => container
          .read(settingsProvider)
          .setApiKey('test-only-not-a-real-key'));

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          initialRoute: '/library',
          onGenerateRoute: AppRouter.onGenerateRoute,
        ),
      ));
      await _waitFor(tester, find.text('还没有资源'));
      await tester.tap(find.byKey(const Key('resource-create-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('AI 创建'));
      await tester.pumpAndSettle();

      // Keep the target below the absolute capacity so the live ceiling can
      // actually prove the picked percent.
      final targetInput =
          find.byKey(const ValueKey('ai_creation_target_words_input'));
      await tester.ensureVisible(targetInput);
      await tester.pumpAndSettle();
      await tester.enterText(targetInput, '10000');
      await tester
          .tap(find.byKey(const ValueKey('ai_creation_target_words_confirm')));
      await tester.pumpAndSettle();
      const worldNominal = 10000;
      int ceilingValue() {
        final text = tester
            .widget<Text>(
                find.byKey(const Key('ai-create-elastic-ceiling-value')))
            .data!;
        return int.parse(text.replaceAll(RegExp(r'[^0-9]'), ''));
      }

      await tester.tap(find.text('独立设置'), warnIfMissed: false);
      await tester.pumpAndSettle();
      final dropdown =
          find.byKey(const Key('ai-create-elastic-percent-dropdown'));
      await tester.ensureVisible(dropdown);
      await tester.pumpAndSettle();

      final sheetListView = find.byType(ListView).last;
      // Rows are scoped to the sheet: the trigger behind the barrier shows
      // the selected label too, so a bare text finder can match twice.
      Finder sheetRow(int percent) => find.descendant(
            of: find.byType(BottomSheet),
            matching: find.text('$percent%'),
          );

      Future<void> openPicker() async {
        await tester.tap(dropdown, warnIfMissed: false);
        await tester.pumpAndSettle();
      }

      Future<void> pickPercent(int percent) async {
        final row = sheetRow(percent);
        await tester.dragUntilVisible(
          row,
          sheetListView,
          Offset(0, percent >= 25 ? -80 : 80),
        );
        await tester.pumpAndSettle();
        await tester.tap(row, warnIfMissed: false);
        await tester.pumpAndSettle();
      }

      // Opened picker: the shared sheet list is capped well below the
      // viewport height instead of stretching to fit all 11 rows.
      await openPicker();
      expect(find.byType(BottomSheet), findsOneWidget);
      final sheetHeight = tester.getRect(sheetListView).height;
      expect(sheetHeight, lessThanOrEqualTo(568 * 0.9));

      // Every one of the 11 options is reachable by scrolling, in both
      // directions.
      const percents = [0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50];
      for (final percent in percents) {
        final row = sheetRow(percent);
        await tester.dragUntilVisible(
          row,
          sheetListView,
          Offset(0, percent >= 25 ? -80 : 80),
        );
        await tester.pumpAndSettle();
        expect(row, findsOneWidget,
            reason: 'option $percent% must be reachable');
      }

      // E = 0% keeps the ceiling exactly at the target (no widening).
      await pickPercent(0);
      expect(ceilingValue(), worldNominal);
      expect(find.byType(BottomSheet), findsNothing,
          reason: 'picking an option closes the picker');

      // E = 35% widens the ceiling to target x 1.35.
      await openPicker();
      await pickPercent(35);
      expect(ceilingValue(), (worldNominal * 135) ~/ 100);

      // Tapping outside the sheet closes it without changing the value.
      await openPicker();
      expect(find.byType(BottomSheet), findsOneWidget);
      await tester.tapAt(const Offset(160, 60));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(ceilingValue(), (worldNominal * 135) ~/ 100);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'an independent 35% selection freezes the real blueprint '
        'budget, not just the UI', (tester) async {
      setViewport(tester, width: 390, height: 844);
      final container = ProviderContainer(
        overrides: [llmGatewayProvider.overrideWithValue(_AiResponses())],
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
      });
      await tester.runAsync(() => container
          .read(settingsProvider)
          .setApiKey('test-only-not-a-real-key'));

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          initialRoute: '/library',
          onGenerateRoute: AppRouter.onGenerateRoute,
        ),
      ));
      await _waitFor(tester, find.text('还没有资源'));
      await tester.tap(find.byKey(const Key('resource-create-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('AI 创建'));
      await tester.pumpAndSettle();

      await tester.enterText(_fieldByLabel('名称'), '弹性冻结资源');
      await tester.enterText(_fieldByLabel('粘贴参考内容'), '山海之间的城市和居民');
      final targetInput =
          find.byKey(const ValueKey('ai_creation_target_words_input'));
      await tester.ensureVisible(targetInput);
      await tester.pumpAndSettle();
      await tester.enterText(targetInput, '10000');
      await tester
          .tap(find.byKey(const ValueKey('ai_creation_target_words_confirm')));
      await tester.pumpAndSettle();

      await tester.ensureVisible(
          find.byKey(const Key('ai-create-elastic-mode-segmented')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('独立设置'));
      await tester.pumpAndSettle();
      final dropdown =
          find.byKey(const Key('ai-create-elastic-percent-dropdown'));
      await tester.ensureVisible(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(dropdown, warnIfMissed: false);
      await tester.pumpAndSettle();
      await tester.dragUntilVisible(
        find.text('35%'),
        find.byType(ListView).last,
        const Offset(0, -80),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('35%').last, warnIfMissed: false);
      await tester.pumpAndSettle();
      final ceilingText = tester
          .widget<Text>(
              find.byKey(const Key('ai-create-elastic-ceiling-value')))
          .data!;
      expect(int.parse(ceilingText.replaceAll(RegExp(r'[^0-9]'), '')),
          (10000 * 135) ~/ 100);

      await _submitAiCreate(tester);
      await _waitFor(tester, find.byType(ResourceStudioPage));
      await _waitFor(tester, find.text('编辑正文'));

      final db = await tester.runAsync(() => DatabaseService.database);
      final sessions = await tester.runAsync(
        () => db!.query('resource_creation_sessions'),
      );
      expect(sessions, hasLength(1));
      // The run-scoped choice must be encoded in the session origin so the
      // confirm transaction can freeze it even if settings change meanwhile.
      final envelope = ResourceCreationOriginEnvelope.decode(
          sessions!.single['origin'] as String);
      expect(envelope.elasticPercent, 35);

      final blueprints = await tester.runAsync(
        () => db!.query('resource_blueprints'),
      );
      expect(blueprints, hasLength(1));
      // The frozen snapshot is the source of truth for every later budget
      // read; the UI label alone would prove nothing.
      expect(blueprints!.single['elastic_percent'], 35);
      expect(tester.takeException(), isNull);
    });
  });

  group('AI creation navigates to the production Resource Studio', () {
    for (final type in ResourceType.values) {
      testWidgets(
          '${type.name} AI creation reaches the Studio and keeps the '
          'target length', (tester) async {
        setViewport(tester, width: 390, height: 844);
        final container = ProviderContainer(
          overrides: [llmGatewayProvider.overrideWithValue(_AiResponses())],
        );
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          container.dispose();
        });
        await tester.runAsync(() => container
            .read(settingsProvider)
            .setApiKey('test-only-not-a-real-key'));

        await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            locale: Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            initialRoute: '/library',
            onGenerateRoute: AppRouter.onGenerateRoute,
          ),
        ));
        await _waitFor(tester, find.text('还没有资源'));

        await tester.tap(find.byKey(const Key('resource-create-button')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('AI 创建'));
        await tester.pumpAndSettle();
        expect(find.byType(ResourceAiCreatePage), findsOneWidget);

        final label = switch (type) {
          ResourceType.worldview => '世界观',
          ResourceType.character => '角色',
          ResourceType.npc => 'NPC',
        };
        if (type != ResourceType.worldview) {
          await tester.tap(find.byKey(const Key('ai-create-type-select')));
          await tester.pumpAndSettle();
          await tester.tap(find.text(label).last);
          await tester.pumpAndSettle();
        }

        final name = 'AI导航${type.name}';
        await tester.enterText(_fieldByLabel('名称'), name);
        await tester.enterText(_fieldByLabel('粘贴参考内容'), '山海之间的城市和居民');
        // Read the UI value so the assertion proves the slider value is what
        // actually reaches the pipeline, not just a type default.
        final targetText = tester
            .widget<Text>(find.byKey(const Key('ai-create-target-value')));
        final uiTarget =
            int.parse(targetText.data!.replaceAll(RegExp(r'[^0-9]'), ''));
        expect(
          uiTarget,
          ResourceLimits.policyFor(type).nominalCharacters,
        );

        await _submitAiCreate(tester);
        await _waitFor(tester, find.byType(ResourceStudioPage));
        await _waitFor(tester, find.text('编辑正文'));

        final db = await tester.runAsync(() => DatabaseService.database);
        final sessions = await tester.runAsync(
          () => db!.query('resource_creation_sessions'),
        );
        expect(sessions, hasLength(1));
        expect(sessions!.single['target_characters'], uiTarget);
        expect(sessions.single['resource_type'], type.storageValue);
        final resources = await tester.runAsync(() => db!.query('resources'));
        expect(resources, hasLength(1));
        // The pipeline owns naming: the confirmed blueprint's suggested name
        // becomes the persisted resource name.
        expect(resources!.single['name'], 'AI新资源');
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      });
    }

    testWidgets(
        'starting creation shows a creation state, not the session '
        'picker', (tester) async {
      setViewport(tester, width: 390, height: 844);
      final container = ProviderContainer(
        overrides: [
          // A slow planner keeps the transient creation state observable.
          llmGatewayProvider.overrideWithValue(_AiResponses(planDelay: 2000)),
        ],
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
      });
      await tester.runAsync(() => container
          .read(settingsProvider)
          .setApiKey('test-only-not-a-real-key'));
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          initialRoute: '/library',
          onGenerateRoute: AppRouter.onGenerateRoute,
        ),
      ));
      await _waitFor(tester, find.text('还没有资源'));
      await tester.tap(find.byKey(const Key('resource-create-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('AI 创建'));
      await tester.pumpAndSettle();
      await tester.enterText(_fieldByLabel('名称'), '创建中资源');
      await tester.enterText(_fieldByLabel('粘贴参考内容'), '城市居民');
      final submit = find.byKey(const Key('ai-create-submit-button'));
      await tester.ensureVisible(submit);
      await tester.pumpAndSettle();
      await tester.tap(submit);

      await _waitFor(tester, find.byType(ResourceStudioPage));
      // While the planner runs the tree is still absent; the Studio must not
      // fall back to the "select a resource or session" picker.
      expect(find.text('正在创建资源并启动生成'), findsOneWidget);
      expect(find.text('选择资源或生成会话'), findsNothing);
      expect(find.text('创建并开始生成'), findsNothing);
      await _waitFor(tester, find.text('编辑正文'));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets(
        'failing creation stays on the Studio with a retry, and never '
        'bounces back to the library', (tester) async {
      setViewport(tester, width: 390, height: 844);
      final container = ProviderContainer(
        overrides: [
          llmGatewayProvider
              .overrideWithValue(_AiResponses(failPlanning: true)),
        ],
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
      });
      await tester.runAsync(() => container
          .read(settingsProvider)
          .setApiKey('test-only-not-a-real-key'));
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          initialRoute: '/library',
          onGenerateRoute: AppRouter.onGenerateRoute,
        ),
      ));
      await _waitFor(tester, find.text('还没有资源'));
      await tester.tap(find.byKey(const Key('resource-create-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('AI 创建'));
      await tester.pumpAndSettle();
      await tester.enterText(_fieldByLabel('名称'), '失败资源');
      await tester.enterText(_fieldByLabel('粘贴参考内容'), '任何内容');
      await _submitAiCreate(tester);

      await _waitFor(tester, find.text('资源创建失败'));
      expect(find.byType(ResourceStudioPage), findsOneWidget);
      expect(find.byType(ResourceLibraryScreen), findsNothing);
      expect(find.text('重试创建'), findsOneWidget);
      expect(find.text('选择资源或生成会话'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets(
        'double tapping 开始创建 creates exactly one resource and one '
        'task', (tester) async {
      setViewport(tester, width: 390, height: 844);
      final container = ProviderContainer(
        overrides: [llmGatewayProvider.overrideWithValue(_AiResponses())],
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
      });
      await tester.runAsync(() => container
          .read(settingsProvider)
          .setApiKey('test-only-not-a-real-key'));
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          initialRoute: '/library',
          onGenerateRoute: AppRouter.onGenerateRoute,
        ),
      ));
      await _waitFor(tester, find.text('还没有资源'));
      await tester.tap(find.byKey(const Key('resource-create-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('AI 创建'));
      await tester.pumpAndSettle();
      await tester.enterText(_fieldByLabel('名称'), '防重复资源');
      await tester.enterText(_fieldByLabel('粘贴参考内容'), '城市居民');
      await _submitAiCreate(tester, secondTapWithoutPump: true);

      await _waitFor(tester, find.byType(ResourceStudioPage));
      await _waitFor(tester, find.text('编辑正文'));

      final db = await tester.runAsync(() => DatabaseService.database);
      final resources = await tester.runAsync(() => db!.query('resources'));
      final sessions =
          await tester.runAsync(() => db!.query('resource_creation_sessions'));
      expect(resources, hasLength(1));
      expect(sessions, hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('returning from the Studio refreshes the library list',
        (tester) async {
      setViewport(tester, width: 390, height: 844);
      final container = ProviderContainer(
        overrides: [
          llmGatewayProvider.overrideWithValue(
            _AiResponses(suggestedName: '返回刷新资源'),
          ),
        ],
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
      });
      await tester.runAsync(() => container
          .read(settingsProvider)
          .setApiKey('test-only-not-a-real-key'));
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          initialRoute: '/library',
          onGenerateRoute: AppRouter.onGenerateRoute,
        ),
      ));
      await _waitFor(tester, find.text('还没有资源'));
      await tester.tap(find.byKey(const Key('resource-create-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('AI 创建'));
      await tester.pumpAndSettle();
      await tester.enterText(_fieldByLabel('名称'), '返回刷新资源');
      await tester.enterText(_fieldByLabel('粘贴参考内容'), '城市居民');
      await _submitAiCreate(tester);
      await _waitFor(tester, find.text('编辑正文'));
      expect(find.byType(AppSelect<ResourceType>), findsNothing);

      await localizedPageBack(tester);
      await _waitFor(tester, find.byKey(const Key('resource-list')));
      await _waitFor(tester, find.text('返回刷新资源'));
      expect(find.byType(ResourceStudioPage), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('Studio remains usable at 320px after creation',
        (tester) async {
      setViewport(tester, width: 320, height: 568);
      final container = ProviderContainer(
        overrides: [llmGatewayProvider.overrideWithValue(_AiResponses())],
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
      });
      await tester.runAsync(() => container
          .read(settingsProvider)
          .setApiKey('test-only-not-a-real-key'));
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          initialRoute: '/library',
          onGenerateRoute: AppRouter.onGenerateRoute,
        ),
      ));
      await _waitFor(tester, find.text('还没有资源'));
      await tester.tap(find.byKey(const Key('resource-create-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('AI 创建'));
      await tester.pumpAndSettle();
      await tester.enterText(_fieldByLabel('名称'), '小屏资源');
      await tester.enterText(_fieldByLabel('粘贴参考内容'), '城市居民');
      await _submitAiCreate(tester);
      // At 320 px the Studio header fills the viewport, so the reader sliver is
      // outside the cache extent and its widgets are not built until scrolled.
      await _waitFor(tester, find.byKey(resourceStudioMainScrollKey));
      await revealInStudio(tester, find.text('编辑正文'));
      expect(find.text('编辑正文'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('worldview Import enters the persisted Runtime authority',
        (tester) async {
      setViewport(tester, width: 390, height: 844);
      final container = ProviderContainer(
        overrides: [llmGatewayProvider.overrideWithValue(_AiResponses())],
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
      });
      await tester.runAsync(() => container
          .read(settingsProvider)
          .setApiKey('test-only-not-a-real-key'));
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: WorldviewAiImportPage(
              mode: ResourceLibraryMode.creation,
              onChanged: () {},
            ),
          ),
        ),
      ));
      await tester.enterText(
        find.byType(TextField).first,
        '浮空城邦\n被风暴包围的城市与居民',
      );
      await tester.tap(find.text('AI 解析'));
      await _waitFor(tester, find.byType(ResourceStudioPage));
      await _waitFor(tester, find.text('编辑正文'));
      await _expectAuthorityChain(tester, ResourceType.worldview,
          libraryMode: 'creation');
      expect(tester.takeException(), isNull);
    });

    for (final kind in ResourceCardImportKind.values) {
      testWidgets('${kind.name} Import enters the persisted Runtime authority',
          (tester) async {
        setViewport(tester, width: 390, height: 844);
        final container = ProviderContainer(
          overrides: [llmGatewayProvider.overrideWithValue(_AiResponses())],
        );
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          container.dispose();
        });
        await tester.runAsync(() => container
            .read(settingsProvider)
            .setApiKey('test-only-not-a-real-key'));
        await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: ResourceCardAiImportPage(
                kind: kind,
                worldviews: const [],
                characterCards: const [],
                detailInstruction: '保留原文事实',
                aiDepth: AiGenerationDepth.simple,
                mode: ResourceLibraryMode.adventure,
                onChanged: () {},
              ),
            ),
          ),
        ));
        await tester.enterText(
          find.byType(TextField).first,
          '${kind.name} 候选\n来自浮空城邦的守卫',
        );
        await tester.tap(find.text('AI 解析'));
        await _waitFor(tester, find.byType(ResourceStudioPage));
        await _waitFor(tester, find.text('编辑正文'));
        await _expectAuthorityChain(
          tester,
          kind == ResourceCardImportKind.character
              ? ResourceType.character
              : ResourceType.npc,
          libraryMode: 'adventure',
        );
        expect(tester.takeException(), isNull);
      });
    }
  });
}

Future<void> _expectAuthorityChain(
  WidgetTester tester,
  ResourceType type, {
  required String libraryMode,
}) async {
  final db = await tester.runAsync(() => DatabaseService.database);
  for (final table in const [
    'resource_creation_sessions',
    'resource_blueprints',
    'resources',
    'resource_generation_sessions',
    'resource_generation_tasks',
    'resource_generation_attempts',
    'resource_parts',
  ]) {
    final rows = await tester.runAsync(() => db!.query(table));
    expect(rows, isNotEmpty,
        reason: '$table should belong to the authority chain');
  }
  final creation = (await tester.runAsync(
    () => db!.query('resource_creation_sessions'),
  ))!
      .single;
  expect(creation['resource_type'], type.storageValue);
  final resource =
      (await tester.runAsync(() => db!.query('resources')))!.single;
  final metadata = jsonDecode(resource['metadata_json']! as String) as Map;
  expect(metadata['mode'], libraryMode);
  final sessions = await tester.runAsync(
    () => db!.query('resource_generation_sessions'),
  );
  expect(sessions!.single['status'], 'completed');
}

// SQLite uses real asynchronous I/O; yield to it outside the fake widget clock
// and stop as soon as the observable UI condition is true.
Future<void> _waitFor(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 300; attempt++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) {
      await tester.pump(const Duration(milliseconds: 300));
      return;
    }
  }
  expect(finder, findsWidgets,
      reason: tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data)
          .join('\n'));
}

/// Only the external model response is controlled. Pipeline, SQLite,
/// repositories, runtime, providers and navigation remain production code.
final class _AiResponses implements LlmGateway {
  _AiResponses({
    this.failPlanning = false,
    this.planDelay = 0,
    this.suggestedName = 'AI新资源',
  });

  final bool failPlanning;
  final int planDelay;

  /// The blueprint's suggested name becomes the persisted resource name (the
  /// pipeline owns naming); tests assert against this value.
  final String suggestedName;

  @override
  bool get isConfigured => true;

  @override
  Future<String> rawCompletion(
      {required String systemPrompt,
      required String instruction,
      int maximumOutputTokens = 4096,
      double temperature = .7,
      LlmTask task = LlmTask.structuredExtraction,
      GenerationTaskHandle? taskHandle}) async {
    if (!systemPrompt.contains('"generation_id"')) {
      if (planDelay > 0) {
        await Future<void>.delayed(Duration(milliseconds: planDelay));
      }
      if (failPlanning) {
        throw StateError('planning failed');
      }
      final sectionId = RegExp(r'允许的 Section ID：([^,\n]+)')
          .firstMatch(systemPrompt)!
          .group(1)!;
      final partId =
          RegExp(r'允许的 Part ID：([^,\n]+)').firstMatch(systemPrompt)!.group(1)!;
      return jsonEncode({
        'suggestedName': suggestedName,
        'summary': '城市与居民',
        'sections': [
          {
            'id': sectionId,
            'title': '概览',
            'summary': '城市',
            'sortOrder': 0,
            'parts': [
              {
                'id': partId,
                'sectionId': sectionId,
                'title': '正文',
                'generationGoal': '描写城市',
                'estimatedLength': 800,
                'dependencies': <String>[],
                'sortOrder': 0
              }
            ]
          }
        ],
      });
    }
    final ids = <String, String>{};
    for (final key in [
      'generation_id',
      'resource_id',
      'section_id',
      'part_id',
      'attempt_id'
    ]) {
      ids[key] = RegExp('"$key": "(.*?)"').firstMatch(systemPrompt)!.group(1)!;
    }
    // U6: a confirmed narrative contract requires the body to reach the dynamic
    // minimum (340 for an 800-length plan), so the fake AI body is long enough.
    final content = 'AI生成正文：山海之间的城市和居民。${'补充正文内容。' * 60}';
    return [
      {
        'protocol_version': 1,
        ...ids,
        'sequence': 0,
        'op': 'start_part',
        'cursor': 0,
      },
      {
        'protocol_version': 1,
        ...ids,
        'sequence': 1,
        'op': 'append_text',
        'text_delta': content,
        'cursor': 0,
      },
      {
        'protocol_version': 1,
        ...ids,
        'sequence': 2,
        'op': 'complete_part',
        'cursor': content.length,
        'summary': '城市',
      },
    ].map(jsonEncode).join('\n');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError(invocation.memberName.toString());
}
