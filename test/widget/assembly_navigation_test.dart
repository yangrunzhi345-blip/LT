import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lt_dialogue/core/theme/app_theme.dart';
import 'package:lt_dialogue/features/adventure/presentation/wizard/screens/assembly_config_page.dart';
import 'package:lt_dialogue/features/adventure/presentation/wizard/screens/assembly_create_page.dart';
import 'package:lt_dialogue/features/adventure/presentation/wizard/screens/assembly_preview_page.dart';
import 'package:lt_dialogue/features/adventure/presentation/wizard/screens/resource_selection_page.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/repositories/library_repository_impl.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  late Directory tempDir;
  late LibraryRepositoryImpl repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'openai_api_key': 'test',
      'deepseek_api_key': 'test',
    });
    tempDir = await Directory.systemTemp.createTemp('lt_assembly_test_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
    repo = LibraryRepositoryImpl(getDb: () => DatabaseService.database);

    final now = DateTime.now().toIso8601String();

    // 预置世界观
    await repo.saveWorldviewPreset(
      id: 'wv_fantasy',
      name: '艾尔登奇幻大陆',
      description: '灵木交错与魔法纪元的古老大陆',
      entriesJson: '[]',
      now: now,
    );

    // 预置角色卡
    await repo.saveCharacterCard(
      id: 'char_arthur',
      name: '亚瑟',
      jsonData: jsonEncode({
        'data': {
          'name': '亚瑟',
          'gender': '男',
          'age': '24',
          'profession': '圣骑士',
          'personality': '沉稳坚毅',
          'background': '誓约王国的年轻骑士长',
        },
      }),
      source: '测试',
      now: now,
    );

    await repo.saveCharacterCard(
      id: 'char_elena',
      name: '艾莲娜',
      jsonData: jsonEncode({
        'data': {
          'name': '艾莲娜',
          'gender': '女',
          'age': '21',
          'profession': '大奥术师',
          'personality': '聪慧好奇',
          'background': '高塔的秘法研习学者',
        },
      }),
      source: '测试',
      now: now,
    );

    // 预置 NPC
    final db = await DatabaseService.database;
    await db.insert('npc_cards', {
      'id': 'npc_innkeeper',
      'name': '老约克',
      'json_data': jsonEncode({
        'name': '老约克',
        'gender': '男',
        'role': '酒馆老板',
        'personality': '热情健谈',
        'description': '风暴港酒馆的驻场老掌柜',
      }),
      'source': '测试',
      'matching_worldview_id': '',
      'created_at': now,
      'updated_at': now,
    });
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  Widget createTestWidget({required Widget child}) {
    return ProviderScope(
      child: MaterialApp(
        theme: AppTheme.light(),
        home: child,
      ),
    );
  }

  group('Assembly Module Navigation & Pipeline Tests', () {
    testWidgets('Full pipeline navigation from Phase 1 to Phase 4 and start',
        (tester) async {
      AdventureConfig? startedConfig;

      await tester.pumpWidget(
        createTestWidget(
          child: AssemblyCreatePage(
            onStartAdventure: (config) async {
              startedConfig = config;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('冒险装配流水线'), findsOneWidget);
      expect(find.text('1. 世界设定'), findsOneWidget);
      expect(find.text('2. 角色阵容'), findsOneWidget);
      expect(find.text('3. 序章分支'), findsOneWidget);
      expect(find.text('4. 装配总览'), findsOneWidget);

      // --- Phase 1: 世界设定 ---
      // 1. 空世界名称点击下一步触发校验拦截
      await tester.tap(find.byKey(const Key('assembly-next-phase-button')));
      await tester.pump();
      expect(startedConfig, isNull);

      // 2. 输入世界名称与描述
      await tester.enterText(
        find.byKey(const Key('assembly-worldview-name-input')),
        '遗忘群岛',
      );
      await tester.enterText(
        find.byKey(const Key('assembly-worldview-desc-input')),
        '迷雾笼罩的古老海域',
      );
      await tester.pump();

      // 3. 点击「下一步：角色阵容」
      await tester.tap(find.byKey(const Key('assembly-next-phase-button')));
      await tester.pumpAndSettle();

      // --- Phase 2: 角色阵容 ---
      // 1. 空阵容点击下一步拦截
      await tester.tap(find.byKey(const Key('assembly-next-phase-button')));
      await tester.pump();

      // 2. 点击「从资料库选择角色」进入 CharacterSelectionPage
      await tester.tap(
          find.byKey(const Key('assembly-open-character-selection-button')));
      await tester.pumpAndSettle();

      expect(find.text('选择冒险角色'), findsOneWidget);
      expect(find.text('亚瑟'), findsOneWidget);
      expect(find.text('艾莲娜'), findsOneWidget);

      // 勾选亚瑟
      await tester.tap(find.text('亚瑟'));
      await tester.pump();

      // 点击确认选择返回
      await tester
          .tap(find.byKey(const Key('resource-selection-confirm-button')));
      await tester.pumpAndSettle();

      // 验证亚瑟已加入阵容且标为主控主角
      expect(find.text('亚瑟 · 圣骑士'), findsOneWidget);
      expect(find.text('设为主控主角'), findsOneWidget);

      // 3. 点击「选择 NPC」进入 NpcSelectionPage
      await tester
          .tap(find.byKey(const Key('assembly-open-npc-selection-button')));
      await tester.pumpAndSettle();

      expect(find.text('选择初始 NPC'), findsOneWidget);
      expect(find.text('老约克'), findsOneWidget);

      // 勾选老约克
      await tester.tap(find.text('老约克'));
      await tester.pump();

      // 确认返回
      await tester
          .tap(find.byKey(const Key('resource-selection-confirm-button')));
      await tester.pumpAndSettle();

      expect(find.text('选择 NPC (1)'), findsOneWidget);

      // 4. 点击下一步推进到序章
      await tester.tap(find.byKey(const Key('assembly-next-phase-button')));
      await tester.pumpAndSettle();

      // --- Phase 3: 序章分支 ---
      expect(find.text('序章剧情内容'), findsOneWidget);

      // 输入序章
      await tester.enterText(
        find.byKey(const Key('assembly-opening-scene-input')),
        '海风呼啸，战舰在暗礁前触底震颤。',
      );
      await tester.enterText(
        find.byKey(const Key('assembly-option-1-input')),
        '拔剑固守船头',
      );
      await tester.pump();

      // 推进到装配总览
      await tester.tap(find.byKey(const Key('assembly-next-phase-button')));
      await tester.pumpAndSettle();

      // --- Phase 4: 装配总览 ---
      expect(find.text('遗忘群岛'), findsOneWidget);
      expect(find.text('亚瑟 (圣骑士)'), findsOneWidget);
      expect(find.text('已选定 1 位初始 NPC'), findsOneWidget);

      // 启动冒险
      await tester
          .tap(find.byKey(const Key('assembly-start-adventure-button')));
      await tester.pumpAndSettle();

      expect(startedConfig, isNotNull);
      expect(startedConfig!.worldview, equals('遗忘群岛'));
      expect(startedConfig!.name, equals('亚瑟'));
      expect(startedConfig!.protagonistClass, equals('圣骑士'));
      expect(startedConfig!.openingScene, equals('海风呼啸，战舰在暗礁前触底震颤。'));
      expect(startedConfig!.openingOptions, contains('拔剑固守船头'));
      expect(startedConfig!.npcSnapshots.length, equals(1));
      expect(startedConfig!.npcSnapshots.first.name, equals('老约克'));
    });

    testWidgets(
        'AssemblyConfigPage validates inputs and returns updated config',
        (tester) async {
      AssemblyConfigData? savedData;

      await tester.pumpWidget(
        createTestWidget(
          child: AssemblyConfigPage(
            initialOpeningScene: '初始第一幕剧情',
            initialOptions: const ['分支 A', '分支 B'],
            worldviewName: '艾尔登大陆',
            protagonistName: '亚瑟',
            onSave: (data) => savedData = data,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('序章剧情与分支配置'), findsWidgets);
      expect(find.text('初始第一幕剧情'), findsOneWidget);
      expect(find.text('分支 A'), findsOneWidget);
      expect(find.text('分支 B'), findsOneWidget);

      // 修改序章剧情与分支
      await tester.enterText(
        find.byKey(const Key('assembly-config-opening-scene-input')),
        '暴风雨在今夜如期而至，城堡的大门被重重扣响。',
      );
      await tester.enterText(
        find.byKey(const Key('assembly-config-option-1-input')),
        '起身执剑开门',
      );
      await tester.enterText(
        find.byKey(const Key('assembly-config-option-2-input')),
        '退至暗处静观其变',
      );
      await tester.pump();

      // 点击保存
      await tester.tap(find.byKey(const Key('assembly-config-submit-button')));
      await tester.pumpAndSettle();

      expect(savedData, isNotNull);
      expect(savedData!.openingScene, equals('暴风雨在今夜如期而至，城堡的大门被重重扣响。'));
      expect(savedData!.openingOptions, equals(['起身执剑开门', '退至暗处静观其变']));
    });

    testWidgets('AssemblyPreviewPage displays complete overview and launches',
        (tester) async {
      bool adventureStarted = false;

      final testConfig = AdventureConfig(
        worldview: '深蓝之海',
        name: '亚瑟',
        protagonistClass: '圣骑士',
        personality: '沉稳',
        protagonistBackground: '来自北方要塞',
        openingScene: '战鼓擂动，第一声号角吹响。',
        openingOptions: ['向前冲锋', '建立防线'],
        selectedCharacters: [
          AdventureSelectedCharacter(
            id: 'c1',
            characterId: 'char_arthur',
            characterName: '亚瑟',
            characterAvatar: '',
            isProtagonist: true,
            narrativeRole: AdventureCharacterRole.protagonist,
            customRoleName: '',
            sortOrder: 0,
            createdAt: '',
            updatedAt: '',
          ),
          AdventureSelectedCharacter(
            id: 'c2',
            characterId: 'char_elena',
            characterName: '艾莲娜',
            characterAvatar: '',
            isProtagonist: false,
            narrativeRole: AdventureCharacterRole.companion,
            customRoleName: '',
            sortOrder: 1,
            createdAt: '',
            updatedAt: '',
          ),
        ],
        characterRelationships: [
          AdventureCharacterRelationship(
            id: 'r1',
            sourceCharacterId: '亚瑟',
            targetCharacterId: '艾莲娜',
            relationType: AdventureRelationType.companion,
            customRelationName: '',
            description: '',
            createdAt: '',
            updatedAt: '',
          ),
        ],
      );

      await tester.pumpWidget(
        createTestWidget(
          child: AssemblyPreviewPage(
            config: testConfig,
            worldviewDesc: '由无数悬浮海岛构成的奇观世界',
            onStartAdventure: (c) async {
              adventureStarted = true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('冒险装配总览'), findsWidgets);
      expect(find.text('世界设定: 深蓝之海'), findsOneWidget);
      expect(find.text('主控主角: 亚瑟 (圣骑士)'), findsOneWidget);
      expect(find.text('同行角色 (1 位):'), findsOneWidget);
      expect(find.text('艾莲娜 · 同伴'), findsOneWidget);
      expect(find.text('• 亚瑟 ↔ 艾莲娜：同伴'), findsOneWidget);
      expect(find.text('战鼓擂动，第一声号角吹响。'), findsOneWidget);
      expect(find.text('向前冲锋'), findsOneWidget);
      expect(find.text('建立防线'), findsOneWidget);

      // 点击踏入冒险
      await tester.tap(find.byKey(const Key('assembly-preview-start-button')));
      await tester.pumpAndSettle();

      expect(adventureStarted, isTrue);
    });
  });

  group('ResourceSelectionPage Standalone Tests', () {
    testWidgets('Search query filters items in real time and clears',
        (tester) async {
      final items = [
        const ResourceSelectionItem<String>(
          id: '1',
          title: '魔法学徒',
          subtitle: '初阶施法者',
          description: '刚刚接触元素魔法的初学者',
          data: 'apprentice',
        ),
        const ResourceSelectionItem<String>(
          id: '2',
          title: '钢铁守卫',
          subtitle: '重装战士',
          description: '手持坚固重盾的戍卫者',
          data: 'guardian',
        ),
        const ResourceSelectionItem<String>(
          id: '3',
          title: '暗影刺客',
          subtitle: '潜行者',
          description: '出没于黑夜的无声杀手',
          data: 'assassin',
        ),
      ];

      await tester.pumpWidget(
        createTestWidget(
          child: ResourceSelectionPage<String>(
            title: '测试选择器',
            items: items,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('魔法学徒'), findsOneWidget);
      expect(find.text('钢铁守卫'), findsOneWidget);
      expect(find.text('暗影刺客'), findsOneWidget);

      // 搜索「刺客」
      await tester.enterText(
        find.byKey(const Key('resource-selection-search-input')),
        '刺客',
      );
      await tester.pump();

      expect(find.text('暗影刺客'), findsOneWidget);
      expect(find.text('魔法学徒'), findsNothing);
      expect(find.text('钢铁守卫'), findsNothing);

      // 搜索不存在的内容，触发空态
      await tester.enterText(
        find.byKey(const Key('resource-selection-search-input')),
        '不存在的角色',
      );
      await tester.pump();

      expect(find.text('暂无匹配资源'), findsOneWidget);
      expect(find.text('未找到包含「不存在的角色」的资源'), findsOneWidget);

      // 点击清空搜索
      await tester.tap(find.text('清空搜索'));
      await tester.pump();

      expect(find.text('魔法学徒'), findsOneWidget);
      expect(find.text('钢铁守卫'), findsOneWidget);
      expect(find.text('暗影刺客'), findsOneWidget);
    });
  });

  group('Assembly Responsive Viewport Tests (320px, 360px, 390px)', () {
    for (final size in const [
      Size(320, 568),
      Size(360, 640),
      Size(390, 844),
    ]) {
      testWidgets('AssemblyCreatePage renders without overflow on $size',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          createTestWidget(
            child: AssemblyCreatePage(
              onStartAdventure: (_) async {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);

        // 验证 Phase 0-3 逐个切换均零 RenderFlex overflow
        const titles = ['1. 世界设定', '2. 角色阵容', '3. 序章分支', '4. 装配总览'];
        for (int phase = 1; phase <= 3; phase++) {
          await tester.tap(find.text(titles[phase]));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));
          expect(tester.takeException(), isNull);
        }
      });

      testWidgets(
          'AssemblyConfigPage and AssemblyPreviewPage render without overflow on $size',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          createTestWidget(
            child: const AssemblyConfigPage(
              initialOpeningScene: '在狂风与巨浪交织的暴雨之夜，孤舟被抛上了长满暗色荆棘的无名荒礁。',
              initialOptions: ['点燃防水火把', '探查礁石洞穴', '呼喊落水同伴'],
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(
          createTestWidget(
            child: AssemblyPreviewPage(
              config: AdventureConfig(
                worldview: '极北冰原',
                name: '亚瑟',
                protagonistClass: '探索者',
                openingScene: '冰霜凝结在面甲上。',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });
}
