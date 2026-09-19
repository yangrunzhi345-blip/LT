# R06 Implementation Report

## 1. Baseline

- Phase: R06 - Final Hardening, Compatibility & Safe Cleanup.
- Start HEAD: `36437d02f3f85ed0874971bf6f76aae808c39d7e`.
- Branch: `main`.
- Accepted full-suite baseline: 1724 passed / 0 failed (R05 acceptance).
- Schema start/end: 43 / 43; no schema or historical migration rewrite.
- Existing R06-A/B/C work was preserved when execution resumed after the prior
  loopback-socket and read-only Git metadata environment block.

## 2. Reconnaissance Findings

- N1 confirmed: upgrade code attempted to change `PRAGMA foreign_keys` inside
  the migration transaction, where SQLite does not transfer FK ownership.
- N2 confirmed: collection-wide `WorldEntry` decoding could turn one corrupt
  row into an empty result or fail the complete read.
- N3 confirmed: v42 -> v43 rewrite was guarded by `DROP ... IF EXISTS`, but
  repeat/idempotency and failed-upgrade rerun behavior lacked dedicated fixtures.
- N16 confirmed: `WorldEntryPosition` was persisted as `enum.index` and decoded
  through an unchecked `values` lookup.
- N17 confirmed: `TranslationMode` had the same ordinal-only persistence
  contract and unknown values had no explicit policy.

## 3. R06-A - Migration Hardening

- Assigned FK ownership exclusively to `onConfigure`, removed ineffective
  transaction-time PRAGMA toggles, and verify the opened/restored connection.
- Added a real v42 fixture covering v42 -> v43 behavior and final FK state.
- Added injected migration failure, transaction rollback, reopen, successful
  rerun, repeat migration, and idempotency coverage.
- Kept schema 43 and all historical migration semantics unchanged.

## 4. R06-B - Corrupt Row Isolation

- Added per-row `WorldEntry` decoding with typed table, row-id, and category
  diagnostics; payloads and user data are not logged.
- Persisted identity fields fail closed. Optional malformed fields use explicit
  defaults and produce diagnostics without discarding valid sibling rows.
- Diagnostic snapshots are immutable. Legacy repository list APIs return
  mutable copies to preserve their established caller contract.

## 5. R06-C - Serialization Compatibility

- New `WorldEntryPosition` and `TranslationMode` writes use stable string codes.
- Frozen legacy ordinal readers and legacy camelCase string readers remain.
- Unknown structural values and out-of-range ordinals fail closed.
- Added WorldEntry fixtures for stable strings, legacy strings/ordinals,
  malformed optional fields, bad identity, and unknown/out-of-range enums.

## 6. Hardening Internal Gate

- Migration fixture / FK behavior / rollback / reopen / rerun / repeat: PASS.
- Corrupt-row isolation / empty-vs-corrupt distinction: PASS.
- Serialization / legacy ordinal and string / unknown value policy: PASS.
- Initial R06-A/B/C targeted result: 16 passed / 0 failed.
- MUT-R06-1: restored wrong FK/PRAGMA ownership; migration/FK test FAILED.
- MUT-R06-2: removed migration idempotency guard; repeat test FAILED.
- MUT-R06-3: restored table-wide catch returning `[]`; isolation test FAILED.
- MUT-R06-4: restored ordinal-only enum persistence; compatibility test FAILED.
- Every mutation was fully restored and its file hash/diff checked.
- Gate result: **PASS**. Cleanup began only after this result.

## 7. Protected Compatibility List

The following surfaces default to **KEEP** and require complete replacement plus
compatibility evidence before deletion:

- Current migrations, historical migration readers, migration markers,
  `PRAGMA user_version`, schema version logic, all deployed table/column names,
  and v42/v43 forward-only behavior.
- Frozen legacy ordinal readers, stable string codecs, legacy camelCase codes,
  legacy JSON keys, compatibility decoders, and persisted identifiers.
