/// Rule-based, offline speech planner.
///
/// It splits a narrative text into narration and dialogue segments and tries to
/// attribute dialogue to a known speaker using the *structured* speaker context
/// plus common Chinese/English quote and attribution patterns.
///
/// It never calls an LLM (that would add latency, cost, network dependence,
/// privacy risk and nondeterminism), never modifies the story text, and when it
/// is not confident it leaves the dialogue unattributed so the narrator reads it
/// rather than the wrong character.
library;

import '../../domain/tts/speech_plan.dart';

/// A quoted span found in a paragraph.
class _QuoteSpan {
  const _QuoteSpan({
    required this.outerStart,
    required this.outerEnd,
  });

  final int outerStart;
  final int outerEnd;

  String outer(String text) => text.substring(outerStart, outerEnd);
}

class SpeechPlanner {
  const SpeechPlanner();

  /// Recognized opening -> closing quote pairs.
  static const List<List<String>> _quotePairs = <List<String>>[
    <String>['“', '”'],
    <String>['「', '」'],
    <String>['『', '』'],
    <String>['"', '"'],
  ];

  /// Speech verbs / attribution cues. Presence near a name + quote raises
  /// confidence.
  static const List<String> _speechVerbs = <String>[
    '说道', '问道', '答道', '笑道', '喊道', '叫道', '吼道', '怒道', '叹道',
    '回答', '反问', '补充', '解释', '低声说', '轻声说', '大声说', '继续说',
    '开口说', '喃喃', '低语', '嘟囔', '嘟哝', '沉吟', '应道', '沉声道',
    '说', '问', '答', '喊', '叫', '道', '笑', '叹',
    // English
    'said', 'asked', 'replied', 'answered', 'shouted', 'whispered',
    'murmured', 'added', 'continued', 'called', 'cried', 'responded',
    'muttered', 'yelled', 'spoke', 'says',
  ];

  /// Colon immediately before a quote is a strong attribution cue.
  static const String _attributionColons = '：:';

  /// Sentences (paragraphs) are separated by blank lines.
  static final RegExp _paragraphSplit = RegExp(r'\n\s*\n');

  /// Plans [text] against [context]. [idPrefix] seeds stable segment ids.
  SpeechPlan plan(
    String text,
    NarrativeSpeakerContext context, {
    String idPrefix = 'seg',
  }) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return SpeechPlan.empty;

    final segments = <SpeechSegment>[];
    var index = 0;

