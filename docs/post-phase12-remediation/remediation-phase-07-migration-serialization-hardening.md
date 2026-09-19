# R07 - Migration, Serialization & Defensive Hardening

> Priority: P2 | Milestone: C | Status: BLOCKED | Dependencies: Milestones A and B complete
> Findings: N1, N2, N3, N16, N17

## Purpose

在 correctness 稳定后强化 migration、corrupt-row isolation、enum/JSON 兼容，不把 P0/P1 生产问题降级到
本阶段。Schema 仍以当时最新生产版本为准，不能机械假定 43。

## Current Production Architecture and Exact Bugs

`DatabaseService` 管理 onConfigure/onUpgrade 与历史 migration；部分 migration 在 transaction 内切换
`PRAGMA foreign_keys`（可能无效，N1），坐标归一化等步骤可能非幂等（N3）。library row mapping 的宽 catch
可把单坏行放大为整列表空（N2）。`WorldEntry` 与若干 enum 使用序数/不一致 unknown policy，JSON 损坏可能
导致整批失败（N16/N17）。

## Root Cause and Required Contract

- FK 策略在 transaction 外正确设置并在升级后恢复/验证。
- data migration 重跑不改变已迁数据；每步有明确输入域/marker。
- 单坏行隔离且可诊断，不能伪装为空库；身份关键字段 fail-closed，可选字段按统一 policy fallback。
- 新写入使用稳定 string code；读取兼容 legacy ordinal/code，枚举声明重排不改变语义。

## Workstreams and Exact Implementation Plan

### R07-A - Migration behavior

- 用旧版本 fixture 实测 FK 状态、升级顺序、失败 rollback 与重复执行；修正 PRAGMA ownership。
- 为归一化步骤增加输入域/迁移标记，使第二次执行 no-op；不改历史版本号含义。

### R07-B - Corrupt row isolation

- repository 按 row decode；typed diagnostic 包含 table/id/error category，不记录敏感 payload。
- 返回其余合法行；调用方可区分“空结果”与“存在损坏”。关键 identity 损坏不得猜默认值。

### R07-C - Stable serialization

- 复用/建立统一 enum codec；先读 legacy ordinal，再写稳定 code；非法 JSON 有字段级 policy。
- WorldEntry keys/position 与审计列举 enum 全部建 compatibility fixtures。

## Database Impact and Concurrency

原则上不升 schema；若必须修复未来 upgrade hook，只修改尚未发布的新 migration 或追加前向 migration，绝不
篡改已部署语义。migration 使用单连接、事务化步骤和 upgrade 后 FK check；失败保留原 DB 可再次升级。

## Test and Mutation Plan

- v42/更早 fixture -> 当前 schema；FK parent/child；中途失败；重复升级/normalization。
- 单坏 row + 多好 row；坏 JSON、unknown enum、越界 ordinal、枚举重排 compatibility。
- Mutation：恢复 transaction 内无效 PRAGMA、无界 normalization、table-wide catch、ordinal-only decode，测试失败。
- targeted migration/serialization suites、full flutter test、analyze/format/diff-check。

## Acceptance Criteria

升级 FK 行为真实可验证；migration 幂等；单坏行不清空集合且有诊断；stable code 与 legacy 兼容；schema 与
用户数据不被破坏；全部旧 migration fixtures 与 full regression 通过。

## Files Expected To Change

`database_service.dart`、migration helpers/tests、library/tree row mapper/repository、WorldEntry 与 enum codecs、
serialization fixtures、`STATUS.md`。不得修改 P0/P1 correctness contract、删除表列或做 cleanup。

## Forbidden Scope, Rollback Safety, Dependencies, Handoff

Milestones A/B 未完成不得实施，以免在变化中的 schema/wiring 上 harden。禁止 catch-all 返回空、猜 identity、
清库或重排历史 migration。代码可 revert；已执行 DB 只能用前向补偿。完成仅 `IMPLEMENTED`，独立 Agent
用历史 fixture 与 mutation 验收。
