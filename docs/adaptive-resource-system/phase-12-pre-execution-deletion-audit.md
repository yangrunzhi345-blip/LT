# Phase 12 Pre-Execution Deletion Audit

本文件是 Phase 12（旧系统删除与总回归）的**执行前只读审计报告**。审计过程未删除任何文件、未修改任何生产代码/测试/配置/数据库，唯一新增文件为本报告。

---

## 1. Audit Baseline

| 项目 | 值 |
| --- | --- |
| Date | 2026-09-19 |
| Branch | `main` |
| HEAD | `6caa76a1ed67f7ec2eb7b61d56e114ef4a750461` |
| HEAD message | `chore(skills): add dart and flutter agent skills with lockfile` |
| origin/main | `6caa76a1ed67f7ec2eb7b61d56e114ef4a750461` |
| Ahead / Behind (`origin/main...HEAD`) | `0 / 0` |
| Worktree state | clean（无 staged、无 modified、无 untracked） |
| `git fetch origin main` | 已执行；本地与远端一致 |
| `git diff --check` | clean |

**采用的 baseline：** 上述 HEAD（`6caa76a`）的干净工作区。审计未执行 pull / merge / rebase / reset / clean / checkout，未改动任何用户未提交内容。

### 相关 Phase 12 文档

- `docs/adaptive-resource-system/phase-12-legacy-removal.md`（Phase 12 执行方案与删除候选清单）
- `docs/adaptive-resource-system/STATUS.md`（执行状态与阶段交接）
- `docs/adaptive-resource-system/README.md`（阶段索引、跨阶段硬约束）
- `docs/adaptive-resource-system/phase-00-architecture-contract.md` … `phase-11-final-independent-acceptance.md`（Phase 0–11 契约与验收）
- `AGENTS.md`、仓库根 `README.md`

### 文档漂移（已记录，未修改文档）

1. `STATUS.md:14` 记录 `Current Repository HEAD = e51f31c…`（Phase 11 验收基线），但实际 HEAD 为 `6caa76a`。实际 HEAD 是 Phase 11 `ACCEPTED` 之后的非功能性 `chore(skills)` 提交，二者不相冲突，但 STATUS 未同步。
2. `STATUS.md:11-13` 记录 Phase 11 `ACCEPTED`、Phase 12 `UNBLOCKED/NOT_STARTED`，与实际代码状态一致。
3. **实际情况与 `phase-12-legacy-removal.md` 第 5 节“重点候选”存在冲突**：该文档列出的 `worldview_ai_import_page.dart`、`resource_card_ai_import_page.dart`、`DetailedWorldviewGenerationCoordinator`、`DetailedCharacterGenerationCoordinator`、`ResourceLibraryImportController`、`ILibraryRepository` 旧方法等，经审计**仍有生产入口或仍被测试契约覆盖**（详见 §7、§8）。按审计规则，代码 + 已验收架构契约优先于旧 Phase 规划；执行 Agent **不得**按 `phase-12-legacy-removal.md` 的候选清单直接删除。

---

## 2. Audit Scope

实际检查范围：

- 全仓 `lib/`（332 个 Dart 文件，约 100,785 行）与 `test/`（171 个 Dart 文件，约 52,832 行）的引用关系。
- 生产可达性：以 `lib/main.dart` 为根做 `import/export` 传递闭包，找出不被应用入口可达的 lib 文件。
- 孤儿文件：反向 import 映射 + 顶层符号全仓引用（含 `test/`、`benchmark/`）。
- 动态引用排查：`part` / `part of`、`export` barrel、`flutter build_runner`（无 `.g.dart`/`.freezed.dart`）、平台目录（android/ios/linux/windows/macos/web）、route 表（`AppRouter.onGenerateRoute`）、Provider 注册、`@pragma('vm:entry-point')`、字符串路由名。
- Phase 12 文档点名的候选逐一验证（worldview/character import 页、coordinator、import controller、`ILibraryRepository`、`DatabaseService` 静态 legacy 包装、`LlmTask`、`WorldviewDetails.moduleKeys`）。
- 数据库与迁移：schema 版本、migration chain、legacy 表、只读兼容读取路径、迁移测试。
- 依赖与资源：`pubspec.yaml`、`assets/`、`pubspec.lock`。
- 标记扫描：`TODO|FIXME|deprecated|obsolete|temporary|legacy`，仅作为线索。

**未纳入范围：** 未执行任何构建产物（`build/`）、未修改依赖、未运行 `pub get`、未运行平台构建。

---

## 3. Current Validation

在只读前提下于 baseline `6caa76a` 运行：

```text
dart format --output=none --set-exit-if-changed .   : PASS（504 files, 0 changed）
flutter analyze                                     : PASS（No issues found, 1.6s）
Phase 12 targeted tests                             : N/A（仓库未提供 Phase 12 定向测试命令）
flutter test                                        : PASS（1600 passed / 0 failed / 0 skipped）
git diff --check                                    : PASS（clean）
```

补充只读验证：

```text
dart analyze --format=machine lib test              : 无任何诊断输出（含 info/hint）
```

