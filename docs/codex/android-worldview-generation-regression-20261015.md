# Android 世界观生成跨版本调查与修复

Status: P0 协议修复与 Release 安全诊断已实施，全量回归与定向测试 PASS；Android 原始故障根因仍 NOT VERIFIED。P1 尚未进入。
Acceptance Mode: Independent Review required（P0-SSE-1 / P0-SSE-2 已独立复审 PASSED；P0-DIAG 实施尚未独立复审）。

## 权威、Scope 与基线

任务来源为用户 2026-10-15 附件《LT 世界观生成故障：跨版本根因调查与分阶段修复任务》及 AGENTS.md。严格 P0 → P1；没有 Android 真机验收，不得宣布 P0 FIXED，不得进入 P1 实施。

- 起始分支 `main`，HEAD `a3458d9f62d48238c907b7c6044a797df2944968`；远端 `git ls-remote --heads origin main` 同 SHA。
- 修复分支 `fix/android-worldview-generation-20261015`；main、历史 Tag 保持不变。
- 起始用户 WIP：`pubspec.lock`（165 additions / 165 deletions）；保留，不纳入任务提交。
- SQLite schemaVersion = 49；本阶段不修改 schema、迁移、资源持久化与原子事务。

## 原始证据矩阵

| 编号 | Android APK | 目标字符 | 原始结果 | 修复后真机复测 |
|---|---|---:|---|---|
| A01 | v1.2.05 | 50,000 | 成功 | NOT VERIFIED |
| A02 | v1.2.06 | 50,000 | 失败 | NOT VERIFIED |
| A03 | v1.2.07 | 50,000 | 失败 | NOT VERIFIED |
| A04 | v1.2.08 | 10,000 | 失败 | NOT VERIFIED |
| A05 | v1.2.08 | 25,000 | 失败 | NOT VERIFIED |
| A06 | v1.2.08 | 50,000 | 失败 | NOT VERIFIED |

没有 v1.2.06/07 的 10,000 或 25,000 证据。Linux Debug / DeepSeek / deepseek-flash / thinking disabled 的 50,000 案例已成功：5 Sections、14 Parts、规划 17,100、实际 23,215（46.43%）；不是生成失败，PART_TRANSITION_STALL 不等于死锁。

## 阶段 A：历史与当前调用链

| Tag | peeled commit | pubspec |
|---|---|---|
| v1.2.05 | 0558707 | 1.2.05+27 |
| v1.2.06 | 9cf96a7 | 1.2.06+28 |
| v1.2.07 | 935645d | 1.2.07+29 |
| v1.2.08 | a3458d9 | 1.2.08+30 |

已执行 git status/branch/log、git diff --cached、四组 Tag 实际 diff 调查。独立只读 Agent 同时复核历史，报告见 [independent review](android-worldview-generation-independent-review-20261015.md)。

生产链：Worldview UI → ResourceStudioController → ResourceStudioRuntime → ResourceAiCreationOrchestrator → ResourceCreationPipeline → BlueprintPlanner → AiGeneratorLlmGateway.rawCompletion → LlmTaskResolver → LLMService SSE → BlueprintParser / BudgetNormalizer / client U6 contract / Validator → blueprint repository → confirm transaction（Resource Tree + tasks）→ Part coordinator → validation → SQLite commit。

v1.2.05→06 与 06→07 没有修改规划器、规划 prompt/parser/validator、gateway、LLMService 或任务策略。05→08 的 LLMService、gateway、规划 prompt 也无变化。固定 4096 和严格截断检查在成功的 05 已存在，不能单独解释历史版本分歧。06 新增正文资源预算门禁；08 新增客户端内容契约等边界，应分别测试，不得把正文预算异常当作 provider-incomplete。

05→08 的 release workflow、Android main manifest、CompletionParams、ModelCapabilities、request scheduler 亦无变化；06→07 build.gradle 仅 debug applicationId/version suffix 变化，未改 release 签名/ABI/TTS配置。并未下载或重新验签历史发行APK，因此 Tag源码与附件所安装APK的逐位一致性未验证。

当前严格文本接口拒绝 `length` / `maxTokens`，即使 detailed result 的 responseCompleted=true 或正文恰好是完整JSON；`stop` 无DONE在正常EOF后接受；无terminal evidence为interrupted；空/stop reasoning-only经rawCompletion返回空后由BlueprintParser拒绝。正文/协议错误与reasoning-only可能被同一用户文案覆盖，不能反推真实失败阶段。

