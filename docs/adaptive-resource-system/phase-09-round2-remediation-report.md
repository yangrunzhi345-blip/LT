# Phase 9 Round 2 Remediation Report

- 阶段：Phase 9 — Revision、自动保存与回收站（Round 2 整改）
- 状态：`REMEDIATED / READY_FOR_RE-ACCEPTANCE`（等待独立 reviewer 第三轮验收；本轮不标记 `ACCEPTED`，Phase 10 保持 `BLOCKED`）
- 执行 Agent：executor-agent（CodeBuddy CLI，remediation 角色）
- Round 2 验收报告：[phase-09-independent-reacceptance-round2.md](phase-09-independent-reacceptance-round2.md)（保留原样，未修改）
- Remediation Start HEAD：`e748c75122742cde3db76df312bf89b1a175fb28`
- Remediation End HEAD：`3c3d253`（`fix(phase9): complete production trash wiring and autosave conflict recovery`）

## 0. 交付摘要

| ID | 级别 | 主题 | 结论 |
| --- | --- | --- | --- |
| R2-B1 | BLOCKER | 生产 UI 删除链路未接回收站桥，删除功能整体不可用 | FIXED |
| R2-M1 | MINOR | 外部写入冲突后同一编辑会话 autosave 永久停摆 | FIXED |
| R2-M2 | MINOR | 迁移资源在 Library 中可能出现两条投影 | DEFERRED to Phase 11（按 Round 2 验收报告裁定，本轮不动 Phase 3 union 读取） |

Round 1 已关闭且本轮未回退的问题：P9-B1 数据安全部分、P9-M1、P9-M2（自致冲突部分）、P9-M3～P9-M9、P9-I1～P9-I5。全量测试 1459 通过，其中包含上述各项的既有回归用例。

## 1. R2-B1 — 生产删除链路接线

### 根因

整改曾把回收站桥接到 `DatabaseService._libraryRepo`，而 Resource Library UI 的删除走
`libraryRepoProvider` 这条完全独立的装配链。两条装配链并存、只有其一接线，`_moveToTrash`
的 fail-closed 守卫使未接线的链路从「不安全但可用」变成「安全但不可用」。

### 修复前生产装配

```text
resourceCrudControllerProvider → libraryRepoProvider
  → LibraryRepositoryImpl(getDb: ...)            // 无 trashBridge → delete 必然抛 StateError

DatabaseService._libraryRepo
  → LibraryRepositoryImpl(getDb:, trashBridge:)  // 已接线，但生产删除不经过它

ChatProvider() 默认构造 / AdventureSetupController、AdventureTemplateController
  回退构造 → LibraryRepositoryImpl(getDb: ...)   // 裸构造，同样未接线
```

### 修复后生产装配

**收敛为单一桥接来源**：`DatabaseService.libraryTrashBridge`（新公开静态 getter，内部仍是
懒构建的 `_buildLibraryTrash()`，仅闭包 `DatabaseService.database`，`resetDatabase()` 后依然有效）。

```text
DatabaseService.libraryTrashBridge            ← 唯一来源
  ├─ resourceLibraryTrashBridgeProvider       ← 直接委托该静态（不再自建一套）
  │    └─ libraryRepoProvider
  │         → LibraryRepositoryImpl(getDb:, trashBridge: ref.read(...))
  │           ← resourceCrudControllerProvider（Resource Library UI 全部删除入口）
  ├─ DatabaseService._libraryRepo（facade，维持原接线）
  ├─ ChatProvider() 默认构造 → trashBridge: DatabaseService.libraryTrashBridge
  ├─ AdventureSetupController 回退构造 → 同上
  └─ AdventureTemplateController 回退构造 → 同上
```

fail-closed 守卫（`library_repository_impl.dart` 的 `_moveToTrash` 抛 `StateError`）**原样保留**，
没有添加任何「桥缺失时回退直接 DELETE / 静默 no-op」的分支。

