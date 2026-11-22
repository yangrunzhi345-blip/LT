# R4 规划 Part 预算守卫独立审查

Status: PASSED（仅 R4 基础规划守卫范围）
Acceptance Mode: Independent Review
Baseline: `2144a40`，main；审核当前未提交 diff。
Date: 2026-10-13

## Summary

未发现本审查范围内的 BLOCKER、MAJOR 或 MINOR。单 Part 规划上界在总量低于、等于目标的分支也执行；超过目标的提案只有在归一化后满足单段上界和显式最低量时才能通过后续验证。不改正文、ID、DAG、资源容量、冻结弹性预算或数据库结构。

本裁决不是完整 Phase 3 或整体修复 ACCEPTED。方案 U6 产品阈值尚待答复，运行时 reserve、有效正文完成闭环、重试保护及 UI 等后续工作不在本次审查范围；整体已确认 MAJOR 不据此解除。

## Authority 与审查范围

- 读取 `AGENTS.md`、`README.md`、code-audit 技能及检查清单。
- 读取正式方案 ISSUE-08 / R4、第 6.1–6.2、10、13、14.2 节及 ADR-0003 `docs/architecture/configurable-generation-elasticity.md`。
- 核对 `character-generation-budget-remediation-progress.md`：前两项 milestone 已提交，完整阶段门禁及产品决策仍未完成。
- 审查两个生产文件：`blueprint_validator.dart`、`blueprint_budget_normalizer.dart`；两项已跟踪测试 diff 与新增 `blueprint_part_budget_sqlite_test.dart`。
- 沿 Planner plan / replan、BlueprintRepository save / read / confirm、parser、content requirements 与 SQLite fixture 核对生产调用链。
- 审查期间出现的 `generation_diagnostics.dart` 与 `test/core/` 并行变更属于其他范围，未对其作独立验收。

## 不变量与证据

1. **新确认规划单段满足 `m ≤ p ≤ 3000`。** `BlueprintValidator.minimumPartBudget` 校验显式契约并读取其 minimum；legacy 保持 10。`validatePartBudget` 使用统一 `ResourceLimits.maxPartCharacters`。Normalizer 的 `total ≤ target` 分支逐段校验；超过目标的分支按各段 minima 分配，并保持 3000 硬上限。
2. **不得擅定产品默认。** 本次未在 Planner、模型请求、正文 commit 中引入默认 profile；测试显式提供 narrative minimum=180，仅验证机制。显式 scalar minimum=1 不被 legacy 10 覆盖。该 fixture 不代表批准最终产品阈值。
3. **全部生产确认路径守卫成立。** plan / replan 均先 normalize、再完整 validate、后 save；confirm 在真实 tree transaction 中、正式写入前再次完整 validate。非法初次规划不保存，非法 replan 不 supersede 旧 draft，非法 direct confirm 不创建资源或 tasks。
4. **历史与冻结预算不变。** find / list 读取没有新增预算校验；confirmed 幂等返回位于新增校验之前，不强制历史 confirmed 蓝图重新过新守卫。未改 schema / migration、正文、hash、Revision、E 冻结列或预算公式。既有 1/2 字 legacy completed 读取与逐表不变回归实际通过。
5. **真实持久化验证。** 新 SQLite fixture 使用 DatabaseService v49 与真实创建管线、BlueprintRepository、tree / revision repositories，只替换模型网络输出及凭证存在性检查。覆盖 character / worldview 的 plan、replan、direct confirm 失败，逐表比较 resources、sections、parts、sessions、blueprints、tasks、attempts、revisions 不变；合法归一化确认核对稳定 ID 映射和依赖 DAG。
6. **没有降低旧容量测试。** aggregate-over-limit fixture 改成每段合法 ≤3000，仍保留原 `BlueprintBudgetExceededException` 与 plannedLength 大于预算的断言，使测试继续命中聚合容量守卫。

## 实际验证

以下由独立审核 Agent 执行，不采信实现方计数代替结果：

```bash
flutter test --no-pub --reporter expanded \
  test/application/resources/blueprint_budget_normalizer_test.dart \
  test/application/resources/blueprint_validator_test.dart \
  test/application/resources/blueprint_planner_test.dart \
  test/application/resources/blueprint_part_budget_sqlite_test.dart \
  test/application/resources/content_requirements_sqlite_test.dart \
  test/application/resources/resource_blueprint_repository_test.dart
```

结果：63 PASS，退出码 0。日志：`/tmp/lt-budget-r4-independent-tests.log`。

- `dart /dev/stdin` 直接 import 当前生产函数，10 项无源码修改的边界探针 PASS：3000 允许；3001 在总量等于 / 低于目标时拒绝；legacy 10 允许 / 9 拒绝；显式 scalar 1 允许；narrative minimum=180 时 179 拒绝 / 180 允许；500 归一化至 180 允许 / 179 拒绝。未生成测试源文件，未执行 mutation。
- `flutter analyze --no-pub`：No issues found，2.0s，退出码 0。日志：`/tmp/lt-budget-r4-independent-analyze.log`。
- `dart format --output=none --set-exit-if-changed` 对五个本次变更 Dart 文件：5 files，0 changed，退出码 0。
- `git diff --check`：PASS。
- 开始、结束均核对 Git 状态及 diff；本 Agent 仅写本报告，没有修改代码、测试、配置，没有 commit / push / 发布。

## Findings 与边界

本有限范围未解决发现：BLOCKER=0、MAJOR=0、MINOR=0。

未运行全量回归、真实模型/设备验证及运行时 reserve / retry / UI 测试；这些不能用本次 63 项定向测试替代。全量回归与最终跨阶段独立验收仍按正式方案执行。没有读取用户数据库，没有付费 API 调用。
