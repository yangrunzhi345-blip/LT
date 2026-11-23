import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/models/completion_params.dart';
import 'package:lt_dialogue/services/ai_generator_service.dart';
import 'package:lt_dialogue/services/character_card_generation_guard.dart';
import 'package:lt_dialogue/services/detailed_character_generation_coordinator.dart';
import 'package:lt_dialogue/services/llm_service.dart';

String _long(String text, {int times = 12}) =>
    List<String>.filled(times, text).join();

class _FakeLlmService extends LLMService {
  _FakeLlmService(this.respond)
      : super(const LLMConfig(
          provider: LLMProvider.deepseek,
          apiKey: 'test-key',
          baseUrl: 'https://example.invalid',
          model: 'deepseek-flash',
        ));

  final String Function(String prompt, GenerationTaskHandle? handle) respond;
  final List<String> prompts = [];

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
    prompts.add(prompt);
    final response = respond(prompt, taskHandle);
    onChunk(response);
    onDone();
    return LLMStreamResult(
      content: response,
      finishReason: LLMFinishReason.stop,
      responseCompleted: true,
    );
  }
}

const _identityMarker = '提炼或设计角色的核心身份定位';
const _appearanceMarker = '请提取并细化角色的生动外貌肖像与身材体格特征';
const _worldviewSupplementMarker = '这是同一个世界观的续写/补全';

Map<String, dynamic> _identity({String name = '艾莉诺亚', String gender = '女'}) => {
      'name': name,
      'gender': gender,
      'age': '22',
      'profession': '学者',
      'archetype': '求真者',
      'personality': _long('她克制而执着。'),
    };

Map<String, dynamic> _appearance({bool withBody = true}) => {
      'appearance': _long('银色长发与月白学者袍十分醒目。'),
      if (withBody) 'bodyDescription': _long('高挑纤细，左肩留有禁印。'),
    };

Map<String, dynamic> _background({
  bool npc = false,
  bool withRp = true,
}) =>
    {
      'description': _long(npc ? '她在港口的酒馆里替各方传递消息。' : '她逃离神殿后调查被篡改的历史。'),
      'faction': '遗民会',
      'home_location': '地下档案库',
      'public_goal': _long('寻找第七石板。'),
      'hidden_motivation': _long('证明导师清白。'),
      'relationship_notes': _long('她拒绝伤害无辜者。'),
      if (withRp) ...{
        'scenario': _long('雨夜的观测塔里，她邀请来访者解读石板。'),
        'first_mes': _long('请不要触碰石板，它会记住谎言。'),
        'mes_example': _long('访客：你相信我吗？\n艾莉诺亚：我暂时需要同行者。'),
        'speaking_style': _long('她说话简短、克制，习惯先给出结论。'),
        'character_arc': _long('她可能从独行者变成愿意托付同伴的人。'),
      },
    };