## 阶段 B/C：已证实缺陷与最小实施规格

以下是生产代码可确定性重放的旧缺陷，**尚无证据证明是六个实机案例的根因**。

### P0-SSE-1：合法 SSE 无空格数据行被丢弃（MAJOR）

- 位置：LLMService._sendOpenAICompatibleStream，`startsWith('data: ')`。
- 触发：服务器返回合法 `data:{JSON}` 和 `data:[DONE]`（冒号后无空格），客户端读取了完整数据但忽略全部行，结果 interrupted / incomplete。
- 依据：[WHATWG SSE field processing](https://html.spec.whatwg.org/multipage/server-sent-events.html#event-stream-interpretation)：冒号后的一个空格是可选的。
- 修复：识别精确 `data:` 字段并仅移除一个可选空格；保持现有逐行 provider 解码接口，不以该修复宣称完整多行 EventSource 支持。不改变 finish_reason、JSON、取消或 timeout 验收规则。
- 测试：通过真实 LLMService HTTP/SSE 路径先 RED，再 GREEN；有/无空格、CRLF、UTF-8 分片、stop / length / DONE / interrupted，对正确响应接受、对截断继续拒绝。`metadata:` 等字段不得误识别。

### P0-SSE-2：usage-only 尾事件统计丢失（MAJOR evidence gap）

- 位置：LLMService._parseOpenAiSseEvent；已读 usage 但 choices=[] / absent 时返回 null。
- 影响：服务端确认的 token 计数丢失，无法可靠调查4096是否耗尽；不能把估算当服务端值。
- 修复：无 choices 的合法 usage-only 事件仍返回 usage 元数据；不产生正文、不改变 finish 状态；keepalive 和畸形 choices 继续分别处理。
- 测试：最终 usage-only 尾事件（空/缺失 choices）保留 prompt/completion/cache 计数，正文只消费一次，未知 finish 不因 usage 变成功。

### 阶段 D：v1.2.05 → v1.2.06 首次退化归因（UNVERIFIED LEAD）

`git diff v1.2.05 v1.2.06` 中与世界观生成链路相关的**唯一新增功能门禁**是弹性预算执行（`part_generation_coordinator.dart`、`part_generation_validator.dart`）：

- 协调器新增 `remainingResourceBudget` 读取；当 `remaining <= 0` 直接抛 `PartGenerationValidationException(field: 'generation_budget')`；当 `remaining < targetCharacters` 时把目标压到剩余预算。
- 校验器新增硬拒绝：`response.content.length > request.maximumAcceptedCharacters` 即抛 `generation_budget` 异常，且明确“不会截断或覆盖已保存正文”。
- 该拒绝发生在 Part 校验阶段，重试用尽后整条 `RUN_FAILED_MAX_RETRIES`——**单个 Part 超预算即可把本可大部分成功的生成转为整体失败**，而 v1.2.05 无此上限检查，只要满足下限即保存。

**该机制来自已正式设计的 character-generation-budget / E50 弹性预算工作，是有意功能而非缺陷**，且与平台无关：它同样作用于 Linux，而 Linux 50k 案例（规划 17,100、实际 23,215）总长度未超预算，因此未被触发。故弹性预算门禁**不能单独解释 Android 专属失败**，列为待真机证据验证的首要推测，不据此改动预算机制（AGENTS.md 要求保留弹性预算、内容契约与失败重试）。

### 边界与禁止范围

不修改4096、thinking、规划结构、正文最小有效性、3000上限、R1/R2/R5、U6、可配置弹性、就绪/压缩、source CAS、事务语义。不补齐或修复截断 JSON 来冒充成功。不读取用户数据库、凭据，不记录正文/Authorization/API Key。不创建 Release、正式 Tag，不合并 main。

Release 诊断目前全部关闭（GenerationDiagnostics.enabled = debug/profile）；这是证据缺口，不能据此断言 Release 执行错误。本阶段先修已证实 SSE/usage 缺陷并扩展完整性矩阵；是否需要最小安全 Release 诊断在协议验证后决定，不能直接开启含任意字符串/stack 的通用 debug dump。

### P0-DIAG：最小安全 Release 请求证据

协议 RED/GREEN 已复现：SSE新增17测试，RED 7 PASS / 10 FAIL，GREEN 64 PASS（含既有测试）。由于 Release 缺少所需证据，继续实施显式 opt-in 请求元数据通道，独立于通用 debug dump。

- 使用编译标志 `LT_SAFE_LLM_DIAGNOSTICS=true`；默认关闭。通用 `GenerationDiagnostics.enabled` 保持原状，不启用 watchdog / 任意快照 / stack trace。
- 复用 GenerationDiagnostics 作为唯一诊断入口，增加专门 LLM 安全方法；由既有 `_LLMAttemptTrace.mark` 同时调用。仅已知事件和显式类型检查的 allowlist metadata；不输出任意 label、prompt、正文、reasoning文本、响应体、headers、异常message/stack、endpoint path/query/userinfo、任意task/session标识。
- 允许字段：provider/model、endpoint host、max_tokens/thinking/response_format、HTTP status、标准化 finish、DONE、completed、content/reasoning长度、usage、malformed计数、超时/取消/重试类别。字符串值需有界、JSON编码；安全类别采用已知枚举，不输出未知原始文本。
- 阶段从 `LlmTaskResolver` 传递的内存 metadata 获得，使用 `LlmTask` enum；若需扩展 CompletionParams，字段仅在内存使用，不进入请求wire或持久化JSON，copyWith保留；不改任何请求参数语义。
- 每次 HTTP attempt 使用本地单调序号关联事件，避免输出外部输入ID；可增加 `LT_BUILD_GIT_SHA` / `LT_BUILD_VERSION` 构建标记，默认unknown并严格验证格式。记录平台和build mode，不冒充实机运行。
- 测试验证：默认关闭/显式开启，生产请求和成功/失败路径出现安全字段；含密钥/正文/异常信息/URL query的输入不可泄漏；不同attempt区分；resolver task仅内存传播。不得为了诊断改变校验/重试/HTTP请求。
- 这是诊断修复，不能视为原始 Android 根因修复或实机验收；真机仍需收集该通道日志并对照10k/25k/50k。

## 验收与阶段门禁

1. 两条确定性旧缺陷先复现，保持 red/green 记录；完整规划JSON、部分JSON、非法JSON、空、reasoning-only、stop、length、缺DONE、中断各自归属正确层级。
2. 定向 transport / blueprint / SQLite / U6 / retry 回归 PASS；dart format、flutter analyze、flutter test、git diff --check；Android ARM64 release build及现有签名/ABI检查。
3. 独立审查 diff、生产调用链、测试覆盖与证据措辞；只可验收已证实协议修复，原始 Android 故障仍 NOT VERIFIED。
4. `adb devices -l` 当前无设备：ANDROID REAL DEVICE: NOT VERIFIED。10k/25k/50k 的实机 planning/tree/正文/SQLite/reopen/restart 均需补证据。
5. P0 真机未通过前 P1 保持 BLOCKED（阶段依赖）；不改变用户目标字数产品语义。

## 验证记录（逐阶段，非实机）

环境：Linux x64 host、Flutter测试VM、DeepSeek/deepseek-flash请求形状、HTTPS example.invalid受控HTTP client；API Key为fixture，未调用真实Provider。SHA基线a3458d9，测试目标见各矩阵；所有SQLite位于独立临时目录，无用户数据写入。

| 记录 | 命令/范围 | 真实结果 | 日志 |
|---|---|---|---|
| SSE-RED | 新增17条 production LLMService SSE测试，修复前 | 7 PASS / 10 FAIL | `/tmp/lt-worldview-sse-red.log` |
| SSE-GREEN | `flutter test --no-pub test/services/llm_streaming_reliability_test.dart --reporter expanded` | 64 PASS | `/tmp/lt-worldview-sse-green.log` |
| PLANNER-RED | planner `--plain-name 'production transport and SQLite boundary'`，修复前 | 2 PASS / 8 FAIL | `/tmp/lt-worldview-planner-boundary-red.log` |
| P0-TARGETED | planner、truncation、task policy、parser、validator、normalizer、orchestrator、contract confirm SQLite、U6C、U6E、角色retry recovery，共11文件 | 133 PASS | `/tmp/lt-worldview-p0-targeted.log` |
| INDEPENDENT | 独立Agent运行 transport + planner + truncation | 100 PASS | 独立审查报告 |
| FORMAT-1 | `dart format --output=none --set-exit-if-changed .` | 890 files、0 changed、exit 0 | `/tmp/lt-worldview-format.log` |

上述计数有交集，不相加为唯一测试数。Planner新增矩阵验证10k/25k/50k的创建会话→真实gateway→真实LLMService→JSON/U6校验→真实SQLite确认事务→关闭/重开数据库；任务仍pending，不冒充正文完成/Android进程重启。故障矩阵验证length、缺terminal、中止、不合法/部分JSON、空、reasoning-only均不能保存Blueprint或Resource。

`flutter doctor -v`：Android SDK/build-tools存在，但若干licenses未接受；adb无设备。`android/key.properties`及正式文档指定的本地签名材料均不存在；不生成替代密钥，不降低release签名门禁。Android构建实际命令及结果待补充。

### 全量回归与 82 文件补跑（2026-10-15 交接后完成）

| 记录 | 命令/范围 | 真实结果 | 日志 |
|---|---|---|---|
| FULL-REGRESSION-1 | `flutter test --no-pub --concurrency=2 --reporter expanded`（交接前首次） | +1605 passed / ~7 skipped / 0 failures，**无最终总结行，进程被中断** | `/tmp/lt-worldview-full-test.log` |
| FULL-REGRESSION-2 | 同上完整重跑 | **+4145 passed / ~7 skipped / 0 failures，`All tests passed!`** | `/tmp/lt-worldview-full-test-rerun.log` |
| MISSING-82 | 对回归日志未覆盖的 82 个测试文件补跑 | **+676 passed / 0 failures，exit 0** | `/tmp/lt-worldview-missing-82.log` |
| MISSING-2 | 对仍未覆盖的 2 个文件补跑 | **+7 passed / 0 failures** | 同上 |

合计 **373/373 测试文件、4828 tests passed / 0 failed**。`dart format` 891 files 0 changed；`flutter analyze` No issues found；`git diff --check` 通过。

**方法学警示（供后续 Agent）**：`flutter test --reporter expanded` 在 stdout 为文件（非 TTY）且 `--concurrency>1` 时，输出采集不完整——上述回归日志仅出现 2 行 `loading`，且 82 个已执行文件的测试名称完全缺失。因此**不能仅凭日志关键字匹配判断某测试文件是否执行**。必须以最终 `All tests passed!` / `Some tests failed` 标记与退出码为准，并对日志未覆盖的文件另行补跑核对。`test/architecture/` 单独执行为 58 tests PASS，证明这些文件可正常执行而非被永久跳过。

**Android 构建状态：BLOCKED。** `flutter build apk --release --target-platform android-arm64` 两次失败：① Gradle daemon 崩溃；② `:app:verifyReleaseSigning` 失败，因 `android/key.properties` 不存在。未产出 APK，未伪造签名，未创建 Release/Tag。
**Android 真机状态：NOT VERIFIED。** `adb devices -l` 无设备。

## Android 下一步实测方法（尚未执行）

在具有正式签名材料的环境，将修复分支的已提交源码构建为 ARM64 Release：

```sh
flutter build apk --release --no-pub --target-platform android-arm64 \
  --dart-define=LT_SAFE_LLM_DIAGNOSTICS=true \
  --dart-define=LT_BUILD_GIT_SHA="$(git rev-parse HEAD)" \
  --dart-define=LT_BUILD_VERSION=1.2.08+30
python3 scripts/verify_android_release_signing.py build/app/outputs/flutter-apk/app-release.apk
python3 scripts/verify_android_arm64_apk.py build/app/outputs/flutter-apk/app-release.apk
```

使用正式签名升级安装，不卸载、不清数据；不创建发布Tag或GitHub Release。逐个运行10k/25k/50k世界观测试，每个案例单独保存仅`[lt-safe-llm]`通道的logcat，人工记下目标/实际UI阶段并对照本地attemptSequence。通道默认不输出用户正文、请求/资源ID、URL path/query、headers或异常原文；同一应用进程的attempt序号单调递增，重启后重新计数。

需要逐案例补齐：Blueprint完成与Sections/Parts/规划字数、Tree确认、Part开始、逐Part真实正文长度及事务成功、最终资源字数和任务状态、重新打开与App重启后仍存在。安全LLM日志只证明请求与响应元数据，**不能单独证明SQLite成功、正文有效或任务完成**；这些应从生产持久化/可见资源状态另行验证。没有覆盖的字段保持NOT VERIFIED，不从fixture或Linux案例推断。

若日志显示length/maxTokens，再依据实际阶段、预算和usage设计有界重新规划或输出预算方案；若stop且完整JSON仍被拒绝，则保留脱敏协议证据定位parser/validator；reasoning-only/空/HTTP错误分别处理。不得先调整4096再把后续一次成功当作根因证据。
