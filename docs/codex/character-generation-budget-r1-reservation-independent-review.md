# 角色卡生成预算 R1（Work Unit 1）：预算可行性与未来容量预留 独立只读审查

Status: PASSED
Acceptance Mode: Independent Review
Scope: R1 / ISSUE-01、04、05（统一预算可行性与 future capacity reservation）
Date: 2026-10-13
Branch: `fix/character-generation-budget-checkpoint-20261013`
Baseline / HEAD: `31fad52ed5d1415b0c4697d687f8fff6bfe3c854`
Working tree: uncommitted（实现方改动，非本次审查产生）

权威来源：
- `docs/character-generation-budget-root-cause-and-remediation.md`（6.2、7、9、10 Phase 3、11、13、14.2）
- `docs/architecture/configurable-generation-elasticity.md`（ADR-0003）
- `docs/codex/character-generation-budget-remediation-progress.md`
- `AGENTS.md`

不在本次审查范围（前序已独立通过）：Phase 1 内容契约基础设施、R3 协议冲突、R4 规划边界、R6 诊断。

审查方式：严格只读。未编辑、创建或删除任何 `lib/`、`test/`、schema、migration 文件；未 commit / push / reset / clean / stash；未修改测试以“制造 PASS”；未运行付费 API、未读取用户数据库。唯一新增文件为本报告。

---

## 1. 审查文件

新增：
- `lib/domain/resources/generation_budget_allocation.dart`
- `test/domain/resources/generation_budget_allocation_test.dart`
- `test/application/resources/character_generation_budget_reservation_sqlite_test.dart`

修改：
- `lib/domain/resources/resource_generation_protocol.dart`
- `lib/application/resources/resource_generation_task_repository.dart`
- `lib/application/resources/part_generation_coordinator.dart`
- `lib/application/resources/resource_generation_error.dart`
- `lib/application/resources/part_generation_prompt_builder.dart`
- `test/application/resources/generation_aggregate_budget_sqlite_test.dart`
- `test/application/resources/configurable_elastic_budget_sqlite_test.dart`
- `test/application/resources/elastic_budget_matrix_test.dart`

同时只读核对：`lib/application/resources/streaming_resource_generation_service.dart`、`blueprint_parser.dart`、`blueprint_validator.dart`、`resource_blueprint_repository.dart`、`lib/domain/resources/resource_blueprint.dart`、`content_requirements.dart`、`resource_limits.dart`、`lib/services/repositories/*`，以及全部受影响测试。

---

## 2. 执行的命令与真实结果

```bash
# 1) 目标测试（真实 SQLite fixture，无网络）
flutter test --no-pub --reporter expanded \
  test/domain/resources/generation_budget_allocation_test.dart \
  test/application/resources/character_generation_budget_reservation_sqlite_test.dart \
  test/application/resources/generation_aggregate_budget_sqlite_test.dart \
  test/application/resources/configurable_elastic_budget_sqlite_test.dart \
  test/application/resources/elastic_budget_matrix_test.dart \
  test/application/resources/part_generation_coordinator_test.dart \
  test/application/resources/retry_failed_parts_test.dart \
  test/application/resources/resource_generation_task_repository_test.dart \
  test/application/resources/r02_part_content_source_cas_test.dart \
  test/application/resources/phase9_concurrency_test.dart
# 结果：00:12 +110: All tests passed!  退出码 0
# 日志：/tmp/lt_r1_review_tests.log
# 新增文件用例数：generation_budget_allocation_test.dart = 12；character_generation_budget_reservation_sqlite_test.dart = 5

# 2) 静态分析
flutter analyze --no-pub
# 结果：Analyzing LT... No issues found! (ran in 1.9s)  退出码 0
# 日志：/tmp/lt_r1_review_analyze.log

# 3) 格式（11 个变更 Dart 文件）
dart format --output=none --set-exit-if-changed <changed files>
# 结果：Formatted 11 files (0 changed) in 0.07 seconds.  退出码 0

# 4) 空白/冲突标记
git diff --check
# 退出码 0（无输出）
```

