# Phase 9 Third Independent Re-Acceptance — Round 3

```text
Result:            ACCEPTED
Audit HEAD:        2dfa69a310f58849f8db5e11230fb0358e2b72ea（== origin/main）
Remediation Range: e748c75..2dfa69a
                   （3c3d253 fix(phase9) + 2dfa69a docs(status)）
Reviewer:          independent re-acceptance agent（Round 3，只读；
                   未修改任何生产代码或测试）
Round 2:           FAILED @ e748c75（R2-B1 BLOCKER + R2-M1 MINOR + R2-M2 MINOR）
Round 2 Report:    docs/adaptive-resource-system/phase-09-independent-reacceptance-round2.md
                   （未改动，逐字保留）
Round 2 Remediation Report:
                   docs/adaptive-resource-system/phase-09-round2-remediation-report.md
                   （仅作为待验证声明，所有结论由本轮独立重验）
```

## Finding Closure

| ID | Round 2 | Round 3 裁定 | 依据 |
| --- | --- | --- | --- |
| R2-B1 | BLOCKER | **CLOSED** | 静态装配审查 + 10 项独立生产实验（真实 ProviderContainer / 无 override / 直接读 SQLite） |
| R2-M1 | MINOR | **CLOSED** | 状态机走读 + 13 项独立 autosave 实验（含竞态注入、迟到 debounce、崩溃恢复、多 Part 隔离） |
| R2-M2 | MINOR | **DEFERRED TO PHASE 11 / NON-BLOCKING** | 本轮整改未触碰 Phase 3 union 读取；重复投影仅为展示问题，不影响删除/恢复/幂等 |

## R2-B1 — 生产删除链路（CLOSED）

### 静态装配审查

- `rg "LibraryRepositoryImpl\s*\(" lib`：全部 5 处生产构造均携带桥接——
  `riverpod_providers.dart:95`（经 `resourceLibraryTrashBridgeProvider`）、
  `database_service.dart:98`、`chat_provider.dart:210`、
  `adventure_setup_controller.dart:63`、`adventure_template_controller.dart:29`
  （后四处直接取 `DatabaseService.libraryTrashBridge`）。
- 单一来源语义成立：provider 与 static 均收敛到 `DatabaseService._libraryTrash`
  这一个懒构建实例；其内部全部依赖以 `getDb` 闭包构造，闭包每次解析
  `DatabaseService.database` 静态 getter，因此 `resetDatabase()` 替换连接后桥接依然有效
  （独立实验 7 实证：读 provider → resetDatabase → 删除仍成功且写入新库）。
- fail-closed 守卫未被削弱：`_moveToTrash` 在桥缺失时仍抛 `StateError`，
  无任何「回退直删 / 静默 no-op」分支（独立实验 1 实证）。
- `_deleteByMode` 仅剩 `prompt_presets`（:510）/ `adventure_templates`（:610）两个调用点。
- 物理删除边界：`LegacyLibraryRowPurger` 是三张资源表唯一物理删除点，
  表名走固定 allowlist（`legacyResourceTables`），`purgeLegacyRowInTransaction`
  拒绝非白名单表（独立实验 8：篡改 `metadata_json` 指向 `adventure_state_commits`
  被拒绝，原行完好）。

### 独立实验（/tmp/r3audit/r3_prod_delete_test.dart，10/10 PASS）

全部使用真实 `ProviderContainer`、零 override、不使用执行 Agent 的测试文件，
每一步直接读 SQLite 验证：

| # | 实验 | 结果 |
| --- | --- | --- |
| A | worldview 生产链删除：success、legacy 行逐字段一致保留、单一 active bin entry（legacy link 正确）、列表与搜索均隐藏、生产 `resourceTrashRuntimeProvider.restore` 后逐字段恢复 | PASS |
| B | character card 同生命周期 | PASS |
| C | npc card 同生命周期 | PASS |
| 1 | 独立构造未接线仓库 → `StateError`，行/树/回收站零变化（fail-closed 未被削弱） | PASS |
| 3 | migrated（legacy+tree+审计记录）：树行软删除、legacy 行保留、单一 bin entry 且记录 before revision、restore 复活且正文一致 | PASS |
| 4 | treeMissing：回退 legacy 标记、行保留、可恢复 | PASS |
| 5 | 重复生产删除：幂等、单一 active entry | PASS |
| 6 | restore→delete→restore 两轮循环：无陈旧 link、无重复投影导致的错误删除、内容一致 | PASS |
| 7 | 桥接生命周期：provider 缓存的桥在 `resetDatabase()` 替换连接后仍正常工作 | PASS |
| 8 | 篡改 metadata_json 无法把 purger 指向其他表 | PASS |

