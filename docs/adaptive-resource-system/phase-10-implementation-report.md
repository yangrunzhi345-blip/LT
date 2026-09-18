# Phase 10 — Assembly Readiness 实施报告

## 基线

- Start HEAD: `f1db3f4ed7a6c96c5ca38e5374ef4129899855bf`（== origin/main，工作区干净）
- End HEAD: `80b97e6b3b9e0936f2cb37a001cff2eeed10e989`（实施提交 `feat(resources): implement phase 10 assembly readiness`；STATUS/报告由紧随其后的 `docs(status)` 提交记录）
- Executor: executor-agent（CodeBuddy CLI）
- Date: 2026-09-18

## 数据库 schema 变化（v41 → v42）

`DatabaseService.schemaVersion` 41 → 42。新增（`createAssemblyReadinessSchema`）：

1. `resource_assembly_readiness`（每资源一行）
   - `resource_id TEXT PRIMARY KEY`
   - `target_revision_id` / `target_content_hash`：本次准备目标 latest head
   - `state`：preparing / ready / failed / stale（语义由冻结的
     `ResourceStateMachines.readiness` 决定，存储层不做推断）
   - `assembly_revision_id` / `assembly_content_hash`：当前可消费 assembly revision
     （stale / preparing 转换时保留旧值，旧 ready revision 保持可选）
   - `attempt_token`：并发 CAS 所有权令牌
   - `validation_message`（进度提示，如压缩等待）、`failure_reason`
   - `started_at` / `completed_at` / `updated_at`
   - 索引：`idx_resource_assembly_readiness_state(state, updated_at)`
2. `resource_assembly_entries`（revision 绑定的语义索引文档）
   - `entry_id TEXT PRIMARY KEY`、`resource_id`、`revision_id`、
     `revision_content_hash`、`keys_json`、`content`、`insertion_order`、
     `sticky`、`created_at`
   - 索引：`idx_resource_assembly_entries_rev(resource_id, revision_id, insertion_order)`
3. `world_entries` 新增列 `source_revision_id TEXT NOT NULL DEFAULT ''`
   （`safeAddColumn` 幂等添加）——世界书条目记录来源 assembly revision；
   embedding 以 entry 外键 + contentHash 间接继承该 provenance。

Migration：`migrateStepByStep` 增加 `oldVersion < 42` 块；只做
`CREATE TABLE / INDEX IF NOT EXISTS` 与幂等 `ADD COLUMN`，不改写既有行；
fresh install 走 `createV42Schema`（两个 onCreate 路径均已接入）。
测试：`database_migration_v42_test.dart`（fresh + v41→v42 升级 + 重复迁移幂等）。
既有 v36/v38/v39/v40/v41 migration 测试中刻意钉死的
`expect(DatabaseService.schemaVersion, ...)` 已按其注释要求随版本提升更新为 42。

## 新增文件

生产代码：

- `lib/application/resources/assembly_readiness_repository.dart`：
  `AssemblyReadinessRecord` / `AssemblyIndexDoc` 模型与
  `IAssemblyReadinessRepository` + SQLite 实现。
- `lib/application/resources/resource_assembly_builder.dart`：
  `ResourceAssemblyBuilder`（实现冻结契约 `ResourceAssemblySnapshotProvider`）。
- `lib/application/resources/assembly_readiness_coordinator.dart`：
  `AssemblyReadinessCoordinator`（Phase 10 核心协调器）。
- `lib/application/adventure/adventure_readiness_gate.dart`：
  `AdventureReadinessGate` + `AdventureAssetReadiness` +
  `AdventureReadinessGateException`（中文可读消息）。
- `lib/features/adventure/presentation/wizard/widgets/assembly_readiness_dialogs.dart`：
  阻断反馈对话框与「使用上一个已就绪版本」明确选择对话框。

测试：

- `test/helpers/phase10_fixture.dart`（按生产装配根组装完整栈）
- `test/application/resources/database_migration_v42_test.dart`
- `test/application/resources/resource_assembly_builder_test.dart`
- `test/application/resources/assembly_readiness_coordinator_test.dart`
- `test/application/resources/phase10_semantic_index_test.dart`
- `test/application/resources/phase10_index_and_compression_test.dart`
- `test/application/resources/phase10_production_wiring_test.dart`
- `test/application/adventure/adventure_readiness_gate_test.dart`
- `test/widget/adventure/assembly_readiness_dialogs_test.dart`

