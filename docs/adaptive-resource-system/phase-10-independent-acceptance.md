# Phase 10 Independent Acceptance

Audit HEAD: `e1a4a6fc648a4fd15f76067451463c0f1f70bfaa`（== origin/main，工作区干净）
Audit Range: `f1db3f4..e1a4a6f`（Phase 10 实施提交 `80b97e6` + 文档提交 `e1a4a6f`；Start HEAD 依 STATUS.md 记录为 `f1db3f4`）
Date: 2026-09-18
Reviewer: independent acceptance agent（只读；未修改任何生产代码、测试或配置）

## Verdict

**FAILED**（1 MAJOR，2 MINOR，2 INFO；0 BLOCKER）

## Summary

Phase 10 的核心生产链在真实路径上成立：readiness 真实持久化（DB v42）、
builder 只读不可变 revision、coordinator 的 attempt-token CAS 在独立对抗实验
（迟到任务、双 prepare、验证后被绕过的 head 变更、幂等重放）中全部守住，
生产 `ProviderContainer` 零 override 装配可达，v41→v42 迁移无损且幂等，
OVERFLOW 正确复用 Phase 8 压缩基础设施且保持 fail-closed。

但存在一个 MAJOR：**Adventure 快照冻结不完整**。`enforceAndFreeze` 只重写
`worldviewSnapshot`、`selectedCharacters[].characterCardJson`、
`npcSnapshots[].npcJson`；而生产提示词实际读取的
`config.characterCard`（主角卡）与 `config.supportingCharacters`（含 NPC
运行时数据）仍为向导从 live 库行组装的内容。在「使用上一个已就绪版本」
（stale-allowed）这一 Phase 10 显式支持的分支中，同一冒险会混合 revision A
（世界观/选中角色）与 head B（主角卡/配角/NPC）两个版本的内容，用户显式
选择被静默部分违背，且 `resourceBindings` 的 provenance 与实际提示词内容
不一致。

## Baseline

- Phase 9 状态：ACCEPTED（第三轮独立验收，STATUS.md 记录一致）
- Phase 10：IMPLEMENTED，End HEAD `80b97e6`，实施报告存在且与 diff 一致
- Phase 11：保持 BLOCKED（未发现越界解封）
- `git diff f1db3f4..HEAD --stat`：31 files，+4154/−22；Phase 5–9 冻结核心
  文件（`resource_revision_service.dart`、`compression_*`、
  `resource_tree_repository_impl.dart`、autosave、trash）零改动；
  `worldview_snapshot_service.dart` / `world_entry.dart` /
  `adventure_config.dart` 为纯增量修改。

## Production Wiring

- `riverpod_providers.dart` 新增 `assemblyReadinessRepositoryProvider`、
  `resourceAssemblyBuilderProvider`、`assemblyReadinessCoordinatorProvider`、
  `assemblyReadinessCompressionLinkProvider`、`adventureReadinessGateProvider`
  （类型 `Provider<IAdventureReadinessGate>`）；`chatProvider` 注入 gate，
  `ChatProvider.withRepos` → `AdventureProvider(readinessGate:)`。
- 独立运行 `phase10_production_wiring_test.dart`（真实 ProviderContainer，
  零 override）：全部 provider 可解析、compression link 无静态循环接入、
  create→capture→prepare→ready→gate freeze 端到端通过。
- 全部用户可达 `createAdventure` 入口（chat_provider:515/616、JSONL 导入
  adventure_provider:1054）汇聚于 `AdventureProvider.createAdventure` 的
  fail-closed 门禁；`DatabaseService.createAdventure` 静态透传无调用方。
- Wizard `_handleStart`（adventure_wizard_screen.dart:2140）在生产代码中
  调用 `gate.resolveConfig`；p0 边界测试通过 provider override 注入
  `_NoopReadinessGate`（FakeAsync 下无法跑真实 DB I/O，属合理测试替身，
  gate 本体另有真实 DB 集成测试）。

## Database / Migration

- `DatabaseService.schemaVersion == 42`；v42 新增
  `resource_assembly_readiness`（attempt_token 为并发 CAS 所有权列）、
  `resource_assembly_entries`、`world_entries.source_revision_id`
  （`safeAddColumn` 幂等）。
- 独立运行 `database_migration_v42_test.dart`：fresh 列/索引、v41→v42
  升级后既有 `resource_parts` 正文逐字保留、新表为空、重复迁移幂等——全部通过。
- 迁移只做 `IF NOT EXISTS` DDL 与幂等加列，配合升级前文件备份，无数据破坏路径。

## Readiness State Machine

- 状态真实持久化（SQLite 行，非 Provider 内存）；字段覆盖 resource id /
  target revision+hash / state / assembly revision+hash / attempt token /
  validation message / failure reason / started/completed/updated。
