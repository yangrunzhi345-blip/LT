# Phase 7 Final Independent Acceptance — Round 2: ACCEPTED

**Round:** 2 — Re-verification (supersedes the Round 1 verdict)
**Date:** 2026-09-17
**Auditor:** independent acceptance reviewer (read-only)
**Audited HEAD:** `054e452038fdc5474bba8c5acc6dd3b1cc45df4e`
**Working tree:** clean (`git status --short` empty)
**Diff under review:** `454447a..054e452` — 15 files, +1041 / −55
**Input:** `phase-07-final-independent-acceptance.md` Round 1 (FAILED, Blocker B1) + `phase-07-b1-remediation-report.md`

## Result

**ACCEPTED**

- **B1 — CLOSED**（Section 一致性不变量对全部内容写入者成立，且以强制失败的原子性测试固定）
- **D1 — VERIFIED**（执行器 generationId 绑定缺陷已消除，基线+锁定语义有真实执行器测试覆盖）
- **D2 — NON-BLOCKING LIMITATION**（判定与理由见下）
- F1–F6 全部 PASS；Phase 5/6 未被破坏；Phase 8 解除 `BLOCKED`。

## Verification

### 0. 基线与范围

| 检查 | 结果 |
| --- | --- |
| HEAD == `054e452` | PASS |
| 工作区 clean | PASS（无未跟踪、无修改） |
| B1 remediation 提交 | `3b265f9`（fix）+ `054e452`（docs） |
| Phase 5 wire protocol / parser / streaming service / coordinator / frozen contracts 在 `454447a..054e452` 中的改动 | **0 文件**（`git diff --name-only` 过滤后计数 0） |

### 1. B1 复验 — **CLOSED**

**1.1 事务顺序（`resource_generation_task_repository.dart:285-410`）**

单一 `db.transaction` 内，顺序为：

1. task 读取 + 绑定校验（resourceId / partId）+ attempt 令牌校验 + 取消态拒绝（`:294-331`）
2. `UPDATE resource_parts`（`content` + `content_hash` + `updated_at`）（`:333-351`）
3. `UPDATE resources`（`updated_at`）（`:353-364`）
4. `_syncOwningSection` → `UPDATE resource_sections`（`updated_at` [+ `validation_state` / `validation_message`]）（`:366-377`）
5. `UPDATE resource_generation_tasks`（completed）（`:379-392`）
6. `UPDATE resource_generation_attempts`（completed）（`:394-408`）

- 需求顺序（parts → sections → tasks/attempts）成立；Section 更新位于 Part 写入之后、任务收尾之前，全部在同一事务。
- **"Part 提交成功但 Section 更新失败"不可发生**：Section 步骤抛错即回滚整个事务。
- 原子性由测试强制证明（而非仅由代码阅读推断）：`test/application/resources/resource_generation_task_repository_test.dart` 的 *Case 3* 用 `CREATE TRIGGER ... BEFORE UPDATE ON resource_sections ... RAISE(ABORT)` 让第 4 步失败，随后断言三件事同时回滚——Part 正文仍为占位空串、task 状态非 `completed`、Section 令牌未变（`:488-540`）。
- 失败语义显式：缺 Part / 缺 `section_id` / 缺 Section 行一律抛 `StateError`，不静默跳过（`_syncOwningSection`）。

**1.2 覆盖完整性（独立枚举，非依赖报告）**

`lib/` 中对 `resource_parts` / `resource_sections` 的全部写入点只有两处：

1. `ResourceTreeRepositoryImpl`（F2 remediation 覆盖的 8 条 Part 路径，均经 `_bumpSection`）
2. `PartGenerationTaskRepositoryImpl.commitPartContent`（本次 B1 修复，经 `_syncOwningSection`）

其余命中均为只读查询（`getPartsContent`、`SectionControlRepositoryImpl` 的分页/聚合/单节读取）。**不存在第三个 Part 正文写入者**，因此不变量不存在旁路。

其它可能改变 Section 内容的路径均不产生过期结论：创建与 `updateResourceTreeInTransaction` 会重建 Section 行（`validation_state` 回到默认 `unvalidated`）；`updateSectionValidation` 只写 `validation_state/message/validated_at`，不推进 `updated_at`（`:193-220`），与本设计的"校验不是内容编辑"一致。

**1.3 结论**：审计要求的三项（`updated_at` 推进、结论失效、同一事务）全部满足，且原子性有强制失败证据。

### 2. 校验状态模型 — PASS

