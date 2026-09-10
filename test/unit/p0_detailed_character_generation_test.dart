import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/models/completion_params.dart';
import 'package:lt_dialogue/models/generation_mode.dart';
import 'package:lt_dialogue/services/ai_generator_service.dart';
import 'package:lt_dialogue/services/character_card_generation_guard.dart';
import 'package:lt_dialogue/services/detailed_character_generation_coordinator.dart';
import 'package:lt_dialogue/services/llm_service.dart';

String _long(String text, {int times = 12}) =>
    List<String>.filled(times, text).join();

/// Records every request that reaches the transport layer.
///
/// Unlike a fake that only answers the last message, this one keeps the whole
/// message snapshot and the [CompletionParams] of every call, which is what the
/// stage-order, thinking and retry contracts are asserted against.
class _RecordingLlmService extends LLMService {
  _RecordingLlmService(this._answer)
      : super(const LLMConfig(
          provider: LLMProvider.deepseek,
          apiKey: 'test-key',
          baseUrl: 'https://example.invalid',
          model: 'test',
        ));

  final String Function(List<Map<String, String>> messages) _answer;
  final List<List<Map<String, String>>> messages = [];
  final List<CompletionParams> params = [];

  @override
  Future<LLMStreamResult> sendMessageStreamDetailed(
    List<Map<String, String>> messages,
    void Function(String chunk) onChunk,
    void Function() onDone, {
    void Function(String reasoningChunk)? onReasoningChunk,
    CompletionParams params = const CompletionParams(),
    GenerationTaskHandle? taskHandle,
  }) async {
    this
        .messages
        .add(messages.map((m) => Map<String, String>.from(m)).toList());
    this.params.add(params);
    final response = _answer(messages);
    onChunk(response);
    onDone();
    return LLMStreamResult(
      content: response,
      finishReason: LLMFinishReason.stop,
      responseCompleted: true,
    );
  }
}

const _stage1Marker = '提炼或设计角色的核心身份定位';
const _stage2aMarker = '请提取并细化角色的生动外貌肖像与身材体格特征';
const _stage2bMarker = '请深入推演角色的身世背景、深层动机';

Map<String, dynamic> _identity() => {
      'name': '艾莉诺亚',
      'gender': '女',
      'age': '22',
      'profession': '破晓神殿圣遗物学者',
      'archetype': '追寻失落真相的叛逆学者',
      'personality': _long('她克制而执着，会为真相承担代价。'),
    };

Map<String, dynamic> _appearance() => {
      'appearance': _long('银色长发与月白学者袍十分醒目。'),
      'bodyDescription': _long('高挑纤细，左肩留有神殿禁印。'),
    };

Map<String, dynamic> _background() => {
      'description': _long('她逃离神殿后持续调查被篡改的历史。'),
      'faction': '遗民会',
      'home_location': '地下档案库',
      'public_goal': _long('寻找第七石板。'),
      'hidden_motivation': _long('证明导师清白。'),
      'relationship_notes': _long('她拒绝伤害无辜者。'),
    };

int _countFor(List<List<Map<String, String>>> messages, String marker) =>
    messages
        .where((call) => (call.last['content'] ?? '').contains(marker))
        .length;

