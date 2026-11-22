# Phase 4 Independent Acceptance Report — Adaptive Blueprint

Reviewed Branch: `main`
Reviewed HEAD: `264151367ffd760c50467f1f79a87d4b7f98fdaf`
Reviewed Commits: `1e7bff5`（实现）+ `2641513`（STATUS 记录）
Reviewer: CodeBuddy CLI（Phase 4 独立验收 Agent，只读审计；未修改任何业务实现）
Review Date: 2026-09-16

**FINAL RESULT: REJECTED**

判定依据：存在 1 个 BLOCKER（B1）与 1 个 HIGH（H1）。二者均由本次独立执行的动作性证据（可执行测试）复现，而非静态推断。整改方向见第 19、20 节。

---

## 1. Executive Result

| 项 | 结果 |
| --- | --- |
| Blueprint 领域模型与契约边界 | 通过 |
| 动态 Schema（无固定字段体系） | 通过 |
| 客户端 ID 安全（未知/重复/跨蓝图/越权） | 通过 |
| DAG 校验（自环、二元环、多元环） | 通过 |
| 容量策略（世界观 50,000 / 角色 NPC 5,000） | 通过 |
| 统一 LLM 栈复用（gateway / task policy / resolver / 取消） | 通过 |
| Bounded Planning Context（8,000 字截断） | 通过 |
| plan / replan / review 不污染正式树 | 通过 |
| confirm 事务原子性（真实中途失败回滚） | 通过 |
| 重复 confirm 幂等（含并发） | 通过 |
| **Phase 3 → Phase 4 链路接管** | **失败（B1 BLOCKER）** |
| **confirm 归属边界（不得覆盖无关资源）** | **失败（H1 HIGH）** |
| Legacy Double-Write | 无（通过） |
| ReferenceSource 隐私 | 无日志输出（通过） |
| Phase 5 Scope Leakage | 无（通过） |
| 数据库 v34 → v35 | 通过（旧库升级保数据、可重放） |

一句话结论：**Phase 4 内部的规划引擎质量很高，ID/DAG/容量/事务/幂等五项核心守卫经独立对抗测试全部成立；但它没有接入任何真实创建链路，`plan → review → confirm` 在生产代码中完全不可达，且 `confirm` 缺少归属校验，可被用来覆盖与本会话无关的既有资源。**

---

## 2. Blueprint Domain Model Audit

- 领域模型集中在 `lib/domain/resources/resource_blueprint.dart`：
  - `ResourceBlueprint`（:216）仅承载 `blueprintId / sessionId / resourceType / suggestedName / summary / revision / status / targetCapacity / sections / resourceId`，**没有任何正文容器字段**。
  - `BlueprintSection`（:145）为 `id / title / summary / sortOrder / parts`；`BlueprintPart`（:61）为 `id / sectionId / title / generationGoal / estimatedLength / dependencies / sortOrder`。
  - `BlueprintIdPool`（:24）实现客户端预分配 SDL。
- 内容与规划边界：Blueprint 唯一承载自然语言的三处字段（`summary`、`section.summary`、`part.generationGoal`）均受 `BlueprintValidator` 硬上限约束（1000 / 500 / 500 字符），`suggestedName`、`title` 另有 100 字符上限。**不存在把 summary/goal/description 当作大段正文容器的可行路径。**
- 全仓库仅存在一份 Blueprint 模型与一份校验器，未发现旁路实现、重复实现的第二套 `Blueprint*`。

结论：满足「Blueprint 只负责规划，不承载正文」。

## 3. Dynamic Schema Audit

- `rg -ni "geography|politics|religion|economy|history|technology|moduleKeys|WorldviewDetails"` 在 Phase 4 全部文件中**零命中**（仅 `blueprint_planner.dart:119/203` 命中英文注释里的 “history” 一词，属措辞而非字段）。
- `moduleKeys` 仍存在于 `lib/models/worldview_details.dart`、`worldview_ai_import_page.dart`、`legacy_resource_mapper.dart` 等**既有兼容路径**，Phase 4 未对其产生任何新依赖。
- Prompt（`blueprint_prompt_builder.dart:38`）明确要求「目录结构必须自适应、动态产生，严禁套用死板九宫格/固定模块/固定表格」。
- 验收矩阵「dynamic section / dynamic part」：`lib/application/resources/blueprint_planner_test.dart` 的用例 4 与我的独立用例 I-9（超出 ID 池规模的大纲被拒）共同证明结构由模型按资源需求动态产生，Section/Part 数量与标题不受固定体系约束。

