# DeepSeek V4.1 Flash 适配（Phase 1：Model Capability 与任务语义）

- 基线：`main` @ `089ee6a8d5921d4609054fd995fb579537dcbb0e`
  （执行前已 `git fetch`，该 commit 即当时 `origin/main` 最新）
- 交付 HEAD：`9c9a02efa2c32c429360f7838f4e21d9c885081c`
- 外部确认：2026-09-10 DeepSeek 发布 V4.1 Flash，模型名 `deepseek-flash`；
  `deepseek-v4-flash` / `deepseek-v4-flash-vision-exp` 为兼容路由；V4 Pro 进入淘汰。
  本报告的模型能力数值以任务给定的 V4.1 Flash API 规范为准。

## 一、本次解决的架构问题

1. **模型名硬编码**：默认模型、在服列表、等级文案、thinking 判断分散在
   `LLMProvider`、`AppConfig`、`CompletionParams.toRequestMap`、设置页 UI 与
   `model.contains('deepseek')` 子串判断中，没有单一能力来源。
2. **请求参数无任务语义**：约 30 个调用点各自拼 `CompletionParams`，
   thinking 只由 `generationMode` 或个别硬编码决定，没有 Task→Policy 层。
3. **传输层无法表达协议字段**：`List<Map<String,String>>` 只能表达
   role/content；vision 靠「把 OpenAI content-block 数组序列化成 JSON 字符串再在
   传输层按 `startsWith('[')` 反解」的 hack；reasoning/tool_calls/tool_result 不可表达。
4. **V4.1 采样语义过时**：非思考模式仍发送 `top_p` / 惩罚项，与 V4.1 固定
   `top_p=1.0` 的规范不符。
5. **模型目录与迁移缺失**：旧模型名不会迁移到 `deepseek-flash`；V4 Pro 无法隐藏
   又保留可读（`availableModels.contains` 会把已保存的 V4 Pro 静默重置为默认）。

## 二、Model Capability 设计

新增 `lib/models/model_capabilities.dart`：

- `ThinkingWireStyle { none, deepSeekV41 }`：wire 层 thinking 形态判别。
- `ModelCapabilities`：`modelId / contextWindow / maximumOutputTokens /
  supportsThinking / supportsReasoningEffort / supportsVision / supportsJsonOutput /
  supportsToolCalls / supportsResponsesApi / supportsFIM / supportsPromptCaching /
  supportsFilesApi / thinkingWireStyle / tokenizerType / reasoningTokenPolicy /
  capabilitySource`，以及目录元数据 `selectableInPicker / isDeprecated / pickerSubtitle`。
- `ModelCapabilities.toContextCapability({providerId})`：投影到既有引擎预算记录，
  不改变预算路径。
- `ModelCapabilityRegistry`：内置目录 + alias 解析。
  - `deepseek-flash`：context 1,000,000；max output 384,000；thinking / reasoning effort /
    vision / JSON / tool calls / Responses API / FIM / prompt caching = true；
    Files API = false。
  - `deepseek-v4-pro`：`selectableInPicker=false`、`isDeprecated=true`，limits 为保守占位值
    （128,000 / 65,536）。
  - `deepseek-v4-flash` / `deepseek-v4-flash-vision-exp`：alias，`resolve` 归一到 flash。
  - 未知/自定义模型：`conservativeFallback`（8192/1024，`thinkingWireStyle.none`）。
  - `canonicalizeAlias / isLegacyAlias / isKnownBuiltIn / pickerModels / knownModelIds`。

替换点：`CompletionParams.toRequestMap({required ModelCapabilities})`、
`LLMService._capabilities`、`LLMProvider.defaultModel/availableModels/knownModels`
（删除 `supportsThinking` 子串判断）、设置页与会话下拉。

## 三、Task → Model Policy

新增 `lib/models/llm_task.dart`（`LlmTask`、`ThinkingPolicy`、`LlmTaskPolicy`）与
`lib/services/llm_task_policy.dart`（`LlmTaskPolicyTable` + `LlmTaskResolver`）。
调用方声明任务，`resolve(task, capabilities, userParams, maximumOutputTokens,
temperatureOverride, forceJson)` 生成 `CompletionParams`，且从不修改 `userParams`。

| Task | thinking | preferJson | 说明 |
|---|---|---|---|
| adventureNarrative | followUserSetting | 否 | 主 RP 叙事，默认关闭思考 |
| adventurePlanning | followUserSetting | 是 | 预设冒险规划 |
| worldviewFast | followUserSetting | 是 | 简易世界观（接收深度推演开关） |
| worldviewDeep | followUserSetting | 是 | 多阶段世界观 |
| characterFast | followUserSetting | 是 | 简易角色卡（接收深度推演开关） |
| characterDeep | followUserSetting | 是 | 多阶段角色卡 |
| importExtraction | disabled | 是 | AI 导入解析 |
| structuredExtraction | disabled | 是 | NPC/选项/SceneBatch/名称识别等 |
| summary | disabled | 否 | 时间线摘要 |
| translation | disabled | 否 | 翻译 |
| visionExtraction | disabled | 否 | 原生图片理解，detail=high |
| runtimeStateAnalysis | disabled | 是 | 预留（Agent Runtime） |
| narrativeSupplement | disabled | 否 | 补正文 |

