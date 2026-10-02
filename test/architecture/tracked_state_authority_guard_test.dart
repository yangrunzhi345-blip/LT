import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guard for the unified tracked-state authority.
///
/// The whole point of the rework is that detection has **one** authority:
/// `AdventureTrackedStateRegistry` + `TrackedStateCandidatePlanner`. This guard
/// fails the build if the old protagonist-first / full-sweep path is
/// reintroduced, or if a resource gains a place to store a current value.
void main() {
  group('Tracked state authority guard', () {
    test('settlement reads the registry and the fair planner', () {
      final engine = File('lib/engines/chat_engine.dart').readAsStringSync();
      expect(engine, contains('AdventureTrackedStateRegistry'));
      expect(engine, contains('TrackedStateCandidatePlanner'));
      expect(engine, contains('_settlementCandidates'));
      // The old protagonist-first, then take(N) path must not come back.
      expect(engine, isNot(contains('_trackedSettlementStatuses')));
    });

    test('validator resolves custom attributes through the registry', () {
      final validator =
          File('lib/services/runtime_state_validator.dart').readAsStringSync();
      expect(validator, contains('AdventureTrackedStateRegistry'));
      // The character-only helper that rejected NPC/world is gone.
      expect(validator, isNot(contains('_attributesForEntity')));
      // Selected-only companions must be recognised via the roster identities.
      expect(validator, contains('AdventureCharacterIdentity'));
    });

    test('settlement prompt is sparse and drops the changed=false flood', () {
      final prompt = File(
        'lib/engines/chat_engine_internals/turn_settlement_prompt.dart',
      ).readAsStringSync();
      expect(prompt, contains('稀疏检测规则'));
      expect(prompt, isNot(contains('custom_status_evaluations')));
      expect(prompt, isNot(contains('changed=false')));
    });

    test('narrative prompt no longer demands a per-status sweep', () {
      final config = File('lib/config/app_config.dart').readAsStringSync();
      expect(config, contains('检测结算规则（稀疏'));
      expect(config, isNot(contains('custom_status_evaluations')));
      expect(config, isNot(contains('changed=false')));
    });

    test('resources declare definitions but never a current value', () {
      for (final path in const [
        'lib/models/character_card.dart',
        'lib/models/supporting_character.dart',
        'lib/models/worldview_details.dart',
      ]) {
        final source = File(path).readAsStringSync();
        expect(source, contains('tracked_state_definitions'),
            reason: '$path must persist tracked_state_definitions');
        expect(source, contains('TrackedStateDefinition'),
            reason: '$path must reuse the single definition model');
      }
      // The definition field set has no place for a current value.
      final definition =
          File('lib/models/tracked_state_definition.dart').readAsStringSync();
      expect(definition, contains('bannedCurrentStateKeys'));
      expect(
        RegExp(r'final\s+num\??\s+currentValue|final\s+Object\??\s+value\s*;')
            .hasMatch(definition),
        isFalse,
        reason: 'TrackedStateDefinition must not own a current value field',
      );
    });

    test('adventure config carries the frozen definition authority', () {
      final config =
          File('lib/models/adventure_config.dart').readAsStringSync();
      expect(config, contains('trackedStateDefinitions'));
      final provider =
          File('lib/providers/adventure_provider.dart').readAsStringSync();
      expect(provider, contains('AdventureTrackedStateFreezer'));
    });

    test('the real adventure start flow runs the opening bootstrap', () {
      final chat = File('lib/providers/chat_provider.dart').readAsStringSync();
      // Not dead code: the start flow instantiates and awaits the runner.
      expect(chat, contains('TrackedStateBootstrapRunner'));
      expect(chat, contains('_runOpeningTrackedStateBootstrap'));
      expect(chat, contains('refreshRuntimeEntities'));
      final runner = File(
        'lib/application/adventure/tracked_state_bootstrap_runner.dart',
      ).readAsStringSync();
      expect(runner, contains('TrackedStateBootstrap'));
      expect(runner, contains('commitRuntimeMutation'));
      // The bootstrap is idempotent, never time-based.
      expect(runner, contains('tracked-state-bootstrap:'));
      expect(runner, isNot(contains('DateTime.now')));
    });

    test('AdventureProvider never gains an LLM transport dependency', () {
      final provider =
          File('lib/providers/adventure_provider.dart').readAsStringSync();
      expect(provider, isNot(contains('llm_service.dart')));
      expect(provider, isNot(contains('LLMService')));
    });
  });
}
