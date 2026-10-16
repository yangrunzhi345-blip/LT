# Audit Result — b88aa6f：SQLite Schema v50 迁移与动态弹性预算历史兼容性

Status: PASS WITH FINDINGS（BLOCKER: 0，MAJOR: 0，MINOR: 3，INFO: 3）

审计模式：Independent Read-only Audit
基线：`main` @ `b88aa6f`（工作区审计开始时 clean；`origin/main` = `76ca400`）
范围：仅 commit `b88aa6f` 的 Schema v50 迁移与弹性预算历史兼容性。
方法：只读代码/调用链核对 + 定向测试执行；未修改生产代码、测试代码或数据库文件。仅本报告文件被写入。

## 实际执行与真实结果

- `git status --short` → 空；`git log --oneline -3` → `b88aa6f`/`76ca400`/`15957dd`。
- `flutter test`（迁移 11 个文件）→ `+46 All tests passed!`
- `flutter test`（预算 5 个文件：generation_budget_policy / elastic_breakout / resource_integrity_authorized_ceiling / configurable_elastic_budget / generation_aggregate_budget）→ `+67 All tests passed!`
- `flutter analyze --no-pub` → `No issues found!`
- 依赖源码核对：`~/.pub-cache/.../sqflite_common-2.5.5/lib/src/database_mixin.dart`（onUpgrade 事务语义）。
- 未执行：真实进程中断迁移、崩溃后恢复流程、付费 LLM、全量套件（同一 commit 上此前已执行过一次：`+4211 ~7`，本次不重复计入本审计结论）。

## 变更核对（代码证明）

- DDL：`database_service.dart:987` `budget_policy_version INTEGER NOT NULL DEFAULT 1`。
- 迁移：`database_service.dart:2594-2603` `safeAddColumn(..., 'INTEGER NOT NULL DEFAULT 1')`（幂等，`:208-217`）。
- 写入：`saveBlueprint`（`resource_blueprint_repository.dart:179`）写入 current(2)；`confirmBlueprint`（`:525`）在冻结 E 的同一事务写入 current(2)。
- 读取/判定：`_readBlueprintBudgetInTransaction`（`resource_generation_task_repository.dart:487`，`SELECT *`）→ `_cumulativeCeilingOf`（`:459`，`policyVersion ?? legacy`）→ `ceilingFor`；`ceilingFor >= 2` 用新公式，否则 `min(..., A)`。
- 授权解析：`authorized_generation_budget.dart:49-92`，`WHERE status='confirmed' AND resource_id IN (...)`，对同一资源取 `max(C)`，空/草稿/跨资源均不授予。

结论：旧任务（升级后默认 v1）走 `min(floor(T×(100+E)/100), A)`；新确认任务冻结 v2 走 `floor(T×(100+E)/100)`。**代码层面成立。**

## 迁移覆盖矩阵

| 场景 | 证据 | 结论 |
| --- | --- | --- |
| 全新安装 | DDL `:987`；`database_migration_v50_test.dart:53-65` | PASS |
| v49→v50 加列（含已填充行默认 1） | `:2594-2603`；`v50_test:76-141` | PASS |
| v48→v50（elastic_percent 已存在） | `database_migration_v49_test.dart` | PASS |
| v36/v38/v39/v40/v41/v42→v50 | 各测试仅断言 `user_version` | PASS（列未断言，见 I1） |
| 重复迁移幂等 | `v50_test:143-150`；v40/v41 "safe to run twice" | PASS |
| 升级中断/回滚 | sqflite `database_mixin.dart:1130-1160`：onUpgrade 位于 `transaction(exclusive:true)`，`user_version` 同事务写入；`database_service.dart:365-370` 预拷贝 `.backup.v$oldVersion`；`safeAddColumn` 幂等 | PASS（依赖源码+备份证明；未执行真实中断） |
| 数据恢复（打开失败/损坏） | `database_service.dart:262-303` 恢复后 `onCreate: createV44Schema`（含新列） | PASS（代码；未执行） |
| 历史 NULL elastic / 非 NULL / 已确认 / 失败 / 恢复 | v50 默认 1 + NULL→20；`elastic_budget_matrix_test.dart`(H/I)；`configurable_elastic_budget_sqlite_test.dart:151-164` | 语义 CODE-PROVEN；commit 路径未测（C1） |
| 未确认（draft）不授权 | `authorized_generation_budget.dart:67` | CODE-PROVEN；无测试 |

## Findings

### C1

等级：MINOR

标题：v1（历史）预算语义仅在"读取/分类"路径被测试，commit 边界未被任何自动化测试锁定。

