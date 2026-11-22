# Phase 8 Final Independent Acceptance — Round 2

**Auditor:** independent acceptance agent (read-only)
**Date:** 2026-09-17
**Scope:** 复验第一轮审计 BUG-001～BUG-004 的 remediation、寻找新增回归/竞态/状态机问题、重评估 A5～A12 与 INFO-001～006、判定 Phase 8 是否 ACCEPTED / Phase 9 是否解锁。

---

## Verdict

**FAILED**

Phase 9 remains **BLOCKED**。

Remediation 确实交付了第一轮缺失的能力（孤儿任务回收、生产可达的重试入口、可操作的超预算失败、阈值触发接线），孤儿死锁本身与重试可达性都已实测修复。但本轮发现：

1. **BUG-001 只部分关闭**：恢复逻辑不是"进程启动一次性"，`recoverInterruptedJobs()` 在**每次 Studio 容量加载**时执行且**全局回收 `running` 行**，会回收仍由活跃 worker 持有的任务（动态复现：`reclaimed=1`，随后同一任务被并发送模型两次）。coordinator 自带的 `_recoveredThisInstance` 闩锁被显式调用绕过，恢复方法只写不读该闩锁。
2. **BUG-003 只部分关闭**：自动触发挂在 **Studio 打开（controller.load）**，不是"离开编辑器"；且**没有任何后台消费者**——自动排入的 job 在用户手动点"生成压缩候选"之前永不执行。Phase 8 原文"离开编辑器后的后台 compression job"未交付。
3. **两个新增 High/Major 缺陷**（均动态复现）：恢复回收活跃任务导致重复并发模型调用与 attempts 丢失更新（BUG-R2-001）；`retryFailedJobs` 在"目标已存在新 queued job"时违反 `idx_compression_jobs_active_target`，把原生 `SqfliteFfiException` 抛到 UI 并中断其余失败任务的重试（BUG-R2-002）。
4. **A5、A7 严重度上调为 MAJOR**（自动排队接线后可达性显著上升，A7 已动态复现双 drain 重复执行同一 job）。

依据验收标准 A（BUG-001 CLOSED）、C（BUG-003 CLOSED）、E（无新增 Blocking Major/High）、N（自动触发满足 Phase 8 运行期要求）均不成立，故 **FAILED**。

---

## Git Baseline

| 项 | 值 |
| --- | --- |
| Expected Start | `752b440` |
| Remediation Commit | `024dd64` |
| Expected HEAD | `03947be` |
| **Actual HEAD** | **`03947be`**（`git rev-parse HEAD` 实测一致） |
| Branch | `main` |
| 分支同步 | `origin/main` 停在 `6dde079`（本地领先，未推送） |
| 工作区 | 仅 `?? .codebuddy/`（既有本地工具目录）与 `?? docs/adaptive-resource-system/phase-08-independent-audit.md`（第一轮审计报告，未跟踪）。**无意外修改。** |

`git diff --stat 752b440..03947be`：15 files changed, 1098 insertions(+), 83 deletions(-)。与 remediation 报告（14 个 remediation 文件 + STATUS.md）一致。

```text
 git status --short
?? .codebuddy/
?? docs/adaptive-resource-system/phase-08-independent-audit.md
 git branch --show-current
main
 git rev-parse HEAD
03947be1a0c52bc034d202be917b622911244aa3
 git diff --name-only 752b440..03947be
docs/adaptive-resource-system/STATUS.md
lib/application/resources/compression_coordinator.dart
lib/application/resources/compression_job_repository.dart
lib/domain/resources/resource_compression.dart
lib/features/resource_studio/application/use_cases/resource_capacity_runtime.dart
lib/features/resource_studio/domain/models/resource_capacity_view_state.dart
lib/features/resource_studio/presentation/controllers/resource_capacity_controller.dart
lib/features/resource_studio/presentation/pages/resource_studio_page.dart
lib/features/resource_studio/presentation/widgets/resource_capacity_panel.dart
test/application/resources/compression_pipeline_test.dart
test/application/resources/resource_capacity_runtime_test.dart
test/domain/resources/resource_compression_test.dart
test/helpers/resource_capacity_fakes.dart
test/helpers/resource_tree_fixtures.dart
test/widget/resource_capacity_test.dart
```

---

## Remediation Closure Matrix

