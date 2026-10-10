import 'package:sqflite/sqflite.dart';
import 'package:flutter/foundation.dart';

import '../../domain/resources/resource_capacity.dart';
import '../../domain/resources/resource_limits.dart';
import '../../domain/resources/resource_compression.dart';
import 'resource_compression_publisher.dart';
import '../../domain/resources/resource_contracts.dart';
import '../../domain/resources/resource_revision.dart';
import '../../domain/errors/diagnostic_envelope.dart';
import 'assembly_readiness_repository.dart';
import 'compression_coordinator.dart';
import 'compression_worker.dart';
import 'resource_assembly_builder.dart';
import 'resource_revision_repository.dart';
import 'resource_revision_service.dart';

/// Outcome of one [AssemblyReadinessCoordinator.prepare] run.
final class AssemblyPrepareOutcome {
  const AssemblyPrepareOutcome({
    required this.record,
    this.awaitedCompression = false,
    this.published = false,
    this.superseded = false,
  });

  /// The readiness row as of the end of the run.
  final AssemblyReadinessRecord record;

  /// True when the head is OVERFLOW and compression preparation was queued;
  /// the run stays `preparing` until compression is published and a later
  /// prepare succeeds.
  final bool awaitedCompression;

  /// True when this run published an assembly revision and reached `ready`.
  final bool published;

  /// True when the head moved while this run was working, so the result was
  /// downgraded to `stale` (or dropped entirely) instead of being published.
  final bool superseded;
}

/// Drives "latest head → immutable revision → validated assembly revision →
/// revision-bound index → ready" for one resource (Phase 10).
///
/// Concurrency model: every run captures an **attempt token**. All terminal
/// writes (`ready`, `failed`, `stale`) are compare-and-set on that token
/// inside one transaction that also re-reads the latest head, so a run whose
/// head changed mid-flight can neither mark a newer head ready nor overwrite
/// a newer run's state — its result becomes `stale` or is dropped.
///
/// State transitions are validated through the frozen
/// [ResourceStateMachines.readiness] machine before any persistence.
final class AssemblyReadinessCoordinator extends ChangeNotifier {
  AssemblyReadinessCoordinator({
    required Future<Database> Function() getDb,
    required IAssemblyReadinessRepository readinessRepository,
    required IResourceRevisionRepository revisionRepository,
    required ResourceRevisionService revisionService,
    required ResourceAssemblyBuilder builder,
    Future<ResourceType?> Function(ResourceId resourceId)? typeResolver,
  })  : _getDb = getDb,
        _readiness = readinessRepository,
        _revisions = revisionRepository,
        _revisionService = revisionService,
        _builder = builder,
        _typeResolver = typeResolver;

  final Future<Database> Function() _getDb;
  final IAssemblyReadinessRepository _readiness;
  final IResourceRevisionRepository _revisions;
  final ResourceRevisionService _revisionService;
  final ResourceAssemblyBuilder _builder;
  final Future<ResourceType?> Function(ResourceId resourceId)? _typeResolver;

  // Compression hooks are attached lazily (see [attachCompression]) instead of
  // arriving through the constructor, so the readiness chain never statically
  // depends on the LLM-gateway provider graph (which reads ChatProvider).
  CompressionCoordinator? _compression;
  CompressionBackgroundWorker? _compressionWorker;
  CompressionPublisher? _publisher;

  /// Wires the Phase 8 compression infrastructure for OVERFLOW heads.
  ///
  /// Called once from the production DI assembly at app startup. Tests may
  /// attach fakes the same way; an unattached coordinator fails fast — an
  /// OVERFLOW head becomes a terminal `failed` record with an explicit
  /// reason instead of silently waiting for a compression that can never run.
  void attachCompression({
    required CompressionCoordinator Function() coordinatorGetter,
    CompressionBackgroundWorker Function()? workerGetter,
    CompressionPublisher Function()? publisherGetter,
  }) {
    _compression = coordinatorGetter();
    _compressionWorker = workerGetter?.call();
    _publisher = publisherGetter?.call();
    _compressionWorker?.onProgress = (_) => notifyListeners();
    _compressionWorker?.onSettled = (id) async {
      if (!isPreparationInFlight(id.value)) await refresh(id);
      notifyListeners();
    };
    _publisher?.onPublished = (id) async {
      await pendingPreparation(id.value);
      await prepare(id);
      notifyListeners();
    };
  }

