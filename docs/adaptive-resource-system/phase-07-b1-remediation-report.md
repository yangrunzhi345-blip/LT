# Phase 7 B1 Blocker Remediation Report

**Date:** 2026-09-17
**Executor:** executor-agent
**Baseline (Start HEAD):** `454447aedd7fef344017f15393da8a83eb9665c5`
**End HEAD:** `3b265f94d1d4943d4361c7beb54d74bf74945e2a`（`fix(phase7): sync section version and verdict on streaming commit`；本报告与 STATUS 的更新为紧随其后的 `docs(phase7)` 提交）
**Input:** `docs/adaptive-resource-system/phase-07-final-independent-acceptance.md`（Result: FAILED，唯一 Blocker B1）
**Status:** `IMPLEMENTED`（等待 Final Independent Audit；本报告不宣布 Phase 7 `ACCEPTED`）

## 1. Blocker 根因

审计结论（B1）：Section 版本一致性不变量被破坏。

- `PartGenerationTaskRepositoryImpl.commitPartContent` 在其事务内只做三件事：写 `resource_parts.content/content_hash`、刷新 `resources.updated_at`、更新 task 与 attempt 状态。**它从不写 `resource_sections.updated_at`，也不失效 `validation_state`**（修复前 `resource_generation_task_repository.dart:335-363`）。
- 该方法正是 Phase 7「重新生成」的落库点：`StreamingSectionRegenerationExecutor.retryPart` → `StreamingRegenerationRuntimeAdapter` → `StreamingResourceGenerationController.retryPart` → `StreamingResourceGenerationService.retryPart` → `PartGenerationCoordinator.retrySinglePart` → `commitPartContent`。也是正常 AI 生成的落库点。
- 证据补充：`sectionsTable = 'resource_sections'` 在该类中已声明但从未使用（修复前 `:82`），说明 Section 耦合被考虑过但未接线。
- 可观察后果：Section 先被验证为 `valid`，随后内容被 AI 改写（生成或重新生成）时，`validation_state` 仍为 `valid`、Section 令牌不变，Studio 继续展示"验证通过"；基于旧令牌的 Section 级写入仍被接受。

## 2. 修改方案

### 2.1 新增单一失效规则（domain）

`lib/domain/resources/section_control.dart`：

- `SectionValidationState` 增加 `stale`（存储值 `'stale'`）：表示"曾有过结论，但其描述的内容此后已被改写"。未引入临时字符串状态，仍是持久化枚举值；DB 列为 TEXT，无需 migration。
- 新增唯一失效规则：

```dart
static SectionValidationState afterContentChange(SectionValidationState current) =>
    switch (current) {
      SectionValidationState.valid || SectionValidationState.invalid => SectionValidationState.stale,
      _ => current,
    };
```

  已记录的结论（`valid` / `invalid`）降级为 `stale`；`unvalidated` / `validating` / `stale` 保持不变，规则幂等。

### 2.2 流式提交路径同步 Section（B1 主修复）

`lib/application/resources/resource_generation_task_repository.dart`：

- `commitPartContent` 在**同一事务**内新增第 3 步，调用新的私有方法 `_syncOwningSection`。
- `_syncOwningSection`：
  1. 从 **`resource_parts.section_id`** 解析所属 Section（Part → Section 的唯一权威映射；**不**通过 Section 行反查自己的 id，避免重演 `_sectionRow` 缺陷）；
  2. 读取该 Section 当前 `validation_state`，用 `afterContentChange` 计算目标状态；
  3. `UPDATE resource_sections SET updated_at = ?`，并且**仅当结论确实被降级时**同时写 `validation_state = 'stale'` 与清空 `validation_message`（未被降级的行保持其既有内容，不写无意义变更）；
  4. 缺 Part / 缺 Section / 缺 `section_id` 时抛 `StateError`，与该方法既有的完整性校验风格一致，绝不静默跳过。