    for (final rawParagraph in trimmed.split(_paragraphSplit)) {
      final paragraph = rawParagraph.trim();
      if (paragraph.isEmpty) continue;
      for (final piece in _planParagraph(paragraph, context)) {
        segments.add(
          SpeechSegment(
            id: '$idPrefix#$index',
            text: piece.text,
            role: piece.role,
            speakerResourceId: piece.speakerResourceId,
            confidence: piece.confidence,
          ),
        );
        index++;
      }
    }
    return SpeechPlan(segments: segments);
  }

  List<SpeechSegment> _planParagraph(
    String paragraph,
    NarrativeSpeakerContext context,
  ) {
    final quotes = _findQuotes(paragraph);
    if (quotes.isEmpty) {
      return <SpeechSegment>[_narration(paragraph)];
    }

    final result = <SpeechSegment>[];
    var cursor = 0;
    for (var quoteIndex = 0; quoteIndex < quotes.length; quoteIndex++) {
      final quote = quotes[quoteIndex];
      final before = quote.outerStart > cursor
          ? paragraph.substring(cursor, quote.outerStart).trim()
          : '';
      if (before.isNotEmpty) {
        result.add(_narration(before));
      }
      final nextQuote = quoteIndex + 1;
      final after = quote.outerEnd < paragraph.length
          ? paragraph.substring(
              quote.outerEnd,
              nextQuote < quotes.length
                  ? quotes[nextQuote].outerStart
                  : paragraph.length)
          : '';
      final attribution = _attribute(
        before: before,
        after: after,
        context: context,
      );
      // Planning partitions text; it does not edit punctuation or the quoted
      // words. Any TTS cleaning belongs to the shared sanitizer boundary.
      result.add(
        SpeechSegment(
          id: '',
          text: quote.outer(paragraph),
          role: SpeechRole.dialogue,
          speakerResourceId: attribution.resourceId,
          confidence: attribution.confidence,
        ),
      );
      cursor = quote.outerEnd;
    }
    final tail = paragraph.substring(cursor).trim();
    if (tail.isNotEmpty) {
      result.add(_narration(tail));
    }
    if (result.isEmpty) return <SpeechSegment>[_narration(paragraph)];
    return result;
  }

  SpeechSegment _narration(String text) => SpeechSegment(
        id: '',
        text: text,
        role: SpeechRole.narration,
        confidence: 1,
      );

  /// Attributes the quote to at most one known speaker, or none.
  _Attribution _attribute({
    required String before,
    required String after,
    required NarrativeSpeakerContext context,
  }) {
    if (context.isEmpty) return const _Attribution(null, 0);

    // Only the adjacent sentence/clause can supply attribution. A name in an
    // earlier sentence or a later quote is not evidence of who is speaking.
    final preceding = before.split(RegExp(r'[。！？.!?\n]')).last.trim();
    final following = after.split(RegExp(r'[，,。！？.!?\n]')).first.trim();
    final candidates = <String>{};
    for (final cue in <String>[
      preceding,
      // A colon opens the next dialogue; it cannot attribute the previous one.
      if (!following.endsWith('：') && !following.endsWith(':')) following,
    ]) {
      if (cue.isEmpty) continue;
      final ids = <String>{};
      for (final speaker in context.speakers) {
        for (final name in speaker.names) {
          if (_isNamedAttribution(cue, name)) ids.add(speaker.resourceId);
        }
      }
      if (ids.length > 1) return const _Attribution(null, 0);
      candidates.addAll(ids);
    }
    return candidates.length == 1
        ? _Attribution(candidates.single, 0.9)
        : const _Attribution(null, 0);
  }

  bool _isNamedAttribution(String cue, String name) {
    final escaped = RegExp.escape(name);
    // Word boundaries prevent Ann matching Joanne. Chinese attribution has no
    // spaces, so accept only known speech/action prefixes after the whole name;
    // arbitrary suffixes such as 林雪儿 must stay unattributed.
    final englishVerb =
        _speechVerbs.where((v) => RegExp(r'^[a-z]+$').hasMatch(v)).join('|');
    if (RegExp('^$escaped\\s+(?:$englishVerb)\\b[\\s,:]*\$',
                caseSensitive: false)
            .hasMatch(cue) ||
        RegExp('^(?:$englishVerb)\\s+$escaped[\\s,:]*\$', caseSensitive: false)
            .hasMatch(cue)) {
      return true;
    }
    if (!cue.startsWith(name)) return false;
    final suffix = cue.substring(name.length).trim();
    if (RegExp('^[$_attributionColons]\$').hasMatch(suffix)) return true;
    if (suffix.isEmpty) return false;
    final verbs = _speechVerbs.where((v) => !RegExp(r'^[a-z]+$').hasMatch(v));
    final actions = RegExp(r'^(望|看|摇头|点头|抬头|低头|转身|微笑|笑|叹|轻声|低声|大声|沉声)');
    // Commas or a second subject make this cue ambiguous rather than assigning
    // the quote to the first person mentioned in a compound sentence.
    if (RegExp(r'[，,：:].+[，,：:]').hasMatch(suffix) ||
        RegExp(r'[，,]')
            .hasMatch(suffix.replaceFirst(RegExp(r'[，,]\s*$'), ''))) {
      return false;
    }
    final end = suffix.replaceFirst(RegExp(r'[：:,，]\s*$'), '').trim();
    final speech = verbs.map(RegExp.escape).join('|');
    if (RegExp('^(?:(?:摇头|点头|抬头|低头|转身|微笑|轻声|低声|大声|沉声)\\s*)?(?:$speech)\$')
        .hasMatch(end)) {
      return true;
    }
    // Named actions with a colon are allowed, but a later speech verb could
    // belong to an unnamed object (林雪看见路人说). Never infer that object's id.
    return (suffix.endsWith('：') || suffix.endsWith(':')) &&
        actions.hasMatch(end) &&
        !verbs.any(end.contains);
  }

  /// Scans [text] for recognized quote spans.
  List<_QuoteSpan> _findQuotes(String text) {
    final spans = <_QuoteSpan>[];
    var i = 0;
    while (i < text.length) {
      final ch = text[i];
      var opened = false;
      for (final pair in _quotePairs) {
        if (ch != pair[0]) continue;
        // Straight double quote used as an inch/quote after a digit is not an
        // opening quote.
        if (ch == '"' && i > 0 && _isDigit(text[i - 1])) continue;
        final close = _findClose(text, i + 1, pair[1], ch);
        if (close < 0) break;
        // Empty or whitespace-only quotes are skipped but delimiters consumed.
        if (close > i + 1) {
          spans.add(
            _QuoteSpan(
              outerStart: i,
              outerEnd: close + 1,
            ),
          );
        }
        i = close + 1;
        opened = true;
        break;
      }
      if (!opened) i++;
    }
    return spans;
  }

  int _findClose(String text, int from, String close, String open) {
    // Straight double quotes: match the next straight double quote.
    for (var i = from; i < text.length; i++) {
      if (text[i] == close) return i;
      // Do not let a “...” span cross into a different quote style.
    }
    return -1;
  }

  static bool _isDigit(String ch) {
    final code = ch.codeUnitAt(0);
    return code >= 0x30 && code <= 0x39;
  }
}

class _Attribution {
  const _Attribution(this.resourceId, this.confidence);
  final String? resourceId;
  final double confidence;
}
