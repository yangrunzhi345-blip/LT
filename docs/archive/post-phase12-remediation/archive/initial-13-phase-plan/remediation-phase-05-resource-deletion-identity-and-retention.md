# Remediation Phase 05 — Resource Deletion Identity, Cascade & Retention

> **Root Cause**: RC-05
> **Findings**: M11, M12 (MAJOR), N4, N6, N14, TG10
> **Depends On**: None
> **Document status**: PLANNED

---

## 1. Purpose

统一资源树与旧资源表（legacy tables）之间的 identity 关系没有在删除/重建生命周期间被记录，导致：

- 通过入口 bridge 编辑过的旧资源被删除后，旧行重新出现、永久删除也删不掉（M11）；
- 软删除后以同一 id 重建资源会命中主键冲突或静默 no-op（M12）；
- 永久删除不清理新子系统的辅助表，留下孤儿数据，且 head revision 永不回收（N4）；
- revision 裁剪不保护 adventure 已引用的 revision（N6）；
- 删除 Section/Part 不取消其生成任务，后续恢复生成被已删目标阻塞（N14）。

本 Phase 修复的 contract 是：**“资源删除/重建是一个有明确 owner、可查询、可幂等收敛的生命周期，
两个投影必须一起隐藏、一起清除；删除节点必须使其派生数据失效。”**

## 2. Audit Findings Covered

```text
Primary:
- M11  删除被入口编辑过的旧资源：旧行复活、永久删除残留
- M12  软删除后同 id 重建：UNIQUE 冲突或静默 no-op

Related:
- N4   永久删除遗留 revision/readiness/assembly/compression/autosave/task 孤儿；head revision 永不回收
- N6   revision 裁剪不保护 world_entries.source_revision_id
- N14  删除 Section/Part 不清其生成任务，阻塞后续恢复生成

Test gaps:
- TG10 无“同 id 旧行影子删除/永久删除”“软删后同 id 重建”用例
```

## 3. Current Production Architecture

### 3.1 identity 复用

```text
LegacyCreationBridge.saveCard/saveWorldview/...(resourceId: legacyId)
  → ResourceCreationPipeline.create
      → ResourceTreeDraft.withId(LegacyCreationBridge.resourceIdFor(legacyId))
                                                       (legacy_creation_bridge.dart:262)
         resourceIdFor(x) => ResourceId(x)               ← 树资源 id == 旧行 id
  → createResourceTreeInTransaction / updateResourceTreeInTransaction
```

Bridge **不写** `resource_migration_records`（Phase 2 迁移才会写）。

### 3.2 库读取 union

```text
LibraryRepositoryImpl.list...
  → _treeOnlyRows (library_repository_impl.dart:202-238)
  → _mergeTreeRows (:240-310)
       旧行被过滤的条件: unifiedIds.contains(id)（:296-306）
       unifiedIds 只来自“本次可见的 live 树行”
```

### 3.3 删除解析

```text
LibraryRepositoryImpl._moveToTrash(table, id)
  → ResourceLibraryTrashBridge.moveToTrash(table, id)     (resource_library_trash_bridge.dart:107)
      → _resolveTarget(db, table, id)                     (:213-250)
           case 1: 树存在 → treeId=id, legacyId=_legacyIdFor(table, treeId)
           case 2: 迁移成功 → treeId=migrated, legacyId=id
           case 3: 无树 → legacy-only marker
      → _legacyIdFor (:276-292)  仅查 resource_migration_records
      if (target.hasLiveTree)
        → _trash.deleteNode(treeId, metadata: {source_table, source_id} 仅当 hasLegacyLink)
      else
        → _trash.deleteLegacyOnlyResource(...)
  → permanentDelete → _purgeLinkedLegacyRow(entry)          (resource_trash_service.dart:594)
       读取 entry.linkedSourceTable / linkedSourceId（来自 entry metadata）
```

### 3.4 生成任务与目标 Part

```text
ResourceGenerationTaskRepositoryImpl.findReadyTasks / findTasksForResource  (:159/:105)
  仅按 resource_id 查询，不 join 节点 liveness
commitPartContent  更新 resource_parts where 'id = ? AND deleted_at IS NULL'
  → 若目标 Part 已删，匹配 0 行 → StateError
```

