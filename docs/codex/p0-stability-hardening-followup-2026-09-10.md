# LT P0/P1 Stability Hardening Follow-up

## 1. 基线

- 审查日期：2026-09-10。
- Repository：`yangrunzhi345-blip/LT`。
- 本地 HEAD：`69f80cfe2461140ce16b03941fdd16868e9494f3`。
- `origin/main`：`69f80cfe2461140ce16b03941fdd16868e9494f3`（本次已执行 `git fetch origin` 后确认）。
- 最新 main commit：`fix: canonical structured JSON, guard prompt, poisoned rows, and wizard resource isolation`。
- 前置方案：[p0-character-import-adventure-loading-remediation.md](p0-character-import-adventure-loading-remediation.md)。
- 本方案为后续增量方案，不替代、不覆盖前置方案。
- 编写开始时 working tree 有 47 个既有未提交修改。本方案编写过程中未处理、格式化、覆盖或暂存这些修改；所有代码证据均来自 `git show origin/main:<path>`，而非 dirty worktree。

GitHub 可见状态（2026-09-10）：`main` 的 branch API 报告 `protected: false`、required status checks 关闭；当前 HEAD 的 check-runs 为 0。仓库树只有 `.github/workflows/release-arm64.yml`，没有 `.github/workflows/ci.yml`。因此当前本地成功测试不能替代远端 CI 的二次门禁。

## 2. 与旧方案关系及已确认修复项

前置 P0 已在当前 main 修复并已有回归覆盖：详细角色严格 `Stage1 → Stage2A → Stage2B`、stage-only schema retry、角色卡 poisoned row 隔离、Wizard 三类资源独立加载、thinking 的 detailed-generation 三态、Guard/Prompt 合同，以及窄屏 Wizard partial-success。

本方案不回滚这些行为。以下十项是对当前 `origin/main` 的重新审查结果；**没有一项可标记为“已验证不存在/已在当前 main 修复”**。

## 3. 当前仍存在的问题总表

| ID | Severity | Status | Root Cause | Files | Risk |
| --- | --- | --- | --- | --- | --- |
| P0-1 | P0 | Confirmed | `_handleStart` 的异常边界只包住最终 callback | Wizard screen | 启动按钮永久 disabled |
| P0-2 | P0 | Confirmed | structured response 在 completion 状态检查前被 repair 接受 | `ai_generator_service.dart` | 截断内容进入正式卡片 |
| P0-3 | P0 | Confirmed | validator 接受 scalar 非字符串，consumer 使用 `as String?` | stage validator / generator | TypeError 或错误资料 |
| P0-4 | P0 | Confirmed | Stage2B validator 接受 nested profile，assembler 只读 flat root | stage validator / generator | 世界定位字段静默丢失 |
| P0/P1-5 | P0/P1 | Confirmed | `maxRetries` 实际代表总 attempts，命名与分层不一致 | `api_error.dart` / generator | 429/timeout 无预期 backoff、预算难审计 |
| P1-6 | P1 | Confirmed | shared controller 的 load 无 single-flight/version | setup controller / dashboard / Wizard | stale load 覆盖较新状态 |
| P1-7 | P1 | Confirmed | `CharacterCard` 保留两套不同严格度 parser | `character_card.dart` | 三方 JSON/PNG 导入 TypeError |
| P1-8 | P1 | Confirmed | 多个 persisted parser 强转且无分类策略 | models/controllers/repositories | 单条旧数据拖垮列表或冒险 |
| P1-9 | P1 | Confirmed | `CompletionParams` 默认 thinking=true | completion params / helper callers | 短请求延迟与 token 成本异常 |
| P1-10 | P1 | Confirmed，独立问题 | SceneBatch 名称严格匹配与单巨型 JSON | batch import path | 批量结果被过滤或截断 |

## 4. Phase A — P0 correctness blockers

### P0-1 Adventure Wizard 启动异常边界

**问题与当前代码证据。** `AdventureWizardScreen._handleStart()` 在约 1754 行先设置 `_submitting = true`，然后在 `try` 之前执行 `saveWorldviewPreset`、`setupController.loadInitialData`、snapshot fallback、逐张 `saveCharacterCard`、`CustomAttributeItem.fromJson(Map.from(item as Map))`、NPC `jsonDecode`、`AdventureConfig` 构造和 `CharacterCard.fromJson`。约 1996 行才开始只包住 `widget.onStartAdventure(config)` 的 `try/catch/finally`。

