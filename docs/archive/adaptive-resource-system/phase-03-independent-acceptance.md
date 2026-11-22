# Phase 3 Independent Acceptance Report

Review date: 2026-09-16. Reviewer: Codex, independent acceptance role.
Scope: Phase 3, against `phase-03-creation-pipeline.md`, ADR-0001 appendix C,
the supplied acceptance instructions, current code, Git history and independently
executed tests. No implementation-agent completion claim was accepted as evidence.

## 1. Verdict

**REJECTED** — most final writes now reach one pipeline, but formal AI entry
semantics, request identity, cancellation, Wizard failure handling and compatibility
behavior do not satisfy the contract. Seven independent acceptance assertions fail.

## 2. Repository Baseline

- Branch: `main`.
- Reviewed HEAD: `6b0965aa55758b6593589adf109025125208b4be`.
- Phase 3 start: `6283187`.
- Working Tree at review start: dirty; the following changes predated this review:
  - `lib/application/resource_library/import_use_cases.dart`
  - `lib/application/resources/legacy_creation_bridge.dart`
  - `lib/application/resources/resource_creation_pipeline.dart`
  - `test/unit/scene_batch_generation_jobs_test.dart`
  - `test/unit/scene_batch_identity_test.dart`
  - `test/unit/scene_batch_test_support.dart`
  - untracked `test/application/resources/creation_entry_points_test.dart`
- Relevant Phase 3 commits:
  - `a7fe1cc`: unified resource creation pipeline.
  - `1bc51ec`: tree resources projected into legacy views.
  - `d847c17`: creation entry rewiring.
  - `51f12dd`, `6b0965a`: progress records.
- Initial `git diff --stat`: 6 tracked files, 192 insertions, 60 deletions;
  excludes the pre-existing untracked entry test.
- Executed baseline checks: `git status --short`, `git branch --show-current`,
  `git rev-parse HEAD`, `git log --oneline -15`, `git diff --stat`,
  `git diff --check`. Initial whitespace check passed.

This verdict applies to HEAD **plus those existing changes**, not HEAD alone.
In particular, the scene batch rewiring and forced-manual bridge are uncommitted
baseline changes. They were neither authored nor reverted by the reviewer.

## 3. Validation

| Command / scope | Independently observed result |
| --- | --- |
| `dart format --output=none --set-exit-if-changed .` before additions | PASS: 334 files, 0 changed |
| Same command after acceptance tests | PASS: 335 files, 0 changed |
| `flutter analyze` before and after acceptance tests | PASS: `No issues found!` |
| `flutter test --reporter compact` before acceptance tests | PASS: 747 passed, 0 failed |
| `flutter test --reporter compact` including acceptance tests | FAIL: 748 passed, 7 failed (755 total) |
| Phase 3 targeted suite including acceptance tests | FAIL: 115 passed, 7 failed |
| Two acceptance-related files in isolation | FAIL: 6 passed, 7 failed |
| `git diff --check` | PASS |

Targeted command:

```sh
flutter test test/application/resources \
  test/services/library_repository_tree_union_test.dart \
  test/services/database_migration_resource_tree_test.dart \
  test/unit/resource_import_semantics_test.dart \
  test/unit/scene_batch_generation_jobs_test.dart \
  test/unit/scene_batch_identity_test.dart \
  test/widget/p0_adventure_wizard_start_boundary_test.dart --reporter compact
```

Logs for this execution are `/tmp/lt-phase3-acceptance-tests.log` (original full
suite), `/tmp/lt-phase3-final-tests.log` (final full suite),
`/tmp/lt-phase3-targeted.log`, and `/tmp/lt-phase3-probes.log` (expanded repros).
These are temporary evidence, not durable dependencies of this report; the tests
committed with the report reproduce the assertions. Initial sandbox attempts
failed because Flutter needed to write its SDK cache; approved reruns executed
normally. No network LLM or real user database was used.

The new tests assert required behavior and intentionally retain the observed
failures. No original test was skipped or relaxed. These failures expose code
defects; they are not evidence that the reviewer changed production behavior.

## 4. Contract Audit

### Creation Pipeline

**FAIL (creation semantics); final-write routing is present.** The only production
construction of `ResourceCreationRequest` found is
`legacy_creation_bridge.dart:141`. Controllers/use cases still own generation,
validation, identities and save orchestration. Routing an already generated tree
through a common writer does not establish the required creation session entry.
No second reachable UI-to-legacy-table insert path was found in the current
worktree; retained storage APIs without UI callers are not misclassified as such.

### Creation Modes

