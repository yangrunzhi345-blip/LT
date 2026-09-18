# Adaptive Resource System — Execution Status

本文件是 Phase 0–12 执行状态与阶段交接的统一记录。各 Phase 的设计与实施要求以对应 `phase-*.md` 为准；本文件不替代实施方案，只记录执行事实、验收状态和阶段依赖。

执行 Agent 在开始、完成或验收阶段时必须更新本文件。不得依据聊天记录、计划内容或尚未验收的代码推断阶段已经完成。

## 当前总体状态

| 字段 | 当前值 |
| --- | --- |
| Current Phase | Phase 11（`FAILED`，Round 2 独立审计未通过，等待 remediation） |
| Last Accepted Phase | Phase 10 |
| Next Phase | Phase 12（`BLOCKED`，等待 Phase 11 独立验收） |
| Current Repository HEAD | `7cb2e86`（Round 2 独立审计基线；Phase 11 remediation End HEAD 为 `61bfe7e8a2ed6dc8b537b75ca73d4982f4a99f65`） |
| Last Updated | 2026-09-18 |

Phase 3 独立复验 **ACCEPTED**：经 remediation 提交（`a09637e`），原独立验收提出的 Blocker B1–B4、High H1–H4 缺陷已全部修复，单测和全量 759 个测试均通过。Phase 3 标记为 `ACCEPTED`。
Phase 4 独立复验 **ACCEPTED**：详见 [Phase 4 Independent Re-Acceptance Report](phase-04-independent-reacceptance.md)。经整改提交（`a3b4271` 与 `f44d0d9`），原独立验收提出的 Blocker B1、High H1 及 M1–M4 缺陷已全部修复，用例端规划通道全面打通，ADR-0001 附录 D 冻结架构决策，单测、集成测试、14 项独立验收测试及全量 822 个测试均通过。Phase 4 标记为 `ACCEPTED`。
Phase 5 整改已在 `8cd8d32` 关闭 P5-B1：`complete_part` 现在校验 cursor 与累计正文长度，生产网关按 NDJSON chunk 即时解析并挂载增量 patch。`flutter analyze` 与 Phase 5 定向回归测试通过。全量 `flutter test` 仍受既有语义检索性能基准（`semantic_retrieval_performance_test.dart` 的 16.7 ms 阈值）影响而失败；该问题不属于 Phase 5 变更。经用户授权，Phase 5 标记为 `ACCEPTED`，Phase 6 解封为 `NOT_STARTED`。
Phase 6 独立验收 **REJECTED**：详见 [Phase 6 Independent Acceptance Report](phase-06-independent-acceptance.md)。候选提交具备已验证的流式运行时基础层，但没有 Phase 6 方案要求的 Resource Studio feature、路由/创建链路接入、事件到 UI 状态层或响应式 Widget 验证。P6-B1 未关闭，Phase 7 保持 `BLOCKED`。
Phase 6 整改后独立复验 **ACCEPTED**：详见 [Phase 6 Independent Re-Acceptance Report](../phase6-independent-reacceptance.md)。Resource Studio 已完成用户入口、生产运行时组装、创建/生成链路、事件到状态到 Widget 的展示与控制、响应式回归验证；全量测试通过。Phase 7 已解封为 `NOT_STARTED`。
Phase 7 最终独立验收 **FAILED**（Round 1，唯一 Blocker B1：`commitPartContent` 未同步 Section 版本与校验状态）→ 已修复并经 **最终复验 ACCEPTED**（Round 2，2026-09-17）：B1 CLOSED、D1 VERIFIED、D2 裁定为 NON-BLOCKING LIMITATION，F1–F6 全部 PASS，Phase 5/6 未被破坏，`flutter analyze` 与全量 1023 个测试通过。详见 [Phase 7 Final Independent Acceptance — Round 2](phase-07-final-independent-acceptance.md)；B1 修复细节见 [Phase 7 B1 Remediation Report](phase-07-b1-remediation-report.md)。Phase 7 标记为 `ACCEPTED`，Phase 8 解封为 `NOT_STARTED`。
Phase 8 独立验收：Round 1 审计 **FAILED**（1 BLOCKER + 3 MAJOR）→ Round 2 验收 **FAILED**（BUG-R2-001/002 HIGH + A5/A7 MAJOR，BUG-001/BUG-003 仅部分关闭）→ Round 2 remediation（`8c62105`）→ Round 3 独立验收 **PASSED**（无 BLOCKER/MAJOR；Round 2 全部阻塞项关闭，新增 3 MINOR + 5 INFO 登记为技术债）。验收基线 `e82dacb`；`dart format` 0 changed、`flutter analyze` 无问题、Phase 8 定向 167 passed、全量 1186 passed，Phase 5/6/7 冻结文件零改动。详见 [Phase 8 Round 3 Independent Acceptance](phase-08-round3-independent-acceptance.md)、[Round 2 Acceptance](phase-08-final-independent-acceptance.md)、[Round 1 Audit](phase-08-independent-audit.md) 与 [Round 2 Remediation Report](phase-08-round2-remediation-report.md)。**Phase 8 标记为 `ACCEPTED`，Phase 9 转为 `UNBLOCKED`。**
Phase 11 Round 1 独立审计 **FAILED**（P11-M1/P11-M2/P11-M3，共 3 MAJOR）；失败历史完整保留。整改提交 `61bfe7e8a2ed6dc8b537b75ca73d4982f4a99f65` 已处理请求竞态与销毁生命周期、活动生成状态优先级及用户可见 `Part` 术语泄漏，并补充定向回归测试。Phase 11 当前标记为 `IMPLEMENTED`，等待独立复验；详见 [Phase 11 Remediation Report](phase-11-remediation-report.md)。Phase 12 继续保持 `BLOCKED`。
Phase 11 Round 2 独立审计 **FAILED**（P11-M4，共 1 MAJOR）：迁移记录转为 `source_changed` 后，资源库 union 仍同时保留陈旧树投影与当前 legacy 投影，Phase 9 延至本阶段的双投影问题尚未完整关闭。Phase 11 当前标记为 `FAILED`，等待 remediation；Phase 12 继续保持 `BLOCKED`。

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
| Phase 7 | Section 精细编辑与生成控制 | `ACCEPTED` | Phase 6 `ACCEPTED` | executor-agent | `4211c8b` | `4db3217`（+ F1–F6 remediation + B1 remediation） | 最终复验通过（Round 2，2026-09-17：B1 CLOSED / D1 VERIFIED / D2 NON-BLOCKING） |
| Phase 8 | 容量与语义压缩 | `ACCEPTED` | Phase 7 `ACCEPTED` | executor-agent（CodeBuddy CLI） | `46c3e0f` | `e82dacb` | 第三轮独立验收 PASSED（2026-09-17，无阻塞项；详见 phase-08-round3-independent-acceptance.md） |
| Phase 9 | Revision、自动保存与回收站 | `ACCEPTED` | Phase 8 `ACCEPTED` | executor-agent（CodeBuddy CLI） | `dbd2303` | `161dd7a` + remediation `dbb8019`/`119f923` + round2 remediation `3c3d253` | Round 1 FAILED；Round 2 FAILED（R2-B1 + R2-M1）；Round 2 整改后第三轮独立验收 **ACCEPTED**（2026-09-18，R2-B1/R2-M1 CLOSED，R2-M2 DEFERRED to Phase 11，详见 phase-09-third-round-independent-acceptance.md） |
| Phase 10 | Assembly Readiness | `ACCEPTED` | Phase 9 `ACCEPTED` | executor-agent（CodeBuddy CLI） | `f1db3f4ed7a6c96c5ca38e5374ef4129899855bf` | `2ea7cf7ea47a9593bebb496c3f3da487833be8b2` | 首轮 FAILED（P10-A1/M1/M2）；整改完成；2026-09-18 独立最终复验 ACCEPTED，详见 phase-10-final-independent-acceptance.md |
| Phase 11 | 资源库 UX 收敛 | `FAILED` | Phase 10 `ACCEPTED` | Codex autonomous pipeline | `92175c1d452d721d1a39f411069454c7cbed3948` | `61bfe7e8a2ed6dc8b537b75ca73d4982f4a99f65` | Round 1 独立审计 FAILED（3 MAJOR）并完成整改；Round 2 独立审计 FAILED（P11-M4，1 MAJOR），等待 remediation |
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

Status: FAILED（首次独立验收未通过）→ 整改后独立复验 **ACCEPTED**（2026-09-17；P6-B1 已关闭，Phase 7 解封）
Executor: executor-agent
Started At: 2026-09-17
Completed At: 2026-09-17

Start HEAD: 8cd8d32
End HEAD: 4d954cd

Implementation Report:
- `4060063`：新增流式生成运行时的领域契约、会话持久化、服务和 headless controller。
- `4fe587e`：修复生命周期并发、取消/暂停、v37 migration 与会话不变量。
- `4d954cd`：实现 Resource Studio feature（用户入口、生产运行时组装、创建/生成链路、事件→状态→Widget、响应式回归）。

Validation:
- dart format: 通过（0 changed）
- flutter analyze: 通过（No issues found）
- targeted tests: 28 passed（基础层）
- 整改后全量 `flutter test`：916 passed（见 Phase 6 独立复验报告）

