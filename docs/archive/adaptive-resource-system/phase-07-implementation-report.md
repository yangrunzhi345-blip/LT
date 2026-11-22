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
  - `SectionValidationState`：`unvalidated / validating / valid / invalid / stale`（`stale` 表示曾有过结论、但其描述的内容此后已被改写；由 `afterContentChange` 规则产生）。
  - `SectionGenerationStateMachine`：唯一合法转移表 + `advance()`，非法边抛 `SectionStateTransitionException`；`completed → generating` 明确支持“重新生成”。
  - `SectionControlEntry`：Section 级视图实体，含 `id / resourceId / title / summary / orderIndex / status(NodeStatus) / generationState / validationState / validationMessage / content / partCount / hasGenerationTasks / createdAt / updatedAt / updatedAtToken / validatedAt`。
  - `SectionControlPage`（分页结果）、`SectionValidationIssue`、`SectionValidationResult`。
  - `SectionGenerationRollup`：由 Phase 5 的 Part 任务状态推导 Section 生成态，优先级 `active > failed > cancelled > pending > completed`；无任务时按是否有正文判定 `generated / pending`。
  - `SectionContentValidator`：结构性校验（无 Part、空正文、单 Part 超 `ResourceLimits.maxPartCharacters`）。

- `section_generation_binding.dart`
  - `SectionGenerationBinding(generationId, resourceId, sectionId, partId)` + `SectionBindingField` + `SectionGenerationBindingException`。
  - `validatePatch()` / `validateResponse()` 对 Phase 5 的 `ResourceGenerationPatch` / `PartGenerationResponse` 做四元绑定校验，逐字段报错，**不重新定义协议**。

- `resource_edit_command.dart`
  - 密封 `ResourceEditCommand`：`CreateSectionCommand`、`RenameSectionCommand`、`UpdateSectionCommand`、`MoveSectionCommand`、`DeleteSectionCommand`、`UpdatePartCommand`、`MovePartCommand`、`DeletePartCommand`、`RegenerateSectionCommand`。
  - 每个变更命令都要求 `expectedUpdatedAt` 乐观锁令牌（含 `RegenerateSectionCommand`，Phase 7 remediation F1 修复）；只有创建命令没有前置版本。AI 命令只携带受限 `instruction`，没有“整资源一次调用”的命令。
  - `AiRewriteMode { regenerate, rewrite, expand, condense }` 带 prompt 指令；`regenerate` 指令为空，保证与原生成 prompt 逐字一致。
  - `ResourceEditCommandValidator`：标题/摘要/指令长度、空标题、缺令牌（含 regenerate）、负索引、Part 正文预算、空更新等结构校验，不做任何 I/O。

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
  - 生成：`regenerateSection` 校验命令令牌与持久化 Section 令牌一致后，读取该 Section 的 Phase 5 任务，逐个通过 `SectionRegenerationExecutor` 重跑；无任务直接拒绝（不新增第二条生成路径）。
  - 编辑正文/删除 Part/调整顺序会将已存在的校验结果重置为 `unvalidated` 并发 `SectionValidationReset`，避免展示过期"验证通过"。
  - `dispose()` 仅释放内部创建的 bus。
- `resource_tree_repository_impl.dart`（Phase 7 remediation F2）：所有 Part 变更路径（`updatePart`、`softDeleteNode(PartId)`、`reorderParts`、`_appendPart`、`_updatePartContent`、`_renameNode`/`_archiveNode`/`_reorderNode` 的 Part 分支）在同一事务内刷新所属 `resource_sections.updated_at`，使 Section 令牌能感知 Part 编辑。顺带修复 `_sectionRow` 曾返回 Section 行导致 `row['section_id']` 恒为 null 的既有缺陷（现为 `_sectionIdOfPart`）。
- `section_control_event_bus.dart`：广播事件流 + 有界（默认 200）有序历史，`SectionControlEventRecord.sequence` 单调递增，保证可追踪/可恢复/可测试。
- `section_regeneration.dart`：`SectionRegenerationExecutor` 端口 + request/outcome，使 Service 不直接依赖 LLM。
- `part_generation_coordinator.dart`（增量改动）：`retrySinglePart` / `_generateSinglePart` 增加可选 `userInstruction`，默认空串时 prompt 与 Phase 5 完全一致。
- `part_generation_prompt_builder.dart`：仅当 `userInstruction` 非空时追加『用户补充要求』区块，显式限定"不得改变协议字段、ID、输出格式或生成范围"，并按 `maxInstructionLength` 截断；`resource_generation_protocol.dart` 的 `PartGenerationRequest` 增加可选 `userInstruction`。

### 2.4 UI（`lib/features/resource_studio/`）

