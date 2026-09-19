# Remediation Phase 07 — Autosave Durability & Failure Isolation

> **Root Cause**: RC-07
> **Findings**: M8 (MAJOR), TG8
> **Depends On**: None（与 R06 共享文件，建议 R06 之后实施）
> **Document status**: PLANNED

---

## 1. Purpose

`ResourceAutosaveService.flush` 假设 `_writeOne` 永不抛异常：它在循环前就清空 `_buffer`，循环内没有
per-item 保护。同时 `_writeOne` 在 journal 写入失败时只返回 `failed`，不会把编辑重新放回 buffer。
结果是：一次 batch 中任何一个编辑触发未捕获异常，会中断整批、丢弃其余编辑且不发出 `onFlushed`
（M8-A）；journal 写失败会让该编辑**永久丢失**（M8-B）。

本 Phase 修复的 contract 是：**“每个缓冲编辑独立结算；任何失败都必须保留该编辑以供重试，且必须向
编辑者报告结果。”**

## 2. Audit Findings Covered

```text
Primary:
- M8    flush 批次中一项异常导致其余编辑丢失；journal 写失败永久丢弃编辑

Test gaps:
- TG8   无“一项抛异常不影响其余”“journal 写失败仍保留可重试”用例
```

## 3. Current Production Architecture

```text
ResourceAutosaveService.schedule → debounce/max-age Timer → flush   (resource_autosave_service.dart:420-447)
ResourceAutosaveService.flush (:347-385)
   _timer?.cancel()
   if (_buffer.isEmpty) return
   final batch = List.from(_buffer.values)
   _buffer.clear()                                    (:360)  ← 先清空
   for (final edit in batch) {
     if (_unresolvedConflicts[partId] != null) { re-buffer; continue; }
     outcomes.add(await _writeOne(edit, trigger));     (:380)  ← 无 try/catch
   }
   onFlushed?.call(result)                            (:383)
   return result

_writeOne (:449-508)
   try { draft = await _persistJournal(edit); }
   catch → return failed(checkpointId:'')             (:459-466)  ← 不 re-buffer
   try { await _committer.applyContent(...) }
   on ResourceTreeConflictException → return _handleConflict(...)  (:490-491)
   on ResourceTreeNotFoundException → _dropJournal; return missingTarget
   catch → return failed

_handleConflict (:530-581) 自身有 await（_readLivePart / _dropJournal / 递归 _writeOne），可能抛异常

dispose → flush(dispose) → 若 _buffer 已空则什么都不做          (:396-407)
```

## 4. Exact Bugs

### Finding M8-A — 批次中一项异常导致其余编辑丢失

#### Trigger
一个 debounce 窗口内编辑了 Part A 与 Part B；A 的写入走到冲突处理或 journal 路径并抛出未捕获异常
（例如 `_handleConflict` 内的 `_readLivePart`/`_dropJournal` 失败，或递归 `_writeOne` 抛错）。

#### Current Behavior
`_handleConflict` 从 `on ResourceTreeConflictException` 的 catch 块内被 `return` 调用，其抛出的异常
不被 `_writeOne` 的其它 catch 覆盖，直接冒泡出 `_writeOne` → 冒泡出 `flush` 的 for 循环 → B 不再写入，
且 B 已不在 `_buffer` 中（batch 于 :360 清空）→ B 永久丢失；`onFlushed` 不触发，UI 既不显示成功也不
显示失败。

#### Expected Behavior
每个编辑独立结算；一项失败不影响其余；失败项重新入 buffer 以待重试；总是报告每个编辑的结果。

#### Evidence
```text
file: lib/application/resources/resource_autosave_service.dart
symbol: flush (:347-385), _writeOne (:449-508), _handleConflict (:530-581)
既有测试: resource_autosave_service_test.dart 的 fake journal/committer 从不从冲突分支抛错
```

#### User / Data Impact
一次异常导致多个 Part 的自动保存静默丢失且无提示。