## 4. Exact Bugs

### Finding M11 — 删除被入口编辑过的旧资源后旧行复活

#### Trigger
对一个 Phase 2 迁移前已存在、且被入口 bridge 编辑过的角色/世界观/NPC，从资源库执行删除。

#### Current Behavior
1. 编辑时 bridge 在树中创建/更新了 id == 旧行 id 的资源，**未写** `resource_migration_records`。
2. 删除时 `_resolveTarget` 走 case 1，`_legacyIdFor` 查 migration record 返回 `null`，因此
   `hasLegacyLink == false`，trash 条目 metadata 为空、`origin=tree`。
3. 树行被软删后不再出现在 `_treeOnlyRows`，`unifiedIds` 不再包含该 id，旧行因此重新出现在库中。
4. 再次删除返回 `alreadyDeleted`；`permanentDelete` 因 `linkedSourceTable` 为空而不清理旧行。

#### Expected Behavior
同 id 的旧行与树行被视为同一资源：删除时一起隐藏，永久删除时一起清除。

#### Evidence
```text
file: lib/application/resources/legacy_creation_bridge.dart:262
file: lib/application/resources/resource_library_trash_bridge.dart:213-292, 126-130, 163-211
file: lib/services/repositories/library_repository_impl.dart:240-310
file: lib/application/resources/resource_trash_service.dart:594-621
既有测试: test/application/resources/phase9_library_delete_test.dart 只覆盖 legacy-only/migrated/tree-only
```

#### User / Data Impact
删除看似成功但资源仍在；永久删除无效；用户无法真正删除旧资源。

---

### Finding M12 — 软删除后同 id 重建失败

#### Trigger
删除某资源后，以同一 id 再次保存/导入（M11 的影子、确定性 id 导入都会命中）。

#### Current Behavior
`ResourceCreationPipeline.create` 的存在性探针是
`SELECT id FROM resources WHERE id = ? AND deleted_at IS NULL`（pipeline 内），软删行不可见 →
走 `createResourceTreeInTransaction` → 裸 `INSERT` 命中被占用的主键 →
`UNIQUE constraint failed: resources.id`。若内容字节相同，`_resolveOperationId` 复用上次
idempotency_key，`create` 以 `reusedExisting` 返回而**未创建任何东西**，无错误浮出。

#### Expected Behavior
以软删除 id 重建必须得到确定结果：要么“作为重新保存，恢复并覆盖（含回收站条目收敛 + revision 记录）”，
要么给出可被 UI 处理的明确领域错误；不得主键冲突、不得静默 no-op。

#### Evidence
```text
file: lib/application/resources/resource_creation_pipeline.dart:319-335
file: lib/services/repositories/resource_tree_repository_impl.dart:95-113
file: lib/application/resources/legacy_creation_bridge.dart:301-331
既有测试: 无 delete→re-save 同 id
```

#### User / Data Impact
用户保存/导入失败或静默丢失内容。

---

### Finding N4 — 永久删除的孤儿数据与 head revision 永不回收

#### Trigger
对资源执行永久删除。

#### Current Behavior
`ResourceTrashService.permanentDelete` 只清除树节点、关联旧行、回收站条目；
`resource_revisions` / `resource_revision_nodes` / `resource_assembly_readiness` /
`resource_assembly_entries` / `resource_autosaves` / `resource_compression_jobs` /
`resource_compression_candidates` / `resource_generation_tasks` / `resource_generation_attempts`
/ `resource_generation_sessions` 全部按字符串 id 关联且**无 FK 到 `resources`**，不会被清理。
`_pruneOneChain` 永远保留链头（`keepFrom = chain.length - 1`），且 `pruneRevisions` 会继续遍历
`resource_revisions` 中存在的 id，因此已删除资源的 head revision 与 readiness 指针永久残留。

#### Expected Behavior
永久删除应在同一事务内清除该资源的所有派生行；或提供一个幂等 sweep，回收 `resources` 中已不存在
的资源 id 的派生行。

#### Evidence
```text
file: lib/application/resources/resource_trash_service.dart:498-550
file: lib/application/resources/resource_revision_service.dart:740-936（head 保护 :904）
file: lib/services/database_service.dart:547-593, 634-745, 808-859, 892-990（无 FK 到 resources）
既有测试: phase9 永久删除只断言树行与旧行
```

