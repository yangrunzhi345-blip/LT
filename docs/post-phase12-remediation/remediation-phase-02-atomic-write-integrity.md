# R02 - Atomic Commit & Content Write Integrity

> Priority: P0 | Milestone: A | Status: PLANNED | Dependencies: none
> Findings: M1, M4, M7, M8, TG3, TG6, TG7, TG8

## Purpose

建立统一的写入版本所有权、commit boundary 与失败 durability contract，防止 DB/memory 分叉、用户编辑
被陈旧生成/压缩覆盖，以及 autosave journal 失败后静默丢失。三个 workstream 独立实现和测试，R02 统一验收。

## Current Production Architecture and Exact Bugs

- A Dialogue：chat/engine 先更新内存，再经 repository 写 DB；取消检查与不可逆提交边界错位。提交成功后
  再把内存回滚会制造 DB/UI 分叉（M1）。
- B Part content：生成提交与 compression publish 都写 `resource_parts.content`；候选基于旧 source content，
  写入时缺少同一 source version/content token 的 CAS，能覆盖中途用户编辑（M4/M7）。
- C Autosave：`ResourceAutosaveService` 持有 per-editor debounce buffer，经 autosave repository/journal 和
  `PartContentCommitService` 写入；flush 把 `_writeOne` 不抛当成前提，journal 失败可丢弃内存编辑（M8）。

## Root Cause and Required Contract

根因是多条写路径各自定义“成功”，没有共同的 owner/version/durability invariant。修复后：

1. cancellation 在不可逆 DB commit 前生效；commit 后的 cancellation 只能停止后续副作用，不能伪回滚。
2. part 写入携带 observed source version（或等价不可伪造 token）；CAS 失败返回 typed conflict，不覆盖新内容。
3. compression candidate 绑定 source version，publish 必须验证仍匹配。
4. autosave batch 只有在 journal/commit 成功后才可从内存确认；失败内容保留可重试且不跨 editor 污染。
5. 同一 operation key 的重复提交幂等；失败不能把“未持久化”报告为已保存。

## Workstreams and Exact Implementation Plan

### R02-A - Dialogue commit boundary

- 沿对话发送入口到 engine/repository/SQLite 绘制唯一 commit point。
- 把最后一次 cancellation check 放在 transaction/insert 前；transaction 开始后定义明确 completion result。
- commit 后 UI state 从 committed result 重建，不执行内存伪回滚；后置副作用失败单独报告。
- 增加 barrier-controlled race：cancel-before-commit 不写 DB；cancel-after-commit DB/UI 同一结果；重复取消幂等。

### R02-B - Part CAS and compression source version

- 复用 `PartContentCommitService`/repository 现有版本字段或 revision token；若现有字段不足，只做最小
  schema migration，并保留旧行兼容。
- generation commit、manual edit、compression publish 都进入同一 CAS boundary，禁止旁路 SQL 更新。
- candidate 持久化 source version；publish 使用 `WHERE id=? AND version=?`（或 transaction 内等价比较）。
- CAS miss 返回 typed conflict，保留用户新内容，任务进入可解释的 stale/retry 状态。

### R02-C - Autosave buffer and journal durability

- 明确 pending/in-flight/acknowledged 三态；flush 先 snapshot，不提前清空 authoritative pending buffer。
- journal 或 commit 抛错时合并回 pending；并发新输入不被旧 flush completion 删除。
- editor dispose 尝试最终 flush；失败仍由 journal/pending contract 保留，不用空 catch。
- 同一 editor 串行 flush，不同 editor 独立；不以 `Future.delayed` 修竞态。

## Database Impact

R02-A/C 优先无 schema 变更。R02-B 只有在现有 revision/version 无法表达 CAS 时才允许 schema 44；必须
检查 migration、model、repository、所有读写入口与旧 fixture，使用 transaction 和参数绑定。不得清表或
重写用户内容。实施 Agent 必须先证明现有 version contract 是否可复用。

## Concurrency Sequence

```text
read source(version=v) -> user edit commits(v+1) -> stale generation/compression CAS(v) -> conflict
autosave snapshot A -> new input B -> A fails -> pending = A + B (ordered), not empty
dialogue cancel before transaction -> no row; cancel after commit -> committed state remains authoritative
```

## Test and Mutation Plan

- R02-A：真实 repository/SQLite race，覆盖 commit 前/中/后取消、DB failure、重复操作（TG3）。
- R02-B：manual edit 与 generation/compression barrier race、CAS miss、旧 candidate、成功 version bump（TG6/7）。
- R02-C：journal throw、committer throw、flush 中新输入、dispose、两个 editor 隔离、retry（TG8）。
- Mutation：移除最后 cancellation check、改 CAS 为 unconditional update、flush 前清 buffer，分别必须失败。
- 每个 workstream targeted tests；阶段门禁为 format、analyze、full flutter test、diff-check。

## Acceptance Criteria

- AC-A：任何取消时序均无 DB/UI 分叉。
- AC-B：陈旧生成或压缩永不覆盖用户新内容；conflict typed 且可恢复。
- AC-C：journal/commit 失败不丢 pending 文本；迟到 flush 不删除新输入。
- AC-D：真实 transaction/race tests 与三个 mutation 全部有效；全量门禁通过。

## Files Expected To Change

按当前 symbol 定位：dialogue engine/provider/repository；`part_generation_coordinator.dart`、part content commit/
repository、compression candidate/coordinator；resource autosave service/repository；必要 migration/model；对应
unit/integration tests；`STATUS.md`。不得修改 streaming lifecycle、resource delete/restore、LLM transport。

## Forbidden Scope, Rollback Safety, Handoff

禁止 UI 新功能、context 重构、用锁覆盖所有业务或吞异常。A/B/C 分别提交，任一 workstream 可独立 revert；
若 schema 变更必须用前向补偿 migration，不回滚用户 DB。实施完成仅标记 `IMPLEMENTED`，由独立 Agent
按三组 targeted tests、full suite 和 mutation 统一验收 R02。
