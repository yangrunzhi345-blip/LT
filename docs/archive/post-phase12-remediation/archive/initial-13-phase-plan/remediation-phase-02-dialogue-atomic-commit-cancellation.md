# Remediation Phase 02 — Dialogue Atomic Commit & Cancellation Boundary

> **Root Cause**: RC-02
> **Findings**: M1 (MAJOR), TG3
> **Depends On**: None
> **Document status**: PLANNED

---

## 1. Purpose

对话引擎 `ChatEngine.sendMessage` 的**唯一不可回退操作**是对 SQLite 的
`commitSceneDialogueTurn`（一次事务写入 user/assistant 消息、`game_state`、runtime、回合记录）。
当前代码在**提交之后**才检查请求是否已被取消；一旦检查失败，它仍按“回滚内存”的语义把用户消息从
内存删除（M1）。于是出现“DB 已提交、内存/UI 未提交”的分叉：下一次对话会用陈旧的内存 `gameState`
覆盖数据库，丢掉上一回合的状态推进。

本 Phase 修复的 contract 是：**“DB 提交是不可回退点”**。提交前可以取消并完整回滚内存；提交后必须
完成内存/UI 应用，取消只能被“记录”而不能撤回已落地的事务。

## 2. Audit Findings Covered

```text
Primary:
- M1   对话提交后才校验取消 → DB/内存分叉、状态推进丢失

Test gaps:
- TG3  无“commit await 期间触发 cancelStreaming”的时序测试
```

## 3. Current Production Architecture

```text
ChatProvider.sendMessage                                  (lib/providers/chat_provider.dart)
  → MessagingProvider.sendMessage                         (lib/providers/messaging_provider.dart)
  → ChatEngine.sendMessage                                (lib/engines/chat_engine.dart:339)
        _activeRequestId = requestId                       (:388)
        _status = ChatStatus.streaming                     (:471/:482)
        ... LLM 流式生成、长度守卫、场景状态计算 ...
        await _adventureRepo.commitSceneDialogueTurn(...)  (:931)   ← 唯一不可回退事务
        if (!_isRequestCurrent(...)) throw GenerationCancelledException  (:978-981)
        _clearPendingCustomStatus(settledConfig)           (:984)
        await _host.applySceneDialogueCommitResult(result) (:985)
        _host.messages.add(aiMsg)                          (:995)
        _status = ChatStatus.idle                          (:1003)
      catch (e)                                            (:1057)
        if (_cancelRequested || !_isRequestCurrent(...))   (:1069-1071)
            _cancelRequested = false
            _scenePhase = cancelled
            _host.messages.removeLast()  // 仅内存          (:1075-1078)

ChatEngine.cancelStreaming                                 (:2122-2125)
    if (_status == streaming || loading) { _cancelRequested = true; _generation++; }

ChatEngine._isRequestCurrent                               (:1723-1735)
    = !_disposed && !_cancelRequested && _activeRequestId == requestId
      && _generation == generation && host 当前 adventure/branch 匹配
      && !(_activeTaskHandle?.isCancelled ?? false)
```

`AdventureRepositoryImpl.commitSceneDialogueTurn` 在单事务内写入 user/assistant 消息、`game_state`、
runtime、`scene_dialogue_turns`（`lib/services/repositories/adventure_repository_impl.dart:413-454`）。

## 4. Exact Bugs

### Finding M1 — 提交后取消校验导致 DB 与内存分叉

#### Trigger
LLM 流已结束（typewriter `onStreamEnd` 已触发），`_status` 仍为 `streaming`（要到 `:1003` 才置
`idle`）；用户在此时点击“停止生成”，且该点击落在 `commitSceneDialogueTurn` 的 `await` 期间。

#### Current Behavior
1. `commitSceneDialogueTurn` 事务已提交：数据库中存在本回合的 user/assistant 消息与状态推进。
2. `:978` 的 `_isRequestCurrent` 因 `_cancelRequested == true` / `_generation` 已递增而失败，抛
   `GenerationCancelledException`。
3. catch 分支（`:1069-1079`）把 user 消息从**内存** `_host.messages` 删除，**不回滚 DB**。
4. `:985 applySceneDialogueCommitResult` 被跳过，host 的 `gameState`/`adventureConfig` 未更新。

结果：DB 有该回合（含状态推进），内存没有；下一回合以陈旧内存状态提交，覆盖 DB，丢掉上一回合推进。

