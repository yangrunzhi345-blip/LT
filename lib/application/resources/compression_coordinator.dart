import '../../domain/resources/resource_capacity.dart';
import '../../domain/resources/resource_compression.dart';
import '../../domain/resources/resource_contracts.dart';
import '../../domain/resources/resource_limits.dart';
import '../../models/generation_task_handle.dart';
import '../../models/llm_task.dart';
import '../../services/repositories/resource_tree_repository.dart';
import '../llm/llm_gateway.dart';
import 'compression_job_repository.dart';
import 'compression_prompt_builder.dart';
import 'compression_response_parser.dart';
import 'resource_capacity_repository.dart';

/// Narrow LLM boundary for compression.
///
/// Keeping this to one method means the coordinator never depends on the whole
/// gateway surface, and tests drive the real parsing / validation path with a
/// tiny fake instead of re-implementing [LlmGateway].
abstract interface class CompressionLlmPort {
  Future<String> compress({
    required String systemPrompt,
    required String instruction,
    GenerationTaskHandle? taskHandle,
  });
}

/// Production adapter over the shared LLM gateway.
final class LlmGatewayCompressionAdapter implements CompressionLlmPort {
  LlmGatewayCompressionAdapter(this._gateway);

  final LlmGateway _gateway;

  @override
  Future<String> compress({
    required String systemPrompt,
    required String instruction,
    GenerationTaskHandle? taskHandle,
  }) {
    return _gateway.rawCompletion(
      systemPrompt: systemPrompt,
      instruction: instruction,
      task: LlmTask.resourceCompression,
      taskHandle: taskHandle,
    );
  }
}

/// Progress report for one drain pass.
final class CompressionRunProgress {
  const CompressionRunProgress({
    required this.totalJobs,
    required this.processedJobs,
    required this.succeededJobs,
    required this.failedJobs,
  });

  final int totalJobs;
  final int processedJobs;
  final int succeededJobs;
  final int failedJobs;

  double get fraction =>
      totalJobs == 0 ? 1 : (processedJobs / totalJobs).clamp(0.0, 1.0);
}

/// Queues and runs semantic compression jobs.
///
/// Boundaries that make this phase safe:
/// - It only ever **writes candidates**. Nothing here updates
///   `resource_parts.content`, so a completed run cannot change any resource
///   head; publishing belongs to Phase 9.
/// - Queueing never blocks on the model. [enqueueForResource] only measures and
///   records jobs, so leaving the editor does not need to wait for a request.
/// - De-duplication is by (resource, scope, target, source version), so the
///   same revision is never compressed twice.
/// - A failing job stops at its attempt budget; nothing retries in a loop.
final class CompressionCoordinator {
  CompressionCoordinator({
    required ICompressionJobRepository jobRepository,
    required IResourceTreeRepository treeRepository,
    required IResourceCapacityRepository capacityRepository,
    required CompressionLlmPort llmPort,
    this.thresholds = CompressionThresholds.defaults,
    this.maxJobsPerDrain = 4,
    DateTime Function()? clock,
    String Function()? jobIdFactory,
  })  : _jobRepository = jobRepository,
        _treeRepository = treeRepository,
        _capacityRepository = capacityRepository,
        _llmPort = llmPort,
        _clock = clock ?? DateTime.now,
        _jobIdFactory = jobIdFactory;

  final ICompressionJobRepository _jobRepository;
  final IResourceTreeRepository _treeRepository;
  final IResourceCapacityRepository _capacityRepository;
  final CompressionLlmPort _llmPort;

  final CompressionThresholds thresholds;
  final int maxJobsPerDrain;
  final DateTime Function() _clock;
  final String Function()? _jobIdFactory;

