---
name: code-audit
description: 对代码仓库、commit 或 diff 进行独立只读的深度漏洞审计，寻找逻辑/架构/数据一致性/状态机/并发/事务/安全/性能/测试覆盖/文档一致性缺陷，并输出结构化 Audit Result 报告（BLOCKER/MAJOR/MINOR/INFO）
allowed-tools: Read, Grep, Glob, Bash(git:*), Bash(flutter:*), Bash(dart:*), Write(docs/**)
---

# code-audit（包装入口）

完整审计规范在仓库的跨 Agent 目录，**唯一事实来源**，请先完整读取：

@${CODEBUDDY_SKILL_DIR}/../../../.agents/skills/code-audit/SKILL.md

参考文件（按需读取，路径同上目录下的 `references/`）：

- `${CODEBUDDY_SKILL_DIR}/../../../.agents/skills/code-audit/references/checklists.md` — 第二阶段逐项扫描清单
- `${CODEBUDDY_SKILL_DIR}/../../../.agents/skills/code-audit/references/report-template.md` — 报告模板

## 审计范围

$ARGUMENTS

若上面范围为空，则默认审计当前分支相对 `origin/main` 的未合并改动（`git log --oneline origin/main..HEAD` 与 `git diff origin/main...HEAD`）；若也为空，审计最近一次 commit。

## 硬性约束（与 SKILL.md 一致，不得放宽）

1. 你是审计 Agent，不是开发 Agent：**禁止修改代码、测试、配置**，禁止 commit / push。
2. 唯一允许的写入是审计报告本身。本 skill 的工具白名单只放开了 `Write(docs/**)`，源码与测试不可写。
3. 所有结论必须可追溯到 `文件:方法:代码路径` + 触发条件 + 实际影响；没有证据的猜测不得作为 finding 输出。
4. 测试通过不等于正确；必须核对测试路径是否等于生产路径。
5. 唯一职责是**找到隐藏错误**，不是证明代码正确。没有发现时简短确认通过即可，不要输出无意义长报告。
