# AGENTS.md

本文件是 LT 项目的 AI 编程 Agent 工作规范，对整个仓库生效。子目录规则可以补充本文件，但不得降低安全、Git、质量和可追溯性要求。

## 项目事实

- 项目：LT / LT Dialogue
- 仓库：`yangrunzhi345-blip/LT`
- 默认分支：`main`
- 技术栈：Flutter、Dart、Riverpod、SQLite、`sqflite_common_ffi`、`flutter_secure_storage`、HTTP/LLM API、TTS、Material 3
- 目标平台：Linux、Windows、Android、macOS、iOS

代码是当前事实来源。文档与代码冲突时，先检查 Git 历史、实际调用链和当前实现意图，再决定修改方式。

## 默认工作流程

遵循“先理解，再设计，再修改，再验证，最后提交”：检查任务与 Git 状态，阅读相关代码，搜索已有实现，分析调用链和影响范围，确定最小修改，实施后格式化、静态分析、测试、检查 diff 与重复实现，最后提交并汇报。

开始任务前执行 `git status --short`、`git branch --show-current`、`git log --oneline -10`；必要时使用 `git diff`、`git diff --cached`、`git log -- path/to/file` 和 `git blame path/to/file`。

## Git 与用户修改保护

已有未提交修改属于用户或其他工作流。不得默认删除、覆盖或恢复它们；未经明确授权不得执行 `git reset --hard`、`git checkout -- .`、`git restore .`、`git clean -fd` 或 `git clean -fdx`。

若与任务冲突，先识别并尽量兼容，只修改必要部分，最终说明冲突。未经明确要求不得强推、重写共享历史、删除未知分支或标签。一个逻辑任务对应一个清晰提交，优先使用 Conventional Commits（如 `feat:`、`fix:`、`refactor:`、`test:`、`docs:`、`chore:`）。

提交前执行 `git status --short`、`git diff`、`git diff --check`，确认没有意外修改、临时调试代码、敏感信息、无关格式化或误删文件。

## 安全、数据与网络

禁止提交 API Key、Token、Password、Cookie、OAuth 凭证、私有证书、用户凭证、本地数据库用户数据或含真实密钥的配置。日志不得输出 API Key、Authorization Header、完整 Token 或用户敏感数据；临时诊断日志应清理。

涉及 SQLite 必须检查数据库版本、migration、Model、Repository/Service、查询和写入调用，保证旧数据兼容、迁移尽可能幂等，必要时使用 transaction，SQL 优先参数绑定。删除角色卡、世界观、Adventure、消息或覆盖导入数据时必须保护用户数据，不得为了开发方便清空数据库。

LLM 能力应复用统一模型服务和 Client，统一处理 Base URL、Key、Model、Timeout、Streaming、错误映射、Retry、Token usage、Cancellation 和 HTTP 状态。网络请求必须考虑超时、断网、非 2xx、限流、无效 JSON、流中断和用户取消，不得无限等待或无限重试。

## 先复用后新增

新增 Widget、Service、Provider、Repository、Helper、Utility、Model、Dialog、Card、Button、数据访问方法、HTTP Client 或 Prompt Builder 前，必须搜索相同或相似能力。优先级为：现有实现、扩展现有组件、Flutter/Dart 标准能力、已安装依赖、成熟可靠的新依赖、自行实现。

不要针对同一能力建立重复实现。只有在存在多个稳定调用方、确属基础能力且抽象后仍易理解时才提取公共组件，避免过度抽象。修复问题优先处理根因，禁止用空 catch、无限重试、无意义 null fallback、`dynamic`、随意延迟或删除测试掩盖错误。

## Dart、Flutter 与 Riverpod

充分利用 Dart 类型系统，避免无必要的 `dynamic`、大量 `as`、大量 `!`、无意义 nullable 和字符串模拟 enum。命名应表达业务意义，布尔值使用 `isLoading`、`hasMessages`、`canRetry`、`shouldPersist` 等形式。

Widget 应职责明确，避免巨大 `build()` 和重复 UI，优先复用主题与 Design Token，支持明暗主题并考虑桌面与移动端差异。新增 Button、Card、Dialog、Input、Navigation、Loading 或 Error View 前，先检查 `lib/widgets`、`lib/core`、现有 screens 和主题文件。

Riverpod Provider 职责必须清晰；UI 不应重复保存业务层已有状态；异步状态必须处理 loading、error、data；生命周期和监听粒度要明确。先确定 Single Source of Truth，避免 Widget、Provider、Service、SQLite 同时被视为当前真实值。

修改通用代码时必须考虑 Linux、Windows、Android、macOS、iOS，平台专属逻辑应清晰隔离。

## 注释、错误处理与依赖

注释解释“为什么”，不逐行翻译代码。复杂业务规则、非显然算法、平台差异、workaround、安全逻辑和 migration 应说明原因与边界；公共 API 可使用 DartDoc。TODO 必须有上下文，不得用 TODO 逃避本次应完成的工作。禁止空 catch，错误应保留信息、转换为领域错误并提供可理解的提示。

新增依赖前确认没有等价能力，评估维护状态、平台支持、体积、许可证和安全风险；未修改依赖时不要无意义修改 `pubspec.lock`。

## 性能、并发与测试

