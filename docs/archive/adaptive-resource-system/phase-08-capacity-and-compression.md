# Phase 8 — 字数策略与语义压缩执行方案

## 目标与交付物

实现统一容量状态和分块语义压缩。超限内容始终可以保存完整原稿；系统推荐或后台执行压缩，绝不直接截断。

## 唯一代码范围

- 集中式字符计数器与 `NORMAL/ELASTIC/OVERFLOW` 状态计算。
- 世界观阈值 50,000/60,000，角色和 NPC 阈值 5,000/6,000。
- 手动压缩及离开编辑器后的后台 compression job。
- 按 Section/Part 生成压缩候选，保留关键事实、名称、规则、约束和关系；合并结果仍通过节点 patch 挂载。

## 压缩流程

1. 快照原稿 revision 接口（正式版本实现由 Phase 9 完成，未接入前不得自动替换）。
2. 计算各 Section 冗余度和目标预算，生成 Part 级任务。
3. 每个任务只处理一个 Part 或受限相邻 Part，返回压缩正文及保留项摘要。
4. 完成后重新计数和语义校验；失败保留原稿并允许局部重试。
5. 用户手动确认或后台策略切换到压缩候选；不满足目标时报告原因，不循环无限压缩。

## 主要修改文件

- `resource_limits.dart` 与新 `resource_capacity_service.dart`
- 新 `compression_job` model/repository/coordinator
- LLM task policy、压缩 prompt builder、job runner
- Studio 容量状态与手动压缩入口
- 字符边界、取消恢复、关键事实保持测试

## 测试与验收

- 49,999/50,000/50,001/60,000/60,001 及角色对应边界均有精确测试并符合定义。
- OVERFLOW 保存成功且原稿逐字符不变；代码中无 substring/truncate 作为容量处理。
- 离开编辑器仅排队，不阻塞导航；同资源同 revision 的 job 去重。
- 网络失败、取消、部分成功、应用重启后可恢复，且无无限重试。
- prompt/响应均以有限节点为边界；压缩不会生成巨型 JSON。

## 不做事项

不决定 Adventure 使用哪个版本；本阶段只产出压缩候选和容量状态，assembly revision 由 Phase 10 管理。
