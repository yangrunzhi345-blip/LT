# Phase 6.1 — Streaming Resource Generation Runtime 技术分析与设计规格

本文件为 Phase 6 第一开发阶段（Phase 6.1: Streaming Resource Generation Runtime）的技术分析与实施设计。

---

## 1. 当前架构概览 (Current Architecture Overview)

经过 Phase 0 至 Phase 5 的演进，LT 项目已建立了分层、解耦、以单个 Part 为原子、以小型 patch 为传输格式的资源生成与持久化体系：

1. **Phase 0 — 领域契约层 (`lib/domain/resources/`)**：
   - 确立了不可变领域值对象模型：`Resource`、`ResourceSection`、`ResourcePart`、`ResourceTree`，以及强类型的 `ResourceId`、`SectionId`、`PartId`。
   - 确立了容量硬上限（`ResourceLimits`：世界观 50,000 / 60,000 字，角色/NPC 5,000 / 6,000 字，单 Part 上限 3,000 字）与 `ResourceCapacityPolicy`。
   - 规定了纯 Dart 领域层无 Flutter、SQLite、HTTP 或整资源 JSON 序列化（由 `resource_contract_layer_test.dart` 守护）。

2. **Phase 1 — 统一内容树持久化 (`lib/services/repositories/`)**：
   - 建立了 `resources`、`resource_sections`、`resource_parts` 三层规范化关系数据库表。
   - `ResourceTreeRepositoryImpl` 实现了单节点 mount、乐观锁（`expectedUpdatedAt`）、树草稿批量写入和级联软删除。

3. **Phase 2 — 旧数据迁移与兼容读取 (`lib/application/resources/`)**：
   - `LegacyResourceMapper` 与 `ResourceMigrationService` 实现了确定性幂等迁移。
   - `ResourceReadFacade` 与 `ILibraryRepository.readResourcePreferringTree` 提供了新树优先、旧表回退的透明读取层。

4. **Phase 3 — 统一创建管线 (`lib/application/resources/resource_creation_pipeline.dart`)**：
   - 所有创建入口收拢至 `ResourceCreationPipeline`，统一管理 `resource_creation_sessions` 会话表与 `idempotencyKey`。
   - 手动创建直接落库内容树；AI 创建仅保存参考资料（`ReferenceSource`）并推进至 `planning` 边界，绝不生成虚假正文。

5. **Phase 4 — 自适应蓝图规划 (`lib/application/resources/blueprint_*.dart`)**：
   - `BlueprintPlanner` 结合 `LlmGateway` 生成结构蓝图 `ResourceBlueprint`，校验有向无环依赖图（DAG 三色 DFS）与字数预算。
   - 蓝图确认（`confirmBlueprint`）单事务原子创建资源树占位节点（正文严格为空）与 `resource_generation_tasks` 任务行。

6. **Phase 5 — 增量 JSON Part 生成协议 (`lib/domain/resources/resource_generation_protocol.dart` & `lib/application/resources/`)**：
   - 定义 Incremental Patch Protocol v1：`start_part`、`append_text`、`complete_part`、`fail_part`。
   - `GenerationPatchParser` 与 `GenerationPatchAccumulator` 实现单调 sequence 与 cursor 偏移校验、NDJSON 流式解析与截断防护。
   - `PartGenerationCoordinator` 按照 DAG 拓扑顺序调度任务（最大并发度 `maxConcurrency = 2`），单事务提交 Part 正文至 `resource_parts`。
   - `resource_generation_attempts` 记录生成尝试审计，支持崩溃恢复 `recoverInterruptedTasks` 与失败重试。

---

## 2. 现有 Phase 5 能力 (Existing Phase 5 Capabilities)

