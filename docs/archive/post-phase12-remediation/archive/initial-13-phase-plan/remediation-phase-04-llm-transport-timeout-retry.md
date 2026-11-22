# Remediation Phase 04 — LLM Transport Timeout & Retry Policy

> **Root Cause**: RC-04
> **Findings**: M2, M3 (MAJOR), TG13
> **Depends On**: None
> **Document status**: PLANNED

---

## 1. Purpose

LLM 传输链存在两个相互放大的问题：

1. **没有任何超时**（M2）。`LLMService` 的 `client.send(...)` 与 `await for` 流读取都没有
   `.timeout(...)`；供应商或代理挂起时等待永不结束，`GenerationRequestScheduler` 的 permit 只在
   `finally` 释放，于是全局并发队列被永久占满，后续所有生成排队不动。视觉/图片调用
   （`AiGeneratorService._callVision`）还完全没有 `taskHandle`，用户无法取消。
2. **重试层数层层叠乘**（M3）。`LLMService.sendMessageStreamDetailedTyped` 内有一层
   `RetryManager.withRetry`，`AiGeneratorService._callText`/`_callMessages` 又包一层
   `RetryManager.withRetry`，再被外层内容循环（最多 5 次）放大，单次逻辑调用最多可达 45 次 HTTP。

本 Phase 修复的 contract 是：**“每次逻辑 LLM 调用只有一个可界定的 transport 预算和一个 content
预算；传输层必须有超时，且超时释放调度许可。”**

## 2. Audit Findings Covered

```text
Primary:
- M2   传输层无超时；挂起请求永久占用 scheduler permit；vision 调用不可取消
- M3   重试在 LLMService 与 AiGeneratorService 两层叠加并被外层内容循环再乘

Test gaps:
- TG13 无总 HTTP 尝试次数、无挂起流超时/许可耗尽测试
```

## 3. Current Production Architecture

```text
所有 chat 调用
  → LLMService.sendMessageStreamDetailed / sendMessageStreamTyped / sendMessageStreamDetailedTyped
       (lib/services/llm_service.dart:194-241)
       // :220-240 wrap in RetryManager.withRetry(shouldRetry: LLMStreamRetryPolicy)
       → GenerationRequestScheduler.shared.schedule(providerId, request)   (:222)
            (lib/services/generation_request_scheduler.dart:55-78)
            queue.acquire() + _globalQueue.acquire()   // :65-66，Completer，无超时
            finally: _globalQueue.release(); queue.release();   // :74-77
       → _doSendMessageStreamDetailed                                  (:243)
            final client = http.Client();                              (:361)
            await client.send(request)                                 (:368)  ← 无超时
            await for (chunk in streamedResponse.stream ... LineSplitter())  (:397) ← 无超时
              ...
              onChunk(content)                                         (:444)  ← 见 R08
  → AiGeneratorService._callText / _callMessages
       (lib/services/ai_generator_service.dart:2295-2340 / 2342-2395)
       // 又包一层 RetryManager.withRetry(maximumAttempts: defaultMaximumTransportAttempts=3)
  → 外层内容循环
       adventure_ai_use_case.dart: generateAdventurePreset for(attempt<=5)  (:28)
                                    generateResourceCharacter for(attempt<=3) (:202)
       summary_service.dart:181-223  for(attempt<3)

RetryBudget (lib/services/api_error.dart:127-144): structuredJson = {transportAttempts:2, contentStageAttempts:3}
RetryManager.maximumAttempts = 3 (api_error.dart:154)
ApiError.fromException 已能把 TimeoutException 映射为 ApiError.networkTimeout (api_error.dart:77-94)
```

## 4. Exact Bugs

### Finding M2 — 无超时 + 挂起请求永久占用调度许可 + vision 不可取消

#### Trigger
供应商/代理接受 TCP 连接后不返回数据、也不关闭连接（黑洞/半开连接）。

#### Current Behavior
- `client.send` / `await for` 永不完成；`schedule` 的 `finally` 不执行，`_globalQueue` 与 provider
  queue 的 permit 永不释放。全局并发上限 `maximumConcurrentModelRequestsGlobally()`（=2）被占满后，
  后续所有生成请求在 `queue.acquire()` 的 `Completer` 上无限等待。