---

### Finding M8-B — journal 写失败永久丢弃编辑

#### Trigger
`upsertDraftInTransaction` 抛错（磁盘满、`database is locked`、约束错误）。

#### Current Behavior
编辑已被 `flush` 从 `_buffer` 移除；`_writeOne` 捕获后返回 `failed(checkpointId:'')`，不 re-buffer。
`hasUnsavedConflict` 可能显示，但后续 `flush`（包括 dispose 的最终 flush 与“立即保存”按钮）看到空
buffer 不做任何事，屏幕上的文本永不落盘。

#### Expected Behavior
journal 写失败后该编辑必须重新入 buffer，使下一次 flush/重试能再次尝试；并向编辑者报告可重试失败。

#### Evidence
```text
file: lib/application/resources/resource_autosave_service.dart
symbol: _writeOne 的 _persistJournal catch (:455-466), flush 的 _buffer.clear (:360)
既有测试: journal fake 从不在 upsertDraftInTransaction 抛错
```

#### User / Data Impact
用户输入永久丢失（无 journal、无 tree 写入）。

## 5. Root Cause

**Symptom**：自动保存偶发丢失多个 Part 的编辑，且无错误提示。

**Root Cause**：`flush` 的批次与 `_writeOne` 的失败处理**没有共同的所有权模型**：
- buffer 在批处理开始前就被清空，等于把“尚未结算”的编辑所有权丢给了 `_writeOne`；
- `_writeOne` 只在“未解决冲突”这一种情况下把编辑重新入 buffer，其它失败（journal 失败、冲突处理
  内部异常）都直接放弃编辑；
- `flush` 没有 per-item 隔离，一个异常终止整批。

这是“批处理与单项结算职责不清”的系统性问题。

## 6. Required Contract After Remediation

1. `flush` 必须对每个编辑独立结算：单项失败/异常不得影响其余编辑。
2. 任何**未成功落盘**的编辑必须保留在 `_buffer`（或被持久化到 journal 且保留 checkpoint），以便重试。
3. `flush` 必须始终调用 `onFlushed`，并为 batch 中每个编辑产出一个 outcome。
4. journal 写入成功但 tree 写入失败时，编辑可由 journal 恢复（现有行为保持）。
5. `dispose`/`flushOnBoundary` 必须仍有最终尝试；失败时编辑保留（不得因进程退出前清空 buffer 而丢失，
   除非已持久化到 journal）。
6. `_handleConflict` 抛出的异常必须被 `_writeOne` 捕获并转化为 failed + re-buffer，不得冒泡终止批次。

## 7. Implementation Plan

### Step 1 — `flush` per-item 隔离

```text
file: lib/application/resources/resource_autosave_service.dart
symbol: flush (:347-385)
```

把循环体改为：

```dart
for (final edit in batch) {
  if (_buffer.containsKey(edit.partId.value)) continue; // 已被其它路径重新缓冲
  final unresolved = _unresolvedConflicts[edit.partId.value];
  if (unresolved != null) {
    _buffer[edit.partId.value] = edit;
    outcomes.add(conflictOutcome(...));
    continue;
  }
  try {
    outcomes.add(await _writeOne(edit, trigger));
  } catch (error) {
    _buffer[edit.partId.value] = edit;                 // 重新入 buffer
    outcomes.add(AutosaveWriteOutcome(
      partId: edit.partId.value,
      status: AutosaveWriteStatus.failed,
      checkpointId: '',
      message: '自动保存失败，已保留待重试：$error',
    ));
  }
}
```

- `onFlushed?.call(result)` 保留在循环之后（无论是否发生异常）。
- `_buffer.clear()` 的位置保留在循环前，但失败项会被重新写回。

### Step 2 — `_writeOne` journal 失败 re-buffer

```text
symbol: _writeOne 的 _persistJournal catch (:455-466)
```

