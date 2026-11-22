# Remediation Phase 12 — Migration & Serialization Hardening

> **Root Cause**: RC-12
> **Findings**: N1, N2, N3, N16, N17 (MINOR)
> **Depends On**: None
> **Document status**: PLANNED

---

## 1. Purpose

数据库迁移与序列化层存在若干潜伏健壮性缺陷：

- 迁移期间的 `PRAGMA foreign_keys = OFF` 在 sqflite 的事务内**无效**，迁移实际以 FK=ON 执行；当前仅
  靠 DROP 顺序侥幸通过（N1）；
- 非幂等的数据迁移步骤 `createNarrativeMapSchema` 的坐标归一化（N3）；
- 资源库读取对任意 DB 异常 `catch (_) { return []; }`，一条坏行/一次 DB 故障会让整个 tree-only 资源
  列表消失（N2）；
- `WorldEntry` 用 `enum.index` 序列化 `insert_position`，`values[index]` 越界抛 `RangeError`，且
  `parseKeys` 的 `jsonDecode` 无保护，单行坏数据中断整个上下文加载（N16）；
- enum 解析策略不一致（有的抛错、有的静默默认），语义漂移（N17）。

本 Phase 修复的 contract 是：**“迁移必须明确且真实地控制 FK enforcement；数据迁移步骤必须幂等；
读取层对单行损坏必须 fail-soft 且不掩盖真实故障；序列化必须使用稳定编码并统一解析策略。”**

## 2. Audit Findings Covered

```text
Primary:
- N1   迁移期 PRAGMA foreign_keys=OFF 在事务内无效（假安全不变量）
- N2   _treeOnlyRows 吞掉所有 DB 异常 → 资源库“看起来为空”
- N3   createNarrativeMapSchema 坐标归一化非幂等
- N16  WorldEntry insert_position 按序数序列化 + parseKeys 无保护
- N17  enum 解析策略不一致（throw vs 静默默认）
```

## 3. Current Production Architecture

### 3.1 打开与迁移

```text
DatabaseService._initDb                                              (database_service.dart:189+)
  openDatabase(path, version: schemaVersion,
    onConfigure: (db) { PRAGMA foreign_keys = ON; PRAGMA journal_mode = WAL; }   (:242-245)
    onCreate: createV43Schema
    onUpgrade: migrateStepByStep(db, old, new)                        (:248-254)
  )
DatabaseService.migrateStepByStep                                     (:1809+)
  // 注释声称迁移期关闭外键 (:504-505, :595-596)
  // 实际 `PRAGMA foreign_keys=OFF` 位于 onUpgrade 事务内 → 无效
  createNarrativeMapSchema                                            (:1595-1596)
    UPDATE map_nodes SET x = x / 960.0 WHERE x > 1.0
    UPDATE map_nodes SET y = y / 720.0 WHERE y > 1.0
  dropLegacyQuestAndMapTables                                          (:606-622)
```

### 3.2 库读取

```text
LibraryRepositoryImpl._treeOnlyRows                                  (library_repository_impl.dart:202-238)
  try { resources = await _treeReader.listResources(...); }
  catch (_) { return const <Map<String, dynamic>>[]; }                (:213-215)
ResourceTreeRowMapper.resourceFromRow 会对坏 metadata/type/status 抛 ResourceTreeCorruptedException
```

### 3.3 WorldEntry 序列化

```text
lib/models/world_entry.dart
  toJson: 'insert_position': insertPosition.index                    (:71)
  fromJson: WorldEntryPosition.values[(json['insert_position'] as int?) ?? 1]  (:101-102)
  parseKeys: (jsonDecode(keysVal) as List<dynamic>).cast<String>()   (:80-89)
lib/services/repositories/world_entry_repository_impl.dart:25 逐行加载，无 per-row 保护
lib/services/database_service.dart:1736  insert_position INTEGER DEFAULT 1
enum WorldEntryPosition { beforePrompt, afterPrompt, inAuthorNote, beforeHistory, afterUser }
```