| 检查 | 证据 | 结果 |
| --- | --- | --- |
| `stale` 是 enum 成员 | `section_control.dart:130`（`stale('stale')`） | PASS |
| 持久化值稳定且可解析 | `storageValue = 'stale'`；`fromStorage` 逐值匹配，未知值回落 `unvalidated`（`:118-126`） | PASS |
| UI 完整映射 | 标签 `:360`（"内容已变更，需重新验证"）、颜色 `:386`（`tertiary`）；两处均为穷尽 switch（编译期保证不漏） | PASS |
| `afterContentChange` 规则 | `valid → stale`、`invalid → stale`、`unvalidated → unvalidated`、`stale → stale`、`validating → validating`（`:136-143`） | PASS |
| 不存在第二条失效规则 | `afterContentChange` 仅被 2 处调用（`section_control_service.dart:533`、`resource_generation_task_repository.dart:456`）；`lib/` 内无其它写 `validation_state` 的位置 | PASS |
| `valid` 不会在内容变化后复活 | 写 `valid` 的唯一路径是 `validateSection`（基于当前 Parts 重新计算），另有测试固定"从未验证过仍保持 `unvalidated`" | PASS |
| 字节级验证 | 域测试覆盖 `fromStorage('stale')` 与规则对全部 5 个状态的映射 + 幂等（`section_control_test.dart`） | PASS |

### 3. Part → Section 映射 — PASS

- `_syncOwningSection` 的第一条查询是 `SELECT section_id FROM resource_parts WHERE id = ?`，**唯一来源是 `resource_parts.section_id`**（`:427-440`）。
- 随后的 `SELECT validation_state FROM resource_sections WHERE id = ?` 只用于读取"已由 Part 行确定的那个 id"的当前结论，**不是**反查自身 id；第一轮 `_sectionRow` 式缺陷（返回 Section 行后读 `row['section_id']`）未重现。
- 测试覆盖：
  - 普通 Part：Case 1/2/3 在蓝图确认后的首个 ready Part 上提交（`resource_generation_task_repository_test.dart`）。
  - 多 Part Section：`setupConfirmedBlueprint()` 的同一 Section 含 2 个 Part；`streaming_resource_generation_service_test.dart` 的完整生成会先后提交同一 Section 的两个 Part（同一 `_syncOwningSection` 路径被执行两次，测试通过）。**观察（非缺陷）**：没有断言"同一 Section 被两次提交后令牌推进两次"，属覆盖密度问题而非不变量问题。
  - regenerate Part：`section_consistency_streaming_regeneration_test.dart` 经真实链路（executor → adapter → controller → service → coordinator → `commitPartContent`）提交正文，断言正文落库、结论 `stale`、令牌推进、新令牌仍可写。
- 边界：Part 行软删除后提交会在第 1 步（`deleted_at IS NULL` 更新 0 行）抛错，不会到达 Section 同步；Section 行查询未加 `deleted_at` 过滤，但在"Part 存活而 Section 已软删"不可达（`softDeleteNode` 级联标记 Parts），因此无实际影响。

### 4. D1 复验（Streaming generationId） — **VERIFIED**

| 检查 | 证据 | 结果 |
| --- | --- | --- |
| 旧逻辑（session id vs 协议 id 比较）已删除 | `grep -n "event.generationId\|PartStarted"` 于执行器 → **无命中** | PASS |
| 新逻辑：首个 patch 建立 baseline | `:101-106` `final runGenerationId = protocolGenerationId ?? event.patch.generationId;` → `binding ??=` 用该 id 构造绑定 | PASS |
| 新逻辑：后续 patch 必须一致 | 同一 binding 在后续 patch 上校验 `generationId`（`SectionGenerationBinding.validatePatch`），不一致即 `generationId` mismatch | PASS |
| 真实执行器测试：patch1=A, patch2=A → 成功 | `streaming_section_regeneration_executor_test.dart:39`（正确绑定成功）；`:97` `binds on the protocol generation, not the runtime session id`（事件=session id、patch=协议 id → 成功，正是旧逻辑必然失败的场景） | PASS |
| 真实执行器测试：patch1=A, patch2=B → 拒绝 | `:114` `rejects a late patch from a superseded generation`（断言错误含两个 id，且回报的 generationId 为首个 patch 的协议 id） | PASS |
| 测试调用真实 executor | `:23` `StreamingSectionRegenerationExecutor(runtime: port)`（仅端口为 fake） | PASS |
| resource/section/part 三维仍逐 patch 校验 | `:67`、`:85`、`:131` 三个不匹配拒绝用例 | PASS |

### 5. D2 审计裁定 — **NON-BLOCKING LIMITATION**

**事实（本轮独立复核）**

