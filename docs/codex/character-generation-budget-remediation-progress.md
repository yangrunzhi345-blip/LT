# 角色生成预算修复执行记录

任务权威：`../character-generation-budget-root-cause-and-remediation.md`、
`../architecture/configurable-generation-elasticity.md`、`../../AGENTS.md`。

Status: PAUSED / CHECKPOINT（整体未验收）
Acceptance Mode: Independent Review（已完成局部范围由另一 Agent 审查，完整阶段未验收）

## 基线与 Scope

- 2026-10-13 开始执行，main / HEAD `e63d161`；工作区干净。
- `git fetch origin` 成功，`HEAD...origin/main` 为 0/0。
- 审计代码基线 `01f6ed0` 后只有方案文档新增，没有生产代码漂移。
- 应用 `1.2.07+29` / SQLite v49；ADR-0003 确认时冻结 E，历史 NULL=20。
- 原实施授权按六个 Phase 修复统一资源生成链，禁止 push / 发布，保护用户库。
  2026-10-13 用户另行明确授权创建干净断点并推送 GitHub 分支；仅解除本断点分支的
  push 限制，不授权合并 main、发布产品或继续未完成实现。
- 未使用真实 API 或读取用户数据库。SQLite 测试只使用临时 fixture 数据库。

## Phase 1：契约与数据保护基础设施

Implementation: 基础设施已实现；完整阶段产品门禁待确认。
本地 milestone commit：`ea5de88 feat(resources): add versioned content requirement foundation`。

- `BlueprintPart.contentRequirements` 可选对象，包含 version、kind、required、
  minimumCharacters、受控 validationProfile、requiredFields、requiredHeadings。
- 缺字段保持 legacy null，不从标题推断类型，不批量修改旧正文或状态。
- 严格 parse / serialize、copy / equality / hash；拒绝未知版本、profile、非法类型、
  未授权字段，不能静默降级 legacy。
- 固定纯规则支持 narrative ATX 小节、单行 scalar、structured JSON 必填非空字段。
  narrative 排除 fenced / indented code 假标题和仅代码示例；最低有效内容采用
  trim 后 UTF-16 长度，资源预算仍使用未经修改原文的 String.length。
- 只建立可注入规则；没有为产品擅自选择默认阈值，也未接入 Planner / 生产请求 /
  commit。该生产闭环属于后续 Phase 3/4，不把纯规则通过称整体修复完成。
- 新增 SQLite 回归确认 optional JSON 契约保存、confirm 幂等、仓库重建、DAG。
  旧 completed 的 1/2 字正文、hash、Part/Section/resource、Task、Attempt、Revision
  逐表比较保持不变；schema 没有变更。

验证记录（本次真实执行）：

- 七组定向 `flutter test --no-pub --reporter expanded`：73 PASS，涵盖
  content_requirements、content_requirements_sqlite、blueprint_parser、
  blueprint_validator、part_generation_validator、r02_part_content_source_cas、
  resource_generation_task_repository。日志 `/tmp/lt-budget-phase1-tests.log`。
- 审查发现 narrative 结构绕过；新增负向测试在修复前 FAILED，日志
  `/tmp/lt-budget-phase1-negative-before.log`；修复后上述 73 测试 PASS。
- `flutter analyze --no-pub` 首轮和修复后复跑均零问题（最终 1.9s）。
- 变更文件 `dart format` 与 `git diff --check` PASS。
- 独立审查报告：`character-generation-budget-phase1-independent-review.md`
  裁决 PASSED（基础设施部分范围），未解决 BLOCKER/MAJOR/MINOR=0。
  独立执行另一组合七组测试 70 PASS、专门 CAS 10 PASS、并发/Revision 11 PASS，
  analyze/format/diff-check PASS。组合不同，计数不混合相加。
  不能把基础设施部分范围判定替代完整 Phase 1 产品门禁。

待产品决策（已提出具体选项，未答复不视为批准）：

1. narrative 最低是否采用计划的 40%（向上取整）及已确认小节；scalar 最低 1、
   需显式审阅确认；structured 已确认 JSON 必填键；legacy 只读审阅。
2. Phase 5 是否仅交付显式人工认可合格编辑/缩减候选，再恢复未完成章节，
   本期不增加改变旧任务预算版本功能。

