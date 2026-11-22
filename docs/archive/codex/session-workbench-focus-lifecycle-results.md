# Session workbench focus lifecycle: execution evidence

STATUS: ACCEPTED.
Acceptance Mode: Independent Review.
BASELINE: `beb1a47` (`main` and `origin/main` at investigation baseline).
BRANCH: `fix/session-workbench-focus-lifecycle`.

## Root cause and fix

The first root-focus `ChatProvider` construction previously started settings loading in the widget test fake async zone. A later real-async mount awaited the same cached future while its originating zone was undriven. The fix constructs the provider and awaits settings initialization together inside `tester.runAsync`, before the real SQLite adventure fixture and MainGate mount.

No production source, MainGate startup path, settings migration, SQLite factory, database schema, timeout, skip, assertion tolerance or original test name changed. The shared scenario preserves every original assertion. Three added same-process tests each use a fresh ProviderContainer and temporary real SQLite database (normal setup/teardown), then run three focus enter/exit cycles using the same draft and controllers. Each cycle verifies scheduler quiescence after settling: no scheduled frame and zero transient callbacks, plus no framework exception.

## Reproduction evidence and classified investigation outcomes

See the formal plan for exact diagnostic stages and counterfactual call paths. Original baseline `/tmp/session-focus-baseline-01.log` stalled before mount; it was interrupted after about 100 seconds (runner last reported 01:19). The tool wrapper returned 0 after SIGINT, but the test and teardown did not complete: **INTERRUPTED, never PASS**. Diagnostic attempt 01 exited 1 because instrumentation read microtaskCount outside an active test; this diagnostic error was corrected. Diagnostic runs 02–04 were interrupted, never PASS. Stage/zone traces proved the first settings future and the real-async waiter belonged to different zones. Counterfactual completed with unchanged real persistence and original assertions. Three clean minimal probes then passed in 7.895s, 7.670s and 7.414s. These are investigation evidence, separate from the final 20-run streak below. All temporary diagnostics were removed before final validation.

## Validation ledger

Every command below actually completed. Durations include process startup and any Flutter tool-lock/contention time; several suites ran concurrently in separate processes against per-test temporary databases. No acceptance retry or watchdog interruption occurred. A PASS means command exit 0 and the Flutter test runner's `All tests passed!` terminal marker (for test commands). Exception/failure phase is **none unhandled / none** for each passing invocation; intentional negative-path errors inside passing suites remain visible in their logs. Full regression retains existing gated real-service/platform skips; this task adds none and does not count skipped tests as executed passes.

Raw append-only ledger: `/tmp/session-focus-final/ledger.jsonl`; runner: `/tmp/session-focus-final/run.py`. Per-invocation external logs and SHA-256 digests below make the evidence auditable. The logs contain generated fixtures rather than user databases or credentials.

