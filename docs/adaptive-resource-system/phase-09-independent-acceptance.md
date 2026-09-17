# Phase 9 Independent Acceptance — Revision、自动保存与回收站

## Audit Result

```text
Audit Result

Audit HEAD: 161dd7a3d63ea2cf31176b2f732acc4d702cb4a0
Phase:      Phase 9 — Revision、自动保存与回收站
Reviewer:   independent audit agent（只读；未修改任何生产代码或测试）
Baseline:   dbd2303（Start HEAD，== Phase 8 验收后的 main）
Scope:      git diff dbd2303..161dd7a — 62 文件；lib/ +7250/-150 行，test/ +约 5300 行
```

前置条件核对：

| 断言 | 实测 | 结论 |
| --- | --- | --- |
| Phase 8 = `ACCEPTED` | STATUS 表格 + 第三轮独立验收报告 | 成立 |
| Phase 9 = `IMPLEMENTED / READY_FOR_INDEPENDENT_ACCEPTANCE` | STATUS 表格 | 成立 |
| Phase 10 = `BLOCKED` | STATUS 表格 | 成立 |
| 工作区无未提交改动 | `git status --short` 仅 `?? .codebuddy/`（本地工具，未跟踪） | 成立 |
| local HEAD == origin/main | `161dd7a == 161dd7a` | 成立 |

**Final Decision: FAILED** —— 1 BLOCKER + 2 MAJOR + 8 MINOR + 5 INFO。
Phase 9 不予验收，Phase 10 保持 `BLOCKED`。

## Validation

全部命令由审查 Agent 独立重跑（非复用执行 Agent 的输出）：

| 命令 | 实际结果 |
| --- | --- |
| `dart format --output=none --set-exit-if-changed .` | `Formatted 464 files (0 changed)`，exit 0 |
| `flutter analyze` | `No issues found!` |
| Phase 9 定向测试（12 文件） | `205 passed / 0 failed`（18s） |
| 全量 `flutter test` | `1392 passed / 0 failed`（1m54s） |
| `git diff --check` | 干净 |

补充独立实验（不写入仓库，全部在 `/tmp` 的 scratch SQLite 中完成）：

1. **schema 约束真实性探针** —— 从 `database_service.dart` 提取 v41 的真实 DDL（含三条部分唯一索引），
   在 scratch 库中执行并逐一攻击不变量。结果见「Mutation / Fault Injection Evidence」。
2. **revision replay 算法复现** —— 按 `ResourceRevisionMath.applyDelta` +
   `readStateInTransaction` 的真实规则，在真实 DDL 上重放 revision 链。

**未验证范围（明确声明）**：审查角色禁止写入测试文件，因此无法新增 Dart 测试或注入运行时异常；
下列「变异实验」部分是靠「重放真实算法 + 读取真实代码路径 + 检查既有测试在变异下是否会失败」完成的，
不是运行时注入。未在 Linux 桌面上人工操作 UI；UI 结论来自 widget 测试与代码走查。

## Findings

### P9-B1 — BLOCKER

