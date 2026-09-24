# Import Authority Convergence — Phase 2

## 1. Baseline

- Branch: `main`
- Start HEAD: `ac0bd4e9aa25f3dcf7d530e7f1292544251784fd`
- `origin/main`: same commit at audit time
- Database schema version: `44`
- No migration or schema change was introduced.

Phase 1 production wiring remains the composition root for the canonical
`ResourceCreationPipeline`, Studio runtime, blueprint repository and streaming
generation infrastructure.

## 2. Removed legacy production surface

The three import controllers, their Riverpod providers, and
`application/resource_library/import_use_cases.dart` were deleted. The old
`import_models.dart` was reduced to the presentation-only
`ResourceCardImportKind` enum. The old `generate → Draft → save` and
`identify → direct LLM → importSelected` paths therefore no longer compile in
production.

Worldview and character/NPC import pages now only collect input and navigate to
`ResourceStudioPage`. Their local `_openingStudio` flag is a navigation guard,
not generation state. Scene Batch keeps only its local command loading/error
state and uses the existing `createAndPlan → candidate selection →
confirmAndStart` flow.

The character reference conversion moved to the stateless
`CharacterReferenceContextMapper`, backed by `CharacterCardStorageAdapter`.

## 3. Final production call graph

```text
Worldview       UI → ResourceStudioPage → ResourceStudioRuntime →
                ResourceAiCreationOrchestrator
Character/NPC   UI → ResourceStudioPage → ResourceStudioRuntime →
                ResourceAiCreationOrchestrator
Scene Batch     UI → createAndPlan → Blueprint candidates → confirmAndStart →
                Streaming Runtime → ResourceStudioPage
Manual CRUD     ResourceCrudController / CharacterManager / WorldEngine →
                LegacyCreationBridge.save* → ResourceCreationPipeline
```

## 4. Retained compatibility surface

`LegacyCreationBridge.saveWorldview`, `saveCard` and `saveCards` remain for
manual and compatibility writes used by `ResourceCrudController`,
`CharacterManager` and `WorldEngine`. Its AI planning wrappers were removed;
planning and confirmation are now called by the formal Studio runtime and
orchestrator. Final bridge removal remains Phase 3 work after explicit tree
ports are available.

## 5. Test migration

| Previous coverage | Result | Current authority |
| --- | --- | --- |
| Import controller/use-case generation and draft lifecycle tests | Deleted as obsolete | Studio runtime/orchestrator tests |
| Scene batch identify/importSelected tests | Deleted as obsolete | Blueprint candidate and Runtime tests |
| CRUD, pipeline idempotency, rollback, revision and readiness tests | Kept | ResourceCreationPipeline / CRUD / readiness |
| Architecture guard | Strengthened | Filesystem/static production graph guard |

## 6. Static guard result

The production tree contains no legacy import controller/provider or import
use-case symbol. LLM gateway methods that support other subsystems remain
available at their interface boundary; the Resource Library production graph
does not call them directly.

## 7. Remaining Phase 3 work

- Define the final `CreationSession` versus generation/readiness projection.
- Introduce a single read-only consumable resource status projection.
- Replace remaining compatibility bridge callers with explicit creation/tree
  ports, then remove `LegacyCreationBridge`.

## 8. Verdict

Phase 2 code scope is complete with schema version 44 unchanged. Validation
results are recorded in the task completion report and must be rerun against
the final worktree before release.
