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
    double? temperatureOverride,
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
      temperature:
          temperatureOverride ?? policy.temperature ?? userParams.temperature,
      topP: userParams.topP,
      frequencyPenalty: userParams.frequencyPenalty,
      presencePenalty: userParams.presencePenalty,
      maxTokens:
          maximumOutputTokens ?? policy.maxTokens ?? userParams.maxTokens,
      enableThinking: thinkingEnabled,
      reasoningEffort: reasoningEffort,
      responseFormat: responseFormat,
    );
  }
}
