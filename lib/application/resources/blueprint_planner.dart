import 'dart:async';

import '../../core/debug/generation_diagnostics.dart';
import '../../domain/resources/blueprint_content_contract_planner.dart';
import '../../domain/resources/resource_blueprint.dart';
import '../../domain/resources/resource_contracts.dart';
import '../../models/llm_task.dart';
import '../../models/model_capabilities.dart';
import '../../services/llm_service.dart';
import '../../services/repositories/resource_tree_repository.dart';
import '../../utils/token_estimator.dart';
import '../llm/llm_gateway.dart';
import 'blueprint_budget_normalizer.dart';
import 'blueprint_parser.dart';
import 'blueprint_prompt_builder.dart';
import 'blueprint_token_budget.dart';
import 'blueprint_validator.dart';
import 'resource_blueprint_repository.dart';
import 'resource_creation_contracts.dart';
import 'resource_creation_pipeline.dart';

/// Function signature for invoking an LLM for structured blueprint planning.
///
/// The injected-completer seam owns its own output sizing: it exists so unit
/// tests can drive the planner without a transport. The production path is the
/// [LlmGateway], which receives the dynamic output budget computed by
/// [BlueprintTokenBudgetPolicy].
typedef BlueprintRawCompleter = Future<String> Function({
  required String systemPrompt,
  required String instruction,
  required LlmTask task,
  GenerationTaskHandle? taskHandle,
});

/// Planning service that coordinates between [ResourceCreationPipeline],
/// LLM completions, [BlueprintValidator] and [IResourceBlueprintRepository].
///
/// Worldview, Character and NPC all flow through this single unified planner.
final class BlueprintPlanner {
  BlueprintPlanner({
    required ResourceCreationPipeline pipeline,
    required IResourceBlueprintRepository blueprintRepository,
    BlueprintRawCompleter? completer,
    LlmGateway? gateway,
    ModelCapabilities Function()? capabilitiesResolver,
  })  : _pipeline = pipeline,
        _blueprintRepository = blueprintRepository,
        _completer = completer,
        _gateway = completer == null ? gateway : null,
        _capabilitiesResolver = capabilitiesResolver ??
            _capabilitiesFromGateway(completer == null ? gateway : null) {
    if (completer == null && gateway == null) {
      throw ArgumentError('BlueprintPlanner 需要提供 completer 或 LlmGateway');
    }
  }

  final ResourceCreationPipeline _pipeline;
  final IResourceBlueprintRepository _blueprintRepository;

  /// Test seam. When non-null the planner delegates completion to it and does
  /// not compute a token budget (the seam, not the transport, sizes output).
  final BlueprintRawCompleter? _completer;

  /// Production boundary. Its model capabilities drive the dynamic budget.
  final LlmGateway? _gateway;

  final ModelCapabilities Function()? _capabilitiesResolver;

  /// Historical planning window, kept as the floor (see the policy's timeout
  /// coordination constants).
  static const Duration defaultPlanningTimeout = Duration(seconds: 60);

  /// At most one bounded full replan after a truncated response. A second
  /// attempt is only allowed when it can actually grant more output than the
  /// first, and never more than the model's own ceiling.
  static const int maxPlanningAttempts = 2;

  /// Internal planning-fold factor for worldview blueprints.
  ///
  /// The model systematically over-generates relative to the planning scale it
  /// is asked for. Worldview plans are therefore *planned* to this fraction of
  /// the user's target so the delivered body still lands inside the elastic
  /// ceiling. This is a planning-time mitigation only: it is applied exactly
  /// once, at the planning entry, and the folded value is never persisted as
  /// (or written back into) the user's real target or elasticity.
  static const double planningFoldFactor = 0.8;

  /// The planning-scale target for [resourceType].
  ///
  /// Worldview folds the user's target by [planningFoldFactor]; every other
  /// resource type plans at the full target, so character, NPC, import and
  /// optimization behaviour is unchanged. `floor` keeps the folded value a
  /// conservative integer that can never exceed the user's own target.
  static int planningTargetFor(
    ResourceType resourceType,
    int userTargetCharacters,
  ) {
    if (resourceType != ResourceType.worldview) return userTargetCharacters;
    return (userTargetCharacters * planningFoldFactor).floor();
  }

  static ModelCapabilities Function()? _capabilitiesFromGateway(
    LlmGateway? gateway,
  ) {
    if (gateway is ModelCapabilityAwareGateway) {
      final aware = gateway as ModelCapabilityAwareGateway;
      return () => aware.activeModelCapabilities;
    }
    return null;
  }

