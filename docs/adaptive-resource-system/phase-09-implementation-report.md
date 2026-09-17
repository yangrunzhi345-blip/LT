# Phase 9 — Revision、自动保存与回收站实施报告

- 阶段：Phase 9
- 状态：`IMPLEMENTED`（等待独立验收；本报告不宣布 `ACCEPTED`）
- 执行 Agent：executor-agent（CodeBuddy CLI）
- 开始时间：2026-09-17
- 完成时间：2026-09-17
- Start HEAD：`dbd2303`
- End HEAD：见 `STATUS.md`（提交后回填）

## 1. 本阶段要解决的问题

Phase 5–8 已经可以生成、重写、压缩资源内容，但没有“可恢复边界”：

- 压缩只产出候选（`applied_at` 恒为 `NULL`），没有合法发布路径；
- 重新生成会直接覆盖 `resource_parts.content`，覆盖前的正文只存在于旧数据里，没有版本记录；
- 删除是 `softDeleteNode`，但没有任何地方记录“删了什么、从哪删的、多久之内可恢复”；
- 编辑器只有显式保存，没有 debounce / final flush，退出即丢失未保存输入。

Phase 9 为手动编辑、AI 生成、重新生成、语义压缩、删除、退出/崩溃建立统一的可恢复边界。

## 2. 数据库

**schema v40 → v41**，非破坏性、幂等：

| 表 | 作用 |
| --- | --- |
| `resource_revisions` | 不可变 revision 元数据 + head 指针（`is_head`） |
| `resource_revision_nodes` | revision 相对父 revision 的**节点增量** |
| `resource_autosaves` | 尚未写入正文树的编辑草稿（write-ahead journal） |
| `resource_trash` | 删除元数据（原父节点、原排序、原因、保留期） |

关键约束：

- `idx_resource_revisions_head` 是 `(resource_id, kind) WHERE is_head = 1` 的**部分唯一索引**，
  head 唯一性由数据库保证，而不是靠调用方自觉。
- `resource_revision_nodes` 对 `resource_revisions` 建外键并 `ON DELETE CASCADE`。
- `idx_resource_autosaves_node`、`idx_resource_trash_active_node` 都是**部分唯一索引**，
  使“同一节点至多一条未解决草稿/回收站记录”成为数据库事实，重复 checkpoint 与重复删除
  收敛为一行而不是累积。
- 迁移只做 `CREATE TABLE / INDEX IF NOT EXISTS`，不重写任何既有行；
  升级时 FK 被关闭，因此迁移不依赖级联，也不搬迁数据。

## 3. Revision 架构

### 3.1 增量链，而不是每次复制整棵树

`resource_revision_nodes` 只保存**相对父 revision 变化的节点**，`is_removed = 1` 表示墓碑。
还原历史版本时从根 revision（`parent_revision_id IS NULL`）逐级 `applyDelta` 即可重建任意状态。

- 单节点编辑只写 1 行增量，与资源大小无关（测试断言“只包含被改动的那个节点”）。
- `ResourceRevisionMath.diff / applyDelta / encodeState` 是纯 Dart，可脱离数据库单测。
- 契约层保持 Phase 0 纯净性：`resource_revision.dart` 不 import Flutter/SQLite/上层目录，
  也**没有**使用 `jsonEncode/jsonDecode/toJson`（手写稳定的 `_stableEncode`），
  因此 Phase 0 的结构守护测试继续通过。

### 3.2 不变量：head 始终等于当前存活树

所有写路径在改动树之后**必须**再抓一次 revision。抓取是幂等的：当存活树已经等于 head 时，
`captureInTransaction` 返回既有 head 且不写任何行，因此“防御性 before 抓取”在正常情况下零成本。

这条设计有一个重要性质：**漏掉一个 hook 只会让下一次 revision 变得更粗，而不会丢数据**。
`beginLossyOperation` 的测试显式验证了这一点（未记录的漂移会被下一次抓取覆盖进 history）。