  /// True once [attachCompression] ran. Production wiring tests assert this
  /// so a composition root that forgets the compression link cannot pass.
  bool get compressionAttached => _compression != null;

  /// Single-flight per resource: repeated `prepare` calls for the same
  /// resource share one run instead of racing each other for the token.
  final Map<String, Future<AssemblyPrepareOutcome>> _inFlight = {};

  /// True while a [prepare] run for [resourceId] is owned by this coordinator.
  ///
  /// Used by read-side reconciliation to distinguish a genuinely running
  /// validation from a persisted/tombstoned state, so it never starts a second
  /// validator for the same resource.
  bool isPreparationInFlight(String resourceId) =>
      _inFlight.containsKey(resourceId);

  /// The in-flight [prepare] future for [resourceId], if one is owned by this
  /// coordinator. Callers can await it to coalesce with — instead of racing —
  /// an already running run.
  Future<AssemblyPrepareOutcome>? pendingPreparation(String resourceId) =>
      _inFlight[resourceId];

  static int _tokenSeq = 0;

  /// Test seam invoked after the build and before the head re-validation, so
  /// a test can inject "the user edited the resource mid-assembly".
  ///
  /// Public but prefixed `debug`: production code never sets it.
  Future<void> Function()? debugInterleaveHook;

  String _newToken() =>
      'attempt_${DateTime.now().microsecondsSinceEpoch}_${++_tokenSeq}';

  static String _now() => DateTime.now().toIso8601String();

  static String _diagnostic(String code,
          [Map<String, Object?> params = const {}]) =>
      DiagnosticEnvelope(code: code, parameters: params).encode();

  /// Reads the persisted readiness row (reconciling a `ready` row against the
  /// current head on the way out).
  Future<AssemblyReadinessRecord?> readiness(ResourceId resourceId) =>
      refresh(resourceId);

  /// Prepares an assembly for the resource's current latest head.
  ///
  /// See the class comment for the concurrency model and [AssemblyPrepareOutcome]
  /// for the possible results.
  Future<AssemblyPrepareOutcome> prepare(ResourceId resourceId) {
    final running = _inFlight[resourceId.value];
    if (running != null) return running;
    final future = _prepare(resourceId);
    _inFlight[resourceId.value] = future;
    void cleanup() {
      if (identical(_inFlight[resourceId.value], future)) {
        _inFlight.remove(resourceId.value);
      }
    }

    // Handle the derived future too: whenComplete otherwise creates a second
    // unhandled error when claiming a preparation fails before validation.
    future.then((_) {
      cleanup();
      notifyListeners();
    }, onError: (Object _, StackTrace __) => cleanup());
    return future;
  }

