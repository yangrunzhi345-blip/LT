# P0：Resource Part 连续生成进程级冻结 — 诊断与修复方案

状态：诊断基础设施已落地（本 commit）；根因归层需在真实设备上跑一次生产路径后，用本方案定义的 marker/heartbeat 数据回答。

## 基线

- Start HEAD：`6a1a690`（test(resources): cover studio responsiveness and reference bounds）
- 实机证据：同一资源 15~17 Part，40%→47%、47%→59%、59%→82% 三次整应用冻结；彻底结束进程后可继续，最终 100% 成功，数据无损坏。→ 指向进程生命周期状态问题，而非持久化数据或确定性 per-Part 逻辑。

## 已排除/已收敛的层

- 协议面（NDJSON decode / sequence+cursor 校验 / accumulator）：全量、严格、fail-closed，逐 patch 有界，保持不变。
- Revision：DB 历史，跨进程重启仍存在，而重启后可继续 → 无证据不得认定为根因。commit/revision 各步骤已注入耗时统计（`revision.*`），见下。
- 前两轮 UI 修复（180ms throttle、ValueNotifier、SliverList lazy reader 等）保持有效。

## 本轮落地的机制

### 1. Lifecycle tracing（debug/profile only，release 全部 no-op）

`lib/core/debug/generation_diagnostics.dart`：`GenerationDiagnostics.instance`。

生产路径 marker（每个 Part 记录单调时间，`debugPrint` 实时输出）：

```
REFERENCE_INDEX_BUILT
PART[x] READY -> DISPATCH
PART[x] ATTEMPT_STARTED
PART[x] HTTP_REQUEST_START
PART[x] FIRST_SSE_EVENT
PART[x] FIRST_NDJSON_PATCH
PART[x] LAST_NDJSON_PATCH          (stream 结束时补记，含 accumulatedLength)
PART[x] STREAM_RETURNED
PART[x] CALLBACK_DRAIN_BEGIN / END
SESSION[s] PART_STARTED
PART[x] VALIDATION_BEGIN / END
PART[x] BEFORE_COMMIT
PART[x] DB_PART_WRITE_BEGIN / END  (含 elapsed)
SESSION[s] PART_COMPLETED_EVENT
PART[x] COMMIT_END
SCHEDULER_NEXT_ITERATION
TRANSITION ...
SESSION[s] GENERATION_COMPLETED_EVENT / RUN_SETTLED
```

实机冻结后，控制台最后一个 marker 即回答"冻结发生在哪个边界"。

### 2. 双 Heartbeat

- UI heartbeat：Studio 页面 `initState` 启动 250ms Timer tick。
- runtime heartbeat：coordinator/service/LLM SSE 每个主要 await 边界 `runtimeHeartbeat(stage)`。

判定（watchdog 自动 dump，`UI_HEARTBEAT_GAP` 在 isolate 恢复后的第一个 UI tick 检出；`RUNTIME_HEARTBEAT_STALLED` 由 5s watchdog 检出）：

- CASE 1（都停）：main isolate 饥饿 / 同步死循环。
- CASE 2（UI 活、runtime 停）：generation Future / DB / network / scheduler stall。
- CASE 3（runtime 活、UI 停）：Flutter layout/render/event queue 饥饿。
- CASE 4（都活但无响应）：pointer/modal 拦截 bug。

### 3. Part transition watchdog（不自动修改数据）

Part committed 后若 `stallWatchdogThreshold`（生产 10s，测试可注入）内无任何 lifecycle transition，dump：sessionId、lastTransition、全部任务状态、inFlight taskIds、retryCounts、sourceConflicted、scheduler 快照（active/waiters/effectiveLimit/rateLimitedUntil）、Studio buffer/dirty/notifier 状态、presentation queue depth、SSE pending。禁止进入"committed + generating + 无 HTTP + 无 dispatch + 无限等待"的不可观测状态。

### 4. 协议面 / 表现面解耦

