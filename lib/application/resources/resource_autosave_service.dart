import 'dart:async';

import 'package:sqflite/sqflite.dart';

import '../../domain/resources/resource_autosave.dart';
import '../../domain/resources/resource_contracts.dart';
import '../../domain/resources/resource_revision.dart';
import '../../services/repositories/resource_tree_repository.dart';
import 'part_content_commit_service.dart';
import 'resource_autosave_repository.dart';

/// The autosave behaviour one editor session needs.
///
/// Declared as an interface so the editor widget can be tested against a tiny
/// fake — the debounce, journal and revision-boundary rules are covered by the
/// service's own tests, and the widget test should only have to prove what the
/// UI does with the outcomes.
abstract interface class AutosaveSession {
  /// Buffers one keystroke. Must not touch the database.
  void schedule({
    required ResourceId resourceId,
    required PartId partId,
    required String content,
    required String expectedUpdatedAt,
  });

  /// Writes every buffered edit.
  Future<AutosaveFlushResult> flush({
    AutosaveFlushTrigger trigger = AutosaveFlushTrigger.manual,
  });

  /// Marks the session closed and performs the final flush.
  Future<AutosaveFlushResult> dispose();

  /// Notified after every flush.
  set onFlushed(void Function(AutosaveFlushResult result)? callback);

  /// Parts with edits that are not yet in the tree.
  int get pendingCount;
}

/// Creates one autosave session per open editor.
///
/// A factory rather than a shared instance: the session owns the debounce
/// buffer, and two editors sharing one buffer would flush each other's text.
/// Declared here (not in the widget layer) so neither the UI nor the
/// composition root has to depend on the other for the type.
typedef AutosaveServiceFactory = AutosaveSession Function();

/// Which lifecycle boundary caused a flush.
///
/// Recorded on the result (and in the UI status) so a test — and a user
/// reading a bug report — can tell a debounce checkpoint apart from the flush
/// that a page exit forced.
enum AutosaveFlushTrigger {
  debounce,
  maxBufferedAge,
  manual,
  pageLeave,
  dispose,
  cancel,
  generationError,
  appLifecycle;

  String get displayLabel => switch (this) {
        AutosaveFlushTrigger.debounce => '输入暂停自动保存',
        AutosaveFlushTrigger.maxBufferedAge => '连续输入自动保存',
        AutosaveFlushTrigger.manual => '手动保存',
        AutosaveFlushTrigger.pageLeave => '离开页面保存',
        AutosaveFlushTrigger.dispose => '编辑器关闭保存',
        AutosaveFlushTrigger.cancel => '取消生成前保存',
        AutosaveFlushTrigger.generationError => '生成失败前保存',
        AutosaveFlushTrigger.appLifecycle => '应用退到后台保存',
      };

  /// Triggers that must run even when the debounce timer has not fired.
  bool get isForced =>
      this != AutosaveFlushTrigger.debounce &&
      this != AutosaveFlushTrigger.maxBufferedAge;
}

/// Outcome of writing one buffered Part edit.
enum AutosaveWriteStatus {
  applied,
  conflict,
  missingTarget,
  failed,
}

/// Per-Part outcome of one flush.
final class AutosaveWriteOutcome {
  const AutosaveWriteOutcome({
    required this.partId,
    required this.status,
    required this.checkpointId,
    this.message = '',
    this.contentCharacters = 0,
  });

  final String partId;
  final AutosaveWriteStatus status;
  final String checkpointId;
  final String message;
  final int contentCharacters;

  bool get persisted => status == AutosaveWriteStatus.applied;
}

/// Result of one flush.
final class AutosaveFlushResult {
  const AutosaveFlushResult({
    required this.trigger,
    required this.outcomes,
  });

  final AutosaveFlushTrigger trigger;
  final List<AutosaveWriteOutcome> outcomes;

  int get applied => outcomes.where((outcome) => outcome.persisted).length;

  int get conflicted => outcomes
      .where((outcome) => outcome.status == AutosaveWriteStatus.conflict)
      .length;

  int get discarded => outcomes
      .where((outcome) => outcome.status == AutosaveWriteStatus.missingTarget)
      .length;

  int get failed => outcomes
      .where((outcome) => outcome.status == AutosaveWriteStatus.failed)
      .length;

  bool get hadWork => outcomes.isNotEmpty;

  /// True when at least one edit is still only in the journal because the tree
  /// refused it. The editor keeps the text on screen instead of pretending the
  /// save succeeded.
  bool get hasUnsavedConflict => conflicted > 0 || failed > 0;
}

final class _BufferedEdit {
  _BufferedEdit({
    required this.resourceId,
    required this.partId,
    required this.content,
    required this.baseUpdatedAt,
    required this.firstBufferedAt,
  });

  final ResourceId resourceId;
  final PartId partId;
  final String content;
  final String baseUpdatedAt;

  /// When this Part first entered the buffer, used to cap how long an edit may
  /// stay only in memory while typing continues without a pause.
  final DateTime firstBufferedAt;
}