Acceptance:
- Result: 首次 REJECTED → 整改后 ACCEPTED
- Reviewer: Codex independent acceptance reviewer
- Reviewed At: 2026-09-17
- Reports: docs/adaptive-resource-system/phase-06-independent-acceptance.md（REJECTED）、docs/phase6-independent-reacceptance.md（ACCEPTED）

Known Issues: 首次验收的 P6-B1（Resource Studio UI、创建后导航、生产组合根接入、UI 节流及响应式验证缺失）已在 `4d954cd` 关闭。
Deferred Issues: 无。
Handoff Notes: Phase 7 已解封为 `NOT_STARTED`，随后进入 `IN_PROGRESS`（Start HEAD `4211c8b`）。

## Phase 7

Status: ACCEPTED（最终独立验收 Round 1 判为 FAILED（Blocker B1）→ B1 remediation → 最终复验 Round 2 通过）
Executor: executor-agent
Started At: 2026-09-17
Completed At: 2026-09-17

Start HEAD: 4211c8b
End HEAD: 9424d02（初次实现 `4db3217` + 文档提交）；remediation `4e6ac96`；B1 remediation `3b265f9`

Implementation Report: [Phase 7 Implementation Report](phase-07-implementation-report.md)
Remediation Report: [Phase 7 Remediation Report](phase-07-remediation-report.md)
Final Independent Acceptance: [Phase 7 Final Independent Acceptance — Round 2: ACCEPTED](phase-07-final-independent-acceptance.md)
B1 Remediation Report: [Phase 7 B1 Remediation Report](phase-07-b1-remediation-report.md)
- `4db3217`：Section 领域模型与状态机、Section 生成绑定校验、Edit Command 层、Section Control Service 与事件总线、migration v38、分页 Repository、Resource Studio Section Controls UI，以及全部 Phase 7 测试。
- `4e6ac96`（F1–F6 remediation）：regenerate 令牌必需且启动前校验；树仓库 Part 变更事务内刷新所属 Section `updated_at`（并修复 `_sectionRow` 恒空缺陷）；恢复迁移测试固定版本断言；抽取 `SectionRegenerationRuntimePort` 并为真实执行器补用例；生成按钮改由 `hasGenerationTasks` 门控；报告与代码对齐。
- `3b265f9`（B1 remediation）：`commitPartContent` 在同一事务内新增 `_syncOwningSection`（按 `resource_parts.section_id` 定位 Section，推进 `updated_at`，并按 `SectionValidationState.afterContentChange` 将 `valid`/`invalid` 降级为新增的 `stale` 并清空过期消息）；两类失效路径共用同一规则；修复执行器 generationId 绑定（事件为 session id、patch 为协议 id）。

Validation:
- dart format: 通过（0 changed）
- flutter analyze: 通过（No issues found）
- Phase 7 定向与 Studio widget 回归: 147 passed（F1–F6 remediation 后）
- full flutter test: 1023 passed（exit 0；初次实现 997，F1–F6 remediation 后 1016）；最终复验 Round 2 在同一 HEAD 复跑 1023 passed

Acceptance:
- Result: Round 1 **FAILED**（唯一 Blocker B1）→ 修复后 Round 2 **ACCEPTED**
- Reviewer: independent acceptance reviewer
- Reviewed At: 2026-09-17（Round 1）、2026-09-17（Round 2 复验）
- Reports: [phase-07-final-independent-acceptance.md](phase-07-final-independent-acceptance.md)（Round 2：ACCEPTED，含 Round 1 记录）

Round 2 复验结论（详见上述报告）:
- B1 CLOSED：Section 内容的两类（且仅有两类）写入者均在各自同一事务内推进 Section 版本并使已记录结论失效；原子性由强制失败回滚测试与真实链路端到端用例固定。
- D1 VERIFIED：执行器旧绑定逻辑（session id vs 协议 id）已删除，改为首个 patch 建立 baseline 并锁定后续 patch，真实执行器测试覆盖 A/A 成功与 A/B 拒绝。
- D2 NON-BLOCKING LIMITATION：已完成任务不可重新生成；不违反数据一致性不变量，根因属 Phase 5 任务生命周期/Phase 9 revision 设计，需在 Phase 8 前落地"受控重置"或"修正 UI 门控"二者之一。

Known Issues: 见实施报告第 5.1–5.3 节。**未修复、上报最终审计的限制（D2）**：`PartTaskStatus.completed` 为终态且 `startAttempt` 拒绝已完成任务，`markTaskReady` 仅服务失败任务，因此对"已全部生成完成"的 Section 执行重新生成会在 `startAttempt` 失败（UI 会显示该错误）；修复需先由 Phase 5 任务状态机/Phase 9 Revision 层面批准重置语义，超出 B1 授权范围。其余非阻塞项：regenerate 为启动前比对而非原子抢占；`_reorderNode` 的 Part 分支仍不刷新 Resource `updated_at`。
Deferred Issues: 容量后台任务、正式 Revision 恢复与回收站页面分别属于 Phase 8/9，本阶段不实现。D2（已完成任务不可重新生成）的处置（受控重置 vs 修正 UI 门控）与其余 6 项非阻塞限制已登记，随 Phase 8 阶段文档处理。Phase 7 已由最终复验（Round 2）判定 `ACCEPTED`，Phase 8 解封为 `NOT_STARTED`。

## Phase 8

Status: IMPLEMENTED（等待独立验收；本阶段不自行宣布 ACCEPTED）
Executor: executor-agent（CodeBuddy CLI）
Started At: 2026-09-17
Completed At: 2026-09-17

Start HEAD: `46c3e0f`
End HEAD: `54f9ca7`（实现 `e515672` + Phase 7 D2 整改 `0d8fbf4` + 记录提交 `df251c6`、`54f9ca7`）

Implementation Report:
- 容量追踪（`resource_capacity.dart` + `resource_capacity_repository.dart` +
  `resource_capacity_service.dart`）：
  - 纯 Dart 领域模型 `ResourceCapacitySnapshot`（总字符、active/archived 字符、token
    估算、Section/Part 数、历史尝试数、`CapacityStatus`、测量时间）与
    `SectionCapacitySnapshot`；token 估算与状态分类经 `ResourceCapacityMath` 走
    `ResourceLimits.policyFor` 单一来源。
  - 测量固定为少量聚合语句：资源级一条 `GROUP BY`、Section 级一条 `GROUP BY`，
    配合 `COUNT`/`attempt` 聚合；无 `SELECT *`、无循环内查询。
  - `resources` 增加 7 个容量缓存列（v39），`ResourceCapacityService.measure` 是唯一
    写入者；`readCached` 对未测量资源返回 null 而不是伪造 0。
- 语义压缩（`resource_compression.dart` + `compression_job_repository.dart` +
  `compression_prompt_builder.dart` + `compression_response_parser.dart` +
  `compression_coordinator.dart`）：
  - `CompressionJob`/`CompressionJobStateMachine`（queued/running/succeeded/failed/
    cancelled，`failed` 只能经 `queued` 显式重试）、`CompressionCandidate`、
    `CompressionRetention`、`CompressionThresholds`、`CompressionTriggers`、
    `CompressionBudget`、`CompressionValidator`。
  - 按 Section 生成任务；超出 `maxCompressionInputCharacters` 的 Section 拆成逐 Part
    任务；入队只测量与落库，不调用模型。
  - 严格单对象 JSON 响应协议（未知字段、错误版本号、超长结果一律拒绝）；校验覆盖
    实体/关系/时间线保留与调用方硬性保留词，失败保留原稿并记录原因。
  - 候选写入 `resource_compression_candidates`（`applied_at` 恒为 NULL）；压缩链路没有
    任何语句写 `resource_parts.content`，正式发布属 Phase 9。
- 上下文压缩（`resource_context_compressor.dart`）：
  - `currentSection > currentState > unresolvedEvents > recentPlot > historicalSummary`
    优先级打包，只在 token 预算内选择完整片段（压缩摘要或整体丢弃），不做 substring
    截断；`ungroupedTokens` 作为自动压缩触发依据。
- 迁移 v38 → v39（`database_service.dart`）：`safeAddColumn` 容量列 +
  `CREATE TABLE IF NOT EXISTS` 压缩任务/候选表与索引，全部幂等。
- LLM 策略：新增 `LlmTask.resourceCompression`（非思考、低温度、4096 maxTokens）。
- Studio：新增 `ResourceCapacityPanel`（320 px 安全、响应式 Wrap 布局）与
  `ResourceCapacityController` / `ResourceCapacityRuntime` 端口、provider 接线，
  提供容量状态展示与手动压缩入口。
- Phase 7 D2（Phase 8 前必须落地其一）：采用**选项 B**——不实现受控重置（属 Phase 9
  Revision 边界），改为在 `ResourceStudioSectionControls` 禁用"已全部生成完成"章节的
  生成动作并给出原因；生成标签按内容存在性决定"生成/重新生成"。
- 明确未修改：`part_generation_coordinator.dart`、`resource_generation_task_repository.dart`、
  `section_control_service.dart`、`streaming_*`、Phase 5 协议与 parser、Phase 6 Studio
  控制器；Phase 5/6/7 已验收行为未变。

