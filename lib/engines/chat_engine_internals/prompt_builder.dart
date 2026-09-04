import 'dart:convert';

import '../../config/app_config.dart';
import '../../models/dialogue_level.dart';
import '../../models/message.dart';
import '../../models/world_entry.dart';
import '../../models/scene_dialogue.dart';
import '../../services/dice_roller.dart';
import '../chat_engine_host.dart';

class PromptBuilder {
  static const worldScanDepth = 4;

  /// 早期事件时间线的包装文案。
  ///
  /// 字数措辞必须跟随对话档位而不硬编码数值：旧版在此写死
  /// “≥3500 字”，与 L0/L1/L2 等低档位的下限直接冲突，属于
  /// 同一请求内自相矛盾的提示词污染。
  static String wrapEarlyTimeline(String chatSummary) {
    return '[早期事件时间线 — 供你快速回顾之前发生了什么。请继续保持当前对话档位要求的叙事细节量。这是新的对话轮次，不要因为前面已经写了很多就缩短回复——每轮都是独立的故事推进，都需要充分的细节展开。]\n'
        '$chatSummary\n'
        '[时间线结束 — 以下是最近6轮完整对话]\n';
  }

  /// User-safe rendering of a context captured before generation starts.
  ///
  /// Only information that is NOT already part of the request is rendered:
  /// recent messages travel as real history roles, the early-event timeline
  /// lives in the system prompt, the current input is the user message
  /// itself and the output budget is appended by ChatEngine. Re-emitting any
  /// of those here duplicates context and makes the model re-narrate content
  /// it has just "read twice" (repetitive prose and repeated options).
  String buildFrozenSceneContext(SceneDialogueContextSnapshot snapshot) {
    final buf = StringBuffer('[本轮冻结场景上下文]');
    buf.writeln('地点：${snapshot.currentLocation}');
    buf.writeln('行动者：${snapshot.actor.name}');
    buf.writeln(
        '在场角色：${snapshot.presentParticipants.map((p) => p.name).join('、')}');
    if (snapshot.confirmedWorldview.isNotEmpty) {
      buf.writeln('已确认世界观：${jsonEncode(snapshot.confirmedWorldview)}');
    }
    if (snapshot.retrievalFacts.isNotEmpty) {
      buf.writeln('本冒险检索参考：${snapshot.retrievalFacts.join('\n')}');
    }
    buf.writeln('（近期对话已按消息顺序提供，请勿重复引用本块之外的历史内容。）');
    buf.writeln('[冻结场景上下文结束]');
    return buf.toString();
  }

  String injectWorldInfo(
    WorldEntryPosition position,
    List<Message> messages,
    List<WorldEntry> entries,
  ) {
    if (entries.isEmpty) return '';

    final scanTexts = <String>[];
    final depth = worldScanDepth.clamp(1, messages.length);
    final start = messages.length - depth;
    for (int i = start < 0 ? 0 : start; i < messages.length; i++) {
      scanTexts.add(messages[i].content);
    }

    final combinedText = scanTexts.join(' ');
    final matched = <WorldEntry>[];

    for (final entry in entries) {
      if (!entry.enabled) continue;
      if (entry.insertPosition != position) continue;
      if (entry.sticky > 0 || entry.matches(combinedText)) {
        matched.add(entry);
      }
    }

    if (matched.isEmpty) return '';

    matched.sort((a, b) => a.insertionOrder.compareTo(b.insertionOrder));
    final buf = StringBuffer();
    buf.writeln('[世界知识 - 当前上下文触发]');
    // Keep the scene prompt bounded even if a detailed library has many
    // keyword matches. Core (sticky) rules are sorted first by their order.
    for (final entry in matched.take(10)) {
      buf.writeln('- ${entry.content}');
    }
    buf.writeln('[世界知识结束]');
    return buf.toString();
  }

  String withNameAnchor(String content, String? name) {
    if (name == null || name.isEmpty) return content;
    return '[$name] $content';
  }