- 所有转换经 `ResourceStateMachines.advanceReadiness` / `canTransitionReadiness`
  校验；`failed→ready`、`stale→ready` 无直达边（必须经 preparing）。
- repository 以 `ConflictAlgorithm.replace` 整行写入，但唯一生产调用方是
  coordinator 的 CAS 流程（先读后写在同一事务内），未发现绕过状态机的
  生产写路径。

## Immutable Assembly

- `ResourceAssemblyBuilder.build` 仅经 `IResourceRevisionRepository.readState`
  重建状态，重建哈希与 revision 行哈希必须一致，`expectedContentHash` 不符
  即拒绝；未发现读取 live tree / legacy 当前行的路径（类型解析例外见
  implementation report，类型为创建后不可变的身份属性，已取证
  `Resource.copyWith` 无 type、无生产路径改写）。
- 对抗验证：head 变更后针对旧 revision 的 build 结果仍严格对应旧 revision
  （P1 探针：索引文档只含旧内容）。

## Race / Concurrency

独立探针（/tmp 副本，双 coordinator 实例，非单飞行内存锁路径）：

- **P1 迟到任务**：A build 中插入 head B 并让 B 完整 prepare → A 完成后
  readiness 行保持 B 的 ready，assembly 指针 = B 的哈希，B 的索引文档
  无污染，A 未写 stale 覆盖 B。通过。
- **P2 无竞争者迟到任务**：结果落 stale，未发布任何 assembly revision
  （count==0）。通过。
- **P3 双 prepare 并发**：最终行 ready、assembly revision 恰好 1 行、
  索引文档完整；被丢弃一方的返回 outcome 可能快照到新属主的
  `preparing` 中间态（见 INFO-1），终态收敛正确。通过。
- **P4 验证后 head 变更**（用冻结 `readHead` 视角绕过 step-5 校验模拟
  E3/E4 窗口）：最终提交事务内的真实 head 复核将其捕获并落 stale，
  未对已变化的 head 标 ready；随后正常 prepare 达 ready。通过——
  check 与写入之间不存在可达 TOCTOU（最终校验与写入同一事务）。

## Overflow / Compression

- OVERFLOW（61000 字 worldview）→ `preparing` + 压缩提示，assembly 不存在；
  附接真实 `CompressionCoordinator` 后 `resource_compression_jobs` 实际入队
  （`phase10_index_and_compression_test.dart`），未 drain、未自动发布候选、
  未触碰 `resource_parts.content`、未自建第二压缩器。通过。

## Wizard / Start Boundary

- 四分支：无 ready（阻断+「尚无可用版本」）、preparing（阻断+进度文案）、
  failed（阻断+原因）、stale 有旧 ready（对话框显式选择，取消则不启动，
  绝不静默降级）——`adventure_readiness_gate_test.dart` + 对话框
  widget 回归（320–768 视口）独立运行通过。
- 启动 TOCTOU：Wizard resolve 与 `createAdventure` 的 `enforceAndFreeze`
  双重门禁；两次之间 head 变更会在创建时被判 stale 并阻断（除非用户
  显式绑定旧 revision）。通过（但见 MAJOR-1 的 stale-allowed 内容混合）。

## Adventure Snapshot Immutability

- gate 冻结后编辑资源并捕获新 head：frozen config 逐字不变（gate 测试）。
- 持久化：`adventure_repository_impl.createAdventure` 存 `jsonEncode(config.toJson())`，
  `loadAdventure` 只读该 JSON 与每冒险 `world_entries`，无运行时库读取
  （`AdventureRuntimeStateResolver` 仅叠加 runtime entity overlay）。
- 创建后资源编辑/压缩/恢复不改变已建冒险。**但冻结覆盖面不完整，见 MAJOR-1。**

## Semantic Index Consistency

- `phase10_semantic_index_test.dart`：revision A（ALPHA 类内容）与 B（BETA
  类内容）文档集互斥、docId revision 作用域无碰撞、旧 revision 文档保留。
- world entries 经 `source_revision_id` + `source_snapshot_hash`
  （= assembly content hash）provenance 落库；embedding 以 entry 外键 +
  contentHash 归属，结构上不可 A/B 混用。

## Restart / Recovery

- `recoverInterrupted()`：无属主 preparing 行 → failed（注明可重试），
  不会自动 ready；启动回调已做异常兜底（main.dart）。
- publish 后、ready 前崩溃：行停留 preparing → 恢复为 failed → 不可消费、
  可重试；已发布 revision 为不可变内容行，重试幂等复用。通过。

## Backward Compatibility

- 旧 config JSON（无 `resourceBindings`、snake_case 别名字段）`fromJson`
  正常、门禁对 notManaged 引用放行（gate 测试）。
- `WorldEntry.toJson` 新增键为增量，旧数据缺列由 `DEFAULT ''` 兜底。

