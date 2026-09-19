---
name: lt-ui-refactor
description: >
  LT / LT Dialogue 专用 Flutter UI/UX 重构规范。
  用于界面设计、响应式布局、移动端适配、导航重构、
  Adventure Dashboard、Adventure Session、资料库、设置页、
  Wizard、Theme、Widget 和视觉系统调整。
  核心目标是建立高级、克制、沉浸、内容优先的叙事产品 UI，
  去除 ChatGPT / Claude 式 AI 产品视觉，并保证手机、平板和桌面均可用。
---

# LT UI Refactor Skill

## 0. 适用范围

本 Skill 仅针对 LT 项目的前端、UI、UX、响应式布局与 Presentation 层重构。

主要适用于：

- Flutter Widget
- Material 3 Theme
- Design Token
- 响应式布局
- 手机端适配
- 平板适配
- 桌面适配
- Navigation
- Sidebar
- Bottom Navigation
- NavigationRail
- AppBar
- Adventure Dashboard
- Adventure Session
- Resource Library
- Settings
- Adventure Wizard
- Dialog
- BottomSheet
- Form
- Input
- Empty / Loading / Error State
- Widget Test
- UI Regression Test

本 Skill 不授权主动重构：

- Adventure Runtime State
- LLM Engine
- Prompt System
- Context System
- Memory System
- SQLite Schema
- Repository
- Domain Model
- Application Service
- 网络层
- 模型适配层

除非用户任务明确要求。

---

# 1. 项目身份

项目：

```text
LT / LT Dialogue
```

Repository：

```text
yangrunzhi345-blip/LT
```

技术栈：

```text
Flutter
Dart
Riverpod
SQLite
Material 3
```

主要目标平台：

```text
Android
Linux
Windows
macOS
iOS
```

LT 不是一个通用 AI Chat Client。

LT 的产品定位应理解为：

> 一个以世界、角色、场景、持续状态和互动叙事为核心的
> 本地优先 Narrative Runtime / Interactive Story Workspace。

UI 的核心对象首先是：

```text
故事
世界
角色
场景
关系
状态
存档
用户行为
```

AI / LLM 只是底层能力。

不要让 AI 成为视觉主体。

---

# 2. 开始任务前必须执行

任何 UI / Frontend 任务开始前，必须先执行：

```bash
git status --short
git branch --show-current
git log --oneline -10
```

然后必须阅读：

```text
AGENTS.md
```

如果存在与当前 Agent 相关的专属规则文件，也必须阅读。

例如：

```text
CODEBUDDY.md
```

代码是当前事实来源。

如果以下内容发生冲突：

```text
旧 Prompt
旧文档
旧 UI 计划
历史聊天
本 Skill
当前代码
AGENTS.md
```

优先级为：

```text
AGENTS.md
↓
当前 main 代码
↓
当前测试与架构约束
↓
本 Skill
↓
任务文档
↓
旧文档 / 旧 Prompt
```

禁止根据历史版本的路径直接修改代码。

必须先搜索当前正式实现。

---

# 3. 默认工作流程

收到 UI 任务后，不要立即开始写代码。

严格遵循：

```text
Inspect
↓
Understand
↓
Search Existing Components
↓
Inspect Responsive Behavior
↓
Identify Root Cause
↓
Design Minimal Change
↓
Implement
↓
Test Compact Viewport
↓
Test Desktop
↓
Analyze
↓
Review Diff
↓
Commit
```

复杂 UI 重构优先先输出计划。

禁止“大爆炸式”一次性改完整个前端。

---

# 4. 当前架构原则

LT 已经建立 Presentation / Domain / Infrastructure 方向约束。

UI 重构必须保护当前架构边界。

主要 UI 目录包括：

```text
lib/main.dart

lib/widgets/

lib/core/theme/
lib/core/widgets/

lib/features/adventure/presentation/
lib/features/resource_library/presentation/
lib/features/settings/presentation/
```

当前 Adventure 首页正式入口：

```text
AdventureDashboardScreen
```

当前 Adventure Session 正式入口：

```text
AdventureSessionScreen
```

当前资料库正式入口：

```text
ResourceLibraryScreen
```

设置区域以当前实际代码中的：

```text
SettingsScreen
SettingsCenterScreen
```

及相关 Feature Presentation 实现为准。

每次修改前都必须搜索实际调用链。

---

# 5. 已删除旧 UI 禁止复活

当前仓库已经清理一批不可达、旧架构或兼容层 UI。

UI 重构不得因为“方便”重新建立相同旧实现。

特别禁止主动恢复：

```text
screens/chat_screen.dart

screens/adventure_builder.dart

screens/adventure_mode_screen.dart

ActionOptionsPanel

resource_library/template_tab.dart

worldview_editor_screen.dart

controllers/home_screen_controller.dart

chat/widgets/ai_generate_section.dart

chat/widgets/worldbook_screen.dart
```

以及其他已经被当前 Feature Presentation 层替代的旧代码。

如果旧文档仍然引用这些文件：

```text
不要恢复。
不要复制。
不要建立 compatibility facade。
```

应该先找到当前正式实现。

---

# 6. Presentation 架构边界

以下路径：

```text
lib/features/**/presentation/**
```

不得为了 UI 开发方便而随意直接依赖：

```text
services/
engines/
managers/
data/
```

如果当前 architecture test 存在明确 file-exact allowlist：

只能遵守已有例外。

不得新增新的跨层依赖来绕过架构。

Presentation 获取业务能力的优先顺序：

```text
现有 Provider
↓
现有 Controller
↓
Application Use Case
↓
已有 abstraction
↓
必要时设计新的正式边界
```

禁止 UI 直接伸手访问 Infrastructure。

---

# 7. Domain Model 禁止承担视觉职责

Domain Model 不应包含：

```dart
Color
IconData
Widget
BuildContext
ThemeData
Material API
```

也不要为了 UI 方便让 Model import：

