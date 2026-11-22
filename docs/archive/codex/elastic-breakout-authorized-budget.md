# 授权 AI 生成弹性预算突破绝对容量（Elastic Breakout）

状态：Implemented（Integrated Single-Agent Full-Cycle）
基线：`main` @ `76ca400`（本任务起点）
范围：世界观 / 角色卡 / NPC 的 AI 资源生成系统

## 1. 问题

旧预算公式对授权 AI 生成任务的累计上限做了绝对容量裁剪：

```
C = min(floor(T × (100 + E) / 100), A)
A: 世界观 60000，角色卡 / NPC 24000
```

一旦 `floor(T × (100+E)/100)` 超过 A（例如世界观 50000 + 50% = 75000 > 60000），弹性配置就无法继续增加真实生成容量。目标是把公式改为：

```
C = floor(T × (100 + E) / 100)
```

且 `A` 不再裁剪已授权任务的 C，同时保留普通资源、导入、手动写入的容量保护。

## 2. 根因：A 实际裁剪/阻断 C 的全部作用点

| # | 位置 | 作用 |
| --- | --- | --- |
| 1 | `GenerationBudgetPolicy.cumulativeCeiling`（`resource_limits.dart`） | `min(..., A)` 公式本体 |
| 2 | `PartGenerationTaskRepositoryImpl._cumulativeCeilingOf` | 唯一生产消费者，把 `A=60000/24000` 传入公式 |
| 3 | `AssemblyReadinessCoordinator._capacityStatusOf` | 用 `policy.absoluteCharacters` 分类：C>A 的正文被判为 `overflow`，装配强制压缩、冒险无法启动 |
| 4 | `ResourceCapacityRepositoryImpl` / `ResourceCapacitySnapshot.status` | 容量快照状态同样只按 A 分类 |
| 5 | `CompressionTriggers.evaluateResource` | 以 A 判定 `capacityOverflow` |
| 6 | `ResourceIntegrityValidator._validateCard` / `validateWorldview` | 角色卡/NPC/世界观 JSON 重新编辑在 A（世界观为 50000）处 fail-closed |
| 7 | UI `_elasticCeilingFor` / `_GenerationBudgetSummary` | 显示被 A 裁剪后的假上界 |

## 3. 设计

### D1 新公式与版本化（历史兼容）

`A` 被移除出已授权任务的 C，但这会让**已冻结**的任务被追溯放宽（旧 `min(..., A)` → 新公式）。因此引入**预算策略版本**：

- `legacyBudgetPolicyVersion = 1`：`C = min(floor(T×(100+E)/100), A)`（历史语义）。
- `currentBudgetPolicyVersion = 2`：`C = floor(T×(100+E)/100)`（突破语义）。

`GenerationBudgetPolicy`：
- `cumulativeCeiling({target, elasticPercent})` — v2 公式，不再接收 `absolute`。
- `legacyCumulativeCeiling({target, absolute, elasticPercent})` — v1 公式。
- `ceilingFor({target, absolute, elasticPercent, policyVersion})` — 版本分派，持久化消费者使用。

`resource_blueprints.budget_policy_version INTEGER NOT NULL DEFAULT 1`（v50 迁移，`safeAddColumn` 幂等）：历史行保持 1；`confirmBlueprint` 在冻结 E 的同一事务写入 2。因此：

- 新创建/确认任务使用新规则；
- 已确认旧任务保持原累计预算；
- 历史 NULL 弹性快照（NULL → 20%）保持旧语义；
- 失败恢复 / 重试不重写快照 → 预算不漂移。

### D2 从理论最小上限推导

接受标准的推导：

- 世界观 T=50000：E=0/20/50 → C=50000/60000/75000。
- 角色卡 T=20000：E=0/20/50 → C=20000/24000/30000。
- NPC T=20000：同上。
- E=0 → C=T；允许恰好 C，拒绝 C+1。

### D3 有效容量（授权而非全局放开）

`ResourceCapacityPolicy.effectiveCharacters(A, authorized) = max(A, authorized)`，其中 `authorized` = 资源所有已确认 blueprint 的最大冻结 C（`AuthorizedGenerationBudgetReader` 解析，**仅** confirmed 行）。

