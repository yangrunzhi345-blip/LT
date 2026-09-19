# R05 - Runtime State, Production Wiring & Context Continuity

> Priority: P1 | Milestone: B - Runtime Reliability | Status: PLANNED | Dependencies: R01 ACCEPTED
> Findings: M13, M14, M15, N9, N10, N11, N12, N13, N18, N19, N20, TG11, TG12, TG14, TG15, C14

This phase is the merged successor of the 8-Phase program's former R05 (Async
State & Production Wiring Consistency) and former R06 (Context Budgeting &
Narrative Continuity). See the "Legacy Phase Mapping" section below.

## Purpose

把"异步工作必须绑定 generation + resource/scene identity + current runtime
state"与"context assembly 必须基于当前 authoritative state"统一为一个 Runtime
Consistency Boundary，并使 production 装配与测试装配等价。请求 A 晚于 B 完成时
不得覆盖 B；load/delete/double-click/dispose 后的 callback 不得操作错误资源；
context 每类 source 唯一注入且总量有界；summary 只覆盖它真正覆盖的历史。

## Why former R05 and R06 were merged

两者共享同一条 Runtime Consistency Boundary：

- former R05 处理 async generation ownership、stale completion/error、resource
  identity during async work、double click、load/delete races、dispose、
  production Provider wiring、CRUD creation pipeline、adventure readiness、
  import wiring、prompt/consumer wiring、fallback composition；
- former R06 处理 worldview/character card/summary/history 注入、source
  deduplication、context ordering、context budget、TokenEstimator、summary
  coverage、history trimming、late summary、restart continuity。

它们的共同 invariant：**异步工作 publish 前必须验证 current ownership；context
assembly 必须基于当前 authoritative state，而不是 stale async result。** 拆成
两个阶段会把"谁的结果可以落地"这一裁决拆到两份 contract 里，合并后由统一的
runtime correctness Phase 持有，避免 wiring 修复与 context 修复互相踩踏同一批
controller/assembler 文件。

## Current Production Architecture, Exact Bugs and R01 Delta

Studio/capacity/version 等控制器存在缺 generation/reentrancy guard 的路径
（M14/N9-N13）。CRUD creation pipeline 与 Studio 装配可能分叉，绕过 revision
capture（M15）；adventure start、import 与 prompt contract 测试没有证明真实
生产链（TG11/12/14）。fallback readiness gate 未 attach compression（C14）。
prompt/context builders、`AiGeneratorService`/chat engine 与 summary/history
组件分别注入资源：详细世界观生产路径可无界注入源文本（M13）；同一资料可能多次
注入（N18）；summary coverage 与 history trimming 窗口不同步（N19）；token
estimator 与中文字符计数口径不一致（N20）。TG15 未覆盖真实 production assembly。

R01 后 `streamingGenerationSessionRepositoryProvider` 与
`streamingResourceGenerationServiceProvider` 是共享 owner；`resourceStudioRuntimeProvider`
使用 `ownsService:false`，`sectionControlRuntimeProvider` 复用 Studio
controller，startup recovery 从 `main.dart` 读取 provider。R05 必须保留这些
关系，不得再造第二套 service/repository/recovery wiring。

## Root Cause and Required Contract

- 每个 async operation 捕获 monotonic generation + resource identity；publish
  前同时验证 current、mounted/alive、target 仍匹配。
- destructive/reentrant action 明确 serialise、dedupe 或 reject；按钮禁用只是
  UX，不是并发保证。
- dispose 取消可取消工作并使不可取消 late result 无效。
- production 与 test 从同一 provider/composition root 获得 pipeline/runtime；
  测试只 override 外部边界。
- CRUD 与 Studio 共享带 revision capture 的 creation pipeline。
- fallback readiness 与 production 行为相同或 fail-fast；不能静默缺 compression。
- 每类 context source 只有一个 owner 和稳定 identity，assembly 去重且顺序确定。
- 总 input budget 硬限制；system/safety、current turn、必要角色/世界 facts、
  summary、recent history 有明确优先级。
- summary coverage marker 与被裁 history 原子推进，不留 gap、不重复。
- 使用统一 `TokenEstimator`；服务端 usage 仅用于最终统计，不反向改变已发送 input。
- 超预算执行可解释 trimming，不截断结构化边界，不静默丢失 current turn。

