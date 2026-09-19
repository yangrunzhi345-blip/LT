# LT Post-Phase-12 Remediation Program

本目录是 LT 在 Phase 0-12 后的当前修复执行计划。Program 经历两次压缩：

1. 2026-09-19（第一次重规划）：初始 13 个平铺阶段压缩为 8 个按风险优先级和架构
   边界组织的阶段。初始 13-Phase 文档位于
   [`archive/initial-13-phase-plan/`](./archive/initial-13-phase-plan/README.md)。
2. 2026-09-19（第二次重规划）：8-Phase 压缩为 **7-Phase**——former
   R05 + R06 合并为新 R05（Runtime State, Production Wiring & Context
   Continuity），former R07 → 新 R06，former R08 → 新 R07。被替代的 8-Phase
   future phase 文档位于
   [`archive/pre-7-phase-plan/`](./archive/pre-7-phase-plan/README.md)，
   仅作历史追溯，不得用于执行。
3. 2026-09-19（第三次重规划，当前生效）：7-Phase 压缩为 **6-Phase**——R01-R05
   全部 `ACCEPTED`（Milestone A、B 均 COMPLETE）后，former R06（Migration,
   Serialization & Defensive Hardening）与 former R07（Cleanup & Code
   Slimming）合并为新 R06（Final Hardening, Compatibility & Safe Cleanup），
   内部以 Hardening Internal Gate 与 Protected Compatibility List 强制
   hardening 先于 cleanup。被替代的 7-Phase future phase 文档位于
   [`archive/pre-6-phase-plan/`](./archive/pre-6-phase-plan/README.md)，
   仅作历史追溯，不得用于执行。

R01-R04 已有历史编号、实施记录和验收记录全部保持不变。

## 阅读顺序

1. [`remediation-master-plan.md`](./remediation-master-plan.md)：基线、优先级、
   里程碑、完整 finding 覆盖矩阵与依赖图。
2. [`STATUS.md`](./STATUS.md)：唯一有效的执行状态与历史记录。
3. 对应 Phase 文档：可独立实施的 contract、workstream、测试与验收规格。
4. 当前代码：文档中的行号漂移时，以 symbol 和真实调用链为准。

## 当前程序：6-Phase Program

| Priority | Phase | Document |
| --- | --- | --- |
| P0 | R01 Streaming Generation Lifecycle & Recovery | [R01](./remediation-phase-01-streaming-lifecycle-and-recovery.md) |
| P0 | R02 Atomic Commit & Content Write Integrity | [R02](./remediation-phase-02-atomic-write-integrity.md) |
| P0 | R03 Resource Identity, Delete, Trash & Revision Lifecycle | [R03](./remediation-phase-03-resource-lifecycle-integrity.md) |
| P1 | R04 LLM Transport & Streaming Protocol Reliability | [R04](./remediation-phase-04-llm-streaming-reliability.md) |
| P1 | R05 Runtime State, Production Wiring & Context Continuity | [R05](./remediation-phase-05-runtime-consistency-context-continuity.md) |
| P2 | R06 Final Hardening, Compatibility & Safe Cleanup | [R06](./remediation-phase-06-final-hardening-safe-cleanup.md) |

R01-R05 全部 `ACCEPTED` 后，执行序列为 R01 → R02 → R03 → R04 → R05 → R06 →
Final Post-Remediation Full Repository Audit。

## 执行规则

- Phase 是否可开始只由其明确 technical dependencies 是否 `ACCEPTED` 决定，不由
  编号决定。
- 单 Agent 按唯一 active 序 R01 → R02 → R03 → R04 → R05 → R06 执行，以降低冲突；
  该顺序是 recommendation，不是 hard dependency。
- 每个 Phase 必须经历 `IMPLEMENTED -> Independent Acceptance -> ACCEPTED / FAILED`。
- R01-R05 全部 `ACCEPTED`；Milestone A 与 Milestone B formal gate 均已闭环；
  R06 已解锁（`PLANNED`）。
- R06 内部必须 hardening（R06-A/B/C）先行，通过 Hardening Internal Gate 并产出
  Protected Compatibility List 后才能开始 cleanup（R06-D/E/F/G）。
- P0 在下一轮大型功能开发前全部完成；P1 强烈建议在下一代状态/权重架构前全部
  完成；P2 在 correctness 收敛后执行。
- 本 Program 不新增功能，不降低测试标准，不用 fallback、空 catch 或删除测试掩盖
  错误。

## 基线

```text
Original Audit / Initial Planning HEAD: c94315e26cd4db3051f9f8af8ad5a3bdca0f7b8c
R01 Start HEAD:                       b412b8b780395e7339fd29bcf612d8c0438bfc1d
R01 Implementation Commit:           67ec88cc431cc8150f844b0397e72e1c0f201b9c
First Replanning (13 -> 8) Start:     4ca946fbcbab52100ed39463b249d2650c636d7c
Second Replanning (8 -> 7) Baseline:  e3c43876dcd77184650a1dc5c3049e2a755dcca7
Third Replanning (7 -> 6) Baseline:   9344ce60e3ad52ddb8425aa52eadf63910e1c437
Schema:                               43
R01 full test evidence:               1610 passed / 0 failed
R04 acceptance evidence:              full 1678 passed / 0 failed
R05 acceptance evidence:              full 1724 passed / 0 failed; targeted 46/0;
                                      critical regression 86/0; BLOCKER=0; MAJOR=0
```
