# D0 Legacy Import Generation Authority Audit

Status: **FAILED**

审计日期：2026-09-20

审计类型：只读生产调用图与 Authority 审计

审计基线：`main@21df97d78dc04ecbbe3b466183fa2519dbd417da`

## 1. Baseline

| 项目 | 结果 |
| --- | --- |
| Branch | `main` |
| HEAD | `21df97d78dc04ecbbe3b466183fa2519dbd417da` |
| `origin/main` | `21df97d78dc04ecbbe3b466183fa2519dbd417da` |
| Ahead / Behind | `0 / 0` |
| Worktree | clean |
| Flutter | `3.44.8 stable` |
| Dart | `3.12.2 stable` |
| Database schemaVersion | `44`（`lib/services/database_service.dart:47`） |

本轮读取了 `docs/adaptive-resource-system/`、`docs/post-phase12-remediation/` 中与 Phase 3/4/5/6/11/12、R01/R04/R05/R06 相关的设计、实施与验收材料。文档只作为预期契约，最终裁决以当前生产代码、Provider composition root、调用方搜索和定向测试为准。

审计期间未修改 Dart 源码、测试、数据库 schema、migration 或 provider，也未执行格式化或实现性修复。

## 2. Executive Verdict

前置假设“Persistence / Creation Authority 已基本收敛，但 Generation Authority 仍存在 Legacy Import 与新 Runtime 双轨”只成立一部分。

已确认事实：

1. 生产 `ResourceCreationPipeline` 已收敛为单一 Provider 实例。Import、CRUD 和 Resource Studio 共享该 pipeline。
2. 新 Generation Runtime 已具备持久化 `StreamingGenerationSession`、`ResourceGenerationTask`、Attempt、Patch accumulator、Runtime validator、CAS/atomic commit、pause/resume/cancel/recovery。
3. `ImportWorldviewUseCase.generate()`、`ResourceCardImportUseCase.generate()`、`ImportConversationCharacterUseCase.generate()` 与 `SceneBatchImportUseCase.importSelected()` 当前没有生产调用链，因此不能仅凭方法存在将其判为 production-reachable legacy generation。
4. 生产仍未完全收敛：
   - Scene Batch 候选识别直接调用 `LlmGateway.identifyCharacterNames()`，没有 Runtime Task/Attempt/cancel/recovery。
   - Character Card 编辑页直接通过 `AdventureAiController` 调用旧结构化角色生成 API，没有进入 Generation Runtime。
   - Worldview、Character/NPC、Scene Batch 导入页面只创建 `CreationSession(planning)`，随后便把 controller/UI 标为 completed；生产代码没有继续执行 blueprint planning、confirm、GenerationSession creation 与 Runtime start。

因此当前架构应描述为：

> **Bottom-half convergence / top-half generation divergence and disconnection.**

底层 creation/persistence 与正式 Runtime 基础设施已经统一，但部分生产 AI 调用仍绕过 Runtime，旧 Import 页面则只接到了新链路的第一步。

## 3. Production Entry Inventory

| ID | 生产入口 | UI / Route 证据 | 当前入口动作 | 状态 |
| --- | --- | --- | --- | --- |
| ENTRY-01 | Worldview AI Import | `worldview_tab.dart:191-206` | `planWorldview()` | `PLANNING_ONLY` |
| ENTRY-02 | Character AI Import | `character_card_tab.dart:261-286` | `ResourceCardImportController.plan()` | `PLANNING_ONLY` |
| ENTRY-03 | NPC AI Import | 与 Resource Card 页面共用 | `ResourceCardImportController.plan()` | `PLANNING_ONLY` |
| ENTRY-04 | Scene Batch Character/NPC | `scene_batch_import_page.dart:52-73` | 先 `identify()`，再 `plan()` | `UNMANAGED_LLM + PLANNING_ONLY` |
| ENTRY-05 | Adventure Wizard Worldview | `adventure_wizard_screen.dart:953-974` | `planWorldview()` | `PLANNING_ONLY` |
| ENTRY-06 | Adventure Wizard Character | `adventure_wizard_screen.dart:1093-1116` | `ResourceCardImportController.plan()` | `PLANNING_ONLY` |
| ENTRY-07 | Resource Studio AI Create | `resource_studio_runtime.dart:177-212` | create → plan → confirm → start | `NEW_PATH` |
| ENTRY-08 | Character Card Editor AI assistant | `character_card_edit_page.dart:339-357` | `AdventureAiController.generate*` | `PRODUCTION_REACHABLE_LEGACY` |
| ENTRY-09 | Conversation-character legacy import | controller API exists | `generateConversationCharacter()` | `DEAD_IN_PRODUCTION` |

未发现 deep link、route 或后台 worker 直接调用 `Import*UseCase.generate()` / `save()`。Resource Library 的主“新建资源”入口已转向 Resource Studio 创建页面，但旧 AI Import 弹窗仍可从旧 Worldview/Character tab 和 Adventure Wizard 到达。

## 4. Production Call Graphs

### 4.1 Worldview AI Import

```text
WorldviewTab.showAiImport
  → WorldviewAiImportPage._generate                    worldview_ai_import_page.dart:174
  → ResourceLibraryImportController.planWorldview      resource_library_import_controller.dart:137
  → ImportWorldviewUseCase.plan                        import_use_cases.dart:338
  → LegacyCreationBridge.planAiCreation                legacy_creation_bridge.dart:99
  → ResourceCreationPipeline.create                    resource_creation_pipeline.dart:173
  → SQLite resource_creation_sessions(status=planning)
  → STOP
```

该页面在 `CreationSession` 建立后显示“已建立 AI 规划会话”，调用 `onChanged()` 并退出。它没有获得 `sessionId`，没有调用 `planWorldviewBlueprint()` 或 `confirmWorldviewBlueprint()`，也没有导航到 Resource Studio。

### 4.2 Character / NPC AI Import

