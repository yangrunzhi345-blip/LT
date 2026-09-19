# R04 - LLM Transport & Streaming Protocol Reliability

> Priority: P1 | Milestone: B | Status: BLOCKED | Dependency: R01 ACCEPTED
> Findings: M2, M3, M10, N15, TG1, TG13

## Purpose

统一 HTTP -> SSE -> provider decode -> consumer callback -> patch parser -> validator -> coordinator 的 timeout、
retry 与 typed failure ownership。网络读取持续消费；UI 节流不得阻塞 transport。

## Current Production Architecture, Exact Bugs and R01 Delta

`LLMService` 负责 provider HTTP/SSE，`AiGeneratorService` 与调用方还有内容级 retry，
`PartGenerationCoordinator` 通过 streaming gateway 将 chunk 交给 patch parser/validator。旧代码无完整 timeout，
多层 retry 相乘（M2/M3）；provider decode catch 可吞 consumer/parser exception（M10）；非流与流协议分叉
（N15），测试偏向非生产分支（TG1/TG13）。

R01 已建立共享 streaming service/session repository、generation failure convergence、completed regeneration、
startup recovery 和 production ownership tests。因此本 Phase 不重建 provider、不再实现 recovery，也不改变
session terminal contract；typed transport/protocol failure必须汇入 R01 已定义的 `failed`/可恢复收敛路径。

## Root Cause and Required Contract

- transport timeout 只有一个 owner，覆盖 connect、首事件、idle/read 与总 deadline，取消可立即终止。
- transport retry 与 content retry 各有明确预算；总 attempts 可计算，禁止嵌套指数相乘。
- `receivedAnyDelta` 只在有效 content delta 被接受后为 true；usage/keepalive/坏事件不算内容。
- provider decode noise 可按政策跳过并计数；consumer/parser/validator exception 原样或 typed 传播，绝不吞。
- streaming 与 fallback 使用同一 patch protocol、sequence/cursor validation 和 completion semantics。

## Workstreams and Exact Implementation Plan

### R04-A - Timeout ownership

- 枚举所有 HTTP/SSE 创建点，集中 timeout policy；取消 subscription/client 并保留 timeout phase 信息。
- 覆盖 never-connect、headers 后无 body、delta 后 stall、正常 `[DONE]`、user cancellation。

### R04-B - Retry budget

- 列出 `LLMService`、`AiGeneratorService`、coordinator 的 retry loops，区分 transport transient 与 content invalid。
- 由上层 operation budget 限制总 attempts/backoff；429/5xx/timeout 与 4xx/schema error 分类；无无限重试。
- 已收到有效 delta 后默认不透明 transport replay，避免重复内容/计费；由 typed failure交给业务恢复。

### R04-C - Decode and consumer errors

- 把 provider JSON decode try/catch 与 `onChunk` 调用分离；consumer stack trace 保留并停止订阅。
- malformed provider event 按阈值处理，不能把整流损坏伪装成空成功；usage 最终 flush 不丢失。
- coordinator 将 parser/sequence/cursor/validation error 映射为 typed protocol failure并走 R01 convergence。

### R04-D - Protocol convergence and production tests

- streaming/fallback 复用 `GenerationPatchParser` 与 accumulator；保留严格字段白名单，必要时仅容忍 fence。
- fake 实现 production streaming gateway，支持跨 chunk 行、无末尾换行、空/大 chunk、异常和取消。
- 测试真实 shared provider/service path，不复制 R01 infrastructure。

## Database Impact and Concurrency

无 schema 变更。失败状态持久化复用 R01 repository。取消、timeout、consumer throw、late chunk 的唯一序列：
停止 transport -> 丢弃迟到事件 -> final usage/known state flush -> R01 session convergence；dispose 后不得通知。

## Test and Mutation Plan

- TG13：精确断言每类故障的最大 attempts 与 backoff，不用 wall-clock flaky wait。
- TG1：production-shape streaming normal、split line、bad JSON、consumer throw、sequence gap、stall、cancel。
- 高频小 chunk、单大 chunk、空 chunk、末尾 buffer、request switch、usage missing 均覆盖。
- Mutation：移除 idle timeout、恢复双层 retry、把 consumer call 放回 decode catch、让 fake 走 non-streaming，
  各测试必须失败。
- targeted + production-path + full suite + analyze/format/diff-check。

## Acceptance Criteria

transport 永不无限挂起；总 retry 有界可审计；consumer/protocol error typed 且到达 R01 failure state；正常流
不因 keepalive 误判；test wiring 与 production streaming path 相同；R01 35 项回归与全量测试仍通过。

## Files Expected To Change

`llm_service.dart`、LLM policy/config、`ai_generator_service.dart`、gateway adapter、
`part_generation_coordinator.dart`、generation patch parser/validator、streaming fakes/tests、`STATUS.md`。
不得修改 R01 lifecycle/provider ownership、DB schema、resource deletion 或 context assembly。

## Forbidden Scope, Rollback Safety, Dependencies, Handoff

R01 未 `ACCEPTED` 不得开始。禁止自动重放已产生 delta 的计费请求、用 UI timer throttle 网络读取、将所有
错误包装成同一字符串。A-D 聚焦提交，可整体 revert 且无 schema 副作用。实施后仅标记 `IMPLEMENTED`，
独立 Agent 必须验证 R01 contract 未被改写及 mutation 有效。
