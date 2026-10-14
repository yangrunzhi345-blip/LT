# 角色卡生成预算 R5（错误分类、安全预算诊断、有限重试与恢复保护）独立只读审查

Status: PASSED WITH FINDINGS（仅限 R5 有限范围）
Acceptance Mode: Independent Review（另一 Agent 独立只读上下文）
Reviewer: 独立审查 Agent（与实现 Agent 不同执行上下文）
Date: 2026-10-14
Branch: `fix/character-generation-budget-checkpoint-20261013`
Reviewed commit: `fb4ba8f feat(resources): classify generation failures and carry safe budget diagnostics`
Note: 审查期间 HEAD 前进到 `47a36ce`（仅文档提交），工作区始终干净。

权威来源：`docs/character-generation-budget-root-cause-and-remediation.md`（6.4、9）、
`docs/codex/character-generation-budget-remediation-progress.md`、`AGENTS.md`。

## 1. 执行的命令与真实结果

```bash
flutter test --no-pub test/application/resources/character_generation_retry_recovery_sqlite_test.dart \
  test/application/resources/resource_generation_error_test.dart test/unit/app_error_localizer_test.dart
# +14 All tests passed  (exit 0)

flutter analyze --no-pub
# No issues found! (2.0s)  (exit 0)

git status --short   # empty（只读审查，未修改任何文件）
```

## 2. 已验证不变量

1. 分类：`resource_generation_error.dart:48-52` 不可行码；`:92-97` `_validationCode`
   `generation_budget→exceeded`、`content_requirements→contentIncomplete`、其余
   `contentInvalid`。与规格一致。
2. 仅安全参数：`_budgetDiagnostic :100-109` 键为
   ceiling/saved/remaining/reserve/minimum/allowed/unfinished；validator
   `:140-143/:155-158 {allowed,actual}`、`:180-183 {minimum,actual}`。无 prompt/正文/凭证。
3. `encodeGenerationDiagnostic :117-126` 无参数写纯码、有参数写 `DiagnosticEnvelope`；
   `resourceGenerationErrorFromCode :130-139` 双向解码，`tryDecode` 对非 JSON / legacy
   返回 null → `unknown`。向后兼容。
4. `resourceGenerationError(AppDomainError)` 原样返回（`:39-40`）经核验不破坏既有 consumer。
5. 不可行 0 请求：auto `coordinator:552-575`、manual `:843-846`、resume 经同一
   `generateAllParts` 闸门（`streaming service resumeGeneration:660-691`）。测试证据
   `calls==0`。有限重试不变（maxRetries=1 → 2 次调用）。
6. 未作 U6 决策：diff 未改阈值 / 配置 / schema / 人工认可；`contentIncomplete` 仅在
   `request.contentRequirements != null`（validator:170）即已确认契约时触发。

## 3. 发现

未解决发现：**BLOCKER=0、MAJOR=0、MINOR=2（含 1 项 MINOR/INFO）、INFO=2**

- **MINOR（会话层诊断丢失）**：`streaming_resource_generation_service.dart:574` 与
  `:581` 在 `success == false` 分支（即不可行的 auto / resume 路径，`generateAllParts`
  返回 false 而非抛异常）持久化 `failureError.code.name`（裸码），而非
  `encodeGenerationDiagnostic`；因此会话行丢失安全数字，重启后
  `resource_studio_controller.dart:238` 本地化 `session.errorMessage` 时数字渲染为 0。
  任务行的 `error_message` 保留数字（retry_recovery 测试断言），实时事件经
  `event.error` 带参数，故影响仅限持久化会话诊断，无崩溃/数据丢失。
- **MINOR/INFO**：`resourceGenerationError(AppDomainError)` 原样返回保留
  parameters/debugMessage/cause，旧实现只重建 code；已核验非破坏性。
- **INFO**：resume 测试只断言 `calls==0`，未覆盖上述会话诊断。
- **INFO**：规格 §6.4 可选列出 target/frozenE/contractVersion，实现未含（与任务显式
  列表一致，无影响）。

## 4. 未验证

- 全仓 `flutter test`；真实模型 / 设备 / UI→SQLite 端到端；mutation 证伪；非 Linux 构建；
  未深入审查文档提交 `47a36ce`。

## 5. 裁决

- Status: **PASSED WITH FINDINGS**（仅限 R5 范围）
- Acceptance Mode: **Independent Review**
- 未解决发现：**BLOCKER=0、MAJOR=0、MINOR=2、INFO=2**
- 结论：R5 在其范围内正确且安全，无阻断问题。

## 6. 审查后修复（Remediation）

针对本节 MINOR（会话层诊断丢失），执行方在同一工作单元内做了最小修复并补充测试：

- `streaming_resource_generation_service.dart` `success == false` 分支改用
  `encodeGenerationDiagnostic(failureError)` 写入会话行与事件 errorMessage（与抛异常
  路径一致）；无参数时仍为纯码，故纯码断言不变。
- `character_generation_retry_recovery_sqlite_test.dart` 的 resume 用例新增断言：不可行
  运行的会话 `errorMessage` 解码回 `resourceGenerationBudgetInfeasible` 且保留
  `minimum=300` / `ceiling=1200`。
- 复核：`character_generation_retry_recovery_sqlite_test` + `streaming_resource_generation_service_test`
  + `streaming_generation_lifecycle_recovery_test` **52 PASS**，退出码 0；
  `flutter analyze` 零问题。日志 `/tmp/lt-r5-fix.log`。
