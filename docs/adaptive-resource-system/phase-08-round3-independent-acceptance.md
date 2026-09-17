# Phase 8 Third Independent Acceptance — Round 3

**Auditor:** independent acceptance agent (read-only, code-audit skill)
**Date:** 2026-09-17
**Scope:** `git diff 03947be..e82dacb` — the Round 2 remediation
(`8c62105` fix, `8ce43a6`/`e82dacb` docs), against
[phase-08-round2-remediation-report.md](phase-08-round2-remediation-report.md) and the
Round 2 findings in [phase-08-final-independent-acceptance.md](phase-08-final-independent-acceptance.md).

---

## Verdict

**PASSED**（无 BLOCKER、无 MAJOR）

Round 2 的全部阻塞项都以可复现的动态证据关闭；本轮未发现任何新的正确性缺陷。
新增 3 条 MINOR 与 5 条 INFO，均为测试覆盖 / 误诊断 / 有界性 / 死代码级别，不影响 Phase 8 的正确性与数据安全，登记后不阻塞。

---

## Git Baseline

| 项 | 值 |
| --- | --- |
| Start HEAD | `03947be` |
| Remediation commit | `8c62105` |
| Docs commits | `8ce43a6`、`e82dacb` |
| **Actual HEAD** | **`e82dacb`**（`git rev-parse HEAD` 实测一致） |
| Branch | `main` |
| Working tree | 仅 `?? .codebuddy/`（既有本地工具目录）。无未提交改动。 |

`git diff --stat 03947be..e82dacb`：25 files, +3106 / −333；其中生产代码 11 个文件、测试 10 个文件、文档 4 个。

## Commands executed (real output)

```text
dart format --output=none --set-exit-if-changed .   → Formatted 431 files (0 changed), exit 0
flutter analyze                                     → No issues found! (ran in 2.0s)
Phase 8 targeted (13 files)                         → +167: All tests passed!
flutter test (full suite)                           → +1186: All tests passed!
git diff --check 03947be..e82dacb                   → exit 0
git diff --name-only 03947be..e82dacb -- <Phase 5/6/7 frozen files>  → empty
```

另在 `/tmp/lt_audit/LT`（仓库副本，审计树从未被写入）执行了 4 组**变异实验**与 1 个**探针**，见
"Mutation Evidence"。

## Core Invariants Verified

| 维度 | 不变量 | 结论 | 证据 |
| --- | --- | --- | --- |
| 数据安全 | 压缩链路不得写 `resource_parts.content` | HOLD | 三个压缩文件内唯一写入目标是 `resource_compression_jobs` / `resource_compression_candidates`；`resource_parts` 仅出现在注释 |
| Phase 边界 | 候选 `applied_at` 恒 NULL，无 apply/publish/revision | HOLD | `compression_job_repository.dart:398` 写 `null`；全仓库无 publish/apply 代码 |
| 并发 | 同一 job 同一时刻至多一个执行者（claim CAS） | HOLD | 变异 A 被 TEST-1 捕获（模型调用 4 次） |
| 并发 | 失去租约的 worker 不得覆盖新 owner 的终态 | HOLD | 探针（pristine）：旧 worker 完成后行仍 `running/worker=wkr_B`、无候选 |
| 恢复 | 活跃租约不得被回收 | HOLD | 变异 C2 被 TEST-2 与 runtime live-lease 测试同时捕获 |
| 恢复 | 孤儿 / 过期租约 / 无租约旧数据必然可恢复且有界 | HOLD | TEST-3；`database_migration_v40_test.dart` legacy running → queued；`attempts >= max → failed` |
| 队列 | 生产 drain 只消费指定资源 | HOLD | TEST-6；`rg "\.drain\(" lib/` 的两个生产调用方都传 resourceId |
| 状态机 | `failed → queued` 只能经显式 retry，且不得违反 active-target 唯一约束 | HOLD | `NOT EXISTS` 守卫 + 约束异常转业务跳过（TEST-4/5） |
| 迁移 | schema 版本单点、幂等、非破坏 | HOLD | v40 测试（fresh / v39→v40 / 重复执行） |
| 派生任务 | 压缩失败不得影响编辑、保存、退出 | HOLD | worker 每个入口自捕获；`notifyEditorLeft` 为 fire-and-forget + 控制器兜底 |

## Remediation Closure Matrix

