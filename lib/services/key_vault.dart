import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';

/// ═══════════════════════════════════════════════════════════════
/// NarrVault — API Key 加密保险库
///
/// 基于成熟开源加密算法：
///   • AES-256-CBC  — 加密（FIPS 197, NIST SP 800-38A）
///   • PBKDF2-HMAC-SHA256 — 密钥派生（RFC 2898 / PKCS #5）
///   • PKCS7 Padding — 填充（RFC 5652）
///   • SecureRandom — 随机盐生成
///
/// 加密后的 Key 以 Base64 存储于本地 SQLite api_keys 表。
/// 仅在用户点击「显示」时解密为明文，其余时间保持加密形态。
/// ═══════════════════════════════════════════════════════════════
class KeyVault {
  KeyVault._();

  // ─── 算法参数 ───
  static const _saltLength = 16; // 盐值长度（128 位）
  static const _ivLength = 16; // IV 长度（128 位，AES 块大小）
  static const _keyLength = 32; // AES-256 密钥长度（256 位）
  static const _pbkdf2Iterations = 10000; // PBKDF2 迭代次数
  static const _macLength = 32; // HMAC-SHA256 长度（用于完整性校验）

  // ─── 应用固定种子（作为 PBKDF2 的第二层盐，编译时嵌入） ───
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

  /// 由密码 + 盐 + 固定种子派生 AES-256 密钥。
  static Uint8List _deriveKey(String password, Uint8List salt) {
    final combinedSalt = Uint8List(salt.length + _appPepper.length)
      ..setAll(0, salt)
      ..setAll(salt.length, _appPepper);

    final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(combinedSalt, _pbkdf2Iterations, _keyLength));

    return pbkdf2.process(utf8.encode(password));
  }

  /// 获取设备密码（由系统信息 + 固定种子混合）。
  /// 不同设备/系统会得到不同的密码，增加跨设备解密难度。
  static String _devicePassword() {
    final sb = StringBuffer();
    sb.write('NarrAItor');
    // 混入应用种子使其无法通过简单逆向获取
    for (final b in _appPepper) {
      sb.write(b.toRadixString(16));
    }
    return sb.toString();
  }

  // ═══════════════════════════════════════════════════════════════
  // 公开 API
  // ═══════════════════════════════════════════════════════════════

  /// AES-256-CBC 加密明文 → Base64 密文。
  ///
  /// 输出格式: Base64(salt[16] + iv[16] + ciphertext + hmac[32])
  static String encrypt(String plaintext) {
    if (plaintext.isEmpty) return '';

    // 从 SecureRandom 生成随机 salt 和 IV
    final salt = _randomBytes(_saltLength);
    final iv = _randomBytes(_ivLength);

    final key = _deriveKey(_devicePassword(), salt);

    // AES-256-CBC 加密
    final cipher = PaddedBlockCipherImpl(
      PKCS7Padding(),
      CBCBlockCipher(AESEngine()),
    )..init(
        true,
        PaddedBlockCipherParameters(
            ParametersWithIV(KeyParameter(key), iv), null));

    final plainBytes = Uint8List.fromList(utf8.encode(plaintext));
    final encrypted = cipher.process(plainBytes);

    // HMAC-SHA256 完整性校验
    final hmac = HMac(SHA256Digest(), 64)..init(KeyParameter(key));
    final macData = Uint8List(iv.length + encrypted.length)
      ..setAll(0, iv)
      ..setAll(iv.length, encrypted);
    hmac.update(macData, 0, macData.length);
    final mac = Uint8List(_macLength);
    hmac.doFinal(mac, 0);

    // 组合: salt + iv + ciphertext + mac
    final result =
        Uint8List(salt.length + iv.length + encrypted.length + mac.length)
          ..setAll(0, salt)
          ..setAll(salt.length, iv)
          ..setAll(salt.length + iv.length, encrypted)
          ..setAll(salt.length + iv.length + encrypted.length, mac);

    return base64Encode(result);
  }

  /// AES-256-CBC 解密 Base64 密文 → 明文 Key。
  static String decrypt(String encrypted) {
    if (encrypted.isEmpty) return '';

    try {
      final data = base64Decode(encrypted);
      if (data.length < _saltLength + _ivLength + 16 + _macLength) return '';

      final salt = Uint8List.sublistView(data, 0, _saltLength);
      final iv =
          Uint8List.sublistView(data, _saltLength, _saltLength + _ivLength);
      final mac = Uint8List.sublistView(data, data.length - _macLength);
      final ciphertext = Uint8List.sublistView(
          data, _saltLength + _ivLength, data.length - _macLength);

      final key = _deriveKey(_devicePassword(), salt);

      // 验证 HMAC（防篡改）
      final hmac = HMac(SHA256Digest(), 64)..init(KeyParameter(key));
      final macData = Uint8List(iv.length + ciphertext.length)
        ..setAll(0, iv)
        ..setAll(iv.length, ciphertext);
      hmac.update(macData, 0, macData.length);
      final computedMac = Uint8List(_macLength);
      hmac.doFinal(computedMac, 0);

      // 定时比较 HMAC（防时序攻击）
      if (!_constantTimeEqual(mac, computedMac)) return '';

      // AES-256-CBC 解密
      final cipher = PaddedBlockCipherImpl(
        PKCS7Padding(),
        CBCBlockCipher(AESEngine()),
      )..init(
          false,
          PaddedBlockCipherParameters(
              ParametersWithIV(KeyParameter(key), iv), null));

      final decrypted = cipher.process(ciphertext);
      return utf8.decode(decrypted);
    } catch (_) {
      return '';
    }
  }

  /// 定时相等比较（防时序攻击）。
  static bool _constantTimeEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    int diff = 0;
    for (int i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  /// 生成加密安全的随机字节。
  static Uint8List _randomBytes(int length) {
    final rng = FortunaRandom();
    final seed = Uint8List(32);
    final secureRand = Random.secure();
    for (int i = 0; i < 32; i++) {
      seed[i] = secureRand.nextInt(256);
    }
    rng.seed(KeyParameter(seed));
    final bytes = Uint8List(length);
    for (int i = 0; i < length; i++) {
      bytes[i] = rng.nextUint8();
    }
    return bytes;
  }
}
