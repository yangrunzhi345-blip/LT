# Phase 9 Independent Re-Acceptance — Round 2

```text
Audit HEAD:        119f923fb37928a157620d14cf5334b9461f334d
Remediation Range: b999132..119f923
                   (dbb8019 fix(phase9) + 119f923 docs(status))
Reviewer:          independent re-acceptance agent（Round 2，只读；
                   未修改任何生产代码或测试）
Round 1:           FAILED @ 161dd7a（1 BLOCKER + 2 MAJOR + 8 MINOR + 5 INFO）
Round 1 Report:    docs/adaptive-resource-system/phase-09-independent-acceptance.md
                   （本轮未改动，逐字保留）
Remediation Report: docs/adaptive-resource-system/phase-09-remediation-report.md
```

## Round 1 Finding Closure

| ID | Round 1 | Round 2 裁定 | 依据 |
| --- | --- | --- | --- |
| P9-B1 | BLOCKER | **PARTIALLY CLOSED → REGRESSED（见 R2-B1）** | 数据安全部分已关闭；但生产删除路径未接线，删除功能在主 UI 上不可用 |
| P9-M1 | MAJOR | **CLOSED** | 实验 B1/B2/B3 + 定向测试 |
| P9-M2 | MAJOR | **CLOSED**（自致冲突已修）＋残留 R2-M1 | 实验 C1–C4 + 编辑器用例 |
| P9-M3 | MINOR | **CLOSED** | `ResourceRevisionMaintenance` + main.dart post-frame |
| P9-M4 | MINOR | **CLOSED** | 透传 `alreadyApplied`，已应用时 savedCharacters=0 |
| P9-M5 | MINOR | **CLOSED** | `resourceUpdatedAt()` + 页面透传 CAS（实验 F3） |
| P9-M6 | MINOR | **CLOSED** | 级联删除后重复 delete 解析到祖先条目 |
| P9-M7 | MINOR | **CLOSED** | 清理按 kind 各跑一遍（实验 E） |
| P9-M8 | MINOR | **CLOSED** | Studio 新增「删除段落」入口（widget 用例） |
| P9-M9 | MINOR | **CLOSED** | label 改为「保存后快照」 |
| P9-I1 | INFO | **CLOSED** | head 读取移进事务 |
| P9-I2 | INFO | **CLOSED** | Blueprint 覆盖分支同事务 capture（代码走查 + 新用例） |
| P9-I3 | INFO | **CLOSED** | 冲突/保护交错用例已补 |
| P9-I4 | INFO | **CLOSED**（维持现状并文档化） |
| P9-I5 | INFO | **CLOSED** | STATUS 已记录 D2 supersede |

## Other Remediation Verification

- `ResourceLibraryTrashBridge` 的目标解析（树 id / 迁移审计 / 回退态）为确定性实现，
  实验A 三种形态逐一验证。
- `LegacyLibraryRowPurger` 是资源三张表唯一的物理删除点，且表名走固定白名单
  （`LegacyLibraryRowPurger.legacyResourceTables`），被篡改的 `metadata_json`
  无法把 `DELETE` 指向别的表。
- `_deleteByMode` 仅剩 `prompt_presets` / `adventure_templates` 两个调用点
  （配置表，不属 Phase 9 范围）。
- `TrashOrigin.legacy` 标记条目：restore 只清标记、permanent delete 才删旧表行，
  且两者都不会触碰内容树（实验 A 场景 1）。
- 迁移资源（旧表行 + `res_legacy_*` 树行）删除时双副本处理正确：
  树行软删除、旧表行保留、两条投影都从列表隐藏、restore 后恢复（实验 A 场景 2）。
- `AutosaveDraftRecovery` 同时被 service 与编辑器使用（单一分类器，无第二套判定）。

## Independent Experiments

全部实验由 Round 2 审查 Agent 编写，放在 `/tmp`（仓库零改动），直接构造
**生产类**（`LibraryRepositoryImpl` / `ResourceLibraryTrashBridge` /
`ResourceTrashService` / `ResourceRevisionService` / `ResourceAutosaveService`），
对真实 SQLite 数据库执行，并逐条读取数据库结果。未复制执行 Agent 的测试代码，
也未使用其测试夹具（`test/helpers/phase9_recovery_fixtures.dart` 已另行审查）。