## Workstreams and Exact Implementation Plan

### R05-A — Async State Ownership

覆盖 former R05 的 async correctness。

- 枚举 Resource Studio、capacity、revision/history、library load/delete 与相关
  controller 的 async entrypoints。
- 复用现有 task handle/generation pattern；每次新请求递增 generation，late
  completion 不 publish/write。
- 对 delete/load、双击、resource switch、dispose 建立明确状态机；副作用前再次
  验证 target identity。
- 错误同样受 generation guard，旧请求不能覆盖新请求成功状态。

Required Contract：每次 async operation 捕获 generation + target identity；
publish / side effect 前验证 current、mounted/alive、target 仍匹配。button
disabled 不得作为 concurrency correctness。

### R05-B — Production Wiring Convergence

覆盖 former R05 的 wiring 一致性。

- 抽取/复用唯一 production `ResourceCreationPipeline` provider，让 CRUD 与 R01
  infrastructure 使用同一 revision capture contract；不得复制 coordinator/service。
- 增加 ProviderContainer/真实 SQLite 装配测试，断言 streaming service/session/
  runtime identity 与 R01 现有 test 一致，并覆盖 CRUD revision、adventure
  readiness、import 实际写入。
- 保留 R01 已验证的共享 ownership：`streamingGenerationSessionRepositoryProvider`、
  `streamingResourceGenerationServiceProvider`、`resourceStudioRuntimeProvider`、
  `sectionControlRuntimeProvider`、startup recovery。不得重新创建第二套 runtime。
- 删除 import 死参数可在此实施；C7 的最终 reachability 清理在新 R07 复核。
  （2026-09-19 7→6 重规划后该清理归属 new R06；且 R05-B 已删除 dead
  `repository`/`now` params，C7 记 CLOSED BY R05。）
- prompt 声明字段要么有 parser/consumer，要么删除无消费者指令并有 contract test。
- C14：优先让 fallback 复用可注入 compression link；若无法安全装配则 fail-fast，
  禁止保持静默降级。

### R05-C — Bounded Context Assembly

覆盖 former R06 的 budget/注入正确性。

- 列出 worldview / character cards / summary / history / current turn / system
  instructions 的所有 injection 点，选定唯一 assembler；移除旁路重复注入。
- 为每 source 记录 stable identity、priority、estimated tokens；先按 contract
  分配，再构造 prompt。
- detailed worldview 同样受 budget，不以完整原文绕过；同一资料不得重复注入；
  禁止通过简单 substring 截断结构化内容。
- 全部预估复用统一 `TokenEstimator` 与同一消息序列；中文、emoji、长英文、
  结构化内容覆盖；记录每 section 预算诊断但不输出敏感全文。

### R05-D — Summary / History Continuity

覆盖 former R06 的 coverage/continuity。

- 定义 coverage range/checkpoint；只允许裁剪已经被成功 summary 覆盖的 history。
- summary failed / cancelled / stale 均不得推进 coverage；并发新消息不会被旧
  summary 覆盖；summary completion 已过时不得覆盖新状态。
- restart 后从持久 checkpoint 重建相同上下文边界。

### R05-E — Runtime Integration Tests

合并阶段最重要的新部分：跨 former R05/R06 boundary 的生产路径测试。

- **E1** Context assembly A starts → resource switch → Context B becomes
  current → A finishes late → A cannot publish。
- **E2** Old summary operation → new dialogue messages arrive → old summary
  finishes → must not advance coverage over new messages。
- **E3** Production ProviderContainer → actual context assembler → current
  resource identity 全部来自同一 production composition。
- **E4** CRUD/import changes resource state → subsequent context assembly reads
  authoritative new state，而不是 stale cached source。
- **E5** dispose/runtime replacement → late context/summary result cannot
  mutate new runtime。

## Legacy Phase Mapping

| Former phase | Findings / test gaps carried over | New workstream |
| --- | --- | --- |
| former R05 (Async State & Production Wiring Consistency) | M14, M15, N9, N10, N11, N12, N13, TG11, TG12, TG14, C14 | R05-A / R05-B |
| former R06 (Context Budgeting & Narrative Continuity) | M13, N18, N19, N20, TG15 | R05-C / R05-D / R05-E |