## R2-M1 — Autosave 外部冲突状态机（CLOSED）

### 状态机走读（resource_autosave_service.dart）

```text
flush → CAS conflict
  ├─ live 缺失            → missingTarget，journal 丢弃
  ├─ live == 草稿          → applied（幂等收尾），journal 丢弃
  ├─ 自致（本 session 上次写 == live）→ 采信 token 重试一次（P9-M2 保持）
  └─ 外部写入             → 采信 live token + journal 保留 + 未解决冲突登记
       → flush 对该 Part 拒写（held，编辑退回 buffer，requiresUserResolution）
       → resolveConflictKeepMine（移除标记 → 读 live → 采信 token → 完整 journal+CAS 写）
       → resolveConflictDiscardMine（移除标记 → 同步清 buffer → 消费 journal → 采纳 live）
```

重点核查结论：

- **Keep Mine 提交内容与 UI 一致**：editor 传 `_controller.text`（实验 4：DB 最终内容
  == 确认文本 mine-v3，非旧草稿 mine-v2）。
- **第二次竞态**（实验 6，`_RacingBoundary` 在 confirm/commit 间注入外部写）：
  CAS 再次拒绝、外部内容保持、草稿持久、冲突继续；竞态平息后重试成功。
  Keep Mine 内部不存在无条件 UPDATE——所有写都经 `PartContentCommitService` 的 CAS。
- **迟到 debounce**：Keep Mine 后迟到（实验 7，最终内容不变、journal 干净）；
  Discard Mine 后迟到（实验 8：discard 同步清 buffer，迟到 flush no-op，草稿不复写）；
  restore 竞态后迟到（实验 9：外部内容不被覆盖，pending 文本留在 journal 且被
  `reconcilePendingDrafts` 判为 `needsUserDecision`）。
- **dispose 不绕过冲突保护**（实验 10）：unresolved 时关闭编辑器，外部内容保持、
  journal 保留；新 session 识别 `needsUserDecision`，load 与 discard 两条路径均可达，
  之后 keep-mine 正常恢复会话。
- **目标被删除**（实验 11）：missingTarget、journal 丢弃、软删除状态保持，不复活。
- **多 Part 隔离**（实验 12）：A 冲突未解决不阻塞 B 的 autosave；A 的 resolution
  不污染 B 的 token/buffer/journal。
- **确认窗口攻击**（实验 13，`_DelayedReadBoundary` 人为打开 250ms 窗口并在窗口内
  触发 debounce）：中途采样 DB 内容未变（`external-v2`）；无确认的 flush 因使用
  陈旧 token 被 CAS 拒绝（实验 9 同证），discard 同步清 buffer 后迟到 flush 为 no-op
  （实验 8 同证）。三条路径均使「未经确认覆盖外部内容」不可达。

### 独立实验（/tmp/r3audit/r3_autosave_test.dart，13/13 PASS）

1. 连续 5 轮 autosave 全部 applied（自致陈旧 token 未复发）。
2. 外部写入冲突：外部内容保持、草稿持久、requiresUserResolution。
3. 未解决期间继续输入：held 不写、最新文本留在 buffer、journal 保留上一份草稿。
4. Keep Mine 提交的正是编辑器当前文本；journal 清空；后续 autosave 恢复。
5. Discard Mine：DB 保持外部内容、journal/buffer 清空、返回 live 正文、后续编辑正常。
6. confirm/commit 间二次外部写入：CAS 再次拒绝、草稿不丢、可重试成功。
7–9. Keep Mine / Discard Mine / restore 三类迟到 debounce 均无危害。
10. unresolved 冲突下 dispose 不绕过保护；重开恢复（needsUserDecision → load/discard）可用。
11. 目标删除 → missingTarget，无复活。
12. 多 Part 隔离。
13. 确认窗口竞态注入：未经确认的覆盖不可达。

## Round 1 已关闭项回归

整改 diff（`git diff --name-only e748c75..2dfa69a`）仅触及 7 个 lib 文件
（providers / controllers / database_service / autosave service / part editor），
不包含任何 revision / assembly / compression / trash 服务文件，
Round 2 已独立验证的 P9-M1/M3～M9、P9-I1～I5 的代码路径零改动。
回归证据（本轮实际运行）：`test/application/resources/` 全目录 + 编辑器 + wizard
边界用例共 **538 passed / 0 failed**，其中包含：

