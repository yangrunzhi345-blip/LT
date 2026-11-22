# Phase 10 审计整改

Start HEAD: `394a880153c644b1d624e8a7c03e15adfe75dd91`（2026-09-18 fetch 后与 origin/main 一致，工作区干净）。
依据：`phase-10-independent-acceptance.md`。Phase 10 保持 FAILED / 待复验，Phase 11 保持 BLOCKED。

## 范围与验收

- P10-A1 MAJOR：gate 新载体冻结未覆盖 Runtime 的 legacy 载体。必须从同一 assembly revision 重建主角 characterCard、资源派生的主角标量、对应 supportingCharacters（角色与 NPC）及快照显示字段；保持用户的叙事角色/关系配置。A/B 字段级回归证明旧 ready 显式选择不混入 live B。
- P10-M1 MINOR：worldview payload/index 按冻结 Part status 排除 draft/archived；canon section fragment 不能包含 draft part。补混合状态回归。
- P10-M2 MINOR：revision retention 在事务内同步清除无引用 assembly entries，保护仍有效的 revision/readiness/trash 引用；补真实 SQLite prune 回归。
- 修改限定 gate、assembly builder、revision retention 及其定向测试。不得扩展 Phase 11、重写压缩或迁移体系、修改独立验收结论。

## 验证要求

format、flutter analyze、Phase 10 定向测试、全量 flutter test、git diff --check。实现后独立审核指定 diff，处理发现后提交并推送 origin/main。报告记录验证结果与提交，不自行 ACCEPTED。

## 执行结果

### P10-A1

`adventure_readiness_gate.dart` 复用 `CharacterCardEntry` 从 assembly `cardRow` 解析，统一冻结主角卡及 name/gender/age/personality/protagonistClass/protagonistBackground。选中角色显示字段与 card JSON 同源；配角按 selection id / resource id 匹配，重建资源派生字段，保留 Adventure 关系和叙事角色。NPC 展开 `data` 与 `legacy_extra_fields`，恢复数值/布尔字段，重建 supporting 条目及 snapshot 名称/来源。解析失败阻断启动，不保留 live fallback。

新增 `test/application/adventure/phase10_field_freeze_test.dart`：真实 mapper→tree→capture→prepare→gate 链路，A/B 的主角、配角、NPC 字段不同；ready 与显式 stale 两个用例逐字段验证同源、binding/hash、输入不变、后续 C 编辑不影响冻结配置、JSON 往返。相同测试在 Start HEAD gate 上 0 passed / 2 failed（实际 name_B，期望 name_A），修复后 2 passed。

### P10-M1

`resource_assembly_builder.dart` 在 worldview projection 合并正文前过滤非 confirmed Part，并阻止 confirmed Section fragment 把 draft 子节点提升为 canon。独立 draft fragment 仍保留 isCanon=false。

builder 回归覆盖 confirmed Section + confirmed/draft/archived Parts，payload/index/canon fragments 均不含 draft/archived；live 后续确认不能改变旧 revision。新增测试先红后绿。两个旧 gate 用例原本用默认 draft fixture 断言正文注入，已明确 `confirmed: true`，保留原断言。

### P10-M2

`resource_revision_service.dart` 在每条 prune 链的同一事务内删除无 revision/readiness/未恢复 trash 引用的 assembly entries；也遍历仅剩历史孤儿文档的 resource id。readiness target/assembly revision 均受保护；数量上限不能覆盖引用保护。未改 schema、migration、压缩或 live 数据。

新增 `phase10_revision_prune_test.dart` 的 5 个真实 SQLite 用例：旧文档清理及新头可重放、readiness 双指针保护、trash 引用释放后回收、索引删除失败时 revision 同事务回滚、历史孤儿清理。与 Phase 9 maintenance / revision service 联跑 53 passed。

### 审核与验证

A1 由未参与 A1 实现的审核 Agent 只读审核，未发现 BLOCKER/MAJOR/MINOR；M1/M2 由主 Agent 核对 diff、引用保护与回归。该代码审核不替代 Phase 10 独立验收。

- `dart format .`：489 files / 0 changed（最终复跑）。
- `flutter analyze`：No issues found。
- Phase 10 定向 10 文件：54 passed / 0 failed。
- `flutter test` 全量：1513 passed / 0 failed / 0 skipped（退出码 0）。
- `git diff --check` 与 `git diff --cached --check`：提交前通过。

定向文件：原 8 文件（gate、builder、coordinator、v42 migration、semantic index、index/compression、production wiring、readiness dialogs）加 field freeze 与 revision prune。

### 状态、风险与回滚

Phase 10：REMEDIATED / READY_FOR_RE-ACCEPTANCE；原独立验收 FAILED 结论保留，不标记 ACCEPTED。Phase 11：BLOCKED。未处理报告 INFO 建议或扩展 legacy/new 投影 UX。无 UI 修改；既有 dialog viewport 回归随定向集验证。

运行工具曾受工作区外 Flutter SDK 缓存只读限制，经提权执行；初轮 analyze 的两条测试 lint 已修复；初轮定向的两项 draft fixture 失败已修正并完整重跑。

代码提交：`2e5fe7a` — `fix(resources): remediate phase 10 assembly freezing and retention`。文档提交随后记录本次验证与状态。回滚使用整改提交的 `git revert`，本次无数据库结构变化。
