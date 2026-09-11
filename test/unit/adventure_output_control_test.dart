import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/engines/chat_engine_internals/response_length_guard.dart';
import 'package:lt_dialogue/models/adventure_response.dart';
import 'package:lt_dialogue/models/scene_dialogue.dart';

/// 4 角色 × 4 自添加项 = 16 状态 的完整快照 JSON。
String _buildSixteenStateJson() {
  final chars = ['主角', '艾莉丝', '莫维奇', '索尔'];
  final status = <Map<String, dynamic>>[];
  for (var i = 0; i < chars.length; i++) {
    for (var j = 0; j < 4; j++) {
      status.add({
        'id': 's${i}_$j',
        'name': '状态${i}_$j',
        'value': '${(i + 1) * 10 + j}/100',
        'currentValue': (i + 1) * 10 + j,
        'maxValue': 100,
        'characterName': chars[i],
      });
    }
  }
  return jsonEncode({
    'scene': '大厅',
    'options': ['前进', '后退', '观察'],
    'custom_status': status,
  });
}

void main() {
  group('LLM history projection (JSON reflux isolation)', () {
    test('strips the full custom_status snapshot from assistant history', () {
      final content = '你推开木门，屋内一片漆黑。\n---JSON---\n'
          '${_buildSixteenStateJson()}';
      final projected = AdventureResponse.llmHistoryProjection(content);

      expect(projected, contains('你推开木门'));
      expect(projected, isNot(contains('custom_status')));
      expect(projected, isNot(contains('custom_status_changes')));
      expect(projected, isNot(contains('"scene"')));
      expect(projected, isNot(contains('"options"')));
      expect(projected, isNot(contains('状态0_0')));
      expect(projected, isNot(contains('{')));
      expect(projected, isNot(contains('[')));
    });

    test(
        'persisted message keeps the full state; only the projection strips it',
        () {
      final content = '你推开木门，屋内一片漆黑。\n---JSON---\n'
          '${_buildSixteenStateJson()}';
      // 持久化消息仍保留完整快照，供 UI 展示与 Adventure 恢复。
      final parsed = AdventureResponse.tryParseSplit(content);
      expect(parsed, isNotNull);
      expect(parsed!.customStatus, hasLength(16));
      // 但发给 LLM 的历史投影绝不携带它。
      expect(AdventureResponse.llmHistoryProjection(content),
          isNot(contains('custom_status')));
    });

    test('10-round history never re-carries the full snapshot', () {
      final fullState = _buildSixteenStateJson();
      final history = StringBuffer();
      for (var round = 0; round < 10; round++) {
        final content = '第 $round 轮叙事正文，剧情持续推进。\n---JSON---\n$fullState';
        history.writeln(AdventureResponse.llmHistoryProjection(content));
      }
      final projected = history.toString();
      expect(projected, isNot(contains('custom_status')));
      expect(projected, isNot(contains('状态0_0')));
      // 历史只保留正文，长度保持有界，不会随轮数恢复膨胀到 2000~3000 字符。
      expect(projected.length, lessThan(600));
    });

    test('payload-only and malformed responses project to empty', () {
      expect(
        AdventureResponse.llmHistoryProjection(
            '{"scene":"x","options":["a","b","c"]}'),
        isEmpty,
      );
      expect(
        AdventureResponse.llmHistoryProjection('{"scene":"x","options":["a"'),
        isEmpty,
      );
    });

    test('plain narrative passes through unchanged', () {
      expect(AdventureResponse.llmHistoryProjection('纯叙事正文。'), '纯叙事正文。');
    });
  });

  group('Separator variants are unified (no JSON leak)', () {
    const payload = '{"scene":"大厅","options":["走","停"],'
        '"custom_status_changes":[{"character_id":"c","attribute_id":"a",'
        '"operation":"set","value":30}]}';

    for (final separator in ['---JSON---', '--- JSON ---', '---\nJSON---']) {
      test('$separator is parsed without leaking into narrative', () {
        final raw = '你踏入大厅。\n$separator\n$payload';
        final parsed = AdventureResponse.parse(raw);
        expect(parsed.kind, AdventureResponseKind.narrativeWithPayload);
        expect(parsed.narrative.join(), '你踏入大厅。');
        expect(parsed.narrative.join(), isNot(contains('"')));

        final canonical = AdventureResponse.canonicalize(raw);
        final marker = canonical.indexOf('---JSON---');
        expect(marker, greaterThan(0));
        // 正文部分绝不携带 JSON；payload 部分正常保留。
        expect(canonical.substring(0, marker), isNot(contains('"options"')));
        expect(canonical.substring(0, marker), contains('你踏入大厅。'));
        // Canonical form always uses the exact separator.
        expect(canonical, contains('---JSON---'));
      });
    }

    test('pure JSON never becomes narrative', () {
      expect(AdventureResponse.parse(payload).kind,
          AdventureResponseKind.payloadOnly);
      expect(AdventureResponse.streamingDisplayText(payload), isEmpty);
    });

    test('malformed JSON tail never leaks into narrative', () {
      const raw = '你走进大厅。\n---JSON---\n{"scene":"大厅","options":["走"';
      expect(AdventureResponse.canonicalize(raw), '你走进大厅。');
      expect(AdventureResponse.parse(raw).narrative.join(), '你走进大厅。');
    });
  });

  group('Multi-stage length stability', () {
    test('L5 budget converges to target, never to hard maximum', () {
      const target = 6500;
      const hardMax = 10000;
      const maxStages = 4;
      var current = 0;
      final stageTargets = <int>[];
      for (var stage = 1; stage <= maxStages; stage++) {
        final plan = SceneDialogueOutputBudget.planStage(
          stage: stage,
          currentChars: current,
          targetChars: target,
          hardMaximum: hardMax,
          maxStages: maxStages,
        );
        if (plan.isFinal && plan.charTarget == 0) break;
        stageTargets.add(plan.charTarget);
        current += plan.charTarget;
        if (plan.isFinal) break;
      }
      expect(stageTargets.fold(0, (a, b) => a + b), target);
    });

    test('five simulated L5 rounds stay bounded around target', () {
      const target = 6500;
      const hardMax = 10000;
      const maxStages = 4;
      final totals = <int>[];
      for (var round = 0; round < 5; round++) {
        var current = 0;
        for (var stage = 1; stage <= maxStages; stage++) {
          final plan = SceneDialogueOutputBudget.planStage(
            stage: stage,
            currentChars: current,
            targetChars: target,
            hardMaximum: hardMax,
            maxStages: maxStages,
          );
          if (plan.isFinal && plan.charTarget == 0) break;
          // 模型每幕多写 20% 模拟真实漂移，预算必须把它拉回上限以内。
          current += (plan.charTarget * 1.2).ceil();
          if (plan.isFinal) break;
        }
        totals.add(current);
        expect(current, lessThanOrEqualTo(hardMax));
      }
      // 不得出现逐轮持续膨胀到 hardMax 的趋势。
      for (final total in totals) {
        expect(total, lessThanOrEqualTo(target + 1000));
      }
    });
  });

  group('LengthGuard hard maximum', () {
    const guard = NarrativeLengthGuard();

    test('converges overflow at a sentence boundary, never mid-sentence', () {
      final narrative = '第一句完整结束。' * 500;
      final converged = guard.convergeToMaximum(narrative, 120);
      expect(guard.countChinese(converged), lessThanOrEqualTo(120));
      expect(converged, endsWith('。'));
    });

    test('does not truncate a narrative already within the cap', () {
      const narrative = '短句一。短句二。短句三。';
      expect(guard.convergeToMaximum(narrative, 100), narrative);
    });

    test('verdict classifies underflow / within range / overflow', () {
      NarrativeLengthGuardResult make(int chars) => NarrativeLengthGuardResult(
            content: '',
            initialChineseChars: chars,
            supplementChineseChars: 0,
            finalChineseChars: chars,
            supplementAttempted: false,
            supplementSucceeded: false,
          );
      expect(make(100).verdict(200, 300), NarrativeLengthVerdict.underflow);
      expect(make(250).verdict(200, 300), NarrativeLengthVerdict.withinRange);
      expect(make(350).verdict(200, 300), NarrativeLengthVerdict.overflow);
    });
  });
}