#### User / Data Impact
数据库无界增长；删除后仍存在“幽灵”readiness/revision 记录，可能影响 readiness 查询与裁剪。

---

### Finding N6 — revision 裁剪不保护 adventure 引用的 revision

#### Trigger
某个 assembly revision 被 adventure 的 `world_entries.source_revision_id` 引用后，它不再是 assembly
head 并超过保留窗口；裁剪运行。

#### Current Behavior
`_pruneOneChain` 的保护集只包含 head、readiness 指针、未解决 trash 指针，不包含
`world_entries.source_revision_id`。被引用的 revision 及其索引文档可被删除，冒险的 provenance
指针成为悬空。

#### Expected Behavior
被 `world_entries.source_revision_id` 引用的 revision 必须纳入保护集（或明确文档化 provenance 可被
回收，并在回收时置空该列）。

#### Evidence
```text
file: lib/application/resources/resource_revision_service.dart:824-879
file: lib/providers/adventure_provider.dart:303
file: lib/services/database_service.dart:587-592（world_entries.source_revision_id）
```

#### User / Data Impact
冒险的来源追溯悬空（当前不影响内容读取，但会破坏 provenance 一致性）。

---

### Finding N14 — 删除 Section/Part 不清生成任务

#### Trigger
删除含生成任务的 Section/Part 后，恢复/继续该资源的生成。

#### Current Behavior
`SectionControlService.deleteSection`（:272）与 `deletePart`（:369）走软删除，但不触碰
`resource_generation_tasks`。`findReadyTasks`/`findTasksForResource` 仅按 `resource_id` 查询。
恢复生成时任务派发到已删 Part，`commitPartContent` 匹配 0 行抛
`StateError('在 resource_parts 中未找到对应的部件节点')`，重试耗尽后 `generateAllParts` 中止，可能
留下其他已提交 Part。

#### Expected Behavior
删除节点时应在同一事务内取消/失效其生成任务；或调度时跳过已删目标并记录为 cancelled。

#### Evidence
```text
file: lib/application/resources/section_control_service.dart:272, 369
file: lib/application/resources/resource_generation_task_repository.dart:105, 159, 380
```

#### User / Data Impact
生成流程被已删节点阻塞，产生失败与部分提交。

## 5. Root Cause

**Symptom**：删除后资源仍在、重建报主键冲突、永久删除留垃圾、已删节点阻塞生成。

**Root Cause**：`LegacyCreationBridge` 让树资源**复用**旧行 id（正确的去重意图），但没有把这个
identity 关系持久化，也没有定义“一份资源的两个投影谁拥有删除责任”。因此：

- 删除链只能识别“迁移产生的链接”（migration record），识别不了“入口编辑产生的同 id 影子”→ M11；
- 创建链的存在性探针只看 live 行，与主键（含软删行）不一致 → M12；
- 删除的 owner 只覆盖树行与显式旧行链接，不覆盖新子系统的派生表 → N4；
- 裁剪的保护集与 adventure provenance 没有建立契约 → N6；
- 节点删除与生成任务之间没有“目标失效”协议 → N14。

这是同一 owner/identity contract 缺失造成的系统性问题。

## 6. Required Contract After Remediation

1. **Identity 可查**：给定 (legacy table, id)，能判定它是否对应一个同 id 的树资源；反之，对树资源
   能判定它是否是某个旧行的影子。
2. **删除一致**：删除一个有两份投影的资源，两份都要被隐藏；恢复时两份都要恢复（或明确旧行仅作投影）。
3. **永久删除完整**：永久删除必须清除该资源全部派生行；随后不存在任何以该 id 为键的残留。
4. **重建确定**：以软删除 id 重建必须返回确定结果（relive+overwrite 或 typed error），不得主键冲突、
   不得静默 no-op。
5. **节点删除使派生数据失效**：删除 Section/Part 必须使其生成任务进入终态（cancelled），后续调度
   跳过已删目标。
6. **裁剪安全**：被 adventure provenance 引用的 revision 不得被裁剪删除。
7. 不得物理删除 legacy 表本身；不得改变已 ACCEPTED 的租约/attempt 语义。

## 7. Implementation Plan