void main() {
  group('Detailed character stage ordering', () {
    test('runs Stage1 -> Stage2A -> Stage2B strictly sequentially', () async {
      final fake = _RecordingLlmService((messages) {
        final prompt = messages.last['content'] ?? '';
        if (prompt.contains(_stage1Marker)) return jsonEncode(_identity());
        if (prompt.contains(_stage2aMarker)) return jsonEncode(_appearance());
        return jsonEncode(_background());
      });

      final result = await AiGeneratorService(fake)
          .textToDetailedCharacterCard('艾莉诺亚，破晓神殿叛逃学者');

      expect(result['name'], '艾莉诺亚');
      expect(fake.messages, hasLength(3));

      // Stage1 sees only system + its own user instruction.
      expect(
          fake.messages[0].map((m) => m['role']), equals(['system', 'user']));
      // Stage2A replays the confirmed Stage1 result.
      expect(fake.messages[1].map((m) => m['role']),
          equals(['system', 'assistant', 'user']));
      // Stage2B replays the confirmed Stage1 *and* Stage2A results.
      expect(fake.messages[2].map((m) => m['role']),
          equals(['system', 'assistant', 'assistant', 'user']));

      expect(jsonDecode(fake.messages[2][1]['content']!), _identity());
      expect(jsonDecode(fake.messages[2][2]['content']!), _appearance());

      // Each snapshot is independent: no stage ever reuses another's list.
      expect(
        identical(fake.messages[1], fake.messages[2]),
        isFalse,
      );
    });
  });

  group('Stage schema retry', () {
    test('retries only Stage2B when Stage2B returns a wrong schema (1/1/2)',
        () async {
      var stage2bCalls = 0;
      final fake = _RecordingLlmService((messages) {
        final prompt = messages.last['content'] ?? '';
        if (prompt.contains(_stage1Marker)) return jsonEncode(_identity());
        if (prompt.contains(_stage2aMarker)) return jsonEncode(_appearance());
        stage2bCalls++;
        // First answer is valid JSON but violates the background schema.
        if (stage2bCalls == 1) return jsonEncode({'unrelated': 'value'});
        return jsonEncode(_background());
      });

      final result = await AiGeneratorService(fake)
          .textToDetailedCharacterCard('艾莉诺亚，破晓神殿叛逃学者');

      expect(_countFor(fake.messages, _stage1Marker), 1);
      expect(_countFor(fake.messages, _stage2aMarker), 1);
      expect(_countFor(fake.messages, _stage2bMarker), 2);
      expect(result['description'], contains('逃离神殿'));

      // The retried Stage2B still sees Stage1 + Stage2A.
      final retried = fake.messages.last;
      expect(retried.map((m) => m['role']),
          equals(['system', 'assistant', 'assistant', 'user']));
    });

    test('an empty Stage2A answer retries only Stage2A', () async {
      var stage2aCalls = 0;
      final fake = _RecordingLlmService((messages) {
        final prompt = messages.last['content'] ?? '';
        if (prompt.contains(_stage1Marker)) return jsonEncode(_identity());
        if (prompt.contains(_stage2aMarker)) {
          stage2aCalls++;
          if (stage2aCalls == 1) return '   ';
          return jsonEncode(_appearance());
        }
        return jsonEncode(_background());
      });

      final result = await AiGeneratorService(fake)
          .textToDetailedCharacterCard('艾莉诺亚，破晓神殿叛逃学者');

      expect(_countFor(fake.messages, _stage1Marker), 1);
      expect(_countFor(fake.messages, _stage2aMarker), 2);
      expect(_countFor(fake.messages, _stage2bMarker), 1);
      expect(result['appearance'], contains('银色长发'));
    });
  });

  group('Structured JSON output', () {
    test('repairs a truncated stage answer into decodable canonical JSON',
        () async {
      const truncated = '{"appearance": "银色微卷长发，戴单片黄铜透镜",'
          ' "bodyDescription": "身形高挑纤细"}';
      final fake = _RecordingLlmService((messages) {
        final prompt = messages.last['content'] ?? '';
        if (prompt.contains(_stage1Marker)) return jsonEncode(_identity());
        if (prompt.contains(_stage2aMarker)) {
          return truncated.substring(0, truncated.length - 1);
        }
        return jsonEncode(_background());
      });

      final result = await AiGeneratorService(fake)
          .textToDetailedCharacterCard('艾莉诺亚，破晓神殿叛逃学者');

      // Only a canonical, re-decodable repair can produce these values.
      expect(result['appearance'], '银色微卷长发，戴单片黄铜透镜');
      expect(result['bodyDescription'], '身形高挑纤细');
      expect(jsonDecode(jsonEncode(result)), isA<Map<String, dynamic>>());
    });
  });

  group('Thinking policy', () {
    Future<bool> messagesThinking(LlmGenerationMode? mode) async {
      final fake = _RecordingLlmService((messages) {
        final prompt = messages.last['content'] ?? '';
        if (prompt.contains(_stage1Marker)) return jsonEncode(_identity());
        if (prompt.contains(_stage2aMarker)) return jsonEncode(_appearance());
        return jsonEncode(_background());
      });
      await AiGeneratorService(fake)
          .textToDetailedCharacterCard('p', generationMode: mode);
      return fake.params.first.enableThinking;
    }

    Future<bool> textThinking(LlmGenerationMode? mode) async {
      final fake = _RecordingLlmService(
          (_) => jsonEncode({'name': '测试世界', 'description': '描述'}));
      await AiGeneratorService(fake).textToWorldview('p', generationMode: mode);
      return fake.params.first.enableThinking;
    }

    test('null mode disables thinking on both paths', () async {
      expect(await messagesThinking(null), isFalse);
      expect(await textThinking(null), isFalse);
    });

    test('fast mode disables thinking on both paths', () async {
      expect(await messagesThinking(LlmGenerationMode.fast), isFalse);
      expect(await textThinking(LlmGenerationMode.fast), isFalse);
    });

    test('deepThinking mode enables thinking on both paths', () async {
      expect(await messagesThinking(LlmGenerationMode.deepThinking), isTrue);
      expect(await textThinking(LlmGenerationMode.deepThinking), isTrue);
    });
  });

  group('Supplement prompt and Guard contract', () {
    test('a prompt-compliant supplement completes in one round', () async {
      final supplementPrompts = <String>[];
      String? supplementCall;
      final fake = _RecordingLlmService((messages) {
        final prompt = messages.last['content'] ?? '';
        if (prompt.contains('这是同一张角色卡的增量补全')) {
          supplementCall = prompt;
          supplementPrompts.add(prompt);
          return jsonEncode({
            'scenario': _long('雨夜的废弃观测塔里，她邀请来访者解读会说话的石板。'),
            'first_mes': _long('请不要触碰石板，它会记住每一个试图说谎的人。'),
          });
        }
        if (prompt.contains(_stage1Marker)) return jsonEncode(_identity());
        if (prompt.contains(_stage2aMarker)) return jsonEncode(_appearance());
        return jsonEncode(_background());
      });

      final result = await AiGeneratorService(fake).textToDetailedCharacterCard(
        '艾莉诺亚，22岁，女，破晓神殿叛逃学者',
        targetTotalCharacters: 800,
      );

      expect(supplementCall, isNotNull);
      // The prompt must state both the two-field rule and the 180-char floor,
      // otherwise the model returns one short field and the Guard rejects it.
      expect(supplementCall, contains('180'));
      expect(supplementCall, contains('任意两项或全部三项'));

      // Following the contract clears roleplayBehavior in a single round.
      expect(supplementPrompts, hasLength(1));
      final report = const CharacterCardGenerationGuard().evaluate(
        card: result,
        targetCharacters: 800,
      );
      expect(
          report
              .moduleReadiness[CharacterCardGenerationModule.roleplayBehavior],
          CharacterModuleReadiness.ready);
      expect(report.completed, isTrue);
    });
  });

  group('No-progress bounded retry', () {
    test('makes exactly three supplement requests before failing', () async {
      var calls = 0;
      await expectLater(
        const DetailedCharacterGenerationCoordinator().complete(
          initial: _identity(),
          targetTotalCharacters: 1000,
          requestSupplement: (_, __) async {
            calls++;
            // Repeats an already-confirmed field: the merge must not count it
            // as progress.
            return {'personality': _identity()['personality']};
          },
        ),
        throwsA(isA<CharacterGenerationNoProgressException>()),
      );
      // One initial request plus two bounded no-growth retries.
      expect(calls, 3);
    });
  });
}