补充只读检查：
- `rg "remainingBudget|_cumulativeCeilingInTransaction" lib/ test/` → 仅命中无关局部变量（prompt builder / response length guard），无被删除 API 的滞留引用。
- `rg "IPartGenerationBudgetReader|budgetAllocation" lib/ test/` → 无遗留只实现旧接口的 Fake/类。
- `rg "streamPartGeneration" lib/` → 唯一生产调用点 `part_generation_coordinator.dart:1298`，位于分配闸门之后。
- `rg "skip:|@Skip|markTestSkipped" <changed tests>` → 无命中（无 skip / 无删除断言）。
- 常量核对：A=60000/24000（+NPC 24000）、K=3000、default E=20、max E=50 —— 未改动。

---

## 3. 已验证的不变量

1. **单一一致预算快照**：`_budgetAllocationInTransaction` 在同一 `txn` 内读取确认蓝图、冻结 `elastic_percent`、其他 Part 实际正文、任务完成集合，一次性计算 `PartGenerationBudgetAllocation`；调度闸门、LLM 请求、事务提交消费同一结构。
2. **分配数学与规格一致**（逐条对照 7.2）：
   - `F_i = Σ max(0, m_j - saved_j)`，对“其他未完成且 required”的 Part 求和；`additionalMinimum` 实现该式。✓
   - `D_i = min(K, max(0, C - S_other - F_i))` → `dispatchableMaximum = roomAfterReserve<=0 ? 0 : min(roomAfterReserve, transportCap)`。✓
   - 可行条件 `m_i <= D_i` 且 `m_i <= p_i <= K`：由 `belowMinimum` / `planOutOfBounds` 覆盖。✓
3. **可行性顺序**：`planOutOfBounds → ceilingExhausted → minimumTotalExceedsCeiling → belowMinimum → feasible`；`budgetless`（ceiling==null）保留历史无 reserve 语义。边界情形由 `generation_budget_allocation_test.dart` 12 例独立验证（budgetless、ceilingExhausted、belowMinimum、minimumTotalExceedsCeiling、planOutOfBounds、optional reserve 0、meets-minimum reserve 0、below-minimum 只预留缺口、recommendedTarget 上界、负值与非法 cap fail-closed、fingerprint 变化）。
4. **不可行路径 0 模型请求**（四道闸门，全部在请求前）：
   - 调度派发闸门 `part_generation_coordinator.dart:549-573`（`isInfeasible` → `markRetryExhausted` → `continue`，先于 `consumeAttempt`）；
   - failed 重排分支 `:703-708`（命中即跳过，不 `markTaskReady`）；
   - `retrySinglePart` `:841-844`（在 `markTaskReady` / `_generateSinglePart` 之前抛 `PartGenerationBudgetInfeasibleException`，任务保持原状）；
   - `_generateSinglePart` 预派发闸门 `:908-911`（在 `startAttempt` 之前，不创建 lease）；以及派发后重新读取 `:1054-1061`（在 `buildSystemPrompt` / gateway 调用之前）。
   两处 LLM 调用分支（`_streamingGateway` 与 `_completer`）均在 `:1054` 之后。
