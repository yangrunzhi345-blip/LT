import 'package:sqflite/sqflite.dart';

import '../../domain/resources/resource_autosave.dart';
import '../../domain/resources/resource_contracts.dart';
import '../../services/repositories/resource_tree_repository.dart';
import 'resource_autosave_repository.dart';

/// Classifies autosave drafts that never reached the content tree.
///
/// Extracted from `ResourceAutosaveService` for two reasons:
/// - the Studio needs to look at pending drafts when an editor opens, and it
///   must not have to own a debounce buffer to do so;
/// - there is then exactly one implementation of the
///   `alreadyApplied` / `needsUserDecision` / `orphaned` decision, so the UI and
///   the crash-recovery path cannot drift apart.
///
/// This is the production recovery path for [AutosaveRecoveryDisposition.
/// needsUserDecision]: without a caller, text kept in `resource_autosaves` is
/// unreachable for the user (Phase 9 audit P9-M2).
final class AutosaveDraftRecovery {
  AutosaveDraftRecovery({
    required IResourceAutosaveRepository journal,
    required IResourceTreeRevisionBoundary treeBoundary,
    required Future<Database> Function() getDb,
  })  : _journal = journal,
        _tree = treeBoundary,
        _getDb = getDb;

  final IResourceAutosaveRepository _journal;
  final IResourceTreeRevisionBoundary _tree;
  final Future<Database> Function() _getDb;

  /// Classifies every unresolved draft, deleting the ones that are settled.
  ///
  /// Rows whose content already matches the live Part are dropped as applied;
  /// rows whose target disappeared are dropped as orphaned; rows that are
  /// genuinely newer than the tree are kept and reported so the user can decide.
  Future<List<AutosaveRecoveryOutcome>> reconcile(
      {ResourceId? resourceId}) async {
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

  /// The unresolved draft of one Part, or null.
  Future<ResourceAutosaveDraft?> findDraft(PartId partId) =>
      _journal.findDraft(partId.value);

  /// Drops a draft the user chose not to recover.
  Future<void> discardDraft(ResourceAutosaveDraft draft) async {
    final db = await _getDb();
    await _journal.deleteDraftInTransaction(db, draft.checkpointId);
  }
}
