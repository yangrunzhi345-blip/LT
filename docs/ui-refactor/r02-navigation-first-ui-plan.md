# R02 Navigation-first UI Architecture Refactor Plan

> 本文档为 R02 规划阶段唯一产物。STRICT READ-ONLY：本轮未修改任何 `lib/`、测试、配置或数据库。全部结论来自当前仓库实际代码（commit `b4d02f1`），无假设性推断。

---

## 1. Baseline

| 项 | 值 |
|---|---|
| 当前 HEAD | `b4d02f1`（tag `v1.1.13`，`main`，与 `origin/main` 同步，工作区干净） |
| Flutter | 3.44.8 stable（framework revision 058e0af2c2） |
| Dart | 3.12.2 stable；`pubspec.yaml` 约束 `sdk: '>=3.0.0 <4.0.0'` |
| 状态管理 | Riverpod `ProviderScope`（根注入）+ 遗留 `ChatProvider extends ChangeNotifier`（`lib/providers/chat_provider.dart:46`） |
| 导航 | 无全局命名路由表；`MaterialApp(home: MainGate)`（`lib/main.dart:98`）状态驱动顶层切换；深层用 `Navigator.push` |

### 1.1 当前导航方式（实际，非假设）

- **顶层 section 切换不走 Navigator**：`MainGate` watch `chatProvider.select((cp) => cp.currentSection)`，按 `AppSection.adventure / resources / settings` 直接在 `body` 内切换 Widget（`lib/main.dart:263-350`）。移动端为 `NavigationBar`，桌面为常驻 `MainSidebar`。
- **深层页面导航**：`Navigator.of(context).push` + `MaterialPageRoute`；统一入口为 `lib/core/router/app_router.dart` 的 `AppRouter.push / pushReplacement / pageRoute / slide`（桌面 Fade / 移动 Slide，200ms/180ms，尊重 `disableAnimations`）。
- **Deep link**：`AppRouter.onGenerateRoute` 仅注册 `/library`、`/studio` 两条 canonical 路由（含 pre-Phase-11 兼容拼写）。
- **已有的 Page 化通道**：`lib/core/widgets/form_sub_page_scaffold.dart` 提供 `FormSubPageScaffold`（AppBar + SafeArea + `resizeToAvoidBottomInset` + `viewInsets` bottomBar 补偿 + maxWidth 840）与 `showFormSubPage()` 推入。

### 1.2 目录结构现状

- `lib/features/`：`resource_library`、`resource_studio`（application/use_cases + domain + presentation 分层，Riverpod controllers）；`adventure`（home/session/wizard/templates）；`prompt_settings`；`settings`。
- `lib/screens/`：**遗留目录**（`chat/`、`resource_library/`），仍被 features 直接 import：
  - `adventure_session_screen.dart:11-14` → `screens/chat/widgets/`（character_sheet、character_switcher、inventory_screen、search_bar）
  - `session_message_list.dart:10-12` → `chat_dialogs.dart`、`error_card.dart`、`message_bubble.dart`
  - `adventure_wizard_screen.dart:28-30` → `screens/resource_library/`（character_card_tab、scene_batch_import_page、worldview_tab）
  - `widgets/app_dialogs.dart:18` → `character_card_edit_page.dart`
- `lib/core/widgets/`：已存在 `AppTextField`、`AppDropdown`/`AppMultiSelectDropdown`、`AppActionButton`、`AppCard`、`AppEmptyState`、`FormSubPageScaffold`、`narr_aitor_dropdown`。

### 1.3 已有可复用基础设施（R02 必须先复用，禁止重复造轮子）

| 设施 | 位置 | 说明 |
|---|---|---|
| `AppRouter` | `lib/core/router/app_router.dart` | push/pushReplacement/pageRoute/slide + deep-link 解析 |
| `FormSubPageScaffold` + `showFormSubPage` | `lib/core/widgets/form_sub_page_scaffold.dart` | Page Shell 雏形，已处理键盘避让 |
| `AppTextField` | `lib/core/widgets/app_text_field.dart` | 统一语义化输入框，M3 token、明暗主题 |
| `AppDropdown<T>` / `AppMultiSelectDropdown<T>` | `lib/core/widgets/app_dropdown.dart`（1097 行） | 全端统一下拉，**基于 `OverlayEntry` 自绘浮层**（见风险） |
| `AppActionButton` / `AppCard` / `AppEmptyState` | `lib/core/widgets/` | 按钮/卡片/空态 |
| `AppBreakpoints.isCompact` | core | 移动/桌面断点 |
| `setViewport` | `test/helpers/responsive_test_helper.dart` | 统一 Widget Test viewport helper |
| `docs/ui/ui-acceptance-checklist.md` | 已存在 | UI 验收清单 |

