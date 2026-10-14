# U6：动态正文有效性契约（v0.1）

文档状态：**APPROVED（v0.1，2026-10-14）**
适用范围：Resource Studio 的世界观、角色卡、NPC 资源生成。
基线检查点：`e33206f`，分支 `fix/character-generation-budget-checkpoint-20261013`。
设计原则：动态规划、类型明确、最低要求可计算、结构检查可验证、历史数据不破坏。

> 本文件取代此前的 PROPOSED 草案。参数已获产品批准（见「已批准产品决策」）。本轮仅执行
> **U6-A**（纯函数 + 单元测试 + 本记录）；是否存在对应实现，以「实施状态」表为准，
> 不得因本文件存在而假定后续阶段已实施或已获授权。

---

## 已批准产品决策（U6 v0.1）

1. Narrative 采用 **50% / 40% / 30%** 分段累积算法，分界点 **200 / 800** UTF-16 单位；
   最低规划长度 **80**，**不另设绝对字数下限**。
2. Narrative 默认**自由叙述**；仅当明确确认分节结构时才要求 Markdown 标题。
3. 新任务类型无法确定时，**确认前要求用户选择或调整规划**，不允许静默生成无契约 Part。
4. Scalar 最低长度为 **1**；Structured 继续使用 **V1 顶层必填字段**校验。
5. Legacy 保留原文、状态及历史记录；**仅允许非破坏性审阅提示**。
6. **不批准**：旧任务预算追溯修改、自动压缩、人工认可迁移。

## 实施状态（APPROVED vs 尚未实施）

| 范围 | 决策状态 | 实现状态 |
| --- | --- | --- |
| §2.1 Narrative 动态最低量**纯函数** | APPROVED | **IMPLEMENTED（U6-A）**：`lib/domain/resources/narrative_minimum_policy.dart` + `test/domain/resources/narrative_minimum_policy_test.dart` |
| §2.2 `p < 80` 需重规划 / 合并 / 重分类 | APPROVED | **IMPLEMENTED（U6-B）**：契约规划器产出 gap，确认门禁拒绝；直接路径安全停止 |
| §2.3 Narrative 结构检查（ATX 标题、排除代码块） | APPROVED | IMPLEMENTED（Phase 1：`content_requirements.dart`） |
| §2.4 完成条件（协议 / minimum / 标题 / K / maximum / reserve / 事务） | APPROVED | IMPLEMENTED（R2 + R1 + R4） |
| §3 Scalar 规则；规划默认 ≤96 | APPROVED | 校验 IMPLEMENTED；**契约由客户端 `PartContentSpec` 生成（U6-B）**；规划默认 ≤96 **NOT IMPLEMENTED** |
| §4 Structured V1 顶层必填字段 | APPROVED | IMPLEMENTED（Phase 1）；**必填字段仅来自客户端 spec（U6-B）**；嵌套字段/值类型**不在 V1** |
| §5 契约单源、`1≤m≤p≤3000`、UTF-16 计量 | APPROVED | **IMPLEMENTED（U6-B）**：唯一公式 `NarrativeMinimumPolicy`；`BlueprintValidator.validateContentContracts` |
| §5 契约在归一化后生成、冻结 | APPROVED | **IMPLEMENTED（U6-B）**：`BlueprintPlanner` 在 `normalize` 后生成并冻结 |
| §6 Legacy 兼容（不补造 / 不改写 / `needsContentReview`） | APPROVED | 领域侧 IMPLEMENTED；无版本标记的蓝图保持 legacy 放行；**只读契约投影 + 低干扰审阅提示 IMPLEMENTED（U6-D）**（`part_contract_status.dart`、`ResourceStudioRuntime.blueprintPartContracts`、outline 提示） |
| §7 失败分类与体验 | APPROVED | 分类 IMPLEMENTED（R5）；审阅页契约展示 IMPLEMENTED（U6-B 最小）；**失败/旧正文区分与 U6-D 提示 IMPLEMENTED** |
| §8 验收标准 A–E | APPROVED | A/B/C 多数 IMPLEMENTED（U6-A/B/C）；**D 真实设备/E 全仓仍 NOT IMPLEMENTED** |
| §9 明确不在本次范围 | 生效 | — |
| 决策 6（追溯预算 / 自动压缩 / 人工认可迁移） | 不批准 | **NOT AUTHORIZED** |

