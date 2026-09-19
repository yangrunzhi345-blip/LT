# LT Post-Phase-12 Remediation Program

本目录是 LT 在 Phase 0-12 后的当前修复执行计划。2026-09-19 的重规划将初始 13 个平铺阶段压缩为
8 个按风险优先级和架构边界组织的阶段。历史 R01 文档保留不变；被替代的旧 R02-R13 位于
[`archive/initial-13-phase-plan/`](./archive/initial-13-phase-plan/README.md)，不得再用于执行。

## 阅读顺序

1. [`remediation-master-plan.md`](./remediation-master-plan.md)：基线、优先级、里程碑、完整 finding
   覆盖矩阵与依赖图。
2. [`STATUS.md`](./STATUS.md)：唯一有效的执行状态与历史记录。
3. 对应 Phase 文档：可独立实施的 contract、workstream、测试与验收规格。
4. 当前代码：文档中的行号漂移时，以 symbol 和真实调用链为准。

## 当前阶段

| Priority | Phase | Document |
| --- | --- | --- |
| P0 | R01 Streaming Generation Lifecycle & Recovery | [R01](./remediation-phase-01-streaming-lifecycle-and-recovery.md) |
| P0 | R02 Atomic Commit & Content Write Integrity | [R02](./remediation-phase-02-atomic-write-integrity.md) |
| P0 | R03 Resource Identity, Delete, Trash & Revision Lifecycle | [R03](./remediation-phase-03-resource-lifecycle-integrity.md) |
| P1 | R04 LLM Transport & Streaming Protocol Reliability | [R04](./remediation-phase-04-llm-streaming-reliability.md) |
| P1 | R05 Async State & Production Wiring Consistency | [R05](./remediation-phase-05-async-wiring-consistency.md) |
| P1 | R06 Context Budgeting & Narrative Continuity | [R06](./remediation-phase-06-context-budgeting-continuity.md) |
| P2 | R07 Migration, Serialization & Defensive Hardening | [R07](./remediation-phase-07-migration-serialization-hardening.md) |
| P2 | R08 Cleanup & Code Slimming | [R08](./remediation-phase-08-cleanup-code-slimming.md) |

## 执行规则

- Phase 是否可开始只由其明确 technical dependencies 是否 `ACCEPTED` 决定，不由编号决定。
- 单 Agent 推荐按 R01 验收、R02、R03、R04、R05、R06、R07、R08 顺序执行，以降低冲突。
- 每个 Phase 必须经历 `IMPLEMENTED -> Independent Acceptance -> ACCEPTED / FAILED`。
- R01 当前仅为 `IMPLEMENTED / Pending Independent Acceptance`，不得视为已验收。
- P0 在下一轮大型功能开发前全部完成；P1 强烈建议在下一代状态/权重架构前全部完成；P2 在
  correctness 收敛后执行。
- 本 Program 不新增功能，不降低测试标准，不用 fallback、空 catch 或删除测试掩盖错误。

## 基线

```text
Original Audit / Initial Planning HEAD: c94315e26cd4db3051f9f8af8ad5a3bdca0f7b8c
R01 Start HEAD:                       b412b8b780395e7339fd29bcf612d8c0438bfc1d
R01 Implementation Commit:           67ec88cc431cc8150f844b0397e72e1c0f201b9c
Replanning Start HEAD:                4ca946fbcbab52100ed39463b249d2650c636d7c
Schema:                               43
R01 full test evidence:               1610 passed / 0 failed
```
