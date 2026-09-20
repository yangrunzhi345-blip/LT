# R02 Unified Actions and Generation Navigation

> 本文档记录 R02 导航优先重构后续修复轮：预存场景操作菜单收敛到统一 Action Menu 组件，
> 以及 AI 创建资源进入生成工作台的根因修复。
> 基线与提交见文末。

---

## 1. 问题一：预存场景操作菜单为什么没有复用统一组件

### 审计结论

- 真实实现位置：`lib/features/adventure/presentation/templates/screens/preset_scenes_screen.dart`
  的 `_PresetSceneCard` 直接构造 `PopupMenuButton<String>`（完整设定预览 / 载入向导微调 /
  删除预存场景）。
- 该菜单不是 R02-B 页面化迁移时遗漏的业务流程，而是被 R02 验收阶段**显式保留**为
  "lightweight context action menu"：见 `docs/ui-refactor/r02-final-navigation-first-acceptance.md`
  第 8 节 Remaining Allowed Modal Inventory，其中 `preset_scenes_screen.dart` 一行的准入理由是
  "lightweight `PopupMenuButton`; preview pushes a page"。
- 根本原因不是遗漏，而是当时缺少"操作菜单"维度的公共组件：R02-A 只统一了 **表单选择**
  (`AppSelect<T>` / `LtSelect<T>`)，没有统一的 **动作菜单**。`AppSelect` 的语义是"选中一个值并回填"，
  带有 selected 勾选、validator、selectedBuilder 等表单语义，强行当 Action Menu 用会引入
  无意义的选中态。因此各 feature 只能自建 `PopupMenuButton`。

### 禁止新增第二套组件

本轮没有把 `AppSelect` 当 Action Menu 复用，也没有让 feature 继续自建菜单，而是：
扩展 UI Foundation，新增统一的 **`AppActionMenu<T>`**，并把两个控件共用的响应式放置策略
与锚定几何抽到公共基础层，避免复制 `AppSelect` 内部逻辑。

---

## 2. 最终统一组件

### 2.1 新增公共组件

| 组件 | 文件 | 职责 |
| --- | --- | --- |
| `AppActionMenu<T>` | `lib/core/widgets/app_action_menu.dart` | 统一三点菜单 / 卡片操作菜单 / 上下文操作菜单 |
| `AppActionMenuItem<T>` | 同上 | 单条动作：`value` / `label` / `icon` / `subtitle` / `enabled` / `destructive` / `dividerBefore` |

能力覆盖：icon、label、value、disabled、destructive、divider/group、selected 回调
（`onSelected`）、mobile/desktop、dark/light 主题。删除类动作通过 `destructive: true`
渲染为主题 `colorScheme.error`。

### 2.2 抽取/复用共同基础能力（不复制 AppSelect 内部逻辑）

| 公共基础 | 文件 | 说明 |
| --- | --- | --- |
| `AppSelectPickerStyle` | `lib/core/widgets/app_picker.dart` | 响应式放置策略枚举，从 `app_select.dart` 迁出，`AppSelect` 只做 `export`，外部 API 不变 |
| `appPickerUsesBottomSheet` | 同上 | `< 600px → BottomSheet`，`>= 600px → 锚定菜单`，两个控件共用同一条判定 |
| `appPickerAnchor` / `AppPickerAnchor` | 同上 | overlay 相对坐标锚定几何，两个控件共用 |

`AppSelect._openPicker` / `_openMenuOrBottomSheet` 已改为调用上述公共函数，
`AppActionMenu` 复用同一套策略与几何，因此二者不会各自漂移。两个控件都从
`lib/core/widgets/ui_foundation.dart` 统一导出。

### 2.3 移动端与桌面端行为

沿用与 `AppSelect` 完全一致的 responsive policy：

- Mobile（`< 600px`）：触控友好的 BottomSheet（标题栏 + 关闭按钮 + `ListTile` 动作列表，
  `maxHeight = min(menuMaxHeight, 70% 屏高)`）。
- Desktop（`>= 600px`）：锚定到当前操作按钮的弹出菜单；触发按钮或 overlay 尚未布局时
  自动回退 BottomSheet。

### 2.4 预存场景迁移结果

`preset_scenes_screen.dart` 的 `PopupMenuButton<String>` 已删除，改为：

```
完整设定预览
载入向导微调        （无 preset 时 disabled）
────────
删除预存场景        （destructive，主题 error color）
```

---

## 3. 问题二：AI 创建后没有进入生成工作台的根因

### 3.1 先排除："导航"并没有断

