# Phase 7 — Section 精细编辑与生成控制 实施报告

**Date:** 2026-09-17
**Executor:** executor-agent
**Start HEAD:** `4211c8b86f58e2c31ba1c9d22976be2a1dcebf78`
**End HEAD:** `4db3217c4ef278c753b0505870d1c285460477ea`（实现提交 `4db3217`；本报告的状态记录为后续 `docs(phase7)` 提交）
**Status:** `IMPLEMENTED`（等待独立验收；本报告不宣布 ACCEPTED）

## 1. 前置条件确认

Phase 6 已由独立复验 **ACCEPTED**（`docs/phase6-independent-reacceptance.md`，`STATUS.md` Phase 状态表 Phase 6 行为 `ACCEPTED`），因此 Phase 7 解封并按规范记录 Start HEAD 后进入 `IN_PROGRESS`。

> 文档不一致说明：`STATUS.md` 原 “## Phase 6” 明细段仍保留首次验收的 `FAILED` 文案，与总表和复验报告矛盾。本次已按规范第 8 条修正明细段，保留首次 REJECTED 的历史记录，不删除失败事实。

## 2. 实现内容

### 2.1 领域模型（`lib/domain/resources/`，纯 Dart）

- `section_control.dart`
  - `SectionGenerationState`：`pending / generating / generated / validating / completed / failed / cancelled`，`fromStorage` 对未知值抛错，不再用裸字符串管理状态。
  - `SectionValidationState`：`unvalidated / validating / valid / invalid`。
  - `SectionGenerationStateMachine`：唯一合法转移表 + `advance()`，非法边抛 `SectionStateTransitionException`；`completed → generating` 明确支持“重新生成”。
  - `SectionControlEntry`：Section 级视图实体，含 `id / resourceId / title / summary / orderIndex / status(NodeStatus) / generationState / validationState / validationMessage / content / partCount / createdAt / updatedAt / updatedAtToken / validatedAt`。
  - `SectionControlPage`（分页结果）、`SectionValidationIssue`、`SectionValidationResult`。
  - `SectionGenerationRollup`：由 Phase 5 的 Part 任务状态推导 Section 生成态，优先级 `active > failed > cancelled > pending > completed`；无任务时按是否有正文判定 `generated / pending`。
  - `SectionContentValidator`：结构性校验（无 Part、空正文、单 Part 超 `ResourceLimits.maxPartCharacters`）。

- `section_generation_binding.dart`
  - `SectionGenerationBinding(generationId, resourceId, sectionId, partId)` + `SectionBindingField` + `SectionGenerationBindingException`。
  - `validatePatch()` / `validateResponse()` 对 Phase 5 的 `ResourceGenerationPatch` / `PartGenerationResponse` 做四元绑定校验，逐字段报错，**不重新定义协议**。

- `resource_edit_command.dart`
  - 密封 `ResourceEditCommand`：`CreateSectionCommand`、`RenameSectionCommand`、`UpdateSectionCommand`、`MoveSectionCommand`、`DeleteSectionCommand`、`UpdatePartCommand`、`MovePartCommand`、`DeletePartCommand`、`RegenerateSectionCommand`。
  - 每个变更命令携带 `expectedUpdatedAt` 乐观锁令牌；AI 命令只携带受限 `instruction`，没有“整资源一次调用”的命令。
  - `AiRewriteMode { regenerate, rewrite, expand, condense }` 带 prompt 指令；`regenerate` 指令为空，保证与原生成 prompt 逐字一致。
  - `ResourceEditCommandValidator`：标题/摘要/指令长度、空标题、缺令牌、负索引、Part 正文预算、空更新等结构校验，不做任何 I/O。

- `section_control_events.dart`
  - 密封 `SectionControlEvent`：`SectionCreated / SectionUpdated / SectionMoved / SectionDeleted / SectionGenerationStarted / SectionGenerationCompleted / SectionGenerationFailed / SectionValidationStarted / SectionValidationPassed / SectionValidationFailed / SectionValidationReset`。

- `section_control_repository.dart`：持久化边界接口（分页读取、单节读取、Part 聚合、任务读取、带令牌写校验结果）。

### 2.2 数据库变化（migration v38）

- `DatabaseService.schemaVersion` 由 37 提升为 38。
- 新增 `createV38Schema()` 与幂等步骤 `addSectionControlColumns()`，为 `resource_sections` 增加：
  - `validation_state TEXT NOT NULL DEFAULT 'unvalidated'`
  - `validation_message TEXT NOT NULL DEFAULT ''`
  - `validated_at TEXT`（可空）
- `migrateStepByStep` 增加 `v37 → v38` 步骤；全新安装与恢复路径改用 `createV38Schema`。
- 旧 migration 未修改；步骤使用既有 `safeAddColumn`（表不存在/列已存在自动跳过），可重复执行。项目无 downgrade 规范，故未新增 downgrade。
- **未新增** `generation_state` 列的理由：Section 生成态完全可由 Phase 5 的 `resource_generation_tasks` 与已提交正文推导（`SectionGenerationRollup`），落库会与任务表分叉；`validation_state` 无法推导（手工新增 Section 无任务），因此持久化。