### Experiment A — Resource Delete（38 项检查，PASS）

生产等价路径：`LibraryRepositoryImpl(deleteBridge) → bridge.moveToTrash →
ResourceTrashService.deleteNode`。

| 场景 | 结果 |
| --- | --- |
| notMigrated（仅旧表）删除 | legacy 行保留（rows=1），内容逐字段一致；列表与搜索隐藏；bin 条目 `TrashOrigin.legacy` 且 link 正确；restore 清标记后行原样可见、内容一致；permanent delete 后 rows=0 |
| migrated（旧表 + `res_legacy_*` 树行）删除 | 树行软删除、旧表行保留、两条投影都隐藏；bin 条目 tree-backed 且记录 before revision；被删正文可从 revision 读回；restore 复活树行；permanent delete 同时清除旧表行与树行 |
| treeMissing（审计记录指向不存在的树行）删除 | 不走树路径、写 legacy 标记、行保留、可恢复 |
| 幂等 | 重复 delete 不产生第二条 bin 记录 |
| fail-closed | 未接桥接的 `LibraryRepositoryImpl` 抛 `StateError` 且不破坏任何数据 |
| 搜索 | 被删除资源从搜索结果中消失 |

### Experiment B — Assembly Replay（PASS）

- 收缩 `{S,P1,P2} → {S,P1}`：replay = `{S,P1}`，P2 不复活；delta 里确实存在
  `is_removed=1` 的 P2 墓碑。
- 混合 `{A,B,C} → {A,C,D}`：B 删除（墓碑）、D 新增（upsert），replay =
  `{A,C,D}`，恰好 3 个 part 节点。
- 契约守卫真实生效：直接向 `insertRevisionInTransaction` 提交
  「父非空 + 目标更小 + 全 upsert」的增量，抛
  `ResourceRevisionDeltaException`（不是测试里"主动遵守"）。
- 发布后 latest head 未被移动；assembly 指针正确指向新发布的 revision。

### Experiment C — Autosave Sticky Conflict（PASS，残留 R2-M1）

- Round 1 根因（自致陈旧 token）已关闭：连续 5 个保存周期全部 applied，不再楔死。
- 外部写入（generation/restore 等）造成的冲突：**不覆盖**外部内容（符合要求），
  用户草稿保留在 journal。
- **残留**：外部冲突之后，同一会话的后续 flush 仍然冲突（实测 applied=0 /
  conflicted=1），即自动保存在本会话内停止工作，直到编辑器重开
  （重开时 `reconcilePendingDrafts` 会提供草稿）。→ R2-M1。

### Experiment D — Stale Debounce vs Restored Content（PASS）

`edit → pending autosave → restore（外部写入）→ 旧 debounce 触发`：
restore 的内容**未被覆盖**；pending 文本保留在 journal（不静默丢弃）。

### Experiment E — Cleanup Protection（PASS，retention = 0 的最激进配置）

- 两条链都被清理（deleted=2、rerooted=2），无 skipped。
- latest head 存活且仍重放出编辑后的正文。
- assembly head 存活且仍重放。
- 被未解决回收站条目引用的 revision 存活。
- 已被取代且无引用的 assembly revision 在 retention=0 下被回收（符合预期）。

### Experiment F — Idempotency + CAS（PASS）

- Section 重复 delete → 同一 bin 条目，无重复。
- 重复 restore → 第二次为 no-op，无重复 Section。
- 带 `expectedUpdatedAt: 'stale-token'` 的 restore 被拒绝。

### Experiment G — Production Provider Delete Path（**FAIL → R2-B1**）

用真实 `ProviderContainer`（无任何 override）读取
`resourceCrudControllerProvider` 并调用 `deleteWorldviewPreset`：

```text
delete success=false
error=Bad state: 资源删除需要 Phase 9 回收站桥接（ResourceLibraryTrashBridge），
      未接线时拒绝删除以避免不可逆数据损失
active trash entries: 0
>>> PRODUCTION DELETE PATH IS BROKEN (fail-closed hit)
```

### Experiment H — Pending Draft Recovery Chain（PASS）

真实类 + 真实库：journal 行写入（复现「journal 已落、正文未写」的崩溃窗口）→
新 session `reconcilePendingDrafts` 判定 `needsUserDecision` → `pendingDraft()`
暴露文本 → 载入 + flush 后正文更新、journal 行被消费 → 「丢弃草稿」亦可。