问题：唯一断言 legacy `min(..., A)` 的测试只验证 `AuthorizedGenerationBudgetReader.authorizedCeiling`，未验证 `_cumulativeCeilingOf`/`commitPartContent` 的累计上限。需求第 5 条"旧任务仍遵守 min(…)"缺少回归锁。

位置：
- 文件：`lib/application/resources/resource_generation_task_repository.dart`
- 方法：`_cumulativeCeilingOf`（:459）、`_readBlueprintBudgetInTransaction`（:487）、提交检查（:797-843）
- 代码路径：`commitPartContent → _budgetAllocationInTransaction(:603) → _readBlueprintBudgetInTransaction(:609) → _cumulativeCeilingOf(:665)`
- 测试：`test/application/resources/elastic_breakout_budget_sqlite_test.dart:246-266`（仅断言 reader）

触发条件：任何 v1 已确认任务（E>20%，T 达 nominal）提交 Part。

实际影响：无当前缺陷（代码分派正确）；但未来把 legacy 分支误改为突破公式时没有测试会失败 → 历史任务被追溯放宽的静默回归风险。

根因分析：新 legacy 测试断言的是授权解析层，而非 commit 消费层。

修复方案：新增 SQLite 测试：构造 v1 行（T=50000, E=50），断言 `budgetAllocation().ceiling == 60000`，且累计跨 60000 的提交被 `PartGenerationValidationException` 拒绝。

验证方式：如上场景断言 `ceiling` 与拒绝。

---

### C2

等级：MINOR

标题：对同一资源重复生成时，授权上限取"所有已确认 blueprint 的最大值"，导致有效容量/手动写入上限宽于当前运行的授权。

问题：`authorizedCeiling` 对 `resource_id` 取 `max(C)`；`confirmBlueprint` 不会把同一资源旧的已确认行置为 superseded（`resource_blueprint_repository.dart` 仅在 `revision>1` 时把 **draft** 置 superseded）。因此对已存在资源的 re-generation 会保留旧（可能更大）的授权。

位置：
- 文件：`lib/application/resources/authorized_generation_budget.dart:86-90`
- 代码路径：`resource_ai_creation_orchestrator.dart:245 explicitResourceId: targetResourceId → confirmBlueprint(resource_id=既有资源) → 追加新的 confirmed 行`
- 消费者：`resource_crud_controller.dart:120-129`（手动写入上限）、`assembly_readiness_coordinator.dart:813-816`、`resource_capacity_repository.dart:167-168`

触发条件：资源 R 先以 T=20000,E=50（C=30000）生成并确认；再以 E=0（C=20000）re-generate 到同一资源。旧 confirmed 行保留 → `authorizedCeiling(R)=30000`。

实际影响：`_authorizedWidenedCeiling` 允许手动角色卡/NPC 保存至旧 C（30000），而当前运行仅授权 20000；容量分类把 24000<len≤30000 视为 `elastic`。无跨资源泄漏，不丢数据，仍受真实历史授权约束，故为 MINOR；但与"授权应对应当前运行"的意图存在偏差。

根因分析：只放宽不收窄的 `max` 聚合，未绑定"最新/当前" confirmed blueprint。

修复方案（二选一）：re-confirm 同一资源时把该资源旧的 confirmed 行置 superseded；或在 `authorizedCeiling` 只取该资源最近一次 confirmed blueprint；或把授权上限落在资源行上。

验证方式：SQLite 测试建两条同资源 confirmed blueprints（C=30000 与 C=20000），断言有效上限符合设计选择。

---

### C3

等级：MINOR

标题：新增的"授权感知"分支缺少自动化覆盖（控制器扩宽、Studio 版本显示、draft 排除）。

问题：以下新分支无测试证明：
1. `ResourceCrudController._authorizedWidenedCeiling` 的生产装配（`resourceCrudControllerProvider` 注入真实 reader）与真实 DB 的组合未被任何测试执行——现有 widget/integration 测试均以无 reader（null）构造控制器。
2. `resolveSessionBudgetPolicyVersion`（:679）链路（runtime/controller/Studio 摘要）无测试，fakes 返回 null。
3. `AuthorizedGenerationBudgetReader` 排除 draft/未确认行的行为无显式测试。

位置：
- 文件：`lib/controllers/resource_crud_controller.dart:120-129`（+调用点 :266,:315,:442,:483,:516）
- 文件：`lib/application/resources/resource_creation_pipeline.dart:679`
- 文件：`lib/features/resource_studio/application/use_cases/resource_studio_runtime.dart:242-247`、`presentation/pages/resource_studio_page.dart:1717-1728`
- 文件：`lib/application/resources/authorized_generation_budget.dart:67`