  /// Queues jobs for every section of [resourceId] that is worth compressing.
  ///
  /// Returns immediately after queueing; no model call happens here. A section
  /// that fits the bounded input window becomes one section-scope job, and a
  /// larger one is split into per-Part jobs so no single request can carry an
  /// unbounded window.
  Future<List<CompressionJob>> enqueueForResource(
    ResourceId resourceId, {
    bool force = false,
  }) async {
    final sections = await _treeRepository.readSections(resourceId);
    if (sections.isEmpty) return const <CompressionJob>[];

    final measurements = await _capacityRepository.measureSections(resourceId);
    final byId = <String, SectionCapacitySnapshot>{
      for (final snapshot in measurements) snapshot.sectionId.value: snapshot,
    };
    final states = await _treeRepository.readNodeStates(
      sections.map((section) => section.id),
    );
    final stateById = <String, ResourceNodeState>{
      for (final state in states) state.id.value: state,
    };

    final jobs = <CompressionJob>[];
    for (final section in sections) {
      final snapshot = byId[section.id.value];
      if (snapshot == null || !snapshot.isComplete) continue;
      if (!force && snapshot.characters < thresholds.minNodeCharacters) {
        continue;
      }

      final sectionState = stateById[section.id.value];
      if (sectionState == null || sectionState.isDeleted) continue;

      if (snapshot.characters <= ResourceLimits.maxCompressionInputCharacters) {
        jobs.add(await _enqueue(
          resourceId: resourceId,
          scope: CompressionScope.section,
          targetNodeId: section.id.value,
          sourceToken: sectionState.updatedAt,
        ));
        continue;
      }

      final parts = await _treeRepository.readParts(section.id);
      final partStates = await _treeRepository.readNodeStates(
        parts.map((part) => part.id),
      );
      final partStateById = <String, ResourceNodeState>{
        for (final state in partStates) state.id.value: state,
      };
      for (final part in parts) {
        if (part.content.trim().isEmpty) continue;
        if (!force && part.content.length < thresholds.minNodeCharacters) {
          continue;
        }
        final partState = partStateById[part.id.value];
        if (partState == null || partState.isDeleted) continue;
        jobs.add(await _enqueue(
          resourceId: resourceId,
          scope: CompressionScope.part,
          targetNodeId: part.id.value,
          parentNodeId: section.id.value,
          sourceToken: partState.updatedAt,
        ));
      }
    }
    return jobs;
  }

  /// Queues exactly one node, used by the Studio's manual compression entry.
  Future<CompressionJob?> enqueueNode({
    required ResourceId resourceId,
    required CompressionScope scope,
    required String targetNodeId,
    String parentNodeId = '',
  }) async {
    final state = await _treeRepository.readNodeState(
      scope == CompressionScope.section
          ? SectionId(targetNodeId)
          : PartId(targetNodeId),
    );
    if (state == null || state.isDeleted) return null;
    return _enqueue(
      resourceId: resourceId,
      scope: scope,
      targetNodeId: targetNodeId,
      parentNodeId: parentNodeId,
      sourceToken: state.updatedAt,
    );
  }

  /// Runs up to [maxJobsPerDrain] queued jobs once.
  ///
  /// A job failure is recorded and the pass continues with the next job. No
  /// job is retried inside a pass, so a failing model cannot spin.
  Future<CompressionRunProgress> drain({
    GenerationTaskHandle? taskHandle,
    int? maxJobs,
    void Function(CompressionRunProgress progress)? onProgress,
  }) async {
    // The first drain of a process is the startup recovery point: nothing of
    // ours can be in `running` yet, so reclaiming orphans here cannot steal a
    // live job. The latch keeps later drains from repeating it.
    if (!_recoveredThisInstance) {
      await recoverInterruptedJobs();
    }

    final limit = maxJobs ?? maxJobsPerDrain;
    final queued = await _jobRepository.findJobsByStatus(
      CompressionJobStatus.queued,
      limit: limit,
    );
    var processed = 0;
    var succeeded = 0;
    var failed = 0;
    for (final job in queued) {
      if (taskHandle?.isCancelled ?? false) break;
      final ok = await _runJob(job, taskHandle: taskHandle);
      processed++;
      if (ok) {
        succeeded++;
      } else {
        failed++;
      }
      onProgress?.call(CompressionRunProgress(
        totalJobs: queued.length,
        processedJobs: processed,
        succeededJobs: succeeded,
        failedJobs: failed,
      ));
    }
    return CompressionRunProgress(
      totalJobs: queued.length,
      processedJobs: processed,
      succeededJobs: succeeded,
      failedJobs: failed,
    );
  }

  /// Re-queues a failed job while its attempt budget allows it.
  ///
  /// This is the only path back from `failed`; [drain] never does it, which is
  /// what makes the retry budget meaningful.
  Future<bool> retryJob(String jobId) async {
    final job = await _jobRepository.findJob(jobId);
    if (job == null || !job.canRetry) return false;
    await _jobRepository.updateJob(job.copyWith(
      status: CompressionJobStateMachine.advance(
        job.status,
        CompressionJobStatus.queued,
      ),
      errorMessage: '',
      updatedAt: _clock(),
    ));
    return true;
  }

