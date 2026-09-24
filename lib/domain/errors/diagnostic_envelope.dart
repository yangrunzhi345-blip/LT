import 'dart:convert';

/// Locale-neutral diagnostic stored in legacy text columns.
final class DiagnosticEnvelope {
  const DiagnosticEnvelope({
    required this.code,
    this.parameters = const <String, Object?>{},
  });

  final String code;
  final Map<String, Object?> parameters;

  String encode() => jsonEncode(<String, Object?>{
        '_lt_diagnostic': 1,
        'code': code,
        'params': parameters,
      });

  static DiagnosticEnvelope? tryDecode(String value) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is! Map || decoded['_lt_diagnostic'] != 1) return null;
      final code = decoded['code'];
      final params = decoded['params'];
      if (code is! String || params is! Map) return null;
      return DiagnosticEnvelope(
        code: code,
        parameters: Map<String, Object?>.from(params),
      );
    } on FormatException {
      return null;
    }
  }
}