## Phase 2 准备：R3 协议冲突守卫

本部分不依赖产品 minimum 默认值；没有以它替代完整 Phase 1/2 Gate。

- Accumulator 复用 ContentHasher SHA256，记录每个已应用事件的规范指纹与原始
  应用 offset；包含身份、op、text、summary、fail 信息，缺省 cursor 与相同正确
  显式 cursor 等价。不同载荷同 seq 抛 PatchSequenceConflictException，禁止响应导出。
- 保留全部有界指纹，默认最多 6002 新事件；允许逐 UTF-16 单位 append，空事件不能
  无限占用历史。超限和 terminal 后新事件显式解析失败，不静默遗忘旧指纹。
- 两种传输路径都将冲突投影为 resourceParseFailed 并发送验证失败事件。
- 重放没有协议/预览 callback 副作用；独立审查发现 Studio 消费重复 delta 导致暂时
  重复预览，已在 coordinator 过滤，仅发布新接受事件，无需扩大 UI 重构。
- 新增真实 SQLite streaming / collected 冲突与幂等测试，分割 JSON/Unicode/转义文本、
  无末尾换行；有效原文重生成失败逐表验证正文/hash、section/resource、revision 不变，
  旧完成 attempt 保留，新 failed attempt 可追溯。

真实验证：

- 修复前冲突回归 5 FAIL / 1 PASS：`/tmp/lt-budget-phase2-negative-before.log`。
- 预览 callback 回归修复前 2 FAIL / 3 PASS：
  `/tmp/lt-budget-phase2-preview-negative-before.log`。
- 最终含旧正文保护及 callback regression 的八组测试 62 PASS：
  `/tmp/lt-budget-phase2-tests.log`；包含 E 冻结矩阵、v49 migration 及原有协议/coordinator
  回归。旧正文 SQLite 单组复跑 5 PASS，不重复加总。
- 最终 `flutter analyze --no-pub` 零问题；五个变更 Dart 文件 format 0 changed；
  `git diff --check` PASS。
- 独立审查：`character-generation-budget-phase2-protocol-independent-review.md`，
  R3 有限范围 PASSED，未解决 BLOCKER/MAJOR/MINOR=0；独立另一组合八组 115 PASS
  （含 shared LLM consumer / transport、真实 CAS/Revision 并发），analyze/format/diff-check
  PASS。与执行方 62 项组合有重叠，不混合加总。完整 Phase 2 与整体仍未验收。

## 后续阶段

完整 Phase 2–6 仍待各自门禁；R1–R6 不宣称整体解决。
最终全仓回归、跨阶段 mutation 守卫验证、跨模块装配和最终独立审查尚未执行；
当前代码静态分析及 R6 局部 mutation 已通过，见下文，不替代最终验收。
整体不得标记 ACCEPTED；已确认的 MAJOR 根因仍需后续生产接入修复。

## R4：规划单段上界与显式最低量保护

2026-10-13 续执行：基线 `2144a40`，工作区干净；前一目标回合为 progress。
U6 尚无答复；本项属于第 14.2 节允许独立推进的基础预算 guard，不能替代完整 Phase 3。

- 总计划低于或等于 T 时也验证每段 `minimum ≤ estimatedLength ≤ 3000`。
- 总计划超过 T 时仍可合法归一化，采用已有确定性 largest-remainder 算法，
  保留每段已显式提供的契约最低量；不存在契约时保持历史规划下限 10。
- normalizer / validator 共用最低量读取与契约验证，不擅设 narrative 产品默认比例。
- plan / replan / direct confirm 的生产路径均执行守卫；无数据库结构、容量、E
  或旧正文修改。读取旧 confirmed 蓝图及其幂等确认不追溯校验。
- 聚合超预算测试夹具调整为每段合法 ≤3000，保留原 aggregate 异常与 plannedLength
  断言，不通过放宽断言制造 PASS。

真实验证：新回归修复前 3 FAIL / 6 PASS，`/tmp/lt-budget-r4-before.log`。
执行方五组 67 PASS；真实 SQLite 八场景 8 PASS，非法 plan/replan/confirm 的
resources/sections/parts/sessions/blueprints/tasks/attempts/revisions 逐表不变，
合法 normalize 后 ID/DAG 保持；日志 `/tmp/lt-budget-r4-tests.log`、
`/tmp/lt-budget-r4-sqlite.log`。analyze 零问题，format/diff-check PASS。

