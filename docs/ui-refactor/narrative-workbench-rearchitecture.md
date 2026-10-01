# LT Narrative Workbench 信息架构重构

## 基线与范围

2026-10-01，main / ef1b2ef，开始时工作区干净。任务来源：用户附件 pasted-text-1.txt（60 节）。完整目标保持为 A–J 全阶段，本文不是缩小任务的替代规格。

只改 Presentation、navigation、interaction、layout、visual hierarchy；不得改变 SQLite、Runtime/Scene presence authority、Context planner、LLM/Streaming、Resource lifecycle/persistence、主题存储与朗读语义。使用真实 Provider/Controller，禁止假数据和第二套设置/导航 authority。

## A：只读审计结论

### Navigation map

- MainGate 由 ChatProvider.currentSection、currentAdventureId、isAdventureChatOpen 驱动；home/adventure 经 LandingScreen 到 AdventureDashboardScreen 或 AdventureSessionScreen。
- MainSidebar 的新建入口调用 navigateToAdventureHome；最近记录调用 openAdventure（取消前一流、加载存档、打开 Session）；资料库调用 openResourceLibrary；设置使用 setCurrentSection。
- MainGate 在 >=600 使用永久 Sidebar，手机非 Session 使用三项 NavigationBar；Session 手机隐藏 Bottom Navigation。侧栏默认折叠，内部通过 OverflowBox + clip 动画保持宽度。
- SettingsCenterScreen -> SettingsPage -> LanguageSettingsPage / ApiSettingsPage / ModelSettingsPage / AdvancedSettingsPage。另一个 SettingsScreen 已有二栏，但不在正式主入口。禁止根据名字误把它视为当前设置中心。
- Dashboard -> RecentSaves（openAdventure）、ActionCards（AssemblyCreatePage、PresetScenesScreen、资料库、设置）、Worlds、Characters、StateHub。
- Session -> AppBar、StatusHudBar、CharacterSwitcher、SessionMessageList、SessionInputBar -> QuickMenuButton；AppBar 与 QuickMenu 都提供角色/背包/字数/系统设置。RuntimeStateHubPage、SceneCharacterManagementPage 通过新 Route 进入，导致主 Navigation 消失。
- RuntimeStateHubPage 从 adventureRepoProvider 获取当前快照、scene、成员、timeline、turns、checkpoint；横向 SegmentedButton 五视图；World 再 ChoiceChip；Turn/Entity 详情 push。必须保留现有查询、分页、编辑、比较与 checkpoint 能力。
- SceneCharacterManagementPage 通过 SceneState.presentCharacterIds 与 Adventure provider 合法 presence mutation 实现 Present/Available/Unavailable；UI 已有分组，仍以 Card 呈现，禁止复活 participant authority。
- ResourceLibraryScreen -> ResourceLibraryController -> runtime abstraction；search/filter/status/sort/page -> grid -> detail 或 Studio；creation/trash 独立流程。不得绕过 Controller。
- ResourceStudioPage -> ResourceStudioController、SectionControlController、Capacity/Revision controller；已有 Outline + reader/editor，右侧 Inspector 缺失，generation/revision/capacity 控制散于正文。

### Control-depth map（基线）

| 控制 | 当前路径 | 目标 |
| --- | --- | --- |
| Continue / Switch | RecentSaves / Sidebar -> openAdventure | 1 click |
| Character management | Input QuickMenu -> Characters | Session 1 click |
| Runtime State | HUD 或 More -> Character | Session 1 click |
| Reply length | More/QuickMenu -> subpage -> option | <=2 interactions |
| Context preset | More -> Prompt -> dropdown -> option | <=2 from Session，visible Inspector 1 click |
| Custom weights | More -> Prompt -> dropdown -> Custom -> ExpansionTile -> slider | <=2 to visible sliders |
| Model | More -> ModelSelectPage -> model | <=2，Generation Inspector |
| Settings | SettingsPage -> pushed category，Advanced 混外观/数据 | Desktop 1 click 替换内容；Mobile 分类+详情 |

### Legacy surface / icon inventory

源码扫描（排除 generated）发现 Icons. 557 处 / 85 文件；Emoji 范围匹配 292 处 / 28 文件，并不等同于 292 个产品 UI Emoji。ARBs 各 25 处，character_sheet 28，dice_check 9；skill_presets、LLM prompt、engine/manager 文本必须先分类以保护叙事/协议内容。仅现有 assets/icons/deepseek.svg，SvgPicture.asset 用于 app_dialogs。未发现核心界面显式 Linear/Radial/SweepGradient（唯一命中 platform_utils）。装饰 Card 与彩色图标容器仍遍布 Dashboard、Prompt、Runtime。主要问题是信息组织与功能分散，不能仅改色彩/图标宣称完成。

## 实施与验收（按阶段提交）

