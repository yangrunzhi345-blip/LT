import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/features/adventure/presentation/state/runtime_state_presentation.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations_zh.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/models/adventure_runtime_state.dart';
import 'package:lt_dialogue/models/supporting_character.dart';
import 'package:lt_dialogue/models/turn_state_history.dart';

void main() {
  final l10n = AppLocalizationsZh();

  group('RuntimeStatePresentation Entity Labels', () {
    test('resolves known entity name and trims whitespace', () {
      expect(
        RuntimeStatePresentation.entityLabel(
          RuntimeEntityType.character,
          '  爱丽丝  ',
          l10n,
        ),
        '爱丽丝',
      );
    });

    test('falls back safely for unknown entity types', () {
      expect(
        RuntimeStatePresentation.entityLabel(
          RuntimeEntityType.character,
          null,
          l10n,
        ),
        l10n.characterStatusTitle,
      );
      expect(
        RuntimeStatePresentation.entityLabel(
          RuntimeEntityType.npc,
          '',
          l10n,
        ),
        l10n.characterStatusTitle,
      );
      expect(
        RuntimeStatePresentation.entityLabel(
          RuntimeEntityType.location,
          null,
          l10n,
        ),
        l10n.worldviewModuleState,
      );
      expect(
        RuntimeStatePresentation.entityLabel(
          RuntimeEntityType.faction,
          null,
          l10n,
        ),
        l10n.worldviewModuleState,
      );
      expect(
        RuntimeStatePresentation.entityLabel(
          RuntimeEntityType.world,
          null,
          l10n,
        ),
        l10n.worldviewModuleState,
      );
      expect(
        RuntimeStatePresentation.entityLabel(
          RuntimeEntityType.relationship,
          null,
          l10n,
        ),
        l10n.runtimeStateRelationships,
      );
    });
  });

  group('RuntimeStatePresentation Values and Diff Formatting', () {
    test('formats boolean values safely without conversion to zero', () {
      expect(
        RuntimeStatePresentation.valueLabel('global_flag', true, l10n),
        l10n.runtimeStateTrue,
      );
      expect(
        RuntimeStatePresentation.valueLabel('global_flag', false, l10n),
        l10n.runtimeStateFalse,
      );
    });

    test('preserves real numbers without loss', () {
      expect(
        RuntimeStatePresentation.valueLabel('hp', 100, l10n),
        '100',
      );
      expect(
        RuntimeStatePresentation.valueLabel('affinity', 75.5, l10n),
        '75.5',
      );
    });

    test('hides technical internal IDs as configured', () {
      expect(
        RuntimeStatePresentation.valueLabel(
            'faction_id', 'faction-uuid-1234', l10n),
        l10n.runtimeStateConfigured,
      );
      expect(
        RuntimeStatePresentation.valueLabel(
            'controller_id', 'controller-uuid-9876', l10n),
        l10n.runtimeStateConfigured,
      );
      expect(
        RuntimeStatePresentation.valueLabel('relationship', 'friend', l10n),
        l10n.runtimeStateConfigured,
      );
    });

    test('suppresses raw JSON and object dumps', () {
      expect(
        RuntimeStatePresentation.valueLabel(
            'status', {'nested': 'raw-data'}, l10n),
        l10n.runtimeStateConfigured,
      );
      expect(
        RuntimeStatePresentation.valueLabel(
            'status', '{"internal_code": 42}', l10n),
        l10n.runtimeStateConfigured,
      );
      expect(
        RuntimeStatePresentation.valueLabel('status', ['raw', 'list'], l10n),
        l10n.runtimeStateConfigured,
      );
    });

    test('formats diff cleanly', () {
      expect(
        RuntimeStatePresentation.formatDiff('hp', 100, 85, l10n),
        '100 → 85',
      );
      expect(
        RuntimeStatePresentation.formatDiff(
            'life_status', 'alive', 'dead', l10n),
        '${l10n.runtimeStateAlive} → ${l10n.runtimeStateDead}',
      );
      expect(
        RuntimeStatePresentation.formatDiff('global_flag', null, true, l10n),
        '— → ${l10n.runtimeStateTrue}',
      );
    });
  });

  group('RuntimeStatePresentation Source and Reason', () {
    test('resolves user-readable sources', () {
      expect(
        RuntimeStatePresentation.sourceLabel(
          null,
          RuntimeEventSource.userEdit,
          l10n,
        ),
        l10n.runtimeStateCauseUserEdit,
      );
      expect(
        RuntimeStatePresentation.sourceLabel(
          null,
          RuntimeEventSource.aiProposal,
          l10n,
        ),
        l10n.runtimeStateCauseDialogue,
      );
      expect(
        RuntimeStatePresentation.sourceLabel(
          null,
          RuntimeEventSource.systemRule,
          l10n,
        ),
        l10n.runtimeStateCauseSystem,
      );
      expect(
        RuntimeStatePresentation.sourceLabel(
          null,
          RuntimeEventSource.resourceImport,
          l10n,
        ),
        l10n.runtimeStateCauseImport,
      );
      expect(
        RuntimeStatePresentation.sourceLabel(
          'scene_dialogue',
          null,
          l10n,
        ),
        l10n.runtimeStateCauseDialogue,
      );
      expect(
        RuntimeStatePresentation.sourceLabel(
          'user_edit',
          null,
          l10n,
        ),
        l10n.runtimeStateCauseUserEdit,
      );
      expect(
        RuntimeStatePresentation.sourceLabel(
          'restore',
          null,
          l10n,
        ),
        l10n.runtimeStateCauseRestore,
      );
    });

    test('validates safe reason and rejects protocol leaks', () {
      expect(RuntimeStatePresentation.isSafeReason('遭遇剧毒陷阱，生命值下降'), isTrue);
      expect(RuntimeStatePresentation.isSafeReason('战斗胜利，获得经验'), isTrue);

      // Leaks to reject:
      expect(RuntimeStatePresentation.isSafeReason('entityId=character-42'),
          isFalse);
      expect(
          RuntimeStatePresentation.isSafeReason('commit_id=abcdef1234567890'),
          isFalse);
      expect(RuntimeStatePresentation.isSafeReason('revision 42'), isFalse);
      expect(RuntimeStatePresentation.isSafeReason('branch_id: 1'), isFalse);
      expect(RuntimeStatePresentation.isSafeReason('request-id: req-999'),
          isFalse);
      expect(RuntimeStatePresentation.isSafeReason('state_path: hp'), isFalse);
      expect(
          RuntimeStatePresentation.isSafeReason('res_cre_12345678'), isFalse);
      expect(
          RuntimeStatePresentation.isSafeReason('custom_attributes.detected'),
          isFalse);
      expect(RuntimeStatePresentation.isSafeReason('SELECT * FROM state'),
          isFalse);
      expect(
          RuntimeStatePresentation.isSafeReason('file:///home/yrz/db.sqlite'),
          isFalse);
      expect(RuntimeStatePresentation.isSafeReason('/home/yrz/LT/main.dart'),
          isFalse);
      expect(
          RuntimeStatePresentation.isSafeReason('Exception: database locked'),
          isFalse);
      expect(RuntimeStatePresentation.isSafeReason('StackTrace: #0 run ()'),
          isFalse);
      expect(
          RuntimeStatePresentation.isSafeReason('{"internal": true}'), isFalse);
    });
  });

  group('RuntimeStatePresentation Turn Summaries and Known Names', () {
    test('summarizes turns with and without changes', () {
      final emptyTurn = TurnStateChangeGroup(
        adventureId: 1,
        branchId: 0,
        turnId: 'turn-1',
        turnRowId: 1,
        turnNumber: 1,
        requestId: 'req-1',
        occurredAt: DateTime(2026, 9, 26, 12, 0),
        revisionStart: 1,
        revisionEnd: 1,
        changes: const [],
      );
      expect(
        RuntimeStatePresentation.turnSummary(emptyTurn, l10n),
        l10n.runtimeStateNoVisibleChanges,
      );

      final changeTurn = TurnStateChangeGroup(
        adventureId: 1,
        branchId: 0,
        turnId: 'turn-2',
        turnRowId: 2,
        turnNumber: 2,
        requestId: 'req-2',
        occurredAt: DateTime(2026, 9, 26, 12, 5),
        revisionStart: 2,
        revisionEnd: 3,
        changes: const [
          TurnStateChange(
            entityType: RuntimeEntityType.character,
            entityId: 'char-1',
            path: 'hp',
            before: 100,
            after: 80,
            reason: '遭受攻击',
            commitId: 'c1',
            revision: 2,
            causeType: 'scene_dialogue',
          ),
          TurnStateChange(
            entityType: RuntimeEntityType.character,
            entityId: 'char-1',
            path: 'mp',
            before: 50,
            after: 40,
            reason: '释放技能',
            commitId: 'c2',
            revision: 3,
            causeType: 'scene_dialogue',
          ),
        ],
      );

      final summary = RuntimeStatePresentation.turnSummary(
        changeTurn,
        l10n,
        entityNames: {'char-1': '林默'},
      );
      expect(summary, contains('林默'));
      expect(summary, contains('2 处状态变化'));

      final affected = RuntimeStatePresentation.turnAffectedEntityLabels(
        changeTurn,
        l10n,
        entityNames: {'char-1': '林默'},
      );
      expect(affected, ['林默']);
    });

    test('resolves known names from AdventureConfig and dynamic members', () {
      final config = AdventureConfig(
        worldview: 'Fantasy',
        name: '主角林默',
        gender: 'male',
        age: '20',
        protagonistClass: 'Warrior',
        protagonistBackground: 'Soldier',
        supportingCharacters: [
          SupportingCharacter(
            id: 'supp-1',
            name: '艾莲',
            relation: '队友',
            affinity: 60,
          ),
        ],
        selectedCharacters: [
          AdventureSelectedCharacter(
            id: 'sel-row-1',
            characterId: 'sel-1',
            characterName: '索菲亚',
          ),
        ],
        npcSnapshots: [
          AdventureNpcSnapshot(
            assetId: 'npc-1',
            name: '老酒保',
            npcJson: {},
          ),
        ],
      );

      final dynamicList = [
        AdventureSelectedCharacter(
          id: 'dyn-row-1',
          characterId: 'dyn-1',
          characterName: '行商',
        ),
      ];

      final names = RuntimeStatePresentation.resolveKnownNames(
        config: config,
        dynamicCharacters: dynamicList,
      );

      expect(names['supp-1'], '艾莲');
      expect(names['sel-1'], '索菲亚');
      expect(names['npc-1'], '老酒保');
      expect(names['dyn-1'], '行商');
    });
  });
}
