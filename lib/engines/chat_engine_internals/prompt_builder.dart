import '../../application/narrative/narrative_context.dart';
import '../../application/narrative/prompt_compiler.dart';
import '../../application/narrative/relationship_context.dart';
import '../../application/narrative/user_intent.dart';
import '../../config/app_config.dart';
import '../../models/dialogue_level.dart';
import '../../models/model_capabilities.dart';
import '../../models/adventure_runtime_state.dart';
import '../../models/message.dart';
import '../../models/scene_dialogue.dart';
import '../../models/scene_state.dart';
import '../../services/dice_roller.dart';
import '../../utils/token_estimator.dart';
import '../chat_engine_host.dart';

class PromptBuilder {
  final ContextOrchestrator _orchestrator = const ContextOrchestrator();
  final PromptCompiler _compiler = const PromptCompiler();
  ContextTrace? lastContextTrace;
  SceneState? lastSceneState;
  RelationshipNarrativeContext lastRelationships =
      const RelationshipNarrativeContext();

  /// The intent the orchestrator derived for the most recent [buildMessages].
  NarrativeIntent? lastIntent;

  /// Current player turn, accounting for an already-appended current input.
  int? lastRound;
  List<Map<String, String>> lastHistoryItems = const [];
  int lastCurrentInputCount = 0;
  String withNameAnchor(String content, String? name) {
    if (name == null || name.isEmpty) return content;
    return '[$name] $content';
  }

  List<Map<String, String>> buildMessages(
    ChatEngineHost host,
    String content,
    List<Message> messages,
    String? chatSummary,
    String? pendingSearchResults, {
    String controlContext = '',
    int runtimeRevision = 0,
    List<RuntimeEntityState> runtimeEntities = const [],
    List<String> archiveRetrievalFacts = const [],
    SceneDialogueOutputBudget? frozenOutputBudget,
  }) {
    final last = messages.lastOrNull;
    final hasCurrentInput =
        last != null && last.isUser && last.content.trim() == content.trim();
    final round =
        messages.where((m) => m.isUser).length + (hasCurrentInput ? 0 : 1);
    lastRound = round;
    // ADR-0003: prefer the turn snapshot's frozen budget so the prompt can
    // never disagree with the multi-stage loop, the length guard and the
    // overflow convergence after a mid-turn settings change. The host-based
    // resolution stays as the fallback for callers without a snapshot.
    final outputBudget = frozenOutputBudget ??
        SceneDialogueOutputBudget.resolve(host.dialogueLevel,
            quickMode: host.quickMode,
            elasticPercent: host.effectiveGenerationElasticPercent);
    final adventurePrompt = AppConfig.adventurePrompt(
      host.brightness,
      host.gameTopic,
      host.gameDifficulty,
      host.adventureConfig,
      host.quickMode,
      round,
      host.dialogueLevel,
      outputBudget.usesMultiStage,
      outputBudget,
    );
    final customPrompt = host.customSystemPrompt;
    final prompt = customPrompt.isNotEmpty
        ? '$customPrompt\n\n---\n\n$adventurePrompt'
        : adventurePrompt;
    final skillSection = _buildSkillSummary(host);
    final affinitySection = _buildAffinitySummary(host, content);
    final hasCustomStatus = (host.adventureConfig?.allTrackedCustomAttributes ??
            host.adventureConfig?.customAttributes ??
            const [])
        .isNotEmpty;
    final formatReminder = _buildFinalFormatReminder(host.dialogueLevel,
        hasCustomStatus: hasCustomStatus,
        isMultiStage: outputBudget.usesMultiStage);

    final note = host.authorsNote.trim();
    final shouldInjectNote = note.isNotEmpty &&
        host.authorsNoteFrequency > 0 &&
        messages.where((message) => message.isUser).length %
                host.authorsNoteFrequency ==
            0;
    final dice = DiceRoller().parseAndRoll(content);
    final controls = [
      controlContext,
      if (skillSection.isNotEmpty) skillSection,
      if (affinitySection.isNotEmpty) affinitySection,
      if (formatReminder.isNotEmpty) formatReminder,
      if (shouldInjectNote) '[作者注释] $note',
      if (dice.isNotEmpty) dice,
      if (pendingSearchResults?.isNotEmpty == true) pendingSearchResults!,
    ].where((section) => section.trim().isNotEmpty).join('\n\n');
    final currentSceneState = host.sceneState.location.isEmpty
        ? host.sceneState.copyWith(location: host.gameState.currentScene)
        : host.sceneState;
    final narrativeTokens = outputBudget.usesMultiStage
        ? SceneDialogueOutputBudget.stageOutputTokens(
            SceneDialogueOutputBudget.planStage(
                    stage: 1,
                    currentChars: 0,
                    targetChars: outputBudget.targetChineseChars,
                    hardMaximum: outputBudget.hardMaximum,
                    maxStages: 4)
                .charTarget)
        : outputBudget.outputTokensFor(host.completionParams.maxTokens);
    final requestTokens = SceneDialogueOutputBudget.requestOutputTokens(
      narrativeTokens: narrativeTokens,
      params: host.completionParams,
      capabilities: ModelCapabilityRegistry.resolve(host.modelName),
    );
    final context = _orchestrator.build(
      rawInput: content,
      config: host.adventureConfig,
      sceneState: currentSceneState,
      worldEntries: host.worldEntries,
      messages: messages,
      summary: chatSummary,
      persona: host.activePersona,
      capability: host.modelContextCapability,
      requestedResponseTokens: requestTokens,
      controlContext: controls,
      runtimePolicyTokens: TokenEstimator(prompt).tokens,
      runtimeRevision: runtimeRevision,
      runtimeEntities: runtimeEntities,
      archiveRetrievalFacts: archiveRetrievalFacts,
      weightProfile: host.contextWeightProfile,
    );
    final compiled = _compiler.compile(
      runtimePolicy: prompt,
      context: context,
    );
    lastContextTrace = compiled.trace;
    lastSceneState = context.sceneState;
    lastRelationships = context.plannedRelationships;
    // Exposed so the engine can apply the same conservative intent reading
    // (exclusions, invitations, scene/time guards) to output authorization
    // without recomputing it from the raw input.
    lastIntent = context.intent;
    lastHistoryItems = [
      for (final message in context.recentHistory)
        {'id': message.id, 'role': message.isUser ? 'user' : 'assistant'},
    ];
    lastCurrentInputCount =
        compiled.messages.length - context.recentHistory.length - 1;
    return compiled.messages;
  }

