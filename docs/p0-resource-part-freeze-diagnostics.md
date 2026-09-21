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

## 真实设备复现时的操作

1. `flutter run -d linux --profile`（或 debug）复现冻结。
2. 记录控制台最后一个 `PART[...]` marker 与 `SCHEDULER_NEXT_ITERATION`。
3. 按 heartbeat 判定 CASE 1-4。
4. 收集 watchdog dump（`GENERATION DIAGNOSTICS DUMP`），关注 `sse.maxPending`、`presentation.maxQueueDepth`、`commit.dbPartWrite`、`revision.*`、scheduler waiters 是否异常。
5. A/B/C 世界观控制组：同一 5000 字角色分别在无 worldview / 30000 字 / 50000 字 worldview 下生成，对比 `REFERENCE_INDEX_BUILT` 的 `resolvedReferenceLength` 与 `reference.*` 耗时；三者都冻结 → 排除 worldview 路径。

## 禁止事项（不变）

不删连续阅读/世界观关联、不降字数、不减 Part、不用 `Future.delayed` 治竞态、不吞异常、不自动改任务状态、不关闭 Revision、不把 timeout 当 freeze 修复。
