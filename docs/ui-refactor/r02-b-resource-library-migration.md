# R02-B Resource Library Migration Report

> 本文档记录 LT 项目 R02 导航优先重构（Navigation-first UI Architecture Refactor）的第二阶段实施成果：资料库新建资源流程页面化迁移与旧 Dialog/BottomSheet 清理。

---

## 1. Baseline

- **Base Commit**: `dc15281` (`feat(ui): implement R02 UI foundation components`)
- **Flutter SDK**: Flutter 3.44.8 stable / Dart 3.12.2
- **规划依据**: `docs/ui-refactor/r02-navigation-first-ui-plan.md` 及 `docs/ui-refactor/r02-a-ui-foundation-implementation.md`
- **实施边界**: STRICT 严格范围控制：只处理 Resource Library + Resource Creation Flow，不修改数据库 schema、不修改业务模型与 LLM 生成协议，彻底将弹窗驱动迁移为路由页面驱动。

---

## 2. Migrated Flows

本阶段将原先深嵌在弹窗中的 5 项核心创作流程彻底重构为独立页面：

| 流程 | 迁移前载体 | 迁移后页面与组件 | 核心变更点 |
|---|---|---|---|
| **创建资源分发** | `showResourceCreationChoices` (ModalBottomSheet) | `ResourceCreatePage` (`AppPageScaffold`) | 独立页面路由，提供直观卡片选择；支持 deep link 路由 `/library/create` |
| **手动创建** | `_ManualResourceDialog` (`showManualResourceDialog` AlertDialog) | `ResourceManualCreatePage` | 采用 `AppFormSection` + `AppSelect` + `AppTextField` + `AppPrimaryButton`；支持表单空值拦截校验、320px 窄屏适配与键盘避让 |
| **AI 智能创建** | `_AiResourceDialog` (`showAiResourceDialog` AlertDialog) | `ResourceAiCreatePage` | 完整页面结构（Header -> 资源基本信息 -> 参考资料来源 -> 提交动作）；支持粘贴/文件/已有资源三种模式 |
| **类型选择** | `DropdownButtonFormField<ResourceType>` | `AppSelect<ResourceType>` (别名 `LtSelect`) | 彻底消除脆弱的 OverlayEntry 与 DropdownButton 嵌套；移动端自动唤出原生 BottomSheet 列表，桌面端使用锚定菜单 |
| **参考资料选择** | 弹窗内 SegmentedButton + 嵌套 DropdownButtonFormField | `ResourceAiCreatePage` 页内 Section | 消除嵌套弹窗，通过 SegmentedButton 在页内直接切换输入模式；已有资源选择采用 `AppSelect<ResourceLibraryItem>` |

---

## 3. Old UI Removed

按照需求规范彻底删除了 `lib/features/resource_library/presentation/widgets/resource_creation_flow.dart` 中的所有废弃弹窗 UI，杜绝新旧两套入口并存：

- **已删除的 BottomSheet**:
  - `showResourceCreationChoices`: 原用于底部弹出选择「AI 创建」或「手动创建」的模态浮层。
- **已删除的 Dialog**:
  - `showManualResourceDialog`: 原用于手动输入名称与简介的 AlertDialog。
  - `_ManualResourceDialog`: 对应的 StatefulWidget 弹窗类。
  - `showAiResourceDialog`: 原用于 AI 参考资料输入的 AlertDialog。
  - `_AiResourceDialog`: 对应的 StatefulWidget 弹窗类。
- **保留的业务与领域契约**:
  - `ManualResourceDraft`: 纯数据模型，保留原字段与契约不变。
  - `resourceTypeLabel`: 资源类型展示映射函数，保留并继续供全仓使用。

---

## 4. New Navigation

### 迁移前后对比

- **旧架构（Dialog 驱动）**:
  ```
  ResourceLibraryScreen (点击新建)
    ↓
  showModalBottomSheet<ResourceCreationChoice> (弹窗 1)
    ↓ 选取分支
  showDialog<Draft> (弹窗 2: AlertDialog)
    ↓ 提交
  Navigator.pop(draft)
    ↓ 回调
  打开 ResourceStudioPage / createManual
  ```

- **新架构（Navigation-first 页面驱动）**:
  ```
  ResourceLibraryScreen (点击新建)
    ↓ AppRouter.push<Object?>
  ResourceCreatePage (独立全端页面，支持 /library/create 深度链接)
    ├─ 点击「AI 智能创建」  → Navigator.push → ResourceAiCreatePage
    └─ 点击「手动空白创建」 → Navigator.push → ResourceManualCreatePage
    ↓ 完成创作并 Navigator.pop(draft)
  ResourceCreatePage 顺畅向下传递 draft
    ↓
  ResourceLibraryScreen 统一接收 Draft 并进入后续流程
  ```

---

## 5. Tests

新增专项 Widget 测试套件：`test/widget/resource_creation_navigation_test.dart`。

包含 **14 个测试用例**，验证全覆盖：
1. **页面进入**:
   - 验证点击 `resource-create-button` 触发 `ResourceCreatePage` 独立路由，零 AlertDialog 与零 BottomSheet 渲染。
2. **类型选择**:
   - 验证 `ResourceCreatePage` 中 `AppSelect<ResourceType>` 正常展开并响应世界观/角色/NPC 类型切换。
3. **手动创建**:
   - 验证 `ResourceManualCreatePage` 空值校验（提示「请输入资源名称」）、表单输入、提交并正确返回 `ManualResourceDraft`。
4. **AI 智能创建**:
   - 验证 `ResourceAiCreatePage` 空值校验、粘贴输入、文件模式（文件名与文件正文双字段校验）、已有资源模式选取、提交并正确返回 `ResourceStudioCreationDraft`。
5. **移动端响应式硬门槛 (320px, 360px, 390px)**:
   - 验证 `ResourceCreatePage`、`ResourceManualCreatePage`、`ResourceAiCreatePage` 在 320×568、360×640、390×844 及软键盘展开状态下：
     - `tester.takeException() == null`
     - 零 RenderFlex overflow
     - 提交按钮可滚动到达且不被键盘遮挡

---

## 6. Risks Assessment

| 级别 | 编号 | 描述 | 状态 / 缓解措施 |
|---|---|---|---|
| **BLOCKER** | R02B-B1 | 资料库新建入口在移动端和小屏设备上由于旧 Overlay 下拉导致卡死或溢出 | **已解决**：完全迁移为 `AppPageScaffold` 页面与 `AppSelect` 组件，320px 零溢出。 |
| **MAJOR** | R02B-M1 | 弹窗返回值驱动业务可能破坏 `ResourceLibraryScreen` 现网数据流 | **已解决**：新页面严格维持 `ManualResourceDraft` 与 `ResourceStudioCreationDraft` 类型契约，路由返回值无缝兼容。 |
| **MINOR** | R02B-N1 | Deep link 无法直达新建资源页面 | **已解决**：在 `AppRouter.onGenerateRoute` 注册 `/library/create` 路由映射。 |

---

## 7. Next Step

### 进入阶段：**R02-C — 对话/场景与角色状态模块迁移 (Chat & Session Dialog Migration)**
- 重点收敛 `session_app_bar.dart` 与 `chat_dialogs.dart` 中的模型选择 BottomSheet。
- 收敛消息编辑与角色状态弹窗。
