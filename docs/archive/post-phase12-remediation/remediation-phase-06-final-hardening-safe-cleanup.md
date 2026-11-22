# R06 - Final Hardening, Compatibility & Safe Cleanup

> Priority: P2 | Milestone: C - Final Hardening & Slimming | Status: PLANNED / READY TO IMPLEMENT | Dependencies: R01-R05 all `ACCEPTED`
> Findings: N1, N2, N3, N16, N17 + C1-C13 + R03-A-N1 carry-forward
> 本文档是 2026-09-19 的 7-Phase → 6-Phase 压缩（replanning baseline `9344ce60e3ad52ddb8425aa52eadf63910e1c437`）产出的完整自包含 spec。former R06（Migration, Serialization & Defensive Hardening）与 former R07（Cleanup & Code Slimming）合并为本 Phase。历史文档见 [`archive/pre-6-phase-plan/README.md`](./archive/pre-6-phase-plan/README.md)，仅供追溯，不得用于执行。

## Purpose

R01-R05 全部 `ACCEPTED`（Milestone A + Milestone B complete）后，correctness 基线
已建立。本 Phase 是 remediation program 的最后一个实施阶段，做两件事并严格排序：

1. **Hardening first（R06-A/B/C）**：强化 migration 行为、corrupt row isolation
   与 enum/JSON 序列化兼容，使历史数据在任何升级/损坏路径下 fail closed 且可诊断。
2. **Safe cleanup（R06-D/E/F/G）**：在 Hardening Internal Gate 与 Protected
   Compatibility List 完成后，基于 R06-A/B/C hardening 之后的 authoritative
   code，删除被证明不可达的 production surface、收敛重复实现、清理 mechanical
   debt。

目标不是最大删除量，而是每项 cleanup 都有 production reachability 证据、不破坏
migration/serialization/protocol/recovery 兼容、可独立回滚。

## Planning Baseline and Schema

- Planning baseline schema: **43** at R05 ACCEPTED HEAD `9344ce6`。
- **Implementation Agent must re-read actual `DatabaseService.schemaVersion` at
  R06 start.** 43 不是永久假设；R01-R05 期间 schema 曾保持 43，但本 Phase 开始
  时以代码为准。
- R05 ACCEPTED evidence（只作依赖确认，不在本 Phase 重新审计）：BLOCKER=0、
  MAJOR=0、targeted 46/0、R01/R02/R04 critical regression 86/0、full flutter
  test 1724/0、Schema 43 unchanged。

## Technical Dependency

R01-R05 全部 `ACCEPTED`。该条件在 replanning baseline `9344ce6` 时已满足，因此
本 Phase 状态为 `PLANNED / READY TO IMPLEMENT`，不写 `BLOCKED`。

## Findings Backlog

### Hardening findings（former R06）

- **N1**：部分 migration 在 transaction 内切换 `PRAGMA foreign_keys`（可能无效），
  FK ownership 需要明确归属。
- **N2**：library row mapping 的宽 catch 可把单坏行放大为整列表空。
- **N3**：坐标归一化等 data migration 步骤可能非幂等，重复升级改变已迁数据。
- **N16**：`WorldEntry` 与若干 enum 使用序数/不一致 unknown policy，JSON 损坏可
  能导致整批失败。
- **N17**：unknown enum / bad JSON 的处理 policy 不一致。

### Cleanup findings（former R07）

C1-C13（C13 的 `_requestedStops` 子项已由 R01 关闭；**C14 已由 R05 correctness
wiring 处理 — CLOSED BY R05，不在本 backlog**；**C7 已由 R05 删除 import 死参数
— CLOSED BY R05，不重复实施**）：

- C1 scene-approval orphan cluster
- C2 resource context compressor reachability
- C3 dead AppSection / navigation
- C4 duplicate PresetManager
- C5 dead multi-character accessors
- C6 unreachable scheduler branch
- C8 duplicate viewport helper
- C9 stale comments
- C10 LLM dead branches
- C11 miscellaneous dead methods
- C12 disabled toast
- C13 remaining dead assignment / self-copy（非 `_requestedStops` 部分）
- C14：**CLOSED BY R05**（fallback gate correctness wiring 已实施）。
- C7：**CLOSED BY R05**（dead `repository`/`now` import params 已删除）。

### Lifecycle cleanup carry-forward