| Finding | Result | Evidence |
| --- | --- | --- |
| BUG-001 | **PARTIALLY CLOSED** | 孤儿 `running` 回收已实现且有界（`compression_job_repository.dart:217-249`，两条常量 UPDATE；`attempts < max_attempts → queued`，`attempts >= max_attempts → failed`），状态机只加一条保留边（`resource_compression.dart:63-73,89-95`），`drain` 首次自动恢复（`compression_coordinator.dart:206-211`），测试 `compression_pipeline_test.dart:445-505`、`resource_capacity_runtime_test.dart:204-258` 用真实 SQLite 断言。**但恢复不是启动一次性**：`recoverInterruptedJobs()`（`:263-271`）只写不读 `_recoveredThisInstance`，而 `resource_capacity_controller.dart:64` 在**每次** `load()` 都显式调用它，SQL（`compression_job_repository.dart:226-246`）按 `status='running'` 全局回收、不校验归属。动态探针复现：活跃 drain 的 job 被回收（`reclaimed=1 status=queued error=应用重启，已释放中断的压缩任务`），随后同一 job 并发调用模型两次（`llmCalls=2`）。详见 BUG-R2-001。 |
| BUG-002 | **CLOSED** | 重试已生产可达：`ResourceCapacityRuntime.retryFailedCompression`（`resource_capacity_runtime.dart:98-100`）→ `CompressionCoordinator.retryFailedJobs`（`compression_coordinator.dart:273-286`，按资源过滤、仅 `failed && canRetry`）→ `retryJob`（`:249-261`，`failed→queued` 合法边，`errorMessage` 清空，`attempts` **不重置**）→ controller（`resource_capacity_controller.dart:145-171`）→ Panel 按钮（`resource_capacity_panel.dart:99-111`，`hasRetryableFailures` 才可点）与失败原因（`:68-75`）。真实 DB 测试 `resource_capacity_runtime_test.dart:154-201` 覆盖"失败可见→重试→成功 exactly once"与"预算耗尽后 `retryFailedCompression == 0`"；widget 测试覆盖 320px 下按钮计数与禁用态。 |
| BUG-003 | **PARTIALLY CLOSED** | 阈值触发已接线并非空实现：`autoQueueCompressionIfNeeded`（`resource_capacity_runtime.dart:86-96`）实时 `measure` → `evaluateResource` → 仅超限 `enqueueForResource`，只建 job（实测 `llm.calls == 0`、正文不变，`resource_capacity_runtime_test.dart:71-140`），且以 `unawaited` 后台链执行、不在 `build` 触发（`resource_capacity_controller.dart:31-51,58-80`；widget 测试 `load starts recovery and the threshold trigger in the background`）。**但**：(a) 触发点是 Studio **打开**（`load`），不是"离开编辑器"（`dispose()` 无任何排队逻辑，`resource_capacity_controller.dart:204-209`）；(b) `grep -rn "\.drain\(" lib/` 只有 `resource_capacity_runtime.dart:79`，其生产者只有手动 `requestCompression`/`retryFailedCompression`——**自动排入的 job 没有后台消费者**，不点按钮永不执行。Phase 8 `phase-08-capacity-and-compression.md:11` 要求的"离开编辑器后的后台 compression job"未交付。 |
| BUG-004 | **CLOSED** | 验收带未放宽：`overBudget` 仍拒绝（`resource_compression.dart:539-556`），文案携带原文/实际/目标/达成比，经 `latestFailureReason` 上屏（`resource_capacity_view_state.dart:40-43`、`resource_capacity_panel.dart:68-75`）并可重试。测试 `compression_pipeline_test.dart:507-550` 固定 800→560 失败（错误含"原文 800 字/目标 480 字"）、无候选、正文逐字符不变、`retryFailedJobs == 1`、512→400 成功后候选恰好 1 个；`resource_compression_test.dart:188-196` 钉死 `compressionTargetRatio == 0.6`、`nodeTargetCharacters(800) == 480`。残留：`resource_compression.dart:440` 的类文档仍写"A candidate that misses it is still a candidate"，与校验器冲突（见 BUG-R2-003，MINOR）。 |

### 四类回归测试要求逐条核对（第十五节）

1. **persisted running recovery** — 真实 SQLite + 真实 coordinator：`compression_pipeline_test.dart:445-465`（`running`→新 coordinator→`drain`→succeeded）、`:467-494`（预算耗尽→failed）、`:496-505`（幂等）；`resource_capacity_runtime_test.dart:205-257` 走生产 runtime。**真实路径，非 mock。**
2. **reachable retry** — 真实 DB 走 `runtime.retryFailedCompression`（`resource_capacity_runtime_test.dart:154-201`）。UI 层用 `FakeResourceCapacityRuntime` 验证按钮/文案/禁用（`test/widget/resource_capacity_test.dart`）。**未有一条单测从"面板按钮"直连"真实 runtime→SQLite"**（分段覆盖，非端到端）。
3. **non-blocking automatic enqueue** — `resource_capacity_runtime_test.dart:71-140`（真实 DB：`llm.calls == 0`、正文不变、同 token 去重）；controller 层 `load` 首屏 `ready` 不等待后台链。**未在 widget 层断言"首屏不被 autoQueue 阻塞"的真实 runtime 版本**（fake runtime 即时返回，无法证明慢 measure 不阻塞渲染；静态上 `unawaited` 成立）。
4. **realistic compression ratio** — `compression_pipeline_test.dart:507-550`，符合要求。**非 mock。**