| Finding | Result | Evidence |
| --- | --- | --- |
| BUG-001 / BUG-R2-001（HIGH）恢复抢占活跃任务 | **CLOSED** | `recoverStaleRunningJobs` 单条语句带租约谓词（`compression_job_repository.dart:303-330`）；`drain` 起始与 `CompressionBackgroundWorker.start()` 调用（`compression_coordinator.dart:235`、`compression_worker.dart:55`），`load()` 已无副作用（`resource_capacity_controller.dart:31-50`），`_recoveredThisInstance` 与 `recoverInterruptedJobs` 全仓库已不存在。变异 C2（恢复退化为"回收所有 running"）被 TEST-2 与 `resource_capacity_runtime_test.dart` "start never touches a job whose lease is still live" 同时捕获。 |
| A7（MAJOR）无原子 claim / 无 CAS | **CLOSED** | `claimJob` 单条 `WHERE job_id=? AND status='queued'`（`:211-236`）；`completeJob` 单条 `WHERE job_id=? AND status='running' AND worker_id=?`（`:240-268`）；候选只在 CAS 成功后写入（`compression_coordinator.dart:415-430`）。变异 A（去掉 claim 守卫）→ TEST-1 失败 `Expected: <1> Actual: <4>`，证明修复是载荷性的且测试有效。 |
| A5（MAJOR）drain 全局队列 | **CLOSED** | `findJobsByStatus(..., resourceId)` 在 SQL 过滤（`:271-290`）；生产调用方 `resource_capacity_runtime.dart:96` 与 `compression_worker.dart:96` 均带 resourceId。TEST-6：A 的两个任务完成、B 保持 queued、B 未触发模型（calls==2 而非 4）。 |
| BUG-R2-002（HIGH）retry 撞 active-target 唯一索引 | **CLOSED** | `retryFailedJob` 单条语句 + `NOT EXISTS` 守卫（`:339-374`），残留约束错误转业务 `false`；`retryFailedJobs` 返回 `CompressionRetryOutcome` 且逐 job 隔离（`compression_coordinator.dart:295-320`）。TEST-4/TEST-5 实测无异常、恰好一条 active 行、批次继续。 |
| BUG-003（原 PARTIALLY CLOSED）自动 compression runtime | **CLOSED** | 触发点在"离开编辑器"（`resource_capacity_controller.dart:56-69` dispose + `resource_studio_page.dart:76-84` 资源切换），App 启动恢复钩子（`main.dart:150-153`）；后台消费者 `CompressionBackgroundWorker.scheduleProcessing` → 资源作用域 drain（`compression_worker.dart:88-103`）。`resource_capacity_runtime_test.dart`：超限资源自动产出候选且正文不变；阻塞式 LLM 证明触发不等待模型；未超限不 enqueue 不调模型；重复生命周期仅 1 个候选；后台模型失败不影响调用方。 |

## Mutation Evidence（测试保护力，动态）

在 `/tmp/lt_audit/LT`（副本）中，把修复点逐一回退为"修复前形状"，再跑现有测试：

| 变异 | 内容 | 现有测试是否捕获 |
| --- | --- | --- |
| A | `claimJob` 去掉 `AND status='queued'`（恢复"先读后直写"） | **捕获**：TEST-1 `Expected: <1> Actual: <4>`（4 个 worker 同时执行同一 job） |
| C2 | `recoverStaleRunningJobs` 去掉租约谓词（恢复"回收所有 running"） | **捕获**：TEST-2 与 runtime live-lease 测试均 `Expected: <0> Actual: <1>` |
| B2 | `retryFailedJob` 去掉 `NOT EXISTS` 守卫（保留约束异常回退） | **未捕获**（7 个并发测试全绿）→ 见 R3-I1 |
| D | `completeJob` 去掉 `AND worker_id=?`（保留 status 守卫） | **未捕获**（7 个并发测试全绿）→ 见 R3-M2 |

探针（副本内新增，`/tmp/lt_audit/LT/test/application/resources/zzz_probe_owner_test.dart`，**不在被审计仓库中**）：
worker A 在模型调用中持有租约 → 强制租约过期 → worker B 恢复并 claim → A 迟到完成。

```text
pristine    : after B claimed: status=running worker=wkr_B
              after stale A finished: status=running worker=wkr_B candidates=0
              final: status=succeeded worker= (cleared) candidates=1 content='乙'×400
mutation D  : after stale A finished: status=succeeded worker=  candidates=1
              final: status=succeeded candidates=1 content='甲'×400   ← 旧 worker 覆盖新 owner 并发布陈旧候选
```

