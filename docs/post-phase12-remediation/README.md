# LT Post-Phase-12 Remediation Program

本目录是 LT 在 Phase 0–12 完成后的**独立缺陷修复计划体系**。它不引入任何新功能，只负责把
[`LT Post-Phase-12 Full Repository Audit`](./remediation-master-plan.md#2-audit-baseline) 发现的
BLOCKER / MAJOR / MINOR / TEST-GAP / CLEANUP 按**根因与架构边界**重新组织为可独立实施的
Remediation Phase。

## 目录结构

```text
docs/post-phase12-remediation/
├── README.md                                  ← 本文件
├── remediation-master-plan.md                 ← 总计划书、Root Cause Map、Phase Index、DAG
├── STATUS.md                                  ← Program 与各 Phase 的统一状态
├── remediation-phase-01-streaming-lifecycle-and-recovery.md
├── remediation-phase-02-dialogue-atomic-commit-cancellation.md
├── remediation-phase-03-part-content-write-version-contract.md
├── remediation-phase-04-llm-transport-timeout-retry.md
├── remediation-phase-05-resource-deletion-identity-and-retention.md
├── remediation-phase-06-soft-delete-revision-restore-semantics.md
├── remediation-phase-07-autosave-durability-failure-isolation.md
├── remediation-phase-08-streaming-protocol-error-propagation.md
├── remediation-phase-09-async-controller-stale-response-guards.md
├── remediation-phase-10-context-budgeting-and-continuity.md
├── remediation-phase-11-production-wiring-convergence.md
├── remediation-phase-12-migration-serialization-hardening.md
└── remediation-phase-13-cleanup-and-code-slimming.md
```

## 使用方式（对未来的 Coding Agent）

每一份 `remediation-phase-XX-*.md` 都是**自包含**的：它包含该 Phase 涉及的真实生产调用链、精确
BUG 证据、根因、必须修改的类/方法、不得破坏的 invariant、测试计划、验收标准与文件边界。

执行一个 Phase 时，只需：

1. 阅读 `remediation-master-plan.md` 的 §2 Audit Baseline / §5 Root Cause Map / §6 Phase Index；
2. 阅读对应 Phase 文档全文；
3. 阅读该 Phase 文档 §3 与 §7 中列出的真实源码；
4. 按 §7 Implementation Plan 实施，按 §14 测试计划补测；
5. 用 §17 的命令验证；
6. 更新 `STATUS.md`。

不需要重新进行全仓考古，也不需要阅读原始审计报告全文。

## 强制约束

- 本 Program 只做修复与收敛，**不新增功能**（见总计划 §4 Non-Goals）。
- 每个 Phase 必须独立闭环（`IMPLEMENTED → INDEPENDENT AUDIT → ACCEPTED / FAILED`）。
- 修复顺序必须遵守总计划 §8 与 §7 的 Dependency Graph；CLEANUP 阶段必须在全部 correctness
  阶段之后（见 Phase 13）。
- 任何 Phase 都不得降低既有测试标准，不得删除失败测试，不得用 `catch (_) {}`、无限重试、
  无意义 fallback 掩盖错误（沿用 `AGENTS.md`）。
- 生产代码事实以仓库当前代码为准。若 Phase 文档中的 `file:line` 与当前代码不一致，**以 symbol
  为准**，并优先信任代码。

## 基线

```text
Audit HEAD / Planning HEAD: c94315e26cd4db3051f9f8af8ad5a3bdca0f7b8c
Branch: main
Schema: v43
Flutter: 3.44.8 / Dart 3.12.2
Audit Verdict: FAILED (BLOCKER 1, MAJOR 15, MINOR 20, TEST-GAP 15, CLEANUP 14)
```
