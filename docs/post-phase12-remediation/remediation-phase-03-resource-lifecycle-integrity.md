# R03 - Resource Identity, Delete, Trash & Revision Lifecycle

> Priority: P0 | Milestone: A | Status: PLANNED | Dependencies: none
> Findings: M9, M11, M12, N4, N5, N6, N7, N14, TG9, TG10, CP-2

## Purpose

为 legacy row 与 unified tree 建立权威 identity，并把 live -> soft deleted -> trash -> restore/gone 与 revision
统一为一个状态机。永久删除不得留下语义有效孤儿，revision 不得绕过 trash 偷偷复活资源。

## Current Production Architecture and Exact Bugs

`LegacyCreationBridge` 创建/迁移 tree shadow 与 legacy row；tree/trash/revision repositories 分别处理删除、
恢复、快照和 retention。当前复用或推导 id 却没有足够 identity contract；树删除可能留下 legacy 数据，
永久删除可能留下辅助行（M11/M12/N4/N6/N14）。revision/child restore 只验证 token/父行存在，未一致验证
`deleted_at`，可复活回收站资源或形成悬挂子节点（M9/N5/N7）。TG9/TG10 缺少真实生命周期回归。

## Root Cause and Required Contract

一个逻辑资源只有一个 canonical identity；legacy/tree 映射必须可查询、不可猜测。合法状态：

```text
live -> soft-deleted/trash -> restore -> live
                         \-> permanent delete -> gone
```

revision 是 live 资源的历史，不是越过 trash/gone 的复活入口。永久删除 transaction 必须删除/失效全部
语义依赖；retention 只能处理已在 trash 的对象，并保持 parent/child、revision、task、mapping 一致。

## Workstreams and Exact Implementation Plan

### R03-A - Identity

- 审计 bridge、migration records、legacy repositories 与 tree lookup 的所有创建/查找入口。
- 选择现有 migration mapping 作为权威关系或补充最小映射；禁止靠相等整数 id 推断身份。
- 对 pre-tree legacy row、已有 shadow、重复 migration 定义幂等 lookup/create 行为。

### R03-B - Trash and delete

- 所有删除入口进入统一 lifecycle service；soft delete 在 transaction 中标记 canonical tree 并同步 identity side。
- restore 验证映射、父状态和资源未 gone；永久删除事务覆盖 tree、legacy row 与明确所有权的辅助状态。
- DB failure 整体 rollback，不允许 UI 报删除成功而任一 authoritative row 仍 live。

### R03-C - Revision restore

- restore revision 前读取 canonical lifecycle；trash/gone 时拒绝 typed error，不能通过 revision 隐式改 `deleted_at`。
- child restore 同时验证 parent live、child identity 和 revision belongs-to；CP-2 在此闭合。
- 若产品要从 trash 恢复，必须先执行显式 trash restore，再允许 revision restore。

### R03-D - Retention and cascade

- 列出 revision、generation/session/task、autosave/compression/mapping 等辅助表的 ownership 分类。
- retention 仅选择超过期限且 soft-deleted 的 canonical resource；每资源 transaction、失败可重试。
- 不属于资源所有权的数据不级联；对需保留的审计记录做明确 tombstone，而非孤儿活引用。

## Database Impact

可能需要 identity/mapping constraint 或索引；实施前检查 schema 43、migration records 与所有 legacy fixture。
migration 必须幂等、旧数据可回填、冲突 fail-closed，并在 transaction 中完成。禁止以清空 legacy 表解决。

## Concurrency Sequence

```text
delete vs restore: canonical state/version 决定唯一胜者
revision restore while trash: reject; no writes
permanent delete: mark/validate -> cascade owned rows -> remove canonical identity -> commit
late legacy bridge create after gone: mapping/tombstone prevents resurrection
```

## Test and Mutation Plan

- TG9：live/trash/gone 下 revision 与 child restore 的真实 SQLite matrix。
- TG10：legacy-only、tree-only、mapped pair、parent/child、辅助行的 soft/permanent delete/restore/retention。
- 覆盖并发 delete/restore、transaction failure、重复调用、旧 DB migration 与 restart 后读取。
- Mutation：恢复 id-equality 推断、移除 `deleted_at` guard、遗漏一种 owned auxiliary table、拆散 transaction，
  测试必须失败。
- format、analyze、targeted、full flutter test、diff-check 全部通过。

## Acceptance Criteria

- 每个逻辑资源 identity 唯一且可追踪；旧资源不会因 tree shadow 删除后重新出现。
- trash/gone 不能被 revision 或 child restore 绕过；显式 restore 后历史仍可用。
- 永久删除无语义有效孤儿；retention 幂等、事务化、可恢复。
- TG9/TG10 与 mutation 证明生产 repository 路径，而非纯 mock。

## Files Expected To Change

`LegacyCreationBridge`、tree/library/trash/revision repositories/services、migration record 与相关 model、必要的
database migration、Riverpod lifecycle wiring、SQLite integration tests、`STATUS.md`。不得修改 part CAS、LLM
transport、context budgeting 或 cleanup candidates。

## Forbidden Scope, Rollback Safety, Handoff

禁止资源模型重写、物理删除未知用户数据、用 revision restore 兼做 trash restore。A-D 分簇提交；schema
变更只能前向补偿。实现报告必须附 ownership/cascade 表与旧 fixture 结果；只标记 `IMPLEMENTED`，独立
Acceptance Agent 统一验收 R03。
