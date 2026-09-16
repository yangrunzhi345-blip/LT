# Phase 3 — 统一创建入口与 Creation Pipeline 执行方案

## 目标与交付物

建立所有入口共用的单一创建会话与提交管线。用户最终只有“AI 创建”和“手动创建”；粘贴文本、文件、已有资源只作为 reference source，不再决定独立保存流程。

## 唯一代码范围

- 新增 `ResourceCreationRequest/Session/ReferenceSource` 与 creation use case。
- 将资源库、Adventure Wizard、AI 助手入口适配到同一 pipeline。
- 手动创建生成空内容树；AI 创建在本阶段只创建待规划会话，具体 blueprint 留给 Phase 4。
- 保存、取消、重复提交、来源记录、模式/资源类型校验统一处理。

## 主要修改点

- 收敛 `ResourceCrudController`、`ResourceLibraryImportController`、`ResourceCardImportController` 与 `import_use_cases.dart` 的创建职责。
- `worldview_ai_import_page.dart`、`resource_card_ai_import_page.dart` 不再拥有独立持久化逻辑，只构造 request。
- Adventure Wizard 快捷入口传递 creation context，完成后拿 resource ID，不复制生成/保存代码。
- 复用 `ResourceProvenance`，参考材料只记录必要来源元数据；正文不得写日志。

## 实施步骤

1. 定义 pipeline 状态：draft → validating → persisted/planning → completed/failed/cancelled。
2. 所有入口统一校验 API key、资源类型、名称、参考资料及重复提交 idempotency key。
3. 手动路径在一次事务内建立 Resource 和可选首个空 Section；失败不留半成品。
4. AI 路径持久化 creation session 与 reference source，再把 session ID 交给下一阶段规划器。
5. 旧入口先保留壳层和 deep link 兼容，但内部只能调用 pipeline。

## 测试与验收

- 每个入口创建的相同 request 得到结构一致的资源，且只产生一次记录。
- 文件/文本/现有资源是 reference source，不出现新的“导入模式”枚举。
- Adventure Wizard 失败时不导航且不残留孤儿资源；成功时只接收统一 resource ID。
- controller 测试覆盖取消、重复点击、无效类型、持久化失败与 session 恢复。
- 本阶段不发起真实正文生成。

## 不做事项

不实现目录规划、Part 生成、流式 Studio 或旧页面视觉删除；这些分别属于 Phase 4–6 和 Phase 11/12。
