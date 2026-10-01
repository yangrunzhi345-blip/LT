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

## UI / UX / Design System：LT Narrative Workbench Design Language

LT 的正式设计语言为 **LT Narrative Workbench Design Language**。产品 UI 应体现 Narrative IDE、Narrative Workbench、Long-form Reading Environment 和 Structured World / Character State Workspace 的组合定位，不得设计成普通 AI Chat App、AI SaaS Dashboard、Material Demo 或 Card-based Flutter App。

### 五条核心原则

所有新增和重构 UI 必须以以下原则作为设计与验收依据：

- **Content first.** 内容优先。
- **State visible.** 状态可见。
- **Tools contextual.** 工具随上下文出现。
- **Structure persistent.** 结构保持稳定。
- **Interface quiet.** 界面保持安静。

### 设计参考与边界

借鉴成熟产品的设计方法，不简单复制任何单一产品：

- **Linear**：Workbench layout、Persistent sidebar、Inspector、高信息密度、Compact controls、Contextual actions、Activity / Timeline 呈现。
- **Readwise Reader**：长文阅读、Focus reading mode、Narrative typography、可配置阅读宽度、阅读留白、TTS / 阅读控制、阅读时减少界面 chrome。
- **Notion**：Document-first 内容呈现、安静的编辑画布、结构化内容层级、Metadata 与内容结合、减少视觉装饰。
- **Raycast**：紧凑控件、Settings 信息架构、Command palette、Keyboard-first 交互、Menu、Dialog、Search；不得复制其 Liquid Glass 风格。
- **Craft**：结构化内容编辑、资源创建工作区、文档 Section、Collection、Outline + Editor + Inspector 组合。

### 工作台布局：Navigation / Workspace / Inspector

Desktop 默认采用 `Navigation | Workspace | Inspector`。三者职责明确，保持工作区上下文和稳定结构，不把所有对象都设计成独立全屏页面。

**Navigation** 是长期稳定的信息架构，主要覆盖 Adventure、Chapters、Characters、World、Timeline、Resources、Creation Studio、Runtime State、Settings。Desktop 优先使用 persistent sidebar，合理场景允许用户折叠；不得过度装饰，也不得因对象层级不断 push 新页面或进入 Character / World / Resource 而让导航和整个工作区上下文消失。

**Workspace** 是主要工作区域，负责 Narrative reading / generation、Character / World / Resource editing、Creation Studio、Timeline inspection、Runtime State 和 Settings content。实际内容必须优先展示；推荐 `Title → Metadata → Primary content → Contextual actions`，禁止以 Decorative header、Gradient banner、Large cards、Feature cards 层层堆叠后才出现实际内容。

**Inspector** 显示当前选中对象的上下文、属性、状态和操作，必须随选择变化，不能成为第二套 Navigation。例如：

- Character「林恩」：Current State（Location、Presence、Life、Mood）、Relations、Scene、Revision、History。
- World Entity「银月城」：World State（Faction、Population、Weather、Threat）、Revision、History。
- Resource：Type、Status、Generation、Revision、Metadata。

### Reading Mode 与 Typography

Narrative Reading 必须具有独立于管理体验的阅读体验，不能仅作为普通 Workspace 内的一张 Card。阅读时应允许收起 Sidebar / Inspector、弱化 Toolbar、增大正文留白，并提供 Narrative Typography、Read Aloud、Reading appearance 和 Focus mode。正文最大宽度建议为 `680–780 px`，允许配置阅读宽度；不得在超宽屏铺满窗口，也不得在小屏强制该宽度。

UI Typography 与 Narrative Typography 必须分开管理，不能使用完全相同的排版参数。以下为建议值，Flutter 中按逻辑像素理解，并尊重系统字体缩放：

| 体系 | 用途 / 层级 | 建议 |
| --- | --- | --- |
| UI Typography | Navigation、Toolbar、Settings、Inspector、Metadata、Table、Form、Control | Sans Serif |
| UI Typography | Page title | 20–24 px |
| UI Typography | Section title | 14–16 px |
| UI Typography | Body | 14 px |
| UI Typography | Secondary | 12–13 px |
| UI Typography | Metadata | 11–12 px |
| Narrative Typography | 小说和长文本正文 | 17–20 px；行高 1.7–1.9 |
| Narrative Typography | 阅读字体 | 可使用 Serif、Noto Serif、Source Han Serif 或系统可用的高质量阅读字体 |

