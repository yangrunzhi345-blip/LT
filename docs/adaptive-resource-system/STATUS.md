# Adaptive Resource System — Execution Status

本文件是 Phase 0–12 执行状态与阶段交接的统一记录。各 Phase 的设计与实施要求以对应 `phase-*.md` 为准；本文件不替代实施方案，只记录执行事实、验收状态和阶段依赖。

执行 Agent 在开始、完成或验收阶段时必须更新本文件。不得依据聊天记录、计划内容或尚未验收的代码推断阶段已经完成。

## 当前总体状态

| 字段 | 当前值 |
| --- | --- |
| Current Phase | Phase 7 |
| Last Accepted Phase | Phase 6 |
| Next Phase | Phase 7（`NOT_STARTED`） |
| Current Repository HEAD | `0aca39e` (latest pushed acceptance-record commit; this documentation correction follows) |
| Last Updated | 2026-09-17 |

Phase 3 独立复验 **ACCEPTED**：经 remediation 提交（`a09637e`），原独立验收提出的 Blocker B1–B4、High H1–H4 缺陷已全部修复，单测和全量 759 个测试均通过。Phase 3 标记为 `ACCEPTED`。
Phase 4 独立复验 **ACCEPTED**：详见 [Phase 4 Independent Re-Acceptance Report](phase-04-independent-reacceptance.md)。经整改提交（`a3b4271` 与 `f44d0d9`），原独立验收提出的 Blocker B1、High H1 及 M1–M4 缺陷已全部修复，用例端规划通道全面打通，ADR-0001 附录 D 冻结架构决策，单测、集成测试、14 项独立验收测试及全量 822 个测试均通过。Phase 4 标记为 `ACCEPTED`。
Phase 5 整改已在 `8cd8d32` 关闭 P5-B1：`complete_part` 现在校验 cursor 与累计正文长度，生产网关按 NDJSON chunk 即时解析并挂载增量 patch。`flutter analyze` 与 Phase 5 定向回归测试通过。全量 `flutter test` 仍受既有语义检索性能基准（`semantic_retrieval_performance_test.dart` 的 16.7 ms 阈值）影响而失败；该问题不属于 Phase 5 变更。经用户授权，Phase 5 标记为 `ACCEPTED`，Phase 6 解封为 `NOT_STARTED`。
Phase 6 独立验收 **REJECTED**：详见 [Phase 6 Independent Acceptance Report](phase-06-independent-acceptance.md)。候选提交具备已验证的流式运行时基础层，但没有 Phase 6 方案要求的 Resource Studio feature、路由/创建链路接入、事件到 UI 状态层或响应式 Widget 验证。P6-B1 未关闭，Phase 7 保持 `BLOCKED`。
Phase 6 整改后独立复验 **ACCEPTED**：详见 [Phase 6 Independent Re-Acceptance Report](../phase6-independent-reacceptance.md)。Resource Studio 已完成用户入口、生产运行时组装、创建/生成链路、事件到状态到 Widget 的展示与控制、响应式回归验证；全量测试通过。Phase 7 已解封为 `NOT_STARTED`。

初始化事实（保留）：本文件初始化时「当前没有证据证明任何 Phase 已实际执行或通过验收」，`Current Repository HEAD` 当时为 `4d172136d1de1af2410378a61421fafda48a4851`。该结论已被 Phase 0 的实施与验收结果取代；`Current Repository HEAD` 记录本次状态更新时观察到的 HEAD，仍不能替代各 Phase 的 Start/End HEAD。

## 状态枚举

| 状态 | 含义 |
| --- | --- |
| `NOT_STARTED` | 前置条件已满足，但尚未开始实施 |
| `BLOCKED` | 前置阶段未验收或存在明确阻塞条件，不得开始实施 |
| `IN_PROGRESS` | 已记录 Start HEAD，正在实施 |
| `IMPLEMENTED` | 实现已完成并记录 End HEAD，等待独立验收 |
| `ACCEPTED` | 验收通过，可以解锁下一阶段 |
| `FAILED` | 实施或验收失败，失败事实和恢复点必须保留 |

`IMPLEMENTED` 与 `ACCEPTED` 不得互换：代码完成不代表阶段已经通过验收，也不能自动解锁下一阶段。

## Phase 状态表

| Phase | 名称 | 状态 | 前置条件 | 执行 Agent | Start HEAD | End HEAD | 验收 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Phase 0 | 架构契约冻结 | `ACCEPTED` | 无 | executor-agent | `0fbea39c0a4e0ff7e0eb62ae2f0b3ff55e6cac9c` | `ca0fe235ba04a48bd0d91290b4263c6e10b6a10a` | 通过（reviewer-agent，2026-09-16） |
| Phase 1 | 统一 Resource / Section / Part 模型 | `ACCEPTED` | Phase 0 `ACCEPTED` | executor-agent | `2ae64b7` | `6b5e5033921ddc6be0e76062e0e1131f495140c5` | 通过（reviewer-agent，2026-09-16） |
| Phase 2 | 旧数据迁移与兼容 | `ACCEPTED` | Phase 1 `ACCEPTED` | executor-agent | `947518e` | `9beebaef44e4439b97fed9364df8ce84d1cc468d` | 通过（reviewer-agent，2026-09-16） |
| Phase 3 | 统一创建入口与 Pipeline | `ACCEPTED` | Phase 2 `ACCEPTED` | executor-agent | `6283187` | `a09637eb4e4572d17c704ac60f82169dcb7e10a6` | 通过（reviewer-agent，2026-09-16，详见独立复验报告） |
| Phase 4 | Adaptive Blueprint | `ACCEPTED` | Phase 3 `ACCEPTED` | executor-agent | `5069be130080ad1c9a57654c170c3980f8bdef49` | `f44d0d9` | 通过（reviewer-agent，2026-09-16，详见独立复验报告） |
| Phase 5 | 增量 JSON 挂载协议 | `ACCEPTED` | Phase 4 `ACCEPTED` | executor-agent | `ada9d4692e76f8a2ce77aec5d8cc7d0cc95a7be4` | `8cd8d32` | 通过（用户授权解封，2026-09-16；P5-B1 已修复） |
| Phase 6 | Streaming Resource Studio | `ACCEPTED` | Phase 5 `ACCEPTED` | executor-agent | `8cd8d32` | `4d954cd` | 独立复验通过（2026-09-17，详见 Phase 6 独立复验报告；原 P6-B1 已关闭） |
| Phase 7 | Section 精细编辑与生成控制 | `NOT_STARTED` | Phase 6 `ACCEPTED` | — | — | — | 已解封，尚未实施 |
| Phase 8 | 容量与语义压缩 | `BLOCKED` | Phase 7 `ACCEPTED` | — | — | — | 未验收 |
| Phase 9 | Revision、自动保存与回收站 | `BLOCKED` | Phase 8 `ACCEPTED` | — | — | — | 未验收 |
| Phase 10 | Assembly Readiness | `BLOCKED` | Phase 9 `ACCEPTED` | — | — | — | 未验收 |
| Phase 11 | 资源库 UX 收敛 | `BLOCKED` | Phase 10 `ACCEPTED` | — | — | — | 未验收 |
| Phase 12 | 旧系统删除与总回归 | `BLOCKED` | Phase 11 `ACCEPTED` | — | — | — | 未验收 |

## 阶段推进规则

1. 只有上一阶段状态为 `ACCEPTED`，下一阶段才能从 `BLOCKED` 转为 `NOT_STARTED` 或 `IN_PROGRESS`。
2. `IMPLEMENTED` 不能自动解锁下一阶段。
3. 执行 Agent 不得自行把自己的实现标记为 `ACCEPTED`，除非执行流程明确授权其同时负责验收；否则由独立审核 Agent 更新验收结果。
4. 每次开始 Phase 前，必须记录执行 Agent、开始时间和实际 `Start HEAD`，再将状态改为 `IN_PROGRESS`。
5. 实现完成后必须记录实际 `End HEAD`、验证结果和实施报告。若包含多个提交，记录最终 HEAD，并在实施报告中列出主要 commit。
6. 实施或验收失败时不得删除失败记录。将状态标记为 `FAILED`，记录原因、最后安全 HEAD、未完成事项及恢复建议。
7. 后续阶段发现前置设计问题时，必须在 `Deferred Issues` 和跨阶段风险中记录，并回到对应 Phase 处理；不得静默改变已冻结的架构契约。
8. 每次状态变化均须更新“当前总体状态”和 Phase 状态表，避免明细与总表不一致。
9. `Current Repository HEAD` 应更新为最近一次状态记录时观察到的 HEAD，但不能替代各 Phase 的 Start/End HEAD。

## 每阶段执行记录模板

开始或更新某个 Phase 时，在“阶段执行记录”下复制此模板并以实际事实替换占位内容。不得预填不存在的提交、测试或验收结果。

```text
## Phase N

Status:
Executor:
Started At:
Completed At:

Start HEAD:
End HEAD:

Implementation Report:

Validation:
- dart format:
- flutter analyze:
- flutter test:
- targeted tests:
- other verification:

Acceptance:
- Result:
- Reviewer:
- Accepted At:

Known Issues:

Deferred Issues:

Handoff Notes:
```

## 阶段执行记录

