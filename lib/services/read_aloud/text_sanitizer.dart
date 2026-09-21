/// 朗读正文清洗器。
///
/// TTS 绝不能直接朗读“原始模型输出”：其中可能混有 Markdown 标记、HTML、
/// 协议 JSON、隐藏 metadata、思维链与异常空白。本清洗器只保留“用户当前能看到
/// 的正文”，并且必须是确定性的（同样的输入永远得到同样的输出）。
///
/// 注意：这里不做任何 LLM/API 调用。普通本地朗读不得依赖网络，否则会引入
/// 费用、延迟与文本漂移。`synthesizeWithLLM` 只作为兼容路径保留在
/// `TtsService`，不参与标准朗读流程。
class TextSanitizer {
  const TextSanitizer();

  /// `---JSON---` 之后的所有结构化数据。
  static final RegExp _jsonSeparator =
      RegExp(r'-{2,}\s*json\s*-{2,}[\s\S]*$', caseSensitive: false);

  /// 未闭合的代码围栏也要整体剔除，避免把半截代码念出来。
  static final RegExp _fencedCode = RegExp(r'```[\s\S]*?(?:```|$)');

  static final RegExp _reasoningBlock = RegExp(
    r'<(thinking|think|reasoning|analysis|scratchpad|reflection)\b[^>]*>[\s\S]*?</\1\s*>',
    caseSensitive: false,
  );

  static final RegExp _htmlComment = RegExp(r'<!--[\s\S]*?-->');
  static final RegExp _htmlTag = RegExp(r'<[^>]*>');

  static final RegExp _image = RegExp(r'!\[[^\]]*\]\([^)]*\)');
  static final RegExp _link = RegExp(r'\[([^\]]*)\]\([^)]*\)');
  static final RegExp _inlineCode = RegExp(r'`([^`\n]*)`');

  /// `*斜体*` / `**粗体**` / `***两者***`。
  static final RegExp _asteriskEmphasis = RegExp(r'\*{1,3}([^*\n]+)\*{1,3}');
  static final RegExp _underscoreEmphasis = RegExp(r'_{1,3}([^_\n]+)_{1,3}');
  static final RegExp _strike = RegExp(r'~~([^~\n]+)~~');

  static final RegExp _heading =
      RegExp(r'^[ \t]{0,3}#{1,6}[ \t]+', multiLine: true);
  static final RegExp _blockquote =
      RegExp(r'^[ \t]{0,3}>[ \t]?', multiLine: true);
  static final RegExp _listMarker =
      RegExp(r'^[ \t]{0,3}(?:[-*+]|\d{1,3}[.)])[ \t]+', multiLine: true);
  static final RegExp _horizontalRule =
      RegExp(r'^[ \t]{0,3}(?:[-*_][ \t]*){3,}$', multiLine: true);
  static final RegExp _tableSeparatorRow = RegExp(
    r'^[ \t]*\|?[ \t]*:?-{2,}:?[ \t]*(?:\|[ \t]*:?-{2,}:?[ \t]*)*\|?[ \t]*$',
    multiLine: true,
  );

  static final RegExp _crlf = RegExp(r'\r\n?');
  static final RegExp _invisible = RegExp('[\u200B-\u200D\uFEFF\u00AD]');
  static final RegExp _horizontalSpaces = RegExp(r'[ \t\u3000]+');
  static final RegExp _newlinePadding = RegExp(r'[ \t]*\n[ \t]*');
  static final RegExp _collapsedNewlines = RegExp(r'\n{3,}');

  /// 清洗为可直接交给本地 TTS 的可见正文。
  String sanitize(String input) {
    if (input.isEmpty) return '';
    var text = input.replaceAll(_crlf, '\n').replaceAll(_invisible, '');

    text = text.replaceAll(_htmlComment, '');
    text = text.replaceAll(_reasoningBlock, '');
    text = text.replaceAll(_jsonSeparator, '');
    text = text.replaceAll(_fencedCode, '');

    text = text.replaceAll(_image, '');
    text = text.replaceAllMapped(_link, (m) => m.group(1) ?? '');
    text = text.replaceAll(_htmlTag, '');
    text = text.replaceAllMapped(_inlineCode, (m) => m.group(1) ?? '');

    text = text.replaceAll(_tableSeparatorRow, '');
    text = text.replaceAll(_horizontalRule, '');
    text = text.replaceAll(_listMarker, '');
    text = text.replaceAll(_blockquote, '');
    text = text.replaceAll(_heading, '');

    text = text.replaceAllMapped(_strike, (m) => m.group(1) ?? '');
    text = text.replaceAllMapped(_asteriskEmphasis, (m) => m.group(1) ?? '');
    text = text.replaceAllMapped(_underscoreEmphasis, (m) => m.group(1) ?? '');
    // 残留的孤立星号/竖线对朗读没有意义，读出来反而干扰。
    text = text.replaceAll('*', '').replaceAll('|', ' ');

    text = text.replaceAll(_horizontalSpaces, ' ');
    text = text.replaceAll(_newlinePadding, '\n');
    text = text.replaceAll(_collapsedNewlines, '\n\n');
    return text.trim();
  }
}
