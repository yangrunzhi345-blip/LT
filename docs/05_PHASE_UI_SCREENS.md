# 阶段五：UI 交互界面与页面组装移植计划

> **文档编号**：`05_PHASE_UI_SCREENS`  
> **前置依赖**：`04_PHASE_PROVIDERS_CONTROLLERS`  
> **预计成果**：完成场景对话、资料库、设置中心三大界面的完整 UI 构建，并组装全局侧边栏导航，形成开箱即用、界面流畅的 Flutter 完整桌面/移动端应用。

---

## 1. 本阶段目标

1. 移植设置中心界面（`SettingsCenterScreen`、`PromptSettingsScreen`），提供直观的模型参数滑块、密钥输入与连接测试。
2. 移植资料库界面（`WorldviewEditorScreen` 及各 Tab），支持世界观、角色卡、NPC、预设模板的可视化查看与编辑。
3. 移植场景对话主界面（`LandingScreen`、`AdventureModeScreen`、`ChatScreen` 及 `chat/widgets/`），支持消息流、打字机、选项交互与数值状态栏。
4. 设计精简的全局导航框架（`MainSidebar` 与 `main.dart` 中的 `MainGate`），提供三栏/抽屉切换能力。

---

## 2. 页面与组件结构设计

### 2.1 顶级页面切换架构

```text
MainGate (应用主外壳)
├── 常驻侧边栏 (MainSidebar - 桌面端固定/移动端抽屉)
│    ├── [1] 💬 场景对话  ──► inGame? AdventureModeScreen(ChatScreen) : LandingScreen
│    ├── [2] 📚 资料库    ──► WorldviewEditorScreen / ConversationLibraryScreen
│    └── [3] ⚙️ 设置中心  ──► SettingsCenterScreen / PromptSettingsScreen
```

---

## 3. 待迁移与适配文件清单

### 3.1 设置模块界面 (`lib/screens/`)

| 目标文件 | 源文件 | 界面功能说明 |
| :--- | :--- | :--- |
| `lib/screens/settings_center_screen.dart` | `lib/screens/settings_center_screen.dart` | 设置主屏：API 密钥输入、服务商选择、温度滑块、主题切换、网络状态检测 |
| `lib/screens/prompt_settings_screen.dart` | `lib/screens/prompt_settings_screen.dart` | 自定义系统提示词预设与格式化指令配置 |

### 3.2 资料库模块界面 (`lib/screens/resource_library/`)

| 目标文件 | 源文件 | 界面功能说明 |
| :--- | :--- | :--- |
| `lib/screens/worldview_editor_screen.dart` | `lib/screens/worldview_editor_screen.dart` | 资料库多标签容器页，顶部 TabBar 切换各个分类 |
| `lib/screens/resource_library/worldview_tab.dart` | 同源 | 世界观设定条目列表与编辑对话框 |
| `lib/screens/resource_library/character_card_tab.dart` | 同源 | 角色卡（伴随角色/主控角色）卡片列表与详细表单 |
| `lib/screens/resource_library/npc_tab.dart` | 同源 | 独立 NPC 档案、阵营、关系网与台词设定 |
| `lib/screens/resource_library/template_tab.dart` | 同源 | 场景剧本模板列表，支持一键载入配置开启冒险 |
| `lib/screens/conversation_library_screen.dart` | `lib/screens/conversation_library_screen.dart` | 针对特定对话场景定制的轻量资料库查看器 |

### 3.3 场景对话模块界面 (`lib/screens/` & `lib/screens/chat/`)

| 目标文件 | 源文件 | 界面功能说明 |
| :--- | :--- | :--- |
| `lib/screens/landing_screen.dart` | `lib/screens/landing_screen.dart` | 场景大厅：展示最近冒险、新冒险创建向导、难度选择 |
| `lib/screens/adventure_mode_screen.dart` | `lib/screens/adventure_mode_screen.dart` | 冒险外壳：管理顶部状态栏（血量/金币/当前地点）与右侧抽屉 |
| `lib/screens/chat_screen.dart` | `lib/screens/chat_screen.dart` | 聊天正文主容器：滚动控制器、下拉加载历史、手势重试与编辑 |
| `lib/widgets/adventure_message_card.dart` | `lib/widgets/adventure_message_card.dart` | 核心消息渲染卡片：气泡渲染、Markdown 格式化、剧情行动选项面板 |
| `lib/screens/chat/widgets/input_bar.dart` | `lib/screens/chat/widgets/input_bar.dart` | 对话底部操作栏：文本输入框、发送按钮、快捷行动选择器 |
| `lib/screens/chat/widgets/character_sheet.dart` | 同源 | 角色属性面板：查看当前玩家状态、技能树与装备栏 |
| `lib/screens/chat/widgets/inventory_screen.dart` | 同源 | 背包物品面板：查看与使用获得的战利品/药剂/钥匙 |
| `lib/screens/chat/widgets/quest_screen.dart` | 同源 | 任务目标追踪面板：查看进行中任务与完成奖励 |
| `lib/screens/chat/widgets/chat_dialogs.dart` | 同源 | 分支回滚确认框、重试弹窗、错误提示弹窗 |

### 3.4 全局外壳组件 (`lib/widgets/` & `lib/main.dart`)

| 目标文件 | 说明 |
| :--- | :--- |
| `lib/widgets/main_sidebar.dart` | 侧边栏：提供场景对话、资料库、设置三大入口切换图标与快捷提示 |
| `lib/widgets/app_dialogs.dart` | 全局快捷弹窗工具类（快速唤起 API 设置对话框） |
| `lib/main.dart` | 应用入口：执行 FFI 初始化，包裹 `ProviderScope`，监听主题变更并渲染 `MainGate` |

---

## 4. 适配与解耦修改点

1. **移除无用页面跳转**：
   - 移除侧边栏中的「创作模式 (Creation)」与「Naila 助手」按钮。
   - 保留的侧边栏仅有 3 项（场景对话、资料库、系统设置），保持视觉清爽。
2. **简化 `main.dart` 启动流程**：
   - 移除 `CreationPostCommitOutboxService().processPending()` 后台队列。
   - 移除 `NailaKnowledgeBackgroundWorker` 后台常驻 Worker。
   - 启动流程简化为：检查 API 密钥 -> 若未配置弹窗引导 -> 进入场景大厅或上次未退出的对话。

---

## 5. 验收标准 (Acceptance Criteria)

- [ ] 启动应用成功展示初始界面，桌面端和移动端响应式布局正常。
- [ ] 点击侧边栏能在【场景对话】、【资料库】、【设置】三大模块间流畅切换。
- [ ] 设置中心输入 Key 后点击「测试连接」，能显示真实的连通性状态提示。
- [ ] 资料库支持新建世界观与角色卡，保存后列表即刻刷新展示。
- [ ] 场景大厅点击「进入世界」，能进入冒险主屏，发送文本后打字机平滑逐字输出。
- [ ] 执行 `git commit -m "feat(ui): implement all screens, widgets, and main sidebar navigation"` 归档。