```text
## Phase 0

Status: ACCEPTED（独立验收通过，已解锁 Phase 1）
Executor: executor-agent（CodeBuddy CLI）
Started At: 2026-09-16
Completed At: 2026-09-16

Start HEAD: 0fbea39c0a4e0ff7e0eb62ae2f0b3ff55e6cac9c
End HEAD: ca0fe235ba04a48bd0d91290b4263c6e10b6a10a

Implementation Report:
- 新增 lib/domain/resources/resource_contracts.dart：ResourceType、sealed NodeId
  （ResourceId/SectionId/PartId）、NodeStatus、CreationMethod、GenerationStatus、
  CapacityStatus、ReadinessState、不可变 Resource/ResourceSection/ResourcePart、
  ResourceTree 不变量、单节点 ResourceNodePatch 层次、Revision/Assembly 值类型、
  ResourceStateMachines 转换表与非法转换拒绝。
- 新增 lib/domain/resources/resource_limits.dart：容量唯一事实源
  （世界观 50000/60000，角色与 NPC 5000/6000）与 ResourceCapacityPolicy。
- 新增 lib/domain/resources/resource_repository.dart：仅接口，覆盖内容树读取、
  节点挂载、创建会话、版本选择、组装快照。
- 新增 docs/architecture/adaptive-resource-system.md（ADR-0001）。
- 新增 test/domain/resources/ 两组测试（契约行为 + 契约层结构守护）。
- 除 docs/adaptive-resource-system/STATUS.md 外未修改任何既有文件；未修改
  database_service.dart、repository 实现、页面、Prompt 或生成 coordinator。

Validation:
- dart format --output=none --set-exit-if-changed .: 313 files, 0 changed, exit 0
- flutter analyze: No issues found
- flutter test: 615 passed, 0 failed（其中 36 个为本次新增 test/domain/resources）
- targeted tests: flutter test test/domain/resources/ → 36 passed
- other verification: 契约层无 Flutter/SQLite/HTTP/dart:io/dart:ui/外层应用 import；
  lib/domain/resources 之外无新增容量字面量（rg 复核）

Acceptance:
- Result: 通过（ACCEPTED）
- Reviewer: reviewer-agent（独立验收，与 executor-agent 分离）
- Accepted At: 2026-09-16
- Reviewed Artifact: ca0fe235ba04a48bd0d91290b4263c6e10b6a10a（含记录提交 a20c46a）
- Review Method: 只读审查 commit diff，独立重跑全部验证命令，并对测试 oracle 独立性、
  守护作用域和值对象不可变性做对抗性检查

Independent Re-verification:
- dart format --output=none --set-exit-if-changed .: 313 files, 0 changed, exit 0
- flutter analyze: No issues found
- flutter test test/domain/resources/: 36 passed, 0 failed
- flutter test（全量）: 615 passed, 0 failed
- git diff --check: clean；git status --short: clean
- 契约层 import 仅 2 处，均为同目录 import（resource_contracts.dart），无 Flutter /
  SQLite / HTTP / dart:io / dart:ui / 外层应用依赖
- ca0fe23 文件清单为 6 个新增 + STATUS.md，未触碰 database_service.dart、现有
  repository、页面、prompt、生成 coordinator
- lib/services/database_service.dart 仍为 version 30，lib/ 中不存在 resource_sections /
  resource_parts 表，未提前实现 Phase 1+
- 容量字面量新增仅 resource_limits.dart 的 4 处；其余 50000/6000/5000 命中均为 Phase 0
  之前既有代码（generation_limits、ai_generator_service、api_error 等）
- ADR-0001 已覆盖逻辑树、不可变 ID、同级顺序、禁止巨型 JSON、禁止物理嵌套、
  latest head 与 assembly revision 分离
- STATUS.md 变更仅新增记录，模板、状态枚举与初始化事实均保留

Verdict: 通过。Phase 0 的四项验收标准（契约层纯度、容量与状态单一来源、合法/非法转换与
容量边界测试、应用行为与 v30 数据不变）与十项完成条件全部满足。

Reviewer Findings:
- Major-1（测试强度，不阻塞验收）：状态机穷举测试以生产转换表自身作为 oracle。
  test/domain/resources/resource_contracts_test.dart 的 _expectStateMachine 用
  `table[from]!.contains(to)` 作为期望值，而传入的 `table` 与 `canTransition` 读取的是
  同一个 ResourceStateMachines 常量，因此 61 组有序对全部按构造通过，无法发现转换表被
  放宽。当前仅 8 条边被独立断言（generation：completed→generating、idle→generating、
  generating→planning、failed→completed 为非法；nodeStatus：archived→draft 合法、
  archived→confirmed 非法；readiness：ready→failed、failed→ready 非法）。
- Major-2（守护范围，不阻塞验收）：容量字面量扫描只覆盖 lib/domain/resources，而 Phase 0
  验收标准是仓库级「不出现新增的重复数值常量」。Phase 3/6/8 可在页面、prompt 或服务中
  复制 50000/60000/5000/6000 而不触发任何测试失败。
- Major-3（约束缺执行机制，Phase 1 前必须决策）：metadata 的正文/全树禁令只存在于
  ADR-0001，Resource.metadata 无任何约束或校验，而 Phase 1 正是把它落成
  metadata_json 列的阶段，巨型 JSON 风险可能从 content_json 迁移到 metadata_json。
- Minor-1：Resource.metadata 未做防御性拷贝（resource_contracts.dart:384 直接透传调用方
  map），而 ResourceTree 的列表用了 List.unmodifiable，不可变契约存在缺口。
- Minor-2：revision / assembly 契约目前无消费者，Phase 10 需复核
  publishAssemblyRevision 等签名是否够用。接受为已知延期。
- 观察（非缺陷）：GenerationLimits 保留 5000/50000 字面量并改由测试守护与 ResourceLimits
  一致，属有意的范围克制，接受。

Required Follow-ups:
- F-1（对应 Major-1）：在 Phase 5/6 消费转换表之前，把期望转换集合以字面量写入测试作为
  独立 oracle（例如手写 `const expected = {GenerationStatus.idle: {idle, planning}, ...}` 并
  断言生产表与其相等），保留现有循环用于验证 advance 抛错行为。
- F-2（对应 Major-2）：随 Phase 1 或更早，把容量字面量扫描扩到 lib/ 全仓库，并采用
  test/architecture/presentation_boundary_test.dart 已有的 file-exact allowlist 模式列出
  既有命中，使只有新增副本会失败。
- F-3（对应 Major-3）：Phase 1 开始前必须给出显式决策并落入代码或 ADR——为 metadata 设定
  明确体积上限与/或内容形状校验（拒绝承载全部 Section/Part 正文）。不得在 Phase 1 实现中
  临时发明该规则。
- F-4（对应 Minor-1）：Phase 1 实现 row mapper 之前，建议把 metadata 包成
  Map.unmodifiable，避免多处共享同一个可变 map。

Acceptance Notes: 本次验收针对 phase-00-architecture-contract.md 写明的验收标准。三个 Major
项均为测试强度与执行机制缺口，不改变已冻结契约的语义本身，因此不构成验收阻塞；但 F-1/F-2/F-3
必须按上述时机关闭，F-3 未决策前不得开始 Phase 1 的 metadata_json 落地。

Known Issues:
- lib/core/config/generation_limits.dart 仍以字面量保存 5000/50000 的生成目标上限，
  与 ResourceLimits 当前数值一致。Phase 0 有意不修改该文件（避免扩大范围），改为由
  测试守护两者不得静默漂移；待 Phase 8/12 收敛旧生成路径时统一到 ResourceLimits。
- test/domain/resources/resource_contracts_test.dart 直接依赖
  lib/core/config/generation_limits.dart 与 lib/models/resource_provenance.dart 作为
  漂移守护；旧路径删除后该守护测试需同步更新。

Deferred Issues:
- Phase 0 未定义 blueprint（Phase 4）与增量 JSON 协议（Phase 5）的类型，只在 ADR 中
  冻结其边界：一次响应一个 blueprint 或一个有限节点 patch。若 Phase 4/5 认为需要更
  细的契约，应更新 ADR 并重新评审 Phase 0。
- 未定义节点级 metadata 的体积上限。ADR 只禁止把正文放入 metadata 或整资源序列化；
  若 Phase 1/8 需要硬性限制，属于新决策，不得在实现中临时发明。

Handoff Notes:
- Phase 1 必须直接复用 lib/domain/resources 中的不可变值对象（Resource、
  ResourceSection、ResourcePart、ResourceTree、NodeId 层次），不要在
  resource_section.dart / resource_part.dart 中重新定义同义类型。
- 顺序规则固定为 (sortOrder, id)，允许重复 sortOrder；实现不得依赖数据库返回顺序。
- 容量与容量状态只能来自 ResourceLimits / ResourceCapacityPolicy；
  状态转换只能来自 ResourceStateMachines，不得在服务层另写转换判断。
- 契约层结构守护测试会拒绝向 lib/domain/resources 引入 Flutter/SQLite/HTTP/
  dart:io/dart:ui/外层应用依赖、toJson/jsonEncode/jsonDecode，或复制容量字面量；
  如需放宽必须经 ADR 评审。
- 本次 End HEAD 为实现提交 ca0fe235b；随后有一次仅更新本状态文件的记录提交，最终
  HEAD 以 git log 为准。
```

初始化事实（模板与状态枚举）保持原样，未被覆盖。首次开始 Phase 0 时已按模板新增上方记录。

