# Remediation Phase 06 — Soft-Delete ↔ Revision/Restore Semantics

> **Root Cause**: RC-06
> **Findings**: M9, N5, N7 (MAJOR/MINOR), plus CP-2（审计 Cross-Phase Risk #2）
> **Depends On**: R05（identity 与软删除判定）
> **Document status**: BLOCKED（等待 R05 ACCEPTED）

---

## 1. Purpose

系统在回收站（`deleted_at` 软删除）语义上存在多处不一致：

- revision 恢复会**悄悄复活**一个在回收站中的资源，却不解决回收站条目（M9）；
- 恢复一个已单独入回收站的 Section/Part 时，父资源可能仍在回收站，结果在“已删除的父”下创建 live 节点
  （N5）；
- `beginLossyOperation` 的 `wasNoOp` 在事务外计算（N7，仅报告）；
- 自动保存草稿把“软删除”当作“永久不存在”，在资源入回收站时**销毁可恢复草稿**（CP-2）。

本 Phase 修复的 contract 是：**“`deleted_at != null` 表示‘在回收站，可恢复’，任何子系统都必须区分
‘软删除’与‘不存在’；revision/restore 不得绕过回收站簿记。”**

## 2. Audit Findings Covered

```text
Primary:
- M9    revision restore 复活已软删除资源，回收站条目残留
- N5    恢复子节点时未检查父资源是否已软删除，产生“已删除父下的 live 节点”

Related:
- N7    beginLossyOperation 的 wasNoOp 在事务外读取 head（报告不准确）
- CP-2  自动保存草稿在软删除时被销毁（审计 Cross-Phase Risk #2；跨 trash 数据丢失）

Test gaps:
- TG9   无“回收站资源的 revision restore”用例
```

## 3. Current Production Architecture

### 3.1 revision 恢复

```text
ResourceStudioPage._confirmRestoreRevision                     (resource_studio_page.dart:414)
  → expectedUpdatedAt = await _revisionController.readResourceUpdatedAt()  (:441-442)
  → ResourceRevisionController.restore                          (:76-113)
  → ResourceRevisionService.restoreRevision                     (resource_revision_service.dart:485-577)
        readRevisionInTransaction / readStateInTransaction
        live = _tree.readLiveState(txn, resourceId)             (:502)  ← 过滤 deleted_at，软删时为 {}
        liveHash = live.isEmpty ? '' : ...
        alreadyAtRevision 判断仅当 liveHash == target.contentHash (:508-520)
        expectedUpdatedAt 校验：_tree.readNodesTimestamps(txn, resourceId)  (:522-538)
             readNodesTimestamps 返回**包含软删行**（resource_tree_repository_impl.dart:1069-1086）
        _capture.captureInTransaction('恢复前')
        _applyTargetState(txn, target.nodes)                    (:548)
             → _upsertRevisionNode(resource 分支)               (resource_tree_repository_impl.dart:832-851)
                  写 'deleted_at': null  ← 无条件清空
        _capture.captureInTransaction('恢复到 ...')
```

`ResourceRevisionService.resourceUpdatedAt`（`:352-358`）同样基于
`readNodesTimestamps`，返回软删行的 token。

### 3.2 回收站恢复

```text
ResourceTrashService.restore → _placeBack                        (resource_trash_service.dart)
  SectionId 分支 :398-428  仅检查父资源行存在
  PartId 分支    :430-491  fallback → createSectionInTransaction   (resource_tree_repository_impl.dart:1272-1309)
                             仅检查资源行存在，不检查 deleted_at
```

### 3.3 自动保存草稿恢复

```text
AutosaveDraftRecovery.reconcile                                  (autosave_draft_recovery.dart:38-76)
  live = readLiveState(...)（过滤 deleted_at）
  live[nodeId] == null → orphaned → deleteDraftInTransaction       (:57-71)
ResourceAutosaveService._writeOne
  on ResourceTreeNotFoundException → _dropJournal                  (resource_autosave_service.dart:492-499)
  ResourceTreeNotFoundException 由 PartContentCommitService 对 !placement.isLive 抛出
```