- `PartTaskStatus.completed` 为终态，仅允许自转移，且源码注释明确："Completed is terminal. Re-generating an already completed part requires an explicit reset or revision."（`resource_generation_protocol.dart:72-76`）。
- `startAttempt` 对已完成任务直接抛 `StateError('任务已完成，禁止重新发起生成')`（`resource_generation_task_repository.dart:207-209`）。
- `markTaskReady` 仅被 coordinator 的**失败任务**重试分支调用（`part_generation_coordinator.dart:326`），不存在对已完成任务的重置。
- 因此对一个"全部 Part 已生成完成"的 Section 执行重新生成会在 `startAttempt` 失败，服务发出 `SectionGenerationFailedEvent` 并在面板显示错误。

**Phase 7 要求判读（`phase-07-section-controls.md`）**

- 目标确实包含"让用户对单个 Section/Part 执行重新生成"，因此这是本阶段承诺的能力方向。
- 但实施步骤第 2 条同时写明"重新生成前的**版本保护由 Phase 9 接管**，本阶段保留接入点"；验收清单要求的是命令语义与编排（"每种命令只改变目标节点/顺序"、"两个并发编辑基于旧版本提交时后提交者收到冲突"、"AI prompt 只包含目标节点"、"全部重新生成被拆成 Part 任务"），**没有任何一条要求"对已完成 Section 的重新生成必须成功"**。

**裁定：NON-BLOCKING LIMITATION**

理由：

1. **不违反任何数据一致性不变量。** 失败发生在任何写入之前（`startAttempt` 抛错 → 事务未开启/无副作用），不留部分状态、不产生过期结论、不移动令牌。本题门控 Phase 8 的是"Section 数据一致性是否可靠"，该问题不触及它。
2. **根因属于 Phase 5 任务生命周期设计，且其重置语义被 Phase 5 层显式保留。** 源码注释要求"an explicit reset or revision"：实现重置意味着决定任务/版本生命周期（重置为 `ready`？开新 attempt？走 Phase 9 revision？），这正是 Phase 7 方案把版本保护交给 Phase 9 的那类决策，超出 Phase 7 的授权范围。
3. **失败是显式且有界**：用户看到明确错误文本，不产生静默损坏。

**强制携带项（不作为 blocker，但必须在 Phase 8 前落地其一）**

- 选项 A：按 Phase 5 注释的授权方式实现"显式重置"（例如 `regenerateSection` 启动前对目标 Section 的 `completed` 任务执行受控重置），并补相应任务状态机测试；
- 选项 B：保持不支持，同时**修正 UI**：当前 `_generateLabel`/门控在 `completed` 状态下把"重新生成"呈现为可用（`resource_studio_section_controls.dart:231-241, 338-343`），必须改为禁用并说明原因，避免继续宣传不可用的动作。
- 无论选哪条，都需在 Phase 8 的阶段文档中登记；Phase 9 的 revision 体系落地后应重新评估选项 A 的正式实现。

### 6. F1–F6 回归确认

| 项 | 结果 | 证据 |
| --- | --- | --- |
| F1 regenerate 乐观锁 | **PASS** | 8 个变更命令均 `required super.expectedUpdatedAt`（`resource_edit_command.dart:100-224`）；validator 8 个分支均 `_requireToken`（`:268-313`，含 regenerate `:311`）；service 在任何 Part 启动前比对持久化令牌（`section_control_service.dart:408-415`）；生产调用链唯一（controller → runtime → service） |
| F2 Section 版本一致 | **PASS**（本轮由 B1 补齐为**全部写入者**） | 树仓库 8 条 Part 路径 + 流式提交路径；旧令牌写回拒绝见 Case 2 |
| F3 迁移测试 | **PASS** | `database_migration_v36_test.dart:49` 与 `database_migration_v38_test.dart:39` 均为固定 `38` |
| F4 真实执行器覆盖 | **PASS** | 10 个用例直驱真实执行器，含正确绑定、三维不匹配、D1 两例、失败/抛错/无会话 |
| F5 UI 生成门控 | **PASS** | widget 中 `partCount` 出现 0 次；由 `hasGenerationTasks` 门控（`:231/237/338`），来源 `section_control_service.dart:624` |
| F6 文档准确 | **PASS** | §5.1 已明确"两类写入者"并写明映射来源与失效规则；§5.2 写明 session id vs 协议 id 与端到端覆盖；§5.3 修正为"对两类写入者关闭"并披露 D2；§2.1 枚举补 `stale`。无遗留过宽声明 |

### 7. 测试与工具验证

