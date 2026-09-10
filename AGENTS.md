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

## 多 Agent 协作

`AGENTS.md` 是唯一正式 Agent 规范；`AGY.md` 仅作为兼容入口，不在其中维护重复规则。跨 Agent 协作时使用以下抽象职责：

- 方案/审计 Agent：调查现状、定位根因、分析调用链与影响范围、拆分任务，并定义可验证的验收标准。
- 执行 Agent：仅在批准范围内修改代码、补充测试并提交 Git；不得擅自扩大任务范围或进行“顺便优化”。
- 审核 Agent：默认只读 review-only，优先审核指定的 Git commit 或 diff，确认实现、测试和验收标准；除非明确授权，不主动修改代码。

默认协作流程为：Plan/审计 → Execute → Review → 必要时返工 → 验收 → 下一阶段。已有可靠审计结论时不得重复全仓库扫描，应优先读取任务指定文件及其调用链。一个任务限定在一个明确子系统内；定向测试优先，全量测试根据变更风险决定。各阶段应交接范围、结论、验收标准和待处理风险，避免重复工作或无依据扩大范围。

### Agent 专属规则文件

`AGENTS.md` 是整个 LT 项目的最高级、跨 Agent 通用规范。Agent 可使用各自的项目规则与上下文文件；例如 CodeBuddy CLI 在开始任务时必须同时阅读 `AGENTS.md` 和 `CODEBUDDY.md`。其中 `AGENTS.md` 存放跨 Agent 通用规则，`CODEBUDDY.md` 仅存放 CodeBuddy 专属工作流、工具约束与上下文说明；两者冲突时以 `AGENTS.md` 为准。不得在两个文件中复制大量相同规则。

### 方案文档交接

复杂修复、架构调整或跨 Agent 接力任务，方案/审核 Agent 应优先将完整实施规格写入 `docs/`，例如 `docs/codex/p0-character-import-adventure-loading-rework.md`，而非仅依赖聊天输出。方案文档至少包含 Git/代码基线、已确认根因、Blocker / Major、修改范围、涉及文件、实施要求、禁止范围、测试要求和验收标准。

执行 Agent 不得将聊天中的超长 Prompt 作为唯一事实来源，默认交接流程为：

`AGENTS.md` + Agent 专属规则文件（如 `CODEBUDDY.md`）+ `docs/` 中本任务实施方案 → 实现 → 独立审核 → 必要时更新方案或返工。

审核 Agent 应将 Blocker / Major 转化为可执行的修复规格；复杂任务优先更新方案文档，而非仅留在聊天输出。执行 Agent 必须严格按方案文档范围工作，发现额外问题只记录，不得未经授权扩大范围。任务完成后，审核 Agent 应优先对照同一份方案文档、commit diff 与测试结果验收。

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

## Flutter 响应式布局与移动端溢出防护

移动端、小窗口、动态文本尺寸属于 LT 的一等支持场景。桌面显示正常不代表 UI 任务完成。

### 最低兼容宽度与响应式判断

所有新增或修改的页面、组件、Dialog、BottomSheet、AppBar、Header、输入栏、状态栏、Card 和列表项，至少考虑以下逻辑 viewport：

- `320 px`：LT 项目的最低兼容逻辑宽度，必须无横向布局溢出，是不可降低的 UI 硬门槛。
- `360 px`：常见小屏 Android。
- `390 px`：常见手机。
- `412 px`：较宽手机。
- `768 px`：平板 / compact desktop。
- `1024 px+`：桌面。

Agent 不得只在开发机桌面尺寸验证 UI。响应式判断必须基于当前组件实际可用空间，不得基于手机品牌、型号或特定设备名称。页面级断点可默认参考：`< 600 px` 为 mobile，`600–899 px` 为 tablet / compact，`>= 900 px` 为 desktop；组件级布局优先根据自身约束决定。禁止散落未解释的魔法断点（如 `width < 537`、`width > 743`）；确需特殊断点时必须写明原因。

