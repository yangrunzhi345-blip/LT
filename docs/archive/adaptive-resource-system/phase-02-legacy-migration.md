# Phase 2 — 旧数据迁移与兼容执行方案

## 目标与交付物

把 v30 的世界观、角色卡和 NPC 无损映射为统一内容树，并建立过渡期兼容读取。迁移必须可恢复、可重复、可审计，且不改变 Adventure 既有快照。

## 唯一代码范围

- `worldview_presets.detail_json/description/entries_json` 到 Section/Part 的确定性映射。
- `character_cards.json_data` 与 `npc_cards.json_data` 固定字段到动态 Section/Part 的映射。
- 保存 legacy source ID、source hash、migration version 和迁移结果。
- 新树优先、旧表回退的兼容 adapter；新代码不再直接新增旧格式内容。

## 映射规则

- 世界观固定 module key 按当前显示顺序转换为 Section；无法识别的数据进入“其他资料”，不得丢弃。
- 角色卡每个非空业务字段转换为语义标题明确的 Section/Part；`firstMessage`、system prompt 等运行时字段保留在 metadata，同时可呈现对应创作节点，但需指定唯一事实源。
- custom attributes、关系、来源和 matching worldview 需保留类型及顺序。
- 空字段不制造空 Section；非法 JSON 保存原始 payload 到隔离字段并产生可诊断 migration failure，不得用空对象覆盖。

## 主要修改文件

- 新建 `lib/application/resources/legacy_resource_mapper.dart`
- 新建 `lib/application/resources/resource_migration_service.dart`
- 修改 `library_repository_impl.dart` 的过渡适配层
- 修改数据库 migration/迁移审计表
- 增加 fixture：简单/详细世界观、chara_card_v2、扁平角色卡、NPC、损坏 JSON、超长内容

## 实施步骤

1. 先实现纯函数 mapper 和 golden fixture，证明字段覆盖及稳定输出。
2. 以每个资源为事务单元迁移，写入 source hash；相同 hash 已成功时跳过。
3. 迁移失败只标记该资源，不能回滚或阻断其他资源，也不能删除旧行。
4. provider/repository 读取统一 view；Adventure 当前 config/snapshot 仍按原格式读取。
5. 提供只读迁移统计：总数、成功、跳过、失败及失败原因，不记录敏感正文。

## 测试与验收

- 真实 v30 fixture 升级后资源数量、名称、全文字符及关联不减少。
- 同一迁移执行两次不产生重复 Resource/Section/Part。
- 损坏 JSON 的旧记录仍存在且可报告；正常资源不受影响。
- `CharacterCard.fromJson` 支持的兼容输入均有映射测试。
- Adventure 旧存档、world entries 与现有语义检索测试保持通过。

## 不做事项

不删除旧表/字段，不重写 Adventure 快照，不改变创建入口，不提供用户手动迁移按钮。旧系统最终删除属于 Phase 12。
