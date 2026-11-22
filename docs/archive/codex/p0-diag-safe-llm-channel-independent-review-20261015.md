# P0-DIAG Release 安全 LLM 诊断通道：独立安全审查

Status: CHANGES REQUESTED → 已按最小范围修复并补回归（见文末 Remediation 状态）。
Acceptance Mode: Independent Review（独立 Agent 只读审查，未修改源码、未运行测试或构建）。
审查对象：commit `ac040e3` vs 基线 `a3458d9`（v1.2.08），分支 `fix/android-worldview-generation-20261015`。
审查结束状态核对：`git status --short` 仅剩用户 ` M pubspec.lock` WIP，审查本身零改动。

## Findings

| ID | Severity | 位置 | 发现 | 处置 |
|---|---|---|---|---|
| F1 | MAJOR | `.github/workflows/quality-gate.yml` + `test/core/debug/safe_llm_diagnostics_test.dart` | CI 全量回归从不传 `--dart-define=LT_SAFE_LLM_DIAGNOSTICS=true`，所有 enabled-path 断言被 `if (!safeLlmEnabled) { return; }` 跳过，泄漏断言在空输出上**空真**。安全控制无自动回归保护 | **已修复** |
| F2 | MINOR | `lib/services/llm_service.dart` `_LLMAttemptTrace.mark` | `markSafeLlm` 先于 legacy `mark` 且无异常隔离；未来新增未防护值类型可能把诊断 bug 变成生成路径失败（抑制 legacy 记录或传入 SSE 监听） | **已修复** |
| F3 | INFO | `generation_diagnostics.dart` `model` 正则 | 允许 `:` 与 `/`，URL 形状（无 query/userinfo）可通过；非 ASCII model/host 被静默丢弃 | 记录接受 |
| F4 | INFO | `llm_service.dart` SSE 解析 | 裸 `data:` 行（合法 SSE 空值字段）现被计为 malformed；旧代码静默跳过 | 已文档化为有意策略 |
| F5 | INFO | `generation_diagnostics.dart` counts | allowlisted int 无上限（仅 `>= 0`）；`httpStatus` 有界 100–599 | 记录接受 |

无 BLOCKER。实现本身在 8 项审查中 7 项判定 SAFE。

## 逐项裁定

**1. 默认关闭与 Release 门禁 — SAFE。** `safeLlmEnabled = bool.fromEnvironment('LT_SAFE_LLM_DIAGNOSTICS')` 为 `static const`，缺省为 false；仅字符串 `'true'` 为真。守卫 `if (!safeLlmEnabled || attemptSequence <= 0) return;` 位于所有逻辑之前，唯一输出 `debugPrint('[lt-safe-llm] …')` 在未 opt-in 时不可达。全仓检索确认该标识只存在于实现、测试与文档；无环境变量、配置文件、设置开关或 Gradle/CI 路径可启用它。注意 `debugPrint` 在 release 不会被裁剪，编译期 const 门禁是唯一保护，且其本身成立。

**2. Allowlist 严格性 — SAFE。** 校验作用于**值**，键必须属于闭集（`counts` / `flags` / `categories` / 特判键）；循环无 `else`，未知键静默丢弃。保留键（`event`、`attemptSequence`、`platform`、`buildMode`、`gitSha`、`version`）在 details 循环**之前**写入且不属于任何 allowlist 集合，不可被覆盖。**`attemptSequence` 不在 `counts` 中**（`counts` 含 `attempt`），通过 `details` 注入的 `attemptSequence` 无论类型均被丢弃。`RegExp(...).stringMatch(value) == value` 因 `^`/`$` 锚定等价于全串匹配，`model` 含换行、带 query 或 userinfo 均被拒；`endpointHost` 字符类排除 `/ @ ?`。`provider` 必须等于真实 `LLMProvider.values` 名称；`task` 必须是真实 `LlmTask`；`httpStatus` 范围校验；`counts` 要求 `value is int`（Dart `is int` 排除 `double`）；`flags` 要求 `is bool`；`gitSha`/`version` 经 `_buildValue` 长度+正则校验。

**3. 间接泄漏路径 — SAFE。** `markSafeLlm` 唯一生产调用点是 `_LLMAttemptTrace.mark`。逐键追溯：构造 details `turnRequest`/`subRequest`/`generation`（task/session ID）**被丢弃**；`attempt`/`maximumAttempts` 为 int；`provider`/`model` 经校验；`task` 为 enum。`snapshot()` 产出 int、`finishReason.stableValue`（∈ categories）、bool，以及 `contentValueTypes`/`reasoningValueTypes`（List，被丢弃）。ATTEMPT_FAILED 附加项中 `runtimeType`、`causeType`、`stackTrace`、`endpointPath` **均被丢弃**；`failureClass` 为 `AppErrorCode` 名称且 ApiError 只映射到前十项（均 ∈ 类别集）；`retryReason` 为闭集字面量。`_buildHeaders` 构造 `Authorization`/`x-api-key`，但**从不进入任何通道**。`ApiError.message`（可能内嵌 provider 错误正文）也从未传入任一通道。流式测试用含 userinfo/path/query 的 URL 驱动并断言无密钥出现。