- `application/use_cases/section_control_runtime.dart`：`SectionControlRuntime` 边界 + `SectionControlServiceRuntime` 生产适配器（UI 不直接碰数据库）；`regenerateSection` 要求并透传 `expectedUpdatedAt`。
- `application/use_cases/streaming_section_regeneration_executor.dart`：生产执行器，经 `SectionRegenerationRuntimePort` 复用唯一 `StreamingResourceGenerationController`（同一 service/事件流，`StreamingRegenerationRuntimeAdapter` 为生产适配器），并在运行期用 `SectionGenerationBinding` 校验每个 `PatchReceived`；跨 Section / 资源 / generation 的 patch 记为失败。该端口同时使执行器可被单元测试（Phase 7 remediation F4）。
- `domain/models/section_control_view_state.dart` + `presentation/controllers/section_control_controller.dart`：不可变视图状态 + 变更后重读首页（数据库为唯一事实源），`busySectionIds` 只让被操作行显示 spinner；订阅运行时事件并以 250ms 去抖刷新。
- `presentation/widgets/resource_studio_section_controls.dart`：Section 列表（标题、生成态、校验态、序号、更新时间）+ 操作（生成/重新生成、验证、重命名、上移/下移、删除）；元数据与操作全部使用 `Wrap`，无固定宽度、无横向滚动；重命名/删除对话框；`_RenameSectionDialog` 自持 `TextEditingController`。生成按钮按 `SectionControlEntry.hasGenerationTasks` 门控（Phase 7 remediation F5），不再使用 `partCount`。
- `presentation/pages/resource_studio_page.dart`：在 Studio 主区命令区与 Part 卡片之间嵌入 Section Controls；`Listenable.merge` 同时监听 Studio 与 Section 控制器；资源 id 就绪后加载 Section 列表。Phase 6 的 runtime / 控制器 / 布局结构未被替换。
- `lib/providers/riverpod_providers.dart`：新增 `sectionControlRuntimeProvider`，复用 `resourceStudioRuntimeProvider` 暴露的 controller/sessionRepository（新增两个只读 getter），避免出现第二套生成运行时。
- `resource_studio_runtime.dart` 仅新增两个 getter，不改变既有契约。

## 3. 架构与契约符合性

- 未改动 Phase 0 冻结实体（`Resource` / `ResourceSection` / `ResourcePart` / `NodeId` / `NodeStatus`）。
- 未改动 Phase 5 增量 JSON 协议：patch 字段、解析、累加器、提交绑定均未变；Phase 7 只新增可选的 Part 级用户指令文本通道与 Section 级绑定校验。
- Phase 6 Resource Studio 的 runtime/controller/page/outline/part card 结构保留，Section Controls 作为增量面板接入。
- 所有 Section 写入经 `SectionControlService` → `IResourceTreeRepository` / `ISectionControlRepository`，UI 不直接访问数据库。
- 乐观锁：所有变更命令要求 `expectedUpdatedAt`（含 regenerate，remediation F1）；校验结果写回使用读取到的 token；校验写回不改 `updated_at`（校验是历史记录而非内容编辑，避免使无关的编辑令牌失效）；Part 编辑推进所属 Section 令牌（remediation F2，详见 5.1）。

## 4. 测试

新增/修改测试文件：