## Validation

| 命令 | 实际结果 |
| --- | --- |
| `dart format --output=none --set-exit-if-changed .` | 472 files / 0 changed |
| `flutter analyze` | No issues found |
| Phase 9 定向测试（21 文件） | 346 passed / 0 failed |
| 全量 `flutter test` | 1446 passed / 0 failed |
| `git diff --check` | 干净 |
| `git rev-parse HEAD` == `git rev-parse origin/main` | `119f923…` 一致 |

## New Findings

### R2-B1 — BLOCKER

```text
ID: R2-B1
Severity: BLOCKER

Title: 生产 UI 的 Resource 删除路径未接线，删除功能整体不可用（fail-closed 变成不可用）

Requirement:
  Round 1 P9-B1 要求「Resource 删除 → ResourceTrashService → before revision →
  trash record → soft delete」，且审计 §十二.1 明确警告
  「fail-closed 不会演变成生产不可用」。

Evidence:
  1. Resource Library 的全部删除入口都经由 `resourceCrudControllerProvider`：
     lib/screens/resource_library/worldview_tab.dart:112→135、
     character_card_tab.dart:245 与 433、npc_tab.dart:207、
     character_card_edit_page.dart:213、npc_edit_page.dart:110、
     lib/widgets/app_dialogs.dart:1231。
  2. 该 provider 的装配（lib/providers/riverpod_providers.dart:153-156）：
       final resourceCrudControllerProvider =
           ChangeNotifierProvider<ResourceCrudController>((ref) {
         return ResourceCrudController(
           repository: ref.read(libraryRepoProvider),   // ← 未接桥接
           ...
  3. `libraryRepoProvider`（同文件:94-96）构造
     `LibraryRepositoryImpl(getDb: ...)` —— 没有 `trashBridge`。
  4. `LibraryRepositoryImpl._moveToTrash`（library_repository_impl.dart:148-157）
     在桥接缺失时抛 `StateError('资源删除需要 Phase 9 回收站桥接…')`。
  5. 整改只在 `DatabaseService._libraryRepo`（database_service.dart:98）接了桥接，
     而生产删除 UI 不经过那条路径。
  6. 实验G：用真实 `ProviderContainer`（无 override）执行
     `resourceCrudControllerProvider.deleteWorldviewPreset`，实测
     `delete success=false`，错误信息即上述 StateError；bin 为空。
  7. 既有 UI 用例没有覆盖到这里：`phase9_library_delete_test.dart` 等使用
     自行装配的仓库（已接线），而没有任何用例沿
     `resourceCrudControllerProvider → libraryRepoProvider` 这条真实装配走一遍删除。

Reproduction:
  1. 打开资源库 → 世界观/角色卡/NPC 任一列表或编辑页 → 删除。
  2. 结果：提示「删除世界观失败，请重试」（或对应文案），资源未被删除、
     回收站为空。三种资源类型全部如此。

Expected: 删除成功并把资源移入回收站，可在回收站恢复。
Actual: 删除必然失败（StateError 被控制器吞成 failure），回收站为空。
Root Cause:
  整改把回收站接到了 `DatabaseService._libraryRepo`，但 Resource Library UI 的
  删除走的是 `libraryRepoProvider` 这条完全不同的装配链。两条装配链并存，
  只有其一被接线；而 `_moveToTrash` 的 fail-closed 设计使得未接线的那个
  从「不安全但可用」变成「安全但不可用」。
Affected Files:
  - lib/providers/riverpod_providers.dart:94-96（libraryRepoProvider 未接桥接）
  - lib/services/repositories/library_repository_impl.dart:148-157（fail-closed）
  - lib/features/resource_library/**（删除入口全部经 resourceCrudControllerProvider）
Impact:
  - 资源库的核心 CRUD 操作（删除）在生产不可用；用户无法删除任何
    世界观/角色卡/NPC。
  - 无数据损失（fail-closed 恰恰阻止了误删），但这是把「不安全删除」
    换成了「没有删除」，Phase 9 的交付目标「删除进入回收站」在主 UI 上未达成。
Required Fix:
  最小修复（一处）：`libraryRepoProvider` 改为经由与
  `DatabaseService._buildLibraryTrash()` 相同的装配，例如
    final libraryRepoProvider = Provider<ILibraryRepository>((ref) {
      final bridge = ref.read(resourceLibraryTrashBridgeProvider);
      return LibraryRepositoryImpl(getDb: () => DatabaseService.database,
          trashBridge: bridge);
    });
  并让 `resourceLibraryTrashBridgeProvider` 成为唯一桥接来源
  （避免与 DatabaseService 各建一份造成两个互不相识的装配）。
  同时核查其余 `LibraryRepositoryImpl(getDb:)` 裸构造
  （chat_provider.dart:211、adventure_template_controller.dart:29、
  adventure_setup_controller.dart:63）是否也需要桥接：
  它们目前不删除资源正文，但应统一走同一来源以免再次出现半接线。
  更彻底的做法：把 Phase 9 装配收敛到一个组合根
  （例如 `ResourceRecoveryStack`），`DatabaseService` 与 providers 都从它取，
  消除「两条装配链」这个结构性根因。
Required Tests:
  - 用真实 `ProviderContainer`（无 override）读取 `resourceCrudControllerProvider`
    并执行三种资源的删除，断言成功、`resource_trash` 出现条目、旧表行保留。
  - 断言删除后 `getWorldviewPresets/getCharacterCards/getNpcCards` 不再返回该资源。
  - 保留 fail-closed 用例：显式构造未接桥接的仓库仍须抛错（防止把守卫拆掉）。
```

