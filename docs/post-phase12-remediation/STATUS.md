# LT Post-Phase-12 Remediation - Program Status

本文件是当前 **7-Phase Program** 的唯一状态源。初始 13-Phase 与中间 8-Phase 状态
仅作为归档历史（`archive/initial-13-phase-plan/`、`archive/pre-7-phase-plan/`），
不再决定执行。2026-09-19 的 8→7 压缩：former R05+R06 合并为新 R05，former R07 →
新 R06，former R08 → 新 R07；R01-R04 的历史编号与验收记录不变。

## 状态规则

1. Phase 只依赖其 `Depends On` 中列出的 technical dependency；编号相邻不构成依赖。
2. 执行 Agent 只能标记 `IMPLEMENTED`，只有独立 Acceptance Agent 可标记 `ACCEPTED`。
3. `BLOCKED` 表示明确依赖尚未 `ACCEPTED`；`PLANNED` 表示技术上可开始。
4. 失败记录不得删除；必须保留失败原因、最后安全 HEAD 和恢复建议。
5. P0/P1/P2 是架构簇优先级，不等同于单个 finding 的 severity。

## 当前总体状态

| 字段 | 当前值 |
| --- | --- |
| Program | Post-Phase-12 Remediation, reprioritized 8-phase plan |
| Original Audit / Initial Planning HEAD | `c94315e26cd4db3051f9f8af8ad5a3bdca0f7b8c` |
| R01 Start HEAD | `b412b8b780395e7339fd29bcf612d8c0438bfc1d` |
| R01 Implementation Commit | `67ec88cc431cc8150f844b0397e72e1c0f201b9c` |
| Replanning Start HEAD | `4ca946fbcbab52100ed39463b249d2650c636d7c` |
| Replanning Docs Commit | Recorded by the docs-only Git commit containing this file |
| Schema Version | 43 |
| Current Milestone | B - Runtime Reliability |
| Current Phase | R04 accepted; R05/R06 unblocked |
| Last Accepted Phase | R04 |
| Next Action | R05 or R06 implementation |
| Last Updated | 2026-09-19 |

## Phase 状态

| Priority | Milestone | Phase | Name | Status | Depends On |
| --- | --- | --- | --- | --- | --- |
| P0 | A | R01 | Streaming Generation Lifecycle & Recovery | `ACCEPTED` | - |
| P0 | A | R02 | Atomic Commit & Content Write Integrity | `IMPLEMENTED`（independent acceptance outstanding） | - |
| P0 | A | R03 | Resource Identity, Delete, Trash & Revision Lifecycle | `ACCEPTED` | - |
| P1 | B | R04 | LLM Transport & Streaming Protocol Reliability | `ACCEPTED` | R01 `ACCEPTED` |
| P1 | B | R05 | Runtime State, Production Wiring & Context Continuity（merged former R05+R06） | `PLANNED` | R01 `ACCEPTED` |
| P2 | C | R06 | Migration, Serialization & Defensive Hardening（former R07） | `BLOCKED` | R01-R05 all `ACCEPTED`（含 R02 independent acceptance） |
| P2 | C | R07 | Cleanup & Code Slimming（former R08） | `BLOCKED` | R01-R06 all `ACCEPTED` |

`PLANNED` 不代表推荐抢先执行。单 Agent 推荐按 R01 → R02 → R03 → R04 → R05 →
R06 → R07 顺序实施；该顺序是 recommendation，可用性仍由 technical dependencies
决定。

## Milestone Gates

| Milestone | Exit Gate |
| --- | --- |
| A Core Integrity | R01-R03 全部 `ACCEPTED`；BLOCKER=0；数据丢失、commit、identity、delete/restore、持久生命周期相关 MAJOR 关闭。**注意：R02 independent acceptance 尚未执行，Milestone A formal acceptance gate remains incomplete**——R03/R04 的验收历史不改变这一事实 |
| B Runtime Reliability | R04 + R05 全部 `ACCEPTED`；transport bounded；typed streaming failures；async state ownership；production/test wiring convergence；context bounded；summary/history continuity |
| C Hardening & Slimming | R06 + R07 全部 `ACCEPTED`；随后执行 Final Post-Remediation Full Repository Audit |

