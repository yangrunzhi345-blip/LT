# Turn State Presentation Contract

## Baseline

- Repository baseline: `88e04d36e332de8aad0e41eda9038c99f63a5c39` (`origin/main` after `git fetch origin`).
- Runtime schema remains the existing `adventure_runtime_heads`, `adventure_runtime_entities`, `adventure_state_commits`, and `adventure_state_changes` archive.
- `scene_dialogue_turns` is the persisted dialogue-turn authority. It is keyed by `request_id`, scoped by `adventure_id` and `branch_id`, and stores creation time, assistant message identity, context snapshot identity, and diagnostics.

## Confirmed authority and call chain

```text
Adventure + branch
  -> scene_dialogue_turns(request_id)
  -> adventure_state_commits(request_id, branch_id, revision)
  -> adventure_state_changes(commit_id, before/after/provenance)
  -> Runtime HEAD / replay projection
  -> AdventureRuntimeStateResolver + RuntimeEffectiveStateView
```

`commitSceneDialogueTurn` performs the dialogue transaction and is idempotent on `request_id`. Runtime mutations are validated and appended by `_applyRuntimeMutation`; HEAD is branch-local and revisions are machine coordinates. `getRuntimeTimeline` performs bounded cursor pagination and repository-side entity filtering. `getRuntimeStateAtRevision` replays the archive and is read-only.

## Turn number semantics

The current schema has no persisted ordinal column. A presentation ordinal is therefore derived in the repository read model from the stable `scene_dialogue_turns` insertion order (`rowid ASC`) after filtering by `(adventure_id, branch_id)`. It is one-based, branch-local, and must never be calculated from message count. Retry requests reuse the same `request_id` and therefore do not create a second turn row.

This ordinal is a display coordinate only. It is not persisted state and does not replace runtime revision.

## Turn → commit mapping

- A normal dialogue request maps to its request-id commit. Additional commits
  can be grouped into the same turn when their persisted `cause_ref` points to
  that turn request ID; this preserves the existing request-id uniqueness
  constraint while supporting a one-turn/multiple-commit read projection.
- A turn can contain multiple change rows in one commit; the read model groups all changes by turn before presentation.
- Non-dialogue commits (manual edit, system rule, revert, import, or legacy rows) have no reliable turn row and must be presented as independent history events with an unknown/legacy turn label.
- No database migration is required for the first presentation release. Adding a turn foreign key or ordinal would change the established archive contract and is not necessary to safely render existing provenance.

## Read-model rules

Presentation models are immutable projections only. They must retain adventure and branch scope, turn ordinal, request/message references, revision range, entity type/id, path, before/after values, cause/provenance, and legacy status. They must not persist current state, duplicate snapshots, write HEAD, or become a restore authority.

Turn history queries must page by a revision/row cursor, filter entity types in SQL/repository code, and batch-load changes/messages. UI must not scan chat text or replay from revision zero for timeline cells.

## Baseline/current and entity semantics

- Current character/world state is `frozen AdventureConfig baseline + branch Runtime HEAD`, resolved through `AdventureRuntimeStateResolver` / `RuntimeEffectiveStateView`.
- Initial is the frozen adventure baseline, never the mutable Resource Library card.
- Historical values use archive replay or persisted before/after changes on demand.
- Entity types are the existing `character`, `npc`, `world`, `location`, `faction`, and `relationship` enum values. Unknown/legacy paths remain safe debug-compatible values and are not fabricated into domain fields.
- Runtime visibility/provenance is authoritative. Only accepted runtime changes are shown as current facts; proposals are not treated as state.
- Dynamic membership is governed by existing adventure membership/baseline data. No history is fabricated before an entity exists.
- All reads are branch isolated. Legacy rows without usable provenance show an explicit legacy/unknown-turn event.

## Acceptance gates for implementation

1. Add read-only turn/entity presentation models and repository queries without a second state store or schema migration.
2. Expose dashboard, character, world/location/faction/relationship, and turn-detail navigation from the existing State Hub/session entry.
3. Keep revision history/checkpoint/compare/revert flows shared with the existing implementation.
4. Localize all user-visible labels and validate long text at 320 logical pixels and larger required viewports.
5. Add repository and widget regression tests for grouping, multi-entity changes, retry, branch isolation, legacy, dynamic membership, and navigation.

## Known limitations to preserve explicitly

The current database cannot represent multiple runtime commits with the same dialogue request ID. The presentation query therefore uses explicit
`cause_ref` provenance for additional commits and never infers a relationship
from revision adjacency. Manual/system/revert/import history without that
provenance remains a separate event class.