```text
ID: P9-B1
Severity: BLOCKER

Title: Resource 删除未接入回收站；可达路径会硬删除唯一副本，且该资源不会出现在回收站

Evidence:
1. Phase 9 方案 `docs/adaptive-resource-system/phase-09-revisions-autosave-trash.md`
   的「唯一代码范围」明确列出「Resource/Section 删除进入回收站…」，
   要求「Resource 删除」与「Section 删除」同为回收站覆盖范围。
2. 实现只把 Section/Part 接入了回收站，**没有任何生产路径把 Resource 移入回收站**：
   $ grep -rn "deleteNode(" lib/ | grep -v resource_trash_service.dart
     lib/application/resources/section_control_service.dart:279  (deleteSection)
     lib/application/resources/section_control_service.dart:364  (deletePart)
   `ResourceTrashService.deleteNode` 的 ResourceId 分支只被测试覆盖。
3. 资源删除的真实用户路径完全没有回收站、没有 before revision、且硬删除旧表：
   - UI 入口：`lib/screens/resource_library/worldview_tab.dart:135`、
     `character_card_tab.dart:245,430`、`npc_tab.dart:207`、
     `character_card_edit_page.dart:213`、`npc_edit_page.dart:110`、
     `lib/widgets/app_dialogs.dart:1231`
     → `ResourceCrudController.deleteWorldviewPreset` (`lib/controllers/resource_crud_controller.dart:84`)
     → `LibraryRepositoryImpl.deleteWorldviewPreset` (`lib/services/repositories/library_repository_impl.dart:295-302`):
       await _deleteUnifiedResource(id);                      // 仅 softDeleteNode，无 trash 行，无 revision
       await _deleteByMode(db, 'worldview_presets', id, mode); // db.delete(...) 物理删除旧表行
   - `_deleteUnifiedResource` (`library_repository_impl.dart:388-396`):
       final state = await _treeReader.readNodeState(resourceId);
       if (state == null || state.isDeleted) return;           // 无新树行 -> 静默 no-op
       await _treeReader.softDeleteNode(...);
4. Phase 9 没有改动该路径上的任何文件：
   $ git diff --name-only dbd2303..161dd7a | grep -E "resource_crud_controller|library_repository|worldview_tab|character_card_tab|npc_tab"
   -> NO delete-path file was modified by Phase 9
5. 回收站 UI 只做 list/restore/purge，没有任何删除入口写入它：
   $ grep -rn "resourceTrashRuntimeProvider" lib/
     lib/providers/riverpod_providers.dart:486                (定义)
     lib/features/resource_library/presentation/screens/resource_library_screen.dart:312  (打开面板)

Reproduction:
场景 A（已迁移资源，最轻后果）：
  1. 在资源库删除一个世界观（确认框点「删除」）。
  2. 打开「回收站」→ 列表为空，该资源不在其中。
  3. 没有任何 UI 路径可以恢复它（库列表过滤 deleted_at IS NULL；回收站无条目）。
场景 B（旧表是唯一副本时 = 不可逆数据丢失）：
  1. 取一个处于 `ResourceReadFacade` 回退态的资源（`ResourceReadFallbackReason.notMigrated`
     / `migrationFailed` / `sourceChanged` / `treeMissing`，
     见 `lib/application/resources/resource_read_facade.dart:18-24,134-169`）。
     这类资源在资源库中正常列出（`_mergeTreeRows` 以 legacy 行为基准）。
  2. 删除它。
     - `_deleteUnifiedResource`：`readNodeState(ResourceId(legacyId))` 返回 null → 直接 return，
       既不软删除、也不写回收站、也不抓 revision。
     - `_deleteByMode`：`db.delete('worldview_presets', ...)` 物理删除唯一副本。
  3. 结果：内容只剩「已删除」这一事实，没有任何副本、没有 revision、没有回收站条目。
     调用 `ResourceTrashService.restore` 也无从下手（没有 trash 行）。

Expected:
  - 删除必须是 `live → trash`：写入 `resource_trash` 行（含原父节点/排序/原因/过期时间）
    + 抓取 before revision + 软删除；资源出现在回收站且可恢复。
  - 旧表行不得在「普通删除」中被物理删除；物理删除只能由显式二次操作
    （`ResourceTrashService.permanentDelete` / 保留期清理）执行。
  - 旧表是唯一副本时（§`ResourceReadFacade` 回退态）尤其不得物理删除。

Actual:
  - 资源删除完全绕开回收站：不写 trash 行、不抓 revision、不在回收站可见、不可恢复。
  - 旧表行被无条件物理删除（`_deleteByMode` → `db.delete`），对回退态资源即唯一副本销毁。
  - 即「普通删除」直接等价于「永久删除」，与 Phase 9 §十「Permanent Delete 必须是显式二次操作」
    以及方案核心原则「任何…删除操作，都不得造成不可逆的数据损失」直接冲突。

Root Cause:
  回收站能力被实现为**新增服务**（`ResourceTrashService`），但接入点只覆盖了 Studio 的
  Section/Part 命令链（`SectionControlService`），没有替换既有的资源删除链路。
  资源删除链路仍停留在 Phase 1/2/3 的形态——「软删除新树 + 硬删除旧表」——
  这是 Phase 1/2 时代（尚无回收站概念）的写法；
  Phase 9 引入了回收站却未把这条链路改接到 `live → trash`，
  于是「软删除新树」并没有升级为「有回收站记录、有 before revision 的可恢复删除」，
  而「硬删除旧表」这一条不可逆操作被完整保留。
  换句话说：**该交付项被实现了一半（服务有了，入口没有）**，
  而未被接入的那一半恰好包含唯一的不可逆破坏路径。

Affected Files:
  - lib/services/repositories/library_repository_impl.dart:106-123, 388-396, 295-302
    （`_deleteByMode` 硬删除、`_deleteUnifiedResource` 无 trash、三个 delete* 方法）
  - lib/controllers/resource_crud_controller.dart:78-131
  - lib/application/resources/resource_trash_service.dart:82-158（ResourceId 分支无生产调用方，
    且对「无新树行」的旧表资源会抛 ResourceTrashNotFoundException，无法原地补救）
  - lib/application/resources/resource_read_facade.dart:18-24,134-169（回退态定义，说明唯一副本来源）
  - 受影响 UI：lib/screens/resource_library/{worldview_tab,character_card_tab,npc_tab,
    character_card_edit_page,npc_edit_page}.dart、lib/widgets/app_dialogs.dart

Impact:
  - 数据安全：可达路径可永久销毁用户内容（回退态资源），回收站无法恢复。
  - 交付完整性：Phase 9 列出的「Resource 删除进入回收站」未实现；
    回收站对用户最主要、最常用的删除入口（资源库删除资源）完全无效。
  - 一致性：同一产品里「Studio 删除章节」可恢复、「资源库删除资源」不可恢复，行为不一致且无提示。

Required Fix:
  1. 把资源删除改接到回收站（最小改动，保留既有入口签名）：
     `LibraryRepositoryImpl.delete{WorldviewPreset,CharacterCard,NpcCard}`
     先解析出**内容树资源 id**（已迁移/管道创建者即树 id；回退态资源需要先经
     `ResourceReadFacade`/迁移得到树 id，或先落一条 trash 行），再调用
     `ResourceTrashService.deleteNode(id: ResourceId(treeId), expectedUpdatedAt: <token from readNodeState>)`，
     由该服务在同一事务内完成 before revision + trash 行 + 软删除。
  2. 旧表行不得在普通删除中物理删除：
     把 `_deleteByMode` 的调用从 delete* 路径移除，改由永久删除路径执行
     （`ResourceTrashService.permanentDelete` 成功后，或 Phase 12 的旧表清理）。
     在 Phase 12 删除旧表之前，旧表行是回退态资源的唯一副本，必须保留。
  3. `ResourceTrashService.deleteNode` 增加「目标没有内容树行」的确定性分支：
     不得抛 `ResourceTrashNotFoundException`；应先把旧表内容落成一条 before revision
     （或一条 trash 行 + 一个承载内容的树节点），再软删除，保证「删除即入回收站」。
  4. 资源库删除后提示语与状态需反映「已移入回收站，可在回收站恢复」，
     并在回收站面板中可 restore / permanent delete。
  5. 若团队决定「资源删除接线」不属于 Phase 9 而属 Phase 11，则必须：
     在 Phase 9 方案与 STATUS 中显式改写交付范围，并且**必须先消除 `_deleteByMode` 的硬删除**
     （否则数据安全原则仍然被违反）；不得在保留硬删除的情况下把该项移出验收范围。

Required Tests:
  - `deleteWorldviewPreset`（及角色卡/NPC 同路径）删除已迁移资源后：
    `resource_trash` 出现该资源条目；`resources.deleted_at` 非空；
    旧表行**仍然存在**；`ResourceReadFacade` 仍能读到内容。
  - 随后 `ResourceTrashService.restore` 能恢复该资源、其 Section/Part 与顺序（幂等重复调用无副作用）。
  - 回退态资源（构造 `source_changed` / `migrationFailed`）被删除后内容仍可取回，
    断言「删除前后内容逐字符相等」或「回收站条目可恢复出相同内容」。
  - 普通删除不得物理删除任何行：以行数断言 `worldview_presets` / `character_cards` /
    `npcs`（或对应表）在 delete 后行数不变。
  - 只有 `permanentDelete` / 保留期清理会真正删除行（对照用例，断言 `resource_trash` 与旧表行同时消失）。
```

### P9-M1 — MAJOR

