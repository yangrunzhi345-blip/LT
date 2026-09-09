import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lt_dialogue/models/completion_params.dart';
import 'package:lt_dialogue/models/resource_library_mode.dart';
import 'package:lt_dialogue/models/worldview_details.dart';
import 'package:lt_dialogue/services/ai_generator_service.dart';
import 'package:lt_dialogue/services/api_error.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/detailed_worldview_generation_coordinator.dart';
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
  Future<LLMStreamResult> sendMessageStreamDetailed(
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
    return LLMStreamResult(
      content: response,
      finishReason: LLMFinishReason.stop,
      responseCompleted: true,
    );
  }

  @override
  Future<String> sendMessageStream(
    List<Map<String, String>> messages,
    void Function(String chunk) onChunk,
    void Function() onDone, {
    void Function(String reasoningChunk)? onReasoningChunk,
    CompletionParams params = const CompletionParams(),
    GenerationTaskHandle? taskHandle,
  }) async {
    final result = await sendMessageStreamDetailed(
      messages,
      onChunk,
      onDone,
      onReasoningChunk: onReasoningChunk,
      params: params,
      taskHandle: taskHandle,
    );
    return result.content;
  }
}

String _targetLengthSupplement() => jsonEncode({
      'modules': {
        for (final module in [
          'overview',
          'world_rules',
          'world_state',
          'locations',
          'factions',
          'customs_and_life',
          'timeline',
          'glossary',
          'creative_constraints',
        ])
          module: {'content': List.filled(50000, module[0]).join()},
      },
    });

class _TruncationSimulatingLLMService extends LLMService {
  int truncatedCallCount = 0;
  bool stateErrorRetried = false;
  int _stage2CallCount = 0;

  _TruncationSimulatingLLMService()
      : super(const LLMConfig(
          provider: LLMProvider.deepseek,
          apiKey: 'test-key',
          baseUrl: 'https://api.deepseek.com',
          model: 'deepseek-v4-pro',
        ));

  @override
  Future<LLMStreamResult> sendMessageStreamDetailed(
    List<Map<String, String>> messages,
    void Function(String chunk) onChunk,
    void Function() onDone, {
    void Function(String reasoningChunk)? onReasoningChunk,
    CompletionParams params = const CompletionParams(),
    GenerationTaskHandle? taskHandle,
  }) async {
    final prompt = messages.last['content'] ?? '';
    if (prompt.contains('同一个世界观的续写')) {
      final response = _targetLengthSupplement();
      onChunk(response);
      onDone();
      return LLMStreamResult(
        content: response,
        finishReason: LLMFinishReason.stop,
        responseCompleted: true,
      );
    } else if (prompt.contains('宏观物理与超自然法则体系')) {
      truncatedCallCount++;
      const truncatedText =
          '{"name": "艾尔德兰", "description": "源流交织的宏大魔导世界", "world_rules": "源流是宇宙能量", "world_state": "当前时代动荡格局';
      onChunk(truncatedText);
      return const LLMStreamResult(
        content: truncatedText,
        finishReason: LLMFinishReason.length,
        responseCompleted: true,
      );
    } else if (prompt.contains('提取并深入推演该世界的地理风貌、核心据点')) {
      _stage2CallCount++;
      if (_stage2CallCount == 1) {
        stateErrorRetried = true;
        throw StateError('模型响应未完整完成，不能使用部分结果');
      }
      final response = jsonEncode({
        'locations': [
          {
            'name': '天空城',
            'terrain': '浮空岛屿',
            'description': '漂浮在云海中的古老城市。',
          },
        ],
      });
      onChunk(response);
      return LLMStreamResult(
        content: response,
        finishReason: LLMFinishReason.stop,
        responseCompleted: true,
      );
    } else if (prompt.contains('提取并深入推演该世界的核心势力、政权、宗派')) {
      final response = jsonEncode({
        'factions': [
          {
            'name': '高天神族',
            'type': '神权',
            'ideology': '维护天理',
            'description': '统治高天的神圣族群。',
          },
        ],
      });
      onChunk(response);
      return LLMStreamResult(
        content: response,
        finishReason: LLMFinishReason.stop,
        responseCompleted: true,
      );
    } else if (prompt.contains('宏篇推演与提炼该世界的社会民俗、民众生活全貌')) {
      final response = jsonEncode({
        'customs_and_life': '民间保留着古老的崇拜仪式。',
      });
      onChunk(response);
      return LLMStreamResult(
        content: response,
        finishReason: LLMFinishReason.stop,
        responseCompleted: true,
      );
    } else if (prompt.contains('历史纪元大事件、核心专有名词表以及创作铁律')) {
      final response = jsonEncode({
        'timeline': [
          {
            'era': '第一纪元',
            'event': '创世之初，天理降临。',
          },
        ],
        'glossary': [
          {
            'term': '源流',
            'definition': '万物之基。',
          },
        ],
        'creative_constraints': '不可打破法则约束。',
      });
      onChunk(response);
      return LLMStreamResult(
        content: response,
        finishReason: LLMFinishReason.stop,
        responseCompleted: true,
      );
    }
    return const LLMStreamResult(
      content: '{}',
      finishReason: LLMFinishReason.stop,
      responseCompleted: true,
    );
  }

