# Android 世界观生成：历史审计与协议修复独立复审

Status: PASSED — 仅 P0-SSE-1 / P0-SSE-2 最小协议修复可接受。
Acceptance Mode: Independent Review。
原始任务：P0 NOT VERIFIED；P1 NOT VERIFIED，受 P0 阶段依赖阻塞。
ANDROID REAL DEVICE: NOT VERIFIED。

## Summary

独立审查 Agent 依照 `code-audit` skill 只读审计历史、生产调用链和修复 diff，并独立运行定向测试。除本报告外未修改文件，未提交。本报告不代替全仓质量门禁、Android 构建或真机验收。

审计基线为 `main` / `v1.2.08` 的 `a3458d9f62d48238c907b7c6044a797df2944968`。修复位于 `fix/android-worldview-generation-20261015`，复审时 HEAD 仍为该基线，修改尚未提交。已有用户 `pubspec.lock` WIP 保留，不属于审查实现范围。

正式实施规格：[`android-worldview-generation-regression-20261015.md`](android-worldview-generation-regression-20261015.md)。本次没有审查后续尚未实施的 P0-DIAG Release 诊断方案。

最小修复范围没有未解决 BLOCKER / MAJOR。Android 原始失败阶段与根因仍缺乏实机证据，两条已修复旧缺陷不得被宣称为 A02–A06 的已确定根因。

## 历史与构建基线

通过 `git rev-list -n 1 <tag>` 和 `git show <tag>:pubspec.yaml` 核对：

| Tag | peeled commit | pubspec |
| --- | --- | --- |
| v1.2.05 | `0558707adf1e7688c6791a12b500978e46b86a1a` | `1.2.05+27` |
| v1.2.06 | `9cf96a78e22979968c112a56b45948223e850f8d` | `1.2.06+28` |
| v1.2.07 | `935645d46860cf7cbd2814edde1dee7e8f5ba1bc` | `1.2.07+29` |
| v1.2.08 | `a3458d9f62d48238c907b7c6044a797df2944968` | `1.2.08+30` |

阅读了以下四组实际代码 diff，而非仅依据提交说明：

| 比较命令范围 | 实际变化与归因边界 |
| --- | --- |
| `git diff v1.2.05 v1.2.06` | BlueprintPlanner / PromptBuilder / Parser / BudgetNormalizer / Validator、AiGeneratorLlmGateway、LLMService、LlmTaskPolicy 无变化。正文 Part 新增 remainingBudget、累计预算事务检查和 `generation_budget` 拒绝；触发在正文阶段，不能直接解释 Blueprint 阶段失败。 |
| `git diff v1.2.06 v1.2.07` | 上述规划和 LLM/SSE 实现仍无变化。新增数字预算输入和压缩队列修复。Android 配置仅新增 debug 的 `.debug` applicationIdSuffix 与 `-debug` versionNameSuffix，release 签名路径不变。 |
| `git diff v1.2.07 v1.2.08` | 新增 U6 客户端 Blueprint 内容契约、单 Part `<=3000` 校验及预算改进。Part task policy 显式禁用 thinking，但 gateway 原先构造参数已默认禁用。这些变化不能解释 v1.2.06 的历史失败。 |
| `git diff v1.2.05 v1.2.08` | LLMService、AiGeneratorLlmGateway、BlueprintPromptBuilder 完全无 diff。固定4096、严格截断检查和本次两条缺陷均已存在于成功的 v1.2.05。 |

另核对 `.github/workflows/release-arm64.yml`、Android manifest / Gradle 配置、CompletionParams、ModelCapabilities、GenerationRequestScheduler。本区间 release workflow / manifest / 参数与能力实现无相关变化；构建仍使用 `flutter build apk --release --target-platform android-arm64`，release 签名配置保留。没有在 Blueprint / gateway / SSE 业务路径发现 Android 或 Release 专属判断。`GenerationDiagnostics.enabled` 仅 debug/profile 为真，Release 缺少同等诊断证据；这不等于已证明 Release 逻辑故障。

没有重新下载或验证四个历史 APK；发行记录中的签名、ABI 和打包结果不作为本次独立实机证据。

## 核心不变量与生产链

生产链为 UI → ResourceStudioController / Runtime → ResourceAiCreationOrchestrator → ResourceCreationPipeline → BlueprintPlanner → AiGeneratorLlmGateway.rawCompletion → LlmTaskResolver → LLMService → BlueprintParser / Normalizer / 客户端契约 / Validator → Blueprint repository → confirm transaction → Part coordinator → validation → SQLite commit。