说明：本次环境可正常执行 `flutter test` 全量（1600 passed），与 Phase 11 最终验收记录（1600 passed / 0 failed / 0 skipped）一致；未出现 Phase 11 Round 3–4 曾记录的本地端口/native asset 阻断。

---

## 4. Architecture Observations

Phase 0–11 重构后，当前**规范（canonical）实现**为：

| 能力 | canonical 实现 |
| --- | --- |
| 统一内容树模型 | `lib/domain/resources/*`（`resource_contracts` / `resource_blueprint` / `resource_generation_protocol` 等） |
| 内容树持久化 | `lib/services/repositories/resource_tree_repository_impl.dart`（唯一写入者） |
| 创建管线 | `lib/application/resources/resource_creation_pipeline.dart` + `resource_creation_contracts.dart` |
| 流式生成 | `lib/features/resource_studio/*` + `lib/application/resources/part_generation_coordinator.dart`、`streaming_resource_generation_service.dart`、`lib/controllers/streaming_resource_generation_controller.dart` |
| Section 控制 | `section_control_service.dart` / `section_regeneration.dart` / `section_control_repository_impl.dart` |
| 容量与压缩 | `resource_capacity_*` / `compression_coordinator.dart` / `compression_worker.dart` / `resource_compression_publisher.dart` |
| Revision / 自动保存 / 回收站 | `resource_revision_*` / `resource_autosave_*` / `resource_trash_*` + `legacy_library_row_purger.dart` |
| Assembly Readiness | `assembly_readiness_coordinator.dart` / `assembly_readiness_repository.dart` |
| 资源库 UI | `lib/features/resource_library/*`（列表/详情/回收站/创建流） |
| 资源 Studio UI | `lib/features/resource_studio/*` |
| 路由 | `lib/core/router/app_router.dart`（canonical `/library`、`/studio`；兼容旧 deep link `resource-library`、`resources`、`resource-studio`） |
| LLM | `lib/services/llm_service.dart` + `llm_task_policy.dart` + `LlmTask` 枚举 |
| 数据库 | `lib/services/database_service.dart`（schema v43，migration chain v22→v43） |

**当前仍存在的 transitional / legacy 层：**

- `lib/screens/resource_library/*`（旧资源库页面：`worldview_tab`、`character_card_tab`、`npc_tab`、`worldview_ai_import_page`、`resource_card_ai_import_page`、`character_card_edit_page`、`npc_edit_page`、`scene_batch_import_page`、`import_history`）以及它们依赖的 `lib/controllers/resource_library_import_controller.dart`、`resource_card_import_controller.dart`。
- `lib/providers/chat_provider.dart` 中的 `@Deprecated` 委托成员块（64 处 `@Deprecated` 注解，约 60 个唯一成员；转发到 `settingsProvider` / `libraryProvider` / `adventureProvider` / `messagingProvider`）。
- `lib/services/repositories/library_repository.dart` 中服务旧表的 `ILibraryRepository` 方法。
- `lib/services/database_service.dart` 末尾（约 2416–2874 行）的 68 个静态委托包装。
- Phase 2 兼容读取子系统：`resource_read_facade.dart` + `resource_migration_service.dart` + `ILibraryRepository.readResourcePreferringTree`。
- 旧 chat widget：`lib/screens/chat/widgets/*`（多数被 `AdventureSessionScreen` 复用，**不是**整体废弃）。

关键结论：**旧资源库页面仍被 `AdventureWizardScreen` 通过静态方法调用**（`WorldviewTab.showAiImport`、`CharacterCardTab.showAiImport`、`showCreateCharacterCardDialog`），因此不能按文件整体删除，详见 §6–§8。

---

## 5. SAFE DELETE

下表每一项均满足：生产不可达、全仓（`lib` + `test` + `benchmark`）零符号引用、无 `part`/`export`、无平台/route/dynamic 引用、无测试契约依赖。

