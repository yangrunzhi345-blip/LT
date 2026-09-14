import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/models/adventure_runtime_state.dart';
import 'package:lt_dialogue/models/game_state.dart';
import 'package:lt_dialogue/models/message.dart';
import 'package:lt_dialogue/models/scene_dialogue.dart';
import 'package:lt_dialogue/models/scene_state.dart';
import 'package:lt_dialogue/models/supporting_character.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/repositories/adventure_repository.dart';
import 'package:lt_dialogue/services/repositories/adventure_repository_impl.dart';
import 'package:lt_dialogue/services/scene_state_proposal_validator.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  late Directory tempDir;
  late IAdventureRepository repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lt_scene_state_delta_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
    repository = AdventureRepositoryImpl(getDb: () => DatabaseService.database);
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('SceneStateChangeProposal', () {
    test('should reject invalid local changes while retaining valid changes',
        () {
      final diagnostics = <String>[];
      final proposal = SceneStateChangeProposal.parse({
        'location': '王宫',
        'characters_enter': ['boris', 'unknown'],
        'characters_leave': ['boris'],
        'goals_add': [
          {'id': 'audience', 'description': '拜见女王'},
        ],
        'goals_update': [
          {'id': 'missing', 'status': 'resolved'},
        ],
      }, diagnostics: diagnostics)!;
      final result = const SceneStateProposalValidator().apply(
        current: const SceneState(location: '酒馆'),
        proposal: proposal,
        knownCharacterIds: const {'protagonist', 'boris'},
        deadCharacterIds: const {},
      );

      expect(result.state!.location, '王宫');
      expect(result.state!.presentCharacterIds, ['protagonist']);
      expect(result.state!.goals.single.id, 'audience');
      expect(result.diagnostics,
          contains('scene_state_changes:characters:conflict:boris'));
      expect(result.diagnostics,
          contains('scene_state_changes:goals_update:missing:missing'));
    });
  });

  group('SceneState structured transaction', () {
    test(
        'should evolve scene state, reject dead entry, remain idempotent and isolate branches',
        () async {
      final adventureId = await repository.createAdventure(
        'scene state delta',
        AdventureConfig(supportingCharacters: [
          SupportingCharacter(id: 'eileen', name: '艾琳'),
          SupportingCharacter(id: 'boris', name: '鲍里斯'),
        ]),
      );
      Future<SceneDialogueCommitResult> commit({
        required String id,
        required int branchId,
        required SceneState base,
        SceneStateChangeProposal? proposal,
        RuntimeStateCommitDraft? runtime,
      }) =>
          repository.commitSceneDialogueTurn(SceneDialogueCommit(
            requestId: id,
            adventureId: adventureId,
            branchId: branchId,
            userMessage: Message(id: '$id-u', content: '行动', isUser: true),
            assistantMessage:
                Message(id: '$id-a', content: '剧情', isUser: false),
            gameState: GameState(
                adventureId: adventureId, currentScene: base.location),
            sceneState: base,
            sceneStateProposal: proposal,
            runtimeStateDraft: runtime,
          ));

      final first = await commit(
        id: 'tavern-to-street',
        branchId: 0,
        base: const SceneState(
            location: '酒馆', presentCharacterIds: ['protagonist']),
        proposal: const SceneStateChangeProposal(
          location: '街道',
          time: '深夜',
          charactersEnter: ['boris'],
          goalsAdd: [SceneGoal(id: 'palace', description: '前往王宫')],
        ),
      );
      expect(first.sceneState!.location, '街道');
      expect(first.gameState.currentScene, '街道');
      expect(first.sceneState!.presentCharacterIds, contains('boris'));

      final second = await commit(
        id: 'street-to-palace',
        branchId: 0,
        base: first.sceneState!,
        proposal: const SceneStateChangeProposal(
          location: '王宫',
          charactersLeave: ['boris'],
          goalsUpdate: {'palace': SceneGoalStatus.resolved},
        ),
        runtime: const RuntimeStateCommitDraft(
          expectedRevision: 0,
          summary: '艾琳死亡',
          changes: [
            RuntimeStateChangeProposal(
              entityType: RuntimeEntityType.character,
              entityId: 'eileen',
              changeKind: RuntimeChangeKind.primary,
              operation: RuntimeChangeOperation.set,
              path: 'life_status',
              value: 'dead',
              reason: '剧情死亡',
            ),
          ],
        ),
      );
      expect(second.sceneState!.location, '王宫');
      expect(second.sceneState!.activeGoals, isEmpty);

      final deathConflict = await commit(
        id: 'dead-cannot-enter',
        branchId: 0,
        base: second.sceneState!,
        proposal: const SceneStateChangeProposal(charactersEnter: ['eileen']),
      );
      expect(deathConflict.sceneState!.presentCharacterIds,
          isNot(contains('eileen')));
      expect((await repository.getRuntimeHead(adventureId, 0)).revision, 1);
      expect(
          (await commit(
            id: 'dead-cannot-enter',
            branchId: 0,
            base: second.sceneState!,
            proposal:
                const SceneStateChangeProposal(charactersEnter: ['eileen']),
          ))
              .applied,
          isFalse);

      final branchId = await repository.createBranch(
          adventureId: adventureId, forkAfterId: 3);
      final branch = await commit(
        id: 'branch-location',
        branchId: branchId,
        base: deathConflict.sceneState!,
        proposal: const SceneStateChangeProposal(location: '秘密花园'),
      );
      expect(branch.sceneState!.location, '秘密花园');
      expect((await repository.getSceneState(adventureId, 0))!.location, '王宫');
    });
  });
}