## Phase 5–9 Regression

- 冻结核心文件零改动；全量 `flutter test` 1505 passed / 0 failed / 0 skipped
  （独立运行，等于 Phase 9 基线 1459 + Phase 10 新增 46）。
- Phase 9 assembly delta/tombstone、retention 保护、autosave CAS、trash
  路径未被 Phase 10 代码绕开（coordinator 发布只调用
  `publishAssemblyRevision` 公共契约）。

## Adversarial Experiments

| ID | 实验 | 结果 |
| --- | --- | --- |
| E1 | 迟到任务迟到提交（双 coordinator） | PASS（P1） |
| E2 | 双 prepare 并发 | PASS，中间态语义见 INFO-1（P3） |
| E3 | 验证与发布之间 head 变更 | PASS（P2/P4） |
| E4 | 发布与 ready 之间 head 变更 | PASS（P4：最终事务内复核捕获） |
| E5 | 索引构建失败 | PASS（failed，gate 阻断，重试补齐） |
| E6 | preparing 中崩溃重启 | PASS（recoverInterrupted → failed 可重试） |
| E7 | 旧 ready 显式选择 | PASS（选择才放行），但内容混合见 MAJOR-1 |
| E8 | Adventure start TOCTOU | PASS（双重门禁） |
| E9 | 快照创建后不可变 | PASS（worldview/选中角色），覆盖面缺口见 MAJOR-1 |
| E10 | A/B 索引 provenance 污染 | PASS |
| E11 | 生产 ProviderContainer 零 override | PASS |
| E12 | v41→v42 迁移 | PASS |
| E13 | 旧 Adventure 兼容 | PASS |
| E14 | draft/archived canon 泄漏 | PARTIAL：archived 排除；draft 见 MINOR-1 |

## Validation（独立运行，非引用执行报告）

- `dart format --output=none --set-exit-if-changed .`：487 files / 0 changed
- `flutter analyze`：No issues found
- Phase 10 定向（8 文件）：46 passed / 0 failed
- `flutter test` 全量：**1505 passed / 0 failed / 0 skipped**
- `git diff --check`：干净
- 对抗探针：6 项（P1–P6），在 /tmp 独立副本运行，审计后已删除副本

## Findings

### BLOCKER

无。

### MAJOR

#### P10-A1（MAJOR）：Adventure 快照冻结不完整 —— `characterCard` 与 `supportingCharacters` 未从 assembly revision 冻结

**Evidence:**

- `lib/features/adventure/presentation/wizard/screens/adventure_wizard_screen.dart`
  `_composeAdventureConfig`（约 :1937-1941）：
  `characterCard: protagonist.libraryEntry?.card ?? CharacterCard.fromJson(protagonist.rawJson)` ——
  来自 live 库行；`_supportingWithNpcs`（约 :1909-1924）：
  `SupportingCharacter.fromJson({..._npcJsonOf(row), 'id': assetId})` ——
  NPC 全量 json 来自 live 行 `json_data`。
- `lib/application/adventure/adventure_readiness_gate.dart`
  `enforceAndFreeze`：仅重写 `worldviewSnapshot`、
  `selectedCharacters[].characterCardJson`、`npcSnapshots[].npcJson` 并写
  `resourceBindings`；**不重写 `config.characterCard` 与
  `config.supportingCharacters`，也不写主角标量字段**
  （name/gender/age/personality/protagonistBackground 亦为 live 向导状态）。
- 生产提示词确实消费这些字段：
  `lib/engines/chat_engine_internals/prompt_builder.dart:35` →
  `AppConfig.adventurePrompt` → `lib/config/app_config.dart:197-200`
  `_buildCharacterCardSection(config.characterCard)`；
  `config.supportingCharacters` 被 `lib/engines/chat_engine.dart:1250/2066`
  等运行时路径消费。

**Trigger:**

1. 资源就绪（Assembly A ready）→ 用户编辑产生 head B；
2. Wizard 启动 → readiness 判定 `staleWithPreviousReady` → 用户显式选择
   「使用上一个已就绪版本」→ 写入 `staleAllowed` binding；
3. `createAdventure` → `enforceAndFreeze` 放行并冻结 revision A 的
   worldview/selectedCharacters，但 `characterCard` 与
   `supportingCharacters` 保留 head B（live）内容。

**Observed behavior:** 同一 Adventure 内世界观与选中角色卡为 revision A
内容，而主角卡（提示词 `characterCard` 段）、配角与 NPC 运行时数据为
head B 内容；`resourceBindings` 声明采用 revision A。

**Expected behavior:** 显式选择旧 revision 后，所有来自该资源的运行时
内容（含 `characterCard`、`supportingCharacters`）都应从 revision A 的
assembly 输出重建，或至少与 binding 声明一致。

