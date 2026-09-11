import 'dart:convert';

import 'package:equatable/equatable.dart';

/// Chat role understood by the transport layer.
enum LlmRole {
  system,
  user,
  assistant,
  tool;

  String get wireValue => name;

  static LlmRole fromString(String? value) {
    return switch (value?.trim().toLowerCase()) {
      'system' => LlmRole.system,
      'assistant' => LlmRole.assistant,
      'tool' => LlmRole.tool,
      _ => LlmRole.user,
    };
  }
}

/// A single piece of a (possibly multimodal) message.
sealed class LlmContentPart with Equatable {
  const LlmContentPart();

  Map<String, dynamic> toWirePart();
}

final class LlmTextPart extends LlmContentPart {
  final String text;

  const LlmTextPart(this.text);

  @override
  Map<String, dynamic> toWirePart() => {'type': 'text', 'text': text};

  @override
  List<Object?> get props => [text];
}

/// Inline base64 image. Encoding to a data URI is the transport's job so
/// callers never hand-build an OpenAI content-block array as a JSON string.
final class LlmImagePart extends LlmContentPart {
  final String base64;
  final String mimeType;

  /// Optional provider detail hint (`low` / `high` / `original`).
  final String? detail;

  const LlmImagePart({
    required this.base64,
    this.mimeType = 'image/jpeg',
    this.detail,
  });

  String get dataUri => 'data:$mimeType;base64,$base64';

  @override
  Map<String, dynamic> toWirePart() => {
        'type': 'image_url',
        'image_url': {
          'url': dataUri,
          if (detail != null) 'detail': detail,
        },
      };

  @override
  List<Object?> get props => [base64, mimeType, detail];
}

/// An assistant tool invocation.
class LlmToolCall with Equatable {
  final String id;
  final String name;
  final String argumentsJson;

  const LlmToolCall({
    required this.id,
    required this.name,
    this.argumentsJson = '{}',
  });

  Map<String, dynamic> toWireMap() => {
        'id': id,
        'type': 'function',
        'function': {'name': name, 'arguments': argumentsJson},
      };

  @override
  List<Object?> get props => [id, name, argumentsJson];
}

/// Typed chat message.
///
/// Unlike the legacy `Map<String, String>`, this can express reasoning traces,
/// tool calls, tool results and image blocks. The transport converts it to the
/// provider wire shape; the legacy map form remains available through
/// [LlmMessageAdapter] so producers can migrate incrementally.
class LlmMessage with Equatable {
  final LlmRole role;
  final List<LlmContentPart> parts;

  /// Assistant thinking trace. Normally stripped from follow-up requests;
  /// DeepSeek requires it to be echoed back when Thinking is combined with
  /// tool calls, which is why it is representable here.
  final String? reasoningContent;

  /// Assistant tool invocations.
  final List<LlmToolCall> toolCalls;

  /// Set on a `tool` result message to bind it back to its call.
  final String? toolCallId;

  /// Optional tool/function name.
  final String? name;

  const LlmMessage({
    required this.role,
    this.parts = const [],
    this.reasoningContent,
    this.toolCalls = const [],
    this.toolCallId,
    this.name,
  });

  bool get hasImages => parts.any((part) => part is LlmImagePart);

  String get joinedText =>
      parts.whereType<LlmTextPart>().map((part) => part.text).join();

  factory LlmMessage.system(String text) =>
      LlmMessage(role: LlmRole.system, parts: [LlmTextPart(text)]);

  factory LlmMessage.user(String text) =>
      LlmMessage(role: LlmRole.user, parts: [LlmTextPart(text)]);

  factory LlmMessage.userWithImages({
    required List<LlmImagePart> images,
    String text = '',
  }) {
    return LlmMessage(role: LlmRole.user, parts: [
      ...images,
      if (text.isNotEmpty) LlmTextPart(text),
    ]);
  }

  factory LlmMessage.assistant({
    String? text,
    String? reasoningContent,
    List<LlmToolCall> toolCalls = const [],
  }) {
    return LlmMessage(
      role: LlmRole.assistant,
      parts: [if (text != null && text.isNotEmpty) LlmTextPart(text)],
      reasoningContent: reasoningContent,
      toolCalls: toolCalls,
    );
  }

