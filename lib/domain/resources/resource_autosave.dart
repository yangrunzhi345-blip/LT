import 'resource_contracts.dart';

/// Base type for autosave failures.
class ResourceAutosaveException implements Exception {
  const ResourceAutosaveException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// One unresolved edit draft.
///
/// The draft is a write-ahead journal entry, not a second copy of the resource:
/// it only exists between "the user stopped typing long enough" and "the tree
/// accepted the write". A normal streaming generation never creates one, which
/// is what keeps every LLM chunk out of SQLite.
final class ResourceAutosaveDraft {
  const ResourceAutosaveDraft({
    required this.checkpointId,
    required this.resourceId,
    required this.partId,
    required this.content,
    required this.contentHash,
    required this.baseUpdatedAt,
    this.createdAtToken = '',
    this.updatedAtToken = '',
  });

  final String checkpointId;
  final ResourceId resourceId;
  final PartId partId;
  final String content;

  /// Hash of [content], computed with the project's single content hasher.
  final String contentHash;

  /// The `resource_parts.updated_at` token the draft was typed against.
  ///
  /// Recovery uses it to tell "the tree already contains this draft" apart from
  /// "the tree moved on and this draft needs a conflict decision".
  final String baseUpdatedAt;

  final String createdAtToken;
  final String updatedAtToken;

  /// Copy used when a later keystroke replaces the buffered content while the
  /// draft is still unresolved.
  ResourceAutosaveDraft withContent({
    required String content,
    required String contentHash,
    required String updatedAtToken,
  }) =>
      ResourceAutosaveDraft(
        checkpointId: checkpointId,
        resourceId: resourceId,
        partId: partId,
        content: content,
        contentHash: contentHash,
        baseUpdatedAt: baseUpdatedAt,
        createdAtToken: createdAtToken,
        updatedAtToken: updatedAtToken,
      );

  @override
  String toString() =>
      'ResourceAutosaveDraft($checkpointId, $partId, ${content.length} chars)';
}

/// What recovery decided for one stored draft.
enum AutosaveRecoveryDisposition {
  /// The live Part already holds exactly this content: the write landed and the
  /// journal row is stale. The draft is dropped.
  alreadyApplied,

  /// The live Part moved past the draft's base token, or holds different
  /// content: the draft is a real unsaved edit the user must decide about.
  needsUserDecision,

  /// The target Part no longer exists (deleted or unreachable). The draft
  /// cannot be applied and is dropped.
  orphaned;

  String get displayLabel => switch (this) {
        AutosaveRecoveryDisposition.alreadyApplied => '已写入，草稿清理',
        AutosaveRecoveryDisposition.needsUserDecision => '存在未保存编辑',
        AutosaveRecoveryDisposition.orphaned => '目标已不存在，草稿丢弃',
      };
}

/// One recovery verdict produced by `reconcilePendingDrafts`.
final class AutosaveRecoveryOutcome {
  const AutosaveRecoveryOutcome({
    required this.draft,
    required this.disposition,
    this.liveContentHash = '',
  });

  final ResourceAutosaveDraft draft;
  final AutosaveRecoveryDisposition disposition;
  final String liveContentHash;

  bool get isResolved =>
      disposition != AutosaveRecoveryDisposition.needsUserDecision;
}

/// Autosave timing policy.
///
/// One place for the debounce number so the editor, the tests and the final
/// flush all agree, and so no page invents its own millisecond value.
abstract final class AutosavePolicy {
  /// How long typing must pause before a checkpoint is written.
  ///
  /// Chosen to be long enough that ordinary typing produces one write instead
  /// of one per keystroke, and short enough that a checkpoint normally exists
  /// before the user can navigate away.
  static const Duration debounce = Duration(milliseconds: 700);

  /// Hard cap on how long an edit may stay only in memory while typing
  /// continues without pause, so a fast typist still gets periodic checkpoints.
  static const Duration maxBufferedAge = Duration(seconds: 5);
}
