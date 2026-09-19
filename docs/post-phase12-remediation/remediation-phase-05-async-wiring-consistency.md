# R05 - Async State & Production Wiring Consistency

> Priority: P1 | Milestone: B | Status: BLOCKED | Dependency: R01 ACCEPTED
> Findings: M14, M15, N9, N10, N11, N12, N13, TG11, TG12, TG14, C14

## Purpose

让异步 UI/controller state 具备明确 generation ownership，并使测试装配等价于生产装配。请求 A 晚于 B
完成时不得覆盖 B；load/delete/double-click/dispose 后的 callback 不得操作错误资源。

## Current Production Architecture, Exact Bugs and R01 Delta

Studio/capacity/version 等控制器存在缺 generation/reentrancy guard 的路径（M14/N9-N13）。CRUD creation
pipeline 与 Studio 装配可能分叉，绕过 revision capture（M15）；adventure start、import 与 prompt contract
测试没有证明真实生产链（TG11/12/14）。fallback readiness gate 未 attach compression（C14）。

R01 后 `streamingGenerationSessionRepositoryProvider` 与
`streamingResourceGenerationServiceProvider` 是共享 owner；`resourceStudioRuntimeProvider` 使用
`ownsService:false`，`sectionControlRuntimeProvider` 复用 Studio controller，startup recovery 从 `main.dart`
读取 provider。R05 必须保留这些关系，不得按旧 R11 再造 service/repository/recovery wiring。

## Root Cause and Required Contract

- 每个 async operation 捕获 monotonic generation + resource identity；publish 前同时验证 current、mounted。
- destructive/reentrant action 明确 serialise、dedupe 或 reject；按钮禁用只是 UX，不是并发保证。
- dispose 取消可取消工作并使不可取消 late result 无效。
- production 与 test 从同一 provider/composition root 获得 pipeline/runtime；测试只 override 外部边界。
- CRUD 与 Studio 共享带 revision capture 的 creation pipeline。
- fallback readiness 与 production 行为相同或 fail-fast；不能静默缺 compression。

## Workstreams and Exact Implementation Plan

### R05-A - Async ownership

- 枚举 Resource Studio、capacity、revision/history、library load/delete 与相关 controller 的 async entrypoints。
- 复用现有 task handle/generation pattern；每次新请求递增 generation，late completion 不 publish/write。
- 对 delete/load、双击、resource switch、dispose 建立明确状态机；副作用前再次验证 target identity。
- 错误同样受 generation guard，旧请求不能覆盖新请求成功状态。

### R05-B - Production wiring convergence

- 抽取/复用唯一 production `ResourceCreationPipeline` provider，让 CRUD 与 R01 infrastructure 使用同一
  revision capture contract；不得复制 coordinator/service。
- 增加 ProviderContainer/真实 SQLite 装配测试，断言 streaming service/session/runtime identity 与 R01
  现有 test 一致，并覆盖 CRUD revision、adventure readiness、import 实际写入。
- 删除 import 死参数可在此实施；C7 的最终 reachability 清理在 R08 复核，不重复删除。
- prompt 声明字段要么有 parser/consumer，要么删除无消费者指令并有 contract test。
- C14：优先让 fallback 复用可注入 compression link；若无法安全装配则 fail-fast，禁止保持静默降级。

## Database Impact and Concurrency Sequence

无预期 schema 变更。production wiring 会触达 revision transaction，必须用真实 DB 验证。序列：A starts ->
B starts/current generation++ -> B publishes -> A completes -> generation mismatch -> discard。delete 后 late load/result
同样 discard；副作用已经提交时不伪回滚，按 operation result 刷新 authoritative state。

## Test and Mutation Plan

- barrier tests：A/B inversion、resource switch、load/delete race、double tap、dispose、late error。
- TG11：真实 ChatProvider/adventure composition，未 ready fail-closed、ready 可启动。
- TG12：import 断言 tree/bridge/DB 实际写入，不用恒真 mock verify。
- TG14：prompt keys 与 parser/consumer contract。
- production ProviderContainer 断言 R01 shared instance、CRUD revision capture、fallback compression/fail-fast。
- Mutation：移除 generation check、给 CRUD 第二套 pipeline、断开 readiness injection、恢复 dead import assert、
  移除 compression link，测试必须失败。全量门禁必需。

## Acceptance Criteria

迟到结果/错误不能覆盖当前资源；重复动作不会重复 destructive side effect；dispose 后无 publish；测试与生产
composition root 一致；CRUD 保存有 revision；adventure/import/prompt/fallback 均有 production-path 证据；
R01 ownership/recovery tests 继续通过。

## Files Expected To Change

Resource Studio/相关 async controllers、`riverpod_providers.dart`、CRUD controller/pipeline、adventure provider/
readiness wiring、import use cases、prompt builder/parser contract、production wiring/race tests、`STATUS.md`。
不得修改 R01 lifecycle、LLM transport policy、context budget 或 DB schema。

## Forbidden Scope, Rollback Safety, Dependencies, Handoff

R01 未 `ACCEPTED` 不得开始。禁止用任意 delay、`mounted` 单独替代 generation、或为测试保留第二套生产逻辑。
A/B 分开提交、无 schema 可 revert。实现完成仅为 `IMPLEMENTED`；独立 Agent 对照 R01 providers、真实 DB
副作用与 mutation 验收。
