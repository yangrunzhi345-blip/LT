# Phase 9 Remediation Report

- 阶段：Phase 9 — Revision、自动保存与回收站
- 状态：`REMEDIATED / READY_FOR_RE-ACCEPTANCE`（等待独立 reviewer 重新验收；本轮不标记 `ACCEPTED`，Phase 10 保持 `BLOCKED`）
- 执行 Agent：executor-agent（CodeBuddy CLI，remediation 角色）
- 审计基线（Audit HEAD）：`161dd7a3d63ea2cf31176b2f732acc4d702cb4a0`
- 审计结论：`FAILED`（1 BLOCKER + 2 MAJOR + 8 MINOR + 5 INFO）
- 原始验收报告：
  [phase-09-independent-acceptance.md](phase-09-independent-acceptance.md)（保留原样，未修改）
- Remediation Start HEAD：`b999132e63ead67cdb693c3ad757f2cfc11dac15`
  （`docs(status): record the phase 9 acceptance failure` — 先把失败记录固化进历史，再开始修复）

## 1. 交付摘要

| ID | 级别 | 主题 | 结论 |
| --- | --- | --- | --- |
| P9-B1 | BLOCKER | Resource 删除未进入回收站，且硬删除旧表唯一副本 | FIXED |
| P9-M1 | MAJOR | `publishAssemblyRevision` 全量 upsert 当作增量，重放复活已删除节点 | FIXED |
| P9-M2 | MAJOR | 自动保存一次冲突后永久失败；journal 草稿无生产出口 | FIXED |
| P9-M3 | MINOR | 清理无生产触发入口 | FIXED |
| P9-M4 | MINOR | 压缩发布 `alreadyApplied=false` 误报 | FIXED |
| P9-M5 | MINOR | 生产 restore 缺少 CAS | FIXED |
| P9-M6 | MINOR | 级联删除后重复 delete 抛冲突而非幂等 | FIXED |
| P9-M7 | MINOR | assembly 链不在清理范围 | FIXED |
| P9-M8 | MINOR | `deletePart` 死代码 | FIXED（补 UI 入口） |
| P9-M9 | MINOR | 保存覆盖后 after 抓取 label 写作「保存前」 | FIXED |
| P9-I1 | INFO | `captureRevision` 在事务外读 head | FIXED |
| P9-I2 | INFO | Blueprint 覆盖分支无 revision 边界 | FIXED |
| P9-I3 | INFO | 缺「edit → restore → stale autosave」交错用例 | 已补（并发/冲突组覆盖） |
| P9-I4 | INFO | `TrashReason` 单值枚举 | 维持现状（已文档化，新增值需随新增产生方） |
| P9-I5 | INFO | Phase 7 D2 门控 supersede 未标注 | FIXED（STATUS 注明） |

## 2. P9-B1 — Resource 删除进入回收站

### 根因

回收站能力被实现为**新增服务**（`ResourceTrashService`），接入点只覆盖了 Studio 的
Section/Part 命令链；资源删除链路仍停留在 Phase 1/2 的形态：

```text
ResourceCrudController.delete*
  → LibraryRepositoryImpl.delete*
    → _deleteUnifiedResource   // 仅 softDeleteNode，无 trash 行、无 before revision
    → _deleteByMode            // db.delete(...) 物理删除旧表行
```

对 `ResourceReadFacade` 回退态资源（`notMigrated` / `migrationFailed` /
`sourceChanged` / `treeMissing`），旧表行是唯一副本，删除即不可逆丢失。

### 修复

1. **新服务 `ResourceLibraryTrashBridge`**（application 层）负责把库行解析到内容所在处：

   ```text
   library row ──▶ resolve
                     ├─ live content tree row  ──▶ trash.deleteNode(treeId)  （软删除 + before revision）
                     └─ no live tree row       ──▶ trash marker entry        （旧表行完全不动）
   ```

   解析顺序（确定性）：① 库 id 本身就是树 id；② 迁移审计记录里 `resource_id = 库 id`；
   ③ 迁移审计记录里 `(source_table, source_id) = (表, 库 id)` 且 `status = succeeded` 且树行存在；
   ④ 都没有 → 回退态，写 marker。

2. **`ResourceTrashService` 新增 `deleteLegacyOnlyResource`**（P9 域概念 `TrashOrigin`）：
   旧表没有软删除列，因此这类条目是**隐藏标记** — legacy 行一个字节都不动，只被库列表过滤掉；
   restore 只清标记，只有显式永久删除才允许删掉那一行。