```text
ID: P9-M1
Severity: MAJOR

Title: publishAssemblyRevision 把「全量 upsert」当作「相对父 revision 的增量」写入，
       导致 assembly 状态重建时无法反映节点删除（复活已删除节点）

Evidence:
  实现（lib/application/resources/resource_revision_service.dart:414-431）：
    await _revisions.insertRevisionInTransaction(
      txn,
      kind: ResourceRevisionKind.assembly,
      cause: RevisionCause.migration,
      parentRevisionId: (await _revisions.readHeadInTransaction(txn, ..., assembly))?.revisionId,
      deltas: state.nodes.values.toList(),   // <-- 全量快照，且全为 isRemoved = false
      ...
    );
  `readStateInTransaction` 只能靠 `isRemoved` 墓碑删除节点：
    - ResourceRevisionMath.applyDelta: `if (delta.isRemoved) next.remove(id) else next[id] = delta`
    - state.nodes 由 applyDelta 重建，map 内**永远不含墓碑项**，因此转成 deltas 后一个删除都不表达。
  对比：同一文件里 latestHead 链由 `captureInTransaction` 写入，
  使用 `ResourceRevisionMath.diff(parent: parentState, current: live)`（会生成墓碑）；
  `rerootInTransaction` 则把 `parent_revision_id` 置 NULL（全量快照语义）。
  只有 `publishAssemblyRevision` 处于「保留了 parent 却写入全量 upsert」的第三种、错误形态。

Reproduction（可执行证据，见 Mutation / Fault Injection Evidence 第 2 项）：
  在真实 v41 DDL 上按真实 replay 规则重放：
    1. assembly A1（parent NULL，delta = {S,P1,P2}）  -> replay = [P1, P2, S]
    2. P2 被删除；用 publishAssemblyRevision 再发布 A2（parent = A1，delta = {S,P1}）
       -> replay(A2) = [P1, P2, S]      ← P2 复活
       期望 = [P1, S]
  `readState` 会用重建结果**重新计算** contentHash，而 `resource_revisions.content_hash`
  存的是发布时的 hash ⇒ 同一 revision 的「列内 hash」与「重建 hash」不一致。

Expected:
  assembly revision 的重建状态必须等于被发布的那份 latestHead 状态；
  「新状态不含某节点」必须在链上表达为墓碑（或让该 revision 成为无 parent 的快照）。

Actual:
  重建状态是被发布状态的**超集**：任何在旧 assembly 状态中存在、在新状态中消失的节点都会复活。
  同时 `select()` 仍会报 `ready`（它比较的是列内 hash，两份相同），
  于是「指针新鲜」与「内容正确」被解耦，调用方会拿到一份含幽灵节点的快照。

Root Cause:
  把「revision 存储的是相对父的增量」这条契约，与「我有一个完整 state，想原样存下来」混为一谈。
  `insertRevisionInTransaction` 只是把传入 deltas 落库，不做 diff，也不校验
  「非空 parent 时必须提供墓碑」；调用方（本方法）因此把一个只含 upsert 的集合挂到了非空 parent 上。
  缺少的是一层契约守卫：非根 revision 的 delta 必须相对 parent 计算。

Affected Files:
  - lib/application/resources/resource_revision_service.dart:378-433（publishAssemblyRevision）
  - lib/application/resources/resource_revision_repository.dart:196-262
    （insertRevisionInTransaction，无「非空 parent 必须提供墓碑」守卫）
  - 消费方（Phase 10）将通过 `ResourceRevisionSelector.select()` + `readState` 读取该状态

Impact:
  - 数据正确性：assembly 快照会包含已删除内容；任何以 assembly 为事实源的消费方
    （Phase 10 Adventure 组装）会注入幽灵节点。
  - 契约不一致：`content_hash` 列与重建 hash 分叉，破坏「hash 用于检测 head 变化」的设计前提。
  - 当前无生产调用方（`grep -rn publishAssemblyRevision lib/` 仅定义），
    因此暂未产生线上错误；但该实现会在 Phase 10 接线时立刻生效，属「已埋下的错误」。

Required Fix:
  方案 A（推荐，与 captureInTransaction 一致）：
    在事务内先读取当前 assembly head 的重建状态 parentState，再
      deltas: ResourceRevisionMath.diff(parent: parentState, current: <目标状态 nodes>)
    这样删除会落成墓碑，语义与 latestHead 链统一。
  方案 B（更简单，语义略重）：
    parentRevisionId: null 且 deltas = 全量快照，与 `rerootInTransaction` 一致；
    代价是每次发布都写一份完整状态，失去增量收益。
  另建议在 `insertRevisionInTransaction` 增加契约守卫/断言：
    非空 parent + 无任何 isRemoved 且节点数少于 parent 状态时，视为可疑并拒绝或记录，
    避免后续再有调用方落入同一形态。

Required Tests:
  - 「发布两次且第二次状态更小」：断言 `readState(A2).nodes.keys == 源 latestHead 状态的 keys`
    （现有用例只发布一次，完全覆盖不到）。
  - 断言 `readState(revisionId).contentHash == <该 revision 行的 content_hash>`（列与重建一致）。
  - 「删除一个 Part 后重新发布 assembly，再读 assembly 状态」不得出现已删除 Part。
  - 反向用例：新增一个 Part 后重新发布，assembly 状态必须包含它（防止修复过度）。
```

### P9-M2 — MAJOR