---

## Remaining Findings Reassessment

### A5 — `drain` 是全局队列，结果记在当前资源上

**Severity: MINOR → MAJOR**
**Status: OPEN（未修复，可达性因 BUG-003 接线而显著上升）**

- 证据：`compression_coordinator.dart:213-217` `findJobsByStatus(queued, limit)` 无 `resource_id` 过滤；`compression_job_repository.dart:189-203` 仅按 `status` 过滤、`orderBy created_at ASC` 全局排序；`resource_capacity_controller.dart:173-196` 用全局 progress 拼装当前资源 A 的消息。
- 触发：打开 A 的 Studio（自动排队 A 的 job）→ 打开 B 的 Studio（自动排队 B 的 job）→ 在 B 上点"生成压缩候选"。因自动排队已接线，多资源同时存在 queued job 由"异常"变为**常规**。
- 影响：`maxJobsPerDrain = 4` 被 A 的 job 抢占，B 的 job 可能不执行；B 的面板却显示"已生成 N 个压缩候选"（N 主要是 A 的）。DB 归属正确（候选按 job 的 `resource_id` 落库），故非数据损坏，但为**误导性成功反馈 + 资源间调度饿死**。
- 根因：`drain` 被设计为全局 worker，而唯一生产者是资源作用域动作，两个契约不一致。
- 建议：给 `findJobsByStatus`/`drain` 增加可选 `resourceId`，Studio 手动入口传当前资源；全局 worker 留给未来后台调度。

### A6 — cancelled / 无正文被计入 failed

**Severity: MINOR（不变）**

- 证据：`compression_coordinator.dart:221-229`（`_runJob` 返回 false ⇒ `failed++`，不区分终态）；`:321-327`（无正文 ⇒ `cancelled`）；`:313-316,:335-338`（取消 ⇒ `cancelled`）；`resource_capacity_controller.dart:177-188`（`failedJobs > 0` ⇒ `failed` 状态 + "N 个压缩任务失败"）。`CompressionRunProgress` 无 cancelled 桶。
- 影响：误报失败。**不影响重试/状态机正确性**（job 自身状态是 `cancelled`，不进入可重试集合），保持 MINOR。

### A7 — 无原子 claim / 无 CAS（**本轮动态复现**）

**Severity: MINOR → MAJOR**
**Status: OPEN，已由动态探针证实**

- 证据：`compression_job_repository.dart:172-187` `updateJob` 无条件 `WHERE job_id = ?` 写 `status/attempts`；`compression_coordinator.dart:298-311` `running` 由调用方陈旧副本派生后盲目写入，无 `WHERE status='queued'` 守卫。
- 动态复现（临时探针，已删除）：对同一 coordinator 并发发起两次 `drain(maxJobs: 1)`，单个 queued job 的结果为 `PROBE2 llmCalls=2` —— 同一 job 被两个 drain 同时执行。
- 生产可达路径：`resourceCapacityRuntimeProvider` 是**非 autoDispose 的 Provider**（`riverpod_providers.dart:352-369`），coordinator 与 `_recoveredThisInstance` 进程级共享；`ResourceCapacityController` 每页一个，`dispose()` 时 `_runtime.dispose()` 为空实现（`resource_capacity_runtime.dart:102-103`），`_runQueue` 不传 `taskHandle`（`resource_capacity_controller.dart:175`）故**不可取消**。因此"旧页 drain 仍在跑 → 新页再点压缩"即可并发。
- 影响：同一 job 重复模型调用（成本）、`attempts` 丢失更新（实测两次执行后 `attempts` 为 1 或 2，取决于写入顺序）、终态被后写者覆盖（一次成功一次失败时最终状态不确定）。候选行因 `idx_compression_candidates_job` UNIQUE + `ConflictAlgorithm.replace`（`compression_job_repository.dart:271`）不会重复。
- 建议：原子 claim（`UPDATE ... SET status='running', attempts=attempts+1 WHERE job_id=? AND status='queued'`，受影响行数为 0 则跳过），`updateJob` 增加期望源状态 CAS。

### A8 — 容量缓存不一致

**Severity: MINOR（不变，但运行期风险已被切断）**

- 证据：`resource_capacity_repository.dart:309` `historicalRevisionCount: 0` 硬编码；`:286` 读取 `capacity_status` 但 `:310` 由 `measured_char_count` 重算，列只写不读；`resource_capacity_runtime.dart:56-61` `summarize` 优先返回缓存；`resource_capacity_panel.dart:151` 直接渲染该值。
- **关键区分（本轮结论）**：自动触发使用 `_capacityService.measure(id)`（`resource_capacity_runtime.dart:91`），`measure` 走 `measureResource` 真实聚合（`resource_capacity_service.dart:22-26`），**不读缓存**——因此触发决策与缓存陈旧无关，A8 保持"纯展示滞后"性质。
- 残留：`load` 的后台链只有在 `queued > 0` 时才回写面板（`resource_capacity_controller.dart:66`），否则面板保留陈旧缓存；`历史版本` 恒显示 0。

