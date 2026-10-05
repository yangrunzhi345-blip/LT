# LT Dialogue

[![Flutter](https://img.shields.io/badge/Flutter-app-02569B?logo=flutter)](https://flutter.dev/) [![Latest release](https://img.shields.io/github/v/release/yangrunzhi345-blip/LT)](https://github.com/yangrunzhi345-blip/LT/releases/latest)

[English](README.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md) | [日本語](README.ja.md) | [한국어](README.ko.md)

LT Dialogue 是一个本地优先的 AI 互动叙事、世界观与角色创作工作台。

创建可复用的资料，从资源快照启动 Adventure 冒险，在阅读故事的同时查看角色和世界状态的变化。LT 使用 Flutter、Dart、Riverpod 和 SQLite。

![LT Dialogue 标志](logo.png)

## 核心功能

- 支持流式回合、行动选择、分支与保存会话恢复的互动冒险。
- 可搜索的 Resource Library 资料库，以及支持结构化编辑和 AI 生成的 Resource Studio。
- 角色关系从资料库进入冒险，在运行中变化并参与叙事上下文。
- Runtime State Hub 提供仪表盘、实体状态、时间线与逐回合变化。
- 翻译与朗读，包括需下载模型的可选本地神经 TTS。
- 响应式导航：桌面侧栏含最近冒险，小屏使用紧凑导航；可进入 Adventure、资料库、运行态与设置。

## 互动冒险

通过创建向导选择世界观、主角、同行角色与 NPC，配置开场并检查就绪状态。选中的资源形成冒险独有的快照，后续资料库编辑不会静默改写已有冒险。

运行中支持流式叙事、行动选择、创建分支、切换当前角色，以及恢复保存的会话。书签、消息编辑、骰点、对话导入导出和上下文摘要为长篇故事提供辅助。

## 资料库与 Resource Studio

创建、导入、搜索、筛选和管理世界观、角色卡与 NPC。资源采用有序的 `Resource → Section → Part` 结构。

Resource Studio 提供章节新增与排序、Part 编辑、流式生成、手动保存、自动保存和草稿恢复。可重试单个失败 Part 或全部失败 Part，查看版本历史并恢复版本。校验与就绪状态帮助判断资源能否用于冒险。

容量工具支持查看资源大小、生成压缩候选，经审阅后显式发布；压缩不会自动替换当前内容。资料库还提供回收站与恢复。

## 角色、关系与运行态

在资料库中管理角色关系，并基于已有角色生成关联角色。选中角色之间的关系可以复制到冒险快照，在运行中继续变化。当前关系状态进入叙事上下文及其加权 Token 预算规划，因此相关变化可以影响后续 AI 叙事。后续资料库关系编辑不会静默改变这份快照。

当前冒险的 Runtime State Hub 提供仪表盘、角色与世界状态、地点、势力、关系、追踪状态、时间线和回合历史。可结合故事查看已记录的变化与实体历史。

## AI 生成流程

配置 OpenAI-compatible 服务地址、模型与 API Key。资源创建与导入经过规划、蓝图、候选确认、Part 流式生成及校验，失败任务支持恢复和重试。不同流程可使用手动输入、粘贴文本、文件文本参考或已有资源。

冒险生成在上下文预算内组装资源快照、近期叙事、摘要和运行态。结构化状态输出经解析和校验后，接受的变化才会持久化并用于后续回合。

## 朗读与本地神经 TTS

默认使用系统 TTS。Enhanced / Neural TTS 为可选模式，使用 Sherpa/ONNX 在设备上合成语音。神经模型不随 APK 内置，也不会自动下载；需在设置 → 朗读 → 模型管理中主动下载。模型管理显示安装状态、下载进度和磁盘占用，支持取消下载与移除模型。

可选择旁白与默认角色声音，启用角色声音自动分配，或在角色/NPC 资源详情中绑定声音。可用声音和语言取决于已安装模型。神经声音、模型或运行环境不可用时，若存在可用系统后端，会回退到系统 TTS。

Linux 系统朗读使用可用的 Speech Dispatcher。对话翻译由已配置的文本模型完成，与 TTS 相互独立。

## 本地优先架构

资源、冒险、消息、版本与应用设置主要持久化在本地 SQLite。API Key 使用应用层加密后保存在本地；这不表示整个数据库已加密，也不表示密钥保存在操作系统凭证库中。

AI 文本生成与翻译会向你配置的服务发送所需上下文，该服务可能位于远端。神经模型下载需要网络，安装后的神经 TTS 模型可在本地合成语音。本地优先存储不代表所有 AI 功能都能离线运行。

## 多语言支持

UI 支持 English、简体中文、繁體中文、日本語与 한국어。首次启动或设置中可选择语言。翻译源文件位于 [`lib/l10n/`](lib/l10n/)。

## 安装

### 下载 Android Release

从 [Latest Release](https://github.com/yangrunzhi345-blip/LT/releases/latest) 下载正式签名 APK。当前官方预编译发行仅提供 **Android ARM64 / arm64-v8a**。此发行流程目前不提供 Windows、Linux、macOS 或 iOS 安装包。

各版本详情及签名、升级说明见 [`docs/releases/`](docs/releases/)。从较旧的 Debug 签名版本迁移时，若 Android 签名规则要求卸载，请先备份或导出数据。

### 从源码运行

仓库包含 Android、Linux、Windows、macOS 和 iOS 平台工程，供源码开发使用；仍需对应工具链，服务可用性也因平台而异。当前 Android 配置将原生库限制为 ARM64。

需要 Git、Flutter stable 与目标平台原生工具链。`pubspec.yaml` 声明 Dart `>=3.0.0 <4.0.0`，但当前 [`pubspec.lock`](pubspec.lock) 要求 **Flutter >=3.44.0、Dart >=3.12.0 <4.0.0**。本次检查使用 Flutter 3.44.8 / Dart 3.12.2。

```bash
git clone https://github.com/yangrunzhi345-blip/LT.git
cd LT
flutter pub get
flutter run
```

需要指定目标时，先用 `flutter devices` 查看设备，再执行 `flutter run -d <device-id>`。AI 生成前，在首次启动流程或设置中配置模型服务。

## 开发

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

开发时优先运行定向测试；仓库 CI 检查格式、静态分析与 Flutter 测试。仓库工作规范见 [`AGENTS.md`](AGENTS.md)。

## 项目结构

- [`lib/features/`](lib/features/)：功能 UI 及相关功能代码。
- [`lib/application/`](lib/application/)：用例、叙事上下文与流程编排。
- [`lib/domain/`](lib/domain/)：领域契约与模型。
- [`lib/services/`](lib/services/)：持久化、Repository、模型访问与 TTS。
- [`lib/core/`](lib/core/)：共享路由、主题与 UI 基础。
- [`test/`](test/)：自动化测试；[`docs/`](docs/)：实现与开发文档。

既有 Controller、Provider、Screen 与 Widget 目录仍与上述边界并存。从 [`lib/main.dart`](lib/main.dart) 开始，更多说明见[文档索引](docs/README.md)。

## 路线图

后续工作聚焦资料创作、冒险状态工具、恢复能力与跨平台体验。这些是持续改进方向，不是额外已交付能力。

## 贡献

欢迎聚焦的 Pull Request。请说明行为变化，保护用户数据和凭证，更新相关文档，并在发起 PR 前运行必要检查。

## 许可证

仓库当前没有根目录 `LICENSE` 文件。重新分发或商业使用前，请通过 GitHub 联系项目所有者。
