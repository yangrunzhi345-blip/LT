import '../../models/turn_settlement.dart';

/// Builds the second, deliberately tiny request of a scene turn.
///
/// The narrative request is a creative, multi-thousand-token job. This one is
/// the opposite: it must be fast and near-deterministic, so it receives only
/// what is needed to settle the turn — the player's action, the **final**
/// narrative (after every length supplement has been merged) and the exact
/// status slots to judge. It never receives the full chat history and it never
/// asks the model to write prose.
final class TurnSettlementPromptBuilder {
  /// Safety valve for the very longest tiers (L5 can reach 10000 Chinese
  /// characters). The middle of a narrative is the least load-bearing part for
  /// settlement, so it is the part that gets dropped.
  static const int maximumNarrativeChars = 16000;
  static const int _headChars = 12000;
  static const int _tailChars = 4000;

  static const String systemPrompt = '''
你是本轮剧情结算器，不是小说作者。

你的唯一工作：只读「本轮已经完成的正文」，做一次快速事实结算，输出一个 JSON 对象。

硬性禁止：
- 禁止续写、扩写、改写或总结剧情正文。
- 禁止添加正文中没有实际发生的新剧情、新事实、新地点。
- 禁止创建正文中没有出现的角色，禁止创建未知状态。
- 禁止修改、猜测或重排下面给出的 character_id / attribute_id / entity_id。
- 禁止为了"看起来有变化"而随机改动数值；同样禁止把没有因果依据的状态一律判成没变化。
- 禁止输出 Markdown、代码块、解释或任何 JSON 之外的文字。

changed=true 的判定标准（满足任意一条即可）：
1. 正文直接明确描述该状态发生变化（例如"体力迅速流失""好感度上升了一截"）。
2. 正文发生了与该状态具有高度确定、即时、自然因果关系的事件。典型因果：
   - 体力/耐力：奔跑、战斗、负重、长距离移动、严重受伤 → 保守下降；休息、睡眠、治疗、进食（且检测规则允许）→ 保守恢复。
   - 好感度：明显帮助、保护、背叛、冲突、重要互动 → 小幅变化。
   - SAN/理智：遭遇恐怖、精神冲击、异常认知 → 变化。
3. 用户在「检测规则」里写明的触发条件被本轮事件覆盖。
普通交谈、观察环境等无关行动 → changed=false。

变化幅度（0~100 且用户未定义幅度时）：轻微影响 ±1~5；明显影响 ±5~15；
重大剧情事件允许更大，但必须在 reason 中写明剧情依据。结果不得超出该状态的上下限。

输出尽量短：reason 每项最多一句短句；options 每项 12 到 40 个中文字。''';

  List<Map<String, String>> buildMessages({
    required String userInput,
    required String finalNarrative,
    required String scene,
    required int runtimeRevision,
    required List<TurnSettlementTrackedStatus> trackedStatuses,
    required List<String> runtimeFacts,
  }) {
    return [
      const {'role': 'system', 'content': systemPrompt},
      {
        'role': 'user',
        'content': _userPrompt(
          userInput: userInput,
          finalNarrative: finalNarrative,
          scene: scene,
          runtimeRevision: runtimeRevision,
          trackedStatuses: trackedStatuses,
          runtimeFacts: runtimeFacts,
        )
      },
    ];
  }

  String _userPrompt({
    required String userInput,
    required String finalNarrative,
    required String scene,
    required int runtimeRevision,
    required List<TurnSettlementTrackedStatus> trackedStatuses,
    required List<String> runtimeFacts,
  }) {
    final statusSection = trackedStatuses.isEmpty
        ? '当前没有需要追踪的自定义状态：custom_status_evaluations 返回空数组。'
        : '必须逐项评估的状态（每一项都给一条 custom_status_evaluations，'
            'changed=false 也要给并写 reason；「检测规则」是用户为该状态定义的判定依据，'
            '本轮事件命中规则时必须如实结算）：\n'
            '${trackedStatuses.map((status) => status.toPromptLine()).join('\n')}';

    final runtimeSection = runtimeFacts.isEmpty
        ? ''
        : '\n\n运行期已知事实（仅供参考，不要输出）：\n'
            '${runtimeFacts.map((fact) => '- $fact').join('\n')}';

    return '''
本轮玩家行动：$userInput
当前场景：${scene.trim().isEmpty ? '未知' : scene.trim()}
运行期版本号（仅供核对，禁止输出）：r$runtimeRevision$runtimeSection

以下是本轮**已经完成**的正文，只根据它结算：
<<<正文开始>>>
${_trimNarrative(finalNarrative)}
<<<正文结束>>>

$statusSection

可选的运行期状态变更（runtime_state_changes）：只有正文明确发生了对应事实时才输出；数值变化用 operation=increment 加带符号 value（例如 -20），设为固定值用 operation=set；没有依据就返回空数组。
允许的 path：hp、mp、energy、experience、level、base_atk、base_def、base_speed、life_status（仅 alive/dead）、affinity、relationship、faction_id、former_faction_id、goal、controller_id、status。

只输出这个 JSON 对象：
{"schema_version":${TurnSettlement.schemaVersion},"options":["选项1","选项2","选项3"],"custom_status_evaluations":[{"character_id":"<上面给出的 ID>","attribute_id":"<上面给出的 ID>","changed":true,"operation":"delta","value":5,"reason":"一句话理由"}],"runtime_state_changes":[{"entity_type":"character","entity_id":"<上面给出的 ID>","change_kind":"primary","operation":"increment","path":"hp","value":-20,"reason":"一句话理由"}]}''';
  }

  String _trimNarrative(String narrative) {
    final text = narrative.trim();
    if (text.length <= maximumNarrativeChars) return text;
    return '${text.substring(0, _headChars)}\n…（中段省略）…\n'
        '${text.substring(text.length - _tailChars)}';
  }
}