已迁移调用点：translation、AI import、timeline summary、
`AiGeneratorService._callText/_callMessages`（注入 `LlmTask`）、
`AiGeneratorLlmGateway.rawCompletion`（新增可选 `task`）、
`ChatEngine._executeAdventureContext`（`ContextTaskType → LlmTask`）、vision。

**保留的显式 override**（其 thinking 已与策略一致，属确定性修复子请求，文档化例外）：
`LLMService.testConnection`、`TtsService`、`_optionRepairParams`（选项修复）、
`NarrativeLengthGuard.supplementParams`（补正文，等价于 `narrativeSupplement`）。

## 四、Thinking 策略

- 所有请求显式决定 thinking，不依赖服务端默认值。
- 辅助任务（翻译、清洗、JSON 抽取、导入、摘要、格式转换、简单视觉、连接测试、补正文）恒为 disabled。
- 普通 Adventure RP 默认 disabled；深度推演由既有开关（followUserSetting）开启。
- 开启时发送 `thinking:{type:'enabled'}` + `reasoning_effort`，且不发送采样参数。
- 关闭时发送 `thinking:{type:'disabled'}` + 仅 `temperature`。
- `reasoning_effort` 仅在 `supportsReasoningEffort` 时透传。

## 五、Context / Cache 策略

- 能力层记录物理上限 1M / 384K，**不**据此扩大业务上下文；引擎软预算保持原值，
  待 benchmark 后再定（见剩余风险）。
- 新增 prompt 组装确定性守卫测试：同输入必须产生逐字节一致的 messages，且稳定前缀
  不得嵌入 `requestId` 等逐请求标记，保护 DeepSeek 前缀缓存复用。
- 未做（延后）：修正世界事实打分排序的不稳定 tie-break
  （`narrative_context.dart:280`）与 runtime 实体 `ORDER BY updated_at DESC`
  （`adventure_repository_impl.dart:86`）导致的前缀漂移；缓存命中率遥测。

## 六、Adventure 协议策略（未改动）

保持既有分层与安全边界：`AdventureResponse.parse/canonicalize`、payload-only recovery、
damaged JSON 处理、流式 JSON 隐藏、开场选项校验、bounded retry 全部保留，
且**未**将 Adventure 改为 JSON Mode。模型输出仍必须经本地 parser → schema/semantic
校验 → `RuntimeStateCommitDraft` → 事务提交边界，模型不能直接写库。

## 七、Vision 策略

- 删除 `LLMService` 中 `startsWith('[')` 反解 hack；vision 改用
  `LlmMessage.userWithImages` + `LlmImagePart`。
- `image/jpeg` data URI 由 `LlmImagePart` 生成；文本 part 仍经 `sanitizeForJson`。
- 按任务下发 `detail`（`visionExtraction` → `high`，密集文字/截图场景）。
- 视觉抽取恒为非思考。

## 八、JSON Output 策略

- 由任务策略声明（`preferJsonOutput`）而非 `prompt.contains('json')` 猜测；
  仅在 `supportsJsonOutput` 时下发 `response_format={"type":"json_object"}`。
- 保留 prompt 中出现 `json` 的既有约束与 `forceJson` 覆盖，行为向后兼容。
- JSON Mode 仅代表合法 JSON，仍走 decode → schema validation → semantic validation →
  stable ID 校验后才进入领域层（未改动）。

## 九、Tool / Agent 兼容策略

- 新增 typed transport `lib/models/llm_message.dart`：`LlmRole`、sealed `LlmContentPart`
  （`LlmTextPart` / `LlmImagePart`）、`LlmToolCall`、`LlmMessage`
  （`reasoningContent / toolCalls / toolCallId / name`）、`LlmMessageAdapter`。
- `toWireMap({includeReasoningContent})`：文本消息仍输出 String content（向后兼容），
  图片消息输出 content-block 数组，tool 字段按需输出；Thinking+tools 的
  reasoning_content 回传为显式 opt-in，为后续 Agent Runtime 预留。
- `LLMService` 新增 `sendMessageStreamTyped` / `sendMessageStreamDetailedTyped`；
  旧字符串方法经 adapter 委托，保留 `sendMessageStreamDetailed` 覆写接缝，
  生产者可渐进迁移。
- 未实现：工具调用运行时、Responses API adapter（含其无状态限制）、
  真实 `tools` / `tool_choice` 往返。

## 十、修改文件

新增：
`lib/models/model_capabilities.dart`、`lib/models/llm_task.dart`、
`lib/models/llm_message.dart`、`lib/services/llm_task_policy.dart`、
`test/unit/model_capability_registry_test.dart`、`test/unit/llm_task_policy_test.dart`、
`test/unit/llm_message_transport_test.dart`、`test/unit/model_alias_migration_test.dart`、
`test/widget/model_picker_catalog_test.dart`。

