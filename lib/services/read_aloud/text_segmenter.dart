/// 长文本分段器。
///
/// 分段目的：把整段正文切成 TTS 友好的小段，使“上一段/下一段/暂停”可定位，
/// 同时避免超长无标点文本一次性塞给引擎。
///
/// 分段不会增删正文内容（除边界空白外）：把每段拼回去、去掉空白后必须与
/// 输入去掉空白后完全一致。测试依赖这一不变式。
class TextSegmenter {
  const TextSegmenter({this.maxLength = 140});

  /// 单段最大长度（UTF-16 code unit）。中英混排下约等于一到两句话。
  final int maxLength;

  /// 中英文句末标点；英文 `.` 需额外判断后才算句末。
  static const String _terminators = '。！？!?；;…';

  /// 把 [text] 切分为若干非空段。
  List<String> segment(String text) {
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) return const <String>[];

    final effectiveMax = maxLength < 2 ? 2 : maxLength;
    final atoms = _splitAtoms(normalized);
    final segments = <String>[];
    final buffer = StringBuffer();
    var bufferedUnits = 0;

    void flush() {
      if (buffer.isEmpty) return;
      segments.add(buffer.toString());
      buffer.clear();
      bufferedUnits = 0;
    }

    for (final atom in atoms) {
      final trimmed = atom.trim();
      if (trimmed.isEmpty) continue;
      if (trimmed.length > effectiveMax) {
        flush();
        segments.addAll(_hardSplit(trimmed, effectiveMax));
        continue;
      }
      final needed = bufferedUnits == 0 ? trimmed.length : trimmed.length + 1;
      if (bufferedUnits > 0 && bufferedUnits + needed > effectiveMax) {
        flush();
      }
      if (buffer.isEmpty) {
        buffer.write(trimmed);
        bufferedUnits = trimmed.length;
      } else {
        buffer.write(' ');
        buffer.write(trimmed);
        bufferedUnits += trimmed.length + 1;
      }
    }
    flush();
    return segments;
  }

  /// 按标点切分为“原子句”。英文句点仅在后续是空白或结尾时才算句末，
  /// 以免切开小数（3.14）或缩写（Fig. 1）。
  List<String> _splitAtoms(String text) {
    final atoms = <String>[];
    final buffer = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      buffer.write(ch);
      final isTerminator = _terminators.contains(ch) || ch == '.';
      if (!isTerminator) continue;
      if (ch == '.') {
        final next = i + 1 < text.length ? text[i + 1] : '';
        if (next.isNotEmpty && !_isWhitespaceUnit(next)) continue;
      }
      atoms.add(buffer.toString());
      buffer.clear();
    }
    if (buffer.isNotEmpty) atoms.add(buffer.toString());
    return atoms;
  }

  /// 超长原子句的兜底切分：优先在空白处断开，否则按码点边界断开，
  /// 保证不会切坏代理对（emoji/生僻字）。
  List<String> _hardSplit(String atom, int maxUnits) {
    final runes = atom.runes.toList(growable: false);
    final pieces = <String>[];
    var start = 0;
    while (start < runes.length) {
      var end = start;
      var units = 0;
      while (end < runes.length) {
        final width = runes[end] > 0xFFFF ? 2 : 1;
        if (units + width > maxUnits && end > start) break;
        units += width;
        end++;
      }
      var cut = end;
      if (end < runes.length) {
        final floor = start + (end - start) ~/ 2;
        for (var k = end - 1; k > floor; k--) {
          if (_isWhitespaceRune(runes[k])) {
            cut = k;
            break;
          }
        }
      }
      if (cut <= start) cut = end;
      final piece = String.fromCharCodes(runes.sublist(start, cut)).trim();
      if (piece.isNotEmpty) pieces.add(piece);
      start = cut;
      while (start < runes.length && _isWhitespaceRune(runes[start])) {
        start++;
      }
    }
    return pieces;
  }

  static bool _isWhitespaceUnit(String ch) =>
      ch == ' ' || ch == '\t' || ch == '\n' || ch == '\u3000';

  static bool _isWhitespaceRune(int rune) =>
      rune == 0x20 ||
      rune == 0x09 ||
      rune == 0x0A ||
      rune == 0x0D ||
      rune == 0x3000;
}
