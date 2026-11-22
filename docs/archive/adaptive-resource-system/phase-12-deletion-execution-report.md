# Phase 12 Deletion Execution Report

本文件是 Phase 12（旧系统删除与总回归）的**删除执行报告**。执行严格限定在 Pre-Execution Deletion Audit 的 SAFE DELETE 白名单内，未处理 PROBABLE DELETE / MANUAL REVIEW / KEEP。

---

## 1. Baseline

| 项目 | 值 |
| --- | --- |
| Start HEAD | `6caa76a1ed67f7ec2eb7b61d56e114ef4a750461` |
| origin/main | `6caa76a1ed67f7ec2eb7b61d56e114ef4a750461` |
| Branch | `main` |
| Ahead / Behind (start) | `0 / 0` |
| Worktree state (start) | clean，仅有 Phase 12 审计报告未跟踪文件 `docs/adaptive-resource-system/phase-12-pre-execution-deletion-audit.md`（本流程产物，保留） |
| Pre-Audit report | `docs/adaptive-resource-system/phase-12-pre-execution-deletion-audit.md` |
| Pre-Audit verdict | `READY FOR PHASE 12 EXECUTION` |
| Gate | 通过（报告明确 READY，未绕过） |

已读取：`AGENTS.md`、`README.md`、`docs/adaptive-resource-system/STATUS.md`、`docs/adaptive-resource-system/phase-12-legacy-removal.md`、Pre-Audit 报告。

---

## 2. Authorized Scope

Pre-Audit SAFE DELETE 授权数量：

```text
Files:        11
Symbols:      ~67 (DatabaseService 静态包装 64 + ILibraryRepository 3)
Clusters:     2 (C1 旧 chat 孤儿簇, C2 NPC 旧子系统簇)
Dependencies: 2 (+1 条件：image，依赖 SD-11)
Assets:       2
Tests:        0
```

---

## 3. Executed Deletions

| ID | Target | Action | Result |
| -- | ------ | ------ | ------ |
| SD-1 | `lib/core/operations/operation_result.dart` | `git rm` | DELETED |
| SD-2 | `lib/core/widgets/empty_state_view.dart` | `git rm` | DELETED |
| SD-3 | `lib/screens/chat/widgets/input_bar.dart` | `git rm` | DELETED |
| SD-4 | `lib/screens/chat/widgets/multi_char_bar.dart` | `git rm` | DELETED |
| SD-5 | `lib/screens/chat/widgets/scene_character_manager.dart` | `git rm` | DELETED |
| SD-6 | `lib/screens/chat/widgets/shop_dialog.dart` | `git rm` | DELETED |
| SD-7 | `lib/widgets/sheet_handle.dart`（Cluster C1） | `git rm` | DELETED |
| SD-8 | `lib/screens/resource_library/import_history.dart` | `git rm` | DELETED |
| SD-9 | `lib/screens/resource_library/npc_tab.dart`（Cluster C2） | `git rm` | DELETED |
| SD-10 | `lib/screens/resource_library/npc_edit_page.dart`（Cluster C2） | `git rm` | DELETED |
| SD-11 | `lib/utils/image_encoder.dart` | `git rm` | DELETED |
| SD-12 | `DatabaseService` 64 个静态委托包装（`database_service.dart`） | 最小编辑删除方法体 + 级联无用 import/repo getter | REMOVED |
| SD-13 | `ILibraryRepository.saveCardBatch`（接口 + 实现） | 最小编辑删除 | REMOVED |
| SD-14 | `ILibraryRepository.getSkillById` / `saveSkill`（接口 + 实现） | 最小编辑删除 | REMOVED |
| DEP-1 | `image_picker`（pubspec.yaml） | 移除 + `flutter pub get` | REMOVED |
| DEP-2 | `flutter_markdown_plus`（pubspec.yaml） | 移除 + `flutter pub get` | REMOVED |
| DEP-3 | `image`（pubspec.yaml，条件依赖 SD-11） | 移除 + `flutter pub get` | REMOVED |
| AST-1 | `assets/icons/qwen.svg` | `git rm` | DELETED |
| AST-2 | `assets/icons/zhipu.svg` | `git rm` | DELETED |

**Cluster 执行结果：**

- **C1**（旧 chat 孤儿簇）整体删除，删除后 `rg` 无 dangling reference。
- **C2**（NPC 旧子系统簇）整体删除，删除后 `rg` 无 dangling reference。