结论：通过。

## 4. ID Security Audit

执行路径：`BlueprintParser.fromMap` → `BlueprintValidator.validate(parsedBlueprint, idPool: pool)`（`blueprint_planner.dart:113/178`）。

| 场景 | 结果 | 证据 |
| --- | --- | --- |
| 未知 ID（不在预分配池） | 拒绝 | `blueprint_validator.dart:215/229`；执行方用例 8；独立用例 I-9 |
| 重复 Section / Part ID | 拒绝 | `_validateIds` :209/:223；执行方用例 |
| Part 的 sectionId 与父 Section 不一致 | 拒绝 | :155 |
| 依赖引用不存在的 Part | 拒绝 | :241 |
| **跨 Blueprint 引用** | **拒绝** | 独立用例 I-7（依赖指向另一个 Blueprint 的 Part ID → `BlueprintIdException`） |
| 模型自造 “分配的 DB 身份” | 不可能 | 落库时 ID 一律重写为 `${resourceId}_${part.id}`（`resource_blueprint_repository.dart:264/268`），模型提供的字面值仅作为槽位后缀 |

结论：客户端完全控制 ID，模型不得制造数据库身份。通过。

补充观察（不阻塞）：ID 池上限（12 Section / 36 Part）同时充当节点数上限，实现正确但属隐式耦合，建议在 ADR 记录。

## 5. DAG Validation Audit

`_validateDag`（`blueprint_validator.dart:251`）采用三色 DFS（0 未访问 / 1 访问中 / 2 已完成），并对自环做前置快速判定。

我的独立用例 I-8 经**完整 planner 真实路径**（构造 LLM JSON → parse → validate）验证：

| 图 | 期望 | 实测 |
| --- | --- | --- |
| A → A | reject | reject（`BlueprintDagCycleException`） |
| A → B，B → A | reject | reject |
| A → B，B → C，C → A | reject | reject |

结论：通过。

## 6. Capacity Policy Audit

`_validateCapacity`（:300）以 `ResourceLimits.policyFor(type).nominalCharacters` 为唯一预算来源，在**规划阶段**即拒绝。

独立用例证据：

| 用例 | 结果 |
| --- | --- |
| I-4 世界观 50,000 恰好通过 / 50,001 拒绝 | 通过 |
| I-5 角色 5,001 拒绝；NPC 5,001 拒绝 | 通过 |
| I-6 模型在 JSON 中声明 `"targetCapacity": 999999` 试图抬高预算 | 仍被拒（服务端预算胜出） |

未复用/复制容量常量：`lib/` 中 50000/60000/5000/6000 的新增副本为零，Phase 4 全部经 `ResourceLimits`。

结论：超预算在 Blueprint 阶段被拦截，不存在「生成正文后暴力截断」。通过。

## 7. Planning Pipeline Audit

链路：

```text
CreationSession（v33 会话，status=planning）
↓ pipeline.findSession + session.awaitsPlanning（resource_creation_contracts.dart:403）
↓ BlueprintPromptBuilder.buildSystemPrompt / buildUserInstruction
↓ BlueprintPlanner._invokeWithTimeout（blueprint_planner.dart:206）
↓ LlmGateway.rawCompletion（lib/application/llm/llm_gateway.dart:107）
↓ AiGeneratorLlmGateway → LlmTaskResolver → 统一 LlmService → taskHandle 取消
↓ BlueprintParser.parseLlmResponse
↓ BlueprintValidator.validate
↓ IResourceBlueprintRepository.saveBlueprint
```

