import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lt_dialogue/application/resource_library/edit_drafts.dart';
import 'package:lt_dialogue/config/app_config.dart';
import 'package:lt_dialogue/core/theme/app_theme.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations_en.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations_zh.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';
import 'package:lt_dialogue/core/widgets/custom_attribute_editor_section.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/models/character_card.dart';
import 'package:lt_dialogue/models/custom_attribute_item.dart';
import 'package:lt_dialogue/models/supporting_character.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lt_dialogue/core/widgets/app_dropdown.dart';
import 'package:lt_dialogue/providers/chat_provider.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';
import 'package:lt_dialogue/screens/chat/widgets/character_sheet.dart';
import 'package:lt_dialogue/screens/chat/widgets/quick_menu.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/repositories/adventure_repository_impl.dart';
import 'package:lt_dialogue/services/repositories/library_repository_impl.dart';
import 'package:lt_dialogue/services/repositories/settings_repository_impl.dart';
import 'package:lt_dialogue/services/repositories/world_entry_repository_impl.dart';
import 'package:lt_dialogue/widgets/adventure_message_card.dart';
import '../helpers/responsive_test_helper.dart';

void main() {
  final en = AppLocalizationsEn();
  final zh = AppLocalizationsZh();
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
      expect(prompt, isNot(contains('退魔之剑：对灾厄魔力具备绝对驱散效果')));
      expect(prompt, contains('祈福治愈：每天仅能使用一次全力复生'));
      expect(
        '祈福治愈：每天仅能使用一次全力复生'.allMatches(prompt),
        hasLength(1),
      );
      expect(prompt, isNot(contains('=== 玩家角色设定 ===')));
      expect(prompt, isNot(contains('=== 角色深度设定 ===')));
    });
  });

  group('CustomAttributeEditorSection Widget Tests', () {
    testWidgets('Empty state renders blank slate and add button',
        (tester) async {
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
      expect(find.text(en.customAttributesTitle), findsOneWidget);
      expect(find.text(en.statusItemsCount(0)), findsOneWidget);
      expect(find.text(en.noCustomAttributes), findsOneWidget);
      expect(find.text(en.addCustomAttributeAction), findsOneWidget);

      // 点击添加项
      await tester.tap(find.text(en.addCustomAttributeAction));
      await tester.pump();

      // 验证新增了一项
      expect(find.text(en.statusItemsCount(1)), findsOneWidget);
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
      await tester.tap(find.text(en.addCustomAttributeAction));
      await tester.pump();

      expect(items.length, 1);
      expect(items.first.importance, CustomAttributeImportance.reference);

      // 输入项名称
      final nameFinder =
          find.widgetWithText(TextField, en.customAttributeNameLabel);
      await tester.enterText(nameFinder, '童年阴影');
      await tester.pump();

      // 输入内容
      final valueFinder = find.widgetWithText(
        TextField,
        en.customAttributeContentLabel,
      );
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
      expect(
        find.text(CustomAttributeImportance.important.label),
        findsOneWidget,
      );
      expect(
        find.text(CustomAttributeImportance.veryImportant.label),
        findsOneWidget,
      );
      expect(
        find.text(CustomAttributeImportance.critical.label),
        findsOneWidget,
      );

      // 选择「不可忽略项」
      await tester.tap(find.text(CustomAttributeImportance.critical.label));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(items.first.importance, CustomAttributeImportance.critical);

      // 点击删除按钮
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump();

      expect(items.isEmpty, isTrue);
      expect(find.text(en.statusItemsCount(0)), findsOneWidget);
      expect(find.text(en.noCustomAttributes), findsOneWidget);
    });

    testWidgets(
        'Adding multiple items and deleting does not trigger disposed controller error',
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
      await tester.tap(find.text(en.addCustomAttributeAction));
      await tester.pump();
      await tester.tap(find.text(en.addCustomAttributeAction));
      await tester.pump();
      await tester.tap(find.text(en.addCustomAttributeAction));
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
    testWidgets('QuickMenuButton does not contain 世界书 and has other menu items',
        (tester) async {
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
      expect(find.text(zh.inventoryTitle), findsOneWidget);
      expect(find.text(zh.characterStatusTitle), findsOneWidget);
      expect(find.text(zh.wordCountSettings), findsOneWidget);
      expect(find.text(zh.settingsCenter), findsOneWidget);
    });

    testWidgets(
        'CharacterStatusScreen renders as full-screen Scaffold with tabs',
        (tester) async {
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
      expect(find.text(zh.characterStatusTitle), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);

      // Verify tabs
      expect(find.text('核心状态'), findsOneWidget);
      expect(find.text('装备随身'), findsOneWidget);
      expect(find.text('身世羁绊'), findsOneWidget);

      // Verify character name
      expect(find.text('阿尔温'), findsWidgets);
    });

    testWidgets(
        'CharacterStatusScreen Add Detection Status page uses AppDropdown for importance',
        (tester) async {
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
      final addBtn = find.text(zh.addDetectedStatusAction).first;
      expect(find.text(zh.addDetectedStatusAction), findsWidgets);
      await tester.tap(addBtn);
      await tester.pumpAndSettle();

      // 页面打开后，应使用 AppDropdown 而非原生 DropdownButton。
      expect(find.byType(DropdownButton), findsNothing);
      expect(
          find.byType(AppDropdown<CustomAttributeImportance>), findsOneWidget);

      // 验证剧情重要度选项
      expect(find.text(zh.storyImportanceLabel), findsOneWidget);
      expect(find.text(zh.customAttributeImportanceImportant), findsOneWidget);

      // 打开下拉
      await tester
          .ensureVisible(find.text(zh.customAttributeImportanceImportant));
      await tester.tap(find.text(zh.customAttributeImportanceImportant));
      await tester.pumpAndSettle();

      // 验证下拉浮层中的所有选项
      expect(find.text(zh.customAttributeImportanceReference), findsOneWidget);
      expect(
          find.text(zh.customAttributeImportanceVeryImportant), findsOneWidget);
      expect(find.text(zh.customAttributeImportanceCritical), findsOneWidget);

      // 选择不可忽略项
      await tester.tap(find.text(zh.customAttributeImportanceCritical));
      await tester.pumpAndSettle();

      expect(find.text(zh.customAttributeImportanceCritical), findsOneWidget);
    });

    testWidgets('character status screen fits required localized viewports',
        (tester) async {
      for (final viewport in requiredUiViewports) {
        setViewport(
          tester,
          width: viewport.width,
          height: viewport.height,
        );
        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              locale: Locale('en'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: CharacterStatusScreen(
                initialName: 'Arwen',
                initialRole: 'Traveler',
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
        expect(tester.takeException(), isNull,
            reason: 'unexpected layout issue at $viewport');
      }
    });
  });

  group('AdventureMessageCard Custom Status Reply Flow Tests', () {
    testWidgets(
        'Renders Narrative -> Custom Status -> Options when custom_status is present',
        (tester) async {
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
      expect(find.text(en.characterFallbackName), findsOneWidget);
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

    testWidgets('Skips Custom Status section when custom_status is absent',
        (tester) async {
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

    testWidgets(
        'Renders Character Grouped Monitoring Status when characters are specified',
        (tester) async {
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

    testWidgets(
        'Renders both protagonist and companion favorability (user scenario)',
        (tester) async {
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
  group('CharacterStatusScreen detection status persistence', () {
    late Directory tempDir;
    late int adventureId;

    setUpAll(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfiNoIsolate;
      // SettingsProvider 构造时会创建 connectivity 流；flutter_test 没有平台
      // 实现，不屏蔽会以 MissingPluginException 污染测试结果。
      final messenger =
          TestWidgetsFlutterBinding.instance.defaultBinaryMessenger;
      for (final name in const [
        'dev.fluttercommunity.plus/connectivity',
        'dev.fluttercommunity.plus/connectivity_status',
      ]) {
        messenger.setMockMethodCallHandler(
            MethodChannel(name), (call) async => null);
      }
    });

    /// 新版组装冒险：非主角只在 selectedCharacters 里，supportingCharacters 为空。
    AdventureConfig assembledConfig() => AdventureConfig(
          name: '莉莉安娜',
          selectedCharacters: [
            AdventureSelectedCharacter(
              id: 'sel-hero',
              characterId: 'hero',
              characterName: '莉莉安娜',
              isProtagonist: true,
              narrativeRole: AdventureCharacterRole.protagonist,
            ),
            AdventureSelectedCharacter(
              id: 'sel-alice',
              characterId: 'alice',
              characterName: '艾莉丝',
              narrativeRole: AdventureCharacterRole.femaleLead,
            ),
          ],
        );

    Future<int> seedAdventure(AdventureConfig config) async {
      final repository = AdventureRepositoryImpl(
        getDb: () => DatabaseService.database,
      );
      return repository.createAdventure('status-ui', config);
    }

    /// 文件系统与数据库初始化放在 setUp：`testWidgets` 的测试体运行在 FakeAsync
    /// 区域内，dart:io 的异步调用在那里不会完成。
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      tempDir = await Directory.systemTemp.createTemp('lt_status_ui_');
      DatabaseService.customDbDir = tempDir.path;
      await DatabaseService.resetDatabase();
      adventureId = await seedAdventure(assembledConfig());
    });

    /// 让 Provider 持有与数据库里同一份冒险：不经过 loadAdventure 也能让
    /// updateAdventureConfig 落到 SQLite。
    ChatProvider openChat() {
      final chat = _StatusPersistenceChat();
      chat.startNewAdventureConfig(assembledConfig());
      chat.adventureProvider.currentAdventureId = adventureId;
      return chat;
    }

    /// 本页带有持续动画（Tab / 进度条），`pumpAndSettle` 永远不会收敛，
    /// 因此统一使用有界的帧推进。
    Future<void> settle(WidgetTester tester, [int frames = 12]) async {
      for (var i = 0; i < frames; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Future<void> pumpSheet(
      WidgetTester tester,
      ChatProvider chat, {
      int initialIndex = 0,
    }) async {
      tester.view.physicalSize = const Size(1280, 960);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatProvider.overrideWith((ref) => chat)],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('zh'),
            theme: AppTheme.light(),
            home: CharacterStatusScreen(
              initialName: '莉莉安娜',
              initialRole: '探险者',
              initialHp: 100,
              initialMaxHp: 100,
              initialEnergy: 100,
              initialMaxEnergy: 100,
              initialGold: 0,
              isDark: false,
              initialLevel: 1,
              initialMp: 50,
              initialMaxMp: 50,
              initialSkillPoints: 0,
              initialBaseAtk: 10,
              initialBaseDef: 5,
              initialBaseSpeed: 8,
              initialExperience: 0,
              initialIndex: initialIndex,
            ),
          ),
        ),
      );
      await settle(tester);
    }

    Future<void> addStatus(WidgetTester tester, String name) async {
      await tester.ensureVisible(find.text(zh.addDetectedStatusAction).first);
      await tester.tap(find.text(zh.addDetectedStatusAction).first);
      await settle(tester);

      await tester.enterText(
        find.widgetWithText(TextField, zh.statusNameLabel),
        name,
      );
      await settle(tester);

      await tester.ensureVisible(find.text(zh.confirmAction));
      await tester.tap(find.text(zh.confirmAction));
      await settle(tester);
    }

    testWidgets(
        'selected-only companion status is persisted with its stable id',
        (tester) async {
      final chat = openChat();
      expect(chat.adventureConfig!.supportingCharacters, isEmpty);

      await pumpSheet(tester, chat);
      await addStatus(tester, '理智值 (SAN)');

      // 1/2/3/4：配置里真的多出了带稳定 ID 的持久化快照。
      final stored = chat.adventureConfig!.supportingCharacters;
      expect(stored, hasLength(1));
      expect(stored.single.id, 'alice');
      expect(stored.single.name, '艾莉丝');
      expect(stored.single.customAttributes.single.name, '理智值 (SAN)');
      expect(stored.single.customAttributes.single.characterName, '艾莉丝');

      // 6：重新打开角色状态页（重建页面树）仍然读到同一份状态。
      await pumpSheet(tester, chat, initialIndex: 0);
      expect(
        chat.adventureConfig!.supportingCharacters.single.customAttributes
            .single.name,
        '理智值 (SAN)',
      );
      expect(find.text('理智值 (SAN)'), findsWidgets);

      // 5：数据库 adventures.config 里真实存在。
      final repository = AdventureRepositoryImpl(
        getDb: () => DatabaseService.database,
      );
      final row = await repository.getAdventureById(adventureId);
      final config = AdventureConfig.fromJson(
          jsonDecode(row!['config'] as String) as Map<String, dynamic>);
      expect(
        config.supportingCharacters
            .singleWhere((c) => c.id == 'alice')
            .customAttributes
            .single
            .name,
        '理智值 (SAN)',
      );
    });

    testWidgets('protagonist add and quick adjust keep working',
        (tester) async {
      final chat = openChat();
      await chat.updateAdventureConfig(
        chat.adventureConfig!.copyWith(
          customAttributes: const [
            CustomAttributeItem(
              id: 'san-hero',
              name: '理智值 (SAN)',
              value: '100/100',
              currentValue: 100,
              maxValue: 100,
            ),
          ],
        ),
      );

      await pumpSheet(tester, chat, initialIndex: -1);

      // 主角：通过 UI 追加一项，必须自动绑定到主角名。
      await addStatus(tester, '精神压力');
      expect(chat.adventureConfig!.customAttributes, hasLength(2));
      expect(
        chat.adventureConfig!.customAttributes.last.characterName,
        '莉莉安娜',
      );

      // quick adjust：-5 后主角状态落到 95。
      await tester.ensureVisible(find.text('-5').first);
      await tester.tap(find.text('-5').first);
      await settle(tester);
      expect(
        chat.adventureConfig!.customAttributes
            .singleWhere((a) => a.name == '理智值 (SAN)')
            .currentValue,
        95,
      );
    });
  });
}

/// 角色状态页 → 检测状态 → SQLite 的真实链路回归。
///
/// 非主角角色只在 `selectedCharacters` 里存在时，旧逻辑把 UI 临时构造的
/// [SupportingCharacter] 当成已持久化对象去更新，命中不到任何记录，保存后状态
/// 立刻消失。这里用真实的 ChatProvider + SQLite 驱动一遍，确保「看起来添加
/// 成功」之外，配置里真的多出了带稳定 ID 的持久化快照。
class _StatusPersistenceChat extends ChatProvider {
  _StatusPersistenceChat()
      : super.withRepos(
          adventureRepo:
              AdventureRepositoryImpl(getDb: () => DatabaseService.database),
          worldEntryRepo:
              WorldEntryRepositoryImpl(getDb: () => DatabaseService.database),
          libraryRepo:
              LibraryRepositoryImpl(getDb: () => DatabaseService.database),
          settingsRepo:
              SettingsRepositoryImpl(getDb: () => DatabaseService.database),
        );
}