```text
CharacterCardTab.showAiImport
  → ResourceCardAiImportPage._generate                 resource_card_ai_import_page.dart:237
  → ResourceCardImportController.plan                  resource_card_import_controller.dart:112
  → ResourceCardImportUseCase.plan                     import_use_cases.dart:96
  → LegacyCreationBridge.planAiCreation
  → ResourceCreationPipeline.create
  → SQLite resource_creation_sessions(status=planning)
  → STOP
```

Character 与 NPC 仅在 `ResourceType`、名称和页面参数上不同，均未进入 blueprint confirmation 或 generation runtime。

### 4.3 Scene Batch Import

候选识别路径：

```text
SceneBatchImportPage._identify                         scene_batch_import_page.dart:139
  → SceneBatchImportController.identify               scene_batch_import_controller.dart:46
  → SceneBatchImportUseCase.identify                   import_use_cases.dart:563
  → LlmGateway.identifyCharacterNames                  import_use_cases.dart:570
  → AiGeneratorLlmGateway.identifyCharacterNames       ai_generator_llm_gateway.dart:80
  → AiGeneratorService.identifyCharacterNames
  → LLM transport
```

候选确认后的路径：

```text
SceneBatchImportPage._import                           scene_batch_import_page.dart:173
  → SceneBatchImportController.plan                    scene_batch_import_controller.dart:99
  → SceneBatchImportUseCase.plan                       import_use_cases.dart:506
  → LegacyCreationBridge.planAiCreation
  → ResourceCreationPipeline.create
  → SQLite resource_creation_sessions(status=planning)
  → STOP
```

因此 Scene Batch 同时具有 unmanaged AI 前置调用和未完成的新 planning path。

### 4.4 Character Card Editor AI assistant

```text
CharacterCardEditPage AI action                        character_card_edit_page.dart:339
  → AdventureAiController.generateDetailedResourceCharacter / generateResourceCharacter
  → AdventureAiUseCase.generateDetailedResourceCharacter / generateResourceCharacter
  → LlmGateway.generateDetailedResourceCharacter / generateResourceCharacter
  → AiGeneratorService
  → Map result
  → CharacterCardGenerationDraft
  → Widget TextEditingControllers
  → 用户稍后点击保存
  → ResourceCrudController.saveCharacterCardDraft
  → ResourceCreationPipeline
  → ResourceTree
```

持久化最终经过 Pipeline，但生成阶段不具有 persisted Session/Task/Attempt、Patch protocol 或 Runtime recovery。

### 4.5 Resource Studio 正常新路径

```text
ResourceStudioRuntime.createAndStart                   resource_studio_runtime.dart:177
  → ResourceCreationPipeline.create
  → CreationSession(planning)
  → ResourceCreationPipeline.planAiSession
  → BlueprintPlanner.plan
  → LlmGateway.rawCompletion
  → BlueprintParser + BlueprintValidator
  → ResourceBlueprintRepository.saveBlueprint
  → ResourceCreationPipeline.confirmAiBlueprint
  → ResourceTree placeholders + GenerationTasks（事务）
  → StreamingResourceGenerationController.createSession
  → StreamingResourceGenerationSessionRepository.createSession
  → StreamingResourceGenerationController.start
  → StreamingResourceGenerationService.startGeneration
  → PartGenerationCoordinator.generateAllParts
  → PartGenerationTaskRepository.startAttempt
  → streaming/raw LLM completion
  → ModelGenerationPatchDecoder
  → GenerationPatchAccumulator
  → PartGenerationValidator
  → PartGenerationTaskRepository.commitPartContent（CAS + atomic commit）
  → StreamingGenerationSession.completed / failed
```

这条链是 D1 应复用的目标实现，不应另建第二套 Runtime。

### 4.6 Call Graph A–S 结果

| 问题 | Legacy Import `generate → Draft → save` | 当前 Import `plan` | Resource Studio Runtime |
| --- | --- | --- | --- |
| A. Production reachable | 否 | 是 | 是 |
| B. Test-only | generate/save 多数是 | 否 | 否 |
| C. 直接调用 LlmGateway | 是 | plan 本身否 | Blueprint/Coordinator 受控调用 |
| D. 经过 Pipeline | save 时是 | 是 | 是 |
| E. 创建 CreationSession | save 创建 manual session；generation 前无 | 是 | 是 |
| F. 经过 Blueprint | 否 | 生产未继续 | 是 |
| G. 创建 GenerationSession | 否 | 否 | 是 |
| H. 创建 GenerationTask | 否 | 否 | 是 |
| I. 创建 Attempt | 否 | 否 | 是 |
| J. 使用 Patch protocol | 否 | 否 | 是 |
| K. Runtime Validator | 否 | 否 | 是 |
| L. Commit owner | Bridge/Pipeline save | 尚无正文 commit | Task repository |
| M. ResourceTree writer | Pipeline/tree repository | 尚未创建 tree | Blueprint confirm + task commit |
| N. completed owner | Controller | Controller错误标记 | persisted Runtime |
| O. failed owner | Controller | Controller | persisted Runtime |
| P. retry owner | UseCase/AiGenerator | 无 generation retry | Runtime + transport 分层 |
| Q. background owner | Controller flag | 不适用 | Runtime service |
| R. cancel owner | callback fence | 无 generation | Runtime handle + persisted state |
| S. recovery owner | 无 | pending session无人消费 | startup Runtime recovery |

## 5. Legacy Generation Reachability Map