## 4. Exact Bugs

### Finding M9 — revision restore 复活已软删除资源

#### Trigger
资源 X 在 Resource Studio 的历史面板仍可用时被移入回收站；用户点击某历史版本“恢复”。

#### Current Behavior
1. `readLiveState` 因 `deleted_at` 过滤返回空，`liveHash = ''`，`alreadyAtRevision` 不命中。
2. `expectedUpdatedAt` 来自 `readNodesTimestamps`（返回软删行 token），因此 CAS 用的是删除后的 token，
   **会通过**。
3. `_applyTargetState → _upsertRevisionNode(resource)` 写 `'deleted_at': null`，根节点复活。
4. `resource_trash` 中该资源的未解决条目**未被触碰**。

结果：树行 live、回收站仍有未解决条目，后续“恢复/永久删除”语义错乱。

#### Expected Behavior
对软删除资源拒绝 revision 恢复（提示先恢复或永久删除）；`_upsertRevisionNode` 不得无条件清空根节点
`deleted_at`。

#### Evidence
```text
file: lib/application/resources/resource_revision_service.dart:352-358, 485-577
file: lib/services/repositories/resource_tree_repository_impl.dart:832-851, 1069-1086
既有测试: resource_revision_service_test.dart 的 restore 组从不先入回收站
```

#### User / Data Impact
回收站与树状态不一致；用户对“已删除”资源的预期被破坏；可能造成条目永久无法解决。

---

### Finding N5 — 恢复子节点时父资源仍在回收站

#### Trigger
先单独把某 Section 移入回收站（生成条目），再移动其整个资源入回收站，然后恢复该 Section 条目。

#### Current Behavior
`_placeBack` 的 Section 分支只检查父资源行存在（`timestamps == null` 判定），不检查 `deleted_at`；
Part 分支的 `createSectionInTransaction` 同样只检查资源行存在。于是 `reviveNodeInTransaction` 清除
子节点删除标记，得到“已删除父资源下的 live 子节点”。因根仍 `deleted_at != null`，
`readLiveState` 为空，前后两次 `captureInTransaction` 都返回 null，恢复被报告为成功
（“恢复到原位置”）但内容不可见、无 revision 记录。

#### Expected Behavior
父资源软删除时拒绝子节点恢复（或把整个资源条目一并恢复）；绝不在软删除父下创建 live 节点。

#### Evidence
```text
file: lib/application/resources/resource_trash_service.dart:398-491
file: lib/services/repositories/resource_tree_repository_impl.dart:1272-1309
既有测试: trash 恢复测试只在 live 资源内恢复
```

#### User / Data Impact
恢复报成功但内容不可见；无 revision 记录；用户以为数据回来了。

---

### Finding N7 — `beginLossyOperation` 的 `wasNoOp` 在事务外计算

#### Trigger
在 `beginLossyOperation` 读取 `headBefore` 与事务内 `captureInTransaction` 之间存在并发 capture。

#### Current Behavior
`headBefore` 由 `_revisions.readHead` 在事务外读取（`resource_revision_service.dart:596-597`），事务内
实际 capture 会重新读 head，两者可能不同，`wasNoOp` 成为猜测值（通常错误为 false）。与 P9-I1 已修复的
`captureRevision` 同类问题。

#### Expected Behavior
在事务内读取 `headBefore`，使 `wasNoOp` 与实际 capture 一致。

#### Evidence
```text
file: lib/application/resources/resource_revision_service.dart:588-616
```

#### User / Data Impact
仅报告/展示不准确，无数据变更。

---

### Finding CP-2（审计 Cross-Phase Risk #2）— 软删除销毁自动保存草稿

#### Trigger
资源或其 Part 被移入回收站时，存在已缓冲或已写入 journal 的自动保存草稿。

