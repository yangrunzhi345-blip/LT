# Android adventure start readiness regression

Status: REPRODUCED CODE DEFECTS FIXED AND VERIFIED; Android acceptance blocked.
Acceptance mode: Integrated Single-Agent Full-Cycle (user requested continuous end-to-end execution).
No release, tag, push, package version change, database reset or user-data migration is authorized by this report.

## Baseline and execution version

- Initial checkout branch: `work`, clean working tree.
- HEAD: `12ed66f7f2d160c4aabb6a0c7e50965059266119` (v1.2.04).
- Initial cached origin/main matched HEAD. After `git fetch origin main`, origin/main:
  `b060462fd98bdf4af72da9cd106287981f3af7c8`.
- The additional remote commit is empty; `git diff HEAD origin/main` has no code changes.
- The code under investigation includes `1cb122cf15cba23e43b12346e6b4a3195aaf1e6f`.
- This proves the checkout's version, not the APK installed on the user's Android device.
  No device, affected database or device log was supplied.

## Confirmed causes and historical introduction

1. **Persistence idempotency skipped readiness recovery.** Single-save reuse,
   interrupted-save reconciliation and batch-save reuse returned a persisted resource
   without running the post-save assembly boundary. A preparation failure after the
   content transaction therefore survived an unchanged Save/Retry indefinitely.
   Production SQLite regression reproduced `failed` after the second save.
   `ecce4d7` (2026-09-21) added post-persistence preparation but omitted these existing
   reuse branches. `bd1f316` renamed the hook without filling the omission.
2. **Part-scoped retry omitted assembly completion.** After editing a generated
   character, a successful Part retry committed content and latestHead and marked the
   generation session completed, but did not call the full generation run's readiness
   completion boundary. Production SQLite regression reproduced `stale` after retry.
   The retry branch dates to `67ec88cc`; `bd1f316` (2026-09-21) added assembly
   preparation to full-run completion only, leaving retry completion disconnected.
3. **Legacy tree recovery stopped before revision capture.** Legacy migration creates
   resource trees without a latestHead. Gate prepare delegated directly to preparation,
   which fails with `noSavedRevision`, so the offered retry could not recover these
   valid saved trees. Reproduced on a real v41 database upgraded to v48 and then migrated.
4. **Presentation erased the evidence.** Both assembly launch screens converted
   `AdventureReadinessGateException.issues` to a generic AppDomainError. `1cb122c`
   introduced `adventureLaunchError` to avoid Unknown Error, but its callers still lost
   individual issues and rendered the reported generic readiness text. Coordinator
   catch handling also discarded the original exception class and failure stage.

The fresh import and manual creation paths passed before the fixes. Production AI
creation, planning, Part commit and full-run completion also passed. These facts do
not support blaming the character import/generation repair itself. The later fixes
(`181c8f3`, `20bc1ba`, `3228414`) improve generation success/failure handling and expose
these paths more often; no evidence establishes them as the source of the missing
readiness hooks. `1cb122c` addresses opaque IDs, legacy worldview shapes and start
boundary errors; it does not repair the above completion-path omissions.

The defects are reproduced code-level causes. Matching one to the user's particular
Android failure still requires safe device diagnostics or a consented affected-db fixture.

## Authority and complete call chain

- Import/manual/legacy generated-card acceptance: production
  `resourceCreationPortProvider` -> mapper -> production `ResourceCreationPipeline`
  -> SQLite content-tree transaction -> revision capture in that same transaction
  -> latestHead -> readiness preparation -> assembly publication and index -> ready.
- Streaming AI: production Studio runtime/orchestrator -> creation session -> blueprint
  -> generation session -> Part coordinator -> SQLite Part commit + revision capture
  -> full-run or retry completion -> the same preparation/publication boundary.
- Wizard/assembly: gate resolves the worldview source ID, selected character resource
  IDs and NPC asset IDs. Resource selection IDs remain distinct from source IDs.
  `enforceAndFreeze` reads immutable assembly revisions and reconstructs worldview,
  character JSON and NPC JSON, recording revision IDs and hashes in resourceBindings.
- `AdventureProvider.createAdventure` performs the authoritative second gate, freezes
  relationships/monitoring definitions and persists session/runtime data.
  `ChatProvider.startAdventureWithConfig` seeds the opening, then enables conversation.
- Duplicate gate checks remain fail-closed: an edit between preview and creation is
  rejected unless the user explicitly authorized the previous ready revision.
- Compression continues to use the existing worker and real publication; pending,
  failed, stale and interrupted states are never mapped to ready by this patch.

