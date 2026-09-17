# Phase 7 Final Independent Acceptance

**Date:** 2026-09-17
**Auditor:** independent acceptance reviewer (read-only)
**Audited HEAD:** `454447aedd7fef344017f15393da8a83eb9665c5`
**Working tree:** clean (`git status --short` empty)
**Commits in scope:** `4db3217`（implementation）、`b015c38`、`9424d02`、`4e6ac96`（remediation）、`454447a`（docs）
**Diff in scope:** `4211c8b..454447a` — 39 files, +7210 / −164

## Result

**FAILED**

Blocker **B1**（F2 未完整达成，并连带 F6 文档失真）未关闭。F1、F3、F4、F5 与 Phase 5/6 架构检查通过。

## Verification

### F1 — Regenerate optimistic lock — **PASS**

| 检查项 | 证据 | 结果 |
| --- | --- | --- |
| 命令要求令牌 | `lib/domain/resources/resource_edit_command.dart:220` `required super.expectedUpdatedAt` | PASS |
| validator 校验令牌 | `resource_edit_command.dart:312-318` regenerate 分支调用 `_requireToken` | PASS |
| service 使用令牌 | `lib/application/resources/section_control_service.dart:408-415`：`_requireRow` 后立即比对 `row.updatedAt != command.expectedUpdatedAt` → `SectionControlException`；比对在读取任务（`:416`）与发出 `SectionGenerationStarted`（`:426`）之前 | PASS |
| 令牌透传链完整 | `section_control_runtime.dart:49,141-149`；`section_control_controller.dart:141-146`（传 `entry.updatedAtToken`） | PASS |
| 绕过路径 | `regenerateSection(` 的生产调用点仅 controller → runtime → service 一条链，全部传令牌 | PASS |
| 边界 | 比对为启动前检查、非数据库 CAS（风险 A） | 见 Remaining Risks |

附带观察（非 F1 缺陷）：Phase 6 已验收的 Part 级 `retryPart`（`resource_studio_controller.retry()`）不经 Section 令牌即可重写 Part 正文。它属于既有 Phase 6 控件而非 Section 重生成入口，因此不构成 F1 绕过；但与 B1 同根：该路径同样不推进 Section 令牌。

### F2 — Section version consistency — **FAIL**

通过的部分（`lib/services/repositories/resource_tree_repository_impl.dart` 中 `_bumpSection` 的全部调用点）：

| Part 变更路径 | Section bump | 证据 |
| --- | --- | --- |
| `updatePart` | PASS | `:425` |
| `softDeleteNode(PartId)` | PASS | `:508` |
| `reorderParts` | PASS | `:548` |
| `_appendPart`（mount） | PASS | `:629` |
| `_updatePartContent`（mount patch） | PASS | `:659` |
| `_reorderNode`（Part 分支） | PASS | `:708` |
| `_renameNode` / `_archiveNode`（Part 分支，经 `_bumpOwnerOf`） | PASS | `:984` |

并发可拒绝性（独立核对，非依赖测试声明）：`test/services/section_control_repository_test.dart` 的 `Section version tracks every Part edit (F2)` 用旧 Section 令牌对 `updateSectionValidation` 写入，四条路径均抛 `ResourceTreeConflictException`，并附"当前令牌仍可写"的反证。

**未通过的部分 — 流式提交路径未纳入 Section 版本推进：**