Phase 5 已完备并验证的能力包括：
- **微粒度 Patch 协议**：支持 `start_part`、`append_text`、`complete_part`、`fail_part` 4 种基础操作，禁止传输完整 Resource JSON。
- **严格流式解析与校验**：`GenerationPatchParser` 执行白名单校验；`GenerationPatchAccumulator` 保证幂等写入、捕获序号缺口（`PatchSequenceGapException`）与游标偏移不匹配（`PatchCursorMismatchException`）。
- **正文校验管线**：`PartGenerationValidator` 校验 5 维身份绑定（`protocol_version`, `generation_id`, `resource_id`, `section_id`, `part_id`），检查正文字数硬上限（<= 3,000 字）及结构合法性。
- **独占租约与原子提交**：`startAttempt` 在数据库层加锁任务状态；`commitPartContent` 单事务更新部件正文、刷新资源更新时间戳、并标记任务和尝试完成。
- **局部崩溃恢复**：`recoverInterruptedTasks` 在重启时将未完成的 `generating`/`validating` 任务重置为 `ready`（若依赖满足）或 `pending`。
- **DAG 依赖调度**：前置 Part 完成后自动激活下游就绪任务。

---

## 3. 缺失的运行时能力 (Missing Runtime Capabilities)

虽然 Phase 5 实现了底层的 Part 增量调度与数据库提交，但距离完整的资源生成运行时（Generation Runtime）仍存在以下关键能力缺口：

1. **缺少统一生成会话生命周期模型 (Generation Session Lifecycle)**：
   - Phase 5 的协调器只有局部 Part 任务状态（`PartTaskStatus`）和粗粒度的 `generateAllParts` 返回值（bool），缺少整个生成作业（Generation Session）的生命周期状态机。
   - 缺少显式的整体运行状态转换：
     `created -> planning -> generating_part -> receiving_patch -> validating -> committing -> completed`，以及控制/失败分支：`failed`, `paused`, `cancelled`, `recovering`。
2. **缺少持久化的运行时状态跟踪 (Runtime State Persistence)**：
   - 现有的 `resource_creation_sessions` 停留在 Phase 3 的规划会话层；`resource_generation_tasks` 记录的是静态 Part 任务。没有专门持久化整个“生成作业运行实例”的表与仓储，导致应用退出或崩溃后，无法确定上一次生成作业的总体进度、当前活动部件、已完成数量、失败原因等整体状态。
3. **缺少解耦的生成事件广播系统 (Generation Events)**：
   - `PartGenerationCoordinator` 仅提供粗粒度的进度轮询回调 `onProgress(PartGenerationProgress)`，无法感知 patch 流入、校验开始、校验成功/失败、单 Part 开启与结束等高保真瞬态事件。
   - 未来 Phase 6.2（事件流式处理）和 Phase 6.3（Streaming Resource Studio UI）需要订阅纯净的 Dart 事件流（`Stream<GenerationRuntimeEvent>`），不能直接耦合数据库查询或轮询。
4. **缺少对“暂停/继续/重试/取消”生命周期行为的高阶协调**：
   - 现有的取消仅停留在 `taskHandle.isCancelled`，没有结构化的 `pause`、`resume`、`retryPart` 接口，无法在不丢失已完成部件的前提下支持用户离开工作台或恢复运行。

---

## 4. 建议实施架构 (Proposed Implementation Architecture)

遵循领域驱动设计与现有项目的 `controller / service / repository` 分层架构，不引入庞大臃肿的单体类：

### 4.1 领域层 (Domain Layer)
新建 `lib/domain/resources/streaming_generation_runtime_contracts.dart`：
- **`StreamingLifecycleStatus` 枚举**：
  `created`, `planning`, `generatingPart`, `receivingPatch`, `validating`, `committing`, `completed`, `failed`, `paused`, `cancelled`, `recovering`。
  对应存储字面量严格遵循规范：`'created'`, `'planning'`, `'generating_part'`, `'receiving_patch'`, `'validating'`, `'committing'`, `'completed'`, `'failed'`, `'paused'`, `'cancelled'`, `'recovering'`。