**Root cause:** 冻结替换的字段清单与运行时实际消费的字段清单不一致；
`characterCard`/`supportingCharacters` 是 legacy 兼容载体，Phase 10 只
冻结了「新载体」（selectedCharacters/npcSnapshots/worldviewSnapshot）。

**Impact:** Case D（显式旧版本）分支产生跨版本混合的冒险，用户显式
选择被静默部分违背；provenance（bindings）与实际提示词内容不一致。
正常 ready 路径因 gate 要求 assembly==head，live 与 revision 内容相等，
无可观察差异，但主角卡 prompt 载体本身从未绑定 revision。

**Required fix:** `enforceAndFreeze` 在 stale-allowed（以及所有 unified
主角）场景下同步重建 `characterCard`（由 revision 的 cardRow 反序列化）
与 `supportingCharacters` 中对应 id 的条目（含 NPC json），或把
`supportingCharacters` 改为从冻结的 `selectedCharacters`/`npcSnapshots`
派生；并为此补 stale-allowed 分支的字段级断言测试。

**Required tests:** stale-allowed 场景中 A/B 两版内容不同的角色与 NPC，
断言 `config.characterCard`、`supportingCharacters`、
`npcSnapshots` 三者内容全部来自 revision A。

### MINOR

#### P10-M1（MINOR，latent）：confirmed Section 下的 draft Part 文本进入 canon fragments 与语义索引文档

**Evidence:** `resource_assembly_builder.dart` `_CanonFilteredView`
仅剔除 archived；`ResourceAdventureView.toWorldviewRow` 将 section 下
所有非 archived Part 文本合并为 module 内容且 module `status` 取自
section；`WorldviewDetails.confirmedModules` 只检查 module 级 status。
探针 P5 实测：`draft_in_index=true`，且 section fragment（isCanon=true）
文本包含 draft Part 文本（与 fragments 逐 Part 的 `isCanon=false` 自相矛盾）。

**Trigger:** 需要「section=confirmed 且其下存在 draft Part」的树状态。
当前生产写方不存在该状态（`LegacyResourceMapper` 同时写 confirmed；
Phase 3 pipeline 保持 draft，无部分确认流程），故为 latent。

**Impact / Root cause:** payload/index 路径与 fragments 路径的 canon
粒度不一致（section 级 vs 节点级）。一旦未来引入 Section 级确认流程，
draft 事实将静默进入 Runtime 上下文，届时应升级为 MAJOR。

**Required fix:** payload 与索引文档派生前按 Part 的冻结 status 过滤
（与 fragments 同粒度），或强制 section 状态与其 Parts 状态一致性校验。

**Required tests:** confirmed section + draft part + archived part 的
worldview，断言 index docs 与 payload 不含 draft 文本。

#### P10-M2（MINOR）：assembly 索引文档不随 revision 清理，产生孤儿行与无界增长

**Evidence:** `AssemblyReadinessRepositoryImpl.replaceIndexDocsInTransaction`
只按 `(resource_id, revision_id)` 替换；`ResourceRevisionService.pruneRevisions`
仅保护 assembly head，被发布更新的旧 assembly revision 过保留期后可被
清理，其 `resource_assembly_entries` 行永远残留。

**Trigger:** 同一资源多次 assembly 发布 + 90 天保留期回收。

**Impact:** 索引表无界增长；孤儿文档引用已删除 revision（当前无读取
路径按旧 revision 取文档，未构成一致性破坏）。

**Required fix:** 发布新 assembly 后清理不再被任何 readiness 行/回收站
引用的旧 revision 文档，或在 retention 清理中同步清理文档。

### INFO

#### P10-I1：双 prepare 中被丢弃一方的 outcome 可能快照到新属主的 `preparing` 中间态

P3 探针观察：并发双方中失去 token 的一方返回的 record 为新属主当时
（preparing）的行，终态收敛 ready。调用方（Wizard 随后重新 resolve）
语义正确；仅说明 `AssemblyPrepareOutcome.record` 不保证反映「本次运行」
的终态。可考虑在 outcome 中显式标注 `ownershipLost`。

#### P10-I2：两处未接线的死代码

`AssemblyReadinessCoordinator.readiness()`（无生产调用方）与
`DatabaseService.createAdventure` 静态透传（无调用方，先于 Phase 10
存在）。前者建议删除或在 Gate 中使用，避免后续审计误读接线。

## Final Decision

**FAILED** —— P10-A1（MAJOR）必须修复：Phase 10 显式支持的
「使用上一个已就绪版本」分支产生跨版本混合的 Adventure 快照，且
`characterCard`/`supportingCharacters` 的运行时内容未绑定 assembly
revision。修复并补齐字段级冻结测试后可提交复验（Round 2）。

## Phase 11 Gate

**BLOCKED**（维持；本报告未修改 STATUS.md，状态同步由后续 Agent 按
流程处理）。
