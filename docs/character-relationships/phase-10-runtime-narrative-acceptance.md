# Phase 10 — Relationship Runtime Integration & Narrative Intelligence

## STATUS

Status: RELEASE READY; acceptance pending push verification.
Acceptance Mode: Independent Review.

## BASELINE

Recovery branch: `main`. Start HEAD and local `origin/main`:
`e7d103c33ac7dec392e54bde86c8970f6a274d34`.
Start worktree: 12 tracked modifications and 5 untracked Phase 10 artifacts.
Database schema: 48 at recovery; 48 after implementation. Migration: NONE.
Dependencies and application version: unchanged.

## RECOVERY ASSESSMENT

Resume reason: previous model/API quota exhausted during independent audit
repair. All correct unfinished implementation was preserved. Recovery inspected
status, branch, HEAD/origin, history, staged/unstaged diff and each untracked
artifact. No reset, clean, checkout, restore or stash was used.

The original MAJOR was missing typed schema numeric bounds during settlement.
The fresh independent review identified eight additional MAJOR findings and
comments C1/C2, all addressed within the same relationship/runtime subsystem.
Previous verification claims are superseded by the final runs listed below.

## ARCHITECTURE

Resource Relationship → frozen Adventure snapshot → branch-local runtime
projection → ContextOrchestrator → NarrativeContext → WeightedContextPlanner
→ PromptCompiler → existing turn settlement → RuntimeStateMutation → typed
state events → timeline/replay → branch-isolated state.

No new relationship persistence authority or separate mutation pipeline.
`SceneState.presentCharacterIds` is the sole relationship presence authority;
legacy participant ids are derived compatibility data.

## RUNTIME AUTHORITY

Existing `AdventureRepositoryImpl` owns settlement, SQLite overlay writes,
commit/change archive and runtime HEAD updates. Complete effective state reads
have no default entity LIMIT; explicit archive retrieval remains bounded.
Frozen relationship id is the runtime identity. Names are presentation data.

## RESOURCE / SNAPSHOT / RUNTIME BOUNDARIES

Resource edits never rewrite an existing Adventure snapshot; runtime writes
never update Resource Library edges. Real SQLite tests cover runtime enemy
while Resource remains friend, later Resource edits, soft deletion and permanent
purge. Frozen snapshot, runtime overlay and replay survive resource deletion.
Missing relationship entities in old forks are seeded idempotently from frozen
Adventure config, with branch/generation guards and no events or resource read.

## STATE CONTRACT

Existing typed registry defines relationship labels, aliases, strength
[-100, 100], notes and shared status. `relation_type`, `relationship_type` and
`type` normalize to `relationship` before duplicate detection and persistence.
Registry entity membership, kind and bounds cannot fall through a legacy
validator. Explicit empty notes clear snapshot prose; remove restores baseline.

## CONTEXT INTEGRATION

Runtime effective relation/strength/notes enter ContextOrchestrator and
NarrativeContext using the current branch's runtime overlay and revision.
Relationship identities are excluded from generic runtime memory to prevent
weight bypass and duplicate records, including character/relationship id
collisions. Prompt preview uses a separate builder and preserves the active
turn's relationships and ContextTrace, proven with an asynchronous barrier.

## WEIGHTED PLANNING

Deterministic relevance uses authoritative scene presence, protagonist,
mentioned names, runtime changes and stable identity tie-breaking. Unrelated
unchanged edges are filtered; relevance caps at 24 records. The relationship
source uses the existing weighted planner, with a 1536-token maximum.
Rendering keeps complete records within the allocated budget; names, labels
and notes are individually bounded. Zero weight removes all relationship data.
Trace records identity, participants, effective value, source/reason, revision,
weight and actual inclusion. Excluded token costs are zero; total counts actual
relationship source and framing once.

## PROMPT CONTRACT

PromptCompiler consumes only planned relationship context. Labels and notes
are explicitly untrusted data, with escaped delimiters and complete framing.
The existing production settlement request receives the same planned records,
frozen ids, effective values and typed field contract. No relationship/monitor
candidates retains the empty-mutation contract. A real ChatEngine/SQLite test
verifies settlement followed by next-turn effective prompt generation.

## MUTATION

Relationship mutation uses existing validation and commit transaction. Alias
collisions are deduplicated consistently in ChatEngine and explicit/legacy
merge. Unsupported entity paths, unknown frozen ids, invalid values and empty
relation labels fail without persisted mutation. Narrative output is settled
through the existing second request and commit boundary.

## BOUNDED NUMERIC VALIDATION

Original MAJOR: strength 90 + delta 20 could persist 110 despite schema
[-100, 100]. Existing bounded numeric policy clamps valid signed increments.
`_applyRuntimeMutation` now supplies typed registry min/max to the existing
settlement operation before overlay, event, revision or HEAD writes.

Real SQLite cases: 90+20=100; -90-20=-100; 100+1=100; -100-1=-100;
90+10=100; -90-10=-100. Persisted state, typed event, timeline, replay,
context and prompt agree. Saturated no-op does not advance revision or consume
request identity. Invalid absolute set is rejected and corrected retry succeeds.
A temporary bounds-removal mutation reproduced 110 versus expected 100 and was
restored before final checks.

## CAS

Stale expectedRevision cannot commit. Tests verify no state/event/HEAD change
and valid retry under the current revision.

## IDEMPOTENCY

Repeated requestId does not duplicate commits. Rejected values, no-op clamp and
transaction failures do not incorrectly reserve requestId; corrected retries
follow the existing contract.

## REPLAY

Replay follows the target runtime HEAD's immutable commit-parent ancestry,
including inherited fork fields and excluding subsequent parent changes.
Current, SQLite and replay agree after reopen. A production fixture with 301
relationships verifies that an old enemy/90 overlay survives 300 newer entities
and subsequent settlement produces 100. Temporarily restoring LIMIT 256 makes
this test fail (256 actual versus 301 expected); the probe was restored.