  /// Releases jobs orphaned by a previous process and returns the reclaim count.
  ///
  /// Called automatically by the first [drain] of this coordinator instance and
  /// also exposed for an explicit startup hook. Idempotent.
  Future<int> recoverInterruptedJobs() async {
    final reclaimed = await _jobRepository.recoverInterruptedJobs();
    _recoveredThisInstance = true;
    return reclaimed;
  }

  /// Re-queues every retryable failed job of [resourceId].
  ///
  /// The attempt budget is the only rule: [retryJob] refuses a job that already
  /// spent `maxAttempts`, so this can never become an unbounded retry loop.
  /// Returns how many jobs were put back on the queue.
  Future<int> retryFailedJobs(ResourceId resourceId) async {
    final jobs = await _jobRepository.findJobsForResource(resourceId.value);
    var requeued = 0;
    for (final job in jobs) {
      if (job.status != CompressionJobStatus.failed || !job.canRetry) continue;
      if (await retryJob(job.jobId)) requeued++;
    }
    return requeued;
  }

  Future<List<CompressionJob>> jobsForResource(ResourceId id) =>
      _jobRepository.findJobsForResource(id.value);

  Future<List<CompressionCandidate>> candidatesForResource(ResourceId id) =>
      _jobRepository.findCandidatesForResource(id.value);

  /// Characters a full adoption of this resource's candidates would save.
  Future<int> potentialSavedCharacters(ResourceId id) =>
      _jobRepository.sumSavedCharacters(id.value);

  Future<bool> _runJob(
    CompressionJob job, {
    GenerationTaskHandle? taskHandle,
  }) async {
    final running = job.copyWith(
      status: CompressionJobStateMachine.advance(
        job.status,
        CompressionJobStatus.running,
      ),
      attempts: job.attempts + 1,
      errorMessage: '',
      updatedAt: _clock(),
    );
    await _jobRepository.updateJob(running);

    if (taskHandle?.isCancelled ?? false) {
      await _finish(running, CompressionJobStatus.cancelled, '');
      return false;
    }

    try {
      final request = await _buildRequest(running);
      if (request == null) {
        await _finish(
          running,
          CompressionJobStatus.cancelled,
          '目标节点没有可压缩的正文',
        );
        return false;
      }

      final raw = await _llmPort.compress(
        systemPrompt: CompressionPromptBuilder.buildSystemPrompt(request),
        instruction: CompressionPromptBuilder.buildInstruction(request),
        taskHandle: taskHandle,
      );

      if (taskHandle?.isCancelled ?? false) {
        await _finish(running, CompressionJobStatus.cancelled, '已取消');
        return false;
      }

      final parsed = CompressionResponseParser.parse(raw);
      final originalContent =
          request.nodes.map((node) => node.content.trim()).join('\n\n');
      final validation = CompressionValidator.validate(
        originalContent: originalContent,
        compressedContent: parsed.compressedContent,
        retention: parsed.retention,
        targetCharacters: request.targetCharacters,
        requiredTerms: _requiredTerms(request, originalContent),
      );

      if (!validation.isValid) {
        await _finish(
          running,
          CompressionJobStatus.failed,
          '压缩校验未通过：${validation.message}',
        );
        return false;
      }

      final candidate = CompressionCandidate(
        candidateId: 'cmpc_${running.jobId}',
        jobId: running.jobId,
        resourceId: running.resourceId,
        scope: running.scope,
        targetNodeId: running.targetNodeId,
        originalCharacters: originalContent.length,
        compressedCharacters: parsed.compressedContent.length,
        compressedContent: parsed.compressedContent,
        retention: parsed.retention,
        isValidated: true,
        createdAt: _clock(),
      );
      await _jobRepository.insertCandidate(candidate);
      await _finish(running, CompressionJobStatus.succeeded, '');
      return true;
    } catch (error) {
      await _finish(
        running,
        CompressionJobStatus.failed,
        _describeError(error),
      );
      return false;
    }
  }

