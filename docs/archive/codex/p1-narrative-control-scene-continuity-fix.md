# P1 互动叙事控制权与场景连续性专项修复 — 实施规格

> 基线：`main @ 88a2dd7`（v1.2.07+29），工作区干净。
> 模式：Production Fix + Regression Testing + Independent Review（独立审查由全新上下文的审查 Agent 完成）。
> 本文档记录根因、设计决策、契约变更与已知限制；实现以代码与测试为最终事实。

## 1. 根因（相对 88a2dd7 复核结论）

| 问题 | 根因 | 性质 |
| --- | --- | --- |
| P1 单轮过度推进 | 历史强制指令已在 v1.1.11（`44b9187`）删除；当前无“到达玩家决策点即可合法停笔”的机制，L4/L5 大字数下限 + 多幕续写 + 补写 + 抗衰减警告与“一个节拍”存在结构性压力；decay 警告旧文案含“推进多幕情节” | 设计缺口 |
| P2 第三者介入 | 提示词无在场封闭集；角色资料白名单注入（不在场角色仍出现 profile / 好感度摘要）；叙事正文无新实体校验；模型可经 `scene_state_changes.characters_enter` 单方面扩大在场集合（只验 ID 合法性） | 设计缺口 |
| P3 无故危机 | 强制危机指令已删除；无正向依据校验；突发闯入无可观测诊断 | 设计缺口 |
| P4 控制权不足 | 意图识别只覆盖显式排除；`location`/`time`/`characters_enter/leave` 提案直接落地，无用户授权核对；settlement 状态变更不过滤玩家排除实体 | 设计缺口 |

## 2. 设计决策

### 2.1 玩家决策点停笔标记（P1）

- 新协议标记 `---等待玩家---`（`AdventureResponse.playerStopMarker`）：正文最后一行独立输出。
- 语义：合法提前停止，**优先于任何字数下限**；输出标记后不再输出 JSON/选项/状态（由独立 settlement 结算）。
- 解析：仅“最后一段落整体等于标记”或“最后一段落以独立行结尾等于标记”时生效；正文内出现的同名文本不视为停笔。`parse`/`canonicalize`/`llmHistoryProjection`/`streamingDisplayText` 均剥离标记，玩家、TTS 与历史都不可见。
- 多幕循环：任一幕带标记即终幕（break），不再请求下一幕。
- 长度守卫：`playerStopRequested` 时跳过补写；`NarrativeLengthVerdict.decisionStop`（diagnostic token `decision_stop`）；`passed()` 视为通过；underflow/decay 警告不因合法停笔触发。
- 协议失败：**仅标记、无正文也无 payload** 的响应视为协议违规（抛 `FormatException`，走失败路径，不提交空 assistant 气泡），与多幕路径一致；普通空/截断响应仍保留既有“同轮补写恢复”行为。连续停笔计数 `_consecutiveDecisionStops` 在 `resetState()` 清零。
- 兼容性：不改变任何档位的字数契约（min/target/hardMaximum 不变），只新增一条合法提前停止路径。旧冒险存档无标记文本，行为逐位兼容。

### 2.2 场景参与者权威（P2）

- `PromptCompiler` 输出【当前在场角色（权威名单）】（冲突解析后：用户排除角色已移除）+ 封闭集规则；被提及但不在场的角色 profile 移入【被提及但不在场的角色】并标注“仅可提及/回忆/背景，不得参与互动”。
- `PromptBuilder._buildAffinitySummary` 收敛到「在场角色 + 本轮玩家输入点名的角色」，绝不回退为列出全部存活 NPC（否则等于把不在场角色重新暗示为在场，正是 P2 根因）；死亡角色清单保留，其性质是禁止而非邀请。
- `SceneConsistencyValidator` 新增**有界诊断**：叙事含突发闯入措辞 + 存在入场提案 + 玩家未邀请 → warning（不阻断；语义合理性判断留给提示词契约）。
- `SceneEntryAuthorizer`（新增，`lib/services/scene_entry_authorizer.dart`）对模型提案做确定性授权过滤：
  - 进入：需“本轮最终正文点名该角色”或“玩家明确邀请”；**玩家排除角色一票否决**（即使正文有点名）。
  - 离开：需正文点名、玩家要求离开或玩家排除；`protagonist` 离场交给结构校验器（保留其专用诊断）。
  - 地点/时间：仅当玩家**显式禁止**时否决变更；玩家显式授权时放行；中性时维持既有“报告”语义（避免把场景标题措辞差异误判为跳场景）。
  - 结构校验（未知 ID / 死亡 / 重复 / protagonist）仍由 `SceneStateProposalValidator` 负责，两者不重叠。
  - 被拒绝的每个 delta 产生一条诊断，落入 `scene_dialogue_turns.diagnostics_json.ignored_scene_state_changes`。

