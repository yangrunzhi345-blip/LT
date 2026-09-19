# Remediation Phase 03 — Part Content Write Conflict & Version Contract

> **Root Cause**: RC-03
> **Findings**: M4, M7 (MAJOR), TG6, TG7
> **Depends On**: None
> **Document status**: PLANNED

---

## 1. Purpose

`resource_parts.content` 有两个**非显式编辑**的写入者，它们都不校验“我要写入的目标是不是我以为的
那个版本”：

1. **生成提交**（`ResourceGenerationTaskRepositoryImpl.commitPartContent`）——条件只有
   `id = ? AND deleted_at IS NULL`，会在用户手工编辑同一 Part 之后覆盖它（M4，丢失更新）。
2. **压缩发布**（`ResourceRevisionService.publishCompressedContentInTransaction`）——只校验 Part
   存在且内容不同，不校验候选是基于哪个版本生成的，会把过期压缩结果覆盖到更新后的正文上（M7）。

本 Phase 修复的 contract 是：**“任何替换 `resource_parts.content` 的写入都必须携带并校验源版本
token”**。这是 Part 内容层的统一乐观并发边界，与显式编辑（`PartContentCommitService`，已有 CAS）
保持一致。

## 2. Audit Findings Covered

```text
Primary:
- M4   生成提交无 CAS，覆盖生成期间的人工编辑（丢失更新）
- M7   过期压缩候选可发布覆盖更新后的内容；节省字数展示失真

Test gaps:
- TG6  无“生成提交 vs 人工编辑”丢失更新用例
- TG7  无“压缩候选生成 → 编辑/恢复 → 发布”用例
```

## 3. Current Production Architecture

### 3.1 生成提交链

```text
PartGenerationCoordinator._generateSinglePart
  → ... 流式生成 / 校验 ...
  → PartGenerationTaskRepository.commitPartContent      (lib/application/resources/resource_generation_task_repository.dart)
        txn.update(resource_parts, {
          'content': response.content,
          'content_hash': ...,
          'updated_at': now,
        }, where: 'id = ? AND deleted_at IS NULL')          ← 无版本校验
        txn.update(resources, {'updated_at': now}, ...)
  → _revisionBoundary.captureBeforeWrite / after
```

对照：显式编辑路径 `PartContentCommitService.applyContent` 使用
`expectedUpdatedAt` 做乐观锁（`lib/application/resources/part_content_commit_service.dart`）。

`startAttempt`（`resource_generation_task_repository.dart:198-260`）在发起 attempt 时检查任务
`generating` lease（`:224-228`），并写 `current_attempt_id`（`:250`），但没有记录目标 Part 的版本。

### 3.2 压缩发布链

```text
ResourceCapacityController.publishCompression                (feature controller)
  → ResourceCapacityServiceRuntime.publishLatestCompression  (resource_capacity_runtime.dart:123)
  → CompressionPublisher.publish                             (resource_compression_publisher.dart:74)
       ├─ _jobs.findCandidateInTransaction(txn, candidateId)
       ├─ _jobs.markCandidateAppliedInTransaction(txn, ...)
       └─ _revisions.publishCompressedContentInTransaction   (resource_revision_service.dart:651)
              ├─ live = _tree.readLiveState(txn, resourceId)  (:660)
              ├─ if (existing.content == compressedContent) → alreadyApplied
              ├─ captureInTransaction('压缩前')
              └─ _applyTargetState(target)                    ← 无条件覆盖
  → _jobs.findPublishableCandidates(resourceId)               (compression_job_repository.dart:475)
       where: validation_state='validated' AND applied_at IS NULL AND scope='part'
```

压缩任务本身已经有 `source_token`（`resource_compression_jobs.source_token`，
`database_service.dart:814`），其值等于发起压缩时目标节点的 `updated_at`
（`compression_coordinator.dart:189/214`）。但 `resource_compression_candidates` 表
（`:835-851`）与领域模型 `CompressionCandidate`（`resource_compression.dart:322-354`）**都不携带该
token**，发布时也无从比较。