void main() {
  group('JSON parse failure never leaks raw output', () {
    test('retries once with a corrective prompt and then succeeds', () async {
      var calls = 0;
      final fake = _FakeLlmService((prompt, _) {
        calls++;
        if (calls == 1) return '这不是 JSON，只是一段解释。';
        return jsonEncode(_identity(name: '雪奈'));
      });

      final result =
          await AiGeneratorService(fake).textToCharacterCard('女主，星辉治愈师');

      expect(calls, 2);
      expect(fake.prompts[1], contains('上一次输出无法解析为合法 JSON'));
      expect(fake.prompts[1], contains('请严格只返回 JSON 对象'));
      expect(result['name'], '雪奈');
    });

    test('fails with an explicit exception after two attempts, no fallback',
        () async {
      final fake = _FakeLlmService((prompt, _) => '{"name":"缺字段"');
      await expectLater(
        AiGeneratorService(fake).textToWorldview('普通世界'),
        throwsA(isA<FormatException>()),
      );
      expect(fake.prompts, hasLength(2));
    });

    test('a missing gender is a parse failure, not a default female', () async {
      final fake = _FakeLlmService(
          (prompt, _) => jsonEncode(_identity()..remove('gender')));
      await expectLater(
        AiGeneratorService(fake).textToCharacterCard('无名角色'),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('gender'),
          ),
        ),
      );
      expect(fake.prompts, hasLength(2));
    });
  });

  group('fastMode world_profile is a Map', () {
    test('decodes the parser JSON text before returning', () async {
      final fake = _FakeLlmService((prompt, _) => jsonEncode({
            ..._identity(),
            'background': '背景',
            'appearance': '外貌',
            'world_profile': {
              'faction': '遗民会',
              'home_location': '档案库',
            },
          }));

      final result = await AiGeneratorService(fake)
          .textToDetailedCharacterCard('艾莉诺亚', fastMode: true);

      expect(result['world_profile'], isA<Map<String, dynamic>>());
      expect(
        (result['world_profile'] as Map)['faction'],
        '遗民会',
      );
    });
  });

  group('NPC routing differs from protagonist routing', () {
    test('NPC prompt carries the supporting-character directive', () async {
      final fake = _FakeLlmService((prompt, _) {
        if (prompt.contains(_identityMarker)) return jsonEncode(_identity());
        if (prompt.contains(_appearanceMarker)) {
          return jsonEncode(_appearance(withBody: false));
        }
        return jsonEncode(_background(npc: true));
      });

      final result = await AiGeneratorService(fake).textToDetailedCharacterCard(
        '酒馆里的情报贩子',
        isNpc: true,
      );

      expect(fake.prompts.first, contains('NPC / 配角'));
      expect(result['bodyDescription'], '');
      expect(result['speaking_style'], isNotEmpty);
      expect(result['first_mes'], isNotEmpty);
    });

    test('protagonist prompt keeps the protagonist directive', () async {
      final fake = _FakeLlmService((prompt, _) {
        if (prompt.contains(_identityMarker)) return jsonEncode(_identity());
        if (prompt.contains(_appearanceMarker)) {
          return jsonEncode(_appearance());
        }
        return jsonEncode(_background());
      });

      await AiGeneratorService(fake).textToDetailedCharacterCard('主角，叛逃学者');

      expect(fake.prompts.first, contains('玩家主角'));
      expect(fake.prompts.first, isNot(contains('NPC / 配角')));
    });

    test('NPC guard does not require bodyDescription or a full history', () {
      const guard = CharacterCardGenerationGuard();
      final npc = {
        'name': '酒保',
        'gender': '男',
        'age': '40',
        'profession': '情报贩子',
        'personality': _long('他圆滑、谨慎，从不主动站队。', times: 8),
        'appearance': _long('独眼、围裙与一串黄铜钥匙。', times: 8),
        'scenario': _long('他在吧台后压低声音兜售情报。', times: 4),
        'speaking_style': _long('说话短促，喜欢用反问。', times: 4),
        'world_profile': {
          'faction': '港口黑市',
          'home_location': '白港酒馆',
          'public_goal': _long('维持自己的情报网。', times: 6),
          'hidden_motivation': _long('为失踪的妹妹留一条退路。', times: 7),
        },
      };

      final npcReport =
          guard.evaluate(card: npc, targetCharacters: 100, isNpc: true);
      expect(
        npcReport.requiredModulesReady,
        isTrue,
        reason: npcReport.moduleReadiness.toString(),
      );
      expect(
        guard.evaluate(card: npc, targetCharacters: 100).requiredModulesReady,
        isFalse,
      );
    });
  });

  group('Soft target degradation', () {
    test('worldview returns the best result with a soft flag', () async {
      final fake = _FakeLlmService((prompt, _) {
        if (prompt.contains('提炼与系统梳理世界观的基石')) {
          return jsonEncode({
            'name': '银月界',
            'description': _long('银月界由潮汐与月相驱动。', times: 6),
            'world_rules': _long('力量来自记忆的交换。', times: 5),
            'world_state': _long('两大城邦正围绕月门对峙。', times: 5),
          });
        }
        if (prompt.contains('地理风貌、核心据点以及活跃的核心势力与民俗生活')) {
          return jsonEncode({
            'locations': [
              {
                'name': '银月城',
                'terrain': '平原',
                'description': _long('白河沿岸的贸易城邦。', times: 4)
              },
            ],
            'factions': [
              {
                'name': '潮汐议会',
                'type': '议会',
                'ideology': '守月',
                'description': _long('控制月门的祭司集团。', times: 4)
              },
            ],
            'customs_and_life': _long('居民按月相安排作息与集市。', times: 4),
          });
        }
        if (prompt.contains('历史编年大事件、核心专有名词表')) {
          return jsonEncode({
            'timeline': [
              {'era': '初月纪', 'event': _long('月门第一次开启。', times: 3)},
            ],
            'glossary': [
              {'term': '月门', 'definition': _long('连接两地的古代通道。', times: 3)},
            ],
            'creative_constraints': _long('记忆交换不可逆。', times: 4),
          });
        }
        if (prompt.contains(_worldviewSupplementMarker)) {
          return jsonEncode({'modules': <String, dynamic>{}});
        }
        return jsonEncode({'name': '银月界', 'description': '概述'});
      });

      final result = await AiGeneratorService(fake).textToDetailedWorldview(
        '银月与潮汐的世界',
        targetTotalCharacters: 6000,
      );

      expect(result['generation_soft_incomplete'], isTrue);
      expect(result['detail_json'], isA<Map>());
    });

    test('character coordinator returns a complete card with a soft flag',
        () async {
      final card = {
        'name': '艾莉诺亚',
        'gender': '女',
        'age': '22',
        'profession': '学者',
        'description': _long('她逃离神殿后调查被篡改的历史。'),
        'personality': _long('她克制而执着，会为真相承担代价。'),
        'appearance': _long('银色长发与月白学者袍十分醒目。'),
        'scenario': _long('雨夜的观测塔里，她邀请来访者解读石板。'),
        'first_mes': _long('请不要触碰石板，它会记住谎言。'),
        'world_profile': {
          'faction': '遗民会',
          'home_location': '地下档案库',
          'public_goal': _long('寻找第七石板。'),
          'hidden_motivation': _long('证明导师清白。'),
        },
      };

      final result = await const DetailedCharacterGenerationCoordinator(
        maximumSupplementRounds: 1,
      ).complete(
        initial: card,
        targetTotalCharacters: 20000,
        requestSupplement: (_, __) async =>
            {'weakness': _long('每次共鸣都会带来短暂失明。')},
      );

      expect(result['generation_soft_incomplete'], isTrue);
      expect(result['weakness'], isNotEmpty);
    });
  });

  group('Cancellation', () {
    test('a cancelled detailed character request stops before the next stage',
        () async {
      final handle = GenerationTaskHandle();
      var identityCalls = 0;
      final fake = _FakeLlmService((prompt, taskHandle) {
        if (prompt.contains(_identityMarker)) {
          identityCalls++;
          taskHandle?.cancel();
          return jsonEncode(_identity());
        }
        if (prompt.contains(_appearanceMarker)) {
          return jsonEncode(_appearance());
        }
        return jsonEncode(_background());
      });

      await expectLater(
        AiGeneratorService(fake).textToDetailedCharacterCard(
          '艾莉诺亚',
          taskHandle: handle,
        ),
        throwsA(isA<GenerationCancelledException>()),
      );

      expect(identityCalls, 1);
      expect(
        fake.prompts.where((p) => p.contains(_appearanceMarker)),
        isEmpty,
      );
    });
  });
}
