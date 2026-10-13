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

## 后续阶段

Phase 2–6 仍待实现和各自门禁；R1–R6 不宣称整体解决。
全量回归、最终静态分析、mutation 守卫验证、跨模块装配和最终独立审查尚未执行。
整体不得标记 ACCEPTED；已确认的 MAJOR 根因仍需后续生产接入修复。
