import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/engines/chat_engine.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/models/completion_params.dart';
import 'package:lt_dialogue/models/dialogue_level.dart';
import 'package:lt_dialogue/models/game_state.dart';
import 'package:lt_dialogue/models/message.dart';
import 'package:lt_dialogue/models/supporting_character.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/llm_service.dart';
import 'package:lt_dialogue/services/repositories/adventure_repository.dart';
import 'package:lt_dialogue/services/repositories/adventure_repository_impl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/chat_engine_host_fixture.dart';

const _narrative = '艾琳在石桥边停下脚步，确认远处的追兵已经失去踪迹。'
    '夜风掠过河面，火把的倒影随着水波摇曳。你们决定暂时在桥边休整，'
    '并为下一段旅程整理装备和线索。';

final class _RuntimeProposalLlmService extends LLMService {
  _RuntimeProposalLlmService(this.response)
      : super(const LLMConfig(
          provider: LLMProvider.deepseek,
          apiKey: 'test-key',
          baseUrl: 'https://example.invalid',
          model: 'deepseek-flash',
        ));

  final String response;

  @override
  Future<LLMStreamResult> sendMessageStreamDetailed(
    List<Map<String, String>> messages,
    void Function(String chunk) onChunk,
    void Function() onDone, {
    void Function(String reasoningChunk)? onReasoningChunk,
    CompletionParams params = const CompletionParams(),
    GenerationTaskHandle? taskHandle,
  }) async {
    onChunk(response);
    onDone();
    return LLMStreamResult(
      content: response,
      finishReason: LLMFinishReason.stop,
      responseCompleted: true,
    );
  }
}

final class _RuntimeTurnHarness {
  _RuntimeTurnHarness({required this.adventureId, required this.repository})
      : config = AdventureConfig(
          name: '旅人',
          supportingCharacters: [
            SupportingCharacter(id: 'eileen', name: '艾琳'),
          ],
        );

  final int adventureId;
  final IAdventureRepository repository;
  final List<Message> messages = <Message>[];
  final AdventureConfig config;
  GameState gameState = GameState();

  ChatEngine build(String response) {
    final llm = _RuntimeProposalLlmService(response);
    return ChatEngine(
      host: ChatDependencies(
        getApiKey: () => 'test-key',
        getApiBaseUrl: () => 'https://example.invalid',
        getProviderType: () => LLMProvider.deepseek,
        getModelName: () => 'deepseek-flash',
        getCustomSystemPrompt: () => '',
        getAuthorsNote: () => '',
        getAuthorsNoteDepth: () => 0,
        getAuthorsNoteFrequency: () => 0,
        getAdventureConfig: () => config,
        getWorldEntries: () => const [],
        getBrightness: () => Brightness.light,
        getGameTopic: () => '测试冒险',
        getGameDifficulty: () => '普通',
        getCompletionParams: () =>
            const CompletionParams(enableThinking: false, maxTokens: 2048),
        getCurrentAdventureId: () => adventureId,
        getCurrentBranchId: () => 0,
        getActivePersona: () => null,
        getSelectedCharacterName: () => null,
        getTts: () => null,
        getLLMService: () => llm,
        setProvider: (_) async {},
        setModel: (_) async {},
        getGameState: () => gameState,
        setGameState: (value) => gameState = value,
        getMessages: () => messages,
        setMessages: (value) {
          messages
            ..clear()
            ..addAll(value);
        },
        getDialogueLevel: () => DialogueLevel.l0,
      ),
      notifyParent: () {},
      adventureRepo: repository,
    );
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  late Directory tempDir;
  late IAdventureRepository repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lt_runtime_turn_test_');
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

  group('ChatEngine runtime state proposal commits', () {
    test('should commit a canonical AI runtime proposal to the Runtime HEAD',
        () async {
      final adventureId = await repository.createAdventure(
        'Runtime proposal',
        AdventureConfig(
          name: '旅人',
          supportingCharacters: [
            SupportingCharacter(id: 'eileen', name: '艾琳'),
          ],
        ),
      );
      const response = '$_narrative\n---JSON---\n'
          '{"scene":"石桥","options":["继续前进","检查装备","观察河面"],'
          '"runtime_state_changes":[{"entity_type":"character",'
          '"entity_id":"eileen","change_kind":"primary",'
          '"operation":"set","path":"life_status","value":"dead",'
          '"reason":"剧情中明确死亡"}]}';
      final harness =
          _RuntimeTurnHarness(adventureId: adventureId, repository: repository);
      final engine = harness.build(response);
      addTearDown(engine.dispose);

      await engine.sendMessage('我查看艾琳的情况。');

      final head = await repository.getRuntimeHead(adventureId, 0);
      final entity =
          (await repository.getRuntimeEntities(adventureId, 0)).single;
      expect(head.revision, 1);
      expect(entity.entityId, 'eileen');
      expect(entity.overlay['life_status'], 'dead');
      expect(entity.lifecycleStatus, 'dead');
    });

    test('should ignore an invalid proposal without aborting the turn',
        () async {
      final adventureId = await repository.createAdventure(
        'Invalid runtime proposal',
        AdventureConfig(
          name: '旅人',
          supportingCharacters: [
            SupportingCharacter(id: 'eileen', name: '艾琳'),
          ],
        ),
      );
      const response = '$_narrative\n---JSON---\n'
          '{"scene":"石桥","options":["继续前进","检查装备","观察河面"],'
          '"runtime_state_changes":[{"entity_type":"character",'
          '"entity_id":"eileen","change_kind":"primary",'
          '"operation":"increment","path":"life_status","value":1,'
          '"reason":"invalid operation"}]}';
      final harness =
          _RuntimeTurnHarness(adventureId: adventureId, repository: repository);
      final engine = harness.build(response);
      addTearDown(engine.dispose);

      await engine.sendMessage('我查看艾琳的情况。');

      expect(engine.lastErrorType, isNull);
      expect(engine.status, ChatStatus.idle);
      expect((await repository.getRuntimeHead(adventureId, 0)).revision, 0);
      expect(await repository.getRuntimeEntities(adventureId, 0), isEmpty);
      expect(await repository.getMessages(adventureId), hasLength(2));
    });
  });
}
