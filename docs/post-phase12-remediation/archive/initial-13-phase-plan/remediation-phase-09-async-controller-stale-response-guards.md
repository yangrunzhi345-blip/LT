# Remediation Phase 09 — Async Controller Stale-Response & Reentrancy Guards

> **Root Cause**: RC-09
> **Findings**: M14, N13, N9, N10, N11, N12 (MAJOR + MINOR)
> **Depends On**: None
> **Document status**: PLANNED

---

## 1. Purpose

多个 UI 控制器在异步操作完成后**无条件**发布状态，缺少“请求代际”或“重入”守卫：

- Studio 容量/版本控制器在资源切换（A→B）后可能被 A 的迟到响应覆盖，并据此对**错误资源**发起写操作
  （M14：发布压缩、恢复历史版本）；
- Studio 生成失败后仍显示未提交的预览正文（N13）；
- 对话/冒险/章节/设置控制器存在并发打开、删除/加载交错、双击重入、dispose 后 notify 等问题
  （N9/N10/N11/N12）。

本 Phase 修复的 contract 是：**“任何异步结果在发布状态或驱动写操作之前，必须证明自己仍对应当前
选中的目标；任何用户动作入口必须防重入；任何 dispose 后的回调不得触碰已销毁对象。”**

## 2. Audit Findings Covered

```text
Primary:
- M14  Studio 容量/版本控制器无请求代际守卫 → 迟到响应驱动对错误资源的写

Related:
- N13  Studio 生成失败后预览正文与已提交状态不一致
- N9   openAdventure 丢弃并发打开请求（最后一次点击不生效）
- N10  deleteAdventure 与 loadAdventure 交错可加载已删除冒险
- N11  SectionControlController._run 无重入校验（双击并发重生成）
- N12  SettingsProvider 帧后回调在 dispose 后仍可能 notifyListeners
```

## 3. Current Production Architecture

### 3.1 正确的参照实现

```text
ResourceLibraryController                      (features/resource_library/presentation/controllers/resource_library_controller.dart)
  int _requestGeneration = 0;                  (:18)
  final requestGeneration = ++_requestGeneration;   (:24)
  emit 前: !_disposed && requestGeneration == _requestGeneration   (:81)
  dispose/切换: _requestGeneration++            (:86)
```

（回收站控制器 `ResourceTrashController._loadGeneration` 同样正确。）

### 3.2 缺失守卫的控制器

```text
ResourceCapacityController.load                 (features/resource_studio/presentation/controllers/resource_capacity_controller.dart:32-51)
    await _runtime.summarize(resourceId) → _emit(state with resourceId=summary.resourceId)
    无 generation 检查
ResourceCapacityController.publishCompression    (:171-198)
    final resourceId = _state.resourceId?.value;      ← 可能来自迟到响应
    await _runtime.publishLatestCompression(resourceId)
ResourceRevisionController.load                 (features/resource_studio/presentation/controllers/resource_revision_controller.dart:36-68)
    无 generation 检查
ResourceRevisionController.restore              (:76-113)（有 _busy 但按 revisionId 解析资源）

ResourceStudioController 事件处理                (features/resource_studio/presentation/controllers/resource_studio_controller.dart:159-231)
    失败事件不清 _buffers[partId] / _pendingPartContents

ChatProvider.openAdventure                       (lib/providers/chat_provider.dart:550)
    if (_isOpeningAdventure) return;                 ← 静默丢弃新请求
AdventureProvider.loadAdventure / deleteAdventure (lib/providers/adventure_provider.dart:312-367, 410-429)
SectionControlController._run                    (features/resource_studio/presentation/controllers/section_control_controller.dart:158-181)
    只 _setBusy(busyId,true)，不检查 busySectionIds.contains
SettingsProvider                                 (lib/providers/settings_provider.dart:463-465, dispose :727)
    addPostFrameCallback((_) => notifyListeners()) 无 _disposed 检查
```

## 4. Exact Bugs

### Finding M14 — Studio 容量/版本控制器迟到响应驱动错误写