## 4. Exact Bugs

### Finding M4 — 生成提交覆盖生成期间的人工编辑

#### Trigger
用户在 Resource Studio 中打开一个正在流式生成的 Part 进行编辑并保存（编辑入口在生成中仍可用），
随后该 Part 的生成 attempt 完成并提交。

#### Current Behavior
`commitPartContent` 以 `id = ? AND deleted_at IS NULL` 更新 `resource_parts.content`，不检查该 Part
在 attempt 开始后是否被人工改写；生成提交“最后写入者胜”，人工内容被静默覆盖（写入前有 revision
捕获，但用户未预期）。

#### Expected Behavior
生成提交若发现目标 Part 的版本在 attempt 期间被其他写者（人工保存/自动保存/恢复）改变，必须
**拒绝提交**并保留人工内容，同时把自己的 attempt 标记为失败（可重试/可重新生成），不得静默覆盖。

#### Evidence
```text
file:    lib/application/resources/resource_generation_task_repository.dart
symbol:  commitPartContent 的 txn.update(resource_parts, ...) where 'id = ? AND deleted_at IS NULL'
对照:    lib/application/resources/part_content_commit_service.dart（显式编辑有 expectedUpdatedAt CAS）
状态:    人工内容被覆盖；既有 revision 可恢复但无冲突提示
既有测试: test/application/resources/part_generation_coordinator_test.dart 等不构造并发人工编辑
```

#### User / Data Impact
用户手工修改的正文被静默丢弃（有 revision 兜底，但非用户预期）；属于用户可见的数据丢失。

---

### Finding M7 — 过期压缩候选覆盖更新后的内容

#### Trigger
对某 Part 生成压缩候选；此后用户编辑该 Part（或从历史恢复旧版本）；用户回到容量面板点“发布压缩
结果”。

#### Current Behavior
`publishCompressedContentInTransaction` 只检查 Part 存在与 `existing.content != compressedContent`，
随即用 `compressedContent` 覆盖当前正文；既不比较候选的源版本，也不用当前正文长度计算
`savedCharacters`（用的是候选生成时的 `originalCharacters`）。

#### Expected Behavior
发布前必须校验候选的源版本 token（= 压缩任务 `source_token` = 候选生成时 Part 的 `updated_at`）
与当前 Part 的 `updated_at` 一致；不一致则拒绝发布，并把该候选标记为 `superseded`（不再被
`findPublishableCandidates` 返回），提示用户重新生成压缩。节省字数必须以当前正文长度为准。

#### Evidence
```text
file:    lib/application/resources/resource_revision_service.dart
symbol:  publishCompressedContentInTransaction (:651-720)
file:    lib/application/resources/compression_job_repository.dart
symbol:  findPublishableCandidates (:475), findCandidateInTransaction
file:    lib/domain/resources/resource_compression.dart
symbol:  CompressionCandidate (:322-354) —— 无 sourceToken 字段
file:    lib/services/database_service.dart
symbol:  resource_compression_jobs.source_token (:814), resource_compression_candidates (:835-851)
既有测试: 压缩测试“生成后立即发布”，无中间编辑
```

#### User / Data Impact
更新后的正文被旧压缩结果覆盖（可经 revision 恢复，但静默发生）；节省字数不实。

## 5. Root Cause

**Symptom**：人工编辑/后续修改被生成提交或压缩发布覆盖。

**Root Cause**：`resource_parts.content` 被**三个写者**修改——显式编辑（有 CAS 与 session token）、
生成提交（无 CAS）、压缩发布（无 CAS）。系统已有一个“Part 内容版本”概念（`resource_parts.updated_at`，
即显式编辑使用的 session token），但只有显式编辑路径使用它。

- 生成路径根本没有在 attempt 开始时记录目标版本，因此提交时无从比较。
- 压缩路径其实**已经计算**了源版本（`resource_compression_jobs.source_token`），只是在候选与发布
  环节把它丢掉了。

这是“同一资源写入者各自实现、未共享同一个版本 contract”的系统性问题，故 M4/M7 同属一个 Phase。

