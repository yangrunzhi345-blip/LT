import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:pointycastle/export.dart';

/// Application-level encryption for API keys stored in local SQLite.
///
/// Security model: this is **application-layer obfuscation**, not device
/// binding and not an OS credential store. The PBKDF2 password and pepper are
/// compiled into the application; the per-record salt and IV are random. This
/// raises the cost of casual inspection of the database, but anyone who can
/// read both the database and reverse the application binary can recover the
/// key. It is not a substitute for platform keychain / keystore storage.
///
/// Format v2: Base64("LTV2" + salt[16] + iv[16] + ciphertext + mac[32]).
/// PBKDF2-HMAC-SHA256 derives a 64-byte master secret which is split into
/// independent AES-256 and HMAC-SHA256 subkeys (encrypt-then-MAC).
///
/// Legacy format: Base64(salt[16] + iv[16] + ciphertext + mac[32]) with a
/// single 32-byte key reused for encryption and authentication. [open] still
/// accepts it so existing databases migrate without losing user keys.
class KeyVault {
  KeyVault._();

  static const _saltLength = 16;
  static const _ivLength = 16;
  static const _keyLength = 32;
  static const _masterLength = _keyLength * 2;
  static const _pbkdf2Iterations = 10000;
  static const _macLength = 32;

  /// Versioned marker that makes a v2 record distinguishable from a legacy
  /// one without relying on a random salt byte.
  static const List<int> _magic = [0x4C, 0x54, 0x56, 0x32]; // "LTV2"
  static const _magicLength = 4;

  /// Compile-time pepper. It is part of the application binary, not a secret
  /// stored by the OS; see the security model above.
  static final _appPepper = Uint8List.fromList([
    0x7B,
    0x1E,
    0x4A,
    0x9F,
    0xD3,
    0x88,
    0x2C,
    0x56,
    0xA1,
    0x0F,
    0x63,
    0xBE,
    0xC5,
    0x3D,
    0x71,
    0x98,
  ]);

  /// Application-level PBKDF2 password.
  ///
  /// This is intentionally a constant: there is no per-device secret available
  /// without an OS credential store. The comment must not imply device binding.
  static String _appPassword() {
    final sb = StringBuffer('LT_Dialogue');
    for (final b in _appPepper) {
      sb.write(b.toRadixString(16));
    }
    return sb.toString();
  }