### A9 — archived 目标语义不一致

**Severity: MINOR（不变）**

- 证据：`compression_coordinator.dart:129-171` 仅过滤 `isComplete`/`minNodeCharacters`/`isDeleted`，**无 archived 过滤**；`resource_context_compressor.dart:206-207` 排除 archived section；`resource_capacity_repository.dart:84-86,128-130` 把 archived 计入 `totalCharacters`。
- 影响：把非正典节点当压缩目标，浪费模型调用与候选行；两组件口径不一致（不会数据损坏，候选不会自动应用）。

### A10 — `recent` 语义与文档不符

**Severity: MINOR（不变，仍无生产调用方）**

- 证据：`resource_context_compressor.dart:187-188` 文档写"newest sections"，`:210-217` 实际取当前章节之前 N 个；`currentIndex < 0` 时边界退化为 `list.length`，全部降级为 `historicalSummary`。`grep -rn "ResourceContextAssembler" lib/` 无生产调用方，属 Phase 10 前潜伏缺陷。

### A11 — 候选 `original_char_count` 含 `\n\n`

**Severity: MINOR（不变）**

- 证据：`compression_coordinator.dart:341-342` `request.nodes.map((n) => n.content.trim()).join('\n\n')`，`:366` `originalCharacters: originalContent.length`；`sumSavedCharacters`（`compression_job_repository.dart:317-329`）求和该口径；面板同屏展示容量口径 `正文 N 字`（`resource_capacity_panel.dart:147`）。
- 影响：仅 UI 节省数字被高估 `2(n-1)`，**不参与** validation/trigger/budget（budget 用的是 `_buildRequest` 的 `Σ node.content.length`，`:437-450`）。

### A12 — 并发 enqueue 暴露内部 `StateError`

**Severity: MINOR（不变，但可达性上升）**

- 证据：`compression_job_repository.dart:130-170` `ConflictAlgorithm.ignore` 后按 version 读回，若冲突来自 `idx_compression_jobs_active_target`（不同 `source_token`）则读回 null ⇒ `StateError('压缩任务写入后无法读回…')`；`resource_capacity_controller.dart:94-98`/`:78` 直接 `error.toString()` 上屏。
- 可达性：自动排队（每次 `load`）与手动排队现在会并发调用 `_enqueue`，竞态窗口变宽；影响仍限于错误文案质量。**其更严重的同源变体见 BUG-R2-002。**

### INFO-001 ～ INFO-006

逐项确认**仍然存在**，remediation 未涉及：

- **INFO-001 死代码**：`enqueueNode`（`compression_coordinator.dart:176`）无调用方；`findCandidateForJob`（`compression_job_repository.dart:58,276`）无调用方；`cacheColumns`（`resource_capacity_repository.dart:66`）无调用方；`CompressionRunProgress.fraction`（`compression_coordinator.dart:62`）无调用方。`grep` 证实仅声明/实现，无生产消费。
- **INFO-002 retention 为模型自述**：未变（无新增非自述校验）。
- **INFO-003 压缩 prompt 缺非可信内容围栏**：未变。
- **INFO-004 压缩行无清理策略**：未变；自动排队使孤儿/历史行数量上升。
- **INFO-005 section 候选无 per-Part provenance**：未变。
- **INFO-006 `_generateLabel` 超出 D2 范围**：未变（`resource_studio_section_controls.dart:340`，本轮 diff 未触碰）。

无 INFO 项因 remediation 被升级为影响 Phase 8 验收的问题。

---

## New Findings

### BUG-R2-001

**Severity: High（Major）**

**Description**

`recoverInterruptedJobs()` 不是"进程启动一次性"，而是**每次 Studio 容量加载**都会执行，并把**全局**处于 `running` 的任务无条件回收为 `queued`，不校验该行是否仍由活跃 worker 持有。活跃 drain 的任务会在执行途中被"释放"，随后被另一个 drain 再次取走并发执行。

**Location**

- `lib/features/resource_studio/presentation/controllers/resource_capacity_controller.dart:64` — `_runBackgroundWorkflow` 每次 `load()` 无条件 `await _runtime.recoverInterruptedJobs()`。
- `lib/application/resources/compression_coordinator.dart:267-271` — `recoverInterruptedJobs()` 只写 `_recoveredThisInstance = true`，**不读**它；`:209-211` 的 `drain` 才读该闩锁。⇒ 显式调用可无限次绕过"每进程一次"。
- `lib/application/resources/compression_job_repository.dart:226-246` — 两条 UPDATE 按 `status='running'`（+ attempts 条件）全局回收，无 owner/lease 校验。
- `lib/application/resources/compression_coordinator.dart:70-72` — 设计注释断言"a live worker always finishes through succeeded/failed/cancelled"，`:206-208` 断言"nothing of ours can be in `running` yet"，两处前提在本调用路径下均不成立。