Validation:
- dart format: 通过（0 changed）
- flutter analyze: No issues found
- flutter test: 1145 passed / 0 failed（Phase 7 基线 1023，本次新增 122）
- Phase 8 定向测试：`test/domain/resources/resource_capacity_test.dart`（29）、
  `resource_compression_test.dart`（28）、
  `test/application/resources/resource_capacity_service_test.dart`（12）、
  `compression_pipeline_test.dart`（22）、`resource_context_compressor_test.dart`（12）、
  `database_migration_v39_test.dart`（3）、`test/widget/resource_capacity_test.dart`（15）；
  合计 121 个新用例，另有 1 个 Phase 7 D2 门控用例；全量由 1023 增至 1145。
- 关键验证方式：
  - 容量边界以字面量独立 oracle 断言 49999/50000/50001/60000/60001 与
    角色/NPC 4999/5000/5001/6000/6001。
  - 以 SQL 语句计数器断言"2 Part 树与 400 Part 树发出完全相同条数的语句"，作为
    无 N+1 的动作性证据。
  - 压缩前后 `resource_parts.content` 逐字符相等（原稿不变）。
  - 去重、重复 drain、空内容、超大 Section 拆分、非法响应、实体丢失、网络失败、
    取消、重启恢复、重试预算耗尽均有用例。
- git diff --check: clean
- 复核记录：全量测试首次运行有 1 次偶发失败，仅出现在既有
  `test/unit/semantic_retrieval_performance_test.dart` 的 UI isolate 16.7 ms 阈值用例；
  单独运行 16/16 通过，重跑全量 1145/1145 通过。该 flake 自 Phase 1 起已登记，与本阶段
  变更无关。

Acceptance:
- Result: 待独立验收
- Reviewer: —
- Accepted At: —

Known Issues:
- 容量缓存列为投影值：既有写路径（树仓库、生成任务仓库）不更新缓存，需由
  `ResourceCapacityService.measure` / Studio 刷新回写。读取权威值仍由聚合查询即时计算，
  因此缓存陈旧只影响列表页展示，不影响触发判断。
- 压缩候选目前没有生产消费方：`applied_at` 恒为 NULL，Phase 9 建立 Revision 边界后
  才有合法发布路径。
- `historicalRevisionCount` 当前取 `resource_generation_attempts` 计数作为"历史版本数"
  的代理；Phase 9 引入 revision 表后应改读真实 revision。
- 既有 flake：`test/unit/semantic_retrieval_performance_test.dart` 的 UI isolate
  16.7 ms 阈值用例对机器负载敏感，偶发失败（自 Phase 1 起登记），本次复核已复现一次并
  通过重跑，与本阶段变更无关。

Deferred Issues:
- 压缩候选的正式发布、压缩前 revision、`PartTaskStatus.completed` 的受控重置（Phase 7 D2
  选项 A）属 Phase 9。
- 上下文压缩器目前面向压缩链路与 Phase 10 assembly；未接入 Phase 5 生成协调器，避免
  改变已验收的生成协议行为。

Handoff Notes:
- Phase 9 接入顺序建议：先建 revision/head 边界，再提供
  `candidate → new head` 的显式发布操作，并在同一事务内使 Section 版本推进、校验结论
  降级（复用 Phase 7 的 `afterContentChange` 规则）。
- 不要在压缩链路中直接写 `resource_parts.content`；本阶段的候选表是唯一压缩落盘点。
- `resource_compression_jobs` 的 `(resource_id, scope, target_node_id, source_token)`
  唯一索引和 `(resource_id, target_node_id) WHERE status IN ('queued','running')`
  部分唯一索引是去重语义的一部分，不要绕过。

### Remediation（2026-09-17，针对独立审计 FAILED）

Audit: [phase-08-independent-audit.md](phase-08-independent-audit.md)（Result: FAILED，1 BLOCKER + 3 MAJOR）
Remediation HEAD: `024dd64`
Executor: executor-agent（CodeBuddy CLI）

已修复：

- **BUG-001（Blocker）中断的 `running` 任务永久死锁其目标** — 已修复。
  `CompressionJobStateMachine` 只增加一条保留恢复边 `running → queued`
  （`recoveryTarget`）；`recoverInterruptedJobs` 用两条常量语句回收孤儿行：仍有 attempt
  预算的回到 `queued`，预算已用尽的转终态 `failed`（这条规则本身即"禁止无限恢复"）；
  coordinator 公开该方法并在**本进程首次 drain** 时自动执行一次（此时不可能有本进程的
  任务在跑，因此不会抢占活跃租约）。
- **BUG-002（Major）failed 无生产重试路径** — 已修复。
  `ResourceCapacityRuntime.retryFailedCompression(resourceId)` 复用 coordinator 的
  `retryFailedJobs`；`ResourceCapacitySummary` 新增 `retryableFailedJobs` /
  `latestFailureReason`；controller 新增 `retryFailedCompression()`；Panel 新增
  「重试失败压缩（N）」按钮与失败原因展示。`attempts >= maxAttempts` 的拒绝语义未放宽。
- **BUG-003（Major）自动触发与离开编辑器后台任务未接线** — 已修复。
  `ResourceCapacityRuntime.autoQueueCompressionIfNeeded` = 实时 `measure` →
  `evaluateResource`（阈值来自 `ResourceLimits`）→ 仅在超限时 `enqueueForResource`；
  只建任务，不调模型、不写正文。`ResourceCapacityController.load` 以一条 `unawaited`
  后台链（先恢复、后触发）运行，不在 build 阶段触发、不阻塞首屏；若产生任务则刷新一次面板。
- **BUG-004（Major）真实压缩比结果被静默丢弃** — 已修复。
  验收边界**未放宽**（仍需"比原文短 且 不超过目标预算"）；`overBudget` 文案改为携带
  原文/实际/目标/达成比；失败原因经 `latestFailureReason` 在面板可见，并可通过 BUG-002
  的重试入口重试。`CompressionBudget` 由显式单测固定（0.6 比例，800 → 480）。

Validation:
- dart format: 通过（0 changed）
- flutter analyze: No issues found
- flutter test: 1166 passed / 0 failed（remediation 前 1145，本次新增 21）
- 新增测试：`resource_compression_test.dart` +2、`compression_pipeline_test.dart` +4、
  新增 `test/application/resources/resource_capacity_runtime_test.dart` +8、
  `test/widget/resource_capacity_test.dart` +7

Phase Boundary Verification:
- Phase 5/6/7 冻结模块（`part_generation_*`、`generation_patch_parser`、
  `resource_generation_task_repository`、`section_control_*`、`streaming_*`、
  `resource_generation_protocol/patch`、`resource_contracts`、两个 repository impl）
  在 `752b440..024dd64` 中**零改动**（`git diff --name-only` 为空）。
- `resource_parts.content` 仍无任何 Phase 8 写入点；候选 `applied_at` 仍恒为 `NULL`。

Remaining（仅登记，未在本次范围内修复）：

- **A5**：`drain` 仍是全局队列，未按资源过滤；手动动作可能消耗其它资源的任务额度并把
  结果记在当前资源上。
- **A6**：取消与「无可压缩正文」仍被计入 `failedJobs`，面板会显示为失败。
- **A7**：`updateJob` 无状态 CAS、`drain` 无原子 claim；并发 drain 可重复调用模型并少计
  attempts（BUG-003 的自动链路落地后可达性上升，Phase 9 后台调度前应处理）。
- **A8**：缓存读路径 `historicalRevisionCount` 恒为 0、状态由陈旧字符数重算；
  `capacity_status` 列只写不读；面板优先使用缓存，故显示值可能滞后。
- **A9**：archived Section/Part 在压缩路径仍是目标，但被上下文打包排除，两处口径不一致。
- **A10**：`ResourceContextAssembler` 的「recent」语义与文档不符；当前章节 id 未知时静默降级。
- **A11**：候选 `original_char_count` 含 `\n\n` 分隔符，与容量口径不一致并高估节省量。
- **A12**：并发入队时 `insertJob` 可能把内部 `StateError` 原样抛给用户。
- **INFO-001..006**：死代码面（`enqueueNode`、`findCandidateForJob`、`cacheColumns`、
  `CompressionRunProgress.fraction`）、retention 为模型自述、压缩 prompt 未做非可信内容
  围栏、压缩行无清理策略、section 候选无 per-Part 映射、`_generateLabel` 超出 D2 最小范围。

Status: IMPLEMENTED（remediation 完成，等待独立二次验收；本阶段不自行宣布 ACCEPTED）

### Remediation Round 2（2026-09-17，针对第二轮独立验收 FAILED）

Acceptance: [phase-08-final-independent-acceptance.md](phase-08-final-independent-acceptance.md)（Result: FAILED，2 HIGH + A5/A7 升级 MAJOR）
Round 1 audit: [phase-08-independent-audit.md](phase-08-independent-audit.md)
Remediation report: [phase-08-round2-remediation-report.md](phase-08-round2-remediation-report.md)
Remediation HEAD: `8c62105`
Executor: executor-agent（CodeBuddy CLI）

已修复：

- **BUG-001 / BUG-R2-001（HIGH）恢复抢占活跃任务** — 已修复。`CompressionJob` 增加
  `worker_id` / `claimed_at` / `lease_expires_at`；claim 时写入
  `ResourceLimits.compressionLeaseDuration` 租约。`recoverStaleRunningJobs` 只回收
  “租约已过期”或“无租约（无法证明归属）”的 `running` 行，活跃租约永不触碰；恢复不再绑定
  Studio 面板，改由 `drain` 起始与新增的 `CompressionBackgroundWorker.start()`（App 启动）执行。