- `lib/application/resources/resource_generation_task_repository.dart:335-350` 直接 `UPDATE resource_parts SET content, content_hash, updated_at`；`:352-363` 仅 `UPDATE resources SET updated_at`。**整个事务没有任何对 `resource_sections.updated_at` 的写入**，也没有失效 `validation_state`。
- 该常量已声明但从未使用：`resource_generation_task_repository.dart:82` `static const String sectionsTable = 'resource_sections';` —— 说明 Section 耦合被考虑过但未接线，证据充分。
- 这是**生产主路径**：Phase 7 的 Section 重新生成正是经由它落库 —— `streaming_section_regeneration_executor.dart:127` → `streaming_resource_generation_controller.dart:84-89` → `streaming_resource_generation_service.retryPart` → `part_generation_coordinator.dart:696` `commitPartContent`。
- 无任何补偿：`updateSectionValidation` 的调用点只有 `section_control_service.dart:361`（显式校验）与 `:531`（`_invalidateSectionValidation`，仅由 `updatePart`/`deletePart`/`movePart` 触发）。`regenerateSection`（`:404-479`）与流式提交均不重置校验结论。

**可观察后果（Phase 7 自身流程可达）：**

1. 某个 Section 先被"验证"为 `valid`，随后用户点"重新生成" → Part 正文被 AI 整体替换，而 `validation_state` 仍为 `valid`，`resource_sections.updated_at` 保持不变 → Studio 继续展示"验证通过"。
2. F2 的目标不变量（Section 令牌随内容变化）对**最主要的写入者**不成立：基于生成前读取的 Section 令牌，在该 Section 内容被 AI 改写后仍能通过写入校验（`regenerateSection` 的令牌门与任何后续 Section 级写入）。
3. 数据损坏风险有限（Phase 5 的 attempt 令牌与 `commitPartContent` 的 attemptId/状态校验仍阻止并发提交相互覆盖），但**状态一致性**要求（本次 remediation 规格中 "其他修改 section 内容路径…必须在 repository/service 层保证"）未满足。

### F3 — Migration test — **PASS**

- `test/application/resources/database_migration_v36_test.dart:49` `expect(DatabaseService.schemaVersion, 38)`（固定值，附"版本提升必须显式更新"注释）；`:45`、`:160` 跟随 `DatabaseService.schemaVersion`。
- `test/services/database_migration_v38_test.dart:39` 同样固定 `38`。
- 独立核对 `4211c8b..HEAD` 的全部测试改动：仅删除 3 行 `expect`（原 `37` 两处、`sectionAfter, equals(sectionBefore)` 一处），三处均为收紧或等价替换，且已在实施报告第 4 节如实记录。无未披露的断言放宽。

### F4 — Streaming executor coverage — **PASS**

- 测试构造**真实执行器**：`test/application/resources/streaming_section_regeneration_executor_test.dart:23` `StreamingSectionRegenerationExecutor(runtime: port)`；`lib/.../streaming_section_regeneration_executor.dart:57-58` 为该实现类。
- 所需 9 项覆盖齐备（`:39` success、`:67` sectionId mismatch、`:85` resourceId mismatch、`:97` generationId mismatch、`:109` partId mismatch、`:121` 无关事件忽略、`:137` 运行时提交失败、`:168` 抛错转失败、`:178` 无会话拒绝）。
- 测试通过 `SectionRegenerationRuntimePort` 注入同步事件流；端口抽取未改变生产语义（`StreamingRegenerationRuntimeAdapter` 包装同一个 controller，`riverpod_providers.dart` 单点装配）。
- 覆盖边界见 Remaining Risks（风险 B）。

### F5 — UI gating — **PASS**

- `lib/features/resource_studio/presentation/widgets/resource_studio_section_controls.dart` 中 **`partCount` 0 次出现**（`grep` 无命中）。
- 门控与标签由 `hasGenerationTasks` 驱动：`:231`（tooltip 文案）、`:237`（`onPressed`）、`:338`（`_generateLabel`：有任务且 `completed` → `重新生成`，否则 `生成`）。
- 语义来源一致：`lib/application/resources/section_control_service.dart:624` `hasGenerationTasks: taskStatuses.isNotEmpty`；`lib/domain/resources/section_control.dart:223/257/305` 字段默认 `false` 且 `copyWith` 正确保留。
- 结论：手工创建（无任务）但有 Part 的 Section → 按钮 `onPressed == null`＋解释性 tooltip；有任务且已完成 → `重新生成` 可点击；空 Section → 禁用。widget 测试三例覆盖。

