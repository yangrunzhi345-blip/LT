# Audit Result

Status: PASSED（仅 R3 协议冲突修复范围）

Acceptance Mode: Independent Review

日期：2026-10-13。基线：`main` @ `ea5de88`，审查当前未提交 diff 与两个新增测试文件。审查 Agent 只读核查；唯一写入为本报告，没有修改代码、测试、配置、commit、push 或发布。

## Summary

未解决发现：BLOCKER = 0、MAJOR = 0、MINOR = 0。R3 协议完整性局部修复可验收；**完整 Phase 2 Gate 与整个修复不标记 ACCEPTED**。Phase 1 产品 profile 批准仍待答复，本报告不验收 Phase 2 的 E 配置 / UI 联动部分或后续预算与正文闭环。

权威依据：`AGENTS.md`、`docs/character-generation-budget-root-cause-and-remediation.md` ISSUE-07、第 6.3、10、13、14.2 节及 ADR-0003。R3 可独立于最终内容阈值实施，不能据此宣称已解决真实现场短正文的未知 wire 根因。

审查文件：`lib/application/resources/generation_patch_parser.dart`、`resource_generation_error.dart`、`part_generation_coordinator.dart`；`test/application/resources/patch_sequence_conflict_test.dart`、`patch_sequence_conflict_sqlite_test.dart`。另外追踪 ModelGenerationPatchDecoder、生产 LLM streaming gateway / consumer 异常传播、StreamingResourceGenerationService、Studio delta 预览与真实 SQLite Task / Revision 提交路径。

## Verification

- 每个已应用 sequence 保存原始应用 offset 与 SHA256 指纹。指纹采用既有 ContentHasher 的 JSON 编码，包含 protocol、绑定身份、sequence、op、text、summary、fail 信息和规范 cursor。缺省 cursor 与等价显式原始 offset 相同；与原 offset 不同明确冲突。没有拼接歧义，也不按当前已增长长度误判旧重放。
- 相同 start / append / complete / fail 重放没有追加、序号增长或重发预览回调；不同同 seq 抛 PatchSequenceConflictException 并使 toResponse 不可用。异常与持久错误只保留安全元数据 / resourceParseFailed，不带冲突正文或摘要。
- 唯一事件指纹数量默认上限 6002；不逐出旧事件，超限显式失败。终止后新连续事件被拒绝，相同终止 marker 重放仍幂等。原身份绑定、gap、cursor、正文传输上限守卫没有放宽。
- streaming 与 collected 均捕获新冲突异常并发一次 validation failure；响应不能进入 commit。真实 SQLite 测试只替换网络边界，覆盖两路冲突与幂等、无末尾换行、跨 chunk NDJSON 和包含 Unicode / 引号 / 反斜线 / 换行的逐字符保存。
- 已有有效正文重生成冲突时，Part（含 hash）、Section、resource、revision 行完整保持；旧 completed attempt 不变，新 failed attempt 可追溯。空正文冲突也不生成 revision、不 completed。既有 source CAS、cancel / superseded lease、Revision 并发保护使用真实 SQLite 复验。
- 原有生产 LLM 客户端将 consumer 异常传播到调用方，并排除 consumer failure 的 transport 重试；未新增协议版本、修改 E / C / A / K、迁移 schema 或改变提交事务。

实际执行命令（最终文件版本）：

```bash
flutter test test/application/resources/patch_sequence_conflict_test.dart test/application/resources/patch_sequence_conflict_sqlite_test.dart test/application/resources/generation_patch_parser_test.dart test/application/resources/part_generation_coordinator_test.dart test/application/resources/model_generation_patch_decoder_test.dart test/application/resources/r02_part_content_source_cas_test.dart test/application/resources/phase9_concurrency_test.dart test/services/llm_streaming_reliability_test.dart --reporter expanded > /tmp/lt-phase2-review-final-all.log 2>&1
# Exit 0; +115: All tests passed!

flutter analyze
# Exit 0; No issues found! (ran in 2.7s)

dart format --output=none --set-exit-if-changed lib/application/resources/generation_patch_parser.dart lib/application/resources/resource_generation_error.dart lib/application/resources/part_generation_coordinator.dart test/application/resources/patch_sequence_conflict_test.dart test/application/resources/patch_sequence_conflict_sqlite_test.dart
# Exit 0; Formatted 5 files (0 changed)

git diff --check
# Exit 0; no output
```

另执行 `dart --packages=.dart_tool/package_config.json /dev/stdin` 只读探针，确认：相同 start / fail 保持 nextSequence；changed fail 抛类型化冲突；complete 后新 append 失败且 response 不可导出。另对不同孤立 UTF-16 surrogate 做指纹探针，JSON 明确编码为不同 escape，hash 不同，重复 sequence 被正确拒绝；该探针以未捕获预期冲突 Exit 255 结束，不列为测试 PASS。

## Findings

未解决发现：无。

独立审查发现并在本轮解决一项 MINOR：初稿 accumulator 忽略相同重放后，coordinator 仍向 onPatchReceived 发布重复 delta；真实路径 `StreamingResourceGenerationService → ResourceStudioController._appendPatch` 直接追加，导致短暂重复预览，直到 snapshot / flush 修正。独立只读探针证实相同 patch 的累积正文为单份、无条件 delta 预览为双份。执行方在两条 coordinator 路径比较 apply 前后 nextSequence，仅发布新接受事件；最终 SQLite 回归同时断言 callback delta 完全等于保存正文、start / append / complete 回调共三次，均通过。没有扩大 Studio UI 修改范围。

## 未覆盖与后续门禁

这是 R3 局部审查，不证明完整 Phase 2 配置快照 / UI 验收完成，也不证明 reserve、内容契约生产接入、重试分类、手动恢复或装配闭环已交付。产品 U6 决策仍需批准；任务总体验收仍需后续阶段、全量回归、负向门禁及最终独立审查。

本次未独立运行全仓库 full regression、真实付费模型、真实设备、v49 migration 或完整 E 冻结矩阵。后两项执行方另有测试记录，但不将其计入本报告的独立验证结果。未读取用户数据库；临时测试使用独立 fixture SQLite。