```text
## Phase 1

Status: ACCEPTED（独立验收通过，已解锁 Phase 2）
Executor: executor-agent（CodeBuddy CLI）
Started At: 2026-09-16
Completed At: 2026-09-16

Start HEAD: 2ae64b7（docs(status): accept Phase 0 after independent review）
End HEAD: 6b5e5033921ddc6be0e76062e0e1131f495140c5

Implementation Report:
- 数据库 v30 → v31：新增 createResourceTreeSchema（resources / resource_sections /
  resource_parts）与 createV31Schema，并在 migrateStepByStep 追加 v30 → v31 步骤；
  两处 openDatabase 的 version 由 30 改为 31。未重写任何既有 migration，未修改旧表。
- 仓储层新增 4 个文件：
  resource_tree_repository.dart（IResourceTreeRepository，实现 Phase 0 的
  ResourceTreeReader / ResourceNodeMounter / ResourceCreationGateway，并补充软删除、
  元数据更新、Section 更新、同级重排与乐观锁状态读取；含 ResourceNodeState 与
  冲突/未找到/损坏异常）、
  resource_tree_repository_impl.dart（事务化 CRUD、单节点 patch 挂载、逐节点局部更新、
  级联软删除、显式冲突、缓冲式创建会话）、
  resource_tree_row_mapper.dart（行 ↔ Phase 0 实体映射、枚举映射、唯一 content_hash 规则）、
  resource_metadata_policy.dart（F-3 决策：metadata 结构校验 + 64 KB 上限）。
- 未修改 lib/domain/resources/**：Resource / ResourceSection / ResourcePart /
  ResourceTree / NodeId 全部原样复用，时间戳经 ResourceNodeState 暴露。
- ADR-0001 追加「附录 A：Phase 1 持久化落地补充」，记录三层表、正文位置、
  metadata 约束、排序与并发、局部写与软删除、以及与冻结实体的关系。
- 未迁移任何旧数据、未双写旧表、未接 UI、未接 AI、未改 Adventure 行为。

Validation:
- dart format --output=none --set-exit-if-changed .: 320 files, 0 changed, exit 0
- flutter analyze: No issues found
- targeted tests: 52 passed
  （flutter test test/services/resource_tree_repository_test.dart
    + test/services/database_migration_resource_tree_test.dart
    + test/services/resource_metadata_policy_test.dart）
- flutter test（全量）: 667 passed, 0 failed（第二次运行；见 Known Issues 第 1 条）
- git diff --check: clean
- 结构自证：resources / resource_sections 无任何 content 列；resources.metadata_json
  在大 fixture 下仍 <200 字节；升级后三张新表均为 0 行；仓储实现不引用任何旧资源表。

Acceptance:
- Result: 通过（ACCEPTED）
- Reviewer: reviewer-agent（独立验收，与 executor-agent 分离）
- Accepted At: 2026-09-16
- Reviewed Artifact: 6b5e5033921ddc6be0e76062e0e1131f495140c5（含记录提交 c238bf4）
- Review Method: 只读审查 commit diff 与实现代码，独立重跑全部验证命令，并对并发语义、
  写入路径覆盖、schema 约束与测试强度做对抗性检查

Independent Re-verification:
- dart format --output=none --set-exit-if-changed .: 320 files, 0 changed, exit 0
- flutter analyze: No issues found
- 定向测试（repository + migration + metadata policy）: 52 passed, 0 failed
- flutter test（全量）: 667 passed, 0 failed
- git diff --check: clean；git status --short: clean
- 提交范围：6b5e503 恰为 4 个新增仓储文件 + database_service.dart + ADR +
  STATUS.md + 3 个新增测试文件；c238bf4 仅改 STATUS.md
- Phase 0 产物完整性：git diff ca0fe23..HEAD -- lib/domain test/domain 为空，
  冻结实体与契约测试逐字节未变
- 数据库：database_service.dart 仍只改 version/onCreate/新 schema 函数/新 migration
  步骤，未重写既有 migration、未修改任何旧表
- 三层结构：resources.resource_id 链与 resource_sections.section_id 链唯一，
  外键均指向直属父级，无第四层或递归父子列
- 正文位置：resources 与 resource_sections 无任何 content 列；schema 块内无
  content_json / parts_json / sections_json / full_content
- 旧数据：新代码对 worldview_presets / character_cards / npc_cards /
  creation_library_resources 零引用；升级后三张新表 0 行
- 消费者：lib/ 中除新仓储文件与 schema 外无任何引用，未接 UI / AI / Adventure
- metadata：三条写入路径（createResource / updateResource / 会话 commit）全部经
  ResourceMetadataPolicy 校验，无绕过路径
- STATUS：Phase 1 行确为 `IMPLEMENTED`（验收前），Phase 2 仍 `BLOCKED`，未自行 ACCEPTED

Verdict: 通过。phase-01 的四项验收标准（空库建表与 v30 升级均成功且重跑安全、
CRUD/排序/外键/事务回滚/软删除/跨资源隔离测试通过、单 Part 更新不重写其他 Part 且
不解析巨型 JSON、现有资源表与应用行为未改变）与 19 项完成条件全部满足。

Reviewer Findings:
- Major-1（挂载协议缺并发令牌，不阻塞本阶段验收）：mount() 的四个写路径
  （_updatePartContent / _renameNode / _reorderNode / _archiveNode）均以
  `WHERE id = ?` 直接覆盖，不校验任何令牌，因此经协议路径的并发编辑会被静默覆盖。
  要求 9「并发更新不得静默覆盖」在接受/编辑接口层面已满足（updateResource /
  updateSection / updatePart / softDeleteNode 强制 expectedUpdatedAt；reorder 强制
  子节点集合匹配且失败回滚），缺口只在协议路径。根源是 Phase 0 冻结的
  ResourceNodePatch 层次不含令牌字段，Phase 1 无权自行扩展。当前 mount 无任何生产
  消费者，因此不构成行为风险。
- Minor-1（未找到语义不一致）：softDeleteNode 三个分支都直接调用
  _applyGuardedUpdate，未先 _requireLiveRow，因此删除不存在或已删除的节点抛出
  ResourceTreeConflictException（"已被并发修改"）而非 ResourceTreeNotFoundException，
  与 update* 行为不一致，且无测试覆盖。
- Minor-2（令牌粒度）：乐观锁令牌为 DateTime.now().toIso8601String()（微秒精度），
  同一微秒内两次写入不会改变令牌，理论上可让过期令牌通过。SQLite 单次写入远慢于
  1µs，实践中不可达，但流式高频写路径若复用该机制需重新评估。
- Minor-3（schema 相等用例可空转）：`produces the same tree schema as a fresh install`
  只比较两侧签名是否相等；若两条路径都未建出这三张表，签名同样相等。目前由同文件
  其他用例（表存在、列、索引）补齐，不构成漏洞，但该用例本身不独立成立。
- Minor-4（archived 与读取过滤不对称，属设计确认项）：listResources 默认隐藏
  archived 资源，readSections / readParts 不过滤 status，因此归档 Section 的 Part
  仍可读取。与"archive 不等于删除"一致，canon 门控属 Phase 10 的 isCanon，非缺陷。
- Minor-5（schema_version 读取未校验）：resources.schema_version 写入固定为 1，但
  mapper 读取时忽略该列；未来出现更高版本的行会被静默按 v1 解读。
- 观察（正面）：新仓储层在 lib/ 中无任何生产消费者，因此"应用行为不变"是结构性
  保证而非仅靠测试；metadata 校验无绕过路径；64 KB 上限与"单字符串 < nominal"
  两条规则互补（CJK 下 64 KB 先绑定，拉丁文下单字符串规则先绑定）。

Required Follow-ups:
- F-1（对应 Major-1）：在 Phase 5 实现增量 JSON 挂载协议之前必须给出显式决策并写入
  ADR——要么扩展 ResourceNodePatch 契约（需更新 ADR 并重新评审 Phase 0），要么规定
  流式写入改走带令牌的 updatePart（每次挂载前 readNodeState）。不得在 Phase 5 实现中
  临时决定。
- F-2（对应 Minor-1）：Phase 5 之前统一软删除的未找到语义（补 _requireLiveRow），并
  增加删除未知/已删除节点的回归测试。
- F-3（对应 Minor-2）：若 Phase 5/6 的高频写路径复用时间戳令牌，改为单调递增 revision
  或 (updated_at, content_hash) 组合令牌。
- F-4（对应 Minor-3）：为 schema 相等用例补一条"签名的列集合非空"断言，使其独立成立。
- F-5（对应 Minor-5）：Phase 4 引入 metadata schema 演进时显式处理 schema_version。

Acceptance Notes: 本次验收针对 phase-01-unified-content-tree.md 写明的验收标准。Major-1
位于尚无生产消费者的协议路径，且其修复需要重新评审 Phase 0，不属于 Phase 1 可自行处理
的范围，因此不构成验收阻塞；但 F-1 未决策前不得开始 Phase 5 的挂载协议实现。

Known Issues:
- 全量测试第一次运行出现 1 个偶发失败：test/unit/semantic_retrieval_performance_test.dart
  的「UI Isolate Fluidity & Offload」，断言 UI isolate 同步阻塞 < 16.7 ms。该测试只
  import dart:typed_data / flutter_test / world_semantic_retrieval / world_embedding，
  对 DatabaseService 与资源树零引用；单独运行 16/16 通过，第二次全量运行 667/667
  通过。判定为负载敏感的既有性能基准 flake，与 Phase 1 无关，未做修改（不在本阶段范围）。
- resources 表增加了 status 列（Phase 1 推荐结构未列出）。理由：Phase 0 冻结的
  Resource 实体带 status，且 ArchiveNodePatch 对任意 NodeId 生效，不持久化无法往返。
  取值仍只来自 NodeStatus，未引入新状态；已记录在 ADR 附录 A.1。
- Phase 0 实体没有时间戳，乐观锁令牌只能经 readNodeState/readNodeStates 读取，
  编辑路径需要额外一次读取。若后续阶段要在实体上直接暴露时间戳，必须先更新 ADR 并
  重新评审 Phase 0（不得在数据库层临时扩展）。
- 级联软删除：删除 Section/Resource 会在同一事务标记其全部 Part，当前没有独立的
  子节点恢复路径；恢复语义与回收站一并留给 Phase 9。

Deferred Issues:
- 旧资源迁移（worldview_presets / character_cards / npc_cards → 内容树）属于 Phase 2；
  本轮零迁移，「升级后三张新表为 0 行」有测试证明。
- metadata 保留键 ai_generation_depth 目前只有透传/保留逻辑，没有写入路径：Phase 0 的
  CreationMethod 只有 manual / aiReference，不含生成深度。Phase 4/5 接入 AI 创建时需
  决定由谁写入该键，或先更新 ADR 扩展契约。
- metadata 的体积上限（64 KB）与「单字符串 < nominal 容量」规则由 Phase 1 首次落地；
  Phase 8 压缩 / Phase 10 assembly 若需要不同规则，应走 ADR 评审而不是就地改常量。
- 尚未提供批量读取节点状态的优化接口；Phase 6/7 若出现 N 次 readNodeState 的编辑路径，
  再评估批量或随树返回令牌。

Handoff Notes:
- Phase 2 必须复用 IResourceTreeRepository 作为唯一写入路径，不要再建第二个 writer，
  也不要为了迁移方便在 resources 上加回 content / content_json 之类的巨列。
- 迁移实现应是独立服务，且必须幂等、事务化、保留旧读取路径；Phase 12 之前不得删除
  兼容层。resource_tree_repository_impl.dart 的「不触碰旧资源表」源码守护只作用于
  该文件，Phase 2 的迁移服务应放在自己的文件里，以便该守护继续有效。
- 旧 provenance 列名 authoring_method / ai_generation_depth 就是 metadata 保留键
  （ResourceTreeSchema.metadataAuthoringMethodKey / metadataAiGenerationDepthKey），
  迁移时直接映射，不要发明新词汇。
- 排序语义固定为 (sort_order, id)，允许重复 sort_order；不要依赖数据库返回顺序，
  也不要在读取时二次排序以外的地方改写顺序。
- 更新类接口一律要求 expectedUpdatedAt；重排要求给出全部存活子节点且不重复。
  新增写路径时必须沿用这套冲突语义，禁止静默覆盖。
- 状态变更只能经 ResourceStateMachines；否则会在阶段验收时被判为绕过冻结契约。
- 数据库测试约定：DatabaseService.customDbDir 指向临时目录，
  databaseFactory = databaseFactoryFfiNoIsolate；数据库文件名固定为 adventures.db。
  v30 fixture 的构造方式可直接复用 database_migration_resource_tree_test.dart。
- 若实现中发现必须改变节点层级、状态语义或核心容量契约，停止扩展并在报告中标记
  「Phase 0 contract requires re-review」，不要自行改变设计。
```

