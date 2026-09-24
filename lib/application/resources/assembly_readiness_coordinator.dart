import 'package:sqflite/sqflite.dart';

import '../../domain/resources/resource_capacity.dart';
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
final class AssemblyReadinessCoordinator {
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

  /// Wires the Phase 8 compression infrastructure for OVERFLOW heads.
  ///
  /// Called once from the production DI assembly at app startup. Tests may
  /// attach fakes the same way; an unattached coordinator fails fast — an
  /// OVERFLOW head becomes a terminal `failed` record with an explicit
  /// reason instead of silently waiting for a compression that can never run.
  void attachCompression({
    required CompressionCoordinator Function() coordinatorGetter,
    CompressionBackgroundWorker Function()? workerGetter,
  }) {
    _compression = coordinatorGetter();
    _compressionWorker = workerGetter?.call();
  }

  /// True once [attachCompression] ran. Production wiring tests assert this
  /// so a composition root that forgets the compression link cannot pass.
  bool get compressionAttached => _compression != null;

  /// Single-flight per resource: repeated `prepare` calls for the same
  /// resource share one run instead of racing each other for the token.
  final Map<String, Future<AssemblyPrepareOutcome>> _inFlight = {};

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

    future.whenComplete(cleanup);
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

    if (head == null) {
      return _fail(
        resourceId,
        token,
        'noSavedRevision',
      );
    }

    try {
      // ── 2. Capacity of the frozen revision state. ──
      final state = await _revisions.readState(head!.revisionId);
      final status = await _capacityStatusOf(resourceId, state);

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
          );
        }
        await compression.enqueueForResource(resourceId);
        _compressionWorker?.scheduleProcessing(resourceId.value);
        final message = _diagnostic('compressionPending', {
          'resourceId': resourceId.value,
        });
        final record = await _casUpdate(
          resourceId,
          token,
          (current, txn, now) => _copyRecord(
            current,
            state: ReadinessState.preparing,
            validationMessage: message,
            updatedAt: now,
          ),
        );
        return AssemblyPrepareOutcome(
          record: record,
          awaitedCompression: true,
        );
      }

      // ── 4. Build from the immutable revision only. ──
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
    } catch (error) {
      return await _fail(resourceId, token, 'preparationFailed');
    }
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
        head.contentHash == assembly.contentHash;
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
    String reason,
  ) async {
    final record = await _casUpdate(
      resourceId,
      token,
      (current, txn, now) => _copyRecord(
        current,
        state: ReadinessState.failed,
        failureReason: _diagnostic(reason, {'resourceId': resourceId.value}),
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
    return ResourceCapacityMath.statusFor(type, activeChars);
  }
}