### 3.3 head 切换与业务写入同一事务

- 生成提交：`commitPartContent` 在**自己的事务内**调用 revision 边界。
- 手动编辑：`PartContentCommitService.applyContent` 一个事务内完成
  before 抓取 → 校验降级 → 正文写入 → 生成任务重置 → after 抓取 → 消费草稿行。
- 压缩发布：`CompressionPublisher.publish` 一个事务内完成
  `applied_at` CAS → before 抓取 → 正文替换 → 任务重置 → after 抓取。
- 恢复：`restoreRevision` 一个事务内完成 before 抓取 → 应用目标状态 → 任务重置 → after 抓取。

失败即整体回滚：测试断言“失败的恢复不会留下任何 revision”“被拒绝的提交不会留下 revision”。

### 3.4 revision cause

`RevisionCause { manualSave, generation, regeneration, compression, restore, migration, deletion }`。

生成提交的 cause 由**数据**推导而不是由调用方声明：写入前该 Part 是否已有非空正文，
决定这次是 `generation` 还是 `regeneration`。

### 3.5 assembly 指针

Phase 0 冻结的 `ResourceRevisionSelector` 由 `ResourceRevisionService` 实现：

- `latestHead()` 只返回 `kind = latestHead` 的 head，不会漂移到已发布版本。
- `publishAssemblyRevision()` 生成/复用一个 `kind = assembly` 的 revision 并把 assembly head
  指过去；两条链彼此独立，发布**不会**移动 latest-head 指针。
- `select()` 只解析**指针新鲜度**（assembly 指针的 content hash 是否仍等于 latest head）。
  它刻意不做 Adventure 消费就绪判断——那属于 Phase 10。

## 4. 自动保存

### 4.1 分层

```text
敲键        → 内存 buffer（schedule 完全不碰数据库）
输入暂停    → journal 行（独立事务，先落盘）
            → 一个事务：Part 正文 + Section 校验 + revision head + 删除 journal 行
```

`schedule` 是同步且无 IO 的；测试用真实写入计数器断言
「25 次输入 → 0 次 journal 写入、0 次正文写入」，暂停后「25 次输入 → 1 次 journal 写入、1 次正文写入」。

### 4.2 debounce 参数

`AutosavePolicy.debounce = 700ms`、`maxBufferedAge = 5s`，集中在 domain 层，
不允许页面各自写魔法毫秒值。`maxBufferedAge` 保证连续快速输入也会被周期性 checkpoint，
不会因为“永远不暂停”而永久停留在内存里。

### 4.3 强制 final flush 边界

| 边界 | 触发 |
| --- | --- |
| dispose / 编辑器关闭 | `ResourceAutosaveService.dispose()`（Widget `dispose` 触发） |
| 页面离开 / 完成编辑 | `pageLeave` |
| 取消生成 | `cancel` |
| 生成异常 | `generationError` |
| 应用退到后台/失焦 | `WidgetsBindingObserver.didChangeAppLifecycleState` → `appLifecycle` |
| 显式保存 | `manual` |

`AutosaveFlushTrigger.isForced` 把“定时器触发”和“终止边界触发”区分开，
后者保证即使 debounce timer 尚未到期也会落盘。

### 4.4 Streaming 语义

流式生成仍然只在**校验通过的 Part** 落库（Phase 5 既有行为，本阶段没有新增第二条写路径）：

- 每个成功 Part 的内容由 `commitPartContent` 原子提交，并同时记录 revision；
- 未确认的 chunk 没有 journal 行，也没有 `completed` 任务状态，
  因此崩溃重启后不会伪装成已完成；
- 取消/失败时已提交内容保留，未提交内容不留痕（测试用 `cancelTasks` / `recordFailedAttempt` 验证）。

## 5. 回收站

### 5.1 删除路径

```text
live → 写回收站行 → deleted_at 软删除
```

