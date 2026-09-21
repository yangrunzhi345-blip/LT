import '../../domain/read_aloud/read_aloud_contracts.dart';
import 'language_tag.dart';

/// 纯本地、确定性的朗读语言检测器。
///
/// 设计约束：
/// - **纯 Dart**：不依赖 Flutter、平台通道或网络，可独立单测；
/// - **不使用 LLM**：普通本地朗读不得因为语言识别而发起 API 请求；
/// - **按有效字符比例判定**：不会因为正文里出现三个拉丁字母（例如 `API`）
///   就把整段判断为英文；
/// - **确定性**：同样输入永远得到同样输出。
///
/// 检测基于 Unicode script 统计（Han / Hiragana / Katakana / Hangul / Latin），
/// 只统计字母类“有效字符”，忽略数字、标点、空白与 emoji。
class ReadAloudLanguageDetector {
  const ReadAloudLanguageDetector();

  /// 检测 [text] 的朗读语言，无法可靠判断时返回 [fallback]。
  ///
  /// [fallback] 是用户配置的固定/兜底语言（归一化 BCP-47）。非法或缺失时
  /// 回退到 [ReadAloudPreferences.defaultLanguageTag]。
  String detect(
    String text, {
    String fallback = ReadAloudPreferences.defaultLanguageTag,
  }) {
    final fallbackTag = _normalizedFallback(fallback);
    if (text.isEmpty) return fallbackTag;

    var han = 0;
    var kana = 0;
    var hangul = 0;
    var latin = 0;
    for (final rune in text.runes) {
      if (_isHangul(rune)) {
        hangul++;
      } else if (_isKana(rune)) {
        kana++;
      } else if (_isHan(rune)) {
        han++;
      } else if (_isLatinLetter(rune)) {
        latin++;
      }
    }

    final total = han + kana + hangul + latin;
    if (total == 0) return fallbackTag;

    // 假名是强日语信号：中文/韩文/英文正文都不会出现假名，因此允许较低比例。
    if (kana > 0 && kana / total >= _kanaRatio) return 'ja-JP';
    // 谚文是强韩语信号。
    if (hangul > 0 && hangul / total >= _hangulRatio) return 'ko-KR';

    final hanRatio = han / total;
    final latinRatio = latin / total;

    if (han >= latin && hanRatio >= _dominanceRatio) {
      return _resolveChineseVariant(text, fallbackTag);
    }
    if (latin > han && latinRatio >= _dominanceRatio) return 'en-US';

    // 混合且都未过半：按绝对数量取较大者，仍无法区分时按 Han 倾向处理。
    if (latin > han) return 'en-US';
    if (han > latin) return _resolveChineseVariant(text, fallbackTag);
    return han > 0 ? _resolveChineseVariant(text, fallbackTag) : fallbackTag;
  }

  /// 中文简繁倾向判断。
  ///
  /// Unicode Han 本身无法完美区分简体/繁体，这里只用一组小型的“特征字符”
  /// 做确定性倾向判断：命中明显更多的一方胜出，否则回退用户默认中文 locale。
  /// 不会因为少量共同汉字（如 `我们今天`）就错误断言某个变体。
  String _resolveChineseVariant(String text, String fallbackTag) {
    var simplifiedHits = 0;
    var traditionalHits = 0;
    for (final rune in text.runes) {
      final ch = String.fromCharCode(rune);
      if (_simplifiedCharacteristics.contains(ch)) simplifiedHits++;
      if (_traditionalCharacteristics.contains(ch)) traditionalHits++;
    }
    if (simplifiedHits > traditionalHits) return 'zh-CN';
    if (traditionalHits > simplifiedHits) return 'zh-TW';
    // 无法判断变体：以用户默认中文 locale 为准；用户兜底语言不是中文时
    // 使用中文默认值，避免把中文正文念成其它语言。
    return languageFamily(fallbackTag) == 'zh'
        ? fallbackTag
        : ReadAloudPreferences.defaultLanguageTag;
  }

