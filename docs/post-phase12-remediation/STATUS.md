# LT Post-Phase-12 Remediation - Program Status

本文件是当前 8-Phase Program 的唯一状态源。初始 13-Phase 状态仅作为归档历史，不再决定执行。

## 状态规则

1. Phase 只依赖其 `Depends On` 中列出的 technical dependency；编号相邻不构成依赖。
2. 执行 Agent 只能标记 `IMPLEMENTED`，只有独立 Acceptance Agent 可标记 `ACCEPTED`。
3. `BLOCKED` 表示明确依赖尚未 `ACCEPTED`；`PLANNED` 表示技术上可开始。
4. 失败记录不得删除；必须保留失败原因、最后安全 HEAD 和恢复建议。
5. P0/P1/P2 是架构簇优先级，不等同于单个 finding 的 severity。

## 当前总体状态

| 字段 | 当前值 |
| --- | --- |
| Program | Post-Phase-12 Remediation, reprioritized 8-phase plan |
| Original Audit / Initial Planning HEAD | `c94315e26cd4db3051f9f8af8ad5a3bdca0f7b8c` |
| R01 Start HEAD | `b412b8b780395e7339fd29bcf612d8c0438bfc1d` |
| R01 Implementation Commit | `67ec88cc431cc8150f844b0397e72e1c0f201b9c` |
| Replanning Start HEAD | `4ca946fbcbab52100ed39463b249d2650c636d7c` |
| Replanning Docs Commit | Recorded by the docs-only Git commit containing this file |
| Schema Version | 43 |
| Current Milestone | A - Core Integrity |
| Current Phase | R03 implemented; awaiting independent acceptance |
| Last Accepted Phase | R01 |
| Next Action | R03 independent acceptance |
| Last Updated | 2026-09-19 |

## Phase 状态

| Priority | Milestone | Phase | Name | Status | Depends On |
| --- | --- | --- | --- | --- | --- |
| P0 | A | R01 | Streaming Generation Lifecycle & Recovery | `ACCEPTED` | - |
| P0 | A | R02 | Atomic Commit & Content Write Integrity | `IMPLEMENTED` | - |
| P0 | A | R03 | Resource Identity, Delete, Trash & Revision Lifecycle | `IMPLEMENTED` | - |
| P1 | B | R04 | LLM Transport & Streaming Protocol Reliability | `PLANNED` | R01 `ACCEPTED` |
| P1 | B | R05 | Async State & Production Wiring Consistency | `PLANNED` | R01 `ACCEPTED` |
| P1 | B | R06 | Context Budgeting & Narrative Continuity | `PLANNED` | - |
| P2 | C | R07 | Migration, Serialization & Defensive Hardening | `BLOCKED` | Milestones A and B complete |
| P2 | C | R08 | Cleanup & Code Slimming | `BLOCKED` | R01-R07 `ACCEPTED` |

`PLANNED` 不代表推荐抢先执行。单 Agent 推荐先完成 R01 独立验收，再按里程碑顺序实施。

## Milestone Gates

| Milestone | Exit Gate |
| --- | --- |
| A Core Integrity | BLOCKER=0；数据丢失、commit、identity、delete/restore、持久生命周期相关 MAJOR 关闭；R01-R03 全部 `ACCEPTED` |
| B Runtime Reliability | transport bounded；typed streaming failures；production/test wiring 对齐；stale response 防护；context bounded 且 continuity 有回归测试；R04-R06 全部 `ACCEPTED` |
| C Hardening & Slimming | R07-R08 `ACCEPTED`；随后执行 Final Post-Remediation Full Repository Audit |

下一轮大型功能开发至少必须等待 Milestone A；角色状态、世界状态、权重管理等下一代架构应等待
Milestone B。P2 只在 correctness 已稳定后执行。

## R01 实施与独立验收历史

Status: `ACCEPTED`

```text
Executor: Remediation R01 Implementation Agent
Started / Completed: 2026-09-19
Start HEAD: b412b8b780395e7339fd29bcf612d8c0438bfc1d
End HEAD / Implementation Commit: 67ec88cc431cc8150f844b0397e72e1c0f201b9c
Implementation: lifecycle, retry convergence, startup recovery, shared provider ownership,
                stop-request cleanup, production wiring tests
dart format: PASS (497 files, 0 changed)
flutter analyze: PASS (No issues found)
targeted tests: PASS (35 passed, 0 failed)
full flutter test: PASS (1610 passed, 0 failed)
mutation MUT-01...MUT-05: PASS
git diff --check: PASS
Acceptance: ACCEPTED at baseline 3485fef1255f24089210fb27f8833c974df8c12b
Reviewer: R01 Independent Acceptance Agent
Acceptance Date: 2026-09-19
Acceptance Report: remediation-phase-01-independent-acceptance.md
Acceptance targeted tests: PASS (35 passed, 0 failed)
Acceptance full flutter test: PASS (1610 passed, 0 failed)
Acceptance mutations: MUT-A1...MUT-A5 detected; MUT-A6 survived as non-blocking TEST-GAP
Known non-blocking finding: production wiring test does not detect an independent
  Section runtime service; current production code was statically verified to reuse
  the Studio controller/session repository. Carry this guard into R05.
Schema: 43
Startup recovery: autoResume=false; no billable LLM request replay
```

## R02 实施历史

Status: `IMPLEMENTED`（等待独立验收）

