import 'dart:convert';

import 'app_event.dart';

/// In-band, versioned representation for events stored in Message.content.
final class AppEventCodec {
  static const int currentVersion = 1;
  static const String marker = '_lt_event';

  static String encode(AppEvent event) => jsonEncode(<String, Object?>{
        marker: currentVersion,
        'code': event.code.name,
        'payload': event.payload,
      });

  static AppEvent? decode(String content) {
    try {
      final value = jsonDecode(content);
      if (value is! Map<String, dynamic> || value[marker] != currentVersion) {
        return null;
      }
      final codeName = value['code'];
      final payload = value['payload'];
      if (codeName is! String || payload is! Map) return null;
      final code = AppEventCode.values.where((item) => item.name == codeName);
      if (code.isEmpty) return null;
      return AppEvent(
        code: code.first,
        payload: Map<String, Object?>.from(payload),
      );
    } on FormatException {
      return null;
    }
  }
}
