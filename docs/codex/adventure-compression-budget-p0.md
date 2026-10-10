# Android adventure compression / generation budget P0

STATUS: INTEGRATED ACCEPTANCE PASS — local code, SQLite, Widget and build validation complete; Android device validation NOT COMPLETED.
Acceptance Mode: Integrated Single-Agent Full-Cycle.
No push, release, version bump or production signing is authorized in this task.

## Baseline and evidence boundaries

The clean starting HEAD was `7e5a409dd4e2e322d0d9eb85dfd8695284550df0` on the previously pushed `fix/android-adventure-readiness` branch. It contains readiness/save fixes `4be8aff`, the v1.2.05 build configuration `0558707`, and release evidence. This task uses local branch `fix/adventure-compression-lifecycle`.

Fetched `origin/main` is `b060462fd98bdf4af72da9cd106287981f3af7c8`; its extra commit changes no code compared with `12ed66f`. Before this task's commit, the repair branch has three commits ahead / one empty commit behind main. We preserve this history; we did not reset, rewrite published commits, replace user changes or merge main under a misleading baseline claim.

The reported Android resources are:

- 艾尔: `res_cre_1791593277951938_3`.
- 利亚: `res_cre_1791592846335305_2`.

The user confirms their actual text exceeds 24,000 characters, but cannot obtain exact counts from the installed UI. No device database was provided and no Android device is attached. **Their exact character counts, Part distribution, job rows and installed APK identity remain unverified.** Synthetic counts below are reproducible regression evidence, not measurements of user data.

## Proven root causes and introduction

1. `BlueprintBudgetNormalizer` constrains estimated plan totals. Old `PartGenerationValidator` only rejected Part text above 3,000 characters; it did not enforce `targetBudget`. `commitPartContent` did not validate aggregate resource spending. A correct 20,000-character plan could therefore persist more than 24,000 actual characters. `git blame` dates the single-Part-only rule to `27a0498`; normalization `63a2ebc` fixed planning, not actual output enforcement.
2. The overflow readiness branch queues work and records `compressionPending`, then returns `preparing`. There was no successful compression → adopted candidate → reassembly continuation. The preparing branch originates in `80b97e6`; scheduling added in `fa7fafe` did not close publication.
3. Worker `8c62105` called one bounded `drain` (default four jobs) and removed its owner. More queued jobs were never rescheduled. A successful compression job and its candidate were written in separate steps, allowing a crash/write error to leave success without a candidate.
4. Automatic queueing could create Section proposals, while publication deliberately only accepts Parts. A Section result cannot safely be split into unknown Parts. Neither bypassing the guard nor treating a proposal as a published revision is valid.
5. SQLite `LENGTH` counts Unicode scalar values (and stops at embedded NUL); Dart `.length` counts UTF-16 units. Live capacity classified total including archived Parts, while frozen readiness excluded archived Parts. These are proven consistency defects; there is no evidence that emoji/archive counting caused this user's failure.
6. Batch adoption exposed another genuine CAS defect: applying the first Part revision rewrote unchanged sibling Part timestamps, invalidating the next candidate. Preserve timestamps of fully identical Part snapshots instead.

`1cb122c` addresses startup JSON/ID/worldview data boundaries, not these lifecycle/budget gaps. `4be8aff` fixes missing preparation after saves/retries and legacy heads, but leaves overflow closure incomplete. The evidence does **not** establish character-card import repairs as the introduction of this regression.

## Before-fix differential reproduction

A detached worktree at `7e5a409` runs real SQLite, production blueprint/task repositories, Part validation, transactional revision capture, capacity and readiness/worker services. Only external model responses are fixed. Each Part estimates 2,000 and returns 2,500 characters, within the old 3,000 upper bound.

| Session target | Blueprint target | Planned total | Actual live | Revision total | Capacity | Readiness | Compression jobs |
|---:|---:|---:|---:|---:|---|---|---|
| 8,000 | 8,000 | 8,000 | 10,000 | 10,000 | normal | ready | none |
| 20,000 | 20,000 | 20,000 | 25,000 | 25,000 | overflow | preparing | 10: 4 succeeded, 6 queued |

