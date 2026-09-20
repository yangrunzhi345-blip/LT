import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:lt_dialogue/application/llm/llm_gateway.dart';
import 'package:lt_dialogue/models/llm_task.dart';
import 'package:lt_dialogue/services/llm_service.dart';
import 'package:lt_dialogue/core/router/app_router.dart';
import 'package:lt_dialogue/application/resources/assembly_readiness_repository.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/core/widgets/app_select.dart';
import 'package:lt_dialogue/domain/resources/resource_limits.dart';
import 'package:lt_dialogue/features/resource_library/presentation/screens/resource_library_detail_page.dart';
import 'package:lt_dialogue/features/resource_library/presentation/screens/resource_library_screen.dart';
import 'package:lt_dialogue/features/resource_library/presentation/screens/resource_manual_create_page.dart';
import 'package:lt_dialogue/features/resource_library/domain/models/resource_library_view_state.dart';
import 'package:lt_dialogue/features/resource_studio/presentation/pages/resource_studio_page.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository_impl.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository.dart';
import 'package:lt_dialogue/features/resource_studio/domain/models/section_control_view_state.dart';
import 'package:lt_dialogue/features/resource_studio/presentation/widgets/resource_studio_section_controls.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lt_dialogue/core/widgets/app_text_field.dart';
import '../helpers/responsive_test_helper.dart';