- 普通资源 / 导入 / 手动写入：无授权 → `effective = A`，行为逐位不变。
- 已授权 AI 资源：`effective = max(A, C)`，正文 ≤ C 判为 `elastic`（不强制压缩），> C 才 `overflow`。
- 只放宽不收窄：即使 C < A（如小目标）也不会把有效边界压到 A 以下。

`statusForEffective(count, effectiveAbsolute)` 承载分类；`statusFor(count)` 等价于 `effective = A`。

### D4 装配 / 压缩链路

`AssemblyReadinessCoordinator._capacityStatusOf` 分类前先解析授权 C，使用 `effectiveAbsolute`。于是授权正文 > 旧 A 时不会再进入强制压缩分支，装配可发布、冒险可启动。`ResourceCapacitySnapshot.effectiveAbsoluteCharacters` 与 `CompressionTriggers.evaluateResource` 同样使用有效边界，容量状态与压缩触发与后端一致。

### D5 卡面 JSON 校验的可追溯授权

`ResourceIntegrityValidator.validateCharacterCard / validateNpcCard` 增加可选 `effectiveCeiling`（内部 `max(该值, A)`，防止调用方收窄）；`validateWorldview` 增加可选 `maxTotalCharacters`（`max(该值, 50000)`）。

`ResourceCrudController` 通过可选注入的 `IAuthorizedGenerationBudgetReader` 解析目标资源的授权上限；**无授权时返回 null**，校验回退到普通上限。因此重新编辑授权资源不会被 A 拒绝，普通保存不被放宽。

### D6 未削弱项

单 Part 3000 字上限、内容契约、NDJSON、CAS（`updated_at` 源码版本）、事务原子提交、未来必填 Part 预留、已保存正文不覆盖、不可变版本历史、失败重试上限、冒险就绪门禁全部保留。规划 token 预算仍由 `BlueprintTokenBudgetPolicy` 动态推导，未重新引入固定 4096。

## 4. 修改文件

域与公式：
- `lib/domain/resources/resource_limits.dart`
- `lib/domain/resources/resource_capacity.dart`
- `lib/domain/resources/resource_compression.dart`

持久化与冻结：
- `lib/services/database_service.dart`（v50 + DDL + 迁移）
- `lib/application/resources/resource_blueprint_repository.dart`（写入版本）
- `lib/application/resources/resource_generation_task_repository.dart`（按版本计算 C）
- `lib/application/resources/authorized_generation_budget.dart`（新增：授权上限解析）

容量 / 装配 / 校验：
- `lib/application/resources/resource_capacity_repository.dart`
- `lib/application/resources/assembly_readiness_coordinator.dart`
- `lib/services/resource_integrity_validator.dart`
- `lib/controllers/resource_crud_controller.dart`

UI 与装配线：
- `lib/features/resource_library/presentation/screens/resource_ai_create_page.dart`
- `lib/features/resource_studio/application/use_cases/resource_studio_runtime.dart`
- `lib/features/resource_studio/presentation/controllers/resource_studio_controller.dart`
- `lib/features/resource_studio/presentation/pages/resource_studio_page.dart`
- `lib/application/resources/resource_creation_pipeline.dart`（会话预算版本解析）
- `lib/providers/riverpod_providers.dart`

测试：
- `test/domain/resources/generation_budget_policy_test.dart`
- `test/application/resources/elastic_breakout_budget_sqlite_test.dart`（新增）
- `test/services/resource_integrity_authorized_ceiling_test.dart`（新增）
- `test/services/database_migration_v50_test.dart`（新增）
- 既有预算 / 规划 / 迁移 / 装配测试版本对齐

## 5. 兼容性

- v50 迁移幂等；旧库升级后 `budget_policy_version` 默认 1，历史任务预算逐位不变。
- 资源、任务、修订、SQLite 数据不被删除或改写；仅新增一列并回填默认值。
- 旧任务的容量分类仍以 A 为边界（授权 C ≤ A），行为不变。

## 6. 剩余风险

- 授权正文处于 `(nominal, C]` 的 `elastic` 带，仍会触发**机会性**（非阻塞、需显式批准）压缩候选，与既有 A 带语义一致。
- 授权上限取资源所有 confirmed blueprint 的**最大** C；重新规划只会放宽有效边界，符合"只放宽不收窄"取向。