---

## 2. Problem Statement

1. **复杂业务流程被塞进 Dialog/Sheet**。典型案例已实锤：资料库"新建资源" = `showResourceCreationChoices`（BottomSheet 选 AI/手动）→ `showAiResourceDialog`（AlertDialog：类型 DropdownButtonFormField + 名称输入 + SegmentedButton 粘贴/文件/已有资源 + 文件内容多行输入 + 已有资源 Dropdown，`lib/features/resource_library/presentation/widgets/resource_creation_flow.dart:170-352`）。这是完整表单页的复杂度，运行在 AlertDialog 内。
2. **API 配置在启动时以 Dialog 弹出**。`MainGate` 初始化失败/未配置 key 时自动 `showApiSettings(context)`（`lib/main.dart:224,240`），全仓约 15 处调用入口。该 Dialog 含 provider 选择、key 输入、模型配置、连接测试，是全项目最重的弹窗。
3. **自定义 Overlay 下拉与 Modal 冲突风险**。`AppDropdown` 用 `OverlayEntry` 自绘浮层（`app_dropdown.dart:427,483,867,912`），与 Dialog/BottomSheet 的 Overlay 层级、键盘避让、`320 px` 小屏滚动存在固有冲突。
4. **顶层导航非路由驱动**。section 切换由 `ChatProvider.currentSection` 状态决定，导致 Android 返回键行为依赖 Provider 状态回退逻辑、deep link 仅覆盖 2 条路由、页面生命周期与 Provider 生命周期耦合。
5. **遗留 `lib/screens/` 与 `lib/features/` 双轨并存**，弹窗最密集的 chat 模块（`chat_dialogs.dart` 6 个 sheet、`character_sheet.dart` 2449 行）位于遗留目录且被 features 反向引用。
6. **弹窗返回值驱动业务**：大量 `await showDialog<T>` 以 record/自定义类型返回草稿（如 `ResourceStudioCreationDraft`），状态在 Dialog State 内临时保存，难以测试与恢复。

---

## 3. Current UI Inventory

统计口径：`grep` 于 `lib/`（HEAD `b4d02f1`）。

| 类型 | 数量 | 位置（主要） | 风险 |
|---|---|---|---|
| `showDialog` 调用 | 30 | resource_studio_page(6)、resource_creation_flow(2)、app_dialogs(1+11 个入口函数)、preset_scenes(2)、scene_batch_import(2)、chat/message_bubble(2)、character_sheet(2)、session_app_bar(1)、resource_trash_sheet(1)、assembly_readiness(2)、section_controls(2)、data_management(2)、worldview/character tabs(3)、worldview_ai_import(1)、resource_card_ai_import(1)、character_card_edit(1)、main_sidebar(2)、dashboard_recent_saves(1) | 高 |
| `AlertDialog` 构建 | 约 40 处 | 同上 + `_ManagementDialog`(main_sidebar:1192) | 高 |
| `showModalBottomSheet` | 16 | chat_dialogs(6)、prompt_settings(2)+preview(1)、session_app_bar(1)、character_sheet(1)、chat/character_sheet(1)、resource_creation_flow(1)、resource_trash_sheet(1)、data_management(1)、app_dialogs(2) | 高 |
| `PopupMenuButton` | 5 | section_controls、preset_scenes:793、session_app_bar:315、quick_menu、status_dropdown | 中 |
| `DropdownButtonFormField` | 5 | resource_studio_page:757、resource_creation_flow:116,206,300 | 中 |
| 自定义 `OverlayEntry` 浮层 | 2 类组件 | `AppDropdown`、`AppMultiSelectDropdown`（app_dropdown.dart） | 高 |
| 自定义 Modal Wrapper | 1 | `PromptPreviewModal`（prompt_preview_modal.dart） | 中 |