#### Trigger
在 Resource Studio 中快速切换资源 A→B，A 的 `summarize` / `listHistory` 晚于 B 返回。

#### Current Behavior
两个控制器都无条件 `_emit`，把 `_state.resourceId` 置回 A、`items` 置为 A 的历史。
`publishCompression` 随后读取 `_state.resourceId`（= A）并发布 A 的压缩候选，而页面显示 B；
`restore(revisionId)` 也可对 A 操作。

#### Expected Behavior
过期响应必须被丢弃；写操作必须基于当前选中的资源，且发布前再次校验资源未变。

#### Evidence
```text
file: lib/features/resource_studio/presentation/controllers/resource_capacity_controller.dart:32-51, 171-198
file: lib/features/resource_studio/presentation/controllers/resource_revision_controller.dart:36-68, 76-113
对照: lib/features/resource_library/presentation/controllers/resource_library_controller.dart:18,24,81,86
既有测试: 无重叠加载乱序完成用例
```

#### User / Data Impact
对错误资源执行压缩发布/恢复 → 内容被非预期修改（有 revision 兜底，但用户预期错位）。

---

### Finding N13 — 生成失败后预览正文残留

#### Trigger
某 Part 生成过程中已收到部分 patch，随后 `ValidationFailed` / `GenerationFailed`。

#### Current Behavior
`ResourceStudioController._appendPatch` 把流式文本写入 `_buffers[partId]`/`_pendingPartContents`，
并合并进 `state.partContents`；失败时控制器不清 `_buffers[partId]`，UI 继续把未提交的预览当作 Part
正文显示，而状态是 `failed`。

#### Expected Behavior
失败/校验失败后，受影响 Part 的预览缓存必须清除（或明确标记为未提交），使 UI 与持久化状态一致。

#### Evidence
```text
file: lib/features/resource_studio/presentation/controllers/resource_studio_controller.dart:159-231
既有测试: Widget 测试用 FakeResourceStudioRuntime，从不 emit 带既有预览的失败 Part
```

#### User / Data Impact
用户看到的内容与实际保存内容不一致，可能误以为已保存。

---

### Finding N9 — openAdventure 丢弃并发打开请求

`ChatProvider.openAdventure`（`lib/providers/chat_provider.dart:550`）用
`if (_isOpeningAdventure) return;` 直接丢弃第二次点击；快速点 A 再点 B 最终打开 A。`AdventureProvider.loadAdventure:313` 有第二个同名 flag。
**期望**：记录最新请求 id，完成后若已变则按最新请求重载。

### Finding N10 — delete/load 交错加载已删除冒险

`AdventureProvider.loadAdventure`（`:312-367`）在多个 `await` 之后才 `_currentAdventureId = id`；
`deleteAdventure`（`:410-429`）在 load 进行中执行时，load 完成后仍可能把已删除冒险置为 `_inGame`。
**期望**：load 完成后二次确认冒险仍存在，或用删除版本号作废 load。

### Finding N11 — SectionControlController._run 无重入校验

`_run`（`section_control_controller.dart:158-181`）只 `_setBusy(busyId,true)`，不检查该 id 是否已 busy；
双击“重新生成”会产生两个并发 retry，第二个在 `startAttempt` 的 lease 校验处失败，表现为偶发失败。
**期望**：`_run` 开头对 `busyId` 做 `busySectionIds.contains` 早退。

### Finding N12 — SettingsProvider dispose 后 notifyListeners

`settings_provider.dart:463-465` 的 `addPostFrameCallback((_) => notifyListeners())` 无 `_disposed` 检查；
若回调在 `dispose()`（`:727` 取消订阅）之前已入队，dispose 后执行会在已销毁 notifier 上
`notifyListeners()`（debug 抛 `was used after being disposed`）。
**期望**：帧后回调内 `if (_disposed) return;`。

## 5. Root Cause

**Symptom**：跨资源/跨请求的状态污染、错误写操作、偶发失败、debug 断言。