**根因与失败链路。** 任何前置 await、强转或构造抛出后都会跳过 finally，`_submitting` 保持 true，controlsBuilder 让按钮 disabled，下一次 `_handleStart()` 又因首行 guard 直接 return。当前 UI 同时承担持久化、序列化、领域装配和导航准备，异常边界不完整。

**正确行为与推荐修改位置。** 将 `_handleStart` 在所有前置校验后改为一个统一 boundary：`setState(submitting=true) → try { prepare/start entire flow } catch (e, st) { map to user-facing error; preserve diagnostic cause } finally { if (mounted) setState(submitting=false) }`。提取不依赖 `BuildContext` 的 `AdventureStartPreparationUseCase`：输入 Wizard draft、资源仓储和 snapshot service，输出 immutable prepared config / typed failure；仅把 UI feedback 与 navigation 留在 Widget。持久化的世界观与角色要明确事务边界：若承诺“启动前保存”，用 repository transaction 包含可原子化写入；若不能跨资源原子化，则返回准备失败并保留已保存资产，不假装回滚。

**不应采用。** 不要在各 await 后散落 `_submitting=false`；不要吞掉异常；不要用 `Future.delayed`；不要为避免失败跳过保存或 silently replace malformed custom attributes。

**回归测试与验收。** widget/use-case tests 分别让 `saveWorldviewPreset`、`loadInitialData`、每张 character save、custom-attribute/config preparation、`onStartAdventure` 抛出。每个 case 断言用户错误可见、`_submitting == false`、启动按钮再次可点；最后一个 case 还断言不会 pop。成功路径断言按既有次序只调用一次。覆盖 320px error feedback 无 overflow。

**影响。** DB migration：否。旧数据：不删除、不清空，失败时需记录哪些写入已确认。UI：错误状态更可靠。LLM/token：无。独立提交：是，`fix: harden adventure start exception boundary`。

### P0-2 Structured JSON 截断响应被错误接受

**问题与证据。** `AiGeneratorService._resolveContent()` 先对 `result.content` 做 tolerant decode 和 `_repairTruncatedJson`；只要 `expectJsonObject` 且 `parsed` 非空，就立即 `jsonEncode(parsed)` 返回。`responseCompleted`、`finishReason.allowsParsing`、`finishReason.isTruncated` 的检查位于这个 return 之后，仅影响非 structured 路径。当前 P0 truncated test 用 `LLMFinishReason.stop` 模拟截断，未模拟 transport 的 `length/maxTokens + responseCompleted=false`。

**根因与失败链路。** 括号闭合只证明语法可恢复，不证明模型已表达完字段、数组或语义；被提前 canonicalize 的半截 JSON 会通过 stage schema 后进入角色卡。

**正确行为与推荐修改位置。** 在 `_resolveContent` 的任何 repair 前先分类 `LLMStreamResult`：对 structured call，`responseCompleted == false`、`finishReason.isTruncated` 或明确 `length/maxTokens` 一律抛出 typed `StructuredOutputIncompleteException`。由当前 stage 的 content retry 预算重新请求，不能把该内容当成功。未来若要保留受控修复，另立显式策略：仅 `responseCompleted=true`、允许的 finish reason、strict canonical decode、完整 schema 与语义 validator 均通过才可接受；默认不启用。

**不应采用。** 不要只靠补 `}`；不要把 `length` 伪造为 `stop`；不要从截断字段填默认值后成功返回。

**回归测试与验收。** 在真实 `LLMStreamResult` fake 中分别传可 repair 文本 + `LLMFinishReason.length`/`maxTokens` + `responseCompleted=false`，断言当前 stage retry、前序 Stage1/2A 不重跑、最终只接受完整 stop 响应。另测 completed `stop` 的可修复控制字符/尾逗号仍 canonicalize；取消不 retry。验收是截断 response 从不成为 final config。

**影响。** DB migration：否。旧数据/UI：否（错误会以可重试生成失败呈现）。LLM/token：可能多一次有界 content retry，减少保存坏卡。独立提交：是，`fix: reject incomplete structured model responses`。

### P0-3 StageSchemaValidator 类型契约不足