**Trigger conditions**

1. 打开资源 A 的 Studio → 后台链排队 A 的 job → 点"生成压缩候选" → `drain` 将 job 置 `running` 并在 LLM 请求中等待（数秒）。
2. 请求未完成期间进入另一资源 B 的 Studio（新页面，或同页切换 session 使 `state.resourceId` 变化 → `resource_studio_page.dart:72-78` 再次 `load`）。旧页 `dispose()` 不取消 drain（`resource_capacity_runtime.dart:102-103` 空实现、`drain(taskHandle: null)`）。
3. 新页 `load` → `_runBackgroundWorkflow` → `recoverInterruptedJobs()` → A 的活跃 `running` 行被改写为 `queued`，`error_message` 被写成"应用重启，已释放中断的压缩任务"。

**Actual impact**

- 同一 job 被**并发**送模型两次：临时探针实测 `llmCalls=2`（单 job）。
- 活跃任务的 `attempts` / 终态发生**丢失更新**（两个执行者各自以陈旧内存副本写 `updateJob`，`compression_job_repository.dart:172-187` 无条件覆盖）：探针观察到最终 `attempts` 与写入顺序相关。
- 活跃任务被写入伪造的"应用重启"错误原因。
- 候选行不会重复（`idx_compression_candidates_job` UNIQUE + replace），资源正文不受影响。

**Root Cause**

恢复被设计为"无归属校验的全局状态重置"，而触发它的 `drain` 首次路径有"此时本进程不可能有 running"的前提；remediation 又把该方法接到**每次容量加载**上，前提被破坏，且 coordinator 的闩锁只保护 `drain` 一侧。

**Reproduction / Proof（动态，已执行）**

临时探针（真实 SQLite + 真实 coordinator，`test/tmp_r2_recovery_race_probe_test.dart`，验证后已删除）：

```text
PROBE reclaimed=1 status=queued error=应用重启，已释放中断的压缩任务
PROBE final status=succeeded attempts=2 llmCalls=2 candidates=1
```

断言 `reclaimed == 1` 在 drain 仍在飞行时成立 ⇒ 活跃任务被回收；随后第二次 drain 使 `llmCalls == 2`。

**Recommended Fix**

给回收加"归属/时间"约束而非无条件全局重置，任选其一：(a) `recoverInterruptedJobs()` 内部改为 `if (_recoveredThisInstance) return 0;` 并只在应用启动（`main.dart` 的启动钩子）调用一次；(b) 引入 lease（`running` 行带 `claimed_at`/owner），只回收超过超时阈值的行；(c) 收窄要求：仅当行 `updated_at` 早于本进程启动时间才回收。同时修正 `compression_coordinator.dart:70-72` 的注释或使其成立。

**Affected Files**

`resource_capacity_controller.dart`、`compression_coordinator.dart`、`compression_job_repository.dart`

---

### BUG-R2-002

**Severity: High（Major）**

**Description**

重试路径绕过了 active-target 唯一约束的保护：当同一 target 已存在一个新的 `queued` job（例如章节被编辑、token 变化后由自动/手动排队产生）时，`retryJob` 把旧的 `failed` job 直接写为 `queued`，触发 `idx_compression_jobs_active_target` 唯一约束失败，原生 `SqfliteFfiException` 抛到 UI，并中断该资源其余失败任务的重试。

**Location**

- `lib/application/resources/compression_coordinator.dart:249-261` — `retryJob` 只做 `canRetry` 检查，随后 `updateJob(status: queued)`，**不检查 target 是否已有 active job**（对比 `_enqueue` 的 `findActiveForTarget` 守卫，`:499-503`）。
- `lib/application/resources/compression_job_repository.dart:172-187` — `updateJob` 无冲突处理。
- `lib/services/database_service.dart:507-510` — `idx_compression_jobs_active_target` 唯一约束 `(resource_id, target_node_id) WHERE status IN ('queued','running')`。
- `lib/application/resources/compression_coordinator.dart:278-286` — `retryFailedJobs` 的循环在异常处整体中断，同资源后续失败 job 不再重试。
- `lib/features/resource_studio/presentation/controllers/resource_capacity_controller.dart:165-170` — `errorMessage: error.toString()` ⇒ 用户看到 SQLite 原生错误。

**Trigger conditions**

1. 章节 T 的 job J1 失败（`attempts=1`，`canRetry=true`）。
2. 用户编辑该章节 → `resource_sections.updated_at` 变化（生产写入路径 `resource_tree_repository_impl.dart:348-360` 确实写 `updated_at`），token 变化。
3. 任何 `enqueueForResource`（打开 Studio 的自动排队，或手动"生成压缩候选"）为 T 插入新 job J2（`findActiveForTarget` 不匹配 `failed` 行，故可插入）。
4. J2 仍为 `queued`（自动排队后不执行，见 BUG-003）时，用户点击"重试失败压缩（N）"。

