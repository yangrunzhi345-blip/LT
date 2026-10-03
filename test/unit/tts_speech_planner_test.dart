import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/domain/tts/speech_plan.dart';
import 'package:lt_dialogue/services/tts/speech_planner.dart';

void main() {
  const planner = SpeechPlanner();

  NarrativeSpeakerContext contextOf(List<List<String>> entries) {
    return NarrativeSpeakerContext(
      speakers: <NarrativeSpeakerRef>[
        for (final entry in entries)
          NarrativeSpeakerRef(
            resourceId: entry[0],
            displayName: entry[1],
            aliases: entry.length > 2 ? <String>[entry[2]] : const <String>[],
          ),
      ],
    );
  }

  final context = contextOf(<List<String>>[
    <String>['char-lin', '林雪', 'Lin'],
    <String>['char-chen', '陈默'],
    <String>['char-lin-alias', '阿雪', '小雪'],
  ]);

  test('empty text yields an empty plan', () {
    expect(planner.plan('', context).isEmpty, isTrue);
    expect(planner.plan('   ', context).isEmpty, isTrue);
  });

  test('text without quotes is entirely narration', () {
    final plan = planner.plan('雨越来越大。', context);
    expect(plan.segments, hasLength(1));
    expect(plan.segments.single.role, SpeechRole.narration);
    expect(plan.segments.single.text, '雨越来越大。');
  });

  test('a colon-attributed quote is assigned to the named speaker', () {
    final plan = planner.plan('林雪望向远处：“我们不能继续待在这里。”', context);
    final dialogue = plan.segments.where((s) => s.isDialogue).toList();
    expect(dialogue, hasLength(1));
    expect(dialogue.single.speakerResourceId, 'char-lin');
    // The planner partitions the authored text without dropping quote marks.
    expect(dialogue.single.text, '“我们不能继续待在这里。”');
    expect(dialogue.single.confidence, greaterThan(0.5));
    // The surrounding text stays narration.
    expect(
      plan.segments.any(
          (s) => s.role == SpeechRole.narration && s.text.contains('林雪望向远处')),
      isTrue,
    );
  });

  test('a verb-attributed quote after the quote is assigned', () {
    final plan = planner.plan('“再等五分钟。”陈默摇头说。', context);
    final dialogue = plan.segments.firstWhere((s) => s.isDialogue);
    expect(dialogue.speakerResourceId, 'char-chen');
  });

  test('two co-occurring speakers in one cue are not guessed', () {
    final plan = planner.plan('林雪说，陈默回答：“好的。”', context);
    final dialogue = plan.segments.where((s) => s.isDialogue).toList();
    expect(dialogue, hasLength(1));
    expect(dialogue.single.speakerResourceId, isNull);
    expect(dialogue.single.confidence, 0);
  });

  test('an unknown speaker is read as narrator, never guessed', () {
    final plan = planner.plan('路人喊道：“让开！”', context);
    final dialogue = plan.segments.where((s) => s.isDialogue).toList();
    expect(dialogue, hasLength(1));
    expect(dialogue.single.speakerResourceId, isNull);
  });

  test('English attribution works', () {
    final plan = planner.plan('Lin said, "Let us go now."', context);
    final dialogue = plan.segments.where((s) => s.isDialogue).toList();
    expect(dialogue, hasLength(1));
    expect(dialogue.single.speakerResourceId, 'char-lin');
  });

  test('multiple paragraphs keep order and roles', () {
    final plan = planner.plan(
      '雨越来越大。\n\n林雪望向远处：“我们不能继续待在这里。”\n\n陈默摇头：“再等五分钟。”',
      context,
    );
    final dialogues = plan.segments.where((s) => s.isDialogue).toList();
    expect(dialogues, hasLength(2));
    expect(dialogues[0].speakerResourceId, 'char-lin');
    expect(dialogues[1].speakerResourceId, 'char-chen');
    // No text is lost (narration + dialogue preserve the content).
    final joined = plan.segments.map((s) => s.text).join();
    expect(joined.contains('雨越来越大'), isTrue);
    expect(joined.contains('再等五分钟'), isTrue);
  });

  test('an empty context never attributes dialogue', () {
    final plan = planner.plan(
      '林雪说：“好。”',
      const NarrativeSpeakerContext.empty(),
    );
    expect(plan.speakerResourceIds, isEmpty);
  });

  test('segment ids are stable and ordered', () {
    final plan = planner.plan('第一段。\n\n第二段。', context, idPrefix: 'src');
    expect(plan.segments.first.id, 'src#0');
    expect(plan.segments[1].id, 'src#1');
  });

  group('local attribution safety', () {
    test(
        'should preserve all authored punctuation and content when partitioning',
        () {
      for (final text in <String>[
        '林雪说：“你好。”\n\n陈默：“再见。”',
        '“你好，”林雪说，“我们走吧。”',
        '林雪说：“她说「我们走吧」。”',
        '林雪说：“她说“我们走吧”。”',
        '林雪说：“”\n\n陈默说：“   ”',
        'Lin said, "Hello, \\"friend\\"."',
      ]) {
        String nonWhitespace(String value) =>
            value.replaceAll(RegExp(r'\s'), '');
        final joined =
            planner.plan(text, context).segments.map((s) => s.text).join();
        expect(nonWhitespace(joined), nonWhitespace(text), reason: text);
      }
    });
    test('should recognize the required Chinese and English local forms', () {
      for (final text in [
        '“你好。”林雪说道。',
        '林雪说：“你好。”',
        '林雪：“你好。”',
        'Lin said, "Hello."',
        '"Hello," Lin said.'
      ]) {
        expect(planner.plan(text, context).speakerResourceIds, ['char-lin'],
            reason: text);
      }
    });
    for (final text in <String>[
      '林雪看向门口。路人说：“你好。”',
      '林雪看见路人说：“你好。”',
      '林雪看向门口。“你好。”',
      '林雪儿说：“你好。”',
      '“你好。”随后林雪走了过来。',
    ]) {
      test('should use narrator for $text', () {
        final dialogue = planner
            .plan(text, context)
            .segments
            .where((s) => s.isDialogue)
            .single;
        expect(dialogue.speakerResourceId, isNull);
      });
    }
    test('should not match English name substrings', () {
      final names = contextOf(<List<String>>[
        <String>['ann', 'Ann'],
      ]);
      expect(
          planner
              .plan('JoAnne said, "Hello."', names)
              .segments
              .firstWhere((s) => s.isDialogue)
              .speakerResourceId,
          isNull);
    });
    test('should preserve separate local and interrupted attributions', () {
      final dialogues = planner
          .plan('林雪说：“你好。”陈默说：“再见。”', context)
          .segments
          .where((s) => s.isDialogue)
          .toList();
      expect(
          dialogues.map((s) => s.speakerResourceId), ['char-lin', 'char-chen']);
      final interrupted = planner
          .plan('“你好，”林雪说，“我们走吧。”', context)
          .segments
          .where((s) => s.isDialogue);
      expect(interrupted.map((s) => s.speakerResourceId),
          ['char-lin', 'char-lin']);
    });
    test('should leave duplicate names and alias conflicts unattributed', () {
      for (final names in <NarrativeSpeakerContext>[
        contextOf([
          ['a', '林雪'],
          ['b', '林雪']
        ]),
        contextOf([
          ['a', '林雪', '小雪'],
          ['b', '阿雪', '小雪']
        ]),
      ]) {
        final text =
            names.speakers.first.aliases.isEmpty ? '林雪说：“你好。”' : '小雪说：“你好。”';
        expect(planner.plan(text, names).speakerResourceIds, isEmpty);
      }
    });
  });
}
