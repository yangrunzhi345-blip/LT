enum TranslationMode {
  off,
  inputOnly,
  outputOnly,
  bidirectional,
}

extension TranslationModeStorage on TranslationMode {
  String get storageCode => switch (this) {
        TranslationMode.off => 'off',
        TranslationMode.inputOnly => 'input_only',
        TranslationMode.outputOnly => 'output_only',
        TranslationMode.bidirectional => 'bidirectional',
      };

  static TranslationMode decode(Object? value) => switch (value) {
        null || 'off' => TranslationMode.off,
        'input_only' || 'inputOnly' => TranslationMode.inputOnly,
        'output_only' || 'outputOnly' => TranslationMode.outputOnly,
        'bidirectional' => TranslationMode.bidirectional,
        0 => TranslationMode.off,
        1 => TranslationMode.inputOnly,
        2 => TranslationMode.outputOnly,
        3 => TranslationMode.bidirectional,
        _ => throw const FormatException('unknown translation mode'),
      };
}