结论：`worker_id` 归属守卫在生产代码中确实生效（pristine 行未被覆盖、A 的候选未写入），但**没有任何测试保护它**。

---

## Findings

### R3-M1

等级：MINOR

标题：约束异常回退的判定过宽，会把任意约束失败伪装成"目标已有进行中的压缩"

问题：`_isUniqueViolation` 同时接受 `'UNIQUE constraint failed'` 与 `'constraint failed'`，后者是 SQLite 对
FOREIGN KEY / NOT NULL / CHECK 失败共有的子串。经变异 B2 验证，在"目标已有 active job"这一路径上，实际
产生业务结果（`skippedActiveTarget`）的正是这条 catch 回退，因此它的判定范围直接决定该路径的语义。

位置：
- 文件：`lib/application/resources/compression_job_repository.dart`
- 方法：`retryFailedJob`（`:339-374`）与静态判定 `_isUniqueViolation`（`:375-379`）
- 代码路径：`ResourceCapacityController.retryFailedCompression` → `Coordinator.retryFailedJobs` → `retryFailedJob` → `on DatabaseException`

触发条件：retry 时该行触发任何非 UNIQUE 的约束失败（例如未来给 `resource_compression_jobs` 增加 FK/NOT NULL
约束后出现写入错误）。

实际影响：真实约束缺陷被报告为"目标已有进行中的压缩，已跳过"，用户看到错误的诊断，维护者失去错误信号
（异常被吞掉且不记录）。无数据损坏。

根因分析：为"绝不向 UI 暴露 Sqflite 异常"这一要求选择的兜底判定使用过宽的子串匹配，未限定为唯一约束。

修复方案：把判定收窄为 `'UNIQUE constraint failed'`（必要时再加错误码 2067/1555），其余 `DatabaseException`
继续 `rethrow`；或在捕获后先查询目标是否真的有 active job，只有确实存在时才返回业务跳过。

验证方式：单测直接断言 `_isUniqueViolation` 对 `'NOT NULL constraint failed: x'` 返回 false（当前实现会返回
true）；或注入一个会抛非唯一约束错误的 job 行，断言异常被重新抛出而不是被计为 skipped。

**Affected Files** `compression_job_repository.dart`

---

### R3-M2

等级：MINOR

标题：`completeJob` 的 worker 归属守卫没有被任何测试保护，其失效可静默变为"旧 worker 覆盖新 owner 并发布陈旧候选"

问题：并发测试组 `claim and ownership`（`test/application/resources/compression_concurrency_test.dart:297-340`）
声称覆盖"失去租约的 worker 无法提交终态"，但该场景中恢复动作已经把 `status` 改回 `queued`，因此**仅靠 status
守卫（`AND status='running'`）就会让写入失败**；`AND worker_id=?` 这一维度没有被任何用例触达。变异 D（只去掉
`worker_id` 条件）下全部 7 个并发测试通过；副本探针则显示：当行已被 worker B 重新 claim 为 `running` 时，
旧 worker A 会写入 `succeeded`、清空 owner，并发布自己（陈旧）的候选，B 的结果被丢弃。

位置：
- 文件：`lib/application/resources/compression_job_repository.dart`
- 方法：`completeJob`（`:240-268`，守卫在 `:260`）
- 代码路径：`CompressionCoordinator._finish`（`compression_coordinator.dart:433-446`）→ `completeJob`；候选写入在其后 `:415-430`
- 测试：`test/application/resources/compression_concurrency_test.dart:297-340`

触发条件：一次压缩请求超过 `ResourceLimits.compressionLeaseDuration`（`resource_limits.dart:76`，5 分钟，
LLM 路径无请求超时，见 R3-M3）→ 租约被判过期 → 另一个 worker 恢复并 claim → 原 worker 随后完成。

实际影响：生产代码当前正确（探针 pristine 已证明行未被覆盖、候选未写入）；风险是**回归无保护**：守卫一旦
被删/被改，行为会退化为"新 owner 的状态与结果被静默覆盖"，且现有测试全绿。属"未来才会暴露"的严重回归，
当前无实际故障。

根因分析：测试只构造了"恢复后无人再 claim"的交错，缺少"过期租约被第二个 worker 重新 claim 后，原 worker 才
完成"这一关键交错；而后者正是 `worker_id` 守卫存在的唯一理由。

修复方案：新增一条并发测试，交错必须是：A claim（租约有效）→ 强制租约过期 → B recover + **B claim（行变
`running`、owner=B）** → A 迟到完成 → 断言行仍为 `running`、`worker_id=B`、候选数为 0；最后释放 B，断言最终
候选内容来自 B。仓库副本内的探针可直接搬用。

