import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/models/dialogue_level.dart';
import 'package:lt_dialogue/models/scene_dialogue.dart';

/// ADR-0003 adventure-dialogue coverage: the user-configured elastic percent
/// only ever *widens* a level's hard maximum. The old-vs-new table below is
/// the contract required by the configuration task: 0% reproduces the legacy
/// budget bit-for-bit, the default 20% is effectively legacy (L1 +12 chars is
/// the only delta and is target-driven), and 50% widens without ever
/// narrowing a level's existing range.
void main() {
  // Legacy budgets (PR #5 era, no elasticity).
  const legacyHardMax = <String, int>{
    'L0': 150,
    'L1': 300,
    'L2': 1000,
    'L3': 2200,
    'L4': 4500,
    'L5': 10000,
  };

  // effectiveHardMax(E) = max(legacyHardMax, floor(target*(100+E)/100)).
  // Target per level: L0 100, L1 260, L2 700, L3 1600, L4 3200, L5 6500.
  const expectedHardMaxAt20 = <String, int>{
    'L0': 150, // 120 < 150
    'L1': 312, // 312 > 300 — the only legacy-visible change at 20%
    'L2': 1000, // 840 < 1000
    'L3': 2200, // 1920 < 2200
    'L4': 4500, // 3840 < 4500
    'L5': 10000, // 7800 < 10000
  };
  const expectedHardMaxAt50 = <String, int>{
    'L0': 150, // 150
    'L1': 390,
    'L2': 1050,
    'L3': 2400,
    'L4': 4800,
    'L5': 10000, // 9750 < 10000
  };

  SceneDialogueOutputBudget resolve(String id, {int? elasticPercent}) =>
      SceneDialogueOutputBudget.resolve(
        DialogueLevel.values.firstWhere((l) => l.id == id),
        elasticPercent: elasticPercent,
      );

  group('E = null and E = 0 reproduce the legacy budget', () {
    for (final id in legacyHardMax.keys) {
      test('$id unchanged', () {
        for (final e in [null, 0]) {
          final b = resolve(id, elasticPercent: e);
          expect(b.hardMaximum, legacyHardMax[id], reason: 'E=$e');
          expect(b.recommendedTokens, recommendedTokensFor(id),
              reason: 'token floor unchanged (E=$e)');
        }
      });
    }
  });

  group('E = 20 (default inherit) keeps every level within noise of legacy',
      () {
    for (final id in legacyHardMax.keys) {
      test('$id hardMaximum ${expectedHardMaxAt20[id]}', () {
        expect(resolve(id, elasticPercent: 20).hardMaximum,
            expectedHardMaxAt20[id]);
      });
    }
  });

  group('E = 50 widens low/mid levels, keeps L0/L5 caps', () {
    for (final id in legacyHardMax.keys) {
      test('$id hardMaximum ${expectedHardMaxAt50[id]}', () {
        expect(resolve(id, elasticPercent: 50).hardMaximum,
            expectedHardMaxAt50[id]);
      });
    }
  });

  group('invariants for every level and percent', () {
    for (final id in legacyHardMax.keys) {
      for (final e in const [0, 5, 20, 35, 50]) {
        test('$id E=$e never narrows and keeps min/target', () {
          final legacy = resolve(id, elasticPercent: null);
          final widened = resolve(id, elasticPercent: e);
          expect(widened.minChineseChars, legacy.minChineseChars,
              reason: 'the lower bound never moves');
          expect(widened.targetChineseChars, legacy.targetChineseChars,
              reason: 'the soft target never moves');
          expect(widened.hardMaximum, greaterThanOrEqualTo(legacy.hardMaximum),
              reason: 'elasticity may only widen');
          // The structural invariant of the dialogue budget system.
          expect(widened.hardMaximum,
              lessThanOrEqualTo(legacy.minChineseChars * 3),
              reason: 'hardMaximum <= min*3 must hold');
          // A widened contract must come with real output tokens.
          expect(widened.recommendedTokens,
              greaterThanOrEqualTo(legacy.recommendedTokens));
        });
      }
    }
  });

  test('quick mode keeps its fixed fast budget regardless of elasticity', () {
    final legacy =
        SceneDialogueOutputBudget.resolve(DialogueLevel.l0, quickMode: true);
    final widened = SceneDialogueOutputBudget.resolve(DialogueLevel.l0,
        quickMode: true, elasticPercent: 50);
    expect(widened.hardMaximum, legacy.hardMaximum);
    expect(widened.minChineseChars, legacy.minChineseChars);
  });

  test('multi-stage trigger follows the min bound, not the widened max', () {
    // L2 min = 400 < 2000: stays single-stage even at E = 50.
    expect(resolve('L2', elasticPercent: 50).usesMultiStage, isFalse);
    // L3 min = 1200... usesMultiStage is min >= 2000, so L3 stays off too.
    expect(resolve('L3', elasticPercent: 50).usesMultiStage, isFalse);
    // L4/L5 (min >= 2000) remain multi-stage.
    expect(resolve('L4', elasticPercent: 50).usesMultiStage, isTrue);
    expect(resolve('L5', elasticPercent: 50).usesMultiStage, isTrue);
  });
}

int recommendedTokensFor(String id) => switch (id) {
      'L0' => 256,
      'L1' => 512,
      'L2' => 1024,
      'L3' => 2048,
      'L4' => 4096,
      'L5' => 8192,
      _ => 1024,
    };
