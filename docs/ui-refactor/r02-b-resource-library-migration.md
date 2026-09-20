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

当前包含 **19 个测试用例**，验证全覆盖：
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

---

## 8. Post-migration Regression Fix: AI 生成长度

### 历史审计与根因

- R02-B 的直接前驱 `_AiResourceDialog` 已没有目标字数控件；因此
  `45fa869` 的页面替换不是单独删除 Slider 的提交。
- 生成协议始终保留长度能力：Blueprint Prompt 支持 `nominalBudget`，
  Blueprint Part 使用 `estimatedLength`，随后由 Part Coordinator 转成
  `PartGenerationRequest.targetBudget`，Part Prompt 与 Parser 继续执行
  `ResourceLimits.maxPartCharacters` 等既有边界。
- 回归根因是 UI、`ResourceStudioCreationDraft` 和 Studio runtime 没有公开及传递
  该预算，Planner 只能使用类型默认 nominal capacity。R02-B 当时又明确限制为不改
  业务模型与生成协议，页面迁移因而延续了这个缺口。

### 修复

- `ResourceAiCreatePage` 在参考资料之后新增“生成长度” Section，采用 Slider、
  明确字数及“短篇 / 长篇”端点标签。
- 统一范围取自 `ResourceLimits`：最小 1000 字、步长 500 字；最大值和默认值
  使用资源类型 nominal capacity（世界观 50000 字，角色 / NPC 5000 字）。切换
  参考来源保留数值；切换类型时保留仍合法的数值，否则 clamp 到新上限。
- 完整参数链：Page State → `ResourceStudioCreationDraft.targetCharacters` →
  Studio Controller / Runtime → `ResourceCreationRequest.targetCharacters` → v44
  `resource_creation_sessions.target_characters` → Blueprint Planner / Prompt /
  Validator → Blueprint Part `estimatedLength` → Part Coordinator
  `targetBudget` → LLM Part Prompt。
- Blueprint Prompt 将总预算表达为“约 N 字”的目标，同时禁止超过 N 字；Validator
  使用同一预算拒绝超限规划。Part 生成仍走原有 Parser、重试与容量协议，没有建立
  第二套正文校验。

### 回归检查与测试

- Widget 测试覆盖默认值、拖动、提交、参考来源切换保值、资源类型 clamp，以及
  320×568、360×640、390×844、412×915 viewport 无 overflow。
- Pipeline / Planner 测试覆盖范围验证、会话持久化、幂等指纹、Prompt 注入、
  Blueprint 目标容量和超预算拒绝；Studio Controller 测试覆盖 runtime 参数传递。
- 对照直接前驱后，类型、名称、三类参考资料、validation 和路由返回能力均保留；
  未发现其他可确认的 R02-B 功能回归。
- 2026-09-20 验证结果：`dart format .` 无额外改写，`flutter analyze` 为
  0 issues，`flutter test` 共 1838 个测试全部通过。

---

## 9. Post-migration CRUD Regression Audit

### 删除回归与历史语义

- `772a4b9` 引入统一资料库及 `ResourceLibraryDetailPage` 时，将详情能力收敛为
  查看与进入创作工作台，但没有迁移旧资料库子页中的删除操作。R02-B 的直接前驱
  已存在该缺口，`45fa869` 的创建流程页面化继续保留了它；因此这是迁移阶段暴露的
  生命周期回归，但根因早于 R02-B 的创建页面提交。
- Phase 9 已将资源删除统一定义为可恢复的 soft delete。恢复后的生产调用链为：
  `ResourceLibraryDetailPage` → `ResourceLibraryController` →
  `ProductionResourceLibraryRuntime` → `ResourceCrudController` →
  `ILibraryRepository` → `ResourceLibraryTrashBridge` →
  `ResourceTrashService` → SQLite transaction。
- 详情页“资源操作”区使用 `AppDangerButton`，确认使用 `AppConfirmDialog`，所有文案
  明确为“移入回收站”。成功后路由返回资料库、立即重新加载并显示成功反馈；失败时
  保留详情页并显示错误，不会先行 pop。
