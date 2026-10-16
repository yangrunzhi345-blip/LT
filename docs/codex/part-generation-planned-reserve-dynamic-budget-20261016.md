# Part 生成动态预算：尾段规划容量预留（根因修复与验收）

Status: 实施完成，定向与全量自动化验证记录见「六、验证记录」。
Acceptance Mode: Integrated Single-Agent Full-Cycle（用户一次性授权连续完成实施、验证与验收）。
本文件为本任务的唯一事实记录：根因、算法、改动、测试矩阵与剩余风险。

## 一、基线与范围

- 工作区 `~/LT-generation`，分支 `fix/resource-generation-budget`，起始 HEAD `beb1a47`（与 `main` 同 SHA，工作区干净）。
- 该工作区由本次任务从 `~/LT` 的 `main` 新建 git worktree，用于与另一个 Agent 的 Widget 修复工作区（`~/LT-widget`）及 session 工作区（`~/LT-session-focus`）完全隔离。
- Scope：世界观 / 角色卡 / NPC 的蓝图 Part 正文生成预算分配、可行性与事务提交复核。
- 禁止范围（遵循任务与 AGENTS.md）：继续削减规划容量、提高硬上限（C / A / K）、截断正文、删除或放宽 Validator、伪造成功、修改其它 Agent 的工作区、push GitHub、合并 main、创建 Tag/Release。
- 未修改 SQLite schema、migration、依赖、版本号。

## 二、用户报告与确定性复现

用户报告（`fix/resource-generation-budget`）：

1. 世界观 20000 目标 / 20% 弹性 / 上限 24000：77% 进度失败，已保存 22534。
2. 世界观 21000 / 20%：100% 完成，已保存 23932。
3. 角色卡 20000 / 20% / 上限 24000：62% 进度失败，已保存 20497。

失败错误：`生成正文超过资源或本段预算`（`AppErrorCode.resourceGenerationBudgetExceeded`）。

使用真实 SQLite fixture（`Phase10Fixture`）、真实 `ResourceCreationPipeline` / `BlueprintRepository` / `PartGenerationTaskRepositoryImpl` / `PartGenerationCoordinator` / `PartGenerationPromptBuilder` / `PartGenerationValidator`，仅替换模型网络输出，确定性复现（世界观 T=20000、10 段、每段计划 2000、C=24000）：

- 早段：`target=2000`，`acceptedMaximum=3000`（传输上限）。模型自然扩写至 ~2800 并提交。
- 第 9 段：`target = acceptedMaximum = 1590` → 模型输出 2226 → 校验拒绝。已保存 22400，进度 8/10。
- 第 10 段：`target = acceptedMaximum = 10`（**十个字符**）。
- 与用户场景 1 的形状一致（失败点 ~80%、已保存 ~22400）。角色卡同构。

复现证明：**当资源仍有剩余容量（1466）时，后续 Part 因为 `dispatchableMaximum` 被压到低于自身 `plannedLength` 而失败。**

## 三、根因

`PartGenerationBudgetAllocation.compute` 的 future reserve 以每个“其他未完成必填 Part”的 **最低内容要求** 求和：

```text
F_i = Σ max(0, minimumCharacters_j - savedLength_j)     // 旧
```

对没有确认内容契约的 legacy Part，`minimumCharacters` 是 `BlueprintValidator.minPartEstimatedLength = 10`。因此：

1. **预留实际上是空的**（10 × 段数 ≈ 数十字符）。早段可以把共享上限一直用到传输上限 K=3000（计划 2000 的 150%），吃光全部弹性余量。
2. 尾段 `D_i = min(K, C - S_other - F_i)` 因此可能 **低于该 Part 自己的 plannedLength**，而 `recommendedTarget = min(plannedLength, D_i)` 同时被压到 `D_i`。
3. 于是该 Part 被要求、且被校验为一个 **低于自身计划长度** 的目标/上限；模型按“软目标 + 自然扩写”输出（或拒绝输出 10 字存根）就会超过 `D_i`，`PartGenerationValidator` 抛 `generation_budget`。
4. 重试重新计算同一快照，得到 **同一个被压扁的上限**，永不收敛（`重试不收敛`）。合同提交复核使用同一 `futureReserve`，同样无法放宽。

对应审计文档 `docs/character-generation-budget-root-cause-and-remediation.md` 的 R1（ISSUE-01/04/05）已实现 `D_i = min(K, C - S_other - F_i)`，但独立审查 `docs/codex/character-generation-budget-r1-reservation-independent-review.md` 第 5 节已经记录：legacy 无契约 Part 的 `min=10` 使该预留形同虚设（“U6 未决的已承认边界”）。本任务即修复该残留缺陷。

根因一句话：**后续必填 Part 的预算预留按“最低要求”而非“规划长度”计算，使早段可以吃掉尾段的规划容量，导致尾段的接受上限低于自身计划。**

## 四、修复（统一的动态预算）

按每个“其他未完成必填 Part”的 **尚未写满的规划长度** 预留：

```text
F_i = Σ max(0, plannedLength_j - savedLength_j)          // 新
D_i = min(K, max(0, C - S_other - F_i))                  // 不变
q_i = min(plannedLength_i, D_i)                          // 不变（= plannedLength_i）
```

改动集中在 `lib/domain/resources/generation_budget_allocation.dart`：

- 新增 `PartBudgetRequirement.additionalPlanned`（= `max(0, plannedLength - savedLength)`）。
- `compute` 的 reserve 求和改用 `additionalPlanned`；其余公式、不可行分类、`recommendedTarget`、提交复核与调度闸门均不变。

不变式（对任何满足 `plannedTotal ≤ C` 的计划，且每个早段遵守自身 `dispatchableMaximum`）：