## 6. Required Contract After Remediation

1. `resource_parts.updated_at` 是 Part 内容的**唯一版本 token**；任何替换内容的写入都必须声明它基于
   哪个 token，并在事务内校验其仍然有效。
2. 生成提交必须携带“attempt 开始时的 Part token”，不一致即拒绝；拒绝时不得写入内容、不得留下
   成功 attempt。
3. 压缩发布必须携带“候选的源 token”，与当前 Part token 不一致即拒绝，并将候选标记为 `superseded`。
4. 拒绝必须是**可见的**（typed error / 状态消息），不得静默覆盖，不得吞异常。
5. 不一致时旧内容（人工编辑结果/更新后正文）必须保留；被拒绝的一方必须可重试（重新生成/重新压缩）。
6. 显式编辑路径现有的 CAS 与 session token 语义不得改变。

## 7. Implementation Plan

### Step 1 — DB：attempt 记录源 token（Schema v44）

```text
file: lib/services/database_service.dart
symbol: createResourceGenerationAttemptSchema
current: resource_generation_attempts 无源版本列
target:  新增列 source_updated_at TEXT NOT NULL DEFAULT ''
```

- 在 `createResourceGenerationAttemptSchema` 中把 `source_updated_at TEXT NOT NULL DEFAULT ''`
  加入建表语句（fresh install）。
- 在 `migrateStepByStep` 中为 `oldVersion < 44` 添加幂等 `safeAddColumn(db, 'resource_generation_attempts',
  'source_updated_at', "TEXT NOT NULL DEFAULT ''")`。
- `DatabaseService.schemaVersion` 从 43 改为 44；`_initDb` 的恢复路径与
  `onCreate: createV44Schema` 链同步（现有结构是 `createV43Schema` 递归，新增 `createV44Schema`
  或在 v43 建表函数内直接加列——**遵循仓库现有递归 createVXX 模式**，实施时以
  `createV43Schema` 的现有组织方式为准）。

### Step 2 — 领域模型：CompressionCandidate 携带源 token

```text
file: lib/domain/resources/resource_compression.dart
symbol: CompressionCandidate
current: 无 sourceToken
target:  final String sourceToken;  // 来自 resource_compression_jobs.source_token
```

同步更新 `const` 构造函数、`withAppliedAt`、`toString`（如打印）与所有构造点
（`compression_job_repository.dart` 的 mapping）。

### Step 3 — 生成提交：attempt 记录并在提交时校验 token

```text
file: lib/application/resources/resource_generation_task_repository.dart
symbol: startAttempt (:198), commitPartContent
```

1. `startAttempt`：在读取/写入 attempt 行时，查询目标 Part 的当前 `updated_at`
   （`resource_parts.updated_at`，`deleted_at IS NULL`），写入 `resource_generation_attempts.source_updated_at`。
   若 Part 不存在，保持现有错误语义。
2. `commitPartContent`：在更新 `resource_parts.content` 时将 where 改为：

   ```sql
   id = ? AND deleted_at IS NULL AND updated_at = ?
   ```

   `updated_at` 用该 attempt 的 `source_updated_at`。
3. 当 `source_updated_at` 为空字符串（升级前遗留 attempt）时，跳过 token 校验以保持向后兼容，
   并用 `_log`/debug 记录一次。
4. 若 guard 使更新行数为 0，区分两种情况：
   - Part 仍存在（`SELECT 1 ... WHERE id=? AND deleted_at IS NULL`）→ 抛
     `ResourceTreeConflictException`（或新增 typed `PartGenerationConflictException`），
     attempt/task 标记为 `failed` 并带明确错误消息；
   - Part 不存在 → 保持现有 `StateError('... 未找到对应的部件节点 ...')`。
5. 顺序：先做 token 校验/冲突判定，再 `captureBeforeWrite` 与 UPDATE，避免为一次被拒绝的提交记录
   无意义 revision（若现有实现已先 capture，调整为先校验后 capture）。

