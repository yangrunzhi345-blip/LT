# 角色卡生成预算 R2（正文有效性与完成状态）审查报告

Status: PASSED（仅限 R2 有限范围）
Acceptance Mode: Integrated Single-Agent Review（由执行同一 Agent 完成，非独立审查）
Date: 2026-10-14
Branch: `fix/character-generation-budget-checkpoint-20261013`
Baseline HEAD（执行前）：`58b6e17`（R1 进度文档提交后）

权威来源：
- `docs/character-generation-budget-root-cause-and-remediation.md`（6.1、6.3、7.2、8、9、10 Phase 4、11、13、14.2）
- `docs/codex/character-generation-budget-remediation-progress.md`
- `docs/codex/character-generation-budget-phase1-independent-review.md`
- `AGENTS.md`

不在本次范围（前序已局部通过）：Phase 1 内容契约基础设施、R1 预算预留、R3 协议冲突、R4 规划边界、R6 诊断。

> **验收模式声明**：本报告由执行实现的同一 Agent 在完成后复查生成。按 `AGENTS.md`
> 规定，同一 Agent 的复查只能称为 Integrated Review / Single-Agent Adversarial
> Review，**不构成 Independent Review**。真正的独立审查须由另一 Agent 或独立执行
> 上下文完成，仍待安排。不得据此报告宣称“独立验收”。

---

## 1. 变更文件

新增：
- `test/application/resources/character_generation_content_contract_sqlite_test.dart`（12 例，真实 SQLite）

修改：
- `lib/application/resources/part_generation_validator.dart`
- `lib/application/resources/resource_generation_task_repository.dart`
- `test/application/resources/part_generation_validator_test.dart`（+4 例）
- `test/application/resources/generation_aggregate_budget_sqlite_test.dart`（fixture 适配，见 §5）

未新增 schema / migration；未改动 A / K / E；未删除或重写任何已保存正文。
未读取用户数据库，未调用真实付费 API。

---

## 2. 真实执行的命令与结果

```bash
# 1) R2 定向生产链（真实 SQLite fixture）
flutter test --no-pub --reporter compact \
  test/application/resources/character_generation_content_contract_sqlite_test.dart \
  test/application/resources/part_generation_validator_test.dart \
  test/application/resources/generation_aggregate_budget_sqlite_test.dart
# 结果：+60 All tests passed!  退出码 0
# 日志：/tmp/lt-r2-final-check.log

# 2) 预算/契约/CAS/协调器组合回归（16 文件）
#    退出码 0；+177 All tests passed!  日志：/tmp/lt-budget-r2-tests2.log

# 3) 资源子系统扩大回归
flutter test --no-pub --reporter compact test/application/resources
# 结果：+844 All tests passed!  退出码 0  日志：/tmp/lt-budget-r2-resources-regression.log
#    （断点基线为 823 PASS；增量来自新增 R2 与 validator 用例）

# 4) 流式/生命周期/集成提交相关（含 integration soak）
#    退出码 0；+72 All tests passed!  日志：/tmp/lt-r2-extra.log

# 5) 静态分析 / 格式 / 空白
flutter analyze --no-pub            # No issues found! (ran in 4.5s)  退出码 0
dart format --output=none --set-exit-if-changed <5 变更 Dart 文件>
                                    # Formatted 5 files (0 changed)  退出码 0
git diff --check                    # 退出码 0（无输出）
```

负向证明（mutation probe）：临时将两个 `lib/` 文件还原为 R2 前内容后运行
`character_generation_content_contract_sqlite_test.dart`，7 个“拒绝”用例 FAIL、
5 个“接受/legacy”用例 PASS（`+5 -7`），证明新守卫确实改变了行为；随后从备份
byte-for-byte 还原，`sha256sum -c` 通过，复跑全部用例 PASS。

---

## 3. 已验证的不变量

1. **契约贯穿生产链**：`PartGenerationRequest.contentRequirements`（Phase 1 已接入
   coordinator 请求）在 `PartGenerationValidator.validate` 第 8b 步按 kind / profile
   / minimum 校验；同一规则在 `commitPartContent` 事务内以确认蓝图重新解析的契约再校验。
   narrative、scalar、structured 分别校验，非“仅非空即通过”。
2. **complete_part 不构成质量证明**：`GenerationPatchAccumulator.toResponse()` 恒置
   `status='completed'`，但内容契约在校验与提交两层独立判定；1–2 字 narrative 在容量
   充足时仍 `failed`，不写库、不 completed（T13/T14）。
3. **合法短 scalar 不被误拒**：scalar `minimum=1`、正文“导师”通过并 completed（T15）。
   多行 scalar 正文按 `invalidScalar` 拒绝。
4. **structured 必填字段**：缺字段（缺 `role`）拒绝；完整 JSON 对象通过（T15）。
5. **无效正文不写 completed / 不覆盖旧正文**：提交守卫位于 `captureBeforeWrite` 与
   任何 `resource_parts` 更新之前；被拒后 part 正文保持原值、revision head 不变、
   兄弟 Part 不变、task 保持 failed、attempt 可追溯（“a refused candidate never
   overwrites an existing committed body”）。
6. **R1 容量预留不被绕过**：内容契约与 K 守卫先于既有累计 C + future reserve 复核，
   三者同事务串行；R1 的四道派发闸门与事务复核逻辑未改动。
7. **提交层 K 守卫（R1 MINOR-1）**：同一事务补 `len(b_i) <= ResourceLimits.
   maxPartCharacters`（3000）。生成路径经 `D_i = min(K, …)` 已保证 ≤K，本守卫仅覆盖
   绕过 validator 的直写路径，属 defense-in-depth；不影响真实生成行为。