- **R03-A-N1**（MINOR / fail-closed litter）：node-scoped Section purge 后，其
  descendant Part generation tasks 与 autosave drafts 可能残留。这不是普通
  dead-code candidate，属于 **targeted lifecycle cleanup carry-forward**：
  - 修复方向（若仍存在）：将 node-scoped cascade 扩展到 descendant part ids，
    使 purge 覆盖这些残留。
  - 未来 Implementation Agent 必须先复核该残留是否仍存在；如果已被其它阶段关闭，
    只记录 `CLOSED EARLIER`，不得重复实施。
- **R05 acceptance INFO**：`app_config.dart` dead setup-context section（唯一
  调用点传 `includeSetupContext=false`）。作为 new R06 cleanup candidate 进入
  本 Phase，具体映射到 R06-D/F/G 中的哪一类由 R06 implementation 时的
  reachability audit 决定。本次 replan 不删除它。
- R05 另一 INFO（switchBranch/switchToMainBranch 无 production UI caller、
  summary reload latent 但正确）：列为 reachability 审计候选，默认倾向 KEEP
  （facade 路径已验证正确，属 latent 而非 dead）。

## Internal Order and Parallelism Rules

本 Phase 内部必须严格按以下顺序执行：

```text
R06-A Migration
  ↓
R06-B Corrupt Row Isolation
  ↓
R06-C Stable Serialization
  ↓
Hardening Internal Gate
  ↓
Protected Compatibility List
  ↓
R06-D Reachability Inventory
  ↓
R06-E Duplicate Convergence
  ↓
R06-F Dead Production Surfaces
  ↓
R06-G Mechanical Debt
  ↓
Targeted Verification
  ↓
Mutation Verification
  ↓
Full Regression
  ↓
R06 IMPLEMENTED
  ↓
Independent Acceptance
  ↓
R06 ACCEPTED
  ↓
Final Post-Remediation Full Repository Audit
```

**R06-A/B/C（hardening）与 R06-D/E/F/G（cleanup）不得无序并行。** 原因：cleanup
可能误删 legacy ordinal reader、migration compatibility helper、JSON key、
historical decoder、provider/recovery surface 等 hardening 正在保护或即将验证的
兼容能力。cleanup 必须基于 Hardening Internal Gate 之后的 authoritative code
执行。

## Workstreams

### R06-A - Migration Behavior（继承 former R06-A）

覆盖 N1、N3。

- `DatabaseService` onConfigure/onUpgrade 的 `PRAGMA foreign_keys` ownership：
  FK 策略在 transaction 外正确设置，升级后恢复/验证；不得依赖 transaction 内的
  PRAGMA 切换。
- Historical migrations：顺序、失败 rollback、repeat upgrade、forward-only
  recovery 全部用旧版本 fixture 实测。
- 归一化等 data migration 步骤增加输入域/迁移 marker，第二次执行 no-op。
- Contract：**migration repeat must be deterministic / no-op where applicable**。
- 不得修改已发布 migration 的历史语义；如需修未来 upgrade hook，只修改尚未发布
  的新 migration 或追加前向 migration。

### R06-B - Corrupt Row Isolation（继承 former R06-B）

覆盖 N2。

- Repository 按 row decode；单坏 row 不得导致整个 collection 变成空。
- Typed diagnostic 包含 table / id / error category，不记录敏感 payload。
- 返回其余合法行；调用方可区分"空结果"与"存在损坏"。
- 关键 identity 字段损坏：**fail closed**，不得猜默认值；可选字段按统一 policy
  fallback。

### R06-C - Stable Serialization Compatibility（继承 former R06-C）

覆盖 N16、N17。

- `WorldEntry` 与 persisted enum：先读 legacy ordinal，再写稳定 string code；
  枚举声明重排不改变语义。
- Unknown enum / bad JSON / legacy JSON：统一字段级 unknown-value policy。
- 为审计列举的所有 enum 与 `WorldEntry` keys/position 建 compatibility fixtures。
- 规则：**新写使用 stable code；旧读保持 legacy-compatible**。
- **不得因为 runtime 无调用就删除 compatibility reader**（此约束同时约束本
  Phase 后半段的 cleanup）。

### Hardening Internal Gate（新增结构，cleanup 前置门槛）

R06-D 开始前必须全部满足。这是 R06 内部 gate，不是独立 phase acceptance：

- migration fixture tests PASS
- FK behavior PASS
- repeated migration PASS
- corrupt row isolation PASS
- serialization compatibility PASS
- hardening mutations detected（MUT-R06-1..4）
- Protected Compatibility List 完成（见下节）

