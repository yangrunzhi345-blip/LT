# Phase 11 — 资源库与整体 UX 收敛执行方案

## 目标与交付物

重组资源库信息架构，使列表只负责“找、看、建”，高级创作能力进入详情/Studio。用户只看到易懂状态和“AI 创建/手动创建”两种入口。

## 唯一代码范围

- 资源库统一列表、筛选、搜索、详情导航和创建按钮。
- 从卡片移除独立 AI 导入、详细世界观、Adventure 业务动作和重复按钮。
- 用户状态文案统一为：生成中、已保存、建议优化、正在优化、已准备完成、优化失败。
- 内部 Part、revision ID、JSON、absolute limit、compression job、assembly revision 不直接暴露。

## 主要修改文件

- `resource_library_screen.dart`、worldview/character/NPC tabs 与统一 card/widget
- Studio/detail route 与 creation entry sheet/dialog
- 状态 presentation mapper 和本地化文案
- 删除页面上的独立保存/生成逻辑调用，但保留 Phase 12 才能删除的兼容类
- 全 viewport widget/golden/accessibility tests

## 响应式实施

1. 使用组件实际约束决定 list/grid 和操作布局，页面级断点仅采用 <600、600–899、≥900。
2. 卡片长名称/状态使用 Flexible 或换行；关键名称不能只靠 ellipsis 丢失。
3. 320 宽操作收纳到菜单，主要创建按钮保持可点击尺寸。
4. Dialog/BottomSheet 使用 SafeArea、受限宽高和可滚动正文；键盘不遮挡名称输入。
5. 搜索结果、空状态、错误/加载状态共用统一组件。

## 测试与验收

- 资源库主界面只出现一个“新建”，展开后只有 AI 创建和手动创建。
- 粘贴、文件、已有资源只能在创建流程的参考资料步骤出现。
- 320×568、360×640、390×844、412×915、768×1024 与桌面无 overflow，长中英文和大字体可用。
- 搜索、筛选、进入详情、恢复回收站资源、查看准备状态均有 Widget test。
- UI 不泄漏内部术语；旧 deep link 能重定向到统一流程。

## 不做事项

本阶段不删除旧类、旧表或旧测试，只停止 UI 到旧路径的正常入口；物理清理属于 Phase 12。
