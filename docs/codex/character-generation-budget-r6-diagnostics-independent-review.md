# R6 心跳生命周期独立审查

Status: PASSED（仅 R6 局部诊断范围）
Acceptance Mode: Independent Review
Baseline: `09a49ea`，main；审查当前未提交 diff。
Date: 2026-10-13

## Summary

未发现当前范围内未解决的 BLOCKER、MAJOR 或 MINOR。UI 心跳停止后重新创建 timer 时重设观测基线，新增 owner 不修改现有 timer 的 interval 或阈值。活跃观测期间真实延迟，包括首 tick 延迟，仍产生 GAP；GAP 只描述观测到的 timer 延迟，不无条件断言 CPU 阻塞。

这是 R6 的局部独立审查，不是完整 Phase 6 或整体任务 ACCEPTED。U6 产品决策、正文有效性、预算预留、重试/UI 和跨模块最终门禁仍需后续完成。

## Authority 与范围

- 按 `AGENTS.md` 和 code-audit 技能执行独立只读审查。
- 依据正式方案 ISSUE-09、第 6.6 / 10 / 13 / 14.2 节及 T29 / T30。
- 唯一生产变更：`lib/core/debug/generation_diagnostics.dart`；新增测试：`test/core/debug/generation_diagnostics_test.dart`。
- 核对 Studio 页面 init/dispose、StreamingResourceGenerationService run 生命周期、coordinator SSE 消费与 scheduler stall dump。
- 未将真实 26 秒 GAP 归因于 CPU、DB、Prompt 或预算；没有扩大性能优化范围，没有修改业务数据、timeout、网络节流或 SQLite。

## 不变量与生产链复核

1. **owner 0→1 创建 timer 重设基线。** `startUiHeartbeat` 在首次真实 timer 创建时设 `_lastUiHeartbeat = _now`。150ms 无 owner 停止段不再进入重启后的活跃间隔。
2. **owner >0 保持已有观测。** owner 计数增加后立即返回，既有 timer、interval、基线与阈值均不重置。`stopUiHeartbeat` 仅在最后 owner 释放时取消 timer；额外 stop 不产生负数。
3. **活跃真实延迟保持可见。** 移除 ticks>0 的附加条件，首 tick 与后续 tick 都按当前 interval×4 判断延迟。理由文字要求检查生命周期与 isolate 活动，不把 timer gap 当作确定的阻塞原因。
4. **可观测状态清楚。** dump 同时展示 owners 和 active / unobserved。active 表示 timer 已建立，不宣称 App 未进入后台；后台状态仍须现场证据判断。
5. **测试 seam 不替换被测 timer。** 默认单例继续使用真实 Stopwatch。`forTesting` 仅注入 elapsed clock；测试运行相同 `Timer.periodic`，由 WidgetTester fake timer 确定性驱动。测试 body 的 finally 先清理 timer，外层 tearDown 恢复 printingEnabled，避免测试间泄漏。
6. **reset 清理 timer 与心跳状态。** 取消 UI / watchdog timer，并清零 owners、ticks、两类 heartbeat 时间 / 序号 / stage 与记录状态。没有新依赖或生产调用 reset 的路径。
7. **生产接线未丢失。** ResourceStudioPage.initState / dispose 成对 start / stop UI heartbeat。生成服务启动 watchdog 和 run，在 whenComplete 中 endRun；最后 run 结束取消 watchdog。coordinator 的每个 SSE chunk 调用 `runtimeHeartbeat('part.sseChunk')`。PART_TRANSITION_STALL 保留在途任务、最近 transition 与 heartbeat dump；此诊断不直接判定 deadlock，业务 DAG deadlock 判定路径未改。
8. **只读诊断边界。** debug/profile gate 保持，release 仍 no-op。变更没有涉及资源写入、CAS、Attempt、Revision、schema 或 E 快照；dump 仍只是有界记录和打印。

## 审查发现与处置

审查初始发现一个文档 MINOR：同一组件 `startWatchdog` DartDoc 仍以 “isolate was blocked and recovered” 解释 GAP。向执行 Agent 提交后，执行 Agent 将其改为 observed timer delay，明确原因需要单独证据。独立复读最终 diff，旧结论已经移除。审核 Agent 未修改源码。

未解决发现：BLOCKER=0、MAJOR=0、MINOR=0。

## 独立实际验证

```bash
flutter test --no-pub --reporter expanded \
  test/core/debug/generation_diagnostics_test.dart \
  test/application/resources/part_generation_coordinator_test.dart \
  test/application/resources/streaming_resource_generation_service_test.dart \
  test/application/resources/p0_malformed_ndjson_spin_test.dart
```

58 PASS，退出码 0。日志：`/tmp/lt-budget-r6-independent-tests.log`。六项 diagnostics 测试覆盖停止 / 重启、多 owner、活跃延迟、首 tick 延迟、reset 清理，以及停止后 dump 状态；连续 30 秒 runtime SSE heartbeat 更新不触发 runtime stall。

- `flutter test --no-pub --reporter expanded test/services/llm_streaming_reliability_test.dart`：47 PASS，退出码 0。日志 `/tmp/lt-budget-r6-independent-shared-llm.log`。包含既有调用 reset 的共享 LLM 回归，避免仅验证新独立实例。
- `flutter analyze --no-pub`：No issues found，6.7s，退出码 0。日志 `/tmp/lt-budget-r6-independent-analyze.log`。
- 两个变更 Dart 文件 `dart format --output=none --set-exit-if-changed`：2 files，0 changed；最终 `git diff --check` PASS。
- 复读执行方负向日志 `/tmp/lt-budget-r6-before.log`（3 FAIL / 1 PASS，初期含 timer cleanup fixture 问题），不把该初次输出全部当作纯业务失败。复读 `/tmp/lt-budget-r6-mutation-restart.log` 与 `...-owner.log`，各 3 PASS / 1 FAIL，分别对应重启基线与多 owner 语义断言。该 mutation 由执行方运行，审核方没有修改源码重演；独立验收依据是当前 diff 和上述实际运行的通过测试。

## 未覆盖范围

没有运行真实设备的后台/前台生命周期、真实 CPU profiling、付费模型或全量回归；fake clock/timer 证明的是诊断逻辑，不证明现场 GAP 原因或模型成功率。完整 Phase 6 的装配、关联、压缩与跨阶段回归不可用本次结果替代。

本审核 Agent 仅新增本报告，没有修改代码、测试、配置，没有 commit、push 或发布。
