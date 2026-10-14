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
import 'package:lt_dialogue/application/resources/blueprint_budget_normalizer.dart';
import 'package:lt_dialogue/application/resources/part_generation_coordinator.dart';
import 'package:lt_dialogue/application/resources/resource_blueprint_repository.dart';
import 'package:lt_dialogue/application/resources/resource_creation_contracts.dart';
import 'package:lt_dialogue/application/resources/resource_creation_pipeline.dart';
import 'package:lt_dialogue/application/resources/resource_generation_task_repository.dart';
import 'package:lt_dialogue/application/resources/streaming_generation_session_repository.dart';
import 'package:lt_dialogue/core/router/app_router.dart';
import 'package:lt_dialogue/core/theme/app_theme.dart';
import 'package:lt_dialogue/core/widgets/app_text_field.dart';
import 'package:lt_dialogue/domain/resources/resource_blueprint.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/streaming_generation_runtime_contracts.dart';
import 'package:lt_dialogue/features/resource_library/presentation/screens/resource_blueprint_review_page.dart';
import 'package:lt_dialogue/features/resource_studio/presentation/pages/resource_studio_page.dart';
import 'package:lt_dialogue/features/settings/presentation/widgets/generation_elastic_section.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';
import 'package:lt_dialogue/models/llm_task.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/llm_service.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository_impl.dart';

import '../helpers/responsive_test_helper.dart';
import '../helpers/r01_streaming_fixture.dart';