- 复用现有栈：`LlmTask.resourceBlueprintPlanning`（`llm_task.dart:49`）、`LlmTaskPolicyTable`（`llm_task_policy.dart:88`，含 thinking/preferJson/maxTokens/temperature）、`LlmTaskResolver` + `ModelCapabilityRegistry`、`GenerationTaskHandle` 取消注册。
- Phase 4 对 Gateway 的唯一改动是给 `rawCompletion` 增加可选 `taskHandle` 形参（`llm_gateway.dart:113`、`ai_generator_llm_gateway.dart:213`）——**传播既有句柄，不是新建第二套 HTTP client 或第二套模型解析**。
- **未发现私自另建的 LLM 调用栈。**
- 唯一自实现部分是外层 `Timer` 超时（:215），见 L4。

结论：架构复用正确（是否有权被调用见 B1）。

## 8. Bounded Planning Context Audit

- `BlueprintPromptBuilder.maxReferenceCharsInPrompt = 8000`（:13），超长参考截取前 8000 字并向模型显式披露截断（:96）。
- 独立用例 I-10：构造 40,000 字 `ReferenceSource.text`，捕获真实 prompt，`【参考资料】` 段实际长度 < 9,000，且**不含完整的 9,000 字连续原文**，含「已截取前」提示。
- 规划上下文仅由「会话名 + 参考资料（有界）+ 上一版大纲概览 + 用户反馈」构成，不含全部数据库、全部历史、全部聊天。

结论：通过。

## 9. Plan / Replan / Review / Confirm Audit

| 阶段 | 结论 | 证据 |
| --- | --- | --- |
| plan | 产生 Blueprint；不产生正文；正式树 0 行 | 独立 I-11；执行方用例 1/2/3/14 |
| replan | 生成新 revision；旧 draft 标记 `superseded`；正式树 0 行 | 独立 I-11；`saveBlueprint` :111-124 |
| review | 仅 `findBlueprint / findLatestBlueprint / listBlueprints` 三个只读入口，不写正式树 | `blueprint_planner.dart:197-204` |
| confirm | 唯一创建 Resource/Section/Part 占位的写入点，Part `content` 恒为 `''` | `resource_blueprint_repository.dart:272`；独立 I-3 断言全部 placeholder 无正文 |

- 「confirm 前无正文」：plan 与两次 replan 后 `resources / resource_sections / resource_parts` 计数均为 0（I-11）。
- 「confirm 后占位」：I-3 经统一读取路径 `treeRepo.findResource / readSections / readParts` 复核，2 个 Part 的 `content` 全为空字符串。

结论：plan/replan/review/confirm 语义正确；生命周期是否可达见 B1。

## 10. Revision / History Audit

- replan 以 `latest.revision + 1` 生成新的 `blueprintId = bp_<sessionId>_revN`，旧 draft 置 `superseded`，历史可读（`listBlueprints`）。I-11 验证 revision 序列 [1, 2] 且状态分别为 superseded / draft。
- **M1（MEDIUM）**：重复调用 `plan()`（而非 `replan`）会以同一个 `bp_<sid>_rev1` 再次写库，因 `saveBlueprint` 使用 `ConflictAlgorithm.replace`（:144）**静默覆盖**上一份 draft，既不报错也不留 `superseded` 记录，provenance 丢失。实测：连续两次 `plan()` 后 `listBlueprints` 长度仍为 1，`storedName` 变为第二次结果。
- **M2（MEDIUM）**：confirm 之后 `replan` 仍可成功，产生 revision 2（draft），但会话已 `completed`，`confirmBlueprint` 的会话状态校验（:243）会永久拒绝它 → 该 revision 成为不可确认的死记录。实测 confirmError=`ResourceCreationException: 创建会话当前状态为 completed，无法确认 Blueprint`（未污染资源树，`resources` 仍为 1）。
- DB 层无 `UNIQUE(session_id, revision)` 约束，revision 唯一性仅靠 `blueprint_id` 主键 + 确定性命名维持（见 M1）。

## 11. Confirm Transaction Audit

