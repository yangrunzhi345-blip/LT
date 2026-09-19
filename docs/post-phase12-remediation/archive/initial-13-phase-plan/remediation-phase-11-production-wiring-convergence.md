# Remediation Phase 11 — Production Wiring & Test Architecture Convergence

> **Root Cause**: RC-11
> **Findings**: M15 (MAJOR), TG11, TG12, TG14, C14
> **Depends On**: R01（启动恢复装配点）
> **Document status**: BLOCKED（等待 R01 ACCEPTED）

---

## 1. Purpose

测试存在与生产装配分叉的路径，导致“测试通过但生产行为不同”：

- CRUD 保存链（角色卡/世界观编辑）没有注入带 revision capture 的 `ResourceCreationPipeline`，
  覆盖已有资源不可恢复（M15）；
- 冒险启动链（`ChatProvider` → readiness gate）在所有测试里被 override，从未真实装配验证（TG11）；
- `import_use_cases` 的 `repository` 依赖是死参数，相关 `verifyNever` 恒真，提供“已验证未写旧表”的
  假象（TG12）；
- prompt 要求 `skill_used` / `level_up`，但没有任何 parser 消费（TG14）；
- `_buildDefaultReadinessGate` 未 `attachCompression`，与生产 gate 分叉（C14）。

本 Phase 修复的 contract 是：**“生产装配路径必须被至少一个使用同一装配（无 override）的测试覆盖；
测试使用的 fake 必须与生产实现语义一致；prompt 声明的每个字段必须有对应消费者。”**

## 2. Audit Findings Covered

```text
Primary:
- M15   CRUD 保存未接入 revision capture（生产装配分叉）

Related:
- TG11  冒险启动链未被真实装配覆盖
- TG12  import use-case 的 repository 死参数 + vacuous verifyNever
- TG14  prompt 声明 skill_used/level_up 但无 parser
- C14   默认 readiness gate 未 attachCompression（与生产分叉）
```

## 3. Current Production Architecture

### 3.1 装配点

```text
lib/providers/riverpod_providers.dart
  resourceCrudControllerProvider (:165-174)
      ResourceCrudController(repository: libraryRepoProvider, onLibraryChanged: ...)
      ← 未传 creationPipeline
  ResourceCrudController 构造默认 pipeline（resource_crud_controller.dart:58-72）
      ResourceCreationPipeline(getDb, hasAiCredentials)   ← 无 revisionCapture

  resourceStudioRuntimeProvider (:415-471)
      final pipeline = ResourceCreationPipeline(..., revisionCapture: revisionCaptureEngineProvider)  (:429-436)

  ChatProvider (:117-131) 通过 adventureProvider / readinessGate 启动冒险
  adventureReadinessGateProvider (:651)
  assemblyReadinessCompressionLinkProvider (:642-647) —— 生产在 main.dart:180-192 读取
  AdventureProvider._buildDefaultReadinessGate (:222-266) —— 未 attachCompression
```

### 3.2 导入用例

```text
lib/application/resource_library/import_use_cases.dart
  ImportConversationCharacterUseCase / ResourceCardImportUseCase / ImportWorldviewUseCase / SceneBatchImportUseCase
  均声明 final ILibraryRepository repository（:46/102/349/523），方法体不使用；保存走 LegacyCreationBridge
```

### 3.3 prompt 字段

```text
lib/engines/chat_engine_internals/prompt_builder.dart:152-153  "skill_used" / "level_up"
lib/config/app_config.dart:171                                  "skill_used"
lib/models/adventure_response.dart:_payloadKeys (:148-167)       不含 skill_used/level_up
lib/models/scene_dialogue_effects.dart                           无相关字段
level_up：由 chat_engine.dart:1962-1994 依据 EXP 本地计算
```

## 4. Exact Bugs

### Finding M15 — CRUD 保存绕过 revision capture

#### Trigger
通过 CRUD 路径编辑已存在的角色卡/世界观（`app_dialogs.dart`、`character_card_edit_page.dart`），
保存时覆盖已有内容。

#### Current Behavior
`resourceCrudControllerProvider` 构造 `ResourceCrudController` 时未注入带 `revisionCapture` 的 pipeline；
`ResourceCrudController` 用默认 pipeline（无 capture）。覆盖已有资源时
`ResourceCreationPipeline._captureRevisionBeforeOverwrite` 为 no-op，旧内容不被记录为 revision，
无法从历史恢复。