### 内容层级与 Card 使用限制

**禁止 Card Everything。** 不得把每个属性、状态或设置项包装为 Card。Current State 下的 Health、Location、Mood、Faction 应优先采用对齐的属性 / 值列表，而不是四张独立 Card。

优先通过 Typography、Spacing、Alignment、Divider、Section hierarchy、Selection state 和 Subtle border 建立层级。Card 仅适合真正独立的对象或预览单元，例如 Adventure preview、Resource preview、Template preview、Collection item、Gallery item；不能作为所有布局的默认容器。

### 视觉语言与渐变边界

采用 Flat surfaces、Subtle borders、Single accent color、Editorial typography、Dense workbench layout、Minimal decoration。核心界面禁止默认采用 Glassmorphism、Liquid Glass、Neon、Glow、Cyberpunk、AI purple gradient、大型装饰渐变、过量阴影、超大圆角 Card、Rainbow module colors 和应用内 Hero banner。

核心产品 UI 默认禁止装饰性渐变，包括 Gradient button、AppBar、Navigation、Settings、Card、AI button、紫蓝 AI 渐变和 Animated gradient。

**Gradients belong to artwork, not to LT's core interface language.** 渐变仅可用于实际 artwork 内容，如 Cover artwork、User-generated artwork、Image overlay、Illustration asset；技术上适当的 Shimmer loading effect 可作为明确例外，不得借此引入普通界面装饰渐变。

### Color、Surface 与 Design Token

颜色以中性色为主体，使用单一 Accent，推荐 Emerald / Jade。以下是暗色主题的推荐方向，不是直接散落到 Widget 的硬编码值；实际颜色必须由项目 Theme / ColorScheme 管理，并提供适配明暗主题的值：

| Token | 暗色推荐值 |
| --- | --- |
| Background | `#0E0F11` |
| Surface | `#121417` |
| Raised Surface | `#17191D` |
| Hover | `#1B1E22` |
| Border | `#292C32` |
| Border Strong | `#363A42` |
| Text Primary | `#F1F2F3` |
| Text Secondary | `#A3A7AE` |
| Text Muted | `#6F747C` |
| Accent | `#42A37B` |
| Accent Hover | `#50B388` |

**禁止彩虹模块色。** 不得以 Characters = Purple、World = Blue、Timeline = Orange、Resources = Green、AI = Pink、Settings = Gray 等方式表达模块身份。颜色主要用于 Selection、Focus、Primary action、Success、Warning、Error 和 Runtime semantic state。Semantic color 仅用于真实语义，如 Success、Warning、Danger、Info、Selected、Unsaved、Present、Alive、Error；不得为丰富页面随意增加颜色，也不得只靠颜色表达重要状态。

Surface / Elevation 保持少量层级：Level 0 = Background、Level 1 = Panel、Level 2 = Popover / Dialog。默认优先使用 `1 px` subtle border 区分层级，不依赖大型阴影。

统一建立 radius token：`xs = 4 px`、`sm = 6 px`、`md = 8 px`、`lg = 12 px`、`xl = 16 px`。建议 Button / Input 为 6 px，Menu / Panel 为 8 px，Dialog 为 12 px，Large modal 为 16 px；普通 UI 不应大量使用 24 / 28 / 32 px 圆角。

Spacing 统一使用 4 px Grid：`4、8、12、16、20、24、32、40、48、64`。常用 Row padding 为 8–12 px、Section gap 为 20–24 px、Page padding 为 24–32 px；根据可用空间响应式调整，Narrative 阅读区域可以使用更大留白。

### Timeline 与 Runtime State

