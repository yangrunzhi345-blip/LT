# 角色状态与世界观状态系统总设计书

> 阶段：Phase 0 设计稿，不包含源码、migration 或功能实现。
>
> 代码基线：GitHub `origin/main`，`dfd41da3a4035ff483227870e0380c59b52dc848`（2026-09-23 检查）；本地 `HEAD` 的额外提交仅更新设计文档，生产代码与远端基线一致。
>
> 数据库基线：`DatabaseService.schemaVersion = 44`。

## 静态架构分析报告

### Resource 与生成模型

- `Resource`、`ResourceSection`、`ResourcePart` 是 `lib/domain/resources/resource_contracts.dart` 中的纯 Dart 三层内容树。资源正文以 Part 为边界，不能把动态剧情状态塞入一份巨型资源 JSON。
- 当前没有统一的 `ResourceVersion`、`GenerationAttempt` 或通用 `ValidationState` 实体。版本能力是 `ResourceRevision` / `ResourceRevisionRecord` / `ResourceRevisionState` 与 `ResourceRevisionService`；revision 区分 `latestHead`（编辑稿）和 `assembly`（已验证、可组装版本）。生成尝试是流式生成运行时事件、generation task/session 等分散职责；验证状态为 `SectionValidationState` 等具名状态机。不能把这些机制误认为运行时剧情历史。
- `ResourceAssemblySnapshot` 与 Adventure 配置中的角色卡、世界观快照用于冻结开始时来源。它们是基线，不是运行中事实的写入目标。
- `ResourceProvenance`、导入桥接和现有 revision 能支撑“状态来自哪个资源/版本”的溯源，但不应把每次剧情变化写成 Resource revision，否则编辑历史与剧情事实会混成一类。

### 角色身份与当前状态

- `CharacterCard` 是资源库中的角色档案，包含姓名、创作者、背景/外观、性格、能力、弱点、装备、阵营/驻地/目标、秘密及自定义属性等。它没有可靠的领域分类来保证哪些字段永不变化；语义层面应把身份和设定视为 Profile/基线，用户编辑仍可通过 Resource Library 管理。
- `AdventureSelectedCharacter` 在 Adventure 配置中保存 `characterId`、显示信息与 `characterCardJson` 快照。该快照保证开局选择不随资源库后续编辑漂移。
- 当前动态角色实体是 `RuntimeEntityType.character` / `npc`，以稳定 entity ID + overlay 表示相对冻结基线的当前差异。已支持 hp/mp/energy/experience/level、生命状态、好感、关系、阵营、目标、生命周期及自定义属性等受限路径。
- 身份数据不应被复制到每次快照。角色身份引用 Profile/Adventure 冻结基线；动态值由当前 Adventure + branch 的运行时权威解析器合并得出。年龄、伤势、装备、心理等新路径需按 typed schema / 允许路径演进，不能把任意字符串路径直接放开。

### 世界观与运行时世界

- `WorldviewDetails`、世界观 `Resource`/Sections/Parts 描述静态设定；`WorldEntry` 及 embedding 用于条目检索。`WorldviewSnapshotService` 与 Adventure 冻结快照保持开局来源稳定。
- 现有运行时实体类型已包含 `world`、`location`、`faction`、`relationship`，可表达某 Adventure 中的控制权、地点、政治关系、地区环境等变化。剧情变化不得反写资源库世界观正文或覆盖冻结 snapshot。
- `SceneState` 是 branch-local 的短期场景事实：位置、时间、在场角色、场景目标与近期变化；持久化在 `scene_runtime_state` 的版本化 JSON 中。它不应承担数百小时剧情的通用世界历史。

### Session / Chat 与事实提交

- Chat 消息保存在 Adventure 关联的 `messages` 中。模型提出的 `RuntimeStateChangeProposal` 和 `SceneStateChangeProposal` 是不可信候选，经白名单/边界校验和协调后才可应用。
- `scene_dialogue_turns` 使用 request ID 做 turn 幂等关联；Adventure Repository 的对话提交事务协调消息、RPG effects、SceneState、runtime commit、entity overlay 与 Runtime HEAD。expected revision 负责拒绝 stale write。
- `AdventureRuntimeStateResolver` 将冻结 baseline 与分支 overlay 合并，是当前角色有效状态的权威读取入口。`RuntimeMemoryProjector` 经现有 `ContextOrchestrator` 有界注入相关运行时事实；显式历史问题才查询有界 commit archive。
- 用户手动编辑、系统效果与 AI 候选最终都必须进入同一个验证/提交边界。不能由 UI、Prompt builder 或另一个状态 Repository 各自直接持久化“当前状态”。