### 3.1 明细清单（按模块）

#### A. 集中式遗留弹窗 `lib/widgets/app_dialogs.dart`（1328 行）

| 入口函数 | 行号 | 用途 | 输入 | 列表 | 状态管理 | 依赖 Provider | 分类 | 推荐目标 |
|---|---|---|---|---|---|---|---|---|
| `showApiSettings` | :21 | LLM Provider/Key/模型/连接测试完整配置 | 有（表单） | 有（provider/model 选择） | Dialog 内 StatefulWidget | ChatProvider/SettingsProvider | **A** | `ApiSettingsPage`（挂入 SettingsCenterScreen） |
| `showFontSizeDialog` | :182 | 字号滑杆 | 滑杆 | 无 | Dialog 局部 | SettingsProvider | B | 保留或并入设置页 |
| `showExportDialog` | :262 | 数据导出：Tab + 范围 + 格式 | 有 | 有 | Dialog 局部 | ChatProvider/各仓库 | **A** | `ExportPage` |
| `showImportDialog` | :402 | 数据导入：粘贴/文件 + 写库 | 有（多行） | 有 | Dialog 局部 | 各仓库 | **A** | `ImportPage` |
| `showCompletionParamsDialog` | :620 | temperature 等 3 滑杆 | 滑杆 | 无 | Dialog 局部 | SettingsProvider | B | 保留或并入模型设置页 |
| `showSaveWorldviewDialog` | :726 | 保存世界观命名 | 单输入 | 无 | Dialog 局部 | ChatProvider | B | 保留（单字段）或并入创建页 |
| `showTokenDashboard` | :795 | Token 统计只读面板 | 无 | 有 | Dialog 局部 | ChatProvider | B | 只读可保留；建议并入设置页 |
| `showThemeDialog` | :871 | 主题色 chips | 点选 | 无 | Dialog 局部 | SettingsProvider | B | 保留或并入设置页 |
| `showCreateCharacterCardDialog` | :924 | 角色卡创建表单 | 有 | 无 | Dialog 局部 | ChatProvider | **A** | 复用/并入 `CharacterCardEditPage`（已存在 Page 化编辑） |
| `showImportCharacterCardDialog` | :944 | 角色卡文件导入 | 有 | 无 | Dialog 局部 | ChatProvider | **A** | `ImportPage` / 导入子页 |
| `showCreateConversationCharacterCardDialog` | :1038 | 会话中新建角色卡 | 有 | 无 | Dialog 局部 | ChatProvider | **A** | 同上 |

`showApiSettings` 调用入口：`main.dart:224,240,363,393`、`adventure_wizard_screen.dart:720 区域 ×4`、`adventure_dashboard_screen.dart:133,150`、`dashboard_hero_header.dart:107,144,160`、`preset_scenes_screen.dart:137`、`character_card_edit_page.dart:280`。

#### B. 资料库 / 资源工作室（features，R02-A 主战场）

| 当前 | 位置 | 用途 | 分类 | 推荐目标 |
|---|---|---|---|---|
| `showResourceCreationChoices`（BottomSheet） | resource_creation_flow.dart:13 | 新建资源入口选择 | **A**（流程入口） | 页面内导航或轻 sheet 保留为入口分发 |
| `showManualResourceDialog`（AlertDialog） | resource_creation_flow.dart:68 | 手动创建：类型下拉+名称+简介 | **A** | `ManualResourceCreatePage` |
| `showAiResourceDialog`（AlertDialog） | resource_creation_flow.dart:78 | AI 创建：类型+名称+参考资料三选一+多行输入 | **A**（典型案例） | `AiResourceCreatePage` |
| `_ResourceCreationDialog`（AlertDialog） | resource_studio_page.dart:724 | Studio 内创建资源（同构表单） | **A** | 复用上述创建页 |
| `_SectionTitleDialog`（AlertDialog） | resource_studio_page.dart:806 | 新增章节命名 | B | 保留（单输入） |
| 删除/放弃确认 ×3 | resource_studio_page.dart:378,415,473 | 删除资源/章节/版本确认 | B | 统一 `AppConfirmDialog` |
| 章节重命名 + 确认 + PopupMenu | resource_studio_section_controls.dart:306,313,252 | 重命名/排序/删除 | B（菜单本身 C 审查） | 保留菜单；确认走统一组件 |
| `ResourceTrashSheet`（BottomSheet） | resource_trash_sheet.dart:226 | 回收站列表+恢复/彻底删除 | **A** | `ResourceTrashPage` |
| 类型 Dropdown ×3 | resource_creation_flow.dart:116,206,300 | 类型/已有资源选择 | C | `LtSelect<T>` 重构 |