**FAIL.** The frozen enum correctly contains only `manual` and `aiReference`, and
there is no new text/file/existing-resource creation enum. However the sole
production adapter always submits `manual` (`legacy_creation_bridge.dart:143`),
including formal AI creation. Existing fast/detailed controls still select real
generation behavior, rather than a pending creation session.

### Manual Transaction

**PASS for new Resource + Section + Part atomic creation.**
`resource_tree_repository_impl.dart:75` uses a single SQLite transaction.
Existing duplicate-Section tests and the new first-Section trigger test prove
rollback leaves zero Resource/Section rows and a failed session. Normal empty
tree, optional Section and retry cases pass. Update error reporting and multi-item
atomicity do not pass; see H1/H4. This PASS does not cover those broader operations.

### AI Creation Session

**FAIL end to end; core method passes in isolation.**
`resource_creation_pipeline.dart:116` persists planning without a resource or
body generation. Core tests prove that behavior. Production pages instead call
LLM generation and then the manual bridge; no production request reaches that
AI branch or returns a planning session ID to the page. See B1.

### State Machine

**FAIL.** An explicit transition table exists, illegal-transition tests pass,
and sequential planning cancellation works. Persistence updates are unconditional
by session ID (`resource_creation_pipeline.dart:411`), using stale in-memory
state. The gated real-repository acceptance test proves a cancelled validating
request still writes a resource. Update failures can also become persisted (H1).
Recovery tests simulate one validating row but do not reopen the database and
resume a full real entry request.

### Idempotency

**FAIL.** Database v33 has a unique key and same-key sequential submissions work.
Actual entry retries generate a new timestamp identity and therefore a new key.
The import replay test observes two resources. Content-derived update keys also
drop legitimate A → B → A edits. Concurrent unique-key losers throw a conflict
instead of returning the winner; end-to-end concurrency/restart coverage is absent.

### ReferenceSource / Provenance

**FAIL end to end.** Core text/file/existing-resource factories and persistence
tests pass, with reference body confined to the session column rather than
provenance. Production bridge requests omit `referenceSource` and default to
`none`; there are no production calls to its three factories. Thus source text,
file identity and existing-resource reference semantics never reach the session.
The existing `ResourceProvenance` remains small, but it is not a substitute for
recording creation references. AI provenance can coexist with `method=manual`.

### Adventure Wizard

**FAIL.** Wizard still generates full worldview/characters and assembles/saves
them itself (`adventure_wizard_screen.dart:830`, `2017`, `2076`). It supplies its
own IDs, and CRUD returns a boolean result rather than a pipeline resource ID.
The added widget test proves a failed CRUD result still invokes the adventure
start callback once. Multi-resource partial failure has no rollback boundary.

### Legacy Compatibility

**FAIL as a shell-only contract.** Physical saves from inspected UI entries now
delegate to the bridge, including the uncommitted scene batch change. But the
controllers/pages retain active generate/review/save semantics (B1), and
compatibility readers/deleters do not consistently consume the new persistence
source (H3). Uncalled legacy storage APIs remain; their mere existence is not a
reason to delete Phase 12 compatibility code.

### Phase Boundary

**PASS for no new Phase 4/5/6/12 implementation.** Comparing the Phase 2 baseline
to HEAD and worktree shows no new Blueprint planner, incremental JSON protocol,
Streaming Studio or deletion of compatibility pages. Existing detailed-generation
coordinators and module-key logic predate Phase 3. Their continued formal use is
a Phase 3 convergence failure, not falsely labeled a newly implemented Phase 4.
The read-only Adventure projection is explicitly authorized in ADR C.7/STATUS.

## 5. Call-Path Audit

| Formal entry | Controller / use case | Persistence path | Contract limitation |
| --- | --- | --- | --- |
| Worldview/NPC/character manual editor, app dialog | `ResourceCrudController.save*` | bridge → pipeline → tree repository transaction | Old validation and IDs remain; no returned resource ID |
| Worldview AI page (reachable from library screen) | `ResourceLibraryImportController` → `ImportWorldviewUseCase.generate/save` | LLM → draft → bridge → manual pipeline → tree | No planning session/reference request |
| Character/NPC AI page | `ResourceCardImportController` → `ResourceCardImportUseCase` | LLM → draft → bridge → manual pipeline → tree | New ID per save; NPC saves per-item |
| Conversation AI import | `ResourceLibraryImportController` → `ImportConversationCharacterUseCase` | LLM → bridge → manual pipeline → tree | Repeat-save duplication reproduced |
| Scene batch page | `SceneBatchImportController` → `SceneBatchImportUseCase.importSelected` | Per-candidate LLM → bridge → manual pipeline → tree | Uncommitted rewiring; no batch transaction |
| Wizard quick generation/save/start | Wizard → `AdventureAiController` and/or `ResourceCrudController` | LLM/save orchestration in Wizard → bridge → tree | Failure value ignored, no resource-ID handoff |
| Character file/JSON import and manager save | `LibraryProvider` → `CharacterManager` | Parsed card → bridge → pipeline → tree | Source not represented as ReferenceSource |
| World engine save/prefs migration | `WorldEngine` | bridge → pipeline → tree | Save adapter, not AI planning |