- `sectionsTable` 常量至此被实际使用（未新增第二个查询入口）。

### 2.3 使两类失效路径共用同一语义

`lib/application/resources/section_control_service.dart`：

- `_invalidateSectionValidation`（由 `updatePart` / `deletePart` / `movePart` 触发）改用同一条 `afterContentChange` 规则，并把提前返回条件从"已是 unvalidated"改为"规则未产生变化"。因此用户编辑与 AI 改写现在产生**同一个**结果状态（`stale`），不再出现两条失效路径语义不一致。

### 2.4 UI 映射

`lib/features/resource_studio/presentation/widgets/resource_studio_section_controls.dart`：

- `stale` → 标签"内容已变更，需重新验证"，颜色 `colorScheme.tertiary`（既非错误红，也不与 `unvalidated` 的灰混淆）。Dart 的穷尽 switch 保证不会漏映射。

## 3. 事务保证

```
db.transaction((txn) async {
  1. 校验 task 与响应绑定（resourceId / partId）
  2. 校验 attempt 令牌与任务状态（拒绝被取代或已取消的提交）
  3. UPDATE resource_parts   (content, content_hash, updated_at)
  4. UPDATE resources        (updated_at)
  5. _syncOwningSection      (UPDATE resource_sections: updated_at[, validation_state, validation_message])
  6. UPDATE resource_generation_tasks (completed)
  7. UPDATE resource_generation_attempts (completed)
});
```

- 全部步骤处于**同一个 SQLite 事务**：不存在"先提交 Part、再更新 Section"的顺序窗口。
- 任一步失败（含第 5 步）→ 整个事务回滚，Part 正文、Section 版本、任务与尝试状态都不会部分落库。Case 3 用触发器强制第 5 步失败，并证明 Part 内容、任务状态、Section 令牌三者均未被写入。

## 4. 新增测试

| 用例 | 文件 | 覆盖 |
| --- | --- | --- |
| Case 1：已 `valid` 的 Section 被提交后结论失效且令牌推进 | `test/application/resources/resource_generation_task_repository_test.dart` | `validation_state == stale`、`validation_message` 清空、`updated_at` 变化 |
| Case 2：提交前读取的令牌被拒 | 同上 | 旧令牌写回抛 `ResourceTreeConflictException`；当前令牌仍可写（守卫未整体损坏） |
| Case 3：事务一致性（Section 更新失败 → 全量回滚） | 同上 | 用 `BEFORE UPDATE ON resource_sections` 触发器 `RAISE(ABORT)` 强制第 5 步失败；断言 Part 内容、任务状态、Section 令牌均回滚 |
| Case 4：真实流式重生成链路 | `test/application/resources/section_consistency_streaming_regeneration_test.dart`（新增） | 完整生产链路（executor → adapter → controller → service → coordinator → `commitPartContent`）：正文确实写入、结论降级为 `stale`、令牌推进、新令牌可写 |
| 规则与枚举（domain） | `test/domain/resources/section_control_test.dart` | `fromStorage('stale')`、`afterContentChange` 对 5 个状态的映射与幂等性 |
| 服务层语义一致 | `test/application/resources/section_control_service_test.dart` | 用户 Part 编辑 → `stale`；从未验证过 → 保持 `unvalidated`（不凭空造结论） |
| 执行器绑定语义（配合下方 D1 修复） | `test/application/resources/streaming_section_regeneration_executor_test.dart` | "以协议 id 而非 session id 绑定"成功用例；"同一运行内出现被取代 generation 的 patch"拒绝用例 |
| UI 新标签无溢出 | `test/widget/resource_studio_section_controls_test.dart` | 六个 viewport 下 `stale` 标签"内容已变更，需重新验证"渲染且无 exception |

## 5. 测试结果

```text
dart format --output=none --set-exit-if-changed .   exit 0（0 changed）
flutter analyze                                     No issues found!
flutter test -r compact                             1023 passed（exit 0，1m25s；修复前 1016）
```