#### C. Adventure（wizard / session / templates / home）

| 当前 | 位置 | 用途 | 分类 | 推荐目标 |
|---|---|---|---|---|
| `showAssemblyReadinessBlockDialog` | assembly_readiness_dialogs.dart:15 | 就绪阻断只读提示 | B | 保留 |
| `showStaleAssemblyChoiceDialog` | assembly_readiness_dialogs.dart:50 | 过期组装继续/重算选择 | B | 保留 |
| 模型选择 BottomSheet | session_app_bar.dart:127 | 模型列表选择 | **A**（列表选择页复杂度） | `ModelSelectPage` 或统一 `LtSelect` picker |
| 删除会话确认 | session_app_bar.dart:215 | 轻确认 | B | 统一组件 |
| 删除确认 + 内容查看 dialog | preset_scenes_screen.dart:184,536 | 预设场景确认/查看 | B | 保留确认；查看改页或保留 |
| PopupMenuButton | preset_scenes_screen.dart:793 | 场景操作菜单 | B | 保留 |
| 删除存档确认 | dashboard_recent_saves.dart:218 | 轻确认 | B | 统一组件 |

#### D. 遗留 chat 模块（`lib/screens/chat/`，被 features 引用）

| 当前 | 位置 | 用途 | 分类 | 推荐目标 |
|---|---|---|---|---|
| `showEditDialog`（BottomSheet） | chat_dialogs.dart:86 | 编辑消息多行文本 | **A** | 内联编辑或 `EditMessagePage` |
| `showRegenerateWithModelMenu` | chat_dialogs.dart:160 | 模型列表选择 sheet | **A** | 与模型选择页合并 |
| `showMessageMenu` | chat_dialogs.dart:223 | 消息操作菜单 | B | 保留（轻菜单） |
| `showRetryMenu` | chat_dialogs.dart:310 | 重试选项菜单 | B | 保留 |
| `showModelSwitchMenu` | chat_dialogs.dart:370 | 模型切换 sheet | **A** | `ModelSelectPage` |
| `showInventorySheet` | chat_dialogs.dart:475 | 物品栏列表 sheet | **A** | 已有 `inventory_screen.dart`（Page），统一到 Page |
| 消息删除/重roll确认 ×2 | message_bubble.dart:402,522 | 轻确认 | B | 统一组件 |
| `showCharacterSheet` | character_sheet.dart:19 | **已 Page 化**（push `CharacterStatusScreen`） | — | 保持 |
| 角色状态内编辑 sheet | character_sheet.dart:376 | 属性分配编辑 | C | 随 R02-C 重审 |
| `showDialog` 确认 ×2 | character_sheet.dart:221,832 | 确认/升级确认 | B | 统一组件 |
| `showMenu`/状态 dropdown | status_dropdown.dart、quick_menu.dart | PopupMenuButton | B | 保留 |

#### E. 设置 / 提示词 / 侧栏

| 当前 | 位置 | 用途 | 分类 | 推荐目标 |
|---|---|---|---|---|
| 导入确认（移动 sheet/桌面 dialog 分支） | data_management_section.dart:314,326 | 覆盖导入确认 | B | 统一组件 |
| 诊断导出确认 | data_management_section.dart:383 + `_DiagnosticExportPrompt` | 轻确认 | B | 统一组件 |
| Preset 导入 sheet（文本输入） | prompt_settings_screen.dart:56 | JSON 粘贴 | **A** | 并入 PromptSettings 页内区块或子页 |
| Preset 导出 sheet（JSON 展示） | prompt_settings_screen.dart:147 | 长文本输出 | **A** | `PromptExportPage` 或页内区块 |
| `PromptPreviewModal`（sheet） | prompt_preview_modal.dart:18 | 长提示词预览 | **A** | `PromptPreviewPage` |
| 会话管理 `_ManagementDialog` | main_sidebar.dart:1192 | 会话列表管理（AlertDialog 内列表+输入） | **A** | `ConversationManagePage` |
| 删除确认 + 查看对话 | main_sidebar.dart:79,118 | 轻确认/内容查看 | B | 统一组件 |