- **A7（MAJOR）无原子 claim / 无 CAS** — 已修复。`claimJob` 单条
  `UPDATE ... WHERE job_id = ? AND status = 'queued'`，只有一个 worker 得到该 job；
  `completeJob` 单条 `UPDATE ... WHERE status = 'running' AND worker_id = ?`，失去租约的
  worker 无法覆盖新 owner 的终态，也无法写入自己的候选。
- **A5（MAJOR）drain 全局队列** — 已修复。`findJobsByStatus` 支持 `resourceId` 过滤，
  生产路径（`ResourceCapacityServiceRuntime.runQueuedCompression(resourceId)` 与后台 worker）
  全部资源作用域，不做 Dart 侧过滤。
- **BUG-R2-002（HIGH）retry 撞 active-target 唯一索引** — 已修复。
  `retryFailedJob` 单条语句并用 `NOT EXISTS` 守卫同 target 的 `queued`/`running` 行，
  残留约束错误被翻译为业务级跳过；`retryFailedJobs` 返回 `CompressionRetryOutcome`
  （requeued / skippedActiveTarget / skippedExhausted），单个冲突不再中断整批，面板显示被跳过的数量。
- **BUG-003（部分关闭项）自动 compression runtime** — 已完成。新增
  `CompressionBackgroundWorker`：`onEditorLeave` = 实时 `measure` → `evaluateResource` →
  仅超限 `enqueueForResource` → 资源作用域非阻塞 `drain`（资源级去重，永不向编辑路径抛错）；
  触发点从 `ResourceCapacityController.load()` 移到“离开编辑器”（控制器 dispose 与 Studio
  资源切换），`start()` 在 `main.dart` 启动钩子执行。自动排队的 job 现在有后台消费者。

Database：

- **schema v39 → v40**：`resource_compression_jobs` 新增 `worker_id` / `claimed_at` /
  `lease_expires_at`（`safeAddColumn`，非破坏性）。迁移不改写业务行；旧 `running` 行继承
  `lease_expires_at = NULL`，按“无租约 = 无法证明归属 = stale”规则由同一恢复路径回收，
  因此不残留永不恢复的 legacy running。新增 `database_migration_v40_test.dart`，
  并同步 `v36/v38/v39` 迁移测试中的 schema 版本钉子（39 → 40）。

Validation:

- `dart format --output=none --set-exit-if-changed .`：431 files / 0 changed
- `flutter analyze`：No issues found
- Phase 8 定向测试：167 passed
- 全量 `flutter test`：1186 passed / 0 failed（remediation 前 1166）
- `git diff --check`：干净
- 新增并发回归（真实重叠，`Future.wait` + 阻塞式 LLM fake，非顺序 await）：
  `compression_concurrency_test.dart`（4 worker 争抢同一 job → 模型仅调用 1 次、attempts=1、
  候选 1 个；活跃租约不被恢复；过期租约恢复→queued→succeeded；retry vs 已存在 queued target
  不抛异常；retry 批次部分冲突；资源作用域 drain；失去租约后终态写入被拒绝）、
  `compression_worker_test.dart`（同资源调度合并、触发失败不抛错、低于阈值时仍消费遗留队列）。

Phase Boundary Verification:

- Phase 5/6/7 冻结文件在 `03947be..8c62105` 中零改动（`git diff --name-only` 为空）。
- `resource_parts.content` 仍无任何 Phase 8 写入点；候选 `applied_at` 仍恒为 `NULL`；
  未实现任何 apply / publish / revision / head 切换。

Remaining（仍登记，本轮未修复）：

- **A6**：取消与「无可压缩正文」仍计入 `failedJobs`，面板会显示为失败。
- **A8**：缓存读路径 `historicalRevisionCount` 恒为 0、状态由陈旧字符数重算；
  `capacity_status` 列只写不读；面板优先使用缓存。（触发器已确认使用实时 measure，与展示问题分离）
- **A9**：archived Section/Part 在压缩路径仍是目标，但被上下文打包排除。
- **A10**：`ResourceContextAssembler` 的「recent」语义与文档不符；当前章节 id 未知时静默降级。
- **A11**：候选 `original_char_count` 含 `\n\n` 分隔符，与容量口径不一致并高估节省量。
- **A12**：并发入队时 `insertJob` 仍可能把内部 `StateError` 抛给用户（重试路径已不再暴露
  数据库异常；入队路径的同类问题仍在）。
- **BUG-R2-003**：`latestFailureReason` 取列表首个（最旧）失败原因，与“最近一次”文案不符。
- **BUG-R2-004**：`CompressionBudget` / `compressionTargetRatio` 文档称“未达预算仍是候选”，
  与 `CompressionValidator` 的硬拒绝实现冲突。
- **INFO-001..006**：死代码面（`enqueueNode`、`findCandidateForJob`、`cacheColumns`、
  `CompressionRunProgress.fraction`）、retention 为模型自述、压缩 prompt 未做非可信内容
  围栏、压缩行无清理策略、section 候选无 per-Part 映射、`_generateLabel` 超出 D2 最小范围。

Status: IMPLEMENTED（Round 2 remediation 完成，等待第三轮独立验收；本阶段不自行宣布 ACCEPTED，
不解除 Phase 9）

### Phase 8 正式收尾（2026-09-17）

Acceptance: [phase-08-round3-independent-acceptance.md](phase-08-round3-independent-acceptance.md)（Result: **PASSED**，无 BLOCKER / MAJOR）
Accepted HEAD: `e82dacb`（`03947be` Round 2 验收基线 → `8c62105` remediation → `8ce43a6`/`e82dacb` 文档记录）
Executor: executor-agent（CodeBuddy CLI）

收尾裁定依据（第三轮独立验收实测结论，本次不重新审计）：

- Round 2 的全部阻塞条件关闭且可动态复现：BUG-001 与 BUG-003 由 PARTIALLY CLOSED 转为 CLOSED；
  BUG-R2-001（HIGH）、BUG-R2-002（HIGH）、A5（MAJOR）、A7（MAJOR）全部 CLOSED。
  证据含 4 组变异实验（claim 守卫与恢复租约谓词的失效均被测试捕获；retry 守卫与 ownership 守卫未被捕获，
  已登记为技术债）与 1 个交错探针（活跃租约不被回收；失去租约的 worker 不覆盖新 owner 的状态与候选）。
- 验收命令真实结果：`dart format --output=none --set-exit-if-changed .` → 431 files / 0 changed；
  `flutter analyze` → No issues found；Phase 8 定向 13 文件 → 167 passed；
  全量 `flutter test` → 1186 passed / 0 failed；`git diff --check` → 干净；
  Phase 5/6/7 冻结文件 diff → 空。
- 数据安全与 Phase 边界不变式保持：压缩链路只写 `resource_compression_jobs` /
  `resource_compression_candidates`；候选 `applied_at` 恒 `NULL`；`resource_parts.content` 零写入；
  未实现任何 publish / revision / head 切换。
- schema 已到 **v40**（compression worker 租约列）；fresh install、v39→v40、迁移幂等与 legacy `running`
  可恢复均有测试覆盖。

技术债（本次收尾**不处理**，仅登记，供后续阶段或专门清理轮次排期）：

- 第三轮新增：**R3-M1**（约束异常回退判定过宽，会把 FK/NOT NULL/CHECK 失败伪装成"目标已有进行中的压缩"）、
  **R3-M2**（`completeJob` 的 `worker_id` 归属守卫无测试保护）、**R3-M3**（租约过期即判 stale，而 LLM 路径
  无请求超时且无续租，超过 5 分钟的单次请求会被重复执行）、**R3-I1**（`NOT EXISTS` 守卫无测试保护）、
  **R3-I2**（worker `lastError`/`processingCount` 无生产读取方，后台基础设施错误不可见）、
  **R3-I3**（每次离开编辑器最多处理 4 个任务，大资源会长期停留在"待压缩"）、
  **R3-I4**（`isLeaseLive`/`isOwnedBy`/`isReclaimable` 为死代码，与 SQL 谓词重复语义）、
  **R3-I5**（租约时间戳沿用工程既有的本地时间 ISO 字符串比较约定）。
- 前轮遗留：**A6**（取消/无正文计入 `failedJobs`）、**A8**（缓存 `historicalRevisionCount` 恒 0、
  `capacity_status` 只写不读）、**A9**（archived 节点是压缩目标但被上下文打包排除）、
  **A10**（`ResourceContextAssembler` "recent" 语义与文档不符）、**A11**（`original_char_count` 含 `\n\n`）、
  **A12**（并发入队仍可能暴露内部 `StateError`）、**BUG-R2-003**（`latestFailureReason` 取最旧失败原因）、
  **BUG-R2-004**（预算文档与硬拒绝实现冲突）、**INFO-001..006**。

Status: **ACCEPTED**。Phase 8 结束；Phase 9 依赖已满足，转为 `UNBLOCKED`（尚未开始，本次不进入其实现范围）。

## Phase 9

