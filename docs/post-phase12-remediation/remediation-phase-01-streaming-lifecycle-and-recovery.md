# Remediation Phase 01 — Streaming Generation Lifecycle & Recovery

> **Root Cause**: RC-01
> **Findings**: B1 (BLOCKER), M5, M6, N8, TG2, TG4, TG5
> **Depends On**: None
> **Document status**: PLANNED

---

## 1. Purpose

流式资源生成（Asset Studio / Resource Studio 的 AI 生成）把会话生命周期状态
`StreamingLifecycleStatus.completed` 定义成**只允许自环的不可逆终态**，而产品层允许用户对已经生成
完成的章节执行“重新生成”。这两者互相矛盾，导致一个用户可见的确定性失败（B1）。同时，`retryPart`
是唯一没有异常收敛的生成入口（M5），进程中断后的会话没有启动恢复入口、恢复代码是死代码（M6），
`_requestedStops` 会为无活动运行的取消/暂停泄漏（N8）。

本 Phase 修复的核心 contract 是：**“`completed` 表示内容已保存，而不是会话不可再工作”**。修复后
系统必须满足：已完成会话可以合法开启新一轮生成；生成失败一律收敛到可恢复状态；进程死亡不产生
永久卡死；旧 attempt 的迟到结果永不落入新 attempt。

## 2. Audit Findings Covered

```text
Primary:
- B1  （BLOCKER）已完成章节重新生成必然抛非法状态转换
- M5   retryPart 无异常收敛，失败后会话卡在非终态 generatingPart
- M6   中断会话无启动自动恢复；findInterruptedSessions / recoverInterruptedGeneration / recover() 未接线

Related:
- N8   _requestedStops 对无活动运行的 cancel/pause 泄漏

Test gaps:
- TG2  无 completed 会话下章节重新生成用例
- TG4  无 retryPart 抛异常后状态收敛用例
- TG5  无 app 重启级流式会话恢复用例
```

CLEANUP：本 Phase 不删除任何代码。M6 会让 `findInterruptedSessions` / `recover()` 从“死代码”
变为“已接线”，因此它们**不得**计入 R13 cleanup 候选。

## 3. Current Production Architecture

### 3.1 入口与调用链（真实代码）

```text
ResourceStudioPage._regenerateSection                         (resource_studio_page.dart:550)
  → SectionControlController.regenerateSection                (presentation/controllers/section_control_controller.dart)
  → SectionControlService.regenerateSection                   (application/resources/section_control_service.dart:491)
      ├─ _requireRow / token check                            (:495-502)
      ├─ _repository.readSectionTasks                          (:503-509)
      ├─ _revisionService.beginLossyOperation(...)             (:519-527)   ← 先把任务重开 + 记录 revision
      └─ for each task:
           _regenerationExecutor.regenerate(...)               (:556)
             → StreamingSectionRegenerationExecutor.regenerate (features/resource_studio/application/use_cases/
                                                                  streaming_section_regeneration_executor.dart:73)
                → StreamingRegenerationRuntimeAdapter.retryPart (:36)
                   → StreamingResourceGenerationController.retryPart
                      → StreamingResourceGenerationService.retryPart  (streaming_resource_generation_service.dart:516)
                         ├─ _sessionRepository.findSession              (:521)
                         ├─ _sessionRepository.updateStatus(generatingPart)  (:526-530)
                         │     → StreamingGenerationSessionRepositoryImpl.updateStatus
                         │        → StreamingLifecycleStateMachine.advance (:239)
                         └─ _coordinator.retrySinglePart                (:532)  ← 无 try/catch
```

### 3.2 会话初始化与生成链（用于理解 contract）

```text
StreamingResourceGenerationService.startGeneration              (:95)
  → _runGeneration                                              (:122)
      → _sessionRepository.updateStatus(planning / generatingPart / receivingPatch / validating / committing)
      → 成功时 updateStatus(completed)                          (:394-398 附近)
      → 异常时 updateStatus(failed) 并 _emit(GenerationFailed)   (:415, :436)
  → whenComplete: _activeRuns.remove / _activeTaskHandles.remove / _requestedStops.remove   (:114-120)
```