- `dispatchableMaximum ≥ plannedLength_i`：任何必填 Part 都能被写到自己的计划长度，不再被要求或校验为低于计划的上限。
- 累计提交总量 `≤ C`：不会突破弹性上限，也不会侵蚀后续必填 Part 的规划容量。
- 早段仍可使用弹性余量（`D_i` 可到 `min(K, C - S_other - F_i)`），但只能在“不把任何后续必填 Part 压到计划以下”的前提下使用。

统一性：C 已按资源类型由 `GenerationBudgetPolicy.cumulativeCeiling`（T、E、A）给出，世界观（A=60000）、角色卡 / NPC（A=24000）共用同一分配公式，因此修复对三者同时生效。

未改动：`PartGenerationValidator` 的拒绝规则、单段传输上限 K=3000、资源绝对容量 A、弹性百分比范围、SQLite 事务与 CAS、失败分类与重试次数上限、正文内容。

## 五、改动文件

生产代码：

- `lib/domain/resources/generation_budget_allocation.dart`：新增 `additionalPlanned`，reserve 基数改为未完成的规划长度，并更新注释 / 诊断文案（`后续必填规划预留`）。

测试：

- `test/application/resources/part_budget_tail_reservation_regression_test.dart`（新增）：生产链回归，参数化 worldview / character / npc。
- `test/domain/resources/generation_budget_allocation_test.dart`：新增规划预留基数与不变式用例；修正一个 `minimum > planned` 的非法 fixture。
- `test/application/resources/elastic_budget_matrix_test.dart`：J 组用例按新语义调整（见下）。

## 六、验证记录

环境：本机 Linux x64、Flutter（工作区 `~/LT-generation`），`flutter test --no-pub`；SQLite 使用 fixture 临时目录，不接触用户数据库；未调用真实 Provider。

### A. 回归测试先 RED 后 GREEN

`part_budget_tail_reservation_regression_test.dart` 在**未修复**的分配上必须失败、修复后必须通过。已实测：

- 未修复（临时把 reserve 基数换回 `additionalMinimum`）：`worldview` / `character` / `npc` 三个端到端用例全部 FAIL，失败信息为 `run must not die in the tail`（`Expected: true / Actual: <false>`），即用户报告的“中途预算超限失败”。同时新增的分配单元用例失败。
- 修复后：5 项全部 PASS。

回归断言：

- 每个被派发 Part 的 `acceptedMaximum ≥ plannedLength`，`targetBudget ≥ plannedLength`（不再有 1590 / 10 这类被压扁的目标）。
- 每个提交 Part 的正文字数 `≥ plannedLength`；总量 `≤ C`。
- 全部 Part `completed`，无 `failed`。
- 守卫用例：把资源填到距 C 仅 1 个字符时，尾段提交仍被拒绝且不写入正文。

### B. 定向套件

`generation_aggregate_budget_sqlite_test`、`character_generation_budget_reservation_sqlite_test`、`configurable_elastic_budget_sqlite_test`、`elastic_budget_matrix_test`、`part_generation_coordinator_test`、`retry_failed_parts_test`、`resource_generation_task_repository_test`、`r02_part_content_source_cas_test`、`part_budget_tail_reservation_regression_test`、`generation_budget_allocation_test`：

`All tests passed!`（108 项）。

其中 `elastic_budget_matrix_test.dart` 的 J 组是**唯一**受新语义影响的既有用例：旧行为允许前 3 段各提交 3000（计划 2000 的 150%），把尾段压到 600；新语义下第 2 段的上限为 2600（`C - 3000 - 2×2000`），因此该用例的写入值改为每段 2400（在各段 `dispatchableMaximum` 之内、且三段加尾段正好填满 C=9600），保留其全部原有断言：共享池累计、恰好 C 接受、C+1 拒绝、被拒事务不破坏其他正文、冻结 50%/35%/20% 不漂移。没有删除、skip 或放宽任何断言。

### C. 全量

- `dart format`：变更文件已格式化，`--set-exit-if-changed` 通过。
- `flutter analyze --no-pub`：`No issues found!`。
- `flutter test --no-pub --concurrency=2` 全量：**`All tests passed!`，4194 passed / 7 skipped / 0 failed**，耗时 12m38s（日志 `/tmp/lt-gen-full-test.log`，退出码 0）。未新增 skip；7 个 skip 为既有平台 / 真实模型用例。
- `git diff --check`：通过。

## 七、兼容性与剩余风险

- 旧数据：`plannedLength` 来自蓝图的 `estimatedLength`，历史蓝图同样具备；无契约 legacy Part 仍按 `minPartEstimatedLength` 作为最低接受线（分类逻辑未改），只是预留基数变成规划长度。
- 行为变化：早段不再能把共享上限用到让尾段低于计划；这是本修复的目的。**当模型对每一段都持续显著超出弹性（例如始终 1.4× 计划）时，总量本身超过 C，运行仍会失败** —— 这是真实超预算，不是分配缺陷；本修复保证的是“只要总量装得下，就不会因为分配把某段压到计划以下而失败”。
- 并发 > 1：本修复未新增 lease reservation；DI 生产并发为 1。并发 >1 时提交事务仍以同一 `futureReserve` 复核，后到候选可能被拒（与修复前一致，属于既有边界）。
- 未执行真实 Provider / 真机验证；真实模型的遵循率与费用不在本任务结论内。
- `PartGenerationPromptBuilder` 与 `PartGenerationValidator` 本次未修改：修复后 `targetBudget` 不再低于计划、`acceptedMaximum ≥ targetBudget`，二者的契约一致，无需改动即消费统一分配结果。
