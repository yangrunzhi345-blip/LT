# Blueprint 动态 Token 预算根因修复与验收

Status: 实施完成，自动化验证通过；真实 Linux/DeepSeek API 与 Android 实机均 NOT VERIFIED。
Acceptance Mode: Integrated Single-Agent Full-Cycle（用户一次性授权连续完成实施、验证与验收）。
本文档为唯一事实记录：算法、改动、测试矩阵与剩余风险。

## 一、基线

- 分支 `main`，起始 HEAD `28ae718868cca1fdf554d2b5c2a155ae6d4091aa`（tag `v1.2.09`，与 `origin/main` 同 SHA）。
- 起始工作区干净（`git status --short` 空），无未提交 WIP（含 `pubspec.lock`）。
- SQLite schemaVersion = 49；本次不修改 schema、migration、事务与持久化语义。
- 本次未 commit、未 push、未创建 Tag/Release/APK。

## 二、已确认根因（生产调用链可确定性重放）

生产链：
`ResourceAiCreationOrchestrator` → `ResourceCreationPipeline.planAiSession` → `BlueprintPlanner.plan/replan`
→ `AiGeneratorLlmGateway.rawCompletion` → `LlmTaskResolver.resolve` → `LLMService` SSE。

固定 4096 有两处叠加，任一处都使输出被钉死：

1. `LlmGateway.rawCompletion({ int maximumOutputTokens = 4096 })`
   （`lib/application/llm/llm_gateway.dart:111`）。
2. `BlueprintPlanner._createGatewayCompleter` 调用 `gateway.rawCompletion(...)` 时**不传** `maximumOutputTokens`，
   于是走默认 4096。
3. `LlmTaskResolver.resolve` 的 `maxTokens: maximumOutputTokens ?? policy.maxTokens ?? userParams.maxTokens`
   会被该 4096 直接覆盖；`LlmTaskPolicyTable` 中 `resourceBlueprintPlanning.maxTokens` 同样是 4096。

因此无论目标字数多大，规划请求恒为 `max_tokens: 4096`。当完整 Blueprint JSON 超过该预算时，
DeepSeek 以 `finish_reason=length` 结束，`LLMService.sendMessageStream` 的完整性门禁抛
`LLMResponseIncompleteException`，规划失败——与 Linux Debug 日志
（`max_tokens: 4096`、`completionTokens: 4095`、`finishReason: length`、`responseCompleted: true`）完全一致。

**HTTP 200 / DONE / responseCompleted=true 均不能证明 JSON 完整**：截断检测由
`finishReason.isTruncated` 独立判定，本次未放宽该门禁。

## 三、模型能力核定（真实来源）

DeepSeek 官方文档（已核对）：

- Chat Completions `max_tokens`：`取值范围为 1 到 384K（393216）`；
  https://api-docs.deepseek.com/zh-cn/api/create-chat-completion/
- 模型 & 价格：`deepseek-flash` 上下文长度 1M，输出长度最大 384K；
  https://api-docs.deepseek.com/zh-cn/quick_start/pricing

结论：`ModelCapabilityRegistry.deepSeekFlash.maximumOutputTokens` 原为十进制的 `384000`，属过时/口径错误；
已修正为 `393216`（384 × 1024）。`contextWindow` 保持 `1000000`（1M）不变。
`deepseek-v4-pro` 为已下线/隐藏模型，其数值标注为保守占位，本次不动。
未知模型/自定义端点仍解析到保守回退（`maximumOutputTokens: 1024`, `contextWindow: 8192`），
**不继承 DeepSeek 上限**。

## 四、动态预算算法

新增纯函数组件 `lib/application/resources/blueprint_token_budget.dart`。

输入：资源类型、目标字数、参考资料字符数、预计输入 Token、模型最大输出 Token、模型上下文窗口，
可选显式 Section/Part 数（默认由目标推导）。

步骤：

1. 结构估计：`estimatedParts = clamp(ceil(target × complexity / 2000), 1, 36)`，
   `estimatedSections = clamp(ceil(parts / 3), 1, 12)`；结构上限复用
   `BlueprintIdPool.defaultMaxSections/defaultMaxParts`（12/36），不另立常量。
   `complexity = 1 + 0.25 × min(refChars, 8000) / 8000`，为参考资料复杂度提供有界加成。
2. 字符估计：`protocolBase(400) + 400 × sections + 600 × parts`。逐元素预算取自校验器接受上限
   （Section 标题 100 + 概述 500、Part 标题 100 + 目标 500，加 key/id/数字/标点），
   使估算成为“校验器会接受的输出”的上界。
