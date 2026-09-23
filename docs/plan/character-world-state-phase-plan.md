# 角色状态与世界观状态阶段执行计划

> 规划文档，不授权或包含实现。基线见[总设计书](../design/character-world-state-system-design.md)。任何阶段开始前需再次检查 GitHub `main`、当前 schema、实际调用链及本地用户改动。

## 总体约束

- 保持 Resource Pipeline、Resource revisions、Assembly 冻结基线与数据库旧数据兼容。
- 动态事实以 Adventure + branch 为范围；现有 Runtime HEAD/commit/change/overlay 及事务是唯一 authority。不得未经审计新增并行 `character_state_*` / `world_state_*` 可写 current/event 系统。
- SQLite 继续本地核心存储；所有变更可按稳定 ID、schema version 和 parent/revision 同步。AI 仅产 proposal。
- UI 是一等目标，移动端优先，遵守 320 px 硬门槛及长文本/大字/SafeArea/键盘规则。
- 先写纯设计/契约，再分阶段实施。各阶段单独提交、聚焦审查；不在本规划中执行任何 Phase。

## Phase A：基础领域模型

**目标**：建立清晰的 Profile/Definition 与 branch Runtime State、typed Event、Snapshot projection 契约；不实现 UI。

**输入**：总设计书；当前 `CharacterCard`、`WorldviewDetails`、Adventure baseline、`RuntimeStateChangeProposal`、`SceneState`、runtime commit/overlay、字段 validator 与本地化契约。

**输出**：纯 Dart typed stable entity/path/value/event/provenance 模型；proposal 与 accepted event 区分；schema/version compatibility 策略；基线+overlay+revision 的纯状态投影/diff；字段分类表（immutable/profile、动态 state、scene-local、机械 state）。不含 Flutter/SQLite/网络依赖。

**涉及模块**：`lib/domain/adventure/` 或经架构确认的现有纯领域目录；`lib/models/adventure_runtime_state.dart` 的接口兼容层；相关 architecture docs。最终目录需以依赖图为准。

**预计风险**：现有 path 字符串与 `Object?` 值类型过宽；领域词义重叠；已有自由文本 reason 误作稳定事件标签；错误迁移旧数据；纯领域依赖边界被破坏。

**验收标准**：角色身份与动态状态分类覆盖当前字段并说明未分类项；世界/场景/机械状态边界明确；event ID/参数 locale-independent；Proposal 不能直接持久化；未知 schema 安全兼容；纯模型序列化、校验、差异和边界测试通过；无 UI/SQLite 依赖。

## Phase B：数据库与 Repository

**目标**：SQLite 原子保存/读取可分页的 typed 状态变化，并保留现有 Runtime HEAD/overlay/archive 单一 authority。

**输入**：Phase A 冻结模型；DB v44 schema 与所有 runtime commit transaction、branch fork/delete、adventure delete、resource purge 调用链；同步冲突设计。

**输出**：经审计的最小 migration（仅在现有表不能表达时新增窄 event metadata 表）；Repository 接口、事务写入/分页 timeline/指定 revision 投影；旧库升级和回滚/恢复兼容策略。

**涉及模块**：`DatabaseService` migration；`adventure_repository.dart` / `adventure_repository_impl.dart`；runtime resolver/read ports；migration 与 repository tests。

**预计风险**：迁移锁表/耗时、部分写导致 HEAD 与 archive 不一致、幂等冲突、branch fork 遗漏 overlay、历史行丢失、外键删除破坏追溯、数据增长、同步未定策略。

**验收标准**：旧 DB 到新版本 migration 幂等且不丢数据；turn/message/commit/change/overlay/HEAD 同事务；request ID 重放幂等、expected revision 冲突可识别；history 游标稳定分页；恢复创建新 revision，原 commits 仍可读；所有历史可从 frozen baseline + archive 还原；无第二个可写当前态；migration、事务、并发及长历史测试覆盖。

## Phase C：状态变化引擎

**目标**：把合法候选确定性应用为 Runtime commit，并统一 AI、用户和系统变化边界。

**输入**：Phase A typed proposal/event 与 Phase B repository；现有 Turn Settlement、RuntimeStateValidator、RPG effects 和 scene dialogue transaction。

**输出**：应用服务/规则引擎；字段 schema 与跨实体 invariant；权限/来源策略、审核需求和冲突结果类型；commit/event idempotency。

**涉及模块**：Adventure application/use cases；validator/settlement 集成；repository commit coordinator；纯规则及应用层测试。