- [x] A 审计：navigation/control-depth/legacy/inventory（本文）。
- [ ] B 基础：复用 Theme、AppBreakpoints、Spacing/Radius，轻量 SVG、workbench/inspector/section/navigation primitives，不新增依赖。
- [ ] C Shell：Sidebar 为 Workspace / Current Adventure / Recent Adventures / Settings；正常模型状态不常驻；Runtime/Characters 在主壳内；手机独立布局；导航 authority 仍 ChatProvider。
- [x] D Dashboard：继续/最近故事优先；Start 紧凑操作；真实 Worlds/Characters/Library；移除四张功能宣传卡与 Settings 卡。
- [ ] E Session：Scene/Characters/State/Context/Generation Inspector；回复长度和 Context 前置；Custom 直接 sliders；模型一步打开 selector；More 只含低频冒险操作；QuickMenu 职责迁移；Focus 隐藏 Sidebar/Inspector，正文复用 760 token；保留 search/send/stop/stream/read aloud。
- [ ] F Settings：正式入口二栏，分类点击替换右侧；手机分类+detail 标准返回；Generation/Context/Prompt advanced 拆责；复用 SettingsProvider persistence。
- [ ] G Runtime：局部侧导航、Turn list/detail、语义 diff、Character grouped actions；preserve authority/checkpoints/timeline/branch。
- [ ] H Resource：Desktop filters/list/selected detail；Studio outline/editor/inspector，手机 sheet/detail；保留 creation/trash/revision/control/朗读。
- [ ] I Visual：逐项分类移除全部 Product UI Emoji，迁移触及图标为 SVG，无伪图标/装饰渐变/glow/glass/module rainbow；最终列遗留表面。
- [ ] J 回归：format / gen-l10n / analyze / 全量 test / diff check / 完成审计。

每阶段先格式化修改文件、flutter analyze、定向 tests、diff check，再 review/commit，禁止把失败留到最后。新增文案覆盖 en/zh/zh-Hans/zh-Hant/ja/ko。Widget tests 复用 responsive_test_helper：320、360、375、390、412、768、1024、1440；长动态文本、放大字体、主题、SafeArea、键盘；验证关键操作实际可达和设置实际改变，不能只检查 Widget 存在。架构测试必须通过。

## 完成证据与交接

各阶段完成后在本节记录 commit、命令及结果、剩余风险。最终严格逐项验收用户 §55、§58、§59；未全部满足时为 PARTIAL，目标继续 active。推送前核对 origin/main，禁止 force；当前用户工作流是否允许推送需以已有授权为依据。

### C 第一阶段记录

主壳 Sidebar 已改为 Workspace / Current adventure / Recent adventures / Settings；Runtime 与 Characters 使用 AppSection 在主壳内显示，导航 authority 仍为 ChatProvider。默认折叠偏好与所有存档行为保留，正常模型状态移除，侧栏不再通过 OverflowBox/crop 动画处理布局。SVG loader 与 18 个统一 outline 资产已建立，6 个 ARB 增加工作区文案。B 的 Inspector/Section primitives 随 E/F 实际调用实现；C 的 Focus shell 随 E 实现，当前不可标为全部完成。

验证：workbench_navigation_test + test/architecture 共 29 项通过；既有 MainSidebar 两项通过；sidebar management route 一项通过。覆盖 320/360/375/390/412/768/1024/1280/1440，1.5x 文本与暗色，实际 Runtime/Library/Characters/Story 导航，保持 adventure ID。flutter gen-l10n 完成；analyze 已修复一项新增测试 const lint，提交前重跑。

### D Dashboard 阶段记录

基于 f7df2de：删除 DashboardActionCards 的四张同构宣传卡，正式替换为 DashboardStartActions（已 rg 检查全部调用并同步 tests）。首页为继续故事 / 最近冒险 / Start / 世界 / 角色 / 状态；Settings 不再是首页入口卡，Header 只有标题与未配置服务时的设置按钮。World/Character 与 RecentSaves 使用真实列表、分隔线和紧凑操作；所有 Dashboard 源码无 Icons./IconData/AppCard。最近存档保留删除确认与 Provider.openAdventure，World/Character 选择仍调用原始 config/card，加载失败明确显示错误与重试。State 入口改为 ChatProvider.setCurrentSection(runtimeState)，主壳不再被 push 覆盖。

建立复用 WorkbenchSection，用标题、分隔线和可换行 contextual action 表达层级。新增 workbenchAdventures 文案覆盖六个 ARB，并 gen-l10n。

验证：Dashboard / ui_screens_and_sidebar / workbench_navigation / architecture 60 项全部通过；实际存档恢复测试通过一个记录并转发 super.openAdventure 的测试 Provider 等待真实加载 Future（避免把点击后尚未完成的异步状态误当导航失败）；320/360/375/390/412/768/1024/1280/1440 与暗色 2.0x 字体；format、analyze 无问题，diff check 无问题。全量 tests 尚未运行（J 阶段执行），整个重构仍为 PARTIAL。

### 下一阶段交接

E 是当前下一步：读取 SessionAppBar / SessionInputBar / SessionMessageList / StatusHudBar / CharacterSwitcher 真实调用；建立 ContextWeightControls、ReplyLengthControls 供 Session 与 Settings 复用；Context Custom 必须保持现有权重并直接显示 sliders，Preset 调用原 SettingsProvider.setContextWeightProfile；消除 QuickMenu 的混合职责；Inspector 为 Scene/Characters/State/Context/Generation；Focus 由单一 Presentation state 驱动主壳收起 Sidebar/Inspector。不得改 Streaming、Runtime authority 或任何用户内容。