  static String _normalizedFallback(String fallback) {
    final normalized = normalizeBcp47(fallback);
    return normalized.isEmpty
        ? ReadAloudPreferences.defaultLanguageTag
        : normalized;
  }

  /// 假名占有效字符的最小比例。
  static const double _kanaRatio = 0.10;

  /// 谚文占有效字符的最小比例。
  static const double _hangulRatio = 0.30;

  /// Han / Latin 至少达到该比例才直接判为中文 / 英文。
  static const double _dominanceRatio = 0.50;

  static bool _isKana(int rune) =>
      (rune >= 0x3040 && rune <= 0x309F) || // Hiragana
      (rune >= 0x30A0 && rune <= 0x30FF) || // Katakana
      (rune >= 0x31F0 && rune <= 0x31FF) || // Katakana phonetic extensions
      (rune >= 0xFF66 && rune <= 0xFF9D); // Halfwidth Katakana

  static bool _isHan(int rune) =>
      (rune >= 0x4E00 && rune <= 0x9FFF) || // CJK Unified Ideographs
      (rune >= 0x3400 && rune <= 0x4DBF) || // Extension A
      (rune >= 0xF900 && rune <= 0xFAFF) || // Compatibility Ideographs
      (rune >= 0x20000 && rune <= 0x2A6DF); // Extension B

  static bool _isHangul(int rune) =>
      (rune >= 0xAC00 && rune <= 0xD7A3) || // Hangul Syllables
      (rune >= 0x1100 && rune <= 0x11FF) || // Hangul Jamo
      (rune >= 0x3130 && rune <= 0x318F) || // Hangul Compatibility Jamo
      (rune >= 0xA960 && rune <= 0xA97F) || // Jamo Extended-A
      (rune >= 0xD7B0 && rune <= 0xD7FF); // Jamo Extended-B

  static bool _isLatinLetter(int rune) =>
      (rune >= 0x41 && rune <= 0x5A) ||
      (rune >= 0x61 && rune <= 0x7A) ||
      (rune >= 0xC0 && rune <= 0xD6) ||
      (rune >= 0xD8 && rune <= 0xF6) ||
      (rune >= 0xF8 && rune <= 0xFF) ||
      (rune >= 0x100 && rune <= 0x24F);

  /// 简体特征字符（仅存在于简体字形），用于倾向判断而非严格判定。
  static const String _simplifiedCharacterSource =
      '们这说时会对来么国学体发现变让点电语话请谢欢见觉认为应该处达与万东车门马鸟鱼龙书长贝页风飞无关开间问单独乐爱岁头义艺术机权员铁银钱验题颜历归给经统红级纪强张态样树桥气汉汤没决冲况净减冻划则刚创剧办务动劳势区医华协卖卫厂厅压厌县参双叶号叹吗听启团园围图圆圣场坏块坚坛坝坟垄垒垦垫';

  /// 繁体特征字符（与简体特征一一对应）。
  static const String _traditionalCharacterSource =
      '們這說時會對來麼國學體發現變讓點電語話請謝歡見覺認為應該處達與萬東車門馬鳥魚龍書長貝頁風飛無關開間問單獨樂愛歲頭義藝術機權員鐵銀錢驗題顏歷歸給經統紅級紀強張態樣樹橋氣漢湯沒決衝況淨減凍劃則剛創劇辦務動勞勢區醫華協賣衛廠廳壓厭縣參雙葉號嘆嗎聽啟團園圍圖圓聖場壞塊堅壇壩墳壟壘墾墊';

  static final Set<String> _simplifiedCharacteristics =
      _toCharacterSet(_simplifiedCharacterSource);

  static final Set<String> _traditionalCharacteristics =
      _toCharacterSet(_traditionalCharacterSource);

  static Set<String> _toCharacterSet(String source) =>
      source.runes.map(String.fromCharCode).toSet();
}
