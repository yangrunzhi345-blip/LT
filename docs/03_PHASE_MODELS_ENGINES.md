# 阶段三：领域模型与业务逻辑引擎移植计划

> **文档编号**：`03_PHASE_MODELS_ENGINES`  
> **当前状态**：✅ **已完成 (Completed)**  
> **前置依赖**：`02_PHASE_PERSISTENCE_SERVICES`  
> **预计成果**：移植场景对话核心契约模型、资料库实体、LLM 通信服务与 `ChatEngine` 状态机内核，实现无 UI 依赖的端到端对话推理链路。

---

## 1. 本阶段目标

1. 移植三大领域（设置、资料库、场景对话）所需的核心数据契约模型（Models）。
2. 移植核心通信网关 `LLMService`（支持流式 SSE、多厂商协议统一适配、Token 统计与错误降级）。
3. 移植对话核心状态机 `ChatEngine` 及其子组件（`PromptBuilder`、`TypewriterController`、`SummaryService`）。
4. 移植游戏数值引擎 `GameEngine` 与世界观动态词条引擎 `WorldEngine`。

---

## 2. 待迁移文件清单

### 2.1 领域契约模型 (`lib/models/`)

| 目标文件 | 领域归属 | 关键类与职责说明 |
| :--- | :---: | :--- |
| `lib/models/llm_provider.dart` | 设置 | `LlmProviderType` 枚举、各厂商基础 URL、模型列表与默认参数 |
| `lib/models/completion_params.dart` | 设置 | 温度、Top_P、最大 Token、惩罚项等生成参数配置 |
| `lib/models/model_context_capability.dart` | 设置 | 模型上下文窗口容量与 Token 阈值描述 |
| `lib/models/character_card.dart` | 资料库 | 角色卡实体（名称、性格、背景、初始装备/技能、问候语） |
| `lib/models/character_card_entry.dart` | 资料库 | 角色卡列表简要轻量条目 |
| `lib/models/worldview_preset.dart` | 资料库 | 世界观设定（背景简介、核心规则、地理与阵营） |
| `lib/models/worldview_details.dart` | 资料库 | 世界观详细扩展信息 |
| `lib/models/world_entry.dart` | 资料库/对话 | 世界观词条条目实体与动态激活匹配规则 |
| `lib/models/prompt_preset.dart` | 资料库/设置 | 系统提示词预设模板（格式化标签、引导指令） |
| `lib/models/persona.dart` | 资料库 | 玩家人设化身（昵称、身份、个人特质） |
| `lib/models/skill.dart` | 资料库/对话 | 技能与专长模型 |
| `lib/models/message.dart` | 场景对话 | 消息实体（角色身份、消息正文、时间戳、思考内容、分支信息） |
| `lib/models/scene_dialogue.dart` | 场景对话 | 场景冻结快照、候选选项列表、字数预算契约 |
| `lib/models/scene_dialogue_effects.dart` | 场景对话 | 剧情副作用（血量变动、金币得失、物品变更、任务触发） |
| `lib/models/dialogue_level.dart` | 场景对话 | L0~L5 对话细致度与描写风格分级 |
| `lib/models/game_state.dart` | 场景对话 | 当前冒险动态数值状态（HP/MP/Gold/Location/Inventory） |
| `lib/models/combat_state.dart` | 场景对话 | 遭遇战状态（敌方属性、行动轮次） |
| `lib/models/quest.dart` | 场景对话 | 任务状态与目标追踪 |
| `lib/models/equipment.dart` | 场景对话 | 装备与道具数据结构 |
| `lib/models/adventure_config.dart` | 场景对话 | 开启新冒险时的整合初始化配置 |
| `lib/models/adventure_response.dart` | 场景对话 | 接收 LLM 返回的双段解析载荷实体 |
| `lib/models/app_section.dart` | 导航外壳 | 顶级页面分区枚举：`adventure`, `resources`, `settings` |

### 2.2 业务逻辑与引擎层 (`lib/engines/` & `lib/services/`)

| 目标文件 | 关键类与职责说明 |
| :--- | :--- |
| `lib/services/llm_service.dart` | 统一 LLM 网关：处理与各提供商的 HTTP 流式交互、重试与网络超时检测 |
| `lib/engines/chat_engine.dart` | **核心引擎**：状态机管理（`idle`, `generating`, `typing`, `error`）、消息生命周期调度、并发保护 |
| `lib/engines/chat_engine_host.dart` | 抽象宿主契约接口：定义引擎读取外部状态与持久化的 25+ 抽象方法，彻底解耦 Provider |
| `lib/engines/chat_engine_internals/prompt_builder.dart` | 提示词构建器：按预算组装系统提示词、世界观硬约束、最近 6 轮滑动上下文及早期摘要 |
| `lib/engines/chat_engine_internals/stream_handler.dart` | 打字机流式控制器：平滑解析 Markdown 增量输出与分离最后的结构化 JSON 块 |
| `lib/engines/chat_engine_internals/summary_service.dart` | 滚动摘要服务：当历史消息超过设定窗口，自动压缩为时间线事件摘要 |
| `lib/engines/game_engine.dart` | 数值运算：根据模型提取的副作用更新血量、扣除金币、发放战利品 |
| `lib/engines/world_engine.dart` | 词条激活：在对话过程中根据关键词命中动态激活相关世界条目 |

---

## 3. 核心机制设计

### 3.1 双段式响应机制与并发守卫 (Double-Segment Response)
LLM 生成的响应由两部分构成：
1. **叙事正文 (Narrative Text)**：给玩家展示的剧情描述、对话与感官细节。
2. **结构化 JSON 块 (Action & State JSON)**：附加在文本末尾包含 ```json 标签的数据块，由 `StreamHandler` 拦截解析为 `SceneDialogueEffects`。

```
LLM 流式输出
   │
   ▼
[StreamHandler]
   ├─► 正文部分 ──► TypewriterController ──► UI 逐字打字动效
   └─► JSON 部分 ──► GameEngine / Repo ──► 原子事务写入 DB (HP/金币/选项)
```

### 3.2 解耦要点
- 在 `prompt_builder.dart` 中，剔除与 Naila 助手混合向量检索相关的注入代码。
- 在 `chat_engine.dart` 中，移除对创作工作流或复杂恢复机制的旁路调度，保留纯粹的冒险对话轮次控制。

---

## 4. 验收标准 (Acceptance Criteria)

- [x] 所有 Model 类的序列化/反序列化（`toMap`/`fromMap` 或 `toJson`/`fromJson`）测试通过。
- [x] `PromptBuilder` 能根据传入的设定和消息历史成功渲染出规范的 System Prompt。
- [x] `StreamHandler` 能够正确将「正文文本 + JSON 块」进行无缝切分，正文平滑送出且 JSON 正常反序列化为对象。
- [x] 执行 `git commit -m "feat(engine): migrate domain models, LLMService, and ChatEngine core"` 归档。

---

## 5. 完成状态 (Completion Status)

- **状态**: ✅ 已完成 (Completed)
- **提交哈希**: `52bbc38` (后续补全 `model_context_capability.dart` 与测试)
- **验证测试**: `test/unit/chat_engine_and_prompt_test.dart` (12/12 测试全部通过)
- **代码分析**: `flutter analyze lib/engines lib/services lib/managers lib/models` (0 errors, 0 warnings)