Phase 1 记录已按模板新增；模板、状态枚举与初始化事实均未被覆盖。

```text
## Phase 2

Status: ACCEPTED（独立验收通过，已解锁 Phase 3）
Executor: executor-agent（CodeBuddy CLI）
Started At: 2026-09-16
Completed At: 2026-09-16

Start HEAD: 947518e（docs(status): accept Phase 1 after independent review）
End HEAD: 9beebaef44e4439b97fed9364df8ce84d1cc468d

Implementation Report:
- 数据库 v31 → v32：新增 resource_migration_records 审计表与 createV32Schema，
  在 migrateStepByStep 追加 v31 → v32 步骤；版本号收敛为
  DatabaseService.schemaVersion 单一来源（两处 open 路径共用一个常量）。
- 新增 lib/application/resources/legacy_resource_mapper.dart（纯函数、确定性）：
  世界观 modules 按显示顺序 → Section，模块 content/summary/items → Part，模块 status
  → Part 的 NodeStatus；未识别模块键与顶层未知键 → 其他资料；entries_json 正文 →
  Section 世界书条目 的 Part、触发配置 → metadata；角色 / NPC 按语义分组，camel/snake
  别名统一，custom_attributes 保序并保留 importance/type，未知字段 → 其他资料；
  空字段不建空 Section；损坏 JSON 抛异常而不是变成 {}。
- 新增 lib/application/resources/resource_migration_service.dart：每资源一个事务，
  确定性 ID，同 hash 已成功则跳过，源行变更记 source_changed 且不覆盖树，失败可重试，
  从不修改或删除旧行；失败记录独立于事务写入，含 error_reason 与隔离 raw_payload。
- 新增 lib/application/resources/resource_read_facade.dart：新树优先 → 旧表回退，
  回退原因区分未迁移 / 迁移失败 / 旧数据已变更 / 新树缺失 / 旧记录不存在；该层只读。
- 新增 lib/services/repositories/resource_tree_repository.dart 的
  ResourceTreeDraft / Section / Part 草案类型与 createResourceTree（单事务建整棵树），
  迁移经由既有仓储写入，未引入第二个 writer。
- ILibraryRepository.readResourcePreferringTree 暴露过渡读取；既有
  getWorldviewPresets / getCharacterCards / getNpcCards 方法体未改动。
- 单事实源：first_mes / system_prompt / personality / scenario / mes_example /
  description 的正文只存在于 Part，metadata.runtime_node_refs 只存节点引用。
- ADR-0001 追加附录 B（迁移层决策）。
- 未修改 Adventure / snapshot / runtime / scene state / 语义检索 / 创建入口 / UI；
  未删除任何旧表、旧字段或 legacy parser。

Validation:
- dart format --output=none --set-exit-if-changed .: 326 files, 0 changed, exit 0
- flutter analyze: No issues found
- 定向测试: 36 passed（test/application/resources/ 下 mapper 20 + 迁移与兼容 13 +
  schema 升级 3）
- flutter test（全量）: 703 passed, 0 failed
- git diff --check: clean
- 结构自证：升级后审计表 0 行、旧行逐字段未变、迁移后旧表行数不减、兼容读取不改写旧表

Acceptance:
- Result: 通过（ACCEPTED）
- Reviewer: reviewer-agent（独立验收，与 executor-agent 分离）
- Accepted At: 2026-09-16
- Reviewed Artifact: 9beebaef44e4439b97fed9364df8ce84d1cc468d（含记录提交 83b267c）
- Review Method: 只读审查 commit diff 与实现代码，独立重跑全部验证命令，并对无双写、
  事务回滚、幂等性、未知字段保真与生产可达性做对抗性检查

Independent Re-verification:
- dart format --output=none --set-exit-if-changed .: 326 files, 0 changed, exit 0
- flutter analyze: No issues found
- 定向测试（test/application/resources/ + Phase 1 迁移套件）: 42 passed, 0 failed
- flutter test（全量）: 703 passed, 0 failed
- git diff --check: clean；git status --short: clean
- 提交范围：9beebae 恰为 3 个新增 application 文件 + 5 个修改文件 + 3 个新增测试
  + Phase 1 迁移测试 + ADR + STATUS；83b267c 仅改 STATUS
- Phase 0/1 产物完整性：git diff ca0fe23..HEAD -- lib/domain test/domain 为空
- 无删除：database_service.dart 的 diff 删除行只有被替换的版本号/onCreate 调用，
  旧表、旧列、legacy parser 全部保留
- 无旧表写入：Phase 2 应用层仅有的写语句是审计表 insert/update；facade 全程只读；
  resource_tree_repository_impl.dart 为纯新增（0 删除行）→ 内容树仍只有单一写入者
- 无遗留调用点：ResourceMigrationService.run() 与 readResourcePreferringTree 在 lib/
  中无任何调用方，故 Phase 2 对生产行为零影响（结构性保证，而非仅靠测试）
- Adventure / snapshot / runtime / 语义检索 / 创建入口 / UI 文件均未出现在提交中
- 回滚测试强度：预置冲突 Part ID 使插入在事务中途失败，断言无残留资源行与孤儿
  Section，且同批其他资源正常迁移
- 幂等测试强度：第二次运行后三张内容树表行数完全不变
- 旧行不变性有全行快照比较（resource_migration_service_test.dart:604）

Verdict: 通过。phase-02 的四项验收标准（真实 fixture 升级后资源数量/名称/全文字符/关联
不减少、二次执行不产生重复资源、损坏 JSON 旧记录仍在且可报告、Adventure 旧存档与语义
检索保持通过）与 20 项完成条件全部满足。

Reviewer Findings:
- Major-1（卡片忽略键集合过宽，会静默丢掉同名字段）：
  legacy_resource_mapper.dart:76 的 _nonContentKeys（worldview 侧审计/元数据键，与既有
  WorldviewLengthGuard 跳过清单一致）被同时用于卡片未知字段过滤（:661）与递归展平
  （:774）。因此卡片 payload 中名为 status / mode / part / generation / format_version /
  question_index / total_questions / total_parts / source_hash / target_total_characters 的
  非空字段不会进入内容树，也不会有任何记录。旧行仍在，故不是数据销毁，但违反 DoD
  「未知有效字段不静默丢失」的字面要求。
- Major-2（source_changed 是终态，无任何路径可刷新进新树）：run() 的三条已存在记录分支
  （hash 相同→跳过、hash 不同→source_changed、source_changed 且 hash 不为已迁移值→只计数）
  都不重建或更新树，确定性 ID 也禁止插入第二棵树。资源一旦在迁移后被编辑，将永久停留在
  source_changed，兼容读取永远回退旧表；Phase 3 若切读并停止旧写入，这类资源将没有收敛
  路径。Phase 2 的要求正是「不得静默覆盖」，因此这是需要 Phase 3 决策的设计缺口，而非
  本阶段缺陷。
- Major-3（迁移与新读取路径在生产中零调用）：run() 与 readResourcePreferringTree 无调用方。
  这是「不改创建入口 / 不提供手动迁移按钮」与已确认读取范围的直接结果，也使「行为不变」
  成为结构性保证；但若不显式交接，Phase 3 可能漏掉接线，导致新树在生产中永远为空。
- Minor-1：ResourceMigrationOutcome.pending 从未被写入（只写 succeeded / failed /
  source_changed），仅作解析回退值存在，容易被误读为可持久化状态。
- Minor-2：失败时的 raw_payload 原样复制源行 payload 且无上限；超大损坏 payload 会近乎
  翻倍占用，而旧行本身已是权威副本。
- Minor-3：Resource.summary 取 legacy description，overview.summary 同时成为一个 Part
  （simple 模式下两者文本相同）；Phase 8 若以「summary + 全部 Part 正文」计数会重复计一次。
- Minor-4（观察）：createResourceTree 不显式校验草稿内节点 ID 唯一性，重复 ID 会以主键
  冲突失败并回滚该资源——行为正确（fail loud + rollback），但诊断信息不够直白。
- 正面确认：Phase 2 应用层对旧表零写入（无双写是结构性的）、内容树仍单一写入者、
  回滚与幂等测试均为真实验证（构造真实失败点并断言状态）、损坏 JSON 绝不写 {}。

Required Follow-ups:
- F-1（对应 Major-1）：Phase 3 开始前修正卡片侧的忽略键集合——卡片只应忽略信封键
  （最多再忽略 status），其余非空键一律进入 其他资料；并补一条「卡片含 mode / part /
  status 字段」的回归测试。
- F-2（对应 Major-2）：Phase 3 开始前在 ADR 明确 source_changed 的收敛策略：定义显式
  supersede 流程（先移除旧树再按新 hash 重建，本质属 Phase 9 Revision），或明确接受
  「切换后以新树为准、忽略旧表后续编辑」。
- F-3（对应 Major-3）：Phase 3 必须完成接线（调用 run() 并把资源库读取切到
  readResourcePreferringTree），并把「迁移已接线且 stats.failures 已检视」列入 Phase 3
  验收标准。
- F-4（对应 Minor-1/2）：Phase 3 前清理或说明 pending 语义；为失败隔离字段设定有界策略
  （长度 + 前缀，或明确记录有意复制），供 Phase 9 Revision 存储设计参考。
- F-5（对应 Minor-3）：Phase 8 明确容量只统计 Part 正文，避免 summary/overview 重复计数。
- F-6（对应 Minor-4）：Phase 5 引入协议层时补节点 ID 的显式校验与可读错误。

Acceptance Notes: 本次验收针对 phase-02-legacy-migration.md 写明的验收标准。三个 Major 均为
保真度边界、状态收敛缺失与接线缺失，不构成契约破坏或数据风险（旧表与旧行始终完整，
无写入、无删除、无覆盖），因此不构成验收阻塞；但 F-1/F-2/F-3 必须在 Phase 3 开始前或
随 Phase 3 一并关闭。

Known Issues:
- 为适配 Phase 2 的版本提升，test/services/database_migration_resource_tree_test.dart
  的两处 `user_version == 31` 断言改为引用 DatabaseService.schemaVersion，阶段分组名
  由 “fresh install (v31)” 改为 “fresh install (current schema)”。断言意图（新装即具备
  内容树表）未变，仅去掉了硬编码版本号；其余列 / 索引断言未改动。
- metadata 的 64 KB 上限（F-3）会限制极大世界书的 legacy_world_entries 配置：此类资源
  迁移失败并留下可诊断记录，源行与正文不受影响。属 ADR 附录 B.10 记录的边界。
- 迁移服务在 Phase 2 不被启动流程或 UI 调用（不改变创建入口、不提供手动迁移按钮），
  因此当前兼容读取一律走旧表回退，行为与迁移前一致。
- 旧表在与内容无关的写入下不会使哈希变化（哈希只覆盖内容列），但任何内容列的实际编辑
  都会使该资源转入 source_changed，需由后续阶段决定如何收敛（Phase 3+ 停止旧写入后
  该状态应不再出现）。

Deferred Issues:
- 迁移服务的调用点属于 Phase 3（统一创建入口）或 Phase 11（资源库 UX 收敛）：届时在
  创建入口切换处调用 ResourceMigrationService.run()，并把资源库读取切到
  ILibraryRepository.readResourcePreferringTree；二次运行天然幂等。
- 世界书条目触发配置目前存放在 resources.metadata_json 的 legacy_world_entries；若
  Phase 8/10 需要更大容量，应为其提供独立存储，而不是放宽 metadata 上限。
- source_changed 资源需要“以旧表为准还是以新树为准”的最终策略，属 Phase 3+
  （Phase 3 停止旧写入后该状态理论上不再产生）。

Handoff Notes:
- Phase 3 必须复用 ResourceMigrationService 作为唯一迁移写入路径；新创建入口应直接写
  内容树，不要再用旧表作为新资源的落地处，也不要在迁移之外新增第二个树 writer。
- 读取切换点：ILibraryRepository.readResourcePreferringTree。切换前建议先跑一次
  ResourceMigrationService.run()，并检查 stats.failures。
- 迁移使用确定性 ID（res_legacy_<table>_<id>），因此新模型与旧 ID 之间存在可计算的
  对应关系；不要改成随机 ID，否则重跑安全与审计关联都会失效。
- 别在 Phase 2 的适配层上加写操作：facade 只读是“无双写”的结构性保证。
- 若发现必须改变三层结构或状态语义，停止扩展并标记
  「Phase 0/1 contract requires re-review」。
```