**Root Cause**：控制器把“发起请求”与“发布结果”视为同一生命周期，未把**请求身份**（代际/资源 id）
与**当前选中目标**绑定。系统里已有正确模式（`ResourceLibraryController._requestGeneration`），但没有
被统一应用；同时若干用户动作入口缺少重入保护，dispose 后的回调缺少存活检查。

## 6. Required Contract After Remediation

1. 任何异步加载在发布状态前，必须校验“请求代际仍是最新且目标资源仍是当前资源”。
2. 任何由控制器状态驱动的写操作（发布压缩、恢复版本）在提交前必须再次校验资源未变。
3. 用户动作入口对同一目标必须防重入（双击不产生并发操作）。
4. dispose 后的任何回调不得发布状态或触碰已销毁对象。
5. 生成失败/校验失败后，受影响的预览缓存必须与持久化状态一致。
6. 不得改变正常（无并发）路径的可见行为。

## 7. Implementation Plan

### Step 1 — Studio 容量控制器加请求代际（M14）

```text
file: lib/features/resource_studio/presentation/controllers/resource_capacity_controller.dart
symbol: class ResourceCapacityController
```

- 新增 `int _requestGeneration = 0; String? _requestedResourceId;`。
- `load(resourceId)`：
  - `final generation = ++_requestGeneration; _requestedResourceId = resourceId;`
  - 发布前 `if (_disposed || generation != _requestGeneration) return;`
- `refresh()` 同 `load`。
- `publishCompression()`：
  - 记录 `final resourceId = _state.resourceId?.value` 后，再校验
    `resourceId == _requestedResourceId`（或直接在发布前 `++_requestGeneration` 并使过期响应失效）。
  - 发布完成后同样按代际校验再 `_emit`。
- `dispose()`：`_disposed = true; _requestGeneration++;`（若尚无 `_disposed` 字段则新增）。

### Step 2 — Studio 版本控制器加请求代际（M14）

```text
file: lib/features/resource_studio/presentation/controllers/resource_revision_controller.dart
symbol: class ResourceRevisionController
```

- 同 Step 1：新增 `_requestGeneration`，`load(resourceId)` 发布前校验代际与 `_resourceId`。
- `restore(revisionId, expectedUpdatedAt)`：
  - 在 `_runtime.restoreRevision` 前后校验代际 `generation == _requestGeneration`；过期则不发布结果。
  - `readResourceUpdatedAt()` 使用当前 `_resourceId`（保持），但 `restore` 开始时捕获并确认该资源仍是
    `_resourceId`。
- `dispose()` 已有 `_disposed`；补充 `_requestGeneration++`。

### Step 3 — Studio 生成失败清理预览（N13）

```text
file: lib/features/resource_studio/presentation/controllers/resource_studio_controller.dart
symbol: 事件处理（ValidationFailed / GenerationFailed 分支）
```

- 失败事件到达时，对被影响的 `partId` 执行 `_buffers.remove(partId)` 与
  `_pendingPartContents.remove(partId)`，并将 `state.partContents[partId]` 恢复为“已提交内容”。
- “已提交内容”来源：`_initialPartContents`（`resource_studio_controller.dart:274-277`）或重新读取的
  tree；实现时选择已有来源，不新增重复缓存。
- 不得清空其它 Part 的预览。

### Step 4 — openAdventure 保留最新请求（N9）

```text
file: lib/providers/chat_provider.dart
symbol: openAdventure (:550)
```
- 新增 `int? _pendingOpenAdventureId;`（或复用请求代际）。
- 正在打开时记录“最新请求”，当前打开完成后若发现请求已变，则按最新请求重新执行，而不是直接 return。
- `AdventureProvider.loadAdventure:313` 的同名 flag 一并处理（或统一到 chat 层）。

### Step 5 — delete/load 交错（N10）

```text
file: lib/providers/adventure_provider.dart
symbol: loadAdventure (:312-367), deleteAdventure (:410-429)
```
- 维护 `int _adventureGeneration`；`loadAdventure` 捕获代际，完成后校验；`deleteAdventure` 使代际自增。
- 或 load 完成后用 `getAdventureById` 二次确认存在。