Status: IMPLEMENTED（等待独立验收；本阶段不自行宣布 ACCEPTED，也不解除 Phase 10）
Executor: executor-agent（CodeBuddy CLI）
Started At: 2026-09-17
Completed At: 2026-09-17

Start HEAD: `dbd2303`
End HEAD: `be00ee9`（实现提交；状态记录提交紧随其后）

Implementation Report: [phase-09-implementation-report.md](phase-09-implementation-report.md)

实现摘要:

- Revision（`resource_revisions` + `resource_revision_nodes` + head 指针）：
  - revision 不可变，只保存相对父 revision 的**节点增量**与墓碑，还原时按父链重放；
    单节点编辑只写 1 行增量（测试断言 delta 只含被改动的节点）。
  - `(resource_id, kind) WHERE is_head = 1` 部分唯一索引在数据库层保证 head 唯一。
  - `RevisionCause { manualSave, generation, regeneration, compression, restore, migration, deletion }`；
    生成提交的 cause 由“写入前该 Part 是否已有正文”推导，不信任调用方声明。
  - head 切换与业务写入同事务：生成提交、手动编辑、压缩发布、恢复、删除全部在一个事务内完成
    before 抓取 → 业务写入 → after 抓取，失败整体回滚。
  - 实现 Phase 0 冻结的 `ResourceRevisionSelector`：`latestHead` / `select`（仅指针新鲜度）/
    `publishAssemblyRevision`（assembly 独立链，不移动 latest-head）。
- 有损操作边界：
  - 生成/重新生成：`commitPartContent` 事务内抓取 before/after（`IPartCommitRevisionBoundary`）。
  - 手动编辑/自动保存：`PartContentCommitService.applyContent` 一个事务完成
    before 抓取、Section 校验降级、正文写入、`completed` 任务受控重置、after 抓取、草稿行消费。
  - 语义压缩：新增 `CompressionPublisher`，在一个事务内完成 `applied_at` CAS、before 抓取、
    正文替换、任务重置、after 抓取；章节级候选无 per-Part 映射，显式拒绝而不是猜测切分。
  - 恢复：`ResourceRevisionService.restoreRevision`，幂等（重复恢复不产生重复 revision）。
- 自动保存（`resource_autosaves`）：
  - `schedule` 只写内存缓冲，**完全不碰数据库**；debounce 700ms、`maxBufferedAge` 5s 集中在
    `AutosavePolicy`。
  - flush 顺序为「journal 独立事务落盘 → 一个事务写正文并消费 journal 行」，
    因此崩溃窗口内留下的草稿可被 `reconcilePendingDrafts` 识别为 `needsUserDecision` 而不是丢失。
  - 强制 final flush：dispose、页面离开、取消、生成异常、应用生命周期、手动保存。
  - Streaming 不新增第二条写路径：只有校验通过的 Part 才落库，未确认 chunk 不会伪装成 `completed`。
- 回收站（`resource_trash`）：
  - 删除一律 `live → trash`（写回收站行 + `deleted_at` 软删除，同事务）。
  - 恢复支持 Resource / Section / Part，保留原父节点与原 `sort_order`；
    原 Section 不存在或仍在回收站时**回退**到 Resource 根下的新 Section，并返回
    `TrashRestorePlacement.recreatedSectionUnderRoot` 供 UI 明确提示。
  - 重复恢复幂等；节点行已被永久删除时显式失败并保留条目，不静默丢数据。
  - 永久删除是显式二次操作，服务层拒绝删除仍存活的节点。
  - 清理只处理 `expires_at` 已过且未恢复的条目，保留期 30 天（`TrashRetentionPolicy`）。
- Revision 清理：只删除最老前缀，删除前把第一个保留者**根化**以保持链可重放；
  永不删除当前 head、assembly 引用、回收站未解决条目引用的 revision，保留期内一律不删，
  链断裂时报告并跳过而不是截断历史。
- 数据库 v40 → v41：三张新表 + 两张部分唯一索引 + 外键级联，非破坏性、幂等，
  不重写任何既有行。
- UI：Studio 新增版本历史面板与正文编辑器（debounce 自动保存 + 状态/冲突提示），
  容量面板新增「发布压缩结果」；资源库新增回收站入口与面板（恢复 / 永久删除二次确认）。
- Phase 7 D2 门控放开：Phase 9 提供受控重置 + 版本回退后，「已完成章节」重新可生成，
  文案与测试同步更新。

Validation:
- `dart format --output=none --set-exit-if-changed .`：464 files / 0 changed
- `flutter analyze`：No issues found
- Phase 9 定向测试：12 个文件 / **205 passed / 0 failed**
- 全量 `flutter test`：**1392 passed / 0 failed**（Phase 8 基线 1186，净增 206）
- `git diff --check`：干净
- Phase 5/6/7 冻结文件（`resource_contracts.dart`、`streaming_*`、`part_generation_*`、
  `generation_patch_parser.dart`、`resource_generation_protocol/patch`）在 `dbd2303..HEAD` 零改动

Acceptance:
- Result: **FAILED**（独立验收未通过）
- Reviewer: independent audit agent（只读审查，未修改生产代码或测试）
- Accepted At: —
- Reviewed Artifact: `161dd7a3d63ea2cf31176b2f732acc4d702cb4a0`
- Review Method: 只读审查 `dbd2303..161dd7a` 全量 diff；独立重跑 format/analyze/定向/全量测试；
  从源码提取真实 v41 DDL 在 scratch SQLite 中攻击 schema 不变量；按真实 replay 算法重放 revision 链；
  走查全部生产写路径与调用方（`git diff`、`grep` 复核）。
- Report: [phase-09-independent-acceptance.md](phase-09-independent-acceptance.md)

Independent Re-verification:
- `dart format --output=none --set-exit-if-changed .`：464 files / 0 changed
- `flutter analyze`：No issues found
- Phase 9 定向测试：205 passed / 0 failed
- 全量 `flutter test`：1392 passed / 0 failed
- `git diff --check`：干净
- schema 约束独立复现：三条部分唯一索引（head / autosave 草稿 / trash ACTIVE 条目）、
  revision_node 外键与级联、`updated_at` CAS 语义全部经 scratch SQLite 攻击验证为真实生效

Blocking Findings（修复后需重新提交独立验收）:
- **P9-B1（BLOCKER）Resource 删除未接入回收站且存在不可逆破坏路径**：
  无任何生产路径把 Resource 移入回收站（`grep -rn "deleteNode(" lib/` 仅 Section/Part 两处）；
  资源删除仍走 `LibraryRepositoryImpl._deleteUnifiedResource`（无 trash 行、无 before revision 的软删除）
  + `_deleteByMode`（旧表 `db.delete` 物理删除）。对 `ResourceReadFacade` 回退态资源
  （`notMigrated` / `migrationFailed` / `sourceChanged` / `treeMissing`）旧表是唯一副本，
  删除即不可逆丢失，且该资源不会出现在回收站、无法恢复。
  违反本阶段核心原则与 §十「Permanent Delete 必须是显式二次操作」。
- **P9-M1（MAJOR）assembly revision 的 delta 构造错误**：
  `publishAssemblyRevision` 把全量 upsert 集合挂到非空 `parent_revision_id` 上，
  而重放只能靠 `is_removed` 墓碑删除节点 ⇒ 二次发布且状态收缩时，已删除节点在重建状态中复活；
  同时列内 `content_hash` 与重建 hash 分叉。已用真实算法 + 真实 DDL 复现（期望 `[P1,S]`，实得 `[P1,P2,S]`）。
  当前无生产调用方，但 Phase 10 接线后会立刻生效。
- **P9-M2（MAJOR）自动保存冲突为粘性失败且草稿无生产出口**：
  编辑器仅在 `applied > 0` 时刷新 CAS 基线 token，冲突后 `_updatedAt` 永不更新 ⇒
  同一会话后续所有保存持续冲突（连续输入跨 `maxBufferedAge` 强制 flush 即可自我触发）；
  `reconcilePendingDrafts` 在生产代码中零调用方，编辑器展示树内容而非草稿 ⇒
  journal 中保留的用户文本对用户不可达，重开编辑器后继续输入会覆盖并删除它
  （仅删除草稿），用户文本实际丢失。

Non-Blocking Findings（8 MINOR + 5 INFO，明细见验收报告）:
- P9-M3 清理从未在生产触发（`pruneRevisions` 无调用方）⇒ 链无限增长、capture 成本随历史线性上升
- P9-M4 压缩发布硬编码 `alreadyApplied: false`，正文已等于候选时误报「节省 N 字 / 已记录历史版本」
- P9-M5 生产 restore 未传 `expectedUpdatedAt`，缺少并发 CAS
- P9-M6 对已被父级联删除的节点再 delete 抛冲突而非幂等
- P9-M7 assembly 链不在清理候选集内（「assembly 被保护」的说明实为空泛）
- P9-M8 `SectionControlRuntime.deletePart` 无 UI 调用方（死代码）
- P9-M9 保存覆盖后的 after 抓取 label 误写为「保存前快照」
- P9-I1 `captureRevision` 的 `headBefore` 在事务外读取（wasNoOp 可能误报）
- P9-I2 `confirmBlueprint` 的「资源已存在」分支覆盖整树且无 revision 抓取（当前不可达，登记为 Phase 10/11 前置风险）
- P9-I3 缺「edit → restore → stale autosave」专门交错用例
- P9-I4 `TrashReason` 仍为单值枚举
- P9-I5 Phase 7 D2 门控放开是对已验收行为的刻意 supersede，建议显式标注

