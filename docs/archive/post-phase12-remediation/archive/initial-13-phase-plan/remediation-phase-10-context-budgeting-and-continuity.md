# Remediation Phase 10 — Context Budgeting & Continuity

> **Root Cause**: RC-10
> **Findings**: M13 (MAJOR), N18, N19, N20, TG15
> **Depends On**: None
> **Document status**: PLANNED

---

## 1. Purpose

上下文预算与历史连续性存在多处问题：

- 详细世界观生成的**生产路径**把完整源文本重复内联到每个阶段请求，无任何上界；有界的
  `DetailedWorldviewContextPolicy` 只被一个 `...ForTesting` 方法使用（M13）；
- `TokenEstimator` 按 UTF-16 code unit 计数，对 emoji / CJK 扩展区估计错误，且与
  `ChineseCharacterCounter` 口径不一致，而预算/裁剪都建立在它之上（N18）；
- 摘要输入直接重发含 `---JSON---` 结算 payload 的 assistant 原文（N19）；
- 摘要窗口（保留最近 12 条）与 prompt 预算裁剪互不联动，预算不足时被裁掉的消息既不在摘要也不在
  history，形成不可恢复的历史断层（N20）。

本 Phase 修复的 contract 是：**“任何进入模型请求的上下文都有明确上界；被移出 prompt 的历史必须已被
摘要覆盖；token 估算与中文字符计数只有一套口径。”**

## 2. Audit Findings Covered

```text
Primary:
- M13  详细世界观生产路径无界内联完整源文本（有界策略仅在死路径）

Related:
- N18  TokenEstimator 按 UTF-16 计数、与 ChineseCharacterCounter 口径不一致
- N19  摘要输入重发结算 JSON
- N20  摘要窗口与预算裁剪不联动 → 历史断层

Test gaps:
- TG15 无“世界观/角色单次注入”的 prompt 组成断言
```

> 说明：审计子报告中曾提出“世界观/角色在对话 prompt 中被注入两次”。本规划核对代码后确认
> `PromptBuilder.buildMessages` 调用 `AppConfig.adventurePrompt(..., includeSetupContext: false)`
> （`prompt_builder.dart:35-44`），因此 `_buildConfigSection` / `_buildCharacterCardSection` 未启用，
> 该条为**误报**，不在本 Phase 处理。

## 3. Current Production Architecture

### 3.1 详细世界观生成

```text
Wizard → AdventureAiController.generateDetailedWorldview
  → AiGeneratorLlmGateway.textToDetailedWorldview                        (ai_generator_llm_gateway.dart:119)
  → AiGeneratorService.textToDetailedWorldview                           (ai_generator_service.dart:103)
      → textToDetailedWorldviewMultiTurn                                 (:201-...)
            $sourceText 内联于 :326,369,403,438,466,511,537,585,604,660,699
            _ensureDetailedWorldviewTarget                               (:901) 最多再补 16 轮
            _worldviewSupplementPrompt                                   (:1025-1037) 再次内联 $sourceText
  → generateDetailedWorldviewCoordinatorForTesting                       (:1114)
        唯一使用 DetailedWorldviewContextPolicy.briefSource             (:1219-1235)；lib 内零调用
```

`DetailedWorldviewContextPolicy`（`detailed_worldview_context_policy.dart`）：
`maximumContextTokens = GenerationLimits.detailedWorldviewContextTokens`，
`approximateCharactersPerToken = 4`，`briefSource` 取首尾。

### 3.2 对话上下文预算与摘要

```text
PromptBuilder.buildMessages → ContextOrchestrator.build                   (narrative_context.dart:~1000+)
    const retainMessageCount = 12                                          (:1131)
    recent = history.sublist(len-12)                                       (:1137-1139)
    historyBudget = inputLimit - fixedTokens
    while (recent.isNotEmpty && historyBudget < 0) recent = recent.sublist(1)  (:1151-1155)

SummaryService.summarize                                                 (summary_service.dart)
    static const summarizeRetainCount = retainFullRounds * 2  (=12)        (:26,32)
    summarizeEnd = totalMsgs - 12 → saveSummary(upToIndex)                 (:112-118)
    systemPrompt / user content 直接使用 m.content                         (:183-190)

TokenEstimator                                                           (token_estimator.dart:10-21)
ChineseCharacterCounter                                                  (chinese_character_counter.dart:19-25)
```

