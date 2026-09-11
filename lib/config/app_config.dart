import 'package:flutter/material.dart';
import '../models/adventure_config.dart';
import '../models/character_card.dart';
import '../models/dialogue_level.dart';
import '../models/scene_dialogue.dart';

class AppConfig {
  static const String apiBaseUrl = 'https://api.deepseek.com';
  // 规范默认模型由 ModelCapabilityRegistry.deepSeekFlash 定义；
  // 这里保留常量仅供历史/展示用途。
  static const String model = 'deepseek-flash';

  static int getTargetWords(
    int round, {
    DialogueLevel dialogueLevel = DialogueLevel.defaultLevel,
  }) {
    return SceneDialogueOutputBudget.resolve(dialogueLevel).targetChineseChars;
  }

  static const List<String> adventureTopics = [
    '奇幻森林',
    '太空探索',
    '深海冒险',
    '末日求生',
    '古堡探险',
    '梦境之旅',
  ];

  static String adventurePrompt(
    Brightness brightness,
    String topic,
    String difficulty, [
    AdventureConfig? config,
    bool quickMode = false,
    int round = 1, // P2-01: 动态字数预算
    DialogueLevel dialogueLevel = DialogueLevel.defaultLevel,
    bool includeSetupContext = true,
  ]) {
    final targetWords = getTargetWords(round, dialogueLevel: dialogueLevel);
    final diffConfig = switch (difficulty) {
      'easy' => '选项后果温和，失败可重来；资源充裕',
      'hard' => '选择后果显著，可能有不可逆的剧情转折；资源稀缺',
      _ => '选项有风险有收益；中等的资源管理',
    };

    final buf = StringBuffer();
    buf.writeln('你是沉浸式文字冒险主持人。回复分为两部分：');
    buf.writeln();
    buf.writeln('【第一部分：叙事文本（逐段输出）】');

    final effectiveQuickMode = quickMode &&
        (dialogueLevel.id == 'L0' || dialogueLevel.minWords <= 150);
    if (effectiveQuickMode) {
      // 字数数值由每轮用户消息携带的输出预算锚点统一声明，系统提示词不重复。
      buf.writeln('当前是快速模式，叙事正文满足本轮字数要求，不设字数上限。');
      buf.writeln('根据用户输入和剧情需要决定篇幅；简洁推进，但不要遗漏必要信息。');
    } else if (dialogueLevel == DialogueLevel.defaultLevel) {
      buf.writeln('当前对话模式：${dialogueLevel.id} ${dialogueLevel.label}。');
      buf.writeln('⚠️ 最高优先级指令：${dialogueLevel.promptRequirement}');
      buf.writeln('默认标准模式要求推进清晰、表达完整，不追求过长篇幅。');
      buf.writeln('段落长度依叙事节奏自然分配，长短错落，兼顾行动反馈、环境线索和角色互动。');
    } else {
      buf.writeln('当前对话模式：${dialogueLevel.id} ${dialogueLevel.label}。');
      buf.writeln('⚠️ 最高优先级指令：${dialogueLevel.promptRequirement}');
      buf.writeln('这是硬性指标，不满足的回复将被拒绝。');
      buf.writeln('不要因为对话历史变长就缩短回复——历史长意味着剧情更深入，应写得更详细。');
      buf.writeln();
      if (dialogueLevel.minWords < 1000) {
        buf.writeln('叙事节奏紧凑，段落依情节自然划分，直达玩家行动结果。');
      } else if (dialogueLevel.minWords < 2000) {
        buf.writeln(
            '【段落长度自然分配准则】（底线 ≥${dialogueLevel.minWords} 字，建议约 $targetWords 字）：');
        buf.writeln('- 段落篇幅完全由剧情张力与叙事焦点自发驱动，长短错落，杜绝机械切块与死板字数定额；');
        buf.writeln('- 视听氛围、言语互动、心理波澜与事件推进有机交织，按戏剧需要自然决定详略；');
        buf.writeln('- 保持从容丰富的叙事质感，总正文字数充实饱满，坚决达到档位底线。');
      } else {
        buf.writeln(
            '⚠️ 深度长篇叙事模式（纯汉字硬性底线 ≥${dialogueLevel.minWords} 字，建议叙事字符充实铺陈至 $targetWords 字左右）：');
        buf.writeln('【纯汉字计数换算校准（重中之重）】：');
        buf.writeln(
            '- 系统采用严格的【纯汉字统计】：第二部分约 600 字的 JSON、选项以及正文内的所有标点符号与空格换行均不计入此 ${dialogueLevel.minWords} 字！');
        buf.writeln(
            '- 关键经验换算：当【第一部分：叙事正文】总字符数达到 3000~3500 字符时，扣除标点格式后纯汉字才稳稳跨过 2500 字门槛！');
        buf.writeln(
            '- 严禁在叙事达到 2000 字符左右时就自以为写够而匆匆输出 JSON 收尾，必须以 3200 字符以上为实际叙事充实基准！');
        buf.writeln('【单轮双重波折推进机制（彻底打破字数瓶颈的叙事引擎）】：');
        buf.writeln('- 严禁单点冲突一解决就草率收场！单轮长篇叙事必须包含【一波三折·双重波折链】：');
        buf.writeln(
            '  1. 第一重波折（初度交锋与表层破局，约 1200 字符）：面对玩家行动，展开深层视听入境、至少 6~8 轮来回言语试探与第一轮动作碰撞；');
        buf.writeln(
            '  2. 第二重波折（事态突变与深层危机激化，约 1200 字符）：第一轮交锋并未让事态彻底平息，反而触动了更危险的隐患——突发变故、第三方隐藏动机曝光、环境坍塌或观念尖锐激化，双方被迫展开第二轮更为激烈的深层言语对质与拉锯对抗；');
        buf.writeln(
            '  3. 第三重破局与余波（阶段定局与重大暗流，约 800 字符）：绝境决断与合力破局，彻底改写双方处境，留下深刻的情感共鸣、好感波澜与后续重大悬念。');
        buf.writeln('【段落长度自然分配准则】：');
        buf.writeln(
            '- 坚决不设死板的单段字数配额：各段篇幅完全由情节张力自然决定。短促对白允许单行成段，环境与心理从容铺展成长段，长短错落有致；');
        buf.writeln(
            '- 依靠上述“双重波折链”与多轮深度对白自然撑起篇幅，确保扣除一切非正文字符后，纯汉字坚决达到 ${dialogueLevel.minWords} 字以上。');
      }
      buf.writeln();
      buf.writeln('写作要求：');
      buf.writeln('- 对话要完整展开，多轮交锋自然分段，不要概括为"他们交谈了几句"');
      buf.writeln('- 心理活动与动作神态自然交织，展示内心矛盾与情感');
      buf.writeln('- 环境与感官细节有机融入叙事进程，不要孤立堆砌');
      buf.writeln('- 推进充足的情节波折与对话回合，写足深度后再进入第二部分');
    }
    buf.writeln('用生动文笔连续叙述，不要输出"第一段""第二段"等段落标签。');
    buf.writeln('叙事结束后立即输出分隔符和 JSON，不要额外空行。');
    buf.writeln();
    final customAttrs = config?.allTrackedCustomAttributes ??
        config?.customAttributes ??
        const [];
    final hasCustomAttrs = customAttrs.isNotEmpty;

    buf.writeln('【第二部分：状态与选项数据（严格一行 JSON）】');
    buf.writeln('在叙事结束后，输出一行分隔符 `---JSON---`，然后紧跟一行 JSON：');
    if (hasCustomAttrs) {
      buf.writeln('{"scene":"第N幕·<场景标题>","options":["<行动1>","<行动2>","<行动3>"],'
          '"custom_status_changes":[{"character_id":"<角色ID>","attribute_id":"<状态ID>","operation":"set|delta","value":"<新值或变化量>"}]}');
      buf.writeln('当前需追踪的自定义检测状态（含稳定 ID，变化时按 ID 引用；名称仅作历史兼容）：');
      for (final attr in customAttrs) {
        final prefix =
            attr.characterName != null && attr.characterName!.isNotEmpty
                ? '[${attr.characterName}] '
                : '';
        final charId = _characterIdFor(config, attr.characterName);
        final attrId =
            attr.id.trim().isNotEmpty ? attr.id.trim() : '（无稳定ID，用名称）';
        buf.writeln(
            '  - $prefix${attr.toPromptText()}（character_id=$charId，attribute_id=$attrId）');
      }
      buf.writeln('【状态变更规则（Delta 增量协议，只输出变化）】：');
      buf.writeln('- 只输出本轮真正发生变化的状态；未变化的状态一律不输出，程序会在本地保留原值。');
      buf.writeln('- 本轮无状态变化时，可完全省略 custom_status_changes 字段。');
      buf.writeln(
          '- 数值状态：operation 用 "set"（直接设值，如 set 30）或 "delta"（增减，如 50 + delta 3 = 53）。');
      buf.writeln('- 文本/阶段状态：只用 "set" 直接设置新值；只有事实变化时才更新，禁止仅因措辞变化而改写。');
      buf.writeln('- 状态变化必须有真实剧情依据，禁止为变化而强行变化或每轮固定波动。');
    } else {
      buf.writeln('{"scene":"第N幕·<场景标题>","options":["<行动1>","<行动2>","<行动3>"]}');
      buf.writeln('（当前无自定义检测状态，JSON 中无需输出 custom_status_changes 字段）');
    }
    buf.writeln();
    buf.writeln('v2.0 可选扩展字段（根据剧情需要自动添加，均为可选）：');
    buf.writeln('  "combat":true — 触发战斗时添加，同时需要 "enemies" 数组');
    buf.writeln(
        '  "enemies":[{"name":"<敌人名称>","hp":45,"max_hp":45,"atk":8,"def":3,"icon":"🐺"}]');
    buf.writeln(
        '  "quest_progress":{"quest_id":{"objective_index":0,"increment":1}}');
    buf.writeln('  "quest_completed":"quest_id" — 任务完成时添加');
    buf.writeln(
        '  "quest_triggered":{"title":"...","objectives":[...],"rewards":[...]}');
    buf.writeln('  "affinity_change":{"NPC名称":5} — 好感度变化');
    buf.writeln('  "character_dead":"NPC名称" — 配角死亡时添加，死亡后不可再出场（也可以是数组）');
    buf.writeln(
        '  "runtime_state_changes":[{"entity_type":"character","entity_id":"稳定角色ID","change_kind":"primary","operation":"set","path":"life_status","value":"dead","reason":"剧情中明确死亡"}] — 仅用于跨场景持久事实；entity_id 必须使用已知稳定 ID，禁止角色名、任意 SQL 或未知实体');
    buf.writeln(
        '  "scene_candidates":[{"type":"location/faction/rule/custom/timeline/npc","content":"候选设定"}] — 新设定只能作为候选提出，绝不可静默写入正式资料');
    buf.writeln('  "skill_used":"skill_id" — 玩家使用了技能时添加');
    buf.writeln(
        '  "items_gained":[{"name":"<物品名>","type":"consumable","data":{...},"owner":"<角色名>"}]');
    buf.writeln(
        '    owner=物品归属（可选，省略归主角/公共），type=consumable/equipment/material/quest');
    buf.writeln('  "level":1,"experience":0,"mp":100,"max_mp":100');
    buf.writeln('  "base_atk":5,"base_def":3,"base_speed":5,"skill_points":0');
    buf.writeln();
    buf.writeln('规则：角色姓名不可更改 | 叙事与JSON之间只用 `---JSON---` 分隔');
    buf.writeln(
        '| options 必须提供 2~4 个行动选项，严禁返回空数组；每个选项为 15~50 个中文字，不得少于 15 字或超过 50 字 | hp/energy/gold 根据剧情更新 | scene 幕编号递增');
    buf.writeln(
        '| 如果剧情没有自然分支，至少提供「继续深入探索周围的环境寻找线索」「仔细观察环境细节看看有什么异常」「检查自身状态与随身物品确认情况」三个通用选项');
    buf.writeln('| 不要用代码块包裹 | 只输出上述两部分，不要额外解释');
    buf.writeln('| v2.0 扩展字段均为可选，只需在相关事件发生时添加');
    buf.writeln();

    if (includeSetupContext) {
      buf.writeln(_buildConfigSection(config));
    }

    final card = config?.characterCard;
    if (includeSetupContext && card != null) {
      buf.writeln(_buildCharacterCardSection(card));
    }

    buf.writeln();
    buf.writeln('=== 游戏机制 ===');
    buf.writeln('冒险主题：${topic.isNotEmpty ? topic : '随机冒险'}');
    buf.writeln('难度：$difficulty ($diffConfig)');
    buf.writeln();
    buf.writeln('=== 首轮特殊处理 ===');
    buf.writeln('如果是首轮（历史消息为空），根据设定展开场景，在叙事中体现角色外貌。');
    buf.writeln();
    buf.writeln('=== 自添加专属设定遵守准则 ===');
    buf.writeln('角色卡与NPC中若包含【自添加专属设定】，AI在推演剧情、撰写对话和判定角色行为时必须严格按重要程度等级遵守：');
    buf.writeln(
        '1. 【不可忽略项】：最高优先级铁律设定。绝对不可违背、遗漏或产生冲突！在涉及该设定的情节、对话、技能或状态时必须严格执行并作为决定性依据。');
    buf.writeln('2. 【很重要参考】：核心关键设定。在角色的重要决策、高潮互动、心理刻画中必须重点体现与遵循。');
    buf.writeln('3. 【重要参考】：重要背景设定。在角色日常言行、习惯特征、互动细节中应积极体现。');
    buf.writeln('4. 【参考】：辅助补充设定。作为背景风貌与性格习惯的辅助参考，自然融入叙事。');
    buf.writeln();
    buf.writeln('=== 重要 ===');
    buf.writeln('严格遵循上述两部分格式。');
    buf.writeln('你不是在写摘要——你是在写小说。根据本轮剧情需要展开，完整回应用户输入后再结束。');

    return buf.toString();
  }