3. **普通删除永远不走 `_deleteByMode`**。`_deleteByMode` 保留给
   `prompt_presets` / `adventure_templates`（配置表，非资源正文），
   资源三张表的物理删除只由显式永久删除触发，且表名走固定白名单
   （防止被篡改的 `metadata_json` 把 `DELETE` 指向别的表）。

4. **失败即拒绝**：`LibraryRepositoryImpl` 没有桥接时，删除抛 `StateError`，
   绝不退回原来的破坏性路径（fail closed）。

5. **UI**：`ResourceOperationResult` 增加 `message`，三个 delete*
   返回「已移入回收站，可在「回收站」中恢复」，7 个删除入口统一 `AppFeedback.success` 提示。

### 关键不变量（测试固定）

- 普通删除后旧表行数不变；
- 回收站出现 ACTIVE 条目，且被删除资源从列表与搜索中消失；
- restore 后列表完全恢复（用删除前的 id 集合比对，不依赖行计数）；
- 只有 `permanentDelete` 才把行数清零。

## 3. P9-M1 — assembly revision 增量

### 根因

`publishAssemblyRevision` 把「完整目标状态」当作 delta 写入非空 `parent_revision_id`。
重放只能靠 `is_removed` 墓碑删除节点，而目标状态 map 里永远不含墓碑，
于是「新状态不包含某节点」无法表达 → 已删除节点在 assembly 状态中复活。

### 修复

1. 改为 `ResourceRevisionMath.diff(parent: previousAssemblyState, current: targetState)`，
   与 `captureInTransaction` 使用同一套算法（删除生成墓碑）。
2. `insertRevisionInTransaction` 增加契约守卫 `_assertDeltaMatchesParent`：
   「父非空 + 目标节点数更少 + 增量全是 upsert」直接抛
   `ResourceRevisionDeltaException` 并说明原因。守卫刻意很窄 ——
   只在这种不可能由正确调用方产生的形态下触发，因此不会误伤根 revision 的全量快照。

### 验证

- 已有：真实 v41 DDL + 真实重放算法的复现（期望 `[P1,S]`，实得 `[P1,P2,S]`）确认根因。
- 新增：`Parent = {S,P1,P2} → Target = {S,P1} → Publish → Replay = {S,P1}`，
  并断言列内 `content_hash` 与重建 hash 一致、latest head 未被发布移动。

## 4. P9-M2 — 自动保存 token、重试与草稿恢复

### 根因

基线 token 的所有权与刷新时机错误：编辑器只在 `applied > 0` 时异步 `_refreshToken()`，
于是「自己上一次保存」会被下一次保存判定为冲突；而冲突分支只报告不修复，
`_updatedAt` 再也不会更新 → 同一会话内之后所有保存都失败（粘性冲突）。
同时 `reconcilePendingDrafts` 没有任何生产调用方，被 journal 保住的文本用户永远取不到。

### 修复

1. **Session 拥有 token**：`ResourceAutosaveService` 记录 `_sessionTokens[partId]`，
   首次 `schedule` 用调用方的 token 做种子，之后**每次成功提交都用
   `PartContentCommitResult.updatedAtToken`（同一个事务写出的值）同步推进**。
   `_tokenFor()` 优先用 session 的值，调用方的 token 退化为种子。
   编辑器不再需要异步刷新（已移除 `readUpdatedAt` 回调），从而消除了那个竞态窗口。

2. **有界重试 + 仍然不覆盖他人写入**：冲突时读一次 live 状态：

   - Part 不存在 → 丢弃草稿；
   - live 正文 == 草稿 → 视为已写入，采信 token、删 journal、报 applied；
   - live 正文 == **本 session 上次持久化的正文** → 说明 token 只因自己的写而移动，
     采信新 token 并重试**一次**；
   - 其余情况 → 保留 journal 行并报 conflict，**不覆盖**外部写入者的内容。

3. **草稿有生产出口**：`AutosaveSession` 暴露 `reconcilePendingDrafts` /
   `pendingDraft` / `discardDraft`；`ResourceStudioPartEditor` 打开时调用
   reconcile，对 `needsUserDecision` 的草稿显示「发现未保存的草稿」横幅，
   提供「载入草稿 / 丢弃草稿」。载入后文本进入编辑器，下一次保存即写入正文。
   （分类逻辑抽到 `AutosaveDraftRecovery`，服务与 UI 共用一份判定，避免两处漂移。）

