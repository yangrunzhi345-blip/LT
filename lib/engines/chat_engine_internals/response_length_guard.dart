import 'dart:math' as math;

import '../../models/completion_params.dart';
import '../../utils/chinese_character_counter.dart';

/// Splits a model response into the narrative displayed to the player and its
/// optional single settlement payload.
final class NarrativeResponseParts {
  final String narrative;
  final String payload;

  const NarrativeResponseParts({
    required this.narrative,
    required this.payload,
  });

  bool get hasPayload => payload.isNotEmpty;
}

/// Three-way verdict of a narrative against the full [minimum, hardMaximum]
/// range. [passed] alone only models the lower bound, which let over-long
/// responses be misreported as "达标".
enum NarrativeLengthVerdict { underflow, withinRange, overflow }

/// The immutable outcome of the one permitted same-turn length supplement.
final class NarrativeLengthGuardResult {
  final String content;
  final int initialChineseChars;
  final int supplementChineseChars;
  final int finalChineseChars;
  final bool supplementAttempted;
  final bool supplementSucceeded;

  /// True when the narrative exceeded [NarrativeLengthGuard.hardMaximum] and
  /// had to be safely converged at a paragraph/sentence boundary.
  final bool overflowDetected;

  const NarrativeLengthGuardResult({
    required this.content,
    required this.initialChineseChars,
    required this.supplementChineseChars,
    required this.finalChineseChars,
    required this.supplementAttempted,
    required this.supplementSucceeded,
    this.overflowDetected = false,
  });

  bool passed(int minimumChineseChars) =>
      finalChineseChars >= minimumChineseChars;

  bool withinMaximum(int hardMaximum) => finalChineseChars <= hardMaximum;

  NarrativeLengthVerdict verdict(int minimumChineseChars, int hardMaximum) {
    if (finalChineseChars < minimumChineseChars) {
      return NarrativeLengthVerdict.underflow;
    }
    if (finalChineseChars > hardMaximum) {
      return NarrativeLengthVerdict.overflow;
    }
    return NarrativeLengthVerdict.withinRange;
  }
}

/// Pure, deterministic operations for the ChatEngine same-turn length guard.
///
/// This deliberately owns no LLM client: the engine remains the sole runtime
/// request entry point and supplies the single continuation request.
final class NarrativeLengthGuard {
  static const jsonMarker = '---JSON---';
  // A short Chinese sentence plus punctuation is commonly six characters;
  // accepting it avoids visibly repeating an immediately preceding sentence.
  static const _minimumOverlapLength = 6;
  static const _maximumOverlapLength = 400;

  const NarrativeLengthGuard();

  NarrativeResponseParts split(String rawResponse) {
    final markerIndex = rawResponse.indexOf(jsonMarker);
    if (markerIndex < 0) {
      return NarrativeResponseParts(
        narrative: rawResponse.trim(),
        payload: '',
      );
    }
    return NarrativeResponseParts(
      narrative: rawResponse.substring(0, markerIndex).trim(),
      payload: rawResponse.substring(markerIndex).trim(),
    );
  }

  /// Counts canonical Chinese characters via the shared
  /// [ChineseCharacterCounter], matching [ChatEngine.countChinese] exactly.
  int countChinese(String text) => ChineseCharacterCounter.count(text);

  /// Leaves enough headroom that a model estimating its own output does not
  /// stop a few characters short of the hard minimum.
  int desiredTotalChars(int minimumChineseChars) {
    final safetyMargin =
        (minimumChineseChars * 0.08).ceil().clamp(30, 300).toInt();
    return minimumChineseChars + safetyMargin;
  }

  int requestedAdditionalChars({
    required int currentChineseChars,
    required int minimumChineseChars,
  }) =>
      math.max(
        desiredTotalChars(minimumChineseChars) - currentChineseChars,
        30,
      );

  /// Preserves the user's sampling configuration while disabling reasoning
  /// only for the deterministic continuation request.
  CompletionParams supplementParams(
    CompletionParams userParams, {
    required int maximumOutputTokens,
  }) =>
      userParams.copyWith(
        enableThinking: false,
        maxTokens: maximumOutputTokens,
      );

  String buildSupplementPrompt({
    required NarrativeResponseParts initial,
    required int currentChineseChars,
    required int minimumChineseChars,
  }) {
    final desiredTotal = desiredTotalChars(minimumChineseChars);
    final additional = requestedAdditionalChars(
      currentChineseChars: currentChineseChars,
      minimumChineseChars: minimumChineseChars,
    );
    if (initial.narrative.trim().isEmpty) {
      // Missing-narrative recovery: the model returned only a settlement
      // payload (or an unusable fragment).  Keep the payload and ask for the
      // prose exactly once in the same turn.
      final payloadReference = initial.hasPayload
          ? '\n以下是本轮已经生成的结算 JSON，请以其 scene/options 与最近对话为依据撰写正文：\n${initial.payload}'
          : '';
      return '''【内部正文补足请求】
本轮尚未生成任何叙事正文，但已经产生了结局结算数据。请根据最近对话、玩家刚才的行动以及结算数据中的 scene/options，撰写本轮完整叙事正文，至少 $desiredTotal 个纯汉字。$payloadReference

这是同一轮回复的正文补写，不是新的剧情回合。不要重新分析玩家意图、重新规划剧情方向、判断状态或生成新分支；不要推翻既定事件结果或重新结算，不要替玩家追加行动或决定。
9. 不得输出 $jsonMarker。
10. 不得输出 options、custom_status 或 custom_status_changes。
11. 直接从正文开始；不要解释补写、字数或本指令。''';
    }
    final finalizeInstruction = initial.hasPayload
        ? '''
9. 不得重新进行状态结算。
10. 不得输出 $jsonMarker。
11. 不得输出 options、custom_status 或 custom_status_changes。'''
        : '''
9. 完成后只输出一次 $jsonMarker 和完整最终 JSON，遵守原本的状态与选项格式。
10. 不得重复第一段已经写过的内容。''';
    return '''【内部长度补足请求】
你刚才的本轮叙事正文只有 $currentChineseChars 个纯汉字，本轮最低要求为 $minimumChineseChars 个，仍需至少补充 $additional 个纯汉字。请直接承接上一段正文，将本轮完整正文补充到至少 $desiredTotal 个纯汉字。

这是已经完成主要推理和剧情决策后的正文补充阶段，也是同一轮回复的后续补写，不是新的剧情回合。不要重新分析玩家意图、规划剧情方向、选择角色目标、判断状态或生成新分支；不要推翻上一段事件结果或重新结算。只需保持人物、地点、世界规则、玩家行动和事件结果完全连续，补充已有场景中的动作、环境、对白、反应、心理和余波。不得替玩家追加行动或决定，不得引入冲突新事实，不得用设定、装备列表或总结凑字数。$finalizeInstruction
11. 直接从续写正文开始；不要解释补写、字数或本指令。''';
  }