触发条件：对 AI 生成的角色/NPC/世界观执行重新编辑保存；在 Studio 打开 legacy(v1) 运行；对含 draft blueprint 的资源做容量测量。

实际影响：测试路径 ≠ 生产路径（skill 原则 3）。代码当前正确，但该注入/显示/排除一旦断开不会被测试发现。

根因分析：新分支只用 pure-function 或 fake 层覆盖。

修复方案：增加 SQLite 集成测试（真实 reader + 真实 DB + AI 生成资源后走 `saveCharacterCardDraft`）与 Studio 摘要 Widget 测试（v1 vs v2 冻结行显示不同 ceiling）；对 reader 增加 draft 排除断言。

验证方式：如上。

---

### I1

等级：INFO

标题：v36/v38/v39/v40/v41/v42→v50 的升级测试未断言新增列及其 legacy 默认值。

位置：`test/application/resources/database_migration_v36_test.dart` 等（仅 `expect(await _userVersion(db), DatabaseService.schemaVersion)`）。
影响：`v36→v50 后 `budget_policy_version` 存在且为 1` 目前是"阶梯 + DEFAULT 1"推断，非断言。
建议：在这些测试的新装/升级断言中追加 `contains('budget_policy_version')`。

### I2

等级：INFO

标题：读取列与列序的健壮性不对称。

位置：`authorized_generation_budget.dart:64-70`（显式 `SELECT ... budget_policy_version`）vs `resource_generation_task_repository.dart:491`（`SELECT *`，缺列时为 null→legacy）。
说明：若 reader 被指向未迁移的旧库会 `no such column` 抛错（生产上 `DatabaseService` 必先迁移，故不可达）；且全新安装的列位置（`elastic_percent` 之后）与升级库（列尾）不同。当前无位置式 INSERT，故无实际缺陷。
建议：如需更强健壮性，读取前 `columnExists` 守卫（可选）。

### I3

等级：INFO

标题：批量 `IN (...)` 查询的变量上限。

位置：`authorized_generation_budget.dart:66-68`。
说明：N=资源数；仅被 `ResourceCapacityService.measureAll` 调用，而该方法当前无生产调用方（仅测试）。超大量资源（~3 万）才会触及 SQLite 变量上限。
建议：如 `measureAll` 未来进入生产，改为分页/临时表。

## 历史兼容性结论

- 升级不会追溯放宽：v50 新增列 `DEFAULT 1`，`ceilingFor(policyVersion<2)` 走 `min(…,A)`；旧 confirmed 任务的 C 与升级前逐位一致（世界观 50000+50% 仍为 60000，而非 75000）。**代码 + v50 迁移测试 + reader 测试证明。**
- 新确认任务冻结 v2 → 突破公式。**代码 + 迁移/域测试证明。**
- NULL elastic：v1 + NULL→20 → 旧语义。**代码证明。**
- 已确认/失败/暂停/恢复：恢复路径不重写蓝图行（`recoverInterruptedTasks`），预算不漂移。**既有 H/I 测试 + 代码证明。**
- 未确认/草稿、跨资源：reader 以 `status='confirmed'` 且 `resource_id` 精确匹配，拒绝。**代码证明（无测试）。**
- 唯一偏差：同一资源重复生成时的 max-widen（C2），属设计取向而非数据错误。

## 未覆盖场景（不得据此高估完整性）

1. 真实进程中断/断电导致的迁移中断（仅由 sqflite 事务语义 + 文件备份推断）。
2. 崩溃后走恢复分支（`database_service.dart:262-303`）的端到端执行。
3. legacy v1 的 commit 上限（C1）。
4. 同一资源多 confirmed blueprint 的上限聚合行为（C2）。
5. 控制器真实 reader 注入 + Studio 版本显示的端到端（C3）。
6. 每一年老版本升级后新列的显式断言（I1）。
7. 并发 confirm 与 commit 交错的实际调度（判定逻辑为只读+事务内读，代码层面无 lost update，但未做交错压力测试）。

## 是否建议进入最终发布验收

**建议进入，但附带条件。** 未发现 BLOCKER/MAJOR，迁移与历史兼容性的**代码证明充分**（含依赖层事务语义），定向测试全绿。建议在发布验收前补齐 C1、C3 两条测试（成本低、直接锁定本次核心声明），C2 需产品确认"只放宽不收窄"是否为预期；I1–I3 可排期。
