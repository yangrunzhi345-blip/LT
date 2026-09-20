# LT Dialogue

[![Flutter](https://img.shields.io/badge/Flutter-app-02569B?logo=flutter)](https://flutter.dev/)
[![Dart](https://img.shields.io/badge/Dart-%3E%3D3.0.0-0175C2?logo=dart)](https://dart.dev/)

LT Dialogue（应用内名称：**LT 灵境**）是一个本地优先的 Flutter AI 叙事应用。它把互动冒险、结构化资料库、AI 资源生成和可恢复的运行态放在同一个工作流中：用户可以先整理世界观与角色资料，再通过装配向导创建冒险，并在对话中持续推进剧情。

项目当前同时服务两类场景：

- **互动冒险**：选择世界观、角色和 NPC，创建冒险后进行流式场景对话。
- **资料创作**：创建、导入和编辑世界观、角色卡、NPC 等结构化资源，供冒险或后续创作复用。

## 当前状态

当前 main 分支处于持续开发与稳定性加固阶段，核心资源生成、版本边界、组装就绪检查和 Adventure 运行态已经接入生产调用链。

| 项目 | 当前值 |
| --- | --- |
| 应用版本 | 1.1.13+16（见 pubspec.yaml） |
| Dart SDK | >=3.0.0 <4.0.0 |
| SQLite schema | 44 |
| 当前主线 | main |
| 数据库 | SQLite；桌面端使用 sqflite_common_ffi |
| 支持目标 | Linux、Windows、Android、macOS、iOS |

仓库中的 package 版本可能领先于 GitHub Release 标签；发布版本请以 Releases 页面中的实际构建产物为准。

## 核心功能

### 主应用入口

主界面由三块一级区域组成：

- **探索 / Adventure**：冒险大厅、最近存档、预设场景和冒险创建入口。
- **资料库 / Resources**：按世界观、角色和 NPC 管理资源，支持搜索、筛选、详情、回收站和创作工作台。
- **设置 / Settings**：模型服务、会话参数、主题外观、字号、数据和聊天导入导出。

桌面端使用常驻侧栏；紧凑屏幕使用抽屉和底部导航。应用启动时会检查模型配置，并启动压缩任务、版本维护、资源组装就绪状态和中断生成会话的恢复流程。

### 资源库与资源模型

资源采用固定的三层结构：

    Resource
      └─ Section
           └─ Part

当前资源类型为：

- worldview：世界观、规则、地点、势力等长篇设定。
- character：角色卡及其关系、背景和行为信息。
- npc：与完整角色卡分开存储和管理的 NPC 资料。

资源节点具有稳定 ID、显式顺序和 draft / confirmed / archived 状态。长正文只存放在 Part 中；资源的创建、编辑、生成、删除和恢复均通过统一的资源管线与仓库边界处理。

资料库还提供：

- 搜索、类型筛选、详情查看和进入 Resource Studio。
- 回收站、恢复和显式永久删除。
- 资源版本历史、当前 head、恢复历史版本和乐观并发检查。
- 容量测量、压缩候选生成与发布；压缩不会直接覆盖当前内容。
- conversation、adventure、creation 三种资料库使用模式。

### 资源创建与导入

新建资源先选择类型，再选择创建方式：

1. **手动创建**：填写类型、名称和简介，建立带初始空章节的资源。
2. **AI 创建**：提供名称、目标字数和参考资料，参考来源可以是粘贴文本、文件文本或已有资源。

AI 资源流程会先创建带幂等键的创建会话，再进行蓝图规划、候选确认和分 Part 生成。生成失败可以恢复或重试，不会因为重复提交而无条件创建重复资源。

现有导入入口包括：

- 世界观 AI 导入：简洁或详细模式，可设定目标字数并显示分阶段进度。
- 角色 / NPC AI 导入：可关联世界观和已有角色，支持简洁或详细生成。
- 场景资料批量导入：先由 AI 识别候选人物，再由用户选择要生成的角色或 NPC。
- 资源库中的手动编辑、AI 整理和已有资源关联。

导入结果会经过结构和语义校验，再进入统一保存/生成链路。旧资源仍由兼容映射与迁移服务读取，但新的创建和保存路径以当前 Resource 树为准。

### Resource Studio

Resource Studio 是资源的结构化编辑和生成工作台。它提供：

- 左侧 Resource → Section → Part 目录；移动端默认收起，可手动展开。
- 当前 Part 的正文预览、编辑、删除和单 Part 重试。
- 章节新增、重命名、上移、下移、删除、验证和重新生成。
- AI 蓝图规划、生成任务、流式正文、暂停、继续、取消、失败恢复和重试。
- 编辑器自动保存、未保存草稿恢复和外部写入冲突处理。
- 容量状态、压缩候选、发布压缩结果和版本历史。

生成链路以 ResourceStudioRuntime、ResourceCreationPipeline、蓝图仓库和流式生成服务为边界。网络接收与 UI 刷新分离，过期请求、取消和迟到事件不会覆盖新的生成任务。

### 冒险组装与运行

冒险创建向导按以下步骤收集运行所需的快照输入：

1. 设定世界观：从资料库选择，或直接填写自定义世界设定。
2. 选择角色阵容：选择主控角色、同行角色及其关系。
3. 选择常驻 NPC：选择本次冒险需要冻结到快照中的 NPC。
4. 配置序章、初始行动分支、难度和自定义指引。
5. 在装配总览中检查所有内容并启动冒险。

启动前会经过 Adventure readiness gate。资源的可用内容从已发布的 assembly revision 构建，装配过程将资料库内容复制为 Adventure 自己的初始快照；之后的冒险运行不会反向修改资料库原始资源。

运行态由冒险自己的消息、场景状态、角色状态、世界条目、分支和 Runtime overlay 组成。对话中的状态更新先经过解析、校验、revision 检查和事务提交，再成为下一轮上下文的一部分。

### 对话与叙事能力

Adventure Session 当前包括：

- 流式叙事输出、可选的 reasoning 展示和打字机刷新。
- 行动选项、单轮结构化结算以及自定义状态评估。
- 世界上下文检索、运行态记忆投影和有界历史摘要。
- 分支创建、切换和分支级消息/摘要/运行态隔离。
- 角色切换、骰点检查、消息编辑、书签和会话管理。
- 对话导入/导出、翻译和本地 TTS。

一轮模型响应由叙事正文和结构化数据两部分组成。结构化部分用于场景、选项和状态变化；本地解析器与运行态服务负责验证和持久化，模型输出不会直接写入数据库。

## 当前架构与技术栈

### 技术栈

- Flutter / Dart 3。
- Material 3 UI，统一主题、颜色、字号和响应式断点。
- Riverpod 作为依赖注入入口，并以 ChangeNotifierProvider 包装现有 Settings、Adventure、Library、Messaging 等状态对象。
- SQLite：移动端使用 sqflite，Linux / Windows / macOS 使用 sqflite_common_ffi；当前 schema version 为 44。
- http：OpenAI-compatible chat completions 与 SSE 流式传输。
- flutter_secure_storage、本地加密 KeyVault、shared_preferences 和 SQLite 配置存储。
- flutter_tts、connectivity_plus、google_fonts、flutter_svg、pointycastle 等平台与 UI 依赖。
- mocktail 与 Flutter test 用于单元、Widget、集成边界和回归测试。

### 分层与主要边界

    Flutter Pages / Widgets
            ↓
    Controllers / ChangeNotifiers / Riverpod providers
            ↓
    Application use cases / Engines / Runtime contracts
            ↓
    Repositories / Services / LLM gateways
            ↓
    SQLite + configured LLM endpoint + platform services

仓库当前仍处于逐步整理中的混合架构：较早的 providers、controllers、services 与较新的 features、application、domain 并存。新的资源创建、生成、版本、回收站和组装能力通过应用层 runtime、repository 和 gateway 接入；不要把旧目录结构理解为所有代码的唯一分层方式。

LLM 调用统一经过当前模型配置和应用层 gateway。模型能力由 ModelCapabilityRegistry 描述，任务由 LlmTask / policy 选择 thinking、JSON、vision 等请求行为；默认 DeepSeek 模型 ID 为 deepseek-flash，也可以配置任意 OpenAI-compatible Base URL、模型名和 API Key。

### 数据与隐私

- 资源、冒险、消息、运行态、版本和本地设置默认保存在设备上的 SQLite 数据库中。
- API Key 写入本地 api_keys 表前经过 KeyVault 加密；密钥不会通过 LT 自有中间服务器转发。
- 使用云端模型时，发送给你配置的模型服务商的内容可能包含当前对话、相关世界资料和运行态上下文。请按自己的隐私要求配置模型服务和资料。
- 数据库启动会执行完整性检查、版本迁移和必要的启动恢复；数据库升级逻辑集中在 DatabaseService。

## 安装与运行

### 环境要求

- Git。
- Flutter stable SDK，且其 Dart SDK 满足 >=3.0.0 <4.0.0。
- 目标平台对应的 Flutter 工具链：Android SDK、Xcode、Linux 或 Windows 桌面依赖等。

### 从源码运行

    git clone https://github.com/yangrunzhi345-blip/LT.git
    cd LT
    flutter pub get

    # 查看可用设备
    flutter devices

    # 桌面端示例
    flutter run -d linux       # 或 windows / macos

    # 移动端示例
    flutter run -d android
    flutter run -d ios

应用入口是 [lib/main.dart](lib/main.dart)。首次启动后打开设置，选择 DeepSeek 官方 API 或自定义 OpenAI-compatible 服务，填写 Base URL（自定义服务）、模型名和 API Key，并测试连通性。

### 常用路由

路由集中在 [lib/core/router/app_router.dart](lib/core/router/app_router.dart)：

- /library：资料库。
- /library/create：新建资源。
- /studio：Resource Studio；需要资源 ID 或生成会话 ID。
- /adventure/create、/adventure/wizard、/adventure/assembly：冒险装配向导。
- /settings、/settings/api、/settings/model、/settings/advanced：设置页面。
- /conversations/manage：对话管理。

## 开发与测试

格式化与静态分析：

    dart format .
    flutter analyze

运行全部测试：

    flutter test

按子系统运行示例：

    flutter test test/widget/resource_studio_test.dart
    flutter test test/application/resources
    flutter test test/unit

性能基准入口为 [benchmark/core_benchmark.dart](benchmark/core_benchmark.dart)：

    flutter test benchmark/core_benchmark.dart

当前仓库包含 187 个 *_test.dart 文件，覆盖领域模型、应用用例、资源生成/迁移/版本、Adventure 运行态、LLM 流式可靠性、架构边界和 Widget 响应式布局。

本次 README 更新基于 2026-09-20 的 main 自检：flutter test 共执行 1,917 个测试，其中 1,914 个通过、3 个失败；失败集中在 resource_library_production_test.dart 的空 Section、缺少正文和正文超长验证映射。flutter analyze 仍有 1 个既有 warning，位于 lib/application/resources/assembly_readiness_coordinator.dart:196（try 块内返回未 await 的 Future）。这些结果反映当前代码基线，不是 README 变更引入的失败。

## 项目结构

    lib/
    ├─ application/    # 用例、LLM gateway、叙事上下文、资源创建/生成/组装
    ├─ config/         # 应用配置与提示词相关配置
    ├─ controllers/    # 既有控制器与资源导入/生成控制器
    ├─ core/           # 路由、主题、响应式断点、通用 UI 基础设施
    ├─ data/           # 内置预设数据
    ├─ domain/         # 资源、Adventure 与运行态领域契约
    ├─ engines/        # ChatEngine 与流式、上下文、摘要等内部组件
    ├─ features/       # Adventure、Resource Library、Resource Studio、Settings
    ├─ models/         # 应用、LLM、Adventure、资源辅助模型
    ├─ providers/      # Riverpod 入口与 ChangeNotifier facade
    ├─ screens/        # 仍在使用的旧页面与兼容入口
    ├─ services/       # SQLite、repository、LLM、TTS、翻译及平台服务
    ├─ widgets/        # 跨功能公共 Widget
    └─ main.dart       # 应用入口与主导航壳

    test/              # 单元、应用层、架构、集成和 Widget 测试
    docs/              # 当前仍有效的设计文档

## 当前边界

README 只描述当前 main 中已经存在的能力。以下内容不应被理解为已经交付的产品功能：

- 通用 Tool Calling / Responses API agent runtime。
- Graph DB、Vector DB 或 Secret Knowledge Graph 产品化存储。
- 面向用户的完整 revision merge / rebase / cherry-pick 工作流。
- 自动化 Agent 自主决策与跨资源影响分析。

这些方向如果进入实现，会以代码、测试和独立设计文档为准更新 README；不会仅因为存在接口、旧文档或历史分支就宣称已经支持。

## 相关文档

- [docs/adventure_runtime_state.md](docs/adventure_runtime_state.md)：Adventure 运行态、分支、上下文和提交模型。
- [docs/README.md](docs/README.md)：当前有效项目文档索引。
- [AGENTS.md](AGENTS.md)：仓库开发、测试、数据安全和 Git 工作规范。

## License

仓库当前未包含 LICENSE 文件。转载、分发或商用前，请通过 GitHub Issue 与作者确认授权范围。