验证方式：上述用例在变异 D 下必须失败（当前版本通过），即用它钉住归属守卫。

**Affected Files** `test/application/resources/compression_concurrency_test.dart`、`compression_job_repository.dart`

---

### R3-M3

等级：MINOR

标题：租约过期即判 stale，而 LLM 请求无超时也没有续租，正常但缓慢的一次压缩会被重复执行

问题：`recoverStaleRunningJobs` 以 `lease_expires_at < now` 为唯一过期判据，没有租约续期机制；同时压缩走的
`LlmGateway.rawCompletion` → `sendMessageStream` 路径在整个仓库中**没有任何请求超时**（只有 web search、
embedding、blueprint 使用 `.timeout`）。因此一个阻塞超过 5 分钟的模型调用（慢供应商或卡住的流）会被下一个
drain 判为 stale：任务回到 `queued`、被另一个 worker 重新执行，原 worker 的结果随后被归属 CAS 拒绝丢弃。

位置：
- 文件：`lib/domain/resources/resource_limits.dart:76`（`compressionLeaseDuration = 5min`）
- 文件：`lib/application/resources/compression_job_repository.dart:303-330`（过期判据）
- 文件：`lib/application/llm/ai_generator_llm_gateway.dart:208-243`（`rawCompletion` 无 timeout）
- 代码路径：`CompressionCoordinator._runClaimedJob` → `_llmPort.compress` → `AiGeneratorLlmGateway.rawCompletion` → `sendMessageStream`

触发条件：单次压缩请求耗时 > 5 分钟（或流卡住），期间发生任意一次 `drain`/`worker.start()`。

实际影响：同一逻辑任务被送模型两次（成本）、旧 worker 的（可能正确的）结果被丢弃、一次执行消耗两次
attempts（预算提前耗尽）。有界：`attempts >= max_attempts` 后恢复转 `failed`，不会无限循环。无数据损坏
（候选不会被 stale worker 写入，正文不受影响）。

根因分析：租约模型假定"请求时长 < 租约时长"，但该前提既没有通过请求超时保证，也没有通过续租维持。

修复方案（任选其一，均属 Phase 8 范围）：(a) 为压缩请求设置明显小于租约的超时（LLM 网关层统一超时）；
(b) 让 `leaseDuration` 明显大于网关可能的最大请求时长并写成显式依赖关系；(c) 在流式回调里续租（需要 LLM 端口
暴露进度回调，改动较大）。若选择保留现状，需要在 `resource_limits.dart` 注释中写明该前提。

验证方式：注入 clock 推进到租约之后触发第二次 drain（等价于我本轮副本探针的强制过期），断言该 job 只被
完成一次；修复后此断言成立。

**Affected Files** `resource_limits.dart`（注释）/ `ai_generator_llm_gateway.dart`（超时）、`compression_job_repository.dart`

---

### R3-I1

等级：INFO

标题：`retryFailedJob` 的 `NOT EXISTS` 守卫同样无测试保护（当前由约束回退兜底）

问题：变异 B2（只去掉 `NOT EXISTS`，保留约束异常回退）下 7 个并发测试全部通过——说明当前语义由**回退层**
产生，守卫层只是避免了一次注定失败的写入。契约（不抛异常、skipped、唯一 active 行）在两层中任一层存在时都
成立，符合"constraint-safe handling"要求，因此不是缺陷；但守卫的正确性无人保护，且与 R3-M1 叠加时，
"约束异常被吞"成为唯一防线。

位置：`lib/application/resources/compression_job_repository.dart:339-374`；
测试 `test/application/resources/compression_concurrency_test.dart` TEST-4/TEST-5。

修复建议：增加一条仓库级测试，直接断言"目标忙时不产生任何约束异常"（例如用一个包装的 `DatabaseFactory`/
`Database` 计数 `SqfliteFfiException`，或断言 `retryFailedJob` 返回 false 且目标行完全未变），从而把守卫本身
钉住。

### R3-I2

等级：INFO

标题：后台 worker 的基础设施错误只留在内存字段，用户与日志都看不到

问题：`CompressionBackgroundWorker.lastError`（`compression_worker.dart:47`）与 `processingCount`（`:44`）在
`lib/` 中没有任何读取方（只有测试读）。若后台 drain 因 DB/IO 错误持续失败，面板会一直显示"待压缩 N"而没有
任何解释，用户也不知道需要手动重试。逐 job 的失败原因仍然可见（写进 job 行）。