- **`StreamingLifecycleStateMachine` 状态机**：
  显式校验并执行合法状态迁移：
  - `created` -> `planning`, `recovering`, `cancelled`
  - `planning` -> `generatingPart`, `failed`, `cancelled`, `paused`
  - `generatingPart` -> `receivingPatch`, `validating`, `failed`, `cancelled`, `paused`
  - `receivingPatch` -> `validating`, `generatingPart`, `failed`, `cancelled`, `paused`
  - `validating` -> `committing`, `failed`, `cancelled`
  - `committing` -> `generatingPart`, `completed`, `failed`, `cancelled`
  - `failed` -> `recovering`, `generatingPart`, `planning`
  - `paused` -> `generatingPart`, `planning`, `cancelled`
  - `cancelled` -> `recovering`, `generatingPart`
  - `recovering` -> `generatingPart`, `planning`, `failed`, `cancelled`
  - `completed` 为终态。
- **`GenerationRuntimeEvent` 领域事件层次（纯 Dart sealed 类）**：
  - `GenerationStarted` (generationId, resourceId, blueprintId, timestamp)
  - `PartStarted` (generationId, resourceId, partId, taskId, attemptId, attemptNumber, timestamp)
  - `PatchReceived` (generationId, resourceId, partId, taskId, attemptId, patch, currentLength, timestamp)
  - `ValidationStarted` (generationId, resourceId, partId, taskId, attemptId, timestamp)
  - `ValidationPassed` (generationId, resourceId, partId, taskId, attemptId, charCount, timestamp)
  - `ValidationFailed` (generationId, resourceId, partId, taskId, attemptId, errorMessage, timestamp)
  - `PartCompleted` (generationId, resourceId, partId, taskId, attemptId, charCount, timestamp)
  - `GenerationCompleted` (generationId, resourceId, totalParts, totalCharacters, timestamp)
  - `GenerationFailed` (generationId, resourceId, failedPartId, errorMessage, timestamp)
- **`StreamingGenerationSession` 不变领域实体**：
  持有 `sessionId`, `resourceId`, `blueprintId`, `creationSessionId`, `status`, `currentPartId`, `currentTaskId`, `currentAttemptId`, `completedPartsCount`, `totalPartsCount`, `errorMessage`, `createdAt`, `updatedAt`。

### 4.2 持久化与仓储层 (Repository Layer)
新建 `lib/application/resources/streaming_generation_session_repository.dart`：
- **`IStreamingGenerationSessionRepository` 接口**：
  - `createSession(StreamingGenerationSession session)`
  - `findSession(String sessionId)`
  - `findLatestSessionForResource(String resourceId)`
  - `updateSessionStatus(String sessionId, StreamingLifecycleStatus status, ...)`
  - `updateProgress(...)`
  - `recordFailure(...)`
  - `findInterruptedSessions()`
  - `recoverInterruptedSession(String sessionId)`
- **`StreamingGenerationSessionRepositoryImpl` 实现**：
  - 持久化至 SQLite 数据表 `resource_generation_sessions`。
  - 在 `DatabaseService` 中提供 `createResourceGenerationSessionSchema(Database db)`，支持自动迁移与幂等初始化。