## 4. Exact Bugs

### Finding M13 — 详细世界观生产路径无界注入源文本

#### Trigger
用户在向导中粘贴较大的世界观源文本（数万字符），或使用小上下文窗口的自定义模型。

#### Current Behavior
`textToDetailedWorldviewMultiTurn` 在最多 5 个阶段与最多 16 轮补充中，**每次请求都完整内联
`$sourceText` 与逐步增长的 `detail` JSON**。有界策略 `DetailedWorldviewContextPolicy` 只被
`generateDetailedWorldviewCoordinatorForTesting` 使用（lib 内零调用）。因此请求体积随源文本线性增长，
第一轮就可能超过 8k 上下文窗口，并在补充轮持续增大。

#### Expected Behavior
生产路径必须对源文本应用有界策略（首尾截断），并只发送相关阶段/模块，而非每次全量源文本+全量 JSON。

#### Evidence
```text
file: lib/services/ai_generator_service.dart（$sourceText 内联点、_ensureDetailedWorldviewTarget、_worldviewSupplementPrompt）
file: lib/services/detailed_worldview_context_policy.dart（briefSource 未被生产使用）
file: lib/application/llm/ai_generator_llm_gateway.dart:119（生产入口）
既有测试: detailed_generation_and_wizard_test.dart 用极小 source 与 mock，不会触发
```

#### User / Data Impact
大源文本下自我生成失败/超上下文；请求成本与延迟膨胀；小上下文模型完全不可用。

---

### Finding N18 — TokenEstimator 计数口径错误

#### Trigger
文本含 emoji / 非 BMP 字符 / CJK 扩展 A（`0x3400-0x4DBF`）。

#### Current Behavior
`TokenEstimator` 遍历 UTF-16 code unit，emoji 代理对记为两个 `>127` 单位；CJK 扩展 A 记 0.5，
而 `ChineseCharacterCounter` 将其计为汉字。预算裁剪、摘要边界、压缩阈值、详细世界观策略都建立在
该估算上，估算偏差会影响保留/裁剪决策。

#### Expected Behavior
按 rune 遍历；CJK 判定与 `ChineseCharacterCounter` 统一为同一套范围定义；两处口径一致并有测试。

#### Evidence
```text
file: lib/utils/token_estimator.dart:10-21
file: lib/utils/chinese_character_counter.dart:23-25
使用点: lib/application/narrative/narrative_context.dart:1125-1155, lib/application/resources/resource_context_compressor.dart, detailed_worldview_context_policy.dart
```

#### User / Data Impact
预算估算偏差导致长文本被过早裁剪或超限；属于正确性边界问题。

---

### Finding N19 — 摘要输入重发结算 JSON

#### Trigger
被摘要的消息范围包含 assistant 结算 payload。

#### Current Behavior
`summary_service.dart:183-190` 直接发送 `m.content`；而 assistant 消息以
`narrative\n---JSON---\n{payload}` 形式持久化（`chat_engine.dart:680-681`）。对话历史路径会用
`AdventureResponse.llmHistoryProjection` 剥离 payload（`prompt_compiler.dart:87-89`），摘要路径不会。

#### Expected Behavior
摘要输入必须经 `AdventureResponse.llmHistoryProjection` 投影为纯叙事。

#### Evidence
```text
file: lib/engines/chat_engine_internals/summary_service.dart:183-190
file: lib/engines/chat_engine.dart:680-681
file: lib/models/adventure_response.dart（llmHistoryProjection）
```

#### User / Data Impact
浪费 token；摘要可能描述 JSON 而非剧情，降低摘要质量。

---

### Finding N20 — 摘要窗口与预算裁剪不联动

#### Trigger
`fixedTokens > inputLimitTokens`（大系统 prompt/世界上下文 + 小窗口模型），且已存在摘要。

#### Current Behavior
摘要覆盖 `[0, totalMsgs-12)`；prompt 保留最近 12 条后若仍超预算，会从头部继续裁剪。被裁掉的
`totalMsgs-12 … totalMsgs-12+k-1` 既不在摘要、也不在 history，历史断层不可恢复。

#### Expected Behavior
裁剪只能裁剪已被摘要覆盖的消息；若预算不足以保留摘要边界，必须 fail-closed 或先补摘要，绝不静默
丢弃未覆盖历史。