### 3.3 UI 状态与命令映射

```text
ResourceStudioController._statusForSession (resource_studio_controller.dart:257-271)
  completed  → ResourceStudioStatus.completed
  paused     → ResourceStudioStatus.paused
  failed/cancelled → failed
  validating → validating
  generatingPart/receivingPatch/committing → generating
  _ (含 recovering) → ready

ResourceStudioPage._commands (resource_studio_page.dart:563-597)
  ready/paused → 「继续生成」(session.status==created ? start : resume)
  generating/validating → 「暂停」
  != completed && != failed → 「取消」
  failed → 「重试」

ResourceStudioSectionControls._canRegenerate (widgets/resource_studio_section_controls.dart:357)
  = hasGenerationTasks && generationState != generating && generationState != validating
```

### 3.4 状态机表（真实代码）

`lib/domain/resources/streaming_generation_runtime_contracts.dart`：

```dart
StreamingLifecycleStatus.completed: { StreamingLifecycleStatus.completed },   // :114-116
```

`StreamingLifecycleStateMachine.advance(from, to)`（`:152-163`）在非法时抛
`StateError('Invalid StreamingLifecycleStatus transition: ...')`。

## 4. Exact Bugs

### Finding B1 — 已完成章节“重新生成”必然失败

#### Trigger
资源被 AI 完整生成一次（会话 status = `completed`，该 section 内所有 task status = `completed`），
用户在 Resource Studio 的章节控制面板点击“重新生成”。

#### Current Behavior
1. `SectionControlService.regenerateSection` 先执行 `beginLossyOperation`，把该 section 的 `completed`
   任务重置为 `ready` 并写入一条 revision（`resource_revision_service.dart:588-616`）。
2. `StreamingSectionRegenerationExecutor.regenerate` 取到该资源的最新会话（`completed`）并调用
   `retryPart`。
3. `retryPart` 第一件事是 `updateStatus(sessionId, generatingPart)`。
4. `updateStatus` 内 `StreamingLifecycleStateMachine.advance(completed, generatingPart)` 抛
   `StateError`（因为 `completed` 只允许自环）。
5. 异常被 `StreamingSectionRegenerationExecutor.regenerate` 的 `catch`（`:132`）转为
   `success=false`，`SectionControlService` 记为失败，用户看到“重新生成失败”。
6. 但是第 1 步已经修改了任务状态并记录了 revision：**失败后任务被留在 `ready`，会话仍是
   `completed`**，系统处于半改状态。

#### Expected Behavior
已完成章节可以重新生成；旧内容通过 `beginLossyOperation` 记录的 revision 可恢复；失败时任务状态
与会话状态一致收敛；不出现“按钮可用但必然失败”。

#### Evidence
```text
file:    lib/domain/resources/streaming_generation_runtime_contracts.dart
symbol:  StreamingLifecycleStateMachine._allowedTransitions[completed]
状态:    session=completed, sectionGenerationState=completed
repo:    StreamingGenerationSessionRepositoryImpl.updateStatus → advance
既有测试: test/application/resources/section_consistency_streaming_regeneration_test.dart:181-185
          （先手动 pauseGeneration 造 paused 前置态，绕过了本 bug）
         test/application/resources/streaming_resource_generation_service_test.dart（retry 前置 failed）
```

#### User / Data Impact
用户可见功能确定性失效（章节重新生成不可用）。附带把任务状态重置为 `ready` 且留下 revision，
使“已完成”会话与其任务状态不一致，后续继续生成/重试路径行为不确定。

---

### Finding M5 — `retryPart` 无异常收敛，失败后会话卡在 `generatingPart`

#### Trigger
`retryPart` 执行期间 `_coordinator.retrySinglePart` 抛出任何异常（解析/校验/网络/DB）。