下一轮大型功能开发至少必须等待 Milestone A 的 formal gate 闭环；角色状态、世界
状态、权重管理等下一代架构应等待 Milestone B。P2 只在 correctness 已稳定后执行。

## R01 实施与独立验收历史

Status: `ACCEPTED`

```text
Executor: Remediation R01 Implementation Agent
Started / Completed: 2026-09-19
Start HEAD: b412b8b780395e7339fd29bcf612d8c0438bfc1d
End HEAD / Implementation Commit: 67ec88cc431cc8150f844b0397e72e1c0f201b9c
Implementation: lifecycle, retry convergence, startup recovery, shared provider ownership,
                stop-request cleanup, production wiring tests
dart format: PASS (497 files, 0 changed)
flutter analyze: PASS (No issues found)
targeted tests: PASS (35 passed, 0 failed)
full flutter test: PASS (1610 passed, 0 failed)
mutation MUT-01...MUT-05: PASS
git diff --check: PASS
Acceptance: ACCEPTED at baseline 3485fef1255f24089210fb27f8833c974df8c12b
Reviewer: R01 Independent Acceptance Agent
Acceptance Date: 2026-09-19
Acceptance Report: remediation-phase-01-independent-acceptance.md
Acceptance targeted tests: PASS (35 passed, 0 failed)
Acceptance full flutter test: PASS (1610 passed, 0 failed)
Acceptance mutations: MUT-A1...MUT-A5 detected; MUT-A6 survived as non-blocking TEST-GAP
Known non-blocking finding: production wiring test does not detect an independent
  Section runtime service; current production code was statically verified to reuse
  the Studio controller/session repository. Carry this guard into R05.
Schema: 43
Startup recovery: autoResume=false; no billable LLM request replay
```

## R02 实施历史

Status: `IMPLEMENTED`（等待独立验收）

```text
Phase / Priority / Milestone: R02 / P0 / A
Executor: Remediation R02 Implementation Agent
Started / Completed: 2026-09-19
Start HEAD: e98cc94cc38b37855ed2b485c1b1eb69178b040c
Implementation Commit(s):
  R02-A dialogue commit boundary: 5a67a2ee472588456aa48a25a55c5662f96f17bc
  R02-B part content source CAS:  76d743f66009fbf226e44200a771473812caa033
  R02-C autosave durability:      45eb245e13786488e843e75ec53e83ec3b524ce0
Schema Version: 43 (unchanged; compression job rows already carried source_token,
                   generation uses resource_parts.updated_at captured at lease)
dart format: PASS (499 files, 0 changed)
flutter analyze: PASS (No issues found)
R02 targeted tests: PASS
  chat_engine_cancellation_commit_boundary_test.dart: 7 passed (A1-A7)
  r02_part_content_source_cas_test.dart: 11 passed (B1-B10 + coordinator)
  resource_autosave_service_test.dart: 42 passed (31 existing + C1-C12)
  phase9_concurrency / phase9_revision_boundary / generation_task_repository /
  streaming_lifecycle: included in the same targeted run, 90 passed / 0 failed
full flutter test: PASS (1638 passed, 0 failed; R01 baseline was 1610)
Mutation verification:
  MUT-R02-A (restore post-commit cancellation throw + fake rollback):
    A2, A3 failed -> guard proven, mutation reverted
  MUT-R02-B (disable source CAS check and guarded where):
    B1, B9/B10, coordinator test failed -> guard proven, mutation reverted
  MUT-R02-C (disable failure requeue after flush snapshot):
    C1, C5, C6 failed -> guard proven, mutation reverted
git diff --check: PASS
Known / Deferred Issues:
  - The pre-commit final gate in ChatEngine sits immediately before the commit
    after a synchronous stretch, so it is defence in depth behind the guards
    after each await; kept intentionally.
  - Mutation note: removing ONLY the final pre-commit gate is not detectable
    because every await between streaming and commit already has its own
    guard; MUT-R02-A therefore restored the original post-commit throw +
    fake-rollback pair, which A2/A3 detect.
Handoff: Independent R02 Acceptance
```