[Executable baseline probe](evidence/adventure-compression-p0/baseline-probe.dart.txt) and [captured output](evidence/adventure-compression-p0/baseline-sqlite.txt).

A separate negative regression against the original Part validator also fails as expected: 1,201 characters are accepted for an authorized 1,200 target. Restoring the fix makes rejection pass. The active worktree was restored immediately; full validation runs the fixed source.

**Why 8,000 succeeds and 20,000 fails:** actual generation can overshoot the estimated target. The smaller resource can still stay below the absolute capacity, taking normal assembly. An actually overflowing larger resource takes the incomplete compression path. This failure mechanism is reproduced, but 25,000 is an example, not a claim about either Android card. 20,000 itself is not overflow; strictly greater than 24,000 is required.

## Fix and safety invariants

Generation:

- Keep blueprint normalization, protocol/identity checks and the 3,000 Part upper bound.
- Read remaining aggregate budget before a model request; authorize the smaller of planned Part budget and remaining actual budget. Prompts state an upper bound rather than an approximate suggestion.
- Reject output beyond this authorized Part bound. Under the same SQLite write transaction as content/revision/task completion, sum actual non-deleted/non-archived other Parts and reject aggregate spending above the persisted blueprint target. Replacement retries subtract their own old content rather than double-count it.
- Overspend is a localized `resourceGenerationBudgetExceeded` error. Rejection does not truncate, overwrite saved body, create a revision or claim completion.

Compression and readiness:

- Drain all queued work in bounded passes, coalescing per-resource ownership. Startup resumes queued work after lease recovery. Existing lease CAS and attempt limits remain; only explicit retry requeues failed work.
- Atomically record succeeded job and candidate under the worker claim. Lost ownership or candidate-insert failure cannot publish an orphan success.
- Adventure overflow prepares **Part-only proposals from original Part bodies**. Structured JSON Maps/Lists and archived Parts are not rewritten as prose. Existing Section proposals remain untouched, and their publisher guard stays enforced.
- Use explicit review/adoption (task specification option B). An independent compressed assembly (option A) would require changing the current source-head/assembly content-hash equality contract; adopting through the existing versioned publisher preserves that invariant. The assembly page shows complete original and proposed Part body, allowing approval or cancellation. Adoption is one transaction guarded by the reviewed latest-head ID, candidate identity/scope/validation, and each Part source CAS. Original before/after immutable history is retained.
- After adoption, execute real `prepare`: measure frozen head, build/validate projection, publish assembly, index and commit readiness CAS. A candidate alone never means ready. Studio publication uses the same continuation callback.
- Queued/running/awaiting approval/failed/stale/ready are distinct diagnostics. Empty targets, absent candidates, failed validation, missing worker, exhausted retries and orphan ownership end in explicit actionable failures. Old under-capacity `compressionPending` rebuilds through real preparation.
- Event notifications update the page, with load epochs preventing older resolutions replacing newer state. No endless timer polling. Start stays disabled until gate-ready; double gate, freeze, start latch, session rollback and ChatProvider authority remain.
- Capacity panel, live service and frozen readiness use active UTF-16 character counts; archived text remains stored and counted separately. Assembly errors display actual/absolute character counts, resource identity and concrete cause. New logs contain IDs, types, phases, states, attempts, counts and revision/hash information, never model content, prompt or key.
- Integrated Widget testing exposed a stale post-frame notification after rollback/disposal. `AdventureProvider` now checks disposal before that deferred notification.

## SQLite / Widget success evidence

- New generation targets 8,000 / 18,000 / 20,000 persist exact compliant totals, match live and frozen revision counts, and publish a real ready assembly.
- Actual 20,000 and 24,000 directly ready; actual 24,001 enters recoverable compression/approval. Emoji and archive probes use the same counting units.
- Production Riverpod DI, the two reported IDs, 25,200 original characters per fixture, 18 validated Part proposals → explicit adoption → ready=2 → frozen=2 → unique sessions=1 → prologue=1 → persisted messages=3. Local HTTP streaming performs actual dialogue continuation. Editing the resource later does not alter the saved session config/messages, and original 25,200-character revisions remain readable.
- 320px Widget test begins with the real gate blocking launch, reviews actual candidates, observes readiness notification, and opens real `AdventureSessionScreen` using the production ChatProvider. It also asserts the displayed actual character count.
- Other probes cover >4 jobs, duplicate prepare/adoption, legacy Section scope, stale review rejection with transaction rollback, failed compression and explicit recovery, retry exhaustion without looping, JSON-only unsafe targets, restart resume, legacy DB migration, world/two-character/NPC binding, malformed card/hash, original revisions and per-session snapshots.

