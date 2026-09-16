# Phase 4 — Adaptive Blueprint 自适应规划执行方案

## 目标与交付物

AI 创建的第一步只生成资源名称、动态目录、Section/Part 规划、规模预算和任务依赖，不生成完整正文。世界观和角色不再按固定字段填表。

## 唯一代码范围

- Blueprint 领域模型、校验器、repository 与 planning service。
- 世界观/角色/NPC 的共用规划 prompt，以及各类型最小核心约束。
- Blueprint 审阅、重新规划、确认接口；确认后才创建待生成节点。
- 规划任务接入统一 LLM gateway、task policy、timeout、取消和错误映射。

## Blueprint 契约

每个响应仅含：资源建议名、简短摘要、Section 列表、每个 Section 的 Part 标题/目标/预计长度、依赖 ID。禁止包含正文、固定九宫格模块或完整资源 JSON。ID 由客户端生成并在请求中预分配，模型只引用允许的 ID。

## 主要修改文件

- 新建 `lib/domain/resources/resource_blueprint.dart`
- 新建 `lib/application/resources/blueprint_planner.dart`
- 新建 `lib/application/resources/blueprint_validator.dart`
- 扩展 `llm_task.dart` 与 `llm_task_policy.dart`
- 新增 blueprint prompt builder 与 parser
- 新增 `test/application/resources/blueprint_*_test.dart`

## 实施步骤

1. 依据 reference source 构建有长度上限的规划上下文；超长来源需分段摘要，不把全文塞进单请求。
2. 要求模型只返回严格、小型 blueprint JSON；parser 拒绝未知节点、重复 ID、循环依赖和越界规模。
3. 校验总预算：世界观目标不高于 50,000、角色/NPC 不高于 5,000；这是规划目标，不是截断规则。
4. 用户确认后，事务化创建 Section/Part 占位节点和 generation tasks；重新规划保留旧 blueprint 记录但不污染正式树。
5. 固定字段 prompt 仍仅供兼容读取，不能被新 AI 创建路径调用。

## 测试与验收

- 同一规划可产生完全不同的 Section 名称，不依赖 `WorldviewDetails.moduleKeys`。
- 测试无效 JSON、重复/未知 ID、循环依赖、过量节点、预算超限、取消和请求切换。
- planner 不接受或返回正文大字段；单次 payload 大小有明确守卫。
- blueprint 确认前不创建正文，确认后待生成节点顺序稳定。

## 不做事项

不生成 Part 正文、不做 Studio 流式展示、不实现局部重写。它们属于 Phase 5–7。