Gate 未通过时禁止任何 cleanup 工作。

### Protected Compatibility List（cleanup 前 Implementation Agent 必须产出）

至少检查以下 symbol 类别，默认 `KEEP`，除非已有明确 replacement 且兼容能力已被
证明完整迁移：

- current schema migrations
- historical migration readers
- migration markers
- enum legacy ordinal readers
- stable enum string codecs
- legacy JSON keys
- compatibility JSON decoders
- `DatabaseService` migration helpers
- R01 recovery/session providers
- R02 CAS / durability code
- R03 lifecycle compatibility code
- R04 transport contracts
- R05 runtime/context authoritative providers
- dynamic routes
- platform entrypoints
- serialization surfaces
- persisted identifiers

该清单是 R06-D/E/F/G 每项 DELETE 决定的强制对照面；删除清单内 symbol 的提案
必须先转为 KEEP 或提供完整迁移证据。

### R06-D - Reachability Inventory（继承 former R07-A）

覆盖 C1-C13 + R03-A-N1（如仍未关闭）。

- 以 **R01-R05 ACCEPTED HEAD** 和 **R06-A/B/C hardening 后 HEAD** 为依据重建
  inventory；旧文档行号/结论仅作线索。
- 每个 candidate 给出 `DELETE` / `KEEP` / `DEFER` 与证据：direct references、
  string references、Git history（`git log -S`）、dynamic route、provider
  construction、serialization、migration、platform entry、startup side effect。
- **`rg` zero refs 只能是证据之一，不能单独决定 DELETE**；production
  startup/reachability test 必须覆盖。
- 不确定项标记 `DEFERRED WITH REASON`，保留代码，不为完成率强删。
- R03-A-N1 按 lifecycle carry-forward 处理（先复核存在性，不是 reachability
  审计的普通条目）。

### R06-E - Duplicate Convergence（继承 former R07-B）

主要 C4、C8 以及执行时发现的真实 duplicate。

- 流程：选定 authoritative implementation → 迁移全部调用者 → tests → 删除
  duplicate。
- viewport helper 必须恢复 `tester.view`、统一 `devicePixelRatio`，避免测试间
  污染（复用现有统一 helper）。
- **禁止为了减少 LOC 同时重写业务逻辑。**

### R06-F - Dead Production Surfaces（继承 former R07-C）

候选（最终清单由 R06-D 在当时 HEAD 决定）：

- C1 scene approval orphan
- C2 resource context compressor
- C3 dead AppSection / navigation
- C5 multi-character accessors
- C6 unreachable scheduler branch
- C10 LLM dead branches
- C11 miscellaneous dead methods
- C12 disabled toast
- `app_config.dart` dead setup-context section（R05 acceptance INFO，若
  reachability audit 确认）
- 其它当时真正满足 reachability deletion contract 的 surface

规则：涉及 migration、serialization、protocol、provider side effect、platform、
dynamic route、recovery 的候选，不确定即 **DEFER**。协议预留/跨平台分支没有产品
决策证据则 DEFER。migration/JSON key/enum persisted value 可停用但不得破坏兼容
读取。删除 provider/controller 前检查初始化/stream disposal side effect；若删除
暴露竞态，停止并记录新 finding，不在本 Phase 修 correctness。

### R06-G - Mechanical Debt（继承 former R07-D）

覆盖 C9（stale comments）、C13 剩余部分（dead assignment / self-copy）。

- 只做 mechanical cleanup。
- **禁止顺手**：architecture refactor、UI redesign、domain redesign、new
  feature、performance rewrite。
- 增加最小 architecture guard，防止已删 legacy symbol 重新进入 production
  composition。

## Database Impact and Concurrency

- 原则上不升 schema；不得删除表列，不写/清用户数据。
- Migration 使用单连接、事务化步骤和 upgrade 后 FK check；失败保留原 DB 可再次
  升级。
- Cleanup 禁止 schema/migration 删除；cleanup 不改变 concurrency contract。

## Test Plan（合并 former R06 + former R07 全部测试需求）

### Hardening tests

- v42 / older DB fixture → current schema（forward-only recovery）
- foreign key parent/child 行为
- failed migration rollback
- repeated migration（deterministic / no-op）
- normalization idempotency
- one corrupt row + multiple valid rows（collection 不为空）
- malformed JSON
- unknown enum
- out-of-range ordinal
- enum reorder compatibility
- legacy string/ordinal fixtures

