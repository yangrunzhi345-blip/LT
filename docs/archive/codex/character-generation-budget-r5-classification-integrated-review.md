# 角色卡生成预算 R5（错误分类、安全预算诊断、有限重试与恢复保护）审查报告

Status: PASSED（仅限 R5 有限范围）
Acceptance Mode: Integrated Single-Agent Review（执行同一 Agent 复查，非独立审查）
Date: 2026-10-14
Branch: `fix/character-generation-budget-checkpoint-20261013`
Reviewed commit: `fb4ba8f feat(resources): classify generation failures and carry safe budget diagnostics`
Baseline parent: `b79b0ac`

权威来源：`docs/character-generation-budget-root-cause-and-remediation.md`（6.4、9、
10 Phase 5、13、14.2）、`docs/codex/character-generation-budget-remediation-progress.md`、
`AGENTS.md`。前序已局部通过：Phase 1、R3、R4、R6、R1、R2。

> **验收模式声明**：本报告由实现同一 Agent 复查生成，按 `AGENTS.md` 只能称 Integrated
> Review，不构成 Independent Review。同一提交的独立只读审查由另一 Agent 单独执行，结果
> 另见（若在编写时尚未返回，则以该独立报告为准）。

## 1. 变更文件

- `lib/domain/errors/app_error.dart`（+2 code）
- `lib/application/resources/resource_generation_error.dart`（分类 + 安全参数 + 编解码）
- `lib/application/resources/part_generation_validator.dart`（异常携带安全参数）
- `lib/application/resources/part_generation_coordinator.dart`（持久化/回调/exhaustBudget）
- `lib/application/resources/streaming_resource_generation_service.dart`（session 失败码编码）
- `lib/core/localization/app_error_localizer.dart` + 6 个 ARB + 生成文件
- `test/application/resources/resource_generation_error_test.dart`（+3 分类/往返/本地化用例）
- `test/application/resources/character_generation_retry_recovery_sqlite_test.dart`（新增 5 例）

未新增 schema / migration；未改动 A / K / E；未删除或改写已保存正文；未读取用户数据库。

## 2. 真实执行的命令与结果

```bash
flutter test --no-pub test/application/resources/character_generation_retry_recovery_sqlite_test.dart \
  test/application/resources/resource_generation_error_test.dart
# +12 All tests passed  (exit 0)  /tmp/lt-r5-new2.log

flutter test --no-pub test/unit/app_error_localizer_test.dart \
  test/application/resources/resource_generation_error_test.dart \
  test/application/resources/character_generation_budget_reservation_sqlite_test.dart \
  test/application/resources/character_generation_content_contract_sqlite_test.dart \
  test/application/resources/patch_sequence_conflict_sqlite_test.dart \
  test/application/resources/p0_malformed_ndjson_spin_test.dart \
  test/application/resources/streaming_generation_lifecycle_recovery_test.dart
# +55 All tests passed  (exit 0)  /tmp/lt-r5-tests1.log

flutter test --no-pub test/application/resources/streaming_resource_generation_service_test.dart \
  test/application/resources/streaming_generation_lifecycle_recovery_test.dart \
  test/application/resources/section_consistency_streaming_regeneration_test.dart
# +48 All tests passed  (exit 0)  /tmp/lt-r5-streaming.log

flutter test --no-pub test/application/resources test/unit
# +2012 ~1 All tests passed (1 pre-existing skip)  (exit 0)  /tmp/lt-r5-regression.log

flutter test --no-pub test/widget/resource_studio_test.dart \
  test/widget/resource_studio_retry_failed_parts_test.dart \
  test/widget/resource_ai_create_budget_input_test.dart
# +71 All tests passed  (exit 0)  /tmp/lt-r5-widget.log

flutter test --no-pub test/application/adventure test/application/narrative \
  test/application/runtime test/application/resource_library
# +122 All tests passed  (exit 0)  /tmp/lt-r5-app-other.log

flutter analyze --no-pub   # No issues found!  (exit 0)
dart format --output=none --set-exit-if-changed <8 变更文件>  # 0 changed
git diff --check            # exit 0
```

