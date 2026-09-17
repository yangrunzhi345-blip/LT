# ADR-0001：自适应资源系统的内容树架构契约

- 状态：Frozen（Phase 0）
- 适用范围：Phase 0–12 全部资源重构阶段
- 契约代码：`lib/domain/resources/resource_contracts.dart`、`lib/domain/resources/resource_limits.dart`、`lib/domain/resources/resource_repository.dart`
- 执行方案：`docs/adaptive-resource-system/`

## 背景

世界观、角色卡与 NPC 当前以固定字段或固定模块表达（`WorldviewDetails.moduleKeys`、`CharacterCard`），创建与导入散布在多个页面与 coordinator 中，容量数字散落在生成配置与业务类里。若要支持自适应结构、增量生成、局部重写、语义压缩与可组装的 Adventure 快照，必须先冻结一套所有阶段共同依赖的术语、层级、状态与容量定义，否则每个阶段都会重新发明 Resource/Section/Part 的含义。

Phase 0 只做契约冻结：新增纯 Dart 契约与测试，不迁移数据、不改用户入口、不接入 UI/AI/数据库。

## 决策

### 1. 三层逻辑树

`Resource -> Section -> Part` 是**逻辑树**：

- `ResourceSection.resourceId` 必须指向一个 `Resource`，Section 必须直属 Resource。
- `ResourcePart.sectionId` 必须指向一个 `ResourceSection`，Part 必须直属 Section。
- 父子关系是**数据**（父 id 字段），不是物理包含。
- 因此不存在 "Section 内嵌 Section" 或 "Part 内嵌 Section" 的类型；`NodeId` 被声明为 `sealed`，层级不可被外部扩展。

约束由 `ResourceTree.validate()` 代码化：跨资源节点、重复 id、指向未知 Section 的 Part 都会抛出 `ResourceContractException`。

### 2. 节点 ID 不可变

- ID 由创建方在节点创建时分配，之后永不改变。
- `NodeId` 为不可变值对象（`ResourceId` / `SectionId` / `PartId`），非空且按值相等。
- 重排、重命名、改写正文都不改变 ID；`sortOrder` 与身份完全分离。

### 3. 同级顺序显式保存

- 每个 Section/Part 都保存显式 `sortOrder`（非负整数）。
- 读取顺序固定为 `(sortOrder, id)` 排序，因此即使出现相同 `sortOrder`，顺序仍然确定，不依赖数据库返回顺序。
- Phase 1 的 `sort_order + id` 稳定排序规则与本契约一致。

### 4. 长正文最终属于 Part

- 只有 `ResourcePart` 拥有 `content`。
- `Resource` 只保存身份、分类、名称、摘要与**类型特有的运行时核心字段**（`metadata`）。
- `ResourceSection` 只保存身份、标题、摘要、顺序与状态。

### 5. 禁止完整 Resource 巨型 JSON

- 禁止把整棵内容树序列化成一个巨型 JSON 列作为正式存储。
- 禁止通过物理嵌套（大字段内嵌数组/对象）制造伪逻辑树。
- 禁止单次模型调用承担完整世界观/角色卡正文。
- 生成协议上限：一次响应只能产出一个 blueprint，或一个**有限节点 patch**；`ResourceNodePatch` 是 `sealed` 且每个子类只暴露一个 `targetNodeId`，任何 patch 都只能操作一个节点。
- 仓储接口不接受序列化整资源；`ResourceNodeMounter.mount` 每次只接收一个 patch。

### 6. 后续生成、重写、扩写、压缩以有限节点为边界

重写、扩写、压缩都表达为对有限节点的 patch 或候选，而不是整资源替换。容量超限时保存完整原稿，压缩只产生候选。

### 7. 原稿与 Assembly 可消费版本分离

- `ResourceRevisionKind.latestHead` 是用户最新保存的编辑稿。
- `ResourceRevisionKind.assembly` 是 Adventure/Runtime 允许消费的已验证版本。
- 两者允许分叉；Runtime 只能读 `ReadinessState.ready` 且已发布的 assembly revision（`ResourceRevisionSelection.canAssemble`）。
- `ResourceAssemblySnapshot.fragments` 按节点产出，且带 `isCanon` 标记，草稿节点不得作为事实注入 canon。

### 8. 容量策略唯一事实源

`ResourceLimits` 是唯一正式定义来源：

| 资源类型 | nominal | absolute |
| --- | --- | --- |
| 世界观 | 50,000 | 60,000 |
| 角色 | 5,000 | 6,000 |
| NPC | 5,000 | 6,000 |