#### Current Behavior
`AutosaveDraftRecovery.reconcile` 用 `readLiveState`（过滤 `deleted_at`）判断草稿目标是否存在；软删除
节点被判定为 `orphaned` 并 `deleteDraftInTransaction`。flush 路径中 `_writeOne` 收到
`ResourceTreeNotFoundException` 也直接 `_dropJournal`。回收站恢复后只恢复已提交内容，用户最新草稿丢失。

#### Expected Behavior
只要目标处于“回收站中”（存在未解决 trash 条目），草稿必须保留；恢复后再决定是否应用。

#### Evidence
```text
file: lib/application/resources/autosave_draft_recovery.dart:38-76
file: lib/application/resources/resource_autosave_service.dart:492-499
file: lib/application/resources/part_content_commit_service.dart:115-120（!isLive 抛 ResourceTreeNotFoundException）
既有测试: resource_autosave_service_test.dart“a draft for a vanished node is dropped”只覆盖硬缺失
```

#### User / Data Impact
跨回收站的数据丢失：用户以为 30 天内可从回收站恢复，但草稿已不可逆销毁。

## 5. Root Cause

**Symptom**：revision 恢复复活已删资源；子节点恢复出现在已删父下；草稿被销毁。

**Root Cause**：全系统只有“节点是否存在于 live 视图”一个判定（`readLiveState` 过滤 `deleted_at`），
**没有把“软删除”与“不存在”区分开**。revision restore、子节点 restore、autosave 分类器都基于这个
二值判定，于是：

- 软删除被当作“无内容” → `alreadyAtRevision` 失效、`_upsertRevisionNode` 复活；
- 父资源软删除被当作“行存在即可” → N5；
- 草稿目标软删除被当作“永久消失” → CP-2。

这是同一“软删除语义未被所有子系统识别”的根因。

## 6. Required Contract After Remediation

1. 系统必须能区分三态：**live / soft-deleted（回收站）/ absent（永不恢复）**。
2. `ResourceRevisionService.restoreRevision` 对 soft-deleted 根资源必须拒绝（typed error），不得复活。
3. `_upsertRevisionNode` 的 **resource 根分支**不得清空 soft-deleted 根的 `deleted_at`；只有回收站
   `restore` 路径（`reviveNodeInTransaction`）可以恢复根节点。子节点的 revive 仍允许（revision 可能
   包含用户此前删除的 Part）。
4. 子节点 restore 必须校验 owning resource 为 live；否则拒绝或级联恢复整个资源条目。
5. 自动保存草稿的目标为 soft-deleted 时必须保留草稿。
6. 上述判定必须复用同一个“是否软删除”查询（见 R05 的 identity/soft-delete 判定），不得各写一份。
7. `beginLossyOperation.wasNoOp` 必须在事务内计算。
8. 不得削弱既有“恢复前捕获 revision”的行为。

## 7. Implementation Plan

### Step 1 — 统一“软删除判定”辅助（与 R05 对齐）

```text
file: lib/services/repositories/resource_tree_repository.dart（接口）/ _impl
```

确认/新增一个可读 soft-delete 状态的查询（`readNodesTimestamps` 已返回 `deletedAt`，可直接复用）。
所有本 Phase 判定使用 `readNodesTimestamps(...).deletedAt != null`。

### Step 2 — revision restore 拒绝软删除资源（M9）

```text
file: lib/application/resources/resource_revision_service.dart
symbol: restoreRevision (:485-577)
```

在 `db.transaction` 内、`_applyTargetState` 之前插入：

```dart
final rootTimestamps = await _tree.readNodesTimestamps(txn, ResourceId(resourceId.value));
if (rootTimestamps == null) {
  throw ResourceRevisionNotFoundException('资源 ${resourceId.value} 已不存在，无法恢复');
}
if (rootTimestamps.deletedAt != null) {
  throw ResourceRevisionConflictException(
    '资源 ${resourceId.value} 在回收站中，无法恢复到历史版本；请先在资源库中恢复或永久删除。',
  );
}
```