- `_callVision`（`ai_generator_service.dart:2192`）调用 `sendMessageStreamTyped` **不传**
  `taskHandle`，因此图片相关问题无法被用户取消。
- 对照：`web_search_service` 与 `SemanticEmbeddingService` 都有 `.timeout(...)`，只有 chat 传输没有。

#### Expected Behavior
- 传输必须有可界定的超时（连接/响应头超时 + 流空闲超时），超时映射为
  `ApiError.networkTimeout`（可重试），并**必然释放** scheduler permit。
- 调度 acquire 也要有超时，超时不得遗留 waiter。
- vision 调用应可取消（至少在有 handle 时透传）。

#### Evidence
```text
file:    lib/services/llm_service.dart
symbol:  client.send (:368/:537); await for stream (:397/:595); 无 timeout
file:    lib/services/generation_request_scheduler.dart
symbol:  schedule (:55-78); _ProviderRequestQueue.acquire (:104-109)
file:    lib/services/ai_generator_service.dart
symbol:  _callVision (:2192-2218) 未传 taskHandle
状态:    挂起请求永久占用 permit
既有测试: 测试用会终止的 fake stream，无挂起/超时/许可耗尽测试
```

#### User / Data Impact
网络异常后应用“卡在生成中”，所有后续模型请求不可用，只能重启；vision 任务无法取消。

---

### Finding M3 — 重试层数叠乘

#### Trigger
持续可重试错误（5xx / 429 / 超时）。

#### Current Behavior
`sendMessageStreamDetailedTyped` 的 `RetryManager.withRetry`（默认 3）× `_callText` 的
`RetryManager.withRetry`（3）× 外层内容循环（最多 5）= 最多 45 次 HTTP；每次都有 `Future.delayed`
退避，一次用户动作可持续数分钟并产生大量计费请求。外层循环不检查 `receivedAnyDelta`，对 onChunk
消费者会从头重流。

#### Expected Behavior
单一 transport 预算 + 单一 content 预算；传输错误不在 content 层重复重试；内容错误不在 transport
层重试（现有 `TransportRetryPolicy` 已区分，但预算层数不清）。

#### Evidence
```text
file: lib/services/llm_service.dart:220-240
file: lib/services/ai_generator_service.dart:2295-2340 (_callText), 2342-2395 (_callMessages),
      57 (defaultMaximumTransportAttempts=3)
file: lib/application/adventure/adventure_ai_use_case.dart:28 (5), :202 (3)
file: lib/engines/chat_engine_internals/summary_service.dart:181-223 (3)
file: lib/services/api_error.dart:127-144 (RetryBudget), :147-200 (RetryManager)
既有测试: 只断言“最终成功/抛错”，从不计数 HTTP 次数
```

#### User / Data Impact
成本与延迟放大；用户误以为“卡死”；重试风暴风险。

## 5. Root Cause

**Symptom**：网络挂起导致全局生成不可用；失败请求重试数十次。

**Root Cause**：
- 传输层依赖 OS 默认 socket 行为，未定义“多久算超时”；
- 重试策略在引入 `LLMService` 内层 `RetryManager` 后，没有清理调用方（`AiGeneratorService`）
  历史上已有的重试包裹，形成“同一失败被两层甚至三层各自重试”的叠加。

这是“传输语义没有单一 owner”的系统性问题，M2/M3 同属一个 Phase。

## 6. Required Contract After Remediation

1. 每个 `LLMService` chat 请求都有：
   - **连接/响应头超时**（`client.send`）；
   - **流空闲超时**（相邻 SSE 事件之间的最大间隔），到期抛超时；
   - 超时统一映射 `ApiError.networkTimeout`（`shouldRetry` 为 true）。
2. `GenerationRequestScheduler` 的 acquire 有超时；超时后**必须**从 waiter 列表移除自己，不得遗留
   幽灵 permit。
3. 每次逻辑调用只有一个 transport 重试预算，来源唯一（`RetryBudget`）。
4. `AiGeneratorService._callText` / `_callMessages` 不再叠加第二层 transport 重试。
5. 外层内容循环只在**内容/校验失败**时重试；对已耗尽 transport 预算的传输错误不得再次重试。
6. 取消（`GenerationCancelledException`）永不重试（既有行为保持）。
7. 部分流已产出（`receivedAnyDelta`）后不得重试（既有 `LLMStreamRetryPolicy` 行为保持）。
8. vision 调用在有 `taskHandle` 时必须可取消。