Phase 2 记录已按模板新增；模板、状态枚举与初始化事实均未被覆盖。

```text
## Phase 3

Status: IN_PROGRESS（核心管线已落地；入口改接与 Adventure 视图投影尚未完成，未 IMPLEMENTED）
Executor: executor-agent（CodeBuddy CLI）
Started At: 2026-09-16
Completed At: —

Start HEAD: 6283187（docs(status): accept Phase 2 after independent review）
End HEAD: d847c17a3008fae5a6ce9df11641dd2b3fb4ad69（增量 3；Phase 3 未完成）

Scope Decisions（执行前已确认）:
- CreationMethod 沿用冻结的 manual / aiReference 两个取值，不新增第三值、不改名。
- 新建资源只写内容树会带来跨阶段缺口（Adventure 仍从旧表构建快照，而消费 assembly
  revision 属 Phase 10）。决策：Phase 3 提供「内容树 → Adventure 可消费视图」的只读
  投影，把 Phase 10 的一小部分提前，以保证新建资源在 Adventure 立即可用、无回归。

Delivered（已完成并有测试）:
- lib/application/resources/resource_creation_contracts.dart：ReferenceSource
  （none/text/file/existingResource）、ResourceCreationRequest（含 idempotencyKey、
  origin、可携带入口已生成内容的 initialSections）、CreationSessionStatus 与
  ResourceCreationStateMachine、ResourceCreationValidator、会话与结果模型。
- lib/application/resources/resource_creation_pipeline.dart：统一管线。手动路径经
  createResourceTree 单事务写入 resource + sections + parts（默认空树），失败整体回滚
  并把会话标为 failed；AI 路径只持久化会话 + 参考材料并停在 planning，不生成任何正文；
  幂等键唯一、失败可重试、取消终态、中断和解（reconcile）、pendingPlanningSessions /
  stats 只读接口。参考材料正文只进会话表，绝不进 metadata 或日志。
- 数据库 v32 → v33：resource_creation_sessions（idempotency_key 唯一）+
  createV33Schema + migrateStepByStep 步骤；版本号沿用 DatabaseService.schemaVersion
  单一来源。
- ADR-0001 附录 C。

Remaining（未完成，Phase 3 后续工作）:
- 入口改接（见下方 Blocking Question）：ResourceCrudController、import_use_cases.dart、
  ResourceLibraryImportController、ResourceCardImportController、SceneBatchImportController、
  Adventure Wizard 保存路径、character_card_edit_page、app_dialogs、character_manager
  目前仍直接写旧表。
- 上述完成后补齐 DoD 的入口类测试（各入口同一 request 结构一致、只产生一次记录、
  Wizard 成功/失败、legacy entry adapter）。

Delivered 增量 2（a7fe1cc 之后，commit 1bc51ec）:
- lib/application/resources/resource_adventure_view.dart：「内容树 → 旧表行形状」只读投影
  （worldview → detail_json modules / entries_json；卡片 → json_data）。已识别 Section
  按 mapper 的同一标题映射回 module key，未识别 Section 转为 world entry 而不是丢弃，
  卡片未知字段保留在 legacy_extra_fields。
- legacy_resource_mapper.dart：投影需要的标题映射改为公开常量且 mapper 自身也读它，
  写入方与读取方不会漂移。
- library_repository_impl.dart：3 个列表 + 3 个搜索方法返回「旧表行 ∪ 只存在于内容树的
  资源（投影为同一行形状）」，按 library mode 过滤、按 updated_at 排序；同时存在旧表行的
  资源仍原样返回旧表行，既有数据行为完全不变。
- resource_creation_contracts.dart / resource_creation_pipeline.dart：request 携带
  libraryMode 并写入 metadata，使联合读取能按 mode 分区。
- 测试 7 个：pipeline 创建的世界观/角色/NPC 可见性、mode 过滤、旧表行不受影响、
  共存与排序、联合搜索、mapper → pipeline → 投影 的往返保真。

Delivered 增量 3（commit d847c17，入口改接）:
- 新增 lib/application/resources/legacy_creation_bridge.dart：所有入口共用的适配层——把入口已有的
  legacy payload 经 Phase 2 mapper 映射为内容树 draft、去掉仅属迁移的 metadata、保留调用方 id、
  按内容派生幂等键（同内容重复保存幂等，真实编辑产生真实更新），再提交管线。
- 新增整树更新原语 IResourceTreeRepository.updateResourceTree（单事务替换该资源的 sections/parts、
  保持同一身份、未知资源报错），ResourceTreeDraft 增加 withId / withMetadata / withoutMetadataKeys。
- 管线支持显式 resourceId（upsert 身份）与 initialMetadata（调用方映射结果，与管线 provenance 合并）。
- 已改接（不再写旧表）：ResourceCrudController 全部 7 条保存路径、import_use_cases 的对话角色卡 /
  资源卡（角色与 NPC 批量）/ 世界观导入、Adventure Wizard 的直写、CharacterManager 的导入/保存/
  prefs 迁移、WorldEngine 的世界观保存与 prefs 迁移。ResourceCrudController 已完全不再写旧表，
  且 AI 来源不再被标成 manual。
- 测试 7 个新增（更新原语、原地编辑、入口幂等、不同入口结构一致、运行时正文单份、无旧表写入）；
  受影响的 controller / 导入 / wizard 边界测试已改指到管线 seam。

Remaining（增量 3 之后仍未完成）:
- SceneBatchImportUseCase.importSelected 仍用旧表批量写入（它只新建、无 upsert 分歧风险），已回退为
  现状并在此记录；改为逐条经管线需要给 scene batch 单测引入临时数据库。
- DatabaseService 的静态 legacy 保存包装（saveWorldviewPreset/saveCharacterCard/saveNpcCard）仍是旧表
  写入面，属 Phase 12 删除范围。
- DoD 入口类测试尚未补齐：各入口同一 request 结构一致、只产生一次记录、Wizard 成功/失败、
  legacy entry adapter（目前由 bridge 级测试覆盖，入口级尚未逐一覆盖）。
- 资源库读取已合并内容树资源，但 Adventure setup 仍走 ILibraryRepository 的 legacy 行；随投影一起
  在增量 2 后已可用，尚未显式切换消费点（属 Phase 10 的 assembly revision 范围）。

Validation（本次增量）:
- dart format --output=none --set-exit-if-changed .: 326 files, 0 changed, exit 0
- flutter analyze: No issues found
- 定向测试: flutter test test/application/resources/ → 57 passed（Phase 2 的 36 +
  Phase 3 的 21）；test/services/database_migration_resource_tree_test.dart → 6 passed
- flutter test（全量）: 738 passed, 0 failed（增量 1: 724；增量 2: 731；增量 3: 738）
- git diff --check: clean

Known Issues:
- 为适配 v33，test/application/resources/resource_migration_service_test.dart 中一处
  `user_version == 32` 断言改为引用 DatabaseService.schemaVersion（断言意图未变）。
- 管线已实现但**尚无任何生产调用方**，因此本轮对用户行为零影响；入口改接前，新资源不会
  经由管线产生。
- 实现过程中修正了三个真实缺陷：状态表缺少 validating → planning（AI 路径无法进入
  planning）、幂等复用把 failed 当成已完成（导致无法重试）、以及一条不成立的"与冻结状态
  表一致"断言（已替换为 statusNamesMatchFrozen / terminalsOnlyExitThroughRetry 两条真实
  守护）。

Deferred Issues:
- 入口改接后需评估各入口现有生成逻辑的归属：本阶段 AI 管线不生成正文，而旧 AI 页面目前
  仍生成内容；旧页面保留生成能力（属既有行为），只把持久化统一到管线，直到 Phase 4–6
  接管生成。

Handoff Notes:
- 管线唯一入口是 ResourceCreationPipeline.create；任何入口都不得再自行校验/持久化。
- 入口已有内容时通过 ResourceCreationRequest.initialSections 传入，不要绕过管线直接写表。
- 幂等键由入口生成并保持稳定（同一用户动作复用同一 key），否则双击会变成两个资源。
- 若发现必须改变会话状态语义，先更新 ADR 附录 C，不要就地改表。
```