#### Current Behavior
`retryPart`（`streaming_resource_generation_service.dart:516-698`）先把会话置 `generatingPart`，
随后 `_coordinator.retrySinglePart` **没有 try/catch**。异常直接向上冒泡，`_runGeneration` 中
“异常 → failed + `_emit(GenerationFailed)`”的兜底（`:415/:436`）不适用于 `retryPart`。会话永久停留
在非终态 `generatingPart`，且不发出 `GenerationFailed`；UI 只能靠控制器自己的 catch 显示 failed。

#### Expected Behavior
`retryPart` 失败时必须收敛到 `failed`（或 `paused`）并发出 `GenerationFailed`，与 `_runGeneration`
语义一致。

#### Evidence
```text
file:    lib/application/resources/streaming_resource_generation_service.dart
symbol:  retryPart (:516-698)
状态:    session 会停在 generatingPart（非终态）
既有测试: 无（TG4）
```

#### User / Data Impact
会话长时间处于 `generatingPart`：章节 `_canRegenerate` 被 `generating` 状态锁死；需要人工 pause→resume
或取消才能恢复。

---

### Finding M6 — 中断会话无启动恢复，恢复代码未接线

#### Trigger
进程在生成中途死亡（LLM 请求前/中/后、DB 写入中），随后用户重启应用并打开该资源。

#### Current Behavior
- `StreamingGenerationSessionRepositoryImpl.findInterruptedSessions`（`:306`）在全仓**只有测试调用**。
- `StreamingResourceGenerationService.recoverInterruptedGeneration`（`:701`）仅通过
  `StreamingResourceGenerationController.recover()`（`resource_studio_controller.dart:110`）可达，而
  `recover()` 在 `lib/` 内**零调用**——`ResourceStudioPage._commands` 没有“恢复”入口。
- `main.dart:174-192` 的启动恢复只处理 assembly readiness 孤儿行，不处理流式会话。

结果：会话/任务停在 `generatingPart/receivingPatch/validating/committing`，用户必须“暂停→继续”
两步才能恢复。

#### Expected Behavior
应用启动时发现中断会话并做**受控恢复**（不自动重放模型请求）：会话进入 `recovering`（可由 UI
“继续生成”恢复），底层 `generating/validating` 任务被 `recoverInterruptedTasks` 收敛，绝不永久
卡死。或者至少提供明确的 UI “恢复”入口。

#### Evidence
```text
file:    lib/application/resources/streaming_generation_session_repository.dart:306
         lib/application/resources/streaming_resource_generation_service.dart:701
         lib/features/resource_studio/presentation/controllers/resource_studio_controller.dart:110
         lib/main.dart:174-192
状态:    findInterruptedSessions / recover() 无生产调用
既有测试: test/application/resources/streaming_generation_session_repository_test.dart:197（仅 repo 层）
```

#### User / Data Impact
进程崩溃后资源长期处于“生成中”，无法重新生成章节，也无法直观恢复。

---

### Finding N8 — `_requestedStops` 对无活动运行的 cancel/pause 泄漏

#### Trigger
对没有活动 `_activeRuns` 的会话调用 `cancelGeneration` / `pauseGeneration`（例如 `created` 会话点取消）。

#### Current Behavior
`cancelGeneration`/`pauseGeneration` 无条件写 `_requestedStops[sessionId]`
（`:495` / `:451`），只有存在 `_activeRuns[sessionId]` 时 `startGeneration` 的 `whenComplete`
（`:114-120`）才清除。无活动 run 时条目永久残留。若后续同一 sessionId 再次进入生成且未清理该标记，
`_runGeneration` 可能读到陈旧 `cancelled` 而误判成功结果为取消。

#### Expected Behavior
无活动 run 的 cancel/pause 在完成状态更新后立刻移除 `_requestedStops[sessionId]`。

#### Evidence
```text
file: lib/application/resources/streaming_resource_generation_service.dart
symbol: cancelGeneration (:491-513), pauseGeneration (:447-461), startGeneration whenComplete (:114-120)
```

#### User / Data Impact
内存泄漏；存在“成功生成被误判为取消”的潜伏风险。