  factory LlmMessage.toolResult({
    required String toolCallId,
    required String content,
    String? name,
  }) {
    return LlmMessage(
      role: LlmRole.tool,
      parts: [LlmTextPart(content)],
      toolCallId: toolCallId,
      name: name,
    );
  }

  /// Provider-agnostic serialization.
  ///
  /// Text-only messages keep `content` as a String so existing requests stay
  /// byte-identical; image messages emit the OpenAI content-block array.
  /// [includeReasoningContent] is opt-in because reasoning must not normally be
  /// echoed back; only the Thinking + tool-call flow needs it.
  Map<String, dynamic> toWireMap({bool includeReasoningContent = false}) {
    final map = <String, dynamic>{'role': role.wireValue};
    map['content'] = hasImages
        ? parts.map((part) => part.toWirePart()).toList()
        : joinedText;
    if (toolCalls.isNotEmpty) {
      map['tool_calls'] = toolCalls.map((call) => call.toWireMap()).toList();
    }
    if (toolCallId != null) map['tool_call_id'] = toolCallId;
    if (name != null) map['name'] = name;
    if (includeReasoningContent && reasoningContent != null) {
      map['reasoning_content'] = reasoningContent;
    }
    return map;
  }

  @override
  List<Object?> get props =>
      [role, parts, reasoningContent, toolCalls, toolCallId, name];
}

/// Bridges the legacy `List<Map<String, String>>` message form to [LlmMessage]
/// and back, so the transport can be typed while producers migrate gradually.
class LlmMessageAdapter {
  LlmMessageAdapter._();

  static List<LlmMessage> fromLegacy(List<Map<String, String>> messages) {
    return messages.map(_fromLegacyMessage).toList(growable: false);
  }

  static LlmMessage _fromLegacyMessage(Map<String, String> message) {
    final role = LlmRole.fromString(message['role']);
    final content = message['content'] ?? '';
    // Compatibility: older vision call sites encoded an OpenAI content-block
    // array as a JSON string. Decode it into typed parts so the transport no
    // longer has to special-case '['-prefixed content.
    if (content.trimLeft().startsWith('[')) {
      final parts = _tryDecodeParts(content);
      if (parts != null && parts.isNotEmpty) {
        return LlmMessage(role: role, parts: parts);
      }
    }
    return LlmMessage(role: role, parts: [LlmTextPart(content)]);
  }

  static List<LlmContentPart>? _tryDecodeParts(String content) {
    try {
      final decoded = jsonDecode(content);
      if (decoded is! List) return null;
      final parts = <LlmContentPart>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final type = item['type']?.toString();
        if (type == 'text') {
          parts.add(LlmTextPart(item['text']?.toString() ?? ''));
        } else if (type == 'image_url') {
          final imageUrl = item['image_url'];
          final url = imageUrl is Map ? imageUrl['url']?.toString() : null;
          if (url == null) continue;
          final detail =
              imageUrl is Map ? imageUrl['detail']?.toString() : null;
          parts.add(_imageFromDataUri(url, detail));
        }
      }
      return parts;
    } catch (_) {
      return null;
    }
  }

  static LlmImagePart _imageFromDataUri(String url, String? detail) {
    final comma = url.indexOf(',');
    if (!url.startsWith('data:') || comma <= 5) {
      return LlmImagePart(base64: url, detail: detail);
    }
    final meta = url.substring(5, comma);
    final mime = meta.split(';').first;
    return LlmImagePart(
      base64: url.substring(comma + 1),
      mimeType: mime.isEmpty ? 'image/jpeg' : mime,
      detail: detail,
    );
  }

  /// Flattens to the legacy text form. Used by code paths (e.g. the Anthropic
  /// adapter) that only understand plain string content.
  static List<Map<String, String>> toLegacy(List<LlmMessage> messages) {
    return messages
        .map((message) => {
              'role': message.role.wireValue,
              'content': message.joinedText,
            })
        .toList(growable: false);
  }
}
