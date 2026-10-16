# Session workbench focus lifecycle: investigation and implementation specification

STATUS: ACCEPTED.
Acceptance Mode: Independent Review (Plan → Execute → Independent Review → Acceptance).

## Authority and protected baseline

User attachment: `/home/yrz/.codex/attachments/c579e716-1b1c-41eb-992e-ddbcfc76aeea/pasted-text-1.txt`; repository `AGENTS.md`; current source and actual call paths. This specification preserves the attachment's complete acceptance scope.

Investigation worktree: `/home/yrz/LT-session-focus`; branch `fix/session-workbench-focus-lifecycle`; HEAD `beb1a47` (`chore(deps): refresh package lockfile`). Parent confirmed `origin/main` and local main are both `beb1a47` after fetch. Initial worktree status was clean. `flutter pub get` completed exit 0 and did not change `pubspec.lock`. Keep original `/home/yrz/LT` WIP untouched. No push, remote branch/PR, release, tag, version or dependency change. Only local task commit is authorized after validation.

## Confirmed root cause

The root focus test creates `ChatProvider` synchronously inside the widget test's fake async zone before entering `tester.runAsync`. Its constructor immediately calls asynchronous `_init()`, which starts `SettingsProvider.loadApiKey()`. Settings coalesces concurrent loads using `_loadFuture`.

`_loadApiKey()` progresses through SharedPreferences and reaches `_migrateEncryptedKeys()` → `_secureStorage.read(key: 'api_key')` in that originating fake zone. The test separately completes real SQLite create/open work in `runAsync`, then `mount()` invokes `settings.loadApiKey()` from another real async zone. Since `_loadFuture` is already active, that call returns the existing fake-zone future. Waiting in `runAsync` cannot drive the originating fake zone's platform-response continuations. The caller stalls before `pumpWidget`, before any MainGate startup callbacks or focus transition execute.

Confirmed classification: **A, Future waiting caused by a cross-zone initialization dependency in test setup**. This is test async ownership, not evidence of a production SQLite or focus-controller bug. It is unnecessary and unjustified to add a MainGate startup switch for this observed failure.

## Evidence and reproducibility

External logs contain only generated test fixture/schema diagnostics; no user credentials or user data were logged.

1. Unmodified test: `/tmp/session-focus-baseline-01.log`. Exact command:
   `flutter test --no-pub test/widget/session_workbench_test.dart --plain-name 'Root focus keeps the Session, draft and reader controller' --reporter expanded`.
   Schema creation completed, then test made no further progress; manually interrupted after the runner had lived about 100 seconds. Flutter log reports `01:19 +0`, target and teardown `did not complete`. The shell tool returned 0 after SIGINT, but this run is **INTERRUPTED / NOT PASS**. Do not mistake the shell code for successful assertions.
2. First instrumentation attempt `/tmp/session-focus-diagnostic-01.log` failed immediately, exit 1, because reading `binding.microtaskCount` outside an active widget test dereferenced null. This was a diagnostic error, corrected by guarding `binding.inTest`, and is not product evidence.
3. Stage-only diagnostic `/tmp/session-focus-diagnostic-02.log` and combined `/tmp/session-focus-trace.log`: target provider creation, createAdventure and openAdventure finished; mount stopped at `loadApiKey begin`. At that boundary `frames=true`, `transient=0`, `phase=idle`, `microtasks=0`. No mount `pumpWidget begin` occurred on the failing run. It was manually interrupted, not passed.
4. Settings/Future/zone diagnostics `/tmp/session-focus-diagnostic-03.log`, `/tmp/session-focus-diagnostic-04.log`, `/tmp/session-focus-settings-trace.log`: initial load `active=false`, zone `1008752875`, reaches `before secure migration await`; second load `active=true`, different zone `441292685`, no completion. Runs manually interrupted. Trace is append-only; timestamps distinguish runs.
5. Causal counterfactual `/tmp/session-focus-counterfactual-real-init.log`: only move initial provider creation and its settings-load await together into `tester.runAsync`; keep real SQLite, original MainGate and every original focus assertion. Exit 0, `+1 All tests passed`, about 3 seconds inside Flutter. Both enter/exit settle traces ended `frames=false`, `transient=0`; provider disposal and database reset both completed.
6. Clean minimal counterfactual, with **all diagnostic source changes removed**: `/tmp/session-focus-minimal-probe-01.log` through `03.log`; measured runner summary `/tmp/session-focus-minimal-probe-results.json`. All three independent runs exit 0 in 7.895s, 7.670s and 7.414s including process launch. The exact temporary change is preserved externally at `/tmp/session-focus-minimal-probe.patch` for Executor reference. This is investigation evidence, not final 20-run acceptance.
7. All temporary Dart modifications and minimal counterfactual edits were restored from exact pre-investigation backups before handoff. `/tmp/session-workbench-original.dart`, `/tmp/session-focus-settings-original.dart` contain original files; diagnostic copies are external `/tmp/session-focus-diagnostic-test.dart` and `/tmp/session-focus-diagnostic-settings.dart`. No live diagnostic test processes remain.