Static searches also inspected `createResource`, `createResourceTree`,
`updateResourceTree`, Section/Part insertion, creation-session writes,
`saveWorldviewPreset`, `saveCharacterCard`, `saveNpcCard`, `saveCardBatch`,
`ResourceCreationRequest`, `ReferenceSource`, idempotency, Wizard, module keys and
both detailed-generation coordinators. The Phase 2 migration service writes trees
directly as migration infrastructure, not a second user creation entry. The
lower-level `createResource`/mount/creation gateway primitives have no discovered
production UI creation callers. Search captures are in
`/tmp/lt-phase3-write-audit.txt` and `/tmp/lt-phase3-symbol-audit.txt`.

## 6. Legacy Write Audit

- `worldview_ai_import_page.dart` / `resource_card_ai_import_page.dart`: no direct
  SQLite insert, but active generation and save pages; not request-only shells.
- `ResourceLibraryImportController` / `ResourceCardImportController`: generate,
  review and save state machines remain. Saves delegate through their use cases.
- `ResourceCrudController`: final creation writes delegate to the bridge;
  validation, ID assignment and result conversion remain. Delete delegates to
  the old repository and therefore misses tree-only resources.
- `import_use_cases.dart`: all current save branches use the bridge; retained
  generation, repeated identity allocation and per-item persistence remain risks.
- `DatabaseService.saveWorldviewPreset/saveCharacterCard/saveNpcCard` and
  `LibraryRepositoryImpl.save*`/`saveCardBatch`: still independent legacy table
  implementations. No current production user-entry caller of these wrappers
  was found. Preserve compatibility pending Phase 12; do not claim they are
  pipeline adapters or that they have already been removed.
- `ResourceReadFacade`, `ResourceAdventureView`: read-only. The facade/migration
  convergence is not wired into normal library lists; the union prefers legacy
  rows for matching IDs, causing the reproduced stale-edit defect.
- `WorldviewDetails.moduleKeys` and detailed coordinators: existing editor,
  validator and generation dependencies, not newly introduced Phase 4 features.

## 7. Test Coverage Review

Existing useful behavioral coverage:

- Real SQLite core pipeline tests: empty tree, first Section, supplied content,
  minimal provenance, AI planning-only behavior, no legacy writes, three reference
  kinds, credentials/name/key validation, sequential deduplication, conflicts,
  planning cancellation, simulated interrupted-session recovery, Section rollback
  and retry.
- Real bridge/tree tests: in-place replacement, fixed-ID repeat save, mapping,
  runtime body storage and no legacy writes.
- Projection/union and migration tests, scene candidate identity and cancellation
  before persistence, import semantic tests.

Important weaknesses and missing evidence:

- The original Wizard tests throw from a substitute CRUD controller; production
  CRUD returns `ResourceOperationResult.failure`. Their green result does not
  establish the real failure boundary.
- The pre-existing untracked entry test accepts both success and failure for
  edits, and makes the NPC type assertion only if save succeeds. It can pass
  without proving the advertised operation. Its cross-entry test checks one
  Resource but not one effective session.
- No end-to-end AI-page → planning/session-ID test, reference propagation from
  real file/text/existing-resource entries, restart with durable request identity,
  concurrent controllers, database session-write failure, full invalid mode/type
  boundary, batch late-write failure or Wizard orphan rollback test.
- `validateResourceType` tests membership of an already typed enum; it does not
  validate string entry values. Scene batch accepts `kind` as a string with
  inconsistent character/NPC fallbacks. There is no invalid-kind regression.

Added acceptance coverage: seven SQLite tests in
`test/application/resources/phase3_independent_acceptance_test.dart` (six fail,
first-Section rollback passes), and one failed-result Widget test added to
`test/widget/p0_adventure_wizard_start_boundary_test.dart` (fails). The latter
reuses the existing fixture and only changes the failure representation to match
production. No production UI was changed; this is not a responsive-completion claim.

## 8. Findings

### BLOCKER B1 — Formal AI entry never enters the AI creation session branch