4. **冲突提示不再被击键静默清除**：只有一次成功保存才清除冲突状态。

## 5. P9-M3 / M7 / I2

- **P9-M3**：新增 `ResourceRevisionMaintenance`（按间隔节流、永不抛错、
  失败写 `lastError`），由 `main.dart` 的 post-frame 钩子触发
  （与 Phase 8 的 compression worker 同一模式；启动是最可控的点，不会有编辑在飞）。
- **P9-M7**：`pruneRevisions` 对 `ResourceRevisionKind` 的每种链各跑一遍
  「保留最新前缀 + 根化幸存者 + 删除更老前缀」；两条链的 head 互相进入保护集合。
- **P9-I2**：`ResourceBlueprintRepositoryImpl.confirmBlueprint` 的
  「资源已存在」分支（它会删掉全部 Section/Part 再重建）现在在同一事务内
  capture before/after，cause 为新增的 `RevisionCause.planning`。

## 6. 其余低风险项

- **M4**：`CompressionPublisher` 透传 `result.alreadyApplied`，并在已应用时
  `savedCharacters = 0`（不再声称节省字数和新建历史版本）。
- **M5**：`ResourceRevisionService.resourceUpdatedAt()` +
  runtime/controller 透传 `expectedUpdatedAt`；页面在用户点确认前读取 token，
  冲突时提示而不是静默丢弃较新状态。
- **M6**：`deleteNode` 遇到「已被祖先级联删除」的节点，解析到祖先条目并返回
  幂等结果，而不是抛 `ResourceTrashConflictException`。
- **M8**：Studio 正文区新增「删除段落」入口（二次确认）→
  `SectionControlRuntime.deletePart` → 回收站，可恢复。
- **M9**：保存覆盖后的 after 抓取 label 改为「保存后快照」。
- **I1**：`captureRevision` 的 head 读取移进事务内，`wasNoOp` 不再是猜测。

## 7. 新增/修改文件（本轮）

### 新增（生产）

- `lib/application/resources/resource_library_trash_bridge.dart`
- `lib/application/resources/legacy_library_row_purger.dart`
- `lib/application/resources/autosave_draft_recovery.dart`
- `lib/application/resources/resource_revision_maintenance.dart`

### 新增（测试）

- `test/application/resources/phase9_library_delete_test.dart`（18）
- `test/application/resources/phase9_revision_maintenance_test.dart`（8）
- `test/application/resources/phase9_blueprint_boundary_test.dart`（3）
- `test/helpers/phase9_recovery_fixtures.dart`（共享装配）

### 新增用例（追加到既有文件）

- `resource_revision_service_test.dart`：assembly 链增量组（6）
- `resource_autosave_service_test.dart`：token 所有权组（3）、冲突保护组（2）、已确认内容组（1）
- `resource_trash_service_test.dart`：级联删除幂等（1）
- `phase9_revision_boundary_test.dart`：压缩已应用发布（1）
- `resource_studio_part_editor_test.dart`：草稿恢复组（5）、冲突可见性组（2）
- `resource_studio_section_controls_test.dart`：删除段落入口组（2）

### 修改（生产）

- `lib/services/repositories/library_repository_impl.dart`（删除改接回收站 + 读取过滤）
- `lib/application/resources/resource_trash_service.dart`（legacy 条目、restore、永久删除、幂等）
- `lib/application/resources/resource_revision_service.dart`（assembly diff、链清理、事务内读 head、resourceUpdatedAt）
- `lib/application/resources/resource_revision_repository.dart`（增量契约守卫）
- `lib/application/resources/resource_autosave_service.dart`（token 所有权、有界重试、草稿接口）
- `lib/application/resources/part_content_commit_service.dart`（返回新 token）
- `lib/application/resources/resource_compression_publisher.dart`（alreadyApplied 透传）
- `lib/application/resources/resource_blueprint_repository.dart`（revision 边界）
- `lib/application/resources/resource_creation_pipeline.dart`（label）
- `lib/domain/resources/resource_trash.dart`（`TrashOrigin`、`linkedSource*`、placement）
- `lib/domain/resources/resource_revision.dart`（`planning` cause、`ResourceRevisionDeltaException`）
- `lib/controllers/resource_crud_controller.dart`（成功提示）
- `lib/services/database_service.dart`（库仓库装配桥接）
- `lib/providers/riverpod_providers.dart`（桥接、purger、maintenance、capture 接线）
- `lib/main.dart`（启动时运行保留期清理）
- `lib/features/resource_studio/...`（编辑器草稿恢复、冲突可见、删除段落、restore CAS）
- 7 个删除入口 UI（worldview_tab / character_card_tab ×2 / npc_tab / 两个编辑页 / app_dialogs）