## 7. Implementation Plan

### Step 1 — 超时配置

```text
file: lib/services/llm_service.dart
symbol: class LLMConfig (:93-105)
target: 新增可选字段
        final Duration connectionTimeout;   // 默认 30s
        final Duration streamIdleTimeout;   // 默认 90s
        final Duration acquireTimeout;      // 默认 30s
```

使用 `const` 可选具名参数 + 默认值，保持所有既有构造点（`LLMConfig(provider:, apiKey:, baseUrl:, model:)`）
兼容。测试通过构造短超时注入。

### Step 2 — `client.send` 与流读取加超时

```text
file: lib/services/llm_service.dart
symbol: _doSendMessageStreamDetailed (:243-...) 与 _doSendAnthropicStreamDetailed (:493-...)
```

- `final streamedResponse = await client.send(request).timeout(config.connectionTimeout);`
- 对 SSE 流加空闲超时：

  ```dart
  await for (final chunk in streamedResponse.stream
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .timeout(config.streamIdleTimeout)) { ... }
  ```

  `Stream.timeout` 的语义是“相邻事件间隔超时”，适合 SSE；到期抛 `TimeoutException`，由既有
  `catch (e) { ... throw ApiError.fromException(e); }`（`:450-453`）映射为 `networkTimeout`。
- `client` 必须在 `finally` 中 `close()`（现状需确认；若未关闭，一并修复，避免连接泄漏）。

### Step 3 — 调度 acquire 超时（可取消 waiter）

```text
file: lib/services/generation_request_scheduler.dart
symbol: GenerationRequestScheduler.schedule (:55-78), _ProviderRequestQueue.acquire (:104-109), release (:111-114)
```

- 给 `_ProviderRequestQueue` 增加 `Future<void> acquire({Duration? timeout})`：
  - 创建 completer 并加入 `_waiters`；
  - 若提供 timeout，`await completer.future.timeout(timeout, onTimeout: () { _waiters.remove(completer); throw ApiError.networkTimeout(); })`；
  - 保证被移除后 `_drain()` 不会再把 permit 分配给已超时的 waiter。
- `schedule` 用 `config.acquireTimeout`（或 scheduler 上的常量）调用两次 acquire（provider + global）。
- 必须保证：超时的 waiter 既不占用也不消耗 permit；`release` 只对真正获得 permit 的调用生效。

### Step 4 — 收敛重试层级

```text
file: lib/services/ai_generator_service.dart
symbol: _callText (:2295-2340), _callMessages (:2342-2395), defaultMaximumTransportAttempts (:57)
```

- **删除** `_callText`/`_callMessages` 中包裹 `_llm.sendMessageStreamDetailed` 的
  `RetryManager.withRetry`（它们目前与 `LLMService` 的内层重试重复）。
- 保留 `_resolveContent`（内容/截断校验）。
- 传输重试预算统一来自 `LLMService`。

```text
file: lib/services/api_error.dart
symbol: RetryBudget (:127-144)
```

- 增加单一 transport 默认预算常量（例如 `static const int defaultTransportAttempts = 3;`），
  `LLMService` 引用它（当前用 `RetryManager` 默认 3）。

```text
file: lib/services/llm_service.dart
symbol: sendMessageStreamDetailedTyped (:212-241)
```

- 用 `RetryBudget.defaultTransportAttempts` 显式传入 `RetryManager.withRetry`，使预算来源唯一。

### Step 5 — 内容循环不再重复传输重试

```text
file: lib/application/adventure/adventure_ai_use_case.dart
symbol: generateAdventurePreset (:28), generateResourceCharacter (:202)
file: lib/engines/chat_engine_internals/summary_service.dart
symbol: 时间线摘要 for 循环 (:181-223)
```

为所有外层内容循环引入共享辅助（放在合适现有工具处，避免新建重复抽象）：

```text
shouldRetryContentLayer(Object error):
  if (error is GenerationCancelledException) return false;
  if (TransportRetryPolicy.shouldRetry(error)) return false; // 传输层已耗尽，内容层不再重试
  return true; // 内容/校验错误由内容预算处理
```

- 循环体在 `catch (e)` 中：`if (attempt < max && shouldRetryContentLayer(e)) { delay } else rethrow/break;`
- 这样最坏尝试数上界为 `transportAttempts + (contentStageAttempts - 1)`（单阶段），不再是乘法。