**U6-C / U6-D / U6-E 未授权实施。** U6-B 只接线 Planner / Normalizer / Review / Confirm 与必要测试，
不修改 R1–R6 已通过的核心行为。客户端类型来源（U6-B 决策）：**未指定类型的 Part 默认自由叙述
（最严格方向）**；Scalar / Structured 仅由客户端 `PartContentSpec`（模板或用户确认）指定，模型
自报的类型 / minimum / 字段一律被覆盖。

---

## 1. 契约权威与生成时机

每个新 Part 应具有明确的正文类型：

- `narrative`：人物经历、性格描述、世界观历史、事件叙述等连续文本。
- `scalar`：名称、称号、关系标签、职业等独立短字段。
- `structured`：要求满足指定字段结构的 JSON 对象。

类型不得仅凭标题关键词推断。

流程：模型生成蓝图 → 客户端校验规划 → 归一化最终 Part 字数 → 客户端生成内容契约 →
用户审阅确认 → 冻结契约与预算 → 正文生成。

模型可以提出内容组织建议，但不得自行决定更低的 minimum 或修改客户端校验规则。
类型不明确时，必须在确认前要求用户选择或通过已授权的资源模板确定，不能静默退回无契约模式。

## 2. Narrative：动态最低正文要求

### 2.1 最低字数计算

- `p`：最终确认的 Part 预计长度；`m`：最低有效正文长度；`K = 3000`。

`m = ceil(0.50 × min(p,200) + 0.40 × min(max(p−200,0),600) + 0.30 × max(p−800,0))`

适用条件：`80 ≤ p ≤ 3000`。前 200 字按 50% 建立下限；201–800 字增量按 40%；超过 800 的
增量按 30%。

| Part 计划长度 p | 最低正文 m |
|---:|---:|
| 100 | 50 |
| 200 | 100 |
| 450 | 200 |
| 800 | 340 |
| 1,000 | 400 |
| 1,500 | 550 |
| 3,000 | 1,000 |

（数值已获批准；整数实现见 U6-A 纯函数，`ceil` 用 `(加权和 + 99) ~/ 100`。）

### 2.2 极短 Narrative 规划

当 `p < 80` 时，不允许自动创建严格 Narrative 契约。应在蓝图确认前选择：增加该 Part 的规划
容量；与其他 Narrative Part 合并；经用户确认改为 Scalar 或 Structured。若目标总预算无法容纳
调整后的规划，应明确提示重新规划，不得偷偷扩大 T、C 或资源硬上限。

### 2.3 Narrative 结构检查

沿用 `narrativeSectionsV1`，支持：**自由叙述**（`requiredHeadings = []`，要求达到动态 minimum，
不强制 Markdown 小标题）与**分节叙述**（对已明确要求多个组成部分的 Part，在确认蓝图时冻结
`requiredHeadings`）。校验必须发现真实存在且包含内容的小节，不能只相信模型在总结中声明
“已覆盖”。本期沿用现有 ATX Markdown 标题识别，标题文字必须与已确认要求匹配。不适合拆成
小标题的内容不应强制分节。

### 2.4 Narrative 完成条件

必须同时满足：完整响应协议与身份校验；`trim()` 后正文达到 minimum；已确认必填标题确实存在
且有正文；单 Part 不超过 K；不超过当前授权 maximum；累计容量与 future reserve 校验通过；
SQLite 事务提交成功。`complete_part` 只表示传输结束，不代表正文合格。

## 3. Scalar：合法短字段保护

适用：角色名称、称号、职业、关系标签、阵营标签。