  /// 根据追踪状态的绑定角色名反查稳定 character_id。
  /// 主角返回 `protagonistCharacter.characterId`（无则 `protagonist`），配角返回 `sc.id`。
  static String _characterIdFor(
      AdventureConfig? config, String? characterName) {
    final name = characterName?.trim() ?? '';
    final protagonist = config?.protagonistCharacter;
    if (name.isEmpty ||
        (protagonist != null &&
            (name == protagonist.characterName.trim() ||
                name == (config?.name.trim() ?? '')))) {
      if (protagonist != null && protagonist.characterId.isNotEmpty) {
        return protagonist.characterId;
      }
      return 'protagonist';
    }
    final supporting = config?.supportingCharacters;
    if (supporting != null) {
      for (final sc in supporting) {
        if (sc.name.trim() == name) return sc.id;
      }
    }
    return 'protagonist';
  }

  static String _buildCharacterCardSection(CharacterCard card) {
    final buf = StringBuffer();
    if (card.description.isNotEmpty) buf.writeln('- 角色描述：${card.description}');
    if (card.bodyDescription.isNotEmpty) {
      buf.writeln('- 身材描述：${card.bodyDescription}');
    }
    if (card.appearance.isNotEmpty) buf.writeln('- 外貌描述：${card.appearance}');
    if (card.personality.isNotEmpty) buf.writeln('- 性格倾向：${card.personality}');
    if (card.scenario.isNotEmpty) buf.writeln('- 场景背景：${card.scenario}');
    if (card.firstMessage.isNotEmpty) {
      buf.writeln('- 首条消息示例：${card.firstMessage}');
    }
    if (card.exampleDialogues.isNotEmpty) {
      buf.writeln('- 对话示例：${card.exampleDialogues}');
    }
    if (card.systemPrompt.isNotEmpty) {
      buf.writeln('- 系统指示：${card.systemPrompt}');
    }
    if (card.postHistoryInstructions.isNotEmpty) {
      buf.writeln('- 后置指令：${card.postHistoryInstructions}');
    }
    if (card.customAttributes.isNotEmpty) {
      final customList = <String>[];
      for (final item in card.customAttributes) {
        final cName = item.name.trim();
        final cVal = item.value.trim();
        final cImp = item.importance.label;
        if (cName.isNotEmpty && cVal.isNotEmpty) {
          customList.add('【$cImp】$cName：$cVal');
        } else if (cName.isNotEmpty) {
          customList.add('【$cImp】$cName');
        } else if (cVal.isNotEmpty) {
          customList.add('【$cImp】$cVal');
        }
      }
      if (customList.isNotEmpty) {
        buf.writeln('- 自添加专属设定：${customList.join('；')}');
      }
    }
    if (buf.length > 0) return '=== 角色深度设定 ===\n$buf';
    return '';
  }

