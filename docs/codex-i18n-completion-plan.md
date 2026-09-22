# LT 全仓用户可见文案 i18n 收口执行计划

## 1. 任务目标

完成 LT 生产代码中的用户可见文案国际化迁移，使以下五种语言均由现有
`AppLocalizations` / Flutter gen_l10n / ARB 体系提供：

- English
- 简体中文
- 繁體中文
- 日本語
- 한국어

本计划只处理用户可见文案，不改变业务协议、数据模型、持久化语义或运行时
生成管线。A 类（应当本地化但遗漏）的硬编码文案必须清零后，才能宣布本轮完成。

## 2. Git 基线与执行纪律

执行开始必须重新确认远端事实，不依据本文件中的旧 SHA 覆盖当前代码：

```bash
git fetch origin
git status --short
git branch --show-current
git rev-parse HEAD
git rev-parse origin/main
git rev-list --left-right --count HEAD...origin/main
git log --oneline -10
```

本计划编写时确认的本地基线是 `9154bee`（`feat(i18n): localize preset scene details`），
但执行 Agent 必须以执行时的 `origin/main` 为唯一基准。已有修改属于用户或其他
工作流，禁止 `reset --hard`、`checkout --`、`restore`、`clean` 或覆盖无关变更。

每个逻辑区域单独提交，建议使用：

```text
feat(i18n): localize <area>
```

最终完成后可再创建一个收口提交：

```text
feat(i18n): complete user-facing localization coverage
```

除非用户明确要求，不要自动创建 Release 或修改版本号；推送远端也必须得到
用户明确授权。

## 3. 已完成范围

当前历史中已经迁移并提交的区域包括：

- Chat 对话、朗读和聊天错误状态
- Data Management、Voice/TTS 设置
- Appearance、Model Reasoning 设置
- Resource Library 筛选、回收站、详情操作、修订历史
- Resource Studio 的部分反馈文案
- Adventure readiness 对话框
- Chat transfer 页面
- Preset scene 详情

现有 `AppLocale`、`AppLocaleController`、首次启动语言选择、语言设置页、
TTS/UI Locale 隔离、ARB 和生成文件均视为既有 Authority。除发现明确 Bug，
不得重构这些基础设施。

## 4. 剩余工作审计

先对整个 `lib/` 做一次新的静态审计，不能直接沿用旧的候选数量。重点目录：

- `lib/features/**`
- `lib/screens/**`
- `lib/widgets/**`
- `lib/core/**`
- 仍参与生产 UI 的其他 Dart 文件

重点检查 `Text`、`RichText`/`TextSpan`、AppBar、Button、Menu、Tab、Navigation、
Tooltip、SnackBar、Dialog、TextField label/hint/helper/error、空/加载/失败状态、
表单校验、用户可见异常，以及 Resource、Assembly、Adventure、Session、Chat、
Settings、Onboarding、TTS 页面。

每条命中必须分类：

- **A：必须本地化但遗漏**。本轮必须处理。
- **B：内部协议/技术字符串**，如数据库 key、JSON key、enum、API 参数、日志。
- **C：用户输入、用户内容或模型生成内容**，不得翻译。
- **D：Service/Domain 错误字符串等高风险技术债务**，当前不能安全迁移时记录原因，
  但不得伪造为已完成。

建议使用 `rg` 定位后逐文件阅读调用链，不能仅凭字符串形式机械替换。审计结果应
记录到执行分支的工作笔记或本计划的更新中，至少包含文件、行号、类别、处理结果。

## 5. 实施顺序

按以下顺序推进，每个区域完成后立即格式化、分析并运行定向测试：

1. 公共组件、导航、通用状态视图。
2. Settings、Onboarding、Language/TTS 页面。
3. Resource Library、Import、Creation、Resource Studio。
4. Assembly 相关页面和对话框。
5. Adventure、Session、Chat 的剩余页面。
6. 跨层错误、校验、运行状态和用户可见异常。

新增 ARB key 时必须同步写入全部六个 ARB 文件（包括项目现有的 locale 文件），
并重新生成 `lib/l10n/generated/`。英文是 template/fallback Authority，但不能
删除或以英文覆盖已有中文、日文、韩文翻译。

动态文案必须使用 placeholder；数量和语法存在差异时使用 ICU plural/select。
禁止通过字符串拼接模拟翻译，也不要在 Domain/Service 注入 `BuildContext`。
跨层错误优先改为稳定 error code/typed error，在 Presentation 层映射为本地化文本；
若改造风险过大，归入 D 类并记录后续债务。

## 6. 禁止范围

本任务不得顺便修改：

- 数据库 schema、migration、Repository persistence semantics
- Resource Creation Authority
- Adventure 状态更新协议和 Turn Settlement
- Generation Pipeline、cursor contract、流式生命周期
- TTS backend/engine 行为
- API、JSON、数据库或内部协议字段
- 与 i18n 无关的架构重构、依赖升级或 UI 设计改版

如发现上述区域存在相关问题，只记录证据并停止扩大范围。

## 7. UI 与响应式要求

英文、日文、韩文通常比中文更长。每次修改动态文案附近的布局时，检查 Flexible、
Expanded、Wrap、可换行文本、Dropdown、AppBar、Card、Row 和固定宽度。不得通过
统一缩小字体、ClipRect、OverflowBox、横向滚动或固定高度掩盖溢出。

至少验证以下 viewport：`320×568`、`360×640`、`390×844`、`412×915`、`768×1024`
和一个桌面尺寸。涉及输入框、Dialog、BottomSheet 或键盘时，同时检查 SafeArea、
viewInsets、按钮可点击和内容可滚动。

## 8. 测试与质量门槛

必须保留并扩展现有本地化测试，至少覆盖：

- 五种 Locale 可加载
- ARB key 集合完整一致
- unsupported locale 回退 English
- Locale 热切换和重启持久化
- 首次启动语言选择
- TTS Locale 不被普通 UI Locale 覆盖
- placeholder/plural 参数和渲染结果
- 核心页面 smoke/widget 测试
- 320 px 窄屏无 RenderFlex/layout exception
- 动态长文案、按钮、AppBar、Dropdown 不出屏

每个已修复的 Overflow 应增加回归测试。建议按变更风险执行：

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test test/unit/localization_test.dart
flutter test <相关定向测试>
flutter test
git diff --check
git status --short
```

如果全量测试失败，必须保存失败输出，并明确区分 `TASK_REGRESSION`、
`ENVIRONMENT` 与 `BASELINE`；不得删除、跳过测试或修改预期值掩盖失败。

## 9. 最终审计与验收

完成迁移后重新扫描整个 `lib/`，输出硬编码清单及 A/B/C/D 分类。验收必须同时满足：

1. A 类为零；所有剩余条目都有可复核的 B/C/D 理由。
2. 新增或修改的 key 在全部目标语言 ARB 中存在，生成文件已更新。
3. 定向测试、`flutter analyze`、`git diff --check` 通过。
4. 全量测试结果已报告，失败项已分类且无新增回归。
5. 320 px、常见手机、平板和桌面布局无明显溢出。
6. 无数据库、协议、TTS backend 或生成管线行为变化。
7. 工作树干净，提交范围仅限本任务。

最终报告必须包含：起始/最终 HEAD、提交 SHA 和 message、修改文件、ARB key 数、
各模块迁移情况、剩余硬编码分类、五语言覆盖状态、测试命令及结果、回归/技术债务、
`git diff --check` 和工作树状态。