#### Expected Behavior
- 取消发生在**提交前**：不写 DB，完整回滚内存（删除 user 消息），状态回到 idle。
- 取消发生在**提交后**：事务是唯一事实，必须执行 `applySceneDialogueCommitResult` 并保留消息；
  取消只能标记/停止后续工作，不得撤回已提交事务、不得让 DB 与内存分叉。

#### Evidence
```text
file:    lib/engines/chat_engine.dart
symbol:  commit 顺序 (:931, :978-985), catch 回滚 (:1057-1079), cancelStreaming (:2122-2125),
         _isRequestCurrent (:1723-1735)
状态:    DB 已提交；_host.messages 被内存删除；gameState 未应用
既有测试: 单测直接调 commitSceneDialogueTurn 或 mock repo，无“commit await 期间 cancel”时序 seam
```

#### User / Data Impact
回合状态推进丢失（等级/经验/场景状态回退）；用户消息在 UI 消失但实际已在历史中；下一回合可能基于
错误状态继续。属于用户可见的数据一致性问题。

## 5. Root Cause

**Symptom**：取消后 UI 无此回合，但重新加载后回合又出现、状态却回退。

**Root Cause**：把“不可回退的 DB 事务”放在“可被取消的请求校验”之后，但取消路径仍实现为
“回滚内存”。即：**回退点（commit）与取消判定点的顺序与语义不匹配**。`_cancelRequested` 是跨整段
async 流程的瞬时标志，无法表达“事务是否已经落地”，而 catch 分支把它当作“什么都没发生”处理。

`chat_engine.dart:982-984` 的注释本身承认“此后的取消路径只会抛 exception”，说明设计上把 commit
之后仍视为可取消，这是错误前提。

## 6. Required Contract After Remediation

1. **提交前取消边界**：commit 之前任何时刻取消 → 不写 DB；内存完整回滚（user 消息移除、
   `_scenePhase = cancelled`、`_status = idle`）。
2. **`COMMIT` 是不可回退点**：`commitSceneDialogueTurn` 一旦返回成功，本回合的
   user/assistant 消息与状态推进即成为唯一事实。
3. **提交后协调（post-commit reconciliation）**：commit 成功后必须无条件
   `applySceneDialogueCommitResult` 并保留消息；即便此时 `_cancelRequested` 为真，也不得删除消息、
   不得跳过状态应用。
4. **DB 与内存一致性**：任何终止路径结束后，内存 `_host.messages` / `gameState` 与 DB 中该回合
   一致（可选：把“取消发生在提交后”作为一次正常完成处理）。
5. **可恢复性**：`_cancelRequested` 在流程结束后必须复位（不得影响下一次发送）。
6. 既有“旧请求不得覆盖新请求”的守卫（`_isRequestCurrent` 的 generation/requestId/branch 校验）不得
   削弱。

## 7. Implementation Plan

### Step 1 — 前置取消校验 + 提交后不抛

```text
file:    lib/engines/chat_engine.dart
symbol:  sendMessage 的提交段 (:925-1005)
```

1. 在 `await _adventureRepo.commitSceneDialogueTurn(...)` **之前**插入一次取消/失效校验：

   ```dart
   if (!_isRequestCurrent(requestId, requestGeneration, adventureId, branchId)) {
     throw const GenerationCancelledException();
   }
   ```

2. **删除**提交之后（原 `:978-981`）的 `_isRequestCurrent` 抛出。提交之后不再因取消而抛
   `GenerationCancelledException`。
3. 引入局部标志 `var turnCommitted = false;`，在 `commitSceneDialogueTurn` 返回后置
   `turnCommitted = true;`；若 `adventureId == null`（无持久化冒险）则在构造 `result` 成功处也视为
   已提交。

### Step 2 — catch 分支区分“已提交/未提交”

```text
file:    lib/engines/chat_engine.dart
symbol:  sendMessage 的 catch (:1057-1079)
```

1. 仅当 `!turnCommitted` 时，才允许执行“删除内存 user 消息 + `_scenePhase = cancelled`”的取消回滚。
2. 若 `turnCommitted == true` 且发生异常（例如 `applySceneDialogueCommitResult` 自身失败），不得删除
   已提交的 user 消息；应记录错误、保持 `_status = idle`，并确保后续可重试不产生重复回合（见 §17）。