优先使用 Flutter 原生约束能力：`LayoutBuilder`、`MediaQuery.sizeOf(context)`、`MediaQuery.paddingOf(context)`、`MediaQuery.viewInsetsOf(context)`、`Flexible`、`Expanded`、`Wrap`、`ConstrainedBox`、`SizedBox`、`SafeArea`、`AspectRatio`，必要时使用 `FittedBox`。布局应先用 `Row`、`Column`、`Expanded`、`Flexible`、`Wrap` 表达弹性关系，再考虑固定尺寸或坐标定位。

### Row、动态文本与操作区域

只要 `Row` 中存在动态 `Text`、用户名、世界观/角色/模型名称、Token 数字、状态字符串、Button、TextField、Dropdown、trailing widget 或动态数量组件，就必须主动检查窄屏。不得默认将动态文本和按钮直接并列后认为布局安全。可能增长的文本必须根据业务语义选择 `Flexible` / `Expanded` 配合 `TextOverflow.ellipsis`，或允许换行；重要业务信息不得仅靠 ellipsis 丢失。

窄屏无法保持单行时，必须按语义改为 `Row -> Wrap`、`Row -> Column`，将横向按钮组改为 `Wrap` / `Column`，或把低优先级操作收纳到菜单。不得为了维持桌面布局牺牲手机可用性，也不得缩小点击区域；移动端必须保留合理触控区域。按钮策略优先级为：`Wrap`、`Column`、菜单收纳、合理缩短文案，再考虑其他响应式策略。

所有 UI 必须假设文本长度不可控，并考虑中文/英文差异、用户输入、AI 返回内容、用户名、模型名、角色名、世界观名、存档名、错误信息、Token 大数字、状态信息和系统字体放大。短标签可使用 `maxLines` 与 `TextOverflow.ellipsis`；正文或核心信息应允许换行、滚动或自适应高度。禁止通过无限缩小字体解决溢出。

### 禁止掩盖 Overflow

出现 overflow 时必须修复约束根因，不得为消除报错而直接使用 `ClipRect`、`OverflowBox`、隐藏 Widget、随意裁切、固定高度强压内容、固定宽度、Transform 位移、负 offset、横向 `SingleChildScrollView`、随机 `SizedBox` 或缩小到不可读的字体。除非它们本身符合真实产品设计需求，否则不能作为普通 Overflow 修复手段；不得用异常捕获掩盖布局问题。

“让黄色 RenderFlex 提示消失”不算修复完成，必须找到真正的父子约束问题，并检查同类组件。

### 高风险区域、Insets 与资源布局

每次修改以下区域都必须额外进行窄屏审查：AppBar、Header、顶部状态栏、Token 进度、字数状态、Adventure Session 顶部栏、Session 输入栏、HUD、Navigation、Bottom Navigation、Dialog 标题、BottomSheet、Wizard / Stepper、多按钮工具栏、Card Header、ListTile trailing、资源库、冒险主页和创建向导。信息过多时优先重新组织层级，不要强行塞入同一行。

任何输入区域必须同时考虑 `320 px`、`SafeArea`、`viewInsets.bottom`、软键盘、多行输入、发送/附加按钮和横屏；不得让 TextField 被挤成极窄区域、发送按钮出屏、键盘挡住核心区域，或让 Bottom Bar 与系统导航区域重叠。

移动端不得假定完整屏幕都可用。必须考虑刘海、灵动岛、Android 状态栏/导航区域、iPhone Home Indicator、横屏和键盘，优先使用 `SafeArea`、`MediaQuery.paddingOf(context)`、`MediaQuery.viewInsetsOf(context)`，禁止用固定 top / bottom padding 模拟系统安全区。

