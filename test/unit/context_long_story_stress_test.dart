import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/narrative/narrative_context.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/models/adventure_runtime_state.dart';
import 'package:lt_dialogue/models/game_state.dart';
import 'package:lt_dialogue/models/message.dart';
import 'package:lt_dialogue/models/model_context_capability.dart';
import 'package:lt_dialogue/models/scene_state.dart';
import 'package:lt_dialogue/models/supporting_character.dart';
import 'package:lt_dialogue/models/world_entry.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/repositories/adventure_repository.dart';
import 'package:lt_dialogue/services/repositories/adventure_repository_impl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  late Directory tempDir;
  late IAdventureRepository repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lt_context_stress_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
    repository = AdventureRepositoryImpl(getDb: () => DatabaseService.database);
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('Long adventure context pressure', () {
    test('should preserve current facts and isolate a branch after 300 turns',
        () async {
      final config = AdventureConfig(
        name: '旅人',
        supportingCharacters: [
          SupportingCharacter(id: 'eileen', name: '艾琳'),
          SupportingCharacter(id: 'boris', name: '鲍里斯'),
          SupportingCharacter(id: 'cora', name: '科拉'),
        ],
      );
      final adventureId = await repository.createAdventure('300 轮压力测试', config);
      final messages = <Message>[];
      SceneState scene = const SceneState(
        location: '白港',
        presentCharacterIds: ['protagonist', 'eileen', 'boris', 'cora'],
        goals: [SceneGoal(id: 'relic', description: '寻找遗物')],
      );

      for (var turn = 1; turn <= 300; turn++) {
        final location = switch (turn) {
          < 76 => '白港',
          < 151 => '雾林',
          < 226 => '王都',
          _ => '终焉塔',
        };
        final present = <String>['protagonist', 'boris'];
        if (turn < 100) present.add('eileen');
        if (turn < 220) present.add('cora');
        scene = SceneState(
          location: location,
          time: '第 $turn 夜',
          presentCharacterIds: present,
          goals: [
            SceneGoal(
              id: 'relic',
              description: '寻找遗物',
              status: turn < 260
                  ? SceneGoalStatus.active
                  : SceneGoalStatus.resolved,
            ),
          ],
          recentChanges: ['turn:$turn', if (turn == 100) '艾琳死亡'],
        );
        final change = turn == 100
            ? const RuntimeStateChangeProposal(
                entityType: RuntimeEntityType.character,
                entityId: 'eileen',
                changeKind: RuntimeChangeKind.primary,
                operation: RuntimeChangeOperation.set,
                path: 'life_status',
                value: 'dead',
                reason: '艾琳在雾林战死',
              )
            : RuntimeStateChangeProposal(
                entityType: RuntimeEntityType.character,
                entityId: 'boris',
                changeKind: RuntimeChangeKind.primary,
                operation: RuntimeChangeOperation.set,
                path: 'goal',
                value: '第 $turn 轮守护遗物',
                reason: '第 $turn 轮剧情推进',
              );
        final changes = <RuntimeStateChangeProposal>[
          change,
          if (turn == 50)
            const RuntimeStateChangeProposal(
              entityType: RuntimeEntityType.character,
              entityId: 'boris',
              changeKind: RuntimeChangeKind.primary,
              operation: RuntimeChangeOperation.increment,
              path: 'affinity',
              value: 5,
              reason: '鲍里斯好感上升',
            ),
          if (turn == 150)
            const RuntimeStateChangeProposal(
              entityType: RuntimeEntityType.character,
              entityId: 'boris',
              changeKind: RuntimeChangeKind.primary,
              operation: RuntimeChangeOperation.set,
              path: 'relationship',
              value: 'trusted_ally',
              reason: '鲍里斯成为可信盟友',
            ),
          if (turn == 200)
            const RuntimeStateChangeProposal(
              entityType: RuntimeEntityType.character,
              entityId: 'boris',
              changeKind: RuntimeChangeKind.primary,
              operation: RuntimeChangeOperation.set,
              path: 'faction_id',
              value: 'royal_guard',
              reason: '鲍里斯加入王都卫队',
            ),
        ];
        final user =
            Message(id: 'u-$turn', content: '第 $turn 轮行动', isUser: true);
        final assistant = Message(
          id: 'a-$turn',
          content: '第 $turn 轮在$location推进剧情。',
          isUser: false,
        );
        messages
          ..add(user)
          ..add(assistant);
        await repository.commitSceneDialogueTurn(SceneDialogueCommit(
          requestId: 'turn-$turn',
          adventureId: adventureId,
          branchId: 0,
          userMessage: user,
          assistantMessage: assistant,
          gameState:
              GameState(adventureId: adventureId, currentScene: location),
          sceneState: scene,
          runtimeStateDraft: RuntimeStateCommitDraft(
            expectedRevision: turn - 1,
            summary: 'turn $turn',
            changes: changes,
          ),
        ));
      }

      final rootHead = await repository.getRuntimeHead(adventureId, 0);
      final rootEntities = await repository.getRuntimeEntities(adventureId, 0);
      final rootScene = await repository.getSceneState(adventureId, 0);
      expect(rootHead.revision, 300);
      expect(rootScene!.location, '终焉塔');
      expect(rootScene.presentCharacterIds, isNot(contains('eileen')));
      expect(rootScene.activeGoals, isEmpty);
      expect(
        rootEntities
            .firstWhere((entity) => entity.entityId == 'eileen')
            .lifecycleStatus,
        'dead',
      );
      final rootBoris =
          rootEntities.firstWhere((entity) => entity.entityId == 'boris');
      expect(rootBoris.overlay['affinity'], 55);
      expect(rootBoris.overlay['relationship'], 'trusted_ally');
      expect(rootBoris.overlay['faction_id'], 'royal_guard');

      final branchId = await repository.createBranch(
        adventureId: adventureId,
        forkAfterId: 300,
      );
      await repository.commitSceneDialogueTurn(SceneDialogueCommit(
        requestId: 'branch-turn',
        adventureId: adventureId,
        branchId: branchId,
        userMessage: Message(id: 'branch-u', content: '改投白卫军', isUser: true),
        assistantMessage:
            Message(id: 'branch-a', content: '鲍里斯改投白卫军。', isUser: false),
        gameState: GameState(adventureId: adventureId, currentScene: '白卫军营地'),
        sceneState: const SceneState(
          location: '白卫军营地',
          presentCharacterIds: ['protagonist', 'boris'],
        ),
        runtimeStateDraft: const RuntimeStateCommitDraft(
          expectedRevision: 300,
          summary: '分支阵营变化',
          changes: [
            RuntimeStateChangeProposal(
              entityType: RuntimeEntityType.character,
              entityId: 'boris',
              changeKind: RuntimeChangeKind.primary,
              operation: RuntimeChangeOperation.set,
              path: 'faction_id',
              value: 'white_guard',
              reason: '分支选择改投白卫军',
            ),
          ],
        ),
      ));

      expect((await repository.getRuntimeHead(adventureId, 0)).revision, 300);
      expect((await repository.getRuntimeHead(adventureId, branchId)).revision,
          301);
      expect((await repository.getSceneState(adventureId, 0))!.location, '终焉塔');
      expect((await repository.getSceneState(adventureId, branchId))!.location,
          '白卫军营地');
      expect(
        (await repository.getRuntimeEntities(adventureId, 0))
            .firstWhere((entity) => entity.entityId == 'boris')
            .overlay['faction_id'],
        'royal_guard',
      );

      const capability = ModelContextCapability(
        providerId: 'test',
        modelId: 'test',
        maximumContextTokens: 8192,
        maximumOutputTokens: 2048,
      );
      final context = const ContextOrchestrator().build(
        rawInput: '艾琳为什么没有和我们同行？我决定完成遗物任务。',
        config: config,
        sceneState: rootScene,
        worldEntries: [
          WorldEntry(
            id: 1,
            keys: const ['遗物', '终焉塔'],
            content: '【世界观/locations】终焉塔封存遗物，只有白港地图能开启入口。',
            sourceType: 'location',
          ),
        ],
        messages: messages,
        summary: '艾琳在雾林战死；队伍随后抵达终焉塔，遗物任务待完成。',
        persona: null,
        capability: capability,
        requestedResponseTokens: 1024,
        runtimeRevision: rootHead.revision,
        runtimeEntities: rootEntities,
        archiveRetrievalFacts: const ['r100: 艾琳在雾林战死'],
      );
      expect(context.recentHistory, hasLength(12));
      expect(context.runtime.memory, contains('life_status=dead'));
      expect(context.world.all.single.entryId, 1);
      expect(context.trace.totalEstimatedTokens,
          lessThanOrEqualTo(context.budget.inputLimitTokens));
    });
  });
}
