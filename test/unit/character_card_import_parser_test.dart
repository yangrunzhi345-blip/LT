import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:lt_dialogue/models/character_card.dart';

/// Builds a minimal PNG whose `chara` tEXt chunk carries [cardJson].
///
/// The parser in [CharacterCard.extractJsonFromPngBytes] only needs the 8-byte
/// signature plus a well-formed tEXt chunk, so CRC bytes can stay zero.
Uint8List _pngWithCharaText(String cardJson) {
  final keyword = utf8.encode('chara');
  final text = utf8.encode(cardJson);
  final data = <int>[...keyword, 0, ...text];

  final bytes = <int>[137, 80, 78, 71, 13, 10, 26, 10];
  void writeUint32(int value) {
    bytes.addAll([
      (value >> 24) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 8) & 0xFF,
      value & 0xFF,
    ]);
  }

  writeUint32(data.length);
  bytes.addAll(utf8.encode('tEXt'));
  bytes.addAll(data);
  writeUint32(0); // CRC placeholder, ignored by the parser.
  return Uint8List.fromList(bytes);
}

void main() {
  group('CharacterCard external import parser tolerance', () {
    test('JSON import accepts legacy scalar type variants', () {
      final card = CharacterCard.parseFromJson(jsonEncode({
        'data': {
          'name': 42,
          'personality': true,
          'first_mes': 7,
          'character_version': 2,
          'tags': [1, 2],
          'alternate_greetings': [3],
        },
      }));

      expect(card, isNotNull);
      expect(card!.name, '42');
      expect(card.personality, 'true');
      expect(card.firstMessage, '7');
      expect(card.characterVersion, '2');
      expect(card.tags, ['1', '2']);
      expect(card.alternateGreetings, ['3']);
    });

    test('JSON import tolerates a non-map data wrapper', () {
      final card =
          CharacterCard.parseFromJson(jsonEncode({'data': 7, 'name': 5}));
      expect(card, isNotNull);
      expect(card!.name, '5');
    });

    test('PNG import routes through the same tolerant parser', () {
      final bytes = _pngWithCharaText(jsonEncode({
        'name': 99,
        'tags': [10],
      }));
      final cards = CharacterCard.parseFromPngBytes(bytes);
      expect(cards, hasLength(1));
      expect(cards.single.name, '99');
      expect(cards.single.tags, ['10']);
      expect(cards.single.importSource, 'PNG导入');
    });

    test('fromJsonString tolerates a non-object top level', () {
      expect(CharacterCard.fromJsonString('[1,2,3]').name, isEmpty);
      expect(CharacterCard.fromJsonString('"text"').name, isEmpty);
    });
  });
}