Finder _fieldByLabel(String label) => find.descendant(
      of: find.widgetWithText(AppTextField, label),
      matching: find.byType(TextField),
    );

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
    directory = await Directory.systemTemp.createTemp('lt_p11_widget_');
    DatabaseService.customDbDir = directory.path;
    await DatabaseService.resetDatabase();
    await DatabaseService.database;
  });
  tearDown(() async {
    await DatabaseService.resetDatabase();
    DatabaseService.customDbDir = null;
    await directory.delete(recursive: true);
  });

  group('Phase 11 production assembly', () {
    testWidgets(
        'should move a resource to trash, refresh, and restore through production wiring',
        (tester) async {
      setViewport(tester, width: 390, height: 844);
      final repository = ResourceTreeRepositoryImpl(
        getDb: () => DatabaseService.database,
      );
      const resourceId = ResourceId('resource-delete-production');
      await tester.runAsync(
        () => repository.createResourceTree(
          const ResourceTreeDraft(
            id: resourceId,
            type: ResourceType.worldview,
            name: '待删除的生产资源',
            sections: <ResourceTreeSectionDraft>[
              ResourceTreeSectionDraft(
                title: '概览',
                parts: <ResourceTreePartDraft>[
                  ResourceTreePartDraft(title: '正文', content: '真实内容'),
                ],
              ),
            ],
          ),
        ),
      );

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            initialRoute: '/library',
            onGenerateRoute: AppRouter.onGenerateRoute,
          ),
        ),
      );
      await _waitFor(tester, find.text('待删除的生产资源'));
      await tester.tap(
        find.byKey(
          const ValueKey<String>('resource-card-resource-delete-production'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('resource-move-to-trash-button')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '移入回收站'));
      await _waitFor(tester, find.text('还没有资源'));

      final db = await tester.runAsync(() => DatabaseService.database);
      final resourceRows = await tester.runAsync(
        () => db!.query(
          'resources',
          where: 'id = ?',
          whereArgs: <Object?>[resourceId.value],
        ),
      );
      final trashRows = await tester.runAsync(
        () => db!.query(
          'resource_trash',
          where: 'node_id = ? AND restored_at IS NULL',
          whereArgs: <Object?>[resourceId.value],
        ),
      );
      expect(resourceRows!.single['deleted_at'], isNotNull);
      expect(trashRows, hasLength(1));

      await tester.tap(find.byKey(const Key('resource-trash-button')));
      await _waitFor(tester, find.text('待删除的生产资源'));
      await tester.tap(find.widgetWithText(TextButton, '恢复'));
      await _waitFor(tester, find.text('恢复到原位置'));
      final restoredRows = await tester.runAsync(
        () => db!.query(
          'resources',
          where: 'id = ?',
          whereArgs: <Object?>[resourceId.value],
        ),
      );
      expect(restoredRows!.single['deleted_at'], isNull);

      await tester.tap(find.byTooltip('返回'));
      await _waitFor(tester, find.text('待删除的生产资源'));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets(
        'should refresh immediately after production AI creation returns',
        (tester) async {
      setViewport(tester, width: 390, height: 844);
      final container = ProviderContainer(overrides: [
        llmGatewayProvider.overrideWithValue(_AiResponses()),
      ]);
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
          )));
      await _waitFor(tester, find.text('还没有资源'));
      await tester.tap(find.byKey(const Key('resource-create-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('AI 创建'));
      await tester.pumpAndSettle();
      await tester.enterText(_fieldByLabel('名称'), 'AI新资源');
      await tester.enterText(_fieldByLabel('粘贴参考内容'), '山海之间的城市和居民');
      await tester.tap(find.text('开始创建'));
      await _waitFor(tester, find.text('编辑正文'));
      await _waitFor(tester, find.textContaining('AI生成正文'));
      await tester.pageBack();
      await _waitFor(tester, find.byKey(const Key('resource-grid')));
      expect(find.text('AI新资源'), findsOneWidget);
      final rows = await tester.runAsync(
          () async => (await DatabaseService.database).query('resource_parts'));
      expect(rows!.single['content'], 'AI生成正文：山海之间的城市和居民。');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
    testWidgets('should submit with keyboard large text and safe area at 320',
        (tester) async {
      setViewport(tester, width: 320, height: 568);
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 16);
      tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 16);
      await tester.pumpWidget(ProviderScope(
          child: MaterialApp(
        initialRoute: '/library',
        onGenerateRoute: AppRouter.onGenerateRoute,
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!),
      )));
      await _waitFor(tester, find.text('还没有资源'));
      final libraryContext = tester.element(find.byType(ResourceLibraryScreen));
      expect(MediaQuery.sizeOf(libraryContext), const Size(320, 568));
      expect(MediaQuery.paddingOf(libraryContext).top, 24);
      await tester.tap(find.byKey(const Key('resource-create-button')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('手动创建'));
      await tester.tap(find.text('手动创建'));
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 240);
      await tester.pumpAndSettle();
      final field = _fieldByLabel('名称');
      expect(
          MediaQuery.viewInsetsOf(
                  tester.element(find.byType(ResourceManualCreatePage)))
              .bottom,
          240);
      await tester.ensureVisible(field);
      await tester.enterText(field, '长名称 Long Resource Name 用于小屏真实提交');
      final summary = _fieldByLabel('简介（可选）');
      await tester.ensureVisible(summary);
      await tester.enterText(summary, '安全区和软键盘同时存在时，滚动填写并提交。');
      final pageScrollable = find
          .descendant(
            of: find.byType(SingleChildScrollView),
            matching: find.byType(Scrollable),
          )
          .first;
      final scrollableState = tester.state<ScrollableState>(pageScrollable);
      scrollableState.position.jumpTo(scrollableState.position.maxScrollExtent);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '创建'));
      await _waitFor(tester, find.byType(ResourceLibraryDetailPage));
      expect(tester.takeException(), isNull);
      final rows = await tester.runAsync(
          () async => (await DatabaseService.database).query('resources'));
      expect(rows!.single['name'], '长名称 Long Resource Name 用于小屏真实提交');
      await tester.pumpWidget(const SizedBox.shrink());
    });
    for (final content in <String?>[
      null,
      '',
      '字' * (ResourceLimits.maxPartCharacters + 1)
    ]) {
      testWidgets(
          'should map real validation for ${content == null ? 'empty section' : content.isEmpty ? 'missing body' : 'oversize body'}',
          (tester) async {
        setViewport(tester, width: 320, height: 568);
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final repository =
            ResourceTreeRepositoryImpl(getDb: () => DatabaseService.database);
        final id = await tester
            .runAsync(() => repository.createResourceTree(ResourceTreeDraft(
                  id: const ResourceId('validation-resource'),
                  type: ResourceType.worldview,
                  name: '校验资源',
                  sections: [
                    ResourceTreeSectionDraft(title: '章节', parts: [
                      if (content != null)
                        ResourceTreePartDraft(title: '正文', content: content),
                    ])
                  ],
                )));
        final tree = await tester.runAsync(() => repository.readTree(id!));
        final runtime = container.read(sectionControlRuntimeProvider);
        await tester
            .runAsync(() => runtime.validateSection(tree!.sections.single.id));
        final entry = await tester
            .runAsync(() => runtime.readSection(tree!.sections.single.id));
        expect(entry!.validationMessage, isNotEmpty);
        await tester.pumpWidget(MaterialApp(
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.6)),
              child: child!),
          home: Scaffold(
              body: SafeArea(
                  child: SingleChildScrollView(
                      child: ResourceStudioSectionControls(
            state: SectionControlViewState(
                status: SectionControlViewStatus.ready,
                resourceId: id,
                entries: [entry],
                totalCount: 1),
            onRefresh: () {},
            onLoadMore: () {},
            onCreate: () {},
            onRename: (_, __) {},
            onDelete: (_) {},
            onMove: (_, __) {},
            onValidate: (_) {},
            onRegenerate: (_) {},
          )))),
        ));
        await tester.pumpAndSettle();
        for (final term in ['Section', 'Part', 'ResourceTree']) {
          expect(find.textContaining(term), findsNothing);
        }
        expect(
            find.textContaining(content == null
                ? '没有任何 段落'
                : content.isEmpty
                    ? '尚未生成正文'
                    : '超出单 段落 上限'),
            findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
    for (final type in ResourceType.values) {
      testWidgets('should create edit save and reload ${type.name}',
          (tester) async {
        setViewport(tester, width: 390, height: 844);
        await tester.pumpWidget(const ProviderScope(
          child: MaterialApp(
            initialRoute: '/library',
            onGenerateRoute: AppRouter.onGenerateRoute,
          ),
        ));
        await _waitFor(tester, find.text('还没有资源'));
        await tester.enterText(
            find.byKey(const Key('resource-search-field')), '测试');
        await tester.tap(find.text(switch (type) {
          ResourceType.worldview => '世界观',
          ResourceType.character => '角色',
          ResourceType.npc => 'NPC',
        }));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('resource-create-button')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('手动创建'));
        await tester.pumpAndSettle();
        final label = switch (type) {
          ResourceType.worldview => '世界观',
          ResourceType.character => '角色',
          ResourceType.npc => 'NPC',
        };
        await tester.tap(find.byType(AppSelect<ResourceType>));
        await tester.pumpAndSettle();
        await tester.tap(find.text(label).last);
        await tester.pumpAndSettle();
        await tester.enterText(
          _fieldByLabel('名称'),
          '测试${type.name}',
        );
        await tester.tap(find.widgetWithText(FilledButton, '创建'));
        await _waitFor(tester, find.byType(ResourceLibraryDetailPage));

        final repository = ResourceTreeRepositoryImpl(
          getDb: () => DatabaseService.database,
        );
        final db = await tester.runAsync(() => DatabaseService.database);
        final rows = await tester.runAsync(() => db!.query('resources'));
        final id = ResourceId(rows!.single['id']! as String);
        final initial = await tester.runAsync(() => repository.readTree(id));
        expect(initial!.sections, hasLength(1));
        expect(initial.parts, hasLength(1));
        expect(initial.parts.single.content, isEmpty);

        await tester.tap(find.text('进入创作工作台'));
        await _waitFor(tester, find.text('编辑正文'));
        final container = ProviderScope.containerOf(
            tester.element(find.byType(ResourceStudioPage)));
        await tester.runAsync(() async {
          await db!.transaction((txn) => container
              .read(assemblyReadinessRepositoryProvider)
              .writeInTransaction(
                txn,
                AssemblyReadinessRecord(
                    resourceId: id.value, state: ReadinessState.ready),
              ));
        });
        await tester.ensureVisible(find.text('编辑正文'));
        await tester.tap(find.text('编辑正文'));
        await _waitFor(tester, find.byType(TextField));
        await tester.ensureVisible(find.byType(TextField));
        await tester.enterText(find.byType(TextField), '真实保存的${type.name}正文');
        await tester.ensureVisible(find.text('立即保存'));
        await tester.tap(find.text('立即保存'));
        await _waitFor(tester, find.textContaining('已自动保存'));
        final saved = await tester.runAsync(() => repository.readTree(id));
        expect(saved!.parts.single.content, '真实保存的${type.name}正文');
        await tester.tap(find.text('完成编辑'));
        await _waitFor(tester, find.text('编辑正文'));
        await tester.pageBack();
        await _waitFor(tester, find.byType(ResourceLibraryScreen));
        await _waitFor(tester, find.text('测试${type.name}'));
        final readiness = await tester.runAsync(() =>
            container.read(assemblyReadinessRepositoryProvider).read(id.value));
        expect(readiness!.state, ReadinessState.ready);
        expect(find.text('已准备完成'), findsOneWidget);
        expect(
            tester
                .widget<EditableText>(find.descendant(
                    of: find.byKey(const Key('resource-search-field')),
                    matching: find.byType(EditableText)))
                .controller
                .text,
            '测试');
        final filter = tester.widget<SegmentedButton<ResourceLibraryFilter>>(
            find.byKey(const Key('resource-filter')));
        expect(filter.selected.single.name, type.name);
        expect(find.byType(ResourceStudioPage), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      });
    }
  });
}

// SQLite uses real asynchronous I/O; yield to it outside the fake widget clock
// and stop as soon as the observable UI condition is true.
Future<void> _waitFor(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 200; attempt++) {
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

// Only the external model response is controlled. Pipeline, SQLite,
// repositories, runtime, providers and navigation remain production code.
final class _AiResponses implements LlmGateway {
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
        'suggestedName': 'AI新资源',
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
