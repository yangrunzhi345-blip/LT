import 'dart:async';

import '../../domain/resources/resource_blueprint.dart';
import '../../domain/resources/resource_contracts.dart';
import '../../models/llm_task.dart';
import '../../services/llm_service.dart';
import '../../services/repositories/resource_tree_repository.dart';
import '../llm/llm_gateway.dart';
import 'blueprint_parser.dart';
import 'blueprint_prompt_builder.dart';
import 'blueprint_validator.dart';
import 'resource_blueprint_repository.dart';
import 'resource_creation_contracts.dart';
import 'resource_creation_pipeline.dart';

/// Function signature for invoking an LLM for structured blueprint planning.
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
  })  : _pipeline = pipeline,
        _blueprintRepository = blueprintRepository,
        _completer = completer ?? _createGatewayCompleter(gateway);

  final ResourceCreationPipeline _pipeline;
  final IResourceBlueprintRepository _blueprintRepository;
  final BlueprintRawCompleter _completer;

  static BlueprintRawCompleter _createGatewayCompleter(LlmGateway? gateway) {
    if (gateway == null) {
      throw ArgumentError('BlueprintPlanner 需要提供 completer 或 LlmGateway');
    }
    return ({
      required String systemPrompt,
      required String instruction,
      required LlmTask task,
      GenerationTaskHandle? taskHandle,
    }) {
      return gateway.rawCompletion(
        systemPrompt: systemPrompt,
        instruction: instruction,
        task: task,
        taskHandle: taskHandle,
      );
    };
  }

  /// Plans a new [ResourceBlueprint] for a pending creation session.
  Future<ResourceBlueprint> plan({
    required String sessionId,
    GenerationTaskHandle? taskHandle,
    Duration timeout = const Duration(seconds: 60),
    BlueprintIdPool? idPool,
  }) async {
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
    final systemPrompt = BlueprintPromptBuilder.buildSystemPrompt(
      resourceType: session.resourceType,
      idPool: pool,
    );
    final userInstruction = BlueprintPromptBuilder.buildUserInstruction(
      resourceName: session.name,
      resourceType: session.resourceType,
      referenceSource: session.referenceSource,
    );

    _checkCancellation(taskHandle);

    final rawOutput = await _invokeWithTimeout(
      systemPrompt: systemPrompt,
      instruction: userInstruction,
      taskHandle: taskHandle,
      timeout: timeout,
    );

    _checkCancellation(taskHandle);

    final blueprintId = 'bp_${session.sessionId}_rev1';
    final parsedBlueprint = BlueprintParser.parseLlmResponse(
      rawOutput: rawOutput,
      blueprintId: blueprintId,
      sessionId: session.sessionId,
      resourceType: session.resourceType,
      revision: 1,
      fallbackName: session.name,
    );

    BlueprintValidator.validate(parsedBlueprint, idPool: pool);

    await _blueprintRepository.saveBlueprint(parsedBlueprint);
    return parsedBlueprint;
  }

  /// Replans an existing blueprint with user feedback, preserving history as revision N.
  Future<ResourceBlueprint> replan({
    required String sessionId,
    required String userFeedback,
    GenerationTaskHandle? taskHandle,
    Duration timeout = const Duration(seconds: 60),
    BlueprintIdPool? idPool,
  }) async {
    _checkCancellation(taskHandle);

    final session = await _pipeline.findSession(sessionId);
    if (session == null) {
      throw ResourceTreeNotFoundException('未找到创建会话：$sessionId');
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

    final systemPrompt = BlueprintPromptBuilder.buildSystemPrompt(
      resourceType: session.resourceType,
      idPool: pool,
    );
    final userInstruction = BlueprintPromptBuilder.buildReplanInstruction(
      previousBlueprint: latest,
      userFeedback: userFeedback,
    );

    _checkCancellation(taskHandle);

    final rawOutput = await _invokeWithTimeout(
      systemPrompt: systemPrompt,
      instruction: userInstruction,
      taskHandle: taskHandle,
      timeout: timeout,
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
    );

    BlueprintValidator.validate(parsedBlueprint, idPool: pool);

    await _blueprintRepository.saveBlueprint(parsedBlueprint);
    return parsedBlueprint;
  }

  /// Confirms a blueprint, creating formal tree placeholders and generation tasks in a single transaction.
  Future<ResourceBlueprintConfirmResult> confirm({
    required String blueprintId,
    String? nameOverride,
    ResourceId? explicitResourceId,
  }) async {
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

  Future<String> _invokeWithTimeout({
    required String systemPrompt,
    required String instruction,
    GenerationTaskHandle? taskHandle,
    required Duration timeout,
  }) async {
    final completer = Completer<String>();
    late final GenerationCancellationRegistration? reg;

    final timer = Timer(timeout, () {
      if (!completer.isCompleted) {
        completer.completeError(
          TimeoutException('Blueprint 规划超时（${timeout.inSeconds} 秒）'),
        );
      }
    });

    reg = taskHandle?.registerCancel(() {
      if (!completer.isCompleted) {
        completer.completeError(const GenerationCancelledException());
      }
    });

    try {
      final responseFuture = _completer(
        systemPrompt: systemPrompt,
        instruction: instruction,
        task: LlmTask.resourceBlueprintPlanning,
        taskHandle: taskHandle,
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

  void _checkCancellation(GenerationTaskHandle? taskHandle) {
    if (taskHandle != null && taskHandle.isCancelled) {
      throw const GenerationCancelledException();
    }
  }
}