- `CapacityStatus`：`normal`（≤ nominal）、`elastic`（nominal < n ≤ absolute）、`overflow`（> absolute），全部由 `ResourceCapacityPolicy.statusFor` 推导。
- 任何页面、Prompt、业务类都不得复制这些数字；`ResourceLimits` 之外的契约文件不得出现这些字面量（由测试守护）。
- `overflow` 不等于截断：超限原稿仍必须完整保存，只触发压缩与新的 assembly revision。

### 9. 状态机与非法转换保护

`ResourceStateMachines` 是唯一转换表，未列出的转换一律非法并抛出 `ResourceStateTransitionException`。自转换允许，重复写入当前状态是幂等的。

- `GenerationStatus`：`idle → planning → generating → completed/failed/cancelled`；终态只能回到 `planning`。
- `NodeStatus`：`draft ↔ confirmed`、`draft/confirmed → archived`、`archived → draft`；`archived → confirmed` 非法（归档内容必须回到草稿重新审阅）。
- `ReadinessState`：`preparing → ready/failed`、`ready → stale/preparing`、`failed/stale → preparing`；`ready → failed` 与 `failed → ready` 非法。

## 被否方案

- **一个 `content_json` 巨列 + 应用层解析**：无法局部读写，无法限定单次生成边界，直接违背 Phase 5/8 目标。
- **在 Resource 上保存 `sectionIds` 有序数组**：与 Phase 1 的逐行 `sort_order` 存储重复表达顺序，容易产生两种事实源。最终选择由子节点的父 id 表达归属、由 `sort_order` 表达顺序。
- **新增与 `ResourceAuthoringMethod` 并行的创建方式枚举值**：当前导入路径复用同样的 manual/aiReference 语义，Phase 0 不发明第三个值。
- **为契约层引入 Flutter/SQLite 类型**：契约必须能在纯 Dart 测试中编译，并由依赖纯净性测试守护。

## 影响

- 后续阶段实现这些定义，而不是各自定义 Resource/Section/Part。
- `lib/domain/resources/` 必须保持纯 Dart：不得 import Flutter、SQLite、HTTP、`dart:io`/`dart:ui` 或任何外层应用目录。
- 既有 `WorldviewDetails`、`CharacterCard`、`GenerationLimits` 在本阶段保持原样；旧路径的收敛属于 Phase 8/12。

## 兼容与迁移边界

Phase 0 不改变任何现有行为与 v30 数据。`GenerationLimits.detailedWorldviewMaximumCharacters` / `detailedCharacterMaximumCharacters` 仍与冻结容量一致，并由测试守护两者不得静默漂移；等旧生成路径在后续阶段收敛时再统一到 `ResourceLimits`。

---

# 附录 A：Phase 1 持久化落地补充（v31）

Phase 1 把上述契约落成正式的 SQLite 结构。本附录只记录**实现层决策**，不改变任何已冻结语义。

## A.1 三层表

`resources` → `resource_sections` → `resource_parts`，数据库版本 v30 → v31。

- Section 只有 `resource_id`，Part 只有 `section_id`；不存在第四层、Section→Part 直连或任意递归父子列。
- 外键 `ON DELETE CASCADE` 只服务将来的永久清理；当前所有删除都先写 `deleted_at`。
- 索引：`idx_resources_type_updated`、`idx_resource_sections_parent(resource_id, sort_order, id)`、`idx_resource_parts_parent(section_id, sort_order, id)`，与读取排序完全一致。

**唯一一处对 Phase 1 推荐结构的偏离**：`resources` 增加 `status` 列。原因：Phase 0 冻结的 `Resource` 实体带有 `status`，且 `ArchiveNodePatch` 对任意 `NodeId`（含 `ResourceId`）生效，不持久化就无法往返。该列取值仍只来自 `NodeStatus`，未引入新状态。

`resources.schema_version` 固定写 1，仅作后续 metadata 演进的基础设施标记；Phase 0 的实体刻意不带该字段，Domain 不受数据库字段影响。

## A.2 正文位置

`resource_parts.content` 是唯一正文列。`resources` 与 `resource_sections` 上不存在任何 `content` / `content_json` / `parts_json` / `sections_json` / `full_content` 列，`resources.metadata_json` 也不承载整棵树。树读取按节点行组装（`readTree` 一次查询 Section、一次按 `section_id IN (...)` 查询 Part），因此读大型资源不需要解析任何巨型 JSON。

## A.3 metadata 约束（F-3 决策）

`ResourceMetadataPolicy`（仓储层，写入边界强制）：

1. 必须可 JSON 序列化；
2. 序列化后 UTF-8 ≤ **64 KB**——远大于角色 system prompt / first message 等运行时核心字段，又远小于 50,000 字世界观正文（UTF-8 JSON 约 150 KB）；
3. 递归禁止内容容器键（`sections`、`parts`、`content`、`content_json`、`modules`、`blueprint` 等，大小写与分隔符不敏感）；
4. 递归禁止单个字符串长度 ≥ 该资源类型的 `nominal` 容量——整段正文不能塞进一个 metadata 字段。