```text
ID: P9-M2
Severity: MAJOR

Title: 自动保存一旦发生冲突便在同一编辑器会话中永久无法再保存；
       journal 草稿没有任何生产消费路径，编辑器显示的也不是草稿内容

Evidence:
  1. 编辑器只在「写入成功」时刷新基线 token
     （lib/features/resource_studio/presentation/widgets/resource_studio_part_editor.dart:116-138）：
       void _onFlushed(AutosaveFlushResult result) {
         ...
         if (result.applied > 0) { widget.onSaved(...); unawaited(_refreshToken()); }
       }
       Future<void> _refreshToken() async { final t = await widget.readUpdatedAt(); if (t != null && mounted) _updatedAt = t; }
     而每次输入都用当前 `_updatedAt` 作为 CAS 基线（同文件:100-107）：
       _autosave.schedule(..., expectedUpdatedAt: _updatedAt);
     ⇒ 冲突（applied == 0）时 `_updatedAt` 不刷新，后续每次 flush 继续用同一个陈旧 token。
  2. 服务层确认冲突是稳定的失败态
     （lib/application/resources/resource_autosave_service.dart:341-349）：
       on ResourceTreeConflictException -> status = conflict，**保留** journal 行（有意为之）。
     写入路径本身的 CAS（`_applyGuardedUpdate`: `WHERE id=? AND updated_at=? AND deleted_at IS NULL`）
     在 token 陈旧时必然 0 行 → 永远冲突。
  3. 自我制造的冲突窗口：`maxBufferedAge`（5s，domain/resource_autosave.dart:135）会在**用户持续输入时**
     强制 flush（service `_armTimer`），而 `_refreshToken()` 是异步 DB 读取；
     这期间用户的下一次击键就会用旧 token 入队 ⇒ 下一次 flush 冲突。
  4. 冲突后无恢复通道：
     - `reconcilePendingDrafts` 在生产代码中**零调用方**：
       $ grep -rn "reconcilePendingDrafts" lib/  → 仅 resource_autosave_service.dart 定义 + domain 注释
     - 编辑器重新打开时显示的是**树内容**而非 journal 草稿
       （resource_studio_page.dart:159-167: `state.partContents[partId] ?? part.content`）。
     - 用户重新打开编辑器后若继续输入，journal 行会被同 node 的 upsert 覆盖
       （`idx_resource_autosaves_node` 唯一）并在成功提交时删除 ⇒ 卡住期间的文本最终消失。

Reproduction:
  1. 打开 Resource Studio，选中一个 Part，点「编辑正文」。
  2. 持续快速输入 > 5 秒（不要停顿 700ms 以上），越过一次 maxBufferedAge 强制 flush。
  3. 观察：状态栏出现「保存冲突：内容仍保留在草稿中，未覆盖较新的版本」。
  4. 继续输入任意内容并等待 —— 状态在「编辑中…」与「保存冲突」之间反复，树内容始终不更新。
  5. 关闭并重开编辑器（「完成编辑」→「编辑正文」）：显示的是树内容，
     卡住期间输入的文字不在编辑器中，也无任何入口可取回。

Expected:
  - 单次冲突后，用户的下一次编辑应能正常保存（基线 token 重新同步，或服务端重读 token 后重试）。
  - journal 中的草稿必须有生产消费路径（恢复提示 / 冲突解决 UI），
    或者冲突文案不得声称「内容仍保留在草稿中」而不给出取回方式。

Actual:
  - 冲突是**粘性**的：`_updatedAt` 不刷新 ⇒ 本会话后续所有保存都失败，且文案在每次击键后被「编辑中…」覆盖。
  - 唯一可能取回文本的 `reconcilePendingDrafts` 无调用方；编辑器展示的是树内容。
  - 换句话说：自动保存（本阶段的核心交付之一）在「连续输入」这一常见场景下会停止工作，
    用户看到的是持续冲突，且被 journal 保住的文本对用户不可达。

Root Cause:
  基线 token 的所有权与刷新时机设计错误：
  (a) 刷新只在成功路径发生，而冲突恰恰是「token 已失效」的信号——此时才是最需要重读 token 的时刻；
  (b) 刷新是异步副作用，flush 完成与 token 更新之间存在窗口，而输入事件不受该窗口约束，
      可继续用旧 token 入队（自我制造冲突）；
  (c) 冲突态被当作「只报告」处理，没有重试或恢复策略，同时该阶段又移除了对草稿的消费路径，
      使「文本仍在草稿里」成为对用户无效的承诺。

Affected Files:
  - lib/features/resource_studio/presentation/widgets/resource_studio_part_editor.dart:100-138
  - lib/application/resources/resource_autosave_service.dart:255-360（flush/_writeOne/conflict 分支）
  - lib/application/resources/part_content_commit_service.dart:98-158（CAS 失败即抛冲突）
  - lib/features/resource_studio/presentation/pages/resource_studio_page.dart:159-167, 280-300

Impact:
  - 用户数据：未确认文本被持久化到 `resource_autosaves` 但不可达；重开编辑器后继续输入会覆盖并删除它，
    最终等同于丢失（不是「已确认数据丢失」，但确实是「用户写了却拿不回来」）。
  - 功能可用性：自动保存是 Phase 9 的核心交付，在连续输入（真实写作场景）下会静默停止工作。
  - 与方案要求冲突：§五要求「频繁输入 → 内存累积 → debounce → checkpoint」并保证
    「生命周期结束时强制 flush 已确认内容」；当前实现把 checkpoint 写进了 journal，
    却无法把它推进到正文树，也没有 resume 手段。

Required Fix（建议组合，任一项单独都不够）：
  1. **每次都同步基线**：把 token 刷新从「仅成功」改为「每次 flush 结束都重读」；
     更彻底的做法是把 token 所有权下移到 `ResourceAutosaveService`/`PartContentCommitService`
     ——写前自行读取当前 `resource_parts.updated_at`，编辑器不再传 token，
     从根上消除「UI 持有过期 token」这一类竞态
     （仍保留 CAS：服务端读到 token 后立即用它与写入同事务校验）。
  2. **冲突后有限重试**：content 已在 journal 中，冲突时重读当前 token 并重试**一次**；
     仍失败才进入冲突态（避免重复覆盖他人刚写入的内容）。
  3. **给草稿一个生产出口**：在 `_startEditing` / Studio 载入时调用
     `reconcilePendingDrafts(resourceId)`；对 `needsUserDecision` 的草稿在编辑器中提示
     「发现未保存的草稿（时间戳）」并提供「载入草稿 / 丢弃草稿」；
     否则应删除该方法与相关 domain 类型，并把冲突文案改为不承诺草稿可取回。
  4. 冲突文案不应被下一次击键的「编辑中…」静默覆盖（冲突需要保持可见直到被解决）。

Required Tests:
  - **连续输入跨 maxBufferedAge**：模拟 t=0..6s 每 150ms 一次 `schedule`，中途触发一次
    强制 flush，随后继续输入并让 debounce 到期 —— 断言最终树内容 == 最后输入文本（当前会失败）。
  - **冲突后可恢复**：构造一次 CAS 冲突（另一写入者先提交），随后再输入并 flush ——
    断言该次写入成功（applied == 1），当前会连续冲突。
  - **草稿可见性**：存在 pending journal 行时打开编辑器（或调用 reconcile），
    断言 UI 提供载入草稿的路径、或断言冲突文案不再声称可取回（二选一，取决于修复取向）。
  - 反向用例：并发/外部写入确实更新了正文时，陈旧 autosave **不得**覆盖它
    （保护 P9-M2 的修复不引入 lost update；现有 `a stale token keeps the text in the journal…` 覆盖此点）。
```

### P9-M3 — MINOR

```text
ID: P9-M3
Severity: MINOR

Title: revision 保留期清理无生产调用方，链永久增长；每次 capture 需重放整条链（O(history)）

Evidence:
  $ grep -rn "pruneRevisions" lib/
    lib/application/resources/resource_revision_service.dart:695   (仅定义)
  Phase 9 方案 §十「清理策略」与 STATUS「Cleanup」都把它列为交付项；
  对比：trash 的 `purgeExpired` 已接线
  （lib/features/resource_library/presentation/controllers/resource_trash_controller.dart:38）。
  每次 capture 都会重放整条父链：
  `RevisionCaptureEngine.captureInTransaction` -> `_revisions.readStateInTransaction(head)`
  -> `readChainInTransaction` + 逐 revision `_readDeltas`。

Reproduction:
  1. 在 Studio 中反复编辑同一 Part 数十次（每次触发一次 autosave checkpoint）。
  2. `SELECT COUNT(*) FROM resource_revisions WHERE resource_id=? AND kind='latestHead'` 持续增长，永不下降。
  3. 观察下一次 capture 发出的读语句数随链长线性增长（可用现有 SQL 计数式断言复现）。

Expected: 超过保留期且不被 head/assembly/回收站引用的 revision 前缀被清理并根化保留者。
Actual: 清理从不运行；链无限增长，capture/readState/restore 的 DB 往返随历史线性增长（整体 O(n²) 会话成本）。
Root Cause: 实现交付了清理算法但没有调度点；Phase 9 未提供任何启动/后台/编辑生命周期钩子调用它。
Affected Files: lib/application/resources/resource_revision_service.dart:695-851；providers 组合根；main.dart 启动钩子。
Impact: 存储与延迟随时间退化（长会话/高频编辑尤其明显）；§十交付项处于「存在但从不生效」状态（无法被验收证明）。
Required Fix: 在明确的生命周期点调用 `pruneRevisions`（例如 Studio 资源切换/离开编辑器，与
  `CompressionBackgroundWorker.onEditorLeave` 同一层；或 main.dart post-frame 启动钩子），
  并传入与 `RevisionRetentionPolicy.defaultRetention` 一致的保留期；同时确保清理与 Studio 写路径不互相阻塞。
Required Tests: 定向测试断言「调用清理后，超过保留期的前缀被删除且保留者被根化、head 仍可重放」已存在；
  需新增「生产生命周期确实会触发清理」的接线测试（例如离开编辑器后触发一次 prune）。
```

### P9-M4 — MINOR