3. `_cancelRequested` 在所有路径结束时复位（现有 `:1072` 仅覆盖取消分支；补充非取消分支的复位）。

### Step 3 — 提交后协调（保留取消意图但完成应用）

```text
file:    lib/engines/chat_engine.dart
symbol:  commit 成功后的应用段 (:984-1005)
```

1. 无条件执行 `_clearPendingCustomStatus` 与 `await _host.applySceneDialogueCommitResult(result)`。
2. 记录一个局部 `lateCancel = _cancelRequested;`（在 commit 前捕获更佳），commit 后：
   - 正常执行 `_host.messages.add(aiMsg)` 等；
   - `_status = ChatStatus.idle; _scenePhase = SceneDialoguePhase.completed;`
   - 若 `lateCancel` 为真，仅作为“用户曾请求停止”的记录（如日志/诊断），不改变已提交事实；
   - 复位 `_cancelRequested = false`。
3. 不得在提交后再抛 `GenerationCancelledException`。

### Step 4 — 测试可观测性

为测试提供可注入的时序 seam，且不改变生产行为：例如在 `AdventureRepository` 的 commit 前后允许
测试注入一个 `Completer`（测试专用 fake 实现 `IAdventureRepository`，在 `commitSceneDialogueTurn`
内 await 一个受控 Completer）。**不得**为测试在生产代码里新增 `Future.delayed` 或公开可变字段。

## 8. Design Decisions

### 8.1 取消 + 已提交时的最终语义

- **方案 A（推荐）**：提交后取消被当作“正常完成”，UI 显示该回合；`_cancelRequested` 复位。
- 方案 B：提交后取消时仍完成应用，但把 `_scenePhase` 标为 `cancelled` 并在 UI 上提示“回合已生成，
  无法撤销”。
- 方案 C：尝试回滚 DB（删除已提交回合）。

**选择 A**。理由：
1. 事务是唯一事实；回滚 DB 需要反向事务，风险高且会产生新的不一致窗口（用户可能已看到内容）。
2. 方案 B 的额外提示对正确性无影响，可留作后续 UX 改进，不是本 Phase 目标。
3. **不采用 C**：删除已提交回合会产生“消息已展示但被删除”的新分叉。

### 8.2 是否需要“取消意图”持久化

**否。** 取消是进程内瞬时事件；本 Phase 不新增字段。

## 9. Database Impact

```text
No schema change required.
```

- 不新增表/列，不修改 `schemaVersion`（保持 43），不修改 migration。
- 已提交回合并不会因本修复被改写；无数据迁移。
- 回滚：纯代码 revert；DB 无副作用。

## 10. Concurrency / Sequence

### 10.1 当前（错误）

```text
LLM stream ends (status still streaming)
  ↓
commitSceneDialogueTurn ───────────────► DB COMMITTED
  ↓
user clicks 停止生成 → _cancelRequested=true, _generation++
  ↓
_isRequestCurrent == false → throw GenerationCancelledException
  ↓
catch: remove user message from memory            ← DB≠memory
       skip applySceneDialogueCommitResult
```

### 10.2 修复后（取消落在提交前）

```text
PRE-COMMIT CANCELLATION BOUNDARY
  ↓
_isRequestCurrent == false → throw
  ↓
catch: !turnCommitted → remove memory user message, status idle
  ↓
DB untouched  → DB == memory (both without the turn)
```

### 10.3 修复后（取消落在提交中/后）

```text
_isRequestCurrent == true
  ↓
COMMIT (DB COMMITTED, turnCommitted = true)
  ↓
user clicks 停止生成（late）
  ↓
POST-COMMIT RECONCILIATION
  applySceneDialogueCommitResult
  add aiMsg, status idle, scenePhase completed
  _cancelRequested = false
  ↓
DB == memory (turn preserved)
```

### 10.4 不变量

```text
不变量: 对每个 requestId，最多只有一个 DB 回合；(DB 存在该回合) ⇔ (内存存在该回合)
```

## 11. Files Expected To Change

