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
import 'package:lt_dialogue/core/widgets/app_select.dart';
import 'package:lt_dialogue/core/widgets/app_text_field.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_limits.dart';
import 'package:lt_dialogue/features/resource_library/presentation/screens/resource_ai_create_page.dart';
import 'package:lt_dialogue/features/resource_library/presentation/screens/resource_library_screen.dart';
import 'package:lt_dialogue/features/resource_studio/presentation/pages/resource_studio_page.dart';
import 'package:lt_dialogue/models/llm_task.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/llm_service.dart';

import '../helpers/responsive_test_helper.dart';

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
  await tester.ensureVisible(submit);
  await tester.pumpAndSettle();
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
      await tester.tap(find.byKey(const Key('ai-create-submit-button')));

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

    testWidgets('returning from the Studio refreshes the library grid',
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

      await tester.pageBack();
      await _waitFor(tester, find.byKey(const Key('resource-grid')));
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
      await _waitFor(tester, find.text('编辑正文'));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });
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