### F6 — Documentation — **FAIL**

以下声明与代码不一致（均因 B1 而产生）：

- `phase-07-implementation-report.md` §5.1 第 1 条："任何影响 Section 内容的 Part 操作都会在同一事务内刷新所属 `resource_sections.updated_at`"，并列出 8 条路径。该集合**遗漏了流式提交路径**，而它是生产中最主要的 Part 正文写入者 → 声明过宽且失实。
- 同文件 §5.3 第 3 条："现在 Part 编辑会推进 Section 令牌，写回将以 `ResourceTreeConflictException` 被拒绝，该竞态已关闭" —— 仅对 tree repository 路径成立；经流式提交的 Part 变更仍不推进令牌，竞态对该路径**未关闭**。

其余文档内容经抽查与代码一致：命令令牌要求、校验写回不推进 `updated_at`、`_reorderNode` 只 bump Section 不 bump Resource（`:708` 已核对）、执行器 9 例、F3 的两处基线变化说明、1016 全量结果。

### 测试结果

```text
dart format --output=none --set-exit-if-changed .   exit 0（403 files, 0 changed）
flutter analyze                                     No issues found!
flutter test -r compact                             01:22 +1016: All tests passed!（exit 0）
```

无 `skip` / `@Skip` / `markTestSkipped`（全仓库 0 命中）；被本次改动的测试中 `// ignore:` 0 命中。

### 架构检查

| 检查项 | 结果 | 证据 |
| --- | --- | --- |
| 1. Phase 5 未被破坏 | **PASS** | `resource_generation_patch.dart`、`generation_patch_parser.dart`、`streaming_resource_generation_service.dart`、`resource_generation_task_repository.dart` 在 `4211c8b..HEAD` 中 **0 改动**；仅 `part_generation_coordinator.dart`(+9)、`part_generation_prompt_builder.dart`(+21)、`resource_generation_protocol.dart`(+8) 为可选 `userInstruction` 的纯增量，默认空串时 prompt 逐字不变。wire protocol 无 breaking change |
| 2. Phase 6 未被破坏 | **PASS** | 改动为纯增量：`resource_studio_page.dart` +107/−2、`resource_studio_runtime.dart` +11（仅新增 getter）；生成流程与 state 层未被替换，Phase 6 既有用例全部通过 |
| 3. 绕过 service 直接操作数据库 | **PASS** | `lib/features/resource_studio/` 内无 `sqflite` / `DatabaseService` / `.database` 引用；Section 写入统一经 `SectionControlService` |
| 4. 状态机非法迁移 | **PASS（附观察）** | `ResourceStateMachines.advanceNodeStatus` 在 tree repository 三处生效（`:365`、`:408`、`:724`）。观察：`SectionGenerationStateMachine` 在本次变更中仅由测试驱动，生产侧 Section 生成态为推导值，不写入，故不存在非法写入；推导序列（如 `completed → pending`）不受该机约束 |
| 5. UI 显示状态与数据库状态不一致 | **FAIL** | UI 未本地缓存，展示值恒等于数据库值；但数据库的 `validation_state` 在内容被流式提交改写后不被失效（B1），因此 Studio 会展示与内容不符的"验证通过"。机制见 F2 一节 |

## Remaining Risks

### Blocking issues

**B1 — F2 的 Section 版本一致性未覆盖 Phase 5 流式提交路径（连带 F6 失真）**