- R01 generation session/task recovery, interrupted-session readers, startup
  recovery providers, and their production construction/side effects.
- R02 dialogue commit boundary, source-token CAS, autosave journal, serialized
  flush/requeue, cancellation, and error durability behavior.
- R03 trash/revision compatibility, belongs-to guards, owned-state purge
  transaction, restore gates, retention, and migration tombstones.
- R04 timeout, bounded retry, cancellation, scheduler permit, streaming,
  provider event, error, and completion contracts.
- R05 authoritative providers, creation pipeline, `ContextOrchestrator`, summary
  continuity, authoritative `TokenEstimator`, readiness gate, and wiring.
- Dynamic route names/strings, platform entrypoints and `main()` variants,
  plugin registration, provider construction, and provider lifecycle effects.

No protected migration, protocol, recovery, serialization, provider side effect,
dynamic route, or platform entrypoint was deleted.

## 8. R06-D - Reachability Inventory

Each candidate was checked against direct and string references, `git log -S`,
routes, provider construction, dynamic/reflection paths, serialization,
migrations, platform entrypoints, startup side effects, and tests. Zero `rg`
references were never used as the sole deletion criterion.

| Candidate | Decision | Evidence / disposition |
| --- | --- | --- |
| C1 scene approval orphan | DELETE | Controller/provider/repository mutation chain had no production construction, route, or dynamic caller. |
| C2 resource context compressor | DELETE | Superseded by R05 `ContextOrchestrator`; only its isolated test referenced it. |
| C3 dead AppSection/navigation | DELETE | Removed `creation`/`data` and unreachable creation-project navigation state. |
| C4 PresetManager duplicate | DELETE | Authoritative manager retained; duplicate model-local static manager had no callers. |
| C5 multi-character accessors | DELETE | Facade/accessors had no production, persisted, dynamic, or test contract. |
| C6 scheduler branches | DELETE | Retained reachable `deepseek`/`custom` policy; impossible provider-id branches removed. |
| C7 | CLOSED BY R05 | Prior R05 production wiring convergence remains authoritative. |
| C8 viewport helper duplicate | DELETE | Callers migrated to `test/helpers/responsive_test_helper.dart`. |
| C9 stale comments | DELETE/FIX | Removed stale phase/provider ownership narration only. |
| C10 LLM dead branches | MIXED | `completeFim` deleted; Anthropic transport branch kept/deferred as a compatibility seam. |
| C11 miscellaneous methods | MIXED | `buildJsonBody`, `generateStructuredJson`, `temperatureOverride`, and dead detailed-worldview hooks deleted; `toResourceTree` kept. |
| C12 disabled toast | DELETE | Disabled widget had no route, provider, or production caller. |
| C13 mechanical debt | DELETE | Removed `firstTerminalError` dead assignment and two self-copies. |
| C14 | CLOSED BY R05 | R05 context overflow behavior remains authoritative. |
| R05 app_config setup-context | DELETE | Production always disabled the branch; R05 orchestrator is authoritative. |
| `switchBranch` / `switchToMainBranch` | KEEP/DEFER | Latent public facade paths retained; no evidence of permanent product removal. |

## 9. R03-A-N1

- Reproduction confirmed that purging a Section left descendant Part generation
  tasks and autosave drafts behind.
- The node-scoped purge now resolves descendant Part ids and deletes their
  generation tasks and autosaves inside the same transaction.
- Tests prove sibling/other-resource isolation, rollback atomicity, and
  retry/idempotency. R03 lifecycle result: 15 passed / 0 failed.
- Final status: **FIXED**.

## 10. R06-E/F/G Cleanup

- R06-E converged C4 to the authoritative preset manager and C8 to the shared
  responsive viewport helper before deleting duplicates.
- R06-F removed only inventory-proven production surfaces: C1, C2, C3, C5,
  C6, the deletable parts of C10/C11, C12, and dead app-config setup context.