```text
ID: P9-M4
Severity: MINOR

Title: 压缩发布在上层硬编码 alreadyApplied=false，与实际「未改动任何内容」的结果不一致

Evidence:
  lib/application/resources/resource_compression_publisher.dart:102-136：
    内层若发现 `existing.content == compressedContent` 会提前返回 alreadyApplied: true（且不建 revision），
    但外层返回语句写死 `alreadyApplied: false` 并带上 `savedCharacters`：
      return CompressionPublishOutcome(..., alreadyApplied: false, savedCharacters: candidate.savedCharacters, ...);
  该结果被 UI 直接用于文案（lib/features/resource_studio/presentation/controllers/resource_capacity_controller.dart）：
      '已发布压缩结果，节省约 ${outcome.savedCharacters} 字；压缩前内容已记录为历史版本'

Reproduction: 让 Part 正文预先等于候选的 compressedContent（例如用户手工粘入），再点「发布压缩结果」。
Expected: 报告「已发布过 / 未改动正文」，且不声称节省字数、不声称新建了历史版本。
Actual: 报告「已发布压缩结果，节省约 N 字；压缩前内容已记录为历史版本」——三处均不成立。
Root Cause: 外层没有把内层的 `CompressionPublishResult.alreadyApplied` 透传出来；
  `savedCharacters` 取自候选的静态统计而非本次实际变更量。
Affected Files: lib/application/resources/resource_compression_publisher.dart:102-136；capacity runtime/controller 文案。
Impact: 用户被误导（以为内容被压缩、以为历史里多了版本）；无数据破坏。
Required Fix: `alreadyApplied: result.alreadyApplied`，并在 alreadyApplied 时把 savedCharacters 置 0、
  文案改为「该压缩结果已生效，未改动正文」。
Required Tests: 预置正文等于候选内容 → 发布 → 断言 alreadyApplied 为 true、savedCharacters 为 0、
  revision 数量不变。
```

### P9-M5 — MINOR

```text
ID: P9-M5
Severity: MINOR

Title: 生产 restore（版本历史恢复）未传 expectedUpdatedAt，缺少并发 CAS

Evidence:
  lib/features/resource_studio/application/use_cases/resource_revision_runtime.dart:45-48：
    final result = await _service.restoreRevision(ResourceRevisionId(revisionId));   // 无 token
  `restoreRevision(expectedUpdatedAt:)` 的 CAS 分支因此从不生效
  （lib/application/resources/resource_revision_service.dart:484-500）。
Reproduction: 编辑器 A 打开版本历史；用户 B（或生成任务）在此期间写入该资源；A 点「恢复」——
  恢复基于陈旧 UI 快照执行，覆盖掉 B 刚写入的内容（B 的内容仅存在于 before revision 中）。
Expected: 与手动编辑/删除一致，恢复也应带 `expectedUpdatedAt`（或等价 expected head）进行 CAS，
  冲突时提示用户「内容已变化，请刷新后重试」。
Actual: 无 CAS，静默覆盖（可通过版本历史找回，因此不是不可逆损失）。
Root Cause: runtime 适配层没有把 token 纳入接口；`RevisionRestoreSummary` 也未携带资源 token 供 UI 使用。
Affected Files: lib/features/resource_studio/application/use_cases/resource_revision_runtime.dart；
  lib/features/resource_studio/presentation/controllers/resource_revision_controller.dart；
  lib/features/resource_studio/presentation/pages/resource_studio_page.dart。
Impact: 并发编辑可被恢复动作覆盖（可从历史恢复，故为 MINOR）；与 §十四「stale version」要求不符。
Required Fix: 在 restore 前读取资源 `updated_at`（Studio 已有 `readNodeState`/资源载入链路可复用），
  经 runtime 传给 `restoreRevision(expectedUpdatedAt:)`；冲突时返回用户可理解的提示。
Required Tests: 恢复前由另一路径修改资源 → 恢复必须抛冲突且树内容不变（现有
  `a stale token refuses the restore...` 只覆盖 service 层带 token 的情况，需补 UI 链路的 token 传递）。
```

### P9-M6 — MINOR

```text
ID: P9-M6
Severity: MINOR

Title: 对已被父节点级联删除的节点再次 deleteNode 会抛冲突异常，而非幂等无操作

Evidence:
  lib/application/resources/resource_trash_service.dart:95-105：
    if (!placement.isLive) {
      final existing = await _repository.findActiveEntryForNodeInTransaction(txn, id.value);
      if (existing == null) throw ResourceTrashConflictException('节点 … 已被删除，但回收站缺少对应记录');
      ...
    }
  级联删除（`softDeleteNodeInTransaction`）只给被删的父节点写 trash 行，
  其子节点没有自己的条目 ⇒ 对子节点调用 deleteNode 必走 throw 分支。
Reproduction: 先删除 Section（其 Parts 被级联软删除），再对其中一个 Part 调用 deleteNode。当前 UI 不可达，
  但该状态在「用户删父节点后 UI 仍持旧子节点 id」或未来脚本/批量操作下是可达的。
Expected: 已是删除态且无自身条目的节点应返回幂等结果（或补齐一条 trash 行），而不是抛异常。
Actual: 抛 ResourceTrashConflictException，调用方无法区分「并发冲突」与「早已被级联删除」。
Root Cause: 幂等分支只覆盖「有自己的 trash 行」的子情形，遗漏「被祖先级联删除」这一最常见形态。
Affected Files: lib/application/resources/resource_trash_service.dart:95-105。
Impact: 特定时序下删除操作报错而非无操作（无数据损失）。
Required Fix: 在该分支区分两种情形：无自身条目时返回
  `TrashDeleteResult(alreadyDeleted: true, entry: <祖先条目或合成视图>)`，
  或为被级联删除的节点补写一条 `TrashReason.userDelete` 条目后再返回幂等结果。
Required Tests: 删除 Section 后对其 Part 调用 deleteNode → 断言不抛异常、树/回收站状态不变。
```

### P9-M7 — MINOR

```text
ID: P9-M7
Severity: MINOR

Title: assembly revision 永不进入清理候选；「assembly 链被保护」的说法实为空泛

Evidence:
  `_pruneOneChain`（resource_revision_service.dart:754-851）只从 **latestHead** head 构造 chain：
    final chain = await _revisions.readChainInTransaction(txn, head.revisionId);
    final doomed = chain.take(keepFrom)...;
  assembly revision 属于独立链（publishAssemblyRevision 的 parent 也是 assembly），
  不可能出现在 latestHead 的祖先链中 ⇒ 既不会被删除，也不会被真正「保护」（protectedIds 里的
  assembly head 项在 chain 上永远匹配不到）。
  API 文档（同文件:686-694）声称「the published assembly head and everything its chain needs」被保护，
  该声明在行为上正确但具有误导性：真实机制是「assembly 链根本不在候选集内」。
Reproduction: 多次 publishAssemblyRevision 后运行 pruneRevisions →
  `SELECT COUNT(*) ... WHERE kind='assembly'` 不下降。
Expected: 清理应覆盖 assembly 链（保留 assembly head 及其祖先，删除更老前缀并根化），
  或明确记录「assembly 链不做保留期清理」并让文档与实现一致。
Actual: assembly 链无限增长；文档措辞暗示了并不存在的保护逻辑。
Root Cause: 清理实现按 kind 单一链设计，没有为 assembly 链做第二遍处理；保护集合与候选集合的
  关系未在代码层校验（保护项不属于候选集时无告警）。
Impact: 存储缓慢增长（每条 assembly 发布写一份全量快照）；文档与实现的可信度问题（非数据安全问题）。
Required Fix: 要么对每种 kind 各跑一遍 `_pruneOneChain`（装配链同样「保留 head + 根化保留者 + 删前缀」），
  要么在文档与常量中显式声明 assembly 链不参与清理；并在 protectedIds 与 chain 无交集时记录诊断信息。
Required Tests: 发布多次 assembly 后运行清理，断言 assembly 链按同一规则收缩且 assembly head 仍可重放。
```

