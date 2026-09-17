# Phase 7 Remediation Report

**Date:** 2026-09-17
**Executor:** executor-agent
**Baseline HEAD (Start):** `9424d022c93937e69e789f3c9b0cb86aa3cdfb1e`
**End HEAD:** `4e6ac96dac79d68230c32b88e60bda1f1dfd9bcc`（`fix(phase7): remediate F1-F6 from the audit findings`；本报告与 STATUS 的更新为紧随其后的 `docs(phase7)` 提交）
**Scope:** 修复 Phase 7 独立审计提出的 F1–F6；不是重新实现 Phase 7
**Status:** `IMPLEMENTED`（等待独立审计；本报告不宣布 Phase 7 `ACCEPTED`）

## 0. 输入与前置检查

- 当前 HEAD 与目标基线一致：`9424d02`（`git status` 干净）。
- 仓库中**不存在** `docs/adaptive-resource-system/phase-07-independent-acceptance.md`。F1–F6 的实际来源是上一轮对报告与 `4db3217` diff 的逐条验证结论（对话中的验证输出）。本报告按同样的编号逐项修复，未虚构审计文档。
- 已阅读并保持一致的文档：`phase-07-implementation-report.md`、`STATUS.md`、`phase-07-section-controls.md`。

## 1. F1 — RegenerateSectionCommand 乐观锁缺失

| 项 | 内容 |
| --- | --- |
| 问题 | 报告声称"每个变更命令携带 `expectedUpdatedAt`"，但 regenerate 的令牌可选、validator 不校验、service 不使用，重新生成没有并发保护 |
| 修复 | `RegenerateSectionCommand.expectedUpdatedAt` 改为 `required`；`ResourceEditCommandValidator` 对 regenerate 增加 `_requireToken`；`SectionControlService.regenerateSection` 在启动任何 Part 之前比对命令令牌与持久化 Section 令牌，不一致抛 `SectionControlException` |
| 令牌透传 | `SectionControlRuntime.regenerateSection` 新增 `required String expectedUpdatedAt`；`SectionControlServiceRuntime`、`SectionControlController`（传 `entry.updatedAtToken`）、测试 fake 同步 |
| 文件 | `lib/domain/resources/resource_edit_command.dart`、`lib/application/resources/section_control_service.dart`、`lib/features/resource_studio/application/use_cases/section_control_runtime.dart`、`lib/features/resource_studio/presentation/controllers/section_control_controller.dart`、`test/helpers/section_control_fakes.dart` |
| 新测试 | `resource_edit_command_test.dart`：`requires an optimistic token for regeneration too`；`section_control_service_test.dart`：`rejects a stale section token before touching any Part`、`accepts a current section token and regenerates`、`rejects a token that went stale because a Part was edited` |
| 残留 | 比对与启动之间存在 TOCTOU 窗口，且不是原子 claim；见实施报告 5.3 |

## 2. F2 — Section `updated_at` 与 Part 修改同步

| 项 | 内容 |
| --- | --- |
| 问题 | `ResourceTreeRepositoryImpl.updatePart` 只刷新 resource，不刷新 `resource_sections.updated_at`，Section 令牌无法感知 Part 修改 |
| 修复 | 统一策略落在 repository 层（不依赖调用方）：新增 `_bumpSection`，并在**同一事务**内从 `updatePart`、`softDeleteNode(PartId)`、`reorderParts`、`_appendPart`、`_updatePartContent`、`_renameNode`/`_archiveNode`（经 `_bumpOwnerOf` 的 Part 分支）、`_reorderNode`（Part 分支）刷新所属 Section |
| 附带修复 | 原 `_sectionRow` 返回 Section 行，使 Part 删除路径 `row['section_id']` 恒为 null（既未刷新 Section 也未刷新 Resource）。改为 `_sectionIdOfPart` 返回 section id；Part 删除现在同时刷新 Section 与 Resource |
| 不改动 | `updateSectionValidation` 仍不推进 `updated_at`（校验是历史记录，不是内容编辑）——该断言已有测试固定 |
| 文件 | `lib/services/repositories/resource_tree_repository_impl.dart` |
| 新测试 | `section_control_repository_test.dart` 新增 `Section version tracks every Part edit (F2)` 组：Part 正文更新 / Part 删除 / Part 重排 / mount Part content patch 均使旧 Section 令牌被拒，并验证当前令牌仍可写（守卫未整体损坏） |
| 既有测试调整 | `resource_tree_repository_test.dart` 的 "updating one part leaves the other parts untouched"：断言从"Section 行完全不变"改为"仅 `updated_at` 可变、其余列逐列不变"。这是 F2 有意引入的契约变化，未降低强度 |
| 残留 | `_reorderNode` 的 Part 分支仍不刷新 Resource（改动前即如此，未扩大范围）；见实施报告 5.1 |