位置：`lib/application/resources/compression_worker.dart:47,55-59,82,96-100`。

修复建议：把后台失败的摘要接到面板状态（例如 `ResourceCapacitySummary` 增加一个 worker 级诊断字段），或至少
在 `main.dart` 的启动钩子处记录一次日志；不要只留在内存。

### R3-I3

等级：INFO

标题：一次"离开编辑器"最多处理 4 个任务，大资源会长期停留在"待压缩"

问题：后台 `_process` 调用 `drain(resourceId:)` 使用默认 `maxJobsPerDrain = 4`
（`compression_coordinator.dart:90,237`）。资源任务数超过 4 时，其余 job 保持 `queued`，直到下一次离开编辑器、
手动点击或重试。这是有意的有界行为，但意味着"自动压缩完成"对大资源并不成立。

位置：`lib/application/resources/compression_worker.dart:96`、`compression_coordinator.dart:90,237`。

修复建议：若希望自动路径收敛，可在 worker 内循环 drain 直到队列为空或达到更高的总预算（保持每次 LLM 调用
之间不阻塞 UI），或在文档/STATUS 中明确"每轮最多 4 个"的语义。

### R3-I4

等级：INFO

标题：新增的租约判定 helper 是死代码，且与 SQL 谓词重复定义同一语义

问题：`CompressionJob.isLeaseLive`（`resource_compression.dart:195`）、`isOwnedBy`（`:202`）、
`isReclaimable`（`:207`）在 `lib/` 与 `test/` 中均无调用方；生产判定分别由 `recoverStaleRunningJobs` 的 SQL
谓词与 `completeJob` 的 WHERE 承担。同一语义存在两处定义，未来可能漂移（例如 SQL 改动而 Dart helper 未同步）。

位置：`lib/domain/resources/resource_compression.dart:195-209`。

修复建议：删除未使用 helper，或让仓库/协调器改用它们（并补对应单测），二者取一，避免"看似被使用的语义"。

### R3-I5

等级：INFO

标题：租约时间戳沿用工程既有的"本地时间 ISO 字符串 + 字符串比较"约定

问题：`lease_expires_at` 以 `DateTime.now().toIso8601String()`（本地、无偏移）存储，恢复用
`lease_expires_at < ?`（ISO 字符串字典序）比较。同一进程/同一时区下正确；跨时区或系统时钟回拨时，旧行可能
被判定为"遥远未来"而长时间不被回收。该约定是仓库既有做法（`created_at` 排序、`updated_at` 比较亦然），非本轮
引入，但租约把它用于正确性判定而不仅是排序。

位置：`lib/application/resources/compression_job_repository.dart:303-330`、`compression_coordinator.dart:101`（`_clock`）。

修复建议：如需长期稳健，统一改用 UTC ISO（`toUtc().toIso8601String()`）并在恢复时传入 UTC now；或记录并
比较 epoch 毫秒列。

---

## Registered Findings Reassessment

| Finding | Status | 复核结论 |
| --- | --- | --- |
| A6 取消/无正文计入 `failedJobs` | 仍存在 | `compression_coordinator.dart:366,375,388` 三条 cancelled 路径仍返回 false → drain `failed++`；UI 语义问题，非阻塞 |
| A8 缓存口径 | 仍存在 | `resource_capacity_repository.dart:309` `historicalRevisionCount: 0`；触发器确认使用实时 `measure`，与展示问题分离 |
| A9 archived 语义不一致 | 仍存在 | `compression_coordinator.dart` 内 `archived` 零匹配（仍不过滤），`resource_context_compressor.dart` 仍排除 |
| A10 `recent` 语义 | 仍存在 | 文件未改动，仍无生产调用方 |
| A11 `original_char_count` 含分隔符 | 仍存在 | `compression_coordinator.dart:394` 仍 `join('\n\n')` 后取 length |
| A12 并发 enqueue 暴露 `StateError` | 仍存在 | `compression_job_repository.dart:205` 仍在；重试路径已不再暴露数据库异常 |
| BUG-R2-003 `latestFailureReason` 取最旧 | 仍存在 | `resource_capacity_runtime.dart` `_firstFailureReason` 未改动 |
| BUG-R2-004 预算文档 vs 硬拒绝 | 仍存在 | `resource_compression.dart` / `resource_limits.dart:79-83` 注释未改动 |
| INFO-001 死代码面 | 仍存在 | `enqueueNode`、`findCandidateForJob`、`cacheColumns`、`CompressionRunProgress.fraction` 仍无调用方（另见 R3-I4 新增同类） |
| INFO-002..006 | 仍存在 | 本轮未涉及（retention 自述、prompt 围栏、行清理、per-Part provenance、`_generateLabel`） |

