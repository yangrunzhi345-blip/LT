# CODEBUDDY.md

本文件是 LT 项目中 CodeBuddy CLI 的专属规则与上下文文件，仅存放 CodeBuddy 专属工作流、工具约束与上下文说明。跨 Agent 通用规范以根目录 [AGENTS.md](AGENTS.md) 为最高权威；两者冲突时以 `AGENTS.md` 为准。不得在本文件中复制 `AGENTS.md` 的通用规则。

## 开始任务前

- 必须同时阅读 `AGENTS.md` 与本文件。
- 先执行 `git status --short`、`git branch --show-current`、`git log --oneline -10`，确认当前基线。

## Git 与 GitHub 提交硬规则

- 默认禁止向 GitHub 提交：未经用户在本次任务中明确命令，不得执行 `git push`、创建或更新远端分支、发起 PR，也不得以其他等价方式把本地提交推送到远端。
- 本地 commit 允许：完成并通过验证后，在任务范围内创建本地 commit 符合规范，提交边界与 Conventional Commits 要求遵循 `AGENTS.md`。
- 语义区分：“不要 push GitHub”“不要推送”“不要上传”只禁止 push，不禁止本地 commit；只有用户明确说“不要提交”时才不得 commit。
- 确需 push 时，先向用户确认目标仓库、目标分支与范围，获得明确授权后再执行；授权仅对本次指定范围有效。
- 本地工具类改动（如 `.agents/skills/`）默认只做本地 commit，不主动 push。

## 工具与上下文约束

- 涉及 Flutter/Dart 编码或审查时，优先使用项目既有技能（如 `.agents/skills/` 下的 `effective-dart`、`flutter-best-practices`、`flutter-ui-refactoring`、`riverpod`、`testing`、`mocktail` 等），避免重复造轮子。
- 验证命令遵循 `AGENTS.md`；受本机网络限制时，`flutter` 命令按需加 `--no-pub`，并区分原有失败与本机环境失败。
