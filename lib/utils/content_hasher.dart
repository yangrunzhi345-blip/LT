import 'dart:convert';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';

/// 内容哈希工具 — 用于保存去重
///
/// 将内容的标准化 JSON 表示进行 SHA256 哈希，同一内容始终产生相同哈希。
/// 保存前比对哈希即可判断是否已保存过相同内容，避免存储爆炸。
///
/// 用法:
///   final hash = ContentHasher.hashContent({'name': 'Alice', ...});
///   // 或对字符串
///   final hash = ContentHasher.hashString('some canonical string');
class ContentHasher {
  ContentHasher._();

  /// 对任意 Dart 对象计算 SHA256 内容哈希
  ///
  /// [content] 可以是 Map、List、String 等可 JSON 序列化的对象。
  /// 内部进行标准化 JSON 编码（键排序），确保同一内容产生相同哈希。
  static String hash(dynamic content) {
    final canonical = _canonicalEncode(content);
    return _sha256Base64(canonical);
  }

  /// 对已标准化的字符串直接计算哈希
  static String hashString(String canonical) {
    return _sha256Base64(canonical);
  }

  /// SHA256 → Base64URL 编码（无填充，URL 安全）
  static String _sha256Base64(String input) {
    final bytes = utf8.encode(input);
    final digest = SHA256Digest();
    final hash = digest.process(Uint8List.fromList(bytes));
    return base64Url.encode(hash);
  }

  /// 标准化 JSON 编码 — Map 键按字母序排列，消除序列化顺序差异
  static String _canonicalEncode(dynamic obj) {
    if (obj is Map) {
      final sorted = <String, dynamic>{};
      final keys = obj.keys.map((k) => k.toString()).toList()..sort();
      for (final key in keys) {
        sorted[key] = obj[key];
      }
      return jsonEncode(sorted);
    }
    if (obj is List) {
      return jsonEncode(obj.map((e) {
        if (e is Map) {
          final sorted = <String, dynamic>{};
          final keys = e.keys.map((k) => k.toString()).toList()..sort();
          for (final key in keys) {
            sorted[key] = e[key];
          }
          return sorted;
        }
        return e;
      }).toList());
    }
    return jsonEncode(obj);
  }
}
