# LT Dialogue

[English](README.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md) | [日本語](README.ja.md) | [한국어](README.ko.md)

LT Dialogue 是一个使用 Flutter 和 Dart 构建、本地优先的 AI 互动叙事平台。它将结构化资料库、AI 世界观与角色创作，以及有状态的 Adventure 冒险整合在一个应用中。资源、冒险、消息、版本和设置默认保存在设备上的 SQLite 中。

![LT Dialogue 标志](logo.png)

## 核心功能

- **互动冒险**：通过向导选择世界观、主角与同行角色，冻结 NPC 快照，配置序章和行动分支，检查装配就绪状态后启动冒险。运行中支持流式回合、行动选择、分支、角色切换和存档恢复。
- **世界与角色资料**：创建、导入、搜索、筛选和编辑世界观、角色卡与 NPC。资料采用有序的 `Resource → Section → Part` 结构，长篇设定可以复用并保持清晰导航。
- **AI 生成流程**：先创建具备幂等性的创建或导入会话，提供粘贴文本或文件文本，规划并确认蓝图，再由配置的模型生成 Part。结果会校验，失败任务可以恢复或重试，不会静默重复创建资料。
- **Resource Studio**：在集中式编辑器中新增和调整章节，编辑或重试单个 Part，查看流式进度，恢复自动保存草稿，检查版本历史，并发布压缩候选而不自动覆盖当前内容。
- **有状态叙事**：每个冒险独立保存消息、场景状态、角色和 NPC 快照、世界条目、分支、摘要与运行态提交。模型结构化输出必须经过解析、活动版本检查和持久化，才会影响下一回合。
- **阅读支持**：通过平台 TTS 翻译并朗读选中的对话内容。Linux 桌面端会探测 Speech Dispatcher；没有可用语音后端时，朗读入口会保持隐藏。
- **导航优先界面**：在 Adventure、资料库、Resource Studio 和设置之间快速切换。桌面端使用侧栏，紧凑屏幕使用抽屉或底部导航。

## 架构概览

```text
Flutter 页面与 Widget
        ↓
Controller、Riverpod Provider 与应用用例
        ↓
领域契约、引擎、Repository 与模型网关
        ↓
SQLite + 已配置的 OpenAI-compatible 服务 + 平台服务
```

仓库正在逐步整理架构。新的 `features/`、`application/`、`domain/` 与既有目录并存；README 不把某个目录宣称为完整架构。

## AI 生成系统

LT 直接连接你配置的 OpenAI-compatible 模型服务。你可以在设置中选择 Base URL、模型和 API Key；密钥通过应用的安全存储路径保存在本地。资源创建和导入支持手动输入、粘贴或文件文本、已有资源、规划会话、结构化蓝图、流式生成、校验和恢复。

冒险响应包含叙事正文和结构化状态数据。应用会在写入本地数据库或进入下一回合前校验结构化结果。

## 角色与世界

资源模型为：

```text
Resource → Section → Part
```

世界观保存规则、地点和势力等设定；角色卡和 NPC 保存可复用的人物资料与关系。冒险启动时会生成冒险自己的快照，之后资料库编辑不会静默改写已有冒险。

## 资料库与阅读体验

资料库支持搜索、类型筛选、详情、手动编辑、AI 创建、导入、自动保存、草稿恢复、版本历史、回收站、容量检查和压缩候选。Resource Studio 提供章节与 Part 的集中编辑和生成工作区。

Adventure 支持流式输出、可选 reasoning、行动选项、分支、书签、角色切换、骰点、消息编辑、上下文摘要、对话导入导出、翻译和朗读。

## 多语言支持

当前 UI 支持 English、简体中文、繁體中文、日本語和한국어。翻译文件位于 [`lib/l10n/`](lib/l10n/)，首次启动和设置中都可以切换语言。

## 截图

仓库目前没有提交 UI 截图；上方为已跟踪的项目标志。稳定的截图集合准备好后再补充。

## 安装与运行

需要 Git、Flutter stable（Dart `>=3.0.0 <4.0.0`）以及目标平台工具链。

```bash
git clone https://github.com/yangrunzhi345-blip/LT.git
cd LT
flutter pub get
flutter devices
flutter run -d linux       # 或 windows / macos
# flutter run -d android
# flutter run -d ios
```

首次启动后在设置中配置 DeepSeek 或其他 OpenAI-compatible 服务。支持的产品平台为 Linux、Windows、Android、macOS 和 iOS。

## 开发

```bash
dart format .
flutter analyze
flutter test
flutter test benchmark/core_benchmark.dart
```

入口文件包括 [`lib/main.dart`](lib/main.dart)、[`lib/core/router/app_router.dart`](lib/core/router/app_router.dart) 和 [`docs/README.md`](docs/README.md)。

## 路线图

项目将继续改进资料创作、Adventure 运行态、恢复行为和跨平台体验。通用 tool-calling agent、图数据库或向量数据库、跨资源自主决策目前不属于已交付功能。

## 贡献

欢迎小范围、聚焦的 Pull Request。请说明行为变化，保护用户数据和凭证，随代码同步更新文档，并运行相关格式化、分析和测试。

## 许可证

仓库当前没有根目录 `LICENSE` 文件。重新分发或商业使用前，请通过 GitHub 联系项目所有者。