| Symbol | 直接 LLM | Legacy Draft | Production caller | 分类 | 证据 |
| --- | ---: | ---: | ---: | --- | --- |
| `ImportConversationCharacterUseCase.generate` | 是 | 是 | 否 | `DEAD` | `lib/` 只有 controller 调用，controller method 无 caller |
| `ImportConversationCharacterUseCase.save` | 否 | 是 | 否 | `DEAD` | controller save method 无 caller |
| `ResourceCardImportUseCase.generate` | 是 | 是 | 否 | `DEAD` | 生产页面已改调 `plan()` |
| `ResourceCardImportUseCase.save` | 否 | 是 | 否 | `DEAD` | 仅 legacy generate/review flow 可达 |
| `ImportWorldviewUseCase.generate` | 是 | 是 | 否 | `DEAD` | 生产页面已改调 `planWorldview()` |
| `ImportWorldviewUseCase.save` | 否 | 是 | 否 | `DEAD` | 仅 legacy review flow 可达 |
| `SceneBatchImportUseCase.importSelected` | 是 | 内部 items | 否 | `TEST_ONLY` | 当前生产页面调用 `plan()` |
| `SceneBatchImportUseCase._generateOne` | 是 | 内部 item | 否 | `TEST_ONLY` | 仅由 `importSelected()` 调用 |
| `SceneBatchImportUseCase.identify` | 是 | 否 | 是 | `PRODUCTION_REACHABLE` | Scene Batch Page → Controller |
| `AdventureAiUseCase.generateResourceCharacter*` | 是 | UI draft | 是 | `PRODUCTION_REACHABLE` | Character Card Editor |

### Adventure Wizard 中的旧分支

`_generateWorldviewWithAi()` 和 `_generateCharacterWithAi()` 内仍保留旧 direct LLM 代码，但当前控制流为：

1. API key 未配置时立即 return；
2. API key 已配置时执行 Import `plan()` 后立即 return；
3. 后续旧 direct LLM block 因此在所有布尔取值下均不可达。

这些分支属于 `DEAD_BY_CONTROL_FLOW`，不得误报为 production reachable；D1 后可在 reachability guard 保护下清理。

## 6. LLM Call-Site Inventory

| Call Site | Caller | Production | Runtime Managed | Retry Owner | Cancellation | Recovery |
| --- | --- | ---: | ---: | --- | --- | --- |
| `BlueprintPlanner → rawCompletion` | Resource Studio | 是 | Creation/Blueprint 管理；尚未有 GenerationSession | transport | `GenerationTaskHandle` | persisted CreationSession/Blueprint 可重新消费 |
| `PartGenerationCoordinator → streamPartGeneration/rawCompletion` | Streaming Runtime | 是 | 是 | Runtime part retry + transport retry | Runtime handle | persisted Session/Task recovery |
| `SceneBatchImportUseCase.identifyCharacterNames` | Scene Batch Page | 是 | 否 | transport | 无 handle；仅 callback fence | 无 |
| `AdventureAiUseCase.generateResourceCharacter*` | Character Card Editor | 是 | 否 | AiGenerator content + transport | Widget mounted 不是请求 cancel | 无 |
| `Import*UseCase.generate*` | tests / dead controller surface | 否 | 否 | AiGenerator + transport | 无 | 无 |
| `SceneBatchImportUseCase.generateSceneBatchCharacter` | tests | 否 | 否 | UseCase `maxItemAttempts` × transport | `isCancelled` 只在请求之间检查 | 无 |
| Adventure opening generation | Adventure Wizard | 是 | 非 Resource Import Runtime 范围 | Adventure subsystem | Adventure controller | 非本 D1 范围 |
| Compression `rawCompletion` | Compression Coordinator | 是 | Compression job runtime | Compression/transport | job ownership | persisted compression recovery |

本表把“模型调用是否经过统一 transport”与“业务 generation 是否由 Runtime 管理”区分开。统一 `LlmGateway` 本身不能证明 Session/Task/Attempt authority 已收敛。

## 7. Generation Authority Matrix

| Business Fact | Current Owner(s) | Persisted | Production Source | Desired Owner | Conflict |
| --- | --- | ---: | --- | --- | ---: |
| creation state | Pipeline；Import controller phase | Pipeline 是 | 两者 | CreationSession | 是 |
| planning state | CreationSession / Blueprint | 是 | Pipeline | Blueprint/Creation | 否 |
| generation state | Runtime；Character editor Widget/controller | Runtime 是，legacy 否 | 两者 | GenerationSession | 是 |
| current part | Runtime | 是 | Runtime | Runtime | 否 |
| task state | GenerationTask | 是 | Runtime | GenerationTask | 否 |
| attempt state | Attempt | 是 | Runtime | Attempt | 否 |
| progress | Runtime；legacy callback/UI | Runtime 是，legacy 否 | 两者 | Runtime-derived | 是 |
| retry | Runtime；AiGenerator content retry；dead Scene Batch loop | 混合 | 多层 | Runtime/defined transport layer | 部分冲突 |
| pause | Runtime | 是 | Studio | Runtime | 否 |
| resume | Runtime | 是 | Studio | Runtime | 否 |
| cancel | Runtime；controller `_generation` fence | Runtime 是，fence 否 | 两者 | Runtime | 是 |
| background | Runtime service；legacy controller boolean | Runtime 是 | 两者 | Runtime | 潜在 |
| recovery | Runtime | 是 | startup provider | persisted Runtime | 非 Runtime 路径缺失 |
| validation | Runtime validator；legacy guards/UI mapping | 混合 | 两者 | Runtime Validator | 是 |
| commit | Task repository；Pipeline manual save | 是 | 两种语义 | Runtime commit boundary | 是 |
| completed | Runtime session；Import controller phase | 混合 | 两者 | persisted Runtime | 是 |
| failed | Runtime session；Import controller error/phase | 混合 | 两者 | persisted Runtime | 是 |
| resource persistence | Pipeline/tree repository | 是 | 单一 composition root | Pipeline/tree repository | 否 |

只要同一个业务事实存在两个可写 owner，即构成 `AUTHORITY_CONFLICT`。本轮确认冲突集中在 generation lifecycle，而非最终 ResourceTree repository 的实例接线。

## 8. ImportController Findings

### 8.1 字段分类

| Controller 字段 | 分类 | Authority 结论 |
| --- | --- | --- |
| request/source/mode | `INPUT_STATE` | 合法 |
| `draft`, `progressStage`, `worldviewProgress`, `error` | `VIEW_STATE` / legacy draft | 不应定义业务终态 |
| `phase` | `AUTHORITATIVE_BUSINESS_STATE`（当前 UI 用法） | 与 Runtime/CreationSession 冲突 |
| `_generation` | `CALLBACK_FENCE` | 只阻止旧回调写 UI |
| `_runInBackground`, `_worldviewRunInBackground` | `LEGACY_GENERATION_STATE` | 不具备 persisted ownership |
| `_disposed` | `CALLBACK_FENCE` | 只保护 notifier 生命周期 |