### 2.3 业务逻辑（`lib/application/resources/`）

- `section_control_service.dart`：所有 Section 操作的唯一入口。
  - 查询：`listSections`（分页，`limit` 上限 `maxPageSize=100`）、`readSection`。
  - 命令：`createSection`、`updateSection`（重命名/更新摘要）、`moveSection`、`deleteSection`、`updatePart`、`deletePart`、`movePart`。
  - 校验：`validateSection` 读单节全部 Part → `SectionContentValidator` → 带令牌写回校验结果并发出事件。
  - 生成：`regenerateSection` 读取该 Section 的 Phase 5 任务，逐个通过 `SectionRegenerationExecutor` 重跑；无任务直接拒绝（不新增第二条生成路径）。
  - 编辑正文/删除 Part/调整顺序会将已存在的校验结果重置为 `unvalidated` 并发 `SectionValidationReset`，避免展示过期"验证通过"。
  - `dispose()` 仅释放内部创建的 bus。
- `section_control_event_bus.dart`：广播事件流 + 有界（默认 200）有序历史，`SectionControlEventRecord.sequence` 单调递增，保证可追踪/可恢复/可测试。
- `section_regeneration.dart`：`SectionRegenerationExecutor` 端口 + request/outcome，使 Service 不直接依赖 LLM。
- `part_generation_coordinator.dart`（增量改动）：`retrySinglePart` / `_generateSinglePart` 增加可选 `userInstruction`，默认空串时 prompt 与 Phase 5 完全一致。
- `part_generation_prompt_builder.dart`：仅当 `userInstruction` 非空时追加『用户补充要求』区块，显式限定"不得改变协议字段、ID、输出格式或生成范围"，并按 `maxInstructionLength` 截断；`resource_generation_protocol.dart` 的 `PartGenerationRequest` 增加可选 `userInstruction`。

### 2.4 UI（`lib/features/resource_studio/`）

- `application/use_cases/section_control_runtime.dart`：`SectionControlRuntime` 边界 + `SectionControlServiceRuntime` 生产适配器（UI 不直接碰数据库）。
- `application/use_cases/streaming_section_regeneration_executor.dart`：生产执行器，复用唯一 `StreamingResourceGenerationController`（同一 service/事件流），并在运行期用 `SectionGenerationBinding` 校验每个 `PatchReceived`；跨 Section patch 记为失败。
- `domain/models/section_control_view_state.dart` + `presentation/controllers/section_control_controller.dart`：不可变视图状态 + 变更后重读首页（数据库为唯一事实源），`busySectionIds` 只让被操作行显示 spinner；订阅运行时事件并以 250ms 去抖刷新。
- `presentation/widgets/resource_studio_section_controls.dart`：Section 列表（标题、生成态、校验态、序号、更新时间）+ 操作（生成/重新生成、验证、重命名、上移/下移、删除）；元数据与操作全部使用 `Wrap`，无固定宽度、无横向滚动；重命名/删除对话框；`_RenameSectionDialog` 自持 `TextEditingController`。
- `presentation/pages/resource_studio_page.dart`：在 Studio 主区命令区与 Part 卡片之间嵌入 Section Controls；`Listenable.merge` 同时监听 Studio 与 Section 控制器；资源 id 就绪后加载 Section 列表。Phase 6 的 runtime / 控制器 / 布局结构未被替换。
- `lib/providers/riverpod_providers.dart`：新增 `sectionControlRuntimeProvider`，复用 `resourceStudioRuntimeProvider` 暴露的 controller/sessionRepository（新增两个只读 getter），避免出现第二套生成运行时。
- `resource_studio_runtime.dart` 仅新增两个 getter，不改变既有契约。

## 3. 架构与契约符合性

- 未改动 Phase 0 冻结实体（`Resource` / `ResourceSection` / `ResourcePart` / `NodeId` / `NodeStatus`）。
- 未改动 Phase 5 增量 JSON 协议：patch 字段、解析、累加器、提交绑定均未变；Phase 7 只新增可选的 Part 级用户指令文本通道与 Section 级绑定校验。
- Phase 6 Resource Studio 的 runtime/controller/page/outline/part card 结构保留，Section Controls 作为增量面板接入。
- 所有 Section 写入经 `SectionControlService` → `IResourceTreeRepository` / `ISectionControlRepository`，UI 不直接访问数据库。
- 乐观锁：所有变更命令携带 `expectedUpdatedAt`；校验结果写回使用读取到的 token；校验写回不改 `updated_at`（校验是历史记录而非内容编辑，避免使无关的编辑令牌失效）。

## 4. 测试

新增/修改测试文件：

