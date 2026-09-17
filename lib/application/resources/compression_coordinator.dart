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
/// - A drain only ever touches queued jobs of the resource it was asked about,
///   claims each one atomically, and finishes it under an ownership check, so
///   concurrent workers cannot run or overwrite the same job.
/// - A job that is `running` is owned by exactly one [workerId] under a lease.
///   Recovery reclaims only rows whose lease is gone, which is what keeps a
///   restart from stealing a job another live worker is still running.
/// - A failing job stops at its attempt budget; nothing retries in a loop.
final class CompressionCoordinator {
  CompressionCoordinator({
    required ICompressionJobRepository jobRepository,
    required IResourceTreeRepository treeRepository,
    required IResourceCapacityRepository capacityRepository,
    required CompressionLlmPort llmPort,
    this.thresholds = CompressionThresholds.defaults,
    this.maxJobsPerDrain = 4,
    this.leaseDuration = ResourceLimits.compressionLeaseDuration,
    DateTime Function()? clock,
    String Function()? jobIdFactory,
    String? workerId,
  })  : _jobRepository = jobRepository,
        _treeRepository = treeRepository,
        _capacityRepository = capacityRepository,
        _llmPort = llmPort,
        _clock = clock ?? DateTime.now,
        _jobIdFactory = jobIdFactory,
        workerId = workerId ?? _defaultWorkerId();

  final ICompressionJobRepository _jobRepository;
  final IResourceTreeRepository _treeRepository;
  final IResourceCapacityRepository _capacityRepository;
  final CompressionLlmPort _llmPort;

  final CompressionThresholds thresholds;
  final int maxJobsPerDrain;
  final Duration leaseDuration;
  final DateTime Function() _clock;
  final String Function()? _jobIdFactory;

  /// Identity this coordinator claims jobs with.
  ///
  /// Two coordinators (two processes, or two instances in a test) therefore
  /// have different owners, which is what the ownership CAS compares against.
  final String workerId;

  static int _workerSequence = 0;

  static String _defaultWorkerId() =>
      'wkr_${DateTime.now().microsecondsSinceEpoch}_${_workerSequence++}';

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