Timeline 面向普通用户呈现叙事活动与语义变化，不能只是 Debug log。例如显示 `Turn 138`、`16:31`、「林恩进入银月城」、`Location：北门 → 银月城`、`Magic：25 → 27`，而非 `character.lynn.runtime.location.path`。点击 Turn 后可在 Workspace 或 Inspector 查看详细 diff。

Runtime State 建议按 Characters、World、Scene、Relations 分层；Character State 采用 Current（Life、Location、Presence、Mood）与 Changes。默认不得向普通用户暴露 raw schema path、internal ID 或 implementation terminology，详细变化也应使用用户可理解的语义。

### Creation Studio、Settings 与 Command Palette

Creation Studio 采用 `Outline | Editor | Inspector`：Outline 可包含 Overview、Appearance、Personality、Background、Relations、Runtime Defaults、Generation Rules；中间编辑内容，右侧展示 Generation state、Revision、Metadata、Validation、Context、Runtime defaults。不得做成长页面堆叠 Card。

Settings 采用稳定二栏结构：左侧类别，右侧实际设置。类别可包括 General、Appearance、Language、Read Aloud、AI Providers、Context、Storage、About；不要每个设置项单独放入大型 Card，设置数量增加后可支持搜索。移动端按下述规则重组，保留类别与当前内容的关系。

未来大量操作应允许通过统一 Command Palette 收敛，例如 Continue story、Open character / world / timeline / resource、Create character、Read aloud、Switch context profile、Open settings。不得因新增功能不断向 AppBar / Toolbar 堆按钮；本规范不要求在文档任务中立即实现 Command Palette。

### Responsive 工作台结构

不得简单压缩 Desktop 三栏布局：

| 场景 | 主结构 | Navigation / Inspector |
| --- | --- | --- |
| Desktop | Navigation / Workspace / Inspector | 稳定 Sidebar 与上下文 Inspector，可折叠 |
| Tablet | Navigation / Workspace | Inspector 使用 Drawer 或 Overlay panel |
| Phone | Workspace 为主 | Navigation 使用 Bottom Navigation、Drawer 或 Compact navigation；Inspector 使用 Detail page、Bottom sheet 或 Full-screen detail |

Creation Studio、Settings 等多栏结构同样需按可用空间重组，保持当前位置、选择和上下文可理解。具体断点、最低 320 px、SafeArea、键盘、触控区域和 viewport 测试遵守下方「Flutter 响应式布局与移动端溢出防护」，不得因高密度桌面设计降低移动端要求。

### Motion、Interaction Density 与 Material 3

Motion 必须快速、克制。建议 Hover 为 80–120 ms、Button 为 100–140 ms、Expand 为 160–200 ms、Panel 为 180–220 ms、Page 为 180–240 ms、Dialog 为 180–220 ms。禁止默认使用 Bounce、Excessive spring、Hover zoom、Floating card animation、Constant glow、Animated gradient。

Desktop 是高信息密度生产力工具：Button 不应普遍过高，Row 不应无限增大，Toolbar 保持紧凑；Secondary action 可在 hover / menu 中出现，但须保留键盘与触控可操作的入口。不要让所有操作同时突出，Primary action 才应获得最明显的视觉权重；紧凑不等于缩小移动端触控区域。

**Material 3 is an implementation foundation, not LT's final visual identity.** 可以继续使用其 Theme、ColorScheme、Typography、Accessibility、Component behavior、Adaptive foundations；不得因为 Flutter 提供默认 Card / FilledButton / Container 就直接照搬默认视觉，必须服从 LT Design Language。

### 产品 UI 禁止 Emoji 与 Unicode 伪图标

LT 正式产品 UI 不得使用 Emoji 作为导航、功能、按钮、菜单、状态、空状态插图、列表项、Section 标识、标题前缀、提示装饰、Toast / Snackbar、Dialog、设置项或任何视觉操作提示（affordance）。此规则覆盖 Adventure、Character、World、Timeline、Resource、AI 相关标识及 Loading / Success / Warning / Error 等状态。