---

## 4. Migration Matrix

> 优先级：P0 = R02-A 首批；P1 = 随所属 Phase；"风险"指迁移对既有行为/测试的破坏面。

| 当前 Dialog/Sheet | 目标 Page | 优先级 | 风险 |
|---|---|---|---|
| `showAiResourceDialog`（resource_creation_flow） | `AiResourceCreatePage` | P0 | MAJOR：入口在 library screen:223，草稿返回值改路由 result |
| `showManualResourceDialog` | `ManualResourceCreatePage` | P0 | MAJOR：同上 |
| `showResourceCreationChoices` | 创建入口（页内分发或轻 sheet） | P0 | MINOR |
| `_ResourceCreationDialog`（resource_studio_page:724） | 复用上述创建页 | P0 | MAJOR：studio 创建链路 `createAndStart` |
| `showApiSettings`（app_dialogs:21） | `ApiSettingsPage`（SettingsCenter 挂载；启动引导改 push） | P0 | **BLOCKER**：15 处调用点 + 启动自动弹窗 + 连接测试流程 |
| `ResourceTrashSheet` | `ResourceTrashPage` | P0 | MAJOR：删除/恢复语义 |
| `showImportCharacterCardDialog` / `showCreateCharacterCardDialog` | 导入子页 / 复用 `CharacterCardEditPage` | P1 | MAJOR：wizard 依赖其草稿返回 |
| `showExportDialog` / `showImportDialog` | `ExportPage` / `ImportPage` | P1 | MAJOR：数据导入写库路径不可回归 |
| `_ManagementDialog`（main_sidebar） | `ConversationManagePage` | P1 | MAJOR：sidebar 状态联动 |
| `showModelSwitchMenu` / `showRegenerateWithModelMenu` / session_app_bar 模型 sheet | `ModelSelectPage`（单一目标） | P1 | MAJOR：chat 与 session 双入口收敛 |
| `showInventorySheet` | 复用已有 `InventoryScreen` | P1 | MINOR |
| `showEditDialog`（消息编辑） | 内联编辑或 `EditMessagePage` | P1 | MAJOR：消息更新链路 |
| `PromptPreviewModal` | `PromptPreviewPage` | P1 | MINOR |
| Preset 导入/导出 sheets | PromptSettings 页内区块/子页 | P1 | MINOR |
| `AppDropdown` Overlay 浮层 | `LtSelect<T>`（移动端 sheet 弹出 / 桌面 anchored menu） | P0（组件先于页面） | **BLOCKER**：全部 5+ DropdownButtonFormField 调用点 + AppDropdown 现有调用面 |
| 全部 `showDialog<bool>` 删除/覆盖确认（约 18 处） | 统一 `AppConfirmDialog`（保留 Dialog 形态） | 随各 Phase | MINOR：仅视觉/行为归一 |
| `showFontSizeDialog` / `showCompletionParamsDialog` / `showThemeDialog` / `showSaveWorldviewDialog` / `_SectionTitleDialog` | 保留（轻量单控件）或并入设置页 | P2 | MINOR |
| `showAssemblyReadinessBlockDialog` / `showStaleAssemblyChoiceDialog` | 保留 | P2 | MINOR |

---

## 5. Target Architecture

### 5.1 Navigation

- **新增子页面一律走 `AppRouter`**（`AppRouter.push` / `pageRoute`），保持统一过渡动画与 `disableAnimations` 尊重；新路由注册进 `onGenerateRoute` 以获得 deep-link 能力（如 `/settings/api`、`/library/create`）。
- **顶层 section 切换暂不迁移**：`ChatProvider.currentSection` 状态驱动是全局架构级改动，R02 仅约束"新增层级必须路由化"，把 section→Navigator 的整体切换列为 R02 后置项（见风险 9-MAJOR-3），避免本轮范围爆炸。
- **Dialog 准入铁律**：仅允许（a）无输入的是/否确认；（b）单字段轻输入（命名类）；（c）只读短提示。含列表选择、多字段、文件/资源引用、长文本的一律 Page。
- **返回值协议**：Page 化后用 `Navigator.pop(context, draft)` 路由返回值替代 Dialog 返回值，草稿类型（`ManualResourceDraft`、`ResourceStudioCreationDraft`、`CharacterCardEditDraft`）保持不变，迁移期间调用方 API 面最小化。