```text
dart format --output=none --set-exit-if-changed .   exit 0（404 files, 0 changed）
flutter analyze                                     No issues found!（2.2s）
flutter test -r compact                             1023 passed（exit 0，1m35s）
```

- 全仓库无 `skip` / `@Skip` / `markTestSkipped`。
- 本轮为只读审计：审计未修改任何代码、测试或文档（除本验收报告自身），未创建 commit（HEAD 仍为 `054e452`）。

### 8. 架构不变量复核（不依赖测试结论，逐项独立判断）

| 不变量 | 判断 | 依据 |
| --- | --- | --- |
| Section 内容变更 ⇒ Section 版本推进 | 成立 | 两个写入者（唯一）均在各自同一事务内推进；见 §1.2 |
| Section 内容变更 ⇒ 已记录结论不得仍为 `valid` | 成立 | 单一规则 `afterContentChange`；无第二条写入路径；`validateSection` 只基于当前 Parts 重新判定 |
| 内容写入与版本/结论更新原子 | 成立 | 单事务 + Case 3 强制失败回滚证据 |
| Part → Section 归属唯一且权威 | 成立 | 仅取 `resource_parts.section_id`；缺失/损坏时抛错回滚 |
| Phase 5 wire protocol 未被破坏 | 成立 | patch 字段、parser、streaming service、coordinator 0 改动；wire 格式未变 |
| Phase 6 Studio 未被破坏 | 成立 | 仅新增端口/执行器/面板；Phase 6 用例全通过 |
| 无绕过 service 的数据库操作 | 成立 | `lib/features/resource_studio/` 无 sqflite/DatabaseService 引用 |
| 状态机无非法迁移 | 成立 | Section 生成态为推导值不写入；NodeStatus 经 `ResourceStateMachines.advanceNodeStatus` 校验；`stale` 是枚举值而非散落字符串 |
| UI 显示与数据库一致 | 成立 | 无本地乐观缓存（变更后重读首页）；`stale` 有完整映射；不再存在"内容变了仍显示验证通过" |

## Remaining Risks

**Non-blocking limitations**（已核实、不阻塞 Phase 7 与 Phase 8，但需携带）

1. **D2（上节）**：已完成任务不可重新生成，需按选项 A 或 B 在 Phase 8 前落地其一。
2. **regenerate 令牌为启动前比对，非数据库 CAS**：比对与首个 Part 启动之间存在 TOCTOU 窗口（`section_control_service.dart:408-415`）。重生成本就要替换正文，防线目标是"不基于过期读发起"；如需严格串行化，应在 Phase 9 Revision 边界引入原子 claim。
3. **`stale` 的 `validated_at` 保留**：结论降级时清空消息但保留 `validated_at`（记录该结论产生时间），UI 不展示——需在 Phase 8/9 若引入"验证历史"时明确其语义。
4. **`_reorderNode` 的 Part 分支不刷新 Resource `updated_at`**：改动前即存在、未扩大；影响仅限资源列表按 `updated_at DESC` 的新鲜度排序。
5. **多 Part Section 的令牌推进缺少显式断言**：路径已被执行覆盖，但未直接断言"同一 Section 两次提交 → 令牌两次推进"。
6. **时间戳令牌粒度**：`updated_at` 使用微秒级 ISO 字符串作为乐观锁令牌（Phase 1 以来的项目级设计），同一微秒内的两次写入理论上令牌相同；非 Phase 7 引入，记录备查。
7. **跨进程/多实例并发**不在当前范围（单进程 SQLite 访问模型）。

## Round 1 record (superseded)

保留失败记录，不删除：Round 1 对本阶段的判定为 **FAILED**，唯一 Blocker 为 **B1**（`commitPartContent` 未同步 Section 版本与校验状态），并列出风险 A/B/C 与两项次要观察。该轮完整文本保存在 git 历史中：`git show 054e452:docs/adaptive-resource-system/phase-07-final-independent-acceptance.md`（Round 1 文本随 B1 remediation 的文档提交一并纳入版本控制）。本轮结论为复验结论：B1 已 CLOSED，D1 已 VERIFIED，D2 裁定为非阻塞。

## Unlock Decision

Phase 7 = **ACCEPTED**。Section 数据一致性不变量在全部内容写入者上成立且有原子性与端到端证据，F1–F6 全部 PASS，Phase 5/6 未被破坏，`flutter analyze` 与全量 1023 个测试通过。

**Phase 8（容量与语义压缩）解除 `BLOCKED`，可由 `NOT_STARTED` 进入实施**；上述 7 项非阻塞限制（尤其第 1 项 D2 的选项 A/B 决策）应在 Phase 8 阶段文档中登记并处理。