## Implementation and invariants

- Run normal preparation on explicit persisted-save reuse/reconciliation, including
  batch imports. No duplicate resource tree or content revision is created by reuse.
- Run normal assembly completion after the last required Part retry commits.
- On explicit gate preparation only, capture an absent latestHead from the saved live
  tree through `ResourceRevisionService` before normal preparation. Read-only resolution
  still reports unsaved/no-revision resources as blocked; retry never fabricates ready.
- Compare readiness target revision/hash, assembly revision/hash and latestHead hash.
  Check reconstructed revision hashes before publishing or reusing an assembly.
- A missing resource with a previously frozen managed binding is an explicit refusal;
  genuine legacy-only IDs retain their established compatibility behavior.
- Resolution and freeze failures retain a resource-scoped typed issue and safe stage /
  exception category. Both assembly launch UIs render all issues, ID/state and localized
  actionable reasons, including snapshot corruption and missing resources.
- Logs use stage, exception class, resource ID/type, revision ID/state and hashes;
  arbitrary exception messages, API keys, prompts and authored content are not logged.
- Start guard coalesces equivalent frozen snapshots despite volatile created_at,
  observes failure cleanup and permits immediate retry after failure.
- Initialization/opening exceptions roll back only the newly created ID owned by that
  attempt, using the existing repository's transactional session deletion. Previously
  existing sessions and source resources/snapshots are never rollback targets. Rollback
  failure is logged and the start still throws; it is never reported as success.
- No database schema or version bump, resource deletion, snapshot rewrite or clearing
  of user databases is needed. `DatabaseService.resetDatabase` in tests only closes
  fixture connections; all fixtures use isolated temporary directories.

## Regression evidence

`test/application/resources/adventure_start_sqlite_production_test.dart` uses real
sqflite_common_ffi SQLite and the production ProviderContainer graph. Model and platform
responses are fixture-controlled; persistence, revision, readiness, freeze, session,
opening and continued conversation are not mocked.

- Fresh import/manual save -> matching latest/assembly hashes -> frozen bindings ->
  concurrent duplicate start returns one ID -> one session and one persisted opening.
- Imported resource -> production HTTP transport to a local SSE fixture -> one user
  message and one assistant continuation -> three SQLite messages -> reopening the
  database retains all three messages.
- Production AI planning/NDJSON Part generation/commit/completion -> readiness -> start.
  Manual Part edit -> stale -> successful Part retry -> new matching ready assembly.
- Edited save with injected preparation failure -> unchanged single save and unchanged
  batch save both recover through actual preparation -> start succeeds.
- Associated worldview + protagonist + second character + NPC -> four frozen resource
  bindings; NPC worldview ID, affinity and session opening persist.
- Corrupted revision -> `revisionHashMismatch`, assemblyBuild stage and exception type,
  resource-scoped refusal, zero sessions, no private-body sentinel in logs. Restoring
  the fixture's original revision bytes followed by preparation restores readiness.
- Corrupt readiness hash -> stale refusal -> real preparation recovers. Dead-process
  preparing record -> recoverInterrupted -> failed -> explicit preparation -> ready.
- Previously bound resource moved to trash -> resourceMissing refusal and zero sessions.
- SQLite triggers fail game_state initialization or opening insert: only the new session
  is rolled back; the prior session, its opening and source resource remain. Dropping
  the trigger permits immediate retry with exactly one new complete session.
- Real v41 schema -> normal v48 upgrade -> legacy migration -> explicit capture/prepare
  -> successful freeze -> session -> persisted opening; the character was saved before
  upgrading, and its legacy source row remains intact.

Existing real-SQLite resource/coordinator/compression/migration suites cover pending and
failed compression, async supersession, single-flight preparation, stale choices and
assembly index publication. The larger targeted run passed 747 tests; the final launch
focused run passed 40 tests. Full-suite and build results are recorded below.

## Validation and build

- `dart format --output=none --set-exit-if-changed`: 21 Dart files checked, zero changes.
- `flutter analyze --no-pub`: No issues found.
- Resource/application expanded targeted run: 747 passed.
- Final launch/SQLite/gate/localization focused run: 40 passed.
- Final SQLite suite after strengthening the pre-upgrade fixture/start assertions: 11 passed.
  No production code changed during the final full-suite run; this last test-only
  extension was separately rerun in full.
- Full `flutter test --no-pub`: 3,637 passed, 2 skipped, zero failures (15m 15s).
  Existing skips require an optional real TTS model or Chrome platform.