```text
flutter/material.dart
flutter/widgets.dart
dart:ui
core/theme
presentation
screens
widgets
```

视觉映射应放在：

```text
core/theme/
presentation/
UI-specific extension
```

中。

UI 重构不能把已经分离出去的视觉职责重新塞回 Model。

---

# 8. LT UI 的最终设计方向

目标设计语言：

```text
Editorial Narrative Workspace
```

关键词：

```text
克制
高级
沉浸
内容优先
编辑感
档案感
叙事感
轻游戏化
低干扰
结构清晰
```

可以吸收：

```text
阅读器
编辑器
知识管理工具
世界档案系统
互动小说
RPG 状态系统
```

的信息组织经验。

不要复制任何一个具体产品。

---

# 9. LT 不应该是什么

不要把 LT 设计成：

```text
ChatGPT Clone
Claude Clone
通用 AI Dashboard
AI SaaS Dashboard
AI Playground
LLM Client
聊天软件 + RPG 按钮
```

最终产品气质应该更接近：

```text
Narrative Workspace
+
Interactive Novel
+
World / Character Archive
+
Persistent RPG Runtime
```

---

# 10. 去除 AI 味

以下视觉元素应逐步减少：

```text
auto_awesome
sparkle
星星图标
AI 发光效果
紫蓝渐变
彩色 Glow
渐变 Logo Box
AI 状态胶囊
模型状态常驻
Token 常驻
大量 AI 文案
```

不要把：

```text
AI
LLM
模型
智能
生成
Provider
API
Token
```

长期放在一级视觉层。

AI 能力应该隐藏在用户体验之后。

正确原则：

> 正常情况下，用户不需要不断被提醒“这是 AI”。

例如：

模型连接正常：

```text
不要长期占据首页空间显示 DeepSeek / Model / Online。
```

模型连接异常：

```text
可以显示“服务不可用”
并提供设置入口。
```

状态异常才需要成为视觉信息。

---

# 11. 禁止 AI Generated UI 套路

不要默认创建以下结构：

```text
大圆角 Card
+
彩色 Icon Container
+
Badge
+
Title
+
Description
+
Arrow
+
Hover Shadow
```

然后重复四五次。

不要依靠：

```text
gradient
glow
glassmorphism
shadow
colorful outline
大量 Container
大量彩色 Badge
```

制造所谓高级感。

高级感首先来自：

```text
信息架构
排版
留白
对齐
字体
内容密度
层级
一致性
交互节奏
```

核心原则：

> 减少容器，增加层级。

---

# 12. Content First

LT 一级页面首先应该展示：

```text
用户的故事
用户的世界
用户的角色
用户的存档
当前正在进行的 Adventure
```

而不是：

```text
软件有哪些功能
支持哪些模型
有哪些 AI 能力
有哪些配置入口
```

每次设计首页时必须问：

> 用户打开 LT 第一眼看到的是自己的内容，还是软件功能？

默认应该是前者。

---

# 13. Typography

优先继承 LT 已有字体体系。

当前方向：

```text
Noto Serif SC
Noto Sans SC
```

总体适合 LT。

推荐：

衬线字体用于：

```text
故事标题
章节标题
世界名称
页面大标题
Editorial Heading
```

无衬线字体用于：

```text
正文
UI 控件
输入框
状态
设置
标签
数据
表单
```

不要无必要增加字体种类。

禁止：

```text
所有标题都超粗
所有标题都 w800
小字堆满页面
用缩小字体解决 overflow
```

优先建立清晰 Typography Hierarchy。

---

# 14. 字体层级原则

建议保持明确层级：

```text
Display
Page Title
Section Title
Item Title
Body
Secondary Body
Label
Metadata
```

不要让：

```text
标题
说明
状态
标签
按钮
```

全部看起来一样重。

正文以舒适阅读为第一目标。

Adventure Narrative 尤其要保持：

```text
合理行高
合理段间距
稳定阅读宽度
低视觉噪声
```

---

# 15. Color System

颜色必须有语义。

主要颜色层级：

```text
Background
Surface
Elevated Surface
Primary Text
Secondary Text
Divider
Primary Accent
Error
Warning
Success
```

普通页面尽量控制为：

```text
中性背景
+
一种品牌强调色
+
必要状态色
```

不要让不同功能入口同时使用：

```text
蓝
绿
橙
紫
粉
青
```

争抢注意力。

颜色主要用于：

```text
选择状态
操作重点
警告
失败
成功
必要的 RPG 状态
```

而不是单纯为了“酷”。

---

# 16. 深色模式

Dark Mode 不是：

```text
纯黑背景
+
高饱和霓虹色
```

LT 深色方向建议：

```text
炭黑
石墨灰
暖灰
低饱和 Accent
柔和高对比文字
```

Adventure Session 深色模式应适合长时间阅读。

禁止大面积纯白文字直接压纯黑背景造成疲劳。

---

# 17. Radius

不要依赖“大圆角 = 现代”。

建议语义区间：

```text
Small
6–8

Medium
10–12

Large
14–16

Pill
仅用于真正适合胶囊形态的元素
```

避免普通 Container 大量使用：

```text
20
24
28
32
```

圆角。

---

# 18. Border

Border 用于结构，不用于装饰。

优先：

```text
低对比 Divider
轻 Outline
Surface 差异
```

不要每个 Card 都使用明显彩色 Border。

Selected 状态可以适当增强。

Normal 状态应克制。

---

# 19. Shadow

默认尽量弱化 Shadow。

优先通过：

```text
Surface
Spacing
Divider
Typography
```

表达层级。

Hover 可以采用：

```text
轻微 Surface Change
Border Change
1–2px Movement
```

不要默认：

```text
彩色 Glow
大 Blur
强阴影
浮空 SaaS Card
```

---

# 20. Material 3

继续使用 Material 3 作为基础能力。

但：

> Material 3 是基础工具，不是 LT 的最终产品视觉身份。