独立审查：`character-generation-budget-r4-planning-independent-review.md`，
R4 有限范围 PASSED，未解决 BLOCKER/MAJOR/MINOR=0；独立六组 63 PASS、10 项
精确边界探针 PASS、analyze/format/diff-check PASS。测试组合有重叠，不加总计数。
完整 Phase 3 和任务整体仍未 ACCEPTED。

## R6：独立诊断生命周期修复

- 真正创建 UI timer 时重设基线；新增 owner 复用现有 timer，不更改 interval 或阈值。
- 停止段标为 unobserved，GAP 只描述观测间隔，不能据此断言 CPU 阻塞。
  活跃首 tick 及后续真实延迟仍报告；连续 SSE 进展不被当成死锁。
- 默认单例继续使用 Stopwatch；测试只注入单调 elapsed，执行同一 Timer.periodic。
  无新依赖，不改变 timeout、流消费、业务数据库或网络逻辑。
- resetForTesting 清理自身 UI/watchdog timer、owners 与 heartbeat 状态；测试在 body
  finally 中释放 timer，符合 WidgetTester 在外层 tearDown 前检查 timer 的要求。

真实验证：最终三组 27 PASS，日志 `/tmp/lt-budget-r6-tests.log`。临时 mutation 分别
移除重启基线、允许追加 owner 改 interval，两组各 3 PASS / 1 FAIL，均由对应语义
断言杀死；文件已 byte-for-byte 恢复，再运行当前代码回归 PASS。
日志 `/tmp/lt-budget-r6-mutation-restart.log`、`/tmp/lt-budget-r6-mutation-owner.log`。
初次 3 FAIL / 1 PASS 含测试 timer 清理问题，不能全部视为纯业务复现。

独立审查：`character-generation-budget-r6-diagnostics-independent-review.md`，
R6 有限范围 PASSED，未解决 BLOCKER/MAJOR/MINOR=0；独立四组 58 PASS、共享 LLM
47 PASS、analyze/format/diff-check PASS。修复同组件残留的无证据 CPU 阻塞注释。
这些结果不替代 Phase 6 跨模块集成门禁、全量回归或真实设备现场证据。

## R1：预算可行性与未来容量预留（Phase 3 预算核心）

Status: PASSED（仅限 R1 有限范围）
Acceptance Mode: Independent Review（另一个 Agent 只读审查）
Commit: `295c7e60d9e2cdf720ff5694e7562d827215bc3d`
`fix(resources): complete R1 budget reservation`（2026-10-13）
基线：`31fad52`；工作区在实现方改动下未提交，独立审查只读执行。

- 新增 `lib/domain/resources/generation_budget_allocation.dart`，把冻结 E/C、本段旧正文、
  其他已保存正文、未完成必填集合、reserve、minimum、recommendedTarget、
  acceptedMaximum 与 constraint fingerprint 收敛为单一 `PartGenerationBudgetAllocation`。
- `_budgetAllocationInTransaction` 在同一 SQLite 事务内读取确认蓝图、冻结
  `elastic_percent`、其他 Part 实际正文与任务完成集合，调度闸门、LLM 请求和事务提交
  消费同一快照；`commitPartContent` 的 ceiling + reserve 复核在任何写入之前。
- 不可行路径（planOutOfBounds / ceilingExhausted / minimumTotalExceedsCeiling /
  belowMinimum）在四个闸门（调度派发、failed 重排、retrySinglePart、
  _generateSinglePart 预派发及派发后复读）于 `startAttempt` / LLM 调用之前终止，
  0 模型请求；`resumeGeneration` 经 `startGeneration → generateAllParts` 汇入同一闸门。
- 未新增 schema / migration，未改动 A/K/E、未截断或重写已保存正文、未删除
  attempt / revision；历史 NULL E 解析为 20%，无契约 legacy Part 保持 floor 10。

真实验证（独立审查真实执行）：定向 10 文件 **110 PASS**，退出码 0；
`flutter analyze --no-pub` 零问题；11 个变更 Dart 文件 format 0 changed；
`git diff --check` PASS。日志 `/tmp/lt_r1_review_tests.log`、`/tmp/lt_r1_review_analyze.log`。