**Actual impact**

- 面板显示原生数据库错误（`SqfliteFfiException ... UNIQUE constraint failed: resource_compression_jobs.resource_id, resource_compression_jobs.target_node_id`），对用户不可读、不可操作。
- 该资源**其余可重试任务**全部被跳过（循环中断），重试功能在该状态下整体失效。
- 不损坏数据（`resource_parts.content` 未变，候选未生成）。

**Root Cause**

`retryJob` 是"凭 job id 直写状态"的操作，未复用 `_enqueue` 的 active-target 守卫，也未把唯一约束失败映射为领域结果；remediation 让它第一次进入生产路径，才使该缺失显形。

**Reproduction / Proof（动态，已执行）**

同一临时探针第三个用例（已删除）：

```text
PROBE3 jobs=[probe_job_2:failed, probe_job_3:queued]
PROBE3 retry threw: SqfliteFfiException(sqlite_error: 2067, SqliteException(2067): while executing statement, UNIQUE constraint failed: resource_compression_jobs.resource_id, resource_compression_jobs.target_node_id ...)
```

**Recommended Fix**

`retryJob` 在写入前调用 `findActiveForTarget`；若已有 active job，则**不新建第二个 active 行**——选择"复用该 active job 并保留/合并重试意图"或"将该 active job 视为取代者并把旧 failed job 标记为 `cancelled`（`failed → cancelled` 是合法边）"，并把冲突映射为领域异常而非原生 DB 异常；`retryFailedJobs` 应逐 job 隔离失败而不是整体中断。

**Affected Files**

`compression_coordinator.dart`、`compression_job_repository.dart`、`resource_capacity_controller.dart`

---

### BUG-R2-003

**Severity: Low（Minor）**

**Description**

`latestFailureReason` 的语义与实现不符：模型/UI 标注"最近一次"，实现返回列表首个失败原因。

**Location**

- `lib/features/resource_studio/domain/models/resource_capacity_view_state.dart:41-43` — "The most recent failure reason"。
- `lib/features/resource_studio/application/use_cases/resource_capacity_runtime.dart:133-143` — `_firstFailureReason` 遍历返回**第一个**带消息的 failed job。
- `lib/application/resources/compression_job_repository.dart:205-215` — `findJobsForResource` `ORDER BY created_at ASC` ⇒ "第一个"是**最旧**失败。
- `lib/features/resource_studio/presentation/widgets/resource_capacity_panel.dart:71` — 文案"最近一次压缩失败原因"。

**Actual impact** 多任务失败时展示最旧而非最近的原因，可能误导重试判断。纯展示问题。

**Recommended Fix** 改为取最后一个失败（或按 `updated_at DESC` 排序），或把文案/文档改为"首要失败原因"。

**Affected Files** `resource_capacity_runtime.dart`、`compression_job_repository.dart`、`resource_capacity_panel.dart`

---

### BUG-R2-004

**Severity: Low（Info）**

**Description** 域文档与实现冲突（自 Phase 8 原始实现起存在，本轮未修复）。

**Location** `lib/domain/resources/resource_compression.dart:440` — "A budget is a *goal*: a candidate that misses it is still a candidate, and nothing in this class ever truncates content."；实际 `CompressionValidator`（`:539-556`）把超预算结果判为失败且**不落候选**。

**Actual impact** 文档会诱导后续阶段实现"短但超预算仍是候选"的语义，与当前验收带冲突。Phase 8 文档 `:20`（"不满足目标时报告原因"）与审计建议曾倾向保留该结果；remediation 选择保留硬拒绝并让其可操作，这一取舍本身自洽（预算耗尽是硬停止，见 `resource_compression_test.dart:178-196`），但类文档必须同步。

**Recommended Fix** 更新该注释以描述实际验收带，或明确"超预算结果不生成候选"为契约。

---

### 无 Blocker 级新增问题

未发现新增 BLOCKER。两个 High 缺陷均有动态证据与可达生产路径，但不造成资源正文损坏、不提前实现 Phase 9 能力。

---

## Concurrency Review

