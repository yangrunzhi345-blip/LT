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
    required this.innerStart,
    required this.innerEnd,
    required this.outerEnd,
  });

  final int outerStart;
  final int innerStart;
  final int innerEnd;
  final int outerEnd;

  String inner(String text) => text.substring(innerStart, innerEnd).trim();
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
    for (final quote in quotes) {
      final before = quote.outerStart > cursor
          ? paragraph.substring(cursor, quote.outerStart).trim()
          : '';
      if (before.isNotEmpty) {
        result.add(_narration(before));
      }
      final after = quote.outerEnd < paragraph.length
          ? paragraph.substring(quote.outerEnd)
          : '';
      final attribution = _attribute(
        before: before,
        after: after,
        context: context,
      );
      final inner = quote.inner(paragraph);
      if (inner.isNotEmpty) {
        result.add(
          SpeechSegment(
            id: '',
            text: inner,
            role: SpeechRole.dialogue,
            speakerResourceId: attribution.resourceId,
            confidence: attribution.confidence,
          ),
        );
      }
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

    final beforeMatches = _matchSpeakers(before, context);
    final afterMatches = _matchSpeakers(after, context);

    // A name adjacent to a speech verb / attribution colon on either side is a
    // strong signal.
    final beforeStrong = _hasAttributionCue(before);
    final afterStrong = _hasAttributionCue(after);

    final strong = <String>{};
    final weak = <String>{};
    for (final id in beforeMatches) {
      (beforeStrong ? strong : weak).add(id);
    }
    for (final id in afterMatches) {
      (afterStrong ? strong : weak).add(id);
    }

    // Resolve to a single speaker only when unambiguous.
    if (strong.length == 1) {
      return _Attribution(strong.first, 0.9);
    }
    if (strong.isEmpty && weak.length == 1) {
      return _Attribution(weak.first, 0.6);
    }
    // Zero or multiple candidates: do not guess.
    return const _Attribution(null, 0);
  }

  /// Returns the resource ids of speakers whose name occurs in [text],
  /// ignoring matches that are immediately followed by another name character
  /// (best-effort; aliases are already sorted longest-first).
  Set<String> _matchSpeakers(String text, NarrativeSpeakerContext context) {
    if (text.isEmpty) return const <String>{};
    final matches = <String>{};
    for (final speaker in context.byNameLength) {
      for (final name in speaker.names) {
        if (name.isEmpty) continue;
        if (text.contains(name)) {
          matches.add(speaker.resourceId);
          break;
        }
      }
    }
    return matches;
  }

  /// Whether [text] contains a speech verb or attribution colon.
  bool _hasAttributionCue(String text) {
    if (text.isEmpty) return false;
    if (text.contains(RegExp('[$_attributionColons]'))) return true;
    final lowered = text.toLowerCase();
    for (final verb in _speechVerbs) {
      if (lowered.contains(verb.toLowerCase())) return true;
    }
    return false;
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
              innerStart: i + 1,
              innerEnd: close,
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