`authoring_method` / `ai_generation_depth` 是允许写入的**来源信息**保留键，沿用旧列名，供 Phase 2 无损映射。

策略放在仓储层而不是契约层：体积测量需要 JSON 序列化，而契约层纯净性守护禁止序列化调用。Domain 实体保持纯 Dart。

## A.4 排序与并发

- 顺序按 `(sort_order, id)` 解析；允许重复 `sort_order`，相同值时由 id 决定，读取不依赖数据库返回顺序。
- `mount(AppendSection/AppendPart)` 取 `MAX(sort_order)+1`（空父节点为 0）。
- `reorderSections` / `reorderParts` 要求调用方给出全部存活子节点且不重复，顺序在同一事务内整体重写；集合不匹配或出现未知节点即抛 `ResourceTreeConflictException`，已写入的位置随事务回滚。
- `updateResource` / `updateSection` / `updatePart` / `softDeleteNode` 必须携带 `expectedUpdatedAt`，`UPDATE ... WHERE updated_at = ?` 命中 0 行即冲突，绝不静默覆盖。
- 状态变更只能经 `ResourceStateMachines`，仓储层不另写转换判断。

## A.5 局部写与软删除

- 更新一个 Part 只写该 Part 行，并刷新所属 Resource 的 `updated_at`（明确设计的父级新鲜度标记，供资源库按最近修改排序）；兄弟 Part 与 Section 行不被重写。
- 软删除是级联的：删除 Section 会同事务标记其全部 Part，删除 Resource 会同事务标记其全部 Section 与 Part，因此存活树永远不会暴露已删除父节点的子节点。回收站、删除历史、保留期与恢复属于 Phase 9。

## A.6 与冻结实体的关系

Phase 1 **没有**修改 `lib/domain/resources/**`：`Resource` / `ResourceSection` / `ResourcePart` / `ResourceTree` / `NodeId` 全部原样复用。时间戳与乐观锁令牌通过仓储层的 `ResourceNodeState` 暴露，因此 Phase 0 的验收结论继续对当前产物成立。

Phase 2 起如需在实体上直接暴露时间戳，必须先更新本 ADR 并重新评审 Phase 0，而不是在数据库层临时扩展。

---

# 附录 B：Phase 2 旧数据迁移决策（v32）

Phase 2 把 legacy 资源映射进附录 A 建立的内容树。本附录记录**迁移层决策**，不改变三层契约。

## B.1 迁移审计表（独立表，不加列）

新增 `resource_migration_records`，主键 `(source_table, source_id, migration_version)`，字段：`source_hash`、`status`、`resource_id`、`error_reason`、`raw_payload`、`created_at`、`updated_at`。

选择独立表而不是给 `resources` 加列，原因有二：映射失败的源行根本不会产生 resource，仍必须留下可诊断记录；且 Phase 1 的三张表已被验收，不应为迁移再改其形状。

## B.2 确定性 ID：重跑安全的结构性保证

资源 ID 固定为 `res_legacy_<source_table>_<source_id>`，Section / Part 也使用确定性 ID（`sec_legacy_...`、`part_legacy_...`）。

这使得"第二次执行不产生第二棵树"由主键约束保证，而不是只靠审计逻辑；同时让 metadata 可以引用它引用的那个节点，并让"树已写入但审计写入前进程中断"这种时序可被检测与修复。

## B.3 状态与跳过规则

`status ∈ {pending, succeeded, failed, source_changed}`：

- 已 `succeeded` 且 `source_hash` 与源行当前哈希一致 → 跳过，不产生任何写入。
- 已 `succeeded` 但源行内容变化 → 记录为 `source_changed`，**不覆盖已迁移的树**，也不产生重复节点。
- `source_changed` 且源行哈希回到已迁移值 → 自愈回 `succeeded`。
- `failed` → 每次运行重试（用户可能修复了数据）；成功则转为 `succeeded`。
- 树已存在但无审计记录（中断场景）→ 补记 `succeeded` 并跳过。

`source_hash` 只覆盖内容相关列，因此与内容无关的写入不会把资源误判为 stale。

## B.4 单资源事务与隔离

每个资源在一次 `db.transaction` 中写入 resource + sections + parts；失败只回滚该资源，批次继续。失败记录在事务之外单独写入，因此失败事实一定被保留。旧表行在任何路径下都不被修改或删除。

## B.5 映射规则