| 属性 | 值 |
|---|---|
| kind | scalar |
| validationProfile | scalarTextV1 |
| minimumCharacters | 1 |
| requiredFields | 空 |
| requiredHeadings | 空 |

Scalar 允许合法的一两个字内容（如“导师”）。必须满足：`trim()` 后非空；不包含换行；满足已确认
的单字段用途；继续受资源容量与单 Part 硬上限保护。建议新 Scalar Part 规划长度默认不超过 96
个 UTF-16 单位；如确需较长解释应考虑 Narrative。该 96 是规划建议，不是正文硬拒绝上限；
若将来要限制 Scalar 实际最大长度，须另行扩展契约，不能把软目标暗中改为硬限制。不能因为标题
叫“人物关系”就自动当作 Scalar；若要求详细描写关系发展，仍应是 Narrative。

## 4. Structured：结构与字段优先

适用：明确采用 JSON 的人物属性、角色关系对象、可机器读取的设定字段。

| 属性 | 规则 |
|---|---|
| kind | structured |
| validationProfile | structuredObjectV1 |
| minimumCharacters | 1 |
| requiredFields | 来源于客户端确认的字段集合 |
| requiredHeadings | 空 |

重点不在字数比例，而在实际 JSON 结构。必须满足：正文可解析为 JSON 对象；已确认必填字段全部
存在；字符串必填值不能仅为空白；必填 List / Map 不能为空；合法的 `false` 和 `0` 不得被当作空值
拒绝；继续满足 K、C 与 future reserve。

`minimumCharacters = 1` 是基础下限，不代表一字符 JSON 就能通过。本期继续使用已有的顶层
`requiredFields` 校验；嵌套字段路径与更复杂的值类型校验应另行设计版本化契约，不能假装 V1
已具备这些能力。若不存在可信的客户端字段规格，则该 Structured Part 不允许凭模型自报的必填
字段直接确认。

## 5. 必填属性与预算保护

新任务默认 `required = true`；只有用户在蓝图审阅时明确批准为可选内容，才允许 `false`。确认前
必须满足 `1 ≤ m_i ≤ p_i ≤ 3000`，并校验：总规划不超过用户目标 T；所有必填 Part 的最低需求可行；
当前冻结预算 C 能容纳必要内容；预留遵守 R1 的 future reserve 机制。

契约必须在最终 Part 字数归一化完成后计算，避免使用模型提出但随后被调整的原始长度。同一份已
确认契约应被 Planner / Blueprint Validator、Part 请求构造、`PartGenerationValidator`、SQLite
`commitPartContent`、自动 / 手动 / Resume、Resource Studio 完成状态共同使用。**禁止 Planner、
Validator 和 Repository 分别使用不同的最低量公式。**

预算计量继续使用 Dart UTF-16 `String.length`；有效正文下限使用现有 `trim().length` 语义，不改变
已有资源容量公式。

## 6. Legacy 历史兼容策略

### 6.1 历史无契约资源
`contentRequirements == null` 保持 Legacy 未知契约：不自动补造类型、不批量重算最低字数、不修改
正文、不修改完成状态、不删除 Attempt / Revision、不自动重新生成。已有极短正文可标记
`needsContentReview`——审阅提示，不是自动失败状态。

### 6.2 已确认的旧蓝图
保留原始契约与预算快照；新 U6 规则不追溯修改旧任务。恢复、失败重试和重新打开资源时继续遵守
其原始冻结状态。

### 6.3 历史人工编辑
用户手动编辑旧正文时，不得仅因内容短而删除或覆盖。若要认可为满足新契约的正式内容，应使用
独立的人工认可流程，保留原正文、Revision、CAS 版本、完成来源、内容 Hash、契约版本。
人工认可的 `completion_provenance` 与数据库迁移属于后续受控实施阶段，本规格**不授权迁移**。