没有任何 finding 或 test gap 因阶段合并被丢弃；全部重新映射到本文件。

## Database Impact and Concurrency Sequence

**Schema change is NOT assumed.** Implementation Agent must first prove whether
durable summary coverage already exists in the current schema/serialization.
Only if no reliable durable summary coverage checkpoint exists may the
implementation propose a **minimal forward migration**（旧记录保守解释为"未确认
覆盖"，不能误删历史）；本规划文档本身绝不修改数据库。

production wiring 会触达 revision transaction，必须用真实 DB 验证。并发序列：
A starts -> B starts/current generation++ -> B publishes -> A completes ->
generation mismatch -> discard。delete 后 late load/result 同样 discard；副作用
已经提交时不伪回滚，按 operation result 刷新 authoritative state。迟到 summary
被 generation/task handle 丢弃；checkpoint 与 summary 在 transaction 内同步。

## Test and Mutation Plan

- barrier tests：A/B inversion、resource switch、load/delete race、double tap、
  dispose、late error（R05-A）。
- TG11：真实 ChatProvider/adventure composition，未 ready fail-closed、ready 可
  启动。TG12：import 断言 tree/bridge/DB 实际写入。TG14：prompt keys 与
  parser/consumer contract。
- production ProviderContainer 断言 R01 shared instance、CRUD revision capture、
  fallback compression/fail-fast（R05-B）。
- TG15 production assembler：超长 worldview/cards/history，断言总预算、唯一注入、
  current turn 保留（R05-C）。
- summary boundary：失败、取消、迟到、restart、coverage gap、exact edge
  （R05-D）。
- estimator fixtures：中英混合、emoji、空内容、大输入；同一输入各调用方一致。
- E1-E5 runtime integration matrix（R05-E）。
- Mutation：移除 generation check、给 CRUD 第二套 pipeline、断开 readiness
  injection、恢复 dead import assert、移除 compression link、绕过 detailed
  worldview budget、双重注入、先 trim 后 summary commit、改用字符数。全量门禁
  必需。

## Acceptance Gate

新 R05 只有一次 Independent Acceptance，但验收必须**分别检查 R05-A / R05-B /
R05-C / R05-D / R05-E**，不得因阶段合并降低验收。必须同时满足：

- stale async result cannot publish
- destructive actions converge（serialise/dedupe/reject 有证据）
- production/test wiring equivalent
- R01 runtime ownership unchanged
- all production prompts bounded
- source injection unique
- summary/history no gap
- stale summary rejected
- restart continuity verified
- production integration tests pass（E1-E5）
- mutations effective
- full regression pass

迟到结果/错误不能覆盖当前资源；重复动作不会重复 destructive side effect；dispose
后无 publish；测试与生产 composition root 一致；CRUD 保存有 revision；
adventure/import/prompt/fallback 均有 production-path 证据；所有 production
prompt 有硬上限；每 source 最多一次；失败不推进 coverage；统一 estimator；长对话
regression 通过；R01 ownership/recovery tests 继续通过。

## Files Expected To Change

Resource Studio/相关 async controllers、`riverpod_providers.dart`、CRUD
controller/pipeline、adventure provider/readiness wiring、import use cases、
prompt builder/parser contract、context/prompt assembler、chat engine internals、
AI generator context path、summary/history service/model/repository、
TokenEstimator 调用点、必要（仅在证明缺失后）的 minimal migration、production
wiring/race/integration tests、`STATUS.md`。

## Forbidden Scope, Rollback Safety, Handoff

禁止用任意 delay、`mounted` 单独替代 generation、为测试保留第二套生产逻辑；禁止
靠截字符串隐藏溢出、删除历史、将服务端 output usage 当 input tokenizer、引入第二
estimator；不得修改 R01 lifecycle ownership、LLM transport policy、resource
delete/part CAS、DB schema（除非按上述规则证明缺失后的 minimal forward
migration）或 UI 新功能。Workstream 聚焦提交；migration 若有，采用前向补偿。
实现完成仅标记 `IMPLEMENTED`；独立 Agent 分别对照 A-E 验收。
