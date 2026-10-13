import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/narrative/narrative_context.dart';
import 'package:lt_dialogue/application/narrative/prompt_compiler.dart';
import 'package:lt_dialogue/application/narrative/user_intent.dart';
import 'package:lt_dialogue/engines/chat_engine_internals/response_length_guard.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/models/adventure_response.dart';
import 'package:lt_dialogue/models/message.dart';
import 'package:lt_dialogue/models/model_context_capability.dart';
import 'package:lt_dialogue/models/scene_state.dart';
import 'package:lt_dialogue/models/supporting_character.dart';
import 'package:lt_dialogue/services/scene_entry_authorizer.dart';

/// Roster used across the intent and authorization tests: the player plus
/// three named NPCs, mirroring a two-person scene plus a third party.
const _roster = <String, String>{
  'protagonist': '旅人',
  'npc-a': '艾拉',
  'npc-b': '鲍里斯',
  'npc-c': '卡森',
};

NarrativeIntent _intent(String input) =>
    const IntentResolver().resolve(input, knownCharacters: _roster);

/// English roster so the English phrasings are resolved from real names.
NarrativeIntent _intentEn(String input) => const IntentResolver().resolve(
      input,
      knownCharacters: const {
        'npc-a': 'Ella',
        'npc-b': 'Boris',
        'npc-c': 'Carson',
      },
    );