#### Expected Behavior
与 Studio 路径一致：覆盖已有资源前记录 revision，可恢复。

#### Evidence
```text
file: lib/providers/riverpod_providers.dart:165-174 vs :429-436
file: lib/controllers/resource_crud_controller.dart:58-72
file: lib/application/resources/resource_creation_pipeline.dart:86-89, 323-332
既有测试: 无“CRUD 覆盖后存在 revision”断言
```

#### User / Data Impact
CRUD 覆盖不可恢复（与产品承诺不一致）。

---

### Finding TG11 — 冒险启动链未被真实装配覆盖

#### Trigger
修改/断开 `riverpod_providers.dart:124` 的 `readinessGate:` 参数。

#### Current Behavior
所有涉及启动的 Widget 测试都 override `startAdventureWithConfig`（如
`test/widget/p0_adventure_wizard_start_boundary_test.dart:31`）或 override gate（:354），因此断开生产
装配不会有测试失败。生产“未就绪资源启动被 fail-closed 拦截”未被端到端证明。

#### Expected Behavior
至少一个测试使用真实 `ChatProvider` 装配（不 override `startAdventureWithConfig`）验证 readiness gate
被调用并 fail-closed。

#### Evidence
```text
file: lib/providers/riverpod_providers.dart:117-131, 124
file: lib/providers/chat_provider.dart:595-624
既有测试: test/widget/preset_scenes_start_navigation_test.dart:71, p0_preset_scenes_quick_start_test.dart:58,
         p0_adventure_wizard_start_boundary_test.dart:31,354（均 override）
```

#### User / Data Impact
生产 fail-closed 边界可能被无声破坏。

---

### Finding TG12 — import use-case 死参数与 vacuous 断言

#### Trigger
阅读/维护 `import_use_cases` 的测试。

#### Current Behavior
`repository` 字段在四个用例中声明但方法体从不使用；测试
`verifyNever(() => repository.saveCharacterCard(...))`（`test/unit/resource_import_semantics_test.dart:263,331`）
恒为真（生产代码从不调用该方法），造成“已验证不写旧表”的假保证；`scene_batch_*` 测试传入从不使用的
`_MockLibraryRepository`。

#### Expected Behavior
删除死参数；用真实断言证明内容写入树（`LegacyCreationBridge` / tree repository），而非依赖
“未调用某个方法”。

#### Evidence
```text
file: lib/application/resource_library/import_use_cases.dart:46,102,349,523
file: test/unit/resource_import_semantics_test.dart:263,331
file: test/unit/scene_batch_identity_test.dart:16,36
file: test/unit/scene_batch_generation_jobs_test.dart:14,36
```

#### User / Data Impact
维护性风险 + 假测试保证。

---

### Finding TG14 — prompt 字段无 parser

#### Trigger
模型返回 `{"skill_used":"fireball"}` / `{"level_up":true}`。

#### Current Behavior
两字段出现在 prompt（`prompt_builder.dart:152-153`、`app_config.dart:171`），但
`AdventureResponse` / `SceneDialogueEffects` 均无对应处理；模型浪费输出 token，应用忽略该信息
（`level_up` 由 EXP 本地计算）。

#### Expected Behavior
要么实现消费，要么从 prompt 移除；并新增“prompt 声明的字段必须有 parser”的契约测试。

#### Evidence
```text
file: lib/engines/chat_engine_internals/prompt_builder.dart:152-153
file: lib/config/app_config.dart:171
file: lib/models/adventure_response.dart:148-167, lib/models/scene_dialogue_effects.dart
```

#### User / Data Impact
token 浪费；prompt 与解析契约漂移（未来维护者会假设字段被处理）。

---

### Finding C14 — 默认 readiness gate 未 attachCompression

#### Trigger
任何未注入 `readinessGate` 的 `ChatProvider`/`AdventureProvider`（如测试或部分装配）。

#### Current Behavior
`AdventureProvider._buildDefaultReadinessGate`（`:222-266`）构造 `AssemblyReadinessCoordinator` 但不调用
`attachCompression`；OVERFLOW 资源会进入 `preparing` 但不会 enqueue 压缩任务，永远无法 ready。
生产通过 `main.dart:180-192` + `assemblyReadinessCompressionLinkProvider` 附加压缩。

#### Expected Behavior
fallback gate 要么也 attachCompression，要么在生产装配缺失时 fail-fast；测试若需要“未附加”行为
必须显式 opt-out。

