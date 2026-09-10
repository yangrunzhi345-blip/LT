# LT P0 接管审计与修复规格

## 1. 当前 Git 状态

- HEAD：`e8c9e9c docs: define agent context and handoff workflow`
- `origin/main`：`d86e695 feat: add fast resource import generation modes`
- 前 P0 commit：`4df1f33 fix: stage-only bounded retry, persistent session messages, and detailed worldview validation`
- 分支：`main`
- Dirty：51 个已修改文件，无未跟踪文件；`git diff --check` 无 whitespace 错误。
- `CODEBUDDY.md`：不存在。
- 风险：working tree 同时含 P0 候选 hunk、大量纯格式化/UI 用户修改，且 P0 候选已造成至少两处编译级问题，不能整体覆盖或直接提交。

三层基线：

- A `origin/main → 4df1f33`：P0 前任修改生成器、详细角色协调器、schema validator。
- B `4df1f33 → e8c9e9c`：仅 `AGENTS.md` 协作规范。
- C 当前 working tree：51 文件、1261 additions / 1013 deletions；只有少量是 P0 语义相关。

当前 51 个 dirty 文件均为既有工作区状态。执行 Agent 必须按 hunk 保护这些修改，严禁整体 `reset`、`restore`、`checkout`、`clean` 或覆盖它们。

## 2. 已确认 Blocker

### B1：当前 P0 dirty 状态无法编译

- 根因：`AiGeneratorService` 的 instance `sessionMessages` 已被 dirty hunk 删除，但世界观 massive 模式仍在 `ai_generator_service.dart:543,551` 调用 `sessionMessages.add(...)`。
- 文件/函数：`lib/services/ai_generator_service.dart`，`textToDetailedWorldviewMultiTurn`。
- 当前错误行为：未定义标识符，编译失败。
- 正确目标：世界观和详细角色都使用每一 stage 独立、不可变的 message snapshot；后续 stage 显式接收确认过的前序结果。不得恢复 instance mutable state。
- 验收：无 `sessionMessages` instance 字段或悬挂引用；分析通过；Stage2B 输入仅含 system、已确认 assistant JSON、当前 user prompt。

另：`lib/models/character_card.dart` dirty hunk 删除了 `dart:typed_data`，但文件仍使用 `Uint8List`，同样会编译失败。必须恢复该 import；不要用 `flutter/foundation.dart` 替代。

### B2：Adventure asset loading 仍为一体式失败

- 根因：`AdventureSetupController.loadInitialData()` 对 worldview、character、NPC 三类资源使用一个大 `try/catch`。
- 文件/函数：`lib/controllers/adventure_setup_controller.dart:95`；Wizard `_loadData()`。
- 当前错误行为：任一加载或 character row 解析失败，后续类型不加载；仅暴露通用 `_error`，Wizard 又吞掉错误，只结束 loading。
- 正确目标：三类独立加载、独立保存 data/error；一个类型失败不能阻断其余两类。
- 验收：2 worldview、2 valid character、1 malformed character、2 NPC 时分别得到 `2 / 2 / 2`；character error 可见且页面仍可选择可用资源。

### B3：poisoned CharacterCard row 仍可拖垮整个列表

- 根因：`CharacterCardEntry.fromRow()` 仅捕获 `jsonDecode`；之后无保护地调用 `CharacterCard.fromJson(raw)`。而 `CharacterCard.fromJson` 对历史脏类型仍有多处强转/`cast<String>()`。
- 文件/函数：`lib/models/character_card_entry.dart:78`，`lib/models/character_card.dart:136`，以及 controller 的 `characterCardEntries`/`scopedCharacterCardEntries`。
- 当前错误行为：JSON 虽可 decode，但 `data`、`world_profile`、`alternate_greetings`、`tags` 或自定义属性类型异常时仍可能 throw，整个 `.map(...).toList()` 失败。
- 正确目标：单条持久化旧数据异常必须被隔离；保留可展示的 row id/name 和安全默认 card，或在 controller 层过滤并记录该 row，不得中断其他卡片。
- 验收：一条 malformed row 与两条有效 row 共存时，有效两条仍返回且可在 Wizard 使用；不会抛异常。

## 3. 已确认 Major

### M1：Guard 与详细角色 Prompt 合同不匹配