不要因为 Flutter 提供某个 Material Component 就机械使用。

应该通过 Theme 和 Component Layer 建立 LT 自己的：

```text
Typography
Spacing
Radius
Surface
Navigation
Button Hierarchy
Input Hierarchy
State Hierarchy
```

---

# 21. Design Token 优先

新增视觉数值前必须先检查：

```text
lib/core/theme/
```

以及现有：

```text
AppSpacing
AppRadius
AppColors
AppTheme
```

能复用则复用。

如果出现很多页面分别写：

```dart
12
14
16
18
20
24
```

来表达相同视觉规则：

应考虑收敛到 Token。

但禁止为了“架构漂亮”过度抽象。

---

# 22. Mobile First

LT 必须真正 Mobile First。

手机不是缩小的 Desktop。

任何新增或修改页面至少首先验证：

```text
320 px
360 px
390 px
412 px
```

然后验证：

```text
768 px
1024 px+
```

其中：

```text
320 px
```

是最低兼容逻辑宽度硬门槛。

任何 UI 修改：

> 320px 下不得产生横向 RenderFlex Overflow。

---

# 23. 页面级响应式断点

默认使用项目统一页面级断点：

```text
< 600
Mobile / Compact

600–899
Tablet / Compact Desktop

>= 900
Desktop
```

不要继续散落无解释断点：

```text
537
643
721
783
867
```

如果组件确实需要特殊布局切换：

优先基于自身实际空间。

---

# 24. 组件级响应式

组件内部优先：

```dart
LayoutBuilder
```

读取：

```dart
constraints.maxWidth
```

根据真实父级可用空间决策。

不要所有 Widget 都依赖：

```dart
MediaQuery.sizeOf(context).width
```

因为组件可能位于：

```text
Sidebar 旁
Dialog 中
BottomSheet 中
Master / Detail 中
窄桌面窗口中
```

屏幕宽度不等于组件宽度。

---

# 25. 禁止散落 Magic Breakpoint

如果确实需要特殊断点：

必须满足：

```text
1. 有明确布局原因
2. 基于实际组件结构
3. 写明原因
4. 不与统一页面断点重复表达同一概念
```

不要仅因为“这里看起来差一点”就写：

```dart
if (width < 713)
```

---

# 26. Adaptive Navigation

全局导航不能长期只有：

```text
Desktop Sidebar
Mobile Drawer
```

应该按照设备形态重新设计。

推荐：

```text
Mobile
Bottom Navigation / Full-page Navigation

Tablet
NavigationRail / Compact Sidebar

Desktop
Persistent Sidebar
```

---

# 27. Mobile 全局导航

普通一级页面建议使用：

```text
Top App Bar
Content
Bottom Navigation
```

一级入口保持少量。

例如：

```text
探索
资料库
设置
```

Drawer 可以保留为：

```text
补充导航
历史
高级入口
```

但不要让 Drawer 成为手机唯一一级导航方式。

核心原因：

> Drawer 的导航入口不可见，不适合作为手机唯一核心 IA。

---

# 28. Tablet 导航

600–899px 不应该完全等于 Mobile。

根据空间可以使用：

```text
NavigationRail
Compact Sidebar
Master / Detail
Two-pane Layout
```

但必须根据具体页面决定。

平板不是：

```text
手机放大版
```

也不是：

```text
桌面缩小版
```

---

# 29. Desktop 导航

Desktop 可以使用：

```text
Persistent Sidebar
+
Content Workspace
```

Sidebar 应保持克制。

推荐结构：

```text
LT

+ 新建冒险

探索
资料库

最近
────────
Adventure A
Adventure B
Adventure C

────────
设置
```

避免常驻：

```text
Provider
Model Name
Token Count
API Status
复杂技术状态
```

正常服务无需长期抢占空间。

---

# 30. Sidebar 原则

Sidebar 的职责主要是：

```text
导航
最近内容
快速新建
设置入口
```

不是：

```text
品牌广告位
AI 状态面板
模型监控器
系统 Dashboard
```

Sidebar 收起状态必须保持：

```text
可理解
可操作
可恢复
```

不能只剩一堆没有明确语义的 Icon。

---

# 31. Adventure Dashboard

首页不应该首先展示：

> 软件有哪些功能。

首页应该首先回答：

```text
我上次在哪里？
我可以继续什么？
我最近创建了什么？
我有哪些世界？
我有哪些角色？
```

优先级建议：

```text
继续最近 Adventure

开始新 Adventure

最近世界

最近角色

最近存档
```

弱化：

```text
API
Provider
模型
技术说明
功能宣传
```

---

# 32. Dashboard 信息架构

移动端首页可以接近：

```text
灵境

继续故事
────────────────
暮色边境
第三章 · 旧港
             继续 →

开始
新建冒险

最近的世界
────────────────
世界 A
世界 B

最近的角色
────────────────
角色 A
角色 B
```

不是必须照抄。

核心是：

> Content First。

---

# 33. Dashboard Card 使用规则

不是所有东西都必须 Card。

可使用：

```text
Section
List
Editorial Row
Grid
Divider
Thumbnail
Typography
Whitespace
```

表达层级。

Card 只用于确实属于：

```text
独立对象
独立交互单元
明确内容实体
```

的区域。

不要把：

```text
新建
资料库
设置
世界
角色
继续
```

全部做成彩色大卡片。

---

# 34. Adventure Session 是特殊模式

进入 Adventure Session 后：

不要机械保留普通页面 Bottom Navigation。

Session 是沉浸式模式。

空间优先给：

```text
剧情
场景
角色
状态
输入行动
```

目标体验：

```text
Interactive Novel
+
RPG Session
```

不是：

```text
AI Chat Window
```

---

# 35. Adventure Session 移动端结构

推荐视觉方向：

