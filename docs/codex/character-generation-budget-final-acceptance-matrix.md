# 角色生成预算修复：最终验收矩阵（U6-B/C/D/E + R1–R6 + Phase + T01–T31）

Baseline（origin/main）: `8ad0680`
Working branch: `fix/u6d-legacy-review-final-20261014`
Status: **ACCEPTED WITH EXPLICIT SCOPE LIMITATIONS**（已授权范围通过；T31 未授权；真实模型/真机 NOT VERIFIED）
Acceptance Mode: Independent Review（各工作单元由另一只读 Agent 审查）

> 本矩阵是正式验收依据。各 SHA 为对应工作单元提交；测试证据见各单元进度记录与 `/tmp/lt-*.log`。
> 不得把“某单元局部 PASSED”等同于整体 Phase 完成；T31 未授权即整体不能标 ACCEPTED。

## FULL REGRESSION

- `flutter test --no-pub`（全仓，372 个 `*_test.dart`）：**+4089 PASS / ~7 SKIP / 0 FAIL，退出码 0**（12m33s）；
  日志 `/tmp/lt-p2-full.log`。
- 首轮曾 **+4082 ~7 -1**：唯一失败是 U6-D 引入的真实回归
  （`r05_async_state_ownership_test.dart` 的 `_ScriptedStudioRuntime` 未实现新增
  `blueprintPartContracts` 且以 `noSuchMethod` 抛错）；已最小修复测试夹具。
- **PR #7 P2 反馈修复**：损坏/不兼容的关联 Blueprint JSON 曾使 `ResourceStudioController.load()` 整体失败；
  已在可选蓝图读取边界（契约投影 + `ensureSession`）实施 fail-quiet 降级为 `unavailable`，
  主体资源树读取仍致命。复现与回归见 `u6d_contract_projection_resilience_sqlite_test.dart`（6 PASS）。
- `flutter analyze --no-pub`：No issues found!　`dart format --output=none --set-exit-if-changed lib test`：
  885 文件 0 changed。`git diff --check`：PASS。
- main@`8ad0680` 的 GitHub Actions Quality gate 此前已通过（含完整 `flutter test`）。

## R1–R6 + E50

| 单元 | 状态 | 提交 | 关键测试 | 独立审查 | 未解决 |
| --- | --- | --- | --- | --- | --- |
| R1 预算可行性与 future reserve | PASSED | `295c7e6` | `generation_budget_allocation_test`, `character_generation_budget_reservation_sqlite_test` | `…r1-reservation-independent-review.md` PASSED | MINOR×4 |
| R2 正文完成契约 + K 守卫 | PASSED | `064eb42` | `character_generation_content_contract_sqlite_test`, `part_generation_validator_test` | `…r2-content-contract-independent-review.md` PASSED | MINOR×2 |
| R3 协议冲突 seq 拒绝 | PASSED | `2144a40` | `generation_patch_parser_test`, `patch_sequence_conflict_sqlite_test` | `…phase2-protocol-independent-review.md` PASSED | — |
| R4 规划单段上界 | PASSED | `09a49ea` | `blueprint_budget_normalizer_test`, `blueprint_validator_test` | `…r4-planning/regression-independent-review.md` PASSED | — |
| R5 失败分类 + 安全数值 + 恢复 | PASSED | `fb4ba8f`,`a74120e` | `character_generation_retry_recovery_sqlite_test`, `resource_generation_error_test` | `…r5-classification-independent-review.md` PASSED | MINOR×2 |
| R6 心跳诊断生命周期 | PASSED | `0932c6d` | `generation_diagnostics` 相关 | `…r6-diagnostics-independent-review.md` PASSED | — |
| E50 弹性预算 UI→SQLite | PASSED | `e33206f` | `e50_elastic_budget_end_to_end_test.dart` | `e50-…-independent-review.md` PASSED WITH FINDINGS（MINOR 已修） | — |

## U6-A–E

