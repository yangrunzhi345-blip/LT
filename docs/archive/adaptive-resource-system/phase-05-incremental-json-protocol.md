# Phase 5 — 增量 JSON 多轮生成协议执行方案

## 目标与交付物

实现以单个 Part 为主要原子、以小型 patch 为传输格式的多轮生成引擎。失败、重试、取消和请求切换均局部化，任何调用都不得生成或回传完整资源 JSON。

## 唯一代码范围

- generation task、节点 lease、generation cursor 与小型 patch 协议。
- 按 Blueprint 依赖调度 Part 任务；局部解析、验证、挂载和持久化。
- 重试、幂等、取消、迟到响应隔离和断点续跑。
- 复用 `GenerationRequestScheduler`、`GenerationTaskHandle`、统一 LLM service；不新增第二套 HTTP client。

## Patch 契约

允许的操作限定为 `start_part`、`append_text`、`complete_part`、`fail_part`。每个 patch 必须包含 generation ID、resource/section/part ID、单调 sequence 和有限正文片段。服务端输出不能创建任意父节点，不能修改其他 Part，不能携带整棵树。

## 主要修改文件

- 新建 `lib/domain/resources/resource_generation_patch.dart`
- 新建 `lib/application/resources/incremental_generation_coordinator.dart`
- 新建 `lib/application/resources/generation_patch_parser.dart`
- 新建 generation task repository/table
- 扩展 LLM task policy 和 prompt builder
- 增加高频 chunk、重试、恢复及乱序测试

## 实施步骤

1. 从已确认 Blueprint 生成有向无环任务队列；只有依赖完成的 Part 可调度。
2. 网络层立即消费 stream，按行/事件解析 patch；不得因 UI 节流暂停读取。
3. 以 `(generation_id, part_id, sequence)` 幂等写入，重复 patch 无副作用，sequence 缺口进入可恢复失败。
4. Part 完成后执行最终校验和原子状态转换；失败只影响该 Part，可从最后确认 cursor 重试。
5. generation/task handle 失效后丢弃迟到 patch；取消时关闭订阅并持久化已确认进度。

## 测试与验收

- 覆盖高频小 chunk、单个大 chunk、空 chunk、结束仍有缓冲、无效 JSON、乱序/重复 sequence。
- 覆盖取消后迟到 chunk、旧 generation 覆盖防护、应用重启续跑、单 Part 重试。
- 生成一个大型 fixture 时，每次模型请求和数据库事务均只触及有限节点。
- `rg` 确认新路径不存在“完整 Resource JSON”请求字段或一次性树保存。
- 任一 Part 失败不会抹除已完成 Part。

## 不做事项

不实现可视化工作台、编辑操作、压缩或 revision UI；本阶段只交付可靠生成协议。