| ID | File / Symbol | Category | Replacement | Evidence | Risk |
| -- | ------------- | -------- | ----------- | -------- | ---- |
| SD-1 | `lib/core/operations/operation_result.dart`（`OperationResult` / `OperationSuccess` / `OperationFailure`，40 行） | Dead generic result type | 无（未被任何代码使用） | E1–E5 | LOW |
| SD-2 | `lib/core/widgets/empty_state_view.dart`（`EmptyStateView`，46 行） | Duplicate widget | `lib/core/widgets/app_empty_state.dart`（`AppEmptyState`，活跃） | E1–E6 | LOW |
| SD-3 | `lib/screens/chat/widgets/input_bar.dart`（`ChatInputBar`，170 行） | Legacy widget | `lib/features/adventure/presentation/session/widgets/session_input_bar.dart`（`SessionInputBar`，活跃） | E1–E5 | LOW |
| SD-4 | `lib/screens/chat/widgets/multi_char_bar.dart`（`MultiCharacterBar`，34 行） | Legacy widget | 无 | E1–E5 | LOW |
| SD-5 | `lib/screens/chat/widgets/scene_character_manager.dart`（`SceneCharacterManagerScreen` / `SceneWorldviewApprovalScreen` / `SceneNpcApprovalScreen`，253 行） | Legacy screen | 无 | E1–E5 | LOW |
| SD-6 | `lib/screens/chat/widgets/shop_dialog.dart`（`ShopDialog` / `ShopItem`，380 行） | Legacy dialog | 无 | E1–E5 | LOW |
| SD-7 | `lib/widgets/sheet_handle.dart`（`SheetHandle`，34 行） | Orphan helper（仅被 SD-6 引用） | 无 | E1–E5，属 Deletion Cluster C1 | LOW |
| SD-8 | `lib/screens/resource_library/import_history.dart`（`ImportHistory`，56 行） | Legacy model | 无 | E1–E5 | LOW |
| SD-9 | `lib/screens/resource_library/npc_tab.dart`（`NpcTab`，228 行） | Legacy screen | 无（Phase 11 已移除最后一个 importer） | E1–E5，属 Deletion Cluster C2 | LOW |
| SD-10 | `lib/screens/resource_library/npc_edit_page.dart`（`NpcEditPage` / `showNpcEditPage`，282 行） | Legacy screen（仅被 SD-9 引用） | 无 | E1–E5，属 Deletion Cluster C2 | LOW |
| SD-11 | `lib/utils/image_encoder.dart`（`ImageEncoder` / `ImageEncodeException`，46 行） | Orphan utility | 无 | E1–E5，同时使 `image` 依赖成为清理候选 | LOW |
| SD-12 | `DatabaseService` 静态委托包装（约 64 个方法，`lib/services/database_service.dart:2416-2874`） | Dead static facade | Repository 实例直接调用（`_adventureRepo` / `_libraryRepo` 等） | E1、E7、E8 | MEDIUM |
| SD-13 | `ILibraryRepository.saveCardBatch`（接口 + `library_repository_impl.dart:773` 实现） | Dead method | 无（批次写入统一走 `resource_creation_pipeline`） | E1、E7 | LOW |
| SD-14 | `ILibraryRepository.getSkillById` / `saveSkill`（接口 + 实现） | Dead methods | `getAllSkills` / `getCharacterSkills` 等仍活跃 | E1、E7 | LOW |

**共用证据定义：**

- **E1** 生产不可达：以 `lib/main.dart` 为根的 import/export 传递闭包不含该文件（SD-12/SD-13/SD-14 为 live 文件内的不可达符号，由全仓引用扫描确定）。
- **E2** 无 importer：反向 import 扫描显示无任何其他 `lib`/`test`/`benchmark` 文件 import/export 该文件。
- **E3** 零符号引用：`rg` 全仓 word-boundary 搜索其顶层类名/函数名，`lib`+`test`+`benchmark` 外部引用为 0。
- **E4** 无动态引用：无 `part`/`part of`；无 barrel `export`；无 `@pragma('vm:entry-point')`；非 `build_runner` 生成文件；平台目录（android/ios/linux/windows/macos/web）无引用；`AppRouter` 无对应 route；无字符串路由名引用。
- **E5** 测试无依赖：无任何测试 import 或按类型引用该符号（`rg` 命中 0）。
- **E6** 存在明确 canonical 替代实现，且替代实现已被生产与测试使用。
- **E7** 全仓引用扫描确认零调用方。
- **E8** 不参与 schema 迁移链（迁移/建表仅由 `createV*Schema` / `migrateStepByStep` / `safeAddColumn` 承担，本项为读写委托，不写 schema）。

### 逐项详细证据

#### SD-1 `lib/core/operations/operation_result.dart`
- E8/E2/E3：`OperationResult`、`OperationSuccess`、`OperationFailure` 全仓外部引用 0（仅自身定义）。
- 无 barrel export、无测试引用、无生产入口。

#### SD-2 `lib/core/widgets/empty_state_view.dart`
- E6：`AppEmptyState`（`lib/core/widgets/app_empty_state.dart`）是唯一被使用空状态组件，被 `dashboard_featured_worlds.dart`、`dashboard_character_cards.dart`、`session_message_list.dart` 使用。
- `EmptyStateView` 外部引用 0。

#### SD-3～SD-6 旧 chat widgets
- 同目录下 `character_sheet` / `character_switcher` / `chat_dialogs` / `error_card` / `inventory_screen` / `message_bubble` / `quick_menu` / `search_bar` / `status_dropdown` / `status_toast` **仍被 `AdventureSessionScreen` 及其子组件复用，必须保留**。
- 仅 `ChatInputBar`（SD-3）、`MultiCharacterBar`（SD-4）、`SceneCharacterManagerScreen` 等（SD-5）、`ShopDialog`（SD-6）四组符号零引用；它们的 importer 数为 0，生产不可达。

#### SD-7 `lib/widgets/sheet_handle.dart`
- 唯一引用来自 `shop_dialog.dart:222`（SD-6）。删除 SD-6 后 `SheetHandle` 全仓零引用。属 Cluster C1。

