# LT 自适应资源系统重构执行方案索引

## 文档目的

本目录把“统一资源模型 + 自适应内容结构 + 增量 JSON 挂载生成 + 可见流式创作 + 局部控制 + 后台语义压缩 + 统一组装就绪机制”拆成 13 个可独立提交、独立验收的实施阶段。执行顺序固定为 Phase 0 → Phase 12；后续阶段不得绕过前置验收。

> 开始或交接任何阶段前，先查看 [执行状态与阶段交接](STATUS.md)。该文件是实际执行进度、Git 基线、验证结果与验收状态的唯一记录入口。

## 当前代码基线

- 数据库当前版本为 v30，资源主要存放在 `worldview_presets`、`character_cards`、`npc_cards`，另有尚未成为统一事实源的 `creation_library_resources` 系列表。
- 世界观详情仍由 `WorldviewDetails.moduleKeys` 固定模块约束；角色卡仍由 `CharacterCard` 固定字段表达。
- 创建与导入分布于资源库页面、Adventure Wizard、多个 controller/use case；世界观和角色的详细生成各有 coordinator。
- 项目已有统一 LLM service/task policy、generation handle、30ms typewriter 与 180ms preview throttle，可扩展但不得复制。
- Adventure 通过配置快照、world entries 与语义 embedding 消费资源，迁移必须保持旧存档可读。

## 阶段文件

1. [Phase 0：架构契约冻结](phase-00-architecture-contract.md)
2. [Phase 1：统一 Resource / Section / Part 模型](phase-01-unified-content-tree.md)
3. [Phase 2：旧数据迁移与兼容](phase-02-legacy-migration.md)
4. [Phase 3：统一创建入口与 Pipeline](phase-03-creation-pipeline.md)
5. [Phase 4：Adaptive Blueprint](phase-04-adaptive-blueprint.md)
6. [Phase 5：增量 JSON 挂载协议](phase-05-incremental-json-protocol.md)
7. [Phase 6：Streaming Resource Studio](phase-06-streaming-resource-studio.md)
8. [Phase 7：Section 精细编辑与生成控制](phase-07-section-controls.md)
9. [Phase 8：容量与语义压缩](phase-08-capacity-and-compression.md)
10. [Phase 9：Revision、自动保存与回收站](phase-09-revisions-autosave-trash.md)
11. [Phase 10：Assembly Readiness](phase-10-assembly-readiness.md)
12. [Phase 11：资源库 UX 收敛](phase-11-library-ux.md)
13. [Phase 12：旧系统删除与总回归](phase-12-legacy-removal.md)

## 跨阶段硬约束

- Resource → Section → Part 是逻辑树；持久化、生成、重写、压缩均以节点为边界，禁止单次巨型 JSON。
- 世界观正常/弹性上限为 50,000/60,000 字符，角色卡为 5,000/6,000 字符；超限原稿仍可保存，不得截断。
- 新模型成为唯一写入路径之前，旧读取路径必须保持；删除兼容层只能发生在 Phase 12。
- 每个阶段只提交本文档列出的能力。发现后续阶段问题只记录，不提前实现。
- 所有数据库升级必须幂等、事务化、可从 v30 真实样本迁移，并保留用户数据。
- 所有 UI 阶段必须通过 320、360、390、412 逻辑宽度 Widget 回归；流式阶段还需覆盖取消、迟到 chunk、任务切换和最终 flush。

## 总体验收

完成 Phase 12 后，世界观、角色卡、NPC 仅通过统一创建管线进入同一内容树；AI 可规划并逐 Part 生成，用户可实时阅读和局部编辑；超限内容由后台压缩生成可组装版本，原稿和历史版本可恢复；Adventure 与语义检索只消费明确的 assembly revision；旧固定生成、重复入口和重复保存逻辑已移除。
