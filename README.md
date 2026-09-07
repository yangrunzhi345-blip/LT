# 🎮 LT Dialogue

**下一代 AI 驱动的沉浸式文字冒险编辑器与角色扮演工作台**

基于 Flutter & Riverpod 构建，专为网文写手、TRPG 跑团玩家与 AI 角色扮演爱好者打造的全平台创作利器。

[![Flutter](https://img.shields.io/badge/Flutter-3.22+-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.0+-0175C2?logo=dart&logoColor=white)](https://dart.dev)
[![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20iOS%20%7C%20Windows%20%7C%20macOS%20%7C%20Linux-brightgreen)](#全平台支持)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![GitHub Stars](https://img.shields.io/github/stars/your-username/lt_dialogue?style=social)](https://github.com/your-username/lt_dialogue)

[功能特性](#-功能特性深度解析) • [快速上手](#-快速上手) • [架构设计](#-架构与技术选型) • [路线图](#-开发路线图-roadmap) • [贡献指南](#-贡献指南)

![项目演示截图](https://raw.githubusercontent.com/your-repo/lt_dialogue/main/docs/screenshot.png)

</div>

---

## 💡 为什么选择 LT Dialogue？

在传统的 AI 对话工具中，创作者常受困于**上下文容易遗忘、设定难以精细调控、多分支剧情难以管理、多端体验割裂**等痛点。

**LT Dialogue** 不只是一个聊天界面，而是一套完整的**文字冒险与互动小说创作环境**：
- 🧭 **精准的设定注入**：将世界观设定、人物小传与上下文规则分层组合，告别“AI 忘本”。
- 🌿 **非线性叙事管理**：支持剧情分支切换、回溯与多重结局探索。
- ⚡ **真正的全端通用**：统一的代码库，支持桌面端重度排版与移动端随时随地推演。
- 🔒 **数据自主与安全**：API Key 本地硬件加密，对话与设定全量 SQLite 本地存储，杜绝隐私泄露。

---

## ✨ 功能特性深度解析

### 1. 🎭 模块化设定资源库（Resource Library）
* **角色卡管理（Character Cards）**：支持独立的角色性格、动机、口癖、第一人称视角设定，支持头像及多状态卡片管理。
* **世界观词条（Lorebooks / Worldview）**：按需激活机制。设定地理、魔法体系、派系阵营等背景规则，在相关事件触发时智能注入提示词上下文。
* **作者注释与提示词预设（Author's Notes & Presets）**：分层管理 System Prompt、Jailbreak、全局格式规范与实时动态微调指令。

### 2. 🌲 剧情分支与冒险编排（Adventure Engine）
* **分支决策树（Branching Narrative）**：支持从任意历史对话节点开辟新分支，对比不同选择下的剧情走向。
* **上下文动态压缩与监控**：实时 Token 占用进度条、智能剔除超长历史、保留核心记忆锚点。
* **多格式全量导入导出**：
  * **JSONL**：便于机器学习微调与数据备份；
  * **Markdown / TXT**：一键导出为规整的小说与阅读文档；
  * **HTML**：生成沉浸式的网页版互动故事书。

### 3. 🧠 灵活的模型接入矩阵（Multi-LLM Matrix）
* **主流模型原生支持**：DeepSeek（V3 / R1）、OpenAI（GPT-4o 系列）、Claude 等。
* **自定义端点（Custom Endpoint）**：兼容任意 OpenAI API 标准中转、本地私有化部署模型（Ollama、vLLM、LM Studio、LocalAI）。
* **高级生成参数微调**：实时调节 `Temperature`、`Top-P`、`Presence Penalty`、`Frequency Penalty` 及停止词序列。

### 4. 🎧 沉浸式多模态与无障碍体验
* **流式极速响应（Stream Response）**：字符级即时吐字，告别漫长等待。
* **内置语音交互（TTS）**：文字转语音朗读对话，赋予角色真实声音。
* **多语言即时翻译**：跨语言角色扮演无障碍，内置多引擎一键互译。
* **离线感知模式**：自动识别断网状态并优雅降级，离线可流畅浏览、编辑、整理本地资料库。

### 5. 🎨 极致的 UI/UX 与性能打磨
* **细粒度局部刷新**：基于 `ValueNotifier` 与精密状态分离，长文本滚动与高频流式输出下依旧稳定 60/120 FPS。
* **深度主题引擎**：Material 3 设计规范，支持动态色彩种子（Color Seeds）、完全可自定义的明暗主题与字号阶梯。

---

## 🖥️ 全平台支持

| 平台 | 状态 | 说明 |
| :--- | :---: | :--- |
| **Windows** | ✅ 完美支持 | 原生桌面布局，快捷键支持，高 DPI 自适应 |
| **macOS** | ✅ 完美支持 | 支持 Apple Silicon 原生架构，沉浸式标题栏 |
| **Linux** | ✅ 完美支持 | 经过 Ubuntu / Arch Linux 等主流发行版测试 |
| **Android** | ✅ 完美支持 | 手势操作优化，移动端自适应键盘交互 |
| **iOS** | ✅ 完美支持 | 遵循 iOS 动效与触控反馈标准 |

---

## 🚀 快速上手

### 环境准备

- [Flutter SDK](https://docs.flutter.dev/get-started/install) `>= 3.22.0`
- [Dart SDK](https://dart.dev/get-dart) `>= 3.0.0 < 4.0.0`
- Git 命令行工具

### 获取源码与依赖


# 1. 克隆项目仓库
git clone [https://github.com/your-username/lt_dialogue.git](https://github.com/your-username/lt_dialogue.git)
cd lt_dialogue

# 2. 安装 Flutter 依赖包
flutter pub get


### 运行应用


# 桌面端开发运行 (以当前操作系统为准)
flutter run -d macos     # macOS
flutter run -d windows   # Windows
flutter run -d linux     # Linux

# 移动端运行 (请确保已连接真机或已启动模拟器)
flutter run -d android
flutter run -d ios


### 接入你的第一个大模型

1. 启动应用后，点击侧边栏左下角进入 **设置中心 (Settings Center)**；
2. 选择 **模型服务商**（例如 `DeepSeek` 或 `Custom OpenAI Compatible`）；
3. 填入你的 **API Key** 与 **Base URL** 并点击保存；
4. 进入主界面创建一段新的冒险，开启你的互动小说之旅！

---

## 🏗️ 架构与技术选型

本项目遵循清晰的关注点分离与分层驱动设计：


lt_dialogue/
├── lib/
│   ├── application/       # 业务逻辑接口层 (Adventure, LLM, PromptPolicy)
│   ├── core/              # 核心基础规范 (Design Token, Theme, Global Constants)
│   ├── models/            # 领域不可变实体 (AdventureConfig, Message, Worldview)
│   ├── providers/         # 全局状态管理枢纽 (Riverpod 驱动的状态树)
│   ├── screens/           # 页面级 UI 组件 (Landing, ChatScreen, Library)
│   ├── services/          # 底层驱动与硬件交互 (SQLite, LLMClient, TTS, Network)
│   └── widgets/           # 复用原子级 UI 组件 (Bubble, InputBar, Sidebar)
├── test/                  # 单元测试与 Widget 交互集成测试
└── assets/                # 预设模板、字体及静态资源



* **状态管理**：采用 `Riverpod` 构建可测试、可观测的单向数据流；
* **渲染优化**：在关键的高频变动模块使用精细化 `ValueListenableBuilder` 隔离重绘区域；
* **跨平台持久化**：统一基于 `sqflite_common_ffi` 实现零依赖的跨端本地 SQLite 存储；
* **安全性**：关键凭证（API Token）通过本地硬件安全加密存储（Keychain / Keystore / 平台加密接口）。



## 🗺️ 开发路线图 (Roadmap)

* [x] 多端桌面与移动适配
* [x] 流式 LLM 交互与 Token 监控
* [x] 角色卡与世界观词条按需激活
* [ ] **RAG 本地知识库**：集成向量检索，支持导入几十万字设定书自动切片召回
* [ ] **视觉增强（NovelAI / Stable Diffusion）**：根据当前场景自动生成场景插图与角色立绘
* [ ] **跑团模组骰娘系统**：支持 DND/COC 检定与规则判定宏



## 🤝 贡献指南

我们非常欢迎社区开发者提交贡献！

1. **Fork** 本仓库；
2. 新建你的特性分支：`git checkout -b feat/amazing-feature`；
3. 遵循 [Effective Dart](https://dart.dev/guides/language/effective-dart) 代码规范，确保执行 `flutter analyze` 无严重警告；
4. 提交你的修改：`git commit -m 'feat: Add some amazing feature'`；
5. 推送到远端分支：`git push origin feat/amazing-feature`；
6. 提交 **Pull Request**。

---

## 📄 开源协议

本项目基于 **MIT License** 协议开源与分发，详情请参阅 [LICENSE](https://www.google.com/search?q=LICENSE) 文件。

---

**如果这个项目对你的创作或学习有所启发，欢迎给个 ⭐ Star 支持一下！**

遇到问题？欢迎提交 [Issues](https://www.google.com/search?q=https://github.com/your-username/lt_dialogue/issues) 或参与 [Discussions](https://www.google.com/search?q=https://github.com/your-username/lt_dialogue/discussions)。