  NarrativeLengthGuardResult merge({
    required String initialRawResponse,
    required String supplementRawResponse,
    required bool supplementSucceeded,
  }) {
    final initial = split(initialRawResponse);
    final supplement = split(supplementRawResponse);
    final trimmedSupplement = removeContinuationOverlap(
      initial.narrative,
      supplement.narrative,
    );
    final narrative = [initial.narrative, trimmedSupplement]
        .where((part) => part.isNotEmpty)
        .join('\n\n');
    // A valid original settlement is authoritative. Otherwise the one emitted
    // by the continuation completes the previously truncated response.
    final payload = initial.hasPayload ? initial.payload : supplement.payload;
    final content = payload.isEmpty ? narrative : '$narrative\n$payload';
    return NarrativeLengthGuardResult(
      content: content,
      initialChineseChars: countChinese(initial.narrative),
      supplementChineseChars: countChinese(trimmedSupplement),
      finalChineseChars: countChinese(narrative),
      supplementAttempted: true,
      supplementSucceeded: supplementSucceeded,
    );
  }

  NarrativeLengthGuardResult withoutSupplement(String rawResponse) {
    final initial = split(rawResponse);
    final chars = countChinese(initial.narrative);
    return NarrativeLengthGuardResult(
      content: rawResponse,
      initialChineseChars: chars,
      supplementChineseChars: 0,
      finalChineseChars: chars,
      supplementAttempted: false,
      supplementSucceeded: false,
    );
  }

  String removeContinuationOverlap(String initial, String supplement) {
    final maxLength = math.min(
      math.min(initial.length, supplement.length),
      _maximumOverlapLength,
    );
    for (var length = maxLength; length >= _minimumOverlapLength; length--) {
      if (initial.endsWith(supplement.substring(0, length))) {
        return supplement.substring(length).trimLeft();
      }
    }
    return supplement;
  }

  /// Safely trims a narrative that exceeded the hard maximum back to a complete
  /// paragraph/sentence boundary. This is a last-resort defence; the engine
  /// should already have budgeted generation to stay under the cap.
  ///
  /// It never cuts mid-sentence, and it never touches the settlement payload
  /// (which is separated from the narrative before this is called).
  ///
  /// Runs in linear time: the Chinese count of `a + b` equals the sum of their
  /// counts, so a single running total replaces re-scanning the accumulated
  /// prefix on every paragraph.
  String convergeToMaximum(String narrative, int hardMaximum) {
    if (countChinese(narrative) <= hardMaximum) return narrative;

    final paragraphs = narrative
        .split(RegExp(r'\n\s*\n'))
        .map((paragraph) => paragraph.trim())
        .where((paragraph) => paragraph.isNotEmpty)
        .toList();
    final kept = <String>[];
    var usedChinese = 0;
    for (final paragraph in paragraphs) {
      final paragraphChinese = countChinese(paragraph);
      if (usedChinese + paragraphChinese <= hardMaximum) {
        kept.add(paragraph);
        usedChinese += paragraphChinese;
        continue;
      }
      final remainingBudget = hardMaximum - usedChinese;
      final trimmed = _trimToSentenceBoundary(paragraph, remainingBudget);
      if (trimmed.isNotEmpty) kept.add(trimmed);
      break;
    }
    return kept.join('\n\n');
  }

  /// Keeps whole sentences until the next sentence would exceed [maxChars].
  /// Falls back to the whole paragraph when no sentence boundary exists, so a
  /// hard cap never produces a half sentence.
  ///
  /// Linear in [text]: sentences never overlap, so a running count avoids
  /// re-scanning the growing candidate on every sentence.
  String _trimToSentenceBoundary(String text, int maxChars) {
    if (maxChars <= 0) return '';
    if (countChinese(text) <= maxChars) return text.trim();
    final sentences = RegExp(r'[^。！？；\n]*[。！？；\n]')
        .allMatches(text)
        .map((match) => match.group(0)!)
        .toList();
    if (sentences.isEmpty) return text.trim(); // no boundary: keep intact
    final kept = StringBuffer();
    var usedChinese = 0;
    for (final sentence in sentences) {
      final sentenceChinese = countChinese(sentence);
      if (usedChinese + sentenceChinese > maxChars) break;
      kept.write(sentence);
      usedChinese += sentenceChinese;
    }
    return kept.toString().trim();
  }
}
