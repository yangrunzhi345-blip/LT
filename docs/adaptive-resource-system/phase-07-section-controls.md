# Phase 7 — Section 精细编辑与生成控制执行方案

## 目标与交付物

让用户对单个 Section/Part 执行重新生成、按要求重写、扩写、压缩、编辑、重命名、移动、删除，并可手动或通过 AI 添加 Section。所有操作只影响选定子树。

## 唯一代码范围

- 节点 command 模型、校验器与 handler；所有 UI 操作统一进入命令层。
- Section/Part 新增、编辑、重命名、同级移动和软删除。
- 局部 AI regenerate/rewrite/expand/condense，以及全局继续生成/全部重新生成的任务编排入口。
- optimistic concurrency：命令携带 base content hash/version，冲突时不覆盖用户新内容。

## 主要修改文件

- 新建 `resource_edit_command.dart`、`resource_edit_service.dart`
- 扩展 tree repository 的原子 reorder 与条件更新 API
- 为 Studio 增加节点菜单、编辑器、确认对话框和简洁全局操作区
- 新增 node command、并发冲突及 responsive widget tests

## 实施步骤

1. 区分纯本地命令与 AI 命令；本地编辑立即事务保存，AI 命令创建限定 node ID 的 generation。
2. 重写/压缩必须生成候选结果，确认后才替换；重新生成前的版本保护由 Phase 9 接管，本阶段保留接入点。
3. 移动只改变同级 sort order；跨 Section 移动 Part 时一次事务更新父 ID 与两侧顺序。
4. 删除使用软删除接口；UI 提示可恢复，但完整回收站在 Phase 9 实现。
5. 高级操作收入 overflow menu；主界面只保留当前最重要操作，移动端按钮不得挤出屏幕。

## 测试与验收

- 每种命令只改变目标节点/顺序，其他 Section 内容 hash 不变。
- 两个并发编辑基于旧版本提交时，后提交者收到冲突并可选择刷新/另存候选，不能静默覆盖。
- AI prompt 只包含目标节点、必要上下文摘要和用户指令，不包含完整资源。
- 320/360/390/412 viewport、长标题、大字体下菜单和编辑对话框可用，无 overflow。
- 全部重新生成被拆成 Part 任务，不能退回单次巨型调用。

## 不做事项

不实现容量后台任务、正式 revision 恢复或回收站页面；只使用前置接口，分别交给 Phase 8/9。