#### SD-8 `lib/screens/resource_library/import_history.dart`
- `ImportHistory` 零引用；全仓无 import。

#### SD-9 / SD-10 NPC 旧子系统（Deletion Cluster C2）
- `NpcTab` 零外部引用；唯一 importer 关系为 `npc_tab.dart` → `npc_edit_page.dart`。
- `NpcEditPage` / `showNpcEditPage` 仅被 `npc_tab.dart:24` 引用；`npc_edit_page.dart` 无其他 importer。
- 注意：`NpcEditDraft`（`lib/application/resource_library/edit_drafts.dart`）是**不同符号**，被 `resource_crud_controller.dart` 与测试使用，**必须保留**。
- git 历史佐证：Phase 11 提交 `772a4b9 feat(resources): implement phase 11 library ux convergence` 移除了 `npc_tab.dart` 的最后一个 importer。

#### SD-11 `lib/utils/image_encoder.dart`
- `ImageEncoder` / `ImageEncodeException` 零引用；该文件是 `package:image` 在 `lib/` 中的**唯一**使用点（`rg "package:image/"` 仅命中本文件）。
- 删除后 `image` 依赖成为清理候选（见 §10），但依赖删除需独立验证，未登记为 SAFE DELETE。

#### SD-12 `DatabaseService` 静态委托包装
- 证据：`rg -o "DatabaseService\.\w+" lib` 仅得到 8 个成员：`database`、`libraryTrashBridge`、`contentHashExists`、`seedDefaultWorldviews`、`seedDefaultSkills`、`seedDefaultCharacterCards`、`schemaVersion`、`_libraryRepo`。
- `lib` + `test` 全仓对 `DatabaseService.createAdventure` / `getMessages` / `saveGameState` / `insertWorldEntry` / 世界条目 embedding / branch / bookmark / settings / `getWorldviewPresets` / `saveWorldviewPreset` / `getCharacterCards` / `saveCharacterCard` / `saveNpcCard` / `getNpcCards` / `getPromptPresets` / `getPersonas` / `getAdventureTemplates` / `getImportRecords` / `saveImportRecord` 等**全部为 0 引用**。
- **必须保留**：`resetDatabase`、`tableExists`、`schemaVersion`、`customDbDir`、`database`、`migrateStepByStep`、所有 `createV*Schema`、`safeAddColumn`、`columnExists`、`addSectionControlColumns`、`addCompressionLeaseColumns`、`addResourceCapacityColumns`、`createResourceCompressionSchema`、`dropLegacyQuestAndMapTables`、`contentHashExists`、`seedDefault*`、`libraryTrashBridge`（均被 lib 或测试使用）。
- 风险 MEDIUM 的原因：同一 live 文件内的大段删除，执行时必须逐符号 `rg` 复核并保证保留上述活跃成员。

#### SD-13 `saveCardBatch`
- 唯一外部出现为 `import_use_cases.dart:609` 的**注释**与实现体；无实际调用。
- `LibraryCardType` / `LibraryCardBatchItem` 仍被测试（`scene_batch_identity_test.dart`、`scene_batch_generation_jobs_test.dart` 的 `registerFallbackValue`）与实现使用 → **类型保留**，仅方法及其实现体可删（或保留类型、移除方法）。

#### SD-14 `getSkillById` / `saveSkill`
- 两者外部引用 0；`getAllSkills`（14）、`getCharacterSkills`（15）、`saveCharacterSkill`（4）、`updateCharacterSkill`（6）活跃，必须保留。

---

## 6. Deletion Clusters

| Cluster | 组成 | 外部入口 | 说明 |
| --- | --- | --- | --- |
| **C1 旧 chat 孤儿簇** | `input_bar.dart`、`multi_char_bar.dart`、`scene_character_manager.dart`、`shop_dialog.dart` → `sheet_handle.dart` | 无 | 各文件互不形成唯一入口；`shop_dialog → sheet_handle` 是内部依赖。整簇与生产图断开。 |
| **C2 NPC 旧子系统簇** | `npc_tab.dart` → `npc_edit_page.dart` | 无 | `npc_tab` 无外部入口，`npc_edit_page` 仅被 `npc_tab` 引用。整体评估。 |
| **C3 未接线压缩工具（PROBABLE）** | `resource_context_compressor.dart` + `test/application/resources/resource_context_compressor_test.dart` | 仅测试 | 该文件仅被自身测试 import，生产图无入口。见 §7。 |

C1、C2 与当前生产依赖图完全断开，可作为整体执行。C3 因存在“行为契约测试”而升级为 PROBABLE DELETE。

---

## 7. PROBABLE DELETE

以下候选高度疑似废弃，但缺少一项无法在只读审计中完全证明的证据，**不得自动删除**。

1. **`lib/application/resources/resource_context_compressor.dart`（293 行）+ 其测试（296 行）**
   - 生产不可达：`ResourceContextPriority` / `ResourceContextCandidate` / `ResourceContextFragment` / `ResourceContextPacking` / `ResourceContextAssembler` / `ResourceContextTriggers` 全仓外部引用 0（唯一引用来自其测试）。
   - 缺失证据：这是 Phase 8 上下文打包策略的工具，行为契约由 `resource_context_compressor_test.dart` 固定；是否存在“未来接线到压缩管线”的规划无法从代码证明。属产品决策，建议 MANUAL REVIEW 后再定。