  Future<AssemblyPrepareOutcome> _prepare(ResourceId resourceId) async {
    final db = await _getDb();
    final token = _newToken();
    final now = _now();

    // ── 1. Capture the head and claim ownership in one transaction. ──
    ResourceRevision? head;
    AssemblyReadinessRecord? existing;
    await db.transaction((txn) async {
      head = await _revisions.readHeadInTransaction(
        txn,
        resourceId,
        ResourceRevisionKind.latestHead,
      );
      existing = await _readiness.readInTransaction(txn, resourceId.value);
      if (existing != null) {
        // Throws on an illegal edge; the write below never happens then.
        ResourceStateMachines.advanceReadiness(
          existing!.state,
          ReadinessState.preparing,
        );
      }
      await _readiness.writeInTransaction(
        txn,
        AssemblyReadinessRecord(
          resourceId: resourceId.value,
          state: ReadinessState.preparing,
          targetRevisionId: head?.revisionId.value ?? '',
          targetContentHash: head?.contentHash ?? '',
          // Preserve the previous consumable assembly so a stale-but-ready
          // revision stays selectable while the new head prepares.
          assemblyRevisionId: existing?.assemblyRevisionId ?? '',
          assemblyContentHash: existing?.assemblyContentHash ?? '',
          attemptToken: token,
          startedAt: now,
          updatedAt: now,
        ),
      );
    });
    // Publish the claimed assembly phase too, including after candidate adoption.
    notifyListeners();

    if (head == null) {
      return _fail(
        resourceId,
        token,
        'noSavedRevision',
      );
    }

    var stage = 'capacity';
    ResourceType? resourceType;
    try {
      // ── 2. Capacity of the frozen revision state. ──
      resourceType = await _typeResolver?.call(resourceId);
      final state = await _revisions.readState(head!.revisionId);
      final status = await _capacityStatusOf(resourceId, state);

      final capacityParameters = <String, Object?>{
        'actualCharacters': state.nodes.values
            .where((node) =>
                node.kind == RevisionNodeKind.part &&
                node.status != NodeStatus.archived)
            .fold<int>(0, (sum, node) => sum + node.content.length),
        if (resourceType != null)
          'absoluteCharacters':
              ResourceLimits.policyFor(resourceType).absoluteCharacters,
      };

      // ── 3. OVERFLOW: enter compression preparation, stay `preparing`. ──
      if (status == CapacityStatus.overflow) {
        final compression = _compression;
        if (compression == null) {
          // C14 fail-fast: without an attached compression link no worker
          // would ever process this overflow, so staying `preparing` would be
          // a silent dead-end. Surface a terminal failure instead.
          return await _fail(
            resourceId,
            token,
            'compressionUnavailable',
            parameters: capacityParameters,
          );
        }
        stage = 'compression';
        final jobs =
            await compression.enqueueForResource(resourceId, partOnly: true);
        if (jobs.isEmpty) {
          return await _fail(resourceId, token, 'compressionNoTargets',
              parameters: capacityParameters);
        }
        final worker = _compressionWorker;
        if (worker == null) {
          return await _fail(resourceId, token, 'compressionUnavailable',
              parameters: capacityParameters);
        }
        await _casUpdate(
            resourceId,
            token,
            (current, txn, now) => _copyRecord(current,
                validationMessage: _diagnostic('compressionPending', {
                  ...capacityParameters,
                  'resourceId': resourceId.value,
                  'jobIds': jobs.map((job) => job.jobId).toList(),
                }),
                updatedAt: now));
        notifyListeners();
        await worker.process(resourceId.value);
        final record = await _reconcileCompression(resourceId);
        return AssemblyPrepareOutcome(
            record: record!, awaitedCompression: true);
      }

      // ── 4. Build from the immutable revision only. ──
      stage = 'assemblyBuild';
      final build = await _builder.build(
        resourceId: resourceId,
        revisionId: head!.revisionId,
        expectedContentHash: head!.contentHash,
      );

      if (debugInterleaveHook != null) {
        await debugInterleaveHook!();
      }

      // ── 5. Re-validate the head before publishing. ──
      final headNow = await _revisions.readHead(
        resourceId,
        ResourceRevisionKind.latestHead,
      );
      final headMoved = headNow == null ||
          headNow.revisionId != head!.revisionId ||
          headNow.contentHash != head!.contentHash;
      if (headMoved) {
        final record = await _casUpdate(
          resourceId,
          token,
          (current, txn, now) => _copyRecord(
            current,
            state: ReadinessState.stale,
            validationMessage: _diagnostic('staleResource', {
              'resourceId': resourceId.value,
              'revisionId': head!.revisionId.value,
            }),
            updatedAt: now,
          ),
          allowTransitionToStale: true,
        );
        return AssemblyPrepareOutcome(record: record, superseded: true);
      }

      // ── 6. Publish the assembly revision (idempotent, delta-with-
      //       tombstone chain owned by Phase 9). ──
      stage = 'assemblyPublication';
      await _revisionService.publishAssemblyRevision(
        resourceId: resourceId,
        revisionId: head!.revisionId,
      );
      final assemblyHead = await _revisions.readHead(
        resourceId,
        ResourceRevisionKind.assembly,
      );
      if (assemblyHead == null) {
        return await _fail(resourceId, token, 'assemblyRevisionMissing');
      }

      stage = 'indexPublication';
      // ── 7. Semantic index sync, bound to the published revision. ──
      await db.transaction((txn) async {
        await _readiness.replaceIndexDocsInTransaction(
          txn,
          resourceId: resourceId.value,
          revisionId: assemblyHead.revisionId.value,
          revisionContentHash: head!.contentHash,
          docs: build.indexDocs,
          now: _now(),
        );
      });

      stage = 'readyCommit';
      // ── 8. Final CAS commit: ready. ──
      final record = await db.transaction<AssemblyReadinessRecord>((txn) async {
        final current =
            await _readiness.readInTransaction(txn, resourceId.value);
        if (current == null) {
          throw AssemblyReadinessException(
            'readiness 行不存在，无法完成提交：${resourceId.value}',
          );
        }
        if (current.attemptToken != token) {
          // Ownership lost: a newer run owns this row; drop our result.
          return current;
        }
        final headFinal = await _revisions.readHeadInTransaction(
          txn,
          resourceId,
          ResourceRevisionKind.latestHead,
        );
        if (headFinal == null ||
            headFinal.revisionId != head!.revisionId ||
            headFinal.contentHash != head!.contentHash) {
          final next = _copyRecord(
            current,
            state: ReadinessState.stale,
            validationMessage: _diagnostic('staleResource', {
              'resourceId': resourceId.value,
              'revisionId': head!.revisionId.value,
            }),
            updatedAt: _now(),
          );
          ResourceStateMachines.advanceReadiness(current.state, next.state);
          await _readiness.writeInTransaction(txn, next);
          return next;
        }
        final next = _copyRecord(
          current,
          state: ReadinessState.ready,
          assemblyRevisionId: assemblyHead.revisionId.value,
          assemblyContentHash: head!.contentHash,
          validationMessage: '',
          failureReason: '',
          completedAt: _now(),
          updatedAt: _now(),
        );
        ResourceStateMachines.advanceReadiness(current.state, next.state);
        await _readiness.writeInTransaction(txn, next);
        return next;
      });
      return AssemblyPrepareOutcome(
        record: record,
        published: record.state == ReadinessState.ready,
        superseded: record.state == ReadinessState.stale,
      );
    } catch (error, stackTrace) {
      final parameters = <String, Object?>{
        'stage': stage,
        'exceptionType': error.runtimeType.toString(),
        'resourceType': resourceType?.storageValue ?? 'unknown',
        'targetRevisionId': head!.revisionId.value,
        'targetContentHash': head!.contentHash,
      };
      debugPrint('[AdventureStart][PREPARATION_FAILED] '
          'resourceId=${resourceId.value} status=failed $parameters');
      debugPrintStack(
          label: '[AdventureStart][PREPARATION_STACK]', stackTrace: stackTrace);
      return await _fail(
          resourceId,
          token,
          error is ResourceAssemblyException
              ? error.diagnosticCode
              : error is ResourceRevisionCorruptedException
                  ? 'revisionHashMismatch'
                  : 'preparationFailed',
          parameters: parameters);
    }
  }