- 协议面：每个 NDJSON patch → decode → sequence/cursor 校验 → accumulator（不变，全量）。
- 表现面：coordinator 以 150ms 节流（`previewThrottleInterval`）发布**全量快照**；`PartPreviewUpdated(partId, accumulatedContent, accumulatedLength)` 由 runtime 发给 UI；stream 结束后强制 final flush，再进入 validation/commit。UI preview 不是 authority。
- presentation 回调队列改为**有界（4）+ 合并**：超界丢弃最旧的 snapshot（快照在执行时读取 accumulator，内容无损）。指标：`presentation.enqueued/drained/dropped/maxQueueDepth/queueDepth`。
- `retryPart` 路径保留逐 patch `PatchReceived`（`StreamingSectionRegenerationExecutor` 的绑定校验契约依赖它），但同样走有界队列。
- LLMService eventGate 注入 `sse.received / sse.processed / sse.maxPending` 计数，验证 provider burst 时是否出现 "SSE producer >>> Dart consumer" 积压。出现持续增长积压时再改为带 backpressure 的单一路径（本轮先取证）。

### 5. GenerationRequestScheduler debug seam

`activeRequests / effectiveLimit / waiterCount / globalWaiterCount / debugSnapshot()`。每个 Part 完成后 `active` 与 `waiters` 必须回落；单调增长即 permit/waiter 泄漏。

### 6. Revision 耗时注入

`revision.readLiveState / readHead / readState / diff / insert / captureTotal`、`commit.dbPartWrite`、`reference.indexBuild / excerptSelect`、`prompt.*`。实机跑 history=1..50 曲线（SOAK 6 已给出本地 SQLite 基线：history 50 时单次 commit ≈ 20-35ms，远离冻结量级）。

## 集成 Soak 测试（test/integration/resource_generation_soak_test.dart）

真实 SQLite/pipeline/coordinator/service/controller + fake streaming gateway（1-3 字碎块 / 20-100 字正常 / burst / 跨 chunk 断行，每 Part 轮换），同进程 0→100%，严禁 restart：

- SOAK 1：7 Section × 17 Part × 500 patch
- SOAK 2：10 Section × 50 Part × 200 patch
- SOAK 3：同一进程连续三个 17 Part 资源
- SOAK 4：stall watchdog 停滞 dump 且不改数据，释放后正常完成
- SOAK 5：真实 LLMService SSE gate，500 行 burst + 1-3 字节碎块
- SOAK 6：revision history 0→50 commit 耗时曲线 + head 复放等价校验

每个测试断言：全部 Part committed 且内容与流逐字节一致；完成后 `activeRuns/activeTaskHandles/pendingStops` 归零、Studio `buffers/dirtyParts/flushTimer` 归零、presentation 队列 `drained+dropped == enqueued` 且 maxDepth ≤ 4、preview notifier 收敛到 committed 内容。

## 实机记录 2026-09-21 第三次（残留错误 Banner，已修复）

真实角色生成（7 Section / 26 Part，关联原世界观）跑了完整 0 → 100%：`part_17` attempt 1 因畸形 NDJSON 失败，attempt 2 成功，最终 `GENERATION_COMPLETED_EVENT` → `RUN_SETTLED`。P0 无限自旋修复在实机确认生效（`attempt: 2, budget: 3`，无自旋、无 attempt 爆炸）。

残留问题：重试成功后顶部仍显示旧错误。根因在 `ResourceStudioController._handleEvent`：

- `PartStarted` 只重置 buffer，不清 `errorMessage`；
- `PartCompleted` 不清 `errorMessage`；
- `GenerationCompleted` 只设 `status = completed`，`copyWith` 未传 `errorMessage` → 旧值被保留。

修复：

- 新增 `_errorPartId`：错误 Banner 记录归属的 Part，新 attempt 开始或该 Part 提交成功时精确清除它（不会误清另一个 Part 的失败）。
- 新增 `_currentAttemptByPart` / `_completedPartIds`：`ValidationFailed` 若来自已被取代的 attempt 或已提交的 Part，直接丢弃（`_isStaleFailure`），杜绝迟到事件污染。
- `GenerationCompleted` 强制 `status = completed` 且 `errorMessage = ''`（终态成功拥有 Banner）。
- 失败历史仍保留在 attempt 行（`recordFailedAttempt`），只是不再占用当前 Banner。

回归测试：`test/widget/resource_studio_test.dart` 新增 `Resource Studio residual error state` 组 5 项，**在移除修复后 5/5 失败，修复后 5/5 通过**。