## 修改文件（生产）

- `lib/services/database_service.dart`：v42 schema + migration。
- `lib/models/world_entry.dart`：`sourceRevisionId` 字段与序列化。
- `lib/models/adventure_config.dart`：`AdventureResourceBinding` 与
  `AdventureConfig.resourceBindings`（toJson/fromJson/copyWith，旧行向后兼容）。
- `lib/services/worldview_snapshot_service.dart`：`buildManagedEntries` 新增可选
  `sourceRevisionId` 透传。
- `lib/providers/adventure_provider.dart`：`createAdventure` 前置
  `enforceAndFreeze`（fail-closed），托管条目写入携带 revision provenance；
  默认 gate 惰性构造。
- `lib/providers/chat_provider.dart` / `lib/providers/riverpod_providers.dart`：
  Phase 10 Provider 装配（readiness repository / builder / coordinator /
  compression link / gate），chatProvider 注入 gate。
- `lib/main.dart`：启动时读取 compression link 并执行 `recoverInterrupted()`。
- `lib/features/adventure/presentation/wizard/screens/adventure_wizard_screen.dart`：
  `_handleStart` 接入 readiness 解析、阻断反馈与旧版本明确选择。

## Readiness 数据模型

见上文 schema。状态机转换全部经 `ResourceStateMachines.advanceReadiness` /
`canTransitionReadiness` 校验：preparing→ready / preparing→failed /
ready→stale / ready→preparing / failed→preparing / stale→preparing。
`ready → stale` 由 `refresh()` 在读取路径上对账（assembly 指针或 head 哈希
不再匹配时落盘 stale）；`stale → ready` 不存在，必须重新 prepare。

## Assembly Builder

- 只读指定 immutable revision（`IResourceRevisionRepository.readState`），
  重建状态哈希与 revision 行哈希必须一致，`expectedContentHash` 不符即拒绝；
  不读取 live tree。
- 输出兼容冻结契约：`ResourceAssemblySnapshot`（canonical `(sortOrder,id)`
  顺序 fragments）+ `ResourceAssemblyFragment`（`isCanon` 按冻结 NodeStatus：
  confirmed→canon、draft→非 canon、archived→整体剔除）。
- worldview：经 `_CanonFilteredView`（剔除 archived）走既有生产投影
  `ResourceAdventureView.toWorldviewRow`，生成与
  `WorldviewSnapshotService.snapshot` 同形的 payload，但 `content_hash` 固定为
  revision 哈希。
- character / npc：使用当前仓库真实存在的 metadata/投影来源
  （`ResourceAdventureView.toCardRow` → `json_data` chara_card_v2），经
  `LegacyResourceMapper.characterFieldForPartTitle` 标题映射得到
  `first_mes` / `system_prompt` 等运行时核心字段；未发明任何字段名；
  缺失内容不会从 live tree 补齐。
- 语义索引文档（worldview）：用与 Adventure 创建完全相同的
  `WorldviewSnapshotService.buildManagedEntries` 从冻结 payload 确定性派生，
  保证落盘索引与运行时条目永不分歧。

## Coordinator 状态机与竞态 / CAS 策略

`prepare(resourceId)` 流程：

1. 单事务内读取 latest head + 现有 readiness 行，校验旧状态→preparing 合法，
   写入 preparing 行并持有新 `attempt_token`（同资源单飞行 map 合并重复调用）。
2. 容量判定基于冻结 revision 状态字符数（`ResourceCapacityMath.statusFor`），
   不做 live 重测。
3. OVERFLOW：保持 preparing，挂接已有 Phase 8 基础设施
   （`CompressionCoordinator.enqueueForResource` + worker `scheduleProcessing`），
   绝不自建压缩器、绝不自动发布压缩候选（保留 Phase 8「候选→显式发布」语义）。
4. NORMAL/elastic：builder 从 immutable revision 构建（含哈希校验）。
5. `debugInterleaveHook`（仅测试注入）之后复核 head：revisionId 或
   contentHash 变化 → 结果降级（见下）。
6. `publishAssemblyRevision`（Phase 9 幂等实现：diff-vs-previous-assembly +
   tombstone；latestHead 与 assembly 两条链保持独立，未被修改）。