（错误类型以既有定义为准；若需新类型，新增在有明确归属的异常文件。）

删除/替换原先仅依赖 `expectedUpdatedAt` 的软删除盲区。

### Step 3 — `_upsertRevisionNode` 根节点不得复活（M9 防线）

```text
file: lib/services/repositories/resource_tree_repository_impl.dart
symbol: _upsertRevisionNode 的 RevisionNodeKind.resource 分支 (:832-851)
```

- where 改为 `'id = ? AND deleted_at IS NULL'`；
- 移除 `'deleted_at': null`；
- 若 `updated == 0`：查询该行是否存在；存在（被软删）→ 抛 `ResourceTreeConflictException`（或复用
  Step 2 的领域错误）；不存在 → 保持现有 `ResourceTreeNotFoundException`。
- 子节点分支保持不变（允许 revive 被此前删除的 Part/Section）。

### Step 4 — 子节点 restore 校验父资源 live（N5）

```text
file: lib/application/resources/resource_trash_service.dart
symbol: _placeBack 的 SectionId 分支 (:398-428) 与 PartId 分支 (:430-491)
```

- 在两个分支开头，用 owning resource 的 `readNodesTimestamps` 读取 `deletedAt`；非 null 时抛
  `ResourceTrashException('父资源在回收站中，无法单独恢复该节点；请先恢复资源')`。
- `resource_tree_repository_impl.dart` 的 `createSectionInTransaction`（:1272-1309）同样要求资源
  `deleted_at IS NULL`，否则抛 conflict。

### Step 5 — 自动保存草稿保留（CP-2）

```text
file: lib/application/resources/part_content_commit_service.dart
symbol: !placement.isLive 抛 ResourceTreeNotFoundException 处 (:115-120)
```

- 区分“Part 被软删除”与“Part 不存在”：当节点行存在但 `deleted_at != null` 时，抛出带标记的异常
  （例如新增 `ResourceTreeTrashedException`，或在 `ResourceTreeNotFoundException` 上增加
  `bool isSoftDeleted` 字段）。实施时选择与现有异常体系一致的最小方案。

```text
file: lib/application/resources/resource_autosave_service.dart
symbol: _writeOne 的 on ResourceTreeNotFoundException 分支 (:492-499)
```

- 若目标为 soft-deleted：**不** `_dropJournal`，返回一个“目标暂时不可写（在回收站）”的结果
  （可复用 `missingTarget` 但保留 checkpoint 与草稿），并保留在 `_buffer`/journal 中以便恢复后重试。

```text
file: lib/application/resources/autosave_draft_recovery.dart
symbol: reconcile (:38-76)
```

- 在分类前读取该资源的未解决回收站条目（或改为读取含软删除的时间戳）；目标为 soft-deleted 的草稿
  归类为“保留（在回收站）”，不删除。
- 需要一个可注入的“软删除判定”端口（复用 R05 的 trash/时间戳查询），避免 autosave 直接依赖 trash 表。

### Step 6 — `beginLossyOperation` 事务内计算 `wasNoOp`（N7）

```text
file: lib/application/resources/resource_revision_service.dart
symbol: beginLossyOperation (:588-616)
```

把 `headBefore` 的读取移入 `db.transaction`（与 `captureRevision:292-325` 的既有做法一致），再用事务内
读到的 head 计算 `wasNoOp`。

## 8. Design Decisions

### 8.1 M9 用“拒绝”还是“级联恢复回收站条目”

- **方案 A（推荐）**：拒绝，并提示用户先恢复/永久删除。
- 方案 B：自动恢复回收站条目再应用 revision。

**选择 A**。理由：用户点击的是“恢复历史版本”，不是“从回收站恢复资源”；自动出库会带来两个语义的
混淆，且需要跨 trash 服务的写权限。**不采用 B。**

