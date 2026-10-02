import '../../models/adventure_config.dart';
import '../../models/adventure_response.dart';
import '../../models/adventure_runtime_state.dart';
import '../../models/turn_settlement.dart';
import 'adventure_tracked_state_registry.dart';
import 'tracked_state_candidate_planner.dart';

/// Opening-scene bootstrap for monitored state.
///
/// Runs once, after the adventure is frozen, the opening scene exists and the
/// runtime entities are seeded. It evaluates only the monitors the opening
/// scene gives real evidence for.
///
/// The contract that matters: **absence is legal**. A character who declares
/// 「诅咒侵蚀」 but opens in a quiet tavern must end up with *no* overlay value
/// — not `0`, not `50`. "No evidence" is not "value zero", and the parser below
/// therefore emits a proposal only for monitors the model explicitly reported.
final class TrackedStateBootstrap {
  const TrackedStateBootstrap._();

  static const String systemPrompt = '''
你是开场检测初始化器，不是小说作者。

你的唯一工作：只读给出的「开场场景」，输出一个 JSON 对象，标记开场场景中已经**有明确依据**的检测项目的初始值。

硬性禁止：
- 禁止续写或扩写场景。
- 禁止新建、重命名或删除检测项目；只能使用候选清单里给出的 entity_id 与 monitor_id。
- 禁止把没有依据的项目初始化为 0、50 或任何默认值：没有依据就不要输出该项目。
- 禁止输出 Markdown、代码块或 JSON 之外的文字。

稀疏规则：
- 只有开场场景明确描述了对应事实（例如直接接触污染、正式宣战、明确受伤）时，才输出该项目。
- 没有提到、或只是背景氛围的项目，一律不输出。未输出表示「尚无剧情记录」。

输出格式：{"runtime_state_changes":[{"entity_type":"character","entity_id":"<候选中的 ID>","change_kind":"primary","operation":"set","path":"custom_attributes.<monitor_id>","value":18,"reason":"开场场景中的依据"}],"options":[]}
没有需要初始化的项目时，runtime_state_changes 返回空数组。''';

  static List<Map<String, String>> buildMessages({
    required String openingScene,
    required List<TrackedStateCandidate> candidates,
  }) {
    final scene = openingScene.trim();
    final candidateSection = candidates.isEmpty
        ? '当前没有任何需要初始化的检测项目：runtime_state_changes 返回空数组。'
        : '可能的检测项目（只初始化开场场景确有依据的项目）：\n'
            '${candidates.map((candidate) => candidate.promptLine).join('\n')}';
    return [
      const {'role': 'system', 'content': systemPrompt},
      {
        'role': 'user',
        'content': '开场场景：\n'
            '<<<场景开始>>>\n${scene.isEmpty ? '（空）' : scene}\n<<<场景结束>>>\n\n'
            '$candidateSection\n\n'
            '只输出 JSON：'
            '{"schema_version":${TurnSettlement.schemaVersion},"options":[],'
            '"runtime_state_changes":[]}',
      },
    ];
  }

  /// Parses the model's opening response into validated proposals.
  ///
  /// Every proposal is validated against the frozen [config] through the same
  /// [AdventureTrackedStateRegistry] the runtime validator uses, so the model
  /// cannot create an undefined monitor during bootstrap either.
  static List<RuntimeStateChangeProposal> parse(
    String raw, {
    required AdventureConfig config,
    List<String>? diagnostics,
  }) {
    final sink = diagnostics ?? <String>[];
    final payload = AdventureResponse.parse(raw).payload ??
        AdventureResponse.decodeObject(raw);
    if (payload == null) {
      sink.add('tracked_state_bootstrap:invalid_json');
      return const [];
    }
    final parsed = RuntimeStateChangeProposal.parse(
      payload['runtime_state_changes'],
      diagnostics: sink,
    );
    if (parsed.isEmpty) return const [];
    final registry = AdventureTrackedStateRegistry.fromConfig(config);
    final accepted = <RuntimeStateChangeProposal>[];
    for (final proposal in parsed) {
      final attributeId =
          RuntimeStateChangeProposal.customAttributeIdFromPath(proposal.path);
      if (attributeId != null &&
          registry.find(proposal.entityType, proposal.entityId, attributeId) ==
              null) {
        sink.add('tracked_state_bootstrap:undefined_monitor:$attributeId');
        continue;
      }
      accepted.add(proposal);
    }
    return List.unmodifiable(accepted);
  }

  /// Builds a balanced candidate set for the opening scene.
  static List<TrackedStateCandidate> candidatesFor({
    required AdventureConfig config,
    required Iterable<RuntimeEntityState> runtimeEntities,
    required Set<String> presentEntityIds,
    Map<String, String> entityNames = const {},
  }) {
    final registry = AdventureTrackedStateRegistry.fromConfig(config);
    if (registry.isEmpty) return const [];
    return const TrackedStateCandidatePlanner().plan(
      registry: registry,
      runtimeEntities: runtimeEntities,
      presentEntityIds: presentEntityIds,
      entityNames: entityNames,
    );
  }
}