### 可复用、需新增与主要风险

| 类别 | 结论 |
| --- | --- |
| 可复用 | Resource 三层树和稳定 ID；latestHead/assembly revision；Assembly/Worldview 冻结快照；Adventure 配置基线；Runtime HEAD/commit/change/overlay；SceneState；Turn Settlement 候选协议；`RuntimeStateValidator`；对话原子提交、request ID 幂等与 expected revision；`AdventureRuntimeStateResolver`；ContextOrchestrator 与有界运行时记忆投影；已有页面化 Adventure 导航结构。 |
| 需要新增/演进 | Character Profile 与运行时字段的明确分类/字段元数据；可版本化的 typed 状态路径和值校验；可区分来源的事件 provenance 与稳定事件类型/参数；快照投影/差异查询服务（优先从 commit/change 回放）；按时间/实体/分支分页的 Timeline 查询；状态页面、时间线页面和编辑/恢复交互；同步所需的 schemaVersion、稳定 ID、冲突规则与 tombstone 语义。 |
| 风险 | 与现有 Runtime commit/archive 形成双重 authority；Adventure 间状态串线；Profile 后续编辑污染已开局基线；模型伪造状态或原因；事件表无限增长与大快照；分支恢复破坏历史；删除角色/Adventure 导致历史溯源丢失；不同步或多设备并发；把本地化展示文案写进持久化事件；UI 小屏 timeline/多字段溢出；把短期 SceneState 与长期角色/世界事实混淆。 |

## 1. 设计目标

角色卡回答“这个角色是谁/被如何设定”；角色状态回答“这个角色在此 Adventure 分支现在如何”。世界观资源回答“世界的基础规则是什么”；世界状态回答“剧情已令这个世界发生了什么”。系统提供可解释、可审阅、可回溯的状态变化，而不是让 Prompt 中的历史对话成为唯一事实来源。

目标是降低角色卡/世界观不断堆叠当前值和旧值造成的膨胀；让世界变化有来源和时间线；把当前事实与噪声历史隔离以减少 AI 上下文污染；让用户可以确认、手动编辑、检查差异并恢复历史状态。恢复只移动分支 HEAD 或产生新的反向提交，永不抹掉已提交历史。

## 2. 核心概念

- **Character Profile**：资源库中的身份与基础设定，Resource 的一种领域视图；保持用户编辑和 revision 语义。
- **Character State**：在 `(adventureId, branchId, characterEntityId)` 范围生效的动态字段。每个 Adventure 从冻结角色快照初始化，之后仅保存 overlay/delta。
- **Character Event**：已接受的、描述一次事实变化的不可变记录；AI proposal 本身不是 Event。
- **World Definition**：静态世界观 Resource 与已选择的冻结 world snapshot。
- **World State**：在 Adventure branch 内对 world/location/faction/relationship 等实体的动态覆盖。
- **World Event**：已接受的世界事实变化，按类型记录地点、势力、政治、环境等 subject。
- **Snapshot**：某 branch 在某 revision 的可重建状态投影。不是单独可写的权威状态副本。
- **Timeline**：按照 branch revision 展示已提交事件、状态差异及 provenance 的读取视图。

```text
Resource Library                     Adventure branch
CharacterCard / World Definition     frozen baseline
          |                               |
          +---- Assembly / snapshot ------+
                                          v
Proposal (AI / user / system / import) -> validate + authorize
                                          |
                               atomic runtime commit
                                  /             \
                          State Event        overlay + HEAD
                                  \             /
                         revisioned Snapshot projection
                                          |
                              Timeline / current state UI
```

一个既有运行时提交可以含多个 entity changes；Event 用来解释并分类已接受变更，不能另建不受同一事务控制的 authority。建议初期将一个 commit 作为一个 timeline event group，单项 changes 保留字段级 before/after。

## 3. 数据模型设计

### 3.1 身份、作用域和类型

持久化身份至少包含 `event_id`、`commit_id`、`adventure_id`、`branch_id`、`revision`、`entity_type`、`entity_id`、`path` 与稳定 `event_type_id`。角色/世界状态默认只在 Adventure 分支内有效，不产生 Resource 全局“当前值”。值使用带 schema 版本的类型（数值/字符串/稳定枚举/结构化对象），并由每个 path 的定义校验；controlled label 和 event type 不能存翻译文案。