```text
┌──────────────────────┐
│ ‹  场景名称        ⋯ │
│ 地点 · HP · MP       │
├──────────────────────┤
│                      │
│                      │
│      Narrative       │
│                      │
│                      │
├──────────────────────┤
│ +  描述你的行动... ↑ │
└──────────────────────┘
```

具体实现必须结合现有组件和状态。

不要为了追求图示而破坏已有业务能力。

---

# 36. Session Header

Session Header 应优先显示：

```text
当前场景
当前地点
必要导航
必要状态
更多操作
```

避免长期显示：

```text
模型
Provider
Token
API
技术状态
```

Header 高度必须严格控制。

手机纵向空间非常宝贵。

---

# 37. Session HUD

移动端 HUD 属于高风险区域。

一级信息建议：

```text
地点
HP
MP / Energy
```

二级信息例如：

```text
金币
经验
等级
技能点
完整属性
其他 Runtime Status
```

可以进入：

```text
Character Sheet
Status Detail
Bottom Sheet
More Panel
```

不要把所有 RPG 数值永久放在屏幕顶部。

---

# 38. HUD 小屏处理

窄屏时禁止简单：

```text
Row overflow
→
全部 Column
```

导致 HUD 高度翻倍。

应考虑：

```text
减少一级信息
横向紧凑布局
状态收纳
短标签
详情 Sheet
```

Session Narrative 可视面积优先级高于低频 HUD 数据。

---

# 39. Character Switcher

移动端 Character Switcher 不应长期占据过高纵向空间。

可以考虑：

```text
横向头像
Compact Chip
Participant Strip
Header Entry
Bottom Sheet
```

必须支持：

```text
长角色名
多角色
动态参与者
死亡角色
隐藏角色
角色切换
自动推进状态
```

不要假定角色名很短。

---

# 40. Session Message / Narrative

Adventure Narrative 应以阅读为中心。

优先：

```text
稳定内容宽度
舒适行高
足够段间距
低视觉噪声
明显但克制的角色区分
```

不要让每一段 AI 内容都变成：

```text
大聊天气泡
彩色头像
强阴影卡片
```

LT 的 Narrative 更应该像：

```text
互动小说正文
+
轻量角色对话
```

而不是普通 IM。

---

# 41. 用户消息与剧情内容

用户行动和 Narrative 可以有视觉区别。

但不要过度 IM 化。

例如用户行动可以：

```text
轻微 Surface
右对齐或明显 Label
较紧凑展示
```

AI Narrative：

```text
内容宽度稳定
正文阅读样式
减少 Bubble 感
```

重点是：

> 用户在推进故事，而不是和机器人聊天。

---

# 42. Session Input

Session Input 是最高优先级交互区域。

移动端默认保持简单：

```text
[ + ] [ 描述你的行动…… ] [ ↑ ]
```

低频功能进入：

```text
Bottom Sheet
Quick Menu
More Menu
```

例如：

```text
角色
背包
任务
地图
回复长度
设置
```

不要让输入框旁边长期出现大量 IconButton。

---

# 43. 输入框约束

必须验证：

```text
320px
Soft Keyboard
横屏
多行输入
长 Hint
Offline 状态
Streaming 状态
Stop 状态
```

输入框必须保留足够宽度。

禁止：

```text
左右按钮太多导致 TextField 极窄
发送按钮出屏
Hint 被压成几个字
输入区域固定高度无法增长
```

---

# 44. Keyboard / Insets

输入相关页面必须处理：

```text
MediaQuery.viewInsets
SafeArea
Android Navigation Bar
iPhone Home Indicator
Soft Keyboard
Landscape
```

键盘出现后：

```text
输入框必须可见
发送按钮必须可见
Narrative 必须可滚动
核心操作不能被挡住
```

避免：

```text
双重 bottom padding
Bottom Bar 与系统导航重叠
键盘打开后整个页面 overflow
```

---

# 45. Token 信息降级

Token 是实现细节。

普通用户不需要持续看到：

```text
12345 / 128K Tokens
```

只有以下场景才建议主动显示：

```text
上下文接近限制
Debug
高级设置
上下文管理
性能诊断
```

不要让 Token Monitor 成为 Session 的常驻视觉组件。

---

# 46. Search

Session Search 打开后必须保持：

```text
不会把 Narrative 压得过小
可快速关闭
支持长关键词
支持键盘
```

移动端如果顶部空间不足：

优先考虑 Overlay / Dedicated Search Mode。

---

# 47. Resource Library

资料库首先是：

```text
世界
角色
NPC
关系
场景 / Preset
```

的档案系统。

不要设计成 AI Asset Dashboard。

Mobile 推荐：

```text
Header
Category
Search
List / Compact Grid
```

点击实体后：

```text
Full Page Detail
```

---

# 48. Resource Library Desktop

Desktop 可以使用：

```text
Category Navigation
+
Grid / List
+
Detail
```

空间允许时可以 Master / Detail。

但不要要求 Mobile 同时显示：

```text
Master + Detail
```

---

# 49. Resource Library Card

世界和角色是内容实体。

Card 可以使用。

但优先展示：

```text
名称
关键摘要
更新时间
状态
必要缩略信息
```

不要给每个实体堆：

```text
Badge
彩色 Icon Box
多个按钮
多个状态 Chip
Glow
```

低频操作可以进入：

```text
Context Menu
More Menu
Detail Page
```

---

# 50. Settings

Desktop 可以保持：

```text
Master / Detail
```

Mobile 不应该简单：

```text
把 Desktop Sidebar 换成横向 TabBar
```

更适合手机的结构：

```text
设置

模型与服务        >
会话与生成        >
外观              >
数据与存储        >
关于 LT           >
```

点击进入独立二级页面。

---

# 51. Settings 二级页面

Mobile：

```text
‹ 设置

模型与服务

[具体配置]
```

Desktop：

```text
Sidebar
+
Detail
```

同一数据模型可以拥有不同 IA。