### Step 4 — 压缩发布：校验源 token 并标记 superseded

```text
file: lib/application/resources/compression_job_repository.dart
symbol: findCandidateInTransaction / findPublishableCandidates mapping
```
- 从 `resource_compression_jobs.source_token` 填充 `CompressionCandidate.sourceToken`
  （候选与 job 是 1:1，有唯一索引 `idx_compression_candidates_job`）。

```text
file: lib/application/resources/compression_publisher.dart
symbol: publish
```
- 把 `candidate.sourceToken` 传入 `publishCompressedContentInTransaction`。

```text
file: lib/application/resources/resource_revision_service.dart
symbol: publishCompressedContentInTransaction
```
- 新增参数 `required String sourceToken`。
- 在读到 `existing`（live Part）后：
  - 若 `sourceToken.isNotEmpty && existing` 的当前 token（由 `readLiveState` 提供的
    `updatedAt`/节点 token）与 `sourceToken` 不一致 → 抛
    `CompressionPublishException('压缩候选已过期（源版本已变更），请重新生成压缩')`。
  - `savedCharacters`/`originalCharacters` 改用**当前** Part 内容长度计算（返回结构中给出当前值）。
- 发布失败时（过期）由 `CompressionPublisher.publish` 捕获并调用新增仓库方法
  `markCandidateSupersededInTransaction(txn, candidateId)`，把 `validation_state` 置为 `superseded`；
  `findPublishableCandidates` 现有 `validation_state='validated'` 过滤会自动排除它。
- 若需要新增 `validation_state` 取值 `superseded`，在 `resource_compression.dart` 的校验枚举/常量
  处补充（确认是否为字符串常量而非 enum，实施时以真实定义为准）。

### Step 5 — UI 文案（最小）

容量面板在发布失败时展示 `CompressionPublishException` 的用户可见消息（复用
`resourceStudioUserMessage`）。不得新增“强制覆盖”按钮。

## 8. Design Decisions

### 8.1 M4 用“attempt 快照 token”还是“写入时重新读并比较内容”

- **方案 A（推荐）**：attempt 开始时快照 Part `updated_at`，提交时 CAS。
- 方案 B：提交时比较 Part 当前内容与 attempt 开始时的内容 hash（需另存 hash）。
- 方案 C：生成期间禁止人工编辑（UI 禁用编辑器）。

**选择 A**。理由：
1. `updated_at` 已经是系统既有版本 token（显式编辑 CAS 使用同一值），复用可避免第二套版本概念。
2. B 需要再存 hash，且“内容相同视为无冲突”会掩盖等价编辑（例如人工回改）。
3. C 改变产品行为且不能覆盖“生成期间其他路径（恢复/压缩）改写”的情况。
4. **不采用 B/C**。

### 8.2 M7 过期候选是“拒绝”还是“自动以新内容重算”

**选择拒绝并标记 `superseded`**。理由：
1. 自动重算需要重新调用模型（计费、延迟），不应在用户点击“发布”时隐式发生。
2. 用户可显式重新触发压缩；被标记的候选不再干扰。
3. **不采用自动重算/自动覆盖。**

### 8.3 是否需要为候选表加列

**否（M7 不需要）**。源 token 已在 job 上；候选通过 `job_id` 关联，读取时 join/二次查询即可。
只有 M4 需要为 attempts 加列。

## 9. Database Impact

```text
Schema change: YES
- 新列: resource_generation_attempts.source_updated_at TEXT NOT NULL DEFAULT ''
- schemaVersion: 43 → 44
- migration: migrateStepByStep 增加 oldVersion < 44 的幂等 safeAddColumn
- 幂等: safeAddColumn 自带 table/column 存在性守卫；重复执行安全
- fresh install: 建表语句包含该列
- old DB: 既有 attempt 行 source_updated_at='' → 提交时跳过 token 校验（向后兼容）
- rollback: 代码 revert 后多余列无害（SQLite 允许保留未使用列）；无需 drop
- resource_compression_candidates: 不变更 schema
```

## 10. Concurrency / Sequence

