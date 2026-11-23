import '../models/completion_params.dart';
import '../models/llm_task.dart';
import '../models/model_capabilities.dart';

/// Static Task → Policy table.
///
/// Helper tasks never think; interactive/deep tasks follow the user's toggle.
/// Only pure structured tasks request JSON output, and only when the model
/// supports it.
class LlmTaskPolicyTable {
  LlmTaskPolicyTable._();

  static const Map<LlmTask, LlmTaskPolicy> _table = {
    LlmTask.adventureNarrative: LlmTaskPolicy(
      task: LlmTask.adventureNarrative,
      thinking: ThinkingPolicy.followUserSetting,
    ),
    // 冒险规划目前只有「生成一份结构化冒险配置」这一个消费者，它必须拿到
    // JSON 对象。此前靠 prompt 里是否出现 json 字样临时开启 response_format，
    // 去掉该启发式后改为在任务策略里显式声明，避免调用方静默失去 JSON 约束。
    LlmTask.adventurePlanning: LlmTaskPolicy(
      task: LlmTask.adventurePlanning,
      thinking: ThinkingPolicy.followUserSetting,
      reasoningEffort: 'high',
      preferJsonOutput: true,
    ),
    LlmTask.worldviewFast: LlmTaskPolicy(
      task: LlmTask.worldviewFast,
      thinking: ThinkingPolicy.followUserSetting,
      reasoningEffort: 'low',
      preferJsonOutput: true,
    ),
    LlmTask.worldviewDeep: LlmTaskPolicy(
      task: LlmTask.worldviewDeep,
      thinking: ThinkingPolicy.followUserSetting,
      reasoningEffort: 'high',
      preferJsonOutput: true,
    ),
    LlmTask.characterFast: LlmTaskPolicy(
      task: LlmTask.characterFast,
      thinking: ThinkingPolicy.followUserSetting,
      reasoningEffort: 'low',
      preferJsonOutput: true,
    ),
    LlmTask.characterDeep: LlmTaskPolicy(
      task: LlmTask.characterDeep,
      thinking: ThinkingPolicy.followUserSetting,
      reasoningEffort: 'high',
      preferJsonOutput: true,
    ),
    LlmTask.importExtraction: LlmTaskPolicy(
      task: LlmTask.importExtraction,
      thinking: ThinkingPolicy.disabled,
      reasoningEffort: 'low',
      preferJsonOutput: true,
    ),
    LlmTask.structuredExtraction: LlmTaskPolicy(
      task: LlmTask.structuredExtraction,
      thinking: ThinkingPolicy.disabled,
      reasoningEffort: 'low',
      preferJsonOutput: true,
    ),
    LlmTask.summary: LlmTaskPolicy(
      task: LlmTask.summary,
      thinking: ThinkingPolicy.disabled,
      reasoningEffort: 'low',
    ),
    LlmTask.translation: LlmTaskPolicy(
      task: LlmTask.translation,
      thinking: ThinkingPolicy.disabled,
      reasoningEffort: 'low',
    ),
    LlmTask.visionExtraction: LlmTaskPolicy(
      task: LlmTask.visionExtraction,
      thinking: ThinkingPolicy.disabled,
      reasoningEffort: 'low',
      // Dense text (screenshots, character-card images) needs full resolution.
      visionDetail: 'high',
    ),
    LlmTask.runtimeStateAnalysis: LlmTaskPolicy(
      task: LlmTask.runtimeStateAnalysis,
      thinking: ThinkingPolicy.disabled,
      reasoningEffort: 'low',
      preferJsonOutput: true,
    ),
    LlmTask.narrativeSupplement: LlmTaskPolicy(
      task: LlmTask.narrativeSupplement,
      thinking: ThinkingPolicy.disabled,
      reasoningEffort: 'low',
    ),
    LlmTask.turnSettlement: LlmTaskPolicy(
      task: LlmTask.turnSettlement,
      // Settlement runs after the player can already read the narrative, so it
      // is pure latency: no thinking, low reasoning, near-deterministic
      // sampling and a bounded output that must never inherit the narrative's
      // multi-thousand token budget.
      thinking: ThinkingPolicy.disabled,
      reasoningEffort: 'low',
      preferJsonOutput: true,
      maxTokens: 1024,
      temperature: 0.15,
    ),
  };

  static LlmTaskPolicy policyFor(LlmTask task) => _table[task]!;
}

/// Turns a [LlmTask] plus the active model capability into [CompletionParams].
///
/// Never mutates [userParams]; always builds a fresh value so persisted user
/// settings are never clobbered by a task override.
class LlmTaskResolver {
  const LlmTaskResolver();

  CompletionParams resolve({
    required LlmTask task,
    required ModelCapabilities capabilities,
    CompletionParams userParams = const CompletionParams(),
    int? maximumOutputTokens,
    bool? forceJson,
  }) {
    final policy = LlmTaskPolicyTable.policyFor(task);

    final thinkingEnabled = switch (policy.thinking) {
      ThinkingPolicy.disabled => false,
      ThinkingPolicy.enabled => capabilities.supportsThinking,
      ThinkingPolicy.followUserSetting =>
        userParams.enableThinking && capabilities.supportsThinking,
    };

    final wantsJson = forceJson ?? policy.preferJsonOutput;
    final responseFormat = wantsJson && capabilities.supportsJsonOutput
        ? const {'type': 'json_object'}
        : null;

    final reasoningEffort = policy.thinking == ThinkingPolicy.followUserSetting
        ? userParams.reasoningEffort
        : policy.reasoningEffort;

    return CompletionParams(
      temperature: policy.temperature ?? userParams.temperature,
      topP: userParams.topP,
      frequencyPenalty: userParams.frequencyPenalty,
      presencePenalty: userParams.presencePenalty,
      maxTokens:
          maximumOutputTokens ?? policy.maxTokens ?? userParams.maxTokens,
      enableThinking: thinkingEnabled,
      reasoningEffort: reasoningEffort,
      responseFormat: responseFormat,
      diagnosticTask: task,
    );
  }
}
