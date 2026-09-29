# Related Character Generation Execution Plan

This is a staged implementation plan only. No phase is started by this design task. Each phase is independently reviewable and must preserve the existing Resource Studio authority.

## Phase 0 — Historical audit and contract freeze

**Goal:** confirm the implementation baseline and freeze vocabulary/ownership.

**Scope:** verify current branch/schema at implementation time; record current Resource Studio entry chain; freeze `CharacterRelationship`, `CharacterGenerationReference`, `CharacterGenerationRelationship`, and `CharacterRelationshipDraft` contracts; document legacy paths that remain forbidden.

**Files:** `docs/character-relationships/*`; relevant current resource/adventure contract files read-only during planning.

**Implementation:** no feature behavior; produce an approved contract decision record before code changes.

**Tests:** contract examples and architecture checks planned, not production tests yet.

**Acceptance criteria:** reviewers agree on resource-vs-Adventure authority, direction model, endpoint identity, and save boundary.

**Out of scope:** schema, UI, prompt, or migration changes.

**Risks:** baseline may move; recheck schema and worktree immediately before Phase 1.

## Phase 1 — Resource relationship domain and repository

**Goal:** create the resource-lifetime relationship authority.

**Scope:** typed entity/value objects, validation, canonical identity, repository interface, endpoint queries, edit/delete, lifecycle hooks.

**Files:** new resource domain/application relationship files; repository/provider wiring; no Adventure model replacement.

**Implementation:** use one entity with endpoint roles; enforce uniqueness and live endpoint checks; expose transactional methods needed by the save use case.

**Tests:** unit and repository tests for symmetric/directional/custom relations, duplicates, indexes, and edits/deletes.

**Acceptance criteria:** no UI or service writes relationship tables directly; repository can create/query both endpoint projections.

**Out of scope:** generation UI and prompt changes.

**Risks:** legacy card IDs versus unified resource IDs; resolve with an explicit adapter.

## Phase 2 — Typed generation reference contract

**Goal:** replace domain-level map propagation with typed references.

**Scope:** mapper, context builder, draft/session payload, compatibility adapter for `AiGeneratorService`.

**Files:** `character_reference_context_mapper.dart`, new application contract/builder files, Resource Studio draft/orchestrator seams, LLM gateway adapter.

**Implementation:** preserve IDs, per-reference relationship specs, bounded facts, worldview inheritance, and deterministic budget ordering; keep map conversion only at the adapter boundary.

**Tests:** mapper, validation, multi-reference isolation, budget behavior, fast/detailed contract tests.

**Acceptance criteria:** fast and all detailed stages receive identical relationship constraints; aliases are confined to the adapter.

**Out of scope:** permanent relationship writes.

**Risks:** staged prompt code has several map call sites; audit every call before changing signatures.

## Phase 3 — Resource Studio integration

**Goal:** carry a relationship draft through planning, generation, review, retry, and candidate acceptance.

**Scope:** creation session metadata, related-generation entry adapter, retry/revision identity, candidate state.

**Files:** Resource Studio application use cases/runtime/controller/page and creation contracts.

**Implementation:** mount draft on the existing session; preserve it across B1→B2 retries; never persist an edge during generation or discard.

**Tests:** session lifecycle, cancellation, late chunks, invalid candidate, retry replacement, and draft recovery.

**Acceptance criteria:** Resource Studio remains the only generation/review pipeline and exposes a typed accepted-candidate payload plus draft.

**Out of scope:** detail display and Adventure projection.

**Risks:** session persistence must not accidentally make a draft look like a permanent edge.

## Phase 4 — Character detail and creation-page UX

**Goal:** provide both product entry points.

**Scope:** locked-source detail flow; repeatable per-reference editor; worldview inheritance; generation request and target length.

**Files:** resource library character detail/AI creation pages, route adapters, shared relationship widgets, ARB files and generated localization.

**Implementation:** use cards/ExpansionTiles/bottom sheets on mobile; localize every label; validate source IDs and relation roles before submit.

**Tests:** widget flows, localized labels, long names/descriptions, 320/360/390/412/768 viewports, no overflow.

**Acceptance criteria:** source A can launch generation without reselecting; general creation supports zero/one/many independently specified references.