- 顶部垃圾桶保持“进入回收站”的原语义。现有入口已经导航到
  `ResourceTrashPage`，支持查看、恢复和经二次确认后的永久删除，没有回退为
  Dialog 或 BottomSheet。

### CRUD 功能等价性

| 范围 | 生产实现与审计结论 |
|---|---|
| Create | 手动创建与 AI 创建均可达；AI 的粘贴、文件、已有资源参考及目标字数均有页面状态、参数传递和生产测试。 |
| Read | 列表、搜索、类型过滤、详情、状态和长文本布局均保留；列表具备 loading、error、retry 和下拉刷新。 |
| Update | 高级创作、正文编辑、autosave、revision、校验与生成状态仍由 Resource Studio 提供。旧世界观/角色属性编辑函数仍留在遗留子页，但在 R02-B 直接前驱的统一资料库中已经不可达，未发现由 R02-B 新近移除的 `ResourceEditPage` 或等价生产入口，因此本轮不复活旧表单式 UI。 |
| Delete | 本次恢复详情页 soft-delete 入口；列表立即移除资源。回收站查看、恢复、永久删除继续复用 Phase 9 服务。 |
| Async / recovery | 创建与 Studio 保留 cancel、错误、流式恢复及 autosave 冲突处理；资料库加载保留 error/retry；删除新增 busy 防重复提交、失败留页和明确反馈。 |

未发现目标字数与删除之外可归因于 R02-B 的其他明确功能回归。名称与旧式资源属性
编辑属于统一资料库之前就已不可达的遗留能力，若产品需要重新开放，应单独定义
`ResourceEditPage` 的字段范围与 tree/legacy 双写契约，不能直接恢复旧 Dialog。

### 回归测试

- `resource_library_phase11_test.dart`：覆盖详情删除入口、统一确认、取消不调用、
  成功返回并刷新、失败留页，以及 320×568、360×640、390×844、412×915。
- `resource_library_production_test.dart`：使用真实 Provider、Controller、Repository、
  Trash Service 与 SQLite，验证删除后资源从列表消失、写入回收站、tree row 被
  soft delete，并可从 `ResourceTrashPage` 恢复后立即重新出现在资料库。
- 既有 `resource_trash_sheet_test.dart` 继续覆盖回收站查看、恢复、永久删除确认和
  全套响应式 viewport。
- 2026-09-20 最终验证：`dart format .` 无额外改写，`flutter analyze` 为
  0 issues，`flutter test` 共 1847 个测试全部通过。

---

## 10. Post-migration Navigation Fix: AI 创建进入生成工作台

### 根因

AI 创建的导航本身没有断（`ResourceCreatePage` → `ResourceAiCreatePage` →
`ResourceStudioPage(creationDraft:)`，与 R02-B 前 Dialog 版本一致，并有真实 SQLite
生产测试）。真正的问题是 `ResourceStudioPage._buildBody` 在 `tree == null` 时无条件
渲染 session picker；而创建流程在 Blueprint 规划完成前 `tree` 一直为 `null`，
导致整段真实创建期间用户看到"选择资源或生成会话"而不是生成态界面。

### 修复

- 创建期间（`_creating`）渲染真实创建态 `_buildCreationInProgress`，不再回退 picker。
- 创建失败（`_creationFailed`）渲染 `_buildCreationFailure` + "重试创建"，留在 Studio，
  不弹回资料库。
- `_creationInFlight`（创建重入）与 `ResourceAiCreatePage._submitting`（提交防重复）。
- `_StatusBar` 段落数为 0 时不再除零。

`ResourceStudioPage` 继续复用现有生产生成能力（Streaming / Patch / Validation /
Retry / Cancel / Recovery），没有新增假工作台或第二套 Generation State；
worldview / character / npc 全部走同一条流程；`targetCharacters` 从 UI 贯通到
`resource_creation_sessions.target_characters`。

完整说明与测试见
`docs/ui-refactor/r02-unified-actions-and-generation-navigation.md`。