### 10.1 M4 当前

```text
attempt start (no snapshot)
  ↓
user manual save P       → resource_parts.updated_at = T1 (session CAS)
  ↓
generation commit P      → UPDATE ... WHERE id=? AND deleted_at IS NULL
  ↓
user content overwritten   ← LOST UPDATE
```

### 10.2 M4 修复后

```text
attempt start → snapshot source_updated_at = T0
  ↓
user manual save P → updated_at = T1
  ↓
generation commit P → UPDATE ... WHERE id=? AND deleted_at IS NULL AND updated_at = T0
  ↓
0 rows → conflict → attempt failed, manual content preserved
```

### 10.3 M7 当前 / 修复后

```text
当前:  candidate(no token) → publish → overwrite regardless of version
修复:  candidate(sourceToken=T0) → publish
         live Part token == T0 ? overwrite : reject + mark superseded
```

### 10.4 并发不变量

```text
不变量1: 生成提交成功 ⇒ 提交按 attempt 快照版本执行，且期间无其他内容写入。
不变量2: 压缩发布成功 ⇒ 候选源版本 == 当前 Part 版本。
不变量3: 任一被拒绝的写入不得改变 resource_parts.content 或读取到错误字数。
```

## 11. Files Expected To Change

```text
Production（Expected）:
- lib/services/database_service.dart                                  （v44 + migration）
- lib/application/resources/resource_generation_task_repository.dart （startAttempt / commitPartContent）
- lib/application/resources/resource_compression.dart                 （CompressionCandidate.sourceToken）
- lib/application/resources/compression_job_repository.dart           （mapping + markCandidateSuperseded）
- lib/application/resources/compression_publisher.dart                （传 sourceToken + 过期处理）
- lib/application/resources/resource_revision_service.dart            （publishCompressedContentInTransaction 校验）

Production（Possible）:
- lib/features/resource_studio/application/use_cases/resource_capacity_runtime.dart（过期提示透传）
- lib/features/resource_studio/presentation/controllers/resource_capacity_controller.dart（用户文案）
- 错误类型定义文件（新增 typed exception）

Tests（Expected，新建）:
- test/application/resources/part_content_generation_manual_edit_conflict_test.dart
- test/application/resources/compression_stale_candidate_publish_test.dart
- test/application/resources/database_migration_v44_test.dart

Tests（Possible，更新）:
- test/application/resources/resource_generation_task_repository_test.dart
- test/application/resources/resource_revision_service_test.dart
- test/application/resources/compression_pipeline_test.dart
- test/application/resources/database_migration_v43*（如有）

Docs:
- docs/post-phase12-remediation/STATUS.md

Forbidden / should not be touched:
- 流式会话 / retryPart / 恢复（R01）
- 对话提交（R02）
- LLM 传输（R04）
- 删除/回收站/旧行 identity（R05/R06）
- 自动保存批次（R07，除了共享 token 语义不得改其行为）
```

## 12. Test Plan

### TEST R03-01（M4 冲突拒绝）
```text
Given: 一个 attempt 已 startAttempt（快照 token=T0）；随后人工保存该 Part（token=T1）
When:  commitPartContent
Then:  提交被拒绝（typed conflict）
       resource_parts.content 仍为人工内容
       attempt/task 标记 failed 且错误消息明确
```

### TEST R03-02（M4 无冲突正常提交）
```text
Given: attempt 开始后无人修改该 Part
When:  commitPartContent
Then:  内容写入成功，updated_at 更新，revision 正常
```

### TEST R03-03（M4 向后兼容）
```text
Given: attempt 行 source_updated_at=''（升级前遗留）
When:  commitPartContent
Then:  跳过 token 校验，正常提交（不因缺快照而失败）
```

### TEST R03-04（M7 过期候选拒绝）
```text
Given: 对 Part 生成压缩候选（sourceToken=T0）；随后编辑该 Part（token=T1）
When:  CompressionPublisher.publish(candidateId)
Then:  抛 CompressionPublishException（过期）
       Part 内容仍为编辑后的正文
       候选 validation_state='superseded'
       findPublishableCandidates 不再返回它
```