**问题与证据。** `StageSchemaValidator._hasValue()` 对非 null、非空 Iterable/Map 的任何 scalar 都返回 true；`{"name":123,"gender":true,...}` 可通过 identity schema。随后 `_generateDetailedCharacterCard()` 以 `t1Data['name'] as String?`、`personality as String?` 等读取，契约不一致。

**根因与失败链路。** validator 的“存在”语义与 assembler 的“字符串”语义不同：错误 payload 先 PASS，再在强转处 TypeError；或在某字段绕过时生产不可信卡片。

**正确行为与推荐修改位置。** 建立 `DetailedCharacterStageNormalizer`，数据流固定为：`raw JSON object → normalize stage aliases/allowed scalar representation → typed schema validation → typed StagePayload DTO → assembler`。正式 LLM stage 字段要求非空 String；`taboos` 要 `List<String>`，而非任意 List；禁止 bool/Map 伪装文本。只在明确 legacy alias（如 `background → description`、`body_description → bodyDescription`）处做映射，并把 alias 列为测试合同。

**不应采用。** 不要让 validator 宽松而在 assembler 内散落 `as String?` 或 `.toString()`；不要把任意 List/Map JSON stringify 成文本以蒙混 schema。

**回归测试与验收。** 每个 stage 对 String、num、bool、List、Map、null 和 legacy alias 建表测试；错误类型必须留在当前 stage 触发 bounded retry；最终 DTO 不含 dynamic 读取。验收是 validator 与 consumer 对每一 canonical 字段类型完全一致。

**影响。** DB migration：否；它只处理 LLM transient payload。旧数据/UI：否。LLM/token：类型错误会产生一次有界 stage retry。独立提交：可与 P0-4 同一提交，建议 `fix: normalize detailed character stage payloads`。

### P0-4 backgroundWorld schema / assembler 契约冲突

**问题与证据。** `StageSchemaValidator.backgroundWorld` 同时接受 root flat fields 和 `world_profile` container；而 Stage2B Prompt 要 flat JSON，assembler 只从 `t2bData['faction']`、`home_location`、`public_goal`、`hidden_motivation` 等 root key 取值。因此 nested `world_profile` 能 validator PASS，却在结果中静默变空。

**根因与失败链路。** producer/validator/consumer 三方没有唯一 canonical shape。

**正确行为与推荐修改位置。** 正式 Stage2B contract 设为 flat：`description, faction, home_location, public_goal, hidden_motivation` 加按 Prompt 所需扩展字段。若兼容 nested，normalizer 必须在 validation 之前且仅在该 stage 做 `world_profile → flat`；key 冲突优先 canonical root，记录无效 nested 不能静默覆盖。assembler 仅消费 DTO。

**不应采用。** 不要继续接受两种 schema 而只实现一种读取；不要在 assembler 内猜测 shape；不要将 whole `world_profile` 原样塞入 final card 而绕过 typed fields。

**回归测试与验收。** flat payload 成功；nested legacy payload 被 normalize 后成功且 final `world_profile` 的 faction/location/goal/motivation 保留；冲突 payload 有确定优先级；缺字段只 retry Stage2B。验收是不存在 validator PASS 但 assembler drop 的 payload。

**影响。** DB migration：否。旧数据：仅对 LLM response 的可选兼容。UI：无。LLM/token：无，除失败 retry。独立提交：同 P0-3。

### P0/P1-5 Structured transport retry 语义错误

**问题与证据。** `structuredJsonTransportRetries = 1` 注释称“single retry”，但 `RetryManager.withRetry` 在 catch 中 `attempt++` 后 `if (attempt >= maxRetries) rethrow`。所以 maxRetries=1 是一共一次 attempt、零次 retry。`_callText/_callMessages` 还将 `StateError` 同时当作 transport retry，stage 层再以 `characterStageMaximumExtraAttempts=2` 调用，预算语义混合。

**根因与失败链路。** `maxRetries` 名称与实现定义不同，429/timeout 无预期 backoff 而直接落到 stage retry；transport/content 分类靠 message substring，难以计算最坏调用次数。