独立审查报告：`character-generation-budget-r1-reservation-independent-review.md`，
裁决 PASSED，未解决发现 **BLOCKER=0、MAJOR=0、MINOR=4**。

保留在后续风险清单的四项 MINOR（不阻断 R1，不得重复修改已通过的 R1 主体）：

1. MINOR-1：`commitPartContent` 事务内未复核单段 `len(b_i) <= K`；LLM 路径因
   `D_i = min(K, …)` 不可达，唯一可达为测试 / 内部直写。建议随 R2/Phase 4 契约校验
   一并补 `len <= ResourceLimits.maxPartCharacters`。
2. MINOR-2：R4 之前确认、单段 `estimatedLength > 3000` 的旧蓝图会在派发前被判
   `planOutOfBounds` → 0 请求、任务 failed（旧行为是“以 ≤3000 生成”），属遗留任务
   可观察行为变化；需确认是否符合产品预期。
3. MINOR-3：`unfinished` 仅排除 `completed`，`cancelled` 等非 completed 任务仍被计入
   future reserve `F_i`；混合场景罕见，需按规格语义明确或记录边界。
4. MINOR-4：ceiling 的 `targetCapacity` 改读 `blueprint_json` 而非 `target_capacity`
   列；正常数据列与 JSON 一致，畸形 / 极旧行可能改变 C。

尚未完成的 Phase 门禁：R1 只交付预算可行性与容量预留，不代表完整 Phase 3。Phase 3
仍缺一致预算快照的 UI 展示闭环；R2 正文完成契约（本记录下一工作单元）是 Phase 4
前提，随 R2 一并补齐 MINOR-1 的提交层 K 守卫。整体 Phase 1–6 与任务整体仍未
ACCEPTED。

下一工作单元 R2 的依赖：Phase 1 内容契约基础设施（`content_requirements.dart`、
`PartGenerationValidator`、`BlueprintPart.contentRequirements`、`commitPartContent`）
已就绪，`PartGenerationRequest` 已携带 `contentRequirements` 与 `acceptedMaximum`，
R2 在其上接入生产闭环；U6 仍未答复，不得擅自引入 narrative 产品默认阈值。

## R2：正文有效性与完成状态（Phase 4 核心）

Status: PASSED（仅限 R2 有限范围）
Acceptance Mode: Independent Review（另一 Agent 独立只读审查；同 Agent 复查报告为 Integrated Review）
起始 HEAD：`58b6e17`（R1 进度文档提交后）；工作区干净。
提交 SHA：`064eb42`（`fix(resources): enforce content contract and K cap at Part completion`）。
审查报告：`character-generation-budget-r2-content-contract-integrated-review.md`（Integrated）、
`character-generation-budget-r2-content-contract-independent-review.md`（Independent）。

实施范围（依据实际调用链）：

- `PartGenerationValidator.validate` 新增第 8b 步：当 `request.contentRequirements`
  非空时调用 `PartContentRequirementsValidator.validate`，narrative / scalar /
  structured 分别按 kind / profile / minimum 校验；失败抛
  `PartGenerationValidationException(field: 'content_requirements')`。`complete_part`
  仅代表协议结束，不再构成正文有效性证明。
- `commitPartContent` 在同一 SQLite 事务内、任何写入之前，新增：
  1. 内容契约复核（`_contentRequirementsInTransaction` 从确认蓝图解析契约，
     null 契约保持 legacy 放行）；
  2. 提交层 K 守卫 `len(b_i) <= ResourceLimits.maxPartCharacters`（R1 MINOR-1）。
  两者先于既有累计 C + future reserve 复核，保持事务原子性与旧正文保护。
- 未改动 UI：Studio 完成标签已由权威 task 状态派生（`resource_studio_outline.dart`
  `_statusLabel`、`resource_studio_controller.dart` 的 `PartCompleted`），提交是唯一
  completed 权威，故无效正文不会显示“已生成”。legacy `needsContentReview` 审阅信号与
  “旧正文已保存 / 本次重生成失败”的区分属 R5 / Phase 5 与 U6。

真实验证：