## 5. Root Cause

**Symptom**：点击“重新生成”报 `Invalid StreamingLifecycleStatus transition: completed -> generating_part`。

**Root Cause**：两套状态语义没有对齐。

- 产品/章节层用 `SectionGenerationState`（`lib/domain/resources/section_control.dart:60-67`）表示
  “这一章节的内容是否已保存”，其中 `completed` 只是“内容已保存、可再次生成”。
- 持久化层用 `StreamingLifecycleStatus` 表示“会话运行过程”，其 `completed` 被建模为**运行结束的
  不可逆终态**（`_allowedTransitions[completed] == {completed}`，`:114-116`）。
- `retryPart` 把“发起一次新的 part 生成”直接表达为 `updateStatus(generatingPart)`，因此在
  `completed` 会话上必然非法。
- 更深层：生成服务的失败收敛逻辑只写在 `_runGeneration` 里，`retryPart` 作为第二个运行入口没有复用；
  恢复能力虽然实现了，却没有被装配到任何启动/UI 入口。

这是一类“同一业务概念在两层各有不同状态机、且第二条写入入口未复用第一条的 contract”的系统性问题，
因此 B1/M5/M6 必须一起修。

## 6. Required Contract After Remediation

修复后，以下不变量**必须**成立（Coding Agent 不得破坏）：

1. 一个 `completed` 的生成会话**可以**合法开启新的生成/重新生成运行。
2. 重新生成前的已完成内容**保持可恢复**（由 `beginLossyOperation` 捕获的 revision 保证）。
3. 任何生成入口（`startGeneration`、`retryPart`、`resumeGeneration`）在失败时**必须**收敛到
   终态或可恢复态（`failed` / `paused`），**不得**停留在 `generatingPart` / `receivingPatch` /
   `validating` / `committing`。
4. 进程死亡不得产生“永久不可恢复”的会话：启动或 UI 必须能把它导向 `recovering`/`paused` 并可继续。
5. 旧 attempt / 旧 generation 的迟到结果**永不**提交到新 attempt（沿用既有 attempt token 守卫，
   不得移除）。
6. `completed` 只表示“当前内容已保存”，不表示“该资源禁止再生成”。

## 7. Implementation Plan

> 按真实修改顺序。所有路径以 symbol 为准。

### Step 1 — 状态机 contract（Domain）

```text
file:    lib/domain/resources/streaming_generation_runtime_contracts.dart
symbol:  StreamingLifecycleStateMachine._allowedTransitions
current: StreamingLifecycleStatus.completed: { StreamingLifecycleStatus.completed }
target:  StreamingLifecycleStatus.completed: {
           StreamingLifecycleStatus.completed,
           StreamingLifecycleStatus.generatingPart,   // 重新生成单个 Part
           StreamingLifecycleStatus.cancelled,        // 允许放弃已完成会话（与 failed/cancelled 语义一致）
         }
```

说明：
- 增加 `completed -> generatingPart`，使 `retryPart` 的既有行为合法。
- 增加 `completed -> cancelled`，使已完成会话也能被“取消”（UI 目前在 `completed` 时隐藏取消按钮，
  但状态机不应比 UI 更严格；若实施时确认 UI 永不从 completed 取消，可只加 `generatingPart`，但需在
  本 Phase 文档的验收中说明）。
- 不新增状态。见 §8 方案选择。

### Step 2 — `retryPart` 失败收敛（Service）

```text
file:    lib/application/resources/streaming_resource_generation_service.dart
symbol:  retryPart (:516-698)
```

修改：

1. 在 `updateStatus(generatingPart)` 之后，把 `_coordinator.retrySinglePart(...)` 调用包进 `try`。
2. 新增私有方法 `Future<void> _convergeAfterRegenerationFailure(String sessionId, Object error)`：
   - 读取当前 session（`findSession`）；
   - 若当前 status 可以合法到达 `failed`（使用 `StreamingLifecycleStateMachine.canTransition`），
     调用 `updateStatus(sessionId, failed, errorMessage: ...)`；
   - 否则（例如已回到 `completed`）只发出事件，不再改状态；
   - `_emit(GenerationFailed(generationId: sessionId, ..., timestamp: DateTime.now()))`。