### 3.4 enum 解析

```text
ResourceType.fromStorageValue            throws        (domain/resources/resource_contracts.dart:68-73)
BlueprintStatus.fromStorage              → draft        (domain/resources/resource_blueprint.dart:13-18)
PartTaskStatus.fromStorage               → pending      (domain/resources/resource_generation_protocol.dart:31-36)
CreationSessionStatus.fromStorage        → draft        (domain/resources/resource_creation_contracts.dart:21-26)
```

## 4. Exact Bugs

### Finding N1 — 迁移期外键未真正关闭

#### Trigger
任何依赖“迁移期 FK 关闭”的迁移步骤（例如换序 `DROP TABLE`、表重建）。

#### Current Behavior
sqflite 在独占事务内运行 `onUpgrade`；SQLite 在事务打开时忽略 `PRAGMA foreign_keys`。`onConfigure`
先执行并设 `foreign_keys = ON`，因此迁移中 FK 实际为 ON。当前 `dropLegacyQuestAndMapTables` 恰好先删
子表后删父表而通过；任何换序都会使整个升级事务失败，应用无法打开数据库。
`purgeNodeInTransaction` 的注释（`resource_tree_repository_impl.dart:1216-1218`）也基于同一错误前提。

#### Expected Behavior
在打开/升级前于**事务外**决定 FK enforcement；迁移期应关闭或使用 `defer_foreign_keys`，并让文档
描述与事实一致。

#### Evidence
```text
file: lib/services/database_service.dart:242-245（onConfigure），:332-336（onUpgrade 内 PRAGMA OFF），
      :504-505/:595-596（注释），:606-622（DROP 顺序）
既有测试: database_migration_v42_test.dart:225-229 使用无 FK 的简化表，从不触发真实 FK 图
```

#### User / Data Impact
未来迁移若换序 → 升级整体失败、用户无法打开数据库（潜在 BLOCKER 级，当前潜伏）。

---

### Finding N2 — 库读取吞掉所有 DB 异常

#### Trigger
`resources` 中某行 `metadata_json` 损坏、`type`/`status` 未知，或任意 DB 异常。

#### Current Behavior
`_treeOnlyRows` 的 `catch (_) { return []; }` 使 `listResources` 抛出的
`ResourceTreeCorruptedException`（单行坏数据即可导致）被吞，库中所有 tree-only（Phase 3 入口创建）
资源一并消失，无任何错误提示。

#### Expected Behavior
只对“表/列不存在”等结构性缺失降级；单行损坏只影响该行并上报；真实 DB 故障应产生可见错误状态。

#### Evidence
```text
file: lib/services/repositories/library_repository_impl.dart:202-215
file: lib/services/repositories/resource_tree_row_mapper.dart:14-23,54-72,79-93
对照: lib/application/resources/resource_read_facade.dart:204、resource_migration_service.dart:157（仅吞“表不存在”）
```

#### User / Data Impact
用户以为资源丢失；真实故障被掩盖。

---

### Finding N3 — 坐标归一化非幂等

#### Trigger
`createNarrativeMapSchema` 被再次执行（恢复/修复工作流、测试重跑）。

#### Current Behavior
`UPDATE map_nodes SET x = x / 960.0 WHERE x > 1.0` 每次执行都会再次除以 960；对 x>960 的数据会持续
缩小。对合法数据（x<=960）一次后 x<=1 而不再命中，因此当前仅在异常数据上表现为非幂等。

#### Expected Behavior
迁移步骤幂等；重复执行不改变数据。

#### Evidence
```text
file: lib/services/database_service.dart:1595-1596
既有测试: database_migration_resource_tree_test.dart:190-209 断言迁移可重跑，但未覆盖含 map_nodes 的路径
```

#### User / Data Impact
潜伏的坐标数据损坏（当前 fresh install 会 drop 该表，影响面小）。

---

### Finding N16 — WorldEntry 序列化脆弱

#### Trigger
未来在 `WorldEntryPosition` 中插入/调整枚举值；或 `keys` / `insert_position` 列损坏。