| Invocation | Exit | Seconds | Runner result | Exception / failed phase | Log SHA-256 |
| --- | ---: | ---: | --- | --- | --- |
| [target-01](/tmp/session-focus-final/target-01.log) | 0 | 7.595 | 00:03 +1: All tests passed! | none / none | `75ab6bd5eca3264886f6f3bb59cbcdf8d141cc24a671b67d16349a453fc21782` |
| [target-02](/tmp/session-focus-final/target-02.log) | 0 | 7.666 | 00:03 +1: All tests passed! | none / none | `c75c9e0f50122efb7a331572e0c30880e4c4bc7dd88bd224137d6d189df14c4d` |
| [target-03](/tmp/session-focus-final/target-03.log) | 0 | 6.404 | 00:02 +1: All tests passed! | none / none | `8edec1554e29741289464ba735465f8872d8245c6f920f72231e3657fdaea5d0` |
| [target-04](/tmp/session-focus-final/target-04.log) | 0 | 7.443 | 00:03 +1: All tests passed! | none / none | `675ef859613b3949c5dc06c1a33ee7ea62b26e8d6d54a0702eeae9f3dc7601e6` |
| [same-process](/tmp/session-focus-final/same-process.log) | 0 | 11.474 | 00:07 +3: All tests passed! | none / none | `8aef8d4818f16cf9bd492b707e358d8245e07fc46b2af8a666180da0fb3d58ab` |
| [target-05](/tmp/session-focus-final/target-05.log) | 0 | 7.702 | 00:03 +1: All tests passed! | none / none | `273e90fd716c96d98201426bb250726ccfb26675e3cfb3d9c429553b36f9b7fb` |
| [target-06](/tmp/session-focus-final/target-06.log) | 0 | 7.084 | 00:03 +1: All tests passed! | none / none | `28f098067b6be6e1ee91828dfc42f892dd6ed164e170f909c0443161b4e07a20` |
| [session-workbench](/tmp/session-focus-final/session-workbench.log) | 0 | 18.032 | 00:14 +15: All tests passed! | none / none | `e791d0b3e1199e64444a269d4351af3f485c71c2d9ee34e83151bc665db63667` |
| [target-07](/tmp/session-focus-final/target-07.log) | 0 | 7.293 | 00:03 +1: All tests passed! | none / none | `cd7bae8290e917a804ab81a301cf95d7dae6d5acfbe86256955424c49f16966c` |
| [target-08](/tmp/session-focus-final/target-08.log) | 0 | 7.287 | 00:03 +1: All tests passed! | none / none | `4bd72568b15aad6fd2327a11c1d3203a3708be9713e54289684560c505c1570c` |
| [session-inspector](/tmp/session-focus-final/session-inspector.log) | 0 | 13.104 | 00:08 +23: All tests passed! | none / none | `dbfacd060ff786cda7f53b6aa9f466deef13087ded75e45b3e36f69a1aa463b0` |
| [target-09](/tmp/session-focus-final/target-09.log) | 0 | 8.947 | 00:04 +1: All tests passed! | none / none | `46f4c40882350b9536b9e7fe18450fb962a691b83ef2450f975e95e1c72a1b04` |
| [target-10](/tmp/session-focus-final/target-10.log) | 0 | 10.874 | 00:04 +1: All tests passed! | none / none | `ea05dd51bb822da3564e00c0e6df3f8ad032500e78726824d390056b041a2d1f` |
| [database-repositories](/tmp/session-focus-final/database-repositories.log) | 0 | 22.709 | 00:05 +27: All tests passed! | none / none | `667ad203a0d932d1998dcdf0d5f07f2b8ec07c4319239b6a231ed345f0925699` |
| [readiness-recovery](/tmp/session-focus-final/readiness-recovery.log) | 0 | 13.398 | 00:03 +9: All tests passed! | none / none | `ddf5e4b170c7cf5f5463f5c27827d3e8f9300ce0113ad55de395a3ca2e7470cc` |
| [production-recovery](/tmp/session-focus-final/production-recovery.log) | 0 | 13.477 | 00:03 +3: All tests passed! | none / none | `49880490bbea4f123b2e84e2f027fa02166cc3b4d4fb52b7a25ec7a977dedf84` |
| [target-11](/tmp/session-focus-final/target-11.log) | 0 | 39.483 | 00:11 +1: All tests passed! | none / none | `08bff213b670fef7f96ec27866d0f043df4767893af2af78ccd15abd17009a5d` |
| [streaming-lifecycle](/tmp/session-focus-final/streaming-lifecycle.log) | 0 | 19.074 | 00:06 +16: All tests passed! | none / none | `2437722299ba216d72f90387063110df21d9f179d57062166499c214b6fc21be` |
| [format](/tmp/session-focus-final/format.log) | 0 | 1.059 | PASS | none / none | `c3bcc35222b18b2e9aab96a1ebd0350c9c73fade030cdbddf7b75d7a11c7c95f` |
| [revision-maintenance](/tmp/session-focus-final/revision-maintenance.log) | 0 | 9.905 | 00:02 +8: All tests passed! | none / none | `3e6912404af7ae44c840b87d6963338339c822c99f6c8f2d2b15bc2ea4eb3241` |
| [adventure-start-recovery](/tmp/session-focus-final/adventure-start-recovery.log) | 0 | 29.773 | 00:16 +18: All tests passed! | none / none | `91e9753d0221e869d8b1c2d49334880bc2504ae8b31de082e819d18806fdebf5` |
| [target-12](/tmp/session-focus-final/target-12.log) | 0 | 13.292 | 00:06 +1: All tests passed! | none / none | `2c0fcd31c67786c2ccb3b06d78846a90eb649b9b7210cff7ca42eef83b0b9bd9` |
| [compression-worker](/tmp/session-focus-final/compression-worker.log) | 0 | 6.891 | 00:01 +4: All tests passed! | none / none | `a6ecd7b7a1d5ac0bce361b96c44a40b5677f312d31b7bc1720b03c886e79fb26` |
| [target-13](/tmp/session-focus-final/target-13.log) | 0 | 10.358 | 00:04 +1: All tests passed! | none / none | `7b073ca7a3363d705e690245518499367aa68d6ef70f594c907800247f2d9989` |
| [target-14](/tmp/session-focus-final/target-14.log) | 0 | 12.126 | 00:05 +1: All tests passed! | none / none | `d047caba3a01d5a7d8fae73ee2b644e3674a29bf695cdab11d9777893df36840` |
| [analyze](/tmp/session-focus-final/analyze.log) | 0 | 34.694 | PASS | none / none | `53e142e4674f37f45139b737e1326b63da86af10beb5861596ade835d7bde253` |
| [diff-check](/tmp/session-focus-final/diff-check.log) | 0 | 0.009 | PASS | none / none | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| [target-15](/tmp/session-focus-final/target-15.log) | 0 | 12.489 | 00:04 +1: All tests passed! | none / none | `2706a4146f03de798cccb2d766bd52d9afac533c1359d463520e8a3192e3092a` |
| [target-16](/tmp/session-focus-final/target-16.log) | 0 | 9.242 | 00:04 +1: All tests passed! | none / none | `2841a6e8a9fa23aecb831d4eb6331e1899fd52744e3d1e3f73fe995346bf5a34` |
| [target-17](/tmp/session-focus-final/target-17.log) | 0 | 9.688 | 00:04 +1: All tests passed! | none / none | `570f08a4242528e3dc6b25b378fee417e65c0949dcdd4fe3ca5811b6dc6d2a4a` |
| [target-18](/tmp/session-focus-final/target-18.log) | 0 | 10.457 | 00:03 +1: All tests passed! | none / none | `89fbb00516c4fd049103668aa791a2ab017cfb4fa7f542d6d87019c6b2297c9f` |
| [target-19](/tmp/session-focus-final/target-19.log) | 0 | 7.596 | 00:03 +1: All tests passed! | none / none | `3c29b50806c96f47d652a97cfb6326319e902105760f0856c8dd1f056fec80c7` |
| [target-20](/tmp/session-focus-final/target-20.log) | 0 | 7.330 | 00:03 +1: All tests passed! | none / none | `1da41310ed970464d2687cd379aab9250b3a3d03adc28727f067fa25526e0a05` |
| [full-regression](/tmp/session-focus-final/full-regression.log) | 0 | 844.471 | 13:57 +4188 ~7: All tests passed! | none / none | `45efc684c76bf5f5dbad2427fee936807eda3d879ff417761f5b4cb9751d8b1d` |

