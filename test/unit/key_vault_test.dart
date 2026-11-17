import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/services/key_vault.dart';

void main() {
  group('KeyVault v2 format', () {
    test('round-trips and carries the version marker', () {
      final encoded = KeyVault.encrypt('sk-v2-round-trip');
      final bytes = base64Decode(encoded);
      expect(bytes.sublist(0, 4), [0x4C, 0x54, 0x56, 0x32]);

      final opened = KeyVault.open(encoded);
      expect(opened, isNotNull);
      expect(opened!.plaintext, 'sk-v2-round-trip');
      expect(opened.usedLegacyFormat, isFalse);
      expect(KeyVault.decrypt(encoded), 'sk-v2-round-trip');
    });

    test('uses fresh salt and IV for every write', () {
      final first = KeyVault.encrypt('same-secret');
      final second = KeyVault.encrypt('same-secret');
      expect(first, isNot(second));
      expect(KeyVault.decrypt(first), 'same-secret');
      expect(KeyVault.decrypt(second), 'same-secret');
    });

    test('rejects a tampered authentication tag', () {
      final bytes = base64Decode(KeyVault.encrypt('tamper-target'));
      bytes[bytes.length - 1] ^= 0x01;
      expect(KeyVault.open(base64Encode(bytes)), isNull);
      expect(KeyVault.decrypt(base64Encode(bytes)), '');
    });

    test('rejects malformed base64 without throwing', () {
      expect(KeyVault.open('not-base64!!!'), isNull);
      expect(KeyVault.decrypt('not-base64!!!'), '');
    });
  });

  group('legacy compatibility', () {
    test('opens a pre-v2 record and reports the legacy format', () {
      final legacy = KeyVault.encryptLegacyForTest('sk-legacy');
      final opened = KeyVault.open(legacy);
      expect(opened, isNotNull);
      expect(opened!.plaintext, 'sk-legacy');
      expect(opened.usedLegacyFormat, isTrue);
      expect(KeyVault.decrypt(legacy), 'sk-legacy');
    });

    test('rejects a tampered legacy authentication tag', () {
      final bytes = base64Decode(KeyVault.encryptLegacyForTest('legacy'));
      bytes[bytes.length - 1] ^= 0x01;
      expect(KeyVault.open(base64Encode(bytes)), isNull);
    });
  });
}