`confirmBlueprint`（`resource_blueprint_repository.dart:192`）整体包在 `_treeRepository.runInTransaction`（= `db.transaction`）内，包含：Blueprint 读取与状态校验 → 会话校验 → `createResourceTreeInTransaction` / `updateResourceTreeInTransaction` → 逐 Part 插入 `resource_generation_tasks` → 更新 blueprint `confirmed` → 更新会话 `completed`。

- **独立用例 I-1（真实中途失败回滚）**：预先占据 confirm 将要生成的 Section 主键，使失败点在**资源行写入之后、Section 插入时**发生。结果：抛出 `DatabaseException`，`resources` 仍为 1（仅预先存在的无关资源）、`resource_sections` 1、`resource_parts` 0、`resource_generation_tasks` 0，Blueprint 仍为 `draft`，会话仍为 `planning`。**未出现孤儿 Resource / Section / Part / 半确认状态。**
- 注意：执行方自带的 `transaction rollback on failure leaves zero orphan records` 用例先 `pipeline.cancel()` 会话，使失败发生在**任何写入之前**，不能证明中途回滚（见 L2）。真实原子性由我的 I-1 独立证明，实现本身是正确的。

结论：事务原子性实现正确，通过。

## 12. Duplicate Confirm Audit

- 顺序重复 confirm：蓝图已 `confirmed` 且 `resourceId != null` 时短路返回 `reusedExisting: true`（:212-221），行数不变（执行方用例已覆盖）。
- **独立用例 I-2（并发）**：`Future.wait` 同时发起两次 confirm，两次结果解析到同一 `resourceId`，最终 `resources=1 / sections=1 / parts=2 / tasks=2`。

结论：通过。

## 13. Phase 3 Integration Audit — **B1 BLOCKER 所在**

事实证据：

1. `rg -n "BlueprintPlanner|BlueprintPlanner\(" lib` 除定义文件外**零命中**；`rg "ResourceBlueprintRepositoryImpl(" lib` 同样零命中。
2. `pendingPlanningSessions()`（`resource_creation_pipeline.dart:397`）在 `lib/` 中**没有任何调用方**（仅定义与测试）。
3. `session.awaitsPlanning`（`resource_creation_contracts.dart:403`）在 `lib/` 中唯一消费者是 `blueprint_planner.dart:75`。
4. Phase 4 提交集（`git show --stat 1e7bff5`）只含 6 个新增业务文件 + `database_service.dart` + `llm_task.dart` / `llm_task_policy.dart` / 2 个 gateway + ADR/测试，**不含任何 entry point、controller、page 或 provider**。

后果：

- Phase 3 明确规定「AI 创建在本阶段只创建待规划会话，具体 blueprint 留给 Phase 4」（phase-03 实施步骤 4）。Phase 4 结束後，`planAiCreation` 产生的 `planning` 会话仍停在原地，**没有任何代码去消费它**，AI 创建链路终点依旧是一个沉睡的会话行。
- `BlueprintPlanner.plan / replan / confirm` 全部是无消费者死代码；第 11、12 节验证过的事务与幂等保证在生产中无法兑现。
- Phase 4 目标句「AI 创建的第一步只生成资源名称、动态目录…不生成完整正文」在产品的任何路径上都没有成立；旧 AI 页面仍按其既有方式生成正文（Phase 3 handoff 已把「Phase 4–6 接管生成」列为延期项，本轮未关闭）。
- Phase 5 的「从**已确认** Blueprint 生成任务队列」将因此失去输入来源：没有任何用户动作能产出 `confirmed` 状态的 Blueprint。

独立用例 I-12（扫描 `lib/` 中所有非 Phase 4 文件，断言存在至少一个 `BlueprintPlanner(` 或 `ResourceBlueprintRepositoryImpl(` 构造点）**失败，实际值为空列表**。

判定：**BLOCKER**。对应验收矩阵第「Phase 3 → Phase 4 integration」项，且直接命中本题给出的 BLOCKER 示例「Blueprint 根本未接入真实 creation flow」。

## 14. Legacy Double-Write Audit