| 层 | 文件 | 覆盖 |
| --- | --- | --- |
| Model | `test/domain/resources/section_control_test.dart` | 状态解析、终态/进行态判定、状态机合法与非法转移、自转移幂等、rollup 优先级、内容校验、entry/page 语义 |
| Protocol | `test/domain/resources/section_generation_binding_test.dart` | generationId / resourceId / sectionId / partId 不匹配拒绝、response 校验、绑定覆盖语义 |
| Command | `test/domain/resources/resource_edit_command_test.dart` | 合法命令、空标题、标题超限、缺令牌、负索引、空更新、正文超预算、指令超限、AI 模式指令 |
| Database | `test/services/database_migration_v38_test.dart` | 全新安装 v38 列与默认值、v37→v38 迁移保留旧数据、列步骤幂等 |
| Database | `test/application/resources/database_migration_v36_test.dart`（修改） | 版本断言由固定 37 改为跟随 `schemaVersion` |
| Repository | `test/services/section_control_repository_test.dart` | 分页读取与总数、非法分页参数、单节读取、Part 聚合与预览截断、按 Section 读任务、单节全量 Part、校验写回与失效令牌冲突 |
| Service | `test/application/resources/section_control_service_test.dart` | 分页上限、创建/重命名/并发令牌拒绝/摘要更新/移动（含无变化不发事件）/越权移动拒绝/软删除、内容编辑重置校验、校验通过/不通过与事件、无任务拒绝生成、生成成功、指令透传、执行器 sectionId 不匹配拒绝、执行器失败中止、事件总线序号与历史上限 |
| UI | `test/widget/resource_studio_section_controls_test.dart` | 320/360/390/412/768/1280 无 overflow、空列表、错误/结果消息、busy 行仅锁自身、验证/重新生成回调、溢出菜单重命名/上移/删除、Studio 集成（渲染/验证/重新生成/新建） |
| UI | `test/widget/resource_studio_test.dart`（修改） | 保持 Phase 6 用例，新增 `sectionControlRuntimeProvider` 覆盖 |

共享测试工具：`test/helpers/responsive_test_helper.dart`（统一 viewport 设置与自动恢复）、`test/helpers/resource_studio_fakes.dart`（可复用 Studio fake，替代原测试内私有 fake）、`test/helpers/section_control_fakes.dart`。

验证命令与结果：

```text
dart format --output=none --set-exit-if-changed .   通过（0 changed）
flutter analyze                                     通过（No issues found）
flutter test test/domain/resources/section_control_test.dart \
  test/domain/resources/section_generation_binding_test.dart \
  test/domain/resources/resource_edit_command_test.dart \
  test/services/section_control_repository_test.dart \
  test/services/database_migration_v38_test.dart \
  test/application/resources/section_control_service_test.dart \
  test/widget/resource_studio_section_controls_test.dart \
  test/widget/resource_studio_test.dart             91 passed
flutter test -r compact                             997 passed（exit 0，1m22s）
```

全量测试未出现既有语义检索性能基准失败；本次变更未引入或遗留失败用例。grep 验证：无测试被跳过、删除或降低预期。

## 5. 已知限制

1. `validation_state = validating` 目前不会被持久化：Phase 7 的校验是同步结构校验，只记录起点事件与最终 `valid/invalid`。异步/语义校验属于后续阶段。
2. Section 级 `generation_state` 为推导值，不落库；若后续需要"手工 Section 的生成态历史"，需在 Phase 9 Revision 体系中引入，不在本阶段。
3. 手工新增的 Section 没有 Phase 5 生成任务，"生成/重新生成"按钮禁用，服务层也会显式拒绝；这是刻意保留单一路径，而非缺失能力。
4. 每次变更后重读首页（数据库为唯一事实源），会使当前列表回到第 1 页；分页上限 100、默认页 20，代价有界。
5. `rewrite/expand/condense` 通过新增的 `userInstruction` 文本通道影响单 Part prompt；未改变协议。若需结构化改写参数，应由 Phase 8 复核。
6. 未实现容量后台任务、正式 Revision 恢复与回收站页面（Phase 8/9 范围）。

## 6. 全量测试结果

```text
flutter test -r compact
01:22 +997: All tests passed!
exit code 0
```

全量 997 个测试全部通过，无跳过、无删除、无降低预期。Phase 5/6 既有回归（增量协议、流式运行时、Resource Studio、数据库迁移、契约层纯度）均保持通过。

## 7. 主要提交

| Commit | Message | 内容 |
| --- | --- | --- |
| `4db3217` | `feat(phase7): implement section controls` | Phase 7 全部代码与测试（33 个文件） |

## 8. 结论

Phase 7 实现范围内代码、迁移、测试与文档已完成，`flutter analyze` 通过，定向与全量测试结果见上。**本报告不宣布 Phase 7 完成或 ACCEPTED**；是否进入独立验收由审计 Agent 依据本报告、commit diff 与测试结果判断。