### 8.2 `_generation` 的真实语义

`_generation` 在 reset、开始新动作和 dispose 时递增；异步回调只在 `_isCurrent(generation)` 为真时更新字段。它没有：

- 传给 `LlmGateway`；
- 调用 `GenerationTaskHandle.cancel()`；
- 取消 HTTP/SSE；
- 记录 Attempt；
- 阻止已经进入持久化边界的旧请求 commit。

因此它只是 **UI callback fencing**，不是 **generation attempt fencing**。

### 8.3 Dispose / reset

Controller dispose/reset 后，若底层 LLM 已启动，请求可以继续运行；只是返回值被 `_isCurrent()` 丢弃。当前 `generate()` 生产 caller 多数已消失，所以该风险主要影响未来误接线和 Scene identify/Character editor 等其他直连路径。

## 9. ImportUseCase Findings

`ResourceCardImportUseCase` 与 `ImportWorldviewUseCase` 同时公开两套语义：

```text
Legacy:
generate → Draft → save

New:
plan → CreationSession
planBlueprint → Blueprint
confirmBlueprint → ResourceTree placeholders + GenerationTasks
```

代码层存在 dual surface，但旧 `generate/save` 没有 production caller。因此本轮不把“API 存在”直接升级为 `DUAL_GENERATION_SEMANTICS` Blocker。

真正的生产缺口是：页面只调用 `plan()`。`pendingPlanningSessions()`、`planBlueprint()` 与 `confirmBlueprint()` 在 `lib/` 中没有页面、provider worker 或 startup consumer；当前完整消费链只在 `test/application/resources/creation_entry_points_test.dart` 中被手工串联。

这属于测试路径与生产路径错位：测试证明能力存在，但没有证明 production wiring 已交付。

## 10. Retry / Background / Cancel Findings

### 10.1 Runtime retry stack

```text
StreamingResourceGenerationService
  → PartGenerationCoordinator.generateAllParts(maxRetriesPerPart)
  → LlmGateway / streaming transport bounded retry
```

Runtime 每次 part attempt 都持久化 `attempt_id`，commit 时比对 current attempt 与 source token，旧 attempt 不能覆盖新 attempt。

### 10.2 Scene Batch legacy retry

```text
SceneBatchImportUseCase.importSelected
  → _generateOne(maxItemAttempts = 2)
  → gateway.generateSceneBatchCharacter
  → AiGenerator/transport retry
```

该乘法 retry stack 当前只由测试到达，不构成生产 `LEGACY_RETRY_AUTHORITY`，但若未来重新接线会立即重新引入多 owner。

### 10.3 Background ownership

- Runtime service 的 active runs、task handles 和 persisted sessions 不依附单一页面。
- Legacy controller 的 `runInBackground` / `detachWorldviewToBackground` 只是 boolean；不创建 persisted task，也不把 ownership 交给 app-level worker。
- 当前 Worldview 页面调用的是快速 `plan()` 而非旧生成，因此“后台运行”控件不再代表实际 Runtime background generation。

### 10.4 Cancel / recovery

- Runtime pause/cancel 会取消 task handle，并收敛 persisted task/session。
- `streamingGenerationRecoveryProvider` 在 `main.dart:196` 被启动，读取 interrupted sessions 并调用 `recoverInterruptedGeneration(autoResume: false)`。
- Scene identify 和 Character editor direct LLM 没有同等 cancel/recovery。

## 11. Validation & Completion Semantics

### Legacy Draft path

```text
LLM structured response
  → Map / Draft
  → CharacterCardGenerationGuard / WorldviewLengthGuard / ResourceIntegrityValidator
  → LegacyCreationBridge.save*
  → ResourceCreationPipeline(method=manual)
  → controller.phase = completed
```

### Runtime path

```text
LLM NDJSON/single response
  → ModelGenerationPatchDecoder
  → GenerationPatchAccumulator
  → sequence/cursor/identity checks
  → PartGenerationValidator
  → onBeforeCommit session state
  → commitPartContent(CAS + transaction)
  → task Attempt completed
  → persisted GenerationSession completed
```

### 当前 Import path

```text
ResourceCreationPipeline.create(method=aiReference)
  → CreationSession(planning)
  → controller.phase = completed
  → UI exits
```

因此当前明确存在：

```text
Import completed != Runtime completed
```

并且此处甚至尚未产生 AI 正文、GenerationTask 或 ResourceTree。

## 12. LegacyCreationBridge Findings

| Symbol / policy | 分类 | 说明 |
| --- | --- | --- |
| `saveWorldview` | `COMPATIBILITY + PURE_MAPPING` | legacy worldview row → tree draft/request |
| `saveCard` | `COMPATIBILITY + PURE_MAPPING` | legacy character/NPC row → tree draft/request |
| `saveCards` | `COMPATIBILITY + PERSISTENCE_POLICY` | 聚合 batch request，由 Pipeline 原子创建 |
| `_normalize` | `PURE_MAPPING` | 对齐 resource id，剔除 migration-only metadata |
| `_request` | `PURE_MAPPING` | 生成 manual creation request |
| `newOperationId` | `IDEMPOTENCY_POLICY` | 生成 operation identity |
| `_resolveOperationId` | `IDEMPOTENCY_POLICY` | fingerprint + latest session reuse |
| `planAiCreation` | `COMPATIBILITY` | 委托 Pipeline 建立 planning session |
| `planAiSession` | `COMPATIBILITY` | 委托 Pipeline/BlueprintPlanner |
| `confirmAiBlueprint` | `COMPATIBILITY` | 委托 Pipeline/BlueprintRepository |
| generation execution | 不拥有 | 无正文生成循环或 Attempt authority |