- Phase 4 全部 6 个业务文件（`resource_blueprint.dart`、`blueprint_{parser,planner,prompt_builder,validator}.dart`、`resource_blueprint_repository.dart`）对 `worldview_presets` / `character_cards` / `npc_cards` **零引用**（rg 确认）。
- 全仓 `lib/` 中旧表引用仅存在于：`database_service.dart`（历史 migration，只读式 `safeAddColumn`）、`library_repository_impl.dart` / `legacy_resource_mapper.dart` / `resource_adventure_view.dart`（读取兼容与投影）、`world_engine.dart` / `character_manager.dart`（既有 prefs 迁移路径）。Phase 4 未新增任何一条。
- 结论：**未恢复 legacy double-write。通过。**

## 15. ReferenceSource Privacy Audit

- Phase 4 全部文件中 `debugPrint` / `print(` / `log(` **零命中**（已排除 `ResourceBlueprint(` 之类的子串误报）。
- `ReferenceSource.body` 的流向只有两处：进入 `BlueprintPromptBuilder` 构造受限 prompt（第 8 节），以及 Phase 3 既有的会话表 `reference_body` 列与 `ContentHasher` 指纹（哈希，非原文）。
- 结论：**参考材料全文不进日志。通过。**
- 附带观察：`BlueprintParseException.rawPayload` 保存 LLM 原始返回全文（非用户参考材料），若将来被直接渲染到错误提示会放大提示注入面，建议收敛为截断片段。

## 16. Phase 5 Scope Leakage Audit

`rg "incremental|continueGeneration|generatePartContent|partContent|contentPatch|streamingGeneration|jsonPatch|generationContinuation" lib test`：零命中（`lib/models/llm_message.dart:100` 仅为注释用词）。

逐项判断：

- **Part 正文生成**：未实现。confirm 后所有 Part `content` 为空（I-3）。
- **Incremental JSON 正文协议**：未实现。无 `start_part` / `append_text` / `complete_part` / `fail_part` 之类 patch 能力。
- **正文 continuation / patch / streaming**：未实现。planner 只做单次非流式 `rawCompletion` 并整段解析。
- `resource_generation_tasks` 表：属 Phase 4 实施方案第 4 步明确要求（「confirm 後同事务创建 Section/Part 占位与 generation tasks」），且仅写入 `pending` 占位，无正文列、无 cursor、无 sequence，**不构成 Phase 5 提前侵入**。

结论：通过（无 Phase 5 泄漏）。

## 17. Database / Migration Audit

新增 v34 → v35（`database_service.dart:400-459`、迁移步骤 :1802）：

- `resource_blueprints`（PK `blueprint_id`，idx `session_id, revision DESC`、`resource_id`）与 `resource_generation_tasks`（PK `task_id`，3 个 idx）。
- 未修改任何已发布 migration 语义，未复用版本号（34 → 35），`createV35Schema` 采用加法 + `IF NOT EXISTS`。
- fresh install：执行方 migration 用例 + 我的 I-13 覆盖。
- **旧库升级**：Phase 1 的 v30 fixture 用例已断言 `user_version == DatabaseService.schemaVersion`（=35）且旧行逐字段保留；我的 I-13 额外以「drop 新表 + `PRAGMA user_version = 34` + 重新 open」走真实 `onUpgrade` 分支，验证新表被重建、既有资源行完好、且 `migrateStepByStep(34,35)` 连跑两次安全。
- 幂等：`CREATE TABLE IF NOT EXISTS` + 可重放步骤。
- **M3（MEDIUM）**：两张新表**没有任何外键约束**。`resource_blueprints.resource_id`、`resource_generation_tasks.{blueprint_id, resource_id, section_id, part_id}` 均无 REFERENCES/ON DELETE CASCADE；而既有 `resource_sections` / `resource_parts` 是有外键的。当前代码路径不会产生孤儿（同事务写入），但资源被软删/清理后，`resource_generation_tasks` 会留下历史孤儿行，Phase 5 调度时需要额外的清理或级联策略。

结论：迁移本身通过；外键完整性为 MEDIUM 缺口。

