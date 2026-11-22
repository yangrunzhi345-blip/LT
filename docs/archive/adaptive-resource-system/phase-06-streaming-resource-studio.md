# Phase 6 — Streaming Resource Studio 执行方案

## 目标与交付物

用户提交 AI 创建后立即进入统一工作台，先看到名称和目录，再按 Section/Part 阅读实时生成内容、当前任务、未开始任务和错误。内部 patch/JSON 对用户完全隐藏。

## 唯一代码范围

- 新增 Studio screen、路由、Riverpod 状态和按 Part 渲染的响应式组件。
- 把生成引擎事件转换为最小粒度 view state；仅正在更新的 Part 重建。
- 复用 `TypewriterController` 的 30ms tick 思路和 `GenerationLimits.streamingPreviewThrottle`，网络消费与 UI 发布分离。
- 支持暂停、继续、取消、重试失败 Part 和离开后恢复页面。

## 状态设计

Resource header、目录、每个 Part 内容、reasoning/进度、滚动位置分别建模。provider 只以 resource/generation ID 查询，页面不保存第二份业务事实。完成事件必须 final flush；dispose 后不得更新 notifier。

## 主要修改文件

- 新建 `features/resource_studio/presentation/...`
- 新建 `resource_studio_controller.dart` 及 provider
- 抽取/扩展可复用 streaming presenter，不直接耦合 ChatEngine
- 修改统一 creation pipeline 的完成导航
- 新增 responsive、streaming 和生命周期 Widget tests

## 响应式要求

- 320–599：目录折叠为抽屉/底部面板，正文单列，操作使用 Wrap 或菜单。
- 600–899：可切换目录与正文，避免固定双栏挤压。
- ≥900：目录与正文双栏，正文宽度受约束。
- 长 Section 标题、长状态、200% text scale、SafeArea、键盘和横屏均不得 overflow。

## 测试与验收

- 320×568、360×640、390×844、412×915、768×1024 和桌面 viewport 无异常，主要操作可点击，长内容可滚动。
- 高频 patch 下整页/目录不随每个 chunk 重建；UI 发布遵守统一节流参数。
- 页面离开、dispose、暂停、取消、重连、最终 flush、旧 generation 迟到事件均有测试。
- 用户只能看到自然正文与可理解状态，不出现 Part ID、JSON、revision ID 或内部异常堆栈。

## 不做事项

不提供重命名/移动/删除/扩写等编辑命令；这些集中在 Phase 7，避免本阶段混入命令体系。
