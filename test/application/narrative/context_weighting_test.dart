import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/narrative/context_weighting.dart';
import 'package:lt_dialogue/utils/token_estimator.dart';
import 'package:lt_dialogue/services/context_weight_profile_store.dart';
import 'package:lt_dialogue/services/repositories/settings_repository.dart';

class _MemorySettings implements ISettingsRepository {
  final values = <String, String>{};
  @override
  Future<void> setSetting(String key, String value) async =>
      values[key] = value;
  @override
  Future<String?> getSetting(String key) async => values[key];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('profile clamps values and ignores unknown ids', () {
    final profile = ContextWeightProfile.fromJson({
      'preset_id': 'custom',
      'weights': {'userControl': 150, 'unknown': 100, 'worldview': -4},
    });
    expect(profile[ContextSourceId.userControl], 100);
    expect(profile[ContextSourceId.worldview], 0);
    expect(profile.toJson()['schema_version'], 1);
  });

  test('planner is deterministic, capped, and keeps mandatory input', () {
    const planner = WeightedContextPlanner();
    final candidates = [
      const ContextCandidate(
        source: ContextSourceId.userControl,
        content: '当前用户必须保留的输入',
        policy: ContextSourcePolicy(
          priority: ContextSourcePriority.mandatory,
          minimumTokens: 0,
          maximumTokens: 32,
        ),
      ),
      const ContextCandidate(
        source: ContextSourceId.worldview,
        content: '世界背景 ' '世界背景 ' '世界背景 ' '世界背景 ' '世界背景 ',
        policy: ContextSourcePolicy(
          priority: ContextSourcePriority.core,
          minimumTokens: 0,
          maximumTokens: 10,
        ),
      ),
    ];
    final first = planner.plan(
      inputLimitTokens: 12,
      profile: ContextWeightPresets.balanced,
      candidates: candidates,
    );
    final second = planner.plan(
      inputLimitTokens: 12,
      profile: ContextWeightPresets.balanced,
      candidates: candidates,
    );
    expect(first.toDiagnostics(), second.toDiagnostics());
    expect(first.usedTokens, lessThanOrEqualTo(12));
    expect(first.allocations.first.decision, 'mandatory');
    expect(
        TokenEstimator(first.allocations.first.content).tokens, greaterThan(0));
  });

  test('presets produce distinct serialized profiles', () {
    expect(ContextWeightPresets.balanced.encode(),
        isNot(ContextWeightPresets.highControl.encode()));
    expect(ContextWeightPresets.highControl.encode(),
        isNot(ContextWeightPresets.immersive.encode()));
    final custom = ContextWeightPresets.balanced.copyWith(
      presetId: 'custom',
      weights: {
        ...ContextWeightPresets.balanced.weights,
        ContextSourceId.worldview: 0
      },
    );
    expect(custom.presetId, 'custom');
    expect(custom[ContextSourceId.worldview], 0);
  });

  test('profile store persists and restores versioned weights', () async {
    final repository = _MemorySettings();
    final store = ContextWeightProfileStore(repository);
    final profile = ContextWeightPresets.highControl.copyWith(
      presetId: 'custom',
      weights: {
        ...ContextWeightPresets.highControl.weights,
        ContextSourceId.worldview: 3
      },
    );
    await store.save(profile);
    final restored = await store.load();
    expect(restored.presetId, 'custom');
    expect(restored[ContextSourceId.worldview], 3);
    expect(repository.values[ContextWeightProfileStore.settingKey],
        contains('schema_version'));
  });
}