- R2 定向三文件 **60 PASS**，退出码 0；`/tmp/lt-r2-final-check.log`。
- 预算/契约/CAS/协调器组合 16 文件 **177 PASS**，退出码 0；`/tmp/lt-budget-r2-tests2.log`。
- 资源子系统扩大回归 **844 PASS**，退出码 0（断点基线 823，增量来自新增用例）；
  `/tmp/lt-budget-r2-resources-regression.log`。
- 流式 / 生命周期 / 集成（含 soak）**72 PASS**，退出码 0；`/tmp/lt-r2-extra.log`。
- 负向证明：临时还原两个 `lib/` 文件为 R2 前内容，R2 定向用例 **+5 -7**（7 个“拒绝”
  用例 FAIL、5 个“接受 / legacy”用例 PASS），随后 byte-for-byte 还原并 `sha256sum -c`
  校验通过，复跑全 PASS。
- `flutter analyze --no-pub` 零问题；5 个变更 Dart 文件 format 0 changed；
  `git diff --check` PASS。

测试夹具适配（非放宽断言）：`generation_aggregate_budget_sqlite_test.dart` 原先直接经
`commitPartContent` 提交 >3000 的正文（R1 MINOR-1 已认定真实生成路径不可达、仅测试直写
可达）。补齐 K 守卫后改为合法候选 `min(total, K)` + 兄弟 Part 承载 remainder，仍精确落在
C / C+1 边界并新增矩阵边界断言；target-boundary 用例改为 8×3000。断言未放宽、无 skip、
无 mock 真实持久化。与 R4 聚合夹具适配先例一致。

未解决问题：

- R2-MINOR-1：commit 现重复解析蓝图（契约与 allocation 各一次），可后续合并；不影响正确性。
- R2-MINOR-2：Planner 当前不产出 `contentRequirements`，新任务默认 legacy，1–2 字 narrative
  在生产中仍可能 completed —— 这是 **U6 未决**的直接后果，非 R2 缺陷；待 U6 批准后由
  Planner / 客户端 profile 产出契约，R2 确定性校验即自动生效。
- `content_requirements` 失败暂映射既有 `resourceContentInvalid`，未新增 `contentIncomplete`
  / `retryDisposition`（R5 范围）。
- R1 MINOR-2 / 3 / 4 本次未处理。

U6 待决子项（暂停，不猜测）：Planner narrative/scalar/structured profile 与最低阈值、
requiredFields / requiredHeadings 覆盖、legacy `needsContentReview` UI 审阅策略。

下一工作单元：R5 错误分类、安全数值与受保护恢复；随后独立弹性 E50 的真实 UI→SQLite
验证、人工认可与历史修订保护、世界观 / 角色 / NPC 集成回归、全仓回归与最终独立审查。

独立审查（另一 Agent，只读）：
`character-generation-budget-r2-content-contract-independent-review.md`，
裁决 **PASSED WITH FINDINGS**，未解决发现 **BLOCKER=0、MAJOR=0、MINOR=2、INFO=3**。
六项 R2 声明（契约贯穿 Validator/Commit、K 守卫、无效不 completed、不覆盖旧正文、legacy
放行、错误映射、R1 不绕过）逐项成立；夹具适配未被削弱。无阻断问题需修复。两项 MINOR 为
性能（重复解析蓝图）与 U6 边界；三项 INFO 为外观 / 不可达边界。独立审查另跑 60 + 35 + 39
用例 PASS、analyze 零问题，结束时工作区为空。

## R5：错误分类、安全预算诊断、有限重试与恢复保护（Phase 5 核心）

Status: PASSED（仅限 R5 有限范围）
Acceptance Mode: 独立审查见下方独立审查行；同 Agent 复查为 Integrated Review
起始 HEAD：`b79b0ac`（R2 独立审查记录提交后）；工作区干净。
提交 SHA：`fb4ba8f`（`feat(resources): classify generation failures and carry safe budget diagnostics`）。
审查报告：`character-generation-budget-r5-classification-integrated-review.md`（Integrated）。

实施范围（依据规格 §6.4 / §9）：

- 错误分类拆分：新增 `AppErrorCode.resourceGenerationBudgetInfeasible`（冻结预算无法满足
  本段，约束不变前不得请求）与 `resourceContentIncomplete`（正文未过已确认内容契约）；
  `resourceGenerationBudgetExceeded` 保留给“本次输出超授权量”的有限纠正。
  `resource_generation_error.dart` 按领域类型 / 字段映射，不再把不可行与超量混为同一码。