- 世界观：`modules` 按既有显示顺序（`WorldviewDetails.moduleKeys`）转为 Section；模块的 `content`/`summary` 与 `items[]` 逐项转为 Part；模块级 `status` 转成 Part 的 `NodeStatus`，从而保留 draft/confirmed/archived 的 canon 语义。
- 无法识别的模块键与 `detail_json` 顶层未知键 → `其他资料` Section，不丢弃。
- `entries_json`：正文进 Part（标题为触发键），触发配置（probability/sticky/insertion_order/enabled 等）进 metadata 的 `legacy_world_entries`，保持机器可读，供 Phase 10 重建 WorldEntry。
- 角色 / NPC：camelCase 与 snake_case 别名统一后按语义分组（概述、人格、外貌、剧情、行为指令、能力、世界关系、基本档案、自定义属性、备用开场、其他创作资料、其他资料）；自定义属性按原顺序保留 name/value/importance，类型信息进 metadata 引用。
- 空字段不创建空 Section；未知字段进入 `其他资料`。
- 卡片信封（`spec`、`data`、`avatar` 等）不参与正文。

## B.6 运行时字段的唯一事实源

`description`、`personality`、`scenario`、`first_mes`、`mes_example`、`system_prompt` 的正文**只存在 Part**；`metadata.runtime_node_refs` 只保存这些字段到 Part ID 的引用。

Phase 10 依 metadata 引用构建 runtime，Phase 7 编辑 Part 立即生效，同一文本全程只有一份，不存在互相竞争的事实源，也不违反 F-3 的 metadata 体积约束。

## B.7 损坏 JSON

严格解码；失败即抛 `LegacyMappingException`，**绝不用 `{}` 覆盖**。源行保持原样，审计记录写入 `error_reason` 与隔离字段 `raw_payload`（源行 payload 原文）。`{}` 这类"空但合法"的 payload 不算损坏，仍会产生资源（无 Section），保证资源数量不减少。

## B.8 兼容读取优先级

`ResourceReadFacade`：

1. 已迁移且哈希仍一致 → 新树；
2. 只有新树、没有旧行（新模型创建的资源）→ 新树；
3. 否则 → 旧表，并给出原因：尚未迁移 / 迁移失败 / 旧数据已变更 / 新树缺失 / 旧记录不存在。

源行在迁移后被编辑时回退到旧表，避免把陈旧内容当作最新内容返回。该层只读，旧表不会被它写入，因此不存在双写；Phase 12 整体删除。

## B.9 接入时机

迁移服务是正式入口，但 Phase 2 **不在启动或任何 UI 中自动调用**（"不提供用户手动迁移按钮"、"不改变创建入口"）。因此 Phase 3 / Phase 11 切换创建入口与资源库读取之前，兼容读取一律走旧表回退，行为与今天完全一致。切换点见 STATUS 的 Phase 2 Handoff Notes。

## B.10 已知边界

metadata 的 64 KB 上限（F-3）会限制极大世界书的 `legacy_world_entries` 配置：此时该资源迁移失败并留下可诊断记录，源行与正文不受影响。若后续阶段需要支持更大配置，应为本就属于 runtime 的条目配置提供独立存储，而不是放宽 metadata 上限。

---

# 附录 C：Phase 3 统一创建管线（v33）

Phase 3 让所有创建入口共用一条管线。本附录记录**创建层决策**，并明确本阶段已交付与尚未交付的边界。

## C.1 两种创建语义，一个枚举

`CreationMethod` 继续使用 Phase 0 冻结的两个取值 `manual` / `aiReference`（决策已确认：不新增第三值、不改名）。Phase 3 的"AI 创建"就是这个 `aiReference` 值，语义上只有"手动"与"AI"两类。

## C.2 ReferenceSource 是来源，不是模式

`ReferenceSource { none, text, file, existingResource }` 只描述参考材料从哪来。禁止出现 `textImport` / `fileImport` / `worldviewImportMode` 这类"导入模式"枚举——文本、文件、已有资源都必须走同一个 `CreationMethod`。

参考材料正文保存在 `resource_creation_sessions.reference_body`（Phase 4 规划需要它），但只记录来源元数据，且正文绝不写日志、不进 `resources.metadata_json`（只记录 kind / label / 字数 / 被引用资源 id）。

## C.3 创建会话状态

`CreationSessionStatus { draft, validating, persisted, planning, completed, failed, cancelled }`，转换表由 `ResourceCreationStateMachine` 单一持有。

它与冻结的 `GenerationStatus` 是**映射关系而非同一张表**：`planning` / `completed` / `failed` / `cancelled` 复用相同拼写与终态语义，另外三个状态表示创建特有的前置阶段。两处刻意的差异：失败的会话经 `validating` 重试（而非经 `planning`），`completed` 只允许经 `planning` 重来。由 `statusNamesMatchFrozen()` 与 `terminalsOnlyExitThroughRetry()` 两个断言守护，避免后续阶段悄悄把终态语义改掉。