### 5.2 Component（复用优先，扩展现有，不新造平行体系）

- **Page Shell**：**扩展 `FormSubPageScaffold`**（已有键盘避让/SafeArea/返回行为），按需增设 `floatingActionButton`、`resizeToAvoidBottomInset` 可调、桌面双栏可选；命名维持现有类名，不引入第二个 scaffold。
- **Form**：新增 `LtFormSection`（Section 标题 + 描述 + 子项 + 错误插槽），配合现有 `AppTextField`；校验收敛到每个创建/编辑 Page 内的 `FormState` + validator。
- **输入**：`AppTextField` 已覆盖明暗主题与 M3 token；按需补 `errorText` 语义与 `textInputAction` 约定，不新建 `LtTextField`。
- **Select**：**重构 `AppDropdown` 为 `LtSelect<T>` 内核**：移动端改用 BottomSheet picker（复用统一 sheet 壳），桌面保留 anchored 菜单；`AppMultiSelectDropdown` 同步；替换 5 处 `DropdownButtonFormField` 与 AppDropdown 全部调用点；预留搜索扩展位。
- **Button**：复用 `AppActionButton`，补充 primary/secondary/danger 语义枚举，不新建三个组件类。
- **状态页**：复用 `AppEmptyState`；新增统一 `AppLoadingView` 与 `AppErrorView`（错误信息 + Retry 回调），放置于 `lib/core/widgets/`。

### 5.3 State

- 新 Page 使用所属 feature 的 Riverpod controller（resource_library/resource_studio 已有 `presentation/controllers` + `application/use_cases` 分层）。
- 遗留模块（chat、app_dialogs 调用方）迁移时保持读写 `ChatProvider` 现状，不借机重写 Provider。
- 页面状态（表单草稿）放 Page State，业务状态放 Provider；禁止 Page 内复制 Provider 已有状态（AGENTS.md SSOT 原则）。

### 5.4 Responsive

- 所有新 Page 必须过 `320 px` 最低宽度；创建类表单页直接复用 `FormSubPageScaffold` 的 maxWidth 840 居中约束。
- `LtSelect` 移动端 sheet 化后天然规避小屏下拉溢出与键盘遮挡；表单页键盘避让沿用 `resizeToAvoidBottomInset` + bottomBar inset 补偿。
- 验证矩阵与 helper：`test/helpers/responsive_test_helper.dart` 的 `setViewport`。

---

## 6. Shared Component Plan

| 组件 | 形态 | 基础 | 变更性质 |
|---|---|---|---|
| Page Shell | `FormSubPageScaffold`（扩展：FAB 槽位、标题/动作约定、可选滚动容器） | `lib/core/widgets/form_sub_page_scaffold.dart` | 扩展现有 |
| `LtFormSection` | 新组件（Section/Label/Error/Validation 布局） | `lib/core/widgets/lt_form_section.dart` | 新增（无等价实现） |
| `LtSelect<T>` | `AppDropdown` 重构内核 + 移动 sheet picker | `lib/core/widgets/app_dropdown.dart` | 重构现有 |
| `AppTextField` 增强 | errorText/textInputAction 约定 | `lib/core/widgets/app_text_field.dart` | 扩展现有 |
| 按钮语义 | `AppActionButton` 增 `AppButtonVariant.{primary,secondary,danger}` | `lib/core/widgets/app_action_button.dart` | 扩展现有 |
| `AppConfirmDialog` | 统一确认弹窗（title/body/confirmText/destructive） | `lib/core/widgets/` | 新增（收编约 18 处裸 AlertDialog） |
| `AppLoadingView` / `AppErrorView` | 统一加载/错误+重试 | `AppEmptyState` 同目录 | 新增 |

> 命名说明：任务书中的 `LtPageScaffold/LtTextField/LtButton` 分别由**扩展 `FormSubPageScaffold`、`AppTextField`、`AppActionButton`** 承担，避免违反 AGENTS.md"先复用后新增、不建重复实现"。