将编辑重新放入 `_buffer`（`_buffer[edit.partId.value] = edit`），返回
`failed`（`checkpointId:''`，消息标注“草稿写入失败，已保留待重试”）。保持“journal 未写成功”语义。

### Step 3 — `_handleConflict` 异常内化

```text
symbol: _writeOne 的 `on ResourceTreeConflictException` 分支 (:490-491)
```

改为：

```dart
} on ResourceTreeConflictException catch (error) {
  try {
    return await _handleConflict(edit, draft, trigger, error, isRetry: isRetry);
  } catch (conflictError) {
    _buffer[edit.partId.value] = edit;
    return AutosaveWriteOutcome(
      partId: edit.partId.value,
      status: AutosaveWriteStatus.failed,
      checkpointId: draft.checkpointId,
      message: '自动保存冲突处理失败，已保留待重试：$conflictError',
    );
  }
}
```

### Step 4 — dispose / 边界 flush 的最终尝试

```text
symbol: dispose (:396-407), flushOnBoundary (:390-393)
```

- 保持 dispose 调用 `flush(dispose)`。
- 若 `flush` 后 `_buffer` 非空且存在可保留的失败编辑，记录诊断日志（不得静默）；不得在 dispose 时
  直接清空 buffer。
- 若编辑已在 journal 中（`_persistJournal` 成功），即使 tree 写入失败也可由 journal 恢复，允许
  dispose 后释放内存 buffer。

### Step 5 — 结果可见性

- 确认 `onFlushed` 的消费方（编辑器生命周期）能把 `failed` outcome 呈现给用户（现有
  `hasUnsavedConflict`/消息通道）。
- 不新增 UI 页面；仅确保失败消息可达。

## 8. Design Decisions

### 8.1 失败编辑是“留在内存 buffer”还是“写 journal”

- **方案 A（推荐）**：优先 journal；journal 不可用时留内存 buffer。
- 方案 B：失败一律写 journal。

**选择 A**。理由：journal 写失败正是本轮要处理的故障（磁盘/锁），此时只能依赖内存 buffer。方案 B 在
journal 本身不可用时无效。**不采用 B。**

### 8.2 是否在 flush 中“重试一次”

**否（本 Phase 不自动重试）。** 理由：自动重试会掩盖错误并可能加剧锁竞争；由用户动作/下一次
debounce 触发重试即可。**不采用隐式重试循环。**

## 9. Database Impact

```text
No schema change required.
```

不新增表/列，不修改 `schemaVersion`，不修改 migration。回滚为纯代码 revert。

## 10. Concurrency / Sequence

### 10.1 当前（批处理中断）

```text
flush: buffer.clear()
  ↓
_writeOne(A) → _handleConflict → throws
  ↓
for 循环终止
  ↓
B 未写入且不在 buffer        ← LOST
onFlushed NOT called
```

### 10.2 修复后

```text
flush: buffer.clear()
  ↓
_writeOne(A) throws → catch → buffer[A]=edit, outcome(A)=failed
  ↓
_writeOne(B) → outcome(B)=applied
  ↓
onFlushed(result with A+B outcomes)
  ↓
next flush retries A
```

### 10.3 journal 失败

```text
flush: buffer.clear()
  ↓
_writeOne(A): _persistJournal throws → buffer[A]=edit, outcome=failed(retryable)
  ↓
onFlushed(result)
  ↓
later flush retries A (journal/tree)
```

### 10.4 并发不变量

```text
不变量1: flush 返回后，任何未 applied 的编辑必然存在于 buffer 或 journal。
不变量2: flush 对 batch 中每个编辑都产出 outcome，且必然调用 onFlushed。
```

## 11. Files Expected To Change