性能优化必须基于真实问题，关注长对话、流式输出、大量消息、图片、SQLite 查询、Widget rebuild 和大型资源库。优先局部刷新、缓存、分页和增量计算，避免每个 token 都重建整个页面。异步逻辑必须考虑 dispose、请求顺序、重复点击、取消、Stream 生命周期、数据库并发、多次保存和 stale state；不要用 `Future.delayed` 掩盖同步问题。

Bug 修复原则上增加回归测试：先证明 Bug，再修复，再证明不再出现。无法自动测试时说明原因并提供人工验证方式。不得删除、跳过或降低失败测试，也不得修改预期值迎合错误实现。

默认验证：`dart format .`、`flutter analyze`、`flutter test`。涉及 Linux 桌面行为时按任务需要执行 `flutter run -d linux` 或相应 build。必须区分原有失败与本次修改引入的失败，不得谎称所有测试通过。

## Token 与流式输出节流规范

流式响应必须把“网络接收”和“界面刷新”分开：网络层应立即消费 SSE/HTTP chunk，不得为了 UI 节流而阻塞读取；中间层累积完整文本，UI 层按固定节奏批量发布。项目现有 `TypewriterController` 是默认实现，保持 30ms tick（约每秒 33 次 UI 更新），并根据缓冲长度自适应每次吐出字符数；不得在每个网络 chunk 上直接触发整页 rebuild。

所有流式控制器必须遵守以下约束：

1. 使用单一累积缓冲区和单调 cursor，chunk 只追加，不重复拼接已经展示的前缀。
2. 正常情况下以 30ms 为 UI 刷新下限；预览型长任务可使用 `GenerationLimits.streamingPreviewThrottle` 的 180ms 合并通知，但不得让网络读取等待 UI 定时器。
3. 流结束、取消、异常或 generation 失效时必须执行一次最终 flush 或明确清空，并取消 Timer/Stream 订阅；不得在 Widget dispose 后更新 `ValueNotifier`。
4. 通过 generation/task handle 丢弃过期响应，不能让旧请求覆盖新请求，也不能用 `Future.delayed` 解决竞态。
5. Token 统计以服务端 usage 为准；服务端未返回 usage 时才使用统一 `TokenEstimator` 做一次最终估算。展示进度可以节流，累计值和最终消息不能因节流丢失。
6. 持久化 Token 总量应合并写入并防抖，不能在每个 chunk 或每次 UI tick 写 SQLite/SharedPreferences；取消和异常也要保证已确认的 usage 不丢失。
7. reasoning、正文、进度条和滚动位置分别使用最小粒度的 notifier；流式正文更新不得触发设置页、资源库或整棵应用树重建。

新增或修改流式逻辑时，至少覆盖：高频小 chunk、单个大 chunk、空 chunk、流结束时仍有缓冲、取消后迟到 chunk、请求切换以及服务端 usage 缺失。节流参数必须集中在配置或控制器中，并解释依据，禁止在页面散落魔法毫秒值。

## 删除、重构与报告

删除代码前使用 `rg "SymbolName"` 检查动态引用、Provider、Route、平台代码、测试和 migration 依赖。重构应保持行为、改善结构，并尽量拆分架构、业务规则、UI 和数据库变更；不要为了理论完美架构扩大范围。

完成前执行 `git diff --check`、`git diff`、`git status --short`，检查正确性、范围、重复实现、安全性、架构边界、关键测试、注释和跨平台影响。

完成报告至少说明完成内容、根因（如适用）、修改文件、验证命令及结果、Commit SHA 与 message、剩余风险。若受环境或仓库问题限制，必须说明已完成、未完成、原因、当前状态、验证进度和下一步所需条件，不得伪造结果。

## 核心准则

1. 先理解后修改。
2. 先复用后新增。
3. 修根因而不是掩盖症状。
4. 使用 Git 保证可追溯。
5. 保护用户数据、凭证和现有工作。
6. 代码首先要让未来的维护者看得懂。

每次修改都应能够回答：改了什么、为什么改、影响什么、如何验证、出问题如何回滚。

## 推荐使用的 Agent Skills

涉及 Flutter/Dart 编码或审查时优先使用项目已有的 `effective-dart`、`flutter-best-practices`、`dart-refactoring`、`flutter-ui-refactoring`、`flutter-use-column-row-first`、`riverpod`、`testing` 和 `mocktail` 技能。涉及 API 凭证、用户数据、网络边界或威胁建模时使用已安装的 `security-best-practices` 与 `security-threat-model` 技能。技能用于辅助判断，不能替代本文件中的安全、Git 和验证要求。

## Agent 效率规范

为减少 Codex 的上下文和工具消耗，同时保持可审计性：

1. 复杂任务先定义目标、验收条件、影响范围和明确不做的事项；优先使用 `define-goal` skill 收敛任务。
2. 搜索优先使用 `rg`，先定位符号和调用链，再读取相关文件；不要无目的读取整个仓库或重复读取已确认内容。
3. 独立的只读检查应合并执行；有依赖关系的修改、验证和提交必须按顺序执行。
4. 文档或单文件修改不运行与风险无关的全量构建；验证范围应与变更风险匹配，但不能省略必要检查。
5. 已获得结论后不要重复调用相同工具；每次工具调用都应服务于任务目标、验证或风险确认。
6. 遇到不确定性先用最小范围搜索和历史检查澄清，不凭文件名猜架构，也不为了“看起来完整”扩大读取范围。
7. 任务完成后立即汇报变更、验证和剩余风险，不继续进行没有明确收益的探索。
