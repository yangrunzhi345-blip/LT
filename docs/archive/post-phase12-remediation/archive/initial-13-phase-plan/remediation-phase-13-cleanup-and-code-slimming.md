# Remediation Phase 13 — Cleanup & Code Slimming

> **Root Cause**: RC-13
> **Findings**: C1–C13（C14 已并入 R11）
> **Depends On**: R01–R12 全部 `ACCEPTED`
> **Document status**: BLOCKED

---

## 1. Purpose

Phase 12 删除旧子系统后，仓库仍残留一批确认无生产引用的代码与技术债。本 Phase 负责在 **correctness
全部稳定之后**安全删除它们，降低维护面。

本 Phase 的核心不是“删除”，而是**证明可以安全删除**：`rg` 无引用**不是**充分证据。每一项都必须检查
动态引用、序列化、反序列化、migration、DB 兼容、反射、测试、动态路由与 JSON 协议。

## 2. Audit Findings Covered

```text
- C1   Scene-approval 后端孤儿（controller/provider/repo 方法）
- C2   resource_context_compressor（仅测试引用）
- C3   AppSection.creation/data + chat_provider 创建项目导航死代码
- C4   重复 PresetManager（prompt_preset.dart vs preset_manager.dart）
- C5   死多角色队列访问器
- C6   generation_request_scheduler 不可达 provider-id 分支
- C7   import use-case 死参数 —— 已在 R11 处理（本 Phase 不重复）
- C8   重复 viewport 测试 helper
- C9   过期文档注释（riverpod_providers:289-294）
- C10  LLM 死代码（completeFim、Anthropic 分支）
- C11  其它死方法（buildJsonBody / generateStructuredJson / toResourceTree /
       temperatureOverride / generateDetailedWorldviewCoordinatorForTesting）
- C12  status_toast 禁用死代码
- C13  死赋值 / 自拷贝（_requestedStops 泄漏已由 R01 修复）
```

**不得删除**（即使看起来无引用）：
- `findInterruptedSessions` / `recover()` / `recoverInterruptedGeneration`
  —— 已被 R01 接线为生产恢复路径。
- `PartGenerationParser` / `PartGenerationResponse` —— R08 后若仍被测试使用则保留；仅在确认无任何
  消费者时才是候选。
- v28 `quest_type` 列与 `dropLegacyQuestAndMapTables` —— migration 兼容，必须保留。

## 3. 删除前置协议（每一项都必须执行）

对每个候选符号 `S`：

```text
1. rg -n "\bS\b" lib test benchmark docs          （直接引用）
2. rg -n "S" lib test  （宽松，捕获字符串形式引用，如反射/路由/序列化 key）
3. 检查是否为 SQLite 列名/JSON key/enum storageValue：若是，必须检查 migration 与读写路径
4. git log --oneline -S "S" -- lib test           （确认是否曾被动态使用/即将启用）
5. 检查是否被 dynamic invoke、反射、路由表、协议字符串引用
6. 只有 1–5 全部证明“无动态/序列化/migration/协议依赖”，才允许删除
7. 删除后必须：dart format、flutter analyze、flutter test 全绿
```

若任一证据不足 → 标记 `DEFERRED`，保留代码并记录原因。

## 4. Candidate Details

### C1 — Scene-approval 后端孤儿
```text
file: lib/controllers/scene_approval_controller.dart
      lib/providers/riverpod_providers.dart:218-221（sceneApprovalControllerProvider）
      lib/providers/chat_provider.dart:509-510,522-528
      lib/providers/adventure_provider.dart:753-835
      lib/services/repositories/adventure_repository*.dart（相关方法）
evidence: sceneApprovalControllerProvider 全仓零消费者
verification: 需确认 adventure_repository 的相关方法只被该簇调用；若被其它路径使用则只删 UI/provider
risk: low（但 repo 方法删除需确认 migration/序列化无引用）
```

### C2 — resource_context_compressor
```text
file: lib/application/resources/resource_context_compressor.dart
evidence: 唯一 import 来自 test/application/resources/resource_context_compressor_test.dart
decision: 若产品仍需要该压缩能力 → DEFERRED；否则删除文件与测试
```

### C3 — AppSection.creation/data + 创建项目导航
```text
file: lib/models/app_section.dart:6-8
      lib/providers/chat_provider.dart:107-115,162-192（_currentCreationProjectId 等）
evidence: 全仓零调用；MainGate 用 default → LandingScreen
verification: 确认 AppSection 是否被持久化（若是则保留枚举值，只删导航方法）
```

### C4 — 重复 PresetManager
```text
file: lib/models/prompt_preset.dart:145（静态工具类，零调用）
      lib/managers/preset_manager.dart:9（被 library_provider.dart:28 使用）
decision: 删除 models 中的重复类，保留 PromptPreset 数据类
```

### C5 — 死多角色队列访问器
```text
file: lib/providers/messaging_provider.dart:196
      lib/managers/multi_char_manager.dart:12
      lib/providers/chat_provider.dart:858-859（deprecated delegate）
verification: 确认无外部/测试调用
```

