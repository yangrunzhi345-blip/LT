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
import 'package:lt_dialogue/core/router/app_router.dart';
import 'package:lt_dialogue/core/widgets/app_text_field.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/features/resource_library/presentation/screens/resource_ai_create_page.dart';
import 'package:lt_dialogue/features/resource_library/presentation/screens/resource_blueprint_review_page.dart';
import 'package:lt_dialogue/features/resource_library/presentation/screens/resource_create_page.dart';
import 'package:lt_dialogue/features/resource_library/presentation/screens/resource_library_detail_page.dart';
import 'package:lt_dialogue/features/resource_library/presentation/screens/resource_library_screen.dart';
import 'package:lt_dialogue/features/resource_library/presentation/screens/resource_manual_create_page.dart';
import 'package:lt_dialogue/features/resource_studio/presentation/pages/resource_studio_page.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';
import 'package:lt_dialogue/models/generation_task_handle.dart';
import 'package:lt_dialogue/models/llm_task.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';
import 'package:lt_dialogue/services/database_service.dart';

import '../helpers/localization_test_helper.dart';
import '../helpers/responsive_test_helper.dart';

Finder _fieldByLabel(String label) => find.descendant(
      of: find.widgetWithText(AppTextField, label),
      matching: find.byType(TextField),
    );

