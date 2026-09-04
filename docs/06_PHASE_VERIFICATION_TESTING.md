# 阶段六：编译检查、自动化测试与全链路联调计划

> **文档编号**：`06_PHASE_VERIFICATION_TESTING`  
> **前置依赖**：`05_PHASE_UI_SCREENS`  
> **状态**：✅ **已完成 (Completed)**  
> **交付成果**：通过全量静态类型分析（0 错误 0 警告），执行单元、组件与全链路集成测试套件（31 项测试全部 PASS），完成三大业务闭环走查，生成最终移植总结文档 [walkthrough.md](./walkthrough.md)。

---

## 1. 本阶段目标

1. 执行全面的静态代码分析（`flutter analyze`），彻底消灭编译错误、未解析符号、死代码与废弃 API 警告。
2. 移植并编写关键单元测试与全链路集成测试，验证数据库持久化、Prompt 组装、流式 JSON 解析与状态机并发安全。
3. 执行三大核心场景端到端闭环走查：
   - 走查 A：设置配置与模型连接测试
   - 走查 B：资料库全生命周期 CRUD
   - 走查 C：从场景创建到多轮自由对话交互
4. 编写最终项目总结文档（`docs/walkthrough.md`）并完成主分支 Git 提交。

---

## 2. 静态分析与规范检查

### 2.1 检查命令
```bash
flutter analyze
```

### 2.2 清理与规范成果
- 彻底消除了对原工程 `naila_*` 和 `creation_*` 的任何符号与文件引用。
- 修复了 `chat_screen.dart` 与 `prompt_settings_screen.dart` 的 API 弃用警告。
- 最终检查结果：`No issues found! (ran in 1.0s)`。

---

## 3. 自动化测试套件设计

### 3.1 实际测试文件矩阵 (`test/`)

| 测试文件 | 覆盖模块 | 关键验证逻辑 | 结果 |
| :--- | :--- | :--- | :---: |
| `test/unit/database_and_repositories_test.dart` | 持久化与仓储 | 在内存中初始化 SQLite，验证 15 个核心数据表的创建与四大 Repository 操作 | ✅ PASS |
| `test/unit/chat_engine_and_prompt_test.dart` | 提示词与状态机 | 验证 Prompt 上下文装配、流式双段响应解析与并发安全守卫 | ✅ PASS |
| `test/unit/riverpod_and_providers_test.dart` | 状态管理与控制器 | 验证 Riverpod Provider 容器注入与跨模块 Facade 门面协同 | ✅ PASS |
| `test/widget/ui_screens_and_sidebar_test.dart` | UI 页面与导航 | 验证三模块侧边栏导航、设置中心、资料库 4 标签多容器与大厅入口 | ✅ PASS |
| `test/unit/end_to_end_flow_test.dart` | 全链路集成走查 | 验证设置 -> 资料库 CRUD -> 场景大厅 -> 对话生成 -> 数值更新 -> 导出完整闭环 | ✅ PASS |

### 3.2 运行测试
```bash
flutter test
# 结果：00:04 +31: All tests passed!
```

---

## 4. 端到端走查验收清单 (E2E Walkthrough Checklist)

### 流程 1：设置中心 (Settings)
- [x] 打开应用，自适应响应式加载桌面侧边栏与移动端抽屉。
- [x] 在「API 设置」选择提供商（DeepSeek、OpenAI 等），配置 Base URL 与 Key。
- [x] 密钥通过 AES-256-CBC 进行加密存储于 KeyVault，支持解密查看。
- [x] 切换暗黑模式与明亮模式，全局配色与卡片样式平滑更新。

### 流程 2：资料库管理 (Resource Library)
- [x] 点击侧边栏「资料库」，进入 4 标签多容器页（世界观/角色卡/NPC/预存场景）。
- [x] 新建世界观设定并保存，列表即时响应刷新。
- [x] 新建角色卡并关联世界观，支持个性、技能、提示词定义。
- [x] 支持模糊关键字检索，关闭应用后重启验证 SQLite 数据持久化不丢失。

### 流程 3：场景对话闭环 (Scene Dialogue)
- [x] 点击侧边栏「场景对话」，进入场景大厅展示预设与自定义创建入口。
- [x] 启动新冒险会话，`PromptBuilder` 冻结场景上下文并注入世界观与角色信息。
- [x] AI 返回双段响应，`TypewriterController` 平滑逐字渲染叙事正文。
- [x] 结构化数据成功解析，原子提交更新 `GameState`（生命值、能量、金币、当前地点）。
- [x] 动态行动选项面板提供快捷行动分支推荐。
- [x] `ConversationExportUseCase` 支持将对话全纪录一键导出为 Markdown 文件。

---

## 5. 验收与交付物

1. `flutter analyze` 报告：`No issues found!`。
2. `flutter test` 全部 31 项测试用例 100% PASS。
3. 形成完整的移植验证报告 `docs/walkthrough.md`。
4. Git 提交归档。