3. `catch` 分支调用 `_convergeAfterRegenerationFailure` 后 `return false`。
4. 保留既有结尾逻辑：所有 task completed → `updateStatus(completed)`，否则 `updateStatus(paused)`。
5. 不得吞掉原始异常信息：错误消息写入 session 的 `error_message` 并随事件上报。

### Step 3 — `_requestedStops` 生命周期（Service）

```text
file:    lib/application/resources/streaming_resource_generation_service.dart
symbol:  cancelGeneration (:491-513), pauseGeneration (:447-461)
```

在“无活动 run”分支完成 `updateStatus` 之后，执行 `_requestedStops.remove(sessionId)`。
（有活动 run 的分支继续由 `startGeneration.whenComplete` 里的 `_requestedStops.remove` 负责。）

### Step 4 — 启动恢复装配（Provider + main）

```text
file:    lib/providers/riverpod_providers.dart
symbol:  resourceStudioRuntimeProvider (:415-471)
```

从 `resourceStudioRuntimeProvider` 中抽出两个可复用 provider（单一装配来源）：

```text
final streamingGenerationSessionRepositoryProvider =
    Provider<IStreamingGenerationSessionRepository>((ref) { ... });

final streamingResourceGenerationServiceProvider =
    Provider<StreamingResourceGenerationService>((ref) {
      // 使用上面的 sessionRepository + 既有 taskRepository/blueprintRepository/coordinator
    });
```

`resourceStudioRuntimeProvider` 改为复用这两个 provider，保证只有一处构造。

新增启动恢复 provider（`Provider<void>`，模式对齐既有 `assemblyReadinessCompressionLinkProvider`）：

```text
final streamingGenerationRecoveryProvider = Provider<void>((ref) {
  final repo = ref.read(streamingGenerationSessionRepositoryProvider);
  final service = ref.read(streamingResourceGenerationServiceProvider);
  unawaited(() async {
    try {
      final interrupted = await repo.findInterruptedSessions();
      for (final session in interrupted) {
        await service.recoverInterruptedGeneration(session.sessionId, autoResume: false);
      }
    } catch (_) {
      // 启动恢复是 best-effort；失败会让会话保持原状（仍可被 UI 取消/暂停）
    }
  }());
});
```

```text
file:    lib/main.dart
symbol:  _MainShellState.initState (:153-193)
```

在 Phase 10 的 `addPostFrameCallback`（:180-192）之后追加同构块：

```dart
WidgetsBinding.instance.addPostFrameCallback((_) {
  try {
    ref.read(streamingGenerationRecoveryProvider);
  } catch (_) {
    // Startup recovery must never crash the app shell.
  }
});
```

`recoverInterruptedGeneration(autoResume: false)` 会把会话置为 `recovering`（`markSessionRecovering`
经 `updateStatus` 合法），UI `_statusForSession` 将其映射为 `ready` 并显示“继续生成”，因此不会自动
重放模型请求，且用户可手动恢复。见 §8 方案选择与 §9 数据库影响。

### Step 5 — UI（最小）

`ResourceStudioPage._commands`（`resource_studio_page.dart:563-597`）已能把 `recovering`（映射为
`ready`）显示为“继续生成”，`_controller.resume` 走 `resumeGeneration`（接受 `paused`/`recovering`）。
因此在 Step 4 完成后**无需新增按钮**。本 Phase 不改 UI 布局。

如果实施时发现某个 `recovering` 会话的 `_statusForSession` 未落到 `ready`，则修正该映射，使其可用
“继续生成”恢复；不得新增第二套恢复按钮。

## 8. Design Decisions（方案选择）

### 8.1 `completed` 如何开启新运行