`RUN_SETTLED → Lost connection to device`：日志中最后一个应用侧事件是正常的 `RUN_SETTLED`，其前后没有任何 Dart/Flutter/native 异常输出（无 "Unhandled exception"、无 stack trace、无信号信息）。仅凭该日志无法区分「用户主动关闭窗口（GTK 窗口关闭在 flutter run 下正是这条提示）」与「native 层静默退出」；未复现，因此只记录、不做任何猜测性修改。

## 实机记录 2026-09-21 第二次（崩溃，根因已定位并修复）

真实角色生成（5000 字，关联原世界观）在 Part 7 崩溃，`Lost connection to device`。日志给出了完整确定性链条：

```
PART[part_7] FIRST_NDJSON_PATCH {seq: 0}
PART[part_7] ATTEMPT_FAILED {error: GenerationPatchParseException:
   模型 Patch #2 校验失败；Patch JSON 解析失败: FormatException:
   Unexpected character (at character 565) ...倾斜。")"}
TRANSITION PART[part_7] FUTURE_SETTLED
SCHEDULER_NEXT_ITERATION
PART[part_4] READY -> DISPATCH {attempt: 1}
PART[part_4] ATTEMPT_STARTED
TRANSITION PART[part_4] FUTURE_SETTLED      ← 0.5ms，无 HTTP_REQUEST_START
SCHEDULER_NEXT_ITERATION
PART[part_4] READY -> DISPATCH {attempt: 2}
... 165ms 内 attempt 冲到 10，随后进程死亡
```

根因链（每一环都有代码与日志对应）：

1. 模型在 JSON 字符串结束后多输出一个 `"` → 该行非法 → `GenerationPatchParseException`（协议层行为正确，保持 fail-closed）。
2. 失败回调把 session 置为 `validating`，并 `recordFailedAttempt` 把 part_4/part_6 置为 `failed`。
3. 调度器 `markTaskReady` → 重新 dispatch → `onPartStarted` 回调要把 session 从 `validating` 转 `generatingPart`，而状态机**禁止**该转换 → 回调抛异常。
4. `onPartStarted` 当时位于 `_generateSinglePart` 的保护 `try` **之外**，异常直接逃逸：attempt 停在 `started`、task 停在 `generating`、`recordFailedAttempt` 从未执行、本地 Future 已结束。
5. 调度器见 `inFlight` 为空 → `recoverInterruptedTasks` 把 `generating` 重置为 `ready` → `continue` → 再次 dispatch。
6. `retryCounts` 只在 catchError 路径自增，这条路径从不到达 → 重试门形同虚设 → **无限自旋**。每轮都建 SQLite transaction、重臂 watchdog，事件循环被饿死，应用失去响应直到进程被杀。

修复（本轮）：

- 状态机允许 `validating -> generatingPart`（唯一的 backward edge，注释说明仅用于失败 Part 的自动 retry；成功路径仍 `validating -> committing -> generatingPart/completed`）。
- `_generateSinglePart` 的保护块提前到 `startAttempt` 之前，`onPartStarted` 纳入其中；新增 `_convergeFailedAttempt` 统一处理"attempt 已获得后的任何失败"，保证不留 `started` attempt + `generating` task。
- `recordFailedAttempt` 收紧：attempt 仅 `started -> failed`；task 仅当前 attempt 匹配且状态为 `generating`/`validating` 时转 failed（`completed`/`cancelled` 绝不降级）。
- retry budget 成为硬约束：dispatch 前判定，dispatch 即消耗，`1 + maxRetriesPerPart` 次为上限；新增 `markRetryExhausted` 把耗尽预算的 `ready` 行显式收敛为终态 failed；新增 `PART[..] RETRY_BUDGET_EXHAUSTED` marker。
- 事件循环 fairness：仅在可能立即重调度的快速路径（recovery 后、failed→ready retry 转换后）`await Future.delayed(Duration.zero)`，明确是调度公平性而非 race workaround。
- 失败策略：失败 Part 达上限后保持 failed，无依赖关系的 ready Part 继续生成，依赖它的节点保持 blocked；全部可推进节点完成后 session = failed（绝不 completed）。

