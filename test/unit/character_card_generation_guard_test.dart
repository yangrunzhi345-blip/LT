import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/services/character_card_generation_guard.dart';

String _text(String seed, int length) => seed * (length ~/ seed.length + 1);

Map<String, dynamic> _completeCard() => {
      'name': '艾莉诺亚',
      'gender': '女',
      'age': '22',
      'profession': '叛逃学者',
      'description': _text('她在破晓神殿的禁书库中长大，因发现历史被篡改而逃亡。', 180),
      'personality': _text('她克制而执着，宁愿独自承担风险也不放弃真相。', 180),
      'appearance': _text('银色长发与磨损的学者袍是她最显眼的标记。', 120),
      'bodyDescription': _text('高挑但因长期逃亡略显疲惫，左肩留有禁印。', 120),
      'scenario': _text('在雨夜的废弃观测塔，她向来访者展示一块会说话的石板。', 110),
      'first_mes': _text('请不要碰那块石板，它会记住每一个试图说谎的人。', 110),
      'mes_example': _text('访客：你为什么相信我？\n艾莉诺亚：我不相信，只是暂时需要同行者。', 110),
      'ability': _text('她能以古代符文读取遗物残留的记忆碎片。', 100),
      'weakness': _text('每次共鸣都会带来偏头痛与短暂失明。', 80),
      'world_profile': {
        'faction': '古代文明研究遗民会',
        'home_location': '破晓旧都地下档案库',
        'public_goal': _text('寻找第七石板并公开它记录的真相。', 80),
        'hidden_motivation': _text('她想证明失踪的导师不是叛徒。', 80),
        'relationship_notes': _text('她与城内走私者互相利用，却始终拒绝伤害无辜者。', 80),
      },
    };

void main() {
  const guard = CharacterCardGenerationGuard();

  group('CharacterCardGenerationGuard', () {
    test('should exclude metadata from effective character count', () {
      final card = _completeCard()
        ..addAll({
          'spec': _text('metadata', 1000),
          'creator': _text('metadata', 1000),
          'tags': [_text('metadata', 1000)],
        });
      expect(guard.count(card), equals(guard.count(_completeCard())));
    });

    test('should exclude whitespace from effective character count', () {
      expect(
        guard.count({'description': '艾 莉\n诺\t亚'}),
        equals('艾莉诺亚'.length),
      );
    });

    test('should count repeated visible text only once', () {
      expect(
        guard.count({'description': '同一段文字', 'personality': '同一段文字'}),
        equals('同一段文字'.length),
      );
    });

    test('should not complete a long background without personality or RP', () {
      final report = guard.evaluate(
        card: {
          'name': '艾莉诺亚',
          'gender': '女',
          'age': '22',
          'profession': '学者',
          'description': _text('很长的背景。', 1500),
        },
        targetCharacters: 1000,
      );
      expect(report.lengthReached, isTrue);
      expect(report.completed, isFalse);
      expect(report.weakModules, contains('roleplayBehavior'));
    });

    test('should not complete when a required module is missing', () {
      final card = _completeCard()..remove('scenario');
      card.remove('first_mes');
      card.remove('mes_example');
      final report = guard.evaluate(card: card, targetCharacters: 1000);
      expect(report.lengthReached, isTrue);
      expect(report.requiredModulesReady, isFalse);
      expect(report.completed, isFalse);
    });

    test(
        'should not complete when required modules are ready but target is unmet',
        () {
      final report =
          guard.evaluate(card: _completeCard(), targetCharacters: 5000);
      expect(report.requiredModulesReady, isTrue);
      expect(report.lengthReached, isFalse);
      expect(report.completed, isFalse);
    });

    test('should complete only with length, modules, and structural identity',
        () {
      final report =
          guard.evaluate(card: _completeCard(), targetCharacters: 1000);
      expect(report.lengthReached, isTrue);
      expect(report.requiredModulesReady, isTrue);
      expect(report.structurallyConsistent, isTrue);
      expect(report.completed, isTrue);
    });
  });
}