  /// Only an explicit user retry spends another compression attempt.
  Future<AssemblyPrepareOutcome> retryPreparation(ResourceId id) async {
    await _compression?.recoverStaleJobs();
    await _compression?.retryFailedJobs(id);
    return prepare(id);
  }

  Future<List<CompressionCandidate>> compressionCandidates(
          ResourceId id) async =>
      await _publisher?.publishableCandidates(id) ?? const [];

  Future<void> approveCompression(
      {required ResourceId resourceId,
      required List<String> candidateIds,
      required String expectedHeadRevisionId}) async {
    await pendingPreparation(resourceId.value);
    final publisher = _publisher;
    if (publisher == null) throw const CompressionPublishException('压缩发布服务不可用');
    await publisher.publishMany(
        resourceId: resourceId,
        candidateIds: candidateIds,
        expectedHeadRevisionId: expectedHeadRevisionId);
  }

  Future<AssemblyReadinessRecord?> _reconcileCompression(ResourceId id) async {
    final row = await _readiness.read(id.value);
    if (row == null || row.state != ReadinessState.preparing) return row;
    final head = await _revisions.readHead(id, ResourceRevisionKind.latestHead);
    if (head == null ||
        head.revisionId.value != row.targetRevisionId ||
        head.contentHash != row.targetContentHash) {
      return _casUpdate(
          id,
          row.attemptToken,
          (current, txn, now) => _copyRecord(current,
              state: ReadinessState.stale,
              validationMessage: _diagnostic('staleResource'),
              updatedAt: now),
          allowTransitionToStale: true);
    }
    if (!isPreparationInFlight(id.value)) {
      final state = await _revisions.readState(head.revisionId);
      if (await _capacityStatusOf(id, state) != CapacityStatus.overflow) {
        // A legacy compressionPending row cannot override current capacity.
        // Rebuild through the full gate pipeline; never synthesize ready.
        return (await prepare(id)).record;
      }
    }
    final diagnostic = DiagnosticEnvelope.tryDecode(row.validationMessage);
    final selected =
        (diagnostic?.parameters['jobIds'] as List?)?.cast<String>();
    final all = await _compression?.jobsForResource(id) ?? <CompressionJob>[];
    final jobs = all
        .where((job) => selected == null
            ? job.scope == CompressionScope.part
            : selected.contains(job.jobId))
        .toList();
    String code;
    var failed = false;
    if (jobs.isEmpty) {
      code = 'compressionNoTargets';
      failed = true;
    } else if (jobs.any((job) => job.isActive)) {
      if (_compressionWorker?.isProcessing(id.value) == true) {
        code = jobs.any((job) => job.status == CompressionJobStatus.running)
            ? 'compressionRunning'
            : 'compressionPending';
      } else {
        code = 'interruptedPreparation';
        failed = true;
      }
    } else if (jobs.any((job) => job.status == CompressionJobStatus.failed)) {
      code = jobs.any((job) =>
              !job.canRetry && job.status == CompressionJobStatus.failed)
          ? 'compressionBudgetExhausted'
          : 'compressionFailed';
      failed = true;
    } else {
      final candidates = await _compression?.candidatesForResource(id) ??
          <CompressionCandidate>[];
      final usable = candidates
          .where((candidate) =>
              candidate.isValidated &&
              candidate.isCandidateOnly &&
              candidate.scope == CompressionScope.part &&
              jobs.any((job) => job.jobId == candidate.jobId))
          .toList();
      code = usable.length == jobs.length
          ? 'compressionApprovalRequired'
          : 'compressionNoCandidate';
      failed = usable.length != jobs.length;
    }
    final encoded = _diagnostic(code, {
      if (diagnostic?.parameters['actualCharacters'] != null)
        'actualCharacters': diagnostic!.parameters['actualCharacters'],
      if (diagnostic?.parameters['absoluteCharacters'] != null)
        'absoluteCharacters': diagnostic!.parameters['absoluteCharacters'],
      'resourceId': id.value,
      'jobIds': jobs.map((job) => job.jobId).toList(),
      'targetRevisionId': row.targetRevisionId,
      'targetContentHash': row.targetContentHash
    });
    if (row.validationMessage == encoded && !failed) return row;
    debugPrint('[AdventureStart][COMPRESSION] resourceId=${id.value} '
        'status=$code jobs=${jobs.length} revision=${row.targetRevisionId} '
        'hash=${row.targetContentHash} '
        'jobStates=${jobs.map((job) => '${job.jobId}:${job.scope.name}:${job.targetNodeId}:${job.status.name}:${job.attempts}').join(',')}');
    final next = await _casUpdate(
        id,
        row.attemptToken,
        (current, txn, now) => _copyRecord(current,
            state: failed ? ReadinessState.failed : ReadinessState.preparing,
            validationMessage: encoded,
            failureReason: failed ? encoded : '',
            updatedAt: now),
        allowTransitionToFailed: true);
    notifyListeners();
    return next;
  }

