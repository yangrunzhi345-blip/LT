import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/models/prompt_preset.dart';
import 'package:lt_dialogue/models/world_entry.dart';

Map<String, Object?> _worldEntryFixture(Object position) => {
      'id': 1,
      'adventure_id': 2,
      'keys': '["harbor"]',
      'content': 'fixture',
      'insert_position': position,
      'enabled': 1,
    };

void main() {
  group('R06 stable serialization compatibility', () {
    test('writes stable string codes instead of enum ordinals', () {
      final entry = WorldEntry(insertPosition: WorldEntryPosition.afterUser);
      final preset = PromptPreset(translationMode: TranslationMode.inputOnly);

      expect(entry.toJson()['insert_position'], 'after_user');
      expect(preset.toJson()['translation_mode'], 'input_only');
    });

    test('reads every legacy WorldEntry ordinal with frozen semantics', () {
      const expected = <WorldEntryPosition>[
        WorldEntryPosition.beforePrompt,
        WorldEntryPosition.afterPrompt,
        WorldEntryPosition.inAuthorNote,
        WorldEntryPosition.beforeHistory,
        WorldEntryPosition.afterUser,
      ];

      for (var ordinal = 0; ordinal < expected.length; ordinal++) {
        expect(
          WorldEntry.fromJson(_worldEntryFixture(ordinal)).insertPosition,
          expected[ordinal],
        );
      }
    });

    test('reads stable and legacy string WorldEntry codes', () {
      expect(
        WorldEntry.fromJson(_worldEntryFixture('before_history'))
            .insertPosition,
        WorldEntryPosition.beforeHistory,
      );
      expect(
        WorldEntry.fromJson(_worldEntryFixture('inAuthorNote')).insertPosition,
        WorldEntryPosition.inAuthorNote,
      );
    });

    test('fails closed for unknown and out-of-range structural values', () {
      expect(
        () => WorldEntry.fromJson(_worldEntryFixture('unknown')),
        throwsFormatException,
      );
      expect(
        () => WorldEntry.fromJson(_worldEntryFixture(99)),
        throwsFormatException,
      );
    });

    test('falls back only malformed optional WorldEntry fields', () {
      final diagnostics = <String>[];
      final entry = WorldEntry.fromJson(
        {
          ..._worldEntryFixture('after_prompt'),
          'keys': '{bad-json',
          'source_type': 42,
        },
        onOptionalFallback: diagnostics.add,
      );

      expect(entry.keys, isEmpty);
      expect(entry.sourceType, isEmpty);
      expect(diagnostics,
          containsAll(['malformed_keys', 'malformed_source_type']));
    });

    test('reads legacy translation ordinals and stable codes', () {
      expect(
        PromptPreset.fromJson({'translation_mode': 2}).translationMode,
        TranslationMode.outputOnly,
      );
      expect(
        PromptPreset.fromJson({'translation_mode': 'bidirectional'})
            .translationMode,
        TranslationMode.bidirectional,
      );
      expect(
        PromptPreset.fromJson({'translation_mode': 'inputOnly'})
            .translationMode,
        TranslationMode.inputOnly,
      );
    });

    test('fails closed for unknown translation mode', () {
      expect(
        () => PromptPreset.fromJson({'translation_mode': 40}),
        throwsFormatException,
      );
      expect(
        () => PromptPreset.fromJson({'translation_mode': 'future_mode'}),
        throwsFormatException,
      );
    });
  });
}