```text
Production（Expected）:
- lib/engines/chat_engine.dart
  （sendMessage 提交段、catch 段；可能新增一个私有收敛方法）

Production（Possible）:
- （无。若需要测试 seam，优先通过 IAdventureRepository fake 注入，不新增生产 API）

Tests（Expected，新建）:
- test/engines/chat_engine_cancellation_commit_boundary_test.dart

Tests（Possible，更新）:
- 现有 chat_engine 相关测试（如有）

Docs:
- docs/post-phase12-remediation/STATUS.md

Forbidden / should not be touched:
- lib/services/llm_service.dart（R04/R08）
- lib/services/repositories/adventure_repository_impl.dart 的事务内容
- lib/application/resources/**（R01/R03/R05/R06/R07）
- UI 布局
```

## 12. Test Plan

优先使用 `test/support/chat_engine_host_fixture.dart`。

### TEST R02-01（提交前取消）
```text
Given: 一个受控 IAdventureRepository fake，commitSceneDialogueTurn 在写库前 await 一个 Completer A
When:  在 A 完成前调用 cancelStreaming()
Then:  commitSceneDialogueTurn 未被调用（或未提交）
       内存不保留该回合；_status=idle；_scenePhase=cancelled
```

### TEST R02-02（提交期间取消 → 提交后协调）
```text
Given: fake commit 已写入“DB”并在写入后 await Completer B
When:  在 B 完成前 cancelStreaming()，然后释放 B
Then:  DB 中存在该回合
       内存存在该回合（user + assistant）
       applySceneDialogueCommitResult 被调用，gameState 已更新
       不抛 GenerationCancelledException
       _cancelRequested == false（已复位）
```

### TEST R02-03（DB 与内存一致性断言）
```text
Given: TEST R02-02 结束后
Then:  DB 回合数 == 内存回合数；两者的 gameState 推进一致
```

### TEST R02-04（旧守卫不被破坏）
```text
Given: 请求 A 进行中
When:  发起请求 B（_generation++ 且 _activeRequestId 改变）后 A 的响应到达
Then:  A 的提交被拒绝（A 不得写入 DB）
```

## 13. Mutation / Negative Verification

```text
Mutation 1: 把提交前取消校验删除（只在提交后校验）
→ TEST R02-01 必须 FAIL

Mutation 2: 恢复提交后的 `_isRequestCurrent` 抛出
→ TEST R02-02 必须 FAIL

Mutation 3: 让 catch 的取消分支在 turnCommitted==true 时也删除 user 消息
→ TEST R02-02 / R02-03 必须 FAIL
```

## 14. Acceptance Criteria

```text
AC-R02-01 提交前取消不写 DB，内存完整回滚。
AC-R02-02 提交成功后即使立即取消，DB 与内存都保留该回合，gameState 已应用。
AC-R02-03 任意终止路径后 DB 回合集合 == 内存回合集合。
AC-R02-04 旧请求不得覆盖新请求的守卫仍然有效。
AC-R02-05 全量 flutter test 保持通过。
```

## 15. Required Verification Commands

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test test/engines/chat_engine_cancellation_commit_boundary_test.dart
flutter test
git diff --check
git status --short
```

## 16. Out of Scope

- 不重构 ChatEngine 的整体结构、不拆分 sendMessage；
- 不改 LLM 流式读取、长度守卫、场景状态校验逻辑；
- 不新增“回合撤销”功能；
- 不改 UI；
- 不删除任何 dead code（R13）。

## 17. Rollback / Failure Safety

- 修复后，任何异常路径必须保证：要么“DB 与内存都没有该回合”，要么“DB 与内存都有该回合”。
- 若 `applySceneDialogueCommitResult` 自身抛异常（提交已落地），系统停在 `_status = idle`，
  内存保留已提交的 user 消息；不得删除它。此时“重试”应基于已有回合状态（不得重复插入同一
  requestId；`requestId` 由上层保证幂等；若不确定，本 Phase 需在实现时确认
  `commitSceneDialogueTurn` 对同 requestId 的幂等性并记录——见 OPEN QUESTION）。
- 回滚即 revert commit；无数据库改动。

## 18. OPEN QUESTION

```text
Q1: commitSceneDialogueTurn 对同一 requestId 是否幂等（重复调用是否会插入两条回合）？
    需要检查 lib/services/repositories/adventure_repository_impl.dart 中
    scene_dialogue_turns / messages 的写入是否以 requestId 去重。
    若不去重，Step 2 的“提交后异常不得重试同一 requestId”必须在实现中明确。
```

## 19. Handoff Notes

- R11（Production Wiring）可为对话链补充装配级测试，但不得改变本 Phase 确立的提交边界顺序。
