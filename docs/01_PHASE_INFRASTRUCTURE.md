# 阶段一：工程基建与依赖初始化计划

> **文档编号**：`01_PHASE_INFRASTRUCTURE`  
> **前置依赖**：无  
> **预计成果**：建立能够通过 `flutter pub get` 的工程骨架，包含完整的主题色彩、反馈提示、基础异常与通用 UI 小部件。

---

## 1. 本阶段目标

1. 配置精简且稳定的 Flutter 工程元数据 (`pubspec.yaml`)，剔除原项目中与 Creation / Naila 相关的非必要依赖（如部分专用大型依赖）。
2. 同步基础配置文件（`analysis_options.yaml`、代码样式规则）。
3. 建立 `assets/` 静态资源目录并迁移关键的基础矢量图标。
4. 迁移 `lib/core/` 基础层代码（主题、色彩、间距、圆角、全局反馈与基础组件）。

---

## 2. 待迁移与创建文件清单

### 2.1 根目录与配置文件

| 目标文件 | 源文件 (`~/NarrAItor/`) | 说明 |
| :--- | :--- | :--- |
| `pubspec.yaml` | `pubspec.yaml` | 裁剪后的精简依赖清单，更新项目名为 `lt_dialogue` |
| `analysis_options.yaml` | `analysis_options.yaml` | 静态检查规则 |
| `.gitignore` | `.gitignore` | 标准 Flutter / Dart gitignore |

### 2.2 核心基础层 (`lib/core/`)

| 目标文件 | 源文件 | 关键类与职责 |
| :--- | :--- | :--- |
| `lib/core/theme/app_colors.dart` | `lib/core/theme/app_colors.dart` | 主题主色、强调色、背景色、文字颜色定义 |
| `lib/core/theme/app_spacing.dart` | `lib/core/theme/app_spacing.dart` | 全局标准内边距与间距常量 |
| `lib/core/theme/app_radius.dart` | `lib/core/theme/app_radius.dart` | 标准圆角定义 |
| `lib/core/theme/app_borders.dart` | `lib/core/theme/app_borders.dart` | 边框与阴影常量 |
| `lib/core/theme/app_theme.dart` | `lib/core/theme/app_theme.dart` | ThemeData 浅色与深色主题配置 |
| `lib/core/feedback/app_feedback.dart` | `lib/core/feedback/app_feedback.dart` | 全局 Toast 与 SnackBar 提示（成功、信息、警告、错误） |
| `lib/core/errors/app_operation_exception.dart` | `lib/core/errors/app_operation_exception.dart` | 标准业务异常封装 |
| `lib/core/operations/operation_result.dart` | `lib/core/operations/operation_result.dart` | 通用操作结果返回体 `OperationResult<T>` |
| `lib/core/state/app_view_status.dart` | `lib/core/state/app_view_status.dart` | 通用页面加载/空/错误状态枚举 |
| `lib/core/widgets/app_card.dart` | `lib/core/widgets/app_card.dart` | 基础卡片样式组件 |
| `lib/core/widgets/empty_state_view.dart` | `lib/core/widgets/empty_state_view.dart` | 统一空状态插画与文字展示 |
| `lib/core/widgets/error_state_view.dart` | `lib/core/widgets/error_state_view.dart` | 统一错误重试展示组件 |
| `lib/core/widgets/app_action_button.dart` | `lib/core/widgets/app_action_button.dart` | 常用主操作/次操作按钮封装 |
| `lib/core/widgets/narr_aitor_dropdown.dart` | `lib/core/widgets/narr_aitor_dropdown.dart` | 自定义下拉选择框 |

### 2.3 静态资产 (`assets/`)

| 目标目录 | 源目录 | 说明 |
| :--- | :--- | :--- |
| `assets/icons/` | `assets/icons/` | 应用 UI 界面中使用的 SVG / PNG 状态与类型图标 |

---

## 3. 核心文件设计细节

### 3.1 `pubspec.yaml` 规格

```yaml
name: lt_dialogue
description: AI-driven Scene Dialogue, Resource Library & Settings System
publish_to: 'none'
version: 1.0.0+1

environment:
  sdk: '>=3.0.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter
  # 状态管理
  flutter_riverpod: ^3.3.2
  # 本地持久化与 SQLite
  sqflite: ^2.3.0
  sqflite_common_ffi: ^2.3.0
  path: ^1.9.0
  path_provider: ^2.1.0
  shared_preferences: ^2.2.0
  # 安全加密存储（API 密钥保险库）
  pointycastle: ^4.0.0
  flutter_secure_storage: ^10.2.0
  # 网络与通信
  http: ^1.2.0
  connectivity_plus: ^7.1.1
  # UI 组件与渲染
  google_fonts: ^8.2.1
  flutter_markdown_plus: ^1.0.7
  flutter_svg: ^2.2.2
  # 语音与辅助
  flutter_tts: ^4.2.5
  # 工具类
  equatable: ^2.1.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^3.0.0
  mocktail: ^1.0.5

flutter:
  uses-material-design: true
  assets:
    - assets/
    - assets/icons/
```

---

## 4. 实施步骤

1. **创建基础配置**：
   - 写入目标 `pubspec.yaml`。
   - 复制 `.gitignore` 与 `analysis_options.yaml`。
2. **复制 assets 静态资源**：
   - 创建 `assets/` 与 `assets/icons/` 目录并拷贝图标资源。
3. **复制 core 基础设施层**：
   - 逐个迁移 `theme/`、`feedback/`、`errors/`、`operations/`、`state/`、`widgets/`。
4. **依赖解析与分析**：
   - 执行 `flutter pub get`。
   - 确保 `lib/core/` 内无未声明符号引用。

---

## 5. 验收标准 (Acceptance Criteria)

- [ ] `flutter pub get` 成功执行，所有依赖成功下载且版本无冲突。
- [ ] `lib/core/theme/app_theme.dart` 及其子文件无语法错误。
- [ ] 执行 `git commit -m "feat(infra): setup base flutter project, dependencies, and core theme"` 完成第一阶段归档。
