# 角色生成预算修复执行记录

任务权威：`../character-generation-budget-root-cause-and-remediation.md`、
`../architecture/configurable-generation-elasticity.md`、`../../AGENTS.md`。

Status: IN PROGRESS（整体未验收）
Acceptance Mode: Independent Review（各阶段由另一 Agent 审查）

## 基线与 Scope

- 2026-10-13 开始执行，main / HEAD `e63d161`；工作区干净。
- `git fetch origin` 成功，`HEAD...origin/main` 为 0/0。
- 审计代码基线 `01f6ed0` 后只有方案文档新增，没有生产代码漂移。
- 应用 `1.2.07+29` / SQLite v49；ADR-0003 确认时冻结 E，历史 NULL=20。
- 本次按六个 Phase 修复统一资源生成链，禁止 push / 发布，保护用户库。
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
全量回归、最终静态分析、mutation 守卫验证、跨模块装配和最终独立审查尚未执行。
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