- 安全预算诊断：`PartGenerationValidationException` 增加可选 `parameters`（仅安全数字）；
  `resourceGenerationError` 为不可行附带 `ceiling/saved/remaining/reserve/minimum/allowed/
  unfinished`，为内容不足附带 `minimum/actual`，为超量附带 `allowed/actual`。不含 prompt、
  正文、Authorization、密钥或模型响应。
- 持久化与恢复：新增 `encodeGenerationDiagnostic` —— 无安全参数时写纯稳定码名，有参数时
  写既有安全 `DiagnosticEnvelope`；`resourceGenerationErrorFromCode` 同时解码二者并对
  历史纯码 / 任意旧文本安全降级为 unknown。coordinator 的 `_failureCode`、三处失败回调
  errorMessage、`exhaustBudget`、流式服务的 session 失败码统一使用同一编码，故安全数字
  可跨“重启”（新实例重建）还原；未知旧码仍安全降级。
- 有限重试与恢复保护：不可行任务在自动（`generateAllParts` 派发闸门）、手动
  （`retrySinglePart` 预检）、恢复（`resumeGeneration → generateAllParts` 同一闸门）三条
  路径均 0 次模型请求；偶发超量按每 pass `1+maxRetriesPerPart` 有限纠正。未新增持久化
  status 字符串、未新增 schema / migration。
- 本地化：6 个 locale 新增 `resourceErrorContentIncomplete` /
  `resourceErrorGenerationBudgetInfeasible`（参数化安全数字）与 `@` 元数据，经
  `flutter gen-l10n` 重新生成；`app_error_localizer` 渲染安全数字。

真实验证：

- R5 定向（`character_generation_retry_recovery_sqlite_test` + `resource_generation_error_test`）
  **12 PASS**，退出码 0；`/tmp/lt-r5-new2.log`。
- 错误分类 / 关联（localizer + 预算预留 + 内容契约 + 冲突 + 畸形流）+ **55 PASS**；
  `/tmp/lt-r5-tests1.log`。
- 流式 / 生命周期 / 段一致性 **48 PASS**，退出码 0；`/tmp/lt-r5-streaming.log`。
- 资源子系统 + unit 扩大回归 **2012 PASS / 1 skipped（既有跳过，非本次）**，退出码 0；
  `/tmp/lt-r5-regression.log`。
- Studio widget **71 PASS**，退出码 0；`/tmp/lt-r5-widget.log`。
- `flutter analyze --no-pub` 零问题；变更 Dart 文件 format 0 changed；`git diff --check` PASS。

U6 合规：**未**引入 narrative/scalar/structured 最低阈值，未实现人工认可，未改变旧任务
冻结预算或版本；`resourceContentIncomplete` 仅在蓝图存在已确认契约时触发。

未解决问题：

- R5 未持久化“实际正文长度”等仅在请求期可知的数字到独立列；安全数字经
  `DiagnosticEnvelope` 存入既有 `error_message` 文本列往返（已测），未新增 schema。
- 失败分类的 `retryDisposition` 仍由既有 allocation / sourceConflict 闸门实现，未新增
  冗余枚举字段（避免过度抽象）。
- R1 MINOR-2 / 3 / 4、R2-MINOR-1（重复解析蓝图）仍未处理。

下一工作单元：独立弹性 E50 的真实 UI→SQLite 验证；随后人工认可与历史修订保护
（依赖 U6、需 minimal nullable provenance 迁移）、世界观 / 角色 / NPC 集成回归、全仓回归
与最终独立审查。

## 2026-10-13 干净断点与恢复入口

Checkpoint Branch: `fix/character-generation-budget-checkpoint-20261013`
Checkpoint Status: PAUSED / NOT ACCEPTED（保存已完成局部修复，不是完整 Phase 验收）

### 本断点收尾验证

- 资源子系统首轮扩大回归：820 PASS / 3 FAIL，退出码 1。三项失败来自旧 fixture
  将 5000–50000 字单段当作合法计划，不是通过删除或 skip 消除失败。
- 两处 fixture 保留聚合容量、模型不能提高目标、编排身份与幂等断言；改用合法分段，
  并增加原 50000 字单段拒绝且未保存、每段上界等断言。