按任务要求先审计真实生成链并对照历史：

- 生产入口 `ResourceLibraryScreen._startCreation`
  → `ResourceCreatePage`
  → `ResourceAiCreatePage`
  → 返回 `ResourceStudioCreationDraft`
  → `ResourceStudioPage(creationDraft:)`
  → `ResourceStudioController.createAndStart`。
- `git show 45fa869 -- resource_library_screen.dart` 证明 R02-B 之前（Dialog 版本）同样是
  `draft → ResourceStudioPage(creationDraft:)`，R02-B 页面化只是换了载体，导航目标不变。
- 现有生产测试 `test/widget/resource_library_production_test.dart`
  （真实 Provider / Controller / Repository / SQLite）端到端通过。

结论：**"没有进入工作台"不是导航丢失**，`ResourceStudioPage` 确实被 push。

### 3.2 真实根因

`ResourceStudioPage._buildBody` 的判定顺序是：

```dart
if (state.status == loading || initial) return CircularProgressIndicator();
if (state.tree == null) return _buildSessionPicker(context, state);   // ← 问题所在
```

创建草稿的流程是 `_load()` 先 `_controller.load()`（此时无 resource/session → `tree == null`），
再 `await _controller.createAndStart(...)`。而 `createAndStart` 内部要顺序完成
资源落库 → Blueprint 规划（LLM 调用）→ 确认蓝图 → 建 streaming session → start，
期间 `state.tree` 始终为 `null`。于是**在整段真实创建/规划期间，用户看到的是
"选择资源或生成会话" 的 session picker（含"创建并开始生成"按钮），而不是生成态界面**。
这看起来就像"点了开始创建却没有进入生成界面"。此外该 picker 允许再次点"创建并开始生成"，
有误触发第二套创建入口的风险。

同类次生缺陷：`_StatusBar` 在 `session.totalPartsCount == 0` 时对 0 取模
（`completed / total * 100`）会得到 NaN 并 `.round()` 抛错；创建初期/空会话存在该路径。

---

## 4. 修复后的调用链

保持"Studio runtime 是唯一创建权威"的现有架构（不新建重复 Generation State，
不引入假工作台页面），只修正渲染状态：

```
ResourceLibraryScreen
  → ResourceCreatePage
  → ResourceAiCreatePage（提交时 _submitting 防重复；按钮 isLoading/disabled）
  → ResourceStudioCreationDraft
  → ResourceStudioPage(creationDraft:)
        initState: _creating = true
        _load(): load() → _beginCreation(draft)
        _beginCreation(): _creationInFlight 防重入
            → ResourceStudioController.createAndStart(...)   // 现有生产入口
            → 成功：tree != null → 真实生成态（Streaming / Patch / Validation / Retry / Cancel）
            → 失败：tree == null && errorMessage != null → _buildCreationFailure（重试创建，留在 Studio）
        创建期间：tree == null && _creating → _buildCreationInProgress（真实创建态，非 picker）
```

新增页面状态：

- `_buildCreationInProgress`：创建/规划进行中的真实状态，展示资源类型、名称与目标字数，
  不是只有转圈的假页面，创建成功后立即被真实生成视图替换。
- `_buildCreationFailure`：创建失败态，显示错误与"重试创建"，**不返回资料库**。
- `_creationInFlight`：创建命令重入保护；`ResourceAiCreatePage._submitting`：提交防重复。

`_showCreateDialog`（Studio 内创建入口）同样改走 `_beginCreation`，两条入口状态一致。

---

## 5. Worldview / Character / NPC 是否统一

统一。三者共用同一条
`ResourceAiCreatePage → ResourceStudioCreationDraft → ResourceStudioPage._beginCreation
→ ResourceStudioController.createAndStart` 流程，没有任何 `if (type == worldview)`
式分支。新增生产测试对 `ResourceType.values` 全类型逐一验证：
点击"开始创建"后创建 generation task 并进入 `ResourceStudioPage`。

---

## 6. Resource Studio 复用情况

复用了现有生产页面 `lib/features/resource_studio/presentation/pages/resource_studio_page.dart`
（AppBar 标题"创作工作台"）。它已经接入真实
`ResourceStudioRuntime` / `ResourceStudioController` / streaming controller / section controls /
capacity / revision 等能力，因此：

- 没有新增假的生成工作台；
- 没有新建第二套 Generation State；
- 生成过程仍由现有 Streaming、Incremental Part Patches、Validation、Retry、Cancel、
  Recovery、Autosave 处理。

