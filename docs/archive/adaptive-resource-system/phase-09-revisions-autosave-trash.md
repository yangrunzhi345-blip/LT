# Phase 9 — Revision、自动保存与回收站执行方案

## 目标与交付物

为生成、编辑、重写、压缩和删除建立可恢复边界。任何 AI 或删除操作都不能造成不可逆数据损失，应用退出或崩溃后可恢复已确认内容。

## 唯一代码范围

- Resource revision、revision node snapshot、head pointer、autosave checkpoint 与 trash record。
- Section 完成即持久化；文本编辑合并防抖，但生命周期结束时强制 flush。
- 重新生成、语义压缩、全部重新生成前创建 revision。
- Resource/Section 删除进入回收站，支持恢复到原父节点和顺序；冲突时使用确定性恢复规则。

## 数据策略

- revision 记录不可变，只存必要节点快照和 parent revision；不得每次 tick 复制完整资源。
- head 切换与操作写入同一事务。
- autosave 保存当前草稿增量，不将每个流式 chunk 写 SQLite。
- trash 保留原 resource/parent/sort metadata、删除原因和过期时间；永久删除必须是显式二次操作。

## 主要修改文件

- 数据库升级及 `resource_revisions`、`resource_revision_nodes`、`resource_autosaves`、`resource_trash` 表
- revision/trash repository 与 application services
- Studio 历史/恢复入口、资源库回收站入口
- job/generation/edit command 接入 revision boundary
- 事务、恢复、崩溃和 debounce tests

## 实施步骤

1. 定义 revision cause：manual save、generation、regeneration、compression、restore、migration。
2. 完成 Part 时写 checkpoint；用户编辑采用统一 debounce，dispose/cancel/error 时 final flush。
3. 有损命令先创建 before revision，再提交新 head；失败保持原 head。
4. 删除只修改 live view 并写 trash；恢复时若父节点不存在则恢复到 Resource 根下的新 Section，并明确提示。
5. 清理策略只删除超过保留期且非 head/assembly 引用的记录。

## 测试与验收

- 模拟生成中崩溃后，已完成 Section/Part 可恢复，未确认 chunk 不伪装成完成。
- 重写、压缩、全部重新生成后可回到操作前版本。
- 删除和恢复 Resource/Section 保留内容及顺序；重复恢复幂等。
- 高频输入/stream 不产生每 tick 数据库写入；取消和异常仍 flush 已确认内容。
- 清理不会删除当前 head、assembly revision 或回收站仍在保留期的数据。

## 不做事项

不实现 Adventure assembly readiness 判断，不删除旧数据表；分别属于 Phase 10 和 Phase 12。
