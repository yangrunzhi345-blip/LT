import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/models/completion_params.dart';
import 'package:lt_dialogue/services/ai_generator_service.dart';
import 'package:lt_dialogue/services/llm_service.dart';

String _long(String text, {int times = 12}) =>
    List<String>.filled(times, text).join();

/// Returns a scripted [LLMStreamResult] per prompt so tests can control the
/// finish reason / completion flag that plain fakes never vary.
class _ScriptedLlmService extends LLMService {
  _ScriptedLlmService(this.respond)
      : super(const LLMConfig(
          provider: LLMProvider.deepseek,
          apiKey: 'test-key',
          baseUrl: 'https://example.invalid',
          model: 'deepseek-flash',
        ));

  final FutureOr<LLMStreamResult> Function(String prompt) respond;
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
    final result = await respond(prompt);
    if (result.content.isNotEmpty) onChunk(result.content);
    return result;
  }
}

LLMStreamResult _stop(String content) => LLMStreamResult(
      content: content,
      finishReason: LLMFinishReason.stop,
      responseCompleted: true,
    );

const _identityMarker = '提炼或设计角色的核心身份定位';
const _appearanceMarker = '请提取并细化角色的生动外貌肖像与身材体格特征';
const _backgroundMarker = '请深入推演角色的身世背景、深层动机';

Map<String, dynamic> _identity(String name) => {
      'name': name,
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
    };

int _countFor(List<String> prompts, String marker) =>
    prompts.where((p) => p.contains(marker)).length;

/// A syntactically truncated but repairable-and-schema-valid identity object.
/// If the incomplete-response guard were missing, this would be accepted.
const _truncatedIdentity =
    '{"name":"截断名","gender":"女","age":"1","profession":"刺客","personality":"她是一位非常冷静且极度克制、拥有漫长过往的刺客。"';

