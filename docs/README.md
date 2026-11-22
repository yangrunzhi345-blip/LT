# 项目文档

`docs/` 保留当前仍有用途的文档，以及有追溯价值的已完成程序历史。

## 当前参考

- [Adventure Runtime State](./adventure_runtime_state.md)：运行态、分支、上下文与提交模型。
- [Turn Settlement Pipeline](./turn-settlement-pipeline.md)：正文生成 → 独立结算 → 原子提交。
- [API Key 存储](./design/api-key-storage.md)：平台凭证库优先、SQLite 密文回退的主从关系。
- [Development: automatic Hot Reload / Hot Restart](./development/hot-reload.md)：开发期文件变更自动 Hot Reload / Hot Restart 工具（仅开发环境）。
- [UI 实机与人工验收清单](./ui/ui-acceptance-checklist.md)：跨平台与窄屏人工验收条目。
- [剩余工作实施计划](./plan/remaining-work-2026-11-18.md)：阶段 1–5 之后的非阻塞后续清单。
- [Releases（发布事实）](./releases/)：历史与当前 release 记录，最新为
  [v1.3.02-android-arm64.md](./releases/v1.3.02-android-arm64.md)；正式发布仅 Android ARM64。

## 功能子系统现状索引

下列子系统各自有唯一的状态入口；它们**不是**另一个全项目 Status Authority，只用于回答“某功能当前做到哪”。

- **Character/World State System（运行时状态）**：已实现部分见 [state-system/](./state-system/)（Phase 1/2/3/4/7 报告与
  presentation contract）；早期设计/阶段计划 [design/character-world-state-system-design.md](./design/character-world-state-system-design.md)、
  [plan/character-world-state-phase-plan.md](./plan/character-world-state-phase-plan.md) 属规划，非当前状态。
- **UI Refactor（Narrative Workbench）**：实机验收清单见 [ui/ui-acceptance-checklist.md](./ui/ui-acceptance-checklist.md)；
  设计与状态以当前代码和 [`AGENTS.md`](../AGENTS.md) 的 LT Narrative Workbench Design Language 为准。
- **资料库（setting card）**：当前实现是单文档设定卡，见 [`README.md`](../README.md) 的 Resource Library 一节，
  以及 [`AGENTS.md`](../AGENTS.md) 的「当前资源架构」。旧资源表仅作兼容迁移，不再驱动资料库。
- **Read Aloud**：当前仅使用系统 TTS（`flutter_tts` / Linux Speech Dispatcher）。本地神经 TTS 已在 Phase 3 移除，
  其设计记录归档在下方「已归档 / 历史设计」。

## 架构决策与审计

- [ADR-0003：可配置生成弹性预算](./architecture/configurable-generation-elasticity.md)：弹性比例与冻结预算的历史决策。
- Import Authority 审计链：[完整链路审计](./architecture/import-authority-full-chain-audit.md) →
  [Phase 2](./architecture/import-authority-phase2-report.md) → [Phase 3 最终报告](./architecture/import-authority-phase3-final-report.md)。
- [角色卡生成预算根因审计](./character-generation-budget-root-cause-and-remediation.md)：修复设计与证据交接（非完成报告）。
- [Phase 6 动态角色在场](./adventure/phase-06-dynamic-character-presence-report.md)、
  [Phase 5 对话上下文权重](./context/phase-05-dialogue-context-weight-management-report.md)。

## 已归档 / 历史设计

以下文档仅作历史参考，不代表当前实现。

- [ADR-0001：自适应资源系统内容树契约](./architecture/adaptive-resource-system.md)：Phase 0 冻结契约；树 / revision / assembly
  管线已被单文档设定卡（setting_cards）替代。
- [U6：动态正文有效性契约](./architecture/u6-dynamic-content-validity-contract.md)：资源树生成时代的正文有效性契约。
- [Enhanced TTS v1（本地神经 TTS）](./read-aloud/enhanced-tts-v1.md)：本地神经 TTS 设计记录，Phase 3 已移除，不随产品发布。
- [Enhanced TTS v1 最终审计计划](./read-aloud/enhanced-tts-v1-final-audit-plan.md)：同上，历史计划。
- [P0：Resource Part 连续生成冻结诊断](./p0-resource-part-freeze-diagnostics.md)：历史 Agent 报告，涉及的 Part 生成管线已移除。

## 历史程序状态

Adaptive Resource System（Phase 0–12）与 Post-Phase-12 Remediation（R01–R06）的验收报告与 STATUS 文件已在 slim 重构的
Phase 1 中移出工作树，仅保留在 git 历史（`git log -- docs/archive`）。它们描述的是已退役的实现，**不是** LT 当前状态。

判断 LT 当前状态：以当前代码、[`README.md`](../README.md)、[`docs/releases/`](./releases/) 与 git 历史为准。

代码是项目当前事实来源。新的复杂修复或架构调整如需交接方案，再在 `docs/` 下新增有明确生命周期的文档。