### 2.3 用户意图与授权（P4）

- `IntentResolver` 新增保守信号（全部默认空/false，旧行为不变）：邀请、要求离开、独处对象、放慢节奏、禁止/授权换场景、禁止/授权跳时间；排除模式扩展（含多角色否定句的互补规则；保护性否定如“不要告诉X”不误判）。
- 意图通过 `PromptBuilder.lastIntent` 暴露给引擎，用于授权过滤与 settlement 过滤；提示词侧渲染【本轮玩家授权与约束】。
- settlement 与叙事旧协议的 `runtime_state_changes` 过滤玩家排除实体（诊断 `runtime_state_change:excluded_entity:<id>`）。

## 3. 契约变更（ additive ）

- 新诊断键：`scene_state_changes:characters_enter:unauthorized|unnamed|excluded:<id>`、`characters_leave:unauthorized:<id>`、`location|time:forbidden`、`fully_unauthorized`、`runtime_state_change:excluded_entity:<id>`、`length_stopped_at_decision`、`consecutive_decision_stops`。
- `length_final_verdict` 新取值 `decision_stop`。
- `NarrativeIntent` 新字段（默认值保持兼容）。
- 无 schema / 依赖 / 版本号变更；无新 API 请求类型（停笔与过滤都**减少**请求：合法停笔不再补写）。

## 4. 测试映射（任务 14 项）

1. A/B 场景模型强行引入 C → 引擎测试 1（无依据入场被拒 + 诊断）。
2. 用户排除 C 仍提交进入提案 → 引擎测试 2（一票否决）。
3. 用户仅提及 C 未允许进入 → 引擎测试 3。
4. 用户明确邀请 C → 引擎测试 4（合法进入）。
5. 有可靠剧情依据的第三者入场 → 引擎测试 5。
6. 安静双人场景无依据突发危机 → 引擎测试 6（闯入诊断）+ 对照组（普通天气突变不被阻断）。
7. 单轮擅自完成阶段目标 → 引擎测试 7（用户分阶段目标保持 active；猜测 goal id 被拒）。
8. L4/L5 多幕跨越决策点 → 引擎测试 8（标记即终幕，无 stage2 请求）。
9. 字数不足但已到决策点 → 引擎测试 9（无补写、decision_stop、下轮无 underflow 警告）。
10. 用户主动快进/换场景 → 引擎测试 10（授权时间跳跃落地）。
11. 正文与 settlement 状态不一致 → 引擎测试 12（排除实体状态变更被丢弃）。
12. 场景状态与玩家授权冲突的事务行为 → 引擎测试 11（否决但回合仍原子提交）。
13. 中英/否定/模糊措辞 → 单元测试 IntentResolver 组。
14. 重试/取消/并发/分支/CAS/幂等 → 引擎测试 13（重复未授权提案逐次过滤）+ 失败回合零提交 + 既有原子性/CAS 套件全量通过。

## 5. 已知限制（未经真实模型验证）

- 停笔标记依赖模型遵循提示词；不遵循时回落到既有字数契约（不会更差）。
- “正文点名即依据”无法区分“入场”与“回忆/提及”；该语义层由提示词契约 + 排除一票否决 + 闯入诊断覆盖，不做阻断式正则。
- 中性玩家输入下的 location/time 变更维持报告语义（不阻断），仅显式禁止时否决。
- 未运行真实付费 API；全部结论来自 Fake LLM 生产路径测试与静态分析。
