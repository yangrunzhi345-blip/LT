# P0：检测状态可靠性 + 叙事节奏控制 — 分析与改动方案

> **文档编号**：`P0_STATUS_AND_NARRATIVE`
> **基线**：`main` @ `ac4e6e5`（v1.1.10）
> **范围**：自定义检测状态链路、提示词叙事规则
> **不在本次范围**：Runtime Entity Overlay 迁移（评估见第 4 节，作为 P1 立项）

---

## 1. 当前流程

### 1.1 状态链路（写入）

```
AI 输出 custom_status_changes
  → AdventureResponse.parse                 (lib/models/adventure_response.dart:180)
    → AdventureResponse.fromJson             (:99)   ← JSON 负载 → 模型对象
      → CustomStatusChange.parse             (lib/models/custom_status_change.dart:28)
  → ChatEngine._applySplitResponse           (lib/engines/chat_engine.dart:241)   ← 只暂存，不改状态
  → _pendingCustomStatusChanges
  → ChatEngine._projectPendingCustomStatus   (:1195)  ← 纯函数投影
    → CustomStatusMerger.applyChanges        (lib/services/custom_status_merger.dart:31)
  → ChatEngine._commitPendingCustomStatus    (:1299)  ← 先清空 pending 再写
  → AdventureProvider.updateAdventureConfig  (lib/providers/adventure_provider.dart:311)
    → AdventureRuntimeStateResolver.baselineForPersistence
  → adventures.config (TEXT)                 (lib/services/repositories/adventure_repository_impl.dart:203)
```

原子性由 `SceneDialogueCommit` 保证：解析阶段零副作用，状态只在提交阶段结算一次
（`adventure_turn_commit_atomicity_test.dart` 覆盖了选项修复失败/取消/重试路径）。

### 1.2 状态链路（读取）— 有两个读取源

| UI | 数据来源 |
|---|---|
| `AdventureMessageCard`（消息内「监测状态」卡片） | 消息正文里内嵌的 `custom_status` 快照，由 `_normalizeCustomStatusInAiContent`（`chat_engine.dart:1780`）/ `_injectOptionsIntoAiContent`（`:1716`）写入 |
| `CharacterStatusScreen`（角色状态面板） | `chat.adventureConfig` → `AdventureProvider.adventureConfig`（叠加 Runtime Overlay 后的有效值） |

两者只在 `_normalizeCustomStatusInAiContent` 成功时保持一致；任一环节静默失败都会让同一轮出现
「卡片新值 / 面板旧值」或反之。

### 1.3 诊断落盘

`SceneDialogueCommit.diagnostics` → `scene_dialogue_turns.diagnostics_json`
（`adventure_repository_impl.dart:544`）。本次新增的 `status_diagnostics` 走同一通道。

### 1.4 提示词组装顺序

```
PromptBuilder.buildMessages            (chat_engine_internals/prompt_builder.dart:23)
  = [customSystemPrompt] + AppConfig.adventurePrompt   (lib/config/app_config.dart:29)
  → PromptCompiler.compile             (application/narrative/prompt_compiler.dart:15)
      追加 角色扮演原则 / 世界硬约束 / 当前场景 / 本轮技术控制(含 controlContext)
```

叙事规则全部是硬编码 Dart 字符串，不入库、不版本化；用户只能**前置**追加
`customSystemPrompt`，无法移除内置规则。

---

## 2. 根因

面板不更新是**两层**原因叠加，只修其中一层都会复发。

### 2.1 层 1：协议无法区分「没变化」与「模型忘了检测」

`custom_status_changes` 的语义是「只输出变化项」（`app_config.dart:144-149` 改后）。模型漏输出、
或输出了文本描述但没给 Delta 时，程序没有任何信号可以区分这两种情况，只能默认「没变化」。

### 2.2 层 2：输出了但在解析/合并阶段被静默丢弃（实际更常见）

| # | 位置 | 失败形态 |
|---|---|---|
| 1 | `custom_status_change.dart:93`（改前） | `delta` + 引号数字（`"3"`）直接判非法 —— 模型极易把数字写成字符串 |
| 2 | `custom_status_change.dart:75-82` | operation 只接受精确 `set`/`delta`；`add`/`SET`/`+5` 全部作废 |
| 3 | `custom_status_merger.dart:_findAttributeIndex`（改前） | `attribute_id` 只与 `attr.id` 比对。提示词同一行里显示了中文名，模型把中文名填进 `attribute_id` → 丢弃 |
| 4 | `custom_status_merger.dart:_matchCharacter`（改前） | 主角无稳定 ID 时提示词给的是字面量 `protagonist`（`app_config.dart:219` 改前），但匹配逻辑只认 `protagonistCharacter.characterId` → 丢弃 |
| 5 | `custom_status_merger.dart:_applyChange` | `delta` 作用于非数值状态时返回 null，只记 `invalid_op:` 一行 `debugPrint` |
| 6 | `adventure_response.dart:486-489`（改前） | `parseCustomStatusChanges` 建了 diagnostics 列表后当场丢弃 |
| 7 | `chat_engine.dart:1175`（改前） | 合并诊断只 `debugPrint`，release 构建里用户与测试都看不到 |
| 8 | 静默「无可见变化」 | 命中上限（`100/100 + 5`）、同值文本 `set` 都不报错，表现为「提交成功但面板没动」 |