一个事务内：抓 before revision → 写回收站行 → 软删除 → 抓 after revision。
资源删除时资源行变软删除，因此 after 抓取是 no-op，**head 停留在删除前状态**，
这正是“已删除资源仍可整体恢复”的原因。

### 5.2 恢复规则

| 情形 | 结果 |
| --- | --- |
| 资源 | 恢复自身与其全部子节点（按同一次删除的时间戳） |
| Section | 恢复到原 Resource 与原 `sort_order` |
| Part，原 Section 仍存活 | 恢复到原 Section 与原顺序 |
| Part，原 Section 不存在或仍在回收站 | **回退**：在 Resource 根下新建 Section 并放入，`TrashRestorePlacement.recreatedSectionUnderRoot` |
| Part/Section 自身行已被永久删除 | 显式失败，条目保留在回收站，不静默丢数据 |
| 重复恢复 | 幂等：`restored_at` 已置位时返回 `alreadyRestored`，不重复建内容 |

回退恢复**永不静默**：`TrashRestoreResult.userMessage` 会被回收站面板直接展示。

删除只影响 `deleted_at` 相同的节点：先单独删除、后被父节点级联删除的 Part 保留自己的时间戳，
恢复父节点不会把它一起复活（测试覆盖）。

### 5.3 永久删除

永久删除是**显式二次操作**：

- UI 必须在确认对话框之后才调用；
- 服务层拒绝删除仍存活的节点（陈旧回收站行无法删除活数据）；
- 重复调用幂等。

### 5.4 清理策略

- `purgeExpired()` 只删除 `restored_at IS NULL AND expires_at <= now` 的条目；
  保留期内的记录、已恢复的记录永不触碰。
- 保留期集中在 `TrashRetentionPolicy`（30 天）。
- 清理入口放在**用户打开回收站时**，而不是应用启动时：保留期 bug 只能影响用户已经打开展示的回收站。

## 6. 清理（Revision）

`pruneRevisions` 只删除“超过保留期且不再被需要”的 revision，并且：

1. 只删除链的**最老前缀**；
2. 删除前把第一个保留的 revision **根化**（用完整快照替换其增量、清空 parent），
   因此存活链永远可重放；
3. 永不删除当前 `latestHead` head；
4. 永不删除 assembly head 及其链；
5. 永不删除回收站未解决条目引用的 revision；
6. 保留期内的一律不删；
7. 链断裂时**报告并跳过**，不为了“清理成功”而截断历史。

## 7. 并发与一致性保护

| 风险 | 保护 |
| --- | --- |
| 两个 head | `(resource_id, kind) WHERE is_head = 1` 部分唯一索引 |
| 并发抓取 | 头读取、插入、head 翻转在同一个事务 |
| 丢失租约/陈旧更新 | 正文写入一律带 `expectedUpdatedAt`；恢复支持 `expectedUpdatedAt` CAS |
| 并发恢复 | 最后一步 `restored_at IS NULL` 守卫更新，输的一方回滚 |
| 并发发布 | `applied_at IS NULL` 守卫更新，输的一方回滚 |
| 恢复 vs 清理 | 清理只处理已过期条目；恢复以守卫更新收尾 |
| 事务内跨连接读 | 所有事务内读写都走 `DatabaseExecutor` 变体（见 §9） |

## 8. Phase 5–8 回归保护

- 生成提交链路复用了 `commitPartContent` 的既有事务，没有新建第二条写 `resource_parts.content` 的路径。
- 压缩链路仍然只写候选表；发布路径是本阶段新增的**唯一**合法出口。
- `ResourceTreeRepositoryImpl` 仍是三张树表的唯一写入者；
  新增的 `readLiveState / applyRevisionState / reviveNode / purgeNode / reparent` 全部收敛在它内部。
- `SectionControlService` 的 Phase 7 行为在未注入 Phase 9 边界时**逐字不变**（边界参数可空），
  因此 Phase 7 单测无需改动即通过。
