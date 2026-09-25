# Phase 6 - Dynamic Character Membership & Scene Presence

## 1. Baseline

Phase 5 closes at the local `main` HEAD and is synchronized with `origin/main`.
The database starts at schema version 45 after this phase.

## 2. Existing Character Architecture

Startup characters remain frozen in `AdventureConfig.selectedCharacters`.
Dynamic characters are stored as branch-local `AdventureSelectedCharacter` JSON
snapshots and are merged into the provider's effective config for context use.

## 3. Presence Authority

`SceneState.presentCharacterIds` is the authoritative participant set.
`ScenePresence.participantIds` is a compatibility projection and its actor is
validated against the authoritative set. Production participant reads use the
provider's SceneState projection.

## 4. Scene Mutation Contract

`ScenePresenceMutation` carries request ID, adventure and branch identity,
expected scene revision, enter/leave deltas, optional actor, source, and an
optional user supplied frozen character snapshot. The repository applies model
and user deltas through the same validator and transaction.

## 5. CAS / Idempotency

`scene_runtime_state.revision` is monotonic. A stale expected revision fails
closed. `scene_presence_mutation_requests` makes repeated request IDs a no-op.
SceneState and compatibility ScenePresence are written in one transaction.

## 6. Dynamic Membership

Attach is user initiated from the scene character page. The operation freezes
the selected character JSON, seeds an idempotent runtime entity, and can enter
the current scene in the same transaction. Existing startup characters cannot
be attached a second time.

## 7. Branch Isolation

Memberships are keyed by adventure and branch. Branch creation copies the source
branch membership and runtime state; subsequent branch mutations remain local.

## 8. Actor Compatibility

The actor is retained only when it is present and alive; otherwise it falls back
to the protagonist. The protagonist cannot be removed by the validator.

## 9. Context and Prompt

The provider exposes the authoritative SceneState participant list. Dynamic
membership snapshots are merged into the effective frozen config, so existing
ContextOrchestrator and WeightedContextPlanner selection includes them without a
PromptCompiler bypass. Leave removes current-scene priority while preserving
membership and runtime state.

## 10. UI and Localization

`SceneCharacterManagementPage` is opened from the conversation quick menu. It
offers present characters, enter/leave actions, and navigation to the existing
full-screen character library for attach. The layout is a SafeArea-backed,
scrollable list and keeps the protagonist protected. New labels are present in
English, Simplified Chinese, Traditional Chinese, Japanese, and Korean.

## 11. Tests and Audit

Repository tests cover validator parity, CAS conflict, request idempotency,
stale dialogue settlement, frozen attach snapshots, runtime seeding, and branch
fork isolation. Compatibility projection reads are verified against stale
`scene_presence` rows. Migration tests cover schema 45. The quick menu, session
input, and scene management tests cover navigation and 320px layout.
`flutter analyze`, focused tests, responsive widget tests, and the full Flutter
test suite pass (2234 passed, 1 skipped).

## 12. Remaining Debt

The legacy public `saveSceneState` and `saveScenePresence` methods remain for
diagnostics and backward compatibility; business mutations use the formal
mutation API. The diagnostic export remains a read-only projection and does not
yet expose branch membership as a first-class export field; membership remains
recoverable from branch state and the frozen effective config.

## Verdict

Implementation is accepted after the authority, atomicity/concurrency, context,
UI, migration, and full regression audits. No Phase 6 blocker or major finding
remains.
