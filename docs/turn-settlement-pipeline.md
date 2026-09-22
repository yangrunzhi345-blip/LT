# Turn Settlement Pipeline（正文生成 → 独立结算 → 原子提交）

基线：`main @ fb355596`（`docs(adventure): record companion detection status persistence fix`）。

## 1. 根因

旧架构把三件不同的事压进**同一个**模型响应：

```
正文（长、创作型、可能多段补写）
---JSON---
{ options, custom_status, custom_status_changes, custom_status_evaluations,
  runtime_state_changes, hp/gold/... }
```

模型必须在一次生成里同时完成「写几千字小说」和「做一次确定性事实结算」。
长正文下失败是结构性的，不是偶发：

1. **注意力与 token 竞争**：档位越高（L4/L5，2500~10000 纯汉字）正文越长，
   留给 JSON 的注意力越少；模型常直接省略 `custom_status_evaluations`，
   或只写 `custom_status` 旧快照（旧快照在评估协议出现时被判定为无权覆盖，
   于是整轮状态零变化）。
2. **补写使结算语义失效**：`NarrativeLengthGuard` 允许一次同轮补写，
   合并规则是「初版 payload 权威，补写 payload 只在初版缺失时才用」。
   即：状态在**第一段正文结束时**就已经被定死，补写里真正发生的事件
   （受伤、好感变化）永远进不了结算。
3. **截断即丢状态**：JSON 在正文之后，一旦被 `length` 截断，正文还在、
   结算整段消失；下游只能靠 `_repairMissingOptions` 补 options，
   状态则直接丢失。
4. **单模型两职责**：同一个 sampling 配置既要 `temperature` 高（创作）
   又要低（结算），无法同时满足。

结果就是用户看到的现象：**正文里角色状态已经变了，状态面板不更新**。

## 2. 架构

### Before

```
User → Narrative（可含 1 次补写）→ 正文 JSON
     → _applySplitResponse：options + custom_status + runtime 全部结算
     → _repairMissingOptions（options 缺失时的第三次请求）
     → commitSceneDialogueTurn
```

### After

```
User
  ↓ A. Narrative Generation（完全不变：字数档位 / LengthGuard / 补写 / 合并 / 收敛）
  ↓    最终 FINAL narrative（补写已合并、overlap 已处理、收敛已完成）
  ↓ B. Turn Settlement（第二次、独立、低延迟、流式请求）
  ↓    只输入：本轮用户输入 + 最终正文 + 稳定 ID 的状态槽 + 运行期事实
  ↓    只输出：options + custom_status_evaluations + runtime_state_changes
  ↓ C. Validation（RuntimeStateValidator / CustomStatusMerger，本地执法）
  ↓ D. Atomic Commit（仍只有一次 commitSceneDialogueTurn）
```

**Narrative Pipeline 必须先彻底结束，Settlement Pipeline 才能开始。**
每个用户 turn 正常只发起一次 Settlement。

## 3. Authority 分层

| 层 | 权威 | 说明 |
|---|---|---|
| 正文 JSON | 兼容 / 正文数据 | `scene`、effects、`game_state` patch、`scene_candidates`；`options` / 状态字段降级为 fallback |
| Turn Settlement | 正常 Options + State Authority | 唯一生产结算来源 |
| RuntimeStateValidator + CustomStatusMerger | 合法性 Authority | 模型不能直接写库 |
| Repository / SQLite | 事实 Authority | revision 只认仓库，不认模型 |

不在正常路径上存在两套状态结算：Settlement 成功即清空正文 legacy 快照，
杜绝 `50 → 60` 的 double delta。

## 4. 流式隔离

| 通道 | 载体 | 用途 |
|---|---|---|
| Narrative | `_streamingContent` → `TypewriterController` → `_streamNotifier` | 玩家可见正文 |
| Settlement | `_settlementStreamingContent`（纯 `String` 累加器） | 只用于流结束后整段解析 |