**正确行为与推荐修改位置。** 将 `RetryManager` API 改为二选一且全仓统一：推荐 `maximumAttempts`（含首次），调用方显式填 2；或 `maximumRetries`（首次之外），内部条件改为 `retriesUsed >= maximumRetries`。为 structured calls 引入 typed `RetryBudget(transportAttempts: 2, contentStageAttempts: 3)`，transport 只涵盖 timeout、429、5xx、connection reset、handshake；content 只涵盖 empty/invalid schema/truncated/semantic failure。Cancellation 永不 retry。记录最大外部请求数，例如每 stage `3 content attempts × 2 transport attempts = 6`，supplement 的 budget 单独定义且不得无限嵌套。

| Layer | Trigger | Budget (recommended) | Backoff | Must not retry |
| --- | --- | --- | --- | --- |
| Transport | timeout, 429, 5xx, reset, handshake | 2 attempts | `retryAfterMs` + capped exponential jitter | cancel, 4xx invalid request |
| Stage content | empty, invalid JSON/schema, length/maxTokens | 3 attempts | no delay beyond transport policy | accepted stage, cancellation |
| Supplement progress | no semantic growth | initial + 2 no-growth attempts | none | cancellation / target complete |

**不应采用。** 不要只改常量值掩盖 off-by-one；不要让 `StateError` 不分类地穿透所有 retry 层；不要增加无限 retry 或固定长 sleep。

**回归测试与验收。** RetryManager exact-attempt tests（0/1/2 retry）、429 retryAfter、timeout、5xx、cancel、invalid 4xx；stage records transport and content call count separately；证明 1/1/2 schema behavior仍成立。验收：命名、实现、文档和测试对 attempts/retries 的含义一致。

**影响。** DB migration：否。旧数据/UI：否。LLM/token：上界显式可审计，可能恢复一次原本遗漏的 transient retry。独立提交：是，`fix: clarify transport and content retry budgets`。

## 5. Phase B — persisted-data hardening

### P1-7 CharacterCard 第二套不安全 parser

**问题与证据。** `CharacterCard.fromJson()` 已有 `_asMap/_asText/_asTextList` tolerant path；但 `parseFromJson`、`parseFromPngBytes` 调用 `_cardFromJson()`，其 `data` 使用 `as Map<String,dynamic>?`，文本字段 `as String?`，tags 和 alternate greetings 用 `.cast<String>()`。第三方 SillyTavern JSON/PNG 的 numeric name、wrong `data`、mixed tags/greetings 会抛 TypeError；PNG 外层 catch 只导致整张卡消失。

**根因与失败链路。** 同一领域模型维护两套 parser，数据库行的兼容策略没有复用于导入渠道。

**正确行为与推荐修改位置。** 让唯一 public canonical parser 接受 `Map` + provenance，并输出 `CharacterCardParseResult(card, warnings, fatalError?)`。`fromJson`、JSON import、PNG metadata、legacy DB row、AI result 都先 canonicalize，再由同一 decoder 构建 card。明确 channel policy：导入可保留 card 并显示 field warnings；持久化列表可隔离坏 row；AI payload 则由 P0 schema 驱动而非借此宽容。

**不应采用。** 不要复制 `_asText` 到 `_cardFromJson`；不要对 malformed import 清库或静默丢失所有 cards；不要把任意 nested value stringify。

**回归测试与验收。** SillyTavern JSON、PNG metadata、legacy row、AI canonical result 使用同一 fixture matrix；覆盖 `data` 为 string/list/null、numeric name、mixed tags/greetings、world_profile types。验收：同一 payload 经四条入口得到一致 card/warning，单张失败不影响邻居。

**影响。** DB migration：否。旧数据：兼容增强且不删除。UI：导入 warning/摘要需要最小呈现。LLM/token：无。独立提交：是，`refactor: unify character card parsing`。

### P1-8 Persisted JSON poisoned-row 系统性风险

**问题与证据。** 当前 main 存在多个用户/历史 DB JSON 强转点：`WorldviewDetails.fromJson` 的 `(json['format_version'] as num?)?.toInt()` 会拒绝字符串 `"2"`；`AdventureConfig.fromJson`、`AdventureSelectedCharacter.fromJson`、`AdventureCharacterRelationship.fromJson`、`SupportingCharacter.fromJson` 多处 `as String?/int?/bool?/Map<String,dynamic>?`；`GameState.fromMap` 和 `WorldEntry.fromJson` 用 `List<String>.from`/`cast<String>()`；`AdventureTemplateController.buildPresetData` 对 char JSON 直接 decode/cast。它们的来源是 persisted/imported data，不应假定总是 canonical。

