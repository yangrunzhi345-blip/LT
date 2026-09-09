import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/services/detailed_character_generation_coordinator.dart';

String _fill(String seed) => List<String>.filled(25, seed).join();

Map<String, dynamic> _initialCard({bool complete = false}) => {
      'name': '艾莉诺亚',
      'gender': '女',
      'age': '22',
      'profession': '叛逃学者',
      'description': _fill('她在破晓神殿发现被篡改的历史，因此踏上逃亡与求真之路。'),
      'personality': _fill('她克制、聪慧且固执，会为守护真相承担代价。'),
      'appearance': _fill('银色长发与月白学者袍令她在人群中十分醒目。'),
      'bodyDescription': _fill('高挑纤细，左肩留有神殿惩戒的禁印。'),
      'world_profile': {
        'faction': '古代文明研究遗民会',
        'home_location': '破晓旧都地下档案库',
        'public_goal': _fill('寻找第七石板，并将其记录的真相公布于世。'),
        'hidden_motivation': _fill('证明失踪导师并非叛徒。'),
        'relationship_notes': _fill('她与城内走私者互相利用，却拒绝伤害无辜者。'),
      },
      if (complete) ..._supplement,
    };

final _supplement = <String, dynamic>{
  'scenario': _fill('雨夜的废弃观测塔中，她邀请来访者共同解读会说话的石板。'),
  'first_mes': _fill('请不要触碰石板，它会记住每一个试图说谎的人。'),
  'mes_example': _fill('访客：你相信我吗？\n艾莉诺亚：我暂时需要一位同行者。'),
  'ability': _fill('她能通过古代符文读取遗物残留的记忆碎片。'),
  'weakness': _fill('每次共鸣都会带来偏头痛和短暂失明。'),
};

void main() {
  group('DetailedCharacterGenerationCoordinator', () {
    test('should skip supplement when initial candidate is complete', () async {
      var calls = 0;
      final result =
          await const DetailedCharacterGenerationCoordinator().complete(
        initial: _initialCard(complete: true),
        targetTotalCharacters: 1000,
        requestSupplement: (_, __) async {
          calls++;
          return const {};
        },
      );
      expect(calls, 0);
      expect(result['name'], '艾莉诺亚');
    });

    test('should supplement until the next report is complete', () async {
      var calls = 0;
      final result =
          await const DetailedCharacterGenerationCoordinator().complete(
        initial: _initialCard(),
        targetTotalCharacters: 1000,
        requestSupplement: (_, __) async {
          calls++;
          return _supplement;
        },
      );
      expect(calls, 1);
      expect(result['scenario'], isNotEmpty);
    });

    test('should make a second supplement call when the first remains thin',
        () async {
      var calls = 0;
      await const DetailedCharacterGenerationCoordinator().complete(
        initial: _initialCard(),
        targetTotalCharacters: 1000,
        requestSupplement: (_, __) async {
          calls++;
          return calls == 1
              ? {'scenario': _fill('她在雨夜邀请陌生人一起解读石板。')}
              : _supplement;
        },
      );
      expect(calls, 2);
    });

    test(
        'should preserve frozen identity when a supplement tries to replace it',
        () async {
      final result =
          await const DetailedCharacterGenerationCoordinator().complete(
        initial: _initialCard(),
        targetTotalCharacters: 1000,
        requestSupplement: (_, __) async => {
          ..._supplement,
          'name': '另一人',
          'age': '99',
          'gender': '男',
          'profession': '猎人',
        },
      );
      expect(result['name'], '艾莉诺亚');
      expect(result['age'], '22');
      expect(result['gender'], '女');
      expect(result['profession'], '叛逃学者');
    });

    test('should remove a suffix-prefix overlap while merging prose', () {
      final merged =
          DetailedCharacterGenerationCoordinator.mergeCharacterCardSupplement(
        {'description': '她逃离神殿后在白港寻找失落石板'},
        {'description': '寻找失落石板，并试图证明导师清白。'},
      );
      expect(merged['description'], '她逃离神殿后在白港寻找失落石板，并试图证明导师清白。');
    });

    test('should fail when a supplement produces no effective growth', () {
      expect(
        () => const DetailedCharacterGenerationCoordinator().complete(
          initial: _initialCard(),
          targetTotalCharacters: 1000,
          requestSupplement: (_, __) async => const {},
        ),
        throwsA(isA<CharacterGenerationNoProgressException>()),
      );
    });

    test('should fail at the safety limit rather than report completion', () {
      expect(
        () => const DetailedCharacterGenerationCoordinator(
          maximumSupplementRounds: 1,
        ).complete(
          initial: _initialCard(),
          targetTotalCharacters: 5000,
          requestSupplement: (_, __) async => {
            'scenario': _fill('她在雨夜邀请陌生人一起解读石板。'),
          },
        ),
        throwsA(isA<CharacterGenerationTargetNotReachedException>()),
      );
    });
  });
}