### Step 6 — vision 可取消

```text
file: lib/services/ai_generator_service.dart
symbol: _callVision (:2192), imageToWorldview (:73), imageToCharacterCard (:80)
```

- 为上述方法增加可选 `GenerationTaskHandle? taskHandle` 参数并透传到 `sendMessageStreamTyped`。
- 调用方（UI/controller）有 handle 时传入；无 handle 时保持 `null`（超时仍生效）。
- 若某调用方无法提供 handle（超出本 Phase 范围），至少保证超时生效，并在文档标注该调用的取消
  能力限制。

## 8. Design Decisions

### 8.1 超时用“总时长”还是“空闲间隔”

- **方案 A（推荐）**：连接/响应头用总超时，流读取用**空闲间隔超时**（`Stream.timeout`）。
- 方案 B：对整个流用总超时。

**选择 A**。理由：流式生成本身可以合法持续数分钟，总超时会误杀正常长响应；空闲间隔超时精确表达
“多久没有新数据算挂起”。**不采用 B。**

### 8.2 传输重试留在哪一层

- **方案 A（推荐）**：只留在 `LLMService`（唯一 transport owner）。
- 方案 B：只留在 `AiGeneratorService`（调用方）。

**选择 A**。理由：`LLMService` 是所有 chat 调用的必经之处（对话也直接调它），把 transport 重试放在
最底层可保证所有调用共享同一预算；`AiGeneratorService` 的外层包裹是历史遗留的重复。
**不采用 B。**

### 8.3 内容循环遇到传输错误是否重试

**选择不重试**（见 Step 5）。理由：传输层已按预算重试；内容层再重试即为乘法。**不采用“内容层再
重试传输错误”。**

### 8.4 OPEN DESIGN QUESTION

```text
Q1: 流空闲超时的合理默认值无法从代码推断（取决于供应商行为）。本 Phase 建议 90s，
    但需在实现时选择一个可配置默认，并记录依据。
    需要的证据：现有 web_search(15s) / embedding(5s) 超时、典型流式响应节奏、
    generation_request_scheduler 的 rate-limit 恢复窗口。
Q2: client.close() 当前是否在 finally 中执行？需要检查 llm_service.dart 三个 http.Client()
    构造点（:361/:529/:680）的关闭路径，避免修复超时后新增连接泄漏。
```

## 9. Database Impact

```text
No schema change required.
```

不新增表/列，不修改 `schemaVersion`，不修改 migration。回滚为纯代码 revert。

## 10. Concurrency / Sequence

### 10.1 当前（挂起）

```text
schedule: acquire provider + global permits
  ↓
client.send (hangs forever)
  ↓
(no timeout) permits NEVER released
  ↓
all later requests wait on acquire() forever
```

### 10.2 修复后（超时释放）

```text
schedule: acquire (with acquireTimeout)
  ↓
client.send .timeout(connectionTimeout)
  ↓
stream .timeout(streamIdleTimeout)
  ↓
TimeoutException → ApiError.networkTimeout
  ↓
finally: release provider + global permits
  ↓
next request proceeds
```

### 10.3 acquire 超时（无幽灵 permit）

```text
waiter W added
  ↓
timeout(acquireTimeout) fires
  ↓
W removed from _waiters ; throw networkTimeout
  ↓
_drain() must NOT hand a permit to W
```

### 10.4 重试预算（修复后）

```text
一次逻辑调用:
  Transport: 最多 T 次（LLMService，唯一）
  Content:   最多 C 次（阶段循环，仅内容错误）
  上界 ≈ T + (C - 1)，而非 T × C × outer
```

## 11. Files Expected To Change

```text
Production（Expected）:
- lib/services/llm_service.dart
- lib/services/generation_request_scheduler.dart
- lib/services/ai_generator_service.dart
- lib/services/api_error.dart
- lib/application/adventure/adventure_ai_use_case.dart
- lib/engines/chat_engine_internals/summary_service.dart

Production（Possible）:
- 调用 _callVision 的上层（若透传 taskHandle）
- 其他直接包裹 LLMService 重试的调用点（实现前用 rg 全面搜索 RetryManager.withRetry）

Tests（Expected，新建）:
- test/services/llm_transport_timeout_test.dart
- test/services/generation_request_scheduler_timeout_test.dart
- test/services/llm_retry_budget_test.dart

Tests（Possible，更新）:
- 现有 LLMService / AiGeneratorService 测试

Docs:
- docs/post-phase12-remediation/STATUS.md

Forbidden / should not be touched:
- onChunk 异常传播（R08，避免与 R04 重叠；R04 只改超时/重试，不动 :446 的 catch 语义）
- 流式会话生命周期（R01）
- 内容写入 CAS（R03）
```