  /// The active model's capabilities, or the conservative registry default when
  /// the gateway cannot report them (a custom endpoint or a test double). An
  /// unidentified model never inherits another provider's ceiling.
  ModelCapabilities _capabilities() =>
      _capabilitiesResolver?.call() ?? ModelCapabilityRegistry.resolve('');

  /// Plans a new [ResourceBlueprint] for a pending creation session.
  Future<ResourceBlueprint> plan({
    required String sessionId,
    GenerationTaskHandle? taskHandle,
    Duration? timeout,
    BlueprintIdPool? idPool,
  }) async {
    final planWatch = Stopwatch()..start();
    GenerationDiagnostics.instance
      ..runtimeHeartbeat('plan.begin')
      ..mark('PLAN[$sessionId] BEGIN', {
        'timeoutMs': timeout?.inMilliseconds,
      });
    _checkCancellation(taskHandle);

    final session = await _pipeline.findSession(sessionId);
    if (session == null) {
      throw ResourceTreeNotFoundException('未找到创建会话：$sessionId');
    }

    if (!session.awaitsPlanning) {
      throw ResourceCreationException(
        '创建会话未处于待规划状态（当前状态: ${session.status.storageValue}）',
      );
    }

    final pool = idPool ?? BlueprintIdPool.createDefault();
    // The user's real target governs the persisted blueprint capacity, the
    // elastic ceiling and the resource capacity checks. The (worldview-folded)
    // planning target only sizes the plan the model is asked for.
    final userTargetCharacters = session.targetCharacters;
    final planningTargetCharacters = planningTargetFor(
      session.resourceType,
      userTargetCharacters,
    );
    final systemPrompt = BlueprintPromptBuilder.buildSystemPrompt(
      resourceType: session.resourceType,
      idPool: pool,
      nominalBudget: planningTargetCharacters,
    );
    final userInstruction = BlueprintPromptBuilder.buildUserInstruction(
      resourceName: session.name,
      resourceType: session.resourceType,
      referenceSource: session.referenceSource,
      relationshipDraft: session.relationshipDraft,
    );
    GenerationDiagnostics.instance.mark('PLAN[$sessionId] PROMPT_BUILT', {
      'systemLength': systemPrompt.length,
      'instructionLength': userInstruction.length,
      'referenceLength': session.referenceSource.body.length,
      'userTargetCharacters': userTargetCharacters,
      'planningTargetCharacters': planningTargetCharacters,
    });

    _checkCancellation(taskHandle);

    final budget = _computeBudget(
      resourceType: session.resourceType,
      targetCharacters: planningTargetCharacters,
      referenceCharacters: session.referenceSource.body.length,
      systemPrompt: systemPrompt,
      instruction: userInstruction,
      sessionId: sessionId,
    );

    _checkCancellation(taskHandle);

    GenerationDiagnostics.instance
      ..runtimeHeartbeat('plan.llmStart')
      ..mark('PLAN[$sessionId] LLM_REQUEST_START');
    final rawOutput = await _requestPlan(
      systemPrompt: systemPrompt,
      instruction: userInstruction,
      taskHandle: taskHandle,
      timeout: timeout,
      sessionId: sessionId,
      budget: budget,
    );
    GenerationDiagnostics.instance
      ..runtimeHeartbeat('plan.llmReturned')
      ..mark('PLAN[$sessionId] LLM_RETURNED', {
        'rawLength': rawOutput.length,
        'elapsedMs': planWatch.elapsedMilliseconds,
      });

    _checkCancellation(taskHandle);

    final blueprintId = 'bp_${session.sessionId}_rev1';
    final parseWatch = Stopwatch()..start();
    final parsedBlueprint = BlueprintParser.parseLlmResponse(
      rawOutput: rawOutput,
      blueprintId: blueprintId,
      sessionId: session.sessionId,
      resourceType: session.resourceType,
      revision: 1,
      fallbackName: session.name,
      targetCapacityOverride: userTargetCharacters,
    );
    parseWatch.stop();

    final normalizeWatch = Stopwatch()..start();
    final normalizedBlueprint =
        BlueprintBudgetNormalizer.normalizeToGenerationTarget(
      parsedBlueprint,
      targetCharacters: planningTargetCharacters,
      targetCapacityOverride: userTargetCharacters,
    );
    // U6: attach the client-authoritative content contract once the final Part
    // lengths are decided. Any contract the model emitted is replaced, so it can
    // never lower a minimum. Parts below the narrative planning floor are left
    // unresolved and block confirm until the plan is reworked.
    final contracted =
        BlueprintContentContractPlanner.apply(normalizedBlueprint);
    BlueprintValidator.validate(
      contracted.blueprint,
      idPool: pool,
      maxBudgetOverride: userTargetCharacters,
    );
    normalizeWatch.stop();
    GenerationDiagnostics.instance
      ..recordDuration('plan.parse', parseWatch.elapsed)
      ..recordDuration('plan.normalizeValidate', normalizeWatch.elapsed)
      ..mark('PLAN[$sessionId] VALIDATED', {
        'sections': contracted.blueprint.sections.length,
        'parts': contracted.blueprint.sections
            .fold<int>(0, (sum, section) => sum + section.parts.length),
        'contractGaps': contracted.gaps.length,
        'parseMs': parseWatch.elapsedMilliseconds,
        'normalizeValidateMs': normalizeWatch.elapsedMilliseconds,
      });

    final saveWatch = Stopwatch()..start();
    await _blueprintRepository.saveBlueprint(contracted.blueprint);
    saveWatch.stop();
    GenerationDiagnostics.instance
      ..recordDuration('plan.saveBlueprint', saveWatch.elapsed)
      ..recordDuration('plan.total', planWatch.elapsed)
      ..mark('PLAN[$sessionId] SAVED', {
        'saveMs': saveWatch.elapsedMilliseconds,
        'totalMs': planWatch.elapsedMilliseconds,
      });
    return contracted.blueprint;
  }