void main() {
  group('Incomplete structured responses are rejected', () {
    test('length-truncated Stage1 is re-requested and never used', () async {
      var stage1Calls = 0;
      final fake = _ScriptedLlmService((prompt) {
        if (prompt.contains(_identityMarker)) {
          stage1Calls++;
          if (stage1Calls == 1) {
            // Real transport truncation: the provider stopped on `length`, so
            // the response never completed. This is the contract the guard must
            // reject (not an artificially completed truncation).
            return const LLMStreamResult(
              content: _truncatedIdentity,
              finishReason: LLMFinishReason.length,
              responseCompleted: false,
            );
          }
          return _stop(jsonEncode(_identity('艾莉诺亚')));
        }
        if (prompt.contains(_appearanceMarker)) {
          return _stop(jsonEncode(_appearance()));
        }
        return _stop(jsonEncode(_background()));
      });

      final result = await AiGeneratorService(fake)
          .textToDetailedCharacterCard('艾莉诺亚，破晓神殿叛逃学者');

      expect(stage1Calls, 2);
      expect(_countFor(fake.prompts, _appearanceMarker), 1);
      expect(_countFor(fake.prompts, _backgroundMarker), 1);
      // The truncated answer must never become the card.
      expect(result['name'], '艾莉诺亚');
    });

    test('maxTokens-truncated Stage2A is re-requested only for Stage2A',
        () async {
      var stage2aCalls = 0;
      final fake = _ScriptedLlmService((prompt) {
        if (prompt.contains(_identityMarker)) {
          return _stop(jsonEncode(_identity('艾莉诺亚')));
        }
        if (prompt.contains(_appearanceMarker)) {
          stage2aCalls++;
          if (stage2aCalls == 1) {
            return const LLMStreamResult(
              content: '{"appearance":"截断外貌","bodyDescription":"截断体格"',
              finishReason: LLMFinishReason.maxTokens,
              responseCompleted: false,
            );
          }
          return _stop(jsonEncode(_appearance()));
        }
        return _stop(jsonEncode(_background()));
      });

      final result = await AiGeneratorService(fake)
          .textToDetailedCharacterCard('艾莉诺亚，破晓神殿叛逃学者');

      expect(stage2aCalls, 2);
      expect(_countFor(fake.prompts, _identityMarker), 1);
      expect(_countFor(fake.prompts, _backgroundMarker), 1);
      expect(result['appearance'], contains('银色长发'));
    });

    test('an interrupted (responseCompleted=false) Stage2B is re-requested',
        () async {
      var stage2bCalls = 0;
      final fake = _ScriptedLlmService((prompt) {
        if (prompt.contains(_identityMarker)) {
          return _stop(jsonEncode(_identity('艾莉诺亚')));
        }
        if (prompt.contains(_appearanceMarker)) {
          return _stop(jsonEncode(_appearance()));
        }
        stage2bCalls++;
        if (stage2bCalls == 1) {
          return LLMStreamResult(
            content: jsonEncode(_background()),
            finishReason: LLMFinishReason.interrupted,
            responseCompleted: false,
          );
        }
        return _stop(jsonEncode(_background()));
      });

      final result = await AiGeneratorService(fake)
          .textToDetailedCharacterCard('艾莉诺亚，破晓神殿叛逃学者');

      expect(stage2bCalls, 2);
      expect(result['description'], contains('逃离神殿'));
    });

    test('a stop finish reason that never completed is still rejected',
        () async {
      var stage2bCalls = 0;
      final fake = _ScriptedLlmService((prompt) {
        if (prompt.contains(_identityMarker)) {
          return _stop(jsonEncode(_identity('艾莉诺亚')));
        }
        if (prompt.contains(_appearanceMarker)) {
          return _stop(jsonEncode(_appearance()));
        }
        stage2bCalls++;
        if (stage2bCalls == 1) {
          // The provider reports `stop` and the body parses, but the transport
          // never completed. Only the responseCompleted flag protects us here.
          return LLMStreamResult(
            content: jsonEncode(_background()),
            finishReason: LLMFinishReason.stop,
            responseCompleted: false,
          );
        }
        return _stop(jsonEncode(_background()));
      });

      final result = await AiGeneratorService(fake)
          .textToDetailedCharacterCard('艾莉诺亚，破晓神殿叛逃学者');

      expect(stage2bCalls, 2);
      expect(result['description'], contains('逃离神殿'));
    });

    test('a completed stop response with a repairable defect is accepted',
        () async {
      var stage1Calls = 0;
      final fake = _ScriptedLlmService((prompt) {
        if (prompt.contains(_identityMarker)) {
          stage1Calls++;
          final encoded = jsonEncode(_identity('艾莉诺亚'));
          // Trailing comma: repair must canonicalise it without a re-request.
          final damaged = '${encoded.substring(0, encoded.length - 1)},}';
          return _stop(damaged);
        }
        if (prompt.contains(_appearanceMarker)) {
          return _stop(jsonEncode(_appearance()));
        }
        return _stop(jsonEncode(_background()));
      });

      final result = await AiGeneratorService(fake)
          .textToDetailedCharacterCard('艾莉诺亚，破晓神殿叛逃学者');

      expect(stage1Calls, 1);
      expect(result['name'], '艾莉诺亚');
    });

    test('a cancelled structured call is never retried', () async {
      var calls = 0;
      final fake = _ScriptedLlmService((prompt) async {
        calls++;
        throw const GenerationCancelledException();
      });

      await expectLater(
        AiGeneratorService(fake).textToDetailedCharacterCard('艾莉诺亚'),
        throwsA(isA<GenerationCancelledException>()),
      );
      expect(calls, 1);
    });

    test('persistent truncation exhausts the bounded content budget', () async {
      final fake = _ScriptedLlmService((prompt) {
        if (prompt.contains(_identityMarker)) {
          return const LLMStreamResult(
            content: _truncatedIdentity,
            finishReason: LLMFinishReason.length,
            responseCompleted: false,
          );
        }
        return _stop(jsonEncode(_background()));
      });

      await expectLater(
        AiGeneratorService(fake).textToDetailedCharacterCard('艾莉诺亚'),
        throwsA(isA<FormatException>()),
      );
      // 3 bounded content attempts, no earlier stage ever ran.
      expect(_countFor(fake.prompts, _identityMarker), 3);
      expect(_countFor(fake.prompts, _appearanceMarker), 0);
    });
  });
}