#### Current Behavior
- 存 `index`：调整枚举顺序会让历史数据指向错误语义。
- 读 `values[index]`：越界（含负数）抛 `RangeError`。
- `parseKeys` 的 `jsonDecode` 无 try/catch；`fromDbMap` 逐行加载且无 per-row 保护 → 单行坏数据中断
  整个 world 上下文装配。

#### Expected Behavior
使用稳定编码（名称/字符串 code）序列化，读取时兼容旧序数；越界与损坏 fail-soft，且不中断其它行。

#### Evidence
```text
file: lib/models/world_entry.dart:71,80-89,101-102
file: lib/services/repositories/world_entry_repository_impl.dart:25
file: lib/services/database_service.dart:1736
```

#### User / Data Impact
一个坏条目导致整个冒险的世界观上下文失败。

---

### Finding N17 — enum 解析策略不一致

#### Trigger
存储中出现未知/损坏的 enum 值（或旧版本读到新版本写的值）。

#### Current Behavior
`ResourceType.fromStorageValue` 抛错（被包装为 `ResourceTreeCorruptedException`），而
`BlueprintStatus` / `PartTaskStatus` / `CreationSessionStatus` 静默默认为某个值（如 `draft`/`pending`），
可能把已完成状态读成初始状态。

#### Expected Behavior
统一的、有文档的策略：身份/关键字段严格拒绝并带诊断；可选/历史字段默认并带诊断。

#### Evidence
```text
file: lib/domain/resources/resource_contracts.dart:68-73
file: lib/domain/resources/resource_blueprint.dart:13-18
file: lib/domain/resources/resource_generation_protocol.dart:31-36
file: lib/domain/resources/resource_creation_contracts.dart:21-26
```

#### User / Data Impact
同一类损坏在不同子系统表现为“整页失败”或“静默错误状态”。

## 5. Root Cause

**Symptom**：迁移/序列化的健壮性依赖隐式假设（FK 关闭、enum 顺序稳定、DB 永不出错）。

**Root Cause**：迁移与序列化没有显式的、可验证的 contract：
- FK enforcement 没有在正确的生命周期点设置；
- 数据迁移步骤没有幂等性约束与测试；
- 读取层的错误处理粒度错误（整表 vs 单行、结构性缺失 vs 真实故障）；
- 序列化使用位置相关编码且解析无统一策略。

## 6. Required Contract After Remediation

1. 迁移期间 FK enforcement 状态**真实可控**，且文档描述与事实一致；迁移不因 FK 顺序失败。
2. 每个数据迁移步骤幂等；重复执行不改变数据。
3. 读取层：结构性缺失可降级；单行损坏只影响该行并上报；真实 DB 故障不被吞。
4. 序列化使用稳定编码；读取兼容旧编码；越界/损坏 fail-soft。
5. enum 解析采用统一、有文档的策略，并有测试守护。
6. 不得改变任何既有 schema 语义；不得降低版本号。

## 7. Implementation Plan

### Step 1 — 迁移期 FK 控制（N1）

```text
file: lib/services/database_service.dart
symbol: _initDb 的 onConfigure (:242-245) 与恢复路径 (:239-255)
```

将 FK 决策移到 `onConfigure`（事务外）：

```dart
onConfigure: (db) async {
  await db.rawQuery('PRAGMA journal_mode = WAL');
  final current = await db.getVersion();
  final upgrading = current != 0 && current < DatabaseService.schemaVersion;
  await db.execute('PRAGMA foreign_keys = ${upgrading ? 'OFF' : 'ON'}');
},
```

- 删除 `onUpgrade` 内无效的 `PRAGMA foreign_keys = OFF`（或替换为 `PRAGMA defer_foreign_keys = ON`
  作为双保险）。
- 修正 `:504-505` / `:595-596` 与 `resource_tree_repository_impl.dart:1216-1218` 的注释与实际一致。
- 恢复路径（`:239-255`）使用同样的 `onConfigure`。

