# R02-A UI Foundation Implementation Report

> 本文档记录 LT 项目 R02 导航优先重构（Navigation-first UI Architecture Refactor）的第一阶段实施成果：UI 基础设施层建设。

---

## 1. Baseline

- **Base Commit**: `b4d02f1` (tag: `v1.1.13`, `main`)
- **Flutter SDK**: Flutter 3.44.8 stable / Dart 3.12.2
- **重构规划文档**: `docs/ui-refactor/r02-navigation-first-ui-plan.md`
- **实施原则**: STRICT 严格范围控制：不迁移/不删除任何既有业务弹窗、不修改数据库、不破坏既有 Provider 与业务逻辑，仅建立标准化、全端响应式、导航优先的 UI 基础设施。

---

## 2. Implemented Components

本阶段在 `lib/core/widgets/` 下建立并完善了全套标准 UI 基础设施：

| 组件名 | 文件路径 | 用途说明 | 核心特性 |
|---|---|---|---|
| `AppPageScaffold` | `lib/core/widgets/app_page_scaffold.dart` | 全局统一页面 Shell 脚手架 | 统一 SafeArea、AppBar、返回键、actions、maxWidth (840 居中约束)、键盘展开 `bottomBar` 弹性补偿、点击空白自动收起键盘 |
| `AppFormSection` (别名 `LtFormSection`) | `lib/core/widgets/app_form_section.dart` | 统一表单分块布局组件 | 替代散落的 Column + Padding + Text；支持标题、描述、右侧操作区 (headerAction)、children/child 间距排版、错误提示区 (error area)、可选卡片化 (card) |
| `AppTextField` (增强) | `lib/core/widgets/app_text_field.dart` | 统一语义化文本输入框 | 增强 `enabled` 禁用态与暗色/浅色主题样式适配、`focusNode`、`textInputAction`，规范 error/hint/label/isPassword 表现 |
| `AppSelect<T>` (别名 `LtSelect<T>`) | `lib/core/widgets/app_select.dart` | 全平台统一泛型选择组件 | 彻底解决旧版 `AppDropdown` 依赖复杂 `OverlayEntry` 导致的层级/滚动冲突。移动端 (<600px) 自动弹出轻量 BottomSheet 列表；桌面端/宽屏自动采用原生锚定菜单 (`PopupRoute`)；支持 validator、errorText、超长文本自动截断 |
| `AppPrimaryButton` | `lib/core/widgets/app_buttons.dart` | 统一主操作高亮按钮 | Material 3 FilledButton 风格；统一 small/medium/large 尺寸；自带 loading 旋转动画阻断与 disabled 状态防误触 |
| `AppSecondaryButton` | `lib/core/widgets/app_buttons.dart` | 统一次级/描边操作按钮 | Material 3 OutlinedButton 风格；统一尺寸规范、loading 状态、禁用状态 |
| `AppDangerButton` | `lib/core/widgets/app_buttons.dart` | 统一危险/破坏性操作按钮 | 醒目 Error 主题色；支持填充 (filled) 与描边 (outlined) 两种形态；统一 loading 与 disabled 守卫 |
| `AppLoadingView` | `lib/core/widgets/app_loading_view.dart` | 全局统一加载状态组件 | 居中主题色 CircularProgressIndicator、自适应间距与提示文案、支持可选 scrim 遮罩 |
| `AppEmptyView` (扩展 `AppEmptyState`) | `lib/core/widgets/app_empty_view.dart` | 全局统一优雅空状态视图 | 纯净白板规范圆形图标槽位、主标题、副说明、主行动按钮 (actionLabel/onAction) 与自定义 actionWidget |
| `AppErrorView` | `lib/core/widgets/app_error_view.dart` | 全局统一错误与重试组件 | 错误图标、错误标题、错误正文、堆栈/详情、一键重试按钮 (onRetry) |
| `AppConfirmDialog` | `lib/core/widgets/app_confirm_dialog.dart` | 全局统一确认对话框 | 收敛全仓裸写 AlertDialog；支持 `AppConfirmDialog.show` 静态调用；支持危险确认 (isDanger)；支持滚动正文防 320px 溢出 |
| `ui_foundation.dart` | `lib/core/widgets/ui_foundation.dart` | 基础设施统一导出入口 | 方便未来各业务页面单行直接引用全套基础组件 |

---

## 3. Reused Existing Components

本阶段严格遵循 `AGENTS.md` 的「先复用后新增」准则，对已有资产进行了深度复用与平滑衔接：

1. **`FormSubPageScaffold`**:
   - 保留原类名与 `showFormSubPage<T>` 签名，内部平滑委托至 `AppPageScaffold`，使既有调用方（如 `CharacterCardEditPage`、`SceneBatchImportPage`）零破坏运行。