3. 字符→Token：用 `ResourceLimits.capacityTokenWeightPerCharacter`（CJK 0.7，`TokenEstimator` 最重权重），
   **不把中文字符数等同 1 Token**。
4. 安全余量：`reserve = max(512, ceil(estimated × 0.35))`。
5. 钳制：`allowed = min(estimated + reserve, modelMaximumOutput, contextWindow − estimatedInputTokens)`。

结构边界：

```text
estimatedOutput = estimateBlueprintTokens(...)
requestedOutput = estimatedOutput + safetyReserve
allowedOutput   = min(requestedOutput, modelMaximumOutput, remainingContextCapacity)
```

实测（`deepseek-flash`，`contextWindow=1,000,000`，日志取证）：

| 目标字数 | Section | Part | estimated | reserve | requested=allowed |
|---:|---:|---:|---:|---:|---:|
| 8,000 | 2 | 4 | 2,520 | 882 | 3,402 |
| 10,000 | 2 | 5 | 2,940 | 1,029 | 3,969 |
| 20,000 | 4 | 10 | 5,600 | 1,960 | 7,560 |
| 25,000 | 5 | 13 | 7,140 | 2,499 | 9,639 |
| 35,000 | 6 | 18 | 9,520 | 3,332 | 12,852 |
| 50,000 | 9 | 25 | 13,300 | 4,655 | 17,955 |

50,000 字世界观经真实规划链的 `[gen-diag] PLAN[…] BUDGET` 取证为
`estimatedParts: 26, estimatedOutputTokens: 13720, requestedOutputTokens: 18522,
allowedOutputTokens: 18522, modelMaximumOutputTokens: 393216`，最终 wire 上 `max_tokens: 18522`。

- 4096 不再是隐式上限（20K 以上目标均显著超过 4096）。
- 16384 不是新的隐式硬上限（50,000 → 18,522 > 16384；若结构更大可继续上升，上限仅为模型/上下文）。
- 不无依据申请 393216：仅当估算需要时才可能接近该值，实际远低于上限。
- 未知模型不兼容时（模型上限过小或上下文不足）抛 `BlueprintBudgetInfeasibleException`，
  明确报告“约束不可行”，不发请求、不保存任何不完整 Blueprint。

## 五、参数传递打通

- `BlueprintPlanner` 现在持有 `LlmGateway`（生产路径）或注入的 `completer`（测试路径）。
  生产路径每类请求都显式传 `maximumOutputTokens: budget.allowedOutputTokens` 给
  `LlmGateway.rawCompletion`；`LlmTaskResolver` 收到的 `maximumOutputTokens` 不再被覆盖。
- 初始规划与重新规划都走同一条预算计算与传参路径。
- 新增 `ModelCapabilityAwareGateway` 可选接口（`llm_gateway.dart`），
  `AiGeneratorLlmGateway` 实现之，返回 `LLMService.capabilities`（新增公开 getter）。
- 注入 `completer` 的测试接缝不计算预算（接缝自行决定输出规模），
  因此既有单元测试语义不变；预算只作用于真实网关路径。
- 未改动 `rawCompletion` 的默认值 4096，因此 Part 正文、压缩、Adventure 规划等任务的输出限制保持不变。

## 六、动态超时与错误恢复

- 超时：`recommendedTimeoutForTokens = clamp(30s + tokens / 60tok·s⁻¹, 60s, 8min)`；
  小计划保持历史 60 s 下界，大预算按比例放宽，且有明确 8 min 硬上界，绝不无限等待。
  `planAiSession`/`plan`/`replan` 的 `timeout` 改为可选，生产不传则由预算推导。
- 超时仍然调用 `handle.cancel()` **真正取消在途请求**（既有能力保留），不是只放弃 Future；
  被取消的请求不写入资源、不持有调度许可。
- 截断重试：仅当失败为 `LLMResponseIncompleteException` 且 `finishReason.isTruncated` 时，
  允许**至多一次**完整重新规划。新预算
  `next = min(modelMax, remainingContext, max(2×current, 2×observedCompletion))`，
  且必须严格大于上一次才重试；上下文受限或已达模型上限时不重试，直接失败。
  重试次数上限 = 2 次请求；单次超时上界 8 min，整体上界 16 min。

## 七、改动文件

生产代码：