### Step 6 — SectionControl 重入（N11）

```text
file: lib/features/resource_studio/presentation/controllers/section_control_controller.dart
symbol: _run (:158-181)
```
- 开头：`if (busyId != null && _state.busySectionIds.contains(busyId)) return false;`
  （字段名以真实实现为准；若无集合则新增）。

### Step 7 — SettingsProvider dispose 检查（N12）

```text
file: lib/providers/settings_provider.dart
symbol: 帧后回调 (:463-465)
```
- 回调内 `if (_disposed) return;`（若无 `_disposed` 字段则新增并在 dispose 置位）。

## 8. Design Decisions

### 8.1 用“请求代际”还是“比较 resourceId”

**选择请求代际 + 目标 id 双重校验**（与 `ResourceLibraryController` 一致）。理由：仅比较 id 无法区分
“同一资源的两次加载”，也无法处理“已 dispose”。**不采用单一 id 比较。**

### 8.2 N13 清预览的时机

**选择在失败事件到达时立即清除受影响 Part。** 理由：失败即意味着该预览从未提交，保留会误导用户。
**不采用“保留并标记未提交”**（需要额外 UI 状态，超出本 Phase）。

### 8.3 N9 是否直接串行化

**选择保留最新请求**。理由：用户最后点击的意图应生效；直接丢弃会违背预期。**不采用“继续丢弃”。**

## 9. Database Impact

```text
No schema change required.
```

不新增表/列，不修改 `schemaVersion`，不修改 migration。回滚为纯代码 revert。

## 10. Concurrency / Sequence

### 10.1 M14 当前

```text
select A → load(A) starts
select B → load(B) starts
B completes → UI = B
A completes late → UI = A, _state.resourceId = A
publishCompression → publishes A's candidate while page shows B
```

### 10.2 M14 修复后

```text
select A → generation=1
select B → generation=2
B completes → generation==2 → emit B
A completes late → generation(1) != 2 → DISCARD
publishCompression → resourceId == requestedResourceId(B) → publishes B
```

### 10.3 N13 修复后

```text
streaming patches → buffers[P] populated, preview shown
ValidationFailed(P) → buffers.remove(P); preview = committed content
```

### 10.4 不变量

```text
不变量1: 控制器的 _state.resourceId 始终等于最后一次用户选择的资源。
不变量2: 写操作只针对当前选中资源。
不变量3: 失败后预览 == 已提交内容。
不变量4: dispose 后无状态发布。
不变量5: 同一目标不产生并发用户动作。
```

## 11. Files Expected To Change

```text
Production（Expected）:
- lib/features/resource_studio/presentation/controllers/resource_capacity_controller.dart
- lib/features/resource_studio/presentation/controllers/resource_revision_controller.dart
- lib/features/resource_studio/presentation/controllers/section_control_controller.dart
- lib/features/resource_studio/presentation/controllers/resource_studio_controller.dart
- lib/providers/chat_provider.dart
- lib/providers/adventure_provider.dart
- lib/providers/settings_provider.dart

Production（Possible）:
- 对应 view state 类（若需新增 busy 集合/代际字段）

Tests（Expected，新建）:
- test/features/resource_studio/studio_controller_stale_response_test.dart
- test/features/resource_studio/studio_failed_part_preview_test.dart
- test/providers/adventure_open_concurrency_test.dart
- test/providers/settings_provider_dispose_test.dart
- test/features/resource_studio/section_control_reentrancy_test.dart

Tests（Possible，更新）:
- 既有 controller/provider 测试

Docs:
- docs/post-phase12-remediation/STATUS.md

Forbidden / should not be touched:
- 内容写入 CAS（R03）
- 流式生命周期（R01）
- 软删除/恢复语义（R06）
- 不新增页面/按钮
```

## 12. Test Plan

### TEST R09-01（M14 容量迟到响应丢弃）
```text
Given: 受控 runtime，summarize(A) 挂起，summarize(B) 先完成
When:  依次 load(A)、load(B)，再释放 A
Then:  state.resourceId == B；A 的结果被丢弃
```

