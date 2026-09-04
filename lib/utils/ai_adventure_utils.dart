import 'dart:convert';
import 'structured_json_codec.dart';

/// AI 冒险生成工具函数 — 可从 landing_screen.dart 中 _callAi/_parseJson 复用
class AiAdventureUtils {
  /// 手动构建 JSON 请求体（绕过 jsonEncode 以兼容特殊字符）
  static String buildJsonBody(String model, String content) {
    final escaped = content
        .replaceAll('\\', '\\\\')
        .replaceAll('"', '\\"')
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '\\r')
        .replaceAll('\t', '\\t');
    return '{"model":"$model","messages":[{"role":"user","content":"$escaped"}],"temperature":0.7,"max_tokens":1024}';
  }

  /// 清理字符串中可能导致 jsonEncode 失败的字符
  static String sanitizeForJson(String input) {
    final bytes = utf8.encode(input);
    final filtered =
        bytes.where((b) => b >= 0x20 || b == 0x0A || b == 0x09).toList();
    return utf8.decode(filtered, allowMalformed: true);
  }

  /// 从 AI 响应文本中提取 JSON 对象
  static Map<String, dynamic>? parseJson(String text) =>
      StructuredJsonCodec.tryDecodeObject(text);
}