- `lib/models/model_capabilities.dart`：`deepseek-flash` 最大输出 384000 → 393216（附官方依据注释）。
- `lib/services/llm_service.dart`：新增 `ModelCapabilities get capabilities`。
- `lib/application/llm/llm_gateway.dart`：新增 `ModelCapabilityAwareGateway` 接口。
- `lib/application/llm/ai_generator_llm_gateway.dart`：实现 `activeModelCapabilities`。
- `lib/domain/resources/resource_blueprint.dart`：`BlueprintIdPool` 暴露 `defaultMaxSections/defaultMaxParts`。
- `lib/application/resources/blueprint_token_budget.dart`（新增）：预算策略与结果模型、不可行异常、重试增长、超时推导。
- `lib/application/resources/blueprint_planner.dart`：接入动态预算、动态超时、有界截断重试；新增诊断标记。
- `lib/application/resources/resource_creation_pipeline.dart`：`planAiSession` 超时参数改为可选。
- `lib/application/resources/resource_generation_error.dart`：`BlueprintBudgetInfeasibleException`
  映射到既有稳定错误码 `AppErrorCode.resourceGenerationBudgetInfeasible`（用户可见的“预算不足”语义）。
- `lib/services/llm_task_policy.dart`：为 `resourceBlueprintPlanning.maxTokens = 4096` 补充说明——
  它只是“未显式传预算时的兜底”，规划器始终以动态预算覆盖它（注释级改动，无行为变化）。

测试：

- `test/application/resources/blueprint_token_budget_test.dart`（新增，19 项）。
- `test/application/resources/blueprint_planner_test.dart`（更新 wire 断言；新增 6 项生产参数/失败路径测试）。
- `test/application/resources/resource_generation_error_test.dart`：新增预算不可行映射断言。
- `test/unit/model_capability_registry_test.dart`：断言更新为 393216。

未改动：Blueprint JSON 解析/完整性校验、SSE stop/length/DONE 语义、U6 内容契约、
R1/R2/R5 与 20% 弹性预算、Part 正文 3000 字约束、SQLite Schema/事务、冒险资源就绪与压缩、
用户思考模式配置。

## 八、测试矩阵

### A. 动态预算单元测试（`blueprint_token_budget_test.dart`）

- 8K/10K/20K/25K/35K/50K：均为正值、可行、随目标严格单调递增、`boundReason=estimate-bound`。
- 4096 非隐含上限（20K+ 均 > 4096）；16384 非新硬上限（50K → 18,522 > 16384）。
- 不同目标得到不同预算（非单一固定常量）。
- 参考资料复杂度提升估算；结构估计不超过 12/36 上限；极端目标不溢出。
- 模型上限约束（≤ 已验证能力）、上下文约束（≤ 剩余上下文）、上下文耗尽不可行、
  未知模型（上限 0）不可行、保守模型可规划小目标。
- 零/负目标、负输入钳制、显式结构覆盖。
- 截断重试增长：可增长且不超模型上限；上下文受限不重试；已达模型上限不重试。
- 超时推导：小预算保持 60 s 下界，大预算按比例增长且不超 8 min 上界。

### B. 生产参数测试（真实 `LlmService` HTTP 路径 + `MockClient` 拦截）

- 请求体 `max_tokens` 为动态值（0 < v ≤ 393216），随目标单调递增，50K > 16384，非 4096。
- 初始规划与重新规划均发送动态预算（均 > 16384）。
- 请求形状：`thinking={type: disabled}`、`response_format={type: json_object}`、`temperature=0.7`、
  非思考模式不含 `top_p`、`stream=true`。
- 10K/25K/50K 的创建→真实网关→真实 LLMService→校验→真实 SQLite 确认事务→关闭/重开数据库复验（既有矩阵保留）。

### C. 失败路径测试

- `stop` + 完整 JSON：接受。
- `length` + 语法完整 JSON：拒绝（不当作完整），触发一次有界重试；
  重试成功则保存，持续截断则抛 `LLMResponseIncompleteException`，请求数恰为 2，且零资源/零 Part 落库。
- 重新规划失败：旧 revision 保持不变（历史仍为 1 条，名称/状态不变）。
- 连接中断（无终止证据）、空响应、reasoning-only、非法 JSON、部分 JSON：均拒绝且不保存。
- 预算不可行：发请求前抛 `BlueprintBudgetInfeasibleException`，零 HTTP 请求，无 Blueprint 落库，会话仍 `awaitsPlanning`。
- 超时：取消在途请求（既有测试保留）。
- 取消：立即中断（既有测试保留）。

### D. 整体回归

见「十、验证记录」。

## 九、约束不可行的产品语义