- 禁止 `✨ AI Generate`、`🚀 Start Adventure`、`📖 Story`、`👤 Character`、`🌍 World`、`🕒 Timeline`、`⚙️ Settings`、`✅ Completed`、`❌ Failed`、`⚠️ Warning` 等图标用法。
- 不得以“让页面更活泼”为由添加 `✨`、`💡`、`🔥`、`🎉`、`❤️`、`📍` 等装饰性 Emoji。
- 不得通过普通 Unicode 符号绕过禁令：`⌂`、`◎`、`◇`、`≋`、`□`、`⌘`、`◈`、`⚙`、`★`、`●`、`▶`、`◀`、`→`、`←`、`✓`、`×`、`+`、`-` 等字符，只要承担图标或控件 affordance 职责，就必须使用正式 SVG 图标。
- 普通文本语义中的标点、箭头、数学符号和代码不受限制，例如 `A → B`、`25 → 27`、`x + y`、`v1.1.16`。判断依据是字符的用途，而非字符本身。

### 必要图标统一使用 SVG，优先考虑无图标

New product UI icons MUST use SVG assets/components. Do not introduce Emoji, Unicode pseudo-icons, or decorative text symbols as substitutes for icons.

新增产品 UI 需要图标时必须使用 SVG。适用范围包括 Navigation、Sidebar、Bottom Navigation、AppBar、Toolbar、Action buttons、Context / Popup menu、Settings、Inspector、Character / World management、Timeline、Runtime State、Resources、Creation Studio，以及 Search、Filter、Sort、Expand / Collapse、Back / Forward、Add / Remove、Edit、Delete、Copy、Share、Import / Export、History、Revision、Read Aloud、Language、Theme 和需要图形表达的 Warning / Error / Success 状态。不得以字体图标或其他伪图标替代这一新增要求。

Do not add an icon merely because a UI element can have one.

图标必须具有实际的信息识别价值。优先通过 Typography、Spacing、Alignment、Divider、Section hierarchy、Color state 和 Selected state 表达界面结构，不给每一行文字附加图标。`Character`、`World`、`Timeline`、`Resources` 等文字足够清晰时直接使用纯文本；`Generate` 不需要装饰，确实需要图标时才使用 SVG 与文本标签组合。

### SVG 风格与主题颜色

- 使用统一设计语言，普通功能图标优先 Outline / Stroke；同一页面不得混用不一致的 Outline、Filled、Emoji、3D 等风格，不以复杂插画代替普通功能图标。
- 保持视觉重量、stroke width、viewBox 和对齐方式一致。默认使用 `24 × 24 viewBox`、`stroke-linecap="round"`、`stroke-linejoin="round"`；按组件上下文调整显示尺寸时保持一致的视觉比例。
- 普通 UI 颜色不得硬编码在 SVG 内部。优先使用 `currentColor`，或可由 Flutter Theme / ColorScheme 控制的着色方式；同时支持 Light / Dark、Hover、Selected、Disabled、Error / Warning / Success 和未来主题切换。
- 同一 SVG 应复用于不同状态，不为普通导航图标创建 `icon_green.svg`、`icon_white.svg`、`icon_dark.svg`、`icon_selected.svg` 等颜色副本。品牌 Logo 保留其品牌识别要求，不将其专用配色与比例作为普通功能图标的默认样式。

### 资产组织与 Flutter 实现

当前项目已使用 `assets/icons/`，`pubspec.yaml` 已声明该目录及 `flutter_svg` 依赖，`lib/widgets/app_dialogs.dart` 已有 `SvgPicture.asset` 加载用法。后续实现必须先搜索现有资产、加载代码与公共组件，复用现有目录和方案；不得未经审查另建目录体系、重复封装加载器或大规模移动资产。本规范任务不添加依赖；未来任务确需改变 SVG 方案时按依赖评估规范处理。

- 文件名使用 lowercase snake_case，描述语义而非颜色，例如 `character.svg`、`world.svg`、`timeline.svg`、`settings.svg`、`history.svg`、`search.svg`、`chevron_left.svg`、`chevron_right.svg`。
- 禁止随机 hash、无语义名称及颜色/版本堆叠名称，例如 `icon1.svg`、`new_icon.svg`、`green_character_icon_final_2.svg`、`settings_white.svg`；不得复制视觉上完全相同的 SVG，优先复用。
- 新 Flutter 代码禁止用 `Text('✨')`、`Text('📖')`、`Text('👤')`、`Text('🌍')`、`Text('⚙️')` 或 `const Text('⌂')`、`const Text('◇')`、`const Text('◎')` 等充当图标；适用于其他文本 Widget、字符串前缀和转义 Unicode 的等价实现。