---

## 4. Skipped Candidates

**无白名单项被跳过。** 所有 11 个文件、3 个符号组（SD-12/13/14）、3 个依赖、2 个 asset 均通过执行前 TOCTOU 复核并已删除。

说明：

- Pre-Audit 的 PROBABLE DELETE 与 MANUAL REVIEW 项**从未进入本轮授权范围**，因此不计入 skipped（见 §9）。
- 未出现 `SKIPPED — NEW REFERENCE FOUND` / `SKIPPED — MIGRATION DEPENDENCY` / `SKIPPED — WORKTREE CONFLICT` / `SKIPPED — AUDIT EVIDENCE STALE`。

---

## 5. Supporting Cleanup

仅做维持编译/一致性所必须的直接清理：

- `lib/services/database_service.dart`：
  - 删除因 SD-12 变为不可达的私有 repo 访问器 `_adventureRepo` / `__adventureRepo`、`_worldEntryRepo` / `__worldEntryRepo`、`_settingsRepo` / `__settingsRepo` 及其在 `resetDatabase()` 中的重置行（`_worldEmbeddingRepo` / `worldEmbeddingRepo` / `_libraryRepo` / `_libraryTrash` 保留，因其仍被 `contentHashExists`、`seedDefault*` 或公共 getter 使用）。
  - 删除 11 个不再使用的 import：`models/adventure_config.dart`、`models/game_state.dart`、`models/message.dart`、`models/world_entry.dart`、`models/world_embedding.dart`、`repositories/adventure_repository.dart`、`repositories/adventure_repository_impl.dart`、`repositories/world_entry_repository.dart`、`repositories/world_entry_repository_impl.dart`、`repositories/settings_repository.dart`、`repositories/settings_repository_impl.dart`。
- `lib/services/repositories/library_repository_impl.dart`：删除因 SD-13 变成无用的 `import '../resource_integrity_validator.dart'`（`ResourceIntegrityValidator` 仍被 `world_engine` / `character_manager` / `resource_crud_controller` / `import_use_cases` 等广泛使用，模块保留）。
- `lib/application/resource_library/import_use_cases.dart`：修正因 SD-13 失效的 doc 引用 `[ILibraryRepository.saveCardBatch]` → `[LegacyCreationBridge.saveCards]`（实际保存调用）。
- `lib/controllers/resource_crud_controller.dart`：修正因 SD-9 失效的注释中对 `npc_tab.dart` 的引用。
- 平台插件注册（`flutter pub get` 自动重生成）：`linux/flutter/generated_plugin_registrant.cc`、`linux/flutter/generated_plugins.cmake`、`windows/flutter/generated_plugin_registrant.cc`、`windows/flutter/generated_plugins.cmake`、`macos/Flutter/GeneratedPluginRegistrant.swift` —— 仅移除 `file_selector_*`（image_picker 的传递插件）注册行。
- `pubspec.lock`：移除被删依赖及其传递依赖（共 20 个包被移除，无任何版本升级）。

---

## 6. Validation

```text
dart format --output=none --set-exit-if-changed .   : PASS（493 files, 0 changed）
flutter analyze --no-pub                            : PASS（No issues found）
Phase 12 targeted tests                             : PASS（63 passed / 0 failed）
flutter test                                        : PASS（1600 passed / 0 failed / 0 skipped）
git diff --check                                    : PASS（clean）
```

补充验证：

```text
flutter build linux --debug                         : PASS（✓ Built build/linux/x64/debug/bundle/lt_dialogue）
```

定向测试集合：`test/architecture/`（含 `feature_removal_guard_test.dart`）、`test/services/library_repository_tree_union_test.dart`、`test/unit/database_and_repositories_test.dart`、`test/application/resources/resource_migration_service_test.dart`、`test/unit/post_removal_smoke_acceptance_test.dart`。

全量测试数量与 Pre-Audit baseline 一致（1600 passed / 0 failed / 0 skipped），未出现回归。

---

## 7. Deletion Metrics

```text
Deleted files:          13（11 lib Dart + 2 SVG asset）
Removed symbols:        67（64 DatabaseService 静态包装 + 3 ILibraryRepository 方法）
                        另级联移除 3 个失效 repo 访问器与 12 个失效 import
Deleted dependencies:   3 direct（image_picker / flutter_markdown_plus / image）
                        lockfile 共移除 20 个包（含传递依赖），无版本升级
Deleted assets:         2（qwen.svg、zhipu.svg）
Deleted tests:          0
Lines added:            2
Lines deleted:          2330
Net LOC reduction:      2328
Files changed:          25
```