修改：
`lib/models/completion_params.dart`、`lib/models/llm_provider.dart`、
`lib/config/app_config.dart`、`lib/services/llm_service.dart`、
`lib/services/ai_generator_service.dart`、`lib/services/ai_import_service.dart`、
`lib/services/translation_service.dart`、
`lib/engines/chat_engine.dart`、
`lib/engines/chat_engine_internals/summary_service.dart`、
`lib/application/llm/llm_gateway.dart`、
`lib/application/llm/ai_generator_llm_gateway.dart`、
`lib/application/adventure/adventure_ai_use_case.dart`、
`lib/providers/settings_provider.dart`、
`lib/features/settings/presentation/widgets/provider_config_section.dart`、
`lib/features/settings/presentation/widgets/model_params_section.dart`、
`lib/features/adventure/presentation/session/widgets/session_app_bar.dart`。

测试更新：`deepseek_reasoning_test`、`llm_helper_thinking_policy_test`、
`chat_engine_and_prompt_test` 及 5 个 `p0_*` / 角色卡语义测试（fixture 模型名改为
真实 `deepseek-flash`，因为 thinking 现由能力门控）。

## 十一、迁移（非破坏性）

`SettingsProvider` 加载时：
- 旧 alias `deepseek-v4-flash` / `deepseek-v4-flash-vision-exp` → 归一为 `deepseek-flash`；
- `recent_models` 归一、去重、限 5；
- `deepseek-v4-pro` 保留可读取（`isKnownBuiltIn`），仅从选择器隐藏；
- 自定义提供商模型名不触碰；
- 仅在存储值确实变化时批量写回（幂等，不覆盖未变化的用户选择）。

## 十二、测试与验收结果

验收命令（本机 Linux，全部通过）：

| 命令 | 结果 |
|---|---|
| `dart format --output=none --set-exit-if-changed .` | `283 files (0 changed)`，exit 0 |
| `flutter analyze` | `No issues found!` |
| `flutter test --reporter compact` | `+381: All tests passed!`（381 项） |

新增覆盖：默认模型 `deepseek-flash`、flash/vision-exp alias 迁移、V4 Pro legacy 可读且隐藏、
V4.1 capability（1M/384K/vision/json/tools/thinking）、thinking on/off 参数映射（非思考不含 top_p/惩罚）、
辅助任务强制非思考、Task→Policy 解析、typed message 往返（text/reasoning/toolCalls/toolCallId/toolResult/image）、
JSON 选择、prompt 确定性、Adventure JSON 不泄漏与 payload recovery（原有用例保持通过）。

Commit（`089ee6a..9c9a02e`，9 个）：

```
1133eaf feat(models): add ModelCapabilities + ModelCapabilityRegistry
5f7faeb refactor(llm): drive request params from model capabilities
01663ff feat(llm): typed message transport and typed vision input
5ca94e8 fix(llm): keep sendMessageStream on the legacy override seam
80ef5e7 feat(settings): model catalog, flash alias migration, hidden legacy v4-pro
7f04000 feat(llm): add Task→Model policy layer and migrate helper call sites
4180151 refactor(adventure): route narrative and vision through the task policy
453de9a feat(settings): V4.1 model picker labels and hidden legacy selection
9c9a02e test: default Adventure RP to non-thinking and guard prompt determinism
```

`git status`：仅剩任务开始前已存在的 7 个 `docs/` 修改（用户原有工作，未触碰）；
本任务未产生额外未跟踪文件。

## 十三、剩余风险与延后项

1. **上下文软预算未重适配**：注册表记录 1M/384K，但 `ModelContextCapability`
   仍为保守业务上限（`messaging_provider.dart` 32768）。64K/128K/256K/+ 的
   TTFT、总耗时、缓存命中率、剧情一致性、状态正确率、成本 benchmark 尚未执行，
   业务软限制保持不变。
2. **无真实 API 集成验证**：全部为单元/Widget 测试，未对线上 `deepseek-flash`
   发请求。`thinking:{type:...}` 顶层形态沿用既有契约；若服务端要求
   `extra_body` 包裹需调整。`LlmImagePart.detail='high'` 未经线上验证。
3. **缓存顺序未治理**：世界事实不稳定排序与 runtime `updated_at DESC` 会使长
   Adventure 前缀漂移，削弱缓存命中，属延后项。
4. **遥测未扩展**：`prompt_cache_hit_tokens` 等已在 `LLMStreamResult` 解析但未被消费/
   持久化；reasoning tokens、latency、TTFT、retry count 未新增。
5. **Responses API / Tool Calls / Agent Runtime**：仅建立 typed 表达能力，未实现运行时。
6. **`deepseek-v4-pro`**：capability 值为保守占位（隐藏/淘汰模型）。
7. **默认思考翻转**：无持久化参数的既有用户将从思考模式切到非思考（符合 V4.1 使用
   指引与低延迟目标，属有意行为变更）；带持久化参数的用户保持原选择。
8. **`runtimeStateAnalysis`**：任务已声明但暂无调用点，预留给后续 Agent Runtime。
9. **显式 override**：`_optionRepairParams`、`supplementParams`、TTS、连接测试未走
   resolver（thinking 已与策略一致，文档化例外）。
