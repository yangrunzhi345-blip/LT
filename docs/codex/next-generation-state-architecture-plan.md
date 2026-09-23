# Next Generation State Architecture Plan

## Objective

Define an implementation contract for the next Character State, World State,
weight/importance, and timeline work. All stored domain data must remain
locale-independent; user-facing text is produced in Presentation from stable
identifiers and typed parameters. This plan is intentionally a specification,
not a schema migration or broad rewrite.

## Git and code baseline

- Repository: `yangrunzhi345-blip/LT`
- Branch: `main`
- Baseline: `dfd41da3a4035ff483227870e0380c59b52dc848`
- `origin/main` matched the baseline at planning time (0 ahead / 0 behind).
- The worktree already contained uncommitted i18n changes in shared widgets,
  completion parameters, adventure message presentation, tests, and
  `test/helpers/localization_test_helper.dart`. Those changes are out of scope
  and must be preserved.
- Database schema version in `DatabaseService` at baseline: 44.
- No implementation changes or migrations are part of this planning phase.

## Current architecture facts

- `SceneState` is branch-local short-lived scene truth persisted as versioned
  JSON in `scene_runtime_state`.
- `AdventureRuntimeStateResolver` combines frozen adventure baselines with
  branch-local overlays. Runtime HEAD, commits, changes, and overlays are
  persisted in `adventure_runtime_heads`, `adventure_state_commits`,
  `adventure_state_changes`, and `adventure_runtime_entities`.
- Dialogue commits already coordinate narrative messages, RPG effects, scene
  state, runtime commit, overlay, and HEAD transactionally. Request IDs provide
  idempotency and expected revisions reject stale writes.
- Worldview snapshots freeze library data for an adventure. They are source
  baselines, not the mutable current world state.
- Turn Settlement is the intended structured source for current-turn state
  proposals; validators and repositories remain the authority for applying
  them.
- Existing fields such as `SceneState.recentChanges`, runtime commit/change
  `summary`/`reason`, and `RuntimeStateChangeProposal.reason` are text-bearing.
  They must not silently become localized UI event captions. Some are
  diagnostics, provenance, or narrative data and need explicit classification
  before reuse.
- `SceneDialogueEffects` still carries user/model-facing item `name` strings;
  that is dynamic content, not a stable system label, and must remain separate
  from localized event templates.

## Confirmed design risks

1. Persisting a rendered caption (for example, “受伤” or “获得技能”) makes
   timeline history locale-dependent and prevents reliable re-rendering after a
   language change.
2. Treating arbitrary narrative text as a status identifier loses user/model
   content semantics; treating it as a localized status label creates the same
   locale lock-in.
3. Adding a second event log or state authority beside Runtime HEAD and the
   scene dialogue transaction can create partial commits and conflicting reads.
4. Free-form exception text and the six recorded D-class debt groups can leak
   untranslated or sensitive diagnostics into new UI flows if new features
   forward `Exception.message`, `toString()`, or `ApiError.message`.
5. Snapshot diffs based only on display strings cannot distinguish a label
   change from a state change and cannot be deterministically replayed.

## Domain and application contract

### Stable identifiers and values

- Persist machine-stable IDs for entity, status, event type, attribute,
  importance/weight, and controlled enum values. Examples: `injured`,
  `critical`, `skill_acquired`.
- Persist numeric/mechanical values as typed values with explicit units or
  schema-defined meaning. Never persist translated labels in place of IDs.
- Display labels are resolved in Presentation from `AppLocalizations` (or a
  locale-aware content catalog for extensible user-authored definitions).
- User-authored and model-generated prose remains content. It may carry source
  locale/provenance when needed, but it is not a localization key and must not
  be rewritten as a status/event label.
- A custom status definition needs a stable `statusId` and a display-name
  content field. Built-in statuses use localization keys; custom names retain
  their author-provided value and are not falsely translated.

### Typed state events

Represent committed events as versioned, locale-neutral data, conceptually:

```text
StateEvent {
  eventId, schemaVersion, eventTypeId,
  adventureId, branchId, revision, occurredAt,
  actorId?, subjectIds[], sourceMessageId?, contextSnapshotId?,
  parameters: typed stable IDs and scalar values,
  visibility, provenance
}
```

Examples include `character_status_changed`, `skill_acquired`,
`inventory_item_granted`, `world_fact_confirmed`. Parameters reference
`characterId`, `statusId`, `skillId`, or `itemId`; they do not contain a
pre-rendered sentence. Event payloads are schema-versioned and validated at the
application boundary. Unknown event types/parameters are preserved or safely
skipped according to an explicit compatibility policy, never rendered via raw
JSON as a user message.

Events describe accepted facts. Model proposals are a separate untrusted input
type and cannot directly write events, snapshots, or runtime state.

### Snapshot, revision, and diff

- Runtime HEAD/revision remains the single current-state authority for durable
  adventure facts. SceneState remains scoped to short-lived scene truth.
- A snapshot is a reproducible projection at `(adventureId, branchId,
  revision)` and includes schema/version identity; it must not become another
  independently writable state store.
- A diff is a typed before/after change keyed by stable `(entityId, path)` and
  carries event/provenance references. Rendering a diff resolves each path and
  enum value through Presentation; it does not store localized text.
- Weight/importance is a stable enum/key such as `minor`, `normal`, `major`,
  `critical`; display labels and explanatory copy come from localization.
- Timeline order is based on committed revision and timestamp, not localized
  text or client-side sort labels.

## Error and presentation contract