---

## 8. Regression Assessment

| 维度 | 结论 | 说明 |
| --- | --- | --- |
| database | 无回归 | 未触碰 schema、`createV*Schema`、`migrateStepByStep`、`safeAddColumn`、表结构；删除的仅是未引用的静态读写委托。 |
| migration | 无回归 | 历史升级链（v22→v43）完整保留；migration 测试全量通过。 |
| persistence | 无回归 | 未修改资源/Adventure/revision/trash/autosave 持久化路径；`legacy_library_row_purger.dart`、`legacy_creation_bridge.dart`、`legacy_resource_mapper.dart` 保留。 |
| runtime | 无回归 | 11 个删除文件生产不可达；SD-12/13/14 为 0 调用符号。 |
| UI | 无回归 | 删除的 UI 组件无生产挂载点；活跃 `AdventureSessionScreen` / `SessionInputBar` 不受影响；`post_removal_smoke_acceptance_test.dart` 通过。 |
| platform | 部分验证 | Linux debug 构建通过。macOS / Windows / Android / iOS 未在本 Linux 环境构建；其插件注册文件仅为 `file_selector_*` 机械移除，Dart 侧 0 引用。**残留验证项，供 Post-Execution Audit 复核。** |
| test | 无回归 | 1600 passed / 0 failed / 0 skipped；无测试引用被删符号。 |

**执行中未发现任何需要 RESTORE 的误判（无 PRE-AUDIT FALSE POSITIVE）。**

---

## 9. Deferred Items

本轮**未执行**、需后续阶段处理：

**PROBABLE DELETE（Pre-Audit §7）：**
- `lib/application/resources/resource_context_compressor.dart` + 其测试（未接线压缩工具）。
- `scene_batch_import_page.dart` 的页面部分（部分文件手术）。
- `AdventureWizardScreen` 运行时死分支（857–970、999–1276）。
- `chat_provider.dart` 的 `@Deprecated` 委托成员块（约 60 个）。
- `DetailedWorldviewGenerationCoordinator` 及 worldview detailed 生成链。

**MANUAL REVIEW（Pre-Audit §8）：**
- Phase 2 兼容读取子系统（`readResourcePreferringTree` / `ResourceReadFacade` / `ResourceMigrationService`）。
- `ILibraryRepository` 旧表写入/读取方法。
- 旧资源库页面（仍被 `AdventureWizardScreen` 可达）。
- `ResourceLibraryImportController` / `ResourceCardImportController`。
- `LlmTask.worldviewFast` / `worldviewDeep` / `importExtraction` 收敛。
- `WorldviewDetails.moduleKeys`。
- `creation_library_resources` / `creation_library_relations` / `creation_library_imports` 表。
- `lib/screens/prompt_settings_screen.dart` 兼容门面。

**OUT OF SCOPE（本轮发现但未处理）：**
- 无。执行中未发现需要登记的新越界问题。

---

## 10. Execution Verdict

```text
READY FOR PHASE 12 POST-EXECUTION AUDIT
```

依据：

- Pre-Audit Gate 为 `READY FOR PHASE 12 EXECUTION`。
- 每个 SAFE DELETE 项执行前做了 TOCTOU 复核，未发现新引用。
- 删除严格限定在白名单；未扩大范围，未处理 PROBABLE / MANUAL REVIEW。
- `dart format`、`flutter analyze`、定向测试、全量测试（1600 passed）、`git diff --check` 全部通过；Linux debug 构建通过。
- 未发现 compile failure / test regression / migration failure / runtime contract break；无需 RESTORE。

---

## 附：提交前检查

- `git status --short`：仅包含白名单删除、直接支持性清理（database_service / library_repository* / import_use_cases 注释 / resource_crud_controller 注释）、`pubspec.yaml` / `pubspec.lock`、由 `flutter pub get` 重生成的平台注册文件，以及本报告与 Pre-Audit 报告。
- 未删除白名单外文件；无无关修改；无意外格式化（`dart format` 仅作用于本轮修改文件，全仓检查 0 changed）；未修改用户已有内容；无隐藏测试失败；无 Phase 13 内容。