- `git diff --check`: passed.

The first final full-suite attempt encountered an existing export test's sandbox write
restriction under Downloads. Its exact synthetic target was absent before escalation.
The same existing end-to-end test passed all 3 cases after automatic approval permitted
the requested test command. The complete suite passed under that permission;
the restricted attempt is not counted as a passing suite.

ARM64 commands were executed for both release and debug (`flutter build apk --no-pub
--target-platform android-arm64`, plus `--debug` for the latter). Debug failed at
`:app:mergeDebugAssets` because official Google Maven AAR downloads returned HTTP 503,
including lifecycle-runtime-ktx 2.7.0 and core-ktx 1.18.0. Flutter/Gradle automatic retries
and bounded direct official-origin retries did not recover all dependencies. Several
successfully downloaded files matched Gradle module SHA256 metadata, but the incomplete
cache was never configured as a project repository. No mirror, insecure TLS setting,
dependency upgrade or source build-configuration workaround was used. No APK is claimed.

The environment initially lacked an Android SDK and a JDK compiler. Both were installed
under `/workspace/.toolchains` without modifying source dependencies or host system files.
Flutter/Dart needed user-level analysis caches; approved sandbox escalation was confined
to running the requested tools. Package downloads used allowed pub.dev; Google and Gradle
traffic retained the session proxy and TLS verification. pubspec.lock was restored to its
original bytes after tooling changed package-host URLs; dependency versions were unchanged.

Release ARM64 reached `:app:verifyReleaseSigning` and was rejected because the configured
stable release identity (`android/key.properties` and associated keystore) is absent.
No replacement signing identity was invented and the release guard was not bypassed.

No Android device is attached (`adb devices -l` returned an empty list). Device reproduction, upgrades on an actual Android file,
backgrounding/process termination, and on-device launch verification remain incomplete.

## Files changed

- `docs/codex/android-adventure-start-regression.md`
- `lib/application/adventure/adventure_readiness_gate.dart`
- `lib/application/resources/assembly_readiness_coordinator.dart`
- `lib/application/resources/resource_assembly_builder.dart`
- `lib/application/resources/resource_creation_pipeline.dart`
- `lib/application/resources/resource_revision_service.dart`
- `lib/application/resources/streaming_resource_generation_service.dart`
- `lib/features/adventure/presentation/wizard/adventure_readiness_message_localization.dart`
- `lib/features/adventure/presentation/wizard/screens/adventure_wizard_screen.dart`
- `lib/features/adventure/presentation/wizard/screens/assembly_create_page.dart`
- `lib/features/adventure/presentation/wizard/screens/assembly_preview_page.dart`
- `lib/l10n/app_en.arb`
- `lib/l10n/app_ja.arb`
- `lib/l10n/app_ko.arb`
- `lib/l10n/app_zh.arb`
- `lib/l10n/app_zh_Hans.arb`
- `lib/l10n/app_zh_Hant.arb`
- `lib/l10n/generated/app_localizations.dart`
- `lib/l10n/generated/app_localizations_en.dart`
- `lib/l10n/generated/app_localizations_ja.dart`
- `lib/l10n/generated/app_localizations_ko.dart`
- `lib/l10n/generated/app_localizations_zh.dart`
- `lib/models/character_card_entry.dart`
- `lib/providers/adventure_provider.dart`
- `lib/providers/chat_provider.dart`
- `lib/services/adventure_start_guard.dart`
- `test/application/resources/adventure_start_sqlite_production_test.dart`
- `test/unit/adventure_readiness_message_localization_test.dart`

## Evidence locations and review

- Root reproductions: `/tmp/lt-production-paths-before.log` and
  `/tmp/lt-production-before.log`.
- Final focused run: `/tmp/lt-targeted-final.log` (40 passed).
- Strengthened production SQLite suite: `/tmp/lt-sqlite-final.log` (11 passed).
- Final full suite: `/tmp/lt-full-test-approved.log` (3,637 passed, 2 skipped).
- Final static analysis: `/tmp/lt-analyze-final.log` (no issues).
- ARM64 build blockers: `/tmp/lt-android-release-final.log` and
  `/tmp/lt-android-debug-final.log`.
- Integrated review checked completion hooks, immutable revision/hash validation,
  per-resource typed refusals, session compensation ownership, safe logging and
  preservation of dependency versions/build configuration. No independent reviewer
  or real Android-device acceptance is claimed.
- Dedicated local branch: `fix/android-adventure-readiness`. No push or release.
