# Phase 0 — 架构契约冻结执行方案

## 目标与交付物

本阶段只建立可编译、可测试的架构契约和决策记录，不迁移数据、不改变用户入口。交付统一术语、依赖方向、状态机与接口桩，使后续阶段不能各自发明 Resource/Section/Part 含义。

## 唯一代码范围

- 新增资源领域枚举与 ID 类型：资源类型、节点状态、创建方式、生成状态、容量状态、就绪状态。
- 定义不带数据库和 Flutter 依赖的领域接口：内容树读取、节点挂载、创建会话、版本选择、组装快照。
- 集中定义世界观与角色容量常量；不得把 50,000/60,000/5,000/6,000 散落到页面或 prompt。
- 写 Architecture Decision Record，明确逻辑树、不可变 ID、排序语义、禁止巨型 JSON、原稿与 assembly revision 分离。

## 建议文件

- 新建 `lib/domain/resources/resource_contracts.dart`
- 新建 `lib/domain/resources/resource_limits.dart`
- 新建 `lib/domain/resources/resource_repository.dart`（仅接口）
- 新建 `docs/architecture/adaptive-resource-system.md`
- 新建 `test/domain/resources/resource_contracts_test.dart`

不得修改 `database_service.dart`、现有 repository 实现、页面、prompt 或生成 coordinator。

## 实施步骤

1. 盘点 `ResourceLibraryMode`、`ResourceProvenance`、`GenerationTaskHandle` 等已有类型，复用其稳定语义，避免同义枚举。
2. 冻结 `ResourceType = worldview/character/npc`；创作内容统一为节点树，但各资源仍允许保留运行时必需 metadata schema。
3. 冻结节点不变量：Section 直属 Resource、Part 直属 Section、同级顺序显式保存、节点 ID 创建后不可变、内容只存 Part。
4. 冻结生成协议上限：每次响应只能操作一个 blueprint 或有限节点 patch；接口不接受完整资源 JSON。
5. 冻结状态转换表，并用纯 Dart 测试证明非法转换被拒绝。

## 验收标准

- 契约层不 import Flutter、SQLite、HTTP 或具体 repository。
- 容量与状态定义只有一个来源；`rg` 不出现新增的重复数值常量。
- 测试覆盖合法/非法状态转换、资源类型和容量边界。
- 应用行为和 v30 数据完全不变。

## 交接

Phase 1 只能实现这里冻结的模型；如必须改变节点或状态语义，应先更新 ADR 并重新评审 Phase 0，而不是在数据库层临时扩展。