### 8.2 Step 3 是否要求子节点也 live

**否。** 理由：revision 快照可能包含用户已删除的 Part；恢复到该 revision 的语义就是“回到那个状态”，
应允许子节点 revive。只保护根节点，避免“整个资源被软删除却被 revision 复活”。

### 8.3 CP-2 草稿保留策略

**保留草稿直到用户显式放弃或永久删除资源。** 理由：回收站承诺 30 天可恢复；草稿是用户最新输入，
不应先于资源被销毁。**不采用“软删除即销毁草稿”。**

## 9. Database Impact

```text
No schema change required.
```

- 不新增表/列，不修改 `schemaVersion`，不修改 migration。
- 若选择通过新增字段 `ResourceTreeNotFoundException.isSoftDeleted` 传递信息，属代码层，无 schema。
- 回滚为纯代码 revert。

## 10. Concurrency / Sequence

### 10.1 M9 当前 / 修复后

```text
当前:
  resource X in trash (deleted_at != null)
  restoreRevision
    liveHash='' ; CAS uses post-delete token → passes
    _upsertRevisionNode clears deleted_at → ROOT REVIVED
    trash entry still unresolved

修复:
  resource X in trash
  restoreRevision
    rootTimestamps.deletedAt != null → throw conflict
    (no content change, trash entry untouched)
```

### 10.2 N5 当前 / 修复后

```text
当前:
  section entry in bin ; resource in bin
  restore(section entry) → reviveNode(section) under deleted resource

修复:
  restore(section entry)
    owning resource deletedAt != null → throw
```

### 10.3 CP-2 当前 / 修复后

```text
当前:
  draft buffered/journaled
  resource trashed
  reconcile: live[node]==null → delete draft   ← DESTROYED

修复:
  resource trashed
  reconcile: node soft-deleted → retain draft
  user restores resource → draft can be applied
```

### 10.4 并发不变量

```text
不变量1: 未解决 trash 条目存在 ⇔ 根节点 deleted_at != null（除迁移/重建的显式收敛点外）。
不变量2: revision restore 不改变回收站条目状态。
不变量3: soft-deleted 目标的草稿不被删除。
```

## 11. Files Expected To Change

```text
Production（Expected）:
- lib/application/resources/resource_revision_service.dart
- lib/services/repositories/resource_tree_repository_impl.dart
- lib/application/resources/resource_trash_service.dart
- lib/application/resources/resource_autosave_service.dart
- lib/application/resources/autosave_draft_recovery.dart
- lib/application/resources/part_content_commit_service.dart（异常标记）
- 相关异常类型文件

Production（Possible）:
- lib/services/repositories/resource_tree_repository.dart（接口若需新增查询）
- lib/providers/riverpod_providers.dart（注入软删除判定端口）

Tests（Expected，新建）:
- test/application/resources/revision_restore_trashed_resource_test.dart
- test/application/resources/trash_restore_child_requires_live_parent_test.dart
- test/application/resources/autosave_draft_survives_trash_test.dart

Tests（Possible，更新）:
- test/application/resources/resource_revision_service_test.dart
- test/application/resources/resource_trash_service_test.dart
- test/application/resources/resource_autosave_service_test.dart

Docs:
- docs/post-phase12-remediation/STATUS.md

Forbidden / should not be touched:
- 删除/identity 生命周期（R05，本 Phase 仅复用其判定）
- 自动保存 flush 批次原子性（R07；本 Phase 只改软删除分类/保留）
- 生成提交 CAS（R03）
- 流式生命周期（R01）
```

## 12. Test Plan

### TEST R06-01（M9 拒绝）
```text
Given: 资源 X 已软删除且回收站有未解决条目
When:  restoreRevision(某历史版本)
Then:  抛 conflict/typed 错误
       X 仍 deleted_at != null
       回收站条目仍 unresolved
       无新 revision
```

