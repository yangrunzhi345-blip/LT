import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/models/completion_params.dart';
import 'package:lt_dialogue/services/ai_generator_service.dart';
import 'package:lt_dialogue/services/detailed_character_stage_normalizer.dart';
import 'package:lt_dialogue/services/llm_service.dart';
import 'package:lt_dialogue/services/stage_schema_validator.dart';

String _long(String text, {int times = 12}) =>
    List<String>.filled(times, text).join();

Map<String, dynamic> _validIdentity() => {
      'name': '艾莉诺亚',
      'gender': '女',
      'age': '22',
      'profession': '学者',
      'archetype': '叛逆者',
      'personality': _long('她克制而执着。'),
    };

class _RecordingLlmService extends LLMService {
  _RecordingLlmService(this.answer)
      : super(const LLMConfig(
          provider: LLMProvider.deepseek,
          apiKey: 'test-key',
          baseUrl: 'https://example.invalid',
          model: 'deepseek-flash',
        ));

  final String Function(String prompt) answer;
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
    final response = answer(prompt);
    onChunk(response);
    return LLMStreamResult(
      content: response,
      finishReason: LLMFinishReason.stop,
      responseCompleted: true,
    );
  }
}

const _identityMarker = '提炼或设计角色的核心身份定位';
const _appearanceMarker = '请提取并细化角色的生动外貌肖像与身材体格特征';
const _backgroundMarker = '请深入推演角色的身世背景、深层动机';

int _countFor(List<String> prompts, String marker) =>
    prompts.where((p) => p.contains(marker)).length;