Exact commands, in ledger completion order:

- `target-01`: `flutter test --no-pub test/widget/session_workbench_test.dart --name '^Root focus keeps the Session, draft and reader controller$' --reporter expanded`
- `target-02`: `flutter test --no-pub test/widget/session_workbench_test.dart --name '^Root focus keeps the Session, draft and reader controller$' --reporter expanded`
- `target-03`: `flutter test --no-pub test/widget/session_workbench_test.dart --name '^Root focus keeps the Session, draft and reader controller$' --reporter expanded`
- `target-04`: `flutter test --no-pub test/widget/session_workbench_test.dart --name '^Root focus keeps the Session, draft and reader controller$' --reporter expanded`
- `same-process`: `flutter test --no-pub test/widget/session_workbench_test.dart --reporter expanded --name 'Root focus lifecycle'`
- `target-05`: `flutter test --no-pub test/widget/session_workbench_test.dart --name '^Root focus keeps the Session, draft and reader controller$' --reporter expanded`
- `target-06`: `flutter test --no-pub test/widget/session_workbench_test.dart --name '^Root focus keeps the Session, draft and reader controller$' --reporter expanded`
- `session-workbench`: `flutter test --no-pub test/widget/session_workbench_test.dart --reporter expanded`
- `target-07`: `flutter test --no-pub test/widget/session_workbench_test.dart --name '^Root focus keeps the Session, draft and reader controller$' --reporter expanded`
- `target-08`: `flutter test --no-pub test/widget/session_workbench_test.dart --name '^Root focus keeps the Session, draft and reader controller$' --reporter expanded`
- `session-inspector`: `flutter test --no-pub test/widget/session_inspector_navigation_test.dart --reporter expanded`
- `target-09`: `flutter test --no-pub test/widget/session_workbench_test.dart --name '^Root focus keeps the Session, draft and reader controller$' --reporter expanded`
- `target-10`: `flutter test --no-pub test/widget/session_workbench_test.dart --name '^Root focus keeps the Session, draft and reader controller$' --reporter expanded`
- `database-repositories`: `flutter test --no-pub test/unit/database_and_repositories_test.dart --reporter expanded`
- `readiness-recovery`: `flutter test --no-pub test/application/resources/assembly_readiness_coordinator_test.dart --reporter expanded`
- `production-recovery`: `flutter test --no-pub test/application/resources/production_streaming_recovery_wiring_test.dart --reporter expanded`
- `target-11`: `flutter test --no-pub test/widget/session_workbench_test.dart --name '^Root focus keeps the Session, draft and reader controller$' --reporter expanded`
- `streaming-lifecycle`: `flutter test --no-pub test/application/resources/streaming_generation_lifecycle_recovery_test.dart --reporter expanded`
- `format`: `dart format --output=none --set-exit-if-changed test/widget/session_workbench_test.dart`
- `revision-maintenance`: `flutter test --no-pub test/application/resources/phase9_revision_maintenance_test.dart --reporter expanded`
- `adventure-start-recovery`: `flutter test --no-pub test/application/resources/adventure_start_sqlite_production_test.dart --reporter expanded`
- `target-12`: `flutter test --no-pub test/widget/session_workbench_test.dart --name '^Root focus keeps the Session, draft and reader controller$' --reporter expanded`
- `compression-worker`: `flutter test --no-pub test/application/resources/compression_worker_test.dart --reporter expanded`
- `target-13`: `flutter test --no-pub test/widget/session_workbench_test.dart --name '^Root focus keeps the Session, draft and reader controller$' --reporter expanded`
- `target-14`: `flutter test --no-pub test/widget/session_workbench_test.dart --name '^Root focus keeps the Session, draft and reader controller$' --reporter expanded`
- `analyze`: `flutter analyze`
- `diff-check`: `git diff --check`
- `target-15`: `flutter test --no-pub test/widget/session_workbench_test.dart --name '^Root focus keeps the Session, draft and reader controller$' --reporter expanded`
- `target-16`: `flutter test --no-pub test/widget/session_workbench_test.dart --name '^Root focus keeps the Session, draft and reader controller$' --reporter expanded`
- `target-17`: `flutter test --no-pub test/widget/session_workbench_test.dart --name '^Root focus keeps the Session, draft and reader controller$' --reporter expanded`
- `target-18`: `flutter test --no-pub test/widget/session_workbench_test.dart --name '^Root focus keeps the Session, draft and reader controller$' --reporter expanded`
- `target-19`: `flutter test --no-pub test/widget/session_workbench_test.dart --name '^Root focus keeps the Session, draft and reader controller$' --reporter expanded`
- `target-20`: `flutter test --no-pub test/widget/session_workbench_test.dart --name '^Root focus keeps the Session, draft and reader controller$' --reporter expanded`
- `full-regression`: `flutter test --no-pub --reporter expanded`