## 6. 修复过程中暴露的第二个缺陷（D1，已修复）与一个未修复限制（D2，上报）

### D1 — 执行器 generationId 绑定在生产链路上必然失败（本次一并修复）

编写 Case 4 时，真实链路立刻失败：

```text
SectionGenerationBindingException: generationId mismatch
  (expected: gen_sess_1789614379101733, actual: retry_res_cre_..._1_1789614379118)
```

- 根因：runtime 事件（`PartStarted` / `PatchReceived`）的 `generationId` 是**生成会话 id**（由 `StreamingResourceGenerationService` 在回调里写入），而 patch 携带的是 Phase 5 每次尝试生成的**协议 generation id**（coordinator 铸造的 `retry_<res>_<millis>`）。修复前的执行器用事件 id 构造绑定、再用 patch id 校验，二者必然不等 → **每一次真实重生成都会被判为失败**（即使正文已成功提交）。
- 为什么 F4 没发现：F4 用 `SectionRegenerationRuntimePort` fake 直驱事件，事件 id 与 patch id 相同，因此掩盖了真实链路的差异。这正是最终审计列为"风险 B（缺少端到端证明）"的那类缺口。
- 修复（仅动 Phase 7 自有代码）：执行器改为**以首个 patch 的协议 generation id 为本次运行的基准并锁定**，后续 patch 必须携带同一 id；resource / section / part 仍对每次 patch 与请求比对。class doc 已写明这一区分。
- 未触达 Phase 5：`resource_generation_patch.dart`、`generation_patch_parser.dart`、`streaming_resource_generation_service.dart`、`part_generation_coordinator.dart` 在本次修复中 **0 改动**（`git diff --name-only` 可验证）。

### D2 — 对"已全部生成完成"的 Section 执行重新生成仍会失败（**未修复，上报最终审计**）

- 事实链：`PartTaskStatus.completed` 是终态（`PartTaskStateMachine` 只允许自转移，`resource_generation_protocol.dart`）；`startAttempt` 对已完成任务直接抛 `StateError('任务已完成，禁止重新发起生成')`（`resource_generation_task_repository.dart:207-209`）；`markTaskReady` 只被 coordinator 的**失败任务**重试分支调用（`part_generation_coordinator.dart:326`），对已完成任务无重置路径。
- 后果：一个已生成完成的 Section（其任务全为 `completed`、UI 依据 rollup 显示"重新生成"且按钮可用）执行重新生成会在 `startAttempt` 处失败，服务返回 `SectionGenerationFailedEvent` 并在面板显示该错误。Phase 7 的封面能力"单独重新生成 Section"在**最常见的已完成状态**下不可用。
- 为什么本次不修：修复需要决定"如何处理已完成的生成任务"（重置为 `ready`？开新 attempt/revision？），这属于 Phase 5 任务状态机语义与 Phase 9 Revision 边界的决策，超出本次"只修复 B1、不得修改 Phase 5 协议/状态机、不得大规模重构"的授权范围。
- 建议：由最终审计判定为独立 Blocker（记为 B2）或在 Phase 8/9 明确设计后修复；最小可选方案是在 `SectionControlService.regenerateSection` 启动前对 `completed` 任务执行显式重置（复用既有 `markTaskReady`），但该语义必须先在 Phase 5 契约层面被批准。
- 已同步写入 `phase-07-implementation-report.md` 第 5.3 节，并在 `section_control_service.dart` 的 regenerate 文档注释中保持中立表述（不隐藏、不夸大）。

## 7. 修改文件列表

生产代码（5）：

- `lib/application/resources/resource_generation_task_repository.dart`（B1 主修复：`_syncOwningSection` + 事务内接线 + 实际使用 `sectionsTable`）
- `lib/domain/resources/section_control.dart`（`stale` + `afterContentChange`）
- `lib/application/resources/section_control_service.dart`（两类失效路径共用同一规则）
- `lib/features/resource_studio/application/use_cases/streaming_section_regeneration_executor.dart`（D1 修复：绑定基准改为协议 generation id）
- `lib/features/resource_studio/presentation/widgets/resource_studio_section_controls.dart`（`stale` 标签与颜色）