- File/location: `lib/application/resources/legacy_creation_bridge.dart:137`;
  `lib/application/resource_library/import_use_cases.dart:296`;
  `lib/screens/resource_library/worldview_ai_import_page.dart:176`.
- Problem: the only production request constructor hardcodes manual and omits
  ReferenceSource. UI → use case generates full content first.
- Impact: AI/session-only and reference semantics are not delivered; the shared
  writer is being used as a compatibility save sink.
- Evidence: static call path; `resource_library_screen.dart:353/367/387` keeps
  these pages reachable; Wizard also calls full generation at line 850.
- Recommendation: formal entries construct AI/manual requests with reference and
  context before generation; AI returns a pending session ID. Keep old shells
  without activating the old generation/save workflow. Do not implement Phase 4.

### BLOCKER B2 — Repeat submit creates another resource

- File/location: `import_use_cases.dart:75`, `233`, `257`, `379`, `513`;
  `resource_crud_controller.dart:340/378`; bridge key at line 168.
- Problem: timestamps are allocated on each save and included in the key. Only
  the character edit draft writes its assigned ID back to the draft.
- Impact: replay/retry/controller repeat calls can create duplicate resources and
  sessions; UI busy flags cannot provide durable idempotency.
- Evidence: new same-draft conversation import test expects 1 row, gets 2.
- Recommendation: allocate and persist a logical request identity once, propagate
  it through all adapters/controllers, and reuse it after retries/restart. Verify
  actual entry calls, concurrent calls and recovery, not just fixed-key core calls.

### BLOCKER B3 — Cancellation does not fence an in-flight write

- File/location: `resource_creation_pipeline.dart:107/153/188/219/411`.
- Problem: cancel updates the row, but create continues using its old session;
  final updates have no expected-status predicate or transaction-level ownership.
- Impact: a successfully cancelled request creates a resource and can overwrite
  cancelled with persisted. Phase 3 state and data safety contract fails.
- Evidence: deterministic Completer gate immediately before real repository write;
  cancel returns cancelled, resumed operation leaves a Resource row.
- Recommendation: serialize/fence cancellation and commit at the persistence
  boundary, with conditional state transitions and no commit by stale ownership.

### BLOCKER B4 — Wizard starts after resource save reports failure

- File/location: `adventure_wizard_screen.dart:2017/2076/2095`;
  `resource_crud_controller.dart:177/229`.
- Problem: Wizard awaits CRUD but ignores its result, and keeps separate full
  generation and save orchestration instead of consuming resource IDs.
- Impact: failure still reaches the start callback; partial resources may remain
  when a later save or setup operation fails.
- Evidence: new `failed CRUD result prevents adventure start` expects callback
  count 0, observes 1. Existing throwing fakes miss this contract mismatch.
- Recommendation: move request/context orchestration to the shared creation use
  case, consume successful IDs, stop on failure, and test later-item failures and
  absence of orphan data. Do not merely change the test fake back to throwing.

### HIGH H1 — Any failed update to an existing ID is reported as success

- File/location: `resource_creation_pipeline.dart:155`.
- Problem: the catch block considers resource existence sufficient evidence that
  this request committed, even if the existing resource predates the request.
- Impact: transaction rollback is converted into `persisted/reusedExisting`, so
  the user's new content is lost while the UI reports success.
- Evidence: duplicate Section IDs force update rollback; the acceptance test gets
  a successful result instead of `ResourceCreationException`.
- Recommendation: reconcile only a commit proven to belong to this request;
  otherwise persist failure and propagate it. Verify old content remains intact.

### HIGH H2 — Content-hash idempotency suppresses real later edits

- File/location: `legacy_creation_bridge.dart:163`;
  `resource_creation_pipeline.dart:83`.
- Problem: A → B → A reuses A's historic creation key, returning the old result
  without updating the current tree. Metadata/mode are also absent from the key.
- Impact: legitimate saves silently do nothing; an edit is confused with replay
  of an earlier operation.
- Evidence: acceptance test expects Part content A, observes B.
- Recommendation: separate durable operation identity from content fingerprint;
  a new edit needs a new operation, while retries of that edit reuse its identity.

### HIGH H3 — Rewired writes disagree with legacy readers and deleters

- File/location: `library_repository_impl.dart:153` (`knownIds` skip),
  `294/376/627` (legacy delete paths).
- Problem: same-ID legacy rows hide newly saved tree content; deletion touches
  only old tables, leaving new tree-only resources visible.
- Impact: existing resource edits appear lost; newly created resources cannot be
  removed through the current library actions. This follows directly from Phase 3
  write rewiring and cannot be deferred as unrelated cleanup.