### Step 2 — 迁移步骤幂等（N3）

```text
file: lib/services/database_service.dart
symbol: createNarrativeMapSchema (:1595-1596)
```

- 将归一化限定在合法像素范围：
  `UPDATE map_nodes SET x = x / 960.0 WHERE x > 1.0 AND x <= 960.0`
  `UPDATE map_nodes SET y = y / 720.0 WHERE y > 1.0 AND y <= 720.0`
- 或（更稳妥）先 `UPDATE ... SET x = MAX(0.0, MIN(1.0, x/960.0)) WHERE x > 1.0`（幂等）。
- 选择其一并在测试中断言“重复执行结果不变”。

### Step 3 — 库读取错误粒度（N2）

```text
file: lib/services/repositories/library_repository_impl.dart
symbol: _treeOnlyRows (:202-215)
```

- 只吞“表/列不存在”类错误（例如 `DatabaseException` 中 `no such table`/`no such column`），其余
  rethrow 或转换为可见错误状态。
- 更好的做法：让 `listResources` 逐行 fail-soft（在 mapper 层捕获单行 `ResourceTreeCorruptedException`
  并跳过该行 + 记录诊断），使一行坏数据不影响其它行；`_treeOnlyRows` 只在结构性缺失时降级。
- 实施时优先在 mapper/读取层做 per-row 保护，`_treeOnlyRows` 不再吞真实异常。

### Step 4 — WorldEntry 稳定编码（N16）

```text
file: lib/models/world_entry.dart
symbol: toJson (:71), fromJson (:80-102)
```

- 为 `WorldEntryPosition` 增加稳定 code（例如 `storageValue` 字符串：`before_prompt` 等）。
- `toJson` 写 `insertPosition` 的稳定 code（字符串）。
- `fromJson`：
  - 若 `insert_position` 是 String → 按 code 解析；
  - 若是 int → 按序数解析，且 `0 <= index < values.length` 才使用，否则默认 `afterPrompt` 并记录诊断；
  - 其它类型 → 默认。
- `parseKeys` 用 try/catch 包裹 `jsonDecode`，失败返回 `[]` 并记录诊断。
- `world_entry_repository_impl` 逐行读取时对单行异常 fail-soft（跳过该行 + 诊断），不中断整个加载。

> schema 影响：`world_entries.insert_position` 列为 INTEGER。SQLite 类型亲和会把非数字字符串保留为
> TEXT；因此写入稳定 code 字符串是兼容的。**无需 schema 变更**。既有行（数字）按序数读取。

### Step 5 — enum 解析策略统一（N17）

新增共享解析工具（放在合适的既有 util 位置，避免重复抽象）：

```text
parseEnumStrict<T>(value, valuesByName, {required String field})   // 未知 → 抛 typed 错误
parseEnumLenient<T>(value, valuesByName, {required T fallback, void Function(String)? onUnknown})
```

- `ResourceType` 使用 strict（身份字段）。
- `BlueprintStatus` / `PartTaskStatus` / `CreationSessionStatus` 使用 lenient + 诊断回调。
- 在文档注释中明确“关键身份字段 strict、可选历史字段 lenient”的策略。
- 为每个 enum 增加 round-trip 与 unknown-value 测试。

## 8. Design Decisions

### 8.1 N1 用 `onConfigure` 关 FK 还是 `defer_foreign_keys`

- **方案 A（推荐）**：`onConfigure` 中依据当前版本决定 FK ON/OFF（事务外，真实生效）。
- 方案 B：onUpgrade 内 `PRAGMA defer_foreign_keys = ON`。

**选择 A**（并保留 B 作为双保险）。理由：A 直接、可验证；`defer_foreign_keys` 对 immediate FK 的行为
在复杂迁移中仍有边界。**不采用仅 B。**

### 8.2 N16 用“稳定 code”还是“保留序数 + 边界检查”

**选择稳定 code + 兼容旧序数**。理由：只有稳定编码才能消除枚举重排风险；兼容读取保证旧数据可用。
**不采用仅边界检查**（不解决重排风险）。