| 单元 | 状态 | 提交 | 本轮实际验证 | 兼容性结论 | 已知限制 |
| --- | --- | --- | --- | --- | --- |
| U6-A Narrative 动态最低量纯函数 | APPROVED / IMPLEMENTED / VERIFIED | `e89e187` | `narrative_minimum_policy_test` 22 PASS；独立审查 PASSED | 纯整数、无浮点，不改预算公式 | — |
| U6-B 动态契约生产接线 | APPROVED / IMPLEMENTED / VERIFIED | `cf17555` | 契约规划器 14 + Confirm SQLite 8 + Review Widget 4；独立审查 PASSED（无确认路径绕过） | 仅新增可选版本化标记；旧蓝图 legacy 放行 | Scalar/Structured 类型选择 UI 未实现 |
| U6-C 生成/校验/提交/重试闭环 | IMPLEMENTED / VERIFIED | `96ea31b` | `u6c_content_contract_production_chain_test` 22 PASS；独立审查 PASSED WITH FINDINGS | 未改生产代码（R2/R1/R5 已闭环） | — |
| U6-D Legacy 只读审阅提示 | IMPLEMENTED / VERIFIED | `7193b52` | 领域 7 + SQLite 5 + Widget 8；独立审查 VERIFIED | 无 schema/迁移；仅 legacy 提示；不改历史数据 | — |
| U6-E 跨模块综合回归 | IMPLEMENTED / VERIFIED | `1337b89` | `u6e_cross_module_integration_test` 5 + 既有跨模块 133；独立审查 PASS | 装配就绪/压缩候选不变 | 真实设备/模型 NOT VERIFIED |

## Phase 1–6

| Phase | 状态 | 依据 |
| --- | --- | --- |
| 1 内容契约与数据保护基线 | IMPLEMENTED（局部门禁 PASS） | `ea5de88` + U6-A/B 接线；旧数据 SQLite 保护测试 PASS |
| 2 配置快照与解析完整性 | IMPLEMENTED（局部门禁 PASS） | R3 `2144a40` + E50 真实 UI→SQLite `e33206f` |
| 3 规划、分配与容量预留 | IMPLEMENTED（局部门禁 PASS） | R4 `09a49ea` + R1 `295c7e6` |
| 4 有效正文与完成闭环 | IMPLEMENTED（局部门禁 PASS） | R2 `064eb42` + U6-C `96ea31b` + U6-D `7193b52` |
| 5 错误分类与受保护恢复 | IMPLEMENTED（局部门禁 PASS） | R5 `fb4ba8f`/`a74120e`；**人工认可 + `completion_provenance` 迁移 NOT AUTHORIZED** |
| 6 诊断与跨模块验收 | IMPLEMENTED（局部门禁 PASS） | R6 `0932c6d` + U6-E `1337b89` + 全仓回归（见下） |

## T01–T31