## C.4 幂等

`resource_creation_sessions.idempotency_key` 唯一。同一 key 再次提交：已进入 `persisted` / `planning` / `completed` 的会话直接复用（不产生第二个资源）；`failed` 允许重试；`cancelled` 拒绝；同一 key 用于不同 resourceType / method / name 时抛 `ResourceCreationIdempotencyConflict`，绝不静默复用。

手动路径的资源 id 由会话 id 派生（`res_<sessionId>`），因此"树已写入但会话未更新"的中断可被检测并和解（reconcile），而不是重插出第二棵树。

## C.5 AI 路径只建立会话

AI 创建在本阶段**不生成任何正文**：只写会话与参考材料，状态停在 `planning`，`pendingPlanningSessions()` 把 session 交给 Phase 4。此阶段不调用世界观/角色正文 Prompt，不建 Section/Part 规划任务，不流式生成。

## C.6 手动路径一个事务

`createResourceTree` 在单个事务中写入 resource + sections + parts；失败整体回滚，会话标记 `failed` 并记录原因，不留 orphan Resource / Section / Part。入口已经生成好的内容通过 `ResourceCreationRequest.initialSections` 交给管线，因此"把入口改接到管线"不会丢内容；默认仍是空内容树。

## C.7 本阶段尚未交付（明确交接）

Phase 3 的核心管线已落地并有测试，但以下两项属同一阶段的后半段，尚未完成，因此 Phase 3 不标记为 `IMPLEMENTED`：

1. **入口改接**：`ResourceCrudController`、`import_use_cases.dart`、`ResourceLibraryImportController`、`ResourceCardImportController`、`SceneBatchImportController`、Adventure Wizard 的保存路径、`character_card_edit_page`、`app_dialogs`、`character_manager` 目前仍直接写旧表；需要改为构造 `ResourceCreationRequest` 并调用本管线（旧页面按方案只保留壳层，但持久化必须统一）。
2. **树 → Adventure 可消费视图投影**（已确认决策）：新建资源只写内容树，而 Adventure 仍从旧表构建快照。因此需要一层"内容树 → `WorldviewPreset` / `CharacterCard` 形状"的只读投影，让 Adventure setup 与 Wizard 能消费新资源，且快照结构与今天一致。这一投影是把 Phase 10 的一小部分提前，属已确认的范围。

此外，资源库读取需要切到 Phase 2 的 `readResourcePreferringTree`，否则只写内容树的新资源在资源库里不可见。

---

# 附录 D：Phase 4 自适应大纲规划决策与消费边界（v35）

Phase 4 引入了自适应大纲规划模型（`ResourceBlueprint`）、结构与容量校验器（`BlueprintValidator`）、大纲仓储（`ResourceBlueprintRepositoryImpl`）与统一规划调度器（`BlueprintPlanner`）。本附录记录**大纲规划层架构决策、消费驱动机制与阶段交接边界**。

## D.1 大纲规划职责边界：只规划结构，不生成正文

AI 资源创建采用分阶段受控演进：
1. **大纲规划阶段（Phase 4）**：根据输入的 `ReferenceSource` 生成动态结构树大纲（资源建议名、简短摘要、动态 Section 列表、每个 Section 的 Part 目标、预计字数与依赖关系）。此阶段严格禁止生成长文本正文，不污染正式内容树。
2. **正文生成阶段（Phase 5–6）**：用户确认大纲后，事务化落库创建占位节点与 `resource_generation_tasks` 任务行。Phase 5 提供按 DAG 拓扑调度的增量 Part 正文挂载协议；Phase 6 提供 Streaming Resource Studio 统一交互工作台。

## D.2 ID 池与 DAG 依赖守卫

1. **客户端预分配 ID 池**：规划 Prompt 中由客户端预分配合规的节点 ID 池（Section 上限 12，Part 上限 36），模型只引用池中 ID，防止产生不受控的游离节点。
2. **三色标记严格 DAG 检测**：`BlueprintValidator` 执行深度优先搜索，严格拦截自环（A→A）、双向环（A→B→A）以及多节点回路（A→B→C→A），确保任务依赖图严格无环。
3. **容量预算唯一真实来源**：容量阈值以 `ResourceLimits`（世界观 50,000 字、角色/NPC 5,000 字）为唯一判定源，在规划阶段提前校验所有 Part `estimatedLength` 之和，杜绝规划期预算失控。

## D.3 确认事务原子性与归属安全边界

