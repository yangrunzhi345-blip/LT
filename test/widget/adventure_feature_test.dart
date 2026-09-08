import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lt_dialogue/core/theme/app_theme.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/features/adventure/presentation/home/widgets/dashboard_character_cards.dart';
import 'package:lt_dialogue/features/adventure/presentation/session/screens/adventure_session_screen.dart';
import 'package:lt_dialogue/features/adventure/presentation/session/widgets/action_options_panel.dart';
import 'package:lt_dialogue/features/adventure/presentation/session/widgets/status_hud_bar.dart';
import 'package:lt_dialogue/features/adventure/presentation/wizard/screens/adventure_wizard_screen.dart';
import 'package:lt_dialogue/features/resource_library/presentation/screens/resource_library_screen.dart';
import 'package:lt_dialogue/features/prompt_settings/presentation/screens/prompt_settings_screen.dart';
import 'package:lt_dialogue/services/database_service.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues(
        {'openai_api_key': 'test', 'deepseek_api_key': 'test'});
    tempDir = await Directory.systemTemp.createTemp('lt_adv_test_');
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

  group('Adventure Feature Unit & Widget Tests', () {
    for (final size in const [
      Size(320, 568),
      Size(360, 640),
      Size(393, 852),
      Size(411, 891),
      Size(600, 960),
      Size(568, 320),
    ]) {
      for (final scale in [1.0, 1.3, 1.5, 1.8]) {
        testWidgets('StatusHudBar should fit $size at text scale $scale',
            (tester) async {
          tester.view.reset();
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(ProviderScope(
            child: MaterialApp(
              theme: AppTheme.light(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(scale),
                ),
                child: child!,
              ),
              home: const Scaffold(body: StatusHudBar()),
            ),
          ));
          await tester.pump();
          expect(tester.takeException(), isNull);
          for (final icon in [
            Icons.favorite_rounded,
            Icons.bolt_rounded,
            Icons.monetization_on_rounded,
            Icons.place_rounded
          ]) {
            expect(find.byIcon(icon), findsOneWidget);
            final bounds = tester.getRect(find.byIcon(icon));
            expect(bounds.left, greaterThanOrEqualTo(0));
            expect(bounds.right, lessThanOrEqualTo(size.width));
          }
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }
    }

    testWidgets('ActionOptionsPanel renders choices and handles tap',
        (tester) async {
      String? selected;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: ActionOptionsPanel(
              options: const ['探索地牢', '回城休整', '查看随身信件'],
              onOptionSelected: (val) => selected = val,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('可选行动分支'), findsOneWidget);
      expect(find.text('探索地牢'), findsOneWidget);
      expect(find.text('回城休整'), findsOneWidget);

      await tester.tap(find.text('探索地牢'));
      await tester.pump();

      expect(selected, '探索地牢');
    });

    testWidgets('StatusHudBar renders status elements', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(
              body: StatusHudBar(),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
      expect(find.byIcon(Icons.bolt_rounded), findsOneWidget);
      expect(find.byIcon(Icons.monetization_on_rounded), findsOneWidget);
      expect(find.byIcon(Icons.place_rounded), findsOneWidget);
    });

    testWidgets('AdventureWizardScreen renders stepper and advances steps',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.light(),
            home: AdventureWizardScreen(
              onStartAdventure: (cfg) async {},
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('世界观'), findsWidgets);
      expect(find.text('角色设计'), findsWidgets);
      expect(find.text('序章剧情'), findsWidgets);
      expect(find.text('确认预览'), findsWidgets);
    });

    testWidgets(
        'AdventureWizardScreen should fit each step on mobile viewports',
        (tester) async {
      addTearDown(tester.view.reset);
      const viewports = [
        Size(320, 568),
        Size(360, 640),
        Size(393, 852),
        Size(411, 891),
        Size(600, 960),
        Size(568, 320),
      ];
      const textScales = [1.0, 1.3, 1.5];

      for (final size in viewports) {
        for (final scale in [...textScales, if (size.width == 320) 1.8]) {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          await tester.pumpWidget(
            ProviderScope(
              child: MaterialApp(
                theme: AppTheme.light(),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(scale),
                  ),
                  child: child!,
                ),
                home: AdventureWizardScreen(onStartAdventure: (_) async {}),
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 300));

          for (var step = 0; step < 4; step++) {
            final stepper = tester.widget<Stepper>(find.byType(Stepper));
            stepper.onStepTapped!(step);
            await tester.pump();
            expect(tester.takeException(), isNull,
                reason: '$size at $scale, step $step should not overflow');
          }
          await tester.pumpWidget(const SizedBox.shrink());
        }
      }
    });

    testWidgets(
        'AdventureWizardScreen Step 1 renders AI worldview panel and creation buttons',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.light(),
            home: AdventureWizardScreen(
              onStartAdventure: (cfg) async {},
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // 验证步骤 1 世界观的 AI 创作与编写组件
      expect(find.text('选择或自定义世界观设定'), findsOneWidget);
      expect(find.text('AI 创作世界观'), findsOneWidget);
      expect(find.text('AI 自动编写世界观设定'), findsOneWidget);
      expect(find.text('支持快速构思与资料库创作'), findsOneWidget);
      expect(find.text('世界观创意要求 / 题材偏好 (可选)'), findsOneWidget);
      expect(find.text('开始 AI 自动编写'), findsOneWidget);
      expect(find.text('资料库 AI 创作 (详尽版)'), findsOneWidget);

      // 验证保存到资料库选项与按钮
      expect(find.text('保存到资料库'), findsOneWidget);
      expect(find.text('立即保存到资料库'), findsOneWidget);
      expect(find.byType(Checkbox), findsWidgets);
    });

    testWidgets(
        'AdventureWizardScreen Step 2 allows adding character with role and relation',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.light(),
            home: AdventureWizardScreen(
              onStartAdventure: (cfg) async {},
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // 点击步骤 2: 角色设计
      final step2Title = find.text('角色设计');
      expect(step2Title, findsWidgets);
      await tester.tap(step2Title.first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('选择或设计冒险角色'), findsOneWidget);
      expect(find.text('新建角色'), findsOneWidget);
      expect(find.text('AI 自动编写角色设定'), findsOneWidget);
      expect(find.text('支持快速构思与资料库创作'), findsOneWidget);
      expect(find.text('开始 AI 自动生成主角'), findsOneWidget);
      expect(find.text('资料库 AI 创作 (详尽版)'), findsOneWidget);

      // 验证保存角色到资料库选项与按钮
      expect(find.text('保存角色到资料库'), findsOneWidget);
      expect(find.text('立即保存到资料库'), findsOneWidget);

      // 点击新建角色打开资料库角色卡界面
      await tester.runAsync(() async {
        await tester.tap(find.text('新建角色'));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();

      expect(find.text('新建角色卡'), findsOneWidget);
      expect(find.text('角色卡信息'), findsOneWidget);
      expect(find.text('AI 智能辅助编写角色卡'), findsOneWidget);
      expect(find.text('AI 填入'), findsOneWidget);
      expect(find.text('姓名 *'), findsOneWidget);
      expect(find.text('职业/身份'), findsOneWidget);
    });

    testWidgets(
        'AdventureWizardScreen Step 2 renders associated characters and relation selectors when characters exist',
        (tester) async {
      final config = AdventureConfig(
        worldview: '星穹世界',
        selectedCharacters: [
          AdventureSelectedCharacter(
            id: 'c1',
            characterId: 'char_jinlan',
            characterName: '烬澜',
            characterAvatar: '',
            isProtagonist: true,
            narrativeRole: 'protagonist',
            customRoleName: '',
            sortOrder: 0,
            createdAt: '',
            updatedAt: '',
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.light(),
            home: AdventureWizardScreen(
              initialConfig: config,
              onStartAdventure: (cfg) async {},
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // 点击步骤 2: 角色设计
      final step2Title = find.text('角色设计');
      expect(step2Title, findsWidgets);
      await tester.tap(step2Title.first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // 验证关联已有角色设定区
      expect(find.text('关联已有角色生成 (可选)'), findsOneWidget);
      expect(find.text('选择关联已有角色'), findsOneWidget);
      expect(find.text('羁绊关系：'), findsOneWidget);
      expect(find.text('青梅竹马'), findsWidgets);
      expect(find.text('恋人'), findsWidgets);
      expect(find.text('师徒'), findsWidgets);
    });

    testWidgets(
        'AdventureWizardScreen Step 3 renders AI prologue generation panel and action branch fields',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.light(),
            home: AdventureWizardScreen(
              onStartAdventure: (cfg) async {},
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // 点击 Stepper 中的 "序章剧情" 步骤
      final step3Title = find.text('序章剧情');
      expect(step3Title, findsWidgets);
      await tester.tap(step3Title.first);
      await tester.pumpAndSettle();

      // 验证 AI 智能编写面板
      expect(find.text('AI 自动编写序章与初始行动分支'), findsOneWidget);
      expect(find.text('联动世界观与角色羁绊'), findsOneWidget);
      expect(find.text('剧情倾向 / 特定开场要求 (可选)'), findsOneWidget);
      expect(find.text('开始 AI 自动编写'), findsOneWidget);

      // 验证开场第一幕与行动分支
      expect(find.text('开场第一幕剧情描写'), findsOneWidget);
      expect(find.text('初始行动分支 (可选)'), findsOneWidget);
      expect(find.text('分支 1'), findsOneWidget);
      expect(find.text('分支 2'), findsOneWidget);
      expect(find.text('分支 3'), findsOneWidget);
    });

    testWidgets('AdventureWizardScreen renders header and close button',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.light(),
            home: AdventureWizardScreen(
              onStartAdventure: (cfg) async {},
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('定制冒险向导'), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    testWidgets(
        'AdventureSessionScreen renders blank slate empty state and input bar',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const AdventureSessionScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('纯净冒险白板'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byIcon(Icons.menu_rounded), findsOneWidget);
    });

    testWidgets(
        'AdventureSessionScreen and ResourceLibraryScreen should fit on mobile',
        (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      Widget scaled(Widget child) => MaterialApp(
            theme: AppTheme.light(),
            builder: (context, content) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(1.5),
              ),
              child: content!,
            ),
            home: child,
          );

      await tester.pumpWidget(
        ProviderScope(child: scaled(const AdventureSessionScreen())),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.more_vert_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pump();
      expect(find.text('提示词设置'), findsOneWidget);
      expect(find.text('重开冒险'), findsOneWidget);
      expect(find.text('设置中心'), findsOneWidget);

      await tester.pumpWidget(
        ProviderScope(child: scaled(const ResourceLibraryScreen())),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      expect(find.byType(TabBar), findsOneWidget);
    });

    testWidgets('DashboardCharacterCards renders section title and icon',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: DashboardCharacterCards(
                onSelectCharacter: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('我的角色卡档案'), findsOneWidget);
      expect(find.byIcon(Icons.badge_outlined), findsOneWidget);
    });

    testWidgets(
        'PromptSettingsScreen renders dialogue level and prompt sections',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const PromptSettingsScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('提示词与推演编排'), findsOneWidget);
      expect(find.text('对话模式分级 (Dialogue Level)'), findsOneWidget);
      expect(find.text('全局系统提示词 (System Prompt)'), findsOneWidget);
      expect(find.text('作者注释 (Author\'s Note)'), findsOneWidget);
    });
  });
}