### R2-M1 — MINOR

```text
ID: R2-M1
Severity: MINOR

Title: 外部并发写入造成的 autosave 冲突后，同一编辑会话内自动保存持续失败
       （需重开编辑器恢复）

Requirement:
  审计 §六要求「Edit A → T1 → external write → T2 → old flush CAS conflict →
  reload latest token → bounded retry → continue editing → later autosave succeeds」。

Evidence:
  实验 C（/tmp/r2_exp_bcdf_test.dart）实测：
  - 外部写入后 flush：applied=0 / conflicted=1（正确，未覆盖外部内容）；
  - **继续编辑后的下一次 flush：applied=0 / conflicted=1**（C3 打印），
    即自动保存在本会话内持续失败；
  - 用户文本保留在 journal（`needsUserDecision`），且重开编辑器会提供
    「载入草稿 / 丢弃草稿」（实验 H + 编辑器用例）。

Reproduction:
  1. 编辑某个 Part → autosave 成功写入 v1。
  2. 另一写入方（generation 提交 / restore / 压缩发布）改写同一 Part。
  3. 用户继续输入并等待 debounce → 每次 flush 都报「保存冲突」。
  4. 关闭并重开编辑器 → 出现「发现未保存的草稿」横幅 → 载入后可继续。

Expected: 冲突后继续编辑，后续 autosave 应能成功（不覆盖外部内容的前提下，
  例如提示用户选择「以我的文本为准 / 以新内容为准」，或自动把草稿 rebase 到
  新内容之上）。
Actual: 会话内自动保存持续失败；恢复必须关闭并重开编辑器。
Root Cause:
  冲突分支只「报告」而不「解决」：`_handleConflict` 会读取 live 状态，
  但当判定为外部写入时既不采信新 token，也不把草稿交给用户，
  于是 session 的 token 停留在旧值，下一次 flush 仍然陈旧。
  这是「不覆盖外部内容」与「后续自动保存必须成功」两条要求之间的
  设计缺口：缺少一个用户可见的冲突解决动作。
Affected Files:
  - lib/application/resources/resource_autosave_service.dart（_handleConflict）
  - lib/features/resource_studio/presentation/widgets/resource_studio_part_editor.dart
Impact: 无数据丢失（journal 保留 + 重开可恢复），但自动保存对外部并发写入
  这一真实场景会停摆，用户需要发现并使用「重开编辑器 → 载入草稿」这一隐藏路径。
Required Fix:
  在冲突被报告时，把 live token 采信进 session（`_sessionTokens[partId] =
  live.token`）并保留草稿；同时让编辑器把冲突升级为用户可见的解决动作
  （「用我的文本覆盖 / 放弃我的文本」），二者选其一后即可恢复自动保存。
  这样既满足「不覆盖外部内容」（需要用户确认才覆盖），也满足
  「后续 autosave 成功」。
Required Tests:
  - 外部写入 → 冲突 → 用户确认覆盖 → 下一次 flush 应成功且正文为草稿文本。
  - 外部写入 → 冲突 → 用户选择放弃 → 草稿删除且正文保持外部内容。
```