- **方案 A（推荐）**：在 `_allowedTransitions[completed]` 增加 `generatingPart`。
- 方案 B：`completed -> recovering -> generatingPart` 两跳。
- 方案 C：在 `retryPart` 里对 `completed` 先 `updateStatus(paused)` 再 `updateStatus(generatingPart)`。

**选择 A**。理由：

1. 其余“可再次运行”的状态（`failed`、`cancelled`、`paused`、`recovering`）都已直接允许
   `generatingPart`；对 `completed` 特判会引入不一致。
2. B/C 都会多写一次 DB，并让 `recovering`/`paused` 承担“用户主动重新生成”的语义，与它们本身的
   “中断恢复/用户暂停”语义混淆。
3. A 的改动最小、可被现有测试直接保护（mutation 可验证）。

**不采用 B/C。** 若独立审核发现 `completed -> generatingPart` 会破坏其他消费者（例如某处依赖
`completed` 为终态做显示），应在 R01 的验收中记录该依赖并改为 A + 明确的前置动作，而不是引入
两跳状态。

### 8.2 启动恢复是否自动重放

**选择不自动重放**（`autoResume: false`）。理由：

1. LLM 请求有计费与副作用；进程刚启动时自动重放不可控。
2. 现有 `recoverInterruptedGeneration(autoResume: false)` 已实现受控收敛，且 UI 能显示“继续生成”。
3. 符合 `AGENTS.md`“不得无限重试/不得掩盖错误”。

**不采用 autoResume: true。**

### 8.3 是否需要新增状态

**否。** `recovering` 已存在且语义匹配“中断后被系统收敛、等待用户决定”。

## 9. Database Impact

```text
No schema change required.
```

- 不新增表/列，不修改 `schemaVersion`（保持 43）。
- 不修改任何 migration。
- 现有数据（处于 `completed` 的会话）在升级后即可被重新生成，无需迁移。
- 中断数据（停在 `generatingPart` 等）在升级后由 Step 4 的启动恢复处理，无需迁移。
- 回滚：本 Phase 只改代码，回滚即为 revert commit；数据库无需回滚。

## 10. Concurrency / Sequence

### 10.1 当前错误时序（B1）

```text
User clicks 重新生成
  ↓
beginLossyOperation: tasks completed → ready, revision captured
  ↓
retryPart: updateStatus(completed → generatingPart)
  ↓
advance() throws StateError        ← 会话未变，任务已变（半改）
  ↓
executor catch → success=false
```

### 10.2 修复后时序（成功）

```text
User clicks 重新生成
  ↓
beginLossyOperation: tasks completed → ready, revision captured
  ↓
retryPart: updateStatus(completed → generatingPart)   ← 现在合法
  ↓
run -> validating -> committing (per part, 带 attempt token)
  ↓
all tasks completed → updateStatus(completed)
  ↓
previous content recoverable via revision
```

### 10.3 修复后时序（失败收敛）

```text
retryPart: generatingPart
  ↓
retrySinglePart throws
  ↓
_convergeAfterRegenerationFailure:
   session.status == generatingPart/validating/committing
   → updateStatus(failed, errorMessage)
   → _emit(GenerationFailed)
  ↓
UI: failed → 「重试」可用；旧内容仍在 revision 中
```

### 10.4 启动恢复时序

```text
App start (post frame)
  ↓
findInterruptedSessions()  → [session X: generatingPart]
  ↓
recoverInterruptedGeneration(X, autoResume:false)
   → markSessionRecovering(X)        (generatingPart → recovering 合法)
   → recoverInterruptedTasks(resourceId)  (generating/validating task → 可重试状态)
  ↓
session X = recovering
  ↓
UI _statusForSession(recovering) = ready → 「继续生成」
  ↓
User clicks 继续 → resumeGeneration (recovering → …) → startGeneration
```

### 10.5 迟到 attempt 的既有保证（不得破坏）

```text
attempt 1 starts (token T1)
  ↓
user 重新生成 → attempt 2 starts (token T2)
  ↓
attempt 1 late response arrives
  ↓
commitPartContent 校验 current_attempt_id == T1 ? 否则拒绝
```