**预计风险**：模型候选越权、derived 与 primary 混淆、迟到 proposal 覆盖用户编辑、角色删除或 branch 切换竞态、同 turn 重复应用。

**验收标准**：非法路径/类型/实体范围全部拒绝；AI 候选默认非事实且按置信/影响规则待审；user/system 来源不能绕过领域不变量；stale proposal 不静默覆盖；一个 turn 的消息及各类状态变更原子提交；所有 source 有 provenance 与审计结果；取消/重试保持幂等。

## Phase D：AI 状态提取

**目标**：从对话中识别可能的角色和世界变化，作为可审阅 proposal 进入既有状态变化引擎。

**输入**：Phase A/C 稳定协议；生成服务统一的模型配置、timeout/cancellation/error 处理；Turn Settlement 与 source message/context snapshot。

**输出**：结构化提取契约、置信度标定、证据引用、候选分组与人工确认策略；通过既有 Pipeline 的 adapter，不直写数据。

**涉及模块**：turn settlement / prompt builder / generation decoder；proposal validator；诊断与可观测性；合约、对抗和集成测试。

**预计风险**：幻觉、否定/假设/回忆时态、低置信错误写入、token/延迟、重复抽取、长文本污染、未翻译 event caption。

**验收标准**：仅提取当前叙事中明确变化，支持 no-op；每 proposal 引用 turn/message 与证据片段 ID；结构损坏、超限、未知字段均安全拒绝；不会将模型生成的 reason 当事实；取消/超时/非 2xx 不阻塞 session；AI 候选未通过引擎前不能进入 prompt 当前态。

## Phase E：UI 展示

**目标**：提供角色当前状态、角色时间线和世界当前状态的完整页面化体验，移动端优先。

**输入**：Phase B 读取/diff/paging；Phase C 审核、编辑、restore 用例；项目导航、主题、localization 与 responsive test helpers。

**输出**：Character State Page、Character Timeline Page、World State Page；字段分组、事件过滤/分页、来源和差异详情、AI proposal 审阅、编辑/恢复预览与空/加载/错误状态。

**涉及模块**：Adventure presentation/navigation；feature controller/provider；领域视图模型；ARB localization；`test/widget/...` viewport tests。

**预计风险**：长事件列表性能、误把基线当当前值、差异丢失关键含义、复杂表格在窄屏溢出、恢复误操作、敏感 hidden motivation/secrets 泄露、语义颜色依赖。

**验收标准**：无主流程 Dialog；320×568、360×640、390×844、412×915 和至少 768×1024/桌面均无 layout exception；长中英文、大 text scale 可读；按钮可达且触控尺寸合理；Timeline 分页且 revision 排序稳定；before/after/source/reason 可辨识；restore 有 diff 预览且不可删除历史；Widget 测试覆盖主要状态和核心操作。

## Phase F：上下文权重系统

**目标**：在有限 Context budget 内按相关性、稳定性和权威性注入 Profile、当前 state、近期 event 与历史。

**输入**：Phase A typed facts；Phase B revision/timeline reads；Phase D provenance；现有 ContextOrchestrator、RuntimeMemoryProjector、token budget 与 context snapshot。

**输出**：可配置/可解释的状态注入优先级；去重、相关 entity 选择、历史检索限额；prompt provenance 诊断。

**涉及模块**：narrative context orchestration、runtime memory projection、prompt construction 与相关 context/token tests。

**预计风险**：历史污染当前事实、重复注入、超出 token 预算、跨 branch 缓存、状态/资源冲突、隐私字段无意注入。

**验收标准**：当前 branch HEAD 对动态事实具有唯一权威；Profile/World Definition 与 runtime state 标签分明；默认不注入完整历史；历史只在相关问题时有界检索；tokens 超限可预测降级且核心当前态优先；context snapshot 记录引用 revision/source；自动化测试覆盖预算、相关性、分支隔离、历史问答与敏感字段策略。

## 跨阶段风险与门禁

- 每阶段开工前复核 `origin/main`、DB schema 和工作区状态；保留用户未提交改动，仅提交本阶段文件。
- 新增表之前必须证明现有 archive/overlay 不能承载需求；migration 必须检查旧数据、事务、幂等、性能和同步兼容。
- 状态变化失败时保留可诊断错误，不允许 empty catch、无界重试、静默回退为另一事实源。
- 阶段验收由独立审核对照本计划、实际 diff 和定向测试；只有通过后才进入下一阶段。