## REVERT

Revert appends a new commit/event; it does not delete old history. Tests cover
ally → enemy → ally and alias normalization, including an inherited revision.

## BRANCH ISOLATION

Parent, fork and nested fork keep separate effective state, timeline, replay
and compiled context. Tests cover divergent enemy/ally values, parent changes
following a fork, inherited strength and nested branch preservation.

## TIMELINE

Existing typed relationship_changed events carry settled before/after values
and revision. UI exposes safe relationship labels and ally → enemy changes,
while technical ids and protocol/SQL data remain filtered. Historical
relationship-label tests were updated with explicit technical-id negative cases
rather than removing the safety contract.

## UI

Existing Runtime State Hub/detail/edit components are reused. Editing presents
one canonical relationship field, safe values and contextual actions; only
explicitly touched/reset fields are submitted. Multiline fields use a matching
keyboard type. No decorative icons, new gradients or unrelated UI redesign.

## I18N

Strength/notes labels are in all six ARB files (en, ja, ko, zh, zh_Hans,
zh_Hant), with generated localization output updated. Existing relationship
labels are reused for context weights and aliases.

## RESPONSIVE

Relationship detail → edit → save is exercised at 320, 360, 390, 412, 768,
1280×800 and 1280×900, using long names/notes and 1.5 text scale. Save remains
reachable; no Flutter layout exceptions or exposed raw relationship ids.
Existing light/dark, localization and workbench navigation coverage remains.

## TESTS

Final targeted suite: 259 PASS, 0 FAIL (expanded reporter, exit 0).
Final full flutter test --no-pub -r expanded: 3276 PASS, 2 existing conditional
skips, 0 FAIL (3 minutes 4 seconds, exit 0). This run started after other tests
and builds finished. The unchanged UI offload threshold passed at 5.29 ms.
Skips: Chrome-only TTS requires --platform chrome; the production real-model
TTS test requires LT_TTS_REAL_MODEL=1 and its dedicated validation directory.
Final flutter analyze --no-pub: PASS, no issues (7.7 seconds, exit 0).
Final dart format .: PASS, 807 files, 0 changed.
Final git diff --check: PASS.

Negative evidence includes rejected typed/cross-entity mutations, stale CAS,
corrected retry, saturated no-op and an SQLite HEAD-write trigger failure.
The trigger failure rolls back state, events and revision atomically, then a
valid retry succeeds. Temporary mutation probes are restored.

One initial post-remediation full run failed only the historical presentation
assertion (friend expected hidden). It was corrected with stronger safe-label
and internal-id coverage. A later concurrent run failed the unchanged semantic
retrieval performance threshold (32.963 ms versus <16.7 ms); tests and builds
were then finished before a new whole-suite run. No threshold, skip or production
retrieval logic was changed. Only the final complete rerun is release evidence.

## BUILDS

Final flutter build linux: PASS (exit 0),
`build/linux/x64/release/bundle/lt_dialogue`.
Final flutter build apk --debug: PASS (exit 0),
`build/app/outputs/flutter-apk/app-debug.apk`.
Other platform builds and external live-model/manual-device assessment:
NOT RUN — outside the available Linux/Android verification environment.

## AUDIT

Fresh Independent Review by `/root/phase10_independent_audit`, read-only.
Final result: PASSED. Remaining BLOCKER = 0, MAJOR = 0, MINOR = 0, INFO = 0.
Reviewer independently ran 29 relationship/settlement/branch/viewport tests,
the enhanced 301-entity production test (1 PASS), flutter analyze (no issues)
and git diff --check (PASS). The reviewer explicitly separated the passed
code audit from the still-pending final release/full-test/push gates.

| Finding | Remediation | Evidence |
| --- | --- | --- |
| Original strength bounds MAJOR | Registry bounds at settlement authority | Six SQLite cases, atomicity and mutation probe |
| M1 production settlement omission | Planned relationship records and registry contract | Real ChatEngine → SQLite → next prompt |
| M2 typed validation fallback | Registry membership/kind are final authority | Cross-entity/invalid-value negative cases |
| M3 empty notes fallback | Empty string clears; absence restores | SQLite current/replay/context assertions |
| M4 fork ancestry replay | Follow immutable target HEAD ancestors | Parent, fork, nested fork and inherited revert |
| M5 alias history conflicts | Canonical path in validation/dedupe/merge | Alias mutation/revert and single UI field |
| M6 preview stale/race | Separate preview builder, current runtime | Paused asynchronous narrative/preview/resume |
| M7 old forks lack relationship identities | Idempotent snapshot seed on switch | Real AdventureProvider and SQLite |
| M8 limited reads lose old overlays | Default complete entity read | 301-relationship production loop and mutation probe |
| C1 opaque values/editing | Visible safe values, localized canonical edit | Technical-id negatives and seven viewport saves |
| C2 truncated records/misleading trace | Whole-record allocation and actual token cost | Weight 0/100, long notes, inclusion/total assertions |

Independent verification logs are temporary files under /tmp and are not
committed. Final acceptance incorporates the review; it is not self-declared
Independent Review by the implementing agent.

## GIT

Existing history is preserved. Task artifacts alone are staged; logs, user
databases, build outputs, dependencies, credentials and unrelated files are
excluded. Implementation commit/push and fetched HEAD equality: PENDING.
The acceptance record will be finalized after successful remote verification.

## FINAL VERDICT

Relationship Runtime Integration Phase 10: implementation, validation, builds
and Independent Review passed. Final ACCEPTED awaits commit/push and fetched
clean-worktree/HEAD equality verification.