#### Evidence
```text
file: lib/providers/adventure_provider.dart:222-266
file: lib/application/resources/assembly_readiness_coordinator.dart:71-90, 184-202
file: lib/main.dart:180-192, lib/providers/riverpod_providers.dart:642-647
既有测试: assembly_readiness_coordinator_test.dart:62-74 有意测试未附加的 fail-closed
```

#### User / Data Impact
非生产装配下 OVERFLOW 资源永久不可 ready（当前生产未走此路径，属潜伏分叉）。

## 5. Root Cause

**Symptom**：测试通过但生产行为不同；覆盖不可恢复；假测试保证。

**Root Cause**：同一能力存在**两条装配路径**（生产 provider 链 vs 测试 override / 默认构造），且没有
“装配一致性”这一层的测试。具体表现为：
- 同一 `ResourceCreationPipeline` 在两个 provider 中分别构造，参数不同（M15）；
- 启动链的测试全部 override 关键方法，等于测试了另一套装配（TG11）；
- 为测试保留的死参数与恒真断言掩盖了真实写入路径（TG12）；
- prompt 与 parser 之间没有契约测试（TG14）；
- fallback gate 与生产 gate 行为不同（C14）。

## 6. Required Contract After Remediation

1. `ResourceCreationPipeline` 只有一个构造装配源，Studio 与 CRUD 共用；覆盖已有资源必须记录 revision。
2. 冒险启动链必须有至少一个使用真实 `ChatProvider` 装配（不 override `startAdventureWithConfig`）的测试，
   验证 readiness gate 生效。
3. 导入用例不得保留死依赖；测试必须断言真实写入路径（树/bridge），而非恒真 `verifyNever`。
4. prompt 声明的每个字段必须有对应的解析/消费，或有契约测试证明“该字段被有意忽略”。
5. fallback readiness gate 与生产 gate 行为一致，或在缺失压缩时 fail-fast。
6. 不得改变公开 API 语义（删除死参数除外）。

## 7. Implementation Plan

### Step 1 — 单一 Pipeline 装配（M15）

```text
file: lib/providers/riverpod_providers.dart
```

- 抽出 `resourceCreationPipelineProvider`（Provider<ResourceCreationPipeline>），使用与 Studio 相同的
  参数（含 `revisionCapture: ref.read(revisionCaptureEngineProvider)`）。
- `resourceStudioRuntimeProvider` 改为 `ref.read(resourceCreationPipelineProvider)`。
- `resourceCrudControllerProvider` 构造 `ResourceCrudController` 时注入该 pipeline。

```text
file: lib/controllers/resource_crud_controller.dart
symbol: 构造函数 / 默认 pipeline (:58-72)
```

- 增加可选 `ResourceCreationPipeline? creationPipeline`（若尚未有）；生产 provider 注入；
  默认构造仅用于测试，保留但标注。

### Step 2 — 冒险启动装配级测试（TG11）

```text
Tests（新建）: test/application/adventure/production_adventure_start_wiring_test.dart
```

- 使用真实 `ProviderContainer`（参考 `test/unit/riverpod_and_providers_test.dart`）与真实 provider 链，
  不 override `startAdventureWithConfig`。
- 构造一个未 ready 的资源，断言启动被 readiness gate 拒绝（fail-closed）。
- 构造一个 ready 资源，断言可启动。
- 该测试必须在断开 `riverpod_providers.dart:124` 的 `readinessGate:` 后 FAIL（Mutation）。

### Step 3 — 导入用例死参数清理（TG12）

```text
file: lib/application/resource_library/import_use_cases.dart
symbol: 四个用例的 `final ILibraryRepository repository;`（:46/102/349/523）
```

- 删除字段与构造参数；更新所有调用点（`riverpod_providers.dart` 中对应的 use case provider）。
- 更新测试：移除 `_MockLibraryRepository` 与 `verifyNever(...)`，改为断言内容确实写入
  `LegacyCreationBridge`/tree（例如注入并 verify bridge 调用，或对真实 SQLite 断言 `resources` 行）。

### Step 4 — prompt 字段契约（TG14）

```text
Decision（推荐）: 删除 prompt 中 skill_used / level_up 指令
file: lib/engines/chat_engine_internals/prompt_builder.dart:152-153
file: lib/config/app_config.dart:171
```

理由：两字段当前无任何消费者；`level_up` 由 EXP 本地计算，技能无对应效果应用。删除可减少 prompt
膨胀与模型无效输出。