1. **单事务确认原子性**：`confirmBlueprint` 在单个 SQLite 事务中完成大纲状态推进（`draft -> confirmed`）、创建会话终态标记（`completed`）、正式资源树写入（占位资源、章节与小节）以及生成任务队列建立。任一环节出错整体回滚，无残留孤儿数据。
2. **所有权隔离守卫**：确认大纲时若指定或复用既有资源 ID，必须校验其 `metadata_json.creation_session_id` 是否为本会话 `sessionId`，或其 ID 是否与会话预分配的 `resource_id` 一致。严禁跨会话覆盖或重写他人资源。
3. **终态守卫与落库前重校验**：已处于 `confirmed` 或 `completed` 的会话禁止重复 replan 生成死 revision；确认事务提交前必须执行 `BlueprintValidator.validate(blueprint)` 二度核验。

## D.4 规划栈消费管道与交互式前台接手阶段（B1 架构决策）

Phase 3 留下的接缝 `pendingPlanningSessions()` 与 `session.awaitsPlanning` 的消费机制决策如下：

1. **生产消费管道在 Phase 4 全面打通**：
   - `ResourceCreationPipeline` 原生组装 `IResourceBlueprintRepository` 与 `BlueprintPlanner`，对外暴露 `plannerWithGateway`、`planAiSession` 与 `confirmAiBlueprint`；
   - `LegacyCreationBridge` 统一暴露 `pendingPlanningSessions()`、`planAiSession(...)` 与 `confirmAiBlueprint(...)`；
   - 业务入口用例（`ImportWorldviewUseCase`、`ResourceCardImportUseCase`、`SceneBatchImportUseCase`）以及控制层（`ResourceLibraryImportController`、`ResourceCardImportController`、`ResourceCrudController`）均已获得直连规划与消费能力，消除了“无调用方”和“死代码”风险。
2. **前台交互式驱动明确归属 Phase 6（Streaming Resource Studio）**：
   - Phase 4 方案明确限定范围为领域契约与规划栈，**不做 Studio 流式展示、不实现局部重写**；
   - 大纲规划需要当前活跃的用户 LLM 凭证（`LlmGateway`），且契约明确规定必须经由「用户审阅与确认」方可落库为正式占位节点与任务。无界面的 CRUD 控制器或后台线程不应在脱离用户界面的情况下私自自动确认大纲；
   - 因此，完整的端到端交互闭环（用户发起 AI 创建 -> 进入工作台实时生成大纲 -> 用户审阅/重新规划 -> 用户确认大纲 -> 唤起 Phase 5 增量生成）正式交由 **Phase 6（Streaming Resource Studio）** 的 `ResourceStudioController` / `features/resource_studio/` 驱动并闭环。

# 附录 E：Phase 8 容量追踪与语义压缩决策（v39）

Phase 8 只建立“测量”和“候选”，不建立“替换”。以下决策冻结本次实现的边界。

## E.1 容量只由一次聚合查询得出，缓存列只是投影

`resources` 新增 7 个容量缓存列（`measured_char_count`、`measured_token_estimate`、
`section_count`、`part_count`、`archive_char_count`、`capacity_status`、
`capacity_measured_at`）。缓存列不是事实来源：权威值始终由 `resource_capacity_repository`
中固定条数的聚合语句即时计算，再由 `ResourceCapacityService.measure` 回写。

- 测量成本与 Section/Part 数量无关（单条 `GROUP BY`）；测试以“2 Part 树与 400 Part 树发出
  完全相同条数的 SQL”作为证据，而不是只依赖代码阅读。
- 缓存列默认 `0` / `'normal'` / `NULL`，对旧数据完全安全；未测量过的资源 `readCached`
  返回 `null` 而不是伪造成 0。
- 列名刻意不含 `content`：Phase 1 的结构守护要求 `resources` 不出现正文列，这里两个列
  是计数投影，不是文本。

## E.2 触发阈值来自冻结的容量策略，不新增第二套数字

- `overflow` 判定沿用 `ResourceLimits.policyFor(type).absoluteCharacters`。
- `elastic` 触发按 **nominal** 预算的比例判定，默认阈值 `1.0`，即“正好等于 nominal 仍是
  normal”，与 `ResourceCapacityPolicy.statusFor` 的含下界语义一致。
- 单节点输入/输出上限分别为 `maxCompressionInputCharacters` /
  `maxCompressionOutputCharacters`；上下文预算为 `resourceContextTokenBudget` 与
  `compressionTriggerContextTokens`。
- 阈值集中放在 `resource_limits.dart`，继续满足 Phase 0 的“容量数字只有一个来源”守护。

## E.3 压缩只产出候选，绝不替换正式 Head

Phase 8 的压缩链路没有任何语句写入 `resource_parts.content`：