  /// Runs up to [maxJobsPerDrain] queued jobs of [resourceId] once.
  ///
  /// [resourceId] scopes the pass: a manual compression of resource A must
  /// never consume resource B's queue or attribute B's results to A. Passing
  /// `null` is the explicit whole-queue form, used only by tests and by a
  /// future global worker.
  ///
  /// Each job is claimed atomically before it is run, so two overlapping drains
  /// can never both execute the same job. A job another worker claimed is
  /// skipped rather than counted, because it is not this pass's work. Stale
  /// leases are reclaimed first, so a crash cannot block a target forever.
  Future<CompressionRunProgress> drain({
    ResourceId? resourceId,
    GenerationTaskHandle? taskHandle,
    int? maxJobs,
    void Function(CompressionRunProgress progress)? onProgress,
  }) async {
    await recoverStaleJobs();

    final limit = maxJobs ?? maxJobsPerDrain;
    final queued = await _jobRepository.findJobsByStatus(
      CompressionJobStatus.queued,
      limit: limit,
      resourceId: resourceId?.value,
    );
    var processed = 0;
    var succeeded = 0;
    var failed = 0;
    for (final job in queued) {
      if (taskHandle?.isCancelled ?? false) break;
      final claimed = await _claim(job);
      if (claimed == null) continue;
      final ok = await _runClaimedJob(claimed, taskHandle: taskHandle);
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

  /// Re-queues a failed job while its attempt budget allows it and no other
  /// active job occupies its target.
  ///
  /// This is the only path back from `failed`; [drain] never does it, which is
  /// what makes the retry budget meaningful. Returns `false` when nothing was
  /// re-queued — the attempt budget is spent, or the target is already busy.
  Future<bool> retryJob(String jobId) =>
      _jobRepository.retryFailedJob(jobId: jobId, updatedAt: _clock());

  /// Reclaims jobs whose worker is gone and returns the reclaim count.
  ///
  /// Safe and cheap to call often: it only touches `running` rows whose lease
  /// has expired (or that carry no lease at all), never a live claim. Called by
  /// every [drain] and by the worker lifecycle at startup.
  Future<int> recoverStaleJobs() =>
      _jobRepository.recoverStaleRunningJobs(now: _clock());

  /// Re-queues every retryable failed job of [resourceId].
  ///
  /// One conflicting job never aborts the batch: each job is attempted on its
  /// own, and a target that already has an active job is reported as skipped
  /// instead of raising a constraint error. The attempt budget stays the hard
  /// stop, so this can never become an unbounded retry loop.
  Future<CompressionRetryOutcome> retryFailedJobs(ResourceId resourceId) async {
    final jobs = await _jobRepository.findJobsForResource(resourceId.value);
    var requeued = 0;
    var skippedActiveTarget = 0;
    var skippedExhausted = 0;
    for (final job in jobs) {
      if (job.status != CompressionJobStatus.failed) continue;
      if (!job.canRetry) {
        skippedExhausted++;
        continue;
      }
      if (await retryJob(job.jobId)) {
        requeued++;
      } else {
        // Classified from the row that was read: the job was retryable, so the
        // atomic statement could only have refused it because the target is
        // already busy.
        skippedActiveTarget++;
      }
    }
    return CompressionRetryOutcome(
      requeued: requeued,
      skippedActiveTarget: skippedActiveTarget,
      skippedExhausted: skippedExhausted,
    );
  }

  Future<List<CompressionJob>> jobsForResource(ResourceId id) =>
      _jobRepository.findJobsForResource(id.value);

  Future<List<CompressionCandidate>> candidatesForResource(ResourceId id) =>
      _jobRepository.findCandidatesForResource(id.value);

  /// Characters a full adoption of this resource's candidates would save.
  Future<int> potentialSavedCharacters(ResourceId id) =>
      _jobRepository.sumSavedCharacters(id.value);

  /// Atomically claims [job] for this worker, or returns null when someone else
  /// already claimed it.
  ///
  /// The returned job carries the ownership and lease the row now holds, so the
  /// rest of the run compares against exactly what was written.
  Future<CompressionJob?> _claim(CompressionJob job) async {
    final claimedAt = _clock();
    final claimed = job.copyWith(
      status: CompressionJobStateMachine.advance(
        job.status,
        CompressionJobStatus.running,
      ),
      attempts: job.attempts + 1,
      errorMessage: '',
      workerId: workerId,
      claimedAt: claimedAt,
      leaseExpiresAt: claimedAt.add(leaseDuration),
      updatedAt: claimedAt,
    );
    final won = await _jobRepository.claimJob(
      jobId: job.jobId,
      workerId: workerId,
      attempts: claimed.attempts,
      claimedAt: claimedAt,
      leaseExpiresAt: claimed.leaseExpiresAt!,
    );
    return won ? claimed : null;
  }

  Future<bool> _runClaimedJob(
    CompressionJob running, {
    GenerationTaskHandle? taskHandle,
  }) async {
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

      // Only a worker that still owns the job may publish its result: if the
      // lease was reclaimed and another worker took over, this run is stale and
      // must not store a candidate the new owner would have to fight with.
      final completed =
          await _finish(running, CompressionJobStatus.succeeded, '');
      if (!completed) return false;

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

  /// Applies a terminal state under an ownership check.
  ///
  /// Returns false when this worker no longer owns the job, which means a
  /// concurrent recovery handed it to someone else and this run's outcome must
  /// be discarded rather than written over the new owner's state.
  Future<bool> _finish(
    CompressionJob job,
    CompressionJobStatus status,
    String errorMessage,
  ) {
    return _jobRepository.completeJob(
      jobId: job.jobId,
      workerId: workerId,
      status: CompressionJobStateMachine.advance(job.status, status),
      updatedAt: _clock(),
      errorMessage: errorMessage,
    );
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

  static String _describeError(Object error) {
    if (error is CompressionParseException) return error.message;
    if (error is ArgumentError) {
      return error.message?.toString() ?? error.toString();
    }
    return error.toString();
  }
}