复审不变量：合法完整响应不得因合法 `data:` 空格形式被丢弃；usage 元数据不得制造正文或完成状态；截断不得交给 BlueprintParser 冒充完整内容；无效或部分 JSON 不得保存为 Blueprint；取消、超时、用户已有正文与 SQLite 事务边界保持不变。

## 原始缺陷与修复核对

### P0-SSE-1：合法无空格 data 字段被丢弃

- 原始位置：`lib/services/llm_service.dart` 的 `_sendOpenAICompatibleStream`，基线约967行仅识别 `startsWith('data: ')`。
- 触发：完整响应使用 `data:{JSON}` / `data:[DONE]`；传输虽完整到达，但行全部被忽略，最终 interrupted，文本 API 抛 `LLMResponseIncompleteException`。
- 根因：把冒号后空格当作必要字段语法。[WHATWG SSE field processing](https://html.spec.whatwg.org/multipage/server-sent-events.html#event-stream-interpretation)规定该空格可选。
- 修复核对：约975行识别精确 `data:` 并只移除一个可选空格，未误识别 `metadata:` / `data :`。
- 回归证据：带/不带空格、CRLF、逐字节分片 UTF-8、DONE、stop、length及无终止证据测试均通过；length即使含完整JSON及DONE仍抛不完整异常。
- 历史边界：缺陷 v1.2.05 已存在，尚未证明 Android失败响应使用该形式。

### P0-SSE-2：usage-only 尾事件统计丢失

- 原始位置：同文件 `_parseOpenAiSseEvent`，读取usage后在choices为空/缺失时直接返回null。
- 触发：服务端在 `choices: []` 或缺失choices的独立事件中报告token计数。
- 实际影响：prompt / completion / cache计数丢失，削弱判断4096是否耗尽的证据。
- 修复核对：约778行返回仅含usage的 `_OpenAiSseEvent`。它不含content、reasoning或finishReason，因此不会使无终止证据的响应成功，也不会改变stop/length语义。
- 回归证据：两类usage-only形态、stop/length/unknown、四个计数字段、正文只消费一次、畸形choices不被usage旁路的测试均通过。

### 已知旧边界

OpenAI-compatible路径仍逐行解码，不完整支持单一SSE事件的多条data行。该限制在基线已存在，本次没有引入，也没有宣称已解决。当前协议修复范围明确限定为可选空格和usage保留；不得据此宣称完整EventSource支持。

## 独立验证

实际独立执行：

```sh
flutter test --no-pub test/services/llm_streaming_reliability_test.dart test/application/resources/blueprint_planner_test.dart test/unit/p0_llm_service_truncation_test.dart --reporter compact
dart format --output=none --set-exit-if-changed lib/services/llm_service.dart test/services/llm_streaming_reliability_test.dart test/application/resources/blueprint_planner_test.dart
git diff --check
```

结果：**100 tests passed，exit 0**；三个文件format零变更；diff-check通过。执行 Agent 报告的先RED计数属于其执行记录，独立审查未通过修改代码重跑RED；原始缺陷另由基线代码直接核对。

新增Planner测试经过真实AiGeneratorLlmGateway、LLMService与临时SQLite，验证10k/25k/50k规划、确认和关闭数据库后重开。它仅证明规划/资源树/task持久化，不证明正文生成、目标字数达成或Android进程重启。错误矩阵验证完整JSON+length、无terminal evidence、空、reasoning-only、非法及部分JSON均拒绝，失败不保存Blueprint、resources或resource_parts。

本次生产diff仅修改LLMService，没有改动截断检查、BlueprintParser、预算/内容契约、3000上限、持久化、schema、就绪、压缩或事务实现。测试未删除、skip或放宽既有断言。

## 原始任务与后续门禁

原始A01–A06结果保持：05/50k成功；06/50k失败；07/50k失败；08/10k、25k、50k失败。没有06/07较小目标的证据。本次没有真机复测，不能改写历史结果。

- P0：Android原始根因未证实，实机planning/tree/正文/SQLite/reopen/restart缺少验证，**NOT VERIFIED**。
- P1：Linux目标50k、规划17,100、实际23,215属于成功但字数不足，未实施或验收；继续等待P0可靠验证。
- Release安全诊断属于后续待审实现；本报告当前不接受或拒绝尚不存在的代码。
- 本次未独立运行flutter analyze、全仓flutter test、Android构建或真机测试；主Agent仍需完成适用质量门禁。

因此可接受的是本次两条协议修复，不能将其扩大为整个P0/P1任务ACCEPTED。