#### Evidence
```text
file: lib/application/narrative/narrative_context.dart:1131-1155
file: lib/engines/chat_engine_internals/summary_service.dart:26,112-118
既有测试: 摘要与预算裁剪分别测试，未测二者交互
```

#### User / Data Impact
角色扮演连续性断裂（模型看不到被丢弃的历史），且用户无法恢复。

## 5. Root Cause

**Symptom**：大文本请求失败/超限；历史断层；摘要质量下降。

**Root Cause**：上下文的“预算/边界”没有单一 owner：
- 详细世界观的生产实现自建 prompt，绕过了为它准备好的有界策略；
- token 估算与字符计数各自实现，口径不同；
- 摘要边界与 prompt 裁剪各自计算，只有“名义条数”被对齐，降级场景未对齐；
- 摘要输入未复用对话历史的投影规则。

## 6. Required Contract After Remediation

1. 任何进入模型请求的源文本必须有明确字符/token 上界（`DetailedWorldviewContextPolicy` 或等价）。
2. token 估算与中文字符计数只有一套口径；CJK 范围与 emoji 处理一致。
3. 摘要输入只包含纯叙事（不含 `---JSON---` 结算 payload）。
4. prompt 裁剪不得丢弃未被摘要覆盖的历史；无法满足时 fail-closed（明确错误）而非静默丢失。
5. 世界观/角色在对话 prompt 中只注入一次（保持现状；新增断言防止回归）。
6. 不改动对话 JSON 输出格式与既有解析。

## 7. Implementation Plan

### Step 1 — 详细世界观生产路径上界（M13）

```text
file: lib/services/ai_generator_service.dart
symbol: textToDetailedWorldviewMultiTurn (:201), _ensureDetailedWorldviewTarget (:901), _worldviewSupplementPrompt (:1025)
```

1. 在 `textToDetailedWorldviewMultiTurn` 内对 `sourceText` 应用
   `const DetailedWorldviewContextPolicy().briefSource(sourceText)`，用于所有内联点。
2. `_worldviewSupplementPrompt` 同样使用 `briefSource`。
3. `_ensureDetailedWorldviewTarget` 的每轮补充只发送**与当前问题相关**的已完成模块，而不是全量
   `detail` JSON（实现时以现有 detail 结构为准，选择最小必要子集）。
4. 生产路径与 `generateDetailedWorldviewCoordinatorForTesting` 的差异：优先让 ForTesting 方法委托到
   生产实现（或在生产实现中复用同一策略），消除“策略只在测试路径生效”的分叉；ForTesting 若仅测试
   使用，保留但委托。
5. 若某模型 `ModelCapabilities.contextWindow` 小于估算请求，应在调用前失败/收缩（见 Step 5）。

### Step 2 — TokenEstimator 口径统一（N18）

```text
file: lib/utils/token_estimator.dart
symbol: TokenEstimator.estimatedTokens (:10-21)
```

- 改为按 `runes` 遍历（或 `characters` 包，若已是依赖）。
- CJK 判定复用 `ChineseCharacterCounter` 的范围定义，抽出一个共享的“是否为中文/全角字符”判定，
  避免两处范围不一致。
- 更新所有依赖估算结果的行为（预算/裁剪/压缩阈值）并在测试中给出可预期的数值。

> 注意：本 Step 会改变预算行为；必须用测试固定“给定文本 → 估算值”的新期望，并在实现报告中说明
> 与旧行为差异。

### Step 3 — 摘要输入投影（N19）

```text
file: lib/engines/chat_engine_internals/summary_service.dart
symbol: 构造摘要 user content 处 (:183-190)
```
- assistant 消息在进入摘要前经 `AdventureResponse.llmHistoryProjection(m.content)`。
- user 消息保持原文。

### Step 4 — 摘要边界与裁剪联动（N20）

```text
file: lib/application/narrative/narrative_context.dart
symbol: 历史裁剪 (:1131-1155)
file: lib/engines/chat_engine_internals/summary_service.dart
symbol: summarizeEnd 计算 (:112-118)
```

- 抽出单一“历史窗口计算”函数：输入 `(totalMessages, budget, fixedTokens)`，输出
  `(retainedStartIndex, summaryBoundaryIndex)`。