  /// Marks every `preparing` row that no live run owns as `failed`.
  ///
  /// Called at startup: a preparing row from a dead process would otherwise
  /// block Adventure start forever. Fail-closed — the row becomes retryable,
  /// never auto-ready.
  Future<int> recoverInterrupted() async {
    final rows = await _readiness.listByState(ReadinessState.preparing);
    var recovered = 0;
    for (final row in rows) {
      if (_inFlight.containsKey(row.resourceId)) continue;
      if (_compression != null &&
          DiagnosticEnvelope.tryDecode(row.validationMessage)
                  ?.code
                  .startsWith('compression') ==
              true) {
        await _compressionWorker?.process(row.resourceId);
        await _reconcileCompression(ResourceId(row.resourceId));
        recovered++;
        continue;
      }
      final db = await _getDb();
      final done = await db.transaction((txn) async {
        final current = await _readiness.readInTransaction(txn, row.resourceId);
        if (current == null || current.state != ReadinessState.preparing) {
          return false;
        }
        if (_inFlight.containsKey(row.resourceId)) return false;
        await _readiness.writeInTransaction(
          txn,
          _copyRecord(
            current,
            state: ReadinessState.failed,
            failureReason: _diagnostic('interruptedPreparation'),
            updatedAt: _now(),
          ),
        );
        return true;
      });
      if (done) recovered++;
    }
    return recovered;
  }