- P9-M1 assembly shrink/tombstone（phase9_revision_boundary_test）
- P9-M2 自致冲突（resource_autosave_service_test token ownership 组）
- P9-M3 revision maintenance（phase9_revision_maintenance_test）
- P9-M4 compression alreadyApplied、P9-M5 restore CAS、P9-M6 级联幂等、
  P9-M7 retention 保护（phase9_revision_service_test / resource_trash_service_test /
  phase9_concurrency_test）
- P9-M8 Part 删除入口、P9-M9 label（Studio 编辑器用例）
- Phase 5–8 冻结文件在 `e748c75..2dfa69a` 零改动（`rg` 复核 diff 文件名清单为空）。

## New Findings（非阻塞）

```text
ID: R3-1  Severity: MINOR
Title: resolveConflictKeepMine 成功后不消费 held buffer 条目
Detail: 未解决冲突期间被 held 的编辑在 keep-mine 成功后仍留在 _buffer
       （resource_autosave_service.dart 的 resolveConflictKeepMine 未清理 buffer）。
       下一次 flush 会以当前 token 重写一次内容完全相同的正文（CAS 保护下无害），
       但 pendingCount 在此期间虚高 1。
Impact: 无数据风险；仅多余一次幂等写与 pending 计数不精确。
Required Fix: resolveConflictKeepMine 成功后 _buffer.remove(partId)（与 discard 对称）。
Required Tests: keep-mine 后断言 pendingCount == 0。
```

```text
ID: R3-2  Severity: MINOR
Title: 未解决冲突期间的新击键不落 journal，崩溃窗口内这些击键不可恢复
Detail: held flush 完全跳过 _writeOne（含 journal 步骤），冲突后输入只存在内存。
       用户在未解决状态下长时间编辑后崩溃/被杀，只能恢复冲突前的最后一份 journal
       草稿（实验 3 实证：journal 仍为 mine-v2，最新 mine-v3 仅在 buffer）。
       Round 2 行为（journal 落盘但会话楔死）与本轮行为（会话可恢复但窗口内
       击键不持久）各有取舍；UI 横幅已明确提示冲突存在，用户可随时二选一恢复持久化。
Impact: 有界丢失（预冲突草稿必然保留），需要用户忽视显式冲突横幅且发生崩溃。
Required Fix: held 路径仍执行 journal upsert（只跳过 CAS 提交），使冲突后输入
       逐步持久化。
Required Tests: 冲突 → 输入 → held flush → 断言 journal 内容为最新文本。
```

两项均为 MINOR，有 workaround、不违反 Phase 9 核心数据安全合同，不阻塞验收；
建议随 Phase 10/11 顺带处理。

## R2-M2 — DEFERRED TO PHASE 11 / NON-BLOCKING

本轮整改未触碰 Phase 3 union 读取；独立实验 3/6（migrated 删除与两轮恢复循环）
证明重复投影未导致错误删除、双 bin entry、恢复缺失或永久删除错误对象。
维持 Round 2 裁定：归 Phase 11（按 `resource_migration_records` 去重投影）。

## Validation（第三轮实际运行结果）

| 命令 | 实际结果 |
| --- | --- |
| `dart format --output=none --set-exit-if-changed .` | 473 files / 0 changed |
| `flutter analyze` | No issues found |
| Phase 9 定向测试（test/application/resources/ 全目录 + 编辑器 + wizard 边界） | 538 passed / 0 failed |
| 全量 `flutter test` | **1459 passed / 0 failed / 0 skipped** |
| `git diff --check` | 干净 |
| Phase 5–8 冻结文件（part_generation_*、generation_patch_parser、resource_generation_protocol/patch、streaming_*、resource_contracts、section_control_repository_impl） | `e748c75..2dfa69a` 零改动 |

## Final Decision

```text
ACCEPTED
Phase 9 ACCEPTED（第三轮独立验收通过）
R2-B1: CLOSED
R2-M1: CLOSED
R2-M2: DEFERRED TO PHASE 11 / NON-BLOCKING
Round 1 Findings: NO REGRESSION
新登记：R3-1（MINOR）、R3-2（MINOR）——非阻塞，随后续阶段处理
Phase 10: UNBLOCKED（转为 NOT_STARTED，等待开工记录 Start HEAD）
```

依据：R2-B1 与 R2-M1 经独立实验关闭，Phase 9 核心数据安全合同
（删除必须可恢复、fail-closed 保留、物理删除单点白名单、CAS 不可被绕过、
崩溃可恢复、cleanup 保护）全部满足；无新的 BLOCKER / MAJOR。