### 6.4 导入资源
手工导入资源不应被错误当作新的 AI 严格生成任务；导入与新 AI 生成的契约适用范围必须显式区分。
不得因为导入字段只有两字就自动认定其损坏。

## 7. 失败分类与用户体验

沿用 R5 分类：`resourceContentIncomplete`（已确认契约不满足）、
`resourceGenerationBudgetInfeasible`（预算无法满足最低需求）、
`resourceGenerationBudgetExceeded`（正文超过当前授权上限）。

**正文内容不足**：不写入 completed；预算可行时允许有限纠正重试；不覆盖已保存有效正文；
UI 提示最低要求与实际长度。**预算不可行**：不调用 LLM；不进行无意义自动重试；提示冻结预算、
可用容量及不足原因；提供重新规划或受保护的人工恢复方向。**历史未知契约**：保留原状态；可提示
审阅；不自动把旧 completed 改为 failed。UI 必须区分“已保存的旧正文”与“本次重新生成失败”。

## 8. 验收标准

A. **契约生成与规划**：新 Narrative 自动生成动态 minimum；100 / 450 / 1000 / 3000 得到确定性
结果；同一输入得到相同契约；模型伪造过低 minimum 不生效；Narrative 小于 80 正确要求重规划或
重分类；Normalizer 调整长度后重新计算契约；必填最低总量不可满足时拒绝确认。
B. **内容类型**：1–2 字 Narrative 拒绝；达到最低要求的自由叙述通过（不强制 Markdown 标题）；
分节 Narrative 缺已确认小节拒绝；代码块伪标题不能满足必填标题；合法短 Scalar 通过；多行 Scalar
拒绝；Structured 缺字段 / 空字段 / 非法 JSON 拒绝；合法 `false`、`0` 通过。
C. **持久化与数据安全**：无效正文不写入 completed；SQLite 拒绝后旧 body / hash / Revision 不变；
新契约能保存、确认、重启、再次读取；未知版本及非法 profile 显式拒绝，不降级为 Legacy；R1 容量
预留在新 minimum 下仍正确；旧任务、旧数据库和旧完成正文保持不变。
D. **真实生成路径**：覆盖 `Blueprint → Normalize → Confirm → Request → Validator → Commit →
Resume`；至少测试角色卡 10,000 目标、世界观 20,000 目标、NPC 生成、关联角色生成、极短正文失败
后重试、较短但合法正文正常完成、预算不足时零模型调用、完成状态与 Studio 展示一致。
E. **最终质量门禁**：Flutter 定向及全仓测试通过；Analyze 零问题；Format 通过；`git diff --check`
通过；SQLite 真实持久化测试通过；不删除 / Skip / 放宽原有断言；独立 Agent 完成审查；真实模型与
设备验证未执行时标记 NOT VERIFIED。

不得因自动校验通过而宣称人物设定在语义上完全正确；正文契约只提供确定性完整性保护，不能取代
内容质量审阅。

## 9. 明确不在本次范围

不授权：扩大资源绝对容量 A；扩大单 Part 上限 K；改写冻结弹性 E；自动压缩或截断已保存正文；
强制更新旧资源的正文契约；自动认可历史编辑；修改冒险对话 L0–L5；大规模重构 Resource Studio；
自动合并 main 或发布 APK。另按决策 6，不批准旧任务预算追溯修改、自动压缩与人工认可迁移。

## 10. 建议实施顺序

1. **U6-A（本轮，已授权）**：客户端动态契约策略与纯函数单元测试。
2. **U6-B（未授权）**：接入 Blueprint Planner、Normalizer、Review、Confirm，并验证所有生成入口。
3. **U6-C（未授权）**：验证 Validator、R1 Reserve、SQLite Commit 和失败恢复生产闭环。
4. **U6-D（未授权）**：Legacy 审阅提示与必要 UI 测试，但不自动修改旧数据。
5. **U6-E（未授权）**：跨模块回归及独立审查。

每个阶段更新正式进度文档、提交并推送 GitHub 检查点分支。