2. **`lib/screens/resource_library/scene_batch_import_page.dart` 的页面部分（约 50–422 行：`showSceneBatchImportPage` / `_SceneBatchImportPage` / `_SceneRelationshipPickerPage`）**
   - `showSceneBatchImportPage` 零调用方；该页面仅使用 `sceneBatchImportControllerProvider`（也仅被该页面使用）。
   - 但同文件 `SceneImportDetailMode`（enum）+ `showSceneImportDetailModePicker`（line 25）**被 `AdventureWizardScreen:1630` 使用** → 文件不可整体删除，只能删除页面部分。属部分文件手术，非整文件删除。

3. **`AdventureWizardScreen` 中的运行时死分支**
   - `adventure_wizard_screen.dart:841-855` 的 `if (chat.isKeyConfigured) { … return; }` 之后，`_generateWorldviewWithAi` 的 857–970 行永不可达（方法入口 835 已在 `!isKeyConfigured` 时 return）。
   - 同理 `_generateCharacterWithAi`（974–1276 行）在 982–997 的 `return` 之后永不可达。
   - 结果：`adventure_ai_controller.generateDetailedWorldview` 的生产调用点（line 871）与 `generateDetailedResourceCharacter`（line 1102）均在死分支内。
   - 缺失证据：这是 4409 行核心生产文件内的删除手术，必须补充回归测试证明行为不变。

4. **`lib/providers/chat_provider.dart` 中的 `@Deprecated` 委托成员块（64 处注解，约 60 个唯一成员）**
   - `flutter analyze` / `dart analyze --format=machine lib test` 均无 `deprecated_member_use` 诊断；逐一追踪 `quickMode` / `dialogueLevel` / `authorsNote` / `customSystemPrompt` / `recentModels` / `setApiKey` / `tts` / `translator` / `presets` / `personas` / `streamingContent` 等代表成员，外部访问均落在 `settingsProvider.*` 或其他对象上，未落在 `ChatProvider`。
   - 缺失证据：`deprecated_member_use_from_same_package` 在默认 `flutter_lints` 下**未启用**，无法用分析器给出同包使用的权威结论；需执行 Agent 手动或临时启用该诊断复核后删除。

5. **`DetailedWorldviewGenerationCoordinator` 及 worldview detailed 生成链**
   - `DetailedWorldviewGenerationCoordinator` 仅被 `ai_generator_service.dart:1119`（`generateDetailedWorldviewCoordinatorForTesting`）引用；该 `*ForTesting` 方法全仓**零调用方**。
   - `DetailedWorldviewContextPolicy` 仅被 `ai_generator_service.dart:1219/1235` 的两个 `*ForTesting` 方法引用；同样零调用方。
   - `generateDetailedWorldviewCoordinatorForTesting`、`parseDetailedWorldviewQuestionResponseForTesting` 均无调用方。
   - `textToDetailedWorldview` / `textToDetailedWorldviewMultiTurn` 仅被测试调用（`detailed_generation_and_wizard_test.dart`）。
   - 缺失证据：这些符号仍被现存测试当作行为契约覆盖；删除需同步处置测试，且属“能力是否正式移除”的产品判断。
   - 注意：`DetailedCharacterGenerationCoordinator` 与 `DetailedCharacterStageNormalizer` **仍经 `textToDetailedCharacterCard` 由 `character_card_edit_page.dart:348` 生产可达**，**不得**与 worldview 侧一并删除。

---

## 8. MANUAL REVIEW

高风险区域，必须人工确认后才能决定，本审计**不**建议直接删除。

1. **Phase 2 兼容读取子系统**
   - `ILibraryRepository.readResourcePreferringTree`（接口 `library_repository.dart:40` + 实现 `library_repository_impl.dart:42`）：全仓**零调用方**。
   - 其唯一下游 `ResourceReadFacade`（`readResourceFacade.readPreferringTree`）仅被该方法使用；`ResourceMigrationService` 仅被 `ResourceReadFacade` 与 `library_repository_impl.dart:256` 的表名常量使用。
   - 风险：这是 v30 旧资源 → 内容树迁移与 tree-first 兼容读取的落点。`STATUS.md` 的 Phase 2 审计明确记载“迁移服务的调用点属于 Phase 3 或 Phase 11”，而当前生产仍未见调用点。
   - **结论：** 不能证明无兼容/迁移责任 → **REQUIRES MANUAL REVIEW**。任何清理必须先确认迁移是否已有其他生产调用路径。