Bridge 不是 Generation Blocker。它是兼容 adapter，但并非完全无 policy：operation ID、request fingerprint 与 latest-session reuse 仍由它决定。D1 应保留并逐步变薄，不能在没有调用方迁移证明时整体删除。

## 13. Production Wiring Findings

### Pipeline

`resourceCreationPipelineProvider` 从 `_streamingGenerationInfrastructureProvider` 读取唯一 pipeline：

```text
_streamingGenerationInfrastructureProvider
  ├─ ResourceTreeRepositoryImpl
  ├─ PartGenerationTaskRepositoryImpl
  ├─ ResourceBlueprintRepositoryImpl
  ├─ ResourceCreationPipeline
  └─ PartGenerationCoordinator
```

`legacyCreationBridgeProvider`、`resourceCrudControllerProvider`、Import UseCases 与 `resourceStudioRuntimeProvider` 均复用这套 composition root。

### Runtime

`streamingGenerationSessionRepositoryProvider` 与 `streamingResourceGenerationServiceProvider` 是生产共享实例。Resource Studio 与 Section regeneration 复用同一个 streaming controller/service/event stream，没有发现第二套正式 Runtime infrastructure。

### Import

Import provider 注入的 Pipeline 与 Gateway 都正确；问题不是 provider 构造了错误实例，而是 production caller 只调用 `plan()` 或直接调用 Gateway，没有消费完整 Runtime API。

## 14. Architecture Contract Results

| Contract | Result | Evidence / reason |
| --- | --- | --- |
| AC-01 AI Import 不直接调用 unmanaged LLM generation | **FAIL** | Scene Batch `identifyCharacterNames` |
| AC-02 所有 production generation 都有 persisted Session/Task/Attempt | **FAIL** | Character editor、Scene identify |
| AC-03 ImportController 不拥有 authoritative generation state | **FAIL** | controller `phase=completed` 与 persisted state 分叉 |
| AC-04 ImportUseCase 不拥有 AI generation retry authority | **PASS（当前生产）** | Scene Batch loop 当前 test-only |
| AC-05 ImportUseCase 不通过 AI Draft 定义 authoritative completion | **PASS（当前生产）** | Draft path dead；但 planning completion 仍失败 |
| AC-06 Runtime 是 retry/pause/resume/cancel/recovery 唯一业务 Authority | **FAIL** | unmanaged 生产 LLM 路径不受 Runtime 管理 |
| AC-07 restart 只根据 persisted Runtime state 恢复 generation | **PASS for Runtime / FAIL globally** | unmanaged 路径无法恢复 |
| AC-08 Legacy attempt/response 无法污染当前 generation | **UNKNOWN** | legacy imports dead；editor 没有 Attempt fence |
| AC-09 Pipeline 是唯一 creation/persistence authority | **PASS** | 单一 provider/composition root 已证明 |
| AC-10 Production Import 页面不存在绕开 Runtime 的 generation path | **FAIL** | Scene identify 绕过；其他 Import 停在 Runtime 之前 |

## 15. Findings

### BLOCKER

#### B1 — Scene Batch 存在 production-reachable unmanaged LLM call

等级：`BLOCKER`

问题：

Scene Batch 页面直接执行 AI 候选识别，绕过 GenerationSession、GenerationTask、Attempt、Patch、Runtime Validator 与 Runtime Recovery。

位置：

- 文件：`lib/screens/resource_library/scene_batch_import_page.dart`
- 方法：`_SceneBatchImportPageState._identify`（`:139-159`）
- 文件：`lib/controllers/scene_batch_import_controller.dart`
- 方法：`SceneBatchImportController.identify`（`:46-66`）
- 文件：`lib/application/resource_library/import_use_cases.dart`
- 方法：`SceneBatchImportUseCase.identify`（`:563-578`）
- 代码路径：Page → Controller → UseCase → `LlmGateway.identifyCharacterNames`

触发条件：

用户打开“批量 AI 导入角色/NPC”，输入非空文本并执行识别。

实际影响：

请求没有持久 Task/Attempt、真正的 cancellation handle、attempt fencing 或 crash recovery。页面/controller 被销毁只会丢弃返回 callback，不能终止模型请求。App restart 后无法判断请求是否已开始、失败或应恢复。

根因分析：

候选识别仍被建模为 UI 前置辅助调用，而不是生成 workflow 的 persisted planning/task 阶段。

修复方案：

优先将候选识别合并进 Blueprint planning，由现有 Blueprint/Runtime 一次性生成稳定候选与 parts。若交互确实要求先选候选，则应把 identification 表达为现有 Runtime 可持久化的明确 task，而不是另建第二套 service/state machine。

验证方式：

增加 production Widget + ProviderContainer + SQLite 测试：点击识别后必须产生可审计 persisted workflow；覆盖运行中 cancel、controller dispose、App restart、迟到 response 与第二次识别替代第一次的场景。

---

#### B2 — 三类生产 Import 只创建 planning session，却宣告 completed

等级：`BLOCKER`

问题：

Worldview、Character/NPC 和 Scene Batch 页面只执行 `plan()`。生产中没有 caller 执行 `planBlueprint()`、`confirmBlueprint()`、创建 `StreamingGenerationSession` 或启动 Runtime，但 controller 将状态置为 completed，UI 显示“已建立 AI 规划会话”并退出。

位置：

- `lib/screens/resource_library/worldview_ai_import_page.dart:_generate`（`:174-215`）
- `lib/screens/resource_library/resource_card_ai_import_page.dart:_generate`（`:237-289`）
- `lib/screens/resource_library/scene_batch_import_page.dart:_import`（`:173-212`）
- `lib/controllers/resource_library_import_controller.dart:planWorldview`（`:137-151`）
- `lib/controllers/resource_card_import_controller.dart:plan`（`:112-127`）
- `lib/controllers/scene_batch_import_controller.dart:plan`（`:99-117`）
- 代码路径：Page → Controller.plan → UseCase.plan → Bridge → Pipeline → `CreationSession(planning)` → STOP

