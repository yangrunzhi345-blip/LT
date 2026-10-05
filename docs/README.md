# 项目文档

`docs/` 保留当前仍有用途的文档，以及有追溯价值的已完成程序历史。

- [Adventure Runtime State](./adventure_runtime_state.md)：运行态、分支、上下文与提交模型。
- [Development: automatic Hot Reload / Hot Restart](./development/hot-reload.md)：开发期文件变更自动 Hot Reload / Hot Restart 工具（仅开发环境）。
- [Next Generation State Architecture Plan](./codex/next-generation-state-architecture-plan.md)：角色/世界状态、事件、权重与时间线的国际化架构契约（设计/规划文档，非当前状态）。
- [Error/Event Localization Migration Audit](./codex/error-event-localization-migration-audit.md)：六组 D 类错误与事件跨层债务的位置清单及迁移验收顺序（迁移尚未完成）。

## 功能子系统现状索引

下列子系统各自有唯一的状态入口；它们**不是**另一个全项目 Status Authority，只用于回答“某功能当前做到哪”。

- **Related Character Generation（角色关系）**：Phase 0–10 全部完成，最终入口为
  [Phase 10 Runtime Narrative Acceptance（ACCEPTED）](./character-relationships/phase-10-runtime-narrative-acceptance.md)；
  Phase 2–8 中间记录见 [`phase-02-08-progress.md`](./character-relationships/phase-02-08-progress.md)（历史快照）。
- **Character/World State System（运行时状态）**：已实现部分见 [`state-system/`](./state-system/)（Phase 1/2/3/4/7 报告与
  presentation contract）；早期设计/阶段计划 [`design/character-world-state-system-design.md`](./design/character-world-state-system-design.md)、
  [`plan/character-world-state-phase-plan.md`](./plan/character-world-state-phase-plan.md) 属规划，非当前状态。
- **UI Refactor（Narrative Workbench）**：R02 navigation-first 收敛已
  `COMPLETE`，见 [`ui-refactor/r02-final-navigation-first-acceptance.md`](./ui-refactor/r02-final-navigation-first-acceptance.md)；
  实机验收清单见 [`ui/ui-acceptance-checklist.md`](./ui/ui-acceptance-checklist.md)。
- **Read Aloud / Enhanced Neural TTS**：当前架构与限制见 [`read-aloud/enhanced-tts-v1.md`](./read-aloud/enhanced-tts-v1.md)。
- **Releases（发布事实）**：[`releases/`](./releases/) 为历史与当前 release 记录，最新为
  [`v1.2.00-android-arm64.md`](./releases/v1.2.00-android-arm64.md)；正式发布仅 Android ARM64。

## 历史程序状态（Status Authority 分层）

以下两个已完成程序的状态文档层级明确，不得混淆，也不得把旧程序当作 LT 当前状态：

1. **Adaptive Resource System（历史 Phase 0–12）** — [执行状态（历史）](./adaptive-resource-system/STATUS.md)。
   Phase 0–12 已全部执行完成，Phase 12 最终独立验收为 `ACCEPTED WITH NON-BLOCKING FINDINGS`。
   该文件仅保留历史记录，**不是** LT 当前状态 Authority。
2. **Post-Phase-12 Remediation（R01–R06）** — [程序状态](./post-phase12-remediation/STATUS.md)。
   作为 Adaptive Resource System 的后继加固程序，R01–R06 全部 `ACCEPTED`，Post-Remediation Program 已 `COMPLETE`。

**判断 LT 当前状态：** 程序级最新状态入口为上述第 2 个文件
（`docs/post-phase12-remediation/STATUS.md`，记录截至 2026-09-20）；其后的功能开发以当前代码、
[`README.md`](../README.md)、[`docs/releases/`](./releases/) 与 git 历史为准。

代码是项目当前事实来源。新的复杂修复或架构调整如需交接方案，再在 `docs/` 下新增有明确生命周期的文档。