不要为了代码复用强迫所有平台 Widget Tree 完全一致。

---

# 52. 设置页信息优先级

普通用户优先理解：

```text
功能含义
当前状态
修改结果
```

不要让：

```text
技术参数名
内部字段
Provider 实现细节
```

占据主视觉。

高级参数可以放在高级区。

---

# 53. Adventure Wizard

Wizard 移动端必须：

```text
单任务
单焦点
明确当前步骤
明确下一步
```

不要把桌面大表单直接压缩到手机。

复杂内容可以拆成：

```text
Section
Sub Page
Picker
Bottom Sheet
Expandable Advanced Options
```

---

# 54. Wizard Stepper

Stepper 必须测试：

```text
320px
长中文步骤名
大字体
横屏
```

不要让：

```text
Step 1
Step 2
Step 3
Step 4
```

横向挤爆。

移动端可以只显示：

```text
步骤 2 / 4
角色
```

而不是强制展示全部步骤标题。

---

# 55. 动态文本永远不可信

以下文本全部假定可能非常长：

```text
Adventure Title
Worldview Name
Character Name
NPC Name
Scene Title
Location
Model Name
Provider Name
Error Message
User Input
AI Output
Status Text
File Name
Preset Name
```

禁止按照示例数据长度设计布局。

---

# 56. Row + 动态文本

只要 Row 中同时存在：

```text
动态 Text
+
Button / Icon / trailing
```

必须检查窄屏。

可采用：

```text
Flexible
Expanded
Wrap
Column fallback
maxLines
ellipsis
```

根据业务语义选择。

核心内容不得仅通过 ellipsis 永久丢失。

---

# 57. Overflow 修复原则

遇到：

```text
RenderFlex overflowed
unbounded constraints
pixel overflow
```

必须修复约束根因。

禁止仅为了让黄色警告消失使用：

```text
ClipRect
OverflowBox
Transform
负 Offset
隐藏 Widget
固定高度强压内容
随机固定宽度
横向 SingleChildScrollView
无限缩小字体
```

除非这些本身就是合理产品设计。

---

# 58. 不允许掩盖 Overflow

以下不算修复：

```text
黄色 RenderFlex 消失了
```

真正完成标准：

```text
父子约束正确
动态内容可处理
手机宽度可适配
字体放大可用
交互不丢失
同类组件已检查
```

---

# 59. Touch Target

Mobile 重要交互区域建议保持：

```text
44–48 logical px
```

视觉 Icon 可以较小。

点击区域不能太小。

不要为了紧凑将：

```text
IconButton
Menu
Back
Send
More
```

缩到难以点击。

---

# 60. SafeArea

所有靠近屏幕边缘的重要 UI 必须考虑：

```text
刘海
灵动岛
状态栏
Android Navigation
Home Indicator
横屏
```

不要假设完整 viewport 都是安全内容区域。

---

# 61. Dialog

Desktop：

```text
Dialog
```

可以用于中小型任务。

Mobile：

复杂 Dialog 优先考虑：

```text
Full-screen Page
Modal Bottom Sheet
Full-height Sheet
```

不要把桌面宽 Dialog 直接缩在手机中央。

---

# 62. BottomSheet

BottomSheet 必须考虑：

```text
SafeArea
Keyboard
Scroll
Max Height
Drag Handle
Dynamic Text
```

操作项过多时：

允许滚动。

不要出现 Sheet 内容被 Home Indicator 挡住。

---

# 63. Loading State

Loading 应克制。

不要每次加载都做：

```text
大 Logo
AI Sparkle
复杂动画
```

优先：

```text
Skeleton
Progress
Inline Loading
Section Loading
```

根据页面语义选择。

---

# 64. Empty State

Empty State 应回答：

```text
这里是什么？
为什么是空的？
下一步可以做什么？
```

不要只是：

```text
暂无数据
```

也不要堆过量插图。

---

# 65. Error State

Error State 应优先告诉用户：

```text
发生什么
影响什么
下一步做什么
```

不要直接展示：

```text
Stack Trace
Exception dump
技术实现细节
```

除非 Debug 模式。

---

# 66. Animation

动画用于：

```text
解释状态变化
建立空间关系
提高操作反馈
```

推荐：

```text
150–250ms
easeOut
fade
small slide
size transition
```

避免：

```text
长时间 Bounce
循环 Glow
过量 Scale
复杂渐变动画
无意义 Hero
```

Adventure 正在 Streaming 时尤其应减少视觉干扰。

---

# 67. Hover

Desktop Hover 只做轻提示。

推荐：

```text
Surface Change
Border Change
轻微位移
Cursor Change
```

不要：

```text
大阴影
大 Scale
Glow
明显弹跳
```

---

# 68. Widget 复用

新增 Widget 之前必须搜索：

```text
lib/widgets
lib/core/widgets
lib/features/**/presentation
```

并搜索相关名称与功能。

优先级：

```text
复用已有
↓
扩展已有
↓
使用 Flutter 标准组件
↓
新增共享组件
↓
新增 Feature 私有组件
```

---

# 69. 禁止重复造轮子

特别禁止产生：

```text
ModernCard
ModernCard2
PremiumCard
BeautifulCard
AIStyledCard
AdvancedCard
NewModernButton
BetterDialog
```

这类没有业务语义的组件。

组件名称应表达：

```text
业务职责
视觉职责
交互职责
```

---

# 70. Widget 拆分

避免巨大 build()。

但不要过度拆分。

应该拆分当组件：

```text
有独立职责
有状态
被重复使用
值得独立测试
视觉结构复杂
```

不要把：

```text
一个 Padding
一个 Icon
一行 Text
```

都拆成独立文件。

---

# 71. Riverpod

UI 重构不得复制业务层状态。

禁止因为新 UI 建立第二份：

```text
currentAdventure
selectedCharacter
currentScene
gameState
runtimeState
```

先确认当前 Single Source of Truth。

UI-only 状态可以属于：

