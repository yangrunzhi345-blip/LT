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
- Added prompt settings controls with preset selection and per-source sliders.

## Verification

Focused narrative budget, runtime and weight contract tests pass. `git diff --check` passes. Full regression and viewport tests remain to be run before release acceptance.