**4. 诱导异常与行为耦合 — SAFE（修复前）→ 已加固。** 修复前 `markSafeLlm` 结构性不可抛（所有插入均有类型守卫，`jsonEncode` 只见平坦 String/int/bool）。重试决策在 `trace.mark('ATTEMPT_FAILED')` **之前**由 `consumerFailed`/尝试次数/取消状态算出；`responseCompleted` 仅由 `[DONE]` 或 Anthropic `message_stop` 设置；`finishReason` 仅来自解析事件；唯一共享可变状态是单调静态 `_nextDiagnosticAttempt`，无决策读取。`malformedEventCount` 仅用于诊断。

**5. SSE `data:` 可选空格修复 — SAFE。** `startsWith('data:')` 不可能匹配 `metadata:`、`data :`、`id:`、`event:`（WHATWG 规定字段名为首个冒号前文本，`data ` 为未知字段应忽略）。只剥除一个前导空格，符合 WHATWG "if value starts with a U+0020 SPACE, remove it"。CRLF 与无尾换行的末行由上游 `LineSplitter` 处理。`data:[DONE]` 被正确识别。

**6. usage-only 事件 — SAFE。** usage-only 分支构造的 `_OpenAiSseEvent` 只含四个 usage 字段，`finishReason`/`reasoningDelta`/`content` 均为 null，消费端只赋 usage 并跳过 null——无法伪造正文或完成标记。畸形 choices 仍抛 `_MalformedProviderEvent` 并被计数。无 usage 的 keepalive 仍返回 null。

**7. Legacy 通道绕过 — SAFE。** `mark()` 早退 `if (!enabled) return;`，`enabled => kDebugMode || kProfileMode` 在 release 为编译期 false。已逐个核对其余 legacy 成员（`counter`、`observeMax`、`setCounter`、`recordDuration`、`beginRun`/`endRun`、`registerSnapshotProvider`、`runtimeHeartbeat`、`startWatchdog`、`startUiHeartbeat`/`stopUiHeartbeat`、`dump`）及 `_SseGateTrace`，均无 release 可达路径。因此安全 allowlist 通道是该子系统在 release 的**唯一**可达输出，与设计意图一致。

**8. 测试覆盖充分性 — CONCERN（已修复）。** 原测试对 enabled 路径设计良好，但 CI 从不启用该路径（F1），且缺少 `attemptSequence` int 碰撞探针、allowlisted 键异常值不抛探针、`endpointHost` userinfo 拒绝探针、legacy 通道 release no-op 门禁测试。

## Remediation（已实施）

**R1（关闭 F1，MAJOR）**
- `.github/workflows/quality-gate.yml` 新增步骤 `Test safe LLM diagnostics allowlist (opt-in enabled)`，对 `test/core/debug/safe_llm_diagnostics_test.dart` 与 `test/services/llm_streaming_reliability_test.dart` 传 `--dart-define=LT_SAFE_LLM_DIAGNOSTICS=true` 执行（仅定向两文件，不重复全量）。
- `test/core/debug/safe_llm_diagnostics_test.dart` 新增 3 个探针：`attemptSequence` 经 details 注入（int 与 String）不得覆盖命名参数；allowlisted 键接收 `toString()` 抛异常对象、`double.nan`、`double.infinity` 时必须被丢弃且不抛；`endpointHost` 含 userinfo 必须被拒而合法 `model` 保留。

**R2（关闭 F2，MINOR）**
- `_LLMAttemptTrace.mark` 将双通道级联包入 try/catch，抑制时只输出静态类型名（`[LLM][DIAGNOSTIC_SUPPRESSED] <runtimeType>`），绝不输出值，避免泄漏 provider 错误正文或请求数据。诊断失败不得影响流式传输、已接收内容或重试决策。

**R3（关闭 F4 文档化）**
- 裸 `data:` 行计为 malformed 的政策已在本文件与回归文档中明确记录：`malformedEventCount` 仅用于诊断，不参与任何内容/重试/finish 决策，因此该行为变化无功能影响。

## 未验证范围

- 审查未运行 `flutter test` / `flutter analyze` / 构建；未复核 commit message 中 "4828 tests passed" 的声明。
- 未编译或运行 Release 构建；release 门禁结论为 `bool.fromEnvironment`、`kDebugMode`/`kProfileMode`/`kReleaseMode` 与早退的源码级推理。
- 未实测 Dart `RegExp` 语义；全串匹配论证由 `^`/`$` 锚定加 `stringMatch(value) == value` 等式导出。
- 未使用真实 Android 设备；A02–A06 的 Android 真机根因仍未被本审查验证。
- `test/application/resources/blueprint_planner_test.dart` 未做内容审查，超出本通道范围。
