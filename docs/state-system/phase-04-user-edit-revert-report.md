# Character & World State Phase 4 Report

## Baseline

- Start HEAD: `cf1de9615cc52df62372de4ea5be7a147ba37e67`
- `origin/main` matched HEAD at start.
- Database schema remains v44.

## Authority and mutation contract

User edits and reverts use `RuntimeStateMutation` and
`RuntimeStateCommitDraft`. The repository validates proposals, checks
`expectedRevision`, and writes the commit archive, changes, overlay, and
Runtime HEAD in one SQLite transaction.

## Append-only revert

Revert computes the current-to-target revision diff and writes a new commit
with `cause_type = revert`. It never changes HEAD to an old revision, deletes
commits, or removes later changes. The historical timeline remains intact.

## UI

Runtime entity cards expose a small edit form. Timeline details expose a
confirmation flow for revert. Both flows are read through the repository and
refresh by returning to the state hub; no direct SQL or writable snapshot was
added to presentation.

## Conflict and idempotency

Stale expected revisions throw `RuntimeHeadConflict`. Repeated mutation request
IDs return the already persisted commit and revision. Timeline and state reads
remain branch-scoped.

## Verification

- `flutter analyze`: passed.
- Runtime mutation, projection, dialogue runtime commit, and state hub widget
  tests: passed.
- New regression test covers user edit, stale CAS rejection, append-only
  revert, current-state projection, and preserved timeline history.

## Acceptance

Phase 4 user state editing and safe revert are implemented through the existing
runtime authority and are ready for final repository regression.