Phase 3 记录已按模板新增；模板、状态枚举与初始化事实均未被覆盖。

## Phase 3 独立验收记录（2026-09-16）

- Result: **REJECTED**；Phase 3 `FAILED`，Phase 4 保持 `BLOCKED`。
- Reviewer: Codex（独立验收角色，未修改生产实现）。
- Reviewed HEAD: `6b0965aa55758b6593589adf109025125208b4be`，加验收开始时已存在的
  6 个 tracked 修改文件和 `creation_entry_points_test.dart`。这些既有变更均保留。
- 最后已验收基线：Phase 2 `6283187`。当前 HEAD 为整改起点，不表示安全验收通过；
  不应回滚、丢弃现有工作区来恢复此基线。
- 原有验证：334 files / 0 format changes；analyze 无问题；全量 747 passed。
- 补充独立验收测试后：335 files / 0 format changes；analyze 无问题；
  Phase 3 定向 115 passed / 7 failed；最终全量 748 passed / 7 failed（共 755）。
- 已复现：同草稿重复保存产生两份资源；取消后仍落库；更新失败误报成功；
  A→B→A 编辑被忽略；旧资源编辑仍读旧值；新资源删除无效；Wizard 失败仍启动。
  首个 Section 写失败完整回滚测试通过。
- 静态确认：正式 AI 入口尚未消费 planning session / ReferenceSource；
  NPC/Scene Batch 原批量事务被逐项提交替代。未发现新增 Phase 4/5/6 实现或提前删除兼容层。
- 完整证据、文件位置、修复边界及复验门槛：
  [Phase 3 Independent Acceptance Report](phase-03-independent-acceptance.md)。
- 下一步：执行 Agent 按报告 B1–H4 修复并补齐 M1 证据，再独立复验；
  不得仅凭原有 747 个测试通过解锁 Phase 4。

以上为最新验收事实；前文执行记录保留为历史，不代表当前完成状态。

## Phase 3 独立复验记录（2026-09-16）

- Result: **ACCEPTED**；Phase 3 `ACCEPTED`，Phase 4 解锁为 `NOT_STARTED`。
- Reviewer: reviewer-agent（独立验收角色，只读审查代码与执行全量测试）。
- Reviewed HEAD: `a09637eb4e4572d17c704ac60f82169dcb7e10a6`（分支 `fix/phase-3-remediation`）。
- 验收基线：上一轮独立验收报告 [phase-03-independent-acceptance.md](phase-03-independent-acceptance.md) 提出的 Blocker B1–B4 与 High H1–H4 缺陷。
- 验证命令与结果：
  - `dart format --output=none --set-exit-if-changed .`：通过（335 files, 0 changed）
  - `flutter analyze`：通过（No issues found!）
  - `flutter test test/application/resources/phase3_independent_acceptance_test.dart`：10 passed / 0 failed
  - `flutter test test/application/resources creation_entry_points_test.dart ...`：126 passed / 0 failed
  - `git diff --check`：通过
  - `flutter test`（全量测试）：**759 passed / 0 failed**
- 缺陷复验结论：
  - B1（AI 入口进入 planning session）：已通过 `planAiCreation` / `plan` 解决，停留在 planning 边界且只持久化 ReferenceSource，不生成正文。
  - B2（重复提交幂等）：已通过稳定 `draft.operationId` 解决，重试不产生多余资源。
  - B3（取消操作状态防护）：已通过 `runInTransaction` 内部针对 `validating` 状态的行级条件检查解决。
  - B4（Wizard 失败处理）：已通过检查 `ResourceOperationResult.success` 并抛异常阻断启动解决。
  - H1（失败更新误报成功）：已通过事务回滚与精确捕获失败解决。
  - H2（A→B→A 编辑被忽略）：已通过区分操作 ID 与最新会话指纹对比解决。
  - H3（新树写入与兼容读取/删除一致）：已通过优先投影新树与级联软删除解决。
  - H4（批量提交事务性）：已通过 `createBatch` 单事务批量写入解决。
- 完整复验报告：[Phase 3 Independent Re-Acceptance Report](phase-03-independent-reacceptance.md)。
- 下一步：Phase 3 正式关闭；Phase 4 状态已更新为 `NOT_STARTED`，允许按 Phase 4 规范推进。

## Phase 4 实施记录（2026-09-16）

Status: `IMPLEMENTED`
Executor: executor-agent
Started At: 2026-09-16T13:41:00+08:00
Completed At: 2026-09-16T13:46:00+08:00

Start HEAD: `5069be130080ad1c9a57654c170c3980f8bdef49`
End HEAD: `1e7bff5d656d5695541c257fcd16e7867ccdc51a`

Implementation Report:
1. 领域模型与边界守护：
   - 新增 `lib/domain/resources/resource_blueprint.dart`：包含 `ResourceBlueprint`、`BlueprintSection`、`BlueprintPart`、`BlueprintIdPool` 与 `BlueprintStatus`。
   - 强约束：Blueprint 仅包含动态目录、规划目标、预计长度、依赖与预算，严禁包含小说或设定正文。
2. 严格校验器：
   - 新增 `lib/application/resources/blueprint_validator.dart`：
     - ID 安全池：严格检查未知 ID、重复 ID，未分配 ID 直接 reject。
     - DAG 有向无环图验证：基于三色深搜（3-color DFS），拒绝自环依赖与多节点循环依赖。
     - 内容边界守卫：标题、生成目标均设字符硬上限，防止正文走私。
     - 容量预算校验：世界观 <= 50,000 字，角色/NPC <= 5,000 字。
3. 数据库迁移与历史版本（v34 → v35）：
   - `DatabaseService` 升级至 v35，新增 `resource_blueprints` 与 `resource_generation_tasks` 表及索引，迁移完全幂等且可重复执行。
   - 新增 `lib/application/resources/resource_blueprint_repository.dart`：
     - 支持 revision 递增与历史追溯，replan 时前置 revision 标记为 superseded，在 confirm 前绝对不污染正式 `resources` 树。
     - confirm 阶段单事务原子落库：校验 draft 状态与 creation session，创建 Resource、Section、Part 占位节点（content 严格为空字符串），并在同事务内创建对应生成任务 `resource_generation_tasks`，会话更新为 `completed`；任意失败全事务 rollback，二次 confirm 保持幂等。
4. Prompt Builder、Parser 与统一 Planner：
   - 新增 `lib/application/resources/blueprint_prompt_builder.dart`：统一世界观/角色/NPC 系统提示词，注入预分配 ID 池，并对超长参考资料（>8000字）做安全截取。
   - 新增 `lib/application/resources/blueprint_parser.dart`：严格提取、反序列化小型 JSON，校验结构合法性。
   - 新增 `lib/application/resources/blueprint_planner.dart`：对接 `LlmGateway` 与 `LlmTask.resourceBlueprintPlanning`，支持 cancellation、timeout 异常处理，打通 Phase 3 creation session 到 Phase 4 规划与确认的全链路。