## R03 实施历史

Status: `IMPLEMENTED`（等待独立验收）

```text
Phase / Priority / Milestone: R03 / P0 / A
Executor: Remediation R03 Implementation Agent
Started / Completed: 2026-09-19
Start HEAD: 9566d3137433593ec7de93068eb4271f3fafbdb4 (R02 end)
Implementation Commit(s):
  R03-C revision lifecycle gate:  35c201fd6287814077041e44aa997f6410efd724
  R03-B owned-state cascade:      e128b0e4a7577b83216ca5d9ab38ebc2f8dcbe9c
  R03 belongs-to guard restore:   67c9a9b82206e611b44bd1c0ade7d5113bb1a36b
Schema Version: 43 (unchanged; every owned auxiliary table carries resource_id,
                   cascades use existing ON DELETE CASCADE foreign keys)
dart format: PASS (500 files, 0 changed)
flutter analyze: PASS (No issues found)
R03 targeted tests: PASS (14 passed / 0 failed, r03_lifecycle_integrity_test.dart)
  TG9: revision restore trashed/gone/live matrix; explicit trash restore first;
       CP-2 child belongs-to (section owner, part owner, part parent owner);
       section restore refused while parent resource is in the bin
  TG10: full owned-state cascade with tombstone; node-scoped purge;
        purge failure full rollback; retention purge idempotent + cascade;
        migration idempotency; purge-then-re-migrate no resurrection
full flutter test: PASS (1652 passed, 0 failed; R02 end baseline was 1638)
Mutation verification:
  MUT-R03-1 (remove revision-restore lifecycle gate):
    TG9 trashed-refusal + restore-order tests failed -> reverted
  MUT-R03-2 (remove section-restore parent-live guard):
    TG9 child-restore test failed -> reverted
  MUT-R03-3 (omit resource_autosaves from owned cascade):
    TG10 cascade + retention tests failed -> reverted
  MUT-R03-4 (split owned purge out of the purge transaction):
    TG10 rollback test failed -> reverted
  MUT-R03-5 (remove belongs-to ownership checks):
    TG9 CP-2 tests failed -> reverted
  id-equality mutation: not applicable - the audit found no integer id
    equality inference anywhere (identity is mapping-table based, deterministic
    res_legacy_ ids, fingerprint idempotency); covered by TG10 identity tests
git diff --check: PASS
Ownership / cascade classification:
  owned & cascaded in the purge transaction: resources/sections/parts (tree),
    resource_trash entry, legacy row (when linked), resource_revisions
    (+revision_nodes via FK), resource_autosaves, resource_compression_jobs
    (+candidates via FK), resource_generation_sessions, resource_blueprints,
    resource_generation_tasks (+attempts via FK), resource_assembly_readiness,
    resource_assembly_entries
  NOT owned / explicit tombstone: resource_creation_sessions (UNIQUE
    idempotency_key must keep blocking reuse), world_entries + embeddings and
    adventure_runtime_entities (adventure aggregate, free-text links)
Known / Deferred Issues:
  - A migration record for a purged resource stays `succeeded` (tombstone);
    a re-created legacy row with the same id/hash is skipped by the migration
    and surfaces as `treeMissing` in ResourceReadFacade instead of silently
    re-creating the tree. Deliberate fail-safe, carried as-is.
  - During mutation verification a working-tree restore temporarily dropped
    the belongs-to guards; the full-suite failure caught it immediately and
    commit 67c9a9b restored them - recorded as process evidence, no residual.
Handoff: Independent R03 Acceptance
```

## R03 实施与独立验收历史

Status: `ACCEPTED`