## Validation and Android

The final source passes the full regression. Failed/interrupted earlier runs are not described as passes.

- `dart format --output=none --set-exit-if-changed lib test`: PASS, 847 files, zero changes.
- `flutter analyze --no-pub`: final source PASS, zero issues (5.5 seconds).
- Targeted SQLite/Widget suites: final combined run PASS 70; final narrow-screen Widget rerun after the assembly phase notification refinement PASS 1. Production/budget run PASS 17; SOAK PASS 7.
- Original full run correctly rejected two over-budget SOAK fixtures and was interrupted for correction. Fixtures now authorize their unchanged four-character patches (500/200 patches, 17/50 Parts); the entire 7-case SOAK suite passes, without removing assertions or reducing load.
- Full `flutter test --no-pub`: PASS 3,661; SKIP 2 existing opt-in tests; FAIL 0; 13m18s. Final process exit code 0. The optional real TTS test was run separately and passed.
- Android ARM64 debug build: final source PASS (32.9 seconds). No release signing, version bump or APK publication.
- APK ABI: only `arm64-v8a`, native ELF64 AArch64 (e_machine=183), includes ONNX and Sherpa C/C++ TTS libraries.
- Optional official Kokoro real-model Linux TTS synthesis: PASS 1 (2m36s), Chinese/English/mixed text, multiple voices and repeated reloads; it does not establish Android device playback. ONNX and both Sherpa native library hashes in the debug APK match v1.2.05.
- [Final debug APK ABI/hash evidence](evidence/adventure-compression-p0/android-debug.json).
- [SQLite and targeted validation output](evidence/adventure-compression-p0/sqlite-fixed.txt) and [final validation summary](evidence/adventure-compression-p0/validation.txt).
- Android device validation: NOT COMPLETED.

## Remaining limits

Exact device data and real Android playback/start are unverified. External model behavior can still fail safe validation or consume retry allowance; failure remains explicit and existing content stays intact. Review and consent are required before adopting rewritten prose. Unsupported structured JSON or a Part above the existing bounded compression input must be edited/reduced rather than silently truncated or guessed. No gate removal, fake ready, database clearing or user-data deletion was used.

## Git delivery

Integrated Review and Integrated Acceptance are complete. Delivery consists of one local commit on `fix/adventure-compression-lifecycle`; its SHA is recorded in the final task response / Git log. No push, tag, version change or release is performed. The initial workspace was clean; changes in this task are isolated to budget/capacity/compression/readiness, their UI/error/DI dependencies, tests and evidence. The detached baseline probe worktree remains available for reproduction.

## User-authorized push / merge follow-up (2026-10-10)

After the local delivery above, the user explicitly authorized pushing the repair branch and merging into main. PR #4 records the strict per-Part generation-budget risk and the incomplete device validation.

The first GitHub Quality gate uses Flutter 3.47.7 and passed formatting, then reported three `unawaited_return_in_try_block` warnings. Add explicit `await` to the two fail-record returns and atomic job/candidate completion so asynchronous database exceptions enter their existing catch handlers. Do not disable the diagnostic or change generation-budget behavior.

A real SQLite trigger that aborts candidate insertion reproduces incorrect failure reconciliation before this follow-up. With the awaits in place, every unsuccessful job becomes failed, no candidate is publishable, original 25,200-character text remains intact, and explicit retry after removing the test-only trigger yields nine reviewed candidates. The trigger exists only in a disposable regression fixture, never the application database. Local targeted suites pass 49 cases; local analyze reports zero issues. The original full-suite / TTS / APK evidence above applies to head `7c2d7d9`; follow-up CI and merge outcome are recorded at https://github.com/yangrunzhi345-blip/LT/pull/4.