/// Debounced autosave for manual text edits.
///
/// Shape of a save:
/// ```text
/// keystroke → in-memory buffer only (no SQLite write)
/// pause     → journal row (durable)
///           → one transaction: Part body + section verdict + revision head
///           → journal row removed
/// ```
///
/// Two properties follow directly from that order:
/// - typing cannot produce one SQLite write per keystroke, because [schedule]
///   never touches the database;
/// - a crash between the journal write and the tree commit leaves a draft the
///   UI can offer back, while a streamed chunk that was never confirmed has no
///   journal row and therefore cannot come back pretending to be complete.
final class ResourceAutosaveService implements AutosaveSession {
  ResourceAutosaveService({
    required IResourceAutosaveRepository journal,
    required PartContentCommitService committer,
    required IResourceTreeRevisionBoundary treeBoundary,
    required Future<Database> Function() getDb,
    Duration debounce = AutosavePolicy.debounce,
    Duration maxBufferedAge = AutosavePolicy.maxBufferedAge,
    this.onFlushed,
  })  : _journal = journal,
        _committer = committer,
        _tree = treeBoundary,
        _getDb = getDb,
        _debounce = debounce,
        _maxBufferedAge = maxBufferedAge;
  final IResourceAutosaveRepository _journal;
  final PartContentCommitService _committer;
  final IResourceTreeRevisionBoundary _tree;
  final Future<Database> Function() _getDb;
  final Duration _debounce;
  final Duration _maxBufferedAge;

  /// Notified after every flush so the editor can show autosave state without
  /// polling.
  ///
  /// Settable rather than constructor-only because the editor is created by a
  /// factory that does not yet have a `State` to call back into.
  void Function(AutosaveFlushResult result)? onFlushed;

  final Map<String, _BufferedEdit> _buffer = <String, _BufferedEdit>{};
  Timer? _timer;
  bool _disposed = false;

  /// Parts with edits that are not yet in the tree.
  @override
  int get pendingCount => _buffer.length;

  bool get hasPendingEdits => _buffer.isNotEmpty;

  /// True while a debounce timer is armed.
  bool get isFlushScheduled => _timer?.isActive ?? false;

  Duration get debounce => _debounce;

  /// Buffers one keystroke.
  ///
  /// Deliberately synchronous and database-free: this runs on every keystroke,
  /// so anything expensive here would show up as typing latency.
  @override
  void schedule({
    required ResourceId resourceId,
    required PartId partId,
    required String content,
    required String expectedUpdatedAt,
  }) {
    if (_disposed) return;
    final now = DateTime.now();
    final existing = _buffer[partId.value];
    _buffer[partId.value] = _BufferedEdit(
      resourceId: resourceId,
      partId: partId,
      content: content,
      baseUpdatedAt: expectedUpdatedAt,
      firstBufferedAt: existing?.firstBufferedAt ?? now,
    );
    _armTimer(now);
  }

  /// Content currently buffered for [partId], or null.
  String? bufferedContent(PartId partId) => _buffer[partId.value]?.content;

  /// Drops a buffered edit without writing it.
  ///
  /// Used when the user explicitly reverts or when the target is known gone;
  /// it never touches a journal row, so a previously flushed draft is not lost.
  void discardBuffered(PartId partId) {
    _buffer.remove(partId.value);
  }

  /// Writes every buffered edit to the tree.
  @override
  Future<AutosaveFlushResult> flush({
    AutosaveFlushTrigger trigger = AutosaveFlushTrigger.manual,
  }) async {
    _timer?.cancel();
    _timer = null;
    if (_buffer.isEmpty) {
      return AutosaveFlushResult(
        trigger: trigger,
        outcomes: const <AutosaveWriteOutcome>[],
      );
    }

    final batch = List<_BufferedEdit>.from(_buffer.values);
    _buffer.clear();

    final outcomes = <AutosaveWriteOutcome>[];
    for (final edit in batch) {
      outcomes.add(await _writeOne(edit, trigger));
    }
    final result = AutosaveFlushResult(trigger: trigger, outcomes: outcomes);
    onFlushed?.call(result);
    return result;
  }

  /// Final flush for a terminating boundary (page exit, editor close,
  /// lifecycle pause). Safe to call repeatedly; a second call finds an empty
  /// buffer and does nothing.
  Future<AutosaveFlushResult> flushOnBoundary(AutosaveFlushTrigger trigger) {
    assert(trigger.isForced, 'flushOnBoundary is for forced triggers only');
    return flush(trigger: trigger);
  }

  /// Marks the service closed and performs the final flush.
  @override
  Future<AutosaveFlushResult> dispose() async {
    if (_disposed) {
      return const AutosaveFlushResult(
        trigger: AutosaveFlushTrigger.dispose,
        outcomes: <AutosaveWriteOutcome>[],
      );
    }
    final result = await flush(trigger: AutosaveFlushTrigger.dispose);
    _disposed = true;
    return result;
  }

