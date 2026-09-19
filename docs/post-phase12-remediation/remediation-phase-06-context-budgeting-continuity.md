# R06 - Context Budgeting & Narrative Continuity

> Priority: P1 | Milestone: B | Status: PLANNED | Dependencies: none
> Findings: M13, N18, N19, N20, TG15

## Purpose

为 worldview、character cards、summary、history 建立单一、可预算、连续的 context assembly contract。该边界
独立于 DB lifecycle，避免把 narrative policy 混入 R02/R03。

## Current Production Architecture and Exact Bugs

prompt/context builders、`AiGeneratorService`/chat engine 与 summary/history 组件分别注入资源。详细世界观
生产路径可无界注入源文本（M13）；同一资料可能多次注入（N18）；summary coverage 与 history trimming
窗口不同步（N19）；token estimator 与中文字符计数口径不一致（N20）。TG15 未覆盖真实 production assembly。

## Root Cause and Required Contract

- 每类 source 只有一个 owner 和稳定 identity，assembly 去重且顺序确定。
- 总 input budget 硬限制；system/safety、current turn、必要角色/世界 facts、summary、recent history 有明确优先级。
- summary coverage marker 与被裁 history 原子推进，不留 gap、不重复。
- 使用统一 `TokenEstimator`；服务端 usage 仅用于最终统计，不反向改变已发送 input。
- 超预算执行可解释 trimming，不截断结构化边界，不静默丢失 current turn。

## Workstreams and Exact Implementation Plan

### R06-A - Source ownership and bounded assembly

- 列出 worldview/card/summary/history 的所有 injection 点，选定唯一 assembler；移除旁路重复注入。
- 为每 source 记录 identity、priority、estimated tokens；先按 contract 分配，再构造 prompt。
- detailed worldview 同样受 budget，不以完整原文绕过。

### R06-B - Summary coverage and continuity

- 定义 coverage range/checkpoint；只裁剪已被成功 summary 覆盖的 history。
- summary 失败/取消时不推进 checkpoint；并发新消息不会被旧 summary 覆盖。
- restart 后从持久 checkpoint 重建相同上下文边界。

### R06-C - Estimation consistency

- 全部预估复用统一 TokenEstimator 与同一消息序列；中文、emoji、长英文、结构化内容覆盖。
- 记录每 section 预算诊断但不输出敏感全文。

## Database Impact and Concurrency

优先无 schema 变更；若当前 summary coverage 无持久字段，允许最小 migration，但须旧记录保守解释为“未
确认覆盖”，不能误删历史。generation/task handle 丢弃迟到 summary；transaction 同步 checkpoint 与 summary。

## Test and Mutation Plan

- TG15 production assembler：超长 worldview/cards/history，断言总预算、唯一注入、current turn 保留。
- summary boundary：失败、取消、迟到、restart、coverage gap、exact edge。
- estimator fixtures：中英混合、emoji、空内容、大输入；同一输入各调用方结果一致。
- Mutation：绕过 detailed worldview budget、双重注入、先 trim 后 summary commit、改用字符数，测试必须失败。
- targeted、production path、full suite、analyze/format/diff-check。

## Acceptance Criteria

所有 production prompt 有硬上限；每 source 最多一次；summary/history 无 gap/重复；失败不推进 coverage；
统一 estimator；TG15 与 mutations 有效，长对话 regression 通过。

## Files Expected To Change

context/prompt assembler、chat engine internals、AI generator context path、summary/history service/model/repository、
TokenEstimator 调用点、必要 migration 与 production-path tests、`STATUS.md`。不得修改 resource delete、part CAS、
LLM transport retries 或 UI 新功能。

## Forbidden Scope, Rollback Safety, Dependencies, Handoff

禁止靠截字符串隐藏溢出、删除历史、将服务端 output usage 当 input tokenizer、引入第二 estimator。各 workstream
聚焦提交；若 migration，采用前向补偿。技术上无 R01 依赖，可规划并行；单 Agent 仍按里程碑顺序。完成后
只标记 `IMPLEMENTED`，独立 Agent 用 production assembler 和 continuity fixtures 验收。