该保证位于 `resource_generation_task_repository.dart` 的 attempt/lease 校验，本 Phase **不得**修改其
语义；R01 的所有测试都必须保持该守卫有效。

## 11. Files Expected To Change

```text
Production（Expected）:
- lib/domain/resources/streaming_generation_runtime_contracts.dart   （Step 1）
- lib/application/resources/streaming_resource_generation_service.dart（Step 2, Step 3）
- lib/providers/riverpod_providers.dart                              （Step 4，抽出 2 个 provider + 1 个恢复 provider）
- lib/main.dart                                                      （Step 4，启动钩子）

Production（Possible）:
- lib/features/resource_studio/presentation/controllers/resource_studio_controller.dart
  （仅当 recovering 映射需要修正；Step 5）

Tests（Expected，新建）:
- test/application/resources/streaming_generation_lifecycle_recovery_test.dart
- test/application/resources/section_regeneration_from_completed_test.dart
- test/application/resources/production_streaming_recovery_wiring_test.dart

Tests（Possible，更新）:
- test/application/resources/streaming_resource_generation_service_test.dart

Docs:
- docs/post-phase12-remediation/STATUS.md
- docs/post-phase12-remediation/remediation-phase-01-streaming-lifecycle-and-recovery.md（如结论变化）

Forbidden / should not be touched:
- lib/services/llm_service.dart（属于 R04/R08）
- lib/application/resources/part_generation_coordinator.dart（属于 R08）
- lib/application/resources/resource_revision_service.dart（属于 R03/R06）
- lib/application/resources/resource_generation_task_repository.dart 的 attempt/lease 语义
- 任何删除 legacy 表 / provider 的改动（属于 R13）
```

## 12. Test Plan

> 测试文件优先复用 `test/helpers/section_control_fakes.dart`、`test/helpers/resource_studio_fakes.dart`、
> `test/helpers/resource_tree_fixtures.dart`、`test/helpers/phase10_fixture.dart` 中的既有装配。

### TEST R01-01（覆盖 B1 成功路径）
```text
Given: 一个资源，其生成会话 status=completed，section 内所有 task completed
When:  SectionControlService.regenerateSection(...) 执行
Then:  新 generation 开始；retryPart 不再抛 StateError
       执行结束时 session 到达 completed
       存在 beginLossyOperation 记录的 revision（旧内容可恢复）
```

### TEST R01-02（覆盖 B1 的“任务不被半改”）
```text
Given: 同 R01-01
When:  regenerateSection 失败（注入 coordinator 抛异常）
Then:  session 收敛到 failed 或 paused，绝不留在 generatingPart
       task 不处于“已 ready 但 session completed”的半改组合
       旧内容仍可由 revision 恢复
```

### TEST R01-03（覆盖 M5）
```text
Given: session 可进入 generatingPart 的任意前置态
When:  retryPart 内部 retrySinglePart 抛异常
Then:  session.status ∈ {failed, paused}（终态/可恢复态）
       发出 GenerationFailed 事件
       不会长时间停留 generatingPart
```

### TEST R01-04（覆盖 M6 启动恢复，装配级）
```text
Given: 数据库中预置一个 status=generatingPart 的 session，其 task status=generating
When:  streamingGenerationRecoveryProvider 被读取（模拟启动）
Then:  findInterruptedSessions 被调用；该 session 变为 recovering
       task 不再是 generating/validating
       UI 映射 _statusForSession(recovering) == ready
       resumeGeneration 可从 recovering 继续（不自动发起模型请求）
```

### TEST R01-05（覆盖 N8）
```text
Given: 一个 created（无活动 run）的 session
When:  cancelGeneration(sessionId) 后再次 startGeneration(sessionId)
Then:  startGeneration 不读取到陈旧 cancelled 标记
       session 正常进入 planning/generatingPart
```