- 根因：Guard 的 `roleplayBehavior` 要求 `scenario`、`first_mes`、`mes_example` 中至少两个非空字段、总计至少 180 字；补全 prompt 仅写“给出 `scenario`、`first_mes` 或 `mes_example`”，没有数量和长度约束。
- 文件/函数：`character_card_generation_guard.dart`；`ai_generator_service.dart:1756` 附近的 supplement prompt。
- 当前错误行为：模型自然遵循“或”只返回一个字段，必然被 Guard 判薄弱，造成额外请求甚至 no-progress。
- 正确目标：Prompt 明确要求至少两个 RP 字段，合计至少 180 个有效字符；优先返回全部三个。
- 验收：遵守 Prompt 的 fake response 一次补全可通过 `roleplayBehavior`，不会因字段合同本身重试。

### M2：Schema validator 的 P0 方向已正确，但当前未被测试保护

- 当前状态：dirty `StageSchemaValidator` 已改为稳定 enum、unknown stage 返回 false，且 `_runCharacterStage()` 已接入详细角色生产路径。
- 正确目标：保留 enum API；只重试当前 stage；Stage2B schema 失败不得重跑 Stage1/2A。
- 验收：Stage1/Stage2A/Stage2B 调用次数为 `1/1/2`，Stage2B 第二次仍能看到 Stage1 + Stage2A。

### M3：JSON recovery 候选实现方向正确，但缺少边界测试

- 当前状态：dirty `_resolveContent(expectJsonObject: true)` 会将 repair 后 Map `jsonEncode` 成规范 JSON；详细角色 stage 和 supplement 已启用该模式。
- 正确目标：empty、无效 JSON、可修复 truncated JSON 均有确定行为；可修复结果必须返回 canonical JSON，不得泄漏 damaged original。
- 验收：truncated 输入返回值可再次 `jsonDecode`；empty/不可修复 JSON 按 stage retry；取消不 retry。

### M4：Wizard 没有 empty/error/partial-success 区分 UI

- 根因：Wizard 只有全局 `_loading`，`_loadData()` catch 后直接结束 loading。
- 文件：`adventure_wizard_screen.dart:55-245`。
- 当前错误行为：全部空、单类失败、部分成功在 UI 上没有不同状态，也无法告诉用户哪些资源仍可用。
- 正确目标：分别呈现各类资源的 empty、error、partial success；不改无关 Wizard 流程。
- 验收：character 失败而 worldview/NPC 成功时，成功区仍可选择，character 区显示可理解错误与空态。

## 4. 已通过、无需再改

- `DetailedCharacterGenerationCoordinator` 的 no-progress 行为应冻结：每个 supplement round 最多初始请求 + 2 次无进展补试；仍无有效字符增长则抛 `CharacterGenerationNoProgressException`。实现逻辑正确。
- dirty 的详细角色 Stage2 已是 `Stage1 → Stage2A → Stage2B`，并以 `confirmedResults: [t1Data, t2aData]` 向 Stage2B 注入上下文；应保留这个设计。
- `_callText` 与 `_callMessages` 当前均为 `generationMode == deepThinking` 才启用 thinking，满足：null=false、fast=false、deepThinking=true。
- `_runCharacterStage()` 对 `GenerationCancelledException` rethrow，避免 stage retry 吞掉取消；应保留。

## 5. 前任实现处理意见

| 前任设计 | 处理 | 说明 |
|---|---|---|
| instance mutable `sessionMessages` | REMOVE | 共享跨请求状态会串话、并发污染。 |
| 每轮 reset 只保留 system prompt | REMOVE | 既丢失确认上下文，又不能解决共享可变状态。 |
| 原 `StageSchemaValidator(String stageName)` | REWORK | 中文 label 不匹配真实“外貌与体态/背景与深层设定”，unknown 默认 true。采用当前 enum 方向。 |
| 世界观 helper 对无效/未知 schema retry | REMOVE | character schema 不应套到世界观；此前 unknown 自动 true，逻辑无效。 |
| 世界观 Prompt 混入 `scenario/first_mes/mes_example` | REMOVE | 与世界观 schema 无关；当前 dirty 已移除。 |
| retry off-by-one | REWORK | 前任 `attempt > max + 1` 实际可多出一次调用；使用明确 `for (extra = 0; extra <= maxExtra; extra++)`。 |
| 取消异常被 world helper 广泛 catch 后 retry | REMOVE | 取消必须即时传播。 |
| `_callText/_callMessages` thinking 语义 | KEEP 当前 dirty 方向 | 两个路径已一致，补生产路径测试。 |
| no-progress bounded retry | KEEP | 逻辑正确，仅补精确调用次数测试。 |

## 6. Dirty Worktree 分类

### P0-GEN

- `lib/services/ai_generator_service.dart`
- `lib/services/stage_schema_validator.dart`

### P0-PARSE

- 无纯净文件。

### P0-LOAD