2. **`lib/services/repositories/library_repository.dart` 中服务旧表的写入/读取方法**
   - `saveWorldviewPreset` / `saveCharacterCard` / `saveNpcCard` / `deleteWorldviewPreset` / `deleteCharacterCard` / `deleteNpcCard` / `getWorldviewPresets` / `getCharacterCards` / `getNpcCards` / `saveAdventureTemplate` / `saveImportRecord` 等**仍有生产调用方**（`AdventureWizardScreen`、`resource_crud_controller.dart`、`character_manager.dart`、`preset_manager.dart`、`world_engine.dart`、`adventure_provider.dart`、`chat_provider.dart` 等）或测试。
   - 风险：它们是旧表写入面。只有在统一创建管线完全接管 `AdventureWizardScreen` 的保存路径后才可移除 → **REQUIRES MANUAL REVIEW**。

3. **旧资源库页面（`WorldviewTab` / `CharacterCardTab` / `worldview_ai_import_page` / `resource_card_ai_import_page` / `character_card_edit_page`）**
   - 它们**生产可达**：`AdventureWizardScreen` 静态调用 `WorldviewTab.showAiImport`（line 808）、`CharacterCardTab.showAiImport`（line 1637）、`showCreateCharacterCardDialog`（line 720，→ `app_dialogs.dart` → `character_card_edit_page.dart`）。
   - 与 `phase-12-legacy-removal.md` 的候选清单直接冲突。**在执行 Agent 先完成 wizard 重接线之前，禁止删除** → **REQUIRES MANUAL REVIEW**。

4. **`ResourceLibraryImportController` / `ResourceCardImportController`**
   - `resourceLibraryImportControllerProvider` 被 `AdventureWizardScreen:845` 与 `worldview_tab.dart:207` 使用；`resourceCardImportControllerProvider` 被 `AdventureWizardScreen:986`、`resource_card_ai_import_page.dart`、`character_card_tab.dart`、`npc_tab.dart` 使用。
   - 结论：仍承担 wizard 的 AI 规划会话职责 → **KEEP / MANUAL REVIEW**（不能作为“重复 orchestration”直接删除）。

5. **`LlmTask.worldviewFast` / `worldviewDeep` / `importExtraction` 收敛**
   - 三者仍被 `ai_generator_service.dart` / `ai_import_service.dart` / `llm_task_policy.dart` 使用；其中 `worldviewFast/worldviewDeep` 的部分调用点位于上面 §7.3 的运行时死分支内。收敛需先完成死分支清除并确认 `ai_import_service` 的调用方仍有效 → **REQUIRES MANUAL REVIEW**。
   - `LlmTask.runtimeStateAnalysis` 仅出现在 `llm_task.dart` 定义与 `llm_task_policy.dart` 映射，无调用方；其注释明确“reserved for the Agent Runtime” → 建议 **KEEP**（预留接口）。

6. **`WorldviewDetails.moduleKeys`**
   - 仍被 `worldview_length_guard.dart`、`resource_integrity_validator.dart`、`edit_drafts.dart`、`worldview_tab.dart`、`worldview_ai_import_page.dart` 及测试使用。
   - `phase-12-legacy-removal.md` 提到“兼容 parser 可暂留” → 在对应消费者迁移前 **KEEP / MANUAL REVIEW**。

7. **`creation_library_resources` / `creation_library_relations` / `creation_library_imports` 表**
   - 仅由 `database_service.dart` 的 `createCreationLibrarySchema` 创建，无任何 DAO/Repository 运行时读写。
   - `phase-12-legacy-removal.md` 明确：“本阶段默认保留只读 legacy 数据，除非独立 migration 证明可回滚”。→ **REQUIRES MANUAL REVIEW / DEFER**，禁止在本阶段 drop。

8. **`lib/screens/prompt_settings_screen.dart` 兼容门面**
   - 是委托到 `features/prompt_settings/.../prompt_settings_screen.dart` 的 facade，仍被 `session_app_bar.dart:10` 使用 → 可内联但非废弃 → **MANUAL REVIEW**。

---

## 9. KEEP

容易被误删、但审计确认仍承担有效职责的重要代码。