2. **`AppEmptyState`**:
   - `AppEmptyView` 兼容并重新导出 `AppEmptyState`，未来调用方可自由互通。
3. **`AppActionButton` 与 `AppButtonSize`**:
   - `AppActionButton` 保留不变并新增导出 `app_buttons.dart`，与既有的 `AppActionButton.primary/secondary/danger` 和 `AppAsyncActionButton` 形成完整按钮矩阵。
4. **`AppDropdownOption`**:
   - `AppSelectItem.fromDropdownOption` 提供了与原 `AppDropdownOption` 的无缝类型适配，便于在后续阶段逐点替换 `AppDropdown`。
5. **`AppBreakpoints` 与 `requiredUiViewports`**:
   - `AppSelect` 与 `AppPageScaffold` 响应式断点统一使用 `lib/core/responsive/app_breakpoints.dart`。
   - 所有 Widget 测试严格复用 `test/helpers/responsive_test_helper.dart` 的 `setViewport` 与 `requiredUiViewports`。

---

## 4. Compatibility & Non-Destructive Design

为什么本阶段没有删除旧 Dialog 和旧组件？

1. **零现网破坏与逐步收敛**：
   - 当前全仓包含 30 处 `showDialog`、40 处 `AlertDialog` 和 16 处 `showModalBottomSheet`。如果在本阶段直接删除或大规模改动这些调用点，会产生极高风险的回归与测试中断。
   - 基础设施层先行：通过在此阶段提供完善的 `AppPageScaffold`、`AppFormSection`、`AppSelect`、`AppButtons`、`AppConfirmDialog`，为后续各阶段的业务迁移提供了完备且经过充分测试的地基。
2. **`AppDropdown` 的渐进替换**：
   - 旧版 `AppDropdown`（基于 `OverlayEntry`）拥有 1097 行实现与现有业务依赖。
   - 本阶段新增的 `AppSelect` 以路由/弹窗（BottomSheet + showMenu）作为交互核心，规避了 Overlay 带来的键盘避让与滚动穿透风险。
   - 旧 `AppDropdown` 在本阶段保留完全兼容，后续在 R02-B（资料库）、R02-C（会话/场景）中按业务块稳步替换。

---

## 5. Tests

新增专项 Widget 回归测试套件：`test/widget/ui_foundation_widgets_test.dart`。

包含 **33 个测试用例**，测试覆盖：
- `AppPageScaffold`: 标题、内容、AppBar actions、自定义 leading/返回键、全量响应式视口（320×568、360×640、390×844、412×915、768×1024、1280×800）零溢出验证。
- `AppFormSection`: 标题、描述、headerAction、child 与 children 排版、errorText 错误区域、卡片模式、320px 超长文本自适应。
- `AppTextField`: 输入响应与 onChanged 回调、errorText 状态、disabled 禁用态防护、320px 视口无溢出。
- `AppSelect`: 默认值渲染、移动端 (<600px) 底部弹窗展开与新值选取、桌面端 (>=600px) 锚定菜单展开与选取、disabled 禁用防护、validator 与 errorText 提示、320px 超长选项文字无溢出。
- `Buttons` (`AppPrimaryButton`, `AppSecondaryButton`, `AppDangerButton`): 点击交互、loading 旋转动画阻断防误触、disabled 禁用防点击、small/medium/large 尺寸排版、outlined 描边变体、320px 满宽与换行布局。
- `State Views` (`AppLoadingView`, `AppEmptyView`, `AppErrorView`): 加载指示器与文案、空状态图标/标题/描述/行动按钮、错误状态与一键重试回调、320px 紧凑屏幕无布局异常。
- `AppConfirmDialog`: 确认返回 `true`、取消返回 `false`、危险确认样式、320px 视口超长正文滚动无溢出。

静态分析与格式化：
- `dart format .`: 全部规范化完成
- `flutter analyze`: 0 warnings, 0 errors (No issues found!)
- `flutter test test/widget/ui_foundation_widgets_test.dart`: 33/33 通过 (100% Pass)

---

## 6. Next Step

### 进入阶段：**R02-B — 资料库与资源工作室迁移 (Resource Library Migration)**

下阶段工作计划：
1. **新建资源流程 Page 化**：
   - 将 `showAiResourceDialog` 迁移为 `AiResourceCreatePage`
   - 将 `showManualResourceDialog` 迁移为 `ManualResourceCreatePage`
   - 将工作室 `_ResourceCreationDialog` 收敛至统一创建页
2. **回收站 Sheet 升级**：
   - 将 `ResourceTrashSheet` 迁移为 `ResourceTrashPage`
3. **选择组件与确认弹窗收敛**：
   - 将 `resource_creation_flow` 与 `resource_studio_page` 中的 `DropdownButtonFormField` 迁移为 `AppSelect`
   - 将资料库模块中的裸 `AlertDialog` 确认替换为 `AppConfirmDialog`