### TEST R03-05（M7 未过期正常发布 + 字数）
```text
Given: 候选 sourceToken 与当前 Part token 一致
When:  publish
Then:  内容被替换为压缩结果
       savedCharacters 基于当前正文长度计算（与 candidate.originalCharacters 一致时相等）
```

### TEST R03-06（迁移 v44）
```text
Given: 一个 v43 数据库（含 resource_generation_attempts 行）
When:  打开到 v44
Then:  source_updated_at 列存在，旧行值为 ''
       再次打开（重复迁移）不报错
```

## 13. Mutation / Negative Verification

```text
Mutation 1: 从 commitPartContent 的 where 移除 updated_at = ?
→ TEST R03-01 必须 FAIL

Mutation 2: 让 publishCompressedContentInTransaction 忽略 sourceToken
→ TEST R03-04 必须 FAIL

Mutation 3: 把 startAttempt 写 source_updated_at 的代码删除
→ TEST R03-01、TEST R03-02 至少一个 FAIL

Mutation 4: 迁移步骤改为非幂等 ALTER（去掉 safeAddColumn 守卫）
→ TEST R03-06 必须 FAIL（重复迁移/已有列时报错）
```

## 14. Acceptance Criteria

```text
AC-R03-01 生成提交在 attempt 期间发生人工编辑时被拒绝，人工内容保留。
AC-R03-02 无冲突的生成提交正常写入。
AC-R03-03 升级前遗留 attempt 仍可提交（向后兼容）。
AC-R03-04 过期压缩候选发布被拒绝且标记 superseded。
AC-R03-05 未过期候选发布正常，字数以当前正文计算。
AC-R03-06 v43→v44 迁移幂等，fresh install 与旧库均可打开。
AC-R03-07 全量 flutter test 通过（含既有 migration 测试）。
```

## 15. Required Verification Commands

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test test/application/resources/part_content_generation_manual_edit_conflict_test.dart
flutter test test/application/resources/compression_stale_candidate_publish_test.dart
flutter test test/application/resources/database_migration_v44_test.dart
flutter test test/application/resources/resource_generation_task_repository_test.dart
flutter test test/application/resources/compression_pipeline_test.dart
flutter test test/application/resources/database_migration_v43_test.dart   # 若存在
flutter test
git diff --check
git status --short
```

## 16. Out of Scope

- 不改动显式编辑 `PartContentCommitService` 的 CAS 语义；
- 不重构压缩调度/lease；
- 不新增“强制覆盖”UI；
- 不改动自动保存的 token 管理（R07 只处理批次失败隔离）；
- 不删除任何代码。

## 17. Rollback / Failure Safety

- 生成冲突：系统停在 attempt `failed` + Part 保持人工内容；可重新生成（R01 保证重新生成可用）。
- 压缩过期：候选被标记 `superseded`，Part 内容不变；用户可重新触发压缩。
- 迁移失败：`safeAddColumn` 幂等，最坏情况列已存在被跳过；不影响旧数据。
- **不允许**出现：内容被覆盖但 attempt 报成功；候选被标记 applied 但内容未写；迁移重复执行报错。

## 18. OPEN QUESTION

```text
Q1: resource_generation_attempts 是 commit 时唯一可查的 attempt 载体吗？确认
    commitPartContent 是否能通过 task/attempt 行读到 source_updated_at。
    （file: resource_generation_task_repository.dart commitPartContent 读取 attempt 的路径）
Q2: resource_compression_candidates.validation_state 是普通 TEXT 还是受限枚举？新增 'superseded'
    是否需要同步更新 domain 校验（file: resource_compression.dart 中的校验/常量）。
```

## 19. Handoff Notes

- R06（软删除语义）与 R07（自动保存）都依赖 Part `updated_at` 作为版本 token；本 Phase 确立的
  “token = resource_parts.updated_at” 是后续 Phase 的共享契约，不得更改。
- R11 应为压缩发布与生成提交补充装配级测试。
