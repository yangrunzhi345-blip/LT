# R4 历史回归 fixture 适配独立复审

Status: PASSED（仅本次两处测试适配）
Acceptance Mode: Independent Review
Baseline: `09a49ea`，main；审核当前未提交 diff。
Date: 2026-10-13

## Summary

未发现 BLOCKER、MAJOR 或 MINOR。本次把聚合容量 / 编排幂等测试中的非法单段规划改为 R4 约束下的合法 fixture，没有删除测试、skip、放宽业务断言、绕过真实 SQLite 或调整生产上限来取得 PASS。没有修改生产行为。

## 范围及证据

只审核 `test/application/resources/phase4_independent_acceptance_test.dart` 与 `test/application/resources/resource_ai_creation_orchestrator_test.dart`，依据正式预算修复方案 ISSUE-08 / R4、T12、第 13 节测试真实性要求，以及已通过的 R4 独立审查。并行 R6 改动不在本复审范围。

- **聚合容量目的保留。** `budgetJson` 把总量分布到各段 ≤3000 的合法 Part；I-4 仍断言 50000 总规划精确等于 worldview nominal，50001 提案归一化后同样精确等于 50000，新增每段 ≤K 断言。未以提高 K、减少总体目标或仅断言“不抛错”替代原容量测试。
- **旧错误 fixture 变为明确负向证据。** 原单 Part 50000 提案仍保留在 I-4，断言 BlueprintValidationException，且 findLatestBlueprint 为空。删除的是“单段 50000 可接受”的过期断言，而不是对应风险覆盖；新的正向 fixture 和负向断言符合 R4 预期。
- **模型不能提高目标的不变量保留。** I-6 仍输入 model targetCapacity=999999，客户端 character nominal 为确认的目标；原目标优先级和聚合上界断言未改变。提案总量仍为 9000，只改为三段各 3000，避免提前命中单段上限而无法验证目标权威。
- **幂等目的保留。** `_PlanningGateway` 默认 estimatedLength 从 5000 改为 3000，满足单段硬上限；调用方目标 5000 保持原值。稳定 creation/resource/generation/candidate 身份、单条 sessions/blueprints/resources/tasks、生成未终止与最终 completed 等原断言均没有变动。其他 twoParts 及显式 estimatedLength 调用也未被弱化。
- **真实持久化路径保持。** 两组仍使用临时 SQLite、真实 pipeline、planner、repository 和 orchestrator；仅网络输出可控。没有改 fake repository 或去掉事务、候选原子采纳、历史和用户正文保护断言。

## 独立实际验证

```bash
flutter test --no-pub --reporter expanded \
  test/application/resources/phase4_independent_acceptance_test.dart \
  test/application/resources/resource_ai_creation_orchestrator_test.dart
```

18 PASS，退出码 0，日志 `/tmp/lt-budget-r4-regression-independent-tests.log`。

- `flutter analyze --no-pub`：No issues found，2.2s，退出码 0；日志 `/tmp/lt-budget-r4-regression-independent-analyze.log`。
- 两个变更文件 `dart format --output=none --set-exit-if-changed`：2 files，0 changed。
- `git diff --check`：PASS。核对全部两处 diff，没有新增 skip、放宽 matcher 或删除测试用例。

未解决发现：BLOCKER=0、MAJOR=0、MINOR=0。

没有重启或操作执行方正在运行的扩大回归 session；本次独立两组测试不替代该扩大回归、全量回归或最终跨阶段验收。U6 仍待产品决定，整体任务不因本报告标记 ACCEPTED。

本审核 Agent 仅新增本报告，没有修改代码、测试、配置，没有 commit / push / 发布。
