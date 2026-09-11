// Phase 0 Dart baseline benchmark for the Rust-core migration audit.
//
// This file is intentionally NOT under `test/` so it never runs as part of the
// normal `flutter test` suite. Run it explicitly with:
//
//   flutter test benchmark/core_benchmark.dart
//
// It measures only the Dart baseline. Rust pure-execution and Dart↔Rust
// round-trip numbers are added in later phases once the FFI bridge exists.

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:lt_dialogue/application/narrative/narrative_context.dart';
import 'package:lt_dialogue/engines/chat_engine_internals/response_length_guard.dart';
import 'package:lt_dialogue/models/adventure_runtime_state.dart';
import 'package:lt_dialogue/models/custom_attribute_item.dart';
import 'package:lt_dialogue/models/custom_status_change.dart';
import 'package:lt_dialogue/models/supporting_character.dart';
import 'package:lt_dialogue/models/world_entry.dart';
import 'package:lt_dialogue/services/custom_status_merger.dart';
import 'package:lt_dialogue/services/runtime_state_validator.dart';
import 'package:lt_dialogue/utils/token_estimator.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Timing helper
// ─────────────────────────────────────────────────────────────────────────────

/// Runs [fn] once for warmup, then [iterations] times, returning the median
/// duration in milliseconds.
double _measureMs(void Function() fn, {int iterations = 7}) {
  fn(); // warmup (JIT)
  final samples = <double>[];
  for (var i = 0; i < iterations; i++) {
    final sw = Stopwatch()..start();
    fn();
    sw.stop();
    samples.add(sw.elapsedMicroseconds / 1000.0);
  }
  samples.sort();
  return samples[iterations ~/ 2];
}

/// Best-effort resident-set delta in MB around a single [fn] execution.
/// Dart has no precise per-allocation counter; RSS is noisy but indicative.
double _rssMb() => ProcessInfo.currentRss / (1024 * 1024);

// ─────────────────────────────────────────────────────────────────────────────
// Synthetic data generation (deterministic)
// ─────────────────────────────────────────────────────────────────────────────

final math.Random _rng = math.Random(42);

String _chineseSentence() {
  const pool = '天地玄黄宇宙洪荒日月盈昃辰宿列张寒来暑往秋收冬藏';
  final buf = StringBuffer();
  final len = 12 + _rng.nextInt(40);
  for (var i = 0; i < len; i++) {
    buf.write(pool[_rng.nextInt(pool.length)]);
  }
  return buf.toString();
}

String _mixedSentence() {
  final buf = StringBuffer();
  final words = ['north', 'temple', 'river', 'sword', 'mage', 'empire'];
  buf.write(words[_rng.nextInt(words.length)]);
  buf.write(' ${_chineseSentence()}');
  buf.write(' ${_rng.nextInt(10000)}');
  return buf.toString();
}

/// Generates a realistic-ish worldview entry mix: constraints, facts, lore.
List<WorldEntry> _generateWorldEntries(int count) {
  final entries = <WorldEntry>[];
  for (var i = 0; i < count; i++) {
    final kind = i % 3; // 0=constraint, 1=fact, 2=lore
    final content = switch (kind) {
      0 => '【世界观/世界规则】${_mixedSentence()}',
      1 => '【世界观/当前世界状态】${_mixedSentence()}',
      _ => '【世界观/背景】${_mixedSentence()}',
    };
    final keys = <String>[
      'kw$i',
      if (i % 5 == 0) 'protagonist',
      if (i % 7 == 0) 'location',
    ];
    entries.add(WorldEntry(
      id: i,
      adventureId: 1,
      keys: keys,
      content: content,
      insertionOrder: i % 100,
      sticky: kind == 0 ? 1 : 0,
      enabled: i % 11 != 0,
      sourceType: switch (kind) {
        0 => 'rule',
        1 => 'location',
        _ => 'world_entry',
      },
    ));
  }
  return entries;
}

List<RuntimeEntityState> _generateRuntimeEntities(int count) {
  return List.generate(count, (i) {
    return RuntimeEntityState(
      entityType: RuntimeEntityType.values[i % RuntimeEntityType.values.length],
      entityId: 'entity-$i',
      overlay: {
        'affinity': _rng.nextInt(100),
        'life_status': i % 3 == 0 ? 'dead' : 'alive',
        'relationship': 'ally-$i',
      },
      lifecycleStatus: i % 5 == 0 ? 'inactive' : 'active',
    );
  });
}

List<RuntimeStateChangeProposal> _generateProposals(int count) {
  const paths = [
    'life_status',
    'lifecycle_status',
    'affinity',
    'relationship',
    'faction_id',
    'former_faction_id',
    'goal',
    'controller_id',
    'status',
  ];
  return List.generate(count, (i) {
    final path = paths[i % paths.length];
    return RuntimeStateChangeProposal(
      entityType: RuntimeEntityType.character,
      entityId: 'entity-$i',
      changeKind:
          i % 2 == 0 ? RuntimeChangeKind.primary : RuntimeChangeKind.derived,
      operation: path == 'affinity'
          ? RuntimeChangeOperation.increment
          : RuntimeChangeOperation.set,
      path: path,
      value: path == 'affinity' ? _rng.nextInt(10) : 'value-$i',
      reason: 'reason-$i',
    );
  });
}