## Call-path and lifecycle assessment

- Test `setUp` creates a unique temporary real SQLite database, resets DatabaseService, constructs a ProviderContainer. Provider construction itself is lazy; the critical first `container.read(chatProvider)` belongs inside real async initialization.
- Common `mount()` already creates the provider inside `runAsync` for ordinary cases. The root focus case bypasses this by reading it before mount. Model selection case also reads it inside `runAsync`.
- `SettingsProvider.loadApiKey()` intentionally deduplicates active loads; replacing that behavior would risk parallel settings migrations. Preserve it.
- `MainGate.skipSplashOnInit` skips splash setup only; revision maintenance, compression/readiness recovery and streaming recovery remain scheduled. In failing diagnostics MainGate was never mounted. Preserve production startup defaults and paths.
- ChatProvider `_init` post-frame seed chain checks disposed only at entry; DatabaseService.resetDatabase has a 500ms opening wait and swallowed close errors. These are candidate risks from source reading, **not confirmed causes in this reproduction**. Do not change them speculatively. Escalate only if final tests demonstrate a task-blocking failure with a separately captured reproduction.
- SessionMessageList has bounded initial jumps (8 attempts), mounted checks around callbacks, and 200/300ms scroll animations. Actual counterfactual enter/exit settled with no transient frame callbacks and preserved controller identity/offset; no evidence supports changing these paths.
- Existing test teardown disposes container then resets DB after framework widget-test cleanup. Counterfactual reset completed; verify repeated lifecycles rather than assuming no latent race.

## Findings and scope

MAJOR: root test initializes an asynchronously active provider in fake async and waits for its cached future in real async, stalling before mount.
Acceptance gate: implementation, all mandated tests, local task commit and Independent Review are complete. Reviewer `/root/review` reported BLOCKER = 0, MAJOR = 0, MINOR = 0; all acceptance requirements passed.
INFO: source-level startup/dispose concerns above are unconfirmed and out of scope unless reproduction proves a dependency fix necessary.

Primary allowed file: `test/widget/session_workbench_test.dart`; this specification may receive final evidence/results. Reuse existing responsive helper, real DB setup, fixture generation and UI assertions. Add a small test helper only if shared by actual scenarios. No new production abstraction, dependency, schema/migration, UI design, icon, network, generation or release work.

## Implementation requirements for Execute

1. Ensure **first construction** of ChatProvider and awaiting its initial settings load occur within the same real async boundary before any root-focus fixture relies on it. A later `runAsync` that merely awaits an already-started fake-zone `_loadFuture` is insufficient. Explain this causal constraint in a concise comment.
2. Preserve real SQLite createAdventure/openAdventure and all existing persistence paths. Do not mock SQLite, remove migration behavior, pre-mark legacy migration as done, or mock away initialization just to avoid the failure. No arbitrary delays, timeout increases, retry-until-pass loops, empty catches or skips.
3. Preserve original exact test name and **all** assertions: sidebar hidden in reading focus; no Inspector; TextEditingController identity; complete unsent draft; ScrollController identity; offset within original tolerance; sidebar restored on exit; no widget exception. Prefer sharing an assertion scenario if adding repetition rather than duplicating a weaker scenario.
4. Add deterministic same-process coverage: repeated related root focus interaction/lifecycle scenarios in one test process, including repeated enter/exit on an existing controller and fresh provider/database lifecycles. Assert controller/draft/offset invariants throughout and no framework exception. Scope repetitions to a small explicit count; they are test scenarios, not retries for failures.
5. Observe end-state scheduler quiescence (`hasScheduledFrame == false`, transient callback count 0 after known animations settle) in relevant lifecycle coverage where consistent with Flutter focus behavior; distinguish intentionally requested cleanup frames. Test resources must dispose and database close complete without waiting on active widget-zone Futures. If observation reveals a genuine cleanup race, capture it and minimally revise this spec before production changes.
6. Keep MainGate production startup untouched on current evidence. No startup-isolation switch is required. The attachment's conditional requirement to add independent tests for a *changed* startup control mechanism is not triggered. Nevertheless run existing real startup/recovery/maintenance suites below. If existing coverage does not prove a changed behavior, add actual coverage; do not claim a static wiring assertion proves persistence recovery.
7. Remove every temporary diagnostic modification before final validation/commit. Retain external logs and a concise reproducible final validation record.

