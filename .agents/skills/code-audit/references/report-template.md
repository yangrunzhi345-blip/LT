# 审计报告模板

严格对应 SKILL.md 第四阶段的输出规则。报告长度应与**真实发现**成正比——不要输出无意义长报告。

---

## 情况一：发现问题 → Status: FAILED

````markdown
# Audit Result

Status: FAILED

## Summary

发现：X 个问题（BLOCKER: a，MAJOR: b，MINOR: c，INFO: d）

审计基线：`<branch>` @ `<commit>`；工作区 `<clean / 有未提交改动>`。
实际执行：`<命令原文>` → `<真实结果>`。
未覆盖范围：`<未审计部分，避免读者高估完整性>`。

## Findings

### B1

等级：BLOCKER

标题：<一句话点明缺陷>

问题：
<详细描述。只陈述缺陷本身，不夹带建议。>

位置：
- 文件：
- 方法：
- 代码路径：

触发条件：
<什么输入 / 时序 / 状态会触发。要可复现。>

实际影响：
<会导致什么：数据损坏 / 状态不确定 / 恢复错误 / 并发竞争 / 用户数据丢失 / 安全风险。>

根因分析：
<为什么会发生。指向真正的根因，不是表面现象。>

修复方案：
<必须具体：修改哪里、修改什么、如何验证。不在此实施。>

验证方式：
<测试建议。写成可执行的场景，例如 barrier 交错、迁移 fixture、断言语义。>

---

### M1

等级：MAJOR

标题：
问题：
位置：
- 文件：
- 方法：
- 代码路径：
触发条件：
实际影响：
根因分析：
修复方案：
验证方式：

---

### C1

等级：MINOR

（同上字段）

---

### I1

等级：INFO

（同上字段；改进建议，不得伪装成缺陷）
````

**编号规则：** `B` = BLOCKER，`M` = MAJOR，`C` = MINOR，`I` = INFO；同类内从 1 递增。

---

## 情况二：未发现问题 → Status: PASSED

````markdown
# Audit Result

Status: PASSED

Summary: 未发现阻塞问题。

Verification:
- 架构检查通过
- 数据一致性检查通过
- 状态机检查通过
- 测试覆盖检查通过
- 文档一致性检查通过
````

---

## Finding 质量门（写入前自查）

缺少以下任一项，不得写入报告：

- [ ] 精确位置：文件 + 方法 + 代码路径
- [ ] 触发条件（可复现）
- [ ] 实际影响
- [ ] 根因分析
- [ ] 可执行的验证方式

## 常见报告错误

- 把"测试通过"当作 PASS 依据
- 只描述现象，不写根因
- 把改进建议写成缺陷（应标 INFO）
- 同一根因拆成多条凑数量；或不同根因合并导致无法逐条修复
- 用"可能/也许"制造无法证伪的漏洞
- 未声明未覆盖范围，让读者高估审计完整性
- 引用不存在的文件/行号，或复述实现报告而未独立核对
- 伪造命令输出或测试计数
- 用超长报告掩盖"其实没有实质发现"

## 附：与 LT `docs/` 审计文档的对应

LT 既有报告（`docs/**/phase-NN-*-audit-report.md`、`phase-NN-independent-acceptance.md`）在 FAILED 报告中使用
`Overall Result / Architecture Findings / Data Integrity / Concurrency / Test Coverage / Performance / Recommended Next Actions` 等分节。

两者并存时：

- **本 skill 的 `Audit Result` 格式为主**（Phase 4 规定的输出）
- 需要写入 `docs/` 作为长期档案时，可在 `Findings` 之上叠加既有分节结构，但每条 finding 必须保留本模板的 9 个字段
