# Import Authority Phase 3 Final Report

## 1. Baseline

- Start HEAD: `27bec21e784284ea2be8867f9839a5f81abb9d9f`
- `origin/main`: `27bec21e784284ea2be8867f9839a5f81abb9d9f`
- Branch: `main`
- Working tree at start: clean
- Database schema: v44

The i18n work was treated as a frozen baseline. No schema migration was
required for this convergence.

## 2. Previous Phase 3 Gap Inventory

The prior audit identified two major gaps: a second `DatabaseService` pipeline
construction path and the absence of a single consumable lifecycle projection.
`LegacyCreationBridge` also remained in production as a payload adapter, which
made the creation boundary ambiguous even though tree writes already used the
same repository transaction.

## 3. Already-Completed Work Discovered at Current HEAD

The current HEAD already had the streaming session/task/attempt runtime,
revision capture, assembly readiness records, a read-only projection skeleton,
Riverpod pipeline wiring, and fail-closed Adventure readiness checks.

## 4. Changes Actually Made

- Renamed the production payload adapter to `ResourceCreationPort` and removed
  `LegacyCreationBridge` from production sources.
- Removed `DatabaseService.entryCreationPipeline` and its ad-hoc pipeline
  builder. Production providers inject the canonical Pipeline explicitly.
- Made CRUD, CharacterManager, and WorldEngine require an injected port for
  save operations; missing test seams fail explicitly instead of constructing
  another Pipeline.
- Extended `ResourceLifecycleProjection` with missing, paused, and recovering
  states and an explicit `isConsumable` contract.
- Routed Resource Library status resolution through the lifecycle projection.
- Added architecture guards for Bridge removal and single Pipeline
  composition, plus lifecycle regression cases.

## 5. Final Production Call Graph

```text
UI / Library / CharacterManager / WorldEngine
  -> ResourceCreationPort
  -> canonical ResourceCreationPipeline (Riverpod composition root)
  -> Blueprint / Generation runtime
  -> ResourceTreeRepository and revision boundaries
  -> SQLite resource tree
```

AI creation continues through `ResourceAiCreationOrchestrator`, Blueprint
confirmation, Streaming Generation Session, Task/Attempt coordination, and
CAS-protected Part commits.

## 6. Lifecycle Semantics

Creation session completion means the creation request/Blueprint phase is
complete. Generation, validation, revision publication, and consumability are
separate facts. A failed, paused, recovering, cancelled, missing, or archived
resource is never consumable.

## 7. Lifecycle Projection Contract

`ResourceLifecycleProjection` is read-only and derives its result from the
resource tree, creation session, generation session, latest revision, and
assembly readiness repositories. It performs no writes, state transitions,
generation, repair, or persistence. `isConsumable` is true only for a
published ready assembly revision.

## 8. LegacyCreationBridge Removal Evidence

```text
rg "LegacyCreationBridge|legacy_creation_bridge|entryCreationPipeline" lib
```

Returned no matches. The former adapter file is now
`lib/application/resources/resource_creation_port.dart` and has no Bridge
symbol.

## 9. Composition-Root Convergence Evidence

```text
rg "ResourceCreationPipeline\\(" lib
```

The only production construction is the streaming infrastructure provider in
`lib/providers/riverpod_providers.dart`; the other match is the class
constructor declaration itself. CRUD, Library, CharacterManager, WorldEngine,
Studio, and Adventure wiring use that provider instance.

## 10. Database / Schema Impact

No database schema change. Existing v44 tables remain authoritative for the
resource tree, sessions, revisions, and readiness. No duplicate current-state
table was introduced.

## 11. Tests Added / Updated / Deleted

- Added lifecycle cases for missing, paused, recovering, and
  `CreationSession.completed` plus generation failure.
- Updated production wiring and entry-point tests for `ResourceCreationPort`.
- Added an architecture guard for Bridge removal and ad-hoc Pipeline
  construction.
- No tests were deleted.

## 12. Validation Commands + Exact Results

- `dart format --set-exit-if-changed .` — passed: 631 files checked, 0 changed.
- `flutter analyze` — passed: no issues found.
- Targeted lifecycle/authority/creation tests — passed.
- `flutter test` — passed: 2211 tests passed, 1 skipped, 0 failed.
- `git diff --check` — passed.

## 13. Three Audit Rounds

### Round 1 — Authority

Static call-graph review and the production wiring test show one Riverpod
Pipeline instance shared by CRUD, Chat child providers, Library, Character, and
Worldview paths. No DatabaseService Pipeline fallback remains.

### Round 2 — Lifecycle

Projection tests cover planning, generation, validation, failure, paused,
recovering, missing, revision carry-through, and ready assembly. A completed
creation session with failed generation remains failed and non-consumable.

### Round 3 — Legacy / Regression

Production source scans show no old Bridge, entry Pipeline, or removed Import
generation surface. Existing streaming task/attempt CAS, revision, autosave,
recovery, and Adventure readiness paths were left intact and targeted tests
remain green.

## 14. Remaining MINOR / INFO

- Some direct unit-test fixtures intentionally construct `ResourceCreationPipeline`
  themselves; they are outside `lib` and are not production composition roots.
- Legacy row projection remains a read-only compatibility view for existing
  consumers; it does not write legacy tables.

## 15. Final Verdict

**ACCEPTED**
