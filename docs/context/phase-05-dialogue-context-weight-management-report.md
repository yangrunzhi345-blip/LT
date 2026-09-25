# Phase 5 Context Weight Management

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

Focused narrative budget, runtime, stress and viewport tests pass. Full regression remains the final release gate.

## Audit Rounds

### Round 1: Authority

`PromptBuilder` is the only production prompt entry point for narrative dialogue; world retrieval remains delegated to `WorldContextBuilder`, and runtime character/world projections are split in `RuntimeMemoryProjector`.

### Round 2: Budget and determinism

The planner orders by priority and stable source ID, protects mandatory candidates, applies source floors/caps, and reallocates remaining budget. Its diagnostics are metadata only and do not contain source text.

### Round 3: Product and persistence

Settings persistence uses the existing KV repository, missing profiles default to Balanced, all six locales have labels, and compact AppBar/source controls were verified at 320, 360 and 390 logical pixels.
