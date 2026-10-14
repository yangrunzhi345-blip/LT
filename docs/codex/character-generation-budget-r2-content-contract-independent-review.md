# 角色卡生成预算 R2（正文有效性与完成状态）独立只读审查

Status: PASSED WITH FINDINGS（仅限 R2 有限范围）
Acceptance Mode: Independent Review（由另一 Agent 在独立只读上下文中完成）
Reviewer: 独立审查 Agent（与实现 Agent 不同的执行上下文）
Date: 2026-10-14
Branch: `fix/character-generation-budget-checkpoint-20261013`
Reviewed commit: `064eb42 fix(resources): enforce content contract and K cap at Part completion`
Baseline parent: `58b6e17`

权威来源：`docs/character-generation-budget-root-cause-and-remediation.md`（6.1、6.3、
6.4、7.2、8、10 Phase 4）、`docs/codex/character-generation-budget-remediation-progress.md`、
`docs/codex/character-generation-budget-r2-content-contract-integrated-review.md`、
`docs/codex/character-generation-budget-r1-reservation-independent-review.md`（MINOR-1）、
`docs/codex/character-generation-budget-phase1-independent-review.md`、`AGENTS.md`。

审查方式：严格只读。未编辑 / 创建 / 删除任何仓库文件；未 `git add/commit/push/reset/
clean/stash`；未修改测试以制造 PASS；未运行付费 API、未读取用户数据库。结束时
`git status --short` 为空。

---

## 1. 审查文件

- `lib/application/resources/part_generation_validator.dart`（diff + 全文）
- `lib/application/resources/resource_generation_task_repository.dart`（diff + 全文，
  含 `commitPartContent`、`_contentRequirementsInTransaction`、`_requirementFor`、
  `_budgetAllocationInTransaction`）
- `lib/application/resources/resource_generation_error.dart`
- `lib/application/resources/part_generation_coordinator.dart`
- `lib/application/resources/part_content_commit_service.dart`（手动保存路径）
- `lib/domain/resources/content_requirements.dart`、`generation_budget_allocation.dart`、
  `resource_limits.dart`
- `lib/application/resources/blueprint_parser.dart`、`blueprint_validator.dart`
- `test/application/resources/character_generation_content_contract_sqlite_test.dart`、
  `part_generation_validator_test.dart`、`generation_aggregate_budget_sqlite_test.dart`

## 2. 执行的命令与真实结果

```bash
flutter test --no-pub character_generation_content_contract_sqlite_test.dart \
  part_generation_validator_test.dart generation_aggregate_budget_sqlite_test.dart
# +60 All tests passed  (exit 0)

flutter analyze --no-pub
# No issues found!  (exit 0)

flutter test --no-pub resource_generation_task_repository_test.dart \
  r02_part_content_source_cas_test.dart retry_failed_parts_test.dart \
  content_requirements_sqlite_test.dart character_generation_budget_reservation_sqlite_test.dart
# +35 All tests passed  (exit 0)

flutter test --no-pub section_consistency_streaming_regeneration_test.dart \
  part_generation_coordinator_test.dart streaming_generation_lifecycle_recovery_test.dart \
  resource_generation_task_repository_test.dart
# +39 All tests passed  (exit 0)
```

## 3. 已验证不变量（逐项核对 R2 声明）

- **C1 ✔** Validator 第 8b 步（`part_generation_validator.dart:149-169`）在
  `request.contentRequirements` 非空时经 `PartContentRequirementsValidator.validate`
  校验，抛 `PartGenerationValidationException(field:'content_requirements')`；null 保持
  legacy 放行。narrative/scalar/structured/legacy 矩阵测试通过。
- **C2 ✔** `commitPartContent`（`resource_generation_task_repository.dart:756-782`）在事务内
  从确认蓝图重读契约并重新施加 `K=3000`，二者均位于 `captureBeforeWrite`（:839）与任何
  `resource_parts` 写入（:851）之前，且与累计 C + future reserve（:784-828）同一事务。
  符合规格 §7.2 提交条件。
- **C3 ✔** 无效正文不会 completed、不会覆盖已保存正文。`lib/` 中唯一写
  `task status='completed'` 的位置是 `commitPartContent:899`，先于它的守卫使被拒事务
  全回滚（“a refused candidate never overwrites an existing committed body”断言正文保留
  且 revision head 为 null）。