### 8.3 N17 严格 vs 宽松

**关键身份字段 strict，可选历史字段 lenient。** 理由：身份字段读错会导致内容错配；历史字段读错只
影响展示/恢复能力，静默默认 + 诊断更稳。

## 9. Database Impact

```text
No schema change required.
- 不新增列/表，不修改 schemaVersion（保持 43）。
- N3 修改既有迁移步骤逻辑（仅影响未来从 <21 升级的路径），无需版本提升。
- N16 将 insert_position 写为字符串 code；列保留 INTEGER 类型（SQLite 类型亲和接受 TEXT），
  旧数据（数字）按序数兼容读取。
- N1 改变 onConfigure 的 FK 设置时机，不改 schema。
- 回滚为纯代码 revert；无破坏性迁移。
```

若实施时决定把 `insert_position` 列迁移为 TEXT（显式），则必须：schemaVersion +1、幂等 `ALTER`/表重建
迁移、fresh install 与旧库双向测试。**默认不采用该方案。**

## 10. Concurrency / Sequence

### 10.1 N1 修复后

```text
openDatabase
  → onConfigure (TX 外): WAL; FK = OFF when upgrading
  → onUpgrade (TX 内): DROP/ALTER ... (FK 已真实关闭)
  → 提交; 版本更新
  → 后续连接 onConfigure: FK = ON
```

### 10.2 N2 修复后

```text
listResources
  → per-row try/catch: 坏行跳过 + 诊断
  → 其它异常上抛/可见
```

### 10.3 不变量

```text
不变量1: 迁移期 FK enforcement 状态由 onConfigure 决定且真实生效。
不变量2: 任一数据迁移步骤重复执行不改变数据。
不变量3: 单行损坏不导致整表/整个列表消失。
不变量4: 序列化编码与枚举声明顺序无关。
```

## 11. Files Expected To Change

```text
Production（Expected）:
- lib/services/database_service.dart
- lib/services/repositories/library_repository_impl.dart
- lib/services/repositories/resource_tree_row_mapper.dart（per-row fail-soft，若选择该方案）
- lib/models/world_entry.dart
- lib/services/repositories/world_entry_repository_impl.dart
- enum 解析工具 + 各 enum 文件（resource_contracts.dart / resource_blueprint.dart /
  resource_generation_protocol.dart / resource_creation_contracts.dart）

Tests（Expected，新建）:
- test/services/database_migration_fk_enforcement_test.dart
- test/services/database_migration_map_normalization_idempotency_test.dart
- test/services/library_corrupted_row_tolerance_test.dart
- test/unit/world_entry_serialization_robustness_test.dart
- test/domain/enum_parse_policy_test.dart

Tests（Possible，更新）:
- test/application/resources/database_migration_v42_test.dart
- test/services/database_migration_resource_tree_test.dart

Docs:
- docs/post-phase12-remediation/STATUS.md

Forbidden / should not be touched:
- schemaVersion 与既有迁移版本顺序
- 内容写入 CAS（R03）
- 软删除/回收站语义（R05/R06）
- 不删除任何表/列
```

## 12. Test Plan

### TEST R12-01（N1 迁移 FK）
```text
Given: 一个 v42 数据库，含父子表与 FK
When:  升级到 v43（且某 DROP/重建步骤）
Then:  升级成功；FK 状态在迁移期实际为 OFF；升级后恢复 ON
```

### TEST R12-02（N3 幂等）
```text
Given: map_nodes 含边界值（x=1000, x<=1, 负值）
When:  重复执行归一化步骤两次
Then:  第二次结果与第一次一致
```

### TEST R12-03（N2 单行损坏）
```text
Given: resources 中一行 metadata_json 损坏
When:  listResources / 库列表
Then:  其余行仍可见；坏行被跳过并有诊断（或可见错误）
       不出现“整个库为空”
```