- 无；所需 controller/Wizard 修改尚未开始。

### P0-UI

- 无；所需 Wizard empty/error/partial UI 尚未开始。

### P0-TEST

- 无有效 P0 测试 hunk；现有 dirty test 改动均为无关格式化。

### MIXED

- `lib/models/character_card.dart`
  - P0 区域：`CharacterCard.fromJson` 的旧数据类型兼容。
  - 必须保护/清理：不要保留删除 `dart:typed_data` 的 hunk；不要把 PNG debug logging、空行和纯格式化混入 P0。
- `lib/models/character_card_entry.dart`
  - P0 区域：`fromRow` 的 malformed row 隔离。
  - 必须保护/清理：现有改动只是日志替换，未修复后续 `CharacterCard.fromJson` throw；必须做真正的隔离，不要仅扩大日志。

### UNRELATED-DIRTY

- `lib/application/prompt_policies/adventure_context_policy.dart`
- `lib/controllers/resource_card_import_controller.dart`
- `lib/core/theme/app_theme.dart`
- `lib/core/widgets/app_dropdown.dart`
- `lib/core/widgets/app_empty_state.dart`
- `lib/core/widgets/app_text_field.dart`
- `lib/core/widgets/custom_attribute_editor_section.dart`
- `lib/data/worldview_knowledge.dart`
- `lib/engines/chat_engine_internals/summary_service.dart`
- `lib/features/adventure/presentation/home/screens/adventure_dashboard_screen.dart`
- `lib/features/adventure/presentation/home/widgets/dashboard_action_cards.dart`
- `lib/features/adventure/presentation/home/widgets/dashboard_hero_header.dart`
- `lib/features/adventure/presentation/session/screens/adventure_session_screen.dart`
- `lib/features/adventure/presentation/session/widgets/action_options_panel.dart`
- `lib/features/adventure/presentation/session/widgets/session_message_list.dart`
- `lib/features/adventure/presentation/templates/screens/preset_scenes_screen.dart`
- `lib/features/prompt_settings/presentation/screens/prompt_settings_screen.dart`
- `lib/features/prompt_settings/presentation/widgets/prompt_preview_modal.dart`
- `lib/features/settings/presentation/screens/settings_screen.dart`
- `lib/features/settings/presentation/widgets/appearance_section.dart`
- `lib/features/settings/presentation/widgets/data_management_section.dart`
- `lib/features/settings/presentation/widgets/model_params_section.dart`
- `lib/features/settings/presentation/widgets/provider_config_section.dart`
- `lib/models/adventure_response.dart`
- `lib/models/custom_attribute_item.dart`
- `lib/models/model_context_capability.dart`
- `lib/screens/chat/widgets/character_sheet.dart`
- `lib/screens/chat/widgets/chat_dialogs.dart`
- `lib/screens/chat/widgets/message_bubble.dart`
- `lib/screens/chat/widgets/scene_character_manager.dart`
- `lib/screens/chat/widgets/status_dropdown.dart`
- `lib/screens/chat/widgets/status_toast.dart`
- `lib/screens/chat_screen.dart`
- `lib/screens/resource_library/npc_edit_page.dart`
- `lib/services/api_error.dart`
- `lib/services/llm_service.dart`
- `lib/widgets/adventure_message_card.dart`
- `lib/widgets/app_dialogs.dart`
- `lib/widgets/main_sidebar.dart`
- `test/unit/deepseek_reasoning_test.dart`
- `test/unit/resource_import_semantics_test.dart`
- `test/unit/riverpod_and_providers_test.dart`
- `test/widget/app_dropdown_test.dart`
- `test/widget/custom_attribute_test.dart`
- `test/widget/session_message_list_scroll_test.dart`
- `test/widget/settings_feature_test.dart`
- `test/widget/ui_screens_and_sidebar_test.dart`

## 7. 下一执行 Agent 的修改顺序

1. **先修 P0 dirty 编译断点**：清除世界观悬挂 `sessionMessages` 引用、恢复 `dart:typed_data`；不接触 unrelated hunk。
2. **Stage2 与 schema retry**：保留 detailed character 的不可变 snapshot 顺序；完成 enum schema、stage-only retry、取消传播。
3. **JSON / thinking**：统一 `_resolveContent` contract；补 canonical repair、empty、truncated、参数语义测试。
4. **Guard / Prompt**：让 supplement prompt 明确满足至少两个 RP 字段和 180 字门槛。
5. **poisoned row**：从 entry/controller 到 `CharacterCard.fromJson` 建立单条失败隔离。
6. **Wizard load isolation**：controller 三类独立 data/error，再接 Wizard。
7. **Wizard UI**：最小化显示 empty/error/partial success；加入 320px viewport widget 回归。
8. **定向测试、analyze、完整 diff 审查**：最后才决定是否适合提交；不得覆盖 unrelated dirty 文件。