### 3.2 逻辑表与现有持久化映射

需求中的四个表名表达逻辑职责；它们**不是默认要新增的四张并行表**。当前 `adventure_state_commits` + `adventure_state_changes` 已经存版本、parent、request、reason、before/after、来源消息和 context snapshot；`adventure_runtime_entities` + `adventure_runtime_heads` 存当前 overlay/HEAD。实施阶段应先扩展现有 archive 的 schema/查询，使其承载 typed event provenance。只有当审计证明现有 change 一行无法承载独立 event group 元数据时，才考虑一张窄的 `adventure_state_events` 辅助索引表，并与原子 commit 共事务；禁止维护第二套可写 before/after 和 current snapshot。

| 逻辑对象 / 需求名 | 建议字段 | 存储决策 |
| --- | --- | --- |
| `character_state_events` | `id`, `adventure_id`, `branch_id`, `character_entity_id`, `commit_id`, `revision`, `timestamp`, `source`, `event_type_id`, `change_reason`, `before`, `after`, `metadata` | 逻辑视图：从同一 Runtime commit/change archive 查询 character/npc changes。若要命名专用表，必须先证明必要，且仅存 event group/typed provenance 并 FK 到既有 commit；不重复存 current truth。 |
| `world_state_events` | 同上，`world_entity_type` / `world_entity_id` 可指 location/faction/relationship/world | 逻辑视图：从同一 archive 查询世界相关实体变化。世界事件可以一个 commit 跨多个实体，以 event group + entity changes 表示。 |
| `character_state_snapshots` | `id`, `adventure_id`, `branch_id`, `resource_id`, `revision`, `timestamp`, `source`, `change_reason`, `before`, `after`, `metadata` | 不建逐事件整卡快照表。由 frozen character baseline + runtime overlay 在 revision 重建；对性能需要，可建立可丢弃/重算的稀疏 checkpoint，必须含 commit/revision、schema/hash，且不能成为 authority。 |
| `world_state_snapshots` | `id`, `adventure_id`, `branch_id`, `resource_id`, `revision`, `timestamp`, `source`, `change_reason`, `before`, `after`, `metadata` | 与角色 snapshot 同理；世界区域、势力等按需投影。禁止复制整个 world definition 每个 revision。 |

建议 `source` 为受限稳定值（`ai_proposal`、`user_edit`、`system_rule`、`resource_import`），另存 `source_message_id`、`actor_id`、`request_id`、`context_snapshot_id`、`confidence`、`event_schema_version`、可选 `parent_event_id` 等到 typed metadata/provenance。`change_reason` 是来源叙述/证据文本而非受信状态字段，也不能替代 event type。`before`/`after` 是单字段或有界结构化值，不应是完整 Resource JSON。

现有 repo 已存 before/after 及 request ID/来源引用，但需要在实现审计时核对具体列和迁移兼容性；文中逻辑字段名不保证与 SQLite 现有列名一致。历史旧记录不得猜测转换成新稳定 event ID，也不得伪造过去事件。

### 3.3 长期数据规模

数百小时会产生大量消息与少量结构化变化。保持每事件最多有界 changes、按 `(adventure_id, branch_id, revision)` 和 `(entity_type, entity_id, revision)` 索引、按 revision 游标分页。Timeline 默认只读最近事件，历史/因果查询限额；不把完整消息正文复制进事件，存 message ID 并按权限延迟读取。当前 overlay 是紧凑状态；定期或按阈值生成 checkpoint 优化长链回放，checkpoint 可重建、可校验。冷历史允许压缩展示摘要但不能删除权威 commit。做 retention 前必须定义分支删除、Adventure 删除和同步 tombstone 规则；默认 archive 与消息一起遵守明确数据保留策略。

## 4. 状态生命周期

1. **创建 Adventure**：冻结 Resource revision/assembly snapshot；以基线计算初始有效状态，Runtime HEAD revision 0。可记录初始化 provenance，但不为每个初始字段虚构剧情 event。
2. **产生候选**：AI Turn Settlement、用户编辑、系统效果或导入转换产生 proposal，附来源、目标 branch/expected revision、证据和幂等 request ID。
3. **校验与提交**：校验实体归属、字段路径和值类型、规则/权限/置信阈值、幂等性和 expected revision；原子写消息（若有）、commit、changes、overlay、HEAD。拒绝 proposal 留诊断/审阅状态，不进入事实 Timeline。
4. **生成 Snapshot**：需要读取 revision 时由冻结 baseline + branch revision changes 重建。缓存/checkpoint 仅为派生数据。
5. **回滚/恢复**：用户选择旧 revision 后先展示 diff 和影响；恢复通过创建新 revision，将目标值作为新提交应用到当前 HEAD，保留后来历史。可另有“从此处新建分支”，继承选定 revision 后形成新 branch。不得物理删除中间 commits。

