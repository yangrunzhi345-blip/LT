# Adaptive Resource System — Execution Status

本文件是 Phase 0–12 执行状态与阶段交接的统一记录。各 Phase 的设计与实施要求以对应 `phase-*.md` 为准；本文件不替代实施方案，只记录执行事实、验收状态和阶段依赖。

执行 Agent 在开始、完成或验收阶段时必须更新本文件。不得依据聊天记录、计划内容或尚未验收的代码推断阶段已经完成。

## 当前总体状态

| 字段 | 当前值 |
| --- | --- |
| Current Phase | Phase 1 |
| Last Accepted Phase | Phase 0 |
| Next Phase | Phase 1 |
| Current Repository HEAD | `a20c46af2eb94db36fc86705f11dcf9a6d3f4bf3` |
| Last Updated | 2026-09-16 |

Phase 0 已通过独立验收（`ACCEPTED`），Phase 1 前置条件已满足，可从 `BLOCKED` 转为 `NOT_STARTED`。Phase 1 尚未开始实施。

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
| Phase 1 | 统一 Resource / Section / Part 模型 | `NOT_STARTED` | Phase 0 `ACCEPTED` | — | — | — | 未验收 |
| Phase 2 | 旧数据迁移与兼容 | `BLOCKED` | Phase 1 `ACCEPTED` | — | — | — | 未验收 |
| Phase 3 | 统一创建入口与 Pipeline | `BLOCKED` | Phase 2 `ACCEPTED` | — | — | — | 未验收 |
| Phase 4 | Adaptive Blueprint | `BLOCKED` | Phase 3 `ACCEPTED` | — | — | — | 未验收 |
| Phase 5 | 增量 JSON 挂载协议 | `BLOCKED` | Phase 4 `ACCEPTED` | — | — | — | 未验收 |
| Phase 6 | Streaming Resource Studio | `BLOCKED` | Phase 5 `ACCEPTED` | — | — | — | 未验收 |
| Phase 7 | Section 精细编辑与生成控制 | `BLOCKED` | Phase 6 `ACCEPTED` | — | — | — | 未验收 |
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

## 已知跨阶段风险

### Phase 8 → Phase 9：压缩候选不得提前替换正式 Head

Phase 8 可以完成容量判断、compression job、压缩候选和后台排队，但在 Phase 9 的 Revision 安全边界接入前，不得自动发布压缩结果或替换正式资源 Head。

Phase 9 才正式建立压缩前 Revision、head 切换和失败恢复边界。Phase 8 验收时必须证明压缩结果仍是候选；Phase 9 验收后，才可以启用安全的正式 Head 切换。

### Phase 1 → Phase 8：metadata_json 不得承接正文

Phase 1 首次把 `metadata_json` 落成正式列。ADR-0001 只冻结了「metadata 不带正文、不存整棵树」的规则，尚未提供任何执行机制。

Phase 1 实现 row mapper 与写入路径时，必须对该规则给出显式决策（体积上限与/或内容形状校验），否则巨型 JSON 风险会从被禁止的 `content_json` 迁移到 `metadata_json`，Phase 8 的压缩与 Phase 5 的增量挂载将重新面对同一问题。归属：Phase 1 实施前决策，Phase 8 验收时复核。

除上述已确认边界外，初始化时未发现需要改变 Phase 0–12 顺序的新依赖冲突。后续发现的跨阶段风险应保持简短，只记录约束、影响阶段和处理归属，不复制阶段实施方案。