  List<Map<String, String>> buildMessages(
    ChatEngineHost host,
    String content,
    List<Message> messages,
    String? chatSummary,
    String? pendingSearchResults,
  ) {
    // 标准冒险提示词（始终包含格式与字数要求）+ P2-01 动态字数预算
    final round = messages.where((m) => m.isUser).length + 1;
    final adventurePrompt = AppConfig.adventurePrompt(
      host.brightness,
      host.gameTopic,
      host.gameDifficulty,
      host.adventureConfig,
      host.quickMode,
      round,
      host.dialogueLevel,
    );
    // 自定义系统提示词作为补充（前置到标准提示词之前，而非替换）
    final customPrompt = host.customSystemPrompt;
    final prompt = customPrompt.isNotEmpty
        ? '$customPrompt\n\n---\n\n$adventurePrompt'
        : adventurePrompt;
    final systemContent = chatSummary != null
        ? '$prompt\n\n${wrapEarlyTimeline(chatSummary)}'
        : prompt;

    final personaContent = host.activePersona?.toPromptString() ?? '';
    final worldBeforePrompt = injectWorldInfo(
        WorldEntryPosition.beforePrompt, messages, host.worldEntries);
    final worldAfterPrompt = injectWorldInfo(
        WorldEntryPosition.afterPrompt, messages, host.worldEntries);
    final skillSection = _buildSkillSummary(host);
    final questSection = _buildQuestSummary(host);
    final affinitySection = _buildAffinitySummary(host);
    final selectedCharacterSection = _buildSelectedCharacterSection(host);

    final segments = [
      if (worldBeforePrompt.isNotEmpty) worldBeforePrompt,
      systemContent,
      if (selectedCharacterSection.isNotEmpty) selectedCharacterSection,
      if (worldAfterPrompt.isNotEmpty) worldAfterPrompt,
      if (skillSection.isNotEmpty) skillSection,
      if (questSection.isNotEmpty) questSection,
      if (affinitySection.isNotEmpty) affinitySection,
      if (personaContent.isNotEmpty) personaContent,
    ];
    final fullSystem = segments.join('\n\n');

    final apiMessages = <Map<String, String>>[
      {'role': 'system', 'content': fullSystem},
    ];

    final note = host.authorsNote.trim();
    final noteDepth = host.authorsNoteDepth.clamp(0, 100);
    final shouldInjectNote = note.isNotEmpty &&
        host.authorsNoteFrequency > 0 &&
        messages.where((m) => m.isUser).length % host.authorsNoteFrequency == 0;

    if (shouldInjectNote && noteDepth == 0) {
      apiMessages.add({'role': 'system', 'content': '[作者注释] $note'});
    }

    // v2.1: 智能上下文窗口 — 最近6轮完整 + 早期事件时间线
    // 对抗 LLM 长上下文衰减：不把所有历史消息发给 AI，
    // 而是「最近 6 轮完整保留 + 早期事件压缩为时间线摘要注入 system prompt」
    const retainFullRounds = 6; // 保留最近 6 轮（=12条消息）
    const retainMsgCount = retainFullRounds * 2; // user + assistant per round
    final totalMessages = messages.length;

    // 如果消息数不多，全量发送
    if (totalMessages <= retainMsgCount) {
      for (int i = 0; i < totalMessages; i++) {
        apiMessages.add({
          'role': messages[i].isUser ? 'user' : 'assistant',
          'content': messages[i].content,
        });
      }
    } else {
      // Tier 2: 早期事件已通过摘要时间线注入 system prompt（见 _buildAffinitySummary）
      // Tier 1: 只发送最近 6 轮完整消息
      final start = totalMessages - retainMsgCount;

      // 注入分隔标记，让 AI 知道上下文切换点
      // (摘要时间线已在 system prompt 中，此处只保留最近对话)
      for (int i = start; i < totalMessages; i++) {
        final msg = messages[i];
        apiMessages.add({
          'role': msg.isUser ? 'user' : 'assistant',
          'content': msg.content,
        });
      }
    }

    if (shouldInjectNote && noteDepth > 0) {
      apiMessages.add({'role': 'system', 'content': '[作者注释] $note'});
    }

    apiMessages.add({
      'role': 'system',
      'content': _buildFinalFormatReminder(host.dialogueLevel),
    });

    final name = host.selectedCharacterName ?? host.adventureConfig?.name;
    apiMessages.add({
      'role': 'user',
      'content': withNameAnchor(content, name),
    });

    final dice = DiceRoller().parseAndRoll(content);
    if (dice.isNotEmpty) {
      apiMessages.add({'role': 'system', 'content': dice});
    }

    if (pendingSearchResults != null && pendingSearchResults.isNotEmpty) {
      apiMessages.add({
        'role': 'system',
        'content': pendingSearchResults,
      });
    }

    return apiMessages;
  }