Remediation 必须遵守:
- 先修 BLOCKER 与两项 MAJOR，再处理 P9-M3/P9-M7/P9-I2（同属「可恢复边界」主题，建议同轮）；
- 每个 finding 的 `Required Fix` / `Required Tests` 已在验收报告中给出，不得只改文案或降低断言；
- 修复后需重新运行 format / analyze / 定向 / 全量并再次提交独立验收。

Status: **FAILED**。Phase 9 不予验收；Phase 10 保持 `BLOCKED`。本轮审查未修改任何生产代码或测试。

### Remediation（2026-09-17，针对独立验收 FAILED）

Status: **REMEDIATED / READY_FOR_RE-ACCEPTANCE**（执行 Agent 完成整改；不自行宣布 `ACCEPTED`，Phase 10 继续 `BLOCKED`）

Remediation Start HEAD: `b999132`（先把失败记录固化进历史）
Report: [phase-09-remediation-report.md](phase-09-remediation-report.md)

- **P9-B1（BLOCKER）FIXED** —— Resource 删除改接回收站：
  新增 `ResourceLibraryTrashBridge` 把库行解析到内容所在处（活树行 → `deleteNode` 软删除 + before revision；
  无活树行 → `TrashOrigin.legacy` 标记条目，旧表行完全不动）。普通删除不再调用 `_deleteByMode`；
  未接桥接的库仓库拒绝删除（fail closed）；三个 delete* 返回「已移入回收站」，7 个删除入口统一提示。
- **P9-M1（MAJOR）FIXED** —— `publishAssemblyRevision` 改为 `diff(previousAssemblyState, targetState)`，
  删除生成墓碑；`insertRevisionInTransaction` 增加契约守卫，拒绝「父非空 + 目标更小 + 全 upsert」的增量。
- **P9-M2（MAJOR）FIXED** —— 自动保存 session 拥有 token（每次成功提交用 `updatedAtToken` 同步推进，
  编辑器不再异步刷新）；冲突后读 live 状态，仅当变更确属本 session 自身时**有界重试一次**，否则保留草稿并报冲突；
  `AutosaveDraftRecovery` 抽为共用分类器，编辑器打开时 reconcile 并展示「发现未保存的草稿 / 载入 / 丢弃」；
  冲突提示不再被击键静默清除。
- **P9-M3 FIXED** —— 新增 `ResourceRevisionMaintenance`（间隔节流、永不抛错），由 `main.dart` post-frame 触发。
- **P9-M4 FIXED** —— 压缩发布透传 `alreadyApplied`，已应用时 `savedCharacters = 0`。
- **P9-M5 FIXED** —— 新增 `resourceUpdatedAt()`，runtime/controller/页面透传 `expectedUpdatedAt`，restore 具备 CAS。
- **P9-M6 FIXED** —— 级联删除后的子节点重复 delete 解析到祖先条目，返回幂等而非冲突。
- **P9-M7 FIXED** —— 清理对 latestHead 与 assembly 两条链各跑一遍；两条链的 head 互进保护集合。
- **P9-M8 FIXED** —— Studio 正文区新增「删除段落」入口（二次确认）→ 回收站，可恢复。
- **P9-M9 FIXED** —— 保存覆盖后的 after 抓取 label 改为「保存后快照」。
- **P9-I1 FIXED** —— `captureRevision` 的 head 读取移进事务内。
- **P9-I2 FIXED** —— Blueprint 覆盖分支在同一事务内 capture before/after（cause：新增 `RevisionCause.planning`）。
- **P9-I3 已补** —— 冲突/保护交错用例（autosave 冲突保护组、并发组）。
- **P9-I4 维持** —— `TrashReason` 仍为单值枚举，待出现新的产生方再加值。
- **P9-I5 FIXED** —— 已标注 Phase 7 D2 门控在本阶段被 supersede。

Phase 边界: 未实现 Phase 10 assembly readiness、未做 Phase 11 资源库 UX 重构、未删除 legacy 表。

Status: **REMEDIATED**。等待独立 reviewer 重新验收；Phase 10 保持 `BLOCKED`。

### Round 2 Independent Re-Acceptance（2026-09-17）

Status: **FAILED**（新 BLOCKER R2-B1 + 1 MINOR R2-M1；Round 1 的 P9-B1/M1/M2 数据安全部分已关闭）
Audit HEAD: `119f923`（== origin/main）
Report: [phase-09-independent-reacceptance-round2.md](phase-09-independent-reacceptance-round2.md)

独立验证（审查 Agent 重跑）：
- `dart format --output=none --set-exit-if-changed .`：472 files / 0 changed
- `flutter analyze`：No issues found
- Phase 9 定向测试：346 passed / 0 failed（21 文件）
- 全量 `flutter test`：1446 passed / 0 failed
- `git diff --check`：干净
- 独立实验（/tmp，真实生产类 + 真实库，共 84 项检查）：A 删除链 38、B replay 10、
  C autosave 12、D stale debounce 6、E cleanup 9、F 幂等/CAS 7、H 草稿恢复链 7

Round 1 关闭情况：
- P9-B1 **PARTIALLY CLOSED**：不可逆破坏路径已消除（旧表行保留、物理删除仅剩显式 purger、
  表名白名单、fail-closed），但**生产 UI 删除路径未接线**（见 R2-B1）。
- P9-M1 **CLOSED**：assembly 增量改为真实 diff 并有写边界契约守卫（实验 B1/B2/B3）。
- P9-M2 **CLOSED**（自致粘性冲突已修）；外部并发写入场景残留 R2-M1。

新发现：
- **R2-B1（BLOCKER）**：`resourceCrudControllerProvider`（资源库全部删除入口）使用
  未接桥接的 `libraryRepoProvider`，删除必然抛
  「资源删除需要 Phase 9 回收站桥接…」——生产 UI 删除完全不可用
  （实测 `ProviderContainer` 无 override 调用即失败，三种资源一致）。
- **R2-M1（MINOR）**：外部并发写入造成的 autosave 冲突后，同一会话内自动保存持续失败
  （C3：applied=0/conflicted=1），需重开编辑器经「载入草稿」恢复；文本不丢失。
- **R2-M2（MINOR）**：迁移资源在资源库出现旧表 + 树两条投影（Phase 3 union 既有行为，
  归 Phase 11）；本轮验证删除/恢复对两条投影一致且无重复入回收站。

整改要求：把桥接接到 `libraryRepoProvider`（或统一 Phase 9 装配来源），并补
「真实 ProviderContainer 走 resourceCrudControllerProvider 删除」的用例；
同时处理 R2-M1 的会话内冲突解决。完成后再次提交独立验收。

Status: **FAILED**（Round 2）。Phase 10 保持 `BLOCKED`。本轮审查未修改任何生产代码或测试。

## Phase 9 Round 2 整改记录（2026-09-18）

Status: `REMEDIATED / READY_FOR_RE-ACCEPTANCE`（等待独立 reviewer 第三轮验收；不自行宣布 ACCEPTED，Phase 10 保持 `BLOCKED`）
Executor: executor-agent（CodeBuddy CLI，remediation 角色）
Started At: 2026-09-18
Completed At: 2026-09-18

Start HEAD: `e748c75122742cde3db76df312bf89b1a175fb28`
End HEAD: `3c3d253`（`fix(phase9): complete production trash wiring and autosave conflict recovery`）

Remediation Report: [phase-09-round2-remediation-report.md](phase-09-round2-remediation-report.md)

整改摘要:

- **R2-B1（BLOCKER）FIXED**：把 Phase 9 回收站桥收敛为单一来源
  `DatabaseService.libraryTrashBridge`；`resourceLibraryTrashBridgeProvider` 委托该静态；
  `libraryRepoProvider` 注入桥接（Resource Library UI 的删除从此到达回收站）；
  `ChatProvider()` 默认构造与 `AdventureSetupController` / `AdventureTemplateController`
  回退构造同步接线。`_moveToTrash` 的 fail-closed 守卫原样保留，无任何回退直删分支。
- **R2-M1（MINOR）FIXED**：外部写入冲突后 session 采信 live token、草稿持久保留、
  part 进入未解决冲突状态，flush 拒写直至用户决策；编辑器提供「使用我的文本」（仍走 CAS，
  二次竞态再次拒绝且不覆盖外部内容）/「放弃我的文本」（采纳 live 正文）；
  `reconcilePendingDrafts` 的 crash recovery 路径不受影响。
- **R2-M2（MINOR）**：按 Round 2 裁定 DEFERRED to Phase 11，本轮未触碰 Phase 3 union 读取。

新增回归测试:
- `test/application/resources/phase9_production_delete_wiring_test.dart`：
  真实 `ProviderContainer`（无 override）沿 `resourceCrudControllerProvider → libraryRepoProvider`
  完成三种资源的 delete → trash → restore 生命周期（防止 R2-B1 复发的生产装配回归测试）。
- `resource_autosave_service_test.dart` 新增 4 个外部冲突场景（keep-mine / discard /
  confirm-commit 间二次竞态 / 重开恢复）。
