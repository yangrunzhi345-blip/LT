import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resource_library/character_generation_context_builder.dart';

void main() {
  group('CharacterGenerationContextBuilder', () {
    test('should select bounded relevant worldview modules', () {
      final context = const CharacterGenerationContextBuilder().build(
        source: '白港炼金师',
        worldview: jsonEncode({
          'mode': 'detailed',
          'modules': {
            'overview': {'summary': '白港是雾银炼金的贸易城市。'},
            'world_rules': {'content': '炼金术会消耗施术者的记忆。'},
            'locations': {'content': '白港下城区聚集着炼金工坊。'},
            'factions': {'content': '白港炼金议会控制牌照。'},
            'timeline': {'content': List.filled(10000, '冗余历史').join()},
          },
        }),
      );

      expect(context.worldview, contains('白港'));
      expect(context.worldview, contains('炼金'));
      expect(context.worldview.length, lessThanOrEqualTo(8000));
    });

    test('should retain each linked character relation independently', () {
      final context = const CharacterGenerationContextBuilder().build(
        source: '新角色',
        associatedCharacters: const [
          {
            'name': '阿尔玛',
            'profession': '医师',
            'background': '很长的背景',
            'relation': '姐姐',
          },
          {
            'name': '贝恩',
            'profession': '卫兵',
            'relation': '敌人',
          },
        ],
      );

      expect(context.associatedCharacters, hasLength(2));
      expect(context.associatedCharacters[0]['relation'], '姐姐');
      expect(context.associatedCharacters[1]['relation'], '敌人');
    });
  });
}