  /// Classifies journal rows that never reached the tree.
  ///
  /// Called after a crash or a restart. Rows whose content already matches the
  /// live Part are dropped as applied; rows whose target disappeared are
  /// dropped as orphaned; rows that are genuinely newer than the tree are kept
  /// and reported so the user can decide.
  Future<List<AutosaveRecoveryOutcome>> reconcilePendingDrafts({
    ResourceId? resourceId,
  }) async {
    final drafts = await _journal.listDrafts(resourceId: resourceId);
    if (drafts.isEmpty) return const <AutosaveRecoveryOutcome>[];

    final db = await _getDb();
    final byResource = <String, List<ResourceAutosaveDraft>>{};
    for (final draft in drafts) {
      byResource.putIfAbsent(draft.resourceId.value, () => []).add(draft);
    }

    final outcomes = <AutosaveRecoveryOutcome>[];
    for (final entry in byResource.entries) {
      final live = await db.transaction(
        (txn) => _tree.readLiveState(txn, ResourceId(entry.key)),
      );
      for (final draft in entry.value) {
        final node = live[draft.partId.value];
        final AutosaveRecoveryDisposition disposition;
        if (node == null) {
          disposition = AutosaveRecoveryDisposition.orphaned;
        } else if (node.content == draft.content) {
          disposition = AutosaveRecoveryDisposition.alreadyApplied;
        } else {
          disposition = AutosaveRecoveryDisposition.needsUserDecision;
        }
        final outcome = AutosaveRecoveryOutcome(
          draft: draft,
          disposition: disposition,
          liveContentHash: node?.contentHash ?? '',
        );
        if (outcome.isResolved) {
          await _journal.deleteDraftInTransaction(db, draft.checkpointId);
        }
        outcomes.add(outcome);
      }
    }
    return outcomes;
  }

  void _armTimer(DateTime now) {
    _timer?.cancel();
    var delay = _debounce;
    if (_buffer.isNotEmpty) {
      final oldest = _buffer.values
          .map((edit) => edit.firstBufferedAt)
          .reduce((a, b) => a.isBefore(b) ? a : b);
      final ageRemaining = _maxBufferedAge - now.difference(oldest);
      if (ageRemaining < delay) delay = ageRemaining;
    }
    if (delay <= Duration.zero) {
      unawaited(flush(trigger: AutosaveFlushTrigger.maxBufferedAge));
      return;
    }
    final trigger = delay == _debounce
        ? AutosaveFlushTrigger.debounce
        : AutosaveFlushTrigger.maxBufferedAge;
    _timer = Timer(delay, () => unawaited(flush(trigger: trigger)));
  }

  Future<AutosaveWriteOutcome> _writeOne(
    _BufferedEdit edit,
    AutosaveFlushTrigger trigger,
  ) async {
    ResourceAutosaveDraft draft;
    try {
      // Step 1 — journal first, in its own transaction. From here on the text
      // is durable even if the tree write below never lands.
      draft = await _persistJournal(edit);
    } catch (error) {
      return AutosaveWriteOutcome(
        partId: edit.partId.value,
        status: AutosaveWriteStatus.failed,
        checkpointId: '',
        message: '草稿写入失败：$error',
      );
    }

    try {
      // Step 2 — tree write, verdict, revision head and journal removal share
      // one transaction.
      final result = await _committer.applyContent(
        PartContentCommitRequest(
          partId: edit.partId,
          expectedUpdatedAt: edit.baseUpdatedAt,
          content: edit.content,
          cause: RevisionCause.manualSave,
          checkpointId: draft.checkpointId,
          reason: trigger.displayLabel,
        ),
      );
      return AutosaveWriteOutcome(
        partId: edit.partId.value,
        status: AutosaveWriteStatus.applied,
        checkpointId: draft.checkpointId,
        contentCharacters: result.contentCharacters,
      );
    } on ResourceTreeConflictException catch (error) {
      // The tree moved on. The journal row is intentionally left in place so
      // the user's text is still recoverable; the editor keeps showing it.
      return AutosaveWriteOutcome(
        partId: edit.partId.value,
        status: AutosaveWriteStatus.conflict,
        checkpointId: draft.checkpointId,
        message: error.message,
      );
    } on ResourceTreeNotFoundException catch (error) {
      await _dropJournal(draft.checkpointId);
      return AutosaveWriteOutcome(
        partId: edit.partId.value,
        status: AutosaveWriteStatus.missingTarget,
        checkpointId: draft.checkpointId,
        message: error.message,
      );
    } catch (error) {
      return AutosaveWriteOutcome(
        partId: edit.partId.value,
        status: AutosaveWriteStatus.failed,
        checkpointId: draft.checkpointId,
        message: '自动保存失败：$error',
      );
    }
  }

  Future<ResourceAutosaveDraft> _persistJournal(_BufferedEdit edit) async {
    final db = await _getDb();
    final now = DateTime.now().toIso8601String();
    return db.transaction(
      (txn) => _journal.upsertDraftInTransaction(
        txn,
        resourceId: edit.resourceId,
        partId: edit.partId,
        content: edit.content,
        baseUpdatedAt: edit.baseUpdatedAt,
        now: now,
      ),
    );
  }

  Future<void> _dropJournal(String checkpointId) async {
    final db = await _getDb();
    await _journal.deleteDraftInTransaction(db, checkpointId);
  }
}