List<CustomAttributeItem> _generateAttributes(int count) {
  return List.generate(count, (i) {
    return CustomAttributeItem(
      id: 'attr-$i',
      name: '状态$i',
      value: i % 3 == 0 ? '${_rng.nextInt(100)}/100' : '文本$i',
      currentValue: i % 3 == 0 ? _rng.nextInt(100) : null,
      maxValue: i % 3 == 0 ? 100 : null,
    );
  });
}

List<CustomStatusChange> _generateChanges(int count) {
  return List.generate(count, (i) {
    return CustomStatusChange(
      characterId: i % 4 == 0 ? 'protagonist' : 'npc-${i % 10}',
      attributeId: 'attr-${i % 20}',
      operation: i % 2 == 0
          ? CustomStatusChangeOperation.set
          : CustomStatusChangeOperation.delta,
      value: i % 2 == 0 ? '新值$i' : _rng.nextInt(10),
    );
  });
}

/// Shape A: one long paragraph of short, high-frequency sentences.
///
/// Each repeated chunk contributes exactly 15 Chinese characters, so
/// [targetChinese] maps deterministically to a repeat count.
String _shortSentenceNarrative(int targetChinese) {
  const chunk = '第一句结束。第二句继续。第三句收尾。';
  final buf = StringBuffer();
  final chunks = (targetChinese / 15).ceil();
  for (var i = 0; i < chunks; i++) {
    buf.write(chunk);
  }
  return buf.toString();
}

/// Shape B: several multi-sentence paragraphs separated by blank lines.
///
/// Each paragraph holds four sentences of 12 Chinese characters.
String _multiParagraphNarrative(int targetChinese) {
  const sentence = '这一段描述场景与人物动作。';
  final buf = StringBuffer();
  var chinese = 0;
  var paragraph = 0;
  while (chinese < targetChinese) {
    if (paragraph > 0) buf.write('\n\n');
    for (var s = 0; s < 4; s++) {
      buf.write(sentence);
      chinese += 12;
    }
    paragraph++;
  }
  return buf.toString();
}

/// Shape C: close to real Adventure prose — Chinese, English names, digits,
/// punctuation and dialogue newlines. Each chunk holds 29 Chinese characters.
String _realisticAdventureNarrative(int targetChinese) {
  final buf = StringBuffer();
  final chunks = (targetChinese / 29).ceil();
  for (var i = 0; i < chunks; i++) {
    buf.write('艾莉丝望向北境的 temple，低声道：“再走 three 里就到了。” '
        '第 ${i + 1} 次交手，火光映着她的长剑。\n');
  }
  return buf.toString();
}