**根因与失败链路。** 资料库 P0 只修 CharacterCard row，其他可持久化聚合仍在各处自行解析，`jsonDecode` 成功但类型不符即可让读列表、启动冒险或模板页面抛出。

**正确行为与推荐修改位置。** 先建立 `PersistedDataNormalizer`（内部 package-level helper，而非泛化 dynamic dumping）：`readText`, `readInt`, `readBool`, `readStringList`, `readMap`, `decodeObject`, `decodeArray`，每个明确输入/默认/diagnostic policy。第一批迁移为 WorldviewDetails、WorldviewPresetEntry、AdventureConfig/selected/relationship/supporting/NPC snapshot、GameState、WorldEntry、AdventureTemplateController。`format_version` 接受 num 或 decimal string；enum index 做范围检查；已强验证的 runtime-only canonical state 保持严格并标注边界。

**不应采用。** 不要全仓机械 `.toString()`；不要吞掉所有异常并空白覆盖；不要修改 schema 或清空旧数据库来逃避兼容。

**回归测试与验收。** 每个模型建立 `valid canonical / legacy numeric-string / wrong scalar / mixed list / wrong map / malformed JSON` matrix；list loader 断言 one poisoned row 不阻止 siblings；template bad char data 返回 typed failure而非 throw；Worldview `format_version:"2"` 成功。验收：每个 persisted boundary 明确 tolerant 或 strict，且有对应 test。

**影响。** DB migration：通常否；仅格式解释扩展，若需写回 canonical 必须独立、幂等、transactional migration。旧数据：保护并提高可读性。UI：为 resource rows/模板显示 non-blocking warning。LLM/token：无。独立提交：是，`fix: tolerate legacy persisted resource payloads`。

## 6. Phase C — concurrency/state ownership

### P1-6 AdventureSetupController 并发加载竞态

**问题与证据。** `AdventureSetupController.loadInitialData()` 每次直接设置 shared `_loading=true`，并发 `Future.wait` 三类资源，完成后无条件写 shared lists/errors/loading。调用点至少有 Wizard `_loadData`、Dashboard Featured Worlds `_loadUserWorlds`、Dashboard Character Cards `_loadCards`，它们共享 provider/controller。

**根因与失败链路。** A starts → B starts → B finishes并显示新数据 → A later returns并覆盖 lists/errors；或 A remains active while B returns so `_loading=false` 与仍进行的 A 矛盾。

**正确行为与推荐修改位置。** 选择 **generation token + latest-request-wins**：每次 load 分配递增 requestId，全部三类结果先留在 local immutable result，only if requestId is current 才一次性 commit state/notify。若并发请求没有参数差异，再加 single-flight 复用同一 Future；显式 `forceReload` 才生成新版本。理由：支持保存后强制刷新，又避免 Dashboard/Wizard 重复 I/O；不会让较老结果覆盖较新结果。将 loading/error/data 聚合为 immutable `AdventureAssetLoadState`，页面只读 snapshot。

**不应采用。** 不要简单 mutex 串行所有请求（保存后的刷新会被旧读取阻塞）；不要在每个 `_loadX` 直接写 shared error；不要依赖页面 mounted 来解决 controller state race。

**回归测试与验收。** 用 controllable futures 验证 A/B completion reverse order，A 不覆盖 B；concurrent identical load 只访问每类 repository 一次；force reload 可启动 B；loading 直到 current request settle；每类失败仍独立。验收：Wizard和两个 Dashboard 都使用一致 snapshot，且无 stale overwrite。

**影响。** DB migration：否。旧数据：无。UI：loading/error transition 更稳定。LLM/token：无。独立提交：是，`fix: serialize adventure asset loading state`。

## 7. Phase D — Thinking policy

### P1-9 CompletionParams 全局默认 Thinking 风险

**问题与证据。** `CompletionParams` 默认 `enableThinking=true`、`reasoningEffort='high'`，且 `fromJson` 缺值也回退 true。尽管 detailed world/character generation 已显式由 `generationMode == deepThinking` 控制，短调用仍省略该参数：`TranslationService`、`TtsService.synthesizeWithLLM`、`AiImportService._callText`、`SummaryService`、`AiGeneratorLlmGateway.rawCompletion`。这会让 DeepSeek helper requests 自动进入 thinking。

