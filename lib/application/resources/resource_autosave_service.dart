import 'dart:async';

import 'package:sqflite/sqflite.dart';

import '../../domain/resources/resource_autosave.dart';
import '../../domain/resources/resource_contracts.dart';
import '../../domain/resources/resource_revision.dart';
import '../../services/repositories/resource_tree_repository.dart';
import 'autosave_draft_recovery.dart';
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

  /// Classifies unresolved drafts, deleting the ones that are settled.
  ///
  /// The editor calls this when it opens, which is what makes
  /// `needsUserDecision` reachable for the user: text kept in
  /// `resource_autosaves` must never be stranded there (P9-M2).
  Future<List<AutosaveRecoveryOutcome>> reconcilePendingDrafts({
    ResourceId? resourceId,
  });

  /// The unresolved draft of one Part, or null.
  Future<ResourceAutosaveDraft?> pendingDraft(PartId partId);

  /// Drops a draft the user chose not to recover.
  Future<void> discardDraft(ResourceAutosaveDraft draft);
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

  /// Optimistic token this session writes each Part under.
  ///
  /// Seeded from the caller's token on the first keystroke, then advanced from
  /// the commit result on every successful write. The session — not the editor —
  /// is the source of truth, because only the session can update it
  /// synchronously with the write it just performed.
  final Map<String, String> _sessionTokens = <String, String>{};

  /// Body this session last persisted per Part, used to recognise a conflict
  /// that this session caused itself.
  final Map<String, String> _lastPersistedContent = <String, String>{};

  Timer? _timer;
  bool _disposed = false;

  /// Shared draft classifier (see [reconcilePendingDrafts]).
  AutosaveDraftRecovery get _recovery =>
      _recoveryInstance ??= AutosaveDraftRecovery(
        journal: _journal,
        treeBoundary: _tree,
        getDb: _getDb,
      );
  AutosaveDraftRecovery? _recoveryInstance;

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
    // The first keystroke seeds the session's token; afterwards the session's own
    // value wins (see `_tokenFor`).
    _sessionTokens.putIfAbsent(partId.value, () => expectedUpdatedAt);
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
  /// Delegates to [AutosaveDraftRecovery] so the Studio's "pending draft"
  /// prompt and this crash-recovery entry point share one classifier.
  @override
  Future<List<AutosaveRecoveryOutcome>> reconcilePendingDrafts({
    ResourceId? resourceId,
  }) =>
      _recovery.reconcile(resourceId: resourceId);

  /// The unresolved draft of one Part, or null. Used by the editor prompt.
  @override
  Future<ResourceAutosaveDraft?> pendingDraft(PartId partId) =>
      _recovery.findDraft(partId);

  /// Drops a draft the user chose not to recover.
  @override
  Future<void> discardDraft(ResourceAutosaveDraft draft) =>
      _recovery.discardDraft(draft);

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
    AutosaveFlushTrigger trigger, {
    bool isRetry = false,
  }) async {
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
          // The session's own token, not the caller's. See [_tokenFor].
          expectedUpdatedAt: _tokenFor(edit),
          content: edit.content,
          cause: RevisionCause.manualSave,
          checkpointId: draft.checkpointId,
          reason: trigger.displayLabel,
        ),
      );
      _sessionTokens[edit.partId.value] = result.updatedAtToken;
      _lastPersistedContent[edit.partId.value] = edit.content;
      return AutosaveWriteOutcome(
        partId: edit.partId.value,
        status: AutosaveWriteStatus.applied,
        checkpointId: draft.checkpointId,
        contentCharacters: result.contentCharacters,
      );
    } on ResourceTreeConflictException catch (error) {
      return _handleConflict(edit, draft, trigger, error, isRetry: isRetry);
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

  /// The optimistic token to write under.
  ///
  /// The session's tracked token wins once it has one. A caller-supplied token
  /// is only a seed: the editor's copy cannot be updated synchronously with a
  /// save, so trusting it would report the user's *own* previous save as a
  /// conflict and then never recover (Phase 9 audit P9-M2).
  String _tokenFor(_BufferedEdit edit) =>
      _sessionTokens[edit.partId.value] ?? edit.baseUpdatedAt;

  /// Resolves a lost CAS race without either losing text or overwriting a
  /// stranger's write.
  ///
  /// Three cases, in order:
  /// - the Part is gone → the draft cannot be applied, drop it;
  /// - the live body already equals the draft → the write landed, drop the row;
  /// - the live body equals what **this session** last persisted → the token
  ///   merely moved because of our own earlier flush, so adopt the fresh token
  ///   and retry **once**;
  /// - anything else means another writer produced that body → keep the draft
  ///   and report the conflict, so a stale edit can never overwrite it.
  Future<AutosaveWriteOutcome> _handleConflict(
    _BufferedEdit edit,
    ResourceAutosaveDraft draft,
    AutosaveFlushTrigger trigger,
    ResourceTreeConflictException error, {
    required bool isRetry,
  }) async {
    final live = await _readLivePart(edit.resourceId, edit.partId);
    final partId = edit.partId.value;

    if (live == null || live.token == null) {
      await _dropJournal(draft.checkpointId);
      return AutosaveWriteOutcome(
        partId: partId,
        status: AutosaveWriteStatus.missingTarget,
        checkpointId: draft.checkpointId,
        message: '目标段落已不存在，草稿已丢弃',
      );
    }
    if (live.content == edit.content) {
      _sessionTokens[partId] = live.token!;
      _lastPersistedContent[partId] = edit.content;
      await _dropJournal(draft.checkpointId);
      return AutosaveWriteOutcome(
        partId: partId,
        status: AutosaveWriteStatus.applied,
        checkpointId: draft.checkpointId,
        contentCharacters: edit.content.length,
      );
    }

    final selfInflicted = _lastPersistedContent[partId] == live.content;
    if (selfInflicted && !isRetry) {
      _sessionTokens[partId] = live.token!;
      return _writeOne(edit, trigger, isRetry: true);
    }

    return AutosaveWriteOutcome(
      partId: partId,
      status: AutosaveWriteStatus.conflict,
      checkpointId: draft.checkpointId,
      message: error.message,
    );
  }

  /// Live body and optimistic token of one Part, or null when it is gone.
  Future<({String? content, String? token})?> _readLivePart(
    ResourceId resourceId,
    PartId partId,
  ) async {
    final db = await _getDb();
    return db.transaction((txn) async {
      final state = await _tree.readLiveState(txn, resourceId);
      final node = state[partId.value];
      if (node == null) return null;
      final timestamps = await _tree.readNodesTimestamps(txn, partId);
      return (content: node.content, token: timestamps?.updatedAt);
    });
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
        // The token this write will actually use, so recovery can tell whether
        // the draft was typed against the state it starts from.
        baseUpdatedAt: _tokenFor(edit),
        now: now,
      ),
    );
  }

  Future<void> _dropJournal(String checkpointId) async {
    final db = await _getDb();
    await _journal.deleteDraftInTransaction(db, checkpointId);
  }
}