  /// Replans an existing blueprint with user feedback, preserving history as revision N.
  Future<ResourceBlueprint> replan({
    required String sessionId,
    required String userFeedback,
    GenerationTaskHandle? taskHandle,
    Duration? timeout,
    BlueprintIdPool? idPool,
  }) async {
    _checkCancellation(taskHandle);

    final session = await _pipeline.findSession(sessionId);
    if (session == null) {
      throw ResourceTreeNotFoundException('未找到创建会话：$sessionId');
    }

    if (!session.awaitsPlanning) {
      throw ResourceCreationException(
        '创建会话当前状态为 ${session.status.storageValue}，不再允许重新规划',
      );
    }

    final latest = await _blueprintRepository.findLatestBlueprint(sessionId);
    if (latest == null) {
      // If no previous blueprint exists, start initial plan
      return plan(
        sessionId: sessionId,
        taskHandle: taskHandle,
        timeout: timeout,
        idPool: idPool,
      );
    }

    final newRevision = latest.revision + 1;
    final pool = idPool ?? BlueprintIdPool.createDefault();
    final userTargetCharacters = session.targetCharacters;
    final planningTargetCharacters = planningTargetFor(
      session.resourceType,
      userTargetCharacters,
    );

    final systemPrompt = BlueprintPromptBuilder.buildSystemPrompt(
      resourceType: session.resourceType,
      idPool: pool,
      nominalBudget: planningTargetCharacters,
    );
    final userInstruction = BlueprintPromptBuilder.buildReplanInstruction(
      previousBlueprint: latest,
      userFeedback: userFeedback,
      relationshipDraft: session.relationshipDraft,
    );

    _checkCancellation(taskHandle);

    final budget = _computeBudget(
      resourceType: session.resourceType,
      targetCharacters: planningTargetCharacters,
      referenceCharacters: session.referenceSource.body.length,
      systemPrompt: systemPrompt,
      instruction: userInstruction,
      sessionId: sessionId,
    );

    _checkCancellation(taskHandle);

    final rawOutput = await _requestPlan(
      systemPrompt: systemPrompt,
      instruction: userInstruction,
      taskHandle: taskHandle,
      timeout: timeout,
      sessionId: sessionId,
      budget: budget,
    );

    _checkCancellation(taskHandle);

    final blueprintId = 'bp_${session.sessionId}_rev$newRevision';
    final parsedBlueprint = BlueprintParser.parseLlmResponse(
      rawOutput: rawOutput,
      blueprintId: blueprintId,
      sessionId: session.sessionId,
      resourceType: session.resourceType,
      revision: newRevision,
      fallbackName: session.name,
      targetCapacityOverride: userTargetCharacters,
    );

    final normalizedBlueprint =
        BlueprintBudgetNormalizer.normalizeToGenerationTarget(
      parsedBlueprint,
      targetCharacters: planningTargetCharacters,
      targetCapacityOverride: userTargetCharacters,
    );
    // U6: a replan gets a freshly generated contract for the NEW plan; the
    // previous revision's contract never carries over.
    final contracted =
        BlueprintContentContractPlanner.apply(normalizedBlueprint);
    BlueprintValidator.validate(
      contracted.blueprint,
      idPool: pool,
      maxBudgetOverride: userTargetCharacters,
    );

    await _blueprintRepository.saveBlueprint(contracted.blueprint);
    return contracted.blueprint;
  }

