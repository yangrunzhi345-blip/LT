# Phase 1 — 统一 Resource / Section / Part 模型执行方案

## 目标与交付物

实现三层内容树及其正式持久化仓库，让世界观、角色卡、NPC 共用相同创作内容基础。此阶段只提供新模型与 CRUD，不迁移旧数据、不接 UI、不接 AI。

## 唯一代码范围

- 数据库从 v30 升级，建立资源主表、Section 表、Part 表及必要索引和外键。
- 实现领域实体、row mapper、统一 repository 和事务化树写入。
- 支持按资源读取有序 Section、按 Section 读取有序 Part、局部 upsert/reorder/delete 标记。
- 内容正文只能落在 Part；Resource/Section 只保存身份、标题、摘要、顺序与状态。

## 建议数据结构

- `resources`：id、type、name、summary、metadata_json、schema_version、created_at、updated_at、deleted_at。
- `resource_sections`：id、resource_id、title、summary、sort_order、status、created_at、updated_at、deleted_at。
- `resource_parts`：id、section_id、title、content、sort_order、status、content_hash、created_at、updated_at、deleted_at。

使用外键级联仅处理永久清理；普通删除先写 `deleted_at`，正式回收站能力留给 Phase 9。

## 主要修改文件

- `lib/services/database_service.dart`
- `lib/domain/resources/resource.dart`
- `lib/domain/resources/resource_section.dart`
- `lib/domain/resources/resource_part.dart`
- `lib/services/repositories/resource_tree_repository*.dart`
- `test/services/resource_tree_repository_test.dart`
- `test/services/database_migration_resource_tree_test.dart`

## 实施步骤

1. 新 schema 创建函数和逐版本 migration 同时落地，保持新装与升级结构一致。
2. repository 读取后在领域层组装树；禁止以一个 `content_json` 巨列作为正式树存储。
3. 为批量创建空树、追加 Section、追加 Part、局部更新、同级重排提供事务 API。
4. 使用 `sort_order + id` 提供稳定排序；处理并发更新时返回明确冲突而非静默覆盖。
5. metadata 仅承载资源类型特有的运行时核心字段，禁止把正文重新塞回 JSON。

## 测试与验收

- 从空库建表及从 v30 升级均成功，migration 重跑不破坏数据。
- CRUD、排序、外键、事务回滚、软删除过滤和跨资源节点隔离测试通过。
- 单独更新一个 Part 不重写其他 Part；读取大型资源无需解析巨型 JSON。
- 现有资源表和现有应用行为未改变。

## 不做事项

不修改 `WorldviewDetails`/`CharacterCard`，不双写旧数据，不生成 blueprint，不增加编辑 UI。这些分别属于 Phase 2、4、6/7。