## 5. 状态变化来源和优先级

- **A AI 自动推断**：最低信任。先作为 proposal；严格白名单、结构/数值验证、来源消息引用、置信度阈值。高影响/歧义变化要求用户确认。模型 reason 仅是解释，不是证据授权。
- **B 用户手动修改**：明确用户意图，通常优先于自动推断；仍受领域不变量、branch 作用域和 revision 冲突保护。保留 before/after 和操作者。
- **C 系统事件**：来自确定性游戏规则、战斗/物品/脚本等系统服务，按领域规则权威处理；规则版本和触发来源必须记录。不可被迟到 AI proposal 覆盖。
- **D 导入资源**：只初始化新 Adventure/新实体的基线或用户明确发起的迁移候选；不得静默覆盖已有 branch runtime state。需预览冲突和目标 revision。

冲突仲裁不是用单一 source 排序覆盖时间：首先检验期望 revision 并串行提交；同一事务按因果顺序；系统硬规则维护不变量；显式用户决策优先于待审 AI 候选；旧 proposal 失败并重新基于当前状态审阅。任何 source 都不能绕过原子提交。

## 6. 与现有 Pipeline 集成及唯一 Authority

- **唯一 Authority**：指定 Adventure branch 的 `adventure_runtime_heads` + commit/change archive + overlay 是长期角色/世界动态事实唯一持久化 authority。`AdventureRuntimeStateResolver` 是有效状态读取权威。冻结 Resource/Assembly snapshot 是身份与世界定义基线，不是当前态；`SceneState` 是短期场景态；GameState/RPG effects 保持各自既有机械职责并通过已协调 turn commit 变更。
- **Resource Pipeline**：资源生成、编辑、导入与 revision 继续只处理资源定义。组装时把选定 Profile/World Definition revision 冻结为 adventure baseline；Assembly 的 canon/readiness 门槛不被 runtime 变化绕开。导入到现有 Adventure 必须经过显式 proposal/确认，不直接写 Resource 或 overlay。
- **Generation Pipeline**：沿用 Turn Settlement 的结构化候选输出和现有校验边界；模型不能写 DB、commit、snapshot 或 HEAD。扩展 typed schema、provenance 和冲突审阅，不新建独立 AI 状态提取写入路径。
- **Session**：turn request ID 关联 assistant message、SceneState、runtime proposal。Repository transaction 是所有持久化改变的唯一边界，使用幂等与 expected revision。用户手动编辑同样调用同一 commit use case。
- **禁止双轨**：禁止再建独立 character/world current-state 表，禁止 UI/local cache 自行成为事实源，禁止从 archive 另维护一份会被独立修改的 timeline truth。需要新 event 表时只作引用/查询投影并与 commit 同事务。

## 7. AI 上下文注入设计

使用现有 ContextOrchestrator/RuntimeMemoryProjector 的预算控制，不直接塞全部历史：

1. **长期注入（高稳定）**：当前选定角色 Profile 的身份、核心设定及当前场景相关规则；当前 Adventure 冻结世界定义中与请求相关的部分。Profile 事实标识来源 revision。
2. **当前状态（最高事实权重）**：本分支 HEAD 的相关角色/地点/势力状态 overlay。与 Profile 矛盾时动态状态说明“此剧情中的当前情况”，不修改 Profile。
3. **事件摘要（中高）**：近期已提交状态事件的简短、稳定结构摘要；按实体和当前场景选取，引用 revision。显示叙事 prose 与机器状态变化分开。
4. **历史检索（按需）**：用户问过去/原因/变化，或当前动作需要历史约束时，按 entity/time/revision 搜索 archive，限数量和 token。默认不注入全部事件、消息或 snapshots。
5. **待确认 proposals（低/非事实）**：仅在审核 UI 或有明确任务需要时可见，Prompt 必须标为未确认，不可作为当前状态陈述。