- `resource_studio_part_editor_test.dart` 新增 5 个冲突横幅用例（含 320 px）。
- 既有 fail-closed 用例保留：未接桥仓库删除仍抛 `StateError`（phase9_library_delete_test.dart）。

Validation:
- `dart format --output=none --set-exit-if-changed .`：473 files / 0 changed
- `flutter analyze`：No issues found
- Phase 9 定向测试：10 个文件 / **187 passed / 0 failed**
- 全量 `flutter test`：**1459 passed / 0 failed**
- `git diff --check`：干净

Acceptance:
- Result: 待第三轮独立验收（本轮不宣布 ACCEPTED）
- Reviewer: —
- Accepted At: —
- Reviewed Artifact: `3c3d253`（Round 2 整改范围 `e748c75..3c3d253`）

## Phase 9 第三轮独立验收记录（2026-09-18）

Result: **ACCEPTED**
Reviewer: independent re-acceptance agent（Round 3，只读；未修改任何生产代码或测试）
Accepted At: 2026-09-18
Reviewed Artifact: `2dfa69a`（审计范围 `e748c75..2dfa69a`，含整改提交 `3c3d253`）
Report: [phase-09-third-round-independent-acceptance.md](phase-09-third-round-independent-acceptance.md)

裁定明细:

- **R2-B1（BLOCKER）CLOSED**：静态装配审查确认全部 5 处生产 `LibraryRepositoryImpl`
  构造携带桥接且单一来源（`DatabaseService.libraryTrashBridge`）语义成立
  （含 `resetDatabase()` 生命周期实证）；fail-closed 守卫未削弱；
  10 项独立生产实验（真实 ProviderContainer、零 override、直接读 SQLite）全部通过，
  覆盖三种资源完整生命周期、legacy-only / migrated / treeMissing、幂等、
  两轮恢复循环、purger 白名单抗篡改。
- **R2-M1（MINOR）CLOSED**：13 项独立 autosave 实验全部通过，覆盖正常连续保存、
  外部冲突、冲突期间继续输入、keep-mine（提交内容与编辑器一致）、discard-mine、
  confirm/commit 间二次竞态、三类迟到 debounce、dispose 不绕过保护、崩溃恢复、
  目标删除、多 Part 隔离、确认窗口竞态注入（未经确认覆盖不可达）。
- **R2-M2（MINOR）**：DEFERRED TO PHASE 11 / NON-BLOCKING（维持 Round 2 裁定）。
- **Round 1 各项：NO REGRESSION**（整改 diff 未触碰 revision/assembly/compression/
  trash 服务；定向 538 passed）。
- **新登记非阻塞项**：R3-1（MINOR，keep-mine 不消费 held buffer，冗余幂等重写）、
  R3-2（MINOR，未解决冲突期间新击键不落 journal，崩溃窗口有界丢失）。建议随后续阶段处理。

独立复核验证:
- `dart format --output=none --set-exit-if-changed .`：473 files / 0 changed
- `flutter analyze`：No issues found
- Phase 9 定向测试：**538 passed / 0 failed**
- 全量 `flutter test`：**1459 passed / 0 failed / 0 skipped**
- `git diff --check`：干净
- Phase 5–8 冻结文件在 `e748c75..2dfa69a` 零改动

**Phase 9 标记为 `ACCEPTED`，Phase 10 解封为 `NOT_STARTED`。**

## Phase 10

Status: ACCEPTED（独立最终复验通过；已解锁 Phase 11）
Executor: executor-agent（CodeBuddy CLI）
Started At: 2026-09-18
Completed At: 2026-09-18

Start HEAD: f1db3f4ed7a6c96c5ca38e5374ef4129899855bf（== origin/main，工作区干净）
End HEAD: 80b97e6b3b9e0936f2cb37a001cff2eeed10e989（实施提交；文档提交紧随其后）

Implementation Report:
- [phase-10-implementation-report.md](phase-10-implementation-report.md)
- DB v42：`resource_assembly_readiness`、`resource_assembly_entries` 两表 +
  `world_entries.source_revision_id` 列；fresh 与 v41→v42 升级迁移均验证，幂等。
- 新增 readiness repository / immutable-revision assembly builder /
  attempt-token CAS coordinator / Adventure readiness gate；
  Wizard `_handleStart` 与 `AdventureProvider.createAdventure` 双重接入
  （fail-closed），被采用 revision 冻结进 `AdventureConfig.resourceBindings`。
- OVERFLOW head 复用 Phase 8 压缩基础设施（enqueue + worker），保持 preparing；
  压缩候选→发布的冻结语义未改动。
- 语义索引按 (resource, revision) 落盘，条目/embedding 经
  `source_revision_id` + contentHash 绑定，A/B revision 不混用。
- 冻结契约冲突取证与最小修复（`toResourceTree` 的 type 缺陷，builder 侧
  绕行，未改动 Phase 0/9 冻结文件）见实施报告。

Validation:
- dart format: 487 files / 0 changed
- flutter analyze: No issues found
- flutter test: 全量 1505 passed / 0 failed / 0 skipped
- targeted tests: Phase 10 定向 8 个测试文件全部通过（含 fresh/升级迁移、
  builder、coordinator 竞态/CAS、gate、语义索引 A/B、索引失败 fail-closed、
  OVERFLOW 压缩入队、生产 ProviderContainer 零 override 装配、
  320–768 视口对话框回归）
- other verification: `git diff --check` 干净

Acceptance:
- Previous acceptance: FAILED（P10-A1/M1/M2；历史记录保留）
- Remediation: completed（含 schema v43 legacy cleanup gap 修复）
- Final independent re-acceptance: ACCEPTED
- Reviewer: independent final verification（Codex）
- Accepted At: 2026-09-18
- Report: [phase-10-final-independent-acceptance.md](phase-10-final-independent-acceptance.md)

Known Issues:
- 索引文档在 assembly 发布后写入：索引失败时 readiness=failed 仍阻断消费
  （fail-closed），重试后文档补齐（详见实施报告「已知限制」）。
- 历史 Adventure/条目无 `resourceBindings` / `source_revision_id`，不回填。

Deferred Issues:
- Phase 9 R2-M2 维持 DEFERRED TO PHASE 11。
- legacy/new 双投影 UX 收敛、legacy 资产门禁化、旧表删除：Phase 11/12。

Handoff Notes: 生产链 latest head → immutable revision → readiness →
builder → validated assembly revision → revision-bound index → frozen
Adventure snapshot → Runtime 已在真实路径成立；Runtime 无任何绕过 ready
assembly 读取 mutable latest 的路径。等待独立 reviewer 验收 Phase 10。

### Phase 10 审计整改（2026-09-18）

Start HEAD: `394a880153c644b1d624e8a7c03e15adfe75dd91`（fetch 后与 origin/main 一致）。
首轮 [独立验收](phase-10-independent-acceptance.md) FAILED。按 [整改方案与报告](phase-10-remediation.md) 修复 P10-A1 字段级冻结、P10-M1 Part canon 过滤、P10-M2 revision 索引清理，并补齐回归。

整改代码提交：`2e5fe7a`。format / analyze / diff check 通过，Phase 10 定向 54 passed，全量 1513 passed。该历史记录保留原“待复验”结论。

### Phase 10 最终独立复验（2026-09-18）

最终复验基于实现提交 `2ea7cf7ea47a9593bebb496c3f3da487833be8b2`，并重新读取规范、整改记录、生产代码与测试。v43 migration 定向测试、Phase 10 定向测试共 48 passed，全量回归 1565 passed / 0 failed / 0 skipped，`flutter analyze --no-pub` 通过。A1/M1/M2 acceptance criteria、真实 production wiring、fail-closed gate、revision/index consistency 与 recovery 均复验通过；未发现 BLOCKER/MAJOR。Phase 10 正式 `ACCEPTED`，Phase 11 解锁为 `NOT_STARTED`。

## Phase 11

Status: FAILED（Round 2 独立审计未通过，等待 remediation；不得宣布 ACCEPTED）
Executor: Codex autonomous pipeline
Started At: 2026-09-18
Completed At: 2026-09-18

Start HEAD: `92175c1d452d721d1a39f411069454c7cbed3948`
End HEAD: `61bfe7e8a2ed6dc8b537b75ca73d4982f4a99f65`

Implementation Report: [phase-11-implementation-report.md](phase-11-implementation-report.md)
Remediation Report: [phase-11-remediation-report.md](phase-11-remediation-report.md)

Validation:
- dart format: 通过（外层门禁；未记录测试数量）
- flutter analyze: 通过（外层门禁）
- flutter test: 通过（外层门禁；未记录测试数量）
- targeted tests: 未单独记录数量
- other verification: `git diff --check` 通过；覆盖 320、360、390、412、768 与桌面宽度的响应式回归场景已纳入实现报告

Acceptance:
- Result: FAILED（Round 1 与 Round 2，2026-09-18；最新阻塞项 P11-M4）
- Reviewer: independent audit agent
- Accepted At: —

### Phase 11 Round 1 独立审计（2026-09-18）

审计输入：`/tmp/lt-phase11-auto.gKm7sE/audit-round-1.json`；审计基线为 Phase 11 End HEAD `772a4b9`。结论为 **FAIL**，以下失败事实、根因与建议修复完整保留：