触发条件：

用户从任一旧 AI Import 页面或 Adventure Wizard 的 AI worldview/character 操作提交有效输入。

实际影响：

数据库留下 pending planning session，但没有 Blueprint、ResourceTree、GenerationTask、GenerationSession 或最终资源。UI completion 与 persisted业务状态矛盾；`onChanged()` 刷新资源库也不会出现已生成资源。Runtime startup recovery 只处理 streaming generation sessions，无法自动推进这些 planning sessions。

根因分析：

Phase 4 为 UseCase/Controller 增加了完整 planning/confirm API，测试也手工串联了它们，但生产页面只迁移了第一步。实现测试证明“各 API 可组合”，没有证明“生产 caller 实际完成组合”。

修复方案：

将 Import caller 迁移到现有 `StreamingResourceStudioRuntime.createAndStart` 等价 orchestration。可增加薄 application adapter 接收 Import request 并调用现有 create → plan → confirm → session → start；不得复制 GenerationSession/Task/Attempt/Patch/Validator/Commit/Recovery。

验证方式：

从真实页面发起操作，使用 production providers 与 SQLite，断言 CreationSession、Blueprint、GenerationTasks、StreamingGenerationSession 和 Attempt 依次产生；只有 persisted Runtime terminal `completed` 才允许 UI 显示完成。失败、取消和 restart 必须从持久化状态恢复显示。

---

#### B3 — Character Card Editor AI generation 绕过 Runtime

等级：`BLOCKER`

问题：

角色卡编辑器通过 `AdventureAiController` 直接调用 legacy structured generation API，把 Map 结果映射到 Widget 表单字段。生成阶段没有进入 Resource Generation Runtime。

位置：

- `lib/screens/resource_library/character_card_edit_page.dart`，AI action（`:339-359`）
- `lib/controllers/adventure_ai_controller.dart`，`generateResourceCharacter` / `generateDetailedResourceCharacter`
- `lib/application/adventure/adventure_ai_use_case.dart`（`:197-242`）
- `lib/application/llm/ai_generator_llm_gateway.dart`（`:35-65`）
- 代码路径：Editor → AdventureAiController → AdventureAiUseCase → LlmGateway → AiGeneratorService → Widget draft

触发条件：

用户在 Resource Library 的角色卡编辑页面使用 AI assistant 生成或补全角色。

实际影响：

生产资源生成存在第二 Authority。请求没有 persisted progress、Attempt fencing、Patch validation、Runtime cancel/recovery；手动编辑与迟到 AI response 的并发也不受 Resource Task source-token CAS 保护。

根因分析：

该页面沿用了 Adventure Wizard 的辅助结构化生成接口，并把“生成草稿”视作纯 UI 行为；最终保存虽经过 Pipeline，但生成 lifecycle 与 Runtime 脱节。

修复方案：

把 AI 重写/补全表达为现有资源的 Runtime regeneration/edit workflow，复用 GenerationTask、Attempt、Patch、validator、revision 和 commit boundary。若需要用户先审阅，审阅内容仍应绑定 persisted attempt，不应退回无身份 Map callback。

验证方式：

增加 production editor 测试：AI 操作必须创建 persisted Attempt；在请求期间进行 manual edit，旧 attempt commit 必须因 source token 变化而拒绝；覆盖 cancel、dispose、restart 与迟到 response。

### MAJOR

无额外独立 MAJOR。为避免重复计数，controller false completion、unmanaged background、缺 recovery 和 dual authority 的具体后果均归入上述三个根因。

### MINOR

无。

### INFO

#### I1 — Dead legacy generation APIs 仍扩大未来误接线风险

等级：`INFO`

问题：

Import UseCases 与 Controllers 仍公开 legacy `generate → Draft → save`、background flag 和 review state，当前虽无生产 caller，但 provider 仍构造这些对象并注入真实 Gateway。

位置：

- `lib/application/resource_library/import_use_cases.dart`
- `lib/controllers/resource_library_import_controller.dart`
- `lib/controllers/resource_card_import_controller.dart`
- `lib/controllers/scene_batch_import_controller.dart`

触发条件：

未来页面、route 或重构重新调用这些现成 public methods。

实际影响：

无需新增基础设施即可重新引入 legacy generation/retry/background authority，且静态类型不会阻止误接线。

根因分析：

迁移采用“新增 plan API、保留旧 API”方式，但尚未完成 caller convergence 与 removal proof。

修复方案：

D1 caller 全部迁移并建立 architecture guard 后，再 deprecated/remove legacy methods 和 Draft types；不能在生产 convergence 前先删兼容 Bridge。

验证方式：

增加 architecture test，扫描 production `lib/` caller，禁止 Import 页面/Controller 调用 legacy generation symbols；mutation 将任一页面改回 legacy call 时测试必须失败。

## 16. Migration Candidate Matrix

| Symbol | Current Role | Production Reachable | Target | Action |
| --- | --- | ---: | --- | --- |
| `ImportWorldviewUseCase.generate/save` | legacy generation/draft persistence | 否 | Runtime | `DEPRECATE_AFTER_MIGRATION` |
| `ResourceCardImportUseCase.generate/save` | legacy generation/draft persistence | 否 | Runtime | `DEPRECATE_AFTER_MIGRATION` |
| `ImportConversationCharacterUseCase.generate/save` | legacy conversation import | 否 | Runtime 或明确移除功能 | `DELETE_AFTER_PROOF` |
| `SceneBatchImportUseCase.identify` | unmanaged AI preprocessing | 是 | Blueprint/Runtime task | `MIGRATE_CALLERS` |
| `SceneBatchImportUseCase.importSelected` | legacy batch generation | test-only | Runtime | `DEPRECATE_AFTER_MIGRATION` |
| `SceneBatchImportUseCase._generateOne` | legacy retry loop | test-only | Runtime | `DELETE_AFTER_PROOF` |
| Character editor direct AI calls | unmanaged resource generation | 是 | Runtime regeneration | `MIGRATE_CALLERS` |
| Adventure Wizard unreachable old branches | dead direct generation | 否 | none | `DELETE_AFTER_PROOF` |
| `LegacyCreationBridge` | mapping/idempotency compatibility | 是 | thin adapter | `KEEP_AS_ADAPTER` |
| `ResourceCreationPipeline` | creation/persistence authority | 是 | same | `DO_NOT_TOUCH` |
| GenerationSession/Task/Attempt/Patch/Validator/Commit | generation authority | 是 | same | `DO_NOT_TOUCH` |