- Domain/Application failures use sealed/typed errors or stable error codes
  plus typed parameters, for example
  `CharacterStateFailure.invalidTransition(currentStatusId, targetStatusId)`.
- No Domain/Service/UseCase layer may construct UI copy, accept `BuildContext`,
  or return a localized error string.
- Presentation maps typed errors to `AppLocalizations`; unknown errors map to
  a safe generic localized message while full diagnostics remain in the
  existing diagnostic channel with secrets/user content redacted.
- Never use `Exception.message`, `toString()`, or raw API errors as final UI
  copy. Do not add fallback behavior that hides failed persistence.

## Persistence and transaction boundaries

- Reuse Runtime HEAD/revision, the existing commit archive, and the atomic
  dialogue commit path for durable character/world state changes where their
  authority applies. Do not add a parallel writable authority.
- Decide whether typed events extend the existing `adventure_state_changes`
  archive or require a separate append-only event table during the first
  implementation phase. The decision must specify idempotency key, branch
  identity, revision ordering, retention, schema versioning, and atomic write
  with state changes before any migration is authored.
- A confirmed world-state change must not mutate the frozen worldview source
  snapshot. It is a branch-local overlay/event tied to its source/provenance.
- Migration requirements: old rows remain readable; migrations are
  transactional/idempotent; old free-form text is not guessed into event IDs;
  no fabricated historical events. Legacy values remain available as legacy
  content until a separately approved migration can classify them.

## D-class localization debt policy

Do not perform the cross-layer localization migration in this workstream.
Record and classify occurrences as:

- **A — new blocker:** newly added code forwards technical/raw errors or stores
  rendered copy in a new domain event/state field. Fix before acceptance.
- **B — known debt:** existing audited areas only: ImportValidationException /
  `error.toString()`; Resource Studio technical errors; Provider/LLM
  `ApiError.message`; Adventure validation/failure detail; Skill/Inventory/
  Combat/ChatEngine business event text; Linux TTS diagnostics.

Do not expand those call paths, add new consumers of their raw strings, or
include their broad migration in state feature commits. A future dedicated
Error/Event Localization Migration phase owns that cleanup.

## Implementation sequence

1. **Contract and inventory:** map current state IDs, paths, event-like text,
   authorities, read/write paths, and relevant migrations. Resolve existing
   `reason`/`summary`/`recentChanges` semantics before reusing them.
2. **Core typed models:** add locale-neutral typed failures, stable event
   models, validated payloads, typed diff/snapshot projections, and stable
   importance/status IDs. Add pure serialization/validation tests first.
3. **Atomic application:** route accepted events through existing transaction,
   revision, request-id, and stale-write guards. Keep proposals untrusted and
   preserve baseline-plus-overlay resolution.
4. **Localized presentation:** add ARB entries in all project-supported
   locales, render typed events/errors through Presentation, and keep
   user-authored/model prose distinct. Do not localize domain data in place.
5. **Feature UI:** implement status editing, world-state controls, weight
   management, and timeline views only against the accepted typed interfaces.
   Check dynamic content and 320px layouts per project UI requirements.

Each phase should be a reviewable commit and receive focused independent review
before the next phase expands scope.

## Expected areas (confirm with call-chain inventory before editing)

- Models: `lib/models/adventure_runtime_state.dart`, `scene_state.dart`,
  `scene_dialogue.dart`, and new event/error/diff model files as justified.
- Application: `lib/application/adventure/` and the existing settlement and
  commit orchestration.
- Persistence: `lib/services/database_service.dart`,
  `lib/services/repositories/adventure_repository_impl.dart`, and repository
  interfaces only if the schema decision requires it.
- Presentation/localization: the specific status/timeline widgets and all
  supported ARB/generated localization files.
- Tests: model serialization/validation, repository transaction/migration,
  settlement idempotency/stale revision, localization mapping, and responsive
  widget tests.

Do not modify Resource Library authority, TTS backend, generation streaming,
unrelated D-class pathways, or existing user work.

## Required verification and acceptance

For implementation commits, run the narrow tests first, then the required
project gates:

```bash
dart format --set-exit-if-changed .
flutter analyze
flutter test
git diff --check
```

Also search the changed production files and review every new `Text(`,
`Exception(`, `throw Exception(`, `SnackBar(`, and hard-coded Chinese string.
Confirm that no raw technical error reaches UI, no rendered caption is stored
as a domain fact, no existing D-class group was broadened, and all visible
labels use localization. For UI, validate 320px, common phone sizes, tablet,
desktop, dynamic long text, and large text scale with regression widget tests.

Acceptance requires:

1. One authoritative current-state source and atomic revisioned writes.
2. Stable IDs and typed parameters for controlled statuses, weights, and
   events; no locale-specific UI string in domain persistence.
3. User/model prose remains distinguishable from system labels and event
   templates.
4. Typed errors map to locale-specific Presentation copy; raw errors are not
   surfaced.
5. Event/diff/snapshot serialization and migrations are compatible, bounded,
   and covered by tests; no fabricated historical data.
6. All target locales have complete ARB keys and generated output.
7. No new A-class localization debt and no expansion of the six known D-class
   debt groups.
8. Required analysis/tests/format/diff checks pass and commit scope excludes
   pre-existing worktree modifications.

## Explicit non-goals

- Broad migration of the six existing D-class debt groups.
- Rewriting ChatEngine, Skill/Inventory/Combat managers, or Linux TTS.
- A second state authority, event-sourced rewrite, or broad database cleanup.
- Translating user-authored or model-generated narrative content.
- Checkpoint merge/rebase/rollback or historical backfill without a separate
  approved design.