/// E50 弹性预算 UI→Controller→Repository→SQLite 端到端验收（ADR-0003）。
///
/// 真实 SQLite、真实 Provider/Controller/Repository/Pipeline；只替换模型网络输出
/// （蓝图规划与正文）。覆盖：全局 20% 与资源独立 50% 的优先级、直接创建、蓝图审阅、
/// 确认冻结、失败重试、重启恢复、旧任务不随设置漂移、UI T/E/C 与实际冻结一致、
/// 320px 与大字体边界。契约阈值为 U6 未决项，本测试不引入产品默认值。
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
    directory = await Directory.systemTemp.createTemp('lt_e50_');
    DatabaseService.customDbDir = directory.path;
    await DatabaseService.resetDatabase();
    await DatabaseService.database;
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    DatabaseService.customDbDir = null;
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  Widget wrap(Widget home, {double textScale = 1}) => MaterialApp(
        locale: const Locale('zh'),
        theme: AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      );

  Future<Database> db() => DatabaseService.database;

  Future<void> setGlobal(int percent) async {
    final database = await db();
    await database.insert(
        'settings',
        {
          'key': 'generation_elastic_percent',
          'value': '$percent',
          'updated_at': ''
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int?> frozenPercent(String blueprintId) async {
    final rows = await (await db()).query('resource_blueprints',
        columns: ['elastic_percent'],
        where: 'blueprint_id = ?',
        whereArgs: [blueprintId],
        limit: 1);
    return (rows.single['elastic_percent'] as num?)?.toInt();
  }

  String envelope(int? percent) => ResourceCreationOriginEnvelope(
        origin: 'test',
        libraryMode: 'adventure',
        elasticPercent: percent,
      ).encode();

  /// Seeds a real confirmed run: creation session → blueprint → confirm (freezes
  /// elastic_percent) → streaming session. `resourceOverride` creates the target
  /// resource first so confirm resolves the resource-level override.
  Future<({ResourceId id, String blueprintId, String streamingSessionId})>
      seedRun({
    required String key,
    required int target,
    int? resourceOverride,
    int? sessionOverride,
    int parts = 4,
  }) async {
    final treeRepo = ResourceTreeRepositoryImpl(getDb: () async => db());
    final pipeline = ResourceCreationPipeline(
        getDb: () async => db(),
        treeRepository: treeRepo,
        hasAiCredentials: () => true);

    ResourceId? explicitResourceId;
    String? expectedToken;
    if (resourceOverride != null) {
      final resource = await treeRepo.createResource(
        type: ResourceType.character,
        name: 'E50 资源 $key',
        metadata: const {},
      );
      await treeRepo.updateGenerationElasticOverride(
          id: resource.id,
          expectedUpdatedAt:
              (await treeRepo.readNodeState(resource.id))!.updatedAt,
          percent: resourceOverride);
      explicitResourceId = resource.id;
      expectedToken = (await treeRepo.readNodeState(resource.id))!.updatedAt;
    }

    final session = await pipeline.create(ResourceCreationRequest(
        resourceType: ResourceType.character,
        method: CreationMethod.aiReference,
        name: 'E50 $key',
        referenceSource: ReferenceSource.text('端到端验收参考'),
        targetCharacters: target,
        idempotencyKey: key,
        origin: envelope(sessionOverride)));
    final blueprint = BlueprintBudgetNormalizer.normalizeToGenerationTarget(
        ResourceBlueprint(
            blueprintId: 'bp_$key',
            sessionId: session.sessionId!,
            resourceType: ResourceType.character,
            suggestedName: 'E50 $key',
            summary: '',
            targetCapacity: target,
            sections: [
              BlueprintSection(id: 's', title: '背景', parts: [
                for (var i = 0; i < parts; i++)
                  BlueprintPart(
                      id: 'p$i',
                      sectionId: 's',
                      title: '背景$i',
                      generationGoal: '角色背景',
                      estimatedLength: target ~/ parts),
              ])
            ]),
        targetCharacters: target);
    final bpRepo = ResourceBlueprintRepositoryImpl(
        getDb: () async => db(), treeRepository: treeRepo);
    await bpRepo.saveBlueprint(blueprint);
    final confirmed = await bpRepo.confirmBlueprint(
        blueprintId: blueprint.blueprintId,
        explicitResourceId: explicitResourceId,
        expectedResourceUpdatedAt: expectedToken);

    final sessions =
        StreamingGenerationSessionRepositoryImpl(getDb: () async => db());
    final streamingId = 'gen_$key';
    await sessions.createSession(StreamingGenerationSession(
      sessionId: streamingId,
      resourceId: confirmed.resourceId,
      blueprintId: blueprint.blueprintId,
      creationSessionId: session.sessionId!,
      status: StreamingLifecycleStatus.paused,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      totalPartsCount: parts,
    ));
    return (
      id: confirmed.resourceId,
      blueprintId: blueprint.blueprintId,
      streamingSessionId: streamingId,
    );
  }

  Future<void> pumpStudio(WidgetTester tester, ProviderContainer container,
      String sessionId) async {
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: wrap(ResourceStudioPage(sessionId: sessionId)),
    ));
    await tester.pumpAndSettle();
  }

  /// Asserts the Studio summary row labelled [label] shows [value]. Scoped to
  /// the row so a coincident value (e.g. remaining == ceiling before spending)
  /// cannot satisfy the assertion by accident.
  void expectBudgetRow(WidgetTester tester, String label, String value) {
    final rows =
        find.ancestor(of: find.text(label), matching: find.byType(Row));
    expect(rows, findsWidgets, reason: 'summary row $label missing');
    expect(
        find.descendant(of: rows, matching: find.text(value)), findsOneWidget,
        reason: '$label should show $value');
  }

  group('global setting widget → SQLite (SettingsProvider persistence)', () {
    testWidgets('numeric input persists and reloads from the settings table',
        (tester) async {
      setViewport(tester, width: 390, height: 844);
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: wrap(const Scaffold(body: GenerationElasticSection())),
      ));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('settings-elastic-input')), '50');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      final rows = await (await db()).query('settings',
          where: 'key = ?', whereArgs: ['generation_elastic_percent']);
      expect(rows, hasLength(1));
      expect(rows.single['value'], '50');
      // The live value label reflects the persisted 50%.
      expect(find.text('50%'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  group('resource override widget → SQLite metadata (studio chain)', () {
    testWidgets(
        'independent 50% persists to resources.metadata_json; frozen run E is unchanged',
        (tester) async {
      setViewport(tester, width: 390, height: 844);
      await setGlobal(20);
      final stack = await seedRun(key: 'studio_ov', target: 8000);
      final container = ProviderContainer();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
      });

      await pumpStudio(tester, container, stack.streamingSessionId);
      // The run is frozen at the global 20%.
      expect(find.text('生效弹性'), findsWidgets);
      expect(find.text('20%'), findsOneWidget);

      await tester.ensureVisible(
          find.byKey(const Key('studio-elastic-mode-segmented')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('独立设置'));
      await tester.pumpAndSettle();

      // Switching to independent freezes the default 20% into the resource row.
      var meta = await readMetadata(stack.id.value);
      expect(meta[ResourceTreeSchema.metadataGenerationElasticPercentKey], 20);

      final dropdown = find.byKey(const Key('studio-elastic-percent-dropdown'));
      await tester.ensureVisible(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(dropdown, warnIfMissed: false);
      await tester.pumpAndSettle();
      await tester.dragUntilVisible(
        find.text('50%'),
        find.byType(ListView).last,
        const Offset(0, -80),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('50%').last, warnIfMissed: false);
      await tester.pumpAndSettle();

      meta = await readMetadata(stack.id.value);
      expect(meta[ResourceTreeSchema.metadataGenerationElasticPercentKey], 50,
          reason: 'UI 独立设置必须写入真实 resources.metadata_json');

      // The already-frozen run keeps E=20: the summary must not drift.
      expect(await frozenPercent(stack.blueprintId), 20);
      expect(find.text('20%'), findsOneWidget, reason: '已冻结运行的摘要 E 不受后续资源覆盖影响');

      // Back to inherit removes the override.
      await tester.ensureVisible(find.text('继承全局'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('继承全局'), warnIfMissed: false);
      await tester.pumpAndSettle();
      meta = await readMetadata(stack.id.value);
      expect(
          meta.containsKey(
              ResourceTreeSchema.metadataGenerationElasticPercentKey),
          isFalse);
      expect(tester.takeException(), isNull);
    });
  });

  group('priority: global 20 vs resource 50 vs session override freeze', () {
    testWidgets('resource 50 beats global 20 and the summary shows T/E/C',
        (tester) async {
      setViewport(tester, width: 390, height: 844);
      await setGlobal(20);
      final stack =
          await seedRun(key: 'pri_res', target: 8000, resourceOverride: 50);
      expect(await frozenPercent(stack.blueprintId), 50);

      final container = ProviderContainer();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
      });
      await pumpStudio(tester, container, stack.streamingSessionId);

      // T = 8000, E = 50%, C = min(floor(8000*1.5), 24000) = 12000.
      expectBudgetRow(tester, '目标字数', '8000 字');
      expectBudgetRow(tester, '生效弹性', '50%');
      expectBudgetRow(tester, '允许生成上界', '12000 字');
      expect(tester.takeException(), isNull);
    });

    testWidgets('session override 35 beats resource 50', (tester) async {
      setViewport(tester, width: 390, height: 844);
      await setGlobal(20);
      final stack = await seedRun(
          key: 'pri_sess',
          target: 8000,
          resourceOverride: 50,
          sessionOverride: 35);
      expect(await frozenPercent(stack.blueprintId), 35);

      final container = ProviderContainer();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
      });
      await pumpStudio(tester, container, stack.streamingSessionId);
      // C = floor(8000*1.35) = 10800.
      expectBudgetRow(tester, '生效弹性', '35%');
      expectBudgetRow(tester, '允许生成上界', '10800 字');
    });

    testWidgets('global 20 is used when neither override exists',
        (tester) async {
      setViewport(tester, width: 390, height: 844);
      await setGlobal(20);
      final stack = await seedRun(key: 'pri_glob', target: 8000);
      expect(await frozenPercent(stack.blueprintId), 20);

      final container = ProviderContainer();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
      });
      await pumpStudio(tester, container, stack.streamingSessionId);
      // C = floor(8000*1.2) = 9600.
      expectBudgetRow(tester, '生效弹性', '20%');
      expectBudgetRow(tester, '允许生成上界', '9600 字');
    });
  });

  group('frozen snapshot survives settings change', () {
    testWidgets('changing the global after confirm never reaches the run',
        (tester) async {
      setViewport(tester, width: 390, height: 844);
      await setGlobal(20);
      final stack = await seedRun(key: 'freeze_guard', target: 8000);
      expect(await frozenPercent(stack.blueprintId), 20);

      // A later global change must not move the frozen run.
      await setGlobal(50);
      expect(await frozenPercent(stack.blueprintId), 20);

      final container = ProviderContainer();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
      });
      await pumpStudio(tester, container, stack.streamingSessionId);
      expectBudgetRow(tester, '生效弹性', '20%');
      expectBudgetRow(tester, '允许生成上界', '9600 字');
    });
  });

  group('second creation path: blueprint review freezes the run', () {
    testWidgets('plan → review → confirm freezes the global percent',
        (tester) async {
      setViewport(tester, width: 390, height: 844);
      await setGlobal(45);
      final container = ProviderContainer(
        overrides: [llmGatewayProvider.overrideWithValue(_E50Gateway())],
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

      await _enterByLabel(tester, '名称', '审阅冻结资源');
      await _enterByLabel(tester, '粘贴参考内容', '山海之间的城市和居民');
      final targetInput =
          find.byKey(const ValueKey('ai_creation_target_words_input'));
      await tester.ensureVisible(targetInput);
      await tester.pumpAndSettle();
      await tester.enterText(targetInput, '10000');
      await tester
          .tap(find.byKey(const ValueKey('ai_creation_target_words_confirm')));
      await tester.pumpAndSettle();

      final plan = find.byKey(const Key('ai-create-plan-button'));
      await tester.ensureVisible(plan);
      await tester.pumpAndSettle();
      await tester.tap(plan);
      await _waitFor(tester, find.byType(ResourceBlueprintReviewPage));

      final confirm = find.text('确认并开始生成');
      await tester.ensureVisible(confirm);
      await tester.pumpAndSettle();
      await tester.tap(confirm);
      await _waitFor(tester, find.byType(ResourceStudioPage));

      final rows = await (await db())
          .query('resource_blueprints', columns: ['elastic_percent']);
      expect(rows, hasLength(1));
      expect(rows.single['elastic_percent'], 45, reason: '蓝图审阅确认路径必须冻结全局 45%');
      expect(tester.takeException(), isNull);
    });
  });

  group('generate + fail-retry use the frozen ceiling', () {
    test('a real retry commits within the frozen C after settings drift',
        () async {
      await setGlobal(20);
      final stack = await seedRun(
          key: 'retry_frozen', target: 8000, resourceOverride: 50);
      final tasks = PartGenerationTaskRepositoryImpl(getDb: () async => db());
      final ready = await tasks.findReadyTasks(stack.id.value);

      // Three completed siblings carry 9000; C(50%) = 12000 leaves the tail
      // exactly 3000.
      for (var i = 0; i < 3; i++) {
        await (await db()).update('resource_parts', {'content': '原' * 3000},
            where: 'id = ?', whereArgs: [ready[i].partId]);
        await (await db()).update(
            'resource_generation_tasks', {'status': 'completed'},
            where: 'task_id = ?', whereArgs: [ready[i].taskId]);
      }

      // Drift the global and the resource override AFTER the run was frozen.
      await setGlobal(0);
      final treeRepo = ResourceTreeRepositoryImpl(getDb: () async => db());
      await treeRepo.updateGenerationElasticOverride(
          id: stack.id,
          expectedUpdatedAt:
              (await treeRepo.readNodeState(stack.id))!.updatedAt,
          percent: 0);

      var calls = 0;
      final coordinator = PartGenerationCoordinator(
        taskRepository: tasks,
        blueprintRepository: ResourceBlueprintRepositoryImpl(
            getDb: () async => db(), treeRepository: treeRepo),
        pipeline: ResourceCreationPipeline(
            getDb: () async => db(),
            treeRepository: treeRepo,
            hasAiCredentials: () => true),
        completer: r01Completer('文' * 3000, onCall: () => calls++),
      );
      expect(
          await coordinator.retrySinglePart(
              blueprintId: stack.blueprintId, partId: ready.last.partId),
          isTrue);
      expect(calls, 1);

      final contents =
          await tasks.getPartsContent(ready.map((t) => t.partId).toList());
      final total = contents.values
          .fold<int>(0, (sum, value) => sum + value.content.length);
      expect(total, 12000,
          reason: '真实重试仍以冻结 50% 的 C=12000 为准（若用漂移后的 0% 会以 8000 拒绝）');
    });
  });

  group('restart recovery keeps the frozen snapshot', () {
    test('recoverInterruptedTasks requeues without rewriting the budget',
        () async {
      await setGlobal(20);
      final stack =
          await seedRun(key: 'recover', target: 8000, resourceOverride: 50);
      final tasks = PartGenerationTaskRepositoryImpl(getDb: () async => db());
      final ready = await tasks.findReadyTasks(stack.id.value);

      // Simulate a crash mid-attempt: the task is left stuck 'generating'.
      await tasks.startAttempt(
          taskId: ready.first.taskId, generationId: 'gen_crash');
      expect((await tasks.findTask(ready.first.taskId))!.status, 'generating');

      final recovered = await tasks.recoverInterruptedTasks(stack.id.value);
      expect(recovered, greaterThan(0));
      expect((await tasks.findTask(ready.first.taskId))!.status, 'ready',
          reason: '中断任务恢复为 ready，可重排');

      final allocation = await tasks.budgetAllocation(
          resourceId: stack.id.value,
          blueprintId: stack.blueprintId,
          partId: ready.first.partId);
      expect(allocation!.ceiling, 12000, reason: '恢复不重写预算快照');
      expect(await frozenPercent(stack.blueprintId), 50);
    });
  });

  group('direct create path freezes the run and starts generation', () {
    testWidgets('direct submit freezes the global percent at confirm',
        (tester) async {
      setViewport(tester, width: 390, height: 844);
      await setGlobal(20);
      final container = ProviderContainer(
        overrides: [llmGatewayProvider.overrideWithValue(_E50Gateway())],
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

      await _enterByLabel(tester, '名称', '直接创建资源');
      await _enterByLabel(tester, '粘贴参考内容', '山海之间的城市和居民');
      final targetInput =
          find.byKey(const ValueKey('ai_creation_target_words_input'));
      await tester.ensureVisible(targetInput);
      await tester.pumpAndSettle();
      await tester.enterText(targetInput, '10000');
      await tester
          .tap(find.byKey(const ValueKey('ai_creation_target_words_confirm')));
      await tester.pumpAndSettle();

      // Direct submit — the non-review creation path.
      final submit = find.byKey(const Key('ai-create-submit-button'));
      await tester.ensureVisible(submit);
      await tester.pumpAndSettle();
      await tester.tap(submit);
      await _waitFor(tester, find.byType(ResourceStudioPage));

      final rows = await (await db())
          .query('resource_blueprints', columns: ['elastic_percent']);
      expect(rows, hasLength(1));
      expect(rows.single['elastic_percent'], 20, reason: '直接创建路径也必须冻结全局 20%');
      expect(tester.takeException(), isNull);
    });
  });

  group('responsive: 320px and large font', () {
    for (final scale in [1.0, 1.8]) {
      testWidgets('studio override + summary fit at 320px, textScale $scale',
          (tester) async {
        setViewport(tester, width: 320, height: 568);
        await setGlobal(20);
        final stack = await seedRun(key: 'resp_$scale', target: 8000);
        final container = ProviderContainer();
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          container.dispose();
        });

        // Independent override so both the segmented control and dropdown render.
        await pumpStudio(tester, container, stack.streamingSessionId);
        await tester.ensureVisible(
            find.byKey(const Key('studio-elastic-mode-segmented')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('独立设置'));
        await tester.pumpAndSettle();
        await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: wrap(ResourceStudioPage(sessionId: stack.streamingSessionId),
              textScale: scale),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });
}

Future<Map<String, Object?>> readMetadata(String resourceId) async {
  final rows = await (await DatabaseService.database).query('resources',
      columns: ['metadata_json'],
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [resourceId],
      limit: 1);
  final raw = rows.single['metadata_json']?.toString() ?? '{}';
  return (jsonDecode(raw) as Map).cast<String, Object?>();
}

Finder _fieldByLabel(String label) => find.descendant(
      of: find.widgetWithText(AppTextField, label),
      matching: find.byType(TextField),
    );

Future<void> _enterByLabel(
    WidgetTester tester, String label, String value) async {
  final field = _fieldByLabel(label);
  await tester.enterText(field.first, value);
  await tester.pump();
}

Future<void> _waitFor(WidgetTester tester, Finder finder,
    {int maxPumps = 40}) async {
  for (var i = 0; i < maxPumps; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for $finder');
}

/// Plans one section/part and yields one valid Part body; no real model.
final class _E50Gateway implements LlmGateway {
  @override
  bool get isConfigured => true;

  @override
  Future<String> rawCompletion({
    required String systemPrompt,
    required String instruction,
    int maximumOutputTokens = 4096,
    double temperature = .7,
    LlmTask task = LlmTask.structuredExtraction,
    GenerationTaskHandle? taskHandle,
  }) async {
    if (!systemPrompt.contains('"generation_id"')) {
      final sectionId = RegExp(r'允许的 Section ID：([^,\n]+)')
          .firstMatch(systemPrompt)!
          .group(1)!;
      final partId =
          RegExp(r'允许的 Part ID：([^,\n]+)').firstMatch(systemPrompt)!.group(1)!;
      return jsonEncode({
        'suggestedName': '审阅冻结资源',
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
                'estimatedLength': 3000,
                'dependencies': <String>[],
                'sortOrder': 0,
              }
            ],
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
    const content = 'AI 生成的正文内容。';
    return [
      {
        'protocol_version': 1,
        ...ids,
        'sequence': 0,
        'op': 'start_part',
        'cursor': 0
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
        'summary': '摘要',
      },
    ].map(jsonEncode).join('\n');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError(invocation.memberName.toString());
}
