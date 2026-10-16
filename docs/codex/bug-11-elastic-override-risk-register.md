# BUG-11 弹性覆盖持久化 —— 风险台账

本文件是 BUG-11（资源独立弹性覆盖在重新规划后被抹除）及其后续遗留风险的**唯一风险台账**。
它只登记风险状态，不构成新的架构或产品 Authority；接口契约以代码与
[ADR-0003](../architecture/configurable-generation-elasticity.md) 为准。

- 台账更新日期：2026-10-16
- 记录基线：`main` @ `bcd1dfdacb1254e2299d9cf6b0d2f926d0105d25`
- 相关提交：
  - `a9b132a` 原始基线（v1.3.01+33）
  - `64cb4e08` BUG-11 核心修复：`confirmBlueprint` 合并 metadata，保留资源级弹性覆盖
  - `bcd1dfd` P3-2 补充测试：连续两次重新规划仍保留覆盖

## 风险总览

| 编号 | 名称 | 分类 | 优先级 | 状态 | 生产缺陷 |
| --- | --- | --- | --- | --- | --- |
| BUG-11 | 资源独立弹性覆盖在重新规划后被抹除 | CONFIRMED BUG（已修复） | — | RESOLVED | 已消除 |
| P3-1 | `updateResource` metadata 整体替换可能丢失弹性覆盖 | CONFIRMED LATENT RISK | P3 | OPEN / MONITORED | NOT APPLICABLE |
| P3-2 | 连续两次 re-plan 覆盖保留未覆盖 | TEST GAP（已关闭） | — | CLOSED | 不适用 |
| P3-3 | 历史 metadata 禁用键兼容性 | UNVERIFIED | P3 | OPEN / PENDING INVESTIGATION | 未确认 |

---

## BUG-11 —— 资源独立弹性覆盖在重新规划后被抹除（RESOLVED）

- 分类：CONFIRMED BUG，已修复。
- 根因：`confirmBlueprint` 对既有资源重新规划时，`treeDraft.metadata` 只含 confirm
  自有字段，而 `updateResourceTreeInTransaction` 整体替换 `resources.metadata_json`，
  导致 `generationElasticPercent` 被静默删除；该覆盖只对当前一次 confirm 生效。
- 修复：`lib/application/resources/resource_blueprint_repository.dart`（`_confirmOwnedMetadataKeys`
  与 `mergedMetadata` 合并逻辑），在同一 confirm 事务内保留非自有键。
- 修复提交：`64cb4e08`。
- 回归：`test/application/resources/resource_elastic_override_persistence_test.dart`。
- 边界（不得据此宣称全部后续风险消除）：
  - 本次修复只覆盖 `confirmBlueprint` 这一条活动生产写入路径。
  - P3-1（另一写入接口）与 P3-3（历史 metadata 兼容性）为独立风险，另行登记。

---

## P3-1 —— `updateResource` metadata 整体替换可能丢失弹性覆盖

- 风险编号：P3-1
- 风险名称：`updateResource` metadata 整体替换可能导致资源独立弹性覆盖丢失
- 分类：**CONFIRMED LATENT RISK**
- 优先级：P3（低）
- 状态：**OPEN / MONITORED**
- 生产缺陷状态：**NOT APPLICABLE**（当前无活动生产数据丢失路径）
- 处置决定：**DEFERRED** —— 当前不实施代码修复。

### 已确认事实

1. `updateResource` 当前**没有生产调用方**：`lib/` 内仅有接口声明
   （`lib/services/repositories/resource_tree_repository.dart:231`）与实现
   （`lib/services/repositories/resource_tree_repository_impl.dart:361`）；其余引用仅在测试。
2. `metadata` 参数采用**整体替换并保留 provenance** 的既定契约
   （`_preserveProvenance`，`resource_tree_repository_impl.dart:1697-1707`）。
3. 该替换语义**已有测试约束**：`test/services/resource_tree_repository_test.dart:78-104`
   断言传入 `{'tags': [...]}` 后 `tags` 生效且 provenance 被携带。
4. 传入局部或空 Map 时，确实可能删除未携带的 `generationElasticPercent`
   （`metadata == null` 时不动 `metadata_json`，`:375`）。
5. 现有生产链路**没有**通过此方法导致弹性覆盖丢失的路径。
6. BUG-11 的 `confirmBlueprint` 持久化修复独立有效（见上），与本风险无耦合。

### 根因

`updateResource` 接口采用**完整替换 metadata 的设计语义**：`metadata` 非空时以传入 Map
替换整个 `metadata_json`，仅回填 provenance 两键；接口没有字段级 patch/delete 表达。

### 触发条件

未来新增 `updateResource` 生产调用方，并传入**不包含 `generationElasticPercent` 的局部或空 metadata**。

### 潜在影响

资源级弹性覆盖或其他未被本次操作管理的 metadata 字段被静默删除。

### 缓解措施

未来引入生产调用方时，强制审查字段所有权与 metadata 更新意图。

### 建议方案

使用语义明确的字段级更新接口，或在适当的事务边界内执行 read-modify-write
（先读现有 metadata，spread 后写）。

### 禁止方案

未经契约调整，直接将 `updateResource` 改为**无条件 Map 合并**——这会改变
`resource_tree_repository_test.dart:78-104` 锁定的替换契约，并与 BUG-11 的
“仅保留非自有键”规则形成两套冲突的字段所有权规则。

### 重新评估条件

新增 `updateResource` 生产调用方、变更 metadata 更新契约，或发现实际数据丢失路径。

### 关闭条件

有证据证明风险已由**接口约束**或**调用路径防护**消除，且配有针对性回归测试。

---

## P3-2 —— 连续两次 re-plan 覆盖保留（CLOSED）

- 分类：TEST GAP，已关闭。
- 内容：BUG-11 复审指出原测试只覆盖单次 re-plan。
- 处置：新增用例「连续两次重新规划后 generationElasticPercent 仍然存在」
  （`test/application/resources/resource_elastic_override_persistence_test.dart`）。
- 提交：`bcd1dfd`。
- 结果：该文件 **6/6 PASS**。

---

## P3-3 —— 历史 metadata 禁用键兼容性（OPEN / PENDING INVESTIGATION）

- 分类：UNVERIFIED（潜在边界）。
- 状态：**OPEN / PENDING INVESTIGATION**。
- 内容：BUG-11 修复会保留既有资源的非自有 metadata 键。若历史/迁移行的
  `resources.metadata_json` 含 `ResourceMetadataPolicy` 的禁用容器键
  （`lib/services/repositories/resource_metadata_policy.dart:106-111`），修复后 `confirmBlueprint`
  会在 `validate` 抛错，而修复前会静默丢弃该键。
- 当前认知：未调查其真实影响，**不得推断或提前关闭**。仓库内所有 repository 写入均经该策略校验，
  迁移不注入此类键。
- 触发条件：存在含禁用容器键的历史/迁移 metadata 行并被重新规划。
- 关闭条件：完成历史数据调查，证明此类行不存在，或有针对性的迁移/兼容处理与回归测试。

---

## 维护约定

- 本台账只登记状态，不复制代码契约；契约以代码与 ADR-0003 为准。
- 风险编号稳定，不因重新分类而改号。
- 状态取值：`OPEN / MONITORED`、`OPEN / PENDING INVESTIGATION`、`CLOSED`、`RESOLVED`。
- 任何“已消除”结论必须附证据（调用路径防护或接口约束）与回归测试。