### 裸构造审计（`rg "LibraryRepositoryImpl\s*\("` lib）

| 构造点 | 处置 | 理由 |
| --- | --- | --- |
| `lib/providers/riverpod_providers.dart`（libraryRepoProvider） | **已接线** | Resource Library UI 删除的唯一生产链 |
| `lib/services/database_service.dart`（`_libraryRepo` facade） | 维持原状（原本已接线） | Round 2 INFO R2-I2：lib/ 内无调用方；接线来源已统一 |
| `lib/providers/chat_provider.dart`（`ChatProvider()` 默认构造） | **已接线** | 当前 lib/ 生产无调用方（生产用 `chatProvider` provider），但它是公开构造路径，必须消除半接线风险 |
| `lib/controllers/adventure_setup_controller.dart`（回退构造） | **已接线** | 生产走 `adventureSetupControllerProvider`（显式传 useCase）；回退构造仅做读写/装配，不删资源，但统一走同一来源 |
| `lib/controllers/adventure_template_controller.dart`（回退构造） | **已接线** | 其 `deleteTemplate` 只删 `adventure_templates`（配置表，走 `_deleteByMode`，不属 Phase 9 范围），但统一来源消除歧义 |
| `test/**` 其余构造 | 不改 | 测试自行装配属预期（fixture 显式接线或显式未接线），production wiring 由新回归测试覆盖 |

### 新增测试

`test/application/resources/phase9_production_delete_wiring_test.dart` — 真实
`ProviderContainer`、**无任何 override**、无手工装配仓库：

- 三种资源（worldview preset / character card / npc card）各自完整生命周期：
  经 `libraryRepoProvider` 建档 → `resourceCrudControllerProvider.delete*` 成功 →
  `resource_trash` 出现 active 条目 → legacy 行未被物理删除（COUNT==1）→
  `getWorldviewPresets/getCharacterCards/getNpcCards` 不再列出 → 经生产
  `resourceTrashRuntimeProvider.restore` 恢复 → 列表重新可见。
- 桥接一致性用例：provider 构建的仓库可直接删除（fail-closed 未被误触发），
  `DatabaseService.libraryTrashBridge` 为同一实例来源。
- 既有 fail-closed 用例保留：`phase9_library_delete_test.dart` 的
  「an unwired library repository refuses to delete」断言未接桥的仓库仍抛 `StateError`
  且不产生任何数据破坏。

### 三种资源真实 ProviderContainer 删除结果

| 资源 | delete 成功 | legacy 行保留 | trash 条目 | 列表隐藏 | restore 后可见 |
| --- | --- | --- | --- | --- | --- |
| worldview preset (`wv-prod`) | ✅ | ✅ (1) | ✅ | ✅ | ✅ |
| character card (`card-prod`) | ✅ | ✅ (1) | ✅ | ✅ | ✅ |
| npc card (`npc-prod`) | ✅ | ✅ (1) | ✅ | ✅ | ✅ |

## 2. R2-M1 — 外部冲突后的会话内恢复

### 根因

`_handleConflict` 的外部写入分支只「报告」不「解决」：不采信 live token、不给出用户决策出口，
session token 停留在陈旧值，后续每次 flush 仍然冲突；用户只能关闭编辑器重开走草稿恢复。

### 冲突状态机（修复后）

```text
flush → CAS conflict
  ├─ live 缺失            → 丢弃草稿，missingTarget
  ├─ live == 草稿         → 视为已落盘，applied（幂等收尾）
  ├─ 自致冲突（本 session 上次写 == live）→ 采信新 token 重试一次（P9-M2，保持不变）
  └─ 外部写入（新增状态转移）
       → session token 采信 live token
       → 草稿保留在 journal（持久）
       → part 进入 _unresolvedConflicts（未解决冲突）
       → 后续 flush 拒写该 part（编辑退回 buffer），返回 requiresUserResolution
       → 编辑器显示冲突横幅：「使用我的文本」/「放弃我的文本」
```

