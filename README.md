# LT Dialogue

[![Release](https://img.shields.io/github/v/release/yangrunzhi345-blip/LT)](https://github.com/yangrunzhi345-blip/LT/releases/latest)
![Flutter](https://img.shields.io/badge/Flutter-app-02569B?logo=flutter)
![Dart](https://img.shields.io/badge/Dart-%3E%3D3.0.0-0175C2?logo=dart)

LT Dialogue 是一个基于 Flutter 的**本地优先 AI 叙事运行时（AI Narrative Runtime）**，用于游玩与创作可长期延续的 AI 文字冒险。它不只生成一段文字，而是围绕**持久世界状态、角色状态演化、结构化剧情副作用、资源库与可控 LLM 上下文**，把每一轮叙事安全地推进到下一轮。

- **AI Adventure**：AI 驱动的互动剧情、分支选项、流式输出与多阶段长文本生成。
- **Resource Library**：世界观、角色卡、NPC、提示词与预设资源的编辑、导入与 AI 生成。
- **Persistent Runtime State**：Adventure 冻结快照 + 分支本地运行态，状态变化可追溯。
- **可控 LLM 上下文**：按相关性筛选世界事实与运行态，而不是把全部设定塞进上下文。
- **多模型与本地优先**：DeepSeek 官方 API 与任意 OpenAI 兼容端点；资产与运行态默认保存在本机。

## 当前版本

| 项目 | 值 |
| --- | --- |
| 应用版本（`pubspec.yaml`） | `1.1.7+10` |
| 最新 GitHub Release | `v1.1.7` |
| 下载 | [Releases / latest](https://github.com/yangrunzhi345-blip/LT/releases/latest) |

## 核心功能

### AI Adventure

- 生成式互动剧情，支持分支行动与多轮推进。
- 流式响应（打字机效果）与 Token 进度反馈。
- 多阶段长文本生成：长篇叙事按幕推进，逐幕累计目标字数。
- 结构化回合输出：正文与结算 JSON（scene / options / 状态变更）分离，JSON 不泄漏进正文。
- 状态更新与选项生成：由模型提出，经本地校验后提交。

### Resource Library

- 世界观、角色卡、NPC、提示词模板、人设化身等资源管理。
- AI 生成与批量导入（含 AI 解析导入）。
- 资源与 Adventure 的**冻结快照边界**：创建 Adventure 后，资料库资产被冻结为不可变基线，剧情推进不会反向修改资料库。

### Persistent Runtime State

Adventure 采用「冻结基线 + 分支本地运行态」模型：

```
Resource Library（原始资产）
        │  创建 Adventure 时冻结
        ▼
Frozen Adventure Baseline
        │  运行时叠加
        ▼
Runtime Overlay  →  Runtime HEAD（当前 revision / commit）
```

- 资料库资源与 Adventure 配置快照是**不可变基线**，叙事输出不会修改它们。
- AI 运行中产生的状态变化写入 **Runtime Overlay**，只记录发生变化的字段。
- 每个 **State Commit** 保留 before / after 值、request ID、上下文快照、assistant 消息引用、原因、父提交与 revision。
- **原子提交**：消息、RPG 效果、SceneState、Runtime Commit、Overlay 与 HEAD 在同一事务中一起写入。
- **冲突与幂等保护**：request ID 让重试保持幂等；expected revision 阻止静默的 last-write-wins。
- **分支本地**：分支只复制当前 HEAD 与 overlay，之后各自分叉；删除分支时保留归档提交以保留来源。

详细设计见 [`docs/adventure_runtime_state.md`](docs/adventure_runtime_state.md)。

### 状态增量协议

回合结算使用 **`custom_status_changes` 增量（Delta）**，而不是每轮完整状态快照：

- 只提交真正发生变化的项，减少上下文膨胀。
- 降低 JSON 泄漏与重复状态风险。
- 由本地合并并校验后落库，模型不能直接写数据库。

### Context & Memory

- `ContextOrchestrator`：统一组织发送给模型的上下文。
- `WorldContextBuilder`：按查询、地点与角色名对世界事实归一化、去重、打分与预算裁剪。
- `RuntimeMemoryProjector`：只投影相关的运行态（当前上限为 **8 个实体 / 600 tokens**）。
- Runtime HEAD 优先于冻结事实；仅当出现明确的历史或因果问题时才启用有界（最多 5 条）的归档查询。

### 输出控制

- `SceneDialogueOutputBudget`：为每个对话层级定义 `minChineseChars` / `targetChineseChars` / `hardMaximum`。
- `NarrativeLengthGuard`：多阶段生成、溢出时安全收敛到段落 / 句子边界、无句界时的硬截断兜底、统一的中文字符计数，并保持正文与结算 JSON 分离。

### 体验与其他

- 本地文本转语音（TTS）与翻译。
- 实时网络状态感知，离线时仍可浏览本地资源。
- 亮 / 暗主题、颜色种子与文字大小自定义。

## Multi-model LLM

- **DeepSeek 官方 API**：默认模型 `deepseek-flash`（DeepSeek V4.1 Flash）。
- **自定义（OpenAI 兼容）**：填入任意兼容端点、模型名与 API Key。
- 模型能力不再靠字符串判断，而由 `ModelCapabilities` / `ModelCapabilityRegistry` 统一描述；旧模型 alias 会自动归一，已淘汰模型仅保留可读、不再出现在选择器中。
- 调用方按任务声明 `LlmTask`，由 Task → Policy 解析 thinking / JSON / Vision 等行为：辅助任务（翻译、导入、抽取、摘要、补正文）恒为非思考；普通 Adventure 叙事默认低延迟非思考，深度推演可由设置开启。
- 视觉输入使用 typed message transport（`LlmMessage` + 图片 part），不再通过序列化 hack 传递。

> 注：注册表中记录的 1M context / 384K output 是**模型能力上限**；LT 当前的业务上下文使用独立的软预算，不会默认占满模型上限。

适配记录见 [`docs/codex/deepseek-v4.1-flash-adaptation.md`](docs/codex/deepseek-v4.1-flash-adaptation.md)（历史适配报告，仅供参考）。

## Runtime 工作方式

```
Resource Library
   → Frozen Adventure Baseline
   → Runtime Overlay
   → Context（WorldContextBuilder + RuntimeMemoryProjector）
   → LLM（Task → Policy → typed transport）
   → Structured State Changes（custom_status_changes）
   → Validation（schema / semantic / revision）
   → Atomic Commit（message + SceneState + RPG + Runtime commit + overlay + HEAD）
   → Next Turn
```

## 下载与安装

### Android

从 [最新 Release](https://github.com/yangrunzhi345-blip/LT/releases/latest) 下载 Android ARM64 APK（`lt-dialogue-v1.1.7-arm64.apk`，约 24 MB）并安装。

安装包大小会随平台与构建配置变化，请以 Releases 中的实际构建产物为准。

### 从源码运行

```bash
git clone https://github.com/yangrunzhi345-blip/LT.git
cd LT
flutter pub get

# 桌面
flutter run -d linux     # 或 -d windows / -d macos

# 移动端
flutter run -d android
flutter run -d ios
```

项目入口为 [`lib/main.dart`](lib/main.dart)。

### 环境要求

- Dart SDK：`>=3.0.0 <4.0.0`（见 `pubspec.yaml`）。
- Flutter：建议使用当前稳定版 Flutter SDK（`pubspec.yaml` 未固定 Flutter 最低版本）。
- 已安装 `git` 与 `flutter` 命令行工具。

## 配置模型

1. 打开**设置中心**。
2. 选择提供商：DeepSeek 官方 API，或自定义 OpenAI 兼容端点。
3. 填入 **API Key**（自定义端点还需 Base URL 与模型名）并保存。

API Key 使用系统安全存储（secure storage）保存。

## 项目结构

```
lib/
├─ application/   # 用例与业务 API（Adventure、LLM、Narrative 上下文等）
├─ config/        # 应用配置与 Prompt 组装
├─ controllers/   # 控制器
├─ core/          # 主题、颜色、圆角等 UI 基础
├─ data/          # 数据层
├─ engines/       # ChatEngine 与内部构件（长度守卫、流处理、Prompt 构建等）
├─ features/      # 面向功能的页面与组件
├─ managers/      # 管理器
├─ models/        # 领域模型（Adventure、模型能力、LLM 消息等）
├─ providers/     # Riverpod 状态
├─ screens/       # 页面
├─ services/      # 数据库、LLM、TTS、翻译、仓库等
├─ utils/         # 通用工具
├─ widgets/       # 公共组件
└─ main.dart      # 入口
```

### 架构说明

```
Flutter UI
    ↓
Providers / Controllers
    ↓
Application / Engines
    ↓
Repositories / Services
    ↓
SQLite + LLM APIs
```

项目正在逐步从早期 Provider / Controller 架构迁移到更明确的 Application / Feature 分层，两套结构当前并存。

## 数据与隐私

- 资产与运行状态通过 SQLite 保存在设备本地；桌面端（Linux / macOS / Windows）使用 `sqflite_common_ffi`，移动端使用 `sqflite`。
- API Key 等敏感信息使用系统安全存储保存。
- 你需要自行配置第三方 LLM API。**当调用云端模型时，必要的上下文会发送到你配置的模型服务商**；本地优先并不代表所有数据永不离开设备。

## 开发与测试

```bash
flutter analyze                              # 静态分析
flutter test                                 # 单元测试 + Widget 测试
flutter test benchmark/core_benchmark.dart   # 性能基准
```

项目使用单元测试、Widget 测试与性能基准覆盖关键的 Adventure、Runtime、LLM 与资源库路径。贡献请遵循 [Effective Dart](.agents/skills/effective-dart/SKILL.md)。

## 文档

- [Adventure Runtime State](docs/adventure_runtime_state.md) — 运行态、分支与上下文设计。
- [DeepSeek V4.1 Flash 适配](docs/codex/deepseek-v4.1-flash-adaptation.md) — 模型能力与任务策略（历史适配报告）。
- [项目文档索引](docs/README.md)。

## 当前边界 / Roadmap

以下能力**尚未实现**，本项目不将其视为已完成：

- 完整 Tool Calling Runtime 与 Responses API runtime。
- Graph DB / Vector DB / Secret Knowledge Graph。
- Checkpoint UI，以及 merge / rebase / cherry-pick / rollback。
- 自主影响分析与完整 Agent Runtime。

LT 当前拥有 Adventure Runtime State 与 typed LLM transport，并为未来的工具调用 / Agent 能力预留了接口。

此外，早期版本中的长篇创作模式（Creation Mode V2）、`CreationAgentRuntime` 与 Naila 助手 / 知识库已经移除。

## License

本仓库当前**未包含 `LICENSE` 文件**。如需转载或商用，请先通过 Issue 与作者确认。