| # | 场景 | 结论 | 证据 |
| --- | --- | --- | --- |
| 1 | 两个 `drain` 同时调用 | **缺陷确认（动态）** | 临时探针：`PROBE2 llmCalls=2`（同一 job 被执行两次）；无 claim/CAS（`compression_job_repository.dart:172-187`、`compression_coordinator.dart:298-311`）。见 A7。 |
| 2 | `autoQueue` 与手动 `requestCompression` 同时调用 | 竞态存在，后果受限 | 二者都会 `_enqueue`；`findActiveForTarget` + `idx_compression_jobs_active_target` 保证同一 target 至多一个 active 行，不同 token 的落败方走 `insertJob` 读回 null ⇒ `StateError`（A12）。**不产生重复 job**，最坏是错误文案。 |
| 3 | `retry` 与 `autoQueue` 同时调用 | **缺陷确认（动态）** | BUG-R2-002：retry 与已存在的新 queued job 冲突 ⇒ UNIQUE 约束异常上屏。 |
| 4 | 资源切换期间后台链完成 | 结果隔离正确，副作用未隔离 | `_runBackgroundWorkflow` 以 `startedFor` + `_isStillShowing` 丢弃过期结果（`resource_capacity_controller.dart:62-83`）✓；但**恢复/排队副作用仍会作用于旧资源**，且 `_emit` 受 `_disposed` 保护 ✓。 |
| 5 | `recovery` 与 `drain` 同时运行 | **缺陷确认（动态）** | BUG-R2-001：活跃 `running` 行被回收。 |
| 6 | 两个 coordinator 实例 | 生产无此形态，测试有 | `resourceCapacityRuntimeProvider` 是单例 Provider（`riverpod_providers.dart:352-369`），生产只有一个 coordinator；测试中 `buildCoordinator` 会被重复创建（`compression_pipeline_test.dart:193-209`），此时第二个实例的首次 `drain` 会回收第一个实例的活跃行——同 BUG-R2-001 机制。 |

说明：场景 2、5、6 的"仅静态证明"部分已在上表标注；场景 1、3、5 有动态证据。

---

## Phase Boundary Verification

```text
git diff --name-only 752b440..03947be -- <Phase 5/6/7 冻结文件>   → 空
```

覆盖并确认为 **0 改动**：`part_generation_coordinator.dart`、`part_generation_prompt_builder.dart`、`part_generation_parser.dart`、`part_generation_validator.dart`、`generation_patch_parser.dart`、`resource_generation_protocol.dart`、`resource_generation_patch.dart`、`resource_generation_task_repository.dart`、`section_control_service.dart`、`section_control_event_bus.dart`、`section_regeneration.dart`、`section_control.dart`、`streaming_generation_session_repository.dart`、`streaming_resource_generation_service.dart`、`streaming_generation_runtime_contracts.dart`、`resource_tree_repository_impl.dart`、`resource_contracts.dart`、`section_control_repository_impl.dart`、`streaming_generation_session_repository_impl.dart`、`lib/features/resource_studio/**/section_control*`、`lib/features/resource_studio/**/streaming*`。

改动面完全落在 Phase 8 自有文件 + `STATUS.md` + 测试，与 remediation 声明一致。

---

## Data Safety Verification

| 断言 | 结果 | 证据 |
| --- | --- | --- |
| 压缩链路不写 `resource_parts.content` | **成立** | `compression_coordinator.dart` / `compression_job_repository.dart` 的全部写操作只有 `insert`/`update`（`compression_job_repository.dart:142,176,226,237,254`），表常量仅 `resource_compression_jobs` / `resource_compression_candidates`（`:78-79`）；对 `resource_parts` 仅出现在注释。`resource_capacity_repository.dart` 的写只有 `:320` 写 `resources` 容量缓存列（计数投影）。 |
| 候选 `applied_at` 恒为 NULL | **成立** | `compression_job_repository.dart:268` 显式写 `null`；`findCandidatesForResource` 甚至不 SELECT 该列（`:295-308`）。 |
| 无 apply/publish/promote/replace head/revision publish | **成立** | 压缩二文件中 `grep -in "apply|publish|promote|revision"` 仅命中注释（`compression_coordinator.dart:71,75`）。 |
| 测试层独立验证正文不变 | **成立** | `readPartBodiesForTest`（`test/helpers/resource_tree_fixtures.dart:52-57`）在 4 个用例中断言正文逐字符不变。 |
| 两次并发执行不产生重复候选 | **成立（间接）** | `idx_compression_candidates_job` UNIQUE（`database_service.dart:533-535`）+ `ConflictAlgorithm.replace`（`:271`）；探针观察到 `candidates=1`。 |

**未发现任何把压缩结果发布到正文的路径。** 该项不构成 FAILED 原因。

---

## Migration Verification

- `DatabaseService.schemaVersion == 39`（`database_service.dart:43`），v38→v39 迁移 `:2035-2039`；`createV39Schema`（`:449-453`）= `createV38Schema` + `addResourceCapacityColumns`（`safeAddColumn`，`:462-476`）+ `createResourceCompressionSchema`（`CREATE TABLE IF NOT EXISTS`，`:486-539`）。
- 测试 `test/application/resources/database_migration_v39_test.dart`：fresh install 断言 `user_version == 39` 与表/列/索引集合（`:41-126`）；v38→v39 断言版本推进、旧资源与新默认值保留（`:136-206`）；重复执行 upgrade 步骤幂等（`:216-228`）。**全部通过**（见 Test Results）。
- `idx_compression_jobs_active_target` 与 `running → queued` 恢复的交互：**静态验证为安全**。唯一索引对 `(resource_id, target_node_id) WHERE status IN ('queued','running')`，而 `_enqueue`（`compression_coordinator.dart:499-503`）在插入前用 `findActiveForTarget` 阻止同一 target 出现第二个 active 行，故回收写入 `queued` 时不可能与该 target 既有的 `queued` 行冲突。**与该索引真正冲突的是重试路径**（见 BUG-R2-002）。
- 测试覆盖缺口（Info）：`database_migration_v39_test.dart:91-98` 只断言索引**名称**，未钉住 `idx_compression_jobs_active_target` 的 `WHERE status IN ('queued','running')` 谓词；谓词被改成无部分条件时测试不会失败。

