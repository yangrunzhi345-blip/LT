# E50 弹性预算 UI→SQLite 端到端验收 独立只读审查

Status: PASSED WITH FINDINGS（审查对象为初稿；MAJOR 已在审查后修复）
Acceptance Mode: Independent Review（另一 Agent 独立只读上下文）
Reviewer: 独立审查 Agent（与实现 Agent 不同执行上下文）
Date: 2026-10-14
Branch: `fix/character-generation-budget-checkpoint-20261013`
Baseline HEAD: `a74120e`
Reviewed artifact: `test/widget/e50_elastic_budget_end_to_end_test.dart`（初稿 10 例，md5
`c142e7bbece7a1ae6ac02578bbd8f815`）

权威来源：`docs/architecture/configurable-generation-elasticity.md`（ADR-0003）、
`docs/character-generation-budget-root-cause-and-remediation.md`（T02/T04/T22、E50）、
`AGENTS.md`。

审查方式：严格只读。审查 Agent 未创建 / 编辑 / 删除任何文件，未 `git add/commit/push/
reset/clean/stash`，未修改测试。

## 1. 执行的命令与真实结果

```bash
flutter test --no-pub test/widget/e50_elastic_budget_end_to_end_test.dart
# +10 All tests passed  (exit 0)

flutter test --no-pub test/widget/resource_studio_test.dart \
  test/widget/settings_workbench_test.dart \
  test/widget/resource_ai_create_studio_navigation_test.dart \
  test/application/resources/configurable_elastic_budget_sqlite_test.dart \
  test/application/resources/elastic_budget_matrix_test.dart
# +98 All tests passed  (exit 0)（无相互干扰）

flutter analyze --no-pub   # No issues found!  (exit 0)
git diff --check           # clean
```

## 2. 已验证不变量（对照五项验收声明）

1. **优先级（PASS）**：三例在真实 `confirmBlueprint` 后读真实冻结列：
   资源 50 > 全局 20 → 50；会话 35 > 资源 50 > 全局 20 → 35；均无覆盖 → 20。
   解析顺序核对 `resource_blueprint_repository.dart:513-541`。
2. **覆盖面（初稿 PARTIAL，见发现）**：蓝图审阅路径真实（`/library` → 创建 → AI 创建 →
   plan → `ResourceBlueprintReviewPage` → “确认并开始生成” → Studio，断言
   `resource_blueprints.elastic_percent==45` 且 `hasLength(1)`）；确认真实（`seedRun` 走真实
   `confirmBlueprint`）。但“直接创建 / 生成 / 重启恢复”初稿未在文件内驱动。
3. **冻结（PASS）**：confirm 后改设置再回读——全局 20→50、资源覆盖 20→50、全局与覆盖同改
   为 0，冻结列 / `budgetAllocation.ceiling` 均不变。
4. **UI T/E/C == 冻结（PASS）**：`expectBudgetRow` 以标签所在 Row 为作用域，避免同值行误配；
   `C = min((T*(100+E))~/100, A)`，A=24000：8000/20→9600、8000/50→12000、8000/35→10800 全部
   PASS。
5. **320px + 大字体（PASS，较弱）**：320×568、textScale 1.0/1.8，独立覆盖渲染，
   `takeException()==null`。

持久化路径真实：设置用例读 `settings` 表；Studio 用例在 UI 点击后读
`resources.metadata_json`；仅审查用例覆盖 `llmGatewayProvider`；生产 Provider 绑定
`DatabaseService.database`（`riverpod_providers.dart:534,578,625`）。

**产品缺陷猎取：E50 链路未发现缺陷。** 两个消费点（`resource_generation_task_repository.dart`
`budgetAllocation:649-653` 与 `commitPartContent:784-814`，经 `_cumulativeCeilingOf`）与 Studio
摘要（`resource_studio_page.dart:1716-1727`）均读同一冻结列；`lib/` 中资源管线没有从实时设置
重算 E 的读路径；没有不落库的 UI 控件。

## 3. 发现

- **MAJOR（覆盖面表述夸大）**：docstring 与分组名声称 `重启恢复` / `直接创建`，但初稿无
  `recoverInterruptedTasks` / 无中断后重开验证，且分组“survives settings change and restart”
  只含设置变更用例；文件内亦无“直接创建” UI 路径。
- **MINOR**：失败重试用例直接调 `budgetAllocation`，未驱动真实失败尝试 + 重试。
- **MINOR**：`_E50Gateway` 的 Part/正文分支为死代码（文件内从不启动生成）。
- **INFO**：声明 #4 的 T（8000）为种子参数、C 为按冻结 E 重算，仅 E 单独回读冻结列；C 边界
  由既有矩阵 / SQLite 测试另行覆盖。
- **INFO**：创建页 C 预览 `resource_ai_create_page.dart:822-837` 只用“独立或全局”，不读目标
  资源覆盖；对新资源创建等价，属既有边界，非缺陷。

## 4. 未验证

全仓测试（非本轮要求）；真实 `recoverInterruptedTasks` 恢复路径的端到端（审查时初稿未含）；
真实生成 / 调度端到端；非 Linux 平台；逐文件计数（compact 输出为 5 文件合计 98）。

## 5. 裁决

- Status: **PASSED WITH FINDINGS**
- Acceptance Mode: **Independent Review**
- 产品缺陷：**0**；发现：MAJOR=1（覆盖面表述）、MINOR=2、INFO=2

## 6. 审查后修复（Remediation）

针对 MAJOR 与两项 MINOR，执行方在同一工作单元内补齐真实覆盖（测试文件由 10 例增至 12 例）：

- 新增**直接创建**用例：`ai-create-submit-button` 直提 → Studio，断言冻结全局 20%，并真实
  启动生成（假网关走 Part 协议分支，消除死代码 MINOR）。
- 新增**重启恢复**用例：真实 `startAttempt` 置任务为 `generating`，`recoverInterruptedTasks`
  恢复为 ready，断言冻结列 50 与 `budgetAllocation.ceiling` 12000 不变。
- 把**失败重试**改为真实 `retrySinglePart`：三兄弟已完成 9000、全局与资源覆盖漂移到 0 后，
  真实提交 3000 → 总量 12000 = 冻结 C（消除 MINOR）。
- 分组“survives settings change and restart”更名为“survives settings change”（重启已由新
  用例独立覆盖）。
- 复核：E50 定向 **12 PASS**（`/tmp/lt-e50e.log`）；弹性相关组合 **110 PASS**
  （`/tmp/lt-e50-reg2.log`）；全 widget **1246 PASS**（`/tmp/lt-e50-widget-reg.log`）；
  资源子系统 **852 PASS**（`/tmp/lt-e50-res-reg.log`）；analyze 零问题；format / diff-check
  PASS。产品代码未改动。