- R06-G removed stale comments, dead assignments/self-copies, unused locals,
  and mechanically impossible branches only.
- No ChatEngine/provider hierarchy/database/UI redesign, performance project,
  or new feature was introduced.
- Cleanup guard result: 2 passed / 0 failed. Cleanup/production targeted group:
  126 passed / 0 failed.

## 11. Cleanup Mutations

- MUT-R06-5: temporarily removed the required `TranslationMode` legacy ordinal
  reader; serialization compatibility test FAILED. Restoration hash matched.
- MUT-R06-6: temporarily disconnected the `MainGate` startup recovery provider;
  production wiring/reachability test FAILED. Restoration hash matched.
- Both mutations were fully restored; no mutation residue remained.

## 12. Verification

- R06 comprehensive targeted group: 169 passed / 0 failed before the B6
  contract regression fixture was added.
- R01 critical regression: 28 passed / 0 failed.
- R02 critical regression: 59 passed / 0 failed.
- R03 lifecycle regression: 15 passed / 0 failed.
- R04 streaming regression: 24 passed / 0 failed.
- R05 runtime/context/summary regression: 46 passed / 0 failed.
- `dart format --output=none --set-exit-if-changed .`: PASS, 506 files,
  0 changed.
- `flutter analyze`: PASS, no issues found.
- First effective full run exposed two legacy adventure-resume failures:
  1729 passed / 2 failed. Root cause was an unmodifiable diagnostic snapshot
  escaping through legacy list APIs whose established caller appends entries.
- Minimal fix: legacy APIs now return mutable copies while diagnostics stay
  immutable. B1-B6 plus post-removal smoke tests: 19 passed / 0 failed.
- Final fail-fast full `flutter test`: **1732 passed / 0 failed**.
- `git diff --check`: PASS before implementation commit and after docs update.
- A prior full-test attempt hit `/tmp` quota; only confirmed regenerable,
  unreferenced Flutter temp directories were removed. No repository/user data
  was deleted, and the final run completed normally.

## 13. Schema and Data Safety

- Schema start/end: 43 / 43.
- No forward migration was required or added.
- No historical migration was rewritten, no historical column was removed,
  and no user data was cleared.

## 14. Files Changed / Deleted

- Hardening: database open/restore FK lifecycle, WorldEntry codec/repository,
  TranslationMode and PromptPreset compatibility codecs.
- Lifecycle: resource owned-state purger/trash service and R03 regression test.
- Cleanup: app config, adventure/chat/messaging providers and controllers,
  scheduler/LLM utilities, app section and related dead surfaces.
- Added tests: R06 migration hardening, corrupt-row isolation, serialization
  compatibility, and cleanup reachability guard.
- Deleted production files: `resource_context_compressor.dart`,
  `scene_approval_controller.dart`, `multi_char_manager.dart`, and
  `status_toast.dart`.
- Deleted superseded tests/helper: resource compressor test and duplicate
  viewport helper.

## 15. Git

- Implementation: `a7f4e7a` - `fix(remediation): implement R06 hardening and cleanup`.
- Documentation/status: commit containing this report.
- `git fetch origin` before commit showed no remote advance or overlap.
- Final push and HEAD/origin convergence are recorded by repository state.

## 16. Known / Deferred Issues

- Anthropic messages transport remains production-unreachable but is retained as
  a compatibility/test seam.
- `switchBranch` and `switchToMainBranch` remain latent public facade paths and
  are intentionally KEEP/DEFER.
- `toResourceTree` remains because domain tests and assembly contracts use it.
- Blocking findings: none. Independent acceptance has not been performed.

## 17. Final Status

**R06 IMPLEMENTED - awaiting independent acceptance**

Milestone C remains **NOT COMPLETE** until R06 independent acceptance. Final
post-remediation repository audit has not been started.