5. **resume 汇流**：`resumeGeneration`（`streaming_resource_generation_service.dart:660`）→ `startGeneration` → `generateAllParts`（`:511`），因此恢复路径经过同一调度闸门。
6. **事务内提交复核且不可绕过**：`commitPartContent` 的 ceiling + reserve 复核位于同一 `db.transaction`（`:717-762`），在任何写入（`captureBeforeWrite` `:772`、`resource_parts` update `:784`）之前；拒绝时抛出发生在读事务阶段，Task/Attempt/Revision/正文/hash 全部不变。`allocation == null` 时回退到原 ceiling-only 守卫；`isBudgetless` 时与旧行为一致（无 ceiling guard）。
7. **调度收敛、无自旋/死锁**：不可行任务在本 pass 只被置为终态 `failed` 一次并加入本地 `budgetInfeasible` 集合；failed 重排分支跳过它；无其它可重排任务时 `scheduledRetry=false` → 循环返回 `false`。`markRetryExhausted` 只作用于 ready/failed/pending 行，不会降级 completed/cancelled。测试断言 `generateAllParts == false`、末段 `failed`、`attempts` 为空、`calls == 0`。
8. **数据安全**：无 schema / migration 改动；无 `A`/`K`/`E` 放宽；无正文截断、无重写已保存正文、无删除 attempt/revision；`frozenElasticPercent ?? defaultElasticPercent` 保证历史 NULL E 解析为 20%；无契约历史 Part 使用 legacy floor `minPartEstimatedLength = 10`，仍可正常生成（`character_generation_budget_reservation_sqlite_test.dart` 的 legacy 用例通过）。
9. **测试未削弱**：三处迁移 `remainingBudget → budgetAllocation(...).remaining` 仅替换 API，断言数值与语义不变（9600 / 8000 / `(8000*135)~/100` / `C - body.length` / 500）。`generation_aggregate_budget_sqlite_test.dart` 的 `attempts` 断言由 `hasLength(2)`（旧行为：先建 lease 再失败）改为 `isEmpty`，对应 R1 的目标新行为“不可行在 `startAttempt` 之前被拒、不创建 lease”，同时保留 `calls == 0`、`status == failed`、`activeCharacters == 9600`（更严格，而非放宽）。无 skip、无删除断言、无扩大生产上限。

---

## 4. 未解决发现

未解决发现：BLOCKER=0、MAJOR=0、MINOR=4

### MINOR-1：事务提交未复核单段传输上限 `len(b_i) <= K`
- 位置：`lib/application/resources/resource_generation_task_repository.dart:717-762`
- 规格：第 7.2 节要求在提交事务内满足 `内容契约通过、len(b_i)<=K、S_other+len(b_i)<=C、S_other+len(b_i)+F_i<=C`；实现只校验了后两个预算式。
- 影响与失败场景：LLM 路径不会触发——请求的 `maximumAcceptedCharacters = D_i`，而 `D_i = min(K, …)`，validator 已在请求前把正文限制在 ≤K；`PartContentCommitService`（用户手动保存）不经过 `commitPartContent`（`rg commitPartContent lib/` 仅命中 coordinator）。唯一可达路径是直接调用 repository 的测试/内部代码写入 >K 正文。因此真实风险低，且“内容契约通过”属于 R2/Phase 4 范围，本工作单元有意不实现。
- 建议：可在同一事务补 `len(b_i) <= ResourceLimits.maxPartCharacters`，或明确记录为 Phase 4 契约校验一并交付。

### MINOR-2：历史“超 K 规划”Part 的行为变化（硬失败 vs 旧上限生成）
- 位置：`lib/domain/resources/generation_budget_allocation.dart:213-215`（`plannedLength > transportCap → planOutOfBounds`）配合 coordinator 闸门。
- 影响与失败场景：R4 之后新确认蓝图已保证 `p_i <= 3000`，但 R4 明确“读取旧 confirmed 蓝图不追溯校验”。若存在 R4 之前确认、单段 `estimatedLength > 3000` 的旧任务，本改动会在派发前直接判 `planOutOfBounds` → 0 请求、任务 `failed`；旧行为是“派发并以 ≤3000 生成”。该行为更安全（避免自相矛盾规划），也可能是规格 7.2/边界表的预期，但属于旧任务的可观察行为变化。
- 建议：确认是否符合产品对遗留任务预期；如需保持旧任务可生成，可对未记录契约的 legacy 蓝图放宽上界判定，仅对新契约任务硬判。