### 2.3 叙事节奏的根因

提示词中有 8 处把「一轮」定义成「一个完整故事」，其中最强的一条在
`chat_engine.dart` 的每轮控制上下文里（改前）：

> 叙事结构采用【一波三折·双重波折】：第一波动作与言语试探结束后，严禁草率收笔，
> 必须立刻引出第二重突发变故/隐藏动机爆发与更深入对质，最后才合力破局与沉淀余波！

配套的还有 `app_config.dart` 的「完整的起承转合：入境铺垫、冲突升级、深度对质、破局与余波」、
「直达玩家行动结果」、「推进充足的情节波折与对话回合」，以及分幕流水线第 1 幕要求的
「冲突引入与第一次波折」。模型据此把整幕剧情在一轮内走完。

---

## 3. 改动方案

### 3.1 新增评估协议 `custom_status_evaluations`（兼容旧协议）

```json
{"custom_status_evaluations":[
  {"character_id":"char_proto","attribute_id":"a1","changed":true,
   "operation":"delta","value":5,"reason":"本轮发生积极互动"},
  {"character_id":"char_proto","attribute_id":"a2","changed":false,"reason":"本轮没有相关事件"}]}
```

* 新模型 `lib/models/custom_status_evaluation.dart`，`changed` 宽容解析
  （`true`/`"true"`/`1`/`是`/`有变化` …）；若 `changed` 缺失但带了 `operation`/`value`，推定 `true`。
* `changed=true` 必须落为一次状态变更；无法适用时记诊断（不再静默丢弃）。
* `changed=false` 不得修改状态，也不触发写盘（`_projectPendingCustomStatus` 返回 `config == null`）。
* 协议一旦出现即为**权威来源**：同一目标在两种协议里重复出现时按解析后的目标去重，
  一轮只结算一次；旧版完整快照 `custom_status` 仅在评估协议缺席时才使用。
* 评估列表缺席的追踪状态 → `unevaluated_attribute:<ref>`，这正是「模型忘记检测」的信号。

### 3.2 诊断词表

| 诊断 | 含义 |
|---|---|
| `unknown_character:<ref>` | 角色 id/名称无法定位 |
| `unknown_attribute:<ref>` | 状态 id/名称无法定位 |
| `invalid_operation:<ref>` | operation 非法 |
| `invalid_value:<ref>` / `invalid_delta_value:<ref>` | set/delta 值非法（含 delta 作用于非数值状态） |
| `no_visible_change:<ref>` | 写入被接受但当前值没有实际变化（命中上下限、同值写入） |
| `unevaluated_attribute:<ref>` | 评估协议出现，但该追踪状态整条缺席 |
| `custom_status_evaluations:type/item/limit` | 负载形态/元素/条数问题 |

诊断经 `SceneDialogueCommit.statusDiagnostics` → `SceneDialogueCommitResult.statusDiagnostics`
返回，同时落入 `scene_dialogue_turns.diagnostics_json` 的 `status_diagnostics`。
`CustomStatusEvaluation.maximumEvaluationsPerTurn` 与 `unevaluated` 差集都以 64 为上限，
避免模型返回空数组时刷屏（诊断只进 diagnostics，不面向用户）。

### 3.3 Merger 加固（修掉第 2.2 节的静默丢弃）

* `attribute_id` 未命中 id 时回退匹配 `name`（`_findAttributeIndex`）。
* `character_id == 'protagonist'` 回退到主角（`_matchCharacter`）。
* `delta` 接受引号/带符号数字字符串：`"3"` / `"+3"` / `"-2"`（`CustomStatusChange.parseNumericDelta`）。
* 同目标去重，保证评估 + 旧 Delta 不双结算。
* 无可见变化记 `no_visible_change` 且不覆盖对象。

### 3.4 提示词：Narrative Beat

* `app_config.dart` 在【第一部分】之后、所有档位分支之前插入**最高优先级·互动叙事核心规则**，
  因此 L0~L5 全部生效：一轮 = 一个叙事节拍；禁止一轮完成整个事件；到达需要玩家回应/选择/行动
  的位置必须立即停笔；长篇只能增加环境/心理/对白细节/瞬时信息密度，**不能**增加时间跨度、
  自动完成的事件数量或结局；约会/初次见面/谈判/探索未知地点/重要剧情节点进一步压低自动推进。