- prompt 使用 `retainedStartIndex` 组装 `recent`；摘要使用 `summaryBoundaryIndex` 作为 `upToIndex`。
- 规则：`summaryBoundaryIndex <= retainedStartIndex`（摘要覆盖所有被移出 prompt 的消息）。
- 若 `fixedTokens` 已超过预算导致 `retainedStartIndex` 必须小于 `summaryBoundaryIndex`，则：
  - 优先触发一次摘要（若可行）；或
  - fail-closed：抛出明确的“上下文超限”错误，不发送请求，不静默裁剪。
- 不得静默制造断层。

### Step 5 — prompt 组成断言与请求上界（TG15 + M13 防线）

- 新增测试断言：对话 prompt 中世界观/角色信息只出现一次（利用 `PromptCompiler` 的 `ContextTrace`
  或对最终 system content 计数关键标记）。
- 对详细世界观生成，断言最终请求文本长度不超过 `ModelCapabilities.contextWindow` 对应的字符上界。

## 8. Design Decisions

### 8.1 M13 复用策略 vs 重写生产 prompt

**选择复用 `DetailedWorldviewContextPolicy`**。理由：策略已存在且有测试语义，重写会引入第二套。**不采用重写。**

### 8.2 N20 用“fail-closed”还是“自动补摘要”

- **方案 A（推荐）**：优先尽量保留；无法覆盖时 fail-closed 并提示。
- 方案 B：同步自动补摘要后再发送。

**选择 A**。理由：自动补摘要是额外的模型调用，会改变请求时序与成本；fail-closed 更可预测。
**不采用 B**（可作为后续增强）。

### 8.3 M13 是否删除 ForTesting 路径

**不删除**（属 R13 cleanup 评估）。本 Phase 让生产与测试共享策略即可。

## 9. Database Impact

```text
No schema change required.
```

不新增表/列，不修改 `schemaVersion`，不修改 migration。回滚为纯代码 revert。
注意：N18 修正会改变“已保存摘要的边界”在新请求中的使用方式，但不改写历史数据。

## 10. Concurrency / Sequence

### 10.1 M13 当前 / 修复后

```text
当前: each of up to 21 requests carries full sourceText (+ growing detail JSON)
修复: each request carries briefSource(sourceText) (+ relevant modules only)
```

### 10.2 N20 当前（断层）

```text
messages: [0 .. N-13 | N-12 .. N-1]        summary covers [0, N-12)
prompt retains [N-12 .. N-1]
if budget short → drop N-12, N-11, ...
   → dropped messages are NOT in summary and NOT in history   ← GAP
```

### 10.3 N20 修复后

```text
summaryBoundary = retainedStart
   → dropped messages are always within summary
if impossible → fail-closed (no request)
```

### 10.4 不变量

```text
不变量1: prompt 保留区间与其前被丢弃区间的并集 ⊆ summary 覆盖区间 ∪ prompt 保留区间，无空洞。
不变量2: 任一模型请求的源文本长度有上界。
不变量3: 摘要输入不含结算 JSON。
不变量4: 世界观/角色在对话 system prompt 中只出现一次。
```

## 11. Files Expected To Change

```text
Production（Expected）:
- lib/services/ai_generator_service.dart
- lib/services/detailed_worldview_context_policy.dart（如需按模型能力）
- lib/utils/token_estimator.dart
- lib/utils/chinese_character_counter.dart（抽出共享判定）
- lib/engines/chat_engine_internals/summary_service.dart
- lib/application/narrative/narrative_context.dart

Production（Possible）:
- lib/models/model_capabilities.dart（模型窗口查询）
- lib/core/config/generation_limits.dart（上界常量）

Tests（Expected，新建）:
- test/unit/token_estimator_parity_test.dart
- test/engines/summary_projection_test.dart
- test/engines/summary_budget_continuity_test.dart
- test/unit/detailed_worldview_context_bound_test.dart
- test/engines/dialogue_prompt_single_injection_test.dart

Tests（Possible，更新）:
- 现有 detailed_generation_and_wizard_test.dart、摘要/上下文测试

Docs:
- docs/post-phase12-remediation/STATUS.md

Forbidden / should not be touched:
- LLM 传输超时/重试（R04）
- 流式协议（R08）
- 对话 JSON 输出格式与解析（AdventureResponse.parse）
- 不改 UI
```

## 12. Test Plan

### TEST R10-01（M13 源文本上界）
```text
Given: 一个超大 sourceText
When:  textToDetailedWorldviewMultiTurn 构造每个阶段请求
Then:  每个请求中的源文本长度 <= policy 上界
       补充轮不重复发送全量源文本
```