  String _buildFinalFormatReminder(DialogueLevel dialogueLevel,
      {bool hasCustomStatus = false, bool isMultiStage = false}) {
    if (isMultiStage) {
      return '【分幕生成格式检查】\n'
          '整轮的篇幅范围适用于所有幕合并后的叙事正文，不要求每一幕达到该范围。\n'
          '当前幕的篇幅与是否为终幕，以本次最后一条用户消息的分幕指令为准。\n'
          '中间幕只写正文，不输出分隔符、JSON、选项或状态；仅终幕输出 ---JSON--- 和 JSON。\n'
          '任何一幕到达玩家决策点时，在正文最后一行单独输出 `---等待玩家---` 并停笔：'
          '该幕即为终幕，不再续写，也不要求达到整轮字数下限。\n'
          '所有幕延续同一个叙事节拍，不替玩家行动、不跨越时间、不自行结束场景。';
    }
    // 字数数值与 JSON 字段骨架已在系统提示词中完整定义，这里只做格式锚定，
    // 不重复数值与字段示例，避免同一请求内指令叠加污染。
    final statusRequirement = hasCustomStatus
        ? '，以及 custom_status_evaluations（逐项评估每一个被追踪状态，changed=false 也要列出并写明 reason；changed=true 时附 operation 与 value）'
        : '；当前无自定义状态，跳过状态字段';
    return '''
【本轮生成流程与格式强制检查】
严格遵循生成流程：正文 ➔ 状态评估（逐项列出全部被追踪状态，若无自定义状态则跳过）➔ 选项：
1. 叙事正文：遵守当前 ${dialogueLevel.id} ${dialogueLevel.label} 档位的字数要求，只推进一个叙事节拍，不得替玩家行动、不得跨越时间、不得自行收束场景；不得在正文中堆砌装备属性或身世清单。已到达玩家决策点时，在正文最后一行单独输出 `---等待玩家---` 并停笔，优先于字数要求；输出标记后不要输出 `---JSON---`、选项或状态。
2. 紧接一行 `---JSON---`，然后紧接一行合法 JSON（必须包含 options 数组$statusRequirement）。

禁止省略 `---JSON---`，禁止省略 options，禁止只写叙事正文。options 必须贴合本轮剧情，不能使用泛化模板。
options 还不得重复或高度相似于最近几轮已经出现过的选项；即使剧情推进很小，也要给出新的、具体的行动方向，禁止把玩家已经选过的行动再次列为选项。
''';
  }