- 独立复审 `character-generation-budget-r4-regression-independent-review.md`：PASSED，
  18 PASS、analyze 零问题、format/diff-check PASS，未解决 BLOCKER/MAJOR/MINOR=0
  （仅该两处 fixture 范围）。
- 收尾扩大回归 `flutter test --no-pub --reporter expanded test/application/resources`：
  **823 PASS，退出码 0**，用时 1:37；日志
  `/tmp/lt-budget-resources-final-interim-regression.log`。
- 收尾 `flutter analyze --no-pub`：零问题，退出码 0，2.4s；日志
  `/tmp/lt-budget-interim-analyze.log`。两个暂停前后台进程均已确认结束。
- 以上不是全仓测试或最终跨阶段验收。临时日志不保证跨机器保留；正式证据摘要及
  独立审查报告已入库，测试本身可从本分支重跑。

### 已完成提交边界

| Commit | 已通过的局部范围 | 尚未代表完成的范围 |
| --- | --- | --- |
| `ea5de88` | Phase 1 内容契约格式、纯验证规则、legacy / SQLite 保护基础 | 产品默认值、Planner / request / commit / UI 全链接入 |
| `2144a40` | R3 冲突 seq 拒绝、相同重放幂等、两路传输及 SQLite 保护 | Phase 2 配置文案与真实 UI→SQLite E50 门禁 |
| `09a49ea` | R4 所有规划分支单段上界与显式 minimum、plan/replan/confirm 保护 | Phase 3 一致预算快照、future reserve、派发及事务内重检 |
| `0932c6d` | R6 heartbeat owner 生命周期、观测语义及负向 / mutation 回归 | Phase 6 跨模块集成、全仓回归与最终独立验收 |
| `295c7e6` | R1 预算可行性与未来必填容量预留、四闸门 0 请求预检、事务内 commit 复核 | Phase 3 UI 快照闭环、R2 正文完成契约、4 项 MINOR 与整体验收 |
| `58b6e17` | R1 进度文档补齐（提交状态、110 PASS、4 MINOR、后续依赖） | 不改变整体状态，仍 NOT ACCEPTED |
| R2 commit | 内容契约贯穿 Validator 与 SQLite Commit、complete_part 不越权、提交层 K 守卫 | Planner 产出契约（依赖 U6）、R5 分类与 UI 审阅信号 |

收尾 commit 另保存两处 fixture 适配、独立报告及本断点记录；其哈希通过分支 HEAD
获得，避免在 commit 内自引用尚未生成的哈希。不改数据库版本、依赖或用户数据。

### 恢复所需决定与未完成工作

1. 先读取原规格第 6、7、10、13、14.2 节及本记录，不重复全仓根因扫描。
2. U6 尚未批准：narrative 最低比例 / 必需小节、scalar 人工确认、structured 必填键、
   legacy 审阅策略，以及 Phase 5 是否仅接受人工认可后的编辑候选。40% 是待决提案，
   不是已批准产品默认值；旧任务预算执行版本功能也未批准。
3. R1 / R2 的生产根因仍是未解决 MAJOR：实现一致预算快照、后续必填预留、派发
   maximum / minimum、自动/manual/resume 预检、事务复核，以及正文完成契约。
4. 再完成失败分类与持久化 retryDisposition、安全数字错误上下文（R5）、有限重试、
   显式人工接受与 provenance / 修订历史保护；具体迁移按正式规格验收。
5. 完成当前冻结预算与后续设置的 UI 区分、真实直接/审阅入口 E50 接线及移动端验证。
6. 最后执行角色/世界观/NPC、关联、装配、压缩显式采纳和冒险启动集成、全仓测试、
   静态分析、格式 / diff 检查和独立最终审查；对照 T01–T31 及第 13 节逐项验收。
   真实模型与设备证据单列，不能把 fixture 验证当现场证明。

恢复先运行 `git status --short`、`git diff`、`git diff --cached`、
`git log --oneline -10`，核对本分支提交与正式报告，从已通过的局部门禁继续。
禁止 reset/clean/stash；不得追溯修改旧 E、裁剪已保存正文或清空数据库。
本断点不标 ACCEPTED，不授权后续自动 push / merge / 发布。