```text
Widget State
Presentation Provider
```

业务状态继续来自正式 Provider / Controller。

---

# 72. 不修改 Runtime 语义

纯 UI 任务不得顺手修改：

```text
Frozen Baseline
Runtime HEAD
State Commit
Scene Commit
Memory
Context
Prompt Assembly
LLM Parsing
Adventure Persistence
Game State Semantics
Database Schema
```

如果 UI 需要的数据当前接口不理想：

先搜索已有 Presentation API。

确需跨层：

```text
说明原因
控制范围
保留架构方向
补测试
```

---

# 73. 不破坏用户数据

UI 重构不得为了开发方便：

```text
清数据库
删存档
重建 DB
改变 JSON Schema
改变 Adventure Persistence
清空角色
清空世界观
```

不得修改用户已有数据语义。

---

# 74. Feature Scope

一个阶段只处理一个清晰领域。

推荐整体顺序：

```text
P0
Design Foundation
Responsive Foundation
Adaptive App Shell

P1
Adventure Session

P1
Adventure Dashboard

P2
Resource Library

P2
Settings

P2
Adventure Wizard

P3
Visual Polish
Animation
Consistency
```

不要一次 PR / Commit 重写所有页面。

---

# 75. Phase 1 — Design Foundation

第一阶段优先统一：

```text
Breakpoints
Spacing
Radius
Typography
Surface
Button Hierarchy
Input Style
Responsive Container
Adaptive Scaffold
Navigation Behavior
```

不要 Phase 1 同时彻底重写所有业务页面。

---

# 76. Responsive Infrastructure

如果当前代码存在大量分散断点：

允许逐步建立统一基础设施。

可以考虑：

```text
AppBreakpoints
AdaptiveLayout
ResponsivePadding
ContentWidth
AdaptiveScaffold
```

但必须先搜索仓库是否已有相同能力。

不要无条件新建一套 Responsive Framework。

---

# 77. Content Width

Desktop 页面不要无限拉宽。

正文、设置、表单、Narrative 应根据内容类型设置合理 maxWidth。

例如：

```text
阅读内容
较窄

设置表单
中等

Grid / Asset Library
较宽
```

不要所有页面统一使用同一最大宽度。

---

# 78. 页面 Padding

Padding 应随 viewport 调整。

例如方向：

```text
Mobile
12–16

Tablet
16–24

Desktop
24–32+
```

具体数值优先使用现有 Token。

不要直接复制固定：

```dart
EdgeInsets.all(32)
```

到手机。

---

# 79. 横屏

Mobile Landscape 必须被视为真实场景。

特别测试：

```text
Adventure Session
Input
Wizard
Dialog
BottomSheet
Settings
```

横屏时高度通常比宽度更危险。

不要只测试 Portrait。

---

# 80. Text Scaling

至少验证：

```text
100%
130%
160%
```

关键页面。

大字体时：

```text
不能 overflow
不能遮挡按钮
不能让标题压坏导航
不能失去关键操作
```

禁止为了保持布局强制缩小系统字体。

---

# 81. Accessibility

至少考虑：

```text
触控面积
文字对比度
状态不要只靠颜色
重要 Icon 有 Tooltip / Semantics
键盘导航
Focus
```

Desktop 控件应支持合理 Keyboard Focus。

---

# 82. 测试 Viewport

涉及 UI 的任务至少考虑：

```text
320 × 720
360 × 800
390 × 844
412 × 915

768 × 1024

1024 × 768
1440 × 900
```

不要求每次都写所有尺寸 Golden Test。

但必须根据修改范围选择有风险的尺寸进行 Widget Test。

---

# 83. 高风险区域

修改以下区域必须额外执行窄屏审查：

```text
AppBar
Header
MainSidebar
Bottom Navigation
NavigationRail
Adventure Session
Status HUD
Character Switcher
Session Input
Wizard
Stepper
Resource Library
Settings
Dialog
BottomSheet
Search
Token UI
Card Header
ListTile trailing
Toolbar
Action Row
```

---

# 84. Widget Test 目标

Widget Test 不应该只检查：

```text
find.text(...)
```

还应根据风险覆盖：

```text
窄屏能 Pump
无 FlutterError
导航可点击
动态文本
长标题
按钮可触达
状态切换
Callback
Theme
Responsive Branch
```

过去出现过 Overflow 的区域：

必须考虑增加 Regression Test。

---

# 85. UI Regression

如果修复一个实际发生过的 UI Bug：

例如：

```text
RenderFlex Overflow
键盘遮挡
按钮出屏
Header 超高
TextField 太窄
```

应尽量增加能在修改前失败、修改后通过的测试。

---

# 86. 性能

UI 重构不得为了美观明显增加：

```text
无意义 rebuild
大型透明层
大量 BackdropFilter
大量 Shadow
复杂动画
列表内重计算
```

Riverpod Watch 应控制粒度。

长列表优先使用：

```text
ListView.builder
GridView.builder
Sliver
```

而不是一次性构建全部大型内容。

---

# 87. 图片与缩略图

如果未来 UI 使用世界、角色、场景图：

必须考虑：

```text
无图片状态
加载失败
长宽比
低性能设备
Cache
Placeholder
```

不要让视觉设计依赖图片一定存在。

---

# 88. 空白内容

LT 允许“纯白板”。

不要在用户没有内容时自动塞大量假数据或 Demo Card。

Empty State 可以引导创建。

但用户数据与预设内容必须清楚区分。

---

# 89. 文案原则

UI 文案尽量自然。

避免 AI SaaS 文案：

```text
开启无限可能
释放智能潜能
AI 驱动
自主意识 AI
下一代智能
超级智能工作流
```

优先使用产品语义：

```text
新建冒险
继续故事
世界
角色
场景
存档
资料库
设置
```

---

# 90. 技术词降级

普通用户页面尽量不把：