## 17. D1 Exact Implementation Plan

# D1 — Generation Authority Convergence

D1 的唯一目标是：

> 让所有 production AI resource/import generation 进入现有 Generation Runtime，而不是重新实现 Runtime。

### D1-1 — Import orchestration convergence

| 项目 | 要求 |
| --- | --- |
| Files | 三个 Import pages/controllers/use cases；现有 Resource Studio application adapter；provider wiring tests |
| Current behavior | 页面只调用 `plan()` 并退出 |
| Required behavior | create → plan blueprint → confirm → create GenerationSession → start Runtime |
| Caller migration | Worldview、Character、NPC、Scene Batch、Adventure Wizard import actions |
| Tests affected | creation entry、production wiring、navigation、recovery、controller state tests |
| Risk | 重复 session、旧 pending session、页面退出后的 ownership、错误 UI completion |
| Rollback | 保留 persisted planning session；失败不得删除 reference/session；可由 Studio 继续消费 |

实施要求：

1. 提取或复用一个 production application orchestration boundary，避免页面自己拼接 5 个调用。
2. 返回稳定的 `sessionId/resourceId`，页面导航到 Studio 或绑定 persisted session 状态。
3. Controller `completed` 必须由 Runtime persisted terminal state 派生。
4. 对现存 pending planning sessions 提供可发现、可继续的消费入口，不能清库。

### D1-2 — Scene Batch identification convergence

| 项目 | 要求 |
| --- | --- |
| File | `scene_batch_import_page.dart`, `scene_batch_import_controller.dart`, `import_use_cases.dart` |
| Current behavior | identify 直接调用 Gateway，候选仅在内存 |
| Required behavior | identification 合并进 Blueprint，或成为 existing Runtime 的 persisted task |
| Caller migration | `_identify()` 不再直接触达 unmanaged Gateway |
| Tests affected | scene batch identity/jobs + production UI/runtime tests |
| Risk | stable candidate ID、用户选择与 Blueprint part identity 对齐 |
| Rollback | 保留原 reference text 和 planning session；取消不删除用户输入 |

优先方案是让 Blueprint planning 返回可选择的候选/parts，避免新建“识别 Runtime”。若产品必须先识别后选择，则需要在现有 task/session 模型中明确这一阶段并持久化。

### D1-3 — Character editor AI convergence

| 项目 | 要求 |
| --- | --- |
| File | `character_card_edit_page.dart` 及现有 section regeneration/runtime adapter |
| Current behavior | direct Adventure AI API → Widget form |
| Required behavior | existing resource Runtime regeneration/edit attempt |
| Caller migration | 移除 editor 对 `AdventureAiController.generateResourceCharacter*` 的依赖 |
| Tests affected | editor Widget、part CAS/revision、runtime cancel/recovery |
| Risk | legacy character JSON 与 resource part tree 映射、审阅体验 |
| Rollback | AI 前 revision 必须可恢复；失败不覆盖手动字段 |

### D1-4 — Legacy API convergence and cleanup

| 项目 | 要求 |
| --- | --- |
| Current behavior | public legacy generate/save/retry APIs 保留 |
| Required behavior | 无 production caller；加 deprecation/guard；随后独立 cleanup |
| Tests affected | architecture reachability guard、legacy fixture compatibility |
| Risk | 隐藏 route/dynamic caller、测试 helper 被误当生产 |
| Rollback | 删除拆成独立 commit；Bridge 与 migration mapper 保留 |

### D1 实施顺序

1. 先建立 production reachability/negative architecture tests。
2. 接通 Import orchestration 与 persisted UI state。
3. 收敛 Scene Batch identification。
4. 收敛 Character editor AI generation。
5. 跑 recovery/cancel/stale-attempt tests。
6. 证明 zero production callers 后，另提交 legacy surface cleanup。

## 18. Required Tests / Mutation Tests

### Production integration tests

1. Worldview Import：真实页面提交后依次存在 CreationSession、Blueprint、GenerationTasks、GenerationSession、Attempt 和 committed ResourceTree。
2. Character Import：同上，并验证 ResourceType/metadata/mode。
3. NPC Import：多 part/task 身份稳定，最终资源可从 Resource Library 读取。
4. Scene Batch：候选识别属于 persisted workflow；候选选择不会丢失 identity。
5. 页面关闭：Controller/Widget dispose 后任务仍由 Runtime 拥有；重新进入可观察进度。
6. Restart：中断 session 由 startup recovery 收敛为 recovering，用户可继续。
7. Cancel：运行中 cancel 取消 transport，task/session 收敛；迟到 patch 不得提交。
8. Request switch：请求 A 晚于请求 B 返回时，A 的 attempt token 不能覆盖 B。
9. Character editor：manual edit 与 AI attempt 交错时，source-token CAS 拒绝 stale commit。
10. Completion：UI 只有在 persisted Runtime `completed` 后显示成功。

### Negative / mutation tests

| Mutation | 必须失败的测试 |
| --- | --- |
| Import page 改回 `UseCase.generate()` | production reachability guard |
| Scene Batch 恢复 direct `identifyCharacterNames` | unmanaged Gateway guard |
| orchestration 跳过 `confirmBlueprint` | production end-to-end |
| orchestration跳过 GenerationSession | persisted lifecycle assertion |
| coordinator 跳过 `startAttempt` | Attempt/commit contract test |
| controller 在 `plan()` 后直接 completed | completion semantics test |
| 移除 attempt/source-token CAS | stale response concurrency test |
| recovery provider 不扫描 interrupted sessions | restart recovery test |
| Character editor 重新调用 Adventure AI API | editor authority guard |