- Evidence: two acceptance tests observe old name after save, and a remaining
  visible row after delete.
- Recommendation: define one authoritative identity/read/delete policy using
  existing tree and compatibility facilities; retain old data and compatibility
  shells, without broad Phase 12 deletion or a new revision system.

### HIGH H4 — Batch transaction was replaced with independent commits

- File/location: `import_use_cases.dart:247/503`; prior implementation in
  `git diff 6283187 -- lib/application/resource_library/import_use_cases.dart`.
- Problem: NPC and scene batch formerly called atomic `saveCardBatch`; now each
  item commits separately. Scene cancellation is checked before the save loop,
  not during it; the comment at line 440 still promises atomic batch persistence.
- Impact: a later failure leaves earlier items saved; retry allocates fresh IDs
  and can duplicate that prefix. This is a confirmed transaction-boundary change;
  an injected late-batch-failure test is still missing.
- Evidence: per-item awaited bridge calls and individual repository transactions;
  no encompassing transaction/compensation. Existing tests cancel during generation.
- Recommendation: preserve the logical batch boundary in unified creation,
  including stable per-item identities, failure rollback and cancellation policy.

### MEDIUM M1 — Key acceptance claims lack adequate tests

- File/location: `test/application/resources/creation_entry_points_test.dart:182/205`;
  `test/widget/p0_adventure_wizard_start_boundary_test.dart:49`.
- Problem: conditional success assertions and throwing-only fakes permit green
  runs while formal behavior is wrong; concurrency/restart/reference and batch
  boundaries are missing (section 7).
- Impact: the original 747-pass result does not prove Phase 3 acceptance.
- Recommendation: require success for advertised success cases and assert real
  persisted state, errors and session IDs at each formal entry. Keep added red
  acceptance assertions unchanged while repairing production code.

### LOW L1 — Progress documentation contradicts current implementation

- File/location: original `STATUS.md` overview, Phase 3 Remaining/Known Issues;
  ADR C.7.
- Problem: it records no production pipeline callers and pending rewiring even
  after rewiring commits, and originally merged the Phase 3/4 table rows.
- Impact: handoff cannot distinguish historical partial work from current state.
- Recommendation: this report and the appended status record establish the
  reviewed state; update implementation inventory during remediation without
  deleting historical failures or changing the frozen contract.

## 9. Changes Made By Reviewer

- Added this report with executable repair requirements.
- Updated `STATUS.md` to record failed independent acceptance, keeping Phase 4
  blocked and preserving previous execution history.
- Added `phase3_independent_acceptance_test.dart`: seven real-SQLite acceptance
  tests, six failing and one passing.
- Added one production-shaped failed-result test and its fake to the existing
  Wizard boundary test: failing as described above.
- No production implementation, frozen contract, dependency, Phase 4–12 code or
  pre-existing dirty file was modified. No push.

### Remediation scope and acceptance gates

Execute within Phase 3 entry/controller/use-case/persistence compatibility code
identified in B1–H4; use the current pipeline and repository. This review does
not authorize redesigning Phase 4–12, generating content, deleting compatibility
layers, clearing databases or changing frozen enums.

Required gates: all B/H items resolved; all added tests green without weaker
assertions; additional real-entry AI/reference, concurrent/restart identity,
session-write failure and late-batch/Wizard failure tests; full format/analyze/test
and diff checks; a renewed static call-path audit proving formal creation and
save semantics end at one pipeline. Existing user changes must remain protected.
Missing tests must be added alongside the corresponding repair, not deferred
past Phase 3. UI changes require the project's 320px responsive gates.

## 10. Phase Boundary Check

- Implement Phase 4 Adaptive Blueprint: **NO**.
- Implement Phase 5 Incremental JSON: **NO**.
- Implement Phase 6 Streaming Studio: **NO**.
- Prematurely delete Phase 12 legacy compatibility: **NO**.

Old detailed generation still being reachable is B1/H, not evidence of a new
Phase 4–6 implementation. The previously authorized Adventure read projection is
in scope, but its compatibility consequences still need repair.

## 11. Final Acceptance Decision

- Phase 3 can be marked ACCEPTED: **NO**.
- Phase 4 can be unlocked: **NO**.
- Blocking items: B1–B4; data correctness regressions H1–H4; missing evidence M1.
  L1 alone would be conditional, but cannot downgrade the substantive failures.

The independent review is complete; final verification results are recorded
above. Implementation remediation is a separate task; this report deliberately
does not turn a rejected acceptance into an unauthorized architecture rewrite.