* 删除「完整的起承转合…破局与余波」「直达玩家行动结果」，改写「多轮交锋」「推进充足的情节波折」。
* `chat_engine.dart` 每轮控制上下文的「一波三折·双重波折」整条替换为叙事节拍铁律，
  并保留字数锚点（改为引用动态目标字数）。
* 分幕流水线第 1 幕去掉「冲突引入与第一次波折」，续写幕限定「只扩充细节、不增加事件/时间/结局」。
* **字数预算一律不动**：`SceneDialogueOutputBudget` 与 `DialogueLevel` 的上下限保持原值，
  节奏问题不通过缩短回复解决。

---

## 4. 冻结配置评估（本次只评估，不迁移）

### 4.1 事实

`AdventureConfig` 的契约是「冻结基线，剧情输出不得修改」（`docs/adventure_runtime_state.md`），
`AdventureRuntimeStateResolver` 的注释也写明返回值只是展示值、不得作为基线持久化。
但自定义检测状态的当前值（`CustomAttributeItem.currentValue` / `.value`）**每轮都被写回
`adventures.config`**：

* `_projectPendingCustomStatus` 读取**叠加后的**有效 config，再把新值 `copyWith` 进 config；
* `_commitPendingCustomStatus` → `updateAdventureConfig` → `baselineForPersistence`
  只剥离 `affinity` / `relationship` / `life_status` 三个已知 Overlay 字段；
* `RuntimeStateChangeProposal.allowedPaths`（`lib/models/adventure_runtime_state.dart:22`）
  **没有**自定义状态路径，`runtime_state_changes` 无法承载它们。

结论：自定义检测状态是当前唯一绕过 Runtime Overlay、直接改写冻结基线的运行态。
它之所以目前不出错，是因为 `baselineForPersistence` 恰好不管这些字段 —— 属于**未被保护的巧合**，
不是设计。

### 4.2 候选方案

| 方案 | 做法 | 代价 / 风险 |
|---|---|---|
| A（现状） | 保持 config 写入 | 冻结基线持续被改写；分支/回放语义与 Overlay 字段不一致 |
| B | 给 `allowedPaths` 加命名空间路径 `custom_attributes.<attributeId>`，`effectiveConfig` 叠加、`baselineForPersistence` 剥离 | 需放开静态 `Set` 校验、改 validator / `_applyRuntimeDraft` / resolver；还需区分「初始值 vs 当前值」——当前 `CustomAttributeItem` 只有一个 `value`，必须加字段，属于模型层改动 |
| C | 单独建 Overlay 表 | 需要改 DB schema，与「非必要不改库」冲突，不推荐 |

B 的主要风险：`baselineForPersistence` 与 Overlay 一旦不同步，会把叠加值写进基线（静默数据污染）；
回放/回滚（`adventure_state_changes` 的 `before_json`/`after_json`）需要为自定义状态补齐语义；
分支 fork 已会克隆 `adventure_runtime_entities`，但自定义状态目前不在其中，fork 后两条分支会共享
config 里的当前值；消息内嵌 `custom_status` 快照的生成时机也在提交之前。

### 4.3 P1 迁移路径（本次不实施）

1. 用 `seedRuntimeEntity` 为每个被追踪状态播种 `character` 实体的一条 overlay 记录；
2. `RuntimeStateChangeProposal.allowedPaths` 增加命名空间路径 `custom_attributes.<attributeId>`，
   validator 同步放行；
3. `AdventureRuntimeStateResolver.effectiveConfig` 叠加该路径，
   `baselineForPersistence` 剥离；
4. `CustomAttributeItem` 增加初始值字段，使「基线初始值」与「HEAD 当前值」可分离；
5. 引擎改走 `RuntimeStateCommitDraft`，`updateAdventureConfig` 不再承载当前值。

**不需要改 DB schema**：`adventure_runtime_entities.state_json` 已是 JSON 列。

---

## 5. 验收

* `test/unit/custom_status_evaluation_test.dart`：评估协议端到端 7 例（含 changed=true 落状态、
  changed=false 不写盘、非法 attribute 记诊断、同目标不双结算、unevaluated、协议不残留）、
  `CustomStatusEvaluation.parse` 8 例、`statusDiagnostics` 默认值 1 例。
* `test/unit/custom_status_delta_test.dart`：诊断词表更新 + 名称回退 / 引号数字 / `protagonist`
  字面量 / `no_visible_change` / 同目标去重。
* `test/unit/chat_engine_and_prompt_test.dart`：叙事节拍规则在 L0/L2/L5 均存在；L1/L3/L5 不再包含
  「破局与余波」「完整的起承转合」「直达玩家行动结果」；评估协议出现在提示词中。
* 回归保持绿灯：`adventure_turn_commit_atomicity_test.dart`、`adventure_output_control_test.dart`、
  `chat_engine_runtime_state_commit_test.dart`、`narrative_runtime_test.dart`、`custom_attribute_test.dart`。
