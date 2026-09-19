# R07 - Cleanup & Code Slimming

> Priority: P2 | Milestone: C - Hardening & Slimming | Status: BLOCKED | Dependencies: R01-R06 all `ACCEPTED`
> Findings: C1-C13 (C13 `_requestedStops` sub-item closed by R01; C14 belongs to new R05), plus R03-A-N1 cleanup carry-forward

> 本 Phase 是 8-Phase 程序中 former R08 的直接后继（2026-09-19 的 8→7 压缩）。
> 历史文档见
> [`archive/pre-7-phase-plan/remediation-phase-08-cleanup-code-slimming.md`](./archive/pre-7-phase-plan/remediation-phase-08-cleanup-code-slimming.md)。

## Purpose

correctness first, cleanup last。删除被前面各阶段证明不可达的代码，收敛重复
helper 与 legacy surface。目标不是最大删除量，而是每项都有 production
reachability 证据且可独立回滚。

## Current Production Architecture and Candidates

C1 scene-approval orphan；C2 resource context compressor；C3 dead
AppSection/navigation；C4 duplicate PresetManager；C5 multi-character
accessors；C6 unreachable scheduler branch；C7 import dead parameter（若
new R05 已删除，仅记录 CLOSED BY R05）；C8 viewport helper duplication；C9
stale comment；C10 LLM dead branches；C11 miscellaneous dead methods；C12
disabled toast；C13 dead assignment/self-copy。R01 已清理 `_requestedStops`，
不得重复修改；其余 C13 仍需复核。

R03 Independent Acceptance 记录的 **R03-A-N1（MINOR：node-scoped section purge
残留其 purged Parts 的 generation tasks 与 autosave drafts）** 的未来 cleanup
归属由 former R08 更新为本 Phase（R07）；若在 R05/R06 期间做 earlier targeted
fix，则此处仅记录 CLOSED，不重复实施。

R01 的 recovery/session/service providers、`findInterruptedSessions`、
`recover()`、`recoverInterruptedGeneration` 已是生产路径，绝非 cleanup
candidate。C14 当前是 correctness wiring，new R05 处理后只可删除被证明无消费者
的 fallback surface。

## Root Cause and Required Contract

历史替代实现、实验分支与 test-only helper 未在功能完成后做 reachability closure。
删除 contract：

1. 每项执行 direct/字符串引用、Git history、dynamic route/reflection、
   serialization、DB/migration、provider side-effect 与平台入口审计。
2. `rg` 零引用只是证据之一；production startup/reachability test 必须覆盖。
3. 不确定项标记 DEFERRED WITH REASON，保留代码；不为完成率强删。
4. migration/JSON key/enum persisted value 可停用但不得破坏兼容读取。

## Workstreams and Exact Implementation Plan

### R07-A - Reachability inventory

- 为 C1-C13（及 R03-A-N1 如仍未关闭）建 DELETE/KEEP/DEFER 表，附 symbol、
  direct/string references、history 与运行入口。
- 重新基于 R01-R06 最终代码检查；旧 R13 行号/结论仅作线索。

### R07-B - Duplicate convergence

- C4/C8 选定现行实现，迁移全部调用者后删除重复；viewport helper 必须恢复
  tester.view、DPR，避免污染。
- C7 与 new R05 的 import 改动去重：若 R05 已删除，仅记录 CLOSED BY R05。

### R07-C - Dead production surfaces

- 分簇处理 C1-C3、C5-C6、C10-C12；协议预留/跨平台分支没有产品决策证据则 DEFER。
- migration/serialization 关联符号即使 runtime 无引用也保留兼容层。

### R07-D - Mechanical debt

- C9/C13 只做已证实 stale comment、dead assignment/self-copy；不趁机重构业务
  逻辑。
- 增加最小 architecture guard 防止已删 legacy symbol 重新进入 production
  composition。

## Database Impact and Concurrency

禁止 schema/migration 删除，不写用户数据。移除 provider/controller 前检查
初始化/stream disposal side effect。cleanup 不改变 concurrency contract；若删除
暴露竞态，停止并记录新 finding，不在本阶段修 correctness。

## Test and Mutation Plan

- 每个删除簇先跑 targeted/startup/production reachability，再跑 full regression；
  format/analyze/diff-check。
- `git log -S`、direct/string `rg`、route/provider/platform/serialization/
  migration checklist 随实现报告保存。
- architecture guard 对已删 symbol FAIL；必须保留的 migration/recovery symbols
  有存在性/行为测试。
- 删除 R01 recovery provider、一个 persisted enum compatibility reader 或唯一
  production provider 时测试必须失败。

## Acceptance Criteria

C1-C13（及 R03-A-N1 carry-forward，如适用）每项有 DELETE/KEEP/DEFER 证据；无
migration/protocol/recovery 破坏；所有删除均有 production reachability 验证；
full regression 通过；各簇可独立 revert；完成后触发 **Final Post-Remediation
Full Repository Audit**（前置条件：R01-R07 全部 `ACCEPTED`）。

## Files Expected To Change

仅 reachability 审计确认的 candidate production/test/helper/docs；`STATUS.md`。
预期涉及旧 R13 列举的 scene approval、context compressor、AppSection、preset/
multi-char/scheduler、LLM utilities、toast、controller dead assignments。实际
清单必须由 R07-A 在当时 HEAD 决定。

## Forbidden Scope, Rollback Safety, Handoff

R01-R06 任一未 `ACCEPTED` 不得开始。禁止删除 migration/schema、R01 recovery、仍
被动态/平台/协议引用的代码，禁止因测试只覆盖 dead code 就直接删测试而无
production proof。每簇独立 commit/revert；不确定即 DEFER。独立 Acceptance Agent
核查 reachability dossier、full regression 与最终审计 handoff。