8. **SQLite 原子性与历史保护**：被拒提交全事务回滚；无契约（legacy null）Part 不被
   自动拒绝；`a legacy completed short body is never auto-modified` 断言历史 1 字正文
   逐字保留、任务仍 completed、0 次模型调用（T23）。
9. **数据安全**：无 schema / migration / A / K / E 放宽；`_contentRequirementsInTransaction`
   仅只读；未截断或改写正文。

---

## 4. 未解决发现

未解决发现（R2 有限范围）：BLOCKER=0、MAJOR=0、MINOR=2

### R2-MINOR-1：契约 validator 与 commit 重复解析蓝图
- 位置：`resource_generation_task_repository.dart` `commitPartContent` 现调用
  `_contentRequirementsInTransaction` 与 `_budgetAllocationInTransaction`，各自
  `_readBlueprintBudgetInTransaction` 解析一次蓝图 JSON。
- 影响：每次 Part 提交多一次 JSON 解析；单用户本地事务下开销可忽略，不影响正确性
  （同事务快照一致）。
- 建议：后续可将契约并入 allocation 返回值，一次读取，减少重复解析。

### R2-MINOR-2：无契约 Part 仍可“仅非空即完成”
- 位置：`PartContentRequirementsValidator.validate`（`requirements == null` →
  `needsContentReview`），validator 与 commit 均对 null 契约放行。
- 影响：由于当前 Planner 不产出 `contentRequirements`，新任务默认是 legacy，1–2 字
  narrative 仍可能 completed。这**不是 R2 缺陷**，而是 U6 未决的直接后果（见 §6）。
- 建议：待 U6 批准后由 Planner / 客户端 profile 产出契约，R2 的确定性校验即自动生效。

---

## 5. 测试夹具适配说明（非“放宽断言”）

`generation_aggregate_budget_sqlite_test.dart` 的“SQLite 提交边界”矩阵与
“target-boundary assembles at exactly C”用例原先直接经 `commitPartContent`
提交 >3000 的正文（4800 / 9600 / 14400 / 19200 / 24000、4×6000），该路径在
R1 review MINOR-1 中已被认定为“真实生成路径不可达、仅测试/内部直写可达”。

在补齐提交层 K 守卫后，这些测试写入被正确拒绝。适配方式（与 R4 对聚合夹具
“调整为每段合法 ≤3000，保留原聚合异常断言”的既有先例一致）：

- 矩阵改为 (target, total, accepted)：候选正文 = `min(total, K)`（合法），兄弟 Part
  直接写入 remainder，使运行总量仍精确落在 C（接受）或 C+1（拒绝）；新增断言
  `total == ceiling || total == ceiling + 1` 校验矩阵确实位于边界。
- target-boundary 用例改为 8 个 Part × 3000 = 24000（而非 4×6000），总量与
  readiness 断言不变。

**断言未放宽**：接受/拒绝边界（C 对 C+1）保持一致，且额外要求候选正文合法。
不存在删除、skip、修改预算上限或 mock 掉真实持久化路径。

---

## 6. 明确未验证 / U6 边界

以下内容本次未验证，PASSED 不覆盖：

- **U6 产品决策**：narrative/scalar/structured 的最低阈值、必填覆盖、legacy 审阅策略
  仍未确认。R2 未引入任何产品阈值；仅在契约已确认时执行确定性拒绝。因此**新任务在
  U6 批准且 Planner 产出契约前，1–2 字 narrative 的生产行为不改变**。这是已承认边界，
  不是缺陷。相关子项（Planner profile、legacy `needsContentReview` UI 信号）暂停等待
  U6，不猜测用户意图。
- **UI**：Studio 完成标签已由权威 task 状态派生
  （`resource_studio_outline.dart` `_statusLabel`、`resource_studio_controller.dart`
  `PartCompleted`）。因提交是唯一 completed 权威，R2 无需改动 UI 即可保证“无效正文
  不显示已生成”。“旧正文已保存 / 本次重生成失败”的区分与 legacy 审阅信号属
  R5 / Phase 5 与 U6 范围。
- **R5 失败分类**：`content_requirements` 目前映射既有 `resourceContentInvalid`，
  未新增 `contentIncomplete` / `retryDisposition` 持久化（R5 范围）。当前失败按既有
  有界重试处理。
- **R1 MINOR-2 / 3 / 4**：本次未处理（旧蓝图 planOutOfBounds、cancelled 计入 reserve、
  blueprint_json vs target_column）。
- **全仓回归 / 真实模型 / 真实设备 / UI→SQLite E50**：未执行。
- 组合运行中 `resource_creation_navigation_stack_test.dart` 存在与本次改动无关的
  顺序相关偶发失败：已确认在 R2 前的干净 HEAD 上同样复现（`/tmp/lt-r2-baseline-nav.log`），
  单文件运行 PASS。

---

## 7. 裁决

- Status: **PASSED**（仅限 R2 / Work Unit 2 范围）
- Acceptance Mode: **Integrated Single-Agent Review**（非独立；独立审查待安排）
- 未解决发现：**BLOCKER=0、MAJOR=0、MINOR=2**（R2-MINOR-1 性能、R2-MINOR-2 U6 边界）
- 结论：内容契约已贯穿“请求 → Validator → SQLite Commit”，complete_part 不再能越过
  正文有效性；无效正文不得写 completed，且不覆盖旧正文、不破坏 Attempt/Revision 一致性；
  legacy 无契约 Part 行为保持不变；提交层补齐 K 守卫（R1 MINOR-1）。R2 范围内未发现
  BLOCKER / MAJOR。整体 Phase 1–6 与任务整体仍未 ACCEPTED。