## 8. 已知问题 / 遗留（不在本轮修复范围）

1. **迁移资源在资源库里会出现两条投影**（旧表行 + 树投影）。
   这是 Phase 3 union 的既有行为，与本次删除改接无关
   （`phase9_library_delete_test` 用「删除前 id 集合 == 恢复后 id 集合」固定往返保真度，
   并已记录 `before` 集合同时包含旧表 id 与树 id）。归属 Phase 11「资源库 UX 收敛」。
2. `TrashReason` 仍为单值枚举：只有产生新增语义的写入方出现时才应加值，本轮不臆造。
3. Phase 8 遗留技术债（A6/A8/A9/A10/A11/A12、R3-M1..M3、INFO-001..006）仍未处理。
4. 未在 Linux 桌面上人工操作 UI；UI 结论来自 widget 测试与代码走查。

## 9. 验证结果

全部命令由 remediation Agent 实际运行（非引用审计 Agent 的输出）：

| 命令 | 结果 |
| --- | --- |
| `dart format --output=none --set-exit-if-changed .` | 472 files / 0 changed（exit 0） |
| `flutter analyze` | No issues found |
| Phase 9 定向测试（21 个文件） | **346 passed / 0 failed** |
| 全量 `flutter test` | **1446 passed / 0 failed**（审计基线 1392，本轮 +54） |
| `git diff --check` | 干净 |

定向测试明细（`346`）：

| 文件 | 用例数 |
| --- | --- |
| `resource_revision_test.dart`（domain） | 18 |
| `resource_trash_test.dart`（domain） | 24 |
| `resource_autosave_test.dart`（domain） | 10 |
| `resource_revision_service_test.dart` | 38（含新增 assembly 链增量组 6） |
| `resource_trash_service_test.dart` | 29（含新增级联幂等 1） |
| `resource_autosave_service_test.dart` | 27（含新增 token 所有权 3、冲突保护 2、已确认内容 1） |
| `phase9_revision_boundary_test.dart` | 17（含新增已应用发布 1） |
| `phase9_concurrency_test.dart` | 11 |
| `phase9_library_delete_test.dart`（新增） | 18 |
| `phase9_revision_maintenance_test.dart`（新增） | 8 |
| `phase9_blueprint_boundary_test.dart`（新增） | 3 |
| `database_migration_v41_test.dart` | 7 |
| `resource_revision_panel_test.dart` | 19 |
| `resource_trash_sheet_test.dart` | 18 |
| `resource_studio_part_editor_test.dart` | 21（含新增草稿恢复 5、冲突可见性 2） |
| `resource_studio_test.dart` | 12 |
| `resource_studio_section_controls_test.dart` | 22（含新增删除段落入口 2） |
| `resource_capacity_test.dart` | 16 |
| `database_and_repositories_test.dart` | 27 |
| `end_to_end_flow_test.dart` | 3 |
| `phase3_independent_acceptance_test.dart` | 18 |

### 本轮由全量回归发现的回归（已修复）

`test/unit/end_to_end_flow_test.dart` 的 「Flow B: Resource Library Complete CRUD &
Search Lifecycle」 直接构造未接桥接的 `LibraryRepositoryImpl` 并调用 `deleteNpcCard`，
触发本轮新增的 fail-closed `StateError`。根因与新契约一致（删除必须有回收站），
已按生产形态注入桥接；该用例的断言（删除后列表不含该 NPC）保持不变并通过。

同类适配共 3 处（`database_and_repositories_test.dart`、`phase3_independent_acceptance_test.dart`、
`end_to_end_flow_test.dart`）：均为「构造方式适配新契约」，不是弱化断言 ——
被审计判定为缺陷的「物理删除旧表行」在这些用例中原本就没有断言依赖；
`phase9_library_delete_test.dart` 用显式行数断言补齐了这一缺口。

### 未验证范围

- 未在 Linux 桌面上人工操作 UI；UI 结论来自 widget 测试与代码走查。
- 未做真实进程崩溃重启测试；崩溃语义由 journal 分类 + 未完成状态断言覆盖。
- 未运行 `flutter build` 打包验证（本轮无平台/构建相关改动）。