| ID | 状态 | 依据 |
| --- | --- | --- |
| T01 | PASS | `generation_budget_policy_test` / `configurable_elastic_budget_sqlite_test`（E20 C12000，C/C+1） |
| T02 | PASS | 直接创建真实 35% 冻结（`resource_ai_create_studio_navigation_test`：**自动化** Widget→runtime→SQLite，**非真机**）+ E50 **自动化** UI→SQLite 端到端（`e50_elastic_budget_end_to_end_test`）。**真实设备/真机未验证（NOT VERIFIED）** |
| T03 | PASS | `elastic_budget_matrix_test`（全局50/本次20 分辨率） |
| T04 | PASS | U6-E + elastic matrix（确认后改设置不追溯） |
| T05 | PASS | `generation_budget_policy_test`（E0/20/50，A 截顶） |
| T06 | PASS | `database_migration_v49_test`（NULL=20%，repo 重建） |
| T07 | PASS | `generation_aggregate_budget_sqlite_test` + U6-C floor 用例（soft 目标可超） |
| T08 | PASS | `generation_aggregate_budget_sqlite_test`（front overspend + reserve） |
| T09 | PASS | `character_generation_budget_reservation_sqlite_test`（m=300 不可行 0 请求） |
| T10 | PASS | 同上（R2 不可行，旧正文不变） |
| T11 | PASS | 同上（R1/R0 有限终止、不重排） |
| T12 | PASS | `blueprint_budget_normalizer_test` / `blueprint_validator_test`（单段 >K 拒绝） |
| T13 | PASS | `character_generation_content_contract_sqlite_test` + U6-C（1 字 narrative 拒绝） |
| T14 | PASS | 同上（2 字拒绝） |
| T15 | PASS | R2 + U6-C（合法 scalar 通过；structured 缺字段失败） |
| T16 | PASS | R2（complete_part 非质量证明）+ R3（冲突失败） |
| T17 | PASS | R3（分块 Unicode/转义/无末尾换行）+ U6-E（世界观逐字保存） |
| T18 | PASS | `character_generation_retry_recovery_sqlite_test`（infeasible 反复点击 0 请求） |
| T19 | PASS | R1 + CAS（预检可行、提交复核） |
| T20 | PASS | R5（偶发超 D 有限纠正） |
| T21 | PASS | `r02_part_content_source_cas_test` + `phase9_concurrency_test`（原子保护） |
| T22 | PASS | E50 套件 + `resource_ai_create_budget_input_test`（旧冻结20/资源50，320px） |
| T23 | PASS | `content_requirements_sqlite_test` + U6-D（历史 1/2 字只读） |
| T24 | PASS | `adventure_start_sqlite_production_test` + U6-E（角色 vs 世界观） |
| T25 | PASS | CAS + phase9 + lifecycle（取消迟到/恢复/重复尝试） |
| T26 | PASS | R3（重复 complete/start/append 语义） |
| T27 | PASS | `worldview_reference_generation_test`（大引用/关联角色/NPC） |
| T28 | PASS | `adventure_start_sqlite_production_test` + `adventure_compression_lifecycle_sqlite_test`（装配/压缩显式发布/启动） |
| T29 | PASS | R6（heartbeat 停止/重启） |
| T30 | PASS | R6（连续 SSE 不判死锁） |
| T31 | **NOT AUTHORIZED** | 人工认可 + `completion_provenance` 迁移未获产品授权；本轮未实现、未虚报 |

## 明确未验证

- 真实付费模型行为、真实 Android/USB 设备、Linux 桌面实机 —— **NOT VERIFIED**。
- T31 人工认可 / `completion_provenance` 迁移 —— **NOT AUTHORIZED**（因此整体只能 PARTIAL / 带范围限制）。

## 裁决

已授权范围（U6-A/B/C/D/E + R1–R6 + E50 + 全仓回归）在 BLOCKER=0、MAJOR=0 下通过，各单元均有独立审查。
因 **T31 未授权** 且 **真实模型/设备未验证**，整体状态为
**ACCEPTED WITH EXPLICIT SCOPE LIMITATIONS**，**不得**标记为完整 ACCEPTED，也不自动合并 main 或发布。

最终独立审查（另一 Agent，只读，独立上下文）：裁决 **ACCEPTED WITH EXPLICIT SCOPE LIMITATIONS**，
BLOCKER=0、MAJOR=0。独立复跑 `part_contract_status_test` + `u6e_cross_module_integration_test` +
`r05_async_state_ownership_test` **26 PASS（退出码 0）**；独立核对 diff 26 文件 / 3 提交，
`grep migration|completion_provenance|database_service|adventure|root-cause` 返回 **NONE**（无未授权内容）；
确认矩阵诚实（T31 NOT AUTHORIZED、真实设备/模型 NOT VERIFIED、无 main 合并）。审查未覆盖：全仓套件
（由本轮 FULL REGRESSION 另行覆盖）、真实设备/模型、T31 路径。