依赖：1 是所有验证前提；2-4 是生成 P0；5 与 6 共同决定 Wizard partial 成功；7 依赖 6；8 依赖全部。

## 8. 测试验收矩阵

| 问题 | 现有覆盖 | 必补测试 | 预期 |
|---|---|---|---|
| Stage1→2A→2B | 假覆盖：旧测试仍断言 parallel message 长度 | production fake LLM 记录消息 | 严格顺序，2B 含 1+2A |
| 2B schema retry | 未覆盖 | 返回错误 schema 后正确 schema | 调用 `1/1/2` |
| empty JSON | 未覆盖 | stage 返回空字符串后正确结果 | 仅当前 stage retry |
| truncated repair | 部分/假覆盖 | 断言返回文本可 `jsonDecode` | canonical JSON |
| null/fast/deepThinking | 部分：只测 `CompletionParams` | 捕获 `_callText`、`_callMessages` params | `false/false/true` |
| Guard/Prompt | Guard 部分覆盖 | prompt contract + generated supplement | 至少两字段、≥180 字 |
| no-progress | 部分覆盖 | 计数 no-growth 请求 | 总 3 次后抛异常 |
| poisoned row | 未覆盖 | 2 valid + 1 malformed row | 2 valid 保留，无 throw |
| Wizard 资源隔离 | 未覆盖 | 2 worldview + 2 valid char + 1 malformed + 2 NPC | `2/2/2`，有 character error |
| Wizard UI | 未覆盖 | 320×568、360×640、390×844、412×915 | empty/error/partial 分别可见，无 exception |

## 9. 禁止范围

禁止下一执行 Agent：

- P1、SceneBatch、Runtime State Versioning。
- 无关 Adventure Session、聊天、设置、主题、Dropdown、Sidebar 重构。
- 覆盖、格式化、删除或合并现有 unrelated dirty 用户修改。
- Git 历史修复、fetch、reset、restore、checkout、clean、stash、rebase、push。
- 为解决 malformed row 而清空数据库、删除用户卡片或降低既有测试。

## 10. 可直接复制给执行 Agent 的任务摘要

在 `main`、HEAD `e8c9e9c` 上处理 P0；先阅读 `AGENTS.md`，仓库没有 `CODEBUDDY.md`。严禁覆盖当前 51 个 dirty 文件中的无关用户修改，也不要处理 P1/SceneBatch/Runtime State Versioning、聊天/设置/主题/UI 重构或 Git 历史。

P0 范围仅限：`ai_generator_service.dart`、`stage_schema_validator.dart`、`detailed_character_generation_coordinator.dart`、`character_card.dart`、`character_card_entry.dart`、`adventure_setup_controller.dart`、Adventure Wizard 及对应定向测试。

先修当前 dirty 编译断点：世界观 massive 路径仍引用已经删除的 `sessionMessages`；`character_card.dart` 删除了仍需的 `dart:typed_data`。不要恢复 instance mutable `sessionMessages`。详细角色正确设计是 Stage1→Stage2A→Stage2B；每次调用使用不可变消息快照，Stage2B 输入必须含 Stage1 和 Stage2A assistant JSON。Schema 使用 `CharacterGenerationStage` enum，unknown 必须失败，错误 schema 只重试当前 stage；取消直接传播。保留 no-progress 的每轮最多三次 supplement 请求。`_callText/_callMessages` 的 thinking 必须为 null=false、fast=false、deepThinking=true。JSON structured path 必须将 repair 后结果返回为可再次 `jsonDecode` 的 canonical JSON。

修正 supplement Prompt：明确要求 `scenario/first_mes/mes_example` 至少两项，合计至少 180 字，以满足 Guard。处理 poisoned row：单条旧卡 JSON/type 异常不能令整个 character list/Wizard 崩溃，保留其他有效卡。

改造 `AdventureSetupController.loadInitialData` 为 worldview、character、NPC 分别加载和存储 error/data；Wizard 显示 empty、error、partial-success，不吞错误。加入生产路径测试：stage 次序、2B schema `1/1/2`、empty、truncated canonical JSON、thinking 三态、Guard/Prompt、no-progress 三次、poisoned row、以及 `2 worldview + 2 valid character + 1 malformed + 2 NPC => 2/2/2`。Wizard widget 测试至少覆盖 320px 与常见手机宽度，无 overflow/exception。