图片必须有明确的最大约束或比例（如 `AspectRatio`、`BoxFit.cover`、`BoxFit.contain`），不得让原始尺寸决定页面布局。`ListTile` / `Card` 必须检查 `leading`、`title`、`subtitle`、`trailing` 的组合；长 title + trailing 是高风险组合。标准 `ListTile` 无法可靠适配时应改为自定义响应式布局。

Dialog / BottomSheet 禁止使用超过 viewport 的固定宽高；长内容必须有正确的滚动区域，并考虑小屏高度、横屏、键盘和 SafeArea。`Column` 加大量动态内容时不得没有 scroll，导致 bottom overflow。

### Overflow Bug 修复流程

遇到 `A RenderFlex overflowed by ...`、`RIGHT OVERFLOWED`、`BOTTOM OVERFLOWED`、`RenderBox was not laid out`、`BoxConstraints forces an infinite width` 或 `BoxConstraints forces an infinite height` 时，Agent 必须：

1. 找到真实 constraint 来源。
2. 判断问题属于父组件约束、子组件固定尺寸、动态文本、Button / trailing、Responsive breakpoint、Scroll hierarchy 或 SafeArea / Insets。
3. 修复根因，并用 `rg` 搜索项目中相同布局模式。
4. 为已修复问题增加或更新 Widget Regression Test。
5. 至少验证 `320 px`、一个常见手机宽度和桌面尺寸，且不得遗留 overflow exception。

### Widget 响应式测试硬规范

凡新增或修改移动端相关 UI，原则上必须增加或更新 Widget Test，至少覆盖 `320 × 568`、`360 × 640`、`390 × 844`、`412 × 915`；重要公共组件还应考虑 `768 × 1024` 和桌面尺寸。测试至少验证 `tester.takeException() == null`、无 RenderFlex overflow、无布局 Exception、主要操作仍存在、核心按钮可点击、必要内容可滚动到，以及 Dialog / BottomSheet 在小屏可用。涉及动态文本时必须提供一个明显长于正常值的文本；涉及字体布局时至少考虑一次较大 text scale。

测试应优先复用统一 viewport helper，例如 `test/helpers/` 或 `test/widget/responsive/` 中的 `setViewport(tester, width: 320, height: 568)`。若已有等价工具必须复用，不得重复造轮子。Helper 必须恢复 `tester.view`，统一 `devicePixelRatio`，并避免测试之间污染 viewport。

任何已经发生并修复过的 UI Overflow，都应尽可能通过自动化回归测试防止复发：人工发现 Bug → 定位根因 → 修复 → 新增 Widget Regression Test → 未来 `flutter test` 自动阻止复发。测试是防回归机制，而不只是记录已有行为。

### UI Definition of Done 与提交前检查

对于任何 Flutter UI 任务，“桌面显示正常” != “任务完成”。若没有验证最低 `320 px` 逻辑宽度及动态内容场景，Agent 不得汇报移动端适配完成、响应式完成、UI 修复完成或 Overflow 已完全解决。

UI 任务至少确认：`320 px` 无横向 RenderFlex overflow；常见手机宽度无异常；动态长文本不破坏布局；Button 不出屏；输入区域可用；SafeArea 正确；键盘场景合理；桌面布局无明显退化。

完成 Flutter UI 修改后，必须主动检查本次 diff 是否新增或修改 `Row`、`Flex`、`Stack`、`Positioned`、固定 width/height、大量 `SizedBox(width:)`、`OverflowBox`、`ClipRect`、`FittedBox`、横向 `SingleChildScrollView`、`TextOverflow`、`ListTile trailing`、Dialog 固定尺寸、魔法 breakpoint、固定字体或动态 `Text`。这些写法不一定错误，但必须确认其在 `320 px` 下具有正确约束。

`flutter analyze` 通过和 `flutter test` 通过不能单独证明响应式布局正确；UI 任务还必须有 responsive / viewport validation。无法启动模拟器时，至少使用 Widget Test 模拟 viewport。

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
