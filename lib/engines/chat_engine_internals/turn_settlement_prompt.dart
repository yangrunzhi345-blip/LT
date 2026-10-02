import '../../application/adventure/tracked_state_candidate_planner.dart';
import '../../models/turn_settlement.dart';

/// Builds the second, deliberately tiny request of a scene turn.
///
/// The narrative request is a creative, multi-thousand-token job. This one is
/// the opposite: it must be fast and near-deterministic, so it receives only
/// what is needed to settle the turn — the player's action, the **final**
/// narrative (after every length supplement has been merged) and the candidate
/// monitoring definitions that could plausibly move this turn. It never
/// receives the full chat history and it never asks the model to write prose.
///
/// Sparse policy: only the genuinely affected monitors are reported. An absent
/// monitor means "irrelevant this turn", never "the model forgot it". The old
/// protocol that demanded one no-change evaluation per tracked status on every
/// turn is gone.
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
- 禁止创建正文中没有出现的角色。
- 禁止新建、重命名、删除任何检测项目：只能使用候选清单里已经给出的 entity_id 与 monitor_id。
- 禁止输出 Markdown、代码块、解释或任何 JSON 之外的文字。

稀疏检测规则（本协议最重要的规则）：
- 你只需要报告本轮剧情**确实影响**的检测项目。没有明确或高度确定的因果关系，就不要输出该项目。
- 没有输出的检测项目表示「本轮与它无关」，这是合法结果，不是漏检。
- 禁止为了填满数组而制造变化；禁止把全部候选项目都返回一遍。
- 禁止为未变化的项目补写「无变化」占位项。

需要输出的字段（runtime_state_changes）：
- path 一律写成 custom_attributes.<monitor_id>。
- entity_type 与 entity_id 必须与候选清单里的完全一致；世界项目用 entity_type=world。
- 数值项目：可以用 operation=set 直接设定新值，或用 operation=increment 加带符号的变化量（例如 5 或 -8）。
- 文本/枚举/布尔项目：只能 operation=set。
- 候选清单里「当前值=无」的项目，首次必须用 operation=set 初始化，不要把 increment 用在尚未存在的值上。

变化幅度（候选给出范围且用户未定义幅度时）：轻微影响取范围的 1%~5%；明显影响 5%~15%；
重大剧情事件可更大，但必须在 reason 中写明剧情依据，且不得超出候选范围。

输出尽量短：reason 每项最多一句短句；options 每项 12 到 40 个中文字。''';

  List<Map<String, String>> buildMessages({
    required String userInput,
    required String finalNarrative,
    required String scene,
    required int runtimeRevision,
    required List<TrackedStateCandidate> candidates,
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
          candidates: candidates,
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
    required List<TrackedStateCandidate> candidates,
    required List<String> runtimeFacts,
  }) {
    final candidateSection = candidates.isEmpty
        ? '本轮没有任何需要检测的项目：runtime_state_changes 必须返回空数组。'
        : '本轮可能的检测项目（不是必须全部输出，只输出剧情真正影响的项目；'
            '不要输出清单之外的项目）：\n'
            '${candidates.map((candidate) => candidate.promptLine).join('\n')}';

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

$candidateSection

可选的运行期状态变更（runtime_state_changes）：只有正文明确发生了对应事实时才输出；没有依据就返回空数组。
数值变化用 operation=increment 加带符号 value（例如 -20），设为固定值用 operation=set。
允许的 path：候选清单中的 custom_attributes.<monitor_id>，以及 hp、mp、energy、experience、level、base_atk、base_def、base_speed、life_status（仅 alive/dead）、affinity、relationship、faction_id、former_faction_id、goal、controller_id、status。

只输出这个 JSON 对象：
{"schema_version":${TurnSettlement.schemaVersion},"options":["选项1","选项2","选项3"],"runtime_state_changes":[{"entity_type":"character","entity_id":"<候选中的 entity_id>","change_kind":"primary","operation":"increment","path":"custom_attributes.<monitor_id>","value":5,"reason":"一句话理由"}]}''';
  }

  String _trimNarrative(String narrative) {
    final text = narrative.trim();
    if (text.length <= maximumNarrativeChars) return text;
    return '${text.substring(0, _headChars)}\n…（中段省略）…\n'
        '${text.substring(text.length - _tailChars)}';
  }
}