  @override
  Future<String> sendMessageStream(
    List<Map<String, String>> messages,
    void Function(String chunk) onChunk,
    void Function() onDone, {
    void Function(String reasoningChunk)? onReasoningChunk,
    CompletionParams params = const CompletionParams(),
    GenerationTaskHandle? taskHandle,
  }) async {
    final result = await sendMessageStreamDetailed(
      messages,
      onChunk,
      onDone,
      onReasoningChunk: onReasoningChunk,
      params: params,
      taskHandle: taskHandle,
    );
    return result.content;
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
    test(
        'Detailed Worldview: executes 4 continuous turns in same session and builds 9 modules',
        () async {
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
              'factions': [
                {
                  'name': '天枢议会',
                  'type': '统治机构',
                  'ideology': '掌控星晶配给',
                  'description': '执政者机构。',
                },
                {
                  'name': '锈蚀隐修会',
                  'type': '地下教团',
                  'ideology': '复苏旧神古机',
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

      expect(turnCount, equals(3));
      expect(stagesReported.length, equals(2));
      expect(result['name'], equals('天枢星穹界'));
      expect(result['description'], contains('天枢星穹界'));

      // Verify same-context progression:
      // Turn 1 has system + user_1 (2 messages)
      expect(fakeLlm.receivedCallMessages[0].length, equals(2));
      expect(fakeLlm.receivedCallMessages[0][0]['role'], equals('system'));
      expect(fakeLlm.receivedCallMessages[0][1]['role'], equals('user'));

      // Turn 2 & Turn 3 are parallel workers
      expect(fakeLlm.receivedCallMessages[1].length, equals(2));
      expect(fakeLlm.receivedCallMessages[2].length, equals(2));

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

    test(
        'Detailed Worldview: massive mode (30000 chars) executes 3 stages (5 parallel workers) and repairs truncated JSON',
        () async {
      int callCount = 0;
      final stagesReported = <String>[];
      final detailedProgressReported = <DetailedWorldviewGenerationProgress>[];

      final fakeLlm = FakeLLMService(
        onCall: (messages) {
          callCount++;
          final prompt = messages.last['content'] ?? '';
          if (prompt.contains('同一个世界观的续写')) {
            return _targetLengthSupplement();
          } else if (prompt.contains('宏观物理与超自然法则体系')) {
            // Stage 1
            return jsonEncode({
              'name': '艾尔德兰',
              'description': '源流交织的宏大魔导世界',
              'world_rules': '源流是一切生命与法则的源头，天理掌管法则。',
              'world_state': '诸神黄昏之后，二十六王座统治各大疆域。',
            });
          } else if (prompt.contains('核心据点与大陆板块生态')) {
            // Stage 2A: locations (testing truncated JSON repair here!)
            return '{"locations": [{"name": "高天王座", "terrain": "至高天域", "description": "天理所居之所"}, {"name": "源流海", "terrain": "魔能海洋", "description": "无尽源流汇聚之海"';
          } else if (prompt.contains('核心势力、政权、宗派')) {
            // Stage 2B: factions
            return jsonEncode({
              'factions': [
                {
                  'name': '高天神族',
                  'type': '神权统治',
                  'ideology': '维持天理运转',
                  'description': '第一代子嗣，掌控法则权柄。',
                },
                {
                  'name': '魔女会',
                  'type': '隐秘结社',
                  'ideology': '探究源流深层真理',
                  'description': '掌握深渊原罪与高阶魔能的秘法学者。',
                },
              ],
            });
          } else if (prompt.contains('社会民俗、民众生活全貌')) {
            // Stage 3A: customs
            return jsonEncode({
              'customs_and_life': '各族以源流晶石为能源核心，民间设有向天理祈运的仪式日。',
            });
          } else if (prompt.contains('历史纪元大事件、核心专有名词表')) {
            // Stage 3B: timeline + glossary + constraints
            return jsonEncode({
              'timeline': [
                {
                  'era': '第一纪元',
                  'event': '天理创世，凝聚源流并创造神族。',
                },
              ],
              'glossary': [
                {
                  'term': '源流',
                  'definition': '宇宙能量的终极形态，万物法则之源。',
                },
              ],
              'creative_constraints': '所有超凡力量必须依托源流流动，不可凭空产生。',
            });
          }
          return '{}';
        },
      );

      final service = AiGeneratorService(fakeLlm);
      final result = await service.textToDetailedWorldviewMultiTurn(
        '艾尔德兰世界设定材料',
        targetTotalCharacters: 30000,
        onProgress: (cur, tot, stage) {
          stagesReported.add('[$cur/$tot] $stage');
        },
        onDetailedProgress: (progress) {
          detailedProgressReported.add(progress);
        },
      );

      expect(callCount, equals(6));
      expect(stagesReported.length, equals(3));
      expect(stagesReported[0], contains('[1/3]'));
      expect(stagesReported[1], contains('[2/3]'));
      expect(stagesReported[2], contains('[3/3]'));

      expect(result['name'], equals('艾尔德兰'));
      expect(result['description'], equals('源流交织的宏大魔导世界'));

      final detailPayload = result['detail_json'] as Map<String, dynamic>;
      final modules = detailPayload['modules'] as Map<String, dynamic>;
      expect(modules['overview']['summary'], contains('源流交织的宏大魔导世界'));
      expect(modules['world_rules']['content'], contains('源流是一切生命'));
      expect(modules['world_state']['content'], contains('诸神黄昏'));
      // Truncated JSON was successfully repaired!
      expect(modules['locations']['content'], contains('高天王座'));
      expect(modules['factions']['content'], contains('高天神族'));
      expect(modules['customs_and_life']['content'], contains('源流晶石'));
      expect(modules['timeline']['content'], contains('第一纪元'));
      expect(modules['glossary']['content'], contains('源流'));
      expect(modules['creative_constraints']['content'], contains('不可凭空产生'));

      // Verify completion progress reported totalQuestions: 3
      final lastProgress = detailedProgressReported.last;
      expect(lastProgress.questionCompleted, isTrue);
      expect(lastProgress.currentCharacters, greaterThanOrEqualTo(30000));
      expect(lastProgress.targetCharacters, equals(30000));
    });

    test(
        'Detailed Worldview: epic mode (50000 chars) executes 5 stages, recovers from connection closed error, and builds 9 modules',
        () async {
      int callCount = 0;
      var simulatedFailureOccurred = false;
      final stagesReported = <String>[];
      final detailedProgressReported = <DetailedWorldviewGenerationProgress>[];

      final fakeLlm = FakeLLMService(
        onCall: (messages) {
          callCount++;
          final prompt = messages.last['content'] ?? '';
          if (prompt.contains('同一个世界观的续写')) {
            return _targetLengthSupplement();
          } else if (prompt.contains('宏观物理与超自然法则体系')) {
            // Stage 1
            return jsonEncode({
              'name': '艾尔德兰',
              'description': '源流交织的宏大魔导世界，天理悬于高天永恒王座。',
              'world_rules': '源流是宇宙能量终极形态，法则严明且蕴含不可逆代价。',
              'world_state': '诸神黄昏后，二十六王座割据，魔女与教会暗流涌动。',
            });
          } else if (prompt.contains('提取并深入推演该世界的地理风貌、核心据点')) {
            // Stage 2: Locations
            return jsonEncode({
              'locations': [
                {
                  'name': '至高天域·王座之巅',
                  'terrain': '高天云海神座',
                  'description': '源流上层结构凝聚而成的法则枢纽，万物因果由此锚定。',
                },
                {
                  'name': '绝渊源流海',
                  'terrain': '液态光原初海洋',
                  'description': '一切生命与魔法法则的起源归宿，魔能狂暴莫测。',
                },
              ],
            });
          } else if (prompt.contains('提取并深入推演该世界的核心势力、政权、宗派')) {
            // Stage 3: Factions (simulate 1 transient Connection closed error!)
            if (!simulatedFailureOccurred) {
              simulatedFailureOccurred = true;
              throw const ApiError(
                type: ApiErrorType.networkTimeout,
                message:
                    'ClientException: Connection closed while receiving data, uri=https://api.deepseek.com/chat/completions',
              );
            }
            return jsonEncode({
              'factions': [
                {
                  'name': '高天神族',
                  'type': '创世神权',
                  'ideology': '守护天理运行',
                  'description': '第一代子嗣，执掌百分之百的底层法则权柄。',
                },
                {
                  'name': '二十六王座大公同盟',
                  'type': '世俗政权',
                  'ideology': '开采魔晶以争霸天下',
                  'description': '控制各大疆域与魔晶贸易命脉的人类帝国联盟。',
                },
              ],
            });
          } else if (prompt.contains('宏篇推演与提炼该世界的社会民俗、民众生活全貌')) {
            // Stage 4: Customs
            return jsonEncode({
              'customs_and_life': '民间依托魔晶采掘建立集市，崇拜源流之光，各阶层皆须在天理安息日履行肃穆的祭典祈祷。',
            });
          } else if (prompt.contains('历史纪元大事件、核心专有名词表以及创作铁律')) {
            // Stage 5: Timeline, glossary, constraints
            return jsonEncode({
              'timeline': [
                {
                  'era': '第一纪元：天理创世',
                  'event': '天理由源流中升腾，凝聚世界并创造神族子嗣。',
                },
              ],
              'glossary': [
                {
                  'term': '源流',
                  'definition': '宇宙能量的终极形态，贯穿万物的液态光。',
                },
                {
                  'term': '魔晶',
                  'definition': '天然源流结晶，支撑帝国经济命脉的超凡能源。',
                },
              ],
              'creative_constraints': '神权法则不可轻易违背，一切魔法施展必须付出源流侵蚀等价代价。',
            });
          }
          return '{}';
        },
      );

      final service = AiGeneratorService(fakeLlm);
      final result = await service.textToDetailedWorldviewMultiTurn(
        '艾尔德兰完整世界观总览',
        targetTotalCharacters: 50000,
        onProgress: (cur, tot, stage) {
          stagesReported.add('[$cur/$tot] $stage');
        },
        onDetailedProgress: (progress) {
          detailedProgressReported.add(progress);
        },
      );

      expect(simulatedFailureOccurred, isTrue);
      // 5 stages + 1 retry + 1 target-length supplement.
      expect(callCount, equals(7));
      expect(stagesReported.length, equals(5));
      expect(stagesReported[0], contains('[1/5]'));
      expect(stagesReported[1], contains('[2/5]'));
      expect(stagesReported[2], contains('[3/5]'));
      expect(stagesReported[3], contains('[4/5]'));
      expect(stagesReported[4], contains('[5/5]'));

      expect(result['name'], equals('艾尔德兰'));
      expect(result['description'], contains('源流交织'));

      final detailPayload = result['detail_json'] as Map<String, dynamic>;
      final modules = detailPayload['modules'] as Map<String, dynamic>;
      expect(modules['overview']['summary'], contains('源流交织'));
      expect(modules['world_rules']['content'], contains('源流是宇宙能量'));
      expect(modules['world_state']['content'], contains('诸神黄昏'));
      expect(modules['locations']['content'], contains('至高天域'));
      expect(modules['factions']['content'], contains('高天神族'));
      expect(modules['customs_and_life']['content'], contains('魔晶采掘'));
      expect(modules['timeline']['content'], contains('天理创世'));
      expect(modules['glossary']['content'], contains('源流结晶'));
      expect(modules['creative_constraints']['content'], contains('源流侵蚀等价代价'));

      // Verify completion progress reported totalQuestions: 5
      final lastProgress = detailedProgressReported.last;
      expect(lastProgress.questionCompleted, isTrue);
      expect(lastProgress.currentCharacters, greaterThanOrEqualTo(50000));
      expect(lastProgress.targetCharacters, equals(50000));
    });

    test(
        'Detailed Worldview: recovers from truncated output (finishReason: length) and StateError retries',
        () async {
      // Use custom sendMessageStreamDetailed to simulate length truncation on stage 1
      // and StateError on stage 2
      final customFakeLlm = _TruncationSimulatingLLMService();
      final service = AiGeneratorService(customFakeLlm);

      final result = await service.textToDetailedWorldviewMultiTurn(
        '艾尔德兰核心材料',
        targetTotalCharacters: 50000,
      );

      expect(result['name'], equals('艾尔德兰'));
      expect(result['description'], contains('源流交织'));
      final detailPayload = result['detail_json'] as Map<String, dynamic>;
      final modules = detailPayload['modules'] as Map<String, dynamic>;
      expect(modules['world_rules']['content'], contains('源流是宇宙能量'));
      expect(modules['locations']['content'], contains('天空城'));
      expect(customFakeLlm.truncatedCallCount, equals(1));
      expect(customFakeLlm.stateErrorRetried, isTrue);
    });

    test(
        'Detailed Character Card: executes 3 continuous turns in same session and builds full profile',
        () async {
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
      expect(stagesReported.length, equals(2));
      expect(result['name'], equals('雷恩·克莱因'));
      expect(result['gender'], equals('男'));
      expect(result['age'], equals('26'));
      expect(result['profession'], equals('星轨机械游侠'));
      expect(result['personality'], contains('外冷内热'));
      expect(result['appearance'], contains('黄铜多联棱镜'));
      expect(result['bodyDescription'], contains('精工锻造的星铜义肢'));
      expect(result['description'], contains('星枢城警卫队'));

      // Verify same-context session progression:
      expect(
          fakeLlm.receivedCallMessages[0].length, equals(2)); // system + user_1
      expect(fakeLlm.receivedCallMessages[1].length,
          equals(4)); // system + user_1 + assistant_1 + user_2a
      expect(fakeLlm.receivedCallMessages[2].length,
          equals(5)); // parallel call user_2b before assistant_2a completes

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

    test(
        'Detailed Character Card: repairs truncated JSON and faithfully preserves user material',
        () async {
      int callCount = 0;
      final stagesReported = <String>[];

      final fakeLlm = FakeLLMService(
        onCall: (messages) {
          callCount++;
          final prompt = messages.last['content'] ?? '';
          if (prompt.contains('提炼或设计角色的核心身份定位')) {
            // Stage 1: Returns character identity
            return jsonEncode({
              'name': '艾莉诺亚',
              'gender': '女',
              'age': '22',
              'profession': '破晓神殿圣遗物学者',
              'archetype': '追寻失落真相的叛逆学者',
              'personality': '表面优雅克制，内心热烈且对古代文明拥有偏执的好奇心',
            });
          } else if (prompt.contains('外貌肖像与身材体格特征')) {
            // Stage 2A: Intentionally return truncated JSON to test auto-repair
            return '{"appearance": "银色微卷长发，戴着单片黄铜透镜，常穿破晓神殿的月白学者袍", "bodyDescription": "身形高挑纤细，左肩烙印有神殿惩戒禁印"';
          } else {
            // Stage 2B: Background
            return jsonEncode({
              'description': '出身神殿名门，因私自破译源流石板被判处流放，逃至下层城邦。',
              'public_goal': '寻找失落的第七石板',
              'hidden_motivation': '揭露神殿篡改历史的真相',
              'ability_source': '源流共鸣与古代符文破译',
              'ability_cost': '每次共鸣后剧烈头痛并短暂失明',
              'faction': '古代文明研究遗民会',
              'home_location': '破晓旧都地宫',
              'taboos': ['绝不向神殿骑士屈服'],
              'relationship_notes': '与主角是旧识，曾共同探秘地宫。',
            });
          }
        },
      );

      final service = AiGeneratorService(fakeLlm);
      final result = await service.textToDetailedCharacterCard(
        '艾莉诺亚，22岁，女，破晓神殿的叛逃学者',
        worldview: '艾尔德兰',
        onProgress: (cur, tot, stage) {
          stagesReported.add('[$cur/$tot] $stage');
        },
      );

      expect(callCount, equals(3));
      expect(stagesReported.length, equals(2));
      expect(result['name'], equals('艾莉诺亚'));
      expect(result['appearance'], contains('银色微卷长发'));
      expect(result['bodyDescription'], contains('神殿惩戒禁印'));
      expect(result['description'], contains('破译源流石板'));
      final profile = result['world_profile'] as Map<String, dynamic>;
      expect(profile['faction'], equals('古代文明研究遗民会'));
      expect(profile['hidden_motivation'], contains('揭露神殿篡改历史'));
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

    test(
        'Concise character generation embeds associated character and specified relation',
        () async {
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
      final sentContent =
          fakeLlm.receivedCallMessages.first.last['content'] ?? '';
      expect(sentContent, contains('烬澜'));
      expect(sentContent, contains('与新角色的指定关系：青梅竹马 / 命定伴侣'));
      expect(sentContent, contains('星契者学徒'));
    });

    test(
        'Detailed character generation embeds associated character and relation into Turn 1 and Turn 3',
        () async {
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
      final turn1UserPrompt =
          fakeLlm.receivedCallMessages[0].last['content'] ?? '';
      expect(turn1UserPrompt, contains('【已有关联角色与指定羁绊】'));
      expect(turn1UserPrompt, contains('烬澜'));
      expect(turn1UserPrompt, contains('与新角色设定关系：恋人 / 命定伴侣'));

      // Check Turn 3 prompt
      final turn3UserPrompt =
          fakeLlm.receivedCallMessages[2].last['content'] ?? '';
      expect(turn3UserPrompt, contains('【重要：羁绊背景融合】'));
      expect(turn3UserPrompt, contains('烬澜（设定关系：恋人 / 命定伴侣）'));
    });

    test(
        'Persistence: Worldview with detail_json and all adopted characters auto-save to database',
        () async {
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
      final presets = await libraryRepo.getWorldviewPresets(
          mode: ResourceLibraryMode.adventure);
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
      final characters = await libraryRepo.getCharacterCards(
          mode: ResourceLibraryMode.adventure);
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