  List<Map<String, String>> getFullPromptPreview(
    ChatEngineHost host,
    List<Message> messages,
    String? chatSummary, {
    int runtimeRevision = 0,
    List<RuntimeEntityState> runtimeEntities = const [],
    List<String> archiveRetrievalFacts = const [],
  }) {
    return buildMessages(
      host,
      '（Prompt 预览：当前玩家输入将在此处）',
      messages,
      chatSummary,
      null,
      runtimeRevision: runtimeRevision,
      runtimeEntities: runtimeEntities,
      archiveRetrievalFacts: archiveRetrievalFacts,
    );
  }

  // ─── v2.0: Skill / Affinity summaries ───

  String _buildSkillSummary(ChatEngineHost host) {
    final gameState = host.gameState;
    final buf = StringBuffer();
    buf.writeln('【角色状态】');
    buf.writeln(
        'Lv.${gameState.level} | EXP ${gameState.experience}/${gameState.expToNextLevel} | HP ${gameState.hp}/${gameState.maxHp} | MP ${gameState.mp}/${gameState.maxMp}');
    buf.writeln(
        'ATK ${gameState.baseAtk} | DEF ${gameState.baseDef} | SPD ${gameState.baseSpeed}');
    buf.writeln('技能点: ${gameState.skillPoints} | 金币: ${gameState.gold}');
    if (gameState.isExhausted) {
      buf.writeln(
          '⚠️ 能量极低（${gameState.energy}/${gameState.maxEnergy}），全属性 -20%。建议休息。');
    }
    buf.writeln('当玩家在对话中表示要使用技能时，请在 JSON 中附加 "skill_used":"技能ID"。');
    buf.writeln('玩家升级时（EXP达标），请在 JSON 中附加 "level_up":true。');
    return buf.toString();
  }

  String _buildAffinitySummary(ChatEngineHost host, String content) {
    final affMgr = host.gameEngine?.affinityMgr;
    final config = host.adventureConfig;
    if (config == null) return '';
    // Only characters the player can actually engage this turn appear in the
    // affinity summary: those present in the scene, plus any the player names
    // in this turn's own input. Listing every living NPC (name + affinity +
    // tracked status) implies absent characters are participating and invites
    // the model to pull them into the scene — the P2 root cause. Never fall
    // back to the whole roster: naming the absent is the only way in.
    //
    // The dead list below stays complete because it is a prohibition, not an
    // invitation.
    final presentIds = host.sceneParticipantIds.toSet();
    // A character the player excluded this turn must not surface here even if
    // the raw presence set still contains them: the authoritative presence
    // list in the same prompt has already dropped them, and echoing their
    // affinity would contradict it.
    final excluded = const IntentResolver()
        .resolve(content, knownCharacters: adventureCharacterNames(config))
        .excludedCharacterIds
        .toSet();
    final buf = StringBuffer();
    final affinities = <String, int>{};
    for (final npc in config.supportingCharacters.where((n) =>
        n.isAlive &&
        !excluded.contains(n.id) &&
        (presentIds.contains(n.id) ||
            (n.name.trim().length >= 2 && content.contains(n.name))))) {
      affinities[npc.name] = npc.affinity;
      if (npc.customAttributes.isNotEmpty) {
        final attrs =
            npc.customAttributes.map((a) => a.toPromptText()).join('；');
        buf.writeln('  📌 ${npc.name}检测状态: $attrs');
      }
    }
    // Also include dead characters
    final dead = config.supportingCharacters.where((n) => !n.isAlive).toList();
    if (dead.isNotEmpty) {
      buf.writeln('【已死亡角色 — 不可再出场】');
      for (final npc in dead) {
        buf.writeln(
            '  💀 ${npc.name} (${npc.role.isNotEmpty ? npc.role : "配角"}) — 已死亡，不可在叙事中出场、不可对话、不可互动');
      }
    }
    // Affinity summary
    if (affMgr != null) {
      final affSummary = affMgr.getPromptSummary(affinities);
      if (affSummary.isNotEmpty) buf.writeln(affSummary);
    }
    buf.writeln('新地点、势力、规则和 NPC 只可作为 scene_candidates 候选提出，不能直接修改正式设定。');
    return buf.toString();
  }
}