### 历史 UI 与内容边界

**No new visual debt. Touch it, align it.**

本任务仅固化设计规范，不要求为更新 AGENTS.md 全量重构历史页面，也不涉及业务、数据库、Repository、Domain、State System、LLM / Streaming / Creation pipeline、版本号、依赖或资产迁移。新增页面必须符合设计语言；修改已有 UI 时在受修改组件范围内同步收敛，不新增 Emoji、Unicode pseudo-icons、无意义渐变、Card Everything 或模块彩虹色，不以此扩大无关重构范围。

图标方面继续遵守 **No new Emoji debt. Touch it, fix it.**

本规范文档任务不要求立即重写历史 Emoji / Unicode 图标，也不得因发现历史用法扩大为全项目 UI 重构。后续新增代码不得引入 Emoji UI 或 Unicode 伪图标；修改已有含此类图标的组件时，必须同时将该组件的相关图标迁移为项目 SVG 方案，若图标无实际价值则移除装饰并保留清晰文本。对应页面重构时必须清理相关历史用法，按组件范围增量迁移。

规则限制产品 UI，不限制用户生成或叙事内容。用户小说正文、角色卡内容、世界观文本、对话内容、用户输入、AI 生成的故事文本、导入资源原文均可包含 Emoji；不得因为产品 UI 禁令过滤、删除或改写这些内容中的 Emoji。

开发日志、测试 fixture、协议测试文本中，Emoji 本身是测试或诊断对象时可以保留；仅作装饰时应避免，包括 `testWidgets('✨ button works')` 这样的测试名称。测试验证语义，优先通过 Key、Semantics、Text label、Widget type 或 stable test identifier 定位控件，不依赖 Emoji 作为 UI identifier。

### 无障碍与审核要求

- 纯装饰 SVG 不得产生无意义的重复语义；Icon-only button 必须提供明确的 tooltip / semantic label 和可访问名称。
- 关键行为不得仅靠无名称图标表达，Back / Delete / Close 等操作必须有明确语义。
- 状态变化不得仅通过颜色或图形表达，应同时提供可访问的文本或语义说明。
- Focus state 必须可见，Keyboard navigation 不得被破坏；hover 中的操作也须可通过键盘到达。
- Text contrast 必须足够；推荐色值与紧凑排版不能替代对实际主题、状态和字体尺寸的可读性检查。
- Interactive target 必须可操作，保留合理触控区域并支持必要的键盘操作。
- UI 任务审核时检查新增图标是否必要、是否使用 SVG、是否符合统一风格与主题状态、受修改组件的历史伪图标是否已迁移，以及内容豁免与无障碍是否保持。图标迁移仍须满足下述响应式布局和触控区域要求。

### UI 开发与审核 Checklist

任何新 UI 或明显 UI 重构，在开发前与验收时至少检查：

- [ ] 内容是否是首要视觉焦点（Content first）？
- [ ] 稳定结构是否保留（Structure persistent）？
- [ ] Inspector 是否随上下文变化，而非第二套 Navigation？
- [ ] 这些信息是否更适合不用 Card 展示？
- [ ] 图标是否确有必要？
- [ ] 必要图标是否使用 SVG？
- [ ] 产品 UI 是否未使用 Emoji？
- [ ] 是否未使用 Unicode symbol 充当 pseudo-icon？
- [ ] 是否未引入装饰性渐变？
- [ ] 模块身份是否避免不必要的颜色依赖？
- [ ] Desktop / Tablet / Phone 布局是否可用，并符合下方 320 px 与 viewport 验证要求？
- [ ] 是否向普通用户隐藏内部实现细节？
- [ ] Accessibility 是否保留，包括语义、可见焦点、键盘、文本对比度和可操作目标？

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