- **C4 ✔** legacy null 契约保持放行（返回 `needsContentReview`）；历史短 completed 正文
  逐字保留、0 模型调用。
- **C5 ✔** 新守卫先于 R1 allocation/ceiling/reserve 块，同事务；R1 逻辑未改动。
  R1 MINOR-1（提交层 `len<=K`）已关闭。
- **C6 ✔** 错误映射正确：`resource_generation_error.dart` 仅将
  `PartGenerationValidationException(field:'generation_budget')` 归为 budget-exceeded；
  `content_requirements` 落到 `resourceContentInvalid`（:37），无错配。

补充核对：`_contentRequirementsInTransaction` 解析蓝图本地 Part id 的方式与
`_requirementFor` 一致（去除 `${resourceId}_`）；两次蓝图读取在同一 SQLite 事务快照内，
无穿插写入，保持一致；`PartContentRequirementsValidator.validate` 只会抛
`ContentRequirementException`（jsonDecode 的 FormatException 在内部捕获）；validator 在
流式与非流式两条路径都执行（单次调用 `coordinator:1443`，请求在 :1079 构建）；`response.status`
从不用于标记任务 completed；手动保存走 `PartContentCommitService.applyContent →
updatePartInTransaction`，不经 `commitPartContent`，故 K 守卫不影响手动保存；
`commitPartContent` 在 `lib/` 只有 coordinator:1504 一个调用方。

`generation_aggregate_budget_sqlite_test.dart` 的夹具适配未被削弱：新元组确实落在 C 或
C+1（由 `expect(total==ceiling||total==ceiling+1)` 守护）；`candidate = min(total,K) ≤ K`
使 K 守卫不触发，拒绝仅由 `projected = savedOther+candidate = total > C` 驱动；无断言被
删除 / skip / 放宽，并**新增**了兄弟 Part 未被改动的断言。

## 4. 发现

未解决发现：**BLOCKER=0、MAJOR=0、MINOR=2、INFO=3**

- **MINOR-1（性能）**：`commitPartContent` 现在解析蓝图 JSON 两次
  （`_contentRequirementsInTransaction` 与 `_budgetAllocationInTransaction`，
  `resource_generation_task_repository.dart:756,784`）。本地单用户事务下可忽略，无正确性
  影响。建议后续将契约并入 allocation 快照一次读取。
- **MINOR-2（U6 边界）**：因 Planner 尚不产出 `contentRequirements`，新任务默认 legacy，
  1–2 字 narrative 仍可能 completed。这是已承认的 U6 决策缺口，不是 R2 缺陷 —— R2 在契约
  确认前正确地不做任何拒绝。
- **INFO**：诊断不一致 —— validator 置 `expected=validationProfile.name`
  （`part_generation_validator.dart:165`），commit 置 `expected=kind.name`（:770），
  同一失败的展示字段不同，纯外观。
- **INFO**：K 守卫现在也作用于 legacy（null 契约）Part，是对 >K 直写路径的窄行为变化；
  生产路径不可达（accumulator 在 `generation_patch_parser.dart:418-420` 超 K 即抛，
  validator 亦将请求限制到 `D_i=min(K,…)`）。
- **INFO**：若 `PartContentRequirementsValidator.validate` 抛非 `ContentRequirementException`
  异常，会映射为 `unknown` 而非 content-invalid；当前 validator 抛点穷尽，不可达。

## 5. 本次未验证

- 全仓 `flutter test` 回归（仅执行了定向 + 14 个文件）。
- 真实模型 / 真实设备 / UI→SQLite E50 端到端（未使用凭证或设备）。
- 独立 mutation 复现（未临时回退 `lib/` 证伪；实现方自报的 mutation 证据未被独立复现）。
- 覆盖 `commitPartContent` 的流式测试替身
  （`streaming_resource_generation_service_test.dart:1322`、
  `streaming_generation_lifecycle_recovery_test.dart:677`）未深入执行。
- 额外蓝图解析的性能测量。

## 6. 裁决

- Status: **PASSED WITH FINDINGS**（仅限 R2 / Work Unit 2 范围）
- Acceptance Mode: **Independent Review**
- 未解决发现：**BLOCKER=0、MAJOR=0、MINOR=2、INFO=3**
- 结论：R2 六项声明全部成立，无阻断问题需修复。两项 MINOR 为性能与已承认 U6 边界，
  三项 INFO 为外观 / 不可达边界。整体 Phase 1–6 与任务整体仍未 ACCEPTED。