### C6 — generation_request_scheduler 不可达 provider-id 分支
```text
file: lib/services/generation_request_scheduler.dart:15-33
evidence: providerId 恒为 config.provider.name，而 LLMProvider 仅 {deepseek, custom}
verification: 确认 LLMProvider 枚举确为 2 值；若未来计划扩展则 DEFERRED
```

### C7 — 已在 R11 处理
```text
见 remediation-phase-11-production-wiring-convergence.md Step 3
本 Phase 不重复。
```

### C8 — 重复 viewport 测试 helper
```text
file: test/helpers/responsive_test_helper.dart:21（setViewport，8 使用者）
      test/support/viewport_test_helper.dart:36（setTestViewport/TestViewports，2 使用者）
decision: 统一为一个（保留语义更完整者），迁移调用点；AGENTS.md 要求复用统一 helper
verification: 确认两者的 reset 语义差异并合并测试
```

### C9 — 过期文档注释
```text
file: lib/providers/riverpod_providers.dart:289-294
evidence: 注释称 per-instance counter，实际为 static int _idSequence（resource_revision_repository.dart:140,587）
decision: 仅修正注释
```

### C10 — LLM 死代码
```text
file: lib/services/llm_service.dart:670（completeFim，零调用）
      lib/services/llm_service.dart:251,292,493-654（Anthropic 分支，usesAnthropicMessagesApi 恒 false）
decision: 删除 completeFim；Anthropic 分支建议 DEFERRED（可能为未来协议预留），若删除需记录
注意: Anthropic 的 joinedText 会丢弃图片 part（llm_message.dart:130-131）——若保留分支，必须记录该
      缺陷或一并修复，避免未来启用时成为 BLOCKER
```

### C11 — 其它死方法
```text
file: lib/utils/ai_adventure_utils.dart:7（buildJsonBody）
      lib/controllers/adventure_ai_controller.dart:110（generateStructuredJson）
      lib/domain/resources/resource_revision.dart:323（toResourceTree；且对缺失 metadata['type'] 会抛错）
      lib/services/llm_task_policy.dart:131（temperatureOverride 无调用方传入）
      lib/services/ai_generator_service.dart:1114（generateDetailedWorldviewCoordinatorForTesting，
        R10 后与生产共享策略；若仅测试使用可保留，若测试改用生产路径则删除）
verification: 逐项按 §3 协议
```

### C12 — status_toast
```text
file: lib/screens/chat/widgets/status_toast.dart:10（_enabled=false）
verification: 若确认永不启用，删除；否则保留
```

### C13 — 死赋值 / 自拷贝
```text
file: lib/application/resources/part_generation_coordinator.dart:228,294（firstTerminalError 赋值未读）
      lib/features/resource_studio/presentation/controllers/resource_studio_controller.dart:167,186
        （partContents.addAll(_state.partContents) 自拷贝 no-op）
note: _requestedStops 泄漏已在 R01 修复，本 Phase 只清理剩余死代码
```

## 5. Root Cause

Phase 12 只删除了“旧 chat 孤儿簇 / 旧 NPC 子系统簇”，未处理跨阶段积累的：
- 被新实现取代但未删除的重复类（C4/C8）；
- 已废弃但保留的枚举值/导航（C3/C5/C6）；
- 试验性/预留方法（C10/C11/C12）；
- 纯技术债（C9/C13）。

这些不属于任何 correctness 根因，集中在本 Phase 处置。

## 6. Required Contract After Remediation

1. 删除的每个符号都经过 §3 协议，并在本 Phase 报告中记录证据。
2. 不删除任何 migration/序列化/SQLite 列/JSON key 依赖的代码。
3. 不删除 R01/R08/R10 已接线或暂留的符号（除非其 Phase 明确判定）。
4. 删除后 `dart format` / `flutter analyze` / `flutter test` / `git diff --check` 全绿。
5. 删除以独立 commit 提交，便于回滚。

## 7. Implementation Plan

### Step 1 — 生成候选清单与证据
- 对 C1–C13 逐项执行 §3 协议，产出“DELETE / DEFERRED + 原因”表。

### Step 2 — 分簇删除（每簇一个 commit）
```text
commit 1: C4 + C8（重复实现收敛）
commit 2: C1 + C3 + C5 + C6（死导航/枚举/访问器）
commit 3: C10 + C11 + C12（死方法/禁用 UI）
commit 4: C9 + C13（注释与死赋值）
commit 5: C2（压缩器，若判定删除）
```
- 每个 commit 后运行完整门禁。

### Step 3 — 新增架构守护测试（可选但推荐）
```text
新增 test/architecture/no_dead_legacy_references_test.dart：
  - 对已删除符号做“不应再出现”的断言（防止未来重新引入）
  - 对必须保留的 migration 符号做“必须仍存在”的断言
```

## 8. Design Decisions

### 8.1 是否“一次性全删”
**否。** 按簇分 commit，便于定位回归与回滚。

### 8.2 不确定项如何处理
**DEFERRED + 记录原因**。不得凭 `rg` 无引用强删。