## 18. Test Execution Results

基态（Reviewed HEAD `2641513`，不含本次新增验收文件）：

| 命令 | 结果 |
| --- | --- |
| `dart format --output=none --set-exit-if-changed .` | 345 files, 0 changed, exit 0 |
| `flutter analyze` | No issues found! |
| Phase 4 定向测试（4 个文件） | **46 passed / 0 failed** |
| Phase 3 回归 + migration（`test/application/resources/` + `test/services/database_migration_resource_tree_test.dart`） | **147 passed / 0 failed** |
| `flutter test`（全量） | **805 passed / 0 failed** |
| `git diff --check` | clean |
| `git status --short`（验收开始前） | clean |

执行方报告的数值（345 files / 46 targeted / 805 全量 / Phase 3 回归 27）**全部复现属实**，未发现谎报。

补充：本次我还独立编写并运行了 `test/application/resources/phase4_independent_acceptance_test.dart`（14 个用例，唯一新增文件，非业务代码）：

| 结果 | 用例 |
| --- | --- |
| pass | I-1 真实中途失败回滚 · I-2 并发重复 confirm · I-3 占位无正文且可读 · I-4 世界观 50000/50001 · I-5 角色 NPC 5001 · I-6 伪造 targetCapacity · I-7 跨蓝图依赖 · I-8 三种环 · I-9 ID 池上限 · I-10 40000 字参考有界 · I-11 plan/replan 不污染树 · I-13 旧库升级保数据 |
| **fail** | **I-12** 生产可达性（`Expected: non-empty / Actual: []`）→ B1 |
| **fail** | **I-14** confirm 归属边界（`confirmBlueprint` 接受 `explicitResourceId: res_victim` 并返回 `ResourceBlueprintConfirmResult(resource: res_victim, reused: false)`，随后该资源的名称与全部 Section/Part 被重写）→ H1 |

含该文件的全量运行：**819 tests / 817 passed / 2 failed**（2 个失败即上述两条加强证据）。

## 19. Findings Matrix

验收矩阵逐项结论：

```text
[x] worldview blueprint planning              pass（LLM JSON → 校验 → 落库）
[x] character blueprint planning              pass
[x] NPC blueprint planning                    pass

[x] dynamic section                           pass
[x] dynamic part                              pass

[x] ReferenceSource reaches planner           pass（I-10 同时证明有界）
[x] blueprint contains no generated prose     pass（I-3/I-11）

[x] unknown ID rejected                       pass
[x] duplicate ID rejected                     pass
[x] invalid dependency rejected               pass
[x] self-cycle rejected                       pass（I-8 A→A）
[x] multi-node cycle rejected                 pass（I-8 A→B→A、A→B→C→A）

[x] capacity overflow rejected                pass（I-4/I-5/I-6）

[x] replan preserves history                  pass（显式 replan）
[x] replan does not pollute Resource Tree     pass（I-11）

[x] confirm-before: no prose                  pass
[x] confirm creates placeholders              pass（I-3）

[x] confirm rollback                          pass（I-1 真实中途失败）
[x] duplicate confirm idempotency             pass（I-2 含并发）

[x] cancellation                              pass（planner 前置检查 + registerCancel）
[x] timeout                                   pass（Timer → TimeoutException）
[x] malformed LLM response                    pass（BlueprintParseException）
[x] forbidden content rejected                pass（prose 走私上限）

[ ] Phase 3 → Phase 4 integration             FAIL → B1 BLOCKER
[ ] confirm must not touch foreign resources  FAIL → H1 HIGH

[x] no legacy double-write                    pass
[x] no ReferenceSource logging                pass
[x] no Phase 5 leakage                        pass
```

## 20. Remaining Findings

### B1 — BLOCKER — Blueprint 规划栈未接入真实创建链路