### Step 1 — 识别“同 id 旧行影子”（M11）

```text
file: lib/application/resources/resource_library_trash_bridge.dart
symbol: _legacyIdFor (:276-292)
```

修改为：

1. 先查 `resource_migration_records`（现有逻辑）。
2. 若无记录，则查询 `table` 中是否存在 `id = treeId` 的旧行；存在则返回 `treeId`。
   （查询使用 `table` 参数，来自 `moveToTrash` 的调用方，值为已知白名单表名。）

```text
symbol: moveToTrash (:107-154)
```

`deleteNode` 的 metadata 现在会自动包含 `source_table/source_id`（因为 `hasLegacyLink` 为真），
从而 `hiddenLegacyIds` 会把它当作 legacy-origin 隐藏旧行，`permanentDelete` 会通过
`_purgeLinkedLegacyRow` 清除旧行。**无需修改 `hiddenLegacyIds`。**

同时修正 `_TrashTarget` 的文档注释（`:51-56`）：当旧行与树行同 id 时，`legacyId` 等于树 id 是**正确
的**，不是“synthetic link”。

### Step 2 — 恢复/永久删除的树+旧行一致性（M11 收尾）

确认（并在必要时修正）：
- `ResourceTrashService.restore` 对带 `source_table/source_id` 的条目只恢复树行，不重建旧行（旧行从未
  被删除）→ 旧行继续被 `hiddenLegacyIds` 隐藏，语义正确。
- `ResourceTrashService.permanentDelete` 对同 id 影子会 `purgeLegacyRowInTransaction(sourceTable, sourceId)`
  并在其后删除树行；顺序必须保证先删树（或其一）后清旧行，且都在同一事务。

如果 `_purgeLinkedLegacyRow` 在树已删除后仍能正确执行，则无需改动。

### Step 3 — 软删除 id 重建（M12）

```text
file: lib/application/resources/resource_creation_pipeline.dart
symbol: create 的 existingTree 探测 (:319-335)
```

1. 探针改为同时查询 live 与 soft-deleted：

   ```sql
   SELECT id, deleted_at FROM resources WHERE id = ? LIMIT 1
   ```

2. 若不存在 → 现有 `createResourceTreeInTransaction`。
3. 若存在且 `deleted_at IS NULL` → 现有 `updateResourceTreeInTransaction`（含 revision 捕获）。
4. 若存在且 `deleted_at != null` → 走“复活并覆盖”：
   - 在同一事务内，先把该资源**未解决的回收站条目**标记为 restored（见下）；
   - 调用新增的 repository 方法
     `reviveResourceForOverwriteInTransaction(txn, draft)`：清除根节点 `deleted_at`、更新资源与
     子树（复用 `updateResourceTreeInTransaction` 的写入逻辑，但允许原本 soft-deleted 的根）；
   - 捕获 before/after revision（复用既有 `_captureRevisionBeforeOverwrite/_AfterOverwrite`）。

回收站条目收敛通过一个窄接口完成，避免 pipeline 直接操作 trash 表：

```text
新增端口（放在 resource_creation_contracts.dart 或邻近文件）:
abstract interface class TrashBookkeepingPort {
  Future<void> resolveUnresolvedEntryInTransaction(DatabaseExecutor txn, String resourceId);
}
```

- `ResourceCreationPipeline` 增加可选构造参数 `TrashBookkeepingPort? trashBookkeeping`。
- 生产装配（`riverpod_providers.dart:429-436`）注入由 `ResourceLibraryTrashBridge` /
  `ResourceTrashRepositoryImpl` 实现的端口，在该事务内把 `resource_trash` 中该 node_id 的未解决条目
  置 `restored_at`。
- 若端口为 null 且命中软删重建（测试或未装配路径），**fail-closed**：抛
  `ResourceCreationException('资源在回收站中，无法直接覆盖')`，不得静默继续。

### Step 4 — 永久删除级联（N4）

```text
file: lib/application/resources/resource_trash_service.dart
symbol: permanentDelete (:498-550)
```

在永久删除事务内，于删除树节点之后追加对以下表的删除（按依赖顺序）：