```text
Token
Context Window
Temperature
Top P
Provider
JSON
Prompt
Schema
```

放在一级信息层。

这些属于：

```text
高级设置
开发信息
调试
模型配置
```

---

# 91. 删除视觉元素之前

不要为了“极简”直接删业务功能。

正确流程：

```text
判断使用频率
↓
判断优先级
↓
重新组织层级
↓
必要时收进 Menu / Sheet / Detail
```

UI 重构是重组功能，不是随意砍功能。

---

# 92. Desktop / Mobile 可以有不同结构

允许：

Desktop：

```text
Sidebar + Master + Detail
```

Tablet：

```text
Rail + Content
```

Mobile：

```text
Bottom Navigation + Full Page Detail
```

不要求三者 Widget Tree 完全一致。

真正应该保持一致的是：

```text
业务语义
数据来源
交互结果
设计语言
```

---

# 93. 视觉一致性

相同语义应拥有一致表现。

例如：

```text
Primary Action
Secondary Action
Destructive Action
Selected Item
Error State
Empty State
Navigation Item
Section Header
```

不要每个 Feature 自己设计一套。

---

# 94. Primary Action

一个视图通常只有一个明显 Primary Action。

不要：

```text
三个 FilledButton
四个高饱和彩色入口
多个相同权重 CTA
```

同时出现。

Secondary 操作应降低视觉强度。

---

# 95. Destructive Action

删除类操作必须：

```text
明确语义
确认
避免误触
颜色表达风险
```

Mobile 不应让删除按钮成为列表中最显眼元素。

可以进入：

```text
Swipe Action
More Menu
Detail
```

根据实际场景决定。

---

# 96. Focus 与 Desktop

桌面端应考虑：

```text
Tab Focus
Keyboard Shortcut
Enter
Escape
Hover
Mouse Cursor
Scroll
```

但不要因为 Desktop 功能破坏 Mobile。

---

# 97. Scroll

滚动区域必须清晰。

避免：

```text
Nested Scroll 混乱
多个 Vertical ScrollController 争夺
页面内部无必要的小滚动框
```

Mobile 优先保持一个主要垂直滚动区域。

---

# 98. 页面标题

页面标题应该告诉用户“在哪里”。

不是产品广告。

优先：

```text
资料库
世界
角色
设置
外观
暮色边境
```

避免：

```text
智能世界资产中心
AI 全景角色管理引擎
```

---

# 99. Splash / Loading

Splash 保持品牌化但克制。

避免：

```text
AI Sparkle
渐变发光
技术状态轮播
模型品牌大字
```

可以使用：

```text
LT
灵境
简洁 Logo
加载状态
```

---

# 100. 品牌

LT / 灵境的品牌视觉应独立于任何模型供应商。

不要让：

```text
DeepSeek
OpenAI
Gemini
```

成为产品品牌视觉的一部分。

用户可以更换模型。

LT 品牌应该保持稳定。

---

# 101. 视觉判断测试 A

每次设计完成后问：

> 如果删除界面里所有 “AI / 模型 / LLM” 文字，这个页面是否仍然像一个完整、有明确定位的产品？

如果答案是否：

说明 UI 仍然过度依赖 AI 身份。

重新设计。

---

# 102. 视觉判断测试 B

问：

> 页面第一眼看到的是用户内容，还是软件功能？

LT 一级页面优先：

```text
用户内容
```

---

# 103. 视觉判断测试 C

问：

> 手机页面是为手指、小屏和键盘重新设计的吗？

如果只是：

```text
Desktop UI
↓
减少 Padding
↓
缩小字体
```

不算 Mobile UI。

---

# 104. 视觉判断测试 D

问：

如果移除：

```text
Gradient
Shadow
Badge
Colorful Icon Container
Glow
```

这个界面是否仍然成立？

如果不成立：

说明信息架构与排版层级不够好。

---

# 105. 视觉判断测试 E

问：

> 这个功能需要一直显示吗？

低频功能优先收纳。

高频功能优先直接可见。

不要为了展示功能丰富度把所有能力摊在屏幕上。

---

# 106. 修改后最低验证

修改完成至少执行：

```bash
dart format .
flutter analyze
flutter test
git diff --check
git status --short
```

如果全量测试耗时较大：

先执行定向 Widget / Unit Test。

但任务结束前应根据修改风险决定是否跑全量。

架构测试必须通过。

---

# 107. 修改前后检查

提交前检查：

```bash
git diff
git diff --check
git status --short
```

确认没有：

```text
用户修改被覆盖
无关文件格式化
临时 Debug
敏感信息
误删文件
生成垃圾文件
重复组件
```

---

# 108. Git 安全

严格遵守 AGENTS.md。

未经明确授权禁止：

```bash
git reset --hard
git checkout -- .
git restore .
git clean -fd
git clean -fdx
```

不要破坏用户或其他 Agent 未提交修改。

不要强推。

不要随意重写共享历史。

---

# 109. Commit 策略

一个清晰阶段对应一个清晰 Commit。

推荐：

```text
refactor(ui): establish adaptive app shell

refactor(ui): redesign adventure session

refactor(ui): simplify adventure dashboard

refactor(ui): adapt resource library for mobile

refactor(ui): redesign mobile settings navigation

refactor(ui): unify responsive design tokens

test(ui): cover compact viewport regressions
```

不要一个 Commit 混入：

```text
UI
Database
LLM
Runtime
Prompt
Docs
无关修复
```

---

# 110. 不做顺便优化

UI 任务中发现其他问题：

```text
记录
说明
必要时创建 TODO / 报告
```

不要未经授权直接扩大范围。

例如：

正在改 Session Input 时发现 Prompt Builder 问题：

```text
不要顺手修改 Prompt Builder。
```

---

# 111. 设计阶段建议顺序

大型 UI 重构默认采用：