7. 单事务内写入 revision 绑定的索引文档（按 resource+revision 替换）。
8. 最终提交（单事务 CAS）：行仍在（attempt_token 匹配）+ head 仍等于捕获值
   才写 ready；ownership 丢失 → 整体丢弃本次结果；head 变化 → 写 stale。

竞态保证：

- 迟到任务永远不能覆盖新任务：所有终态写入都是 attempt-token CAS；
  「旧任务把新 head 标成 ready」被 4/8 两处 head 复核 + token 校验阻止。
- `refresh(resourceId)`：ready 行对账（ready→stale），失败/准备中不动。
- `recoverInterrupted()`：启动时把无属主的 preparing 行落为 failed
  （原因注明可重试），fail-closed，绝不自动 ready。
- 索引构建失败 → 整体 failed（已发布的 assembly revision 行本身不可被
  消费，因为 readiness 未 ready；重试成功后索引文档补齐才 ready）。

## Wizard / start boundary 接线

- Wizard `_handleStart`：启动前 `gate.resolveConfig(config)`；准备中 /
  失败 / 尚无可用版本 → 弹出中文阻断对话框并取消启动；存在旧 ready revision
  （staleWithPreviousReady）→ 弹出「资源已修改」对话框，用户必须显式选择
  「使用上一个已就绪版本」（写入 `resourceBindings(staleAllowed: true,
  revisionId: 旧 assembly)`）或取消；绝不静默降级。
- 中央 fail-closed 边界：`AdventureProvider.createAdventure` →
  `gate.enforceAndFreeze(config)`；所有创建入口（向导、预设场景、JSONL 导入）
  汇聚于此。未托管资源（纯 legacy 行）返回 `notManaged`，不参与门禁
  （legacy/new 双投影收敛属 Phase 11，本阶段不破坏现有行为）。
- UI 文案覆盖：准备中 / 准备失败（含原因）/ 尚无可用版本 /
  当前资源已修改，可使用上一个已就绪版本。不存在以 StateError/Exception/null
  形式暴露给用户的路径。
- 重复 start / duplicate guard：沿用既有 `AdventureStartGuard`（未修改）。

## Adventure snapshot 固定方式

`enforceAndFreeze` 对每个托管资源：

1. 解析 readiness（ready 或显式 staleAllowed）；
2. 用 builder 从该 assembly revision 重建 runtime payload（worldview
   snapshot payload / 角色卡 json_data / NPC json）并覆盖 config 中对应字段；
3. 写入 `resourceBindings`：`resourceId + assemblyRevisionId + contentHash`
   （+ staleAllowed）。

因此 config 序列化进 `adventures.config` 后，资源库的编辑 / 重新生成 /
压缩发布 / 恢复 / 删除均无法改变已创建 Adventure 的内容；Runtime 继续只读
冻结 config（本次未发现任何 play-time 读取资源库 mutable latest 的路径，
`ResourceAdventureView` / `WorldEngine` 仅服务资源库 UI）。
旧 Adventure 存档（无 `resourceBindings` 的 config JSON）经
`fromJson` 缺省空列表继续可读。

## Semantic index revision/hash 一致性方案

- 协调器在 ready 前把索引文档按 `(resource_id, revision_id)` 落盘
  （`resource_assembly_entries`），文档内容哈希即 revision content hash；
  A/B 两个 revision 的文档集不相交，旧 ready revision 的文档保留。
- Adventure 创建时托管条目经 `buildManagedEntries(sourceRevisionId:)` 写入
  `world_entries.source_revision_id`，`source_snapshot_hash` =
  assembly content hash；embedding 以 entry（FK）+ contentHash 归属，结构上
  不可能出现 assembly B + entries A 或 entries B + embeddings A 的混用。
- 测试 `phase10_semantic_index_test.dart` 构造 revision A → revision B，
  证明文档按 revision 隔离且旧 revision 文档保持完整。

## 冻结契约冲突记录（真实发现，最小破坏修复）

**缺陷**：`ResourceRevisionState.toResourceTree()`（Phase 9 领域文件
`resource_revision.dart`）以 `root.metadata['type']` 解析资源类型；但生产
writer（`ResourceTreeRepositoryImpl` / `ResourceTreeRowMapper`）把 `type`
存为 `resources` 表列，`metadata_json` 从不携带该键。因此该辅助方法对任何
标准树都抛 `ResourceContractException: Unknown resource type: null`——
实施报告要求先取证：已通过 builder 首次生产调用、异常栈
（`resource_revision.dart:359`）与 `resourceFromRow`/`readLiveState` 源码
确认 metadata 无 `type` 键。