```text
resource_revision_nodes   (按 revision_id in (select revision_id from resource_revisions where resource_id = ?))
resource_revisions        (resource_id = ?)
resource_assembly_entries (resource_id = ?)
resource_assembly_readiness (resource_id = ?)
resource_autosaves        (resource_id = ?)
resource_compression_candidates (job_id in (select job_id from resource_compression_jobs where resource_id = ?))
resource_compression_jobs (resource_id = ?)
resource_generation_attempts (task_id in (select task_id from resource_generation_tasks where resource_id = ?))
resource_generation_tasks (resource_id = ?)
resource_generation_sessions (resource_id = ?)
resource_blueprints       (resource_id = ?)   // 仅在确认 blueprint 以 resource_id 归属时
```

- 全部使用参数绑定；不得拼接。
- 若某表可能不存在（旧库），先用 `DatabaseService.tableExists` 守卫。
- 同时修正裁剪：`_pruneOneChain` 允许删除“资源已不存在”的链的 head（新增判定：`resources` 中无该
  id 时不再保护 head）。

```text
file: lib/application/resources/resource_revision_service.dart
symbol: _pruneOneChain, pruneRevisions (:740-936)
```

### Step 5 — 裁剪保护 adventure provenance（N6）

```text
file: lib/application/resources/resource_revision_service.dart
symbol: _pruneOneChain 的保护集 (:824-879)
```

- 查询 `world_entries` 中 `source_revision_id` 属于当前资源链的 id，加入保护集
  （实现前确认 `world_entries` 与资源 id 的关联列；file: `database_service.dart:587-592`）。
- 若某 revision 已被裁剪但 provenance 仍引用，属于本次修复前遗留；本 Phase 只保证修复后不再产生。

### Step 6 — 删除节点使生成任务失效（N14）

```text
file: lib/application/resources/resource_tree_repository_impl.dart
symbol: softDeleteNodeInTransaction (:915-992)
```

- 对 `SectionId` / `PartId` 分支，在同一事务内把对应 `resource_generation_tasks`
  置为 `cancelled`（按 `part_id`/`section_id`），并清理/终态化其 `generating` attempt。
- 实现前确认 `resource_generation_tasks` 是否有 `section_id` 列（schema `:894-918` 有 `section_id`、
  `part_id`）。

```text
file: lib/application/resources/resource_generation_task_repository.dart
symbol: findReadyTasks (:159)
```

- 增加防御：join `resource_parts` 并过滤 `deleted_at IS NULL`（或按 task status 排除 cancelled），
  确保即使任务未被取消也不会派发到已删目标。

## 8. Design Decisions

### 8.1 M11 用“同 id 旧行”还是“补写 migration record”

- **方案 A（推荐）**：在 `_legacyIdFor` 增加“同 id 旧行存在”的回退。
- 方案 B：入口 bridge 写一条 `resource_migration_records`。

**选择 A**。理由：migration record 语义是“Phase 2 迁移产物”，入口编辑不是迁移；补写会污染迁移
统计与 `source_hash` 校验语义（`_mergeTreeRows` 会根据 migration status 决定 union 行为）。**不采用 B。**

### 8.2 M12 用“复活覆盖”还是“报错让用户先恢复”

- **方案 A（推荐）**：管线内复活 + 覆盖 + 收敛回收站条目。
- 方案 B：抛 typed error，要求用户先恢复或永久删除。

**选择 A**。理由：导入/保存是高频路径，报错会让用户困惑；复活并记录 revision 与回收站收敛语义与
“重新保存”一致，且不丢内容。**不采用 B**（保留为端口缺失时的 fail-closed 兜底）。

### 8.3 永久删除用“显式删除”还是“加 FK 级联”

**选择显式删除**。理由：给已存在的表加 FK 需要重建表（SQLite 无 `ALTER ADD CONSTRAINT`），风险与
复杂度高，且会与既有部分唯一索引/迁移交互。**不采用新增 FK。**

### 8.4 N14 用“删除时取消任务”还是“调度时过滤”

**选择两者都做**：删除时取消（正确 owner），调度时过滤（防御）。**不采用只做其一。**

## 9. Database Impact

```text
No schema change required.
```