### 现有测试缺口

`creation_entry_points_test.dart` 当前手工执行 `plan → planBlueprint → confirmBlueprint`，证明 API 能力，但没有从 production Widget 或 route 发起。D1 必须新增 production-shape test，而不是只扩展现有 UseCase test。

## 19. Files Expected To Change In D1

预期变更范围：

- `lib/screens/resource_library/worldview_ai_import_page.dart`
- `lib/screens/resource_library/resource_card_ai_import_page.dart`
- `lib/screens/resource_library/scene_batch_import_page.dart`
- `lib/screens/resource_library/character_card_edit_page.dart`
- `lib/controllers/resource_library_import_controller.dart`
- `lib/controllers/resource_card_import_controller.dart`
- `lib/controllers/scene_batch_import_controller.dart`
- `lib/application/resource_library/import_use_cases.dart`
- `lib/features/resource_studio/application/use_cases/resource_studio_runtime.dart` 或同层薄 orchestration adapter
- `lib/providers/riverpod_providers.dart`（仅复用/暴露 orchestration 所需的最小 wiring）
- production path / recovery / cancellation / architecture guard tests
- 本文档（若实施事实与计划发生变化）

是否修改 `legacy_creation_bridge.dart` 应由 caller migration 的具体适配需求决定；不得为了“变薄”而提前删除 idempotency policy。

## 20. Files That Must NOT Be Changed In D1

除非实施过程中发现独立、可证明的现有契约缺陷并重新评审范围，否则 D1 不得重写或扩展：

- `resource_generation_patch.dart` 与 Patch protocol version；
- `GenerationPatchAccumulator`；
- `PartGenerationValidator`；
- `PartGenerationTaskRepositoryImpl` 的 Attempt、source-token CAS 与 atomic commit；
- `StreamingGenerationSessionRepositoryImpl`；
- startup Runtime recovery 基础设施；
- SQLite schemaVersion、migration 和历史 fixture；
- `ResourceCreationPipeline` 的单一 creation authority；
- Legacy migration mapper/decoder 与历史序列化兼容；
- Adventure narrative/opening generation runtime；
- Compression runtime。

D1 不得通过新增另一套 Import-specific GenerationSession、retry manager、background worker 或 recovery table 解决问题。

## 21. Final Verdict

### 1. 当前是否存在 production-reachable Legacy Import Generation？

传统的 `ImportUseCase.generate → Draft → save` 链当前没有生产 caller，因此答案是：**该特定旧链不可达**。

但仍存在 production-reachable unmanaged AI resource/import calls：

- Scene Batch candidate identification；
- Character Card Editor AI generation。

### 2. 哪些具体入口仍能绕过 Generation Runtime？

1. `SceneBatchImportPage._identify → SceneBatchImportUseCase.identify → LlmGateway.identifyCharacterNames`。
2. `CharacterCardEditPage → AdventureAiController → AdventureAiUseCase → LlmGateway.generate*ResourceCharacter`。

其余旧 Import 页面不是完整走 Runtime，而是停在 Creation planning。

### 3. 当前是否存在两个 Generation Authority？

**是。** 正式 Streaming Runtime 与 direct Gateway/UI-draft generation 并存。Import controller 还以本地 `phase` 独立定义完成/失败，形成 lifecycle authority conflict。

### 4. Creation/Persistence Authority 是否已经基本收敛？

**是。** `resourceCreationPipelineProvider` 是生产单一构造源，Bridge、CRUD、Import 与 Studio 共享 pipeline/tree infrastructure。未发现 production direct SQLite resource write 绕过该 boundary。

### 5. Retry Authority 是否重复？

当前生产 Import 主链未发现 ImportUseCase retry 与 Runtime retry 相乘，因为 Scene Batch `_generateOne` 已是 test-only。正式 Runtime 与 transport/content retry 仍有分层 owner。若 legacy `importSelected()` 被重新接线，将恢复 UseCase × transport 的乘法 retry 风险。

### 6. Background generation 是否由 Runtime 持久管理？

正式 Studio generation：**是**。

Scene identify、Character editor direct generation 与 legacy controller background flags：**否**。

### 7. App restart 能否恢复旧 Import generation？

**不能。** 旧 Draft/direct requests 没有 persisted Runtime state。当前 Import 创建的 planning session会保留，但没有生产 consumer 自动推进它；startup recovery 只恢复 streaming generation sessions。

### 8. LegacyCreationBridge 是 Blocker、兼容层还是两者兼有？

**兼容层，不是 Generation Blocker。** 它拥有 legacy DTO mapping、operation ID 与 fingerprint/idempotency reuse policy，并把持久化委托给唯一 Pipeline；它不拥有正文 generation loop、Task、Attempt 或 retry。D1 应保留为 thin adapter，待 caller convergence 后再评估 cleanup。

### Overall Result

**FAILED — 禁止宣告 Generation Authority 已收敛。**

D1 必须优先完成 production caller convergence，复用现有 Runtime，并以真实页面到 SQLite terminal state 的 production-path tests 作为验收证据。

## Verification Record

实际运行：

```text
flutter test \
  test/application/resources/creation_entry_points_test.dart \
  test/application/runtime/r05_production_wiring_test.dart \
  test/application/resources/production_streaming_recovery_wiring_test.dart \
  test/unit/scene_batch_identity_test.dart \
  test/unit/scene_batch_generation_jobs_test.dart
```

结果：`37 passed, 0 failed`。

该结果证明现有 pipeline/runtime/recovery 能力和测试内手工组合成立，但不能推翻本报告的 production reachability finding：完整 Import blueprint/runtime 消费链只在测试中被调用，生产页面没有等价调用。

未运行全量 `flutter test` 或 `flutter analyze`：本轮是只读、无源码变更的定向架构审计；静态调用图与 production wiring 是主要证据，定向测试只用于验证既有 Runtime 与测试装配行为。
