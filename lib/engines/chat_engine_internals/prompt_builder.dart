import '../../application/narrative/narrative_context.dart';
import '../../application/narrative/prompt_compiler.dart';
import '../../config/app_config.dart';
import '../../models/dialogue_level.dart';
import '../../models/adventure_runtime_state.dart';
import '../../models/message.dart';
import '../../models/scene_dialogue.dart';
import '../../models/scene_state.dart';
import '../../services/dice_roller.dart';
import '../chat_engine_host.dart';

class PromptBuilder {
  final ContextOrchestrator _orchestrator = const ContextOrchestrator();
  final PromptCompiler _compiler = const PromptCompiler();
  ContextTrace? lastContextTrace;
  SceneState? lastSceneState;
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
  }) {
    final round = messages.where((m) => m.isUser).length + 1;
    final adventurePrompt = AppConfig.adventurePrompt(
      host.brightness,
      host.gameTopic,
      host.gameDifficulty,
      host.adventureConfig,
      host.quickMode,
      round,
      host.dialogueLevel,
      false,
    );
    final customPrompt = host.customSystemPrompt;
    final prompt = customPrompt.isNotEmpty
        ? '$customPrompt\n\n---\n\n$adventurePrompt'
        : adventurePrompt;
    final skillSection = _buildSkillSummary(host);
    final questSection = _buildQuestSummary(host);
    final affinitySection = _buildAffinitySummary(host);
    final hasCustomStatus = (host.adventureConfig?.allTrackedCustomAttributes ??
            host.adventureConfig?.customAttributes ??
            const [])
        .isNotEmpty;
    final formatReminder = _buildFinalFormatReminder(host.dialogueLevel,
        hasCustomStatus: hasCustomStatus);

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
      if (questSection.isNotEmpty) questSection,
      if (affinitySection.isNotEmpty) affinitySection,
      if (formatReminder.isNotEmpty) formatReminder,
      if (shouldInjectNote) '[作者注释] $note',
      if (dice.isNotEmpty) dice,
      if (pendingSearchResults?.isNotEmpty == true) pendingSearchResults!,
    ].where((section) => section.trim().isNotEmpty).join('\n\n');
    final currentSceneState = host.sceneState.location.isEmpty
        ? host.sceneState.copyWith(location: host.gameState.currentScene)
        : host.sceneState;
    final context = _orchestrator.build(
      rawInput: content,
      config: host.adventureConfig,
      sceneState: currentSceneState,
      worldEntries: host.worldEntries,
      messages: messages,
      summary: chatSummary,
      persona: host.activePersona,
      capability: host.modelContextCapability,
      requestedResponseTokens: SceneDialogueOutputBudget.resolve(
              host.dialogueLevel,
              quickMode: host.quickMode)
          .outputTokensFor(host.completionParams.maxTokens),
      controlContext: controls,
      runtimeRevision: runtimeRevision,
      runtimeEntities: runtimeEntities,
      archiveRetrievalFacts: archiveRetrievalFacts,
    );
    final compiled = _compiler.compile(
      runtimePolicy: prompt,
      context: context,
    );
    lastContextTrace = compiled.trace;
    lastSceneState = context.sceneState;
    return compiled.messages;
  }

  String _buildFinalFormatReminder(DialogueLevel dialogueLevel,
      {bool hasCustomStatus = false}) {
    // 字数数值与 JSON 字段骨架已在系统提示词中完整定义，这里只做格式锚定，
    // 不重复数值与字段示例，避免同一请求内指令叠加污染。
    final statusRequirement = hasCustomStatus
        ? '，以及本轮真正发生变化的状态（custom_status_changes，无变化可省略）'
        : '；当前无自定义状态，跳过状态字段';
    return '''
【本轮生成流程与格式强制检查】
严格遵循生成流程：正文 ➔ 状态（仅输出本轮变化，若无自定义状态则跳过）➔ 选项：
1. 叙事正文：遵守当前 ${dialogueLevel.id} ${dialogueLevel.label} 档位的字数要求，生动推进剧情，不得在正文中堆砌装备属性或身世清单。
2. 紧接一行 `---JSON---`，然后紧接一行合法 JSON（必须包含 options 数组$statusRequirement）。

禁止省略 `---JSON---`，禁止省略 options，禁止只写叙事正文。options 必须贴合本轮剧情，不能使用泛化模板。
options 还不得重复或高度相似于最近几轮已经出现过的选项；即使剧情推进很小，也要给出新的、具体的行动方向，禁止把玩家已经选过的行动再次列为选项。
''';
  }

  List<Map<String, String>> getFullPromptPreview(
    ChatEngineHost host,
    List<Message> messages,
    String? chatSummary,
  ) {
    return buildMessages(
      host,
      '（Prompt 预览：当前玩家输入将在此处）',
      messages,
      chatSummary,
      null,
    );
  }

  // ─── v2.0: Skill / Quest / Affinity summaries ───

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

  String _buildQuestSummary(ChatEngineHost host) {
    final questMgr = host.gameEngine?.questMgr;
    if (questMgr == null) return '';
    return questMgr.getPromptSummary(null);
  }

  String _buildAffinitySummary(ChatEngineHost host) {
    final affMgr = host.gameEngine?.affinityMgr;
    final config = host.adventureConfig;
    if (config == null) return '';
    final buf = StringBuffer();
    final affinities = <String, int>{};
    for (final npc in config.supportingCharacters.where((n) => n.isAlive)) {
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