**Out of scope:** writing relationship rows.

**Risks:** unrelated existing worktree localization/UI edits; isolate changes and review diff carefully.

## Phase 5 — Atomic persistence

**Goal:** persist accepted B and all resource edges as one business operation.

**Scope:** application use case, repository transaction, idempotency, typed failure mapping, resource ID allocation.

**Files:** resource save use case, library/resource repository transaction methods, providers, session completion path.

**Implementation:** `BEGIN` insert B and edges, commit together; rollback on any error; use creation session/idempotency key to make repeated saves safe.

**Tests:** commit, rollback, duplicate conflict, double tap, cancellation/no-write, and B1/B2 final-edge tests.

**Acceptance criteria:** impossible states (edge without B or successful UI with only B) are rejected and covered by tests.

**Out of scope:** migration of old Adventure relationships.

**Risks:** resource lifecycle/revision writes may require transaction participation; define repository transaction ports first.

## Phase 6 — Relationship display, edit, and delete

**Goal:** make resource relationships usable after save.

**Scope:** endpoint projections on character detail, perspective labels, edit form, delete edge, unavailable/trash states.

**Files:** character detail/library widgets, relationship application use cases, localized strings.

**Implementation:** query by either endpoint; derive perspective from endpoint roles; delete only the edge; guard against stale endpoint rows.

**Tests:** both endpoint views, directional labels, edit/delete, trashed and restored endpoints, responsive long content.

**Acceptance criteria:** A and B show semantically correct perspectives and no unknown IDs.

**Out of scope:** Adventure snapshot projection.

**Risks:** legacy and unified detail surfaces may read different repositories; route both through one authority.

## Phase 7 — Adventure projection

**Goal:** bridge resource facts into Adventure snapshots without coupling lifecycles.

**Scope:** selection-time projection, user confirmation, mapping to `AdventureCharacterRelationship`, snapshot edit semantics.

**Files:** Adventure creation/wizard application layer and tests; no direct resource mutation from Adventure runtime.

**Implementation:** project only when both endpoints are selected; preserve roles where the snapshot supports them; resource changes affect future projections only.

**Tests:** projection, refusal of missing endpoints, snapshot isolation, existing Adventure regression suite.

**Acceptance criteria:** an Adventure can start with a confirmed projection and later diverge without changing the library edge.

**Out of scope:** redesigning all Adventure relationship semantics.

**Risks:** current Adventure model may need a narrowly scoped perspective field.

## Phase 8 — i18n and responsive convergence

**Goal:** complete locale and viewport quality gates.

**Scope:** all locales, generated localization, 320–desktop widget regression matrix, keyboard/insets and SafeArea review.

**Files:** ARB/generated files, shared relationship widgets, responsive test helpers.

**Implementation:** remove literals; use flexible/wrapped layouts and scrollable dialogs/sheets.

**Tests:** all mandated viewports, long dynamic text, large text scale, `tester.takeException()` and overflow assertions.

**Acceptance criteria:** no horizontal/bottom overflow and all core actions remain reachable at 320 px.

**Out of scope:** new product behavior.

**Risks:** generated localization churn; run only after source ARB review and isolate unrelated edits.

## Phase 9 — Deep verification and independent audit

**Goal:** prove the closed loop and preserve existing behavior.

**Scope:** full targeted unit/repository/integration/widget matrix, static analysis, diff audit, security/data review, architecture review.

**Files:** tests and audit documentation only within approved scope.

**Implementation:** execute tests against current schema; inspect transaction traces and prompt projections; verify no legacy authority reappears.

**Tests:** all Phase 1–8 acceptance tests plus ordinary generation, no-reference generation, Resource Studio, Resource Library, Adventure Wizard, and existing relationship regressions.

**Acceptance criteria:** requirement-by-requirement evidence proves source facts + explicit relation + AI generation + user review + atomic save + persistent edge + Adventure projection; `dart format`, `flutter analyze`, targeted `flutter test`, and `git diff --check` pass for the implementation diff.

**Out of scope:** unrelated worktree cleanup or opportunistic refactoring.

**Risks:** schema drift, flaky LLM tests, and pre-existing failures must be separated from regressions and reported honestly.
