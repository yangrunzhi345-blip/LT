# LT Dialogue

![项目截图](https://raw.githubusercontent.com/your-repo/lt_dialogue/main/docs/screenshot.png)

## 项目简介

**LT Dialogue** 是一款基于 Flutter 与 Riverpod 开发的 AI 驱动文字冒险与对话编辑器。它集成了多模型（DeepSeek、OpenAI、Custom）支持，提供场景生成、角色卡、世界观管理以及实时聊天功能，帮助创作者快速构建沉浸式文字冒险。

- **跨平台**：支持 Android、iOS、macOS、Windows、Linux
- **实时对话**：流式 LLM 输出，配合 Token 进度条
- **完整资源库**：角色卡、提示词预设、世界观预设一键管理
- **高度可定制**：系统提示、作者注释、对话层级、模型参数均可调

## 关键特性

- 🎮 **冒险管理**：创建、分支、保存、导入/导出 JSONL、Markdown、HTML
- 📚 **资源库**：角色卡、人物设定、世界观、提示词预设的增删改查
- 🤖 **多模型支持**：DeepSeek、OpenAI、Custom，支持自定义端点
- 🌈 **主题&配色**：支持亮暗主题、颜色种子、文字大小自定义
- 🔊 **文字转语音** 与 **翻译**：内置 TTS 与翻译服务
- 📶 **离线感知**：实时网络状态监控，自动切换在线/离线模式
- 🛠️ **细粒度 UI 重建**：基于 `ValueNotifier` 的局部刷新，性能卓越

## 快速开始

### 环境要求

- Flutter SDK >= 3.22.0
- Dart >= 3.0.0 < 4.0.0
- 已安装 `git` 与 `flutter` 命令行工具

### 克隆仓库 & 获取依赖

```bash
git clone https://github.com/your-username/lt_dialogue.git
cd lt_dialogue
flutter pub get
```

### 运行示例

```bash
# 在桌面平台（macOS/Windows/Linux）
flutter run -d macos   # 或 -d windows / -d linux

# 在移动设备
flutter run -d android
flutter run -d ios
```

> 项目入口文件：[`main.dart`](file:///home/yrz/LT/lib/main.dart)

### 配置 LLM API Key

1. 打开 **设置** 页面（Settings Center）
2. 选择模型提供商（如 DeepSeek）
3. 输入对应的 **API Key** 并保存

系统会自动加密存储并在启动时加载。

## 项目结构

```
lt_dialogue/
├─ lib/
│  ├─ application/          # 业务层 API（Adventure, LLM, PromptPolicy 等）
│  ├─ core/                 # 主题、颜色、半径等 UI 基础
│  ├─ models/               # 数据模型（AdventureConfig, Message, Worldview 等）
│  ├─ providers/            # 全局状态中心（ChatProvider, SettingsProvider …）
│  ├─ screens/              # 各页面 UI（Landing, Chat, ResourceLibrary …）
│  ├─ services/             # 本地数据库、LLM 调用、TTS、翻译等服务实现
│  └─ widgets/              # 公共 UI 组件（侧边栏、弹窗、气泡等）
├─ test/                     # 单元/Widget 测试
├─ assets/                   # 静态资源（图标、图片）
├─ pubspec.yaml              # Flutter 配置与依赖声明
└─ README.md                 # 本文件
```

## 运行原理概览

- **入口**：`main.dart` → `ProviderScope` → `_AppRoot` → `MainGate`
- **全局状态**：`ChatProvider` 组合 `SettingsProvider`, `AdventureProvider`, `LibraryProvider`, `MessagingProvider`
- **细粒度刷新**：`tokenVersion`, `stateVersion`, `titleBarVersion`, `themeVersion` 等 `ValueNotifier` 驱动局部 UI 更新
- **LLM 调用**：`SettingsProvider.getOrCreateLlm()` 产生 `LLMService`，通过 `MessagingProvider` 发起流式请求
- **持久化**：`DatabaseService` 使用 `sqflite_common_ffi` 在所有平台统一管理 SQLite 数据库

## 贡献指南

1. Fork 本仓库
2. 创建 feature 分支
3. 编写或修改代码后添加对应测试
4. 提交 Pull Request，遵守 **Effective Dart** 代码风格

> 代码规范参考：[`effective-dart` skill](./.agents/skills/effective-dart/SKILL.md)

## 常见问题 FAQ

- **如何切换模型？** 在设置页面选择不同的 `LLMProvider`，系统会自动加载对应的模型与端点。
- **离线时还能使用吗？** 离线模式下 UI 仍可浏览已缓存的资源库，发送消息会提示网络不可用。
- **项目体积大吗？** 基础包约 80 MB（包含 Flutter 引擎），实际运行时根据平台会有所不同。

## 许可证

本项目采用 **MIT License**，详见 [LICENSE](LICENSE)。

---

🌟 如果你觉得项目有价值，请给我们点个 Star，或在 Issues 中提出你的想法！祝你创作愉快 🎉