### TEST R06-02（M9 防线：根节点不复活）
```text
Given: 直接调用 _applyTargetState（或等价）在软删除根上
When:  应用包含 resource 根节点的 target
Then:  根节点 deleted_at 不被清空；抛冲突
```

### TEST R06-03（子节点 revive 仍允许）
```text
Given: 资源 live，某 Part 曾删除（软删），revision 快照包含该 Part
When:  restoreRevision
Then:  该 Part 被恢复为 live（子节点 revive 允许）
```

### TEST R06-04（N5 拒绝）
```text
Given: section 条目在回收站，其 owning resource 也在回收站
When:  恢复 section 条目
Then:  抛错误；section 仍 deleted_at != null
```

### TEST R06-05（CP-2 草稿保留）
```text
Given: 资源有 journal 草稿
When:  资源软删除并执行 reconcile
Then:  草稿仍存在（未被删除）
       资源恢复后草稿可被重新应用
```

### TEST R06-06（N7）
```text
Given: 构造 headBefore 与事务内 head 不同的场景（通过并发 capture）
When:  beginLossyOperation
Then:  wasNoOp 与事务内实际 capture 结果一致
```

## 13. Mutation / Negative Verification

```text
Mutation 1: 移除 restoreRevision 的 deletedAt 检查
→ TEST R06-01 必须 FAIL

Mutation 2: 恢复 _upsertRevisionNode resource 分支的 'deleted_at': null
→ TEST R06-02 必须 FAIL

Mutation 3: 移除 _placeBack 的资源 live 检查
→ TEST R06-04 必须 FAIL

Mutation 4: 恢复 reconcile 的“软删=orphaned”分类
→ TEST R06-05 必须 FAIL
```

## 14. Acceptance Criteria

```text
AC-R06-01 软删除资源的 revision restore 被拒绝，回收站条目状态不变。
AC-R06-02 根节点不会被 revision 应用复活；子节点 revive 仍可用。
AC-R06-03 父资源软删除时子节点 restore 被拒绝。
AC-R06-04 软删除目标的自动保存草稿被保留。
AC-R06-05 beginLossyOperation.wasNoOp 准确。
AC-R06-06 全量 flutter test 通过。
```

## 15. Required Verification Commands

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test test/application/resources/revision_restore_trashed_resource_test.dart
flutter test test/application/resources/trash_restore_child_requires_live_parent_test.dart
flutter test test/application/resources/autosave_draft_survives_trash_test.dart
flutter test test/application/resources/resource_revision_service_test.dart
flutter test test/application/resources/resource_trash_service_test.dart
flutter test
git diff --check
git status --short
```

## 16. Out of Scope

- 不重做回收站 UI；
- 不改 revision 裁剪策略（N6 属 R05）；
- 不改 autosave flush 的批次失败隔离（R07）；
- 不新增“自动出库”功能；
- 不删除代码。

## 17. Rollback / Failure Safety

- revision restore 被拒绝 → 资源仍在回收站，用户可正常恢复/永久删除。
- 子节点 restore 被拒绝 → 子节点仍归回收站条目管理，资源恢复后仍可恢复它。
- 草稿保留 → 占用少量 journal 空间，资源永久删除时应联动清理（R05 的 permanentDelete 级联已含
  `resource_autosaves`）。
- 回滚为纯代码 revert。

## 18. OPEN QUESTION

```text
Q1: 子节点 restore 时，是“拒绝”还是“级联恢复整条资源”？本 Phase 默认拒绝（简单、可解释）。
    需要产品确认是否存在“用户只想恢复单个 section”的合法场景。
Q2: 草稿保留的“可注入软删除判定端口”是否复用 R05 新增的端口，还是新增独立端口？
    实现前确认 R05 的端口边界。
```

## 19. Handoff Notes

- R07 与本案共享 `resource_autosave_service.dart`；R06 完成后 R07 再改 `flush` 批次逻辑，避免冲突。
- R11 应为“回收站中的资源”补充装配级测试。