- 不新增表/列，不修改 `schemaVersion`（保持 43），不修改 migration。
- 所有改动为事务内显式删除 / 查询回退 / 新增端口，均不改 schema。
- 既有软删除数据在升级后即可按新语义重建；永久删除会对既有孤儿数据仅在“再次永久删除该资源”时
  清理，不做全库 sweep（sweep 作为可选后续，见 OPEN QUESTION）。
- 回滚为纯代码 revert；数据库无破坏性改动。

## 10. Concurrency / Sequence

### 10.1 M11 修复后（删除）

```text
delete(table, legacyId == treeId)
  ↓
_resolveTarget case1 → legacyId = treeId（旧行存在）
  ↓
deleteNode(treeId, metadata{source_table, source_id=treeId})
  ↓
hiddenLegacyIds → 隐藏旧行（库中不再出现）
permanentDelete → purge 旧行 + 树行
```

### 10.2 M12 修复后（软删重建）

```text
create(resourceId = X)
  ↓
probe: row X exists, deleted_at != null
  ↓
resolve trash entry (restored_at = now)
  ↓
revive root (deleted_at = null) + overwrite tree
  ↓
revision before/after captured
```

### 10.3 并发不变量

```text
不变量1: 同一 (table,id) 的删除/恢复/重建必须在事务内完成，且回收站条目状态与树行状态一致。
不变量2: 永久删除事务提交后，不存在任何以该 resourceId 为键的派生行。
不变量3: 已删节点的生成任务不得被派发。
```

## 11. Files Expected To Change

```text
Production（Expected）:
- lib/application/resources/resource_library_trash_bridge.dart     （Step 1）
- lib/application/resources/resource_creation_pipeline.dart         （Step 3）
- lib/application/resources/resource_creation_contracts.dart        （TrashBookkeepingPort）
- lib/services/repositories/resource_tree_repository_impl.dart      （revive 方法 + Step 6 取消任务 + findReadyTasks join）
- lib/application/resources/resource_trash_service.dart             （Step 4 级联）
- lib/application/resources/resource_revision_service.dart          （Step 4 裁剪 + Step 5 保护集）
- lib/providers/riverpod_providers.dart                             （注入 TrashBookkeepingPort）

Production（Possible）:
- lib/application/resources/resource_migration_service.dart（若需查询辅助）
- lib/services/repositories/library_repository_impl.dart（若 union 需调整）

Tests（Expected，新建）:
- test/application/resources/legacy_shadow_deletion_test.dart
- test/application/resources/soft_deleted_recreate_test.dart
- test/application/resources/permanent_delete_cascade_test.dart
- test/application/resources/revision_prune_provenance_test.dart
- test/application/resources/delete_node_invalidates_generation_tasks_test.dart

Tests（Possible，更新）:
- test/application/resources/phase9_library_delete_test.dart
- test/application/resources/resource_trash_service_test.dart
- test/application/resources/phase9_revision_maintenance_test.dart

Docs:
- docs/post-phase12-remediation/STATUS.md

Forbidden / should not be touched:
- 生成 attempt/lease 语义（R01/R03）
- 内容写入 CAS（R03）
- 软删除与 revision 的“是否可恢复”判定扩展（R06；本 Phase 只做 identity 与 owner，不重写 revision
  restore 的 deleted_at 判定）
- 删除 legacy 表结构（不得）
```

## 12. Test Plan

### TEST R05-01（M11 删除同 id 影子）
```text
Given: legacy 表中存在 id=X 的行；树中存在 id=X 的 live 资源（无 migration record）
When:  library delete(X)
Then:  X 从 library 列表消失
       resource_trash 条目 origin=legacy 且含 source_table/source_id
```

### TEST R05-02（M11 永久删除同 id 影子）
```text
Given: TEST R05-01 之后
When:  permanentDelete(entry)
Then:  树行删除；legacy 表中 id=X 的行删除；回收站条目删除
```

### TEST R05-03（M12 软删重建）
```text
Given: 资源 X 已软删除且回收站有条目
When:  ResourceCreationPipeline.create(resourceId: X, 新内容)
Then:  创建成功（不抛 UNIQUE）
       树 X 复活且内容为新内容
       回收站条目 restored
       存在 before/after revision
```

### TEST R05-04（M12 幂等/静默 no-op 防护）
```text
Given: 同上但内容与软删前相同
When:  create
Then:  不出现“返回 reusedExisting 但什么都没创建”的情况
       （要么复活覆盖，要么明确错误）
```