## 3. F3 — 迁移测试声明不实

| 项 | 内容 |
| --- | --- |
| 问题 | 初次实现把 `expect(DatabaseService.schemaVersion, 37)` 放宽为 `greaterThanOrEqualTo(37)`，但报告声明"无降低预期" |
| 修复（方案 A） | 恢复严格断言为固定 `38`，并加注释说明"版本提升必须显式更新此处（以及 v38 测试）"；`_userVersion` 断言保持跟随 `DatabaseService.schemaVersion` |
| 文件 | `test/application/resources/database_migration_v36_test.dart` |
| 报告修正 | `phase-07-implementation-report.md` 第 4 节改为如实说明两处基线变化，删除"无降低预期"表述 |

## 4. F4 — StreamingSectionRegenerationExecutor 无测试

| 项 | 内容 |
| --- | --- |
| 问题 | 真实运行路径（跨 Section patch 的运行期防线）只有 fake 覆盖，执行器本身无测试 |
| 修复 | 在 `section_regeneration.dart` 增加窄端口 `SectionRegenerationRuntimePort`（`events` / `latestSessionIdForResource` / `retryPart`）；`StreamingSectionRegenerationExecutor` 改为依赖该端口；生产侧由 `StreamingRegenerationRuntimeAdapter` 包装**同一个** `StreamingResourceGenerationController` 与 session repository（仍是单套生成栈） |
| 文件 | `lib/application/resources/section_regeneration.dart`、`lib/features/resource_studio/application/use_cases/streaming_section_regeneration_executor.dart`、`lib/providers/riverpod_providers.dart` |
| 行为兼容 | 生产装配等价（同一 controller / 同一事件流），`retryPart` 调用与事件过滤逻辑未变 |
| 新测试 | `test/application/resources/streaming_section_regeneration_executor_test.dart`（9 个用例，调用真实执行器）：正确绑定成功（含 `characterCount`/`generationId` 捕获）、sectionId / resourceId / generationId / partId 不匹配拒绝并点名实际值、无关 Part/Resource 事件被忽略、校验失败与运行时抛错转为失败结果、无会话时不调用运行时 |
| 覆盖边界 | 跨 Section patch 在真实链路中会先在 Phase 5 累加器抛错；"执行器防线先于累加器"这一顺序未被端到端集成测试固定。见实施报告 5.2 |

## 5. F5 — UI 门控错误

| 项 | 内容 |
| --- | --- |
| 问题 | 生成按钮按 `entry.partCount > 0` 门控，手工新增但有 Part 的 Section 会显示可点击却必然失败的"生成" |
| 修复 | `SectionControlEntry` 新增明确字段 `hasGenerationTasks`（由 `SectionControlService._entryFrom` 依据 Phase 5 任务存在性填充）；UI 改为按该字段门控与禁用，并对不可生成的行给出 tooltip；停用 `partCount` 判断 |
| 标签规则 | `hasGenerationTasks && generationState == completed` → `重新生成`；其余 → `生成`（无任务时禁用） |
| 文件 | `lib/domain/resources/section_control.dart`、`lib/application/resources/section_control_service.dart`、`lib/features/resource_studio/presentation/widgets/resource_studio_section_controls.dart` |
| 新测试 | `resource_studio_section_controls_test.dart` 新增 `generation gating` 组：手工有 Part 无任务 → 按钮 `onPressed == null`、tooltip 存在、点击不触发回调；有任务且已完成 → `重新生成` 可点击；空 Section → 禁用 |
| 解释性决策 | 任务书同时写了"无生成任务：允许生成"与"不可生成：按钮禁用"。二者互斥：让无任务的手工 Section 可生成，等于新增第二条生成路径（Phase 7 明确不做，且会引入临时 workaround）。因此采用"无生成任务 → 禁用并解释原因"，并把该解释写入实施报告 5.1(3)。若审计要求相反语义，需要新的任务编排设计而非本次 remediation |

## 6. F6 — 报告完整性