---

## 7. Migration Order

### R02-A 资料库模块（P0，首批）
1. 先建共享组件：`LtSelect`（重构 AppDropdown）、`AppConfirmDialog`、`LtFormSection`、Loading/Error 视图。
2. `showAiResourceDialog` → `AiResourceCreatePage`；`showManualResourceDialog` → `ManualResourceCreatePage`；`_ResourceCreationDialog`（studio）收敛到同一创建页。
3. `ResourceTrashSheet` → `ResourceTrashPage`。
4. library/studio 内 5 处 `DropdownButtonFormField` → `LtSelect`；本模块确认弹窗收编 `AppConfirmDialog`。
5. 回归：resource_library + resource_studio 全部既有测试 + 新增 320/390/412 viewport widget test。

### R02-B 组装模块（wizard）
1. `showCreateCharacterCardDialog` / `showImportCharacterCardDialog` → Page（复用 `CharacterCardEditPage`）。
2. `showStaleAssemblyChoiceDialog` / readiness 阻断提示保留（B 类），换皮 `AppConfirmDialog`。
3. wizard 内 4 处 `showApiSettings` 调用点改跳转 `ApiSettingsPage`。

### R02-C 对话/场景模块（最大遗留面）
1. 模型选择三入口（session_app_bar sheet、`showModelSwitchMenu`、`showRegenerateWithModelMenu`）→ 单一 `ModelSelectPage`。
2. `showInventorySheet` → 复用 `InventoryScreen`；`showEditDialog` → 内联编辑或 Page。
3. `character_sheet.dart` 内 sheet/确认按 B/C 类逐项处理；`chat_dialogs.dart` 菜单类保留。
4. 逐步把 `screens/chat/widgets` 被 features 引用的部分向 `features/adventure/presentation/session/` 内迁（仅移动文件与 import，不改行为；超出部分只记录不动手）。

### R02-D 设置模块
1. `showApiSettings` → `ApiSettingsPage`（SettingsCenter 挂载；启动引导 `main.dart:224,240` 改为 push 页面）。
2. `showExportDialog`/`showImportDialog` → `ExportPage`/`ImportPage`；`data_management_section` 确认收编。
3. `PromptPreviewModal` → Page；preset 导入/导出 sheet → 页内区块。
4. 字号/参数/主题/Token 面板按 B 类评估并入设置页或保留。

### R02-E 其他模块
1. `_ManagementDialog` → `ConversationManagePage`（sidebar 联动）。
2. `showSaveWorldviewDialog`、`_SectionTitleDialog` 等 B 类收尾。
3. 全项目 `rg "showDialog|AlertDialog|showModalBottomSheet"` 复查，产出清理后残留清单与豁免理由。

依赖关系：R02-A 第 1 步（共享组件）是所有后续 Phase 的前置；R02-D 的 `ApiSettingsPage` 需先于 R02-B 的调用点切换；R02-C 依赖 `LtSelect`（模型选择）。

---

## 8. Testing Strategy

### Widget Test（每批迁移必备）
- 统一使用 `test/helpers/responsive_test_helper.dart` `setViewport`，覆盖 `320×568`、`360×640`、`390×844`、`412×915`；公共组件（`LtSelect`、`AppConfirmDialog`、`LtFormSection`）加 `768×1024`。
- 硬门槛：`tester.takeException() == null`、无 RenderFlex overflow；主要操作存在且可点击；长文本用例（超长资源名/模型名/错误信息）；至少一组 `textScaleFactor` 放大用例。
- `LtSelect` 专项：展开/收起、禁用态、长文本、键盘弹出下 sheet 不遮挡输入、选项滚动可达。
- 表单页专项：键盘弹出时提交按钮可达（`viewInsets`）、返回键放弃编辑的确认行为、路由返回值正确。

### Integration Test（R02-A 与 R02-D 各一批）
- 创建资源全链路：入口 → 创建页 → 提交 → 列表刷新（复用 `test/helpers/resource_studio_fakes.dart`、`resource_capacity_fakes.dart` 既有 fake 体系，不 mock 数据库）。
- API 设置链路：未配置 key 启动 → 引导进入 `ApiSettingsPage` → 保存 → 主流程放行。

