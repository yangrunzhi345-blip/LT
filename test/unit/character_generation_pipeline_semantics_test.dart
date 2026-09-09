import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/models/completion_params.dart';
import 'package:lt_dialogue/models/worldview_details.dart';
import 'package:lt_dialogue/services/ai_generator_service.dart';
import 'package:lt_dialogue/services/character_card_storage_adapter.dart';
import 'package:lt_dialogue/services/llm_service.dart';
import 'package:lt_dialogue/services/resource_integrity_validator.dart';
import 'package:lt_dialogue/application/resource_library/edit_drafts.dart';

class _FakeLlmService extends LLMService {
  final String Function(String prompt) responseFor;
  final Future<void>? gate;
  int calls = 0;
  final List<String> prompts = [];

  _FakeLlmService(this.responseFor, {this.gate})
      : super(const LLMConfig(
          provider: LLMProvider.deepseek,
          apiKey: 'test-key',
          baseUrl: 'https://example.invalid',
          model: 'test',
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
    calls++;
    final prompt = messages.last['content'] ?? '';
    prompts.add(prompt);
    await gate;
    final response = responseFor(prompt);
    onChunk(response);
    onDone();
    return LLMStreamResult(
      content: response,
      finishReason: LLMFinishReason.stop,
      responseCompleted: true,
    );
  }
}

String _long(String text) => List<String>.filled(30, text).join();

void main() {
  group('Detailed character service pipeline', () {
    test('should share only an identical detailed generation flight', () async {
      final gate = Completer<void>();
      final fake = _FakeLlmService((prompt) {
        if (prompt.contains('这是同一张角色卡的增量补全')) {
          return jsonEncode({
            'personality': _long('她克制而执着，会为真相承担代价。'),
            'description': _long('她逃离神殿后持续调查被篡改的历史。'),
            'appearance': _long('银色长发与月白学者袍十分醒目。'),
            'bodyDescription': _long('高挑纤细，左肩留有禁印。'),
            'scenario': _long('雨夜的观测塔里，她邀请来访者解读石板。'),
            'first_mes': _long('请不要触碰石板，它会记住谎言。'),
            'world_profile': {
              'faction': '遗民会',
              'home_location': '地下档案库',
              'public_goal': _long('寻找第七石板。'),
              'hidden_motivation': _long('证明导师清白。'),
              'relationship_notes': _long('她拒绝伤害无辜者。'),
            },
          });
        }
        return jsonEncode({
          'name': '艾莉诺亚',
          'gender': '女',
          'age': '22',
          'profession': '叛逃学者',
          'personality': '执着',
          'background': '正在逃亡',
        });
      }, gate: gate.future);
      final service = AiGeneratorService(fake);

      final first = service.textToDetailedCharacterCard(
        '艾莉诺亚',
        targetTotalCharacters: 1000,
        fastMode: true,
      );
      final second = service.textToDetailedCharacterCard(
        '艾莉诺亚',
        targetTotalCharacters: 1000,
        fastMode: true,
      );
      await Future<void>.delayed(Duration.zero);
      expect(fake.calls, 1);

      gate.complete();
      final results = await Future.wait([first, second]);
      expect(results[0]['name'], '艾莉诺亚');
      expect(results[1]['name'], '艾莉诺亚');
    });

    test('should supplement an incomplete initial candidate and keep anchors',
        () async {
      final progressMessages = <String>[];
      final fake = _FakeLlmService((prompt) {
        if (prompt.contains('提炼或设计角色的核心身份定位')) {
          return jsonEncode({
            'name': '艾莉诺亚',
            'gender': '女',
            'age': '22',
            'profession': '叛逃学者',
            'personality': _long('她克制而执着，绝不放弃被掩埋的历史真相。'),
          });
        }
        if (prompt.contains('外貌肖像与身材体格特征')) {
          return jsonEncode({
            'appearance': _long('银色长发、月白学者袍与磨损的铜质透镜十分醒目。'),
            'bodyDescription': _long('高挑纤细，左肩带着神殿惩戒留下的禁印。'),
          });
        }
        if (prompt.contains('这是同一张角色卡的增量补全')) {
          return jsonEncode({
            'name': '错误名称',
            'scenario': _long('雨夜的废弃观测塔里，她邀请来访者共同解读会说话的石板。'),
            'first_mes': _long('请不要触碰石板，它会记住每一个试图说谎的人。'),
            'mes_example': _long('访客：你相信我吗？\n艾莉诺亚：我暂时需要一位同行者。'),
          });
        }
        return jsonEncode({
          'description': _long('她在破晓神殿的禁书库发现历史被篡改，因此踏上逃亡与求真的道路。'),
          'faction': '古代文明研究遗民会',
          'home_location': '破晓旧都地下档案库',
          'public_goal': _long('寻找第七石板，并将其记录的真相公布于世。'),
          'hidden_motivation': _long('证明失踪的导师并非叛徒。'),
          'relationship_notes': _long('她与城内走私者互相利用，却拒绝伤害无辜者。'),
        });
      });

      final result = await AiGeneratorService(fake).textToDetailedCharacterCard(
        '艾莉诺亚，22岁，女，破晓神殿叛逃学者',
        targetTotalCharacters: 1000,
        worldview: '魔法必须消耗记忆',
        onProgress: (_, __, message) => progressMessages.add(message),
      );

      expect(fake.calls, 4);
      expect(result['name'], '艾莉诺亚');
      expect(result['age'], '22');
      expect(result['scenario'], isNotEmpty);
      expect(result['first_mes'], isNotEmpty);
      expect(progressMessages.join('\n'), contains('当前有效内容'));
      expect(
        fake.prompts.join('\n'),
        contains('世界观硬约束：魔法必须消耗记忆'),
      );
    });
  });

  group('Canonical character payload', () {
    test('should preserve generated aliases and world profile fields', () {
      final canonical = CharacterCardStorageAdapter.canonicalizeGenerated({
        'name': '艾莉诺亚',
        'background': '叛逃背景',
        'body_description': '体态描述',
        'scenario': '场景',
        'first_mes': '开场白',
        'mes_example': '示例对话',
        'ability': '符文共鸣',
        'weakness': '失明',
        'equipment': '铜质透镜',
        'customAttributes': [
          {'name': '誓言', 'value': '不得背叛同伴'},
        ],
        'world_profile': {
          'secrets': ['第七石板藏在地下档案库'],
          'ability_cost': '损耗记忆',
        },
      });

      expect(canonical['description'], '叛逃背景');
      expect(canonical['bodyDescription'], '体态描述');
      expect(canonical['first_mes'], '开场白');
      expect(canonical['mes_example'], '示例对话');
      expect(canonical['ability'], '符文共鸣');
      expect(canonical['custom_attributes'], isNotEmpty);
      final profile = canonical['world_profile'] as Map<String, dynamic>;
      expect(profile['secrets'], ['第七石板藏在地下档案库']);
      expect(profile['ability_cost'], '损耗记忆');
    });

    test('should expose canonical generation fields as an editor draft', () {
      final draft = CharacterCardGenerationDraft.fromGenerated({
        'body_description': '体态描述',
        'custom_attributes': jsonEncode([
          {'id': 'oath', 'name': '誓言', 'value': '不得背叛同伴'},
        ]),
        'world_profile': jsonEncode({
          'faction': '白港炼金议会',
          'taboos': ['不得伪造记忆'],
        }),
      });

      expect(draft.bodyDescription, '体态描述');
      expect(draft.faction, '白港炼金议会');
      expect(draft.taboos, ['不得伪造记忆']);
      expect(draft.customAttributes.single.name, '誓言');
    });
  });

  group('ResourceIntegrityValidator detailed worldview count', () {
    test(
        'should use the deduplicating worldview guard instead of summing modules',
        () {
      final repeated = _long('重复世界观正文');
      final details = WorldviewDetails(
        mode: WorldviewEditingMode.detailed,
        modules: {
          for (final key in WorldviewDetails.moduleKeys) key: repeated,
        },
      );

      expect(
        () => ResourceIntegrityValidator.validateWorldview(
          name: '测试世界',
          description: repeated,
          details: details,
        ),
        throwsA(
          isA<ResourceValidationException>().having(
            (error) => error.message,
            'message',
            contains('当前 ${repeated.replaceAll(RegExp(r'\\s+'), '').length} 字'),
          ),
        ),
      );
    });
  });
}