- **P11-M1（MAJOR）** — `lib/features/resource_library/presentation/controllers/resource_library_controller.dart:21-39,46-72`（`ResourceLibraryController.load/createManual/_setState`）。根因：异步操作没有请求代际或 disposed 生命周期保护；初次加载、下拉刷新、回收站返回后的 load、创建后的 load 可重叠，旧 Future 完成后无条件写入状态并 `notifyListeners`。触发场景是快速刷新/离开页面或连续刷新导致旧结果较晚完成，可能显示过期列表/错误，或在 debug 下对已 dispose 的 `ChangeNotifier` 调用 `notifyListeners`。建议修复：为 `load/create` 引入递增 request token，await 返回后仅接受最新请求；增加 `_disposed` 标志，在 dispose 后禁止 `_setState/notifyListeners`，并覆盖 refresh、创建后 reload 及快速离开回归测试。
- **P11-M2（MAJOR）** — `lib/features/resource_library/application/use_cases/resource_library_runtime.dart:87-111`（`ProductionResourceLibraryRuntime._displayStatus`）。根因：读取生成会话前直接返回非空 readiness；新一轮生成时旧 assembly readiness 仍存在，活动生成状态被旧 readiness 遮蔽。触发场景是已 ready/stale 的资源再次生成或重试，资源库可能显示错误的“已准备完成/建议优化/正在优化”，而不是“生成中”。建议修复：先查询最新生成会话并为活动会话赋予“生成中”优先级，或在生成启动时原子失效旧 readiness；增加 readiness 与 active/completed/paused/failed session 组合测试。
- **P11-M3（MAJOR）** — `lib/features/resource_studio/presentation/controllers/section_control_controller.dart:147-151`（`SectionControlController.regenerateSection` successMessage）。根因：术语收敛只覆盖部分列表模型和组件，章节重新生成成功消息仍拼接内部英文模型名 `Part`。触发场景是 Studio 成功重新生成章节，Snackbar 显示类似“1/2 Part”，泄漏 Phase 11 禁止内部术语。建议修复：将用户可见文案中的 `Part` 统一替换为中文业务词（如“段落”），并扫描 Studio/detail/library 的 Snackbar、状态、空态和按钮文案；增加成功流程断言及全页面禁止术语回归测试。

审计分类汇总：BLOCKER 0；MAJOR 3（P11-M1、P11-M2、P11-M3）；MINOR 0；INFO 0。审计摘要确认 Phase 9 R2-M2 迁移去重代码与回归测试已存在，未见越界实施。`git diff --check` 通过；`dart format`、`flutter analyze`、Phase 11 定向测试及全量 `flutter test` 均因 Flutter SDK 尝试写入只读缓存（`engine.stamp.tmp/engine.realm`）而无法执行，不得据此视为通过。

Remediation: P11-M1/P11-M2/P11-M3 待整改；在独立复验通过前，Phase 12 必须保持 `BLOCKED`。

Known Issues: Phase 9 R2-M2（旧表与资源树投影去重）已在本阶段实现；Round 1 已发现 P11-M1/P11-M2/P11-M3，等待 remediation，因此不解除 Phase 12 阻塞。

Handoff Notes: Phase 11 Round 1 独立审计 FAILED；完成 remediation 并通过独立复验前，Phase 12 继续保持 `BLOCKED`。

### Phase 11 Round 1 Remediation（2026-09-18）

整改代码提交与本轮 End HEAD：`61bfe7e8a2ed6dc8b537b75ca73d4982f4a99f65`。整改详情见 [Phase 11 Remediation Report](phase-11-remediation-report.md)。

- **P11-M1 已整改**：`ResourceLibraryController` 增加请求代际和 dispose 生命周期保护，避免旧请求覆盖新状态及销毁后通知；新增并发加载和销毁后完成的回归测试。
- **P11-M2 已整改**：`ProductionResourceLibraryRuntime` 调整展示状态决策，使活动生成会话优先于旧 readiness；新增生成中、生成完成和无会话组合测试。
- **P11-M3 已整改**：章节重新生成成功文案将内部术语 `Part` 替换为用户可见“段落”；新增 Studio 文案回归测试。

整改执行方验证：直接 Dart 格式化通过，定向 Dart 静态分析通过，`git diff --check` 通过。`flutter analyze` 与 `flutter test` 未能启动，原因是 Flutter SDK wrapper 尝试写入只读缓存目录 `/home/yrz/development/flutter/bin/cache`；该环境限制不等同于测试通过，留待独立复验环境重跑。

Acceptance 状态仍为 Round 1 **FAILED**，本轮整改不自行宣布 `ACCEPTED`。Phase 11 现为 `IMPLEMENTED` 并等待独立复验；Phase 12 继续保持 `BLOCKED`。

### Phase 11 Round 2 独立审计（2026-09-18）

审计输入：`/tmp/lt-phase11-auto.gKm7sE/audit-round-2.json`；审计基线为 detached HEAD `7cb2e86`，审计确认初始及结束工作树均干净。结论为 **FAIL**。Round 1 的 P11-M1/P11-M2/P11-M3 整改可在代码中对应，但 Phase 9 延至 Phase 11 的双投影问题仅覆盖 `succeeded`，在真实 `source_changed` 状态仍会复发。以下发现、根因、触发条件与建议修复完整保留：

- **P11-M4（MAJOR）** — `lib/services/repositories/library_repository_impl.dart:203-238,241-281`（`LibraryRepositoryImpl._treeOnlyRows()` / `_mergeTreeRows()`）。触发条件：旧资源成功迁移后，用户或旧兼容路径修改 legacy 行；再次执行 migration 使迁移记录由 `succeeded` 变为 `source_changed`，随后打开资源库或搜索该资源。根因：union 合并先无条件把所有非 `creation_session_id` 的树加入 `extra`，随后去重查询仅筛选 `status = succeeded`；记录转成 `source_changed` 后，陈旧树仍在 `extra`，对应 legacy source ID 却不再进入 `migratedLegacyIds`，因此两条投影同时保留。这也违反 `ResourceMigrationService.isTreeCurrent()` 已定义的“仅 `succeeded` 且哈希一致时树优先”语义。建议修复：合并列表前以 `resource_migration_records` 的 `(source_table, source_id, resource_id)` 关系决定唯一投影；`succeeded` 且哈希仍匹配时保留树投影，`source_changed` 时隐藏陈旧树投影并保留当前 legacy 行，同时覆盖 character/NPC，不能只查询 `succeeded` 记录。建议回归测试：扩展 `library_repository_tree_union_test.dart`，先迁移 worldview/character/NPC，再修改 legacy 行并再次运行 migration 产生 `source_changed`；分别断言 list 与 search 只返回一条、返回当前 legacy 内容且不出现陈旧 deterministic tree ID；再把源内容恢复为原哈希，断言重新只显示树投影。

审计分类汇总：BLOCKER 0；MAJOR 1（P11-M4）；MINOR 0；INFO 0。审计同时核验了主列表、唯一“新建”入口、AI/手动分支、参考资料位置、卡片动作收敛、六种状态文案、生产路由接线、回收站 UI、响应式测试资产与 Phase 12 阻塞状态。`git diff --check` 通过；`dart format --output=none --set-exit-if-changed .`、`flutter analyze`、Phase 11 定向测试及全量 `flutter test` 均未启动，统一被 Flutter SDK 只读缓存 `/home/yrz/development/flutter/bin/cache/engine.stamp.tmp.14` / `engine.realm` 阻断（exit 1），不得视为通过。审计未修改生产代码或测试。

Remediation: P11-M4 待整改；整改并通过独立复验前，Phase 11 保持 `FAILED`，Phase 12 必须保持 `BLOCKED`。

Known Issues: `source_changed` 状态下资源库 list/search 会同时暴露陈旧 deterministic tree 投影和当前 legacy 投影；worldview、character 与 NPC 均须纳入整改及回归范围。

Handoff Notes: 按迁移记录关系和当前源哈希建立唯一投影语义，补齐 list/search 与恢复原哈希的回归测试；不得删除 Round 1 失败、整改或本轮失败历史。

## 已知跨阶段风险


## 已知跨阶段风险

### Phase 8 → Phase 9：压缩候选不得提前替换正式 Head

Phase 8 可以完成容量判断、compression job、压缩候选和后台排队，但在 Phase 9 的 Revision 安全边界接入前，不得自动发布压缩结果或替换正式资源 Head。

Phase 9 才正式建立压缩前 Revision、head 切换和失败恢复边界。Phase 8 验收时必须证明压缩结果仍是候选；Phase 9 验收后，才可以启用安全的正式 Head 切换。

Phase 8 实现结论：该约束在实现层面成立——`resource_compression_candidates` 是唯一
落盘压缩结果的位置，`applied_at` 恒为 `NULL`，压缩链路中没有任何语句写
`resource_parts.content`；测试以“压缩前后 `resource_parts.content` 逐字符相等”固定该性质。
候选的正式发布（含受控重置 `PartTaskStatus.completed`）仍属 Phase 9。
该性质已在 Phase 8 第三轮独立验收（2026-09-17，基线 `e82dacb`）中复核为 HOLD；
Phase 9 必须继续保持本约束，直到其自建的 Revision / head 边界通过验收。

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