### Device / Platform Test
- 移动端（模拟 320-412 宽 + 键盘展开 + 横竖屏 + 系统返回键）：无法起模拟器时以 Widget Test viewport 模拟为准，并在验收报告注明。
- 桌面（Linux/Windows）：`AppRouter` Fade 过渡、`LtSelect` anchored 形态、鼠标交互、`MainSidebar` 与新 Page 的联动。
- 主题：Dark/Light 双跑组件 golden 或双主题 widget test；`AppConfirmDialog` destructive 样式两主题核对。
- 回归底线：`dart format .`、`flutter analyze`、`flutter test` 全绿；R02 期间全量测试每 Phase 至少跑一次（当前基线 1738 通过）。

---

## 9. Risk Assessment

| 级别 | 编号 | 描述 | 缓解 |
|---|---|---|---|
| BLOCKER | R-B1 | `showApiSettings` 有 15 处调用点且启动时自动弹出（`main.dart:224,240`）；迁移触碰冷启动引导与连接测试关键路径 | 放 R02-D 单独一批；先建 `ApiSettingsPage` 并保持 `showApiSettings` 为兼容薄壳（内部 push），逐调用点切换后再删壳 |
| BLOCKER | R-B2 | `AppDropdown` Overlay 浮层重构影响全部现网调用点，行为回归面大 | `LtSelect` 先做成 `AppDropdown` 同签名替换，移动端 sheet 行为加 feature flag 式分步启用；专项 widget test 覆盖全部现有调用形态 |
| MAJOR | R-M1 | 弹窗返回值（`ManualResourceDraft`、`ResourceStudioCreationDraft`、`CharacterCardEditDraft`）是 wizard/library 的业务契约，改路由返回值易破坏调用方 | 保留草稿类型不变，仅替换展示载体；每处迁移配套调用方测试 |
| MAJOR | R-M2 | 数据导入/导出/删除（`showImportDialog`、`ExportPage`、回收站）涉及用户数据写库，回归代价高 | R02-D 迁移时保留原 Service 调用链不动，仅换 UI 壳；导入确认语义（覆盖 vs 合并）逐字保留 |
| MAJOR | R-M3 | 顶层 `ChatProvider.currentSection` 状态驱动导航与路由体系并存，长期双轨 | 本轮明确"新增层级路由化、顶层不迁移"；将顶层迁移列为独立后续提案，不在 R02 范围内偷跑 |
| MAJOR | R-M4 | 遗留 `lib/screens/chat/`（`character_sheet.dart` 2449 行）被 features 反向引用，R02-C 迁移可能牵连 session 稳定 | R02-C 只做 UI 载体迁移与文件归位，不改业务逻辑；每步定向测试 session 相关套件 |
| MINOR | R-N1 | 约 18 处裸 `AlertDialog` 确认换 `AppConfirmDialog` 属视觉归一，可能影响既有 widget test 的 finder | 提供 `Key` 约定；测试按 finder 迁移指南批量更新 |
| MINOR | R-N2 | PopupMenuButton/轻 sheet（消息菜单、重试菜单）保留后与 `LtSelect` sheet 形态风格不一致 | 统一 sheet 壳样式 token；不改交互结构 |
| MINOR | R-N3 | `showSceneImportDetailModePicker` 等选择器在 wizard 深链中，Page 化会增加返回栈复杂度 | 保留 B 类 Dialog 形态（无复杂输入），仅在风格上归一 |
| INFO | R-I1 | `FormSubPageScaffold` 的 bottomBar 键盘补偿采用 `AnimatedPadding` 手动处理，与 `resizeToAvoidBottomInset` 叠加，扩展时需验证横屏与手势导航 | 扩展该组件时补 320px 键盘 widget test |
| INFO | R-I2 | 文档命名 `LtXxx` 与现有 `AppXxx` 前缀不一致 | 本计划已统一为"扩展 AppXxx + 必要时新增 LtFormSection/LtSelect"，避免双前缀体系 |

---

## 执行边界重申

本计划为 R02 规划阶段唯一交付物。未修改任何 `lib/` 源码、测试、配置、依赖或数据库；未实现任何 R02 条目。所有文件路径、行号、调用点均来自 HEAD `b4d02f1` 实际代码检索。
