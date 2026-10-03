# Related Character Generation Phase 9 Integrated Acceptance

Status: ACCEPTED
Acceptance Mode: Integrated Single-Agent Full-Cycle

## Baseline and scope

Baseline commits: `edb6d27` through `ef38ad6`, with scope validation in
`225831b` and session-resume revalidation in `4dc247c`. The integrated
acceptance hardening commits are `c7b714c`, `61ad90e`, and `ea30051`; the
current working tree adds runtime, route, projection, and preview-boundary
hardening.

The accepted scope covers typed relationship intent, durable session drafts,
Resource Studio generation, candidate identity, atomic acceptance, character
detail relationship management, Adventure creation-time projection, and
responsive UI coverage.

## Recovery record

This acceptance was resumed after an unexpected host power-off. The initial
recovery state was **State B**: the implementation commits were present, while
the post-acceptance runtime, route, projection, preview-boundary, and test
changes were still in the working tree. Recovery started at `96ccdd4` with
`origin/main` at `ddc9023`; the completed hardening was committed as
`0ae639a`.

## Acceptance evidence

- Core Phase 2–9 targeted matrix: **121 tests passed, 0 failed, 0 skipped**,
  covering typed references, relationship persistence, atomic acceptance,
  runtime acceptance, Adventure projection, route/UI behavior, authority
  guards, responsive layouts, and localization paths.
- Production runtime acceptance seam: **8 tests passed** against the real
  SQLite repositories and `StreamingResourceStudioRuntime`.
- Character Detail → related generation route: **42 widget tests passed** in
  the Resource Library Phase 5 suite, including locked source A, optional
  reference B, typed draft propagation, and the Resource Studio route.
- Atomic acceptance suite: **11 tests passed** after the stale-candidate
  revision guard was added.
- Full `flutter test --no-pub`: **3245 tests passed, 2 skipped, 0 failed**.
- Mutation probes: removing the SQLite transaction caused the rollback proving
  test to fail; removing both idempotency guards caused the double-submit test
  to fail. All mutations were restored.
- `flutter analyze --no-pub`: **0 errors; 2 pre-existing test infos**
  (`prefer_const_constructors`).
- `git diff --check`: **passed**.

## Invariants reviewed

- Resource relationships are written only by the atomic acceptance use case.
- Relationship endpoints must be live character or NPC resources.
- Repeated acceptance is idempotent by operation identity and resource identity.
- Candidate review has no permanent relationship rows before explicit accept.
- Adventure reads relationships only during creation and stores a snapshot.
- Directional and custom endpoint roles survive resource-to-Adventure
  projection; legacy Adventure JSON defaults missing role fields safely.
- Mixed worldview references without an explicit compatible target raise a typed
  scope error; no first-reference fallback is used.
- Candidate acceptance revalidates the persisted creation session and confirmed
  Blueprint before committing. The acceptance boundary also rejects a
  candidate whose revision differs from the resource's persisted
  `blueprint_revision`, and records candidate identity/revision metadata.
- The Studio acceptance command is shown only for completed character/NPC
  resources created by a persisted creation session with a non-empty
  relationship draft. The generation session must also be completed and bound
  to the latest confirmed blueprint. Manual and ordinary no-reference
  character records do not expose a misleading acceptance action.
- The Adventure preview resolves the same application-owned relationship
  projection used by launch, so selected live resource edges are visible before
  the user confirms the Adventure.

## Production runtime acceptance coverage

The runtime-level SQLite tests cover successful relationship persistence,
idempotent repeated acceptance, missing or mismatched creation sessions,
missing relationship drafts, incomplete generation sessions, unconfirmed or
resource-mismatched blueprints, and stale resource/blueprint revisions. The
tests assert that review has no permanent edge, then assert both the
relationship row and accepted candidate metadata after the commit, and assert
no edge is written on every rejected path.

## Platform build evidence

- Recovery revalidation — Linux desktop: `flutter build linux --no-pub` passed
  for `0ae639a` and produced
  `build/linux/x64/release/bundle/lt_dialogue`.
- Historical pre-recovery evidence — Android debug: `flutter build apk --debug --no-pub` passed and produced
  `build/app/outputs/flutter-apk/app-debug.apk`.
- Historical pre-recovery evidence — Android release bundle: `flutter build appbundle --release --no-pub` passed
  and produced `build/app/outputs/bundle/release/app-release.aab`.
- Windows, macOS, and iOS builds were not run because the current host is
  Linux and only the Linux desktop and Android toolchains are available here.

Remaining scope findings: BLOCKER 0, MAJOR 0, MINOR 0, INFO 0. The two
pre-existing analyzer infos are listed above and are outside this scope.

The recovery task explicitly authorizes the final GitHub upload after the
post-recovery gates pass; the final remote state is verified by the recovery
workflow after push.