备选：实现消费（新增 `SceneDialogueEffects` 字段并应用）。若产品要求技能使用追踪，则必须实现完整
链路（解析 → 应用 → 展示），不得只加字段。

```text
Tests（新建）: test/engines/prompt_parser_contract_test.dart
```
- 枚举 prompt 中的 JSON key 声明，断言每个 key 要么在 `AdventureResponse._payloadKeys` /
  消费路径中，要么在显式“ignored keys”白名单中（白名单需为空或注释说明）。

### Step 5 — fallback gate 收敛（C14）

```text
file: lib/providers/adventure_provider.dart
symbol: _buildDefaultReadinessGate (:222-266)
```

- 方案 A：让 fallback gate 也 `attachCompression`（复用 compression coordinator provider）。
- 方案 B：构造 fallback gate 时要求显式传入“是否附加压缩”；生产/默认附加，测试可 opt-out。

推荐 A（与生产一致），除非存在无法注入依赖的循环；若存在循环，采用 B 并让测试显式 opt-out。

## 8. Design Decisions

### 8.1 M15 用“抽出共享 provider”还是“给 CRUD 单独传参”

**选择抽出共享 provider**。理由：杜绝第二条装配；CRUD 与 Studio 参数一致。**不采用单独传参。**

### 8.2 TG14 用“删除 prompt”还是“实现消费”

**推荐删除 prompt 指令**（除非产品要求技能追踪）。理由：无消费者的指令只会误导模型与维护者。
**不采用“只加字段不应用”。**

### 8.3 C14 用“附加压缩”还是“删除 fallback”

**选择附加压缩**（方案 A）。理由：保留 fallback 的可测试性，同时与生产一致。**不采用删除 fallback。**

## 9. Database Impact

```text
No schema change required.
```

不新增表/列，不修改 `schemaVersion`，不修改 migration。回滚为纯代码 revert。
（若 Step 4 选择“实现消费”，可能需要在 `SceneDialogueEffects` 上新增字段，但那是内存模型，仍无
schema 改动；若需持久化则属新功能，超出本 Program。）

## 10. Concurrency / Sequence

### 10.1 M15 修复后

```text
CRUD save(existing resource)
  → ResourceCrudController.save...(creationPipeline: shared)
  → ResourceCreationPipeline.create
       existing live → _captureRevisionBeforeOverwrite (now wired)
       update tree
       _captureRevisionAfterOverwrite
  → revision 可恢复
```

### 10.2 TG11 装配级测试

```text
ProviderContainer(real providers)
  ↓
ChatProvider.startAdventureWithConfig(unready resource)
  ↓
AdventureReadinessGate.enforceAndFreeze
  ↓
REJECT (fail-closed)   ← 断开 readinessGate: 后此断言必须失败
```

### 10.3 不变量

```text
不变量1: 覆盖已有资源的任何生产路径都记录 revision。
不变量2: 冒险启动必须经过 readiness gate。
不变量3: 测试不得依赖恒真的 verifyNever 代表写入正确性。
不变量4: prompt 声明的字段都有消费者或显式忽略记录。
```

## 11. Files Expected To Change

```text
Production（Expected）:
- lib/providers/riverpod_providers.dart
- lib/controllers/resource_crud_controller.dart
- lib/application/resource_library/import_use_cases.dart
- lib/engines/chat_engine_internals/prompt_builder.dart
- lib/config/app_config.dart
- lib/providers/adventure_provider.dart

Production（Possible）:
- lib/models/scene_dialogue_effects.dart（仅当选择实现 skill_used）
- 调用 import use-case 的 providers

Tests（Expected，新建）:
- test/application/adventure/production_adventure_start_wiring_test.dart
- test/application/resources/crud_revision_capture_wiring_test.dart
- test/engines/prompt_parser_contract_test.dart

Tests（Possible，更新）:
- test/unit/resource_import_semantics_test.dart
- test/unit/scene_batch_identity_test.dart
- test/unit/scene_batch_generation_jobs_test.dart
- test/widget/p0_adventure_wizard_start_boundary_test.dart

Docs:
- docs/post-phase12-remediation/STATUS.md

Forbidden / should not be touched:
- 流式会话生命周期/恢复（R01）
- 内容写入 CAS（R03）
- 软删除/恢复（R06）
- 传输超时/重试（R04）
- 不删除生产 provider（除本 Phase 明确的死参数）
```

