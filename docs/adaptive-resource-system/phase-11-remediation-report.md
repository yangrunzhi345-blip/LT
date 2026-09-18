# Phase 11 Remediation Report

## 基线与结论

- Round 1 implementation End HEAD: `772a4b979e38b09e6065d98a61b112243ab786d0`
- Round 1 audit result: **FAILED**（P11-M1/P11-M2/P11-M3，共 3 MAJOR）
- Remediation End HEAD: `61bfe7e8a2ed6dc8b537b75ca73d4982f4a99f65`
- Remediation commit: `61bfe7e8a2ed6dc8b537b75ca73d4982f4a99f65`（`fix(resources): remediate phase 11 audit round 1`）
- Date: 2026-09-18
- Status: `IMPLEMENTED`，等待独立复验
- Phase 12: `BLOCKED`

本报告只记录整改事实，不覆盖或删除 Round 1 的 **FAILED** 历史，也不宣布 Phase 11 `ACCEPTED`。Round 1 的完整缺陷、根因与建议修复继续保留在 [STATUS.md](STATUS.md) 的“Phase 11 Round 1 独立审计”章节。

## 整改内容

### P11-M1：资源库异步竞态与销毁生命周期

`ResourceLibraryController` 增加递增请求代际。异步加载完成后，只有最新请求可以发布状态，较早请求的迟到结果不会覆盖新列表或新错误状态。控制器同时增加 dispose 生命周期保护，销毁后的异步完成不会继续更新状态或调用 `notifyListeners`。

回归测试覆盖并发加载后旧请求迟到，以及控制器销毁后请求才完成的场景。

### P11-M2：活动生成状态被旧 readiness 遮蔽

`ProductionResourceLibraryRuntime` 调整展示状态决策顺序：活动生成会话优先于已有 readiness，因此资源再次生成或重试时，资源库展示“生成中”，不会继续显示旧 assembly 的“已准备完成”或其他 readiness 文案。没有活动会话时仍按 readiness 与已完成会话状态决定展示结果。

回归测试覆盖活动生成、生成完成和无会话场景。

### P11-M3：用户可见文案泄漏内部术语

`SectionControlController.regenerateSection` 的成功文案将内部英文模型名 `Part` 替换为中文业务词“段落”。Studio Widget 回归测试固定该成功文案，防止用户界面再次暴露该术语。

## 修改范围

整改提交修改以下生产与测试文件：

- `lib/features/resource_library/application/use_cases/resource_library_runtime.dart`
- `lib/features/resource_library/presentation/controllers/resource_library_controller.dart`
- `lib/features/resource_studio/presentation/controllers/section_control_controller.dart`
- `test/features/resource_library/application/resource_library_runtime_test.dart`
- `test/widget/resource_library_controller_test.dart`
- `test/widget/resource_studio_section_controls_test.dart`

本轮记录更新不修改生产代码、测试或 Phase 11/12 计划文档。

## 验证

整改执行报告 `/tmp/lt-phase11-auto.gKm7sE/remediation-round-1.txt` 记录：

- 直接 Dart 格式化：通过。
- 定向 Dart 静态分析：通过，无问题。
- `git diff --check`：通过。
- `flutter analyze` / `flutter test`：未能启动。Flutter SDK wrapper 尝试写入只读缓存目录 `/home/yrz/development/flutter/bin/cache`，被 `Read-only file system` 阻断。

上述环境阻断不记为测试通过。独立复验应在 Flutter SDK 缓存可写的环境中重跑静态分析、Phase 11 定向测试和全量测试，并核对 P11-M1/P11-M2/P11-M3 的验收标准。

## 交接

Phase 11 已从“Round 1 审计失败、等待整改”转为 `IMPLEMENTED`，等待独立复验。只有独立复验将 Phase 11 标记为 `ACCEPTED` 后，Phase 12 才能解除 `BLOCKED`。

## Round 2 Remediation

### 基线与结论

- Round 2 audit result: **FAILED**（P11-M4，共 1 MAJOR）
- Round 2 remediation End HEAD: `5881f6d6f62b0d025a20675b35ac4a35ba72b333`
- Remediation commit: `5881f6d6f62b0d025a20675b35ac4a35ba72b333`（`fix(resources): remediate phase 11 audit round 2`）
- Date: 2026-09-18
- Status: `IMPLEMENTED`，等待独立复验
- Phase 12: `BLOCKED`

本节记录 Round 2 整改，不覆盖或删除 Round 2 的 **FAILED** 历史。Phase 11 未标记为 `ACCEPTED`，Phase 12 不因本轮整改自动解锁。

### P11-M4：迁移状态下的树/legacy 双投影

`LibraryRepositoryImpl._mergeTreeRows()` 现在同时识别 `succeeded`、`source_changed` 等迁移状态，并基于当前 legacy 行重新计算哈希。仅当树投影仍对应当前版本时隐藏 legacy 行；陈旧树投影会被过滤，避免 `source_changed` 时资源库同时展示陈旧树投影与当前 legacy 投影。worldview、character、NPC 均补充了回归覆盖。

### 修改范围

本轮整改提交修改以下生产与测试文件：

- `lib/services/resource_migration_service.dart`
- `lib/features/resource_library/data/repositories/library_repository_impl.dart`
- `test/features/resource_library/data/library_repository_tree_union_test.dart`

本轮记录更新不修改生产代码、测试或 Phase 11/12 计划文档。

### 验证

整改执行报告 `/tmp/lt-phase11-auto.gKm7sE/remediation-round-2.txt` 记录：

- Dart formatter：通过。
- 定向 Dart 静态分析：通过，无问题。
- `git diff --check`：通过。
- `flutter analyze`、定向/全量 `flutter test`：已尝试，但被只读 Flutter engine 缓存阻断（`engine.stamp.tmp.*` / `engine.realm` 无法写入）。上述环境阻断不记为测试通过。

独立复验应在 Flutter SDK 缓存可写的环境中重跑静态分析、Phase 11 定向测试和全量测试，并核对 P11-M4 的验收标准。

### 交接

Phase 11 Round 2 remediation 已完成，当前状态为 `IMPLEMENTED`，等待独立复验。只有独立复验将 Phase 11 标记为 `ACCEPTED` 后，Phase 12 才能解除 `BLOCKED`。