回归测试：`test/application/resources/p0_malformed_ndjson_spin_test.dart`（11 项）+ soak `SOAK 7`。

## 实机记录 2026-09-21（角色卡，23 Part，未复现冻结）

同一进程内 23 个 Part 全部顺序提交成功（`GENERATION_COMPLETED_EVENT` → `RUN_SETTLED`），零重试、零失败：

- `DB_PART_WRITE_END` 9-28ms，随 revision 历史增长**无上升趋势**；`CALLBACK_DRAIN` <1ms；validation 1.5-6ms
- 单 Part 网络占绝大多数时间（HTTP→FIRST_SSE 0.8-1.3s，流式 1-2.5s），整轮 23 Part ≈ 66s
- 本轮该 provider 每 Part 只推 2-8 个 patch（大 delta），因此逐 patch 事件量本身不是本轮的压力源

同时捕获到一次 **CASE 1**（生成之前的创建/规划窗口）：

```
reason: UI_HEARTBEAT_GAP age=3404.5ms
uptime: 91840.1ms        activeRuns: {}
uiHeartbeat: ticks=21, interval=250ms, age=3408.1ms
runtimeHeartbeat: seq=2250, lastStage=llm.sseLine, age=3353.0ms
sse.received: 2250   sse.processed: 2249   sse.maxPending: 45
scheduler: {deepseek: {active: 1, waiters: 0}}
last markers: (empty)
```

读法：UI 与 runtime heartbeat **同时**停摆 ≥3.4s → main isolate 被同步代码/事件循环饱和阻塞；`activeRuns` 为空、`scheduler.active=1`、最后阶段为 `llm.sseLine` → 阻塞发生在**规划 LLM 流期间**，且当时仍有一个模型请求持有 permit；`last markers` 为空说明该阶段当时**没有任何埋点**（本轮已补）。

处置：

1. **补齐创建/规划阶段埋点**：`CREATE[..] BEGIN / REFERENCE_RESOLVED / PIPELINE_CREATED / PLAN_READY / CONFIRM_BEGIN / CONFIRM_END / GENERATION_SESSION_READY`，`PLAN[..] BEGIN / PROMPT_BUILT / LLM_REQUEST_START / LLM_RETURNED / VALIDATED / SAVED / TIMEOUT`，并记录 `creation.resolveReference`、`creation.pipelineCreate`、`creation.confirmBlueprint`、`plan.parse`、`plan.normalizeValidate`、`plan.saveBlueprint`、`plan.total` 耗时。`REFERENCE_RESOLVED.resolvedReferenceLength` 即 A/B/C 世界观控制组的判定依据。
2. **修复规划超时后请求不被取消的真实缺陷**：`BlueprintPlanner._invokeWithTimeout` 过去超时只 `completeError`，而规划链路从不传 `taskHandle`，导致超时后 SSE 流继续消费 isolate、继续持有 `GenerationRequestScheduler` permit，最长拖到 transport overall（10 分钟）。现在 planner 自己铸造 `GenerationTaskHandle`，超时即 `cancel()` 中止请求（调用方自带 handle 时保持尊重调用方），并有回归测试锁定。

## 真实设备复现时的操作

1. `flutter run -d linux --profile`（或 debug）复现冻结。
2. 记录控制台最后一个 `PART[...]` marker 与 `SCHEDULER_NEXT_ITERATION`。
3. 按 heartbeat 判定 CASE 1-4。
4. 收集 watchdog dump（`GENERATION DIAGNOSTICS DUMP`），关注 `sse.maxPending`、`presentation.maxQueueDepth`、`commit.dbPartWrite`、`revision.*`、scheduler waiters 是否异常。
5. A/B/C 世界观控制组：同一 5000 字角色分别在无 worldview / 30000 字 / 50000 字 worldview 下生成，对比 `REFERENCE_INDEX_BUILT` 的 `resolvedReferenceLength` 与 `reference.*` 耗时；三者都冻结 → 排除 worldview 路径。

## 禁止事项（不变）

不删连续阅读/世界观关联、不降字数、不减 Part、不用 `Future.delayed` 治竞态、不吞异常、不自动改任务状态、不关闭 Revision、不把 timeout 当 freeze 修复。