当目标无法在模型真实能力内完成时，规划在**发请求前**失败并携带可读原因
（需要多少输出 Token、模型上限、剩余上下文、受限原因），
不静默产出截断蓝图，也不盲目重试。这是对“宁缺勿假”的落实。

## 十、验证记录

环境：Linux x64 host、Flutter 3.47.2 / Dart 3.13.2、Flutter 测试 VM、DeepSeek `deepseek-flash` 请求形状、
受控 `MockClient`（`example.invalid`），API Key 为 fixture，**未调用真实 Provider**；
SQLite 全部位于独立临时目录，无用户数据写入。

| 记录 | 命令 | 真实结果 |
|---|---|---|
| FORMAT | `dart format --output=none --set-exit-if-changed lib test` | 888 files、0 changed、exit 0 |
| ANALYZE | `flutter analyze --no-pub` | `No issues found!` |
| BUDGET-UNIT | `flutter test --no-pub test/application/resources/blueprint_token_budget_test.dart` | 20 PASS / 0 FAIL |
| PLANNER | `flutter test --no-pub test/application/resources/blueprint_planner_test.dart` | 37 PASS / 0 FAIL |
| ERROR-MAP | `flutter test --no-pub test/application/resources/resource_generation_error_test.dart` | PASS（含新增预算不可行映射用例） |
| CAP-REGISTRY | `flutter test --no-pub test/unit/model_capability_registry_test.dart` | PASS（393216） |
| TARGETED | `test/application/resources/` + `test/services/llm_streaming_reliability_test.dart` + `test/unit/` | 2182 PASS / 1 skipped / 0 FAIL |
| WIDGET | 资源库 / E50 弹性预算 / 创建导航 / 创建栈 widget 测试 | 47 PASS / 0 FAIL |
| INTEGRATION | `test/integration/resource_generation_soak_test.dart` + 角色真实 DeepSeek 验收（fixture） | 7 PASS / 5 skipped / 0 FAIL |
| FULL-REGRESSION | `flutter test --no-pub --concurrency=2`（全量 `test/`） | **+4176 passed / ~7 skipped / 0 failures，`All tests passed!`**，日志 `/tmp/lt-blueprint-full-regression.log` |
| DIFF-CHECK | `git diff --check` | 通过 |

**方法学警示**：本次后台命令用 fish `$?` 取退出码，fish 中应为 `$status`，导致 shell 末条命令报错、
任务被标记为 exit 121；该退出码来自 shell，而非 `flutter test`。判据以日志中的
`All tests passed!` 最终标记为准——日志中不存在 `Some tests failed` 或任何失败用例标记，
4176 passed / 7 skipped / 0 failed。

真实 API 与实机：**均未执行**，标记 NOT VERIFIED：

- LINUX REAL API（50,000 字世界观完整生成 + 规划保存 + Part 正文 + 重开 + 重启）：NOT VERIFIED。
- ANDROID ARM64 RELEASE（10k/25k/50k 实机）：NOT VERIFIED（无正式签名材料、无 adb 设备）。

## 十一、剩余风险

- 未执行真实 DeepSeek 调用；`max_tokens` 已在 wire 层取证，但真实响应长度/费用/端到端世界观保存未验证。
- 未在 Android 实机复测 v1.2.05→v1.2.09 的历史失败样本；本文档只证明“固定 4096 导致截断”这一确定根因，
  不据此断言历史全部 Android 失败同因（SSE、正文预算门禁仍需独立证据）。
- 思考模式下 reasoning token 计入同一 `max_tokens`；`resourceBlueprintPlanning` 经 `rawCompletion`
  实际恒为非思考，故当前无额外 reasoning 预留；若未来改为跟随用户思考开关，需要重新评估推理预留。
- 未知/自定义模型现在受保守上限（1024 输出 / 8192 上下文）约束，超目标时明确失败而非截断；
  这是刻意的安全取舍，可能与期望“自定义大模型也能生成大资源”的用户预期不同。
- 有界重试的最坏整体耗时上界为 2 × 8 min。

## 十二、下一步

1. 用户授权后用 Linux Debug 对 50,000 字世界观做一次真实 API 端到端（预计 1 次规划请求，约 18.5K 输出上限）
   并核对保存、重开与重启。
2. 取得正式签名材料后构建 ARM64 Release，用 `LT_SAFE_LLM_DIAGNOSTICS` 通道逐案 10k/25k/50k 复测。
3. 真实数据落地后再决定是否需要下调安全余量或调整结构估计权重。