```text
Executor: Remediation R03 Implementation Agent
Started / Completed: 2026-09-19
Start HEAD: 9566d3137433593ec7de93068eb4271f3fafbdb4
Implementation Commit(s):
  R03-C revision lifecycle gate:  35c201fd6287814077041e44aa997f6410efd724
  R03-B owned-state cascade:      e128b0e4a7577b83216ca5d9ab38ebc2f8dcbe9c
  R03 belongs-to guard restore:   67c9a9b82206e611b44bd1c0ade7d5113bb1a36b
Implementation: revision restore lifecycle gate (trashed/gone typed refusal),
                CP-2 child belongs-to guards, owned-state purge cascade in the
                permanent-delete transaction, section-restore parent-live guard,
                TG9/TG10 real-SQLite lifecycle matrix
Schema: 43
dart format: PASS (500 files, 0 changed)
flutter analyze: PASS (No issues found)
targeted tests: PASS (14 passed, 0 failed, r03_lifecycle_integrity_test.dart)
full flutter test: PASS (1652 passed, 0 failed)
Implementation mutations: gate removal / parent guard / omitted cascade /
  split transaction / belongs-to removal all DETECTED and reverted
Acceptance: ACCEPTED at baseline 93ce815a9eb4357a99754c6fe828ede02099189e
Reviewer: R03 Independent Acceptance Agent
Acceptance Date: 2026-09-19
Acceptance Report: remediation-phase-03-independent-acceptance.md
Acceptance targeted tests: PASS (190 passed, 0 failed)
Acceptance full flutter test: PASS (1652 passed, 0 failed)
Acceptance mutations: MUT-ACC-1..3 DETECTED; MUT-ACC-4 probe confirmed MINOR
Known non-blocking finding: R03-A-N1 (MINOR) - node-scoped purge of a Section
  leaves its purged Parts' generation tasks and autosave drafts behind. Fail-
  closed litter (recovery classifier drops vanished-node drafts; task commit
  fails closed), no resurrection/data-loss path. Repair: extend node-scoped
  cascade to descendant part ids; can ride R08 or an earlier targeted fix.
Handoff: Milestone A exit gate reached; R04/R05/R06 technically unblocked
```

## R04 实施历史

Status: `IMPLEMENTED`（等待独立验收）

```text
Phase / Priority / Milestone: R04 / P1 / B
Executor: Remediation R04 Implementation Agent
Started / Completed: 2026-09-19
Start HEAD: bfc57f0e7820eb485f17f93a2b4c0183c31b5df3 (R03 end)
Implementation Commit(s):
  R04 A/B/C/D production+tests:   ea1d721
  test probes (B7/D11 strengthen): b92a569
Schema Version: 43 (unchanged)
Timeout policy (LLMStreamTimeoutPolicy, single owner = LLM transport layer):
  connect 30s / first-event 90s / idle 120s / overall 10min; FIM call bounded
  by overall. Typed LLMStreamTimeoutException extends ApiError(networkTimeout)
  and carries the phase. Cancellation closes the client and surfaces as
  GenerationCancelledException, never as a timeout.
Retry maximum:
  transport owner = LLMService only: RetryManager maximumAttempts 3 (incl.
  first), suppressed once a content delta was accepted (receivedAnyDelta
  flips only after the consumer accepted the chunk)
  AiGeneratorService: no transport retry of its own (removed)
  structured stage content budget: 3 attempts
  worst case HTTP requests per structured stage: 3 x 3 = 9 (bounded)
  coordinator part retries: maxRetriesPerPart 2 => 3 x 3 = 9 (bounded)
  retryable: 429/5xx/connect/first-event/idle timeouts, connection failures;
  not retryable: other 4xx, auth, schema/protocol errors, consumer
  exceptions, cancellation, any request whose delta already streamed
Error propagation:
  malformed provider JSON / shape => malformedEventCount++ and skipped
  consumer/parser/validator exception => propagates VERBATIM (stack kept),
  subscription stops, never counted as provider noise, never wrapped as
  transport failure (also fixed on the Anthropic branch)
  usage/keepalive events never create content deltas; usage still captured
  stream without completion semantics => responseCompleted=false and the
  typed text API refuses the partial result
Protocol convergence:
  fallback and streaming share PartGenerationParser allowlist,
  GenerationPatchParser.responseToPatches, GenerationPatchAccumulator
  (sequence/cursor/identity) and PartGenerationValidator; D11 drives the
  real coordinator fallback path with an unauthorized field
dart format: PASS (502 files, 0 changed)
flutter analyze: PASS (No issues found)
R04 targeted tests: PASS (35 passed / 0 failed,
  llm_streaming_reliability_test.dart: A1-A6, B1-B9, C1-C6, D2/D3/D4/D11)
R01 regression: PASS (22 passed / 0 failed across streaming lifecycle
  recovery, shared service/controller, section regeneration tests)
full flutter test: PASS (1678 passed / 0 failed; R03 end baseline 1652)
Mutation verification (all reverted, no residue):
  MUT-R04-1 remove idle/first-event window distinction => A3 FAILED
  MUT-R04-2 allow transport retry after receivedAnyDelta => B7 FAILED
  MUT-R04-3 put onChunk back into the decode catch => C1 FAILED
  MUT-R04-4 bypass unified protocol validation in fallback => D11 FAILED
git diff --check: PASS
Known / Deferred Issues:
  - Anthropic messages branch is currently unreachable in production
    (LLMProvider.usesAnthropicMessagesApi is constant false); its failure
    semantics were fixed symmetrically and are covered via a test seam.
  - RetryManager base backoff (1s/2s) remains per-attempt wall-clock wait in
    production; tests inject the delay seam.
Handoff: Independent R04 Acceptance
```