同一事实只从 authority 读取一次；事件摘要不能覆盖 HEAD 当前值。受限预算按“当前相关状态 > 相关定义 > 少量近期事件 > 按需历史”分配，并记录 context snapshot ID 以便追溯生成时视图。Prompt 输出与系统 label locale 无关的稳定 ID，用户 prose 按内容原样保留。

## 8. UI 展示设计

页面作为 Adventure 页面化导航中的一等页面，不使用 Dialog 承载主流程。编辑确认可用专页或移动端 BottomSheet；Timeline、全量差异和恢复预览均有自己的可滚动页面。

### Character State Page

- 顶部：角色名/头像、Adventure 分支、当前 revision 与“基于资源版本”提示；小屏换行，身份关键内容不只靠 tooltip。
- “当前状态”卡按生命/数值、状态标签、关系阵营、装备/物品、目标心理分组；只显示已确认的运行时值，区分 inherited baseline 与 branch override。可按配置隐藏不适用字段。
- “属性变化”区列出相对 Profile 基线及上一事件的变化，提供 before → after、时间、来源、原因、commit/revision。
- “最近事件”列表只渲染最近若干项，继续查看进入 Character Timeline Page；可按类别/source 筛选。
- 状态 diff 使用字段级变化，不比较渲染后的长文；未知字段以可恢复兼容视图展示，避免原始 JSON 泄露为正文。
- 操作：编辑当前值、查看来源资源版本、打开完整时间线、恢复到历史状态。高影响 AI proposal 明确确认/拒绝。

### World State Page

- 当前世界摘要与 branch/revision；区域、政治势力、关系、地区环境/控制权分区展示。
- “地区变化”以可访问列表/地图切换表示，不要求首期地图；“政治变化”显示势力关系及时间；“历史事件”展示 event group 与涉及实体。
- 每项状态提供当前值、最近变化、来源和相关地点/势力链接；未知或待确认变更清晰分组。
- 后续地图是 State 的另一种投影，不成为世界状态数据库。

### 响应式与桌面/移动

- 移动端优先：单列卡片、过滤项收进可滚动/可折叠区域、操作 Wrap 或菜单化；Timeline 以卡片纵向排列，不使用宽表格。页面有明确刷新/加载/空/错误/离线状态。
- 桌面端：主区展示当前状态，侧栏提供事件/过滤/实体导航；宽屏可双栏，但需在组件约束内适配。
- 所有页面遵守项目硬门槛：320 logical px 无横向溢出，考虑 360/390/412、768 和桌面、长中英文、系统大字、SafeArea、键盘；动态内容可换行/滚动，按钮保留触控尺寸。UI 实现阶段需 viewport widget tests 覆盖主要页面、Timeline 和恢复确认流。
- Timeline 分页加载、按需差异，不在首帧载入所有历史；筛选、排序、当前选中 revision 与路由可还原。

## 9. Git-like 版本体验

- **Snapshot** 是 branch 某一 revision 的只读重建状态；revision 线性递增，commit 有 parent commit、来源和差异。
- **Branch** 是独立运行的 Adventure 分支。分支从选定 HEAD 创建，之后 overlay/commit 分叉；禁止角色/世界 Resource 编辑 revision 被误认为剧情 branch。
- **Timeline** 按 revision 顺序显示人类可读事件、变更字段、时间、来源与原因；时间戳辅助阅读，revision 是稳定排序依据。
- **Restore** 可恢复单角色/单字段或整分支状态。先显示从当前到目标 revision 的可解释 diff 与覆盖字段，再创建新 commit 或新 branch。对话消息仍在其历史位置，不重写消息内容。不能 hard delete 或重写共享历史。
- 首期不做 merge/rebase/cherry-pick；跨分支合并属于后续冲突策略设计。UI 可查看任意 revision，不等同于把 Runtime HEAD 改回过去。

## 10. 后续扩展

- 多角色关系图：实体与关系仍由同一 branch 状态存储，图是投影。
- 世界地图状态：地理位置/控制区的可视化投影，支持无地图的列表 fallback。
- AI 自动状态检测：proposal、confidence、来源证据、人工审核阈值与可观测误报率；永远不让模型绕过 validator。
- 状态冲突检测：字段 schema、领域规则、expected revision、跨实体约束和用户可解释冲突。
- 同步：稳定 UUID、branch/commit parent、幂等操作 ID、schema version、冲突保留与删除 tombstone；离线期间不使用墙钟最后写入覆盖分支事实。
- 进一步扩展前必须由测量证明需要更复杂 checkpoint、索引或专用存储，首期不建图数据库或通用工作流框架。
