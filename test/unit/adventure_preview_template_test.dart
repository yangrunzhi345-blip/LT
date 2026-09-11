import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lt_dialogue/application/adventure/adventure_template_use_case.dart';
import 'package:lt_dialogue/controllers/adventure_template_controller.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/models/custom_attribute_item.dart';
import 'package:lt_dialogue/models/supporting_character.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/repositories/library_repository_impl.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  late Directory tempDir;
  late LibraryRepositoryImpl libraryRepo;
  late AdventureTemplateController controller;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('lt_preview_test_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
    libraryRepo = LibraryRepositoryImpl(getDb: () => DatabaseService.database);
    controller = AdventureTemplateController(
      useCase: AdventureTemplateUseCase(libraryRepo),
    );
  });

  tearDown(() async {
    controller.dispose();
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  AdventureConfig richConfig() => AdventureConfig(
        worldview: '雾隐群岛',
        name: '林述',
        gender: '男',
        age: '二十四',
        protagonistClass: '流浪剑客',
        personality: '寡言但重情',
        protagonistBackground: '为寻找失踪的兄长而踏上群岛。',
        openingScene: '咸腥的海风掀起他的衣角，码头上一片嘈杂。',
        openingOptions: ['登上渡船', '询问码头工人', '前往酒馆打听消息'],
        customAttributes: const [
          CustomAttributeItem(
            id: 'sanity',
            name: '理智',
            value: '88/100',
            currentValue: 88,
            maxValue: 100,
          ),
        ],
        selectedCharacters: [
          AdventureSelectedCharacter(
            id: 'protagonist',
            characterId: 'protagonist',
            characterName: '林述',
            isProtagonist: true,
            narrativeRole: AdventureCharacterRole.protagonist,
            sortOrder: 0,
            characterCardJson: {
              'name': '林述',
              'gender': '男',
              'age': '二十四',
              'profession': '流浪剑客',
              'personality': '寡言但重情',
              'description': '为寻找失踪的兄长而踏上群岛。',
              'custom_attributes': [
                {'id': 'sanity', 'name': '理智', 'value': '88/100'},
              ],
            },
          ),
          AdventureSelectedCharacter(
            id: 'companion_1',
            characterId: 'companion_1',
            characterName: '苏晚',
            narrativeRole: AdventureCharacterRole.companion,
            sortOrder: 1,
            characterCardJson: {
              'name': '苏晚',
              'personality': '机敏',
              'custom_attributes': [
                {'id': 'affinity', 'name': '好感度', 'value': '60/100'},
              ],
            },
          ),
        ],
        characterRelationships: [
          AdventureCharacterRelationship(
            id: 'protagonist__companion_1',
            sourceCharacterId: 'protagonist',
            targetCharacterId: 'companion_1',
            relationType: AdventureRelationType.companion,
            description: '同行的旧识',
          ),
        ],
        supportingCharacters: [
          SupportingCharacter(
            id: 'companion_1',
            name: '苏晚',
            role: '航海士',
            relation: '同伴',
            personality: '机敏',
            customAttributes: const [
              CustomAttributeItem(
                id: 'affinity',
                name: '好感度',
                value: '60/100',
                currentValue: 60,
                maxValue: 100,
              ),
            ],
          ),
        ],
        npcSnapshots: [
          AdventureNpcSnapshot(
            assetId: 'npc_old_sailor',
            name: '老水手',
            originWorldviewId: 'wv_mist',
            npcJson: {'name': '老水手', 'role': '码头向导'},
          ),
        ],
      );

  test('saveAdventurePreview persists a fully restorable preview', () async {
    final saved = await controller.saveAdventurePreview(
      id: 'wizard_preview_test',
      name: '雾隐群岛 · 冒险预览',
      worldviewName: '雾隐群岛',
      worldviewDesc: '常年被浓雾笼罩的群岛，暗流涌动。',
      config: richConfig(),
    );
    expect(saved, isTrue);

    final rows = await libraryRepo.getAdventureTemplates();
    final row = rows.firstWhere((t) => t['id'] == 'wizard_preview_test');
    expect(row['status'], 'draft');
    expect(row['worldview_name'], '雾隐群岛');

    final preset = controller.buildPresetData(row);
    expect(preset, isNotNull);
    expect(preset!.restoredConfig, isNotNull);

    final restored = preset.restoredConfig!;
    expect(restored.worldview, '雾隐群岛');
    expect(restored.name, '林述');
    expect(restored.protagonistClass, '流浪剑客');
    expect(restored.openingScene, contains('咸腥的海风'));
    expect(restored.openingOptions, ['登上渡船', '询问码头工人', '前往酒馆打听消息']);
    expect(restored.selectedCharacters, hasLength(2));
    expect(restored.characterRelationships, hasLength(1));
    expect(restored.characterRelationships.single.relationType,
        AdventureRelationType.companion);
    expect(restored.customAttributes.single.name, '理智');
    expect(restored.supportingCharacters.map((c) => c.name), contains('苏晚'));
    expect(
      restored.supportingCharacters
          .firstWhere((c) => c.id == 'companion_1')
          .customAttributes
          .single
          .name,
      '好感度',
    );
    expect(restored.npcSnapshots.single.assetId, 'npc_old_sailor');
    expect(restored.npcSnapshots.single.npcJson['role'], '码头向导');
  });

  test('legacy templates without the preview marker still parse', () {
    final preset = controller.buildPresetData({
      'id': 'legacy',
      'name': '旧预设',
      'worldview_name': '旧世界',
      'worldview_desc': '旧世界描述',
      'char_data_json':
          '{"name":"旧主角","gender":"女","profession":"法师","openingScene":"开场",'
              '"options":["a","b"]}',
      'npc_data_json': '{"npcs":[{"name":"旧NPC","role":"向导"}]}',
    });
    expect(preset, isNotNull);
    expect(preset!.restoredConfig, isNull);
    expect(preset.charName, '旧主角');
    expect(preset.profession, '法师');
    expect(preset.openingScene, '开场');
    expect(preset.options, ['a', 'b']);
    expect(preset.supportingCharacters.single.name, '旧NPC');
  });
}
