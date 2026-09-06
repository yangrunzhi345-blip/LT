import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lt_dialogue/application/resource_library/edit_drafts.dart';
import 'package:lt_dialogue/config/app_config.dart';
import 'package:lt_dialogue/core/theme/app_theme.dart';
import 'package:lt_dialogue/core/widgets/custom_attribute_editor_section.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/models/character_card.dart';
import 'package:lt_dialogue/models/custom_attribute_item.dart';
import 'package:lt_dialogue/models/supporting_character.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lt_dialogue/core/widgets/app_dropdown.dart';
import 'package:lt_dialogue/screens/chat/widgets/character_sheet.dart';
import 'package:lt_dialogue/screens/chat/widgets/quick_menu.dart';
import 'package:lt_dialogue/widgets/adventure_message_card.dart';

void main() {
  group('CustomAttributeItem Model & Serialization Tests', () {
    test('CustomAttributeImportance parses correctly', () {
      expect(CustomAttributeImportance.fromString('参考'),
          CustomAttributeImportance.reference);
      expect(CustomAttributeImportance.fromString('重要参考'),
          CustomAttributeImportance.important);
      expect(CustomAttributeImportance.fromString('很重要参考'),
          CustomAttributeImportance.veryImportant);
      expect(CustomAttributeImportance.fromString('不可忽略项'),
          CustomAttributeImportance.critical);
      expect(CustomAttributeImportance.fromString('unknown'),
          CustomAttributeImportance.reference);
    });

    test('CustomAttributeItem toPromptText produces structured output', () {
      const item = CustomAttributeItem(
        id: '1',
        name: '随身佩剑',
        value: '由极北寒铁铸成，出鞘有微光',
        importance: CustomAttributeImportance.critical,
      );
      expect(item.toPromptText(), '【不可忽略项】随身佩剑：由极北寒铁铸成，出鞘有微光');
    });

    test('CharacterCard serializes and deserializes custom_attributes', () {
      final card = CharacterCard(
        name: '夜羽',
        personality: '冷静隐忍',
        customAttributes: const [
          CustomAttributeItem(
            id: 'c1',
            name: '特殊体质',
            value: '对精神攻击具备抗性',
            importance: CustomAttributeImportance.veryImportant,
          ),
        ],
      );

      final json = card.toJson();
      final data = json['data'] as Map<String, dynamic>;
      expect(data['custom_attributes'], isNotEmpty);

      final restored = CharacterCard.fromJson(json);
      expect(restored.customAttributes.length, 1);
      expect(restored.customAttributes.first.name, '特殊体质');
      expect(restored.customAttributes.first.importance,
          CustomAttributeImportance.veryImportant);
    });

    test('SupportingCharacter handles custom_attributes and description', () {
      final npc = SupportingCharacter(
        name: '莫维奇',
        role: '老学者',
        customAttributes: const [
          CustomAttributeItem(
            id: 'sc1',
            name: '双重契约',
            value: '灵魂受暗影议会监控',
            importance: CustomAttributeImportance.critical,
          ),
        ],
      );

      final json = npc.toJson();
      expect(json['custom_attributes'], isNotEmpty);

      final restored = SupportingCharacter.fromJson(json);
      expect(restored.customAttributes.length, 1);
      expect(restored.customAttributes.first.name, '双重契约');
      expect(restored.customAttributes.first.importance,
          CustomAttributeImportance.critical);
      expect(restored.description, contains('自添加专属设定：【不可忽略项】双重契约：灵魂受暗影议会监控'));
    });

    test('NpcEditDraft parses and serializes custom_attributes', () {
      final draft = NpcEditDraft(
        name: '索尔',
        gender: '男',
        profession: '铁匠',
        customAttributes: const [
          CustomAttributeItem(
            id: 'n1',
            name: '锻造秘法',
            value: '知晓古代矮人锻造术',
            importance: CustomAttributeImportance.important,
          ),
        ],
      );

      final storedJson = draft.toStoredJson();
      final restored = NpcEditDraft.fromExisting({
        'id': 'npc_1',
        'name': '索尔',
        'json_data': storedJson,
      });

      expect(restored.customAttributes.length, 1);
      expect(restored.customAttributes.first.name, '锻造秘法');
      expect(restored.customAttributes.first.importance,
          CustomAttributeImportance.important);
    });

    test('CharacterCardEditDraft parses and saves custom_attributes', () {
      final draft = CharacterCardEditDraft(
        name: '艾斯特尔',
        gender: '女',
        customAttributes: const [
          CustomAttributeItem(
            id: 'a1',
            name: '施法誓约',
            value: '不能在封闭地下使用三环以上魔法',
            importance: CustomAttributeImportance.critical,
          ),
        ],
      );

      final storedJson = draft.toStoredJson();
      final restored = CharacterCardEditDraft.fromExisting({
        'id': 'char_1',
        'name': '艾斯特尔',
        'json_data': storedJson,
      });

      expect(restored.customAttributes.length, 1);
      expect(restored.customAttributes.first.name, '施法誓约');
      expect(restored.customAttributes.first.importance,
          CustomAttributeImportance.critical);
    });

    test('AppConfig.adventurePrompt includes custom attributes and rules', () {
      final config = AdventureConfig(
        name: '主角林克',
        selectedCharacters: [
          AdventureSelectedCharacter(
            id: 'char_1',
            characterId: 'c1',
            characterName: '主角林克',
            isProtagonist: true,
            narrativeRole: AdventureCharacterRole.protagonist,
            characterCardJson: {
              'profession': '勇者',
              'custom_attributes': [
                {
                  'name': '退魔之剑',
                  'value': '对灾厄魔力具备绝对驱散效果',
                  'importance': '不可忽略项',
                }
              ]
            },
          ),
        ],
        supportingCharacters: [
          SupportingCharacter(
            name: '同伴米法',
            role: '治疗师',
            customAttributes: [
              const CustomAttributeItem(
                id: 'attr2',
                name: '祈福治愈',
                value: '每天仅能使用一次全力复生',
                importance: CustomAttributeImportance.veryImportant,
              ),
            ],
          ),
        ],
      );

      final prompt = AppConfig.adventurePrompt(
        Brightness.dark,
        '海拉鲁冒险',
        '普通',
        config,
        false,
        1,
      );

      expect(prompt, contains('=== 自添加专属设定遵守准则 ==='));
      expect(prompt, contains('【不可忽略项】：最高优先级铁律设定'));
      expect(prompt, contains('自添加专属设定：【不可忽略项】退魔之剑：对灾厄魔力具备绝对驱散效果'));
      expect(prompt, contains('自添加专属设定：【很重要参考】祈福治愈：每天仅能使用一次全力复生'));
    });
  });

  group('CustomAttributeEditorSection Widget Tests', () {
    testWidgets('Empty state renders blank slate and add button', (tester) async {
      List<CustomAttributeItem> currentItems = [];

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return SingleChildScrollView(
                  child: CustomAttributeEditorSection(
                    initialItems: currentItems,
                    onChanged: (items) {
                      setState(() => currentItems = items);
                    },
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();

      // 默认没有，纯净白板状态
      expect(find.text('自添加项'), findsOneWidget);
      expect(find.text('0 项'), findsOneWidget);
      expect(find.text('暂无自添加项（纯净白板）'), findsOneWidget);
      expect(find.text('添加项'), findsOneWidget);

      // 点击添加项
      await tester.tap(find.text('添加项'));
      await tester.pump();

      // 验证新增了一项
      expect(find.text('1 项'), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(2)); // Name + Value
    });

    testWidgets('Can add item, set name, change importance, and delete',
        (tester) async {
      List<CustomAttributeItem> items = [];

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return SingleChildScrollView(
                  child: CustomAttributeEditorSection(
                    initialItems: items,
                    onChanged: (newItems) {
                      items = newItems;
                    },
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();

      // 点击添加项
      await tester.tap(find.text('添加项'));
      await tester.pump();

      expect(items.length, 1);
      expect(items.first.importance, CustomAttributeImportance.reference);

      // 输入项名称
      final nameFinder = find.widgetWithText(TextField, '项名称 *');
      await tester.enterText(nameFinder, '童年阴影');
      await tester.pump();

      // 输入内容
      final valueFinder = find.widgetWithText(TextField, '项内容 / 设定描述');
      await tester.enterText(valueFinder, '对幽暗深处的笛声有本能的恐惧');
      await tester.pump();

      expect(items.first.name, '童年阴影');
      expect(items.first.value, '对幽暗深处的笛声有本能的恐惧');

      // 更改重要程度：打开 AppDropdown
      expect(find.text('参考'), findsOneWidget);
      await tester.tap(find.text('参考'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // 检查浮层中的选项：重要参考、很重要参考、不可忽略项
      expect(find.text('重要参考'), findsOneWidget);
      expect(find.text('很重要参考'), findsOneWidget);
      expect(find.text('不可忽略项'), findsOneWidget);

      // 选择「不可忽略项」
      await tester.tap(find.text('不可忽略项'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(items.first.importance, CustomAttributeImportance.critical);

      // 点击删除按钮
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump();

      expect(items.isEmpty, isTrue);
      expect(find.text('0 项'), findsOneWidget);
      expect(find.text('暂无自添加项（纯净白板）'), findsOneWidget);
    });

    testWidgets('Adding multiple items and deleting does not trigger disposed controller error',
        (tester) async {
      List<CustomAttributeItem> items = [];

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return SingleChildScrollView(
                  child: CustomAttributeEditorSection(
                    initialItems: items,
                    onChanged: (newItems) {
                      items = newItems;
                    },
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();

      // 添加 3 项
      await tester.tap(find.text('添加项'));
      await tester.pump();
      await tester.tap(find.text('添加项'));
      await tester.pump();
      await tester.tap(find.text('添加项'));
      await tester.pump();

      expect(items.length, 3);
      expect(find.byIcon(Icons.close_rounded), findsNWidgets(3));

      // 删除中间一项（索引 1）
      await tester.tap(find.byIcon(Icons.close_rounded).at(1));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(items.length, 2);
      expect(tester.takeException(), isNull);

      // 删除第一项
      await tester.tap(find.byIcon(Icons.close_rounded).first);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(items.length, 1);
      expect(tester.takeException(), isNull);
    });
  });

  group('CharacterStatusScreen Full-Screen & QuickMenu Tests', () {
    testWidgets('QuickMenuButton does not contain 世界书 and has other menu items', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: Center(
              child: QuickMenuButton(
                isDark: false,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Open popup menu
      await tester.tap(find.byType(QuickMenuButton));
      await tester.pumpAndSettle();

      expect(find.text('世界书'), findsNothing);
      expect(find.text('背包物品'), findsOneWidget);
      expect(find.text('角色状态'), findsOneWidget);
      expect(find.text('字数设置'), findsOneWidget);
      expect(find.text('设置中心'), findsOneWidget);
    });

    testWidgets('CharacterStatusScreen renders as full-screen Scaffold with tabs', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: CharacterStatusScreen(
              initialName: '阿尔温',
              initialRole: '旅者',
              initialHp: 100,
              initialMaxHp: 100,
              initialEnergy: 80,
              initialMaxEnergy: 100,
              initialGold: 50,
              isDark: false,
              initialLevel: 1,
              initialMp: 50,
              initialMaxMp: 50,
              initialSkillPoints: 0,
              initialBaseAtk: 10,
              initialBaseDef: 5,
              initialBaseSpeed: 8,
              initialExperience: 0,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Verify Scaffold and AppBar
      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.text('角色状态'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);

      // Verify tabs
      expect(find.text('核心状态'), findsOneWidget);
      expect(find.text('装备随身'), findsOneWidget);
      expect(find.text('身世羁绊'), findsOneWidget);

      // Verify character name
      expect(find.text('阿尔温'), findsWidgets);
    });

    testWidgets('CharacterStatusScreen Add Detection Status dialog uses AppDropdown for importance', (tester) async {
      tester.view.physicalSize = const Size(1280, 960);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: CharacterStatusScreen(
              initialName: '阿尔温',
              initialRole: '旅者',
              initialHp: 100,
              initialMaxHp: 100,
              initialEnergy: 80,
              initialMaxEnergy: 100,
              initialGold: 50,
              isDark: false,
              initialLevel: 1,
              initialMp: 50,
              initialMaxMp: 50,
              initialSkillPoints: 0,
              initialBaseAtk: 10,
              initialBaseDef: 5,
              initialBaseSpeed: 8,
              initialExperience: 0,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // 找到添加检测状态按钮
      final addBtn = find.text('添加检测状态').first;
      expect(find.text('添加检测状态'), findsWidgets);
      await tester.tap(addBtn);
      await tester.pumpAndSettle();

      // 对话框弹出，应使用 AppDropdown 而非原生 DropdownButton
      expect(find.byType(DropdownButton), findsNothing);
      expect(find.byType(AppDropdown<CustomAttributeImportance>), findsOneWidget);

      // 验证剧情重要度选项
      expect(find.text('剧情重要度: '), findsOneWidget);
      expect(find.text('重要参考'), findsOneWidget);

      // 打开下拉
      await tester.tap(find.byType(AppDropdown<CustomAttributeImportance>));
      await tester.pumpAndSettle();

      // 验证下拉浮层中的所有选项
      expect(find.text('参考'), findsOneWidget);
      expect(find.text('很重要参考'), findsOneWidget);
      expect(find.text('不可忽略项'), findsOneWidget);

      // 选择不可忽略项
      await tester.tap(find.text('不可忽略项'));
      await tester.pumpAndSettle();

      expect(find.text('不可忽略项'), findsOneWidget);
    });
  });

  group('AdventureMessageCard Custom Status Reply Flow Tests', () {
    testWidgets('Renders Narrative -> Custom Status -> Options when custom_status is present', (tester) async {
      const jsonContent = '''你穿过古老的墓园，寒风凛冽。

四周传来窃窃私语，你的理智在不断受到侵蚀。

---JSON---
{
  "options": ["点燃火把", "念诵驱魔咒", "快步离开"],
  "custom_status": [
    {"name": "SAN值", "value": "60/100"},
    {"name": "体温", "value": "寒冷"}
  ]
}''';

      String? selectedOption;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: AdventureMessageCard(
                jsonContent: jsonContent,
                brightness: Brightness.light,
                onOptionTap: (opt) => selectedOption = opt,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. 叙事正文
      expect(find.text('你穿过古老的墓园，寒风凛冽。'), findsOneWidget);
      expect(find.text('四周传来窃窃私语，你的理智在不断受到侵蚀。'), findsOneWidget);

      // 2. 监测状态（默认展开，绑定角色）
      expect(find.text('监测状态'), findsOneWidget);
      expect(find.text('角色A'), findsOneWidget);
      expect(find.text('SAN值'), findsOneWidget);
      expect(find.text('60/100'), findsOneWidget);
      expect(find.text('体温'), findsOneWidget);
      expect(find.text('寒冷'), findsOneWidget);

      // 3. 行动选项（默认展开）
      expect(find.textContaining('3 个选项'), findsOneWidget);
      expect(find.text('点燃火把'), findsOneWidget);
      expect(find.text('念诵驱魔咒'), findsOneWidget);
      expect(find.text('快步离开'), findsOneWidget);

      // 监测状态和选项均默认展开，因此有两个“收起 ▲”
      expect(find.text('收起 ▲'), findsNWidgets(2));

      // 点击选项
      await tester.tap(find.text('点燃火把'));
      await tester.pump();
      expect(selectedOption, '点燃火把');

      // 收起选项
      await tester.tap(find.text('收起 ▲').last);
      await tester.pumpAndSettle();
      expect(find.text('展开 ▼'), findsOneWidget);
      expect(find.text('点燃火把'), findsNothing);

      // 不显示旧状态条或随身装备/身世羁绊
      expect(find.text('HP'), findsNothing);
      expect(find.text('EN'), findsNothing);
      expect(find.text('Gold'), findsNothing);
      expect(find.text('随身装备'), findsNothing);
      expect(find.text('身世羁绊'), findsNothing);
    });

    testWidgets('Skips Custom Status section when custom_status is absent', (tester) async {
      const jsonContent = '''你安全回到了旅馆，壁炉里火光温暖。

---JSON---
{
  "options": ["休息到天亮", "喝一杯麦酒"]
}''';

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: SingleChildScrollView(
              child: AdventureMessageCard(
                jsonContent: jsonContent,
                brightness: Brightness.light,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 正文显示
      expect(find.text('你安全回到了旅馆，壁炉里火光温暖。'), findsOneWidget);

      // 无自定义状态时完全跳过
      expect(find.text('监测状态'), findsNothing);
      expect(find.text('HP'), findsNothing);

      // 选项正常显示（默认展开）
      expect(find.textContaining('2 个选项'), findsOneWidget);
      expect(find.text('收起 ▲'), findsOneWidget);
      expect(find.text('休息到天亮'), findsOneWidget);
      expect(find.text('喝一杯麦酒'), findsOneWidget);

      // 可点击收起
      await tester.tap(find.text('收起 ▲'));
      await tester.pumpAndSettle();
      expect(find.text('展开 ▼'), findsOneWidget);
      expect(find.text('休息到天亮'), findsNothing);
    });

    testWidgets('Renders Character Grouped Monitoring Status when characters are specified', (tester) async {
      const jsonContent = '''伙伴们在营火旁休整。

---JSON---
{
  "options": ["分配守夜任务", "查看补给储备"],
  "custom_status": {
    "角色A": {
      "理智值": "85/100",
      "心智状态": "清醒"
    },
    "角色B": {
      "好感度": "90/100"
    }
  }
}''';

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: SingleChildScrollView(
              child: AdventureMessageCard(
                jsonContent: jsonContent,
                brightness: Brightness.light,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 监测状态默认展开
      expect(find.text('监测状态'), findsOneWidget);
      expect(find.text('收起 ▲'), findsNWidgets(2)); // 监测状态与选项均默认展开

      // 按角色分组显示
      expect(find.text('角色A'), findsOneWidget);
      expect(find.text('理智值'), findsOneWidget);
      expect(find.text('85/100'), findsOneWidget);
      expect(find.text('心智状态'), findsOneWidget);
      expect(find.text('清醒'), findsOneWidget);

      expect(find.text('角色B'), findsOneWidget);
      expect(find.text('好感度'), findsOneWidget);
      expect(find.text('90/100'), findsOneWidget);

      // 选项默认展开
      expect(find.text('分配守夜任务'), findsOneWidget);
      expect(find.text('查看补给储备'), findsOneWidget);
    });

    testWidgets('Renders both protagonist and companion favorability (user scenario)', (tester) async {
      const jsonContent = '''你与艾莉丝一同走出马车，微风拂过艾莉丝的金发。
艾莉丝低声说道：“只要有你在身边，我就安心了……”

---JSON---
{
  "options": [
    "牵起艾莉丝的手，轻声安抚她的情绪，告诉她无论发生什么自己都会保护她",
    "向艾莉丝说明目前的处境，商讨下一步对策",
    "环顾四周，寻找可以作为掩体的安全地点"
  ],
  "custom_status": {
    "莉莉安娜·冯·艾德斯坦": {
      "好感度": "62/100"
    },
    "艾莉丝·冯·奥伯莱恩": {
      "好感度": "60/100"
    }
  }
}''';

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: SingleChildScrollView(
              child: AdventureMessageCard(
                jsonContent: jsonContent,
                brightness: Brightness.light,
                defaultCharacterName: '莉莉安娜·冯·艾德斯坦',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 监测状态面板标题与总项数
      expect(find.text('监测状态'), findsOneWidget);
      expect(find.text('2项'), findsOneWidget);

      // 主角状态展示
      expect(find.text('莉莉安娜·冯·艾德斯坦'), findsOneWidget);
      expect(find.text('62/100'), findsOneWidget);

      // 同伴状态展示
      expect(find.text('艾莉丝·冯·奥伯莱恩'), findsOneWidget);
      expect(find.text('60/100'), findsOneWidget);

      // 两位角色的“好感度”标签均存在
      expect(find.text('好感度'), findsNWidgets(2));

      // 行动选项均存在
      expect(find.textContaining('牵起艾莉丝的手'), findsOneWidget);
      expect(find.textContaining('向艾莉丝说明目前的处境'), findsOneWidget);
      expect(find.textContaining('寻找可以作为掩体的安全地点'), findsOneWidget);
    });
  });
}