### TEST R12-04（N16 稳定编码）
```text
Given: insert_position 存为旧序数 int
When:  fromJson
Then:  正确映射（含越界回退默认）
       写入后读出为稳定 code，语义不变
       keys 为非法 JSON 时返回 [] 不抛
```

### TEST R12-05（N16 单行 fail-soft）
```text
Given: world_entries 中一行 keys 损坏
When:  加载冒险世界条目
Then:  其余条目正常加载；坏行被跳过
```

### TEST R12-06（N17 策略）
```text
Given: 各 enum 的未知存储值
When:  解析
Then:  身份字段抛 typed 错误；可选字段回退默认并产生诊断
```

## 13. Mutation / Negative Verification

```text
Mutation 1: 恢复 onUpgrade 内无效的 PRAGMA foreign_keys=OFF（移除 onConfigure 版本判断）
→ TEST R12-01 必须 FAIL

Mutation 2: 恢复 `x = x/960 WHERE x > 1.0`（无上界）
→ TEST R12-02 必须 FAIL

Mutation 3: 恢复 _treeOnlyRows 的 `catch (_) { return []; }`
→ TEST R12-03 必须 FAIL

Mutation 4: 恢复 `WorldEntryPosition.values[(json['insert_position'] as int?) ?? 1]`
→ TEST R12-04 必须 FAIL

Mutation 5: 让可选 enum 未知值抛错（或不诊断）
→ TEST R12-06 必须 FAIL
```

## 14. Acceptance Criteria

```text
AC-R12-01 迁移期 FK 状态真实可控，迁移不因 FK 顺序失败。
AC-R12-02 数据迁移步骤幂等。
AC-R12-03 单行损坏不导致整表消失。
AC-R12-04 WorldEntry 序列化与枚举顺序解耦，损坏 fail-soft。
AC-R12-05 enum 解析策略统一并有测试。
AC-R12-06 既有全部 migration 测试通过；schemaVersion 不变。
AC-R12-07 全量 flutter test 通过。
```

## 15. Required Verification Commands

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test test/services/database_migration_fk_enforcement_test.dart
flutter test test/services/database_migration_map_normalization_idempotency_test.dart
flutter test test/services/library_corrupted_row_tolerance_test.dart
flutter test test/unit/world_entry_serialization_robustness_test.dart
flutter test test/domain/enum_parse_policy_test.dart
flutter test test/application/resources/database_migration_v36_test.dart
flutter test test/application/resources/database_migration_v39_test.dart
flutter test test/application/resources/database_migration_v40_test.dart
flutter test test/application/resources/database_migration_v41_test.dart
flutter test test/application/resources/database_migration_v42_test.dart
flutter test test/services/database_migration_v38_test.dart
flutter test test/services/database_migration_resource_tree_test.dart
flutter test
git diff --check
git status --short
```

## 16. Out of Scope

- 不改 schemaVersion；
- 不改既有迁移的版本顺序/语义；
- 不做表重建；
- 不处理 R03/R05/R06 的数据一致性问题；
- 不删除代码。

## 17. Rollback / Failure Safety

- 迁移改动若引入问题，既有 migration 测试会失败；回滚为 revert。
- per-row fail-soft 只影响读取，不写数据；最坏情况是隐藏一行坏数据（有诊断），优于整表消失。
- enum 解析工具严格/宽松的选择有测试守护；误判可在测试中立即发现。
- 无破坏性 schema 操作。

## 18. OPEN QUESTION

```text
Q1: `map_nodes` 的合法坐标范围是否严格为 [0,960]×[0,720]？若存在其它范围，Step 2 的守卫需调整
    （file: createNarrativeMapSchema 与 map_nodes 的写入点）。
Q2: 是否已有可复用的 enum 解析 util？若已有，扩展而非新建。
    需要 rg `static .* fromStorage` 与既有 util 目录。
```

## 19. Handoff Notes

- 本 Phase 与 correctness Phase 无强依赖，可较早并行执行，但不得与 R03 的 schema v44 同时修改
  `database_service.dart`（避免版本冲突）。建议 R12 在 R03 之后或以 rebase 方式合入。