### TEST R05-05（N4 永久删除级联）
```text
Given: 资源 X 有 revision / readiness / autosave / compression job / generation task
When:  permanentDelete(X)
Then:  上述所有表中 resource_id=X 的行数为 0
       再次 permanentDelete 幂等或返回“不存在”
```

### TEST R05-06（N6 裁剪保护 provenance）
```text
Given: revision R 被 world_entries.source_revision_id 引用，且已过保留窗口
When:  pruneRevisions
Then:  R 未被删除
```

### TEST R05-07（N14 删除节点使任务失效）
```text
Given: Part P 有 ready/generating 生成任务
When:  softDeleteNode(P)
Then:  该任务 status == cancelled
       findReadyTasks 不返回已删 Part 的任务
       后续生成不因 P 抛 “未找到对应的部件节点”
```

## 13. Mutation / Negative Verification

```text
Mutation 1: 移除 _legacyIdFor 的同 id 回退
→ TEST R05-01、R05-02 必须 FAIL

Mutation 2: 恢复 create 探针为仅 live 行
→ TEST R05-03 必须 FAIL

Mutation 3: 移除 permanentDelete 的级联删除
→ TEST R05-05 必须 FAIL

Mutation 4: 从 _pruneOneChain 保护集移除 world_entries 引用
→ TEST R05-06 必须 FAIL

Mutation 5: 移除 softDeleteNodeInTransaction 的任务取消
→ TEST R05-07 必须 FAIL
```

## 14. Acceptance Criteria

```text
AC-R05-01 同 id 旧行影子删除后从库中消失；永久删除清除两份。
AC-R05-02 软删 id 重建返回确定结果，无 UNIQUE 冲突、无静默 no-op。
AC-R05-03 永久删除后无该 resourceId 的派生行残留。
AC-R05-04 adventure 引用的 revision 不被裁剪。
AC-R05-05 删除节点使其生成任务进入 cancelled，调度不再派发已删目标。
AC-R05-06 既有 Phase 9 删除/恢复测试仍通过。
AC-R05-07 全量 flutter test 通过。
```

## 15. Required Verification Commands

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test test/application/resources/legacy_shadow_deletion_test.dart
flutter test test/application/resources/soft_deleted_recreate_test.dart
flutter test test/application/resources/permanent_delete_cascade_test.dart
flutter test test/application/resources/revision_prune_provenance_test.dart
flutter test test/application/resources/delete_node_invalidates_generation_tasks_test.dart
flutter test test/application/resources/phase9_library_delete_test.dart
flutter test test/application/resources/resource_trash_service_test.dart
flutter test
git diff --check
git status --short
```

## 16. Out of Scope

- 不删除 legacy 表；
- 不重写 revision restore / 软删除语义（R06）；
- 不改生成提交 CAS（R03）；
- 不做全库孤儿 sweep（除非独立审核要求；见 OPEN QUESTION）；
- 不改 UI 布局。

## 17. Rollback / Failure Safety

- 永久删除事务失败 → 整体回滚，资源仍在回收站，可重试；不得留下“树已删但旧行未删”或反之。
- 软删重建失败 → 抛出领域错误，原软删状态与回收站条目保持可恢复。
- 删除节点取消任务失败 → 事务回滚，节点仍未删除（fail-closed）。
- 全部为事务内操作，无 schema 改动，revert 安全。

## 18. OPEN QUESTION

```text
Q1: resource_generation_tasks 是否真的含 section_id 列（用于按 Section 取消任务）？
    见 database_service.dart:894-918。
Q2: world_entries 与资源/assembly revision 的关联列（source_revision_id）是否对所有资源类型都存在？
    见 database_service.dart:587-592。
Q3: 是否需要为既有孤儿数据提供一次性 sweep？本 Phase 默认不做（只保证新删除正确）。
    需要产品判断：孤儿数据是否会影响 readiness/provenance 查询。
```

## 19. Handoff Notes

- R06 依赖本 Phase 的 identity/软删除判定；实施 R06 前必须确认本 Phase 的“同 id 影子”语义已生效。
- R11 必须为“库删除/永久删除”补充使用生产装配（无 override）的测试，覆盖本 Phase 的 identity 回退。