  /// Legacy derivation: one 32-byte key for both AES and HMAC.
  ///
  /// Kept only to open records written before format v2.
  static Uint8List _deriveLegacyKey(String password, Uint8List salt) {
    final combinedSalt = Uint8List(salt.length + _appPepper.length)
      ..setAll(0, salt)
      ..setAll(salt.length, _appPepper);
    final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(combinedSalt, _pbkdf2Iterations, _keyLength));
    return pbkdf2.process(utf8.encode(password));
  }

  /// Derives independent encryption and authentication subkeys from one
  /// 64-byte PBKDF2 output.
  static ({Uint8List encryption, Uint8List authentication}) _deriveKeys(
    String password,
    Uint8List salt,
  ) {
    final combinedSalt = Uint8List(salt.length + _appPepper.length)
      ..setAll(0, salt)
      ..setAll(salt.length, _appPepper);
    final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(combinedSalt, _pbkdf2Iterations, _masterLength));
    final master = pbkdf2.process(utf8.encode(password));
    return (
      encryption: Uint8List.fromList(master.sublist(0, _keyLength)),
      authentication:
          Uint8List.fromList(master.sublist(_keyLength, _masterLength)),
    );
  }

  /// Encrypts with the current v2 format.
  ///
  /// Output: Base64("LTV2" + salt[16] + iv[16] + ciphertext + mac[32]).
  static String encrypt(String plaintext) {
    if (plaintext.isEmpty) return '';

    final salt = _randomBytes(_saltLength);
    final iv = _randomBytes(_ivLength);
    final keys = _deriveKeys(_appPassword(), salt);

    final cipher = PaddedBlockCipherImpl(
      PKCS7Padding(),
      CBCBlockCipher(AESEngine()),
    )..init(
        true,
        PaddedBlockCipherParameters(
            ParametersWithIV(KeyParameter(keys.encryption), iv), null));
    final plainBytes = Uint8List.fromList(utf8.encode(plaintext));
    final encrypted = cipher.process(plainBytes);

    final header = Uint8List(_magic.length + salt.length + iv.length)
      ..setAll(0, _magic)
      ..setAll(_magic.length, salt)
      ..setAll(_magic.length + salt.length, iv);
    final macData = Uint8List(header.length + encrypted.length)
      ..setAll(0, header)
      ..setAll(header.length, encrypted);
    final mac = _hmac(keys.authentication, macData);

    final result = Uint8List(macData.length + mac.length)
      ..setAll(0, macData)
      ..setAll(macData.length, mac);
    return base64Encode(result);
  }

  /// Encrypts using the pre-v2 single-key format.
  ///
  /// Only tests use this to build realistic legacy fixtures; production code
  /// never writes this format again.
  @visibleForTesting
  static String encryptLegacyForTest(String plaintext) {
    if (plaintext.isEmpty) return '';

    final salt = _randomBytes(_saltLength);
    final iv = _randomBytes(_ivLength);
    final key = _deriveLegacyKey(_appPassword(), salt);

    final cipher = PaddedBlockCipherImpl(
      PKCS7Padding(),
      CBCBlockCipher(AESEngine()),
    )..init(
        true,
        PaddedBlockCipherParameters(
            ParametersWithIV(KeyParameter(key), iv), null));
    final plainBytes = Uint8List.fromList(utf8.encode(plaintext));
    final encrypted = cipher.process(plainBytes);

    final macData = Uint8List(iv.length + encrypted.length)
      ..setAll(0, iv)
      ..setAll(iv.length, encrypted);
    final mac = _hmac(key, macData);

    final result = Uint8List(salt.length + macData.length + mac.length)
      ..setAll(0, salt)
      ..setAll(salt.length, macData)
      ..setAll(salt.length + macData.length, mac);
    return base64Encode(result);
  }

  /// Opens either a current v2 record or a legacy single-key record.
  ///
  /// Returns null for malformed, tampered or undecryptable input. A v2 marker
  /// whose authentication/decryption fails still falls back to the legacy
  /// parser, matching the required smooth-migration behaviour.
  static KeyVaultOpenResult? open(String encoded) {
    if (encoded.isEmpty) return null;

    final Uint8List data;
    try {
      data = base64Decode(encoded);
    } catch (_) {
      return null;
    }

    if (_hasMagic(data)) {
      final plaintext = _decryptV2(data);
      if (plaintext != null) {
        return KeyVaultOpenResult(
          plaintext: plaintext,
          usedLegacyFormat: false,
        );
      }
    }

    final legacy = _decryptLegacy(data);
    if (legacy != null) {
      return KeyVaultOpenResult(
        plaintext: legacy,
        usedLegacyFormat: true,
      );
    }
    return null;
  }

  /// Backward-compatible text API. Prefer [open] when the caller needs to know
  /// whether the record must be re-encrypted.
  static String decrypt(String encrypted) => open(encrypted)?.plaintext ?? '';

  static String? _decryptV2(Uint8List data) {
    const minimumLength =
        _magicLength + _saltLength + _ivLength + 16 + _macLength;
    if (data.length < minimumLength) return null;
    try {
      const saltStart = _magicLength;
      const ivStart = saltStart + _saltLength;
      const cipherStart = ivStart + _ivLength;
      final macStart = data.length - _macLength;
      if (macStart <= cipherStart) return null;

      final salt = Uint8List.sublistView(data, saltStart, ivStart);
      final iv = Uint8List.sublistView(data, ivStart, cipherStart);
      final mac = Uint8List.sublistView(data, macStart);
      final ciphertext = Uint8List.sublistView(data, cipherStart, macStart);
      final keys = _deriveKeys(_appPassword(), salt);

      final authenticated = Uint8List.sublistView(data, 0, macStart);
      final computedMac = _hmac(keys.authentication, authenticated);
      if (!_constantTimeEqual(mac, computedMac)) return null;

      final cipher = PaddedBlockCipherImpl(
        PKCS7Padding(),
        CBCBlockCipher(AESEngine()),
      )..init(
          false,
          PaddedBlockCipherParameters(
              ParametersWithIV(KeyParameter(keys.encryption), iv), null));
      return utf8.decode(cipher.process(ciphertext));
    } catch (_) {
      return null;
    }
  }

  static String? _decryptLegacy(Uint8List data) {
    if (data.length < _saltLength + _ivLength + 16 + _macLength) return null;
    try {
      final salt = Uint8List.sublistView(data, 0, _saltLength);
      final iv =
          Uint8List.sublistView(data, _saltLength, _saltLength + _ivLength);
      final mac = Uint8List.sublistView(data, data.length - _macLength);
      final ciphertext = Uint8List.sublistView(
          data, _saltLength + _ivLength, data.length - _macLength);

      final key = _deriveLegacyKey(_appPassword(), salt);
      final macData = Uint8List(iv.length + ciphertext.length)
        ..setAll(0, iv)
        ..setAll(iv.length, ciphertext);
      final computedMac = _hmac(key, macData);
      if (!_constantTimeEqual(mac, computedMac)) return null;

      final cipher = PaddedBlockCipherImpl(
        PKCS7Padding(),
        CBCBlockCipher(AESEngine()),
      )..init(
          false,
          PaddedBlockCipherParameters(
              ParametersWithIV(KeyParameter(key), iv), null));
      return utf8.decode(cipher.process(ciphertext));
    } catch (_) {
      return null;
    }
  }

  static Uint8List _hmac(Uint8List key, Uint8List data) {
    final hmac = HMac(SHA256Digest(), 64)..init(KeyParameter(key));
    hmac.update(data, 0, data.length);
    final mac = Uint8List(_macLength);
    hmac.doFinal(mac, 0);
    return mac;
  }

  static bool _hasMagic(Uint8List data) {
    if (data.length < _magic.length) return false;
    for (var i = 0; i < _magic.length; i++) {
      if (data[i] != _magic[i]) return false;
    }
    return true;
  }

  /// Constant-time comparison to avoid leaking MAC prefix information.
  static bool _constantTimeEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  /// Cryptographically secure random bytes.
  static Uint8List _randomBytes(int length) {
    final rng = FortunaRandom();
    final seed = Uint8List(32);
    final secureRand = Random.secure();
    for (var i = 0; i < 32; i++) {
      seed[i] = secureRand.nextInt(256);
    }
    rng.seed(KeyParameter(seed));
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = rng.nextUint8();
    }
    return bytes;
  }
}

/// Result of opening one API-key record.
final class KeyVaultOpenResult {
  const KeyVaultOpenResult({
    required this.plaintext,
    required this.usedLegacyFormat,
  });

  final String plaintext;

  /// True when the record was written by the pre-v2 single-key format and
  /// should be rewritten with [KeyVault.encrypt].
  final bool usedLegacyFormat;
}