F 使用正式 SettingsPage（SettingsCenterScreen 的真实目标），不是仅改未接入的 SettingsScreen；后者是否删除需 rg 所有调用与 tests 后决定。G 保留 RuntimeStateHub 的实际五视图、world filters、分页、checkpoint/compare/edit、语义 guard。H 保留 ResourceStudio lifecycle/section/capacity/revision/朗读与 Library Controller。I 的 292 Emoji 范围匹配需要分类，不得删除用户叙事、fixture、prompt protocol。

### E Session 阶段记录

Scene / Characters / State / Context / Generation Inspector 已接入实际 Session。宽度依据 Workspace constraints：900+ 内联 300 px Inspector；更窄使用 SafeArea 的 85% 高底部面板。输入区直接提供篇幅、Context、角色、状态、模型，More 仅保留重启。旧 QuickMenu 与无效 callback facade 已删除并迁移所有调用与测试。角色/状态继续使用 ChatProvider.setCurrentSection，SceneState 与 runtime authority 未改变。

ContextWeightControls 复用 SettingsProvider 保存；4 个 preset 直接选择，Custom 保留现有权重并直接显示全部 sliders，拖动结束保存。ReplyLengthControl 两步选定；ModelSelectPage 的 Session applyOnSelection 分支选中后调用原 setProviderAndModel，其他 regenerate 路径保留确认。Focus 由主壳 Presentation state 驱动；root Expanded 与 reader Expanded 有稳定 Key，真实回归已确认切换不丢草稿、正文 controller 和 offset。HUD 变成文本状态摘要。字体放大时手势提示原本固定挤占 reader 导致溢出，现进入正文滚动并补齐关闭按钮语义与触控区域。

验证：Session workbench / phase3 / widgets / adventure feature / custom attribute / post-removal smoke / architecture 共 129 项通过，新增12项覆盖320/360/375/390/412/768/1024/1280/1440、暗色1.5x、真实Context/preset/custom slider持久化与重载、两步篇幅、模型实际切换、MainGate Focus保留draft/scroll；既有2x字体、键盘输入、send/stop/search/朗读等通过。SQLite异步测试使用真实仓库队列与pump刷新UI continuation，不使用任意延迟。analyze无问题；diff check通过。

E 的正文排版与 reading appearance 随 B/F/I 收敛，尚不将 E 整体勾选完成。F 的正式入口仍为 settings_pages.dart 中 SettingsPage：目前 push API/Model/Advanced，需改为真正的分类侧栏与替换内容；未接入 SettingsScreen 不能作为完成证据。

### F Settings 导航与拆责阶段记录

正式 SettingsPage 已使用自身 LayoutBuilder constraints，>=600 为240 px分类侧栏与右侧内容；小于600为分类列表/详情、标准SVG返回和PopScope系统返回。同一页面内替换内容，NavigatorObserver九种viewport回归确认分类切换不push新Route。分类仅采用已存在能力：Appearance、Language、Read Aloud、Generation、Context、Data；没有为General/About制造配置。

Generation复用ProviderConfigSection、ReplyLengthControl、ModelParamsSection；Context为ContextWeightControls + PromptAdvancedSettings。后者从旧PromptSettingsScreen实际拆出system prompt、author note和presets/preview，移除回复篇幅与权重的重复实现。未接入主入口的SettingsScreen和旧PromptSettingsScreen兼容门面删除；API/Model/Advanced独立页面删除，原/settings/api、model、advanced路径映射正式SettingsPage对应分类，showApiSettings也接入该分类。原语言独立deep-link保留，但嵌入内容复用LanguageSettingsContent。

朗读偏好移入独立ReadAloudSettingsSection，保留原readAloudController、实际语言能力、设置KV与全部测试。Appearance改为平面Section、可换行theme chips、语义选中色盘，移除glow、装饰图标和Card；Data以文本用量、真实诊断导出与原确认删除呈现。旧ClearCache按钮只显示成功SnackBar而无清理操作，故不再作为虚假能力展示；没有改动缓存/SQLite/Runtime backend。触及的新语言/朗读/外观/数据/Prompt控件均不新增字体图标、伪图标或Emoji。

验证：settings_workbench、r02_settings_navigation、settings_feature、settings_mobile、settings_read_aloud、adventure_feature、architecture共96项通过；最终API deep-link统一及朗读chips调整后重跑相关46项通过。新增10项覆盖320/360/375/390/412/768/1024/1280/1440、1.5x暗色所有分类、2x主题控件，保留既有主题/Accent/滚动/朗读KV回归。analyze无问题；format和diff check通过。

F 的Generation底层组件旧装饰Card和字体图标随I迁移；B/E正文排版仍待收敛。当前整个任务仍PARTIAL，下一步G Runtime的稳定局部导航、Turn list/detail和Character grouped actions；严格保留查询、presence、timeline/checkpoint/compare/edit authority。
