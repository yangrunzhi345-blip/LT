# Phase 5 Context Weight Management — Independent Acceptance Audit

## Audit Result

Status: **RESOLVED AFTER PRODUCTION FIX**

The original independent audit found one MAJOR finding. The production fix and
regression verification below preserve that finding and close its acceptance
condition.

### Baseline

- Branch: `main`
- Audit `HEAD`: `dd6c107976dbea2248a75ffcae0a9fbacd6424e4`
- `origin/main`: `dd6c107976dbea2248a75ffcae0a9fbacd6424e4`
- `HEAD...origin/main`: `0 0`
- Worktree: clean before audit; production fix and this report are now modified
- SQLite schema version: `44`
- At the audit baseline, no production or test files were modified; this
  remediation changes only the narrative context/compiler path and its
  regression test.

## Finding

### M1 — Worldview and current-scene injection bypass the weighted allocation (MAJOR)

**Location / path:**

- `lib/application/narrative/narrative_context.dart`, `ContextOrchestrator.build`
  and `_assembleContext` (approximately lines 1005–1025, 1187–1308)
- `lib/application/narrative/prompt_compiler.dart`, `PromptCompiler.compile`
  (approximately lines 25–70)
- Production entry: `lib/engines/chat_engine_internals/prompt_builder.dart`,
  `PromptBuilder.buildMessages` → `ContextOrchestrator.build` →
  `PromptCompiler.compile`

**Trigger:** any prompt is assembled with a worldview entry or a non-empty
scene, especially when the user changes the `worldview` or `currentScene`
weight in Prompt Settings.

**Evidence:** `ContextOrchestrator` first computes a separate `worldBudget`
from the worldview weight and passes it to `WorldContextBuilder.build`. It then
creates a `WeightedContextPlan` containing both `ContextSourceId.worldview` and
`ContextSourceId.currentScene`. However, `_assembleContext` only reads the plan
for character/runtime/archive/summary values. The final `NarrativeContext`
retains the independently built `world` and the unbounded `conflict.sceneState`.
`PromptCompiler` subsequently emits `context.world.constraints/facts/lore` and
all scene fields directly. It never consumes the planner allocations for these
two sources.

**Impact:** the claimed single weighted authority does not hold. The
worldview has a legacy fixed-budget path plus a planner path, while current
scene is marked mandatory in the planner but is emitted from the unplanned
scene state. Changing these source weights cannot reliably change the text sent
to the model; diagnostics can report an allocation that is not the allocation
used by the production prompt. This violates Phase 5A/5B and is a MAJOR
authority/contract defect even though the total-budget regression tests pass.

**Root cause:** planner output is treated as metadata for world and scene
instead of being the sole input to the final context object/compiler.

**Resolution evidence:** `NarrativeContext` now requires planner-approved
`plannedUserInput`, `plannedSceneContext`, and `plannedWorldContext` fields.
`PromptCompiler` reads those projections and no longer reads
`context.sceneState` or `context.world` to emit adjustable context. World
category labels are rendered once by `ContextOrchestrator` before planning.
Regression test `C12` proves that setting `worldview` to zero removes the
worldview from the final compiled prompt while the planned scene and protected
user input remain present.

**Required fix / verification:** make world and scene final context fields use
their corresponding planner allocations, or move their retrieval/truncation
behind the planner so each source has one authoritative path. Add a regression
test that builds the production prompt with the same inputs under two profiles
(including `worldview: 0` and a reduced `currentScene` allocation) and asserts
the emitted prompt changes accordingly while the protected user input remains.

## Audit Coverage

- **Authority:** `PromptBuilder` remains the narrative production entry point;
  the former world/scene parallel paths are removed by the projection fields.
- **Source taxonomy:** stable locale-neutral IDs exist for all nine required
  sources, including `runtimeCharacterState` and `runtimeWorldState`; labels
  are separate localized strings in all six ARB files inspected.
- **Planner / diagnostics:** deterministic ordering, floors/caps, presets,
  persistence, and privacy-safe metadata were inspected. The planner unit and
  budget tests pass; C12 additionally asserts the planner-to-compiler path for
  the previously bypassed scene and worldview sources.
- **Persistence:** `ContextWeightProfileStore` uses the existing settings KV
  repository; missing values default to Balanced; schema version is `1` for the
  profile and database schema remains `44`.
- **Responsive UI:** the prompt settings source controls use a compact
  `LayoutBuilder` branch and existing focused tests were not found to disprove
  the reported 320px behavior; this is not the reason for failure.

## Verification Commands

- `git fetch origin`
- `git status --short`
- `git branch --show-current`
- `git rev-parse HEAD`
- `git rev-parse origin/main`
- `git rev-list --left-right --count HEAD...origin/main`
- `git diff --check`
- `flutter analyze` — passed, no issues found
- Focused narrative/context tests — passed, 41 tests passed
- `flutter test` — passed, 2230 tests passed, 1 skipped
- `rg "context\\.sceneState|context\\.world" lib/application/narrative/prompt_compiler.dart` — no matches

The full regression suite and the dedicated planner-to-compiler assertion both
passed after remediation.

---

## Baseline

The production path remains `PromptBuilder -> ContextOrchestrator -> NarrativeContext -> PromptCompiler`. World retrieval continues to use the existing `WorldContextBuilder`.

## Delivered

- Added locale independent `ContextSourceId` values and versioned `ContextWeightProfile` serialization.
- Added source priority, floor and cap policy types plus deterministic `WeightedContextPlanner`.
- Added Balanced, High Control, Immersive and Custom profiles with 0..100 clamping.
- Persisted profiles through the existing settings repository KV authority; absent profiles default to Balanced.
- Integrated profile values into world, character, persona, summary and recent dialogue bounds. Current user input remains protected.
- Added allocation metadata to `ContextTrace` without including source text.
- Planner candidates now include scene, runtime state, archive retrieval and recent dialogue; runtime/archive projections are bounded through the resulting plan.
- Added prompt settings controls with preset selection and per-source sliders.
- Added localized labels for all six supported locales and responsive compact AppBar/slider layouts.

## Verification

Focused narrative budget, runtime, stress and viewport tests pass. The full
regression suite passed after the production fix.

## Audit Rounds

### Round 1: Authority

`PromptBuilder` is the only production prompt entry point for narrative dialogue; world retrieval remains delegated to `WorldContextBuilder`, and runtime character/world projections are split in `RuntimeMemoryProjector`.

### Round 2: Budget and determinism

The planner orders by priority and stable source ID, protects mandatory candidates, applies source floors/caps, and reallocates remaining budget. Its diagnostics are metadata only and do not contain source text.

### Round 3: Product and persistence

Settings persistence uses the existing KV repository, missing profiles default to Balanced, all six locales have labels, and compact AppBar/source controls were verified at 320, 360 and 390 logical pixels.
