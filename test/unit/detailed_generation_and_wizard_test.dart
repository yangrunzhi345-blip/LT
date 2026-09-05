import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lt_dialogue/models/completion_params.dart';
import 'package:lt_dialogue/models/resource_library_mode.dart';
import 'package:lt_dialogue/models/worldview_details.dart';
import 'package:lt_dialogue/services/ai_generator_service.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/llm_service.dart';
import 'package:lt_dialogue/services/repositories/library_repository_impl.dart';

/// Fake LLMService allowing programmable streaming responses and tracking message history
class FakeLLMService extends LLMService {
  final String Function(List<Map<String, String>> messages)? onCall;
  final List<List<Map<String, String>>> receivedCallMessages = [];

  FakeLLMService({this.onCall})
      : super(const LLMConfig(
          provider: LLMProvider.deepseek,
          apiKey: 'test-key',
          baseUrl: 'https://api.deepseek.com',
          model: 'deepseek-v4-pro',
        ));

  @override
  Future<String> sendMessageStream(
    List<Map<String, String>> messages,
    void Function(String chunk) onChunk,
    void Function() onDone, {
    void Function(String reasoningChunk)? onReasoningChunk,
    CompletionParams params = const CompletionParams(),
    GenerationTaskHandle? taskHandle,
  }) async {
    receivedCallMessages.add(
      messages.map((m) => Map<String, String>.from(m)).toList(),
    );
    final response = onCall != null ? onCall!(messages) : '{}';
    onChunk(response);
    onDone();
    return response;
  }
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  late Directory tempDir;
  late LibraryRepositoryImpl libraryRepo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('lt_detailed_gen_test_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
    libraryRepo = LibraryRepositoryImpl(getDb: () => DatabaseService.database);
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  group('Same-Context Multi-Turn Generation & Persistence Tests', () {
    test('Detailed Worldview: executes 4 continuous turns in same session and builds 9 modules', () async {
      int turnCount = 0;
      final stagesReported = <String>[];

      final fakeLlm = FakeLLMService(
        onCall: (messages) {
          turnCount++;
          if (turnCount == 1) {
            return jsonEncode({
              'name': '天枢星穹界',
              'description': '天枢星穹界：星轨机械与玄奥灵力共存的大陆',
              'world_rules': '灵气由天枢星环投射，机械核心驱动道法运转。',
              'world_state': '星环正在缓缓停转，各大仙枢门派彼此争夺星晶。',
            });
          } else if (turnCount == 2) {
            return jsonEncode({
              'locations': [
                {
                  'name': '星枢城',
                  'terrain': '浮空核心',
                  'description': '悬浮于万仞云海之上的机械核心枢纽。',
                },
                {
                  'name': '荒芜蚀谷',
                  'terrain': '禁忌深渊',
                  'description': '星屑残渣堆积的禁地。',
                },
              ],
            });
          } else if (turnCount == 3) {
            return jsonEncode({
              'factions': [
                {
                  'name': '天枢议会',
                  'doctrine': '掌控星晶配给',
                  'description': '执政者机构。',
                },
                {
                  'name': '锈蚀隐修会',
                  'doctrine': '复苏旧神古机',
                  'description': '地下教团。',
                },
              ],
              'customs_and_life': '日常以星纹机械代步，佩戴灵压调和表。',
            });
          } else {
            return jsonEncode({
              'timeline': [
                {
                  'era': '100年前',
                  'event': '天枢坠落，星环建立。',
                },
              ],
              'glossary': [
                {
                  'term': '星晶',
                  'definition': '提供能量的核心矿石。',
                },
              ],
              'creative_constraints': '不得出现任何非星能驱动的超自然神迹。',
            });
          }
        },
      );

      final service = AiGeneratorService(fakeLlm);
      final result = await service.textToDetailedWorldviewMultiTurn(
        '蒸汽朋克修真浮空城',
        onProgress: (cur, tot, stage) {
          stagesReported.add('[$cur/$tot] $stage');
        },
      );

      expect(turnCount, equals(4));
      expect(stagesReported.length, equals(4));
      expect(result['name'], equals('天枢星穹界'));
      expect(result['description'], contains('天枢星穹界'));

      // Verify same-context progression:
      // Turn 1 has system + user_1 (2 messages)
      expect(fakeLlm.receivedCallMessages[0].length, equals(2));
      expect(fakeLlm.receivedCallMessages[0][0]['role'], equals('system'));
      expect(fakeLlm.receivedCallMessages[0][1]['role'], equals('user'));

      // Turn 2 has system + user_1 + assistant_1 + user_2 (4 messages)
      expect(fakeLlm.receivedCallMessages[1].length, equals(4));
      expect(fakeLlm.receivedCallMessages[1][2]['role'], equals('assistant'));
      expect(fakeLlm.receivedCallMessages[1][3]['role'], equals('user'));

      // Turn 3 has 6 messages
      expect(fakeLlm.receivedCallMessages[2].length, equals(6));

      // Turn 4 has 8 messages
      expect(fakeLlm.receivedCallMessages[3].length, equals(8));

      // Verify all 9 modules assembled in detail_json
      final detailPayload = result['detail_json'] as Map<String, dynamic>;
      final modules = detailPayload['modules'] as Map<String, dynamic>;
      expect(modules['overview']['summary'], contains('星轨机械'));
      expect(modules['world_rules']['content'], contains('天枢星环'));
      expect(modules['world_state']['content'], contains('星环正在缓缓停转'));
      expect(modules['locations']['content'], contains('星枢城'));
      expect(modules['factions']['content'], contains('天枢议会'));
      expect(modules['customs_and_life']['content'], contains('星纹机械'));
      expect(modules['timeline']['content'], contains('100年前'));
      expect(modules['glossary']['content'], contains('星晶'));
      expect(modules['creative_constraints']['content'], contains('非星能驱动'));
    });

    test('Detailed Character Card: executes 3 continuous turns in same session and builds full profile', () async {
      int turnCount = 0;
      final stagesReported = <String>[];

      final fakeLlm = FakeLLMService(
        onCall: (messages) {
          turnCount++;
          if (turnCount == 1) {
            return jsonEncode({
              'name': '雷恩·克莱因',
              'gender': '男',
              'age': '26',
              'profession': '星轨机械游侠',
              'personality': '外冷内热，重情重义，谨小慎微',
            });
          } else if (turnCount == 2) {
            return jsonEncode({
              'appearance': '身着防风皮风衣，左眼佩戴黄铜多联棱镜单镜片。',
              'bodyDescription': '身材精悍结实，右手小臂为精工锻造的星铜义肢。',
            });
          } else {
            return jsonEncode({
              'background': '曾是星枢城警卫队的王牌工匠，因发现议会走私禁药被迫逃离。',
              'faction': '荒原流浪工匠联盟',
              'home_location': '星枢下层街区“锈水街”',
              'public_goal': '寻找失踪的妹妹',
              'hidden_motivation': '向天枢议会第三席复仇',
              'secrets': ['右手的义肢中藏有一枚禁忌的原生星核碎片'],
              'ability_source': '星纹回路与机械义肢过载',
              'ability_cost': '每次过载都会侵蚀神经并消耗高纯度润滑机油',
              'taboos': ['绝不向任何人透露妹妹的下落', '绝不背弃同伴'],
              'relationship_notes': '与主角曾经共同从荒芜蚀谷逃生，彼此生死托付。',
            });
          }
        },
      );

      final service = AiGeneratorService(fakeLlm);
      final result = await service.textToDetailedCharacterCard(
        '蒸汽朋克游侠',
        worldview: '天枢星穹界，机械与灵力交织',
        onProgress: (cur, tot, stage) {
          stagesReported.add('[$cur/$tot] $stage');
        },
      );

      expect(turnCount, equals(3));
      expect(stagesReported.length, equals(3));
      expect(result['name'], equals('雷恩·克莱因'));
      expect(result['gender'], equals('男'));
      expect(result['age'], equals('26'));
      expect(result['profession'], equals('星轨机械游侠'));
      expect(result['personality'], contains('外冷内热'));
      expect(result['appearance'], contains('黄铜多联棱镜'));
      expect(result['bodyDescription'], contains('精工锻造的星铜义肢'));
      expect(result['description'], contains('星枢城警卫队'));

      // Verify same-context session progression:
      expect(fakeLlm.receivedCallMessages[0].length, equals(2)); // system + user_1
      expect(fakeLlm.receivedCallMessages[1].length, equals(4)); // + assistant_1 + user_2
      expect(fakeLlm.receivedCallMessages[2].length, equals(6)); // + assistant_2 + user_3

      final profile = result['world_profile'] as Map<String, dynamic>;
      expect(profile['faction'], equals('荒原流浪工匠联盟'));
      expect(profile['home_location'], contains('锈水街'));
      expect(profile['public_goal'], contains('寻找失踪的妹妹'));
      expect(profile['hidden_motivation'], contains('复仇'));
      expect(profile['ability_source'], contains('星纹回路'));
      expect(profile['ability_cost'], contains('机油'));
      expect(profile['taboos'], contains('绝不背弃同伴'));
      expect(profile['relationship_notes'], contains('彼此生死托付'));
    });

    test('Concise modes remain single-turn and functional', () async {
      final fakeLlm = FakeLLMService(
        onCall: (messages) {
          return jsonEncode({
            'name': '简易世界',
            'description': '这是一个简易世界的背景法则设定，包含了基本的力量体系与世界格局。',
          });
        },
      );

      final service = AiGeneratorService(fakeLlm);
      final result = await service.textToWorldview('简易 prompt');
      expect(fakeLlm.receivedCallMessages.length, equals(1));
      expect(result['name'], equals('简易世界'));
    });

    test('Concise character generation embeds associated character and specified relation', () async {
      final fakeLlm = FakeLLMService(
        onCall: (messages) {
          return jsonEncode({
            'name': '雪奈',
            'gender': '女',
            'age': '21',
            'profession': '星辉治愈师',
            'personality': '温柔体贴，默默支持同伴',
            'background': '自幼与烬澜在星契者神殿一同受训的青梅竹马。',
          });
        },
      );

      final service = AiGeneratorService(fakeLlm);
      final result = await service.textToCharacterCard(
        '女主',
        worldview: '星契者大陆',
        associatedCharacters: [
          {
            'name': '烬澜',
            'gender': '男',
            'profession': '星契者学徒',
            'personality': '沉稳勇敢',
            'relation': '青梅竹马 / 命定伴侣',
          }
        ],
      );

      expect(result['name'], equals('雪奈'));
      expect(result['gender'], equals('女'));
      expect(fakeLlm.receivedCallMessages.length, equals(1));
      final sentContent = fakeLlm.receivedCallMessages.first.last['content'] ?? '';
      expect(sentContent, contains('烬澜'));
      expect(sentContent, contains('与新角色的指定关系：青梅竹马 / 命定伴侣'));
      expect(sentContent, contains('星契者学徒'));
    });

    test('Detailed character generation embeds associated character and relation into Turn 1 and Turn 3', () async {
      int turnCount = 0;
      final fakeLlm = FakeLLMService(
        onCall: (messages) {
          turnCount++;
          if (turnCount == 1) {
            return jsonEncode({
              'name': '瑟琳娜',
              'gender': '女',
              'age': '22',
              'profession': '神圣奥术师',
              'personality': '表面冷傲，实则极度在乎搭档',
            });
          } else if (turnCount == 2) {
            return jsonEncode({
              'appearance': '银色长发，淡紫双眸。',
              'bodyDescription': '修长轻盈。',
            });
          } else {
            return jsonEncode({
              'description': '与烬澜曾经生死与共，结下宿命契约。',
              'faction': '星契者守卫团',
              'relationship_notes': '对烬澜怀有深厚羁绊与微妙情感。',
            });
          }
        },
      );

      final service = AiGeneratorService(fakeLlm);
      final result = await service.textToDetailedCharacterCard(
        '女主角',
        worldview: '星穹大陆',
        associatedCharacters: [
          {
            'name': '烬澜',
            'profession': '星契者剑士',
            'personality': '刚毅坚韧',
            'relation': '恋人 / 命定伴侣',
          }
        ],
      );

      expect(turnCount, equals(3));
      expect(result['name'], equals('瑟琳娜'));
      // Check Turn 1 prompt
      final turn1UserPrompt = fakeLlm.receivedCallMessages[0].last['content'] ?? '';
      expect(turn1UserPrompt, contains('【已有关联角色与指定羁绊】'));
      expect(turn1UserPrompt, contains('烬澜'));
      expect(turn1UserPrompt, contains('与新角色设定关系：恋人 / 命定伴侣'));

      // Check Turn 3 prompt
      final turn3UserPrompt = fakeLlm.receivedCallMessages[2].last['content'] ?? '';
      expect(turn3UserPrompt, contains('【重要：羁绊背景融合】'));
      expect(turn3UserPrompt, contains('烬澜（设定关系：恋人 / 命定伴侣）'));
    });

    test('Persistence: Worldview with detail_json and all adopted characters auto-save to database', () async {
      // 1. Save detailed worldview
      const wvId = 'wv_test_1001';
      const details = WorldviewDetails(
        mode: WorldviewEditingMode.detailed,
        modules: {
          'overview': {'summary': '机械神殿与浮空浮岛'},
          'world_rules': '灵气潮汐每12小时涨落一次',
        },
      );

      await libraryRepo.saveWorldviewPreset(
        id: wvId,
        name: '浮空神域',
        description: '漂浮在云海中的遗迹大陆',
        entriesJson: '[]',
        now: DateTime.now().toIso8601String(),
        detailJson: details.encode(),
        mode: ResourceLibraryMode.adventure,
      );

      // Verify saved worldview preset in database
      final presets = await libraryRepo.getWorldviewPresets(mode: ResourceLibraryMode.adventure);
      expect(presets.any((w) => w['id'] == wvId), isTrue);
      final savedWv = presets.firstWhere((w) => w['id'] == wvId);
      expect(savedWv['name'], equals('浮空神域'));
      expect(savedWv['detail_json'], contains('灵气潮汐'));

      // 2. Save adopted characters associated with wvId
      final char1Json = jsonEncode({
        'name': '亚瑟',
        'gender': '男',
        'age': '24',
        'profession': '魔导剑士',
        'personality': '勇敢坚毅',
        'description': '来自浮空城边境的剑士',
      });
      final char2Json = jsonEncode({
        'name': '薇薇安',
        'gender': '女',
        'age': '22',
        'profession': '星穹学者',
        'personality': '聪慧好奇',
        'description': '研究古代浮岛核心的占星术士',
      });

      await libraryRepo.saveCharacterCard(
        id: 'char_001',
        name: '亚瑟',
        jsonData: char1Json,
        source: '冒险向导',
        now: DateTime.now().toIso8601String(),
        matchingWorldviewId: wvId,
        mode: ResourceLibraryMode.adventure,
      );

      await libraryRepo.saveCharacterCard(
        id: 'char_002',
        name: '薇薇安',
        jsonData: char2Json,
        source: '冒险向导',
        now: DateTime.now().toIso8601String(),
        matchingWorldviewId: wvId,
        mode: ResourceLibraryMode.adventure,
      );

      // Verify both adopted characters are persisted to SQLite table character_cards
      final characters = await libraryRepo.getCharacterCards(mode: ResourceLibraryMode.adventure);
      expect(characters.length, equals(2));

      final arthur = characters.firstWhere((c) => c['id'] == 'char_001');
      expect(arthur['name'], equals('亚瑟'));
      expect(arthur['matching_worldview_id'], equals(wvId));

      final vivian = characters.firstWhere((c) => c['id'] == 'char_002');
      expect(vivian['name'], equals('薇薇安'));
      expect(vivian['matching_worldview_id'], equals(wvId));
    });
  });
}