### 4.3 核心服务运行时层 (Service / Runtime Layer)
新建 `lib/application/resources/streaming_resource_generation_service.dart`：
- 作为连接 Phase 3 会话、Phase 4 蓝图、Phase 5 调度协调器的编排核心。
- 提供广播事件流 `Stream<GenerationRuntimeEvent> get eventStream`。
- 贯穿生命周期执行：
  1. `createSession(...)`：初始化并持久化会话，状态为 `created`。
  2. `startGeneration(...)`：
     - 若 Blueprint 尚未确认则进入 `planning` 并执行确认；
     - 触发 `GenerationStarted` 事件；
     - 调用增强型 `PartGenerationCoordinator`，接入 patch 监听钩子（Hook）；
     - 当 Part 启动，记录状态 `generating_part`，触发 `PartStarted`；
     - 当 Patch 到达，记录状态 `receiving_patch`，累积正文，触发 `PatchReceived`；
     - 当 Part 流结束，记录状态 `validating`，触发 `ValidationStarted`，执行 `PartGenerationValidator`；成功触发 `ValidationPassed`，失败触发 `ValidationFailed`；
     - 校验通过后，记录状态 `committing`，调用 `commitPartContent` 原子提交；提交成功触发 `PartCompleted` 并递增已完成计数；
     - 全部 Part 完成后，跃迁至 `completed`，触发 `GenerationCompleted`。
  3. `pauseGeneration(...)` / `resumeGeneration(...)` / `cancelGeneration(...)`：支持外部暂停、恢复与优雅取消。
  4. `recoverInterruptedGeneration(...)`：检索未处于终态的作业，重置底层任务依赖状态，迁移会话至 `recovering`，然后恢复调度。

### 4.4 控制器适配层 (Controller Layer)
新建 `lib/controllers/streaming_resource_generation_controller.dart`：
- 封装 UI 或工作台调用的门面，不耦合具体的 Flutter Widget，提供响应式状态暴露与操作命令入口（start / pause / resume / cancel / retry）。

---

## 5. 需要修改与新增的文件 (Files to Modify and Add)

### 新建文件
1. `docs/phase-06.1-analysis.md`（本文档）
2. `lib/domain/resources/streaming_generation_runtime_contracts.dart`（领域状态枚举、状态机、事件体系、运行时会话模型）
3. `lib/application/resources/streaming_generation_session_repository.dart`（运行时会话持久化仓储接口与实现）
4. `lib/application/resources/streaming_resource_generation_service.dart`（核心生成运行时编排服务）
5. `lib/controllers/streaming_resource_generation_controller.dart`（控制层门面与订阅管理）
6. `test/domain/resources/streaming_generation_runtime_contracts_test.dart`（状态机、事件与模型测试）
7. `test/application/resources/streaming_generation_session_repository_test.dart`（仓储增删查改与持久化测试）
8. `test/application/resources/streaming_resource_generation_service_test.dart`（正常流、异常流、补丁流、校验流、恢复流全覆盖测试）
9. `docs/phase-06.1-implementation-report.md`（实施总结与验收报告）

### 现有修改文件
1. `lib/services/database_service.dart`：
   - 增加 `createResourceGenerationSessionSchema` 表结构定义与索引，并接入 `createV36Schema`（或初始化 hook），确保全新安装与现有库均可安全建表。
2. `lib/application/resources/part_generation_coordinator.dart`：
   - 增加细粒度生命周期回调钩子（`onPartStarted`, `onPatchReceived`, `onValidationStarted`, `onValidationPassed`, `onValidationFailed`, `onPartCommitted`），使运行时层无需重写 Phase 5 的 DAG 调度与协议累加逻辑即可捕获事件并维护状态机。

---

## 6. 风险与兼容性考量 (Risks and Compatibility Considerations)

1. **契约层纯净性守护 (Contract Layer Purity)**：
   `lib/domain/resources/` 下所有新增文件绝不能引入 `dart:io`, `package:flutter`, `package:sqflite`, 或全量 JSON 序列化，确保通过 `resource_contract_layer_test.dart`。
2. **数据一致性与零重复提交**：
   - 继承 Phase 5 的独占租约机制与 `(resource_id, part_id)` 绑定；
   - 校验未通过的 Part 绝不触发 `commitPartContent`；
   - 已完成（`completed`）的 Part 绝不重复提交；
   - 运行时服务通过原子事务和状态机防卫，杜绝并发竞争。
3. **现有代码与测试完全兼容**：
   - `PartGenerationCoordinator` 的既有调用签名保持默认可选参数，所有 Phase 5 现有单测无需修改即可保持 100% 通过；
   - 不增加外部三方依赖；
   - 数据库操作保证幂等与向前兼容。