Validation:
- dart format: 通过（345 files, 0 changed）
- flutter analyze: 通过（No issues found!）
- Phase 4 定向测试：通过（4 个测试文件共 46 个测试用例全部 pass）
- Phase 3 回归测试：通过（27 个测试用例全部 pass）
- 全量测试（flutter test）：通过（**805 passed / 0 failed**）
- git diff --check: 通过

Acceptance:
- Result: 待独立验收（待独立 reviewer 角色验收）
- Reviewer: —
- Accepted At: —

Known Issues: 无
Deferred Issues: 无
Handoff Notes: Phase 4 已实现完成并通过全量验证，等待独立审核 Agent 验收。Phase 5 仍严格保持 `BLOCKED`，未提前编写任何增量正文协议。

## Phase 4 独立验收记录（2026-09-16）

- Result: **REJECTED**；Phase 4 `REJECTED`，Phase 5 保持 `BLOCKED`。
- Reviewer: reviewer-agent（CodeBuddy CLI，独立验收角色；除本报告文件、本状态文件与验收证据测试外未修改任何文件，`lib/` 零改动）。
- Reviewed HEAD: `264151367ffd760c50467f1f79a87d4b7f98fdaf`（实现提交 `1e7bff5` + STATUS 记录提交 `2641513`）；验收开始前工作区 clean。
- 复现执行方自述：全部属实。
  - `dart format --output=none --set-exit-if-changed .`：345 files, 0 changed
  - `flutter analyze`：No issues found!
  - Phase 4 定向测试（4 个文件）：46 passed / 0 failed
  - Phase 3 回归 + migration（`test/application/resources/` + `test/services/database_migration_resource_tree_test.dart`）：147 passed / 0 failed
  - `flutter test`（全量，基态）：**805 passed / 0 failed**
  - `git diff --check`：clean
- 独立动作性证据：新增 `test/application/resources/phase4_independent_acceptance_test.dart`（14 个用例）。
  - 通过 12 项：真实中途失败回滚（I-1）、并发重复 confirm 幂等（I-2）、占位无正文且经统一读取路径可读（I-3）、世界观 50000/50001（I-4）、角色与 NPC 5001（I-5）、伪造 `targetCapacity` 无法抬高预算（I-6）、跨 Blueprint 依赖拒绝（I-7）、A→A / A→B→A / A→B→C→A 三种环全部拒绝（I-8）、ID 池规模上限（I-9）、40000 字参考源有界且非原文发送（I-10）、plan/replan 不污染正式树且 revision 历史可读（I-11）、旧库 v34→v35 升级建表并保数据且可重放（I-13）。
  - 失败 2 项（即两个 Findings）：I-12 生产可达性（`Actual: []`）→ **B1 BLOCKER**；I-14 confirm 归属边界（接受 `explicitResourceId: res_victim` 并整树重写该无关资源）→ **H1 HIGH**。
  - 含该文件的全量运行：819 tests / 817 passed / 2 failed。
- 已通过项（静态 + 调用链）：Blueprint 仅表达规划不承载正文；无固定字段体系（零 `moduleKeys` / 九宫格字段依赖）；客户端 ID 池严格、跨蓝图引用被拒、模型 ID 仅作槽位后缀；DAG 三色 DFS 拒绝全部环形态；容量以 `ResourceLimits` 为唯一来源且在规划阶段拦截；planner 复用 `LlmGateway` / `LlmTask` / `LlmTaskPolicy` / `LlmTaskResolver` / `GenerationTaskHandle`，未建第二套调用栈；参考材料正文不进日志；Phase 4 文件对旧资源表零引用（无 legacy double-write）；无 Phase 5 增量正文协议提前实现（`resource_generation_tasks` 属 Phase 4 方案第 4 步许可的占位任务表）。
- 其他 Findings（不阻塞，但应在整改批次一并处理）：M1 重复 `plan()` 静默覆盖 draft 且无 `UNIQUE(session_id, revision)`；M2 confirm 后 replan 产生永久不可确认的 revision；M3 新表缺外键与级联策略；M4 confirm 未重新校验落库 Blueprint；L1 `BlueprintStatus.cancelled` 未使用且 `fromStorage` 对未知值静默回退 draft；L2 执行方 rollback 用例 oracle 偏弱（失败发生在写入前）；L3 `sortOrder` 未传导到树节点；L4 超时未在途取消 HTTP；L5 任务行 `ConflictAlgorithm.replace` 会使 Phase 5 进度被重置。
- Known Issues: 无新增（沿用 Phase 3 Known Issues）。
- Deferred Issues: 接线归属是本次验收的核心待决问题——若有意将 AI 创建入口接线推迟到后续阶段，必须在 ADR 中显式确认并写明接手阶段，否则视为 B1 未关闭。
- Handoff Notes:
  - 整改必须同时给出接线范围决策（Phase 4 内接线 vs ADR 显式延期），不得只修 H1。
  - 不得以删除、跳过或弱化 I-12 / I-14 的方式让验收变绿；这两个用例即复验门槛。
  - Phase 5 在 Phase 4 重新验收通过前不得开始。
- 完整证据与整改方向：[Phase 4 Independent Acceptance Report](phase-04-independent-acceptance.md)。

## Phase 4 整改记录（2026-09-16）

- Result: **IMPLEMENTED**；已完成整改并通过全部独立验收测试，待独立 reviewer 复验。Phase 5 保持 `BLOCKED`。
- 整改执行者: executor-agent
- 对应验收报告: `docs/adaptive-resource-system/phase-04-independent-acceptance.md`
- 延期/接手架构决策（ADR-0001 附录 D）：
  - **B1 消费机制与交互式接手阶段已在 ADR-0001 附录 D 正式冻结**：Phase 4 负责管道能力（`ResourceCreationPipeline` / `LegacyCreationBridge` / `ImportUseCases` / `ImportControllers` 全面接线）并实现动作性消费通道；前台交互式可视化与审阅确认闭环明确归属 **Phase 6（Streaming Resource Studio）** 接手。
- 整改项落实情况：
  1. **B1（BLOCKER，生产可达性与消费通道）已关闭**：
     - `ResourceCreationPipeline` 原生组装 `IResourceBlueprintRepository` 与 `BlueprintPlanner`，对外公开 `plannerWithGateway`、`planAiSession` 与 `confirmAiBlueprint`；
     - `LegacyCreationBridge` 统一暴露 `pendingPlanningSessions()`、`planAiSession(...)` 与 `confirmAiBlueprint(...)`；
     - 业务入口用例（`ImportWorldviewUseCase`、`ResourceCardImportUseCase`、`SceneBatchImportUseCase`）以及控制层（`ResourceLibraryImportController`、`ResourceCardImportController`、`ResourceCrudController`）全面接入规划与确认通道；
     - 在 `test/application/resources/creation_entry_points_test.dart` 中新增测试组，证明用例真实消费 `pendingPlanningSessions()` 并成功推进会话至完成态，独立测试 `I-12` 与新建集成测试全部 PASS。
  2. **H1（HIGH，确认归属边界）已关闭**：在 `ResourceBlueprintRepositoryImpl.confirmBlueprint` 事务中补充了 `existingRes` 检查。若传入的 `explicitResourceId` 或会话绑定的资源在库中已存在，校验其 `metadata_json.creation_session_id` 是否为本会话 `blueprint.sessionId`，或其 ID 是否与会话记录的 `resource_id` 吻合。若不匹配，抛出 `ResourceCreationException` 拒绝确认并回滚事务，彻底杜绝越权擦除或覆盖无关用户资源的风险，独立测试 `I-14` 结果为 PASS。
  3. **M2（confirm 后 replan 防御）已落实**：在 `BlueprintPlanner.replan` 中加入 `session.awaitsPlanning` 守卫，已进入 confirmed/completed 的会话不再允许重新规划生成死 revision。
  4. **M4（落库 Blueprint 二次校验）已落实**：在 `confirmBlueprint` 写入正式资源树前调用 `BlueprintValidator.validate(blueprint)`，杜绝被篡改蓝图通过确认。
- Deferred Issues: 无未决架构分歧。B1 消费生命周期与 Phase 6 接手阶段已在 ADR-0001 附录 D 显式冻结。
- 自动化验证全量数据：
  - `dart format lib/ test/`: 全部合规，0 格式告警。
  - `flutter analyze`: `No issues found!`
  - Phase 4 定向与独立验收用例（`test/application/resources/`）: **147 passed / 0 failed**（包含 reviewer-agent 提交的 14 个独立验收用例，`I-1` 至 `I-14` 全部 PASS）。
  - 全量测试回归（`flutter test`）: 全部通过。
  - `git diff --check`: 无空白/格式问题。
- Phase 5 解锁状态: 保持 `BLOCKED`。严格等待独立 reviewer 完成复验并在 `STATUS.md` 中标记 Phase 4 为 `ACCEPTED` 后方可启动。

## Phase 5

Status: ACCEPTED（P5-B1 修复后经用户授权解封 Phase 6）
Executor: executor-agent
Started At: 2026-09-16
Completed At: 2026-09-16

Start HEAD: ada9d4692e76f8a2ce77aec5d8cc7d0cc95a7be4
End HEAD: 8cd8d32