// ─────────────────────────────────────────────────────────────────────────────
// Benchmarks
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  test('Dart core baseline benchmark', () {
    final out = StringBuffer();

    // ── Token estimate: single large batch ─────────────────────────────────
    out.writeln('## TokenEstimate (batch of N strings, ~150 chars each)');
    out.writeln('| N | Dart ms (median) |');
    out.writeln('|---|-------------------|');
    for (final n in [100, 1000, 10000, 50000]) {
      final texts = List.generate(n, (_) => _mixedSentence());
      var sink = 0;
      final ms = _measureMs(() {
        var total = 0;
        for (final t in texts) {
          total += TokenEstimator(t).tokens;
        }
        sink = total;
      });
      expect(sink, greaterThan(0));
      out.writeln('| $n | ${ms.toStringAsFixed(3)} |');
    }

    // ── WorldContextBuilder: full context build ────────────────────────────
    out.writeln();
    out.writeln(
        '## WorldContextBuilder.build (normalize+dedup+match+score+rank+budget)');
    out.writeln('| N | Dart ms (median) |');
    out.writeln('|---|-------------------|');
    for (final n in [100, 1000, 10000, 50000]) {
      final entries = _generateWorldEntries(n);
      final names = ['主角', 'protagonist', 'river', 'temple'];
      const builder = WorldContextBuilder();
      final ms = _measureMs(() {
        builder.build(
          entries: entries,
          query: '主角 前往 temple 查看 river',
          location: 'location',
          characterNames: names,
          tokenBudget: 4096,
        );
      });
      out.writeln('| $n | ${ms.toStringAsFixed(3)} |');
    }

    // ── RuntimeMemoryProjector ─────────────────────────────────────────────
    out.writeln();
    out.writeln('## RuntimeMemoryProjector.project');
    out.writeln('| entities | Dart ms (median) |');
    out.writeln('|---|-------------------|');
    for (final n in [16, 100, 1000, 10000]) {
      final entities = _generateRuntimeEntities(n);
      final relevant = {'entity-0', 'entity-1', 'entity-5', 'entity-9'};
      const projector = RuntimeMemoryProjector();
      final ms = _measureMs(() {
        projector.project(
          revision: 3,
          entities: entities,
          relevantEntityIds: relevant,
        );
      });
      out.writeln('| $n | ${ms.toStringAsFixed(3)} |');
    }

    // ── RuntimeStateValidator ──────────────────────────────────────────────
    out.writeln();
    out.writeln('## RuntimeStateValidator.accept');
    out.writeln('| proposals | Dart ms (median) |');
    out.writeln('|---|-------------------|');
    for (final n in [16, 100, 1000, 10000]) {
      final proposals = _generateProposals(n);
      const validator = RuntimeStateValidator();
      final ms = _measureMs(() {
        validator.accept(proposals);
      });
      out.writeln('| $n | ${ms.toStringAsFixed(3)} |');
    }

    // ── CustomStatusMerger ─────────────────────────────────────────────────
    out.writeln();
    out.writeln('## CustomStatusMerger.applyChanges');
    out.writeln('| attributes | changes | Dart ms (median) |');
    out.writeln('|---|--|-------------------|');
    for (final n in [16, 100, 1000]) {
      final attrs = _generateAttributes(n);
      final sc = SupportingCharacter(
        id: 'npc-1',
        name: '同伴甲',
        customAttributes: attrs,
      );
      final changes = _generateChanges(math.min(n, 64));
      final ms = _measureMs(() {
        CustomStatusMerger.applyChanges(
          protagonistName: '主角',
          protagonistId: 'protagonist',
          protagonistAttributes: attrs,
          supportingCharacters: [sc],
          changes: changes,
        );
      });
      out.writeln('| $n | ${math.min(n, 64)} | ${ms.toStringAsFixed(3)} |');
    }

    // ── NarrativeLengthGuard ───────────────────────────────────────────────
    // The overflow convergence path is the algorithmically interesting one: it
    // used to re-scan the growing candidate on every paragraph/sentence, which
    // made it near-quadratic in the response length.
    const guard = NarrativeLengthGuard();
    const guardSizes = [1000, 3000, 10000, 30000, 100000];
    const guardIterations = 5;
    final shapeA = <int, String>{};
    final shapeB = <int, String>{};
    final shapeC = <int, String>{};
    for (final n in guardSizes) {
      shapeA[n] = _shortSentenceNarrative(n);
      shapeB[n] = _multiParagraphNarrative(n);
      shapeC[n] = _realisticAdventureNarrative(n);
    }

    out.writeln();
    out.writeln('## NarrativeLengthGuard.countChinese');
    out.writeln('| target chinese chars | Dart ms (median) |');
    out.writeln('|---|-------------------|');
    for (final n in guardSizes) {
      final text = shapeA[n]!;
      final ms = _measureMs(() {
        guard.countChinese(text);
      }, iterations: guardIterations);
      out.writeln('| $n | ${ms.toStringAsFixed(3)} |');
    }

    out.writeln();
    out.writeln('## NarrativeLengthGuard.convergeToMaximum (within-cap)');
    out.writeln('| target chinese chars | Dart ms (median) |');
    out.writeln('|---|-------------------|');
    for (final n in guardSizes) {
      final text = shapeA[n]!;
      final cap = guard.countChinese(text) + 1000;
      final ms = _measureMs(() {
        guard.convergeToMaximum(text, cap);
      }, iterations: guardIterations);
      out.writeln('| $n | ${ms.toStringAsFixed(3)} |');
    }

    out.writeln();
    out.writeln('## NarrativeLengthGuard.convergeToMaximum (overflow)');
    out.writeln('| shape | target chinese chars | Dart ms (median) |');
    out.writeln('|---|---|-------------------|');
    for (final shape in {'A': shapeA, 'B': shapeB, 'C': shapeC}.entries) {
      for (final n in guardSizes) {
        final text = shape.value[n]!;
        final cap = guard.countChinese(text) ~/ 2;
        final ms = _measureMs(() {
          guard.convergeToMaximum(text, cap);
        }, iterations: guardIterations);
        out.writeln('| ${shape.key} | $n | ${ms.toStringAsFixed(3)} |');
      }
    }

    // ── Memory (best-effort RSS delta) ─────────────────────────────────────
    out.writeln();
    out.writeln('## Memory (best-effort RSS, MB)');
    final before = _rssMb();
    final bigEntries = _generateWorldEntries(50000);
    final bigTexts = List.generate(50000, (_) => _mixedSentence());
    final after = _rssMb();
    expect(bigEntries.length + bigTexts.length, greaterThan(0));
    out.writeln('50K entries + 50K texts delta: '
        '${(after - before).toStringAsFixed(1)} MB (process RSS, noisy)');

    // ───────────────────────────────────────────────────────────────────────
    // ignore: avoid_print
    print('\n===== DART BASELINE BENCHMARK =====\n$out');
  });
}