## Completed gate summary

TEST RESULTS: all required targeted suites PASS; workbench 15, inspector 23, database/repositories 27, production streaming wiring 3, streaming lifecycle 16, revision maintenance 8, compression worker 4. Additional readiness 9 and adventure-start SQLite 18 PASS. Same-process selected suite: 3 fresh lifecycles, 9 enter/exit cycles, PASS.
20-RUN STABILITY RESULTS: 20 consecutive independent exact-name processes PASS, each +1; 210.356 seconds total (6.404–39.483 seconds per process); no hangs or interruptions.
FULL REGRESSION: PASS, exit 0 in 844.471 seconds wall time; runner 13:57, +4188 passed / ~7 existing skipped. No failures.
STATIC CHECKS: dart format PASS; flutter analyze PASS with No issues found; git diff --check PASS. Final staged diff/status review is also captured in `/tmp/session-focus-final/precommit.log`.

## Coverage and limits

The 20 standalone runs select only the anchored original name, each `+1`. The same-process gate selects three fresh lifecycles with nine focus cycles total; the full workbench suite also runs the original scenario and those three cases. Provider disposal, real database reset/close and temporary-directory deletion complete through normal teardown.

The existing production recovery wiring suite runs MainGate's streaming trigger and separately verifies persisted interrupted tasks/sessions become resumable without automatic generation. The lifecycle recovery suite verifies recovery waits for explicit resume. Revision maintenance tests execute actual retention passes and protect revision heads/history in real SQLite. Compression worker tests process queued jobs and exercise actual persistence with deterministic LLM responses. Readiness coordinator and adventure-start SQLite suites additionally verify orphaned preparing rows recover to failed states. These jointly cover the unchanged startup services; they do not claim a new end-to-end MainGate recovery test for every maintenance callback. MainGate was never reached in the reproduced hang and remains unchanged.

