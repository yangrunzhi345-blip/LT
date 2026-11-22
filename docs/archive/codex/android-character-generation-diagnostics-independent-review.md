# Android character generation diagnostics — Independent Review

Status: ACCEPTED — diagnostic repair only

Acceptance Mode: Independent Review

Original intermittent Android character-generation failure: UNRESOLVED

## Authority and scope

Reviewed against `AGENTS.md`, the original Android investigation request, the user's subsequent authorization to repair diagnostics, and `android-character-generation-intermittent-investigation.md`. Baseline: `acb642b014b3939049a32f7a42d062e07333be09` on `main`; initial worktree was clean. Implementation and its validation were performed by `/root/execute_failure_diagnostics`; `/root` reviewed the resulting source/test diff and independently ran the checks below. This is not Integrated Acceptance.

The accepted scope fixes loss of safe error classification during body generation, retry exhaustion, terminal event publication and Studio reload. It does not claim to reproduce or resolve the user's intermittent Android failure without a device or its original exception evidence.

## Findings and invariants

Blocker: 0. Major: 0 within diagnostic repair scope.

- Failure types and explicit operation boundaries produce stable codes; raw provider bodies, historical exception strings and secrets do not become persisted failure copy or user-facing diagnostics.
- Retry exhaustion retains the task's safe failure code. Task, attempt, session and terminal event classifications are tested through real SQLite paths, including an aborting write trigger and successful retry.
- Retry convergence reads persisted errors only from the exact attempt started by that retry. Foreign or historical attempts cannot determine its classification.
- Original exceptions are rethrown. Cancellation and typed source-conflict handling keep their existing control-flow behavior; errors are projected only for storage/events.
- NDJSON decoding, sequence/cursor checks, nonempty/body validation, retry budgets, source-token CAS and transactional content writes were not relaxed. No schema, dependency, R8 or provider configuration change was introduced.
- Reopening a failed session restores localized safe copy; successful completion clears stale errors. Six locale variants and phone/desktop viewports are covered.
- Worldview and character use the same body pipeline. Their input/resource-type differences remain unchanged; both successful persistence paths are exercised. There is no evidence identifying why the user's original worldview request succeeded while a character request failed.

Pre-review issues corrected before acceptance: reload clearing its restored error; wrapping exceptions instead of preserving their type; missing fallback-preview/lifecycle classifications; confusing protocol cursor/sequence failure with an editing conflict; retry ownership based only on a changed attempt ID; generic 5xx presentation; and incorrect Chinese script locale fixtures.

## Validation evidence

- Three initial SQLite regressions failed against the original implementation, demonstrating retry-budget text replacing the failure code. They passed after the repair.
- First full run reported four failures and was not accepted. Two obsolete diagnostic-contract assertions were updated while preserving budget/status/persistence assertions; the new 5xx test was rerun against frozen code. An existing recovery timeout passed without changing its timeout or assertion. The focused rerun passed 77 tests.
- Final frozen implementation: `dart format .` completed (830 files inspected); `flutter analyze` passed; `flutter test --concurrency=2` exited 0 with 3424 passed, 2 existing environment/platform skips and 0 failures; `git diff --check` passed.
- Reviewer independently ran `flutter test --concurrency=2 test/application/resources/resource_generation_error_test.dart test/application/resources/streaming_resource_generation_service_test.dart test/application/resources/part_generation_coordinator_test.dart test/application/resources/streaming_generation_lifecycle_recovery_test.dart test/widget/resource_studio_test.dart`: exit 0, 104 passed. This includes cancellation, source-conflict and residual-error checks.
- `flutter build apk --release --target-platform android-arm64` succeeded, producing the local release APK. Reviewer independently ran both `scripts/verify_android_release_signing.py` and `scripts/verify_android_arm64_apk.py`: exit 0; LT release certificate identity verified, APK signature v2/v3 verified, only arm64-v8a present, Neural TTS ARM64 native libraries present.

Local execution logs are in `/tmp/lt-diagnostics-*.log`; they are not committed user data. APK remains a local build artifact, with no GitHub Release or APK upload.

## Remaining evidence gap

No Android device is connected. There is no release logcat/HTTP/parser exception capture from the user's failed character request. A new failure on the repaired build should identify network/provider/parser/validation/persistence/lifecycle safely, but unknown historical errors cannot be reconstructed. Original-task acceptance remains pending that evidence; this report accepts only the authorized diagnostic repair.