**根因与失败链路。** 全局默认代表昂贵模式，而不是安全的常规请求；调用方无法从构造处判断是否会产生 reasoning token。

**正确行为与推荐修改位置。** 先审计聊天主流程 (`SettingsProvider`、preset persistence、`ChatDependencies`) 是否明确依赖 default true。推荐将 constructor/fromJson missing default 改为 false，使用命名 factories 如 `CompletionParams.narrative()`、`.deepThinking()`，并让主聊天从用户已保存 setting 显式传参；迁移旧 setting 时保留存储的 true，只有缺字段使用兼容策略并记录 rationale。每个 helper 显式 `enableThinking:false`。

**不应采用。** 不要盲改默认后假设主聊天无影响；不要对所有 API 强制禁用用户已选择的深度思考；不要散落 provider-specific bool。

**回归测试与验收。** request-map test 覆盖 DeepSeek/non-DeepSeek；translation/TTS/import/summary/gateway all false；chat main flow keeps persisted true/false; null/fast/deep detail contract remains false/false/true。验收：每个 network call 的 thinking policy 可由构造处读出。

**影响。** DB migration：可能仅需 settings compatibility migration，不更改用户显式值。旧数据：必须保留既有 preference。UI：仅在设置缺省语义变更时提示。LLM/token：短请求显著减少 reasoning token/latency。独立提交：是，`fix: make thinking opt-in for helper requests`。

## 8. Phase E — SceneBatch（独立于单角色 P0）

### P1-10 SceneBatch import semantics

**问题与证据。** `SceneBatchImportRequest` 没有 `generationMode`；`generateSceneBatchCharacters` 以一个 `items` 巨型 JSON 和固定 8192 output tokens 生成所有选中卡；`SceneBatchImportUseCase.importSelected` 用 `selectedNames.contains(item['name']?.toString().trim())` 严格完全匹配过滤。模型轻微改名、别名、附职业就会把可用结果过滤为空。每张资料可请求 3000/5000 字，多个角色总输出与单请求 token budget 本身矛盾。

**范围声明。** 这不是此前“单角色约 60 次仅成功约 1 次”的根因；单角色 P0 已走独立 detailed stage path。SceneBatch 必须独立设计和验收，不能把其失败归咎于 P0 Stage2。

**正确行为与推荐修改位置。** 请求层加入 `generationMode` 并传到 gateway；识别阶段输出 stable candidate IDs、原文 spans 和 canonical display name，生成结果回传 `candidateId`，保存按 ID 而非模型 name 关联。按角色逐个或小批次生成（根据 token budget planner 分组），每个 card 有独立 structured validation/retry和结果报告；若暂时保留 batch，限制 selected count/总字符预算并在 UI 前置显示。每卡 length rule 必须由 aggregate token planner 可实现。

**不应采用。** 不要 fuzzy-match 后悄悄绑定错误角色；不要简单提高 maxTokens；不要将无 `generationMode` 的默认 implicit thinking 当作产品策略。

**回归测试与验收。** name 改写/空白/别名仍凭 candidateId 保存正确卡；N cards 在 output budget 内分批；单卡失败不阻止其他卡且报告失败；generation mode reaches gateway；总字数约束与 token plan consistent。验收：每个 confirmed candidate 有 success/failure outcome，绝不因 strict name mismatch 静默丢失。

**影响。** DB migration：否（candidate ID 只在 request/result transient contract）。旧数据：无。UI：显示 per-card progress/outcome。LLM/token：从一次巨型请求改为受预算的小批/单卡，成本可预测。独立提交：是，`fix: harden scene batch import semantics`。

## 9. 为什么此前 P0 会反复修复失败

1. shared mutable state 让 generation/load 的时间顺序成为隐式输入；
2. parser contract 分裂，DB、PNG、JSON、AI 路径对同一字段假设不同；
3. schema 与 consumer 类型/shape 不一致，导致 validator pass 后仍失败或静默丢字段；
4. transport/content/no-progress retry 职责重叠且 attempts 语义不清；
5. UI 直接做持久化和领域装配，异常边界难以完整覆盖；
6. 同一数据有重复 parser，修一个入口不等于修其余入口；
7. 测试偏 happy path 或 helper，未模拟真实 `LLMStreamResult` truncate metadata、throwing repositories、reverse completion order、malformed persisted type；
8. 本地 test 结果没有 GitHub CI/required checks 的独立验证。