- **File / Line**：`lib/application/resources/blueprint_planner.dart:62/120/185`、`lib/application/resources/resource_blueprint_repository.dart:86`；对照 `lib/application/resources/resource_creation_pipeline.dart:397`（`pendingPlanningSessions` 无调用方）
- **Problem**：`BlueprintPlanner` 与 `ResourceBlueprintRepositoryImpl` 在 `lib/` 中没有任何构造点或调用方；Phase 3 留下的 `pendingPlanningSessions()` / `session.awaitsPlanning` 接缝无人消费；Phase 4 提交集不含任何入口或 UI 文件。
- **Evidence**：`rg "BlueprintPlanner\(|ResourceBlueprintRepositoryImpl\(" lib` → 无结果；`git show --stat 1e7bff5` → 15 个文件，无 entry point；独立用例 I-12 失败（`Actual: []`）。
- **Why it violates Phase 4**：phase-04 目标是「AI 创建的第一步只生成…不生成完整正文」，未接入即表示该行为在产品中完全不存在；且 Phase 3 明确把 blueprint 交给 Phase 4，链路在此断裂。命中 BLOCKER 示例「Blueprint 根本未接入真实 creation flow」。
- **Required remediation direction（不含实现）**：说明 Phase 4 是否有意 defer 接线（若有意，需经 ADR/方案评审显式确认并写入 `STATUS.md` 的 Deferred Issues，同时明确哪一阶段负责接线）；否则应在 Phase 4 范围内把 AI 创建入口接到 planner（例如入口拿到 `planning` 会话后调用 `plan`，向用户呈现 Blueprint，用户确认后调用 `confirm`），并**同步决定旧 AI 生成路径的归属**，避免形成第二套 AI creation pipeline。接线时必须沿用 `ResourceCreationPipeline` 单一入口，不得再新增并行持久化路径。

### H1 — HIGH — confirm 可覆盖与本会话无关的既有资源（无归属校验）

- **File / Line**：`lib/application/resources/resource_blueprint_repository.dart:250`（`allocatedResId` 直接采信 `explicitResourceId`）、:302（存在即走 `updateResourceTreeInTransaction`）、对应 `resource_tree_repository_impl.dart:142-153`（硬删除并重插该资源全部 Section/Part）
- **Problem**：`confirmBlueprint(explicitResourceId: X)` 不校验 X 是否属于该 Blueprint 的创建会话，只要 X 存在就整树替换：资源名称被改写为 Blueprint 建议名，原有 Section/Part（含用户已写正文）被物理删除后重建为空占位。
- **Evidence**：独立用例 I-14 失败，返回 `ResourceBlueprintConfirmResult(resource: res_victim, reused: false)`，受害资源名称变为 `独立验收大纲`。
- **Why it violates Phase 4**：「confirm 只允许按本 Blueprint 创建占位」「规划过程不得污染正式 Resource Tree」被反向突破——confirm 成为一条可销毁既有用户内容的写路径。当前因无生产调用方（B1）而处于潜伏状态，**一旦接线且入口透传 resourceId，即为直接数据销毁**。
- **Required remediation direction**：在 confirm 事务内校验归属——`explicitResourceId` 必须等于会话自身的 `resource_id`（或记录ified 由本次会话创建），否则拒绝；对「资源已存在」分支明确区分「本会话幂等重放」与「覆盖他人资源」两种语义；不要依赖 `updateResourceTree` 的整树硬删除作为幂等手段（优先短路返回 `reusedExisting`）。

### MEDIUM

- **M1 — 重复 `plan()` 静默销毁上一份 draft，revision 唯一性无 DB 约束**
  `resource_blueprint_repository.dart:128-145`：`ConflictAlgorithm.replace` + 确定性 `bp_<sid>_rev1`，二次 plan 覆盖首份 draft 且无 `superseded` 记录；`resource_blueprints` 缺 `UNIQUE(session_id, revision)`。方向：区分「新建 draft」与「重放」，重放应失败或显式生成新 revision；补唯一约束。
- **M2 — confirm 后 replan 产生永久不可确认的 revision**
  `planner.dart:120` 不检查会话/BP 终态，而 `repository.dart:243` 因会话 `completed` 拒绝后续 confirm。方向：明确 post-confirm 修订语义（禁止 replan，或定义新的会话/blueprint 生命周期），并在 ADR 记录。