  /// Reconciles the persisted row with the current head/assembly pointers.
  ///
  /// A `ready` row whose assembly pointer no longer matches the latest head
  /// becomes `stale` (legal edge `ready → stale`). Everything else is returned
  /// untouched; `stale` never flips back to `ready` without a fresh prepare.
  Future<AssemblyReadinessRecord?> refresh(ResourceId resourceId) async {
    final record = await _readiness.read(resourceId.value);
    if (record == null) return null;
    if (record.state == ReadinessState.preparing &&
        _compression != null &&
        DiagnosticEnvelope.tryDecode(record.validationMessage)
                ?.code
                .startsWith('compression') ==
            true) {
      return _reconcileCompression(resourceId);
    }
    if (record.state != ReadinessState.ready) return record;

    final head = await _revisions.readHead(
      resourceId,
      ResourceRevisionKind.latestHead,
    );
    final assembly = await _revisions.readHead(
      resourceId,
      ResourceRevisionKind.assembly,
    );
    final fresh = head != null &&
        assembly != null &&
        record.assemblyRevisionId == assembly.revisionId.value &&
        head.contentHash == assembly.contentHash &&
        record.targetRevisionId == head.revisionId.value &&
        record.targetContentHash == head.contentHash &&
        record.assemblyContentHash == assembly.contentHash;
    if (fresh) return record;

    return _casUpdate(
      resourceId,
      record.attemptToken,
      (current, txn, now) => _copyRecord(
        current,
        state: ReadinessState.stale,
        validationMessage: _diagnostic('staleResource', {
          'resourceId': resourceId.value,
        }),
        updatedAt: now,
      ),
      allowTransitionToStale: true,
      expectToken: record.attemptToken,
    );
  }

  // ─── internals ───

  Future<AssemblyPrepareOutcome> _fail(
    ResourceId resourceId,
    String token,
    String reason, {
    Map<String, Object?> parameters = const {},
  }) async {
    final record = await _casUpdate(
      resourceId,
      token,
      (current, txn, now) => _copyRecord(
        current,
        state: ReadinessState.failed,
        failureReason: _diagnostic(
            reason, {'resourceId': resourceId.value, ...parameters}),
        completedAt: now,
        updatedAt: now,
      ),
      allowTransitionToFailed: true,
    );
    return AssemblyPrepareOutcome(record: record);
  }

  /// Compare-and-set update: runs [update] only when the row still carries
  /// [token] (or [expectToken]). Returns the row as written, or as found when
  /// ownership was lost.
  Future<AssemblyReadinessRecord> _casUpdate(
    ResourceId resourceId,
    String token,
    AssemblyReadinessRecord Function(
            AssemblyReadinessRecord current, DatabaseExecutor txn, String now)
        update, {
    bool allowTransitionToStale = false,
    bool allowTransitionToFailed = false,
    String? expectToken,
  }) async {
    final db = await _getDb();
    final now = _now();
    return db.transaction((txn) async {
      final current = await _readiness.readInTransaction(txn, resourceId.value);
      if (current == null) {
        throw AssemblyReadinessException(
          'readiness 行不存在，无法完成 CAS 更新：${resourceId.value}',
        );
      }
      final ownedToken = expectToken ?? token;
      if (current.attemptToken != ownedToken) {
        // Ownership lost — return the row untouched instead of clobbering.
        return current;
      }
      final next = update(current, txn, now);
      if (next.state != current.state) {
        var legal = ResourceStateMachines.canTransitionReadiness(
          current.state,
          next.state,
        );
        // A stale/failed downgrade of a preparing row is how an expired run
        // records "my result must not become ready"; permit exactly those
        // edges explicitly.
        if (!legal &&
            allowTransitionToStale &&
            next.state == ReadinessState.stale) {
          legal = true;
        }
        if (!legal &&
            allowTransitionToFailed &&
            next.state == ReadinessState.failed) {
          legal = true;
        }
        if (!legal) {
          throw ResourceStateTransitionException(
            domain: 'readiness',
            from: current.state.storageValue,
            to: next.state.storageValue,
          );
        }
      }
      await _readiness.writeInTransaction(txn, next);
      return next;
    });
  }

