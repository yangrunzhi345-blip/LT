import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/features/adventure/presentation/state/tracked_state_presentation.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations_zh.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/models/adventure_runtime_state.dart';
import 'package:lt_dialogue/models/adventure_tracked_state.dart';
import 'package:lt_dialogue/models/supporting_character.dart';
import 'package:lt_dialogue/models/tracked_state_definition.dart';
import 'package:lt_dialogue/models/typed_runtime_state.dart';

/// The shared read-only projection is the single place that decides
/// "definition exists but has no runtime value → untriggered" and formats every
/// value. The HUD / Inspector / overview panel / hub all read it, so these
/// unit tests pin the semantics those surfaces depend on.
void main() {
  final l10n = AppLocalizationsZh();

  const curse = TrackedStateDefinition(
    id: 'curse_corruption',
    name: '精神污染',
    valueKind: RuntimeStateValueKind.integer,
    minimum: 0,
    maximum: 100,
  );
  const trust = TrackedStateDefinition(
    id: 'trust',
    name: '信任度',
    valueKind: RuntimeStateValueKind.integer,
  );
  const wounded = TrackedStateDefinition(
    id: 'wounded',
    name: '受伤状态',
    valueKind: RuntimeStateValueKind.boolean,
  );
  const stance = TrackedStateDefinition(
    id: 'war_stance',
    name: '战争立场',
    valueKind: RuntimeStateValueKind.enumValue,
    enumValues: {'和平', '中立', '敌对'},
  );
  const fear = TrackedStateDefinition(
    id: 'fear',
    name: '恐惧',
    valueKind: RuntimeStateValueKind.integer,
    minimum: 0,
    maximum: 100,
  );
  const legacyName = TrackedStateDefinition(
    id: 'curse',
    name: '诅咒侵蚀',
    valueKind: RuntimeStateValueKind.text,
  );

  AdventureConfig buildConfig() => AdventureConfig(
        name: '李维',
        selectedCharacters: [
          AdventureSelectedCharacter(
            id: 'lc',
            characterId: 'lc',
            characterName: '林澈',
            isProtagonist: true,
          ),
          AdventureSelectedCharacter(
            id: 'alice',
            characterId: 'alice',
            characterName: 'Alice',
          ),
          AdventureSelectedCharacter(
            id: 'bob',
            characterId: 'bob',
            characterName: 'Bob',
          ),
          // Selected-only companion: present in the roster but never in the
          // legacy supportingCharacters list.
          AdventureSelectedCharacter(
            id: 'carol',
            characterId: 'carol',
            characterName: 'Carol',
          ),
        ],
        supportingCharacters: [
          SupportingCharacter(id: 'alice', name: 'Alice'),
          SupportingCharacter(id: 'bob', name: 'Bob'),
        ],
        trackedStateDefinitions: const [
          AdventureTrackedStateDefinition(
            entityType: RuntimeEntityType.character,
            entityId: 'lc',
            definition: curse,
          ),
          AdventureTrackedStateDefinition(
            entityType: RuntimeEntityType.character,
            entityId: 'lc',
            definition: trust,
          ),
          AdventureTrackedStateDefinition(
            entityType: RuntimeEntityType.character,
            entityId: 'lc',
            definition: wounded,
          ),
          AdventureTrackedStateDefinition(
            entityType: RuntimeEntityType.character,
            entityId: 'lc',
            definition: stance,
          ),
          AdventureTrackedStateDefinition(
            entityType: RuntimeEntityType.character,
            entityId: 'alice',
            definition: fear,
          ),
          AdventureTrackedStateDefinition(
            entityType: RuntimeEntityType.character,
            entityId: 'bob',
            definition: fear,
          ),
          AdventureTrackedStateDefinition(
            entityType: RuntimeEntityType.character,
            entityId: 'carol',
            definition: fear,
          ),
          AdventureTrackedStateDefinition(
            entityType: RuntimeEntityType.character,
            entityId: 'lc',
            definition: legacyName,
          ),
        ],
      );

  group('definition exists without a runtime value (Case A)', () {
    test('untriggered definition still projects, never a fabricated zero', () {
      final config = buildConfig();
      final summaries = TrackedStatePresentation.summaries(
        config: config,
        entities: const [],
        entityType: RuntimeEntityType.character,
        entityId: 'lc',
      );

      final curseSummary = summaries.firstWhere((s) => s.name == '精神污染');
      expect(curseSummary.value, isNull);
      expect(curseSummary.isTriggered, isFalse);
      expect(
        TrackedStatePresentation.valueText(
            curseSummary.definition, curseSummary.value, l10n),
        l10n.trackedStateUntriggered,
      );
    });
  });

  group('value formatting', () {
    test('integer with maximum renders value / maximum (Case B)', () {
      final summaries = TrackedStatePresentation.summaries(
        config: buildConfig(),
        entities: [
          RuntimeEntityState(
            entityType: RuntimeEntityType.character,
            entityId: 'lc',
            overlay: const {'custom_attributes.curse_corruption': 37},
          ),
        ],
        entityType: RuntimeEntityType.character,
        entityId: 'lc',
      );
      final curseSummary = summaries.firstWhere((s) => s.name == '精神污染');
      expect(
        TrackedStatePresentation.valueText(
            curseSummary.definition, curseSummary.value, l10n),
        '37 / 100',
      );
    });

    test('integer without maximum renders bare value', () {
      const definition = trust;
      expect(TrackedStatePresentation.valueText(definition, 12, l10n), '12');
    });

    test('boolean renders localized yes / no (Case C)', () {
      final summaries = TrackedStatePresentation.summaries(
        config: buildConfig(),
        entities: [
          RuntimeEntityState(
            entityType: RuntimeEntityType.character,
            entityId: 'lc',
            overlay: const {'custom_attributes.wounded': true},
          ),
        ],
        entityType: RuntimeEntityType.character,
        entityId: 'lc',
      );
      final wound = summaries.firstWhere((s) => s.name == '受伤状态');
      expect(wound.isTriggered, isTrue);
      expect(
        TrackedStatePresentation.valueText(wound.definition, wound.value, l10n),
        l10n.trackedStateBoolYes,
      );

      // A triggered boolean false is still triggered, not "untriggered".
      expect(
        TrackedStatePresentation.valueText(wounded, false, l10n),
        l10n.trackedStateBoolNo,
      );
    });

    test('enum renders the user-defined value verbatim (Case D)', () {
      expect(TrackedStatePresentation.valueText(stance, '敌对', l10n), '敌对');
    });

    test('text renders the stored string', () {
      expect(
          TrackedStatePresentation.valueText(legacyName, '侵蚀加深', l10n), '侵蚀加深');
    });
  });

  group('adventure without definitions (Case E)', () {
    test('hasAnyDefinition is false and summaries are empty', () {
      final config = AdventureConfig(name: '空冒险');
      expect(TrackedStatePresentation.hasAnyDefinition(config), isFalse);
      expect(
        TrackedStatePresentation.summaries(
          config: config,
          entities: const [],
          entityType: RuntimeEntityType.character,
          entityId: 'lc',
        ),
        isEmpty,
      );
    });
  });

  group('multi-character identity (Case F)', () {
    test('same definition id on two entities resolves by stable id only', () {
      final entities = [
        RuntimeEntityState(
          entityType: RuntimeEntityType.character,
          entityId: 'alice',
          overlay: const {'custom_attributes.fear': 20},
        ),
        RuntimeEntityState(
          entityType: RuntimeEntityType.character,
          entityId: 'bob',
          overlay: const {'custom_attributes.fear': 80},
        ),
      ];
      final config = buildConfig();

      final alice = TrackedStatePresentation.resolveSelectedCharacter(
        config: config,
        selectedCharacterIndex: 0,
      );
      final bob = TrackedStatePresentation.resolveSelectedCharacter(
        config: config,
        selectedCharacterIndex: 1,
      );
      expect(alice.entityId, 'alice');
      expect(bob.entityId, 'bob');

      final aliceFear = TrackedStatePresentation.summaries(
        config: config,
        entities: entities,
        entityType: alice.entityType,
        entityId: alice.entityId,
      ).single;
      final bobFear = TrackedStatePresentation.summaries(
        config: config,
        entities: entities,
        entityType: bob.entityType,
        entityId: bob.entityId,
      ).single;

      expect(
        TrackedStatePresentation.valueText(
            aliceFear.definition, aliceFear.value, l10n),
        '20 / 100',
      );
      expect(
        TrackedStatePresentation.valueText(
            bobFear.definition, bobFear.value, l10n),
        '80 / 100',
      );
    });

    test('out-of-range selection falls back to the protagonist', () {
      final ref = TrackedStatePresentation.resolveSelectedCharacter(
        config: buildConfig(),
        selectedCharacterIndex: 99,
      );
      expect(ref.isProtagonist, isTrue);
      expect(ref.entityId, 'lc');
      expect(ref.name, '林澈');
    });
  });

  group('selected-only companion (Case G)', () {
    test('a roster character outside supportingCharacters still projects', () {
      final summaries = TrackedStatePresentation.summaries(
        config: buildConfig(),
        entities: [
          RuntimeEntityState(
            entityType: RuntimeEntityType.character,
            entityId: 'carol',
            overlay: const {'custom_attributes.fear': 55},
          ),
        ],
        entityType: RuntimeEntityType.character,
        entityId: 'carol',
      );
      expect(summaries, hasLength(1));
      expect(
        TrackedStatePresentation.valueText(
            summaries.single.definition, summaries.single.value, l10n),
        '55 / 100',
      );
    });
  });

  group('null is not zero and is not hidden', () {
    test('rawValue returns null when the overlay path is absent', () {
      expect(
        TrackedStatePresentation.rawValue(curse, const {}),
        isNull,
      );
      expect(
        TrackedStatePresentation.rawValue(
            curse, const {'custom_attributes.curse_corruption': 0}),
        0,
      );
    });
  });
}
