# LT Dialogue

[![Flutter](https://img.shields.io/badge/Flutter-app-02569B?logo=flutter)](https://flutter.dev/) [![Latest release](https://img.shields.io/github/v/release/yangrunzhi345-blip/LT)](https://github.com/yangrunzhi345-blip/LT/releases/latest)

[English](README.md) | [简体中文](README.zh-CN.md)

LT Dialogue 是一个本地优先的 AI 互动叙事、世界观与角色创作工作台。

创建可复用的资料，从资源快照启动 Adventure 冒险，在阅读故事的同时查看角色和世界状态的变化。LT 使用 Flutter、Dart、Riverpod 和 SQLite。

![LT Dialogue 标志](logo.png)

## 核心功能

- 支持流式回合、行动选择、分支与保存会话恢复的互动冒险。
- 可搜索的 Resource Library 资料库，支持世界观、角色卡与 NPC 的手动编辑与单次 AI 起草。
- 角色关系从资料库进入冒险，在运行中变化并参与叙事上下文。
- Runtime State Hub 提供仪表盘、实体状态、时间线与逐回合变化。
- 翻译与系统朗读，适用于对话与资源正文。
- 响应式导航：桌面侧栏含最近冒险，小屏使用紧凑导航；可进入 Adventure、资料库、运行态与设置。

## 互动冒险

通过创建向导选择世界观、主角、同行角色与 NPC，配置开场并检查就绪状态。选中的资源形成冒险独有的快照，后续资料库编辑不会静默改写已有冒险。

运行中支持流式叙事、行动选择、创建分支、切换当前角色，以及恢复保存的会话。书签、消息编辑、骰点、对话导入导出和上下文摘要为长篇故事提供辅助。

## 资料库

创建、编辑、搜索、筛选、排序与删除世界观、角色卡与 NPC。每份资料都是一张设定卡：一份可编辑文档，包含名称、摘要、状态与正文。编辑器直接写入整份文档，AI 草稿渲染进同一份文档，可在此基础上继续编辑。

从旧版资料库迁移的卡片会读取一次旧表并写入设定卡，旧表保持原样。删除卡片会将其从资料库移除。

角色卡与 NPC 卡关联冒险向导和运行态中心读取的关系与追踪状态定义。

## 角色、关系与运行态

在资料库中管理角色关系，在创建向导起草新角色时可关联已有角色。选中角色之间的关系可以复制到冒险快照，在运行中继续变化。当前关系状态进入叙事上下文及其加权 Token 预算规划，因此相关变化可以影响后续 AI 叙事。后续资料库关系编辑不会静默改变这份快照。

当前冒险的 Runtime State Hub 提供仪表盘、角色与世界状态、地点、势力、关系、追踪状态、时间线和回合历史。可结合故事查看已记录的变化与实体历史。

## AI 辅助创作

配置 OpenAI-compatible 服务地址、模型与 API Key。资料库可以按简短指令起草世界观、角色卡或 NPC。起草是每张卡一次操作：模型返回的结构化结果会渲染为卡片正文，你可以在此基础上继续编辑。

冒险生成在上下文预算内组装资源快照、近期叙事、摘要和运行态。结构化状态输出经解析和校验后，接受的变化才会持久化并用于后续回合。

## 朗读

朗读使用平台系统语音引擎。设置中提供启用、自动朗读、语速、音调与语言。

Linux 系统朗读使用可用的 Speech Dispatcher。对话翻译由已配置的文本模型完成，与朗读相互独立。

## 本地优先架构

设定卡、冒险、消息与应用设置主要持久化在本地 SQLite。操作系统提供凭证库时 API Key 保存在平台凭证库，并以应用层加密的 SQLite 记录作为回退；这不表示整个数据库已加密。

设定卡存放在 `setting_cards` 表。启动冒险时会把选中卡片冻结为冒险快照，之后的卡片编辑不会改写正在进行的冒险。更早版本使用的资源表仅为兼容而保留：迁移时读取一次，之后不再驱动当前资料库。

AI 文本生成与翻译会向你配置的服务发送所需上下文，该服务可能位于远端。本地优先存储不代表所有 AI 功能都能离线运行。

## 多语言支持

UI 支持 English 与简体中文。首次启动或设置中可选择语言。翻译源文件位于 [`lib/l10n/`](lib/l10n/)。

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
