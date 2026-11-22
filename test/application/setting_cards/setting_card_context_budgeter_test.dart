import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/setting_cards/setting_card_context_budgeter.dart';
import 'package:lt_dialogue/application/setting_cards/setting_card_reference_input.dart';

String repeat(String unit, int count) => List.filled(count, unit).join();

/// Splits budgeter output of the form 【key】\nbody\n\n【key】\nbody back into
/// key/body pairs so each module can be measured independently.
Map<String, String> parseSections(String text) {
  final sections = <String, String>{};
  final pattern = RegExp(r'【([^】]+)】\n([\s\S]*?)(?=\n\n【|$)');
  for (final match in pattern.allMatches(text)) {
    sections[match.group(1)!] = match.group(2)!;
  }
  return sections;
}

void main() {
  const budgeter = SettingCardContextBudgeter();

  group('selectReference', () {
    test('returns empty for blank reference', () {
      expect(budgeter.selectReference(source: '林恩', reference: ''), '');
      expect(budgeter.selectReference(source: '林恩', reference: '  \n  '), '');
    });

    test('keeps a 7999 character reference verbatim', () {
      final reference = repeat('a', 7999);

      expect(
        budgeter.selectReference(source: '', reference: reference),
        reference,
      );
    });

    test('truncates an oversized single paragraph to the cap', () {
      final reference = repeat('b', 8001);

      final selected =
          budgeter.selectReference(source: '', reference: reference);

      expect(selected.length, 8000);
      expect(selected, repeat('b', 8000));
    });

    test('keeps paragraphs matching the source before unrelated ones', () {
      final filler = repeat('c', 4000);
      final relevant = 'dragon lore ${repeat('d', 3000)}';
      final tail = repeat('e', 3000);
      final reference = '$filler\n\n$relevant\n\n$tail';

      final selected = budgeter.selectReference(
        source: 'dragon lore',
        reference: reference,
      );

      expect(selected.length, lessThanOrEqualTo(8000));
      expect(selected.contains(relevant), isTrue);
      expect(selected.indexOf('dragon'), lessThan(selected.indexOf(filler)));
      expect(selected.contains(tail), isFalse);
    });

    test('keeps document order when no paragraph matches the source', () {
      final first = repeat('f', 5000);
      final second = repeat('g', 5000);

      final selected = budgeter.selectReference(
        source: 'unrelated',
        reference: '$first\n\n$second',
      );

      expect(selected.startsWith(first), isTrue);
      expect(selected.contains(second), isFalse);
    });
  });

  group('selectWorldview', () {
    test('returns empty for blank worldview', () {
      expect(budgeter.selectWorldview(source: 'x', worldview: '  '), '');
    });

    test('scores modules, caps each section and hides status', () {
      final worldview = jsonEncode({
        'format_version': 2,
        'mode': 'detailed',
        'modules': {
          'timeline': {'content': repeat('t', 2500), 'status': 'confirmed'},
          'world_rules': {
            'content': repeat('r', 2500),
            'status': 'confirmed',
          },
          'overview': {'summary': 'Overview text', 'status': 'confirmed'},
        },
      });

      final selected =
          budgeter.selectWorldview(source: '', worldview: worldview);
      final sections = parseSections(selected);

      expect(selected.length, lessThanOrEqualTo(8000));
      expect(selected.startsWith('【overview】'), isTrue);
      expect(
        sections.keys,
        containsAll(<String>['overview', 'world_rules', 'timeline']),
      );
      expect(sections['world_rules']!.length, 1600);
      expect(sections['timeline']!.length, lessThanOrEqualTo(1600));
      expect(selected.contains('confirmed'), isFalse);
    });

    test('falls back to bounded plain text without splitting surrogate pairs',
        () {
      final worldview = '${repeat('a', 7999)}🙂${repeat('z', 10)}';

      final selected =
          budgeter.selectWorldview(source: '', worldview: worldview);

      expect(selected.length, 7999);
      expect(selected, repeat('a', 7999));
      final lastUnit = selected.codeUnits.last;
      expect(lastUnit >= 0xD800 && lastUnit <= 0xDBFF, isFalse);
    });

    test('treats invalid JSON as plain text', () {
      expect(
        budgeter.selectWorldview(source: '', worldview: '{broken json'),
        '{broken json',
      );
    });
  });

  group('summarizeAssociatedCharacters', () {
    test('truncates personality and background, keeps identity fields', () {
      final characters = <Map<String, String>>[
        {
          'name': ' Lin ',
          'profession': 'Ranger',
          'personality': repeat('p', 300),
          'background': repeat('b', 500),
          'relation': 'sister',
        },
      ];
      final untouched = characters
          .map((character) => Map<String, String>.from(character))
          .toList();

      final summarized = budgeter.summarizeAssociatedCharacters(characters);

      expect(summarized, hasLength(1));
      expect(summarized.single['name'], 'Lin');
      expect(summarized.single['profession'], 'Ranger');
      expect(summarized.single['personality']!.length, 280);
      expect(summarized.single['background']!.length, 400);
      expect(summarized.single['relation'], 'sister');
      expect(characters, untouched);
    });

    test('falls back to role and relationship keys', () {
      final summarized = budgeter.summarizeAssociatedCharacters(const [
        {
          'name': 'Bane',
          'role': 'Guard',
          'relationship': 'enemy',
        },
      ]);

      expect(summarized.single['profession'], 'Guard');
      expect(summarized.single['relation'], 'enemy');
      expect(summarized.single['personality'], '');
      expect(summarized.single['background'], '');
    });
  });

  test('empty inputs return safe values', () {
    expect(budgeter.selectReference(source: '', reference: ''), '');
    expect(budgeter.selectWorldview(source: '', worldview: ''), '');
    expect(budgeter.summarizeAssociatedCharacters(const []), isEmpty);
  });

  group('SettingCardReferenceInput', () {
    test('isEmpty only when neither text nor card id is usable', () {
      expect(
        const SettingCardReferenceInput(mode: SettingCardReferenceMode.paste)
            .isEmpty,
        isTrue,
      );
      expect(
        const SettingCardReferenceInput(
          mode: SettingCardReferenceMode.paste,
          text: '  \n ',
        ).isEmpty,
        isTrue,
      );
      expect(
        const SettingCardReferenceInput(
          mode: SettingCardReferenceMode.paste,
          text: ' 设定 ',
        ).isEmpty,
        isFalse,
      );
      expect(
        const SettingCardReferenceInput(
          mode: SettingCardReferenceMode.file,
          label: 'lore.md',
          text: '# 正文',
        ).isEmpty,
        isFalse,
      );
      expect(
        const SettingCardReferenceInput(
          mode: SettingCardReferenceMode.existingCard,
        ).isEmpty,
        isTrue,
      );
      expect(
        const SettingCardReferenceInput(
          mode: SettingCardReferenceMode.existingCard,
          sourceCardId: ' card-1 ',
        ).isEmpty,
        isFalse,
      );
    });
  });
}