  /// Confirms a blueprint, creating formal tree placeholders and generation tasks in a single transaction.
  Future<ResourceBlueprintConfirmResult> confirm({
    required String blueprintId,
    String? nameOverride,
    ResourceId? explicitResourceId,
  }) {
    return _blueprintRepository.confirmBlueprint(
      blueprintId: blueprintId,
      nameOverride: nameOverride,
      explicitResourceId: explicitResourceId,
    );
  }

  Future<ResourceBlueprint?> getBlueprint(String blueprintId) =>
      _blueprintRepository.findBlueprint(blueprintId);

  Future<ResourceBlueprint?> getLatestBlueprint(String sessionId) =>
      _blueprintRepository.findLatestBlueprint(sessionId);

  Future<List<ResourceBlueprint>> getBlueprintHistory(String sessionId) =>
      _blueprintRepository.listBlueprints(sessionId);

  /// Computes the dynamic output budget, or null on the injected-completer seam.
  ///
  /// Throws [BlueprintBudgetInfeasibleException] when the active model cannot
  /// physically emit a complete plan for the target, so an impossible plan is
  /// reported explicitly instead of silently producing a truncated Blueprint.
  BlueprintTokenBudget? _computeBudget({
    required ResourceType resourceType,
    required int targetCharacters,
    required int referenceCharacters,
    required String systemPrompt,
    required String instruction,
    required String sessionId,
  }) {
    if (_gateway == null) return null;
    final capabilities = _capabilities();
    final estimatedInputTokens = TokenEstimator(systemPrompt).tokens +
        TokenEstimator(instruction).tokens;
    final budget = BlueprintTokenBudgetPolicy.compute(
      resourceType: resourceType,
      targetCharacters: targetCharacters,
      referenceCharacters: referenceCharacters,
      estimatedInputTokens: estimatedInputTokens,
      modelMaximumOutputTokens: capabilities.maximumOutputTokens,
      modelContextWindow: capabilities.contextWindow,
    );
    GenerationDiagnostics.instance.mark('PLAN[$sessionId] BUDGET', {
      'model': capabilities.modelId,
      'targetCharacters': targetCharacters,
      'estimatedSections': budget.estimatedSections,
      'estimatedParts': budget.estimatedParts,
      'estimatedOutputTokens': budget.estimatedOutputTokens,
      'safetyReserveTokens': budget.safetyReserveTokens,
      'requestedOutputTokens': budget.requestedOutputTokens,
      'allowedOutputTokens': budget.allowedOutputTokens,
      'modelMaximumOutputTokens': budget.modelMaximumOutputTokens,
      'modelContextWindow': budget.modelContextWindow,
      'estimatedInputTokens': budget.estimatedInputTokens,
      'remainingContextTokens': budget.remainingContextTokens,
      'boundReason': budget.boundReason,
      'feasible': budget.feasible,
    });
    if (!budget.feasible) {
      GenerationDiagnostics.instance.counter('plan.budgetInfeasible');
      throw BlueprintBudgetInfeasibleException(
        '当前模型无法为 $targetCharacters 字的目标生成完整 Blueprint：预计需要 '
        '${budget.requestedOutputTokens} 输出 Token（约 ${budget.estimatedSections} Section / '
        '${budget.estimatedParts} Part），而模型最大输出为 '
        '${budget.modelMaximumOutputTokens}、剩余可用上下文为 '
        '${budget.remainingContextTokens}（受限原因：${budget.boundReason}）。',
      );
    }
    return budget;
  }