- `resource_compression_jobs` 记录按 `(resource_id, scope, target_node_id, source_token)`
  去重的任务；部分唯一索引再保证同一目标同时只有一个未结束任务。
- `resource_compression_candidates` 保存压缩正文与保留项清单；`validation_state` 只能是
  `validated` / `rejected`，`applied_at` 恒为 `NULL`。
- “用户确认后替换正文”属于 Phase 9 的 Revision 安全边界，本阶段只提供候选与
  `potentialSavedCharacters` 统计。
- 因此 STATUS.md 的跨阶段风险“Phase 8 不得自动发布压缩结果或替换正式 Resource Head”
  在实现层面成立，而不是仅靠约定。

## E.4 压缩任务以有限节点为边界，且重试有硬上限

- 目标窗口是“一个 Part”或“一个能放进 `maxCompressionInputCharacters` 的 Section”；
  超出窗口的 Section 会被拆成逐 Part 任务，任何一次请求都不会携带整棵资源树。
- 压缩任务是 `CompressionJobStateMachine` 的受控状态机；`failed` 只能经 `queued`
  回到执行态，且 `attempts` 达到 `maxCompressionAttempts` 后 `retryJob` 直接拒绝。
  `drain` 从不重试失败任务，避免无限重试。
- 入队只做测量与落库，不发起模型请求，因此离开编辑器仅排队、不阻塞导航。

## E.5 压缩结果必须通过可证明的保留校验

`CompressionValidator` 只检查无需模型即可证明的性质：结果必须更短且落在预算内；
模型声明的实体、关系、时间线必须真实出现；调用方给出的硬性保留词（资源名、节点标题）
必须在**原文中本来存在**才被要求保留，避免对模型提出它无法满足的要求。

校验失败时原稿完全不变，任务记为 `failed` 并带可读原因，等待显式重试。

## E.6 上下文压缩按固定优先级打包，且不做 substring 截断

`ResourceContextCompressor` 以 `currentSection > currentState > unresolvedEvents >
recentPlot > historicalSummary` 的顺序，在 token 预算内选择**完整片段**：要么发送候选的
压缩摘要，要么整体丢弃并记录原因，绝不把一段正文截成半句。未打包总量（`ungroupedTokens`）
用于判断是否需要压缩，打包结果严格有界（`withinBudget` 由构造保证）。

Phase 8 不修改 Phase 5 的 `PartGenerationPromptBuilder` 与生成协调器：上下文压缩器面向
压缩链路与 Phase 10 的 assembly，避免改变已验收的生成协议行为。

## E.7 数据库与迁移

v38 → v39 的迁移只做三件事，且全部幂等：`safeAddColumn` 增加容量缓存列、
`CREATE TABLE IF NOT EXISTS` 建立压缩任务与候选表、建立索引。既有 `resources` /
`resource_sections` / `resource_parts` 行不被改写，`user_version` 单调提升到 39。

# 附录 F：Phase 9 可恢复边界决策（v41）

Phase 9 为生成、编辑、重写、压缩与删除建立可恢复边界。本附录记录**实现层决策**，不改变任何已冻结语义。

## F.1 revision 是增量链，不是整树快照

`resource_revisions` 保存元数据与 `parent_revision_id`，`resource_revision_nodes` 只保存
**相对父 revision 变化的节点**（`is_removed = 1` 为墓碑）。还原任意历史状态时从
`parent_revision_id IS NULL` 的根 revision 逐级 `applyDelta`。

- 单节点编辑只写 1 行增量，成本与资源大小无关，直接满足 Phase 9 方案「不得每次 tick 复制完整资源」。
- 首次 revision 必然是完整快照（无父可重放），这是链的根。
- 清理只能删除链的**最老前缀**，且删除前必须把第一个保留者根化（用完整快照替换其增量、清空 parent），
  否则存活链会断裂。这条规则是增量模型的直接推论，不是可选优化。

## F.2 head 唯一性由数据库保证

`resource_revisions` 上的部分唯一索引 `(resource_id, kind) WHERE is_head = 1` 使
「每个 (resource, kind) 至多一个 head」成为数据库事实。应用层只负责在插入新 revision 前把旧 head
置 0，两者在同一事务内完成，因此不存在两个 head 的窗口。

`ResourceRevisionKind.latestHead` 与 `assembly` 是**两条独立链**：发布 assembly 版本会新建一条
assembly revision，而不是把 latest-head 行改头。这样 `latestHead()` 永远不会漂移到已发布版本，
两个指针可以合法分叉。

## F.3 不变量：head 等于当前存活树

所有写路径在改动树之后必须再抓取一次 revision；抓取在「存活树已等于 head」时是零写入的 no-op，
因此防御性 before 抓取在正常路径上不产生成本。