| 层 | 文件 | 覆盖 |
| --- | --- | --- |
| Model | `test/domain/resources/section_control_test.dart` | 状态解析、终态/进行态判定、状态机合法与非法转移、自转移幂等、rollup 优先级、内容校验、entry/page 语义 |
| Protocol | `test/domain/resources/section_generation_binding_test.dart` | generationId / resourceId / sectionId / partId 不匹配拒绝、response 校验、绑定覆盖语义 |
| Command | `test/domain/resources/resource_edit_command_test.dart` | 合法命令、空标题、标题超限、缺令牌（含 regenerate）、负索引、空更新、正文超预算、指令超限、AI 模式指令 |
| Database | `test/services/database_migration_v38_test.dart` | 全新安装 v38 列与默认值、v37→v38 迁移保留旧数据、列步骤幂等 |
| Database | `test/application/resources/database_migration_v36_test.dart`（修改） | 版本断言由固定 37 收紧为固定 38（remediation F3 已恢复严格断言） |
| Repository | `test/services/section_control_repository_test.dart` | 分页读取与总数、非法分页参数、单节读取、Part 聚合与预览截断、按 Section 读任务、单节全量 Part、校验写回与失效令牌冲突、Section 令牌随 Part 更新/删除/重排/patch 移动（F2） |
| Repository | `test/services/resource_tree_repository_test.dart`（修改） | “更新一个 Part 不改写兄弟 Part”新增 Section 令牌必须移动的精确断言（F2 契约变化，非放宽） |
| Service | `test/application/resources/section_control_service_test.dart` | 分页上限、创建/重命名/并发令牌拒绝/摘要更新/移动（含无变化不发事件）/越权移动拒绝/软删除、内容编辑重置校验、校验通过/不通过与事件、无任务拒绝生成、令牌缺失/过期拒绝且不启动任何 Part（F1）、生成成功、指令透传、执行器 sectionId 不匹配拒绝、执行器失败中止、事件总线序号与历史上限 |
| Protocol | `test/application/resources/streaming_section_regeneration_executor_test.dart` | 真实执行器：正确绑定成功、sectionId/resourceId/generationId/partId 不匹配拒绝、无关事件忽略、校验失败与抛错转为失败结果、无会话拒绝（F4） |
| UI | `test/widget/resource_studio_section_controls_test.dart` | 320/360/390/412/768/1280 无 overflow、空列表、错误/结果消息、busy 行仅锁自身、验证/重新生成回调、溢出菜单重命名/上移/删除、生成按钮门控（手工有 Part 无任务→禁用、有任务已完成→重新生成、空 Section→禁用，F5）、Studio 集成（渲染/验证/重新生成/新建） |
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
flutter test -r compact                             1016 passed（exit 0，1m24s，remediation 后）
```

全量测试未出现既有语义检索性能基准失败；本次变更未引入或遗留失败用例。

如实说明测试基线的两处变化（Phase 7 remediation F2/F3）：

- `database_migration_v36_test.dart` 的精确版本断言在初次实现时曾被放宽为 `>= 37`；remediation 已恢复为固定 `38`，并保留“版本提升必须显式更新断言”的注释。
- `resource_tree_repository_test.dart` 的 “updating one part leaves the other parts untouched” 断言由“Section 行完全不变”改为“仅 Section 的 `updated_at` 可变、其余列逐列不变”。这是 remediation F2 有意引入的契约变化，断言强度未降低（额外增加了逐列不变检查）。

除此之外无测试被跳过、删除或放宽。

## 5. 已知限制

1. `validation_state = validating` 目前不会被持久化：Phase 7 的校验是同步结构校验，只记录起点事件与最终 `valid/invalid`。异步/语义校验属于后续阶段。
2. Section 级 `generation_state` 为推导值，不落库；若后续需要"手工 Section 的生成态历史"，需在 Phase 9 Revision 体系中引入，不在本阶段。
3. 手工新增的 Section 没有 Phase 5 生成任务，"生成/重新生成"按钮按 `hasGenerationTasks` 禁用并给出 tooltip，服务层也会显式拒绝；这是刻意保留单一路径，而非缺失能力。
4. 每次变更后重读首页（数据库为唯一事实源），会使当前列表回到第 1 页；分页上限 100、默认页 20，代价有界。
5. `rewrite/expand/condense` 通过新增的 `userInstruction` 文本通道影响单 Part prompt；未改变协议。若需结构化改写参数，应由 Phase 8 复核。
6. 未实现容量后台任务、正式 Revision 恢复与回收站页面（Phase 8/9 范围）。

### 5.1 Section 版本（`updated_at`）推进策略（remediation F2 + B1 remediation）

存在**两类**写入者，二者都已在**同一事务内**同步所属 Section：

1. 树仓库路径（`ResourceTreeRepositoryImpl`，remediation F2）：`updatePart`、`softDeleteNode(PartId)`、`reorderParts`、`_appendPart`、`_updatePartContent`、以及 `_renameNode` / `_archiveNode` / `_reorderNode` 的 Part 分支，经 `_bumpSection` 刷新 `resource_sections.updated_at`。
2. Phase 5 流式提交路径（`PartGenerationTaskRepositoryImpl.commitPartContent` → `_syncOwningSection`，B1 remediation）：在写入 `resource_parts.content/content_hash`、刷新 `resources.updated_at` 的同一事务内，刷新 `resource_sections.updated_at` 并按下述规则处理校验结论。Section 归属取自 **`resource_parts.section_id`**（Part → Section 的唯一权威映射），不通过 Section 行反查自己的 id。

校验结论失效规则（单一来源：`SectionValidationState.afterContentChange`）：

- 已记录的结论（`valid` / `invalid`）在内容变化后降级为 `stale`；`unvalidated` / `validating` / `stale` 保持不变，规则幂等。
- 仅在结论真正被降级时同时清空 `validation_message`；`updated_at` 始终推进。
- `validated_at` 保留（记录该结论产生的时间），不再被 UI 展示为有效结论。

其余约束：

- 校验结果写回（`updateSectionValidation`）**不**推进 `updated_at`：校验是历史记录，不是内容编辑；推进它会让无关的编辑令牌失效。
- 直接后果：任何 Part 内容变化都会使此前读取的 Section 令牌过期，因此调用方必须在操作前重新读取令牌（`SectionControlService.updatePart/deletePart/movePart` 已在内部重读后写回失效）。这是有意的"宁可拒绝也不覆盖"。
- 附带修复（F2）：原 `_sectionRow` 返回的是 Section 行，导致 Part 删除路径取 `row['section_id']` 恒为 null（既不刷新 Section 也不刷新 Resource）；已改为 `_sectionIdOfPart`。
- 已知不一致（保持现状、未扩大范围）：`_reorderNode` 的 Part 分支会刷新 Section，但仍像改动前一样不刷新 Resource 的 `updated_at`。

### 5.2 流式执行器测试覆盖（remediation F4 + B1 remediation）

- `StreamingSectionRegenerationExecutor` 由 `test/application/resources/streaming_section_regeneration_executor_test.dart` 直接覆盖（真实执行器 + `SectionRegenerationRuntimePort` fake）：正确绑定成功、sectionId / resourceId / partId 不匹配拒绝、同一运行内出现被取代 generation 的 patch 被拒、无关事件忽略、校验失败与抛错转为失败结果、无会话拒绝。
- 绑定语义：runtime 事件里的 `generationId` 是 **session id**，而 patch 携带的是 Phase 5 每次尝试生成的**协议 generation id**。执行器以首个 patch 的协议 id 为本次运行的基准并锁定，后续 patch 必须携带同一 id；resource / section / part 则对每次 patch 都与请求比对。（B1 remediation 修正：此前用事件 id 与 patch id 比较，导致真实链路每次都被判为 generationId 不匹配。）
- 端到端覆盖：`test/application/resources/section_consistency_streaming_regeneration_test.dart` 走**完整生产链路**（executor → adapter → controller → service → coordinator → `commitPartContent`），断言 Section 令牌推进、结论降级为 `stale`、且新令牌仍可写入。
- 仍未覆盖：真实 `LlmGateway`/网络（沿用 Phase 5/6 既有的 headless 测试边界，用符合协议的 completer 代替）。

### 5.3 剩余并发考量（remediation F1/F2 + B1 remediation）

- `regenerateSection` 在**启动前**比对命令令牌与持久化 Section 令牌；比对与第一个 Part 开始之间存在 TOCTOU 窗口。这是有意的：重新生成本就会替换 Part 正文，运行期间不再二次校验；防线保证的是"不基于过期读发起重生成"。
- 令牌比对不是原子领取（没有 `UPDATE ... WHERE updated_at = ?` 声明式抢占）。若后续要求严格串行化，可在 Phase 9 Revision 边界引入原子 claim。
- `validateSection` 的"读令牌 → 读 Parts → 写结论"竞态**已对两类写入者关闭**：树仓库 Part 编辑与流式提交都会推进 Section 令牌，因此基于过期读取的结论写回会被 `ResourceTreeConflictException` 拒绝。
- 跨进程/多实例并发不在本阶段范围内：项目当前仍是单进程 SQLite 访问模型。
- **已披露的未修复限制（超出 B1 范围，交由最终审计裁定）**：`PartTaskStatus.completed` 是终态（`PartTaskStateMachine` 仅允许自转移），`startAttempt` 对已完成任务直接抛 `StateError('任务已完成，禁止重新发起生成')`，而 `markTaskReady` 只被失败任务的重试分支调用。因此对**已全部生成完成**的 Section 执行"重新生成"会在 `startAttempt` 处失败（UI 会显示该错误）。Phase 7 当前未提供重置已完成任务的机制。详见 `phase-07-b1-remediation-report.md` 第 6 节。

## 6. 全量测试结果

```text
flutter test -r compact
01:24 +1016: All tests passed!
exit code 0
```

全量 1016 个测试全部通过（初次实现为 997，remediation 新增 19 个用例），无跳过、无删除。Phase 5/6 既有回归（增量协议、流式运行时、Resource Studio、数据库迁移、契约层纯度）均保持通过。测试基线的两处有意变化见第 4 节说明。

## 7. 主要提交

| Commit | Message | 内容 |
| --- | --- | --- |
| `4db3217` | `feat(phase7): implement section controls` | Phase 7 全部代码与测试（33 个文件） |
| `4e6ac96` | `fix(phase7): remediate F1-F6 from the audit findings` | F1–F6 修复，见 `phase-07-remediation-report.md` |

## 8. 结论

Phase 7 实现范围内代码、迁移、测试与文档已完成，并通过 Phase 7 remediation 修复 F1–F6；`flutter analyze` 与全量 1016 个测试通过。**本报告不宣布 Phase 7 完成或 ACCEPTED**；是否进入独立验收由审计 Agent 依据本报告、remediation 报告、commit diff 与测试结果判断。