- Phase 7 D2（已完成章节不可重新生成）在原方案中被推迟到 Phase 9；
  本阶段提供了受控重置 + 版本回退后，门控放开并附说明文案，对应测试同步更新。

## 9. 中断恢复说明

本次执行曾在实施中途被中断（未提交），恢复后核对仓库状态为：
Start HEAD 仍为 `dbd2303`，全部 Phase 9 代码仅存在于工作区，未提交、未推送。

恢复过程中发现并修复的问题：

- **事务内跨连接读取导致死锁**（真实缺陷，非测试问题）：
  `ResourceRevisionService.restoreRevision` 与 `ResourceTrashService` 在已打开的事务回调里调用了
  非事务版本的仓库方法（`readRevision` / `findEntry` / `findActiveEntryForNode`），
  这些方法通过 `Database` 对象重新入队，而该连接正被同一事务占用，于是永久等待。
  sqflite 只打印 “database has been locked” 警告并挂起，不会报错，因此这类缺陷只能靠真实数据库测试发现。
  修复方式：为 revision / trash 仓库补齐 `...InTransaction(DatabaseExecutor, ...)` 变体，
  服务层在事务内一律使用它们，并在接口上写明“事务内必须使用本变体”。
- 复核了全部新增事务路径（revision capture/restore/publish/prune、trash delete/restore/purge、
  part content commit、autosave flush、compression publish），确认没有其他事务内跨连接调用。

## 10. 新增/修改文件

### 新增（domain）

- `lib/domain/resources/resource_revision.dart`
- `lib/domain/resources/resource_trash.dart`
- `lib/domain/resources/resource_autosave.dart`

### 新增（application）

- `lib/application/resources/resource_revision_repository.dart`
- `lib/application/resources/resource_revision_service.dart`
- `lib/application/resources/resource_trash_repository.dart`
- `lib/application/resources/resource_trash_service.dart`
- `lib/application/resources/resource_autosave_repository.dart`
- `lib/application/resources/resource_autosave_service.dart`
- `lib/application/resources/part_content_commit_service.dart`
- `lib/application/resources/resource_compression_publisher.dart`

### 新增（services）

- `lib/services/repositories/section_validation_boundary.dart`

### 新增（feature UI）

- `lib/features/resource_studio/domain/models/resource_revision_view_state.dart`
- `lib/features/resource_studio/application/use_cases/resource_revision_runtime.dart`
- `lib/features/resource_studio/presentation/controllers/resource_revision_controller.dart`
- `lib/features/resource_studio/presentation/widgets/resource_revision_panel.dart`
- `lib/features/resource_studio/presentation/widgets/resource_studio_part_editor.dart`
- `lib/features/resource_library/domain/models/resource_trash_view_state.dart`
- `lib/features/resource_library/application/use_cases/resource_trash_runtime.dart`
- `lib/features/resource_library/presentation/controllers/resource_trash_controller.dart`
- `lib/features/resource_library/presentation/widgets/resource_trash_sheet.dart`

### 修改

- `lib/services/database_service.dart`（v41 schema 与迁移步骤）
- `lib/services/repositories/resource_tree_repository.dart`（新增 `IResourceTreeRevisionBoundary`）
- `lib/services/repositories/resource_tree_repository_impl.dart`（边界实现；`_idSequence` 改为进程级）
- `lib/services/repositories/section_control_repository_impl.dart`（事务内校验读写变体）
- `lib/application/resources/resource_creation_pipeline.dart`（保存覆盖前/后抓取 revision）
- `lib/application/resources/resource_generation_task_repository.dart`（提交事务内抓取、受控任务重置）
- `lib/application/resources/section_control_service.dart`（接入删除/编辑/重生成边界）
- `lib/application/resources/compression_job_repository.dart`（`applied_at` 读写、可发布候选查询）
- `lib/domain/resources/resource_compression.dart`（`appliedAt` / `isPublishable`）
- `lib/providers/riverpod_providers.dart`（Phase 9 组合根）
- `lib/features/resource_studio/...`（历史面板、正文编辑器、容量面板发布入口、章节门控放开）
- `lib/features/resource_library/...`（回收站入口）