刻意保留的性质：**漏掉一个 hook 只会让下一次 revision 更粗，不会丢数据**。这与「失败保持原 head」
一起，使 revision 系统对未来的新写路径是退化安全的，而不是必须一次性接全。

## F.4 有损操作的 before/after 与事务边界

`IPartCommitRevisionBoundary` 的钩子接收调用方已经打开的 `DatabaseExecutor`，而不是自己开事务。
原因：before 快照若在提交事务之外完成，一次失败的提交会留下一个从未与树匹配的 revision。
因此生成提交、手动编辑、压缩发布、恢复、删除全部满足「before 抓取 → 业务写入 → after 抓取」
同事务提交或整体回滚。

## F.5 压缩发布：Phase 8 候选的唯一合法出口

Phase 8 只写候选且 `applied_at` 恒为 `NULL`。Phase 9 的 `CompressionPublisher` 是唯一把候选
变成正式 head 的路径，且：

- `applied_at` 的 CAS（`WHERE applied_at IS NULL`）与正文替换同事务，重复发布是幂等 no-op，
  并发发布输的一方整体回滚；
- 只接受 **part 范围**的候选。section 候选没有 per-Part 映射（Phase 8 INFO-005），
  此时显式拒绝而不是猜测切分；
- 压缩前的正文由 before 抓取保留，因此发布完全可回退。

## F.6 自动保存：journal 先落盘的 write-ahead 结构

`resource_autosaves` 只存**尚未写入正文树**的草稿。flush 分两步：

1. journal 行（独立事务）；
2. 一个事务内写正文 + 校验降级 + 生成任务重置 + revision after 抓取 + 删除 journal 行。

因此崩溃窗口只有「journal 已落盘、正文未写」这一种，`reconcilePendingDrafts` 可以把它判定为
`needsUserDecision` 而不是丢失；反过来「正文已写、journal 未删」会被判定为 `alreadyApplied` 并清理。
同一节点至多一条未解决草稿（部分唯一索引），所以连续的 debounce 不会累积成按键历史。

流式生成**不写这张表**：只有校验通过的 Part 经生成提交链路落库，未确认 chunk 既没有 journal 行
也没有 `completed` 状态，因此重启后不会伪装成已完成。

## F.7 回收站：删除只改 live view

删除 = 写 `resource_trash` 行 + `deleted_at` 软删除（同事务）。正文始终留在
`resource_parts.content`，所以回收站不复制长文本，恢复也不需要重放序列化树。

恢复按「原父节点是否存在」确定性分流：

- 原父节点存活 → 恢复原位与原 `sort_order`；
- Part 的原 Section 不存在或仍在回收站 → 在 Resource 根下新建 Section 并放入，
  并返回 `TrashRestorePlacement.recreatedSectionUnderRoot` 让 UI 明确提示；
- 节点行本身已消失 → 显式失败并保留条目。

删除与恢复都带有「只处理同一删除时间戳」的语义：先单独删除、后被父节点级联删除的节点保留自己的
时间戳，恢复父节点不会把它一起复活。

永久删除是显式的第二次操作，服务层拒绝删除仍存活的节点（因此陈旧的回收站行无法删除活数据）。

## F.8 清理只有一种合法形态

- Revision：只删超过保留期**且**不被当前 head / assembly 链 / 回收站未解决条目引用的最老前缀，
  删除前先根化；链断裂时报告并跳过，不截断历史。
- Trash：只删 `expires_at` 已过且未恢复的条目，保留期内一律不碰。清理入口在用户打开回收站时执行，
  而不是应用启动时，使保留期缺陷的影响面被限制在用户已经看见的回收站内。

## F.9 事务内必须使用 DatabaseExecutor 变体

sqflite 的一连接事务模型下，在事务回调里通过 `Database` 对象发起任何读写都会**永久等待**
（只打印 “database has been locked” 警告，不抛错）。因此 Phase 9 为所有需要被事务内调用的仓库方法
补齐了 `...InTransaction(DatabaseExecutor, ...)` 变体，并在接口注释中写明约束。

本次实施中 `restoreRevision` 与回收站服务曾因此出现真实死锁，由集成测试捕获；这类缺陷无法靠代码
阅读发现，因此 Phase 9 的定向测试全部使用真实 SQLite 而不是内存 fake。

## F.10 与 Phase 10 的边界

`ResourceRevisionSelector.select()` 只解析**revision 指针**（哪条 revision 存在、assembly 指针的
content hash 是否仍等于 latest head），据此返回 `preparing` / `ready` / `stale`。
它刻意不判断「资源是否可以被 Adventure 消费」——那是 Phase 10 的 readiness 策略。
