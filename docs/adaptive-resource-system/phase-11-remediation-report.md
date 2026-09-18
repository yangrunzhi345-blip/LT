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

## Round 3 Remediation

### 基线与结论

- Round 3 audit result: **FAILED**（P11-R3-M1/P11-R3-M2，共 2 MAJOR；P11-R3-C1，共 1 MINOR）
- Round 3 remediation End HEAD: `37defebb1816a0dda88cdef78da34373d2259d9e`
- Remediation commit: `37defebb1816a0dda88cdef78da34373d2259d9e`（`fix(resources): remediate phase 11 audit round 3`）
- Date: 2026-09-18
- Status: `IMPLEMENTED`，等待独立复验
- Phase 12: `BLOCKED`

本节记录 Round 3 整改，不覆盖或删除 Round 1、Round 2、Round 3 的 **FAILED** 历史。本轮不宣布 Phase 11 `ACCEPTED`；Phase 12 不因整改完成而解锁。

### P11-R3-M1：Studio 用户可见错误术语

新增统一用户可见错误映射，覆盖 Studio 控制器、运行时事件、章节重新生成、容量与版本面板、编辑器状态和 Snackbar。默认错误文案使用“段落”等业务词，避免向用户暴露协议字段和内部术语；相应 Studio 页面与章节失败路径补充文案回归测试。

### P11-R3-M2：回收站异步竞态与生命周期

`ResourceTrashController` 增加请求代际与 dispose 生命周期保护。恢复和永久删除操作会使旧读取失效，操作期间拒绝并发刷新；旧列表、旧错误及销毁后的迟到结果均不能覆盖当前状态或继续发布通知。回归测试覆盖并发加载、旧错误覆盖、恢复交错和 dispose 后迟到完成。

### P11-R3-C1：生产装配级 Widget 覆盖

该项为 Round 3 审计登记的 MINOR。本轮没有新增直接覆盖 `AppRouter.onGenerateRoute`、回收站恢复以及 readiness 生产装配链路的 Widget 测试，继续作为已知覆盖缺口保留，交由独立复验判断是否接受为非阻塞技术债。

### 修改范围

整改提交修改 9 个生产文件和 6 个测试/测试辅助文件，集中于 Resource Studio 用户消息映射、回收站控制器及对应回归覆盖。完整文件清单以提交 `37defebb1816a0dda88cdef78da34373d2259d9e` 为准。

本轮记录更新只修改 `STATUS.md` 与本报告，不修改生产代码、测试或 Phase 11/12 计划文档。

### 验证

整改执行报告 `/tmp/lt-phase11-auto.gKm7sE/remediation-round-3.txt` 记录：

- 格式检查通过，338 个文件无需调整。
- `flutter analyze` 通过，0 issues。
- `git diff --check` 通过。
- 定向及全量 `flutter test` 均已尝试，但沙箱禁止绑定 `127.0.0.1:0`，测试在加载阶段失败，未产生断言失败；全量并发加载另触发临时目录配额限制。
- 临时 Flutter SDK 已清理；Phase 12 与 legacy removal 均未启动。

上述环境阻断不记为测试通过。独立复验应在允许本地端口绑定且临时空间充足的环境中重跑 Phase 11 定向测试与全量测试，并核对 P11-R3-M1、P11-R3-M2 的验收标准及 P11-R3-C1 的处置。

### 交接

Phase 11 Round 3 remediation 已完成，当前状态为 `IMPLEMENTED`，等待独立复验。只有独立复验将 Phase 11 标记为 `ACCEPTED` 后，Phase 12 才能解除 `BLOCKED`。

## Round 4 Remediation

### 基线与结论

- Round 4 audit result: **FAILED**（P11-M1，共 1 MAJOR；P11-M2，共 1 MINOR；P11-V1，共 1 INFO）
- Round 4 remediation End HEAD: `bb7e34ee20e42afa5846a3f98c6069909a2fa140`
- Date: 2026-09-18
- Status: `IMPLEMENTED`，等待独立复验
- Phase 12: `BLOCKED`

本节记录 Round 4 remediation，不覆盖或删除 Round 1–4 的 **FAILED** 历史。本轮不宣布 Phase 11 `ACCEPTED`；Phase 12 不因状态恢复为 `IMPLEMENTED` 而解锁。

### 执行结果

整改执行报告 `/tmp/lt-phase11-auto.gKm7sE/remediation-round-4.txt` 明确说明：当前会话没有完成生产代码或测试修改，也没有运行验证。报告确认 P11-M1 的根因是 `ResourceStudioSectionControls` 直接展示 `entry.validationMessage`，建议在展示边界调用 `resourceStudioUserMessage(...)`，并建议增加覆盖空章节、缺失正文和超限段落的真实校验消息 Widget 回归，验证 320×568 与大字体布局。P11-M2 保持 MINOR，本轮未扩大修改范围。

上述执行结果仅作为 remediation 记录，不表示 P11-M1/P11-M2 已通过代码变更关闭，也不表示任何静态分析或测试通过。独立复验必须根据实际仓库状态重新核对这些发现。

### 修改范围

本轮记录更新只修改 `STATUS.md` 与本报告，不修改生产代码、测试或 Phase 11/12 计划文档。

### 验证

- 未执行 `dart format`、`flutter analyze` 或 `flutter test`。
- 未产生可声明为通过的定向或全量测试结果。
- 文档记录完成后仅执行文档 diff、`git diff --check` 与工作区范围检查。

### 交接

Phase 11 按本轮记录恢复为 `IMPLEMENTED`，等待独立复验，但不视为 `ACCEPTED`。独立复验应核对 P11-M1/P11-M2 的实际关闭状态，并在依赖可用环境重跑必要验证。Round 1–4 的失败历史必须继续保留；Phase 12 继续保持 `BLOCKED`。