---

## Test Results

```text
dart format --output=none --set-exit-if-changed .
Formatted 427 files (0 changed) in 2.01 seconds.        ← 通过（退出码 0）

flutter analyze
No issues found! (ran in 4.7s)                          ← 通过

Phase 8 targeted tests
flutter test test/application/resources/compression_pipeline_test.dart \
  test/application/resources/resource_capacity_runtime_test.dart \
  test/application/resources/resource_capacity_service_test.dart \
  test/application/resources/resource_context_compressor_test.dart \
  test/application/resources/database_migration_v39_test.dart \
  test/domain/resources/resource_compression_test.dart \
  test/domain/resources/resource_capacity_test.dart \
  test/widget/resource_capacity_test.dart
00:05 +142: All tests passed!                           ← 通过（142）

flutter test (full suite)
01:31 +1166: All tests passed!                          ← 通过（1166，0 failed）

git diff --check 752b440..03947be                        ← 无空白/冲突标记（退出码 0）
```

- 全量 1166 与 remediation 报告声明一致；remediation 新增 21 个测试（`resource_capacity_runtime_test.dart` +8、`compression_pipeline_test.dart` +4、`resource_compression_test.dart` +2、`test/widget/resource_capacity_test.dart` +7），与 diff 中 `resource_capacity_fakes.dart` 的 fake 行为修正（`res_fake` → 回显请求 id，`test/widget/resource_capacity_test.dart` 断言随之从 `['res_fake']` 改为 `['res_1']`）相符，非降低断言强度。
- 测试全绿但**未覆盖**本轮两个 High 缺陷（无"活跃 drain 期间回收"、无"重试 vs 已存在 queued job"、无并发 drain claim 用例），故不构成充分条件。

---

## Phase 9 Unlock Decision

**Phase 8 FAILED.**
**Phase 9 remains BLOCKED.**

---

## Final Conclusion

Remediation 的方向正确，四项修复中 BUG-002、BUG-004 可判 CLOSED，孤儿回收与重试入口是真实可用代码，测试为真实 SQLite + 真实 coordinator 路径而非 mock。但：

1. **BUG-001 只部分关闭**：恢复能力存在且有界，但被接到"每次 Studio 容量加载"，并由一个不读闩锁的公开方法全局回收 `running`，动态复现了活跃任务被释放与并发重复执行（BUG-R2-001）。这直接违反 Phase 8 自身的"同一目标同时只有一个未结束任务"不变量。
2. **BUG-003 只部分关闭**：阈值触发已接线，但触发点是"打开 Studio"，且**没有后台消费者**，Phase 8 要求的"离开编辑器后的后台 compression job"未交付，自动排队的 job 不点按钮永不执行。
3. **新增两个 High 缺陷**：重试路径绕过 active-target 守卫，把原生 `SqfliteFfiException` 抛给用户并中断其余重试（BUG-R2-002）；并发 drain 无 claim/CAS（A7 动态复现，严重度上调 MAJOR）。
4. A5 因自动排队接线而升级为 MAJOR（跨资源调度与误导性成功反馈）。

不得为推进 Phase 9 降低标准。建议下一轮 remediation 聚焦：恢复的归属/一次性语义（含闩锁真正生效）、`retryJob` 的 active-target 守卫与领域异常映射、并发 claim/CAS，以及"后台消费者"的显式交付或对 Phase 8 文档与 STATUS 的正式澄清（若该交付被显式移出 Phase 8 范围，需有授权记录，而不是由实现自行降格）。

---

**Audit scope note.** 本轮为只读验收。除本报告 `docs/adaptive-resource-system/phase-08-final-independent-acceptance.md` 外，未修改任何生产代码、测试、配置、`STATUS.md` 或 Phase 文档；未创建任何 commit；HEAD 仍为 `03947be`。为验证 BUG-R1-001/A7/BUG-R2-002 曾临时新增 `test/tmp_r2_recovery_race_probe_test.dart`（探针，不提交），运行后已删除并确认工作区恢复为基线状态（`git status --short` 仅剩验收前就存在的 `.codebuddy/` 与第一轮审计报告两个未跟踪项）。两个 High 缺陷均有动态运行证据；A5/A9/A10/A11/A12 与 INFO 项为静态证据。