| 类别 | 保留项 | 原因 |
| --- | --- | --- |
| 历史 migration | `database_service.dart` 的 `createV5Schema`…`createV43Schema`、`migrateStepByStep`、`safeAddColumn`、`columnExists`、`dropLegacyQuestAndMapTables`、`createCreationLibrarySchema` | 旧版本数据库 → 最新版本的升级链；删除会导致升级失败 |
| migration 测试 | `test/application/resources/database_migration_v36/v39/v40/v41/v42_test.dart`、`test/services/database_migration_v38_test.dart`、`test/services/database_migration_resource_tree_test.dart`、`resource_migration_schema_upgrade_test.dart`、`resource_migration_service_test.dart` | 迁移回归 |
| 已移除功能守卫 | `test/architecture/feature_removal_guard_test.dart` | Quest/WorldMap 移除防回归（同时是 Phase 12 新增守卫的模板） |
| 架构守卫 | `test/architecture/presentation_boundary_test.dart`、`layer_dependencies_test.dart`、`models_boundary_test.dart`、`source_imports.dart` | 层级/边界回归 |
| 兼容读取 | `legacy_resource_mapper.dart`（被 `resource_read_facade` / `resource_adventure_view` / `legacy_creation_bridge` / `library_repository_impl` 使用） | tree↔legacy 映射 |
| 兼容读取 | `legacy_creation_bridge.dart`（`resource_crud_controller` / `character_manager` / `world_engine` / `import_use_cases` 使用） | 入口适配 |
| 删除安全 | `legacy_library_row_purger.dart`（`resource_library_trash_bridge` / `database_service` / providers 使用） | 旧行隐藏/回收站来源 |
| 运行态 | `resource_adventure_view.dart`、`world_entry_repository*`、`world_embedding_repository*` | Adventure 快照与检索 |
| 兼容模型 | `model_capabilities.dart` 中 `isDeprecated` 的 V4 Pro 等 | 已保存配置可解析，仅隐藏 |
| 回归/恢复/并发测试 | `phase9_*_test.dart`、`phase10_production_wiring_test.dart`、`resource_trash_service_test.dart`、`compression_concurrency_test.dart`、`adventure_setup_controller_concurrency_test.dart`、`session_message_list_scroll_test.dart` 等 | bug 复现/竞态/恢复/持久化契约 |
| 仍活跃旧页面 | `worldview_tab.dart`、`character_card_tab.dart`、`worldview_ai_import_page.dart`、`resource_card_ai_import_page.dart`、`character_card_edit_page.dart`、`scene_batch_import_page.dart` | `AdventureWizardScreen` 生产可达 |
| 仍活跃旧 chat widget | `character_sheet` / `character_switcher` / `chat_dialogs` / `error_card` / `inventory_screen` / `message_bubble` / `quick_menu` / `search_bar` / `status_dropdown` / `status_toast` | `AdventureSessionScreen` 复用 |
| 预留 enum | `LlmTask.runtimeStateAnalysis` | 注释明确预留 |
| 其他 | `preset_adventures.dart`、`skill_presets.dart`、`connectivity_plus`、`shared_preferences` | 生产使用 |

---

## 10. Dependency Cleanup Candidates

以下依赖/资源在源码中已无任何引用，但删除属于 `pubspec.yaml`/平台插件注册变更，需独立验证；本审计**未执行**任何修改。

| 目标 | 现状 | 证据 | 建议等级 |
| --- | --- | --- | --- |
| `image_picker`（dependencies） | `lib` 与 `test` 中 0 引用；仅出现在生成的 `.flutter-plugins-dependencies` | `rg "image_picker" lib test` = 0 | 可移除；需 `flutter pub get` 重生成插件注册并至少构建 Android/Linux 验证 |
| `flutter_markdown_plus`（dependencies） | 0 import；`exportToMarkdown()` 是自有领域方法，与包无关 | `rg "flutter_markdown_plus"` = 0 | 可移除 |
| `image`（dependencies） | 仅被 SD-11 孤儿文件使用 | `rg "package:image/" lib` 仅 `image_encoder.dart` | 依赖 SD-11 删除后移除 |
| `assets/icons/qwen.svg`、`assets/icons/zhipu.svg` | 无引用；`providerBrandIcon` 仅对 `LLMProvider.deepseek` 返回 SVG | `rg "qwen.svg|zhipu.svg" lib` = 0 | 可移除（`assets/icons/deepseek.svg` 保留） |

**保留：** `flutter_riverpod`、`http`、`shared_preferences`、`sqflite`、`sqflite_common_ffi`、`path`、`path_provider`、`flutter_tts`、`flutter_secure_storage`、`connectivity_plus`、`google_fonts`、`flutter_svg`、`pointycastle`、`equatable`、`mocktail`（均有实际引用）。

**不建议在本阶段处理：** `pubspec.lock`（未被要求变动时不修改）、`dependency_overrides.objective_c`（注释说明为 SDK 兼容锁定）。

---

## 11. Expected Phase 12 Execution Scope

基于本审计的证据，给执行 Agent 的**明确范围**（下表已排除所有 MANUAL REVIEW/PROBABLE 项）：

```text
Files safe to delete:              11
  1. lib/core/operations/operation_result.dart
  2. lib/core/widgets/empty_state_view.dart
  3. lib/screens/chat/widgets/input_bar.dart
  4. lib/screens/chat/widgets/multi_char_bar.dart
  5. lib/screens/chat/widgets/scene_character_manager.dart
  6. lib/screens/chat/widgets/shop_dialog.dart
  7. lib/widgets/sheet_handle.dart
  8. lib/screens/resource_library/import_history.dart
  9. lib/screens/resource_library/npc_tab.dart
 10. lib/screens/resource_library/npc_edit_page.dart
 11. lib/utils/image_encoder.dart

Symbols safe to remove:            ~67
  - DatabaseService 静态委托包装: 约 64 个（database_service.dart 2416-2874 内，排除
    seedDefaultWorldviews / seedDefaultCharacterCards / seedDefaultSkills / contentHashExists）
  - ILibraryRepository.saveCardBatch + 实现体: 1
  - ILibraryRepository.getSkillById + 实现体: 1
  - ILibraryRepository.saveSkill + 实现体: 1
  （类型 LibraryCardType / LibraryCardBatchItem 保留）

Deletion clusters:                 2
  C1: {input_bar, multi_char_bar, scene_character_manager, shop_dialog, sheet_handle}
  C2: {npc_tab, npc_edit_page}

Dependencies safe to remove:       2（+1 条件）
  - image_picker
  - flutter_markdown_plus
  - image（条件：SD-11 删除后）
  另可删除未引用 asset: assets/icons/qwen.svg、assets/icons/zhipu.svg

Tests safe to remove/update:       0
  （无测试引用上述 11 个文件或 SD-12/13/14 符号；测试范围保持不变）
```