  Future<void> _finish(
    CompressionJob job,
    CompressionJobStatus status,
    String errorMessage,
  ) async {
    await _jobRepository.updateJob(job.copyWith(
      status: CompressionJobStateMachine.advance(job.status, status),
      errorMessage: errorMessage,
      updatedAt: _clock(),
    ));
  }

  /// Builds the bounded request for one job, or null when there is nothing to
  /// compress. Reads at most one section's Parts, never the whole tree.
  Future<CompressionRequest?> _buildRequest(CompressionJob job) async {
    final resource = await _treeRepository.findResource(job.resourceId);
    if (resource == null) return null;

    final nodes = <CompressionSourceNode>[];

    if (job.scope == CompressionScope.section) {
      final section = _findSection(
        await _treeRepository.readSections(job.resourceId),
        job.targetNodeId,
      );
      if (section == null) return null;
      for (final part in await _treeRepository.readParts(section.id)) {
        if (part.content.trim().isEmpty) continue;
        nodes.add(CompressionSourceNode(
          nodeId: part.id.value,
          title: part.title,
          content: part.content,
        ));
      }
    } else {
      final sectionId = job.parentNodeId;
      if (sectionId.isEmpty) return null;
      for (final part
          in await _treeRepository.readParts(SectionId(sectionId))) {
        if (part.id.value != job.targetNodeId) continue;
        if (part.content.trim().isEmpty) return null;
        nodes.add(CompressionSourceNode(
          nodeId: part.id.value,
          title: part.title,
          content: part.content,
        ));
      }
    }

    if (nodes.isEmpty) return null;

    final originalCharacters =
        nodes.fold<int>(0, (sum, node) => sum + node.content.length);
    final request = CompressionRequest(
      jobId: job.jobId,
      resourceId: job.resourceId,
      resourceType: resource.type,
      scope: job.scope,
      targetNodeId: job.targetNodeId,
      resourceName: resource.name,
      resourceSummary: resource.summary,
      nodes: nodes,
      targetCharacters: CompressionBudget.nodeTargetCharacters(
        originalCharacters,
      ),
    );
    CompressionPromptBuilder.assertWithinInputBudget(request);
    return request;
  }

  static ResourceSection? _findSection(
    List<ResourceSection> sections,
    String sectionId,
  ) {
    for (final section in sections) {
      if (section.id.value == sectionId) return section;
    }
    return null;
  }

  /// Hard retention terms: names the original actually contained must still be
  /// present. Terms absent from the original are not required (the compressed
  /// text is not expected to invent them), which keeps the check precise.
  static List<String> _requiredTerms(
    CompressionRequest request,
    String originalContent,
  ) {
    final candidates = <String>[
      request.resourceName,
      ...request.nodes.map((node) => node.title),
    ];
    return candidates
        .map((term) => term.trim())
        .where((term) => term.isNotEmpty && originalContent.contains(term))
        .toSet()
        .toList();
  }

  Future<CompressionJob> _enqueue({
    required ResourceId resourceId,
    required CompressionScope scope,
    required String targetNodeId,
    required String sourceToken,
    String parentNodeId = '',
  }) async {
    final existing = await _jobRepository.findByVersion(
      resourceId: resourceId.value,
      scope: scope,
      targetNodeId: targetNodeId,
      sourceToken: sourceToken,
    );
    if (existing != null) return existing;

    final active = await _jobRepository.findActiveForTarget(
      resourceId: resourceId.value,
      targetNodeId: targetNodeId,
    );
    if (active != null) return active;

    final job = CompressionJob(
      jobId: _nextJobId(),
      resourceId: resourceId,
      scope: scope,
      targetNodeId: targetNodeId,
      parentNodeId: parentNodeId,
      sourceToken: sourceToken,
      createdAt: _clock(),
      updatedAt: _clock(),
    );
    return _jobRepository.insertJob(job);
  }

  String _nextJobId() {
    final custom = _jobIdFactory;
    if (custom != null) return custom();
    return 'cmp_${_clock().microsecondsSinceEpoch}_${_sequence++}';
  }

  int _sequence = 0;

  /// True once this instance has reclaimed orphaned jobs, so [drain] only pays
  /// for recovery at process start rather than on every pass.
  bool _recoveredThisInstance = false;

  static String _describeError(Object error) {
    if (error is CompressionParseException) return error.message;
    if (error is ArgumentError) {
      return error.message?.toString() ?? error.toString();
    }
    return error.toString();
  }
}