## 12. Test Plan

### TEST R11-01（M15 CRUD revision）
```text
Given: 通过 resourceCrudControllerProvider 覆盖一个已有资源
When:  保存
Then:  存在覆盖前的 revision（可从历史恢复）
```

### TEST R11-02（TG11 启动装配）
```text
Given: 真实 ProviderContainer，未 override startAdventureWithConfig
When:  以未 ready 资源启动冒险
Then:  被 readiness gate 拒绝
       断开 riverpod_providers.dart readinessGate: 后该测试失败（Mutation）
```

### TEST R11-03（TG12 导入真实写入）
```text
Given: 导入一个世界观
When:  执行 use case
Then:  断言内容写入 LegacyCreationBridge / tree（真实路径）
       不再使用恒真 verifyNever
```

### TEST R11-04（TG14 prompt 契约）
```text
Given: prompt 构造器声明的 JSON key 集合
When:  与解析/消费路径比对
Then:  每个 key 都有消费者或在显式忽略白名单
```

### TEST R11-05（C14 fallback gate）
```text
Given: 未注入 readinessGate 的 AdventureProvider（fallback）
When:  OVERFLOW 资源触发 readiness
Then:  压缩被 enqueue（行为与生产 gate 一致），或显式 opt-out 时明确
```

## 13. Mutation / Negative Verification

```text
Mutation 1: 让 resourceCrudControllerProvider 不注入 creationPipeline
→ TEST R11-01 必须 FAIL

Mutation 2: 移除 riverpod_providers.dart:124 的 readinessGate:
→ TEST R11-02 必须 FAIL

Mutation 3: 恢复 import use-case 的死 repository 参数并让测试 verifyNever
→ TEST R11-03 必须 FAIL

Mutation 4: 恢复 prompt 中 skill_used/level_up 但不加消费者
→ TEST R11-04 必须 FAIL

Mutation 5: 让 fallback gate 不 attachCompression
→ TEST R11-05 必须 FAIL
```

## 14. Acceptance Criteria

```text
AC-R11-01 CRUD 覆盖已有资源产生 revision。
AC-R11-02 冒险启动链有真实装配测试；断开 gate 会使测试失败。
AC-R11-03 导入用例无死依赖；测试断言真实写入路径。
AC-R11-04 prompt 字段与解析契约一致（有消费者或显式忽略）。
AC-R11-05 fallback gate 与生产 gate 行为一致。
AC-R11-06 全量 flutter test 通过。
```

## 15. Required Verification Commands

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test test/application/adventure/production_adventure_start_wiring_test.dart
flutter test test/application/resources/crud_revision_capture_wiring_test.dart
flutter test test/engines/prompt_parser_contract_test.dart
flutter test test/unit/resource_import_semantics_test.dart
flutter test
git diff --check
git status --short
```

## 16. Out of Scope

- 不实现新功能（技能使用追踪属新功能，除非产品明确要求）；
- 不改对话/生成业务逻辑；
- 不重构 UI；
- 不删除生产 provider/页面（除本 Phase 的死参数）。

## 17. Rollback / Failure Safety

- 抽共享 provider 后若装配错误，测试（装配级）会失败；生产行为与 Studio 一致。
- 删除 prompt 指令只影响模型输出字段，不改变解析；若模型不再输出这些字段也无副作用（本就被忽略）。
- 删除死参数需同步更新测试，编译期即可发现遗漏。
- 回滚为纯代码 revert。

## 18. OPEN QUESTION

```text
Q1: 产品是否需要技能使用追踪（skill_used）？若需要，本 Phase Step 4 改为实现完整链路，并可能属于
    新功能（应移出本 Program）。需要产品确认。
Q2: `_buildDefaultReadinessGate` 附加压缩是否会造成 provider 循环依赖？需要检查
    compressionCoordinatorProvider / assemblyReadinessCoordinatorProvider 的依赖图。
Q3: CRUD 覆盖路径是否还有其他入口（例如批量导入覆盖）未走 ResourceCrudController？需要用 rg 全面
    搜索 `ResourceCreationPipeline(` 的全部构造点，确保只有一处生产装配。
```

## 19. Handoff Notes

- R01 必须已完成，本 Phase 的启动恢复接线与装配级测试基于 R01 抽出的 provider。
- R13 可评估删除 `_buildDefaultReadinessGate`（若确认无合法消费者）。
