# 阶段六：编译检查、自动化测试与全链路联调计划

> **文档编号**：`06_PHASE_VERIFICATION_TESTING`  
> **前置依赖**：`05_PHASE_UI_SCREENS`  
> **预计成果**：通过全量静态类型分析，执行单元测试套件与端到端手动闭环走查，修复所有潜在边缘 Bug，完成最终的发布验收与完整归档。

---

## 1. 本阶段目标

1. 执行全面的静态代码分析（`flutter analyze`），彻底消灭编译错误、未解析符号、死代码与废弃 API 警告。
2. 移植并编写关键单元测试，验证数据库持久化、Prompt 组装、流式 JSON 解析与状态机并发安全。
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

### 2.2 重点清理项
- 确保没有残留对已剔除的 `naila_*` 和 `creation_*` 文件或符号的引用。
- 确保所有的 `BuildContext` 异步访问跨帧调用均包含 `if (!mounted) return;` 守卫。
- 确保没有遗漏的参数类型或未显式初始化的 `late` 变量。

---

## 3. 自动化测试套件设计

### 3.1 测试文件规划 (`test/`)

| 测试文件 | 覆盖模块 | 关键验证逻辑 |
| :--- | :--- | :--- |
| `test/unit/database_service_test.dart` | 持久化主库 | 在内存中初始化 SQLite，验证 15 个核心数据表的创建与外键约束生效 |
| `test/unit/key_vault_test.dart` | 安全存储 | Mock 安全存储，验证多厂商 API 密钥的加密写入与准确读取 |
| `test/unit/prompt_builder_test.dart` | 提示词构建器 | 验证给定世界观、角色卡与消息历史时，组装出的 System Prompt 格式与 Token 预算合规 |
| `test/unit/stream_handler_test.dart` | 流式打字机 | 模拟 LLM 包含 Markdown 文本与末尾 `{"hp": -10}` JSON 的分块推送，验证正文与结构化数据的准确剥离 |
| `test/unit/chat_engine_guard_test.dart` | 对话状态机 | 验证在 `isGenerating` 为 true 时，并发调用 `sendMessage` 会被安全忽略，防止重复消耗 Token |
| `test/unit/library_repository_test.dart` | 资料库仓储 | 测试角色卡与世界观预设的插入、按 ID 查询、模糊检索与级联删除 |

### 3.2 运行测试
```bash
flutter test
```

---

## 4. 端到端手动走查验收清单 (E2E Walkthrough Checklist)

### 流程 1：设置中心 (Settings)
- [ ] 打开应用，自动检测当前无 API 密钥，弹出配置引导或进入设置中心。
- [ ] 在「API 设置」选择提供商（如 DeepSeek 或 OpenAI 兼容接口），填入 Base URL 和 Key。
- [ ] 点击「测试连接」，弹出成功提示，右上角状态更新为在线。
- [ ] 切换暗黑模式与明亮模式，界面色彩平滑过渡且全局一致。

### 流程 2：资料库管理 (Resource Library)
- [ ] 点击侧边栏「资料库」，进入多标签管理页。
- [ ] 新建一个世界观设定（例如：“赛博朋克 2077 新夜之城”），填写规则并保存。
- [ ] 新建一张角色卡（例如：“黑客·艾拉”），设置性格特质与初始技能，保存后在列表中可见。
- [ ] 退出应用重新启动，验证之前创建的世界观与角色卡数据完整保留。

### 流程 3：场景对话闭环 (Scene Dialogue)
- [ ] 点击侧边栏「场景对话」，进入场景大厅。
- [ ] 点击「新建冒险」，勾选刚刚创建的“赛博朋克”世界观与“艾拉”角色卡，设置难度并开始。
- [ ] 成功进入聊天主界面，AI 发出开场白，以打字机动效呈现，并在底部给出 3 个行动预设选项。
- [ ] 点击其中一个选项（或手动输入一段自定义行动文本），消息立即上屏，底部显示生成中状态。
- [ ] AI 成功返回续写剧情，伴随数值状态栏血量/金币等动态更新。
- [ ] 测试消息手势：左滑可重试或删除上一轮对话。

---

## 5. 验收与交付物

1. `flutter analyze` 报告：`No issues found!`。
2. `flutter test` 全部测试用例 PASS。
3. 形成完整的移植验证报告 `docs/walkthrough.md`。
4. Git 提交：`feat: complete migration of dialogue, library, and settings modules from NarrAItor`。