## 11. UI

### Resource Studio

- 新增「版本历史」面板：列表（原因、时间、节点数、字数）、当前标记、逐条「恢复到此版本」、空/加载/错误状态。
- 新增正文编辑器：可编辑 Part、debounce 自动保存、保存状态与冲突提示、「立即保存」「完成编辑」。
  非编辑态仍显示只读卡片并新增「编辑正文」入口。
- 容量面板新增「发布压缩结果（N）」，发布前二次确认，发布后刷新版本历史。

### Resource Library

- 头部「历史与回收站」下拉新增「回收站」入口。
- 回收站面板：列表、恢复、永久删除（二次确认）、空/加载/错误/回退提示。
- 关闭回收站后自动刷新资源列表。

### 响应式

新增/修改的 UI 组件都在 `320×568`、`360×640`、`390×844`、`412×915`、`768×1024`、`1280×800`
下通过 `tester.takeException() == null` 断言，并覆盖长动态文本与 `textScale 1.6`。
所有操作按钮组使用 `Wrap`，没有把动态文本与按钮放进同一个紧凑 `Row`。

## 12. 测试

### 新增测试文件

| 文件 | 覆盖 |
| --- | --- |
| `test/domain/resources/resource_revision_test.dart` | cause、diff/墓碑/顺序、applyDelta 无副作用、state 编码稳定性、树重建、保留策略 |
| `test/domain/resources/resource_trash_test.dart` | 节点类型、原因、身份解析、placement 语义、保留期边界 |
| `test/domain/resources/resource_autosave_test.dart` | debounce 策略、草稿身份保持、恢复判定 |
| `test/application/resources/resource_revision_service_test.dart` | 首次根 revision、幂等抓取、增量、不可变性、head 唯一、assembly 指针、恢复/幂等/回滚/stale、lossy 边界、清理全部保护规则、latestHead |
| `test/application/resources/resource_trash_service_test.dart` | 资源/Section/Part 删除、幂等删除、删除前 revision、恢复各种情形、回退、重复恢复、永久删除、保留期清理、查询 |
| `test/application/resources/resource_autosave_service_test.dart` | 不逐键写库、暂停合并、maxBufferedAge、各终止边界 flush、冲突保留草稿、目标消失丢弃、写入链路副作用、崩溃恢复分类 |
| `test/application/resources/phase9_revision_boundary_test.dart` | 生成/重生成提交边界、stale attempt、取消/失败语义、压缩发布全流程与拒绝路径 |
| `test/application/resources/phase9_concurrency_test.dart` | 12 类交错：autosave×生成/重生成/删除、双恢复、清理×恢复、stale head、发布×抓取、退出/取消/失败/崩溃 |
| `test/application/resources/database_migration_v41_test.dart` | 全新安装、列/索引/head 唯一约束/级联、v40→v41 数据保持、重复迁移 |
| `test/widget/resource_revision_panel_test.dart` | 响应式、状态、恢复动作门控 |
| `test/widget/resource_trash_sheet_test.dart` | 响应式、状态、恢复、永久删除二次确认、忙碌行 |
| `test/widget/resource_studio_part_editor_test.dart` | 响应式、输入缓冲、保存/冲突/丢弃状态、退出与 dispose flush |

### 修改测试

- 迁移测试的 schema 版本钉子（v36/v38/v39/v40 → 41）。
- `test/widget/resource_studio_section_controls_test.dart`：Phase 7 D2 门控用例改为断言
  “Phase 9 之后已完成章节可重新生成”，并新增“生成中禁止再次触发”用例。
- `test/helpers/section_control_fakes.dart`、`test/helpers/resource_capacity_fakes.dart`：
  实现新增的 runtime 方法。