传入的 identifier 沿用当前生产架构实际需要的载体：`ResourceStudioCreationDraft`
（类型、名称、参考资料、目标字数）。创建完成后 Studio 内部持有真实
`resourceId` / `sessionId` 并驱动后续生成。

---

## 7. targetCharacters 传递情况

贯通，未丢失：

```
ResourceAiCreatePage State (_targetCharacters, 默认 = ResourceLimits.policyFor(type).nominalCharacters)
  → ResourceStudioCreationDraft.targetCharacters
  → ResourceStudioPage._beginCreation
  → ResourceStudioController.createAndStart
  → ResourceStudioRuntime.createAndStart
  → ResourceCreationPipeline ResourceCreationRequest.targetCharacters
  → resource_creation_sessions.target_characters
  → Blueprint Planner / Prompt / Validator
```

新增测试在提交前读取 UI 上的 `ai-create-target-value`，提交后断言
`resource_creation_sessions.target_characters` 等于该 UI 值，从而证明是"UI 值"而非
"类型默认值"进入链路。

---

## 8. 测试结果

新增测试：

- `test/widget/preset_scenes_action_menu_test.dart`（8 个）
  - 三点按钮打开统一 Action Menu；完整设定预览可达；载入向导微调可达；
  - 删除走统一确认 + 现有删除链；destructive 使用主题 error color；
  - 320px 为 BottomSheet 且无 overflow；`requiredUiViewports` 全量可用；
  - 源码级断言：`preset_scenes_screen.dart` 不含 `PopupMenuButton` / `showMenu` / `OverlayEntry`。
- `test/widget/resource_ai_create_studio_navigation_test.dart`（8 个）
  - worldview / character / npc 全类型：AI 创建 → 创建 task → 进入 `ResourceStudioPage`；
  - targetCharacters 从 UI 贯通到 `resource_creation_sessions`；
  - 创建进行中显示创建态而非 session picker；
  - 创建失败留在 Studio 显示失败态 + 重试，不弹回资料库；
  - 双击"开始创建"只产生 1 个 resource + 1 个 session；
  - Studio 返回后资料库刷新并显示新资源；320px 创建后 Studio 可用。

顺带修复的既有 320px 缺陷（同页面，属 UI Definition of Done 要求）：

- AppBar 标题 Row 在 320px 被挤压溢出 → 标题 `Flexible` + ellipsis，compact 下操作区改用图标按钮。
- `_PresetSceneCard` 在单列 `ListView` 中 `Expanded` 遇到无界高度断言 → 单列卡片给定与网格
  一致的 `mainAxisExtent` 高度。
- 卡片底部时间戳动态长文本溢出 → `Expanded` + ellipsis。
- `_StatusBar` 段落数为 0 时除零 → 仅在 `totalPartsCount > 0` 时展示进度与百分比。

---

## 9. 全仓菜单审计

审计命令：

```bash
rg -n "PopupMenuButton|showMenu|OverlayEntry" lib --glob '*.dart'
```

| 位置 | 分类 | 处置 |
| --- | --- | --- |
| `core/widgets/app_action_menu.dart` | 公共组件内部实现 | 新增，统一入口 |
| `core/widgets/app_select.dart` | 公共组件内部实现 | 共用 `app_picker.dart` 策略/几何 |
| `preset_scenes_screen.dart` | 卡片 action menu | 本轮已迁移到 `AppActionMenu` |
| `features/resource_studio/.../resource_studio_section_controls.dart` | 卡片/上下文 action menu | 待迁移（记录，本轮不做） |
| `features/adventure/.../session_app_bar.dart` | 顶部溢出 action menu | 待迁移（记录，本轮不做） |
| `screens/chat/widgets/quick_menu.dart` | 上下文 action menu | 待迁移（记录，本轮不做） |
| `screens/chat/widgets/status_dropdown.dart` | 状态下拉 action menu | 待迁移（记录，本轮不做） |

- `OverlayEntry`：0。
- `showMenu`：仅剩两个公共组件内部（`app_action_menu.dart`、`app_select.dart`），符合
  "feature 不得自建菜单"的约束。
- 剩余 4 处 feature 级 `PopupMenuButton` 均为轻量上下文菜单，未发现与预存场景完全相同的
  重复组件，按"不扩大到无关业务重构"本轮只记录，后续统一到 `AppActionMenu<T>`。

---

## 10. Git 与验证基线

- 验证：`dart format .`、`flutter analyze`、相关定向测试、`flutter test`。
- 提交信息：`fix(ui): restore unified actions and generation navigation`（不 push）。