## 10. Phase F — CI regression gate（本轮不创建 workflow）

未来新增 `.github/workflows/ci.yml`，在 push 和 pull request 执行：

1. `dart format --output=none --set-exit-if-changed .`
2. `flutter analyze`
3. P0 targeted suites（detailed character, structured JSON/retry, Wizard start/load, poisoned resources）
4. `flutter test`
5. Android compile/build smoke（例如 `flutter build apk --debug`，配缓存和合理 timeout）

将该 workflow 配置为 main required check，并在 branch protection 开启 review/required status checks。CI 引入前，任何“本地通过”都只可作为候选证据，不能视为合并门禁。

## 11. 分阶段实施顺序与提交建议

1. `fix: harden adventure start exception boundary`
2. `fix: reject incomplete structured model responses`
3. `fix: normalize detailed character stage payloads`
4. `fix: clarify transport and content retry budgets`
5. `refactor: unify character card parsing`
6. `fix: tolerate legacy persisted resource payloads`
7. `fix: serialize adventure asset loading state`
8. `fix: make thinking opt-in for helper requests`
9. `fix: harden scene batch import semantics`
10. `ci: add flutter regression quality gate`

每个提交必须只含一个可验证行为，携带相应 regression test，先运行定向测试再运行 analyze/full suite；任何持久化变更都先写读取兼容测试。不要把 P1 parser/concurrency/SceneBatch 与 P0 generator 修复混入同一个 commit。

## 12. Regression test matrix

| Area | Must prove |
| --- | --- |
| Wizard start | 五类前置/最终异常都复位 submitting，可重试且错误可见 |
| Structured output | `length/maxTokens + incomplete` 必 retry；completed valid repair 可 canonicalize |
| Stage DTO | scalar-type matrix、aliases、nested profile normalize、only failing stage reruns |
| Retry | attempts/retries 精确计数、429/backoff、timeout/5xx/cancel、budget upper bound |
| Character parser | PNG/JSON/DB/AI fixture matrix 的一致 card/warning |
| Persisted models | numeric string、mixed lists、wrong maps、坏行与好行共存 |
| Load concurrency | A/B reverse completion、single-flight、force refresh、per-type errors |
| Thinking | helper explicit false；chat persisted setting preserved；detail false/false/true |
| SceneBatch | candidate IDs、改名不丢、per-card outcome、budget batching |
| UI | Wizard error/partial/empty at 320/360/390/412，`takeException()==null` |

## 13. Risk / rollback strategy

- 先增加 characterization tests，再变更 parser/retry behavior；每个 commit 可单独 revert。
- 绝不清空 SQLite 或删除坏资源；tolerant read 只扩大可读性。若未来写回 canonical data，必须有幂等 transaction、备份/rollback 策略。
- retry policy 改动先记录真实 attempt metrics，限制每个 user action 的最大请求数；429 尊重 server retry-after。
- thinking default 改动采用 stored-setting compatibility 测试和 staged rollout，防止改写用户偏好。
- SceneBatch 使用 candidateId 前需保持旧 name-only result 的明确 fallback/warning，不能 silent remap。

## 14. Definition of Done

P0 closure requires:

- `_handleStart` 任意失败均恢复 submitting；
- `length/maxTokens` structured output 不会被错误视为成功；
- schema validator、normalizer、assembler 类型完全一致；
- Stage2B 仅有一种 canonical payload；
- transport/content retry 语义明确且有界；
- 单角色 Stage1→2A→2B 顺序不回归；
- null/fast 不开启 thinking；
- poisoned character row 不影响其他资产；
- worldview/character/NPC 继续独立加载；
- P0 regression、`flutter analyze`、`flutter test` 和 Android smoke 全部通过。

Project hardening additionally requires:

- legacy persisted JSON 有统一兼容策略；
- 不再有明显重复的 CharacterCard parser contract；
- AdventureSetupController 并发策略已实现并覆盖测试；
- thinking 成为 explicit opt-in，或有书面且测试化的例外；
- SceneBatch 独立完成；
- GitHub CI 与 required checks 可阻止上述回归。