```text
Phase / Priority / Milestone: R02 / P0 / A
Executor: Remediation R02 Implementation Agent
Started / Completed: 2026-09-19
Start HEAD: e98cc94cc38b37855ed2b485c1b1eb69178b040c
Implementation Commit(s):
  R02-A dialogue commit boundary: 5a67a2ee472588456aa48a25a55c5662f96f17bc
  R02-B part content source CAS:  76d743f66009fbf226e44200a771473812caa033
  R02-C autosave durability:      45eb245e13786488e843e75ec53e83ec3b524ce0
Schema Version: 43 (unchanged; compression job rows already carried source_token,
                   generation uses resource_parts.updated_at captured at lease)
dart format: PASS (499 files, 0 changed)
flutter analyze: PASS (No issues found)
R02 targeted tests: PASS
  chat_engine_cancellation_commit_boundary_test.dart: 7 passed (A1-A7)
  r02_part_content_source_cas_test.dart: 11 passed (B1-B10 + coordinator)
  resource_autosave_service_test.dart: 42 passed (31 existing + C1-C12)
  phase9_concurrency / phase9_revision_boundary / generation_task_repository /
  streaming_lifecycle: included in the same targeted run, 90 passed / 0 failed
full flutter test: PASS (1638 passed, 0 failed; R01 baseline was 1610)
Mutation verification:
  MUT-R02-A (restore post-commit cancellation throw + fake rollback):
    A2, A3 failed -> guard proven, mutation reverted
  MUT-R02-B (disable source CAS check and guarded where):
    B1, B9/B10, coordinator test failed -> guard proven, mutation reverted
  MUT-R02-C (disable failure requeue after flush snapshot):
    C1, C5, C6 failed -> guard proven, mutation reverted
git diff --check: PASS
Known / Deferred Issues:
  - The pre-commit final gate in ChatEngine sits immediately before the commit
    after a synchronous stretch, so it is defence in depth behind the guards
    after each await; kept intentionally.
  - Mutation note: removing ONLY the final pre-commit gate is not detectable
    because every await between streaming and commit already has its own
    guard; MUT-R02-A therefore restored the original post-commit throw +
    fake-rollback pair, which A2/A3 detect.
Handoff: Independent R02 Acceptance
```

## R03 实施历史

Status: `IMPLEMENTED`（等待独立验收）

```text
Phase / Priority / Milestone: R03 / P0 / A
Executor: Remediation R03 Implementation Agent
Started / Completed: 2026-09-19
Start HEAD: 9566d3137433593ec7de93068eb4271f3fafbdb4 (R02 end)
Implementation Commit(s):
  R03-C revision lifecycle gate:  35c201fd6287814077041e44aa997f6410efd724
  R03-B owned-state cascade:      e128b0e4a7577b83216ca5d9ab38ebc2f8dcbe9c
  R03 belongs-to guard restore:   67c9a9b82206e611b44bd1c0ade7d5113bb1a36b
Schema Version: 43 (unchanged; every owned auxiliary table carries resource_id,
                   cascades use existing ON DELETE CASCADE foreign keys)
dart format: PASS (500 files, 0 changed)
flutter analyze: PASS (No issues found)
R03 targeted tests: PASS (14 passed / 0 failed, r03_lifecycle_integrity_test.dart)
  TG9: revision restore trashed/gone/live matrix; explicit trash restore first;
       CP-2 child belongs-to (section owner, part owner, part parent owner);
       section restore refused while parent resource is in the bin
  TG10: full owned-state cascade with tombstone; node-scoped purge;
        purge failure full rollback; retention purge idempotent + cascade;
        migration idempotency; purge-then-re-migrate no resurrection
full flutter test: PASS (1652 passed, 0 failed; R02 end baseline was 1638)
Mutation verification:
  MUT-R03-1 (remove revision-restore lifecycle gate):
    TG9 trashed-refusal + restore-order tests failed -> reverted
  MUT-R03-2 (remove section-restore parent-live guard):
    TG9 child-restore test failed -> reverted
  MUT-R03-3 (omit resource_autosaves from owned cascade):
    TG10 cascade + retention tests failed -> reverted
  MUT-R03-4 (split owned purge out of the purge transaction):
    TG10 rollback test failed -> reverted
  MUT-R03-5 (remove belongs-to ownership checks):
    TG9 CP-2 tests failed -> reverted
  id-equality mutation: not applicable - the audit found no integer id
    equality inference anywhere (identity is mapping-table based, deterministic
    res_legacy_ ids, fingerprint idempotency); covered by TG10 identity tests
git diff --check: PASS
Ownership / cascade classification:
  owned & cascaded in the purge transaction: resources/sections/parts (tree),
    resource_trash entry, legacy row (when linked), resource_revisions
    (+revision_nodes via FK), resource_autosaves, resource_compression_jobs
    (+candidates via FK), resource_generation_sessions, resource_blueprints,
    resource_generation_tasks (+attempts via FK), resource_assembly_readiness,
    resource_assembly_entries
  NOT owned / explicit tombstone: resource_creation_sessions (UNIQUE
    idempotency_key must keep blocking reuse), world_entries + embeddings and
    adventure_runtime_entities (adventure aggregate, free-text links)
Known / Deferred Issues:
  - A migration record for a purged resource stays `succeeded` (tombstone);
    a re-created legacy row with the same id/hash is skipped by the migration
    and surfaces as `treeMissing` in ResourceReadFacade instead of silently
    re-creating the tree. Deliberate fail-safe, carried as-is.
  - During mutation verification a working-tree restore temporarily dropped
    the belongs-to guards; the full-suite failure caught it immediately and
    commit 67c9a9b restored them - recorded as process evidence, no residual.
Handoff: Independent R03 Acceptance
```

## 阶段记录模板

```text
Phase / Priority / Milestone:
Status:
Executor:
Start HEAD:
Implementation Commit:
Targeted tests:
Full flutter test:
flutter analyze:
Mutation / negative tests:
git diff --check:
Independent Acceptance:
Known / Deferred Issues:
Handoff:
```