  /// Runs the planning request, retrying at most once with a larger budget when
  /// the response was truncated by `finish_reason=length`.
  ///
  /// A truncated response is never salvaged; the retry re-requests the whole
  /// plan with more output tokens, and only when a larger grant is actually
  /// possible (never for a context-bound or already-ceilinged request).
  Future<String> _requestPlan({
    required String systemPrompt,
    required String instruction,
    required GenerationTaskHandle? taskHandle,
    required Duration? timeout,
    required String sessionId,
    required BlueprintTokenBudget? budget,
  }) async {
    var maxOutputTokens = budget?.allowedOutputTokens;
    final maxAttempts = budget == null ? 1 : maxPlanningAttempts;

    for (var attempt = 1;; attempt++) {
      final effectiveTimeout = timeout ??
          (maxOutputTokens == null
              ? defaultPlanningTimeout
              : BlueprintTokenBudgetPolicy.recommendedTimeoutForTokens(
                  maxOutputTokens,
                ));
      try {
        return await _invokeWithTimeout(
          systemPrompt: systemPrompt,
          instruction: instruction,
          taskHandle: taskHandle,
          timeout: effectiveTimeout,
          maximumOutputTokens: maxOutputTokens,
          sessionId: sessionId,
          attempt: attempt,
        );
      } on LLMResponseIncompleteException catch (error) {
        final truncated = error.result.finishReason.isTruncated;
        GenerationDiagnostics.instance.mark('PLAN[$sessionId] INCOMPLETE', {
          'attempt': attempt,
          'finishReason': error.result.finishReason.stableValue,
          'truncated': truncated,
          'completionTokens': error.result.completionTokens,
          'promptTokens': error.result.promptTokens,
          'maxTokens': maxOutputTokens,
        });
        if (budget == null || !truncated || attempt >= maxAttempts) rethrow;
        _checkCancellation(taskHandle);
        final next = BlueprintTokenBudgetPolicy.nextTruncationRetryBudget(
          budget,
          observedCompletionTokens: error.result.completionTokens,
        );
        if (next == null || next <= (maxOutputTokens ?? 0)) rethrow;
        GenerationDiagnostics.instance
          ..counter('plan.truncationRetries')
          ..mark('PLAN[$sessionId] TRUNCATION_RETRY', {
            'attempt': attempt,
            'previousMaxTokens': maxOutputTokens,
            'nextMaxTokens': next,
            'modelMaximumOutputTokens': budget.modelMaximumOutputTokens,
          });
        maxOutputTokens = next;
      }
    }
  }

  Future<String> _invokeWithTimeout({
    required String systemPrompt,
    required String instruction,
    required GenerationTaskHandle? taskHandle,
    required Duration timeout,
    required int? maximumOutputTokens,
    String sessionId = '',
    int attempt = 1,
  }) async {
    final completer = Completer<String>();
    late final GenerationCancellationRegistration? reg;

    // The planner owns cancellation of the request it starts. A timeout that
    // only abandons the Future leaves the transport streaming: the SSE stream
    // keeps consuming the isolate, keeps its upstream subscription alive and
    // keeps holding a GenerationRequestScheduler permit until the transport's
    // own overall deadline (minutes). A caller-supplied handle is respected;
    // otherwise the planner mints one so the timeout can abort the request.
    final ownedHandle =
        taskHandle ?? GenerationTaskHandle(taskId: 'blueprint_planning');
    final ownsHandle = taskHandle == null;

    final timer = Timer(timeout, () {
      if (completer.isCompleted) return;
      GenerationDiagnostics.instance
        ..counter('plan.timeouts')
        ..mark('PLAN[$sessionId] TIMEOUT', {
          'timeoutMs': timeout.inMilliseconds,
          'abortingRequest': ownsHandle,
          'attempt': attempt,
          'maxTokens': maximumOutputTokens,
        });
      if (ownsHandle) unawaited(ownedHandle.cancel());
      completer.completeError(
        TimeoutException('Blueprint 规划超时（${timeout.inSeconds} 秒）'),
      );
    });

    reg = taskHandle?.registerCancel(() {
      if (!completer.isCompleted) {
        completer.completeError(const GenerationCancelledException());
      }
    });

    try {
      final responseFuture = _dispatch(
        systemPrompt: systemPrompt,
        instruction: instruction,
        taskHandle: ownedHandle,
        maximumOutputTokens: maximumOutputTokens,
      );

      responseFuture.then((res) {
        if (!completer.isCompleted) {
          completer.complete(res);
        }
      }).catchError((Object err, StackTrace st) {
        if (!completer.isCompleted) {
          completer.completeError(err, st);
        }
      });

      return await completer.future;
    } finally {
      timer.cancel();
      reg?.dispose();
    }
  }

  Future<String> _dispatch({
    required String systemPrompt,
    required String instruction,
    required GenerationTaskHandle taskHandle,
    required int? maximumOutputTokens,
  }) {
    final completer = _completer;
    if (completer != null) {
      return completer(
        systemPrompt: systemPrompt,
        instruction: instruction,
        task: LlmTask.resourceBlueprintPlanning,
        taskHandle: taskHandle,
      );
    }
    return _gateway!.rawCompletion(
      systemPrompt: systemPrompt,
      instruction: instruction,
      task: LlmTask.resourceBlueprintPlanning,
      taskHandle: taskHandle,
      maximumOutputTokens: maximumOutputTokens!,
    );
  }

  void _checkCancellation(GenerationTaskHandle? taskHandle) {
    if (taskHandle != null && taskHandle.isCancelled) {
      throw const GenerationCancelledException();
    }
  }
}