### P9-M8 — MINOR

```text
ID: P9-M8
Severity: MINOR

Title: SectionControlRuntime.deletePart 无任何 UI/生产调用方（死代码）

Evidence:
  $ grep -rn "deletePart" lib/ → 只有
    lib/features/resource_studio/application/use_cases/section_control_runtime.dart:63,185,190
  （接口 + 适配器实现），没有 widget/controller 调用。
Reproduction: 静态检索即可。
Expected: 要么提供删除 Part 的 UI 入口（回收站已支持 Part 恢复，能力已具备），要么不暴露该 API。
Actual: 已接线到 `SectionControlService.deletePart` → `ResourceTrashService`，但无人调用。
Root Cause: 为「Part 删除也应进回收站」预留了通道，但未同步提供 UI 动作（能力已实现，入口缺失）。
Impact: 无功能风险；增加表面积与「看似已支持」的误判风险。
Required Fix: 在 `ResourceStudioPartCard`/编辑器提供「删除此段落」（走回收站，二次确认），
  或删除该 runtime 方法直到有需求（AGENTS.md「先复用后新增」与避免死代码）。
Required Tests: 若保留，则补一个 widget 测试证明入口可达并走回收站；否则无需新增。
```

### P9-M9 — MINOR

```text
ID: P9-M9
Severity: MINOR

Title: 保存覆盖后的 after 抓取被标成「保存前快照」，版本历史展示错误标签

Evidence:
  lib/application/resources/resource_creation_pipeline.dart:
    _captureRevisionAfterOverwrite(...) → captureAfterWrite(..., label: '保存前快照')
  该 label 会经 `listRevisions` 进入 UI（`ResourceRevisionItem.title` 优先使用 label）。
Reproduction: 在资源库保存一个已有世界观 → 打开 Studio 版本历史 →
  新版本条目显示「保存前快照」，而它描述的是保存**之后**的状态。
Expected: after 抓取应使用「保存后（自动记录）」之类的标签；before 抓取才叫「保存前快照」。
Actual: after 抓取被标为「保存前快照」，用户看到的历史语义颠倒。
Root Cause: 两个辅助方法共用同一文案常量，after 方法传入的 label 是 before 的语义。
Impact: 版本历史文案误导（无数据影响）。
Required Fix: after 抓取改为 `label: '保存后快照'`（或空 label，让 cause 显示「手动保存」）。
Required Tests: 保存后读取 history，断言最新条目的 label 不表示「保存前」。
```

### INFO

```text
ID: P9-I1  Severity: INFO
Title: captureRevision 的 headBefore 在事务外读取，wasNoOp 在并发下可能误报
Detail: resource_revision_service.dart:297-317 先 `readHead` 再开事务；两个并发 capture 时
  后者的 headBefore 可能已是前者刚写入的 head，导致 wasNoOp 判定与实际写入不符。
  影响仅限报告字段（无数据影响）。建议在事务内读取 head 用于计算 wasNoOp。

ID: P9-I2  Severity: INFO
Title: confirmBlueprint 的「资源已存在」分支覆盖整棵树且无 revision 抓取
Detail: lib/application/resources/resource_blueprint_repository.dart:345-350 调用
  updateResourceTreeInTransaction（该方法会先删除全部 Section/Part 再重建），Phase 9 未在此抓取 revision。
  可达性判定：进入该分支要求 blueprint.status == draft 且 session ∈ {planning, persisted}
  （同文件:219-253），而 confirm 成功后 session 被标记 completed、blueprint 变 confirmed
  （重复 confirm 走幂等早退），因此当前**不可达于已有确认内容的资源**。
  登记为风险：若 Phase 10/11 允许重规划，这里必须补 before/after 抓取，否则会成为整树覆盖的无版本写入。

ID: P9-I3  Severity: INFO
Title: 缺少「edit → restore → stale autosave」交错测试
Detail: phase9_concurrency_test.dart 覆盖 autosave×生成/重生成/删除、双恢复、清理×恢复、
  stale head、发布×抓取、退出/取消/失败/崩溃，但没有「先编辑入队 → 恢复 → 旧 debounce 生效」。
  机制上安全（恢复会 bump updated_at，旧 token 的 CAS 失败 → 不会覆盖恢复结果），
  但缺少把该保证固定下来的用例。

ID: P9-I4  Severity: INFO
Title: TrashReason 目前只有单一取值
Detail: resource_trash.dart 的 TrashReason 仅有 userDelete；注释已说明为前向兼容。
  可接受，但在出现第二个原因（如 supersededByRegeneration）之前该枚举不携带信息。

ID: P9-I5  Severity: INFO
Title: Phase 7 D2 门控放开被 Phase 8 验收记录为「option B」，STATUS 未标注 supersede
Detail: 本次放开（resource_studio_section_controls.dart:_canRegenerate）是 Phase 8 D2
  「option A 属 Phase 9」的正当收口，实施报告亦有说明；但 Phase 8 收尾段落仍写着
  「不实现受控重置」且第三轮验收据此判定，建议 STATUS 显式标注该决定已在 Phase 9 被取代，
  避免后续审计误判为对已验收行为的无授权修改。
```

## Mutation / Fault Injection Evidence

审查角色禁止写入测试或修改源码，因此变异实验以「在真实 schema 上重放真实算法 + 走查真实代码路径 +
核对既有测试在该变异下是否会失败」完成。以下逐项说明结论与证据强度。

### 实验 1：schema 不变量是否真的被保护（真实 DDL，scratch SQLite）

从 `lib/services/database_service.dart` 提取 v41 全部 18 条 `CREATE TABLE/INDEX`（含 3 条部分唯一索引），
在 `/tmp` 内存库中执行后攻击每条不变量：

| 攻击 | 结果 |
| --- | --- |
| 同一 `(resource_id, kind)` 插入第二个 head | **ENFORCED**（IntegrityError，部分唯一索引生效） |
| 同一 resource 的 assembly head 插入第二个 | **ENFORCED** |
| 不同 resource 各自持有 head | OK |
| 清旧 head 标志后插入新 head（生产 head 翻转） | OK |
| `resource_revision_nodes` 指向不存在的 revision | **ENFORCED**（FK） |
| 删除 revision 后其节点行 | 级联删除（remaining=0） |
| 同一 node 第二条未解决 autosave 草稿 | **ENFORCED** |
| 同一 node 第二条 ACTIVE trash 条目 | **ENFORCED** |
| 已恢复（restored_at 非空）后对该 node 再删除 | OK（可再次入回收站） |
| 陈旧 `updated_at` 的 CAS 更新 | 命中 0 行（乐观锁有效） |
| 当前 `updated_at` 的 CAS 更新 | 命中 1 行 |
| 软删除行的 CAS 更新 | 命中 0 行 |
| 删除 resources → sections/parts 级联 | 全部清空 |