FILES CHANGED: `test/widget/session_workbench_test.dart`, formal plan, this result record.
FIX DETAILS: same-zone first initialization; shared original assertion scenario; bounded deterministic focus and lifecycle repetition with scheduler assertions.
INDEPENDENT REVIEW: PASS by separate Agent `/root/review` on implementation commit `5063150f0d3cf43369301d836fe849c5525cc602`; BLOCKER = 0, MAJOR = 0, MINOR = 0. The reviewer independently checked all 34 ledger entries against actual terminal logs and SHA-256 digests, including 20 exact target runs (+1 each) and the full +4188 / ~7 result. Independent command `git diff beb1a47 HEAD --check` exited 0.
COMMIT SHA: see local `fix(test): stabilize session workbench focus lifecycle` commit containing this record (self-referential SHA intentionally not embedded).
REMAINING RISKS: finite stress evidence samples a bounded set of schedules; 7 existing real-service/platform gated tests remain skipped in the full run and are not counted as executed passes.
WIP PROTECTION: isolated worktree; parent Plan agent rechecked `/home/yrz/LT`: clean `git status --short`, branch `main`, HEAD `beb1a47e9f5e8f21d0084a2259efbc37fcb067e6`; `git diff --exit-code beb1a47 -- pubspec.lock` exited 0 in both worktrees. No lockfile, main-worktree, version, dependency, remote branch, PR, tag or release edits. No push, reset, clean or shared-history rewrite.

## Independent Review evidence

Reviewer: `/root/review`. Reviewed implementation commit: `5063150f0d3cf43369301d836fe849c5525cc602`. Both independent reruns completed with no unhandled exception or failed phase. The final documentation-only amend records this completed review and preserves the exact tested Dart implementation.

| Independent rerun | Exit | Seconds | Terminal result | External log SHA-256 |
| --- | ---: | ---: | --- | --- |
| [Exact original target](/tmp/session-focus-final/independent-target.log) | 0 | 7.042 | `+1 All tests passed!` | `a45ed5a29455cf4ec96d5fe9983540383684124e74445a0485ab927dbdbe7620` |
| [Same-process lifecycle suite](/tmp/session-focus-final/independent-same-process.log) | 0 | 10.707 | `+3 All tests passed!` | `6119b785351f92e65c83acf67d9644950d1486011dce7401baa56a045846d3af` |

Review confirmed preserved original assertions, real SQLite, unchanged production startup behavior, no timeout/skip weakening and no new asynchronous race in the scoped change.