Settlement 的 `onChunk` **只**写 `_settlementStreamingContent`；
不传 `onReasoningChunk`，不碰 `_typewriter`、`_streamNotifier`、
`_reasoningStreamNotifier`、`_isThinkingNotifier`。
UI 只显示 `SessionSettlingHint`（「正在生成选项与结算状态…」），
原始 JSON 永远不进聊天气泡。

## 5. 状态机

- `ChatStatus`：`idle / loading / streaming / settling`
  - `isStreaming` 仍只代表正文 streaming。
  - `sendMessage()` 在 `settling` 期间仍被拒绝（`_status != idle`），
    避免 turn N 的 settlement 与 turn N+1 的 narrative 并发。
  - 仍是单一枚举，没有回到 `_isLoading/_isStreaming/_isSettling` 三 bool。
- `SceneDialoguePhase`：新增 `settling`。

## 6. 失败与隔离策略

- Settlement 最多 2 次尝试（1 次请求 + 1 次快速 JSON/网络重试），不无限重试。
- 任何失败都不重新生成正文；正文正常保留并持久化。
- 失败时状态优先 fail-closed；只有在正文 payload 本身带了旧协议数据时，
  才作为**显式标注**的 `legacy_*_fallback` 经 validator 落地。
- 迟到隔离：Settlement 返回后、提交前必须确认
  `requestId / generation / adventureId / branchId / runtimeRevision` 全部未变，
  否则 `stale`，一律不应用。
- 重复 `entity:path` 在引擎侧去重（first-wins）并写诊断，
  避免 `RuntimeStateValidator` 抛错炸掉整轮。

## 7. 涉及文件

| 文件 | 改动 |
|---|---|
| `lib/models/llm_task.dart` | 新增 `LlmTask.turnSettlement` |
| `lib/services/llm_task_policy.dart` | 新增策略：thinking=disabled / reasoningEffort=low / preferJsonOutput / maxTokens=1024 / temperature=0.15 |
| `lib/models/turn_settlement.dart` | 新增：`TurnSettlement`、`TurnSettlementTrackedStatus`（复用 `AdventureResponse` / `CustomStatusEvaluation` / `RuntimeStateChangeProposal` 解析） |
| `lib/engines/chat_engine_internals/turn_settlement_prompt.dart` | 新增：结算器 Prompt（只传必要信息） |
| `lib/engines/chat_engine.dart` | `ChatStatus.settling`、`SceneDialoguePhase.settling`、`ContextTaskType.adventureTurnSettlement`、`_applyNarrativeResponse` / `_applySettlement` / `_applySettlementFailure`、`_runTurnSettlement`、独立累加器、去重、`_repairMissingOptions` 降级 |
| `lib/models/adventure_response.dart` | 暴露 `decodeObject` 供二级协议复用同一解析器 |
| `lib/providers/messaging_provider.dart`、`chat_provider.dart` | `isSettling` |
| `lib/features/.../session_input_bar.dart`、`adventure_session_screen.dart` | 结算期间禁止发送/返回 |
| `lib/features/.../session_message_list.dart`、`session_settling_hint.dart` | 轻量结算态提示 |
| `test/unit/turn_settlement_test.dart` | Case A–L |
| `test/widget/session_settling_hint_test.dart` | 320/360/390/412/768/1280 + 大字号 |

## 8. 验收

`flutter analyze` 无问题；`flutter test` 全量 2174 通过。
Case A–L 见 `test/unit/turn_settlement_test.dart`。

## 9. 剩余风险

1. 每次 turn 多一次 LLM 往返（目标 200~600 tokens），结算期间输入被禁用。
2. 结算前取消仍会丢弃整轮（与既有「提交前取消」语义一致，未改动）。
3. 正文系统提示词仍要求模型输出 `options` / `custom_status_evaluations`
   （作为 fallback 与旧数据兼容），这部分现在正常情况下被丢弃。
4. 正文 `game_state` patch（hp/gold/...）仍在正文侧结算；
   Settlement 的 `runtime_state_changes` 走 overlay，二者目标不同。
5. 无任何稳定 ID 的历史同伴（既不在 `supportingCharacters` 也无
   `selectedCharacters` 行）不会被列入结算槽。