测试（5 修改 + 1 新增）：

- 新增 `test/application/resources/section_consistency_streaming_regeneration_test.dart`
- `test/application/resources/resource_generation_task_repository_test.dart`（Case 1–3）
- `test/application/resources/streaming_section_regeneration_executor_test.dart`（D1 回归）
- `test/application/resources/section_control_service_test.dart`（`stale` 语义 + 不凭空造结论）
- `test/domain/resources/section_control_test.dart`（枚举与失效规则）
- `test/widget/resource_studio_section_controls_test.dart`（新标签无溢出）

文档（2 + 1 待提交）：

- `docs/adaptive-resource-system/phase-07-implementation-report.md`（5.1 / 5.2 / 5.3 修正为准确描述，见下）
- `docs/adaptive-resource-system/phase-07-b1-remediation-report.md`（本文件）
- `docs/adaptive-resource-system/STATUS.md`

`git diff --stat`（相对 `454447a`）：11 个已跟踪文件 +461 / −42，另加 1 个新增测试文件。

> 说明：上一轮审计生成的 `docs/adaptive-resource-system/phase-07-final-independent-acceptance.md` 仍为未跟踪文件。为让工作区对下一轮审计保持 clean，本次一并将其纳入文档提交（内容未做任何修改）；如审计方希望自行管理该文件，请在验收时说明。

## 8. 文档修正（原错误声明）

`phase-07-implementation-report.md`：

- §5.1 原声明："任何影响 Section 内容的 Part 操作都会在同一事务内刷新所属 `resource_sections.updated_at`"，且只列出树仓库的 8 条路径 → 已改为**明确区分两类写入者**（树仓库 8 条路径 + Phase 5 流式提交路径 `_syncOwningSection`），并写明 Part → Section 归属取自 `resource_parts.section_id`、失效规则、`validation_message` 清空条件与 `validated_at` 的保留。
- §5.3 原声明："现在 Part 编辑会推进 Section 令牌…该竞态已关闭"（对流式提交路径不成立）→ 已改为"**已对两类写入者关闭**"，并新增 D2 限制的披露。
- §5.2 补充执行器绑定语义（session id vs 协议 id）与端到端覆盖文件。
- §2.1 枚举清单补充 `stale`。

## 9. 验证

```text
dart format --output=none --set-exit-if-changed .   通过（0 changed）
flutter analyze                                     通过（No issues found）
flutter test -r compact                             1023 passed（exit 0）
```

禁止事项遵守情况：

- Phase 5 wire protocol / parser / streaming service / coordinator：本次 **0 改动**。
- 未修改 frozen contracts（`resource_contracts.dart` / `resource_repository.dart` 0 改动）。
- 未删除测试、未使用 `skip`/`ignore`、未放宽断言（唯一变更的既有断言是 `unvalidated` → `stale` 的语义收紧，并新增反向用例证明"从未验证过仍保持 unvalidated"）。
- 未引入临时 workaround；`stale` 是持久化枚举值而非字符串散落状态。

## 10. 结论

B1 已修复：Section 内容的两类写入者现在都在各自的同一事务内推进 Section 版本并按下述单一规则失效校验结论（`valid`/`invalid` → `stale`），有 4 类新测试覆盖（含真实流式链路的端到端用例）。修复过程中暴露的 D1（执行器绑定必然失败）已一并修复；D2（已完成任务无法重新生成）已如实上报、未修复。

**本报告不宣布 Phase 7 `ACCEPTED`**；是否通过由 Final Independent Audit 依据本报告、`phase-07-final-independent-acceptance.md`、commit diff 与测试结果裁定。Phase 8 保持 `BLOCKED`。