**不在本审计批准范围内（需另行授权）：** §7 的 5 组 PROBABLE DELETE、§8 的全部 MANUAL REVIEW 项，以及 `phase-12-legacy-removal.md` 直接点名的、但仍可达的候选。

---

## 12. Risk Assessment

- **Database risk（低）**：本审计批准的删除不含任何 `createV*Schema` / `migrateStepByStep` / `safeAddColumn` / 表结构变更；SD-12 的静态包装不写 schema。SD-12 风险仅在于同文件大段删除，需逐符号复核。
- **Migration risk（无，但存在未决项）**：历史升级链（v22→v43）完整保留。`ResourceMigrationService`/`ResourceReadFacade` 的兼容/迁移责任不明，已列为 MANUAL REVIEW，不在执行范围。
- **Runtime risk（低）**：11 个删除文件均生产不可达；SD-12/13/14 为 0 调用符号。删除后 `flutter analyze` 必须保持 0 issue。
- **UI risk（低）**：被删 UI 组件（ShopDialog、MultiCharacterBar、SceneCharacterManager、ChatInputBar、EmptyStateView）均无生产挂载点；活跃的 `AdventureSessionScreen` 与 `SessionInputBar` 不受影响。不存在 320 px 响应式回归面。
- **Persistence risk（无）**：不触碰资源/Adventure/revision/trash/autosave 的持久化路径；`legacy_library_row_purger.dart` 保留。
- **Platform risk（中，仅依赖项）**：移除 `image_picker` 会改变生成的插件注册（Android/iOS/Linux/Windows/macOS/Web）。需 `flutter pub get` 后至少构建受影响平台；若无法构建，则依赖移除应降级为 MANUAL REVIEW。
- **Regression risk（低）**：baseline 1600 passed；被删项无测试覆盖。删除后需复跑 `dart format` / `flutter analyze` / `flutter test` / `git diff --check`，并确认仍为 1600 passed（SD-12 若连带测试重置，需确认无测试引用被删符号）。

---

## 13. Pre-Execution Verdict

```text
READY FOR PHASE 12 EXECUTION
```

依据：

- **删除目标明确**：§5 的 11 个文件 + SD-12/13/14 符号组有完整证据链（生产不可达 + 全仓零引用 + 无动态/平台/route/测试依赖）。
- **SAFE DELETE 有证据**：每项均附 E1–E8 证据。
- **高风险项被排除**：全部数据库/迁移/兼容/persistence 相关项已归入 §8 MANUAL REVIEW，未进入执行范围。
- **baseline 无未知失败**：format/analyze/full-test/diff-check 全绿（1600 passed / 0 failed / 0 skipped）。
- **删除边界明确**：执行范围限定为 §11；§7 PROBABLE 与 §8 MANUAL REVIEW 明确排除。

**执行前置约束（必须遵守）：**

1. 执行 Agent **不得**按 `docs/adaptive-resource-system/phase-12-legacy-removal.md` 第 5 节的候选清单直接删除；该清单中的旧资源库页面、coordinator、import controller、`ILibraryRepository` 旧方法当前**仍生产可达或仍被测试契约覆盖**（文档漂移，见 §1）。
2. 每个删除动作前，对该文件/符号重新执行 `rg` 反向验证；若出现任何新引用，停止并升级为 MANUAL REVIEW。
3. SD-12 必须逐符号确认保留 `resetDatabase`、`tableExists`、`schemaVersion`、`database`、`migrateStepByStep`、`createV*Schema`、`safeAddColumn`、`columnExists`、`addSectionControlColumns`、`addCompressionLeaseColumns`、`addResourceCapacityColumns`、`createResourceCompressionSchema`、`dropLegacyQuestAndMapTables`、`contentHashExists`、`seedDefault*`、`libraryTrashBridge`。
4. 依赖与 asset 清理必须独立提交、独立验证；`image_picker` 若无法完成跨平台构建验证，则不得删除。
5. 删除后必须复跑 `dart format --output=none --set-exit-if-changed .`、`flutter analyze`、`flutter test`、`git diff --check`，任何失败即回滚该次删除。
6. 不得删除任何 migration 测试、回归测试、恢复/并发/持久化测试。

**本轮为只读审计。未删除任何文件、未修改任何生产代码/测试/配置/数据库、未 commit、未 push。审计到此结束，未进入 Phase 12 Execution。**