void main() {
  group('Typed detailed-character stage normalizer', () {
    test('identity accepts canonical strings and numeric age', () {
      final payload = DetailedCharacterStageNormalizer.normalize(
        CharacterGenerationStage.identity,
        {
          'name': '艾莉诺亚',
          'gender': '女',
          'age': 22,
          'profession': '学者',
          'personality': _long('她克制而执着。'),
        },
      );
      expect(payload, isA<CharacterIdentityPayload>());
      expect((payload! as CharacterIdentityPayload).age, '22');
    });

    test('identity rejects bool/map/list scalars for text fields', () {
      for (final bad in <Map<String, dynamic>>[
        {..._validIdentity(), 'name': 123},
        {..._validIdentity(), 'name': true},
        {..._validIdentity(), 'gender': true},
        {
          ..._validIdentity(),
          'personality': ['a', 'b']
        },
        {
          ..._validIdentity(),
          'profession': {'x': 'y'}
        },
        {..._validIdentity(), 'name': '   '},
      ]) {
        expect(
          DetailedCharacterStageNormalizer.normalize(
            CharacterGenerationStage.identity,
            bad,
          ),
          isNull,
          reason: 'should reject $bad',
        );
      }
    });

    test('appearance maps the legacy body_description alias', () {
      final payload = DetailedCharacterStageNormalizer.normalize(
        CharacterGenerationStage.appearance,
        {'appearance': _long('银色长发。'), 'body_description': _long('高挑。')},
      );
      expect(payload, isA<CharacterAppearancePayload>());
      expect((payload! as CharacterAppearancePayload).bodyDescription,
          _long('高挑。'));
    });

    test('appearance rejects a numeric appearance', () {
      expect(
        DetailedCharacterStageNormalizer.normalize(
          CharacterGenerationStage.appearance,
          {'appearance': 42, 'bodyDescription': '体型'},
        ),
        isNull,
      );
    });

    test('background accepts a flat payload and defaults taboos', () {
      final payload = DetailedCharacterStageNormalizer.normalize(
        CharacterGenerationStage.backgroundWorld,
        {
          'description': _long('背景。'),
          'faction': '遗民会',
          'home_location': '档案库',
          'public_goal': _long('目标。'),
          'hidden_motivation': _long('动机。'),
        },
      );
      expect(payload, isA<CharacterBackgroundPayload>());
      final background = payload! as CharacterBackgroundPayload;
      expect(
          background.taboos, [DetailedCharacterStageNormalizer.defaultTaboo]);
    });

    test('background normalizes a nested world_profile container', () {
      final payload = DetailedCharacterStageNormalizer.normalize(
        CharacterGenerationStage.backgroundWorld,
        {
          'world_profile': {
            'description': _long('嵌套背景。'),
            'faction': '嵌套阵营',
            'home_location': '嵌套地点',
            'public_goal': _long('嵌套目标。'),
            'hidden_motivation': _long('嵌套动机。'),
            'taboos': ['不得背誓'],
          },
        },
      );
      final background = payload! as CharacterBackgroundPayload;
      expect(background.faction, '嵌套阵营');
      expect(background.homeLocation, '嵌套地点');
      expect(background.description, _long('嵌套背景。'));
      expect(background.taboos, ['不得背誓']);
    });

    test('root fields win over a conflicting nested world_profile', () {
      final payload = DetailedCharacterStageNormalizer.normalize(
        CharacterGenerationStage.backgroundWorld,
        {
          'description': _long('根背景。'),
          'faction': '根阵营',
          'home_location': '根地点',
          'public_goal': _long('根目标。'),
          'hidden_motivation': _long('根动机。'),
          'world_profile': {'faction': '嵌套阵营'},
        },
      );
      final background = payload! as CharacterBackgroundPayload;
      expect(background.faction, '根阵营');
    });

    test('background rejects missing fields and malformed taboos', () {
      final flat = {
        'description': _long('背景。'),
        'faction': '遗民会',
        'home_location': '档案库',
        'public_goal': _long('目标。'),
        'hidden_motivation': _long('动机。'),
      };
      expect(
        DetailedCharacterStageNormalizer.normalize(
          CharacterGenerationStage.backgroundWorld,
          {...flat}..remove('faction'),
        ),
        isNull,
      );
      expect(
        DetailedCharacterStageNormalizer.normalize(
          CharacterGenerationStage.backgroundWorld,
          {...flat, 'taboos': '不是列表'},
        ),
        isNull,
      );
      expect(
        DetailedCharacterStageNormalizer.normalize(
          CharacterGenerationStage.backgroundWorld,
          {
            ...flat,
            'taboos': ['ok', 7],
          },
        ),
        isNull,
      );
    });
  });

  group('StageSchemaValidator matches the typed contract', () {
    test('accepts the canonical identity shape only', () {
      expect(
        StageSchemaValidator.validate(
          CharacterGenerationStage.identity,
          _validIdentity(),
        ),
        isTrue,
      );
      expect(
        StageSchemaValidator.validate(
          CharacterGenerationStage.identity,
          {..._validIdentity(), 'name': 123},
        ),
        isFalse,
      );
    });

    test('no longer accepts a nested world_profile directly', () {
      expect(
        StageSchemaValidator.validate(
          CharacterGenerationStage.backgroundWorld,
          {
            'world_profile': {
              'faction': '遗民会',
              'home_location': '档案库',
              'public_goal': '目标',
              'hidden_motivation': '动机',
            },
          },
        ),
        isFalse,
      );
      expect(
        StageSchemaValidator.validate(
          CharacterGenerationStage.backgroundWorld,
          {
            'description': '背景',
            'faction': '遗民会',
            'home_location': '档案库',
            'public_goal': '目标',
            'hidden_motivation': '动机',
          },
        ),
        isTrue,
      );
    });
  });

  group('Generation uses the canonical payload', () {
    test('a nested Stage2B world_profile survives into the final card',
        () async {
      final fake = _RecordingLlmService((prompt) {
        if (prompt.contains(_identityMarker)) {
          return jsonEncode(_validIdentity());
        }
        if (prompt.contains(_appearanceMarker)) {
          return jsonEncode({
            'appearance': _long('银色长发。'),
            'bodyDescription': _long('高挑。'),
          });
        }
        return jsonEncode({
          'world_profile': {
            'description': _long('嵌套生平。'),
            'faction': '遗民会',
            'home_location': '地下档案库',
            'public_goal': _long('寻找石板。'),
            'hidden_motivation': _long('证明清白。'),
          },
        });
      });

      final result = await AiGeneratorService(fake)
          .textToDetailedCharacterCard('艾莉诺亚，叛逃学者');

      final profile = result['world_profile'] as Map<String, dynamic>;
      expect(profile['faction'], '遗民会');
      expect(profile['home_location'], '地下档案库');
      expect(profile['public_goal'], contains('石板'));
      expect(profile['hidden_motivation'], contains('清白'));
      expect(result['description'], contains('嵌套生平'));
    });

    test('a wrong-typed identity retries only Stage1', () async {
      var stage1Calls = 0;
      final fake = _RecordingLlmService((prompt) {
        if (prompt.contains(_identityMarker)) {
          stage1Calls++;
          if (stage1Calls == 1) {
            return jsonEncode({..._validIdentity(), 'name': 123});
          }
          return jsonEncode(_validIdentity());
        }
        if (prompt.contains(_appearanceMarker)) {
          return jsonEncode({
            'appearance': _long('银色长发。'),
            'bodyDescription': _long('高挑。'),
          });
        }
        return jsonEncode({
          'description': _long('生平。'),
          'faction': '遗民会',
          'home_location': '档案库',
          'public_goal': _long('目标。'),
          'hidden_motivation': _long('动机。'),
        });
      });

      final result = await AiGeneratorService(fake)
          .textToDetailedCharacterCard('艾莉诺亚，叛逃学者');

      expect(stage1Calls, 2);
      expect(_countFor(fake.prompts, _appearanceMarker), 1);
      expect(_countFor(fake.prompts, _backgroundMarker), 1);
      expect(result['name'], '艾莉诺亚');
    });
  });
}