**决策**：不修改已 ACCEPTED 的 Phase 0/9 冻结契约文件。builder 自行从
revision state 重建 `ResourceTree`，类型经 `typeResolver` 解析
（metadata 优先、缺失时读 `resources.type` 列）。资源**类型**是创建后不可
变更的身份属性（`Resource.copyWith` 无 type、无任何生产路径改写该列），
在 revision 之外解析它不可能把可变内容泄入 snapshot；正文内容仍然只来自
revision。coordinator 容量判定采用同一 resolver，无法确定类型时 fail-closed。

## 测试结果

- `dart format --output=none --set-exit-if-changed .`：487 files / 0 changed
- `flutter analyze`：No issues found
- Phase 10 定向测试（8 个文件）：**37 passed / 0 failed**
  - migration v42：fresh 列/索引、v41→v42 升级数据保留、幂等
  - builder：canonical 顺序、哈希不符拒绝、draft 不入 canon、archived 剔除、
    worldview payload 哈希钉扎、索引文档派生、character 字段来自冻结 revision、
    readSnapshot 契约
  - coordinator：NORMAL→ready（含 assembly 指针 + 索引文档）、幂等重复
    prepare、OVERFLOW→preparing（无 assembly）、组装中 head 变更→stale 且
    不发布、迟到任务不覆盖新任务（双 coordinator 真实交错）、ready→stale、
    stale→preparing→ready、failed→preparing→ready、recoverInterrupted、
    索引失败→failed（gate 阻断）+ 健康重试→ready + 文档补齐、OVERFLOW 实际
    入队 Phase 8 压缩任务（真实 CompressionCoordinator + jobs 落库）
  - gate：notManaged 不阻断、无 revision 阻断、ready 通过 + payload 冻结 +
    bindings、创建后编辑冻结不变、stale 无显式选择阻断 / 显式选择通过且使用
    旧 revision 内容、旧 config 向后兼容
  - semantic index：A/B 文档隔离、旧 revision 文档保留
  - production wiring：真实 `ProviderContainer`（零 override）解析全部
    Phase 10 provider、compression link 无循环接入、端到端
    create→capture→prepare→ready→gate freeze→条目 provenance
  - widget：两个对话框在 320/360/390/412/768 视口无 overflow、动作可点、
    长文本滚动
- 全量 `flutter test`：见 STATUS.md 记录（本次提交时执行）。
- `git diff --check`：干净

## 已知限制

1. 索引文档在 assembly 发布之后写入：索引失败时 revision 行已存在但
   readiness=failed 不可消费（fail-closed 由 readiness 状态保证），重试后
   文档补齐。若要求「publish 前建索引」需要先能确定未来的 assembly
   revision id，会破坏 Phase 9 publish 的幂等复用语义，故未采用。
2. `world_entries.source_revision_id` 只对新建冒险的托管条目生效；历史
   存档的条目该列为空串（不回填，属 Phase 11/12 数据收敛范畴）。
3. 语义 embedding 向量本身沿用 Phase 8/9 的 entry+contentHash 惰性缓存，
   未改为按 revision 预生成（当前生产检索通道未接入真实 embedding 服务，
   无预生成触发点）。
4. OVERFLOW 资源在压缩候选发布前保持 preparing；是否/何时发布压缩候选仍由
   用户在资源库显式决定（Phase 8/9 冻结语义，未自动化）。

## 明确未实现（Phase 11/12）

- Phase 9 R2-M2（deferred to Phase 11）未处理。
- legacy/new 双投影 UX 收敛、`notManaged` 资源的门禁化、
  `worldview_presets`/`character_cards`/`npc_cards` 旧表删除、兼容代码清理：
  Phase 11/12。
- 资源库信息架构与 UI 美化：未触碰。

## 回滚

单个 feature 提交（含文档），`git revert <commit>` 即可整体回滚；
v42 迁移为增量 DDL，回滚代码后 v42 库可被旧版本以降级保护拒绝打开
（既有行为），数据不丢失（迁移前自动文件备份机制未改动）。
