# Related Character Generation Phase 2–8 Progress Record

> **历史进度快照（Historical progress snapshot）——Phase 8 结束、Phase 9/10 之前的时点状态。**
>
> 本文件记录 Related Character Generation 在执行到 Phase 8 时的进度。该程序随后继续推进：
> Phase 9 集成验收见 [`phase-09-integrated-acceptance.md`](./phase-09-integrated-acceptance.md)，
> Phase 10 Runtime Narrative Integration 已 `ACCEPTED`
> （见 [`phase-10-runtime-narrative-acceptance.md`](./phase-10-runtime-narrative-acceptance.md)）。
> 因此下文的 "Current status / Phases 2–8 are implemented" 是**当时快照**，不是本程序的最终状态。

## Verified baseline

- Current schema version is 48. Version 48 adds the durable
  `relationship_draft_json` column to `resource_creation_sessions` and an
  idempotent v47 → v48 migration.
- The working tree is clean after the implementation commits listed below.
- `flutter analyze --no-pub` passes.
- Full `flutter test --no-pub` passes: 3211 tests passed and 2 skipped.

## Implemented contracts

- `CharacterGenerationReference`, `CharacterGenerationRelationship`, and
  `CharacterRelationshipDraft` provide immutable typed generation intent.
- References use `ResourceId`, validate directional roles, isolate metadata,
  and serialize for session recovery.
- Legacy map conversion is isolated to `toLegacyPromptMaps()`.
- Resource Studio drafts, creation sessions, and the AI orchestrator carry the
  typed relationship draft.
- `CharacterGenerationCandidate` distinguishes regenerated candidates by
  candidate id and revision.

## Persistence and projection seams

- `AcceptGeneratedRelatedCharacter` owns one SQLite transaction for a Resource
  tree and all relationship edges. A real SQLite test proves rollback when a
  later endpoint fails.
- `CharacterRelationship.perspectiveFor` provides endpoint-correct roles.
- `CharacterRelationshipManagement` is the application boundary for list,
  update, and delete operations.
- `ResourceRelationshipProjection` and
  `AdventureAssembler.assembleWithResourceRelationships` create an Adventure
  snapshot only when both endpoints are selected.

## Status at the end of Phase 8 (historical snapshot)

Phases 2–8 are implemented. Relationship editing is available from Character
Detail, Adventure creation projects a frozen relationship snapshot, the
Resource Studio carries typed relationship drafts through planning and resume,
and candidate acceptance is routed through the atomic application boundary.
Phase 9 acceptance evidence is recorded in
`phase-09-integrated-acceptance.md`.

## Commits

- `8c50201` through `a05eeb8` contain the typed contracts, session durability,
  perspective/projection seams, atomic accept use case, and verification.
- `96a25e3` aligns migration fresh-install assertions with schema 48.