| 项 | 内容 |
| --- | --- |
| 修复 | `phase-07-implementation-report.md` 与代码对齐：命令令牌声明、regenerate 令牌校验、F2 的 Section 版本推进、`hasGenerationTasks`、执行器端口、F3 的断言说明；新增 `5.1 Section 版本推进策略`、`5.2 流式执行器测试覆盖`、`5.3 剩余并发考量`；全量测试结果更新为 1016 |
| 文件 | `docs/adaptive-resource-system/phase-07-implementation-report.md` |

## 7. 修改文件列表

生产代码（10）：

- `lib/services/repositories/resource_tree_repository_impl.dart`
- `lib/domain/resources/resource_edit_command.dart`
- `lib/domain/resources/section_control.dart`
- `lib/application/resources/section_control_service.dart`
- `lib/application/resources/section_regeneration.dart`
- `lib/features/resource_studio/application/use_cases/section_control_runtime.dart`
- `lib/features/resource_studio/application/use_cases/streaming_section_regeneration_executor.dart`
- `lib/features/resource_studio/presentation/controllers/section_control_controller.dart`
- `lib/features/resource_studio/presentation/widgets/resource_studio_section_controls.dart`
- `lib/providers/riverpod_providers.dart`

测试（8，含 1 个新增）：

- 新增 `test/application/resources/streaming_section_regeneration_executor_test.dart`
- `test/application/resources/section_control_service_test.dart`
- `test/application/resources/database_migration_v36_test.dart`
- `test/domain/resources/resource_edit_command_test.dart`
- `test/services/section_control_repository_test.dart`
- `test/services/resource_tree_repository_test.dart`
- `test/widget/resource_studio_section_controls_test.dart`
- `test/helpers/section_control_fakes.dart`

文档（2）：

- `docs/adaptive-resource-system/phase-07-implementation-report.md`
- `docs/adaptive-resource-system/phase-07-remediation-report.md`（本文件）
- `docs/adaptive-resource-system/STATUS.md`

`git diff --stat`（相对 `9424d02`）：18 个已跟踪文件 +559 / −93，另加 1 个新增测试文件。

## 8. 新增测试列表

| 文件 | 新增用例 |
| --- | --- |
| `resource_edit_command_test.dart` | `requires an optimistic token for regeneration too` |
| `section_control_service_test.dart` | `rejects a stale section token before touching any Part`、`accepts a current section token and regenerates`、`rejects a token that went stale because a Part was edited` |
| `section_control_repository_test.dart` | `Section version tracks every Part edit (F2)` 组：Part content update / Part delete / Part reorder / mounted Part content patch 各 1 例 |
| `streaming_section_regeneration_executor_test.dart` | 9 例：正确绑定成功、section/resource/generation/part 不匹配、无关事件忽略、运行时失败、抛错、无会话 |
| `resource_studio_section_controls_test.dart` | `generation gating` 组 3 例：手工有 Part 无任务、有任务已完成、空 Section |
| `resource_tree_repository_test.dart` | 既有 1 例改为精确断言（仅 `updated_at` 可变），非新增 |

合计新增 19 个用例（全量 997 → 1016）。

## 9. 验证结果

```text
dart format .                          通过（0 changed）
flutter analyze                        通过（No issues found）
flutter test -r compact                1016 passed（exit 0，1m24s）
```

定向回归（修复过程中逐项执行）：`resource_tree_repository_test` + `section_control_repository_test` 51 passed；`section_control_service_test` + `resource_edit_command_test` + `resource_studio_section_controls_test` 46 passed；`streaming_section_regeneration_executor_test` 9 passed。修复后同口径的 Phase 7 定向 + Studio 回归集合（10 个文件，含 `resource_tree_repository_test`）为 **147 passed**。

## 10. 禁止事项遵守情况

- 未修改 Phase 5 wire protocol：`resource_generation_patch.dart`、`generation_patch_parser.dart`、`streaming_resource_generation_service.dart`、`part_generation_coordinator.dart` 在本次 remediation 中 **0 改动**（`git diff` 不含）。
- 未修改 frozen contracts：`resource_contracts.dart`、`resource_repository.dart` 0 改动。
- 未删除任何测试；未使用 `skip`/`ignore`；未放宽断言（唯一被审计指出的放宽已恢复为更严格的固定版本断言）。
- 未引入临时 workaround：执行器端口抽取是生产可用的抽象，生产接线等价。

## 11. 结论

F1–F6 均已修复并有测试与文档支撑，`flutter analyze` 与全量 1016 个测试通过。**本报告不宣布 Phase 7 `ACCEPTED`**；是否通过由独立审计 Agent 依据本报告、实施报告、commit diff 与测试结果裁定。Phase 8 保持 `BLOCKED`。