- **M3 — 新表缺少外键与级联策略**
  `database_service.dart:410/437`：两张新表无任何 REFERENCES。方向：补外键或明确「软删除 → 任务行的清理职责归属 Phase 5/9」，避免孤儿 `resource_generation_tasks`。
- **M4 — confirm 不重新校验落库的 Blueprint**
  `confirmBlueprint` 只信任 `blueprint_json`，所有 ID/DAG/容量守卫都是调用方责任。方向：把 `BlueprintValidator.validate` 下沉到 confirm 入口（或 repository 写路径），使任何写入源都无法绕过。

### LOW

- **L1 — `BlueprintStatus.cancelled` 从未使用**；`BlueprintStatus.fromStorage` 对未知值静默回退为 `draft`（`resource_blueprint.dart:13`），可能让状态损坏的行被当作可确认。
- **L2 — 执行方 rollback 用例的 oracle 偏弱**：先 cancel 会话使失败发生在任何写入之前，不能证明中途回滚。真实原子性已由 I-1 证明，建议将该用例改为真实主键冲突型失败点。
- **L3 — `BlueprintSection.sortOrder` / `BlueprintPart.sortOrder` 未传导到树节点**：`ResourceTreeSectionDraft` / `ResourceTreePartDraft` 无 sortOrder 字段，`_insertTree` 用数组下标落排序值；而 `resource_generation_tasks.sort_order` 用的是蓝图里的数值。二者可能在模型乱序输出时不一致。方向：统一以数组顺序为唯一事实源，或让 draft 类型承载 sortOrder。
- **L4 — 外层 `Timer` 超时不取消在途 HTTP 请求**（`planner.dart:215`），超时后底层请求仍在运行。方向：超时时同时触发 `taskHandle.cancel()`，或明确由底层栈统一提供超时。
- **L5 — `resource_generation_tasks` 插入使用 `ConflictAlgorithm.replace`**（`repository.dart:337`），Phase 5 落地后会把已完成/生成中的任务状态重置为 `pending`。方向：Phase 5 引入 typing/状态时改为幂等 upsert（按 `(generation_id, part_id, sequence)`）。

## 21. STATUS.md Update

已按 verdict 更新 `docs/adaptive-resource-system/STATUS.md`：

- Phase 4 状态：`IMPLEMENTED` → **`REJECTED`**（保留 IMPLEMENTED 事实与 End HEAD，新增本次验收记录）。
- Phase 5 状态：保持 **`BLOCKED`**（不得解锁）。
- `Current Repository HEAD` 记录为 `264151367ffd760c50467f1f79a87d4b7f98fdaf`。

本次验收对仓库的唯一写入：

1. `docs/adaptive-resource-system/phase-04-independent-acceptance.md`（本报告）
2. `docs/adaptive-resource-system/STATUS.md`（状态更新）
3. `test/application/resources/phase4_independent_acceptance_test.dart`（验收证据，非业务代码）

**业务实现（lib/）零修改。**

## 22. Phase 5 Unlock Decision

```text
Phase 4 = REJECTED
Phase 5 = BLOCKED
```

解锁前置条件（必须全部满足后重新提交验收）：

1. B1 关闭：要么在 Phase 4 范围内完成 AI 创建入口到 planner 的接线并证明 `pendingPlanningSessions` 被真实消费，要么经 ADR 明确「接线归属后续阶段」并写入 Deferred Issues 与接手阶段。
2. H1 关闭：confirm 增加归属校验，禁止覆盖非本会话资源；并补一条针对该场景的回归测试（可用独立用例 I-14 作为验收门槛）。
3. 上述修复后，`test/application/resources/phase4_independent_acceptance_test.dart` 的 I-12 与 I-14 必须通过；M1–M4 建议同批或明确延期，`flutter analyze`、Phase 4 定向、Phase 3 回归与全量 `flutter test` 需全部通过。

在 Phase 4 重新验收通过之前，Phase 5（增量 JSON 挂载协议）不得开始实施。
