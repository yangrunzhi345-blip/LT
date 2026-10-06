import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/services/ai_generator_service.dart';

/// Regression coverage for the opening prompt's authority model.
///
/// The reported bug was that an organization could be re-written as a person
/// because (a) the prompt gave *user preference* the highest authority and let
/// it override the world, and (b) entity type was never asserted at all. These
/// tests lock in the corrected authority ordering and the Canon entity block.
void main() {
  const canonEntities = <Map<String, String>>[
    {
      'name': '洛恩',
      'type': 'organization',
      'source': '角色「A」的角色卡',
      'relation': 'A 是洛恩的实际掌控者',
    },
    {'name': 'A', 'type': 'character', 'source': '已选角色卡', 'relation': '主角'},
  ];

  group('renderCanonEntitySection', () {
    test('renders every declared entity with its type and relation', () {
      final section =
          AiGeneratorService.renderCanonEntitySection(canonEntities);
      expect(section, contains('洛恩'));
      expect(section, contains('类型：organization'));
      expect(section, contains('A 是洛恩的实际掌控者'));
      expect(section, contains('类型：character'));
    });

    test('states that name form is not a type indicator', () {
      final section =
          AiGeneratorService.renderCanonEntitySection(canonEntities);
      expect(section, contains('不能作为类型判断依据'));
      expect(section, contains('绝不能把它写成人物'));
    });

    test('is empty for an empty entity list', () {
      expect(AiGeneratorService.renderCanonEntitySection(const []), isEmpty);
    });
  });

  group('buildOpeningPrompt authority', () {
    String build({List<Map<String, String>> entities = canonEntities}) =>
        AiGeneratorService.buildOpeningPrompt(
          userPrompt: '让洛恩本人走进大厅和 A 对话',
          worldview: '银月城由议会统治',
          protagonistName: 'A',
          protagonistRole: '主角',
          protagonistExtra: '',
          selectedCharacterSection: '已选角色卡：\n- 名称：A\n',
          relationshipSection: '',
          npcSection: '',
          canonEntitySection:
              AiGeneratorService.renderCanonEntitySection(entities),
        );

    test('Canon facts rank above the user requirement', () {
      final prompt = build();
      final canonIndex = prompt.indexOf('Canon 既定事实');
      final userIndex = prompt.indexOf('用户序章要求');
      final creativeIndex = prompt.indexOf('模型创意自由');
      expect(canonIndex, isNonNegative);
      expect(userIndex, greaterThan(canonIndex));
      expect(creativeIndex, greaterThan(userIndex));
    });

    test('marks Canon as non-overridable and forbids the drift', () {
      final prompt = build();
      expect(prompt, contains('不可被任何用户要求或模型创意覆盖'));
      expect(prompt, contains('必须以 Canon 为准'));
      expect(prompt, contains('名称的形式不能作为实体类型判断依据'));
      // The organization declaration reaches the final prompt.
      expect(prompt, contains('洛恩'));
      expect(prompt, contains('类型：organization'));
    });

    test('substitutes every placeholder, even with no canon entities', () {
      final prompt = build(entities: const []);
      for (final placeholder in const [
        '{userPrompt}',
        '{worldview}',
        '{protagonistName}',
        '{protagonistRole}',
        '{protagonistExtra}',
        '{selectedCharacters}',
        '{characterRelationships}',
        '{npcs}',
        '{canonEntities}',
      ]) {
        expect(prompt.contains(placeholder), isFalse,
            reason: '$placeholder must be substituted');
      }
      expect(prompt, contains('让洛恩本人走进大厅和 A 对话'));
    });

    test('keeps the structured JSON output contract', () {
      final prompt = build();
      expect(prompt, contains('"scene"'));
      expect(prompt, contains('"options"'));
      expect(prompt, contains('2~4'));
      expect(prompt, contains('必须是纯 JSON'));
    });
  });
}