### MINOR-3：`cancelled` 等非 completed 任务被计入 future reserve
- 位置：`lib/application/resources/resource_generation_task_repository.dart:602-615`（`unfinished` 仅排除 `completed`）
- 影响与失败场景：若同一资源内存在 `cancelled` 的未完成任务（或状态非 completed 但不会再生成为完成的任务），其 `minimumCharacters` 会被计入 `F_i`，使仍在派发的 Part 被高估 reserve、可能被误判 `belowMinimum`/`minimumTotalExceedsCeiling`。当前 `cancelTasks` 通常整体取消整资源，混合场景罕见。
- 建议：按规格语义明确 reserve 只统计“将生成的必填 Part”，或在文档中记录该边界。

### MINOR-4：ceiling 的 `targetCapacity` 改用 `blueprint_json` 而非 `target_capacity` 列
- 位置：`lib/application/resources/resource_generation_task_repository.dart:487-505, 617-626`（旧实现读 `target_capacity` 列）
- 影响与失败场景：写路径（`resource_blueprint_repository.dart:161,479`）始终同时写列与 JSON，正常数据二者一致；但 `ResourceBlueprint` 在 JSON 缺 `targetCapacity` 时回退到类型 nominal（`resource_blueprint.dart:240-241`），对“列有值、JSON 缺该键”的畸形/极旧行可能改变 C。已核对 `findBlueprint` 也走同一解析，故生成链在到达预算读取前已能解析该行，实际风险很低。
- 建议：如需严格等价，可在 JSON 缺 `targetCapacity` 时以列值为准（当前无此场景证据）。

---

## 5. 明确未验证的内容

以下内容本次**未**验证，也不被本报告的 PASSED 覆盖：

- **全仓回归**：仅运行了指定 10 个文件（110 PASS）。未运行全量 `flutter test`，未运行 widget / Linux 桌面 / Android / iOS / macOS 行为测试。
- **真实模型与真实设备**：未调用任何真实 LLM / 付费 API，未在模拟器或真机运行；无法给出真实模型遵循率、费用或现场恢复结论。
- **R2 / R5 与 UI 工作**：正文最低内容契约的生产闭环与完成判定（R2 / Phase 4）、安全错误数字与恢复 UI（R5 / Phase 5）、UI 预算显示与移动端 320px 验证（Phase 6 跨模块）均未审查。本工作单元只交付预算可行性与容量预留。
- **U6 产品决策**：narrative 最低阈值等产品默认值仍待批准；本实现仅使用“已确认契约 minimum，否则 legacy floor 10”，未擅自引入产品阈值。因此 legacy 无契约任务在 R=1–4 时仍可能被判定为“可行”（因 min=10），这是 U6 未决的已承认边界，不是本工作单元的缺陷。
- **并发 >1 的 reservation 释放设计**：DI 当前并发为 1；本实现未新增 lease-reservation 表，也未验证并发 >1 时的 reservation 释放（规格 6.2 已声明该设计需在启用并发前单独进行）。
- **迁移 / schema**：本次变更未触碰 schema；未重新运行 v49 迁移测试（前序已覆盖）。

---

## 6. 裁决

- Status: **PASSED**（仅限 R1 / Work Unit 1 范围）
- Acceptance Mode: **Independent Review**
- 未解决发现：**BLOCKER=0、MAJOR=0、MINOR=4**
- 结论：R1 根因的预算可行性 + 未来必填容量预留机制与规格 6.2/7.2 一致；不可行路径在四个闸门与事务提交中均为 0 模型请求；提交复核与正文写入同一 SQLite 事务且在任何写入之前；调度不产生自旋或死锁；保存正文、Part ID、DAG、冻结预算与 A/K/E 上限均未被破坏；三处测试 API 迁移未削弱断言，`attempts` 断言变更反映的是更强的新行为。四项 MINOR 均为低风险边界或已在规格中显式延期到 Phase 4/5 的事项，不阻断本工作单元通过。整体任务（Phase 1–6）仍未 ACCEPTED。
