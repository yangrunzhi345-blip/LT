# Phase 10 — Runtime Relationship and Narrative Integration

Status: implementation scope

This phase extends the existing branch-local typed runtime state archive. It
does not create a relationship repository, relationship timeline, or database
authority. Resource relationships remain the source library authority;
`AdventureConfig.characterRelationships` is the creation-time snapshot; and
`RuntimeEntityType.relationship` overlays are the branch-local effective
state.

## Contract

- A relationship runtime entity is keyed by the frozen snapshot relationship
  `id`, with endpoint ids retained in the snapshot. Display names never form a
  state key.
- Runtime overlays use the existing typed state paths. `relationship` is the
  compatibility path for the effective relation label; `relation_type`,
  `relationship_type`, `status`, `strength`, and `notes` are validated typed
  fields for relationship entities. Type aliases (`relation_type`,
  `relationship_type`, `type`) normalize to `relationship` before duplicate
  detection and persistence, so updates and revert have one history.
- Runtime changes use the existing `RuntimeStateMutation` transaction,
  expected revision CAS, request idempotency, append-only commits, replay, and
  revert. Only relationships present in the frozen snapshot may be changed.
- Adventure creation seeds relationship runtime entities from the frozen
  snapshot. Resource edits are never read after creation and runtime commits
  never write to resource tables.

## Narrative path

`ContextOrchestrator` projects the snapshot plus branch-local overlays through a
deterministic relevance planner. Scene presence comes only from
`SceneState.presentCharacterIds`; protagonist and mentioned ids receive stable
priority, while unrelated unchanged edges are filtered. The selected records
enter the existing `WeightedContextPlanner` under a `relationship` source and
are rendered by `PromptCompiler` as bounded, explicitly untrusted relationship
data. `ContextTrace` records the relationship id, participants, effective
value, selection reason, revision, and token cost.

## Acceptance

The implementation must cover snapshot isolation, ally-to-enemy runtime
mutation, CAS and request idempotency, replay and append-only revert, branch
isolation, scene/protagonist relevance and budget bounds, deterministic prompt
ordering, untrusted relationship notes, timeline before/after/revision data,
runtime state presentation, localization, and compact/medium/wide layouts.

## Quota interruption recovery

Baseline: `e7d103c33ac7dec392e54bde86c8970f6a274d34` on `main`, equal to
the local `origin/main` at recovery. Preserve all twelve modified files and
five untracked Phase 10 artifacts. Do not reset, clean, restore or stash.

The previous independent audit's MAJOR is an omitted typed schema numeric
range in `_applyRuntimeMutation`: `90 + 20` persisted strength `110`. Existing
settlement policy clamps bounded numeric increments. Feed the registry's
`minimum` / `maximum` into the existing settlement operation before state,
events and revision writes; do not create a relationship validation authority.

Real SQLite regressions must cover `90 + 20`, `-90 - 20`, `100 + 1`,
`-100 - 1`, `90 + 10`, `-90 - 10`; persisted overlays, typed events, timeline,
replay, context and prompt must agree. No-op clamp must not advance revision;
invalid sets and transaction failures must not consume request identity.
Verify CAS and retry, alias updates/revert, resource mutation/delete/purge
isolation, branch context/prompt isolation and responsive relationship rows.

Release gates: targeted tests, whole-repository formatting, diff check,
`flutter analyze --no-pub`, `flutter test --no-pub`, Linux and available Android
builds, then a fresh independent audit. Fix all BLOCKER/MAJOR findings before
updating the single acceptance record, committing, pushing `origin main`,
fetching and verifying a clean worktree and matching HEAD / origin/main.

## Independent audit remediation specification

The fresh review found eight additional MAJOR findings and two review comments.
These are required within Phase 10, rather than new subsystems:

1. **Production settlement contract:** pass the actual budget-approved
   relationship records from `PromptBuilder` to the existing second-turn
   settlement request. Supply frozen identities, effective values and fields
   from `RuntimeStateSchemaRegistry`; never ask the model to invent identities.
   A real ChatEngine turn and SQLite archive must prove narrative → settlement
   → runtime overlay → next-turn prompt integration.
2. **Typed validation bypass:** registry entity membership and value kind are
   authoritative. Delete the fallback that accepted a failed typed schema
   check. Numeric deltas are finite and match numeric kind; absolute bounds
   apply at settlement. Empty relation labels and cross-entity paths fail
   without events, revision advancement or request-id consumption.
3. **Empty notes:** an explicit empty runtime string clears snapshot notes;
   only absence/removal falls back to the frozen snapshot.
4. **Inherited replay:** replay follows the target branch HEAD's immutable
   commit-parent ancestry, including inherited values and excluding later
   parent changes. Do not substitute the parent branch's current HEAD or replay
   branch-local commits alone. Raw SQL fixtures must include real runtime
   heads. Cover nested forks and revert to an inherited revision.
5. **Canonical relation aliases:** normalize relation type spellings before
   validation, duplicate detection, explicit/legacy merge and persistence.
   Revert and UI edits must use one canonical path.
6. **Preview concurrency:** a prompt preview uses a separate builder and
   current branch runtime data. It must not replace active-turn planned
   relationships or ContextTrace. Verify using a paused asynchronous narrative
   request, preview, resume, real settlement and persisted trace.
7. **Existing forks:** switching to a fork predating relationship seeding
   idempotently registers missing entities from the frozen Adventure config,
   with stale generation/branch guards and no resource-library read or event.
8. **Complete effective reads:** `getRuntimeEntities` defaults to an unlimited
   state read (`limit: null`), while explicitly bounded archive/display callers
   retain their limit. An older relationship overlay must survive 300 newer
   seeded entities in Current, replay, narrative prompt and settlement. Verify
   the real production turn and that a temporary old LIMIT 256 reproduces the
   failure; restore the probe before release checks.

**C1 — readable editing:** relationship values and timeline diffs are visible
while technical ids remain filtered. Localize strength/notes in every ARB;
offer one canonical relation field; submit only touched/reset fields. Exercise
detail, edit and save at 320/360/390/412/768/1280×800/1280×900 with long names,
notes and 1.5 text scale.

**C2 — bounded record integrity:** fit complete ranked relationship records
inside the existing weighted allocation; cap each name/label/note and retain
untrusted-data delimiters. Trace decisions and total token estimates match
actual inclusion, counting relationship framing once and excluded records zero.
Relationship
entities never re-enter via generic runtime memory, even when their identity
matches a character identity or relationship weight is zero.

Do not modify database version, dependencies, resource ownership, branch
history, or unrelated UI. Verification must use real SQLite persistence;
negative/mutation probes must be restored before the final gates. The single
acceptance record records both the original bounds finding and these review
remediations, with final independent findings and current verification counts.
