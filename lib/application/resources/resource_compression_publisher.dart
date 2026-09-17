import 'package:sqflite/sqflite.dart';

import '../../domain/resources/resource_compression.dart';
import '../../domain/resources/resource_contracts.dart';
import 'compression_job_repository.dart';
import 'resource_revision_service.dart';

/// Thrown when a candidate cannot be published because it is not a valid,
/// unapplied, part-scoped proposal.
class CompressionPublishException implements Exception {
  const CompressionPublishException(this.message);

  final String message;

  @override
  String toString() => 'CompressionPublishException: $message';
}

/// One publish request's outcome.
final class CompressionPublishOutcome {
  const CompressionPublishOutcome({
    required this.candidateId,
    required this.partId,
    required this.alreadyApplied,
    required this.savedCharacters,
    this.headRevisionId,
  });

  final String candidateId;
  final String partId;

  /// True when the candidate had already been published (or its text already
  /// matches the Part), so this call changed nothing.
  final bool alreadyApplied;

  final int savedCharacters;
  final ResourceRevisionId? headRevisionId;
}

/// Publishes validated compression candidates as the resource head.
///
/// This is the Phase 9 half of the Phase 8 contract. Phase 8 only ever wrote
/// candidates with `applied_at = NULL`; nothing there could replace a resource
/// head. Publishing is therefore an explicit operation with a revision boundary:
///
/// ```text
/// current head  →  before revision (cause: compression)
///               →  Part body replaced, section verdict + task state synced
///               →  after revision becomes the head
///               →  candidate marked applied
/// ```
///
/// All of it commits together. A crash or a failed write leaves both the body
/// and `applied_at` untouched, so a candidate is never half-published.
final class CompressionPublisher {
  CompressionPublisher({
    required ICompressionJobRepository jobRepository,
    required ResourceRevisionService revisionService,
    required Future<Database> Function() getDb,
  })  : _jobs = jobRepository,
        _revisions = revisionService,
        _getDb = getDb;

  final ICompressionJobRepository _jobs;
  final ResourceRevisionService _revisions;
  final Future<Database> Function() _getDb;

  /// Candidates of [resourceId] that can be published right now.
  Future<List<CompressionCandidate>> publishableCandidates(
    ResourceId resourceId,
  ) =>
      _jobs.findPublishableCandidates(resourceId.value);

  /// Publishes one candidate.
  ///
  /// The claim on `applied_at` is written first, inside the same transaction as
  /// the body: a second publish of the same candidate loses the guarded update
  /// and rolls back instead of writing the text twice.
  Future<CompressionPublishOutcome> publish(String candidateId) async {
    final db = await _getDb();
    final now = DateTime.now().toIso8601String();

    return db.transaction((txn) async {
      final candidate =
          await _jobs.findCandidateInTransaction(txn, candidateId);
      if (candidate == null) {
        throw CompressionPublishException('压缩候选不存在：$candidateId');
      }
      if (!candidate.isValidated) {
        throw CompressionPublishException(
          '压缩候选未通过校验，拒绝发布：${candidate.validationMessage}',
        );
      }
      if (candidate.scope != CompressionScope.part) {
        // A section-scoped candidate has no per-Part mapping, so publishing it
        // would have to guess a split. That mapping is deliberately not
        // invented here.
        throw CompressionPublishException(
          '暂不支持发布章节级压缩结果（缺少逐段映射）：$candidateId',
        );
      }
      if (!candidate.isCandidateOnly) {
        return CompressionPublishOutcome(
          candidateId: candidateId,
          partId: candidate.targetNodeId,
          alreadyApplied: true,
          savedCharacters: 0,
          headRevisionId: null,
        );
      }

      final claimed = await _jobs.markCandidateAppliedInTransaction(
        txn,
        candidateId: candidateId,
        appliedAt: now,
      );
      if (!claimed) {
        throw CompressionPublishException('压缩候选已被并发发布：$candidateId');
      }

      final result = await _revisions.publishCompressedContentInTransaction(
        txn,
        candidateId: candidateId,
        partId: candidate.targetNodeId,
        resourceId: candidate.resourceId,
        compressedContent: candidate.compressedContent,
        originalCharacters: candidate.originalCharacters,
      );

      // The inner call returns early when the body already equals the candidate.
      // Reporting that as a fresh publish would claim savings and a new history
      // entry that do not exist (audit P9-M4).
      return CompressionPublishOutcome(
        candidateId: candidateId,
        partId: candidate.targetNodeId,
        alreadyApplied: result.alreadyApplied,
        savedCharacters: result.alreadyApplied ? 0 : candidate.savedCharacters,
        headRevisionId: result.headRevisionId,
      );
    });
  }
}