## R04 实施与独立验收历史

Status: `ACCEPTED`

```text
Executor: Remediation R04 Implementation Agent
Started / Completed: 2026-09-19
Start HEAD: bfc57f0e7820eb485f17f93a2b4c0183c31b5df3
Implementation Commit(s):
  ea1d721db0c4dbb9a92d8efe36e1245e9d7c1693  A/B/C/D production + tests
  b92a5694155f535f38d04c714ca2c9e613df8c71  B7/D11 probe strengthening
Implementation: single-owner timeout policy (connect/first-event/idle/overall,
                typed exception with phase), single transport retry owner
                (max 3, delta-suppressed), consumer error verbatim
                propagation, protocol convergence pinned by tests
Schema: 43
dart format: PASS (502 files, 0 changed)
flutter analyze: PASS (No issues found)
targeted tests: PASS (35 passed / 0 failed)
R01 regression: PASS (22 passed / 0 failed)
full flutter test: PASS (1678 passed / 0 failed)
Implementation mutations: idle-window removal / receivedAnyDelta retry /
  onChunk-into-decode-catch / fallback bypass all DETECTED and reverted
Acceptance: ACCEPTED at baseline 029f1ccc5c139d67aaa7ae2b85e96b2667b6a713
Reviewer: R04 Independent Acceptance Agent
Acceptance Date: 2026-09-19
Acceptance Report: remediation-phase-04-independent-acceptance.md
Acceptance targeted tests: PASS (94 passed / 0 failed incl. R01 regression)
Acceptance full flutter test: PASS (1678 passed / 0 failed)
Acceptance mutations: MUT-ACC-1/2/4 DETECTED; MUT-ACC-3 initially SURVIVED
  (A6 probe too fast) - A6 strengthened during acceptance, then DETECTED;
  strengthened probe committed with the acceptance
Known non-blocking finding: R04-A-INFO-1 - Anthropic messages branch is
  production-unreachable (provider flag constant false); failure semantics
  fixed symmetrically, covered via test seam.
Handoff: R05/R06 unblocked
```

## 阶段记录模板

```text
Phase / Priority / Milestone:
Status:
Executor:
Start HEAD:
Implementation Commit:
Targeted tests:
Full flutter test:
flutter analyze:
Mutation / negative tests:
git diff --check:
Independent Acceptance:
Known / Deferred Issues:
Handoff:
```