### TEST R10-02（N18 估算口径）
```text
Given: emoji、CJK 扩展 A、中文、英文混合文本
When:  TokenEstimator.tokens 与 ChineseCharacterCounter
Then:  两者的“汉字”判定一致；emoji 不双计
       给出固定期望值
```

### TEST R10-03（N19 摘要投影）
```text
Given: assistant 消息含 ---JSON--- payload
When:  构造摘要输入
Then:  输入中不含 payload；只含叙事正文
```

### TEST R10-04（N20 无断层）
```text
Given: 小窗口模型 + 大 fixedTokens + 已存在摘要
When:  组装 prompt
Then:  被移出 prompt 的消息全部在摘要覆盖范围内
```

### TEST R10-05（N20 fail-closed）
```text
Given: 预算不足以在无断层前提下组装
When:  组装 prompt
Then:  抛出明确错误；不发送请求；不静默裁剪
```

### TEST R10-06（TG15 单次注入）
```text
Given: 一个含世界观与角色的冒险
When:  构建对话 system prompt
Then:  世界观标记与角色标记各只出现一次
```

## 13. Mutation / Negative Verification

```text
Mutation 1: 让 textToDetailedWorldviewMultiTurn 直接内联完整 sourceText
→ TEST R10-01 必须 FAIL

Mutation 2: 恢复 TokenEstimator 的 UTF-16 遍历
→ TEST R10-02 必须 FAIL

Mutation 3: 摘要输入直接使用 m.content
→ TEST R10-03 必须 FAIL

Mutation 4: 恢复“保留 12 条后从头部继续裁剪”且不联动摘要
→ TEST R10-04 必须 FAIL

Mutation 5: 让 PromptBuilder 传 includeSetupContext:true
→ TEST R10-06 必须 FAIL
```

## 14. Acceptance Criteria

```text
AC-R10-01 详细世界观生成每个请求的源文本有上界。
AC-R10-02 TokenEstimator 与 ChineseCharacterCounter 口径一致（含 emoji/CJK 扩展）。
AC-R10-03 摘要输入不含结算 JSON。
AC-R10-04 prompt 裁剪不产生未被摘要覆盖的历史断层。
AC-R10-05 预算无法满足时 fail-closed。
AC-R10-06 世界观/角色在对话 prompt 中只注入一次。
AC-R10-07 全量 flutter test 通过。
```

## 15. Required Verification Commands

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test test/unit/token_estimator_parity_test.dart
flutter test test/engines/summary_projection_test.dart
flutter test test/engines/summary_budget_continuity_test.dart
flutter test test/unit/detailed_worldview_context_bound_test.dart
flutter test test/engines/dialogue_prompt_single_injection_test.dart
flutter test
git diff --check
git status --short
```

## 16. Out of Scope

- 不改 LLM 传输层（R04）与流式协议（R08）；
- 不改对话 JSON 输出格式/解析；
- 不实现“自动补摘要”；
- 不删除 ForTesting 方法（R13 评估）；
- 不改 UI。

## 17. Rollback / Failure Safety

- M13 修复后请求变小，最坏情况是模型信息不足（可通过调整 policy 上界缓解），不会损坏数据。
- N20 fail-closed 会让极端配置下的请求被拒绝并提示，而不是静默丢历史；这是可接受的降级。
- TokenEstimator 行为变化可能影响保留条数，属一致性修正；用测试固定新行为。
- 回滚为纯代码 revert；无 schema 改动。

## 18. OPEN QUESTION

```text
Q1: `_ensureDetailedWorldviewTarget` 的“相关模块”最小子集如何界定？需要检查 detail JSON 结构与
    prompt 依赖，才能确定哪些模块必须随每轮发送。
Q2: N20 的“历史窗口计算函数”放在 narrative_context 还是独立 helper？需确认调用方
    （PromptBuilder 与 SummaryService）的依赖方向，避免循环依赖。
Q3: TokenEstimator 是否可改用已安装的 `characters` 包（若已是依赖）；若不是，按 rune 实现。
```

## 19. Handoff Notes

- R04/R08 完成后本 Phase 才涉及 `ai_generator_service.dart` 的 prompt 构造（非传输）。若并行，需协调
  文件冲突。
- R13 可评估 `generateDetailedWorldviewCoordinatorForTesting` 的取舍（本 Phase 不删）。