  static String _buildConfigSection(AdventureConfig? config) {
    if (config == null) return '';
    final buf = StringBuffer();
    buf.writeln('=== 玩家角色设定 ===');
    if (config.worldview.isNotEmpty) buf.writeln('- 世界观：${config.worldview}');
    final selectedCharacters = List<AdventureSelectedCharacter>.from(
      config.selectedCharacters,
    )..sort((a, b) {
        if (a.isProtagonist != b.isProtagonist) {
          return a.isProtagonist ? -1 : 1;
        }
        return a.sortOrder.compareTo(b.sortOrder);
      });
    if (selectedCharacters.isEmpty && config.name.isNotEmpty) {
      buf.writeln('- 姓名：${config.name}（主角，必须使用此姓名）');
    }
    if (config.gender.isNotEmpty) buf.writeln('- 性别：${config.gender}');
    if (config.age.isNotEmpty) buf.writeln('- 年龄：${config.age}');
    if (config.protagonistClass.isNotEmpty) {
      buf.writeln('- 职业/身份：${config.protagonistClass}');
    }
    if (config.protagonistBackground.isNotEmpty) {
      buf.writeln('- 背景故事：${config.protagonistBackground}');
    }
    if (config.personality.isNotEmpty) {
      buf.writeln('- 性格：${config.personality}');
    }
    if (config.narrativePerson.isNotEmpty) {
      buf.writeln('- 叙述人称：${config.narrativePerson}');
    }
    if (config.styleEnhancement.isNotEmpty) {
      buf.writeln('- 文风：${config.styleEnhancement}');
    }
    if (config.bodyDescription.isNotEmpty) {
      buf.writeln('- 外貌/身材：${config.bodyDescription}');
    }
    if (selectedCharacters.isNotEmpty) {
      final protagonist = selectedCharacters.firstWhere(
        (c) => c.isProtagonist,
        orElse: () => selectedCharacters.first,
      );
      buf.writeln();
      buf.writeln('=== 已选角色卡（只允许一个玩家主角） ===');
      buf.writeln(
          '唯一主角：${protagonist.characterName}（玩家主要代入/控制角色，剧情身份：${protagonist.effectiveRole}）');
      for (final character in selectedCharacters) {
        final card = character.characterCardJson ?? const <String, dynamic>{};
        final cardData = card['data'] is Map<String, dynamic>
            ? card['data'] as Map<String, dynamic>
            : card;
        final details = <String>[];
        if (character.isProtagonist) details.add('玩家主角');
        details.add('剧情身份：${character.effectiveRole}');
        final gender = cardData['gender']?.toString() ?? '';
        final profession = cardData['profession']?.toString() ?? '';
        final personality = cardData['personality']?.toString() ?? '';
        final background =
            (cardData['background'] ?? cardData['description'])?.toString() ??
                '';
        final bodyDescription = (cardData['bodyDescription'] ??
                    cardData['body_description'] ??
                    cardData['physique'] ??
                    cardData['figureDescription'] ??
                    cardData['bodyShape'] ??
                    cardData['bodyType'] ??
                    cardData['physicalDescription'] ??
                    cardData['appearanceDetail'] ??
                    cardData['lookDescription'])
                ?.toString() ??
            '';
        final appearance = cardData['appearance']?.toString() ?? '';
        if (gender.isNotEmpty) details.add('性别：$gender');
        if (profession.isNotEmpty) details.add('职业：$profession');
        if (personality.isNotEmpty) details.add('性格：$personality');
        if (background.isNotEmpty) details.add('背景：$background');
        if (bodyDescription.isNotEmpty) details.add('身材：$bodyDescription');
        if (appearance.isNotEmpty) details.add('外貌：$appearance');
        final rawCustom =
            cardData['custom_attributes'] ?? cardData['customAttributes'];
        if (rawCustom is List && rawCustom.isNotEmpty) {
          final customList = <String>[];
          for (final item in rawCustom) {
            if (item is Map) {
              final cName = item['name']?.toString().trim() ?? '';
              final cVal = item['value']?.toString().trim() ?? '';
              final cImp = item['importance']?.toString().trim() ?? '参考';
              if (cName.isNotEmpty && cVal.isNotEmpty) {
                customList.add('【$cImp】$cName：$cVal');
              } else if (cName.isNotEmpty) {
                customList.add('【$cImp】$cName');
              } else if (cVal.isNotEmpty) {
                customList.add('【$cImp】$cVal');
              }
            }
          }
          if (customList.isNotEmpty) {
            details.add('自添加专属设定：${customList.join('；')}');
          }
        }
        buf.writeln('- ${character.characterName}：${details.join('；')}');
      }
      final relationships = config.characterRelationships
          .where((r) =>
              r.relationType != AdventureRelationType.unset ||
              r.description.trim().isNotEmpty)
          .toList();
      if (relationships.isNotEmpty) {
        final nameById = {
          for (final character in selectedCharacters)
            character.characterId: character.characterName,
        };
        buf.writeln();
        buf.writeln('=== 角色关系（无方向关系） ===');
        for (final relation in relationships) {
          final source = nameById[relation.sourceCharacterId] ??
              relation.sourceCharacterId;
          final target = nameById[relation.targetCharacterId] ??
              relation.targetCharacterId;
          final desc = relation.description.trim();
          buf.writeln(
              '- $source 与 $target：${relation.effectiveRelation}${desc.isNotEmpty ? '，$desc' : ''}');
        }
      }
    }
    if (config.supportingCharacters.isNotEmpty) {
      buf.writeln();
      buf.writeln('=== 角色设定（按重要性排序，以下姓名不可更改） ===');
      buf.writeln('必须使用以下实际姓名，权重高的角色应有更多对话和互动：');
      for (final sc in config.supportingCharacters) {
        buf.writeln('- ${sc.description}');
      }
    }
    if (config.effectiveOpeningScene.isNotEmpty) {
      buf.writeln();
      buf.writeln('=== 开场设定 ===');
      buf.writeln('开场场景：${config.effectiveOpeningScene}');
      final opts = config.openingOptions.where((o) => o.isNotEmpty).toList();
      if (opts.isNotEmpty) {
        buf.writeln('开场选项：');
        for (final o in opts) {
          buf.writeln('  - $o');
        }
      }
    }
    return buf.toString();
  }
}