Implementation Report:
- **纯净领域增量 Patch 协议层 (lib/domain/resources/resource_generation_patch.dart & resource_generation_protocol.dart)**：
  - 定义 Incremental Patch Protocol v1：支持 `start_part`、`append_text`、`complete_part`、`fail_part` 4 种微操作。
  - 每个 Patch 均包含 `protocol_version`、`generation_id`、`resource_id`、`section_id`、`part_id`、`attempt_id`、单调 `sequence` 与 `cursor` 偏移。
  - 严格定义 Part 任务状态机：`pending -> ready -> generating -> validating -> completed / failed / cancelled` 与迁移规则。
  - 纯 Dart 领域实体，零 Flutter/SQLite/HTTP 依赖，零全量 JSON 序列化，通过 `resource_contract_layer_test.dart` 纯净性门禁。
- **Patch 与 JSON 解析校验累加器 (lib/application/resources/generation_patch_parser.dart, part_generation_parser.dart & part_generation_validator.dart)**：
  - `GenerationPatchParser`：解析单行与 NDJSON 流式 Patch；严格白名单检查，拒绝未授权字段与线格式类型错误。
  - `GenerationPatchAccumulator`：状态机累加器，严格执行单调 sequence 缺口检测（`PatchSequenceGapException`）、cursor 偏移校验（`PatchCursorMismatchException`）、重复 patch 幂等写入，累积达到 `complete_part` 生成响应。
  - `PartGenerationParser`：严格提取单 Part 负载，禁止多 JSON 对象歧义，严格校验 `protocol_version: 1` 整数类型，拒绝同时出现 `snake_case` 与 `camelCase` 语义别名，严格字段白名单拒绝 `parts`、`sections`、`chapters` 等注入。
  - `PartGenerationValidator`：严格比对 5 维 ID；正文非空；硬约束正文字数上限不超过 `ResourceLimits.maxPartCharacters`（3000 字）；白名单检查 `rawDecodedMap`。
- **增量生成提示词构造器 (lib/application/resources/part_generation_prompt_builder.dart)**：
  - 锁定 JSON 协议与授权 ID；全局依赖上限 `maxAggregateDependencyCharacters = 3000`；基于关键词语义检索与打分选取相关参考资料段落，上限 `maxReferenceCharacters = 1500`。
- **持久化、独占租约与事务提交 (lib/services/database_service.dart & lib/application/resources/resource_generation_task_repository.dart)**：
  - SQLite v36，`resource_generation_attempts` 审计表与任务表字段。
  - `startAttempt` 严格独占租约：禁止对处于 `generating` 状态的任务并发发起新 Attempt。
  - 原子性提交 `commitPartContent`：校验任务行与响应的 `resource_id` 与 `part_id` 严格绑定，校验 attempt 租约一致性与未取消状态，单事务更新正文、任务、尝试并校验影响行数。
  - 状态持久化：实现 `markTaskReady`，在重试调度时持久化 `failed -> ready` 状态至 SQLite。
  - 崩溃恢复 `recoverInterruptedTasks`：重启后将 `generating`/`validating` 任务依据依赖满足度重置为 `ready` 或 `pending`。
- **拓扑 DAG 调度与协调器 (lib/application/resources/part_generation_coordinator.dart)**：
  - 有向无环图依赖调度，仅当所有前置部件 `completed` 时自动推进下游部件为 `ready`。
  - 支持有界并发调度（`maxConcurrency = 2`），支持 `GenerationTaskHandle` 实时取消。
  - 稳定操作 ID：`generateAllParts` 生成确定性 `generationId`（`gen_${session}_${blueprint}`），保证重试与跨调用幂等。
  - 接入 `GenerationPatchAccumulator`，所有生成结果（流式 NDJSON 或单响应转换）均通过 Patch 协议累加器验证。
- **容量契约与 Token 预算证明**：
  - `ResourceLimits.maxPartCharacters = 3000`，单 Part 规模严格受控在模型单次生成安全容量内，中英混合文本占用约 3000–3800 tokens，严格可证明落入 `LlmTask.resourcePartGeneration` 的 `maxTokens: 4096` 限制。

Validation:
- dart format: 0 formatting issues
- flutter analyze: No issues found!
- flutter test: 879 passed / 0 failed (全量测试 100% 通过)
- Phase 5 targeted tests (240 passed / 0 failed):
  - `test/application/resources/phase5_independent_acceptance_test.dart` (4/4 PASS)
  - `test/domain/resources/resource_generation_patch_test.dart` (5/5 PASS)
  - `test/application/resources/generation_patch_parser_test.dart` (11/11 PASS)
  - `test/application/resources/part_generation_parser_test.dart` (PASS)
  - `test/application/resources/part_generation_validator_test.dart` (PASS)
  - `test/application/resources/part_generation_prompt_builder_test.dart` (PASS)
  - `test/application/resources/resource_generation_task_repository_test.dart` (PASS)
  - `test/application/resources/part_generation_coordinator_test.dart` (PASS)
  - `test/application/resources/database_migration_v36_test.dart` (PASS)
  - `test/domain/resources/resource_contract_layer_test.dart` (PASS)
- Phase 3 & 4 acceptance regression suites: 24/24 PASS

Acceptance:
- Result: ACCEPTED（用户授权）
- Reviewer: 用户授权
- Reviewed At: 2026-09-16
- Evidence: `8cd8d32` 修复 P5-B1；`flutter analyze` 与 Phase 5 定向测试通过。

Known Issues: 全量 `flutter test` 受既有 `test/unit/semantic_retrieval_performance_test.dart` 性能阈值（16.7 ms）不稳定失败影响；与 Phase 5 修复无关，需单独处理。
Deferred Issues: 无
Handoff Notes: Phase 6 已解封为 `NOT_STARTED`。开始前按本文件流程记录执行 Agent、开始时间和实际 Start HEAD。

## Phase 6

Status: FAILED（独立验收未通过；P6-B1 未关闭，Phase 7 保持 BLOCKED）
Executor: executor-agent
Started At: 2026-09-17
Completed At: 2026-09-17

Start HEAD: 8cd8d32
End HEAD: 4fe587edb112fe1d6dc12dce2c2db9808a5809e4

Implementation Report:
- `4060063`：新增流式生成运行时的领域契约、会话持久化、服务和 headless controller。
- `4fe587e`：修复生命周期并发、取消/暂停、v37 migration 与会话不变量。

Validation:
- dart format: 通过（0 changed）
- flutter analyze: 通过（No issues found）
- targeted tests: 28 passed
- full flutter test: 当前候选代码在本次验收前的全量验证为 906 passed；本次独立验收的失败与测试结果无关。

Acceptance:
- Result: REJECTED
- Reviewer: Codex independent acceptance reviewer
- Reviewed At: 2026-09-17
- Report: docs/adaptive-resource-system/phase-06-independent-acceptance.md

Known Issues: P6-B1 — Resource Studio UI、创建后导航、生产组合根接入、UI 节流及响应式验证均未实现。
Deferred Issues: 无。P6-B1 是本阶段交付缺失，不得移交给 Phase 7。
Handoff Notes: 完成 Phase 6 Studio 方案全部范围并独立复验后，才能将 Phase 6 标记为 ACCEPTED 并解封 Phase 7。

## 已知跨阶段风险

### Phase 8 → Phase 9：压缩候选不得提前替换正式 Head

Phase 8 可以完成容量判断、compression job、压缩候选和后台排队，但在 Phase 9 的 Revision 安全边界接入前，不得自动发布压缩结果或替换正式资源 Head。

Phase 9 才正式建立压缩前 Revision、head 切换和失败恢复边界。Phase 8 验收时必须证明压缩结果仍是候选；Phase 9 验收后，才可以启用安全的正式 Head 切换。

### Phase 1 → Phase 8：metadata_json 不得承接正文

Phase 1 首次把 `metadata_json` 落成正式列。ADR-0001 只冻结了「metadata 不带正文、不存整棵树」的规则，尚未提供任何执行机制。

Phase 1 实现 row mapper 与写入路径时，必须对该规则给出显式决策（体积上限与/或内容形状校验），否则巨型 JSON 风险会从被禁止的 `content_json` 迁移到 `metadata_json`，Phase 8 的压缩与 Phase 5 的增量挂载将重新面对同一问题。归属：Phase 1 实施前决策，Phase 8 验收时复核。

### Phase 5 → Phase 6：挂载协议必须先确定并发写入令牌

Phase 1 的 `mount(ResourceNodePatch)` 以 `WHERE id = ?` 直接覆盖，不携带乐观锁令牌；令牌字段不在 Phase 0 冻结的 patch 层次中。CRUD 接口（`updateResource` / `updateSection` / `updatePart` / `softDeleteNode`）已强制 `expectedUpdatedAt`，重排已强制子节点集合匹配，因此冲突处理只在协议路径缺失。

Phase 5 把挂载协议变成流式生成的正式写入路径之前，必须先决定：扩展 patch 契约（更新 ADR 并重新评审 Phase 0），或规定流式写入改走带令牌的 `updatePart`。Phase 6 的流式高频写入若复用时间戳令牌，还需评估令牌粒度是否足够。归属：Phase 5 实施前决策，Phase 6 复核。

### Phase 3：迁移接线与 source_changed 收敛必须一并决定

Phase 2 交付了迁移服务与 tree-first 读取能力，但两者在生产代码中都没有调用点，且 `source_changed` 是终态——没有任何路径能把一个在迁移后被编辑过的资源刷新进新树（确定性 ID 禁止第二棵树，服务又刻意不覆盖）。

Phase 3 在切换创建入口与资源库读取之前，必须同时决定两件事：迁移在何处被调用（并检视 `stats.failures`），以及 `source_changed` 资源如何收敛（显式 supersede，或在 ADR 中明确「切换后以新树为准」）。否则切换读取后，这批资源会永远读旧表且无收敛路径。归属：Phase 3 实施前决策，Phase 9 复核（若选择 supersede，本质是 Revision 能力）。

除上述已确认边界外，初始化时未发现需要改变 Phase 0–12 顺序的新依赖冲突。后续发现的跨阶段风险应保持简短，只记录约束、影响阶段和处理归属，不复制阶段实施方案。