/// A creation flow is transient: once it commits (resource persisted, the
/// Studio opened), pressing Back must never re-enter the create hub, AI form or
/// blueprint review page. These regressions exercise the real production
/// providers / repositories / SQLite navigation stack; only the model response
/// is controlled.
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
    directory = await Directory.systemTemp.createTemp('lt_creation_nav_stack_');
    DatabaseService.customDbDir = directory.path;
    await DatabaseService.resetDatabase();
    await DatabaseService.database;
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    DatabaseService.customDbDir = null;
    if (directory.existsSync()) {
      try {
        directory.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  Future<ProviderContainer> boot(
    WidgetTester tester, {
    String suggestedName = 'AI新资源',
    double width = 390,
    double height = 844,
  }) async {
    setViewport(tester, width: width, height: height);
    final container = ProviderContainer(
      overrides: [
        llmGatewayProvider
            .overrideWithValue(_AiResponses(suggestedName: suggestedName)),
      ],
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });
    await tester.runAsync(
        () => container.read(settingsProvider).setApiKey('test-only-key'));
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
    return container;
  }

  Future<void> openAiForm(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('resource-create-button')));
    await tester.pumpAndSettle();
    expect(find.byType(ResourceCreatePage), findsOneWidget);
    await tester.tap(find.text('AI 创建'));
    await tester.pumpAndSettle();
    expect(find.byType(ResourceAiCreatePage), findsOneWidget);
  }

  Future<void> selectType(WidgetTester tester, ResourceType type) async {
    if (type == ResourceType.worldview) return;
    await tester.tap(find.byKey(const Key('ai-create-type-select')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('角色').last);
    await tester.pumpAndSettle();
  }

  Future<void> fillAiForm(WidgetTester tester, String name) async {
    await tester.enterText(_fieldByLabel('名称'), name);
    await tester.enterText(_fieldByLabel('粘贴参考内容'), '山海之间的城市和居民');
    await tester.pump();
  }

  Future<void> tapKey(WidgetTester tester, Key key) async {
    final finder = find.byKey(key);
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
  }

  void expectNoCreationFlowVisible() {
    expect(find.byType(ResourceCreatePage), findsNothing);
    expect(find.byType(ResourceAiCreatePage), findsNothing);
    expect(find.byType(ResourceBlueprintReviewPage), findsNothing);
  }

  /// Taps the back affordance that belongs to [page].
  ///
  /// During a route transition the page below is briefly still on-stage, so a
  /// global tooltip lookup can match two back buttons. Scoping the lookup to
  /// the page under test keeps the tap deterministic.
  Future<void> backFrom(WidgetTester tester, Finder page) async {
    final button = find.descendant(
      of: page,
      matching: find.byTooltip('返回'),
    );
    expect(button, findsOneWidget,
        reason: 'expected exactly one back button on $page');
    await tester.tap(button);
  }

  /// Asserts the Resource Studio is rendered inline inside the library (no
  /// pushed Studio route) and returns its widget for further inspection.
  ///
  /// The creation pages are already off the Navigator history when the inline
  /// Studio appears, but they may still be playing their exit transition, so
  /// this drains that transition before asserting they are gone.
  Future<ResourceStudioPage> expectInlineStudio(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ResourceStudioPage), findsOneWidget);
    final studio = tester.widget<ResourceStudioPage>(
      find.byType(ResourceStudioPage),
    );
    expect(studio.embedded, isTrue,
        reason: 'desktop wide layout must host the Studio inline');
    expect(find.byType(ResourceLibraryScreen), findsOneWidget);
    expectNoCreationFlowVisible();
    return studio;
  }

  /// Closes the inline Studio through its own back affordance and waits for the
  /// stable library surface to come back.
  Future<void> closeInlineStudio(WidgetTester tester) async {
    await expectInlineStudio(tester);
    final back = find.descendant(
      of: find.byType(ResourceStudioPage),
      matching: find.byTooltip('返回'),
    );
    expect(back, findsOneWidget);
    await tester.tap(back);
    await _waitFor(tester, find.byKey(const Key('resource-list')));
  }

  Future<int> dbCount(WidgetTester tester, String table) async {
    final db = await tester.runAsync(() => DatabaseService.database);
    final rows = await tester.runAsync(() => db!.query(table));
    return rows!.length;
  }

  group('Direct AI creation collapses its transient flow', () {
    for (final type in const [ResourceType.worldview, ResourceType.character]) {
      testWidgets(
          '${type.name}: create -> Studio -> Back -> Resource Library, with no '
          'creation page left behind', (tester) async {
        await boot(tester, suggestedName: '直接创建${type.name}');
        await openAiForm(tester);
        await selectType(tester, type);
        await fillAiForm(tester, '直接创建${type.name}');
        await tapKey(tester, const Key('ai-create-submit-button'));

        await _waitFor(tester, find.byType(ResourceStudioPage));
        await _waitFor(tester, find.text('编辑正文'));

        await localizedPageBack(tester);
        await _waitFor(tester, find.text('直接创建${type.name}'));

        expect(find.byType(ResourceStudioPage), findsNothing);
        expect(find.byType(ResourceLibraryScreen), findsOneWidget);
        expectNoCreationFlowVisible();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Blueprint review creation collapses the whole creation flow', () {
    for (final type in const [ResourceType.worldview, ResourceType.character]) {
      testWidgets(
          '${type.name}: create hub -> AI form -> review -> confirm -> Studio '
          '-> Back -> Resource Library', (tester) async {
        await boot(tester, suggestedName: '蓝图创建${type.name}');
        await openAiForm(tester);
        await selectType(tester, type);
        await fillAiForm(tester, '蓝图创建${type.name}');
        await tapKey(tester, const Key('ai-create-plan-button'));

        await _waitFor(tester, find.byType(ResourceBlueprintReviewPage));
        await tapKey(tester, const Key('blueprint-confirm-button'));

        await _waitFor(tester, find.byType(ResourceStudioPage));
        await _waitFor(tester, find.text('编辑正文'));
        // The review page and the creation forms must be gone from the stack
        // as soon as the blueprint commits.
        expectNoCreationFlowVisible();

        await localizedPageBack(tester);
        await _waitFor(tester, find.text('蓝图创建${type.name}'));

        expect(find.byType(ResourceStudioPage), findsNothing);
        expect(find.byType(ResourceLibraryScreen), findsOneWidget);
        expectNoCreationFlowVisible();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Desktop wide layout hosts the Studio inline', () {
    const desktopWidth = 1280.0;
    const desktopHeight = 900.0;

    for (final type in const [ResourceType.character, ResourceType.worldview]) {
      testWidgets(
          'desktop ${type.name}: create -> inline Studio (no pushed Studio) '
          '-> close -> stable Library', (tester) async {
        await boot(
          tester,
          suggestedName: '桌面内联${type.name}',
          width: desktopWidth,
          height: desktopHeight,
        );
        await openAiForm(tester);
        await selectType(tester, type);
        await fillAiForm(tester, '桌面内联${type.name}');
        await tapKey(tester, const Key('ai-create-submit-button'));

        await _waitFor(tester, find.byType(ResourceStudioPage));
        await _waitFor(tester, find.text('编辑正文'));
        // Inline: the Studio is a child of the library route, not a pushed
        // route, and every creation page has been popped.
        await expectInlineStudio(tester);
        expect(find.byType(ResourceLibraryDetailPage), findsNothing);
        // Exactly one resource and one creation session: no duplicate create.
        expect(await dbCount(tester, 'resources'), 1);
        expect(await dbCount(tester, 'resource_creation_sessions'), 1);

        await closeInlineStudio(tester);
        expect(find.byType(ResourceStudioPage), findsNothing);
        expect(find.byType(ResourceLibraryScreen), findsOneWidget);
        expect(find.text('桌面内联${type.name}'), findsWidgets);
        expectNoCreationFlowVisible();
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets(
        'desktop blueprint: review confirm -> identity hosts inline Studio, '
        'with no create / AI / review residue and no second persistence',
        (tester) async {
      await boot(
        tester,
        suggestedName: '桌面蓝图资源',
        width: desktopWidth,
        height: desktopHeight,
      );
      await openAiForm(tester);
      await selectType(tester, ResourceType.character);
      await fillAiForm(tester, '桌面蓝图资源');
      await tapKey(tester, const Key('ai-create-plan-button'));

      await _waitFor(tester, find.byType(ResourceBlueprintReviewPage));
      await tapKey(tester, const Key('blueprint-confirm-button'));

      await _waitFor(tester, find.byType(ResourceStudioPage));
      await _waitFor(tester, find.text('编辑正文'));
      await expectInlineStudio(tester);
      // The blueprint committed one resource through one creation session.
      expect(await dbCount(tester, 'resources'), 1);
      expect(await dbCount(tester, 'resource_creation_sessions'), 1);
      expect(await dbCount(tester, 'resource_generation_sessions'), 1);

      await closeInlineStudio(tester);
      expect(find.byType(ResourceStudioPage), findsNothing);
      expect(find.byType(ResourceLibraryScreen), findsOneWidget);
      expect(find.text('桌面蓝图资源'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'desktop existing-resource editing stays inline and returns to the '
        'inline detail unchanged', (tester) async {
      await boot(
        tester,
        suggestedName: '桌面已有资源',
        width: desktopWidth,
        height: desktopHeight,
      );
      await openAiForm(tester);
      await fillAiForm(tester, '桌面已有资源');
      await tapKey(tester, const Key('ai-create-submit-button'));
      await _waitFor(tester, find.byType(ResourceStudioPage));
      await expectInlineStudio(tester);

      // Closing the creation Studio returns to the stable library, which at
      // desktop width shows the resource's detail inline (not pushed).
      await closeInlineStudio(tester);
      await _waitFor(tester, find.byType(ResourceLibraryDetailPage));
      expectNoCreationFlowVisible();

      // Re-open the existing resource's editor inline and close it again.
      await tapKey(tester, const Key('resource-open-studio-button'));
      await _waitFor(tester, find.byType(ResourceStudioPage));
      await expectInlineStudio(tester);

      await closeInlineStudio(tester);
      expect(find.byType(ResourceLibraryDetailPage), findsOneWidget);
      expect(find.byType(ResourceLibraryScreen), findsOneWidget);
      expectNoCreationFlowVisible();
      expect(tester.takeException(), isNull);
    });
  });

  group('Created resource detail and existing-resource editing', () {
    testWidgets('manual creation -> created detail -> Back -> Library',
        (tester) async {
      await boot(tester);

      await tester.tap(find.byKey(const Key('resource-create-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('create-choice-manual')));
      await tester.pumpAndSettle();
      expect(find.byType(ResourceManualCreatePage), findsOneWidget);
      await tester.enterText(
          find.byKey(const Key('manual-create-name-field')), '手动创建资源');
      await tester.pump();
      await tapKey(tester, const Key('manual-create-submit-button'));

      // Manual creation persists the resource and opens its detail page.
      await _waitFor(tester, find.byType(ResourceLibraryDetailPage));
      await _waitFor(tester, find.text('手动创建资源'));
      expectNoCreationFlowVisible();

      await localizedPageBack(tester);
      await _waitFor(tester, find.byKey(const Key('resource-list')));
      expect(find.byType(ResourceLibraryDetailPage), findsNothing);
      expectNoCreationFlowVisible();
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'existing resource edit: detail -> Studio -> Back to detail -> '
        'Library (ordinary Back unchanged)', (tester) async {
      await boot(tester, suggestedName: '已有资源');
      await openAiForm(tester);
      await fillAiForm(tester, '已有资源');
      await tapKey(tester, const Key('ai-create-submit-button'));
      await _waitFor(tester, find.byType(ResourceStudioPage));
      await localizedPageBack(tester);
      await _waitFor(tester, find.text('已有资源'));

      // Open the created resource's detail from the library (a normal, stable
      // navigation), then its Studio (edit), and verify ordinary Back.
      await tester.tap(find.text('已有资源').first);
      await tester.pumpAndSettle();
      await _waitFor(tester, find.byType(ResourceLibraryDetailPage));
      await tapKey(tester, const Key('resource-open-studio-button'));
      await _waitFor(tester, find.byType(ResourceStudioPage));

      await backFrom(tester, find.byType(ResourceStudioPage));
      await _waitFor(tester, find.byType(ResourceLibraryDetailPage));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(ResourceStudioPage), findsNothing);
      expectNoCreationFlowVisible();

      await backFrom(tester, find.byType(ResourceLibraryDetailPage));
      await _waitFor(tester, find.byKey(const Key('resource-list')));
      expect(tester.takeException(), isNull);
    });
  });

  group('Unfinished creation keeps Back/Cancel behaviour', () {
    testWidgets(
        'backing out of the AI form returns to the hub then library, '
        'creating nothing', (tester) async {
      await boot(tester);
      await openAiForm(tester);
      await fillAiForm(tester, '未完成资源');

      await localizedPageBack(tester);
      await tester.pumpAndSettle();
      expect(find.byType(ResourceCreatePage), findsOneWidget);
      expect(find.byType(ResourceAiCreatePage), findsNothing);

      await localizedPageBack(tester);
      await tester.pumpAndSettle();
      await _waitFor(tester, find.text('还没有资源'));
      expect(find.byType(ResourceCreatePage), findsNothing);

      final db = await tester.runAsync(() => DatabaseService.database);
      final resources = await tester.runAsync(() => db!.query('resources'));
      expect(resources, isEmpty,
          reason: 'backing out must not persist a resource');
      expect(tester.takeException(), isNull);
    });
  });
}

Future<void> _waitFor(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 400; attempt++) {
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
  _AiResponses({this.suggestedName = 'AI新资源'});

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
    const content = 'AI生成正文：山海之间的城市和居民。';
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