### R2-M2 — MINOR

```text
ID: R2-M2
Severity: MINOR

Title: 迁移资源在资源库中会出现两条投影（旧表行 + 树行），删除/恢复虽一致但列表重复

Evidence: 实验 A 场景 2 restore 后 `getNpcCards()` 同时包含旧表 id `npc_mig`
  与树 id `res_legacy_npc_cards_npc_mig`（Phase 3 union 的既有行为，
  `phase9_library_delete_test.dart` 以「删除前后 id 集合一致」固定了往返保真度）。
Reproduction: 建立迁移资源 → 删除 → 恢复 → 列表。
Expected/Actual: 数据一致、无重复进入回收站、无 ID 冲突；仅列表可能重复展示。
Root Cause: Phase 3 的 union 读取未按迁移关系去重；属 Phase 11 范围。
Impact: 仅展示重复；Phase 9 的删除/恢复/幂等均正确。
Required Fix: 归 Phase 11（按 `resource_migration_records` 去重投影）。
Required Tests: 归 Phase 11。
```

### INFO

```text
ID: R2-I1  Severity: INFO
Title: libraryRepoProvider 仍有 8 个消费方未接桥接
Detail: 除 ResourceCrudController 外，chat_provider、adventure_setup_controller、
  adventure_template_controller 等也使用未接桥接的 LibraryRepositoryImpl。
  它们目前不做资源正文删除，但修复 R2-B1 时应统一来源，避免再次半接线。

ID: R2-I2  Severity: INFO
Title: `DatabaseService.delete*` 三个 facade 方法在生产无调用方
Detail: 接了桥接的 `DatabaseService._libraryRepo` facade
  （database_service.dart:2487/2527/2698）没有任何 lib/ 调用方；
  真正的生产删除走 libraryRepoProvider。接线修复时应以 provider 链为准。

ID: R2-I3  Severity: INFO
Title: legacy-only 条目不记录 revision_id
Detail: `TrashOrigin.legacy` 条目的 `revision_id` 为空（内容从未进树，无需 revision）。
  语义正确，但建议在报告中明确，避免后续被误判为缺失。
```

## Regression Assessment

- **Phase 5/6/7/8 冻结文件**：`dbb8019` 与 `119f923` 均未改动
  `part_generation_*`、`generation_patch_parser.dart`、`resource_generation_protocol/patch`、
  `streaming_*`、`resource_contracts.dart`、`section_control_repository_impl.dart`
  之外的 Phase 5 协议文件（实测 `git diff --name-only b999132..119f923` 复核）。
- **Phase 5 提交协议**：`commitPartContent` 未被本轮改动；全量 1446 通过。
- **Phase 6 Streaming Studio**：页面/控制器改动仅限新增面板与编辑器；既有用例通过。
- **Phase 7 Section Controls**：D2 门控放开已被 Phase 9 记录（supersede），
  门控用例更新为「提供 regenerate」+「运行中禁止」，全量通过。
- **Phase 8 压缩**：coordinator 仍只写候选表；`CompressionPublisher` 是唯一发布路径；
  压缩相关测试全部通过。
- **新增回归（本轮发现）**：R2-B1（生产删除不可用）—— 见上。

## Final Decision

```text
FAILED
Phase 9 NOT ACCEPTED
Phase 10 remains BLOCKED
```

理由：R2-B1（BLOCKER）。整改确实关闭了 Round 1 的数据安全缺口
（不可逆破坏路径已消除、assembly replay 正确、自致 autosave 冲突已修、
清理双链保护正确、草稿有生产恢复出口），但引入了一个新的 BLOCKER：
**生产 UI 的资源删除完全不可用**（实测 `resourceCrudControllerProvider.deleteWorldviewPreset`
抛 `StateError`，三种资源类型一致）。

本轮审查未修改任何生产代码或测试。修复规格见 R2-B1 的 `Required Fix`
（核心是把桥接接到 `libraryRepoProvider`，并统一 Phase 9 装配来源），
交由执行 Agent 实施后再次提交独立验收。