### TEST R01-06（覆盖“迟到 attempt 不得提交”）
```text
Given: attempt T1 进行中，随后发起 attempt T2
When:  T1 的响应迟到到达 commit 点
Then:  commit 被拒绝（attempt token 不匹配）
       DB 中该 part 内容来自 T2 或保持未提交
```

### TEST R01-07（TG5 的端到端形态）
```text
Given: 预置中断会话
When:  读取恢复 provider 后再读取 ResourceStudio 状态
Then:  资源可继续生成；章节重新生成按钮状态与任务状态一致
```

## 13. Mutation / Negative Verification

必须用以下 mutation 证明测试有效（在 `/tmp` 工作树或临时副本执行，不得污染主工作树）：

```text
Mutation 1: 从 _allowedTransitions[completed] 移除 generatingPart
→ TEST R01-01 必须 FAIL

Mutation 2: 删除 retryPart 的 try/catch 收敛
→ TEST R01-03 必须 FAIL

Mutation 3: 移除 main.dart 中的 streamingGenerationRecoveryProvider 读取
→ TEST R01-04 必须 FAIL

Mutation 4: 删除 commitPartContent 的 attempt 校验（临时，仅验证）
→ TEST R01-06 必须 FAIL

Mutation 5: 恢复 cancelGeneration 无活动 run 分支不 remove _requestedStops
→ TEST R01-05 必须 FAIL
```

## 14. Acceptance Criteria

```text
AC-R01-01 completed session 可以成功重新生成一个章节，且不抛状态转换异常。
AC-R01-02 重新生成失败后会话收敛到 failed/paused，任务不被留在半改组合。
AC-R01-03 retryPart 抛异常后会话不在非终态；发出 GenerationFailed。
AC-R01-04 启动时能发现中断会话并收敛为 recovering，UI 可“继续生成”。
AC-R01-05 无活动 run 的 cancel/pause 不泄漏 _requestedStops。
AC-R01-06 旧 attempt 的迟到响应不能提交（既有守卫仍有效）。
AC-R01-07 全量 flutter test 保持通过（不得少于基线 1600 passed）。
AC-R01-08 仅修改 §11 允许范围内的文件。
```

## 15. Required Verification Commands

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test test/application/resources/streaming_generation_lifecycle_recovery_test.dart
flutter test test/application/resources/section_regeneration_from_completed_test.dart
flutter test test/application/resources/production_streaming_recovery_wiring_test.dart
flutter test test/application/resources/section_consistency_streaming_regeneration_test.dart
flutter test test/application/resources/streaming_resource_generation_service_test.dart
flutter test test/application/resources/streaming_generation_session_repository_test.dart
flutter test
git diff --check
git status --short
```

## 16. Out of Scope

本 Phase **不得**顺手：

- 重构 `LLMService` / 传输层超时与重试（属于 R04）；
- 修改流式协议消费者异常传播或 parser（属于 R08）；
- 修改 revision / compression / autosave / trash 语义（属于 R03/R05/R06/R07）；
- 修改 UI 布局或新增页面/按钮；
- 删除任何 dead code（属于 R13）；
- 引入新的生成状态或新的持久化表。

## 17. Rollback / Failure Safety

- 修复后若重新生成运行失败：系统停在 `failed`（可重试）或 `paused`（可继续），旧内容由 revision 保留；
  **不产生** `generatingPart` / `committing` 的无归属状态。
- 若启动恢复自身失败：会话保持原状（仍可被 UI 取消/暂停），启动流程不崩溃（恢复在 `try` 内且
  best-effort）；不得让启动恢复失败导致 app 无法打开。
- 若 mutation 证明某守卫被误删：立即回滚该 commit（本 Phase 的改动本身是可 revert 的纯代码改动，
  无数据库副作用）。

## 18. Handoff Notes

- 下一个 Phase 若涉及流式协议（R08），必须复用本 Phase 确立的“失败收敛到 failed/paused”路径。
- R11（Production Wiring）必须基于本 Phase 抽出的
  `streamingGenerationSessionRepositoryProvider` / `streamingResourceGenerationServiceProvider`
  编写装配级测试，不得再造第二套装配。