void main() {
  group('IntentResolver soft constraints (P4)', () {
    test('excludes a named third party with natural phrasings', () {
      expect(_intent('不要让卡森打扰我们。').excludedCharacterIds, ['npc-c']);
      expect(_intent('别让卡森跟来').excludedCharacterIds, ['npc-c']);
      expect(_intent('我不想让卡森跟着').excludedCharacterIds, ['npc-c']);
      expect(_intentEn("Don't let Carson interrupt us.").excludedCharacterIds,
          ['npc-c']);
    });

    test('multi-name negative excludes every mentioned roster character', () {
      final intent = _intent('别让艾拉和鲍里斯跟来，我想自己行动。');
      expect(intent.excludedCharacterIds, containsAll(['npc-a', 'npc-b']));
    });

    test('protective negative does not exclude', () {
      // 「不要告诉艾琳」 is about secrecy, not scene participation.
      expect(_intent('不要告诉艾拉这件事。').excludedCharacterIds, isEmpty);
      expect(_intent('别让艾拉知道这件事。').excludedCharacterIds, isEmpty);
      // An unrelated 「来」 in a protective clause must not cancel the
      // protection and leak into a false exclusion.
      expect(_intent('别让艾拉担心我来晚了。').excludedCharacterIds, isEmpty);
      expect(_intent('别让艾拉操心，我自己会来。').excludedCharacterIds, isEmpty);
      // A mixed clause that also asks the character to stay away excludes.
      expect(_intent('别让卡森参与，也别让他知道。').excludedCharacterIds, ['npc-c']);
    });

    test('multi-name accompanying negatives still exclude every name', () {
      expect(_intent('别让艾拉和鲍里斯跟来。').excludedCharacterIds,
          containsAll(['npc-a', 'npc-b']));
      expect(_intent('别让艾拉和鲍里斯来。').excludedCharacterIds,
          containsAll(['npc-a', 'npc-b']));
    });

    test('exclusion wins over invitation in the same clause', () {
      final intent = _intent('不要让卡森来，叫他待在营地。');
      expect(intent.excludedCharacterIds, ['npc-c']);
      expect(intent.invitedCharacterIds, isEmpty);
    });

    test('recognizes explicit invitations and dismissals', () {
      expect(_intent('叫卡森一起来吧。').invitedCharacterIds, ['npc-c']);
      expect(_intent('邀请鲍里斯加入我们').invitedCharacterIds, ['npc-b']);
      expect(
          _intentEn('invite Carson to join us').invitedCharacterIds, ['npc-c']);
      expect(_intent('让鲍里斯先走吧。').dismissedCharacterIds, ['npc-b']);
      expect(_intentEn('ask Carson to leave').dismissedCharacterIds, ['npc-c']);
    });

    test('recognizes privacy, pacing and scene/time guards', () {
      expect(_intent('我想单独和艾拉相处。').privateWithCharacterIds, ['npc-a']);
      expect(_intentEn('I want to be alone with Ella.').privateWithCharacterIds,
          ['npc-a']);
      expect(_intent('慢一点，一步一步来。').wantsSlowerPace, isTrue);
      expect(_intentEn('slow down').wantsSlowerPace, isTrue);

      expect(_intent('暂时不要换场景。').forbidsSceneChange, isTrue);
      expect(_intentEn('stay here').forbidsSceneChange, isTrue);
      expect(_intent('不要跳过这段过程。').forbidsTimeSkip, isTrue);
      expect(_intentEn("don't skip ahead").forbidsTimeSkip, isTrue);

      final skip = _intent('直接跳到第二天。');
      expect(skip.requestsTimeSkip, isTrue);
      expect(skip.forbidsTimeSkip, isFalse);
      final move = _intent('我们去王宫吧。');
      expect(move.requestsSceneChange, isTrue);

      final negatedSkip = _intent('别跳到第二天，我要慢慢逛。');
      expect(negatedSkip.forbidsTimeSkip, isTrue);
      expect(negatedSkip.requestsTimeSkip, isFalse);
    });

    test('legacy behavior stays intact', () {
      final intent = _intent('我不去王宫了，我去酒馆。');
      expect(intent.refusals, contains('我不去王宫了'));
      expect(intent.goals, contains('我去酒馆'));
      expect(intent.changesPreviousGoal, isTrue);
      expect(_intent('艾拉为什么会变成这样？').asksHistory, isTrue);
      expect(_intent('我走向酒馆。').asksHistory, isFalse);
    });
  });

  group('SceneEntryAuthorizer (P2/P4)', () {
    const authorizer = SceneEntryAuthorizer();
    const names = <String, String>{
      'protagonist': '旅人',
      'npc-a': '艾拉',
      'npc-b': '鲍里斯',
      'npc-c': '卡森',
    };

    SceneStateChangeProposal proposal({
      List<String> enter = const [],
      List<String> leave = const [],
      String? location,
      String? time,
    }) =>
        SceneStateChangeProposal(
          charactersEnter: enter,
          charactersLeave: leave,
          location: location,
          time: time,
        );

    test('an unnamed arrival never authorizes a named entry', () {
      // A generic arrival sentence must not release an arbitrary
      // `characters_enter`: the proposal claims a specific roster identity, so
      // the prose has to name that identity. Letting 「走进」/「出现」 alone
      // authorize an entry is the bypass that would despoil quiet two-person
      // scenes.
      final result = authorizer.authorize(
        proposal: proposal(enter: ['npc-c']),
        authorization: const SceneEntryAuthorization(
          narrativeHasArrival: true,
          characterNames: names,
        ),
        currentLocation: '咖啡馆',
        currentTime: '傍晚',
      );
      expect(result.proposal, isNull);
      expect(result.diagnostics,
          contains('scene_state_changes:characters_enter:unnamed:npc-c'));
    });

    test('an arrival with no depiction trace is diagnosed as unauthorized', () {
      final result = authorizer.authorize(
        proposal: proposal(enter: ['npc-c']),
        authorization: const SceneEntryAuthorization(characterNames: names),
        currentLocation: '咖啡馆',
        currentTime: '傍晚',
      );
      expect(result.proposal, isNull);
      expect(result.diagnostics,
          contains('scene_state_changes:characters_enter:unauthorized:npc-c'));
    });

    test('a named arrival is a valid entry basis', () {
      final result = authorizer.authorize(
        proposal: proposal(enter: ['npc-c']),
        authorization: const SceneEntryAuthorization(
          narrativeNames: {'卡森'},
          narrativeHasArrival: true,
          characterNames: names,
        ),
        currentLocation: '咖啡馆',
        currentTime: '傍晚',
      );
      expect(result.proposal?.charactersEnter, ['npc-c']);
    });

    test('entry without narrative basis or invitation is rejected', () {
      final result = authorizer.authorize(
        proposal: proposal(enter: ['npc-c']),
        authorization: const SceneEntryAuthorization(characterNames: names),
        currentLocation: '咖啡馆',
        currentTime: '傍晚',
      );
      expect(result.proposal, isNull);
    });

    test('entry with narrative basis is accepted', () {
      final result = authorizer.authorize(
        proposal: proposal(enter: ['npc-b']),
        authorization: const SceneEntryAuthorization(
          narrativeNames: {'鲍里斯'},
          characterNames: names,
        ),
        currentLocation: '咖啡馆',
        currentTime: '傍晚',
      );
      expect(result.proposal?.charactersEnter, ['npc-b']);
    });

    test('invited entry is accepted even without narrative naming', () {
      final result = authorizer.authorize(
        proposal: proposal(enter: ['npc-c']),
        authorization: const SceneEntryAuthorization(
          invitedCharacterIds: {'npc-c'},
          characterNames: names,
        ),
        currentLocation: '咖啡馆',
        currentTime: '傍晚',
      );
      expect(result.proposal?.charactersEnter, ['npc-c']);
    });

    test('exclusion vetoes entry even with narrative basis', () {
      final result = authorizer.authorize(
        proposal: proposal(enter: ['npc-c']),
        authorization: const SceneEntryAuthorization(
          excludedCharacterIds: {'npc-c'},
          narrativeNames: {'卡森'},
          characterNames: names,
        ),
        currentLocation: '咖啡馆',
        currentTime: '傍晚',
      );
      expect(result.proposal, isNull);
    });

    test('leave needs narrative basis, dismissal or exclusion', () {
      final noBasis = authorizer.authorize(
        proposal: proposal(leave: ['npc-a']),
        authorization: const SceneEntryAuthorization(characterNames: names),
        currentLocation: '咖啡馆',
        currentTime: '傍晚',
      );
      expect(noBasis.proposal, isNull);

      final dismissed = authorizer.authorize(
        proposal: proposal(leave: ['npc-a']),
        authorization: const SceneEntryAuthorization(
          dismissedCharacterIds: {'npc-a'},
          characterNames: names,
        ),
        currentLocation: '咖啡馆',
        currentTime: '傍晚',
      );
      expect(dismissed.proposal?.charactersLeave, ['npc-a']);

      final excluded = authorizer.authorize(
        proposal: proposal(leave: ['npc-a']),
        authorization: const SceneEntryAuthorization(
          excludedCharacterIds: {'npc-a'},
          characterNames: names,
        ),
        currentLocation: '咖啡馆',
        currentTime: '傍晚',
      );
      expect(excluded.proposal?.charactersLeave, ['npc-a']);
    });

    test('protagonist leave is left to the structural validator', () {
      final result = authorizer.authorize(
        proposal: proposal(leave: ['protagonist']),
        authorization: const SceneEntryAuthorization(characterNames: names),
        currentLocation: '咖啡馆',
        currentTime: '傍晚',
      );
      expect(result.proposal?.charactersLeave, ['protagonist']);
    });

    test('forbidden scene/time changes are dropped, unchanged values kept', () {
      final blocked = authorizer.authorize(
        proposal: proposal(location: '王宫', time: '第二天'),
        authorization: const SceneEntryAuthorization(
          allowsLocationChange: false,
          allowsTimeChange: false,
          characterNames: names,
        ),
        currentLocation: '咖啡馆',
        currentTime: '傍晚',
      );
      expect(blocked.proposal, isNull);

      final sameValue = authorizer.authorize(
        proposal: proposal(location: '咖啡馆', time: '傍晚'),
        authorization: const SceneEntryAuthorization(
          allowsLocationChange: false,
          allowsTimeChange: false,
          characterNames: names,
        ),
        currentLocation: '咖啡馆',
        currentTime: '傍晚',
      );
      expect(sameValue.proposal?.location, '咖啡馆');
      expect(sameValue.proposal?.time, '傍晚');
    });

    test('neutral proposal keeps location and time (report semantics)', () {
      final result = authorizer.authorize(
        proposal: proposal(location: '王宫', time: '第二天'),
        authorization: const SceneEntryAuthorization(characterNames: names),
        currentLocation: '咖啡馆',
        currentTime: '傍晚',
      );
      expect(result.proposal?.location, '王宫');
      expect(result.proposal?.time, '第二天');
    });

    test('goals pass through untouched', () {
      final result = authorizer.authorize(
        proposal: const SceneStateChangeProposal(
          charactersEnter: ['npc-c'],
          goalsAdd: [SceneGoal(id: 'g1', description: '查明真相')],
        ),
        authorization: const SceneEntryAuthorization(characterNames: names),
        currentLocation: '咖啡馆',
        currentTime: '傍晚',
      );
      expect(result.proposal?.charactersEnter, isEmpty);
      expect(result.proposal?.goalsAdd.single.description, '查明真相');
    });

    test('diagnostics are reported per rejected delta', () {
      final result = authorizer.authorize(
        proposal: proposal(enter: ['npc-c'], leave: ['npc-a']),
        authorization: const SceneEntryAuthorization(characterNames: names),
        currentLocation: '咖啡馆',
        currentTime: '傍晚',
      );
      expect(result.proposal, isNull);
    });
  });

  group('AdventureResponse player-decision marker (P1)', () {
    test('trailing standalone marker is stripped and flagged', () {
      final parsed = AdventureResponse.parse(
          '她望向窗外，等待你的回答。\n${AdventureResponse.playerStopMarker}');
      expect(parsed.stoppedAtDecision, isTrue);
      expect(parsed.narrative.join('\n'), '她望向窗外，等待你的回答。');
    });

    test('marker before the JSON payload keeps the payload', () {
      final parsed = AdventureResponse.parse(
          '她望向窗外。\n${AdventureResponse.playerStopMarker}\n${AdventureResponse.jsonSeparator}\n'
          '{"scene":"第2幕·咖啡馆","options":["a","b","c"]}');
      expect(parsed.stoppedAtDecision, isTrue);
      expect(parsed.narrative.join('\n'), '她望向窗外。');
      expect(parsed.payload?['options'], ['a', 'b', 'c']);
    });

    test('marker inside prose is not a stop request', () {
      final parsed = AdventureResponse.parse(
          '她说着${AdventureResponse.playerStopMarker}之类的话。');
      expect(parsed.stoppedAtDecision, isFalse);
      expect(parsed.narrative.join('\n'),
          contains(AdventureResponse.playerStopMarker));
    });

    test('canonicalize and history projection strip the marker', () {
      const raw = '她望向窗外。\n${AdventureResponse.playerStopMarker}';
      expect(AdventureResponse.canonicalize(raw), '她望向窗外。');
      expect(AdventureResponse.llmHistoryProjection(raw), '她望向窗外。');
      expect(AdventureResponse.streamingDisplayText(raw), '她望向窗外。');
    });

    test('a mid-text standalone marker line is scrubbed by canonicalize', () {
      // Protocol deviation: the marker is not the final line. It must never
      // reach the bubble or history, but it is not a stop request either.
      const raw = '她推开门。\n${AdventureResponse.playerStopMarker}\n然后坐到你对面。';
      final parsed = AdventureResponse.parse(raw);
      expect(parsed.stoppedAtDecision, isFalse);
      expect(AdventureResponse.canonicalize(raw),
          isNot(contains(AdventureResponse.playerStopMarker)));
      expect(AdventureResponse.canonicalize(raw), contains('她推开门。'));
      expect(AdventureResponse.canonicalize(raw), contains('然后坐到你对面。'));
    });
  });

  group('NarrativeLengthGuard decision stop (P1)', () {
    const guard = NarrativeLengthGuard();

    test('stopped turn is never an underflow', () {
      const raw = '她望着你，等待答复。\n${AdventureResponse.playerStopMarker}';
      final result = guard.withoutSupplement(raw);
      expect(result.stoppedAtDecision, isTrue);
      expect(result.passed(400), isTrue);
      expect(result.verdict(400, 1200), NarrativeLengthVerdict.decisionStop);
      expect(result.verdict(400, 1200).diagnosticToken, 'decision_stop');
    });

    test('stopped turn above the minimum is within range', () {
      final long = '测' * 500;
      final raw = '$long\n${AdventureResponse.playerStopMarker}';
      final result = guard.withoutSupplement(raw);
      expect(result.verdict(400, 1200), NarrativeLengthVerdict.withinRange);
    });

    test('a short turn without the marker is still an underflow', () {
      final result = guard.withoutSupplement('她望着你。');
      expect(result.stoppedAtDecision, isFalse);
      expect(result.verdict(400, 1200), NarrativeLengthVerdict.underflow);
    });
  });

  group('PromptCompiler presence authority and player authorization (P2/P4)',
      () {
    NarrativeContext contextWith({
      List<String> present = const ['protagonist', 'npc-a', 'npc-b'],
      NarrativeIntent intent = const NarrativeIntent(rawInput: ''),
      String absentMentioned = '',
    }) {
      return NarrativeContext(
        intent: intent,
        sceneState: SceneState(presentCharacterIds: present),
        world: const WorldRuntimeContext(),
        plannedUserInput: '继续',
        characterContext: '旅人；剑士\n艾拉；吟游诗人',
        absentMentionedCharacterContext: absentMentioned,
        knownCharacterNames: _roster,
        plannedSceneContext: '咖啡馆',
        plannedWorldContext: '',
        personaContext: '',
        runtime: const RuntimeContextView(),
        historicalSummary: null,
        recentHistory: const <Message>[],
        controlContext: '',
        budget: const ContextBudget(
          contextWindowTokens: 32768,
          responseReserveTokens: 1024,
          inputLimitTokens: 30720,
        ),
        trace: const ContextTrace(
          entries: [],
          conflictRules: [],
          totalEstimatedTokens: 0,
          responseReserveTokens: 1024,
        ),
      );
    }

    String systemOf(NarrativeContext context) => const PromptCompiler()
        .compile(runtimePolicy: ' POLICY ', context: context)
        .messages
        .first['content']!;

    test('renders the authoritative presence list and its rules', () {
      final system = systemOf(contextWith());
      expect(system, contains('【当前在场角色（权威名单）】旅人、艾拉、鲍里斯'));
      expect(system, contains('只有名单中的角色可以与玩家互动'));
      expect(system, contains('被提及、回忆、引用或作为背景资料出现，不等于进入场景'));
      expect(system, contains('characters_enter'));
    });

    test('labels mentioned-but-absent profiles as reference only', () {
      final system = systemOf(contextWith(absentMentioned: '卡森；商人'));
      expect(system, contains('【被提及但不在场的角色】'));
      expect(system, contains('不得参与当前场景的互动、对话或行动'));
    });

    test('renders every player authorization and constraint', () {
      final intent = _intent('慢一点，我想单独和艾拉相处，暂时不要换场景，'
          '也不要跳过这段过程，叫卡森一起来，让鲍里斯先走。');
      final system = systemOf(contextWith(intent: intent));
      expect(system, contains('【本轮玩家授权与约束】'));
      expect(system, contains('玩家希望单独与 艾拉 相处'));
      expect(system, contains('玩家要求放慢节奏'));
      expect(system, contains('玩家要求不要切换场景'));
      expect(system, contains('玩家要求不要跳跃时间'));
      expect(system, contains('玩家本轮明确邀请：卡森'));
      expect(system, contains('玩家本轮要求其离开：鲍里斯'));
    });

    test('excluded characters are stated as a hard constraint', () {
      final intent = _intent('不要让卡森打扰我们。');
      final system = systemOf(contextWith(intent: intent));
      expect(system, contains('玩家本轮明确排除的角色：卡森'));
      expect(system, contains('不得以任何方式参与本轮互动'));
    });

    test('a neutral turn renders no authorization block', () {
      final system = systemOf(contextWith());
      expect(system, isNot(contains('【本轮玩家授权与约束】')));
    });
  });

  group('ContextOrchestrator character context split (P2)', () {
    AdventureConfig config() => AdventureConfig(
          name: '旅人',
          supportingCharacters: [
            SupportingCharacter(id: 'npc-a', name: '艾拉', role: '吟游诗人'),
            SupportingCharacter(id: 'npc-b', name: '鲍里斯', role: '保镖'),
            SupportingCharacter(id: 'npc-c', name: '卡森', role: '商人'),
          ],
        );

    test('present characters get profiles; mentioned absent ones are separated',
        () {
      const orchestrator = ContextOrchestrator();
      final built = orchestrator.build(
        rawInput: '卡森最近怎么样？',
        config: config(),
        sceneState: const SceneState(
          location: '咖啡馆',
          presentCharacterIds: ['protagonist', 'npc-a', 'npc-b'],
        ),
        worldEntries: const [],
        messages: const [],
        summary: null,
        persona: null,
        capability: const ModelContextCapability.conservative(
          providerId: 'deepseek',
          modelId: 'deepseek-flash',
        ),
        requestedResponseTokens: 1024,
      );
      expect(built.characterContext, contains('艾拉'));
      expect(built.characterContext, contains('鲍里斯'));
      expect(built.characterContext, isNot(contains('卡森')));
      expect(built.absentMentionedCharacterContext, contains('卡森'));
      expect(built.absentMentionedCharacterContext, isNot(contains('艾拉')));
      expect(built.knownCharacterNames['npc-c'], '卡森');
    });

    test('an unmentioned absent character appears in neither section', () {
      final built = const ContextOrchestrator().build(
        rawInput: '我环顾四周。',
        config: config(),
        sceneState: const SceneState(
          location: '咖啡馆',
          presentCharacterIds: ['protagonist', 'npc-a', 'npc-b'],
        ),
        worldEntries: const [],
        messages: const [],
        summary: null,
        persona: null,
        capability: const ModelContextCapability.conservative(
          providerId: 'deepseek',
          modelId: 'deepseek-flash',
        ),
        requestedResponseTokens: 1024,
      );
      expect(built.characterContext, isNot(contains('卡森')));
      expect(built.absentMentionedCharacterContext, isNot(contains('卡森')));
    });
  });
}
