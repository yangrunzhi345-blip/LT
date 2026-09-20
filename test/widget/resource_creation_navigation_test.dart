import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/core/theme/app_theme.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_limits.dart';
import 'package:lt_dialogue/features/resource_library/domain/models/resource_library_view_state.dart';
import 'package:lt_dialogue/features/resource_library/presentation/screens/resource_ai_create_page.dart';
import 'package:lt_dialogue/features/resource_library/presentation/screens/resource_create_page.dart';
import 'package:lt_dialogue/features/resource_library/presentation/screens/resource_library_screen.dart';
import 'package:lt_dialogue/features/resource_library/presentation/screens/resource_manual_create_page.dart';
import 'package:lt_dialogue/features/resource_library/presentation/widgets/resource_creation_flow.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/features/resource_studio/presentation/pages/resource_studio_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/responsive_test_helper.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir =
        await Directory.systemTemp.createTemp('lt_resource_creation_nav_test_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  Widget buildTestApp(Widget home) {
    return ProviderScope(
      child: MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        home: home,
      ),
    );
  }

  const fakeExistingResources = <ResourceLibraryItem>[
    ResourceLibraryItem(
      id: 'res-1',
      name: '艾泽拉斯世界设定',
      type: ResourceType.worldview,
      summary: '高魔奇幻史诗大陆',
      updatedAt: '2026-09-20',
      status: ResourceDisplayStatus.ready,
      isStudioAvailable: true,
    ),
    ResourceLibraryItem(
      id: 'res-2',
      name: '阿尔萨斯·米奈希尔',
      type: ResourceType.character,
      summary: '洛丹伦王子与巫妖王',
      updatedAt: '2026-09-20',
      status: ResourceDisplayStatus.ready,
      isStudioAvailable: true,
    ),
  ];

  group('R02-B: 页面进入 (Navigation Entry)', () {
    testWidgets('点击新建按钮跳转进入 ResourceCreatePage，不弹出 Dialog 或 BottomSheet',
        (tester) async {
      await tester.pumpWidget(buildTestApp(const ResourceLibraryScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final createButton = find.byKey(const Key('resource-create-button'));
      expect(createButton, findsOneWidget);

      // 点击新建按钮
      await tester.tap(createButton);
      await tester.pumpAndSettle();

      // 验证已直接推入 ResourceCreatePage 独立页面
      expect(find.byType(ResourceCreatePage), findsOneWidget);
      expect(find.text('新建资源'), findsOneWidget);
      expect(find.byKey(const Key('create-choice-ai')), findsOneWidget);
      expect(find.byKey(const Key('create-choice-manual')), findsOneWidget);

      // 验证未出现任何旧 Dialog 或 BottomSheet
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(BottomSheet), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('R02-B: 类型选择 (AppSelect on ResourceCreatePage)', () {
    testWidgets('ResourceCreatePage 中 AppSelect 正常展开并切换资源类型', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const ResourceCreatePage(
            resources: fakeExistingResources,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('预选类型'), findsOneWidget);
      expect(find.text('世界观'), findsOneWidget);

      // 点击展开 AppSelect
      await tester.tap(find.text('世界观'));
      await tester.pumpAndSettle();

      // 选取角色类型
      expect(find.text('角色'), findsWidgets);
      await tester.tap(find.text('角色').last);
      await tester.pumpAndSettle();

      // 验证当前显示为角色
      expect(find.text('角色'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('R02-B: 手动创建 (ResourceManualCreatePage)', () {
    testWidgets('表单输入、空值校验拦截与正常提交返回 ManualResourceDraft', (tester) async {
      ManualResourceDraft? submittedDraft;

      await tester.pumpWidget(
        buildTestApp(
          Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  final result = await Navigator.push<ManualResourceDraft>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ResourceManualCreatePage(),
                    ),
                  );
                  submittedDraft = result;
                },
                child: const Text('打开手动创建'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开手动创建'));
      await tester.pumpAndSettle();

      expect(find.byType(ResourceManualCreatePage), findsOneWidget);
      expect(find.text('手动创建资源'), findsOneWidget);

      // 1. 测试空值校验拦截
      await tester.tap(find.byKey(const Key('manual-create-submit-button')));
      await tester.pumpAndSettle();

      expect(find.text('请输入资源名称'), findsOneWidget);
      expect(submittedDraft, isNull);

      // 2. 正常输入
      await tester.enterText(
        find.byKey(const Key('manual-create-name-field')),
        '达拉然魔法王国',
      );
      await tester.enterText(
        find.byKey(const Key('manual-create-summary-field')),
        '肯瑞托法师议会统治的魔法城邦',
      );
      await tester.pump();

      // 提交表单
      await tester.tap(find.byKey(const Key('manual-create-submit-button')));
      await tester.pumpAndSettle();

      // 验证成功返回草稿
      expect(submittedDraft, isNotNull);
      expect(submittedDraft!.name, '达拉然魔法王国');
      expect(submittedDraft!.summary, '肯瑞托法师议会统治的魔法城邦');
      expect(submittedDraft!.type, ResourceType.worldview);
      expect(tester.takeException(), isNull);
    });
  });

  group('R02-B: AI 创建 (ResourceAiCreatePage)', () {
    testWidgets('参考资料来源切换、校验与正常提交返回 ResourceStudioCreationDraft',
        (tester) async {
      ResourceStudioCreationDraft? submittedDraft;

      await tester.pumpWidget(
        buildTestApp(
          Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  final result =
                      await Navigator.push<ResourceStudioCreationDraft>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ResourceAiCreatePage(
                        resources: fakeExistingResources,
                      ),
                    ),
                  );
                  submittedDraft = result;
                },
                child: const Text('打开AI创建'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开AI创建'));
      await tester.pumpAndSettle();

      expect(find.byType(ResourceAiCreatePage), findsOneWidget);
      expect(find.text('AI 智能创建资源'), findsOneWidget);
      expect(
        find.text('${ResourceLimits.worldviewNominalCharacters} 字'),
        findsOneWidget,
      );

      // 1. 空值校验拦截
      final submitButton = find.byKey(const Key('ai-create-submit-button'));
      await tester.scrollUntilVisible(
        submitButton,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -80),
      );
      await tester.pumpAndSettle();
      await tester.tap(submitButton);
      await tester.pumpAndSettle();

      expect(find.text('请输入资源名称'), findsOneWidget);
      expect(find.text('请输入或粘贴参考资料正文'), findsOneWidget);
      expect(submittedDraft, isNull);

      // 2. 正常粘贴参考资料
      await tester.enterText(
        find.byKey(const Key('ai-create-name-field')),
        '冰封王座之巅',
      );
      await tester.enterText(
        find.byKey(const Key('ai-create-paste-field')),
        '诺森德严寒冰川上的决战，亡灵天灾在天灾军团领袖带领下崛起。',
      );
      await tester.pump();

      // 提交粘贴模式
      await tester.scrollUntilVisible(
        submitButton,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -80),
      );
      await tester.pumpAndSettle();
      await tester.tap(submitButton);
      await tester.pumpAndSettle();

      expect(submittedDraft, isNotNull);
      expect(submittedDraft!.name, '冰封王座之巅');
      expect(submittedDraft!.referenceSource.hasBody, isTrue);
      expect(
        submittedDraft!.targetCharacters,
        ResourceLimits.worldviewNominalCharacters,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('Slider 拖动后保留目标字数并随草稿提交', (tester) async {
      ResourceStudioCreationDraft? submittedDraft;

      await tester.pumpWidget(
        buildTestApp(
          Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  submittedDraft =
                      await Navigator.push<ResourceStudioCreationDraft>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ResourceAiCreatePage(
                        resources: fakeExistingResources,
                      ),
                    ),
                  );
                },
                child: const Text('打开长度控制'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开长度控制'));
      await tester.pumpAndSettle();

      final sliderFinder = find.byKey(const Key('ai-create-target-slider'));
      expect(sliderFinder, findsOneWidget);
      expect(
        tester.widget<Slider>(sliderFinder).value,
        ResourceLimits.worldviewNominalCharacters,
      );

      await tester.ensureVisible(sliderFinder);
      await tester.drag(sliderFinder, const Offset(-120, 0));
      await tester.pumpAndSettle();
      final adjustedTarget = tester.widget<Slider>(sliderFinder).value.round();
      expect(
        adjustedTarget,
        lessThan(ResourceLimits.worldviewNominalCharacters),
      );

      await tester.tap(find.text('文件'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('粘贴'));
      await tester.pumpAndSettle();
      expect(tester.widget<Slider>(sliderFinder).value.round(), adjustedTarget);

      await tester.enterText(
        find.byKey(const Key('ai-create-name-field')),
        '可控长度世界观',
      );
      await tester.enterText(
        find.byKey(const Key('ai-create-paste-field')),
        '用于验证目标字数贯穿提交草稿的参考资料。',
      );
      final submitButton = find.byKey(const Key('ai-create-submit-button'));
      await tester.scrollUntilVisible(
        submitButton,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -80),
      );
      await tester.pumpAndSettle();
      await tester.tap(submitButton);
      await tester.pumpAndSettle();

      expect(submittedDraft?.targetCharacters, adjustedTarget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('AI 创建支持切换至「文件」与「已有资源」参考源', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const ResourceAiCreatePage(
            resources: fakeExistingResources,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 切换至文件输入
      await tester.tap(find.text('文件'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ai-create-filename-field')), findsOneWidget);
      expect(
          find.byKey(const Key('ai-create-filecontent-field')), findsOneWidget);

      // 切换至已有资源输入
      await tester.tap(find.text('已有资源'));
      await tester.pumpAndSettle();

      expect(
          find.byKey(const Key('ai-create-existing-select')), findsOneWidget);
      expect(find.text('世界观 · 艾泽拉斯世界设定'), findsOneWidget);

      expect(tester.takeException(), isNull);
    });

    testWidgets('切换资源类型时将目标字数收敛到新类型容量', (tester) async {
      await tester.pumpWidget(
        buildTestApp(const ResourceAiCreatePage()),
      );
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<Slider>(
              find.byKey(const Key('ai-create-target-slider')),
            )
            .value,
        ResourceLimits.worldviewNominalCharacters,
      );

      await tester.tap(find.text('世界观'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('角色').last);
      await tester.pumpAndSettle();

      final characterSlider = tester.widget<Slider>(
        find.byKey(const Key('ai-create-target-slider')),
      );
      expect(characterSlider.value, ResourceLimits.characterNominalCharacters);
      expect(characterSlider.max, ResourceLimits.characterNominalCharacters);
      expect(tester.takeException(), isNull);
    });

    testWidgets('角色和 NPC 显示仅包含世界观的关联选择器', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const ResourceAiCreatePage(
            initialType: ResourceType.character,
            resources: fakeExistingResources,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final selector = find.byKey(
        const Key('ai-create-origin-worldview-select'),
      );
      expect(selector, findsOneWidget);
      await tester.tap(selector);
      await tester.pumpAndSettle();
      expect(find.text('艾泽拉斯世界设定'), findsOneWidget);
      expect(find.text('阿尔萨斯·米奈希尔'), findsNothing);

      await tester.tap(find.text('不指定').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('角色'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('NPC').last);
      await tester.pumpAndSettle();
      expect(selector, findsOneWidget);

      await tester.tap(find.text('NPC'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('世界观').last);
      await tester.pumpAndSettle();
      expect(selector, findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('关联世界观独立于粘贴资料并随草稿保存', (tester) async {
      ResourceStudioCreationDraft? submittedDraft;
      await tester.pumpWidget(
        buildTestApp(
          Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  submittedDraft =
                      await Navigator.push<ResourceStudioCreationDraft>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ResourceAiCreatePage(
                        initialType: ResourceType.character,
                        resources: fakeExistingResources,
                      ),
                    ),
                  );
                },
                child: const Text('打开关联创建'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开关联创建'));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('ai-create-origin-worldview-select')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('艾泽拉斯世界设定'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('ai-create-name-field')),
        '关联角色',
      );
      await tester.enterText(
        find.byKey(const Key('ai-create-paste-field')),
        '角色的主要参考资料。',
      );
      final submit = find.byKey(const Key('ai-create-submit-button'));
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();

      expect(submittedDraft?.originWorldviewId, 'res-1');
      expect(submittedDraft?.referenceSource.body, '角色的主要参考资料。');
      expect(tester.takeException(), isNull);
    });
  });

  group('R02-B: 移动端适配与无溢出验证 (320px, 360px, 390px, 412px)', () {
    final viewports = [
      const Size(320, 568),
      const Size(360, 640),
      const Size(390, 844),
      const Size(412, 915),
    ];

    for (final size in viewports) {
      testWidgets(
          'ResourceCreatePage renders without overflow on ${size.width}x${size.height}',
          (tester) async {
        setViewport(tester, width: size.width, height: size.height);

        await tester.pumpWidget(
          buildTestApp(
            const ResourceCreatePage(resources: fakeExistingResources),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('新建资源'), findsOneWidget);
        expect(find.byKey(const Key('create-choice-ai')), findsOneWidget);
        expect(find.byKey(const Key('create-choice-manual')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets(
          'ResourceManualCreatePage renders without overflow on ${size.width}x${size.height} with keyboard',
          (tester) async {
        setViewport(tester, width: size.width, height: size.height);

        await tester.pumpWidget(
          buildTestApp(
            const ResourceManualCreatePage(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('手动创建资源'), findsOneWidget);
        expect(find.byKey(const Key('manual-create-submit-button')),
            findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets(
          'ResourceAiCreatePage renders without overflow on ${size.width}x${size.height} with keyboard',
          (tester) async {
        setViewport(tester, width: size.width, height: size.height);

        await tester.pumpWidget(
          buildTestApp(
            const ResourceAiCreatePage(resources: fakeExistingResources),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('AI 智能创建资源'), findsOneWidget);
        expect(
            find.byKey(const Key('ai-create-submit-button')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
