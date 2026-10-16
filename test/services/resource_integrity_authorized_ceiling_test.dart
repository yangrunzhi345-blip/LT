import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/domain/resources/resource_limits.dart';
import 'package:lt_dialogue/services/resource_integrity_validator.dart';

/// An authorized AI generation run may store a card body above the type's
/// ordinary absolute capacity (24000) up to its frozen ceiling. Re-editing that
/// resource must not reject it, while an ordinary (unauthorized) write keeps the
/// absolute ceiling.
void main() {
  String cardJson(int bodyLength) => jsonEncode({
        'spec': 'chara_card_v2',
        'data': {'name': '测试', 'description': '文' * bodyLength},
      });

  group('character card body ceiling', () {
    test('an unauthorized body above the absolute is rejected', () {
      expect(
        () => ResourceIntegrityValidator.validateCharacterCard(
            name: '测试', jsonData: cardJson(24001)),
        throwsA(isA<ResourceValidationException>()),
      );
    });

    test('an authorized ceiling accepts a body up to C = 30000', () {
      const authorized =
          ResourceLimits.characterAbsoluteCharacters + 6000; // 30000
      expect(
        () => ResourceIntegrityValidator.validateCharacterCard(
          name: '测试',
          jsonData: cardJson(30000),
          effectiveCeiling: authorized,
        ),
        returnsNormally,
      );
      expect(
        () => ResourceIntegrityValidator.validateCharacterCard(
          name: '测试',
          jsonData: cardJson(30001),
          effectiveCeiling: authorized,
        ),
        throwsA(isA<ResourceValidationException>()),
      );
    });

    test('an effective ceiling below the absolute can never narrow it', () {
      // A caller passing a smaller number is clamped back up to the absolute.
      expect(
        () => ResourceIntegrityValidator.validateCharacterCard(
          name: '测试',
          jsonData: cardJson(24001),
          effectiveCeiling: 20000,
        ),
        throwsA(isA<ResourceValidationException>()),
        reason: 'the ordinary absolute still applies',
      );
      expect(
        () => ResourceIntegrityValidator.validateCharacterCard(
          name: '测试',
          jsonData: cardJson(24000),
          effectiveCeiling: 20000,
        ),
        returnsNormally,
      );
    });
  });

  group('npc card body ceiling', () {
    test('an unauthorized body above the absolute is rejected', () {
      expect(
        () => ResourceIntegrityValidator.validateNpcCard(
            name: '测试', jsonData: cardJson(24001)),
        throwsA(isA<ResourceValidationException>()),
      );
    });

    test('an authorized ceiling accepts a body up to C = 30000', () {
      const authorized = ResourceLimits.npcAbsoluteCharacters + 6000;
      expect(
        () => ResourceIntegrityValidator.validateNpcCard(
          name: '测试',
          jsonData: cardJson(28000),
          effectiveCeiling: authorized,
        ),
        returnsNormally,
      );
    });
  });
}