- 事实：`resource_generation_task_repository.dart:335-363` 在同一事务内改写 `resource_parts.content/content_hash` 与 `resources.updated_at`，但不写 `resource_sections.updated_at`、不失效 `validation_state`；该路径是 Phase 7「重新生成」的实际落库路径，也是正常 AI 生成的落库路径（`part_generation_coordinator.dart:696`）。
- 为何是 blocker（而非 accepted limitation）：
  1. 本次 remediation 规格把 F2 明确限定为"任何影响 Section 内容的 Part 操作…其他修改 section 内容路径…必须在 repository/service 层保证"，该路径属于明确的必达范围，不是新增需求。
  2. 修复手段不触碰 Phase 5 wire protocol（仅在同一既有事务内附加一次 `UPDATE resource_sections` 与一次校验失效写入），因此"禁止修改 Phase 5 协议"不能作为不覆盖的理由。
  3. 它产生用户可见的错误状态（重生成后仍显示"验证通过"），即审计清单第 5 项的实质不通过。
- 为何阻塞 Phase 8：Phase 8（容量与语义压缩）与 Phase 10（assembly readiness）要在 Section/Part 内容与校验状态之上做压缩与组装决策。若最频繁的 AI 写入不推进 Section 版本、不失效校验，任何以"Section 令牌 / 校验结论"为前置条件的压缩或组装门禁都会在过期状态上运行；先接受 Phase 7 会把一个已知不成立的一致性不变量带入后续阶段。
- 建议的最小修复方向（不在本次审计范围内实施）：在 `commitPartContent` 的事务内解析 `taskRow['section_id']`，`UPDATE resource_sections SET updated_at = now WHERE id = ?`，并将该 Section 的 `validation_state` 置回 `unvalidated`（或改为在 `PartGenerationTaskRepositoryImpl` 注入 Section 一致性回调，避免任务仓储直接承担 Section 语义）；同时补一条"流式提交后旧 Section 令牌被拒 / 校验被失效"的回归测试，并修正实施报告 §5.1、§5.3 的表述。

### Non-blocking limitations（对已通过项）

**风险 A — `regenerateSection` 令牌检查为启动前比对，不是数据库 CAS**：属 accepted limitation。比对发生在任何 Part 启动之前（`section_control_service.dart:408-415`），语义目标是"不基于过期读发起重生成"；重生成本就要替换正文，运行期二次校验无意义。若后续需要严格串行化，应在 Phase 9 Revision 边界引入原子 claim。**不阻塞**（但注意：受 B1 影响，该门目前无法感知"由生成自身造成的内容变化"）。

**风险 B — 执行器防线与 Phase 5 累加器的先后顺序缺少端到端证明**：属 accepted limitation。真实链路中跨 Section 的 patch 会先在 Phase 5 `GenerationPatchAccumulator` 抛错，执行器自身防线由 9 个直驱真实执行器的用例覆盖（F4 PASS）。两条防线都收敛到"拒绝并失败"，未发现可绕过组合；缺口是集成测试覆盖，而非正确性。**不阻塞**。

**风险 C — `_reorderNode` 的 Part 分支不刷新 Resource `updated_at`**：**不影响 Phase 7 correctness**。该行为在改动前即存在且未被扩大；Phase 7 的要求针对 Section 令牌（已满足，`:708`）。唯一影响是资源列表按 `updated_at DESC` 排序时的新鲜度标记，属既有行为。

### 其他观察（非阻塞、无需求违背）

- `SectionGenerationStateMachine` 目前仅被测试使用；生产生成态为推导值，不写入，故不影响正确性。
- Phase 6 的 Part 级 `retryPart` 不携带 Section 令牌（既有已验收行为）；它与 B1 同根，随 B1 的修复一并获得 Section 版本推进。

## Unlock Decision

F2 未达成（B1）且 F6 文档在相关处失真，因此 **Phase 7 = FAILED**；Phase 8 保持 **BLOCKED**。关闭 B1（补齐流式提交路径的 Section 版本推进与校验失效，并修正 §5.1/§5.3 表述）后，可提交复验；F1、F3、F4、F5 及 Phase 5/6 架构检查的结论可在复验中沿用，无需重复全量审查。