## 13. 验证结果

| 命令 | 结果 |
| --- | --- |
| `dart format --output=none --set-exit-if-changed .` | 464 files / 0 changed |
| `flutter analyze` | No issues found |
| Phase 9 定向测试（上表 12 个文件） | **205 passed / 0 failed** |
| 全量 `flutter test` | **1392 passed / 0 failed**（Phase 8 基线 1186，本阶段净增 206） |
| `git diff --check` | 干净 |

定向测试明细：

| 文件 | 用例数 |
| --- | --- |
| `resource_revision_test.dart` | 18 |
| `resource_trash_test.dart` | 24 |
| `resource_autosave_test.dart` | 10 |
| `resource_revision_service_test.dart` | 32 |
| `resource_trash_service_test.dart` | 28 |
| `resource_autosave_service_test.dart` | 21 |
| `phase9_revision_boundary_test.dart` | 16 |
| `phase9_concurrency_test.dart` | 11 |
| `database_migration_v41_test.dart` | 7 |
| `resource_revision_panel_test.dart` | 19 |
| `resource_trash_sheet_test.dart` | 18 |
| `resource_studio_part_editor_test.dart` | 14 |

Phase 5–8 回归：

- 全量测试包含 Phase 5/6/7/8 的全部既有用例，1392 全绿。
- Phase 5/6/7 冻结文件（`resource_contracts.dart`、`streaming_*`、`part_generation_*`、
  `generation_patch_parser.dart`、`resource_generation_protocol.dart`、`resource_generation_patch.dart`）
  在 `dbd2303..HEAD` 中**零改动**（`git status --short` 复核为空）。
- Phase 8 的压缩链路约束保持：`resource_parts.content` 的唯一新写入者是本阶段新增的
  revision-boundary 路径（`applyRevisionState` / `updatePartInTransaction`），
  压缩 coordinator 本身仍只写候选表。

## 14. 已知问题与限制

1. **章节级压缩候选不可发布**：Phase 8 已知 `section` 候选没有 per-Part 映射（INFO-005）。
   本阶段选择**显式拒绝**而不是猜测切分；候选仍保留，等待后续阶段补齐映射。
2. **契约层 `select()` 只做指针新鲜度**：不判断 Adventure 可消费性，属 Phase 10。
3. **`updateResourceTree`（旧库存档保存）之外仍有未接线写路径**：
   `ResourceBlueprintRepository` 在确认蓝图时创建占位树（首次创建，非覆盖），
   因此不需要 before revision；若后续出现覆盖式写入，必须同样接入边界。
4. **永久删除的 revision 残留**：资源被永久删除后其 revision 链保留（内含最后一份正文）。
   这是刻意的：清理策略按保留期处理，不为“删除”额外销毁历史。
   若产品要求永久删除同时销毁版本历史，需要在 Phase 10/12 明确并实现。
5. **Phase 8 遗留项未在本阶段修复**（A6/A8/A9/A10/A11/A12、R3-M1..M3、INFO-001..006）：
   仍登记在 `STATUS.md` 技术债中。
6. **`historicalRevisionCount`** 仍来自生成尝试计数（Phase 8 已知 A8），
   本阶段未切换为真实 revision 计数——这属于容量展示口径调整，不在 Phase 9 范围内。

## 15. Deferred Issues

- 章节级压缩候选的 per-Part 映射与发布（需要 Phase 8 候选结构扩展）。
- 永久删除是否级联销毁 revision 历史的产品决策。
- `PartTaskStatus.completed` 的受控重置目前由 revision 边界在每个覆盖路径触发；
  是否需要一个统一的“重置入口”留给 Phase 11 的 UX 收敛评估。
- 回收站清理目前只在打开回收站时运行；若后续要求后台周期清理，需要与 Phase 10 的
  后台调度一起设计（避免与 Phase 8 的 compression worker 争用同一连接）。