结论：**§十二「约束是否真的保护业务不变量」成立**。执行 Agent 关于 schema 的声明经独立复现属实。

### 实验 2：revision replay 算法能否发现 assembly 缺陷（真实算法 + 真实 DDL）

按 `applyDelta`/`readStateInTransaction` 的真实规则重放：

```text
A1 = assembly(parent NULL, delta {S,P1,P2})            replay = [P1, P2, S]
A2 = assembly(parent A1,   delta {S,P1})   ← publishAssemblyRevision 的写法
                                                       replay = [P1, P2, S]   ← P2 复活
期望                                                    [P1, S]
L1 = latestHead(parent NULL, delta {S,P1,P2})
L2 = latestHead(parent L1, delta {P2 tombstone})       replay = [P1, S]       ← 正确
```

结论：**同一 replay 规则下，latestHead 链正确、assembly 链错误** —— 证明缺陷在
`publishAssemblyRevision` 的 delta 构造，而非存储或重放层。→ P9-M1 成立。

### 实验 3：Mutation 1（禁用/延迟 autosave version guard）

- 变异方式：移除 `_applyGuardedUpdate` 的 `updated_at = ?` 谓词（等价去掉版本守卫）。
- 探测该变异的既有测试：
  `resource_autosave_service_test.dart:484『a stale token keeps the text in the journal instead of losing it』`
  断言 `result.conflicted == 1` 且 `liveContent() == '原始正文'`。
- 判定：守卫被移除后该写入会成功（applied=1）→ 两条断言均失败。
- 结论：**该变异能被测试捕获**（覆盖充分）。此实验同时确认：陈旧 autosave 不会覆盖较新内容，
  即「edit → restore/generation 提交 → 旧 debounce 生效」不会产生 Lost Update。

### 实验 4：Mutation 2（在 revision 创建与 head 更新之间注入异常）

- 结构性证据：`insertRevisionInTransaction` 的 `UPDATE is_head=0` 与 `INSERT ... is_head=1`
  使用调用方传入的 `DatabaseExecutor`，与业务写入同一事务；任何异常都会回滚整体。
- 已存在的等价故障注入用例（会在变异下失败）：
  - `resource_trash_service_test.dart`『a stale token refuses the delete』：
    失败发生在 before 抓取**之后**，断言 `countRevisions == 0` ⇒ 证明「已创建的 revision 随事务回滚」。
  - `phase9_revision_boundary_test.dart`『a failed publish leaves both the body and applied_at untouched』：
    失败发生在 `applied_at` 已写入**之后**，断言 `applied_at` 仍为 NULL ⇒ 证明 claim 与内容写入同事务。
  - `resource_revision_service_test.dart`『a failed restore rolls back the revision it tried to record』：
    断言失败恢复后 revision 数量不变。
- 结论：**「revision 已推进但内容没写完」「内容已覆盖但 before revision 没创建」两类形态均被结构性排除且有用例固定**。

### 实验 5：Mutation 3（restore 之后陈旧 debounce 生效）

- 走查：`applyRevisionState` → `_upsertRevisionNode` 会写 `updated_at = now`，
  陈旧 autosave 携带旧 token ⇒ CAS 命中 0 行 ⇒ 冲突、不覆盖。
- 判定：**不得覆盖 restored state（性质成立）**；但冲突后的粘性失败见 P9-M2（另一个独立缺陷）。
- 缺口：无专门用例固定该交错（→ P9-I3）。

### 实验 6：Mutation 4（删除 parent 后 restore Section）

- 既有用例覆盖三种形态且通过：
  `resource_trash_service_test.dart`『a missing parent falls back to a new section under the root』
  『a parent still in the bin also triggers the fallback』
  『a section whose resource is gone fails explicitly and keeps the entry』
  『a Part whose own row is gone fails instead of pretending』。
- 结论：**fallback 合法且不丢内容**；父节点不存在时不会静默失败，条目保留。

### 实验 7：Mutation 5（清理看到「已过期但仍被引用」的 revision）

- 走查 + 既有用例：
  - `never deletes the current head`（clamp 保证 head 存活）
  - `never deletes a revision an unresolved bin entry points at`（`protectedIds` 生效）
  - `never deletes a revision an assembly pointer still needs`（实际机制见 P9-M7，用例通过但保护是空泛的）
  - `prunes the old prefix, re-roots the survivor and stays replayable`（根化后链可重放）
  - `reports a broken chain instead of truncating it`（链断裂只报告不截断）
- 结论：**不会因「时间过期」误删仍被 head / 回收站引用的 revision**。
- 附加发现：清理在**生产环境从不运行**（P9-M3），因此该算法目前只被测试执行；
  以及 assembly 链根本不在候选集内（P9-M7）。

### 变异实验覆盖缺陷登记

| 变异 | 是否被现有测试捕获 | 说明 |
| --- | --- | --- |
| autosave 版本守卫移除 | 是 | `resource_autosave_service_test.dart:484` |
| revision 写入后异常回滚 | 是 | trash 陈旧 token / publish 失败 / restore 失败三处断言 |
| 陈旧 debounce 覆盖 restore | 是（间接） | 由守卫用例保证；缺专门交错用例（P9-I3） |
| 父节点缺失 fallback | 是 | 4 个用例 |
| 清理误删被引用 revision | 是 | 4 个用例（assembly 保护为空泛，见 P9-M7） |
| **assembly 二次发布（状态收缩）** | **否** | 无用例；P9-M1 |
| **autosave 冲突后继续编辑** | **否** | 无用例；P9-M2 |
| **资源库删除资源 → 回收站** | **否** | 无用例；P9-B1 |
| **清理在生产被触发** | **否** | 无接线测试；P9-M3 |

## Data Integrity Assessment

成立的部分（独立复核）：

- revision 不可变：无任何 `UPDATE resource_revisions` 修改内容列的路径（仅 `is_head` 与清理时的
  `reroot` 改写 delta/parent）；`resource_revision_service_test.dart`『revision rows are never updated in place』固定。
- head 唯一性由数据库保证（实验 1），插入前 `is_head=0` 与插入同事务。
- 有损操作（生成提交、手动编辑、压缩发布、恢复、删除）的 before/after 抓取与业务写入同事务
  （实验 4），失败整体回滚，不存在「head 已推进但内容半提交」。
- 手动编辑/自动保存/删除/恢复/压缩发布的 CAS 均以 `updated_at` 守卫，陈旧写入命中 0 行（实验 1/3/5）。
- 增量存储：单节点编辑只写 1 行 delta（`resource_revision_test.dart` 断言 delta 只含被改动节点），
  未违反 §十五「不得每次 tick 复制整棵资源树」。