```text
Phase 1
Design Foundation

Phase 2
Adaptive App Shell

Phase 3
Adventure Session

Phase 4
Adventure Dashboard

Phase 5
Resource Library

Phase 6
Settings

Phase 7
Adventure Wizard

Phase 8
Polish / Regression
```

每阶段完成后：

```text
测试
Review
Commit
```

再进入下一阶段。

---

# 112. Phase 1 验收

Design Foundation 完成后应至少拥有：

```text
明确 Breakpoint
统一 Spacing
统一 Radius
统一 Typography
统一 Surface
统一 Button Hierarchy
统一 Input Hierarchy
统一 Content Width 原则
统一 Responsive 原则
```

不要求同时重写所有页面。

---

# 113. Phase 2 验收

Adaptive App Shell 应达到：

Mobile：

```text
清晰一级导航
不依赖唯一 Drawer
```

Tablet：

```text
充分利用中等宽度
```

Desktop：

```text
Persistent Navigation
```

同时：

```text
导航状态唯一
业务路由行为不变
```

---

# 114. Phase 3 Session 验收

Adventure Session 应达到：

```text
320px 无横向 Overflow

键盘弹出可正常输入

Narrative 保持主要视觉空间

HUD 不过度占高

Input 保持足够宽

低频 RPG 功能被合理收纳

Token 不再抢占普通用户视觉

长场景名可处理

长地点名可处理

多角色可处理

Dark Mode 可读
```

---

# 115. Phase 4 Dashboard 验收

Dashboard 应达到：

```text
内容优先
继续故事优先
减少 SaaS Feature Cards
减少 AI 文案
减少模型技术状态
手机信息密度合理
Desktop 不空洞
```

---

# 116. Phase 5 Resource Library 验收

Mobile：

```text
分类清晰
搜索清晰
列表/网格可用
详情独立
```

Desktop：

```text
利用宽度
支持高效浏览
```

同时：

```text
世界
角色
NPC
场景
```

视觉语义一致。

---

# 117. Phase 6 Settings 验收

Mobile：

```text
设置分类列表
二级页面
无拥挤 TabBar
```

Desktop：

```text
Master / Detail
```

高级技术配置不应压过普通配置。

---

# 118. Phase 7 Wizard 验收

移动端：

```text
步骤明确
单任务聚焦
长标题安全
按钮安全
键盘安全
Picker 安全
```

Desktop：

```text
充分利用宽度
但不形成超宽难读表单
```

---

# 119. Phase 8 Polish 验收

最后才处理：

```text
动画
Hover
微交互
视觉细节
一致性
```

不要在架构和响应式尚未稳定时先投入大量动画。

---

# 120. 最终完成检查表

任何 UI 重构任务结束前必须自检：

```text
[ ] 已阅读 AGENTS.md

[ ] 已确认当前 Git 状态

[ ] 未覆盖用户未提交修改

[ ] 未恢复已删除 Legacy UI

[ ] 未破坏 Presentation 架构边界

[ ] 未让 Domain Model 承担 UI 职责

[ ] 未重复造 Widget

[ ] 未修改无关业务逻辑

[ ] 未修改 Runtime 语义

[ ] 未修改用户数据语义

[ ] 320px 无横向 Overflow

[ ] 360px 可用

[ ] 390px 可用

[ ] Tablet 可用

[ ] Desktop 可用

[ ] 横屏已考虑

[ ] SafeArea 已考虑

[ ] Soft Keyboard 已考虑

[ ] Dynamic Text 已考虑

[ ] Text Scaling 已考虑

[ ] Light Theme 可用

[ ] Dark Theme 可用

[ ] Touch Target 合理

[ ] 没有通过裁剪掩盖 Overflow

[ ] 没有过量 Gradient

[ ] 没有过量 Shadow

[ ] 没有过量 Badge

[ ] 没有过量彩色 Icon Container

[ ] 没有明显 ChatGPT Clone

[ ] 没有明显 Claude Clone

[ ] AI 能力没有压过故事内容

[ ] 首页内容优先于功能宣传

[ ] Session 更像互动叙事而不是 AI Chat

[ ] flutter analyze 通过

[ ] flutter test 通过

[ ] git diff --check 通过

[ ] Git diff 已人工复核
```

---

# 121. Agent 输出要求

完成 UI 任务后，最终报告应至少包含：

```text
1. 基线 Commit

2. 修改范围

3. 修改文件

4. UI / UX 变化

5. Mobile 行为变化

6. Tablet / Desktop 行为变化

7. 是否改变业务逻辑

8. 测试结果

9. flutter analyze 结果

10. 剩余风险

11. 最终 Commit
```

如果没有执行某项验证：

必须明确写：

```text
未执行
```

不得假装已经验证。

---

# 122. 核心产品原则

始终遵守：

> AI 能力隐藏在体验之后。

> 内容比功能入口重要。

> 手机不是缩小的桌面。

> 颜色用于表达意义，不用于表达“酷”。

> 减少容器，增加层级。

> 信息架构优先于装饰。

> 排版优先于 Glow。

> 修复约束根因，不掩盖 Overflow。

> Presentation 不污染 Domain。

> UI 重构不污染 Runtime。

> 先复用，再新增。

> 当前代码优先于旧文档。

> 一个阶段只解决一个明确问题。

> 每一步必须可验证、可回滚、可追溯。

---

# 123. LT 最终体验目标

最终用户打开 LT 时，不应该首先感觉：

> 我正在使用一个 AI 工具。

而应该感觉：

> 我正在进入自己的世界。

Adventure Session 不应该首先感觉：

> 我正在和一个模型聊天。

而应该感觉：

> 我正在参与一个持续演变的故事。

Resource Library 不应该感觉：

> 我正在管理 Prompt 资产。

而应该感觉：

> 我正在整理自己的世界、角色与故事档案。

Settings 不应该感觉：

> 我正在调一个 LLM Playground。

而应该感觉：

> 我正在配置 LT 的行为与体验。

这就是 LT UI 重构的最终判断标准。
