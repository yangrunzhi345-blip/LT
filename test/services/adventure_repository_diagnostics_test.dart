import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/models/adventure_runtime_state.dart';
import 'package:lt_dialogue/models/game_state.dart';
import 'package:lt_dialogue/models/message.dart';
import 'package:lt_dialogue/models/scene_state.dart';
import 'package:lt_dialogue/models/supporting_character.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/repositories/adventure_repository.dart';
import 'package:lt_dialogue/services/repositories/adventure_repository_impl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  databaseFactory = databaseFactoryFfiNoIsolate;

  late Directory tempDir;
  late IAdventureRepository repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lt_diagnostics_repo_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
    repository = AdventureRepositoryImpl(
      getDb: () => DatabaseService.database,
    );
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('IAdventureRepository.getDiagnosticSessionExport', () {
    test(
        'exports diagnostic session with deterministic user message linking and branch isolation',
        () async {
      final config = AdventureConfig(
        name: '测试冒险',
        supportingCharacters: [
          SupportingCharacter(
            id: 'char_elena',
            name: '艾莲娜',
            role: '同伴',
            affinity: 50,
          ),
        ],
      );

      final advId = await repository.createAdventure('王城秘辛', config);

      // Seed a runtime entity on branch 0
      await repository.seedRuntimeEntity(
        adventureId: advId,
        branchId: 0,
        entityType: RuntimeEntityType.character,
        entityId: 'char_elena',
      );

      // Save initial scene state
      await repository.saveSceneState(
        advId,
        0,
        const SceneState(
          location: '中央广场',
          time: '清晨',
          presentCharacterIds: ['protagonist', 'char_elena'],
          goals: [
            SceneGoal(id: 'g1', description: '探访公会'),
          ],
        ),
      );

      // 1. Commit Turn 1 on Branch 0
      final userMsg1 = Message(
        id: 'user_msg_001',
        content: '向艾莲娜询问公会的情况。',
        isUser: true,
      );
      final aiMsg1 = Message(
        id: 'ai_msg_001',
        content:
            '艾莲娜微微一笑：“公会就在前方的钟楼右拐处。”\n---JSON---\n{"options": ["道谢并前进", "继续追问细节"]}',
        reasoningContent: '秘密推理：艾莲娜对主角态度温和',
        isUser: false,
      );

      await repository.commitSceneDialogueTurn(
        SceneDialogueCommit(
          requestId: 'req_001',
          adventureId: advId,
          branchId: 0,
          userMessage: userMsg1,
          assistantMessage: aiMsg1,
          gameState: GameState(adventureId: advId),
          contextSnapshotId: 'snap_001',
          diagnostics: const {
            'budget_tokens': 1024,
            'length_final_verdict': 'within_range',
          },
          runtimeStateDraft: const RuntimeStateCommitDraft(
            expectedRevision: 0,
            summary: '艾莲娜好感提升',
            changes: [
              RuntimeStateChangeProposal(
                entityType: RuntimeEntityType.character,
                entityId: 'char_elena',
                changeKind: RuntimeChangeKind.primary,
                operation: RuntimeChangeOperation.increment,
                path: 'affinity',
                value: 5,
                reason: '玩家礼貌询问',
              ),
            ],
          ),
        ),
      );

      // 2. Commit Turn 2 on Branch 0 (with level up additional message and no runtime changes)
      final userMsg2 = Message(
        id: 'user_msg_002',
        content: '我们快点出发吧。',
        isUser: true,
      );
      final aiMsg2 = Message(
        id: 'ai_msg_002',
        content: '你们穿过熙熙攘攘的集市，抵达了公会大门前。',
        isUser: false,
      );

      await repository.commitSceneDialogueTurn(
        SceneDialogueCommit(
          requestId: 'req_002',
          adventureId: advId,
          branchId: 0,
          userMessage: userMsg2,
          assistantMessage: aiMsg2,
          gameState: GameState(adventureId: advId),
          contextSnapshotId: 'snap_002',
          diagnostics: const {
            'budget_tokens': 1024,
            'continuity': 'passed',
          },
        ),
      );

      // 3. Create a branch and commit Turn on Branch 1
      final branch1Id = await repository.createBranch(
        adventureId: advId,
        forkAfterId: 1,
        name: '支线：前往黑市',
      );

      final userMsgB1 = Message(
        id: 'user_msg_b1_001',
        content: '我们改道去暗巷黑市看看。',
        isUser: true,
      );
      final aiMsgB1 = Message(
        id: 'ai_msg_b1_001',
        content: '艾莲娜眉头微皱：“那里鱼龙混杂，务必当心。”',
        isUser: false,
      );

      await repository.commitSceneDialogueTurn(
        SceneDialogueCommit(
          requestId: 'req_b1_001',
          adventureId: advId,
          branchId: branch1Id,
          userMessage: userMsgB1,
          assistantMessage: aiMsgB1,
          gameState: GameState(adventureId: advId),
        ),
      );

      // 4. Test Export of Branch 0
      final export0 = await repository.getDiagnosticSessionExport(
        adventureId: advId,
        branchId: 0,
        appVersion: '1.1.11+14',
        platformName: 'linux',
      );

      expect(export0.schema, equals('lt.diagnostic_session'));
      expect(export0.schemaVersion, equals(1));
      expect(export0.scope.adventureTitle, equals('王城秘辛'));
      expect(export0.scope.branchName, equals('main'));
      expect(export0.scope.branchId, equals(0));
      expect(export0.runtimeSnapshot.headRevision, equals(1));
      expect(export0.runtimeSnapshot.sceneState?.location, equals('中央广场'));
      expect(export0.runtimeSnapshot.entities.first.entityId,
          equals('char_elena'));
      expect(export0.turns.length, equals(2));

      // Check Turn 1
      final turn1 = export0.turns[0];
      expect(turn1.turnIndex, equals(1));
      expect(turn1.requestId, equals('req_001'));
      expect(turn1.user?.content, equals('向艾莲娜询问公会的情况。'));
      expect(turn1.user?.messageId, equals('user_msg_001'));
      expect(turn1.assistant.content, equals('艾莲娜微微一笑：“公会就在前方的钟楼右拐处。”'));
      expect(turn1.assistant.options, equals(['道谢并前进', '继续追问细节']));
      expect(turn1.runtime.committed, isTrue);
      expect(turn1.runtime.changes.length, equals(1));
      expect(turn1.runtime.changes.first.path, equals('affinity'));
      expect(turn1.runtime.changes.first.after, equals(55));
      expect(turn1.diagnostics['length_final_verdict'], equals('within_range'));

      // Check Turn 2
      final turn2 = export0.turns[1];
      expect(turn2.turnIndex, equals(2));
      expect(turn2.requestId, equals('req_002'));
      expect(turn2.user?.content, equals('我们快点出发吧。'));
      expect(turn2.assistant.content, equals('你们穿过熙熙攘攘的集市，抵达了公会大门前。'));
      expect(turn2.runtime.committed, isFalse);

      // Verify branch isolation: Branch 1 turn must NOT appear in Branch 0 export
      expect(export0.turns.any((t) => t.requestId == 'req_b1_001'), isFalse);

      // 5. Test Export of Branch 1
      final export1 = await repository.getDiagnosticSessionExport(
        adventureId: advId,
        branchId: branch1Id,
      );

      expect(export1.scope.branchName, equals('支线：前往黑市'));
      expect(export1.scope.branchId, equals(branch1Id));
      expect(export1.turns.length, equals(1));
      expect(export1.turns.first.turnIndex, equals(1));
      expect(export1.turns.first.requestId, equals('req_b1_001'));
      expect(export1.turns.first.user?.content, equals('我们改道去暗巷黑市看看。'));

      // 6. Verify Turn Limit works properly
      final exportLimited = await repository.getDiagnosticSessionExport(
        adventureId: advId,
        branchId: 0,
        turnLimit: 1,
      );
      expect(exportLimited.turns.length, equals(1));
      expect(exportLimited.turns.first.turnIndex, equals(1));
      expect(exportLimited.turns.first.requestId, equals('req_002'));
      expect(exportLimited.scope.turnRange.actual, equals(1));
      expect(exportLimited.scope.turnRange.requested, equals(1));

      // 7. Verify reasoning_content is never present in serialized export
      final jsonStr = export0.toPrettyJson();
      expect(jsonStr.contains('秘密推理'), isFalse);
      expect(jsonStr.contains('reasoning_content'), isFalse);
    });

    test('handles orphaned assistant turn gracefully with warning', () async {
      final advId = await repository.createAdventure(
        '孤儿测试',
        AdventureConfig(name: '测试'),
      );

      final db = await DatabaseService.database;
      // Insert an assistant message directly without any preceding user message
      await db.insert('messages', {
        'adventure_id': advId,
        'branch_id': 0,
        'role': 'assistant',
        'content': '孤立的开篇叙述。',
        'timestamp': DateTime.now().toIso8601String(),
        'client_message_id': 'ai_orphan_001',
      });

      await db.insert('scene_dialogue_turns', {
        'request_id': 'req_orphan_001',
        'adventure_id': advId,
        'branch_id': 0,
        'created_at': DateTime.now().toIso8601String(),
        'assistant_client_message_id': 'ai_orphan_001',
        'diagnostics_json': '{}',
      });

      final export = await repository.getDiagnosticSessionExport(
        adventureId: advId,
        branchId: 0,
      );

      expect(export.turns.length, equals(1));
      expect(export.turns.first.turnIndex, equals(1));
      expect(export.turns.first.user, isNull);
      expect(export.turns.first.assistant.content, equals('孤立的开篇叙述。'));
      expect(export.exportWarnings.isNotEmpty, isTrue);
      expect(
          export.exportWarnings.first, contains('no preceding message found'));
    });
  });
}