不成立/被削弱的部分：

- **删除路径存在不可逆数据损失**（P9-B1）：资源删除不进回收站且硬删旧表；回退态资源丧失唯一副本。
- **assembly revision 的存储内容与声明不符**（P9-M1）：重建状态可能包含已删除节点，且列内 hash 与重建 hash 分叉。
- 自动保存的持久化承诺在会话内可失效且草稿不可达（P9-M2）。

## Crash Recovery Assessment

- 流式语义正确：只有校验通过的 Part 经 `commitPartContent` 落库，
  未确认 chunk 既无 journal 行也无 `completed` 状态；
  `phase9_concurrency_test.dart`『a crash leaves a recoverable draft and no fake completion』
  『an uncommitted attempt never becomes completed』『a cancelled task refuses a late commit』
  分别固定「未确认不伪装完成」与「已提交内容在取消/失败后保留」。
- journal 语义正确：`alreadyApplied` / `needsUserDecision` / `orphaned` 三态分类有测试，
  且「树已写、journal 未删」可由 hash 收敛、「journal 新于树」保留（Case B 符合方案预期）。
- **缺口**：Case A 中「Part1/Part2 已确认、Part3 流式中崩溃」的完整重启语义只能由
  cancel/error 用例近似（进程内无法真正重启），但语义已被 `cancelTasks`/`recoverInterruptedTasks` +
  未完成状态断言覆盖，判定为可接受。
- **缺口**：`needsUserDecision` 的草稿没有任何生产消费路径（P9-M2），
  因此「崩溃后可恢复」对用户实际不成立——数据在库里，但产品层面无法取回。

## Autosave / Concurrency Assessment

- debounce 真实存在且 `schedule` 不触库（测试以真实写入计数器断言「25 次输入 → 0 次 journal / 0 次正文写入」），
  满足 §五。
- final flush 边界齐全：dispose、page leave、cancel、generation error、app lifecycle、manual
  （`AutosaveFlushTrigger` 枚举 + `isForced`；widget 侧 `dispose`/`didChangeAppLifecycleState`/`_close` 均有接线）。
- 交错场景：autosave×生成、autosave×重生成边界、autosave×删除、双恢复、清理×恢复、
  stale head、发布×抓取均有用例；陈旧 autosave 不会产生 Lost Update（实验 3）。
- **缺陷**：冲突粘性 + 无草稿出口（P9-M2）；**缺**「edit→restore→stale autosave」专门用例（P9-I3）。

## Revision Assessment

- 增量链、不可变、parent 链、head 指针、事务边界、回滚、幂等（重复恢复/重复抓取）、
  stale 保护、清理保护规则均独立复核成立（实验 1/2/4/7 与定向测试）。
- **缺陷**：`publishAssemblyRevision` 的 delta 构造错误（P9-M1）；
  清理从未在生产触发（P9-M3）；assembly 链不在清理范围（P9-M7）；
  `select()` 未用于判断 Adventure readiness（符合 Phase 10 边界，未越界）。

## Trash / Restore Assessment

- 删除一律 `live → trash`（软删除 + 行记录）对 **Section/Part** 成立；
  恢复支持原父/原序、fallback 到根下新章节并明确提示、重复恢复幂等、永久删除为显式二次操作
  且拒绝存活节点——全部独立复核成立（实验 6 与 `resource_trash_service_test.dart` 28 用例）。
- **缺陷（BLOCKER）**：**Resource 删除完全没有接入回收站**，且仍有硬删除旧表的可达路径（P9-B1）。
  回收站 UI 只覆盖 Studio 的 Section/Part 删除，对用户最常用的「资源库删除资源」无效。
- 次要：对已被级联删除的节点再删除会抛冲突（P9-M6）。

## Migration Assessment

- `schemaVersion = 41`，`createV41Schema` 链入 onCreate，`onUpgrade` 有独立
  `oldVersion < 41 && newVersion >= 41` 步骤，只做 `CREATE TABLE/INDEX IF NOT EXISTS`，幂等、非破坏。
- 独立复核：`database_migration_v41_test.dart` 7 用例覆盖「全新安装 / v40→v41 且既有行逐字保留 /
  新表初始为空 / 重复迁移安全」；实验 1 额外证明三条部分唯一索引与 FK 级联真实生效，
  且 CAS 语义（陈旧 token 0 行、软删除行 0 行）成立。
- 未发现「表能创建但约束不保护不变量」的情形。迁移项判定通过。

## Regression Assessment

- 全量 1392 用例通过（含 Phase 5/6/7/8 既有用例）；Phase 5/6/7 冻结文件
  （`resource_contracts.dart`、`streaming_*`、`part_generation_*`、`generation_patch_parser.dart`、
  `resource_generation_protocol/patch`）在 `dbd2303..161dd7a` 零改动（`git status` 复核）。
- 生产写路径未被复制：`resource_parts.content` 的写入者仍是 `commitPartContent`、
  `ResourceTreeRepositoryImpl.updatePart/updatePartInTransaction`、`applyRevisionState`、
  创建期 insert；压缩 coordinator 仍只写候选表。
- Phase 7 D2 门控放开是刻意且有文档的收口，端到端链路经复核成立
  （`SectionControlService.regenerateSection` → `beginLossyOperation(partIds: <task parts>)`
    重开 completed 任务 → `startAttempt` 可执行），但建议在 STATUS 标注 supersede（P9-I5）。
- 无 Phase 10/11/12 越界实现（未接 Adventure readiness、未重构资源库 UX、未删旧表）。

## Final Decision

```text
FAILED
Phase 9 NOT ACCEPTED
Phase 10 remains BLOCKED
```

阻塞理由（任一即足以拒绝）：

1. **P9-B1（BLOCKER）**：Phase 9 明确列出的「Resource 删除进入回收站」未实现——
   没有任何生产路径把 Resource 移入回收站；而资源删除的可达路径仍执行旧表物理删除，
   对 `ResourceReadFacade` 回退态资源即不可逆销毁唯一副本，回收站无从恢复。
   直接违反本阶段核心原则「任何…删除操作，都不得造成不可逆的数据损失」与 §十
   「Permanent Delete 必须是显式二次操作」。
2. **P9-M1（MAJOR）**：`publishAssemblyRevision` 以全量 upsert 冒充增量写入父链，
   重放会复活已删除节点，且列内 `content_hash` 与重建 hash 分叉（有可执行证据）。
3. **P9-M2（MAJOR）**：自动保存在一次冲突后于同一会话内永久失效，
   且被 journal 保住的用户文本在生产代码中无任何取回路径。

必须修复后重新提交独立验收。本轮**不修改任何生产代码**；修复规格见各 Finding 的
`Required Fix` / `Required Tests`，交由执行 Agent 实施。

另请注意：P9-M3/P9-M7（清理未接线、assembly 链不清理）与 P9-I2（blueprint 覆盖分支无 revision）
虽非阻塞，但同属「可恢复边界」这一交付主题，建议在同一轮 remediation 中一并处理，
避免 Phase 10 在这些地基上继续叠加。
