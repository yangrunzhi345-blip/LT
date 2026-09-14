/// Canonical Chinese-character counting for Adventure narrative text.
///
/// A "Chinese character" here is a BMP CJK Unified Ideograph in either:
///
/// * CJK Unified Ideographs Extension A, U+3400–U+4DBF
/// * CJK Unified Ideographs, U+4E00–U+9FFF
///
/// Everything else — ASCII, digits, Chinese/ASCII punctuation, whitespace,
/// newlines, emoji and other Unicode — counts as zero. Surrogate halves are
/// never counted, so emoji cannot inflate the total.
///
/// Both ranges live in the Basic Multilingual Plane, so a counted character is
/// always exactly one UTF-16 code unit. That lets callers locate a character by
/// code-unit index without risking a split surrogate pair.
///
/// This is deliberately narrower than full Unicode Han coverage (no Extension
/// B+ or compatibility ideographs); widening the definition is a separate
/// product decision, not a counting utility concern.
final class ChineseCharacterCounter {
  const ChineseCharacterCounter._();

  /// True when [codeUnit] is one of the canonical BMP CJK ideograph code units.
  static bool isChineseCodeUnit(int codeUnit) =>
      (codeUnit >= 0x3400 && codeUnit <= 0x4DBF) ||
      (codeUnit >= 0x4E00 && codeUnit <= 0x9FFF);

  /// Number of canonical Chinese characters in [text].
  static int count(String text) {
    var count = 0;
    for (var i = 0; i < text.length; i++) {
      if (isChineseCodeUnit(text.codeUnitAt(i))) count++;
    }
    return count;
  }
}