### TEST R09-02（M14 版本迟到响应丢弃）
```text
同 TEST R09-01，针对 listHistory
```

### TEST R09-03（M14 写操作针对当前资源）
```text
Given: A 的迟到响应到达后（应被丢弃）
When:  publishCompression()
Then:  发布的候选属于当前资源 B，而非 A
```

### TEST R09-04（N13 失败清预览）
```text
Given: 某 Part 有流式预览缓冲，随后收到 ValidationFailed
When:  处理事件
Then:  state.partContents[partId] == 已提交内容
       UI 不再显示未提交预览
```

### TEST R09-05（N9 最新打开请求生效）
```text
Given: open(A) 进行中
When:  open(B) 被调用，随后 A 完成
Then:  最终打开 B（不是 A，也不是无操作）
```

### TEST R09-06（N10 删除后不被加载）
```text
Given: load(X) 进行中
When:  deleteAdventure(X) 执行后 load 完成
Then:  不进入 _inGame；不加载 X 的消息
```

### TEST R09-07（N11 重入）
```text
Given: section busy
When:  再次触发 regenerateSection
Then:  第二次被拒绝（不产生第二个并发 retry）
```

### TEST R09-08（N12 dispose 安全）
```text
Given: 帧后回调已入队
When:  dispose 后回调执行
Then:  不调用 notifyListeners；无 disposed 异常
```

## 13. Mutation / Negative Verification

```text
Mutation 1: 移除容量控制器的 generation 校验
→ TEST R09-01、R09-03 必须 FAIL

Mutation 2: 移除版本控制器的 generation 校验
→ TEST R09-02 必须 FAIL

Mutation 3: 失败事件不清 buffers
→ TEST R09-04 必须 FAIL

Mutation 4: 恢复 openAdventure 的 `if (_isOpeningAdventure) return;`
→ TEST R09-05 必须 FAIL

Mutation 5: 移除 _run 的重入检查
→ TEST R09-07 必须 FAIL

Mutation 6: 移除 settings 回调的 _disposed 检查
→ TEST R09-08 必须 FAIL
```

## 14. Acceptance Criteria

```text
AC-R09-01 Studio 容量/版本控制器丢弃过期响应，状态始终对应当前资源。
AC-R09-02 由控制器驱动的写操作只作用于当前资源。
AC-R09-03 生成失败后预览与已提交内容一致。
AC-R09-04 并发打开冒险时最后一次意图生效。
AC-R09-05 删除/加载交错不加载已删除冒险。
AC-R09-06 章节操作不因双击并发。
AC-R09-07 dispose 后无状态发布。
AC-R09-08 全量 flutter test 通过。
```

## 15. Required Verification Commands

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test test/features/resource_studio/studio_controller_stale_response_test.dart
flutter test test/features/resource_studio/studio_failed_part_preview_test.dart
flutter test test/providers/adventure_open_concurrency_test.dart
flutter test test/providers/settings_provider_dispose_test.dart
flutter test test/features/resource_studio/section_control_reentrancy_test.dart
flutter test
git diff --check
git status --short
```

## 16. Out of Scope

- 不重构 Studio 页面/控制器架构；
- 不改业务逻辑（生成/压缩/恢复的语义）；
- 不新增 UI 提示或按钮（除必要的最小文案）；
- 不删除代码。

## 17. Rollback / Failure Safety

- 引入代际守卫后，最坏情况是丢弃一个过期响应（正确行为），不影响当前资源。
- 写操作前校验失败 → 拒绝执行并提示，不产生错误修改。
- 回滚为纯代码 revert。

## 18. OPEN QUESTION

```text
Q1: SectionControlController 是否已有 busy 集合字段？需按真实字段名实现 N11
    （file: section_control_controller.dart）。
Q2: AdventureProvider 是否已有可用于代际的计数器/版本号？若已有则复用，避免新增重复状态
    （file: lib/providers/adventure_provider.dart）。
```

## 19. Handoff Notes

- R11 应为 Studio 控制器的迟到响应与失败预览补充装配级测试。