- **使用我的文本**（`resolveConflictKeepMine`）：以刚采信的 live token 为 expected token
  走完整 `_writeOne`（journal → CAS 提交）。成功则草稿被同一事务消费、冲突清除、后续 autosave 正常；
  若 confirm 与 commit 之间再次发生外部写入，CAS 再次拒绝、live token 再次采信、草稿保留、
  冲突保持未解决 —— **不静默覆盖**。
- **放弃我的文本**（`resolveConflictDiscardMine`）：消费 journal 行、清空 buffer、
  session token 与基线采纳 live 内容，返回 `adoptedLive` 状态并携带 live 正文供编辑器直接回显；
  后续编辑 autosave 正常。
- 会话内未解决即关闭编辑器：journal 行保留，重开后 `reconcilePendingDrafts` 仍按
  `needsUserDecision` 提供「载入/丢弃草稿」——原有 crash recovery 路径（Case 4）不受影响。

### 新增测试（`resource_autosave_service_test.dart` 组 `external conflict resolution (R2-M1)`）

1. 外部写入 → 冲突（v2 未被覆盖、草稿保留）→ 冲突期间继续输入被拒写（held）→
   keep-mine 成功 → journal 消费 → 同一 session 下一次 autosave（v4）applied。
2. 外部写入 → discard-mine → live 内容采纳返回、草稿清除 → 后续编辑 autosave 成功。
3. 二次竞态：`_RacingTreeBoundary` 在 confirm 与 commit 之间注入外部写入 → CAS 再次拒绝、
   live 内容保持 `external-v3-race`、草稿仍持久 → 竞态平息后重试 keep-mine 成功。
4. 未解决冲突时关闭编辑器 → journal 保留 → 新 session `reconcilePendingDrafts` 判定
   `needsUserDecision` → discard → 会话恢复正常保存（crash recovery 未被破坏）。

编辑器侧（`resource_studio_part_editor_test.dart` 组 `external conflict resolution (R2-M1)`）：
冲突横幅出现两个动作；keep-mine 传当前编辑文本并在成功后清除横幅；二次竞态保持横幅；
discard-mine 将 live 内容回显进编辑器；横幅在 320 px 无溢出。

## 3. R2-M2 — Deferred to Phase 11

迁移资源在 Library 的重复投影（legacy projection + tree projection）属 Phase 3 union 读取
未按迁移关系去重，Round 2 验收已裁定归 Phase 11（Library UX 收敛）。本轮未修改 Phase 3
union read / migration projection 去重逻辑。

## 4. Regression 安全

- `git diff --name-only e748c75..3c3d253` 仅触及上文列出的 7 个 lib 文件与 3 个测试文件；
  未触碰 Phase 5–8 冻结协议（`part_generation_*`、`generation_patch_parser.dart`、
  `resource_generation_protocol/patch`、`streaming_*`、`resource_contracts.dart`、
  `section_control_repository_impl.dart` 等）。
- Resource 删除语义：无任何 hard delete legacy row 的新路径；restore / permanent delete、
  legacy-only TrashOrigin、migrated/tree-backed 资源行为均由既有用例覆盖且全部通过。
- fail-closed 守卫未动；`_deleteByMode` 仍仅服务 `prompt_presets` / `adventure_templates`。

## 5. Validation

| 命令 | 结果 |
| --- | --- |
| `dart format --output=none --set-exit-if-changed .` | 473 files / 0 changed |
| `flutter analyze` | No issues found |
| Phase 9 定向测试（10 文件，含新增 wiring 测试） | 187 passed / 0 failed |
| 全量 `flutter test` | 1459 passed / 0 failed |
| `git diff --check` | 干净 |

## 6. 状态

```text
Phase 9:  REMEDIATED / READY_FOR_RE-ACCEPTANCE
Phase 10: BLOCKED（等待 Phase 9 独立第三轮验收）
```

是否 `ACCEPTED` 由下一轮独立验收 Agent 裁定。
