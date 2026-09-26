# Turn State UI Implementation Report

## Baseline / final state

- Baseline HEAD: `88e04d36e332de8aad0e41eda9038c99f63a5c39`.
- Final HEAD: implementation commit containing this report (`HEAD`).
- Schema before/after: unchanged (v46). **NO DATABASE MIGRATION REQUIRED.**

## Contract and authority

`scene_dialogue_turns` remains the branch-local dialogue authority. The new
`TurnStateChangeGroup` projection derives a one-based ordinal from the
branch-scoped SQLite row cursor and joins accepted runtime commits and changes
in repository code. Runtime HEAD, commit archive, replay, resolver, and
comparison remain the only state authorities. The projection is never written
back to SQLite and does not move HEAD.

## User interface

The existing State Hub now exposes a story-turn history alongside current
character/world views and exact revision history. Turn cards show localized
turn labels, change counts, and revision ranges; selecting a card opens
`TurnStateDetailPage`, which groups every accepted change in that turn by
runtime entity and shows before/after values and reasons. Existing entity
history, initial-state, comparison, checkpoint, and append-only restore flows
remain the shared implementation.

Current character cards include frozen adventure membership when no overlay has
been written yet, while runtime overlays remain branch-local. World, location,
faction, and relationship entities continue to use the existing typed runtime
registry and entity history query.

## Branch, retry, legacy, and dynamic membership

- Every turn query requires adventure and branch IDs and uses a bounded row
  cursor; tests cover branch isolation.
- Retries reuse the existing request ID uniqueness contract and do not create a
  duplicate turn.
- Runtime commits without a dialogue row remain in the existing legacy/runtime
  revision timeline and are never assigned a fabricated turn number.
- Baseline supporting characters are projected only from the frozen adventure
  membership; no historical rows are synthesized for them.

## Performance and localization

Turn pages use one bounded turn query plus batched commit/change queries; the UI
does not replay snapshots or issue one query per card. New turn and revision
range labels are present in all six ARB locales and generated localization
sources. The existing State Hub responsive coverage remains active for 320,
360, 390, 412, and 768 logical pixel widths.

## Verification

- `flutter analyze`: passes with one pre-existing unused import in
  `test/widget/runtime_state_hub_test.dart`.
- `flutter test test/unit/runtime_projection_test.dart`: passed, including turn
  grouping and cursor/branch isolation.
- `flutter test test/widget/runtime_state_hub_test.dart`: passed at all
  required viewport sizes.
- `dart format ...`: passed.
- `git diff --check`: passed.

## Audit rounds

### Round 1 — Authority

Passed: no second runtime state/history store, no UI SQL, no CharacterCard or
World Resource mutation, and no turn projection persistence.

### Round 2 — Historical correctness

Passed for the implemented contract: turn ordinals are branch-local row-order
projections, revisions remain independent, all changes for a request are
grouped, retry is idempotent, and legacy rows are not guessed into turns.

### Round 3 — UX / performance

Passed for the covered State Hub and turn detail flow: bounded repository
queries, localized labels, narrow viewport widget coverage, long entity IDs,
and existing revision navigation remain intact.

## Remaining debt

The existing archive schema enforces one runtime commit per request ID. It
therefore cannot currently produce multiple commits for one dialogue request;
the projection is ready to group multiple matching commits if that invariant is
relaxed in a future migration. Dedicated world/location/faction detail shells,
message excerpts, and richer field metadata are follow-up presentation work.

## Verdict

Turn-based state presentation is implemented on the existing Runtime State
authority without a schema migration. The remaining items above are explicitly
outside this incremental delivery and do not alter persisted state semantics.