## 12. Test Plan

### TEST R04-01（连接超时释放 permit）
```text
Given: 注入一个 send() 永不返回的 fake http.Client；connectionTimeout=短
When:  发起生成请求
Then:  抛出 ApiError.networkTimeout
       scheduler.activeRequestsGlobally == 0（permit 已释放）
```

### TEST R04-02（流空闲超时）
```text
Given: fake 流先发 1 个事件后长时间无事件；streamIdleTimeout=短
When:  消费流
Then:  抛 ApiError.networkTimeout；permit 释放
```

### TEST R04-03（acquire 超时无幽灵 permit）
```text
Given: 已占满全局 permit；acquireTimeout=短
When:  新请求 acquire
Then:  抛 networkTimeout
       原持有时释放后，新一轮 acquire 能正常获得 permit（无幽灵占用）
```

### TEST R04-04（重试次数上界）
```text
Given: 一个持续返回 5xx 的 fake transport；计数 client.send 调用
When:  走 generateResourceCharacter（内容循环 3）路径
Then:  client.send 总次数 <= transportAttempts + (contentStageAttempts - 1)
       不为 3×3×3=27
```

### TEST R04-05（取消不重试）
```text
Given: 携带 taskHandle 的请求，在第一次尝试中触发 cancel
When:  传输抛 GenerationCancelledException
Then:  不重试；client.send 只调用 1 次
```

### TEST R04-06（部分流不重试）
```text
Given: 第一个 chunk 已产出后连接中断
When:  传输抛错
Then:  不重试（LLMStreamRetryPolicy 行为保持）
```

## 13. Mutation / Negative Verification

```text
Mutation 1: 移除 client.send 的 .timeout
→ TEST R04-01 必须 FAIL

Mutation 2: 移除流的 .timeout
→ TEST R04-02 必须 FAIL

Mutation 3: 在 acquire 超时分支不移除 waiter
→ TEST R04-03 必须 FAIL

Mutation 4: 恢复 _callText 里的 RetryManager.withRetry
→ TEST R04-04 必须 FAIL

Mutation 5: 让内容循环对传输错误也重试
→ TEST R04-04 必须 FAIL
```

## 14. Acceptance Criteria

```text
AC-R04-01 挂起的 send/流在超时后抛 ApiError.networkTimeout 并释放所有 permit。
AC-R04-02 scheduler acquire 超时不遗留 waiter。
AC-R04-03 单次逻辑调用 HTTP 次数有明确上界（非乘法）。
AC-R04-04 取消与部分流已产出场景不重试。
AC-R04-05 既有 LLM 功能（对话、生成、摘要）测试全部通过。
AC-R04-06 全量 flutter test 通过。
```

## 15. Required Verification Commands

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test test/services/llm_transport_timeout_test.dart
flutter test test/services/generation_request_scheduler_timeout_test.dart
flutter test test/services/llm_retry_budget_test.dart
flutter test
git diff --check
git status --short
```

## 16. Out of Scope

- 不改 `onChunk` 的异常吞掉语义（R08）；
- 不改流式会话生命周期（R01）；
- 不改内容写入 CAS（R03）；
- 不引入新的 LLM 供应商或协议；
- 不改 UI。

## 17. Rollback / Failure Safety

- 修复后，任何超时/失败都必须释放 permit；最坏情况是请求失败并可重试，而不是永久挂起。
- 若超时值设置过短导致正常长响应被中断：属于配置问题，可通过 `LLMConfig` 调整；不得用删除超时
  规避。
- 回滚为纯代码 revert。

## 18. Handoff Notes

- R08 必须在 R04 完成后进行，以避免同时修改 `llm_service.dart` 的 try/catch 结构。
- R08 的“消费者异常必须传播”不得重新引入重试放大：消费者异常属于内容错误，由内容层处理。