## 3. 已验证的不变量

1. **分类拆分**：`resourceGenerationError` 按领域类型 / 字段返回
   `resourceGenerationBudgetInfeasible`（不可行）、`resourceGenerationBudgetExceeded`
   （超授权量）、`resourceContentIncomplete`（内容契约不满足）、`resourceContentInvalid`
   （其他无效）。旧 `resourceGenerationBudgetExceeded` 语义收窄为“本次输出超量”，不再吞并
   不可行。
2. **安全参数**：仅 `ceiling/saved/remaining/reserve/minimum/allowed/unfinished` 与
   `minimum/actual`、`allowed/actual`；无 prompt、正文、凭证、模型响应。单元测试断言具体
   数值。
3. **编解码与向后兼容**：`encodeGenerationDiagnostic` 无参数时写纯码名（历史行与既有
   consumer 不变，未滥用错误串塞 JSON），有参数时写既有安全 `DiagnosticEnvelope`；
   `resourceGenerationErrorFromCode` 同时解码并对历史纯码 / 任意旧文本安全降级为 unknown。
   往返测试覆盖码 + 参数。
4. **持久化一致性**：coordinator `_failureCode`、三处失败回调 errorMessage、
   `exhaustBudget`（关键修复：不再把已解码诊断压平为裸码）、streaming service session
   失败码，全部使用同一编码；因此不可行任务重开后仍能还原安全数字。`p0_malformed`
   （'unknown'）、`patch_sequence_conflict`（resourceParseFailed）等纯码断言不变。
5. **0 请求保证**：不可行任务在 auto（派发闸门）、manual（`retrySinglePart` 预检）、
   resume（`resumeGeneration → generateAllParts` 同一闸门）三条真实路径均 0 次 gateway
   调用，任务保持 failed/ready，未创建 attempt。
6. **有限重试**：偶发超量按每 pass `1+maxRetriesPerPart` 有限纠正（测试断言 2 次调用后
   终止），未新增无限重试。
7. **本地化**：6 locale 新增参数化键，`app_error_localizer` 渲染安全数字；穷尽式
   localizer 测试覆盖全部 `AppErrorCode.values`。
8. **数据安全 / U6**：无 schema、无阈值、无人工认可、无旧预算版本变更；契约与预算闸门
   均未放宽。

## 4. 未解决发现

未解决发现（R5 有限范围）：BLOCKER=0、MAJOR=0、MINOR=2

- **R5-MINOR-1**：`resourceGenerationError(AppDomainError)` 现在原样返回该错误（保留
  parameters/debugMessage/cause），而旧实现只取 code 重建。这是 R5 意图内的行为变化
  （保留安全数字），但属于可观察差异；已由全量资源 + unit（2012 PASS）与 streaming
  （48 PASS）回归确认未破坏既有 consumer。
- **R5-MINOR-2**：`retryDisposition` 未新增独立枚举字段，仍由既有 allocation /
  sourceConflict 闸门表达，避免过度抽象；若未来 UI 需要显式 disposition 展示，可在
  Phase 6 单独添加。

## 5. 明确未验证

- 真实模型 / 真实设备 / UI→SQLite E50 端到端。
- 全仓 `flutter test`（仅执行资源、unit、widget 资源、adventure/narrative/runtime/
  resource_library，合计约 2300+ 用例）。
- 独立 mutation 复现（未临时回退 lib/ 证伪）。
- 本报告为 Integrated Review；独立审查结论以另一 Agent 报告为准。

## 6. 裁决

- Status: **PASSED**（仅限 R5 / Work Unit 3 范围）
- Acceptance Mode: **Integrated Single-Agent Review**（非独立）
- 未解决发现：**BLOCKER=0、MAJOR=0、MINOR=2**
- 结论：错误分类、安全预算诊断、有限重试与恢复保护均按规格 §6.4/§9 实现；不可行任务在
  自动 / 手动 / 恢复三条路径 0 模型请求；安全数字跨重启可还原；未擅自决定 U6。整体
  Phase 1–6 与任务整体仍未 ACCEPTED。