无一项因本轮改动升级为阻塞。

## Test Integrity Review

- 删除的测试行仅为：API 改名（`recoverInterruptedJobs` → `recoverStaleJobs`）、返回类型变化
  （`retryFailedJobs` → `CompressionRetryOutcome`）、schema 版本钉子（39 → 40），以及 3 条断言"load 触发
  恢复 + 阈值触发"的控制器测试——其前提正是第二轮验收判定为缺陷的设计。
- 逐条确认替代覆盖：`load only reads the panel and triggers nothing` / `dispose triggers the automatic path`
  / `notifyEditorLeft survives a throwing runtime`（控制器侧）与 `automatic compression lifecycle`、
  `compression_worker_test.dart`（runtime/worker 侧）；"入队不调用模型"仍由未改动的
  `compression_pipeline_test.dart` "queueing never calls the model" 钉住。
- 无断言被删除而无更强替代。

## Phase Boundary / Data Safety / Migration

- Phase 5/6/7 冻结文件在 `03947be..e82dacb` **零改动**（`git diff --name-only` 为空，含 part_generation_*、
  generation_patch_parser、resource_generation_protocol/patch、section_control*、streaming_*、
  resource_generation_task_repository、两个 repository impl、resource_contracts）。
- 压缩链路写入仅限 `resource_compression_jobs` / `resource_compression_candidates`；`applied_at` 恒 `NULL`；
  `resource_parts.content` 无任何写入点（测试仍在压缩前后逐字符比对）。
- v39 → v40 迁移：`safeAddColumn` 幂等；fresh install（schemaVersion 40 钉子）与 v39→v40（旧行保留、legacy
  `running` 可恢复、重复执行幂等）均有测试；未新增索引（恢复按 `status` 走既有 `idx_compression_jobs_status`），
  `idx_compression_jobs_active_target` 定义未变，恢复的 `running → queued` 不会与该索引冲突（唯一索引保证同一
  target 至多一条 active 行）。

## Unverified Scope

- 未做真实进程崩溃/`SIGKILL` 复现：孤儿恢复用 fixture 行（无租约/过期租约）验证，状态等价但非真实崩溃。
- R3-M3 的"超过 5 分钟请求"用强制过期（SQL 改写租约）模拟，未真实等待；"LLM 路径无超时"为 grep 静态证据，
  未用真实挂起的供应商验证。
- 变异实验与探针均在 `/tmp/lt_audit/LT` 副本内执行，被审计仓库未被写入（`git status --short` 复核通过）。
- 本轮只核对 Phase 5/6/7 的冻结文件边界，未重新审计其内部实现。
- 未评估真实设备/多进程并发（桌面单实例假设未验证）。

---

## Verdict Detail

- 第二轮验收的全部阻塞条件（BUG-001 PARTIALLY CLOSED、BUG-003 PARTIALLY CLOSED、BUG-R2-001 HIGH、
  BUG-R2-002 HIGH、A5 MAJOR、A7 MAJOR）**全部关闭**，且关闭均可动态复现（含 4 组变异实验与 1 个交错探针）。
- 未发现新的 BLOCKER/MAJOR；新登记 3 MINOR + 5 INFO，均为覆盖/诊断/有界性/死代码类，不改变运行时正确性。
- 数据安全、Phase 边界、迁移与冻结模块不变量全部保持。

**Round 3 Verdict: PASSED**（无阻塞项）。
Phase 8 是否可以正式标记 ACCEPTED、Phase 9 是否解锁，属于项目验收流程的决策；本报告只提供独立证据与结论，
不代替该决定，也不执行任何解锁动作。

**Audit scope note.** 本轮为只读验收。唯一写入为本报告
`docs/adaptive-resource-system/phase-08-round3-independent-acceptance.md`；未修改任何生产代码、测试、配置、
STATUS.md 或既有文档；未创建 commit；审计结束时 HEAD 仍为 `e82dacb`，工作区仅剩验收前就存在的 `.codebuddy/`。
变异实验与探针写在 `/tmp/lt_audit/LT` 副本内（该副本随后删除），未进入被审计仓库。