```text
Production（Expected）:
- lib/application/resources/resource_autosave_service.dart

Production（Possible）:
- 消费 onFlushed 的编辑器/控制器（仅当需要展示 failed outcome）

Tests（Expected，新建）:
- test/application/resources/autosave_flush_failure_isolation_test.dart

Tests（Possible，更新）:
- test/application/resources/resource_autosave_service_test.dart

Docs:
- docs/post-phase12-remediation/STATUS.md

Forbidden / should not be touched:
- 软删除草稿保留（R06；本 Phase 不改 reconcile 分类）
- Part 内容 CAS token 语义（R03）
- PartContentCommitService 的提交逻辑
- 不改 UI 布局
```

## 12. Test Plan

### TEST R07-01（一项抛异常不影响其余）
```text
Given: buffer 中有 A、B 两个编辑；
       注入一个 fake committer，使 A 的 applyContent 抛出非 ResourceTreeConflict/NotFound 的异常
When:  flush
Then:  B 被成功写入
       A 的 outcome=failed 且 A 仍在 buffer
       onFlushed 被调用一次，outcomes 含 A 与 B
```

### TEST R07-02（冲突处理内部异常）
```text
Given: A 的 applyContent 抛 ResourceTreeConflictException，且 _readLivePart 抛异常
When:  flush
Then:  A 不冒泡；A 重新入 buffer；其余编辑正常
```

### TEST R07-03（journal 写失败保留）
```text
Given: A 的 upsertDraftInTransaction 抛异常
When:  flush
Then:  A 仍在 buffer，outcome=failed 可重试
       后续再次 flush（journal 恢复正常）时 A 被成功写入
```

### TEST R07-04（dispose 最终尝试）
```text
Given: buffer 中有编辑且 journal 正常
When:  dispose()
Then:  flush 被调用；编辑落盘或保留在 journal
       不出现“dispose 后编辑凭空消失”
```

### TEST R07-05（无编辑时行为不变）
```text
Given: buffer 为空
When:  flush
Then:  返回空 outcomes，无副作用
```

## 13. Mutation / Negative Verification

```text
Mutation 1: 移除 flush 的 per-item try/catch
→ TEST R07-01 必须 FAIL

Mutation 2: 移除 _writeOne journal catch 的 re-buffer
→ TEST R07-03 必须 FAIL

Mutation 3: 让 _handleConflict 异常继续冒泡
→ TEST R07-02 必须 FAIL

Mutation 4: 让 dispose 在有未保存编辑时提前返回
→ TEST R07-04 必须 FAIL
```

## 14. Acceptance Criteria

```text
AC-R07-01 单个编辑失败/异常不导致其它编辑丢失。
AC-R07-02 未落盘的编辑始终保留在 buffer 或 journal。
AC-R07-03 flush 总是为每个编辑产出 outcome 并调用 onFlushed。
AC-R07-04 journal 故障恢复后可重试成功。
AC-R07-05 无编辑时 flush 行为不变。
AC-R07-06 全量 flutter test 通过。
```

## 15. Required Verification Commands

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test test/application/resources/autosave_flush_failure_isolation_test.dart
flutter test test/application/resources/resource_autosave_service_test.dart
flutter test
git diff --check
git status --short
```

## 16. Out of Scope

- 不改 autosave 的 debounce/上限逻辑；
- 不改软删除时的草稿保留（R06）；
- 不新增 UI 或“重试”按钮（复用既有失败消息通道）；
- 不删除代码。

## 17. Rollback / Failure Safety

- 修复后，任何失败都会保留编辑并报告；不会出现静默丢失。
- 内存 buffer 中的编辑在进程崩溃时仍可能丢失（这是既有边界），但 journal 成功的编辑可恢复；本 Phase
  不承诺“进程崩溃零丢失”，只承诺“失败隔离与可重试”。
- 回滚为纯代码 revert。

## 18. Handoff Notes

- 若 R06 先实施，本 Phase 在 `_writeOne` 的 `ResourceTreeNotFoundException` 分支只做“不丢编辑”的
  加强，不改变 R06 的软删除保留语义。