## Mandatory validation and evidence ledger

Execute actual commands, save every test invocation's log and measured duration, exit code, exception/failure phase. A timeout/interruption is not PASS even if wrapper returns 0. No retry hides a failed acceptance run; investigate and record failures before a new clean consecutive run begins.

- Exact original target alone in **20 consecutive independent Flutter test processes**, all exit 0 and target `+1` (or explicit selected-count equivalent), no hang. Record per-run outcome/duration, not merely a final total.
- Same-process repeated related focus interactions and fresh lifecycle coverage (as described above); report number of scenarios/loops and actual passed tests.
- Full `test/widget/session_workbench_test.dart`.
- Full `test/widget/session_inspector_navigation_test.dart`.
- Related actual DB lifecycle/repository coverage: `test/unit/database_and_repositories_test.dart`; additionally any focused lifecycle regression introduced for confirmed dependencies. Do not infer the full DB gate from one focus test.
- MainGate/recovery related suites: `test/application/resources/production_streaming_recovery_wiring_test.dart`, `test/application/resources/streaming_generation_lifecycle_recovery_test.dart`, `test/application/resources/phase9_revision_maintenance_test.dart`, `test/application/resources/compression_worker_test.dart`. Inspect tests and results to confirm production startup trigger/real persisted recovery and relevant maintenance behavior actually execute.
- `dart format --output=none --set-exit-if-changed` on changed Dart files (format before checking).
- `flutter analyze` (no new issues; record any pre-existing diagnostics accurately).
- `git diff --check`.
- `flutter test --no-pub` full regression, actual completion required. Do not report stopped runner as passing.
- Review final diff for unchanged original assertions, no skips/timeouts/mocks that weaken persistence, no diagnostics/secrets/lockfile or unrelated modifications. Confirm main worktree WIP protection against parent baseline.
- One clear local commit, suggested `fix(test): stabilize session workbench focus lifecycle`; no push.
- A different review Agent independently reads spec, commit/diff and logs, validates root cause vs masking, async races, startup behavior and test strength. Resolve all BLOCKER/MAJOR findings before acceptance.

## Acceptance and final report

ACCEPTED requires reproduced cause addressed, original target 20 consecutive passes, same-process repeated interactions/lifecycles, full two widget suites, DB/startup recovery gates, format/analyze/diff checks and full regression PASS, unchanged product invariants, no ongoing scheduling/resource symptoms, local commit and Independent Review PASS. Root cause was reproduced here; if a later claim changes causal attribution or loses reproduction fidelity, explain that limitation. An unreproduced original problem can only be PARTIAL under user instruction; do not declare a speculative fix ACCEPTED.

Final report must preserve user fields:
`STATUS`, `BASELINE`, `BRANCH`, `ROOT CAUSE`, `REPRODUCTION EVIDENCE`, `FILES CHANGED`, `FIX DETAILS`, `TEST RESULTS`, `20-RUN STABILITY RESULTS`, `FULL REGRESSION`, `INDEPENDENT REVIEW`, `COMMIT SHA`, `REMAINING RISKS`, `WIP PROTECTION`.

## Execution handoff

See [execution results](session-workbench-focus-lifecycle-results.md) for all actual commands, exits, elapsed times, runner counts, exception/failure classification and external log SHA-256 digests. The original target passed 20 consecutive independent processes; same-process fresh lifecycles and focus repetitions passed. Both full session suites, database/repository and startup/recovery-related suites passed. Format, flutter analyze (zero issues), and diff checks passed. Full `flutter test --no-pub --reporter expanded` completed exit 0 in 844.471 seconds, `+4188 ~7 All tests passed!`. Existing skips are unchanged. No production code changed. Independent reviewer `/root/review` accepted implementation commit `5063150f0d3cf43369301d836fe849c5525cc602`, verified all 34 execution ledger entries and log SHA-256 digests, and independently reran the exact target (+1, exit 0, 7.042s), same-process lifecycle suite (+3, exit 0, 10.707s) and baseline-to-commit diff check (exit 0). See the results record for independent log paths and digests. This final documentation update records that completed Independent Review; it changes no tested implementation.