### Cleanup tests

- startup reachability
- production provider reachability
- routes
- string/dynamic refs
- platform entrypoints
- serialization presence（compatibility reader 存在性）
- migration reader presence
- architecture guard（已删 symbol 重新出现必须 FAIL）
- full regression

每个删除簇先跑 targeted/startup/production reachability，再跑 full regression；
全部实施须 format/analyze/diff-check。

## Mutation Plan（最多 6 个高价值 mutation）

| Mutation | 内容 | Expected |
| --- | --- | --- |
| MUT-R06-1 | 恢复错误 FK/PRAGMA ownership | migration FK test FAIL |
| MUT-R06-2 | 去掉 migration idempotency guard | repeat migration test FAIL |
| MUT-R06-3 | 恢复 table-wide catch → [] | bad-row isolation FAIL |
| MUT-R06-4 | 退回 ordinal-only enum serialization | legacy/stable compatibility FAIL |
| MUT-R06-5 | 删除 Protected Compatibility List 中必要 reader | compatibility/startup test FAIL |
| MUT-R06-6 | 删除唯一 production/recovery provider | production reachability test FAIL |

所有 mutation 验证后必须 revert，不留 residue。

## Independent Acceptance（一次，分两部分验）

只有一次 R06 Independent Acceptance，但必须分别验证：

### Part A - Hardening

- migration 行为（FK、rollback、repeat、idempotency）
- corrupt row isolation
- serialization stability 与 legacy compatibility
- MUT-R06-1..4 detected

### Part B - Cleanup

- C1-C13 coverage（含 C7/C14 的 CLOSED BY R05 记录核对）
- R03-A-N1 carry-forward 处置（CLOSED EARLIER 或已修复）
- DELETE/KEEP/DEFER evidence 完整
- Protected Compatibility List 已产出且未被违反
- production reachability 验证
- no compatibility break / no recovery break / no protocol break
- MUT-R06-5/6 detected

### 最终门槛

- full flutter test PASS
- BLOCKER = 0
- MAJOR = 0

满足后才可标记 `R06 ACCEPTED`。

## Acceptance Criteria（汇总）

- 升级 FK 行为真实可验证；migration 幂等；单坏行不清空集合且有 typed 诊断；
  stable code 与 legacy 兼容；schema 与用户数据不被破坏。
- C1-C13（及 R03-A-N1 carry-forward，如适用）每项有 DELETE/KEEP/DEFER 证据；无
  migration/protocol/recovery 破坏；所有删除均有 production reachability 验证；
  各簇可独立 revert。
- Hardening Internal Gate 与 Protected Compatibility List 记录保存于实现报告。
- 全部旧 migration fixtures 与 full regression 通过。
- 完成后触发 **Final Post-Remediation Full Repository Audit**（前置条件：
  R01-R06 全部 `ACCEPTED`）。

## Files Expected To Change

Hardening：`database_service.dart`、migration helpers/tests、library/tree row
mapper/repository、WorldEntry 与 enum codecs、serialization fixtures。
Cleanup：仅 reachability 审计确认的 candidate production/test/helper/docs。
两类均含 `STATUS.md`。实际清单必须由 R06-D 在当时 HEAD 决定。不得修改
P0/P1 correctness contract。

## Forbidden Scope, Rollback Safety, Handoff

- 禁止 catch-all 返回空、猜 identity、清库、重排历史 migration、篡改已部署
  migration 语义。
- 禁止删除 migration/schema、R01 recovery providers、Protected Compatibility
  List 内 symbol、仍被动态/平台/协议引用的代码。
- 禁止因测试只覆盖 dead code 就直接删测试而无 production proof。
- 禁止 R06-A/B/C 与 R06-D/E/F/G 无序并行。
- 禁止在 cleanup 中重写业务逻辑、重构架构、重设计 UI/domain、新增功能或性能
  重写。
- 代码可 revert；已执行 DB 只能用前向补偿。每簇独立 commit/revert。
- Implementation Agent 完成后仅标记 `IMPLEMENTED`；独立 Acceptance Agent 用历史
  fixture、reachability dossier 与 mutation 证据验收。
- R06 ACCEPTED 后，program 进入 **Final Post-Remediation Full Repository
  Audit**（覆盖 R01 lifecycle/recovery、R02 atomic writes/CAS/autosave、R03
  resource lifecycle、R04 transport/retry/stream、R05
  runtime/context/summary、R06 migration/serialization/cleanup）。