  AssemblyReadinessRecord _copyRecord(
    AssemblyReadinessRecord base, {
    ReadinessState? state,
    String? assemblyRevisionId,
    String? assemblyContentHash,
    String? validationMessage,
    String? failureReason,
    String? completedAt,
    String? updatedAt,
  }) =>
      AssemblyReadinessRecord(
        resourceId: base.resourceId,
        state: state ?? base.state,
        targetRevisionId: base.targetRevisionId,
        targetContentHash: base.targetContentHash,
        assemblyRevisionId: assemblyRevisionId ?? base.assemblyRevisionId,
        assemblyContentHash: assemblyContentHash ?? base.assemblyContentHash,
        attemptToken: base.attemptToken,
        validationMessage: validationMessage ?? base.validationMessage,
        failureReason: failureReason ?? base.failureReason,
        startedAt: base.startedAt,
        completedAt: completedAt ?? base.completedAt,
        updatedAt: updatedAt ?? base.updatedAt,
      );

  /// Capacity classification of a frozen revision state, using the single
  /// capacity policy (never a live re-measurement). The resource type is an
  /// immutable identity attribute resolved via [typeResolver] when the root
  /// metadata does not carry it (the production writer never writes `type`
  /// into `metadata_json`).
  Future<CapacityStatus> _capacityStatusOf(
    ResourceId resourceId,
    ResourceRevisionState state,
  ) async {
    final root = state.nodes.values
        .where((node) => node.kind == RevisionNodeKind.resource)
        .firstOrNull;
    ResourceType? type;
    final metadataType = root?.metadata['type']?.toString();
    if (metadataType != null && metadataType.isNotEmpty) {
      type = ResourceType.fromStorageValue(metadataType);
    } else {
      type = await _typeResolver?.call(resourceId);
    }
    // Unknown type cannot be classified against any budget: fail closed.
    if (type == null) {
      throw ResourceAssemblyException(
        '无法确定资源 ${resourceId.value} 的类型，无法进行容量判定',
      );
    }
    final activeChars = state.nodes.values
        .where((node) => node.kind == RevisionNodeKind.part)
        .where((node) => node.status != NodeStatus.archived)
        .fold(0, (sum, node) => sum + node.content.length);
    final db = await _getDb();
    final live = await db.rawQuery(
        'SELECT p.id, p.content, p.status FROM resource_parts p '
        'JOIN resource_sections s ON s.id = p.section_id '
        'WHERE s.resource_id = ? AND s.deleted_at IS NULL AND p.deleted_at IS NULL',
        [resourceId.value]);
    final liveActive = live
        .where((row) => row['status'] != 'archived')
        .fold<int>(
            0, (sum, row) => sum + (row['content']?.toString() ?? '').length);
    final plan = await db.rawQuery(
        'SELECT b.target_capacity, b.blueprint_id, s.target_characters '
        'FROM resource_blueprints b LEFT JOIN resource_creation_sessions s ON s.session_id = b.session_id '
        'WHERE b.resource_id = ? ORDER BY b.created_at DESC LIMIT 1',
        [resourceId.value]);
    debugPrint(
        '[AdventureStart][CAPACITY] resourceId=${resourceId.value} resourceType=${type.storageValue} '
        'revision=${state.revisionId.value} revisionCharacters=$activeChars liveCharacters=$liveActive '
        'activeParts=${live.where((row) => row['status'] != 'archived').length} '
        'generationTarget=${plan.firstOrNull?['target_characters']} blueprintTarget=${plan.firstOrNull?['target_capacity']} '
        'status=${ResourceCapacityMath.statusFor(type, activeChars).name}');
    return ResourceCapacityMath.statusFor(type, activeChars);
  }
}