  String _buildSelectedCharacterSection(ChatEngineHost host) {
    final name = host.selectedCharacterName?.trim();
    if (name == null || name.isEmpty) return '';
    final selected = host.adventureConfig?.selectedCharacters
        .where((character) => character.characterName == name)
        .firstOrNull;
    final card = selected?.characterCardJson ?? const <String, dynamic>{};
    final profile = card['world_profile'] is Map
        ? card['world_profile'] as Map
        : const <String, dynamic>{};
    final facts = <String>[];
    void add(String label, dynamic value) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty) facts.add('$label：$text');
    }

    add('身份', card['profession']);
    add('性格', card['personality']);
    add('所属势力', profile['faction']);
    add('活动地点', profile['home_location']);
    add('公开目标', profile['public_goal']);
    add('能力来源', profile['ability_source']);
    add('能力限制', profile['ability_cost']);
    add(
        '禁忌',
        profile['taboos'] is List
            ? (profile['taboos'] as List).join('、')
            : profile['taboos']);
    return '[当前发言角色]\n'
        '本轮用户操作和对话都以“$name”为当前行动/发言角色。'
        '请优先让“$name”执行用户输入的动作、承担视角推进，并保持该角色身份一致。'
        '除非用户明确要求切换，否则不要把本轮动作转移给其他角色。\n'
        '${facts.isEmpty ? '' : '角色核心设定：${facts.join('；')}\n'}'
        '[当前发言角色结束]';
  }

  String _buildFinalFormatReminder(DialogueLevel dialogueLevel) {
    // 字数数值与 JSON 字段骨架已在系统提示词中完整定义，这里只做格式锚定，
    // 不重复数值与字段示例，避免同一请求内指令叠加污染。
    return '''
【本轮输出格式强制检查】
你接下来必须只输出两部分，且每轮都必须包含第二部分 JSON：
1. 叙事正文：遵守当前 ${dialogueLevel.id} ${dialogueLevel.label} 档位的字数要求，不要因对话历史变长而缩水。
2. 紧接一行 `---JSON---`，然后紧接一行合法 JSON（字段结构按系统提示词的定义，必须包含 options）。

禁止省略 `---JSON---`，禁止省略 options，禁止只写叙事正文。options 必须贴合本轮剧情，不能使用泛化模板。
options 还不得重复或高度相似于最近几轮已经出现过的选项；即使剧情推进很小，也要给出新的、具体的行动方向，禁止把玩家已经选过的行动再次列为选项。
''';
  }

  List<Map<String, String>> getFullPromptPreview(
    ChatEngineHost host,
    List<Message> messages,
    String? chatSummary,
  ) {
    // 标准冒险提示词（始终包含格式与字数要求）+ P2-01 动态字数预算
    final round = messages.where((m) => m.isUser).length + 1;
    final adventurePrompt = AppConfig.adventurePrompt(
      host.brightness,
      host.gameTopic,
      host.gameDifficulty,
      host.adventureConfig,
      host.quickMode,
      round,
      host.dialogueLevel,
    );
    // 自定义系统提示词作为补充（前置到标准提示词之前，而非替换）
    final customPrompt = host.customSystemPrompt;
    final prompt = customPrompt.isNotEmpty
        ? '$customPrompt\n\n---\n\n$adventurePrompt'
        : adventurePrompt;
    final systemContent = chatSummary != null
        ? '$prompt\n\n${wrapEarlyTimeline(chatSummary)}'
        : prompt;

    final personaContent = host.activePersona?.toPromptString() ?? '';
    final worldBeforePrompt = injectWorldInfo(
        WorldEntryPosition.beforePrompt, messages, host.worldEntries);
    final worldAfterPrompt = injectWorldInfo(
        WorldEntryPosition.afterPrompt, messages, host.worldEntries);
    final skillSection = _buildSkillSummary(host);
    final questSection = _buildQuestSummary(host);
    final affinitySection = _buildAffinitySummary(host);

    final segments = [
      if (worldBeforePrompt.isNotEmpty) worldBeforePrompt,
      systemContent,
      if (worldAfterPrompt.isNotEmpty) worldAfterPrompt,
      if (skillSection.isNotEmpty) skillSection,
      if (questSection.isNotEmpty) questSection,
      if (affinitySection.isNotEmpty) affinitySection,
      if (personaContent.isNotEmpty) personaContent,
    ];
    final fullSystem = segments.join('\n\n');

    final preview = <Map<String, String>>[
      {'role': 'system', 'content': fullSystem},
    ];

    if (host.authorsNote.isNotEmpty) {
      preview.add({
        'role': 'system',
        'content':
            '[Author\'s Note (depth=${host.authorsNoteDepth}, freq=${host.authorsNoteFrequency}): ${host.authorsNote.trim()}]',
      });
    }

    // v2.1: 智能窗口 — 最近6轮完整 + 早期时间线已在 system prompt 中
    const retainMsgCount = 12; // 6 rounds × 2
    final start =
        messages.length > retainMsgCount ? messages.length - retainMsgCount : 0;
    for (int i = start; i < messages.length; i++) {
      final msg = messages[i];
      preview.add({
        'role': msg.isUser ? 'user' : 'assistant',
        'content': msg.content,
      });
    }

    return preview;
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
    final affinities = <String, int>{};
    for (final npc in config.supportingCharacters.where((n) => n.isAlive)) {
      affinities[npc.name] = npc.affinity;
    }
    // Also include dead characters
    final buf = StringBuffer();
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