### 8.3 C10 Anthropic 分支
**建议 DEFERRED**（协议预留）。若删除，必须同时删除其依赖的 `usesAnthropicMessagesApi` 分支与
`_doSendAnthropicStreamDetailed`；若保留，必须在代码注释中记录 `joinedText` 丢弃图片 part 的缺陷。

## 9. Database Impact

```text
No schema change required.
- 不删除任何表/列。
- 若删除的代码涉及 migration 中的符号，必须 DEFERRED。
- 若删除 enum 值（如 AppSection.creation），必须确认其未被持久化；若被持久化则保留。
- 回滚为 revert 对应 commit。
```

## 10. Concurrency / Sequence

本 Phase 不涉及并发逻辑；但删除前必须确认无初始化顺序依赖（例如某个 provider 的副作用），删除后
用全量测试验证启动路径（`test/widget_test.dart` 等）不回归。

## 11. Files Expected To Change

```text
Production（Expected，删除/编辑，视证据而定）:
- lib/controllers/scene_approval_controller.dart
- lib/providers/riverpod_providers.dart
- lib/providers/chat_provider.dart
- lib/providers/adventure_provider.dart
- lib/application/resources/resource_context_compressor.dart
- lib/models/app_section.dart
- lib/models/prompt_preset.dart
- lib/providers/messaging_provider.dart
- lib/managers/multi_char_manager.dart
- lib/services/generation_request_scheduler.dart
- lib/services/llm_service.dart
- lib/utils/ai_adventure_utils.dart
- lib/controllers/adventure_ai_controller.dart
- lib/domain/resources/resource_revision.dart
- lib/services/llm_task_policy.dart
- lib/screens/chat/widgets/status_toast.dart
- lib/application/resources/part_generation_coordinator.dart
- lib/features/resource_studio/presentation/controllers/resource_studio_controller.dart

Tests（Expected）:
- 迁移 test/helpers/responsive_test_helper.dart 与 test/support/viewport_test_helper.dart 的调用点
- 删除被删符号对应的测试（若测试本身只测死代码）
- 新增 test/architecture/no_dead_legacy_references_test.dart

Forbidden / should not be touched:
- 任何 migration / 表结构 / schemaVersion
- findInterruptedSessions / recover / recoverInterruptedGeneration（R01 已接线）
- attempt/lease/CAS 守卫
- v28 quest_type 列与 dropLegacyQuestAndMapTables
```

## 12. Test Plan

### TEST R13-01（删除后全量门禁）
```text
When:  每个删除 commit 之后
Then:  dart format 0 changed；flutter analyze 0 issues；flutter test 全绿；git diff --check clean
```

### TEST R13-02（架构守护）
```text
Given: no_dead_legacy_references_test.dart
When:  运行
Then:  已删除符号不再出现；必须保留的 migration 符号仍存在
```

### TEST R13-03（启动路径）
```text
Given: 删除后
When:  flutter test test/widget_test.dart（或等价启动测试）
Then:  应用 shell 正常初始化，无 provider 初始化回归
```

## 13. Mutation / Negative Verification

本 Phase 的“负向验证”体现为：对每个保留的 migration/协议符号，人为删除其在代码中的使用会导致测试
失败（由既有 migration/序列化测试覆盖）。在报告中记录：

```text
- 删除 v28 quest_type 相关 migration → database_migration_* 测试必须失败
- 删除 AppSection 被持久化值（若存在）→ 对应读取测试必须失败
```

## 14. Acceptance Criteria

```text
AC-R13-01 每个候选项有 DELETE 或 DEFERRED 的书面证据。
AC-R13-02 不删除任何 migration/序列化/SQLite/协议依赖。
AC-R13-03 删除后全量门禁通过。
AC-R13-04 新增架构守护测试（若实施）。
AC-R13-05 每个删除簇有独立可回滚 commit。
```

## 15. Required Verification Commands

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
git diff --check
git status --short
```

## 16. Out of Scope

- 不修任何 correctness（若发现新 bug，记录并转回对应 Phase）；
- 不重构；
- 不删除 migration/schema；
- 不新增功能。

## 17. Rollback / Failure Safety

- 每簇独立 commit，可单独 revert。
- 若某删除导致测试失败 → 立即 `git revert` 该 commit，并把该项标记 DEFERRED。
- 无数据库副作用。

## 18. OPEN QUESTION

```text
Q1: C1 的 adventure_repository 相关方法是否只被 scene-approval 簇调用？需完整调用链确认。
Q2: AppSection 是否被持久化（SharedPreferences/SQLite）？若是，枚举值必须保留。
Q3: C10 Anthropic 分支是否有明确的路线图？无则建议 DEFERRED 并记录 joinedText 缺陷。
Q4: C2 resource_context_compressor 是否仍被产品需要（例如作为离线压缩回退）？
```

## 19. Handoff Notes

- 本 Phase 必须在 R01–R12 全部 ACCEPTED 后开始；不得与 correctness 修复并行。
- 删除完成后建议触发一次轻量级全项目复审（或至少运行完整门禁 + 启动测试）。
