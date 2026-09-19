import 'package:sqflite/sqflite.dart';

/// The auxiliary state a resource owns, and how a permanent delete must
/// discharge that ownership (R03-B / R03-D).
///
/// Ownership classification of every table that carries a `resource_id` (or a
/// node id derived from one):
///
/// ```text
/// table                          owned?  purge behaviour
/// -----------------------------  ------  -------------------------------
/// resources / sections / parts   yes     purged by the tree repository
/// resource_trash                 yes     the entry row itself
/// legacy row (worldview_presets, yes     purged by ILegacyLibraryRowPort
///   character_cards, npc_cards)          when the entry records the link
/// resource_revisions             yes     rows deleted; revision_nodes go
///                                        with them via ON DELETE CASCADE
/// resource_autosaves             yes     drafts for a gone resource (or a
///                                        purged node) can never be applied
/// resource_compression_jobs      yes     candidates go with the jobs via
///                                        ON DELETE CASCADE
/// resource_generation_sessions   yes     sessions of a gone resource
/// resource_blueprints            yes     blueprints of a gone resource
/// resource_generation_tasks      yes     attempts go with the tasks via
///                                        ON DELETE CASCADE
/// resource_assembly_readiness    yes     readiness of a gone resource
/// resource_assembly_entries      yes     assembly keys of a gone resource
/// resource_creation_sessions     NO      kept as an explicit tombstone: the
///                                        UNIQUE idempotency_key must keep
///                                        blocking reuse of a consumed
///                                        operation fingerprint even after
///                                        the resource is gone
/// world_entries / embeddings     NO      adventure-domain data; entity links
///                                        are free-text and not owned by the
///                                        resource tree
/// adventure_runtime_entities     NO      adventure-domain runtime state
/// ```
///
/// Anything in the "NO" group must not be cascaded: it is either a deliberate
/// tombstone or data owned by another aggregate.
abstract interface class IResourceOwnedStatePort {
  /// Deletes the auxiliary state [resourceId] owns, inside the caller's
  /// transaction.
  ///
  /// Called by the recycle bin's permanent delete so a purged resource leaves
  /// no semantically live orphan behind. When [nodeId] is non-null the purge
  /// targets one node (a Section or Part) of a still-living resource: only
  /// node-scoped rows are removed and resource-wide state is untouched.
  Future<void> purgeOwnedStateInTransaction(
    DatabaseExecutor txn, {
    required String resourceId,
    String? nodeId,
  });
}

/// Production implementation of [IResourceOwnedStatePort].
///
/// Straight `DELETE` statements on the owned tables above. Every statement
/// runs inside the transaction the trash service opened, so a failure rolls
/// the whole permanent delete back: no entry removed while auxiliary rows
/// survive, and no auxiliary rows removed while the entry survives.
final class ResourceOwnedStatePurger implements IResourceOwnedStatePort {
  ResourceOwnedStatePurger();

  @override
  Future<void> purgeOwnedStateInTransaction(
    DatabaseExecutor txn, {
    required String resourceId,
    String? nodeId,
  }) async {
    if (nodeId != null) {
      // Node-scoped purge (a Section or Part of a living resource):
      // resource-wide state stays because the resource itself stays.
      await txn.delete(
        'resource_autosaves',
        where: 'node_id = ?',
        whereArgs: [nodeId],
      );
      await txn.delete(
        'resource_compression_jobs',
        where: 'target_node_id = ?',
        whereArgs: [nodeId],
      );
      return;
    }

    // Resource-scoped purge. revision_nodes, compression_candidates and
    // generation_attempts are covered by their ON DELETE CASCADE foreign keys.
    await txn.delete(
      'resource_revisions',
      where: 'resource_id = ?',
      whereArgs: [resourceId],
    );
    await txn.delete(
      'resource_autosaves',
      where: 'resource_id = ?',
      whereArgs: [resourceId],
    );
    await txn.delete(
      'resource_compression_jobs',
      where: 'resource_id = ?',
      whereArgs: [resourceId],
    );
    await txn.delete(
      'resource_generation_sessions',
      where: 'resource_id = ?',
      whereArgs: [resourceId],
    );
    await txn.delete(
      'resource_blueprints',
      where: 'resource_id = ?',
      whereArgs: [resourceId],
    );
    await txn.delete(
      'resource_generation_tasks',
      where: 'resource_id = ?',
      whereArgs: [resourceId],
    );
    await txn.delete(
      'resource_assembly_readiness',
      where: 'resource_id = ?',
      whereArgs: [resourceId],
    );
    await txn.delete(
      'resource_assembly_entries',
      where: 'resource_id = ?',
      whereArgs: [resourceId],
    );
  }
}
