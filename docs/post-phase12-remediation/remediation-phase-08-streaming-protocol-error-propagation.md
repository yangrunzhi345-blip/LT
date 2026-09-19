# Remediation Phase 08 — Streaming Protocol Integrity & Consumer Error Propagation

> **Root Cause**: RC-08
> **Findings**: M10, N15 (MAJOR/MINOR), TG1
> **Depends On**: R01, R04
> **Document status**: BLOCKED（等待 R01、R04 ACCEPTED）

---

## 1. Purpose

流式资源生成协议存在三个相互关联的问题：

1. **消费者异常被传输层吞掉**（M10）：`LLMService` 在解析 SSE 事件的 `try` 内调用 `onChunk(content)`，
   其 `catch (_) { malformedEventCount++; }` 会把 `GenerationPatchParser` 抛出的解析/校验异常当作“坏
   SSE 事件”吞掉，导致 coordinator 的类型化失败路径永不触发、错误被掩埋、流继续消费 token。
2. **两套协议漂移**（N15）：非流式分支用 `PartGenerationParser`（要求单个 `content` 对象），而它自己的
   prompt 要求 NDJSON patch 行；生产走流式分支掩盖了该漂移，而测试恰好走非流式分支。
3. **流式分支完全无测试**（TG1）：全仓没有任何 `PartGenerationStreamingGateway` 的 fake。

本 Phase 修复的 contract 是：**“解析/校验失败必须原样传播到 coordinator 的 typed handler，并被上报为
失败；生产与测试使用同一套协议与同一条调用路径。”**

## 2. Audit Findings Covered

```text
Primary:
- M10   流式消费者异常在传输层被吞，typed 失败路径不触发
- N15   非流式 parser 与自身 prompt 协议不一致（生产/测试路径分叉）

Related（流式健壮性，来自流式审计）:
- streaming parser 不容忍 Markdown code fence（parsePatchLine 直接 jsonDecode）

Test gaps:
- TG1   无 PartGenerationStreamingGateway fake，流式分支未被任何测试覆盖
```

## 3. Current Production Architecture

```text
PartGenerationCoordinator._generateSinglePart                     (part_generation_coordinator.dart)
  构造: gateway is PartGenerationStreamingGateway ? _streamingGateway : null   (:146-148)
  生产: AiGeneratorLlmGateway implements PartGenerationStreamingGateway          (ai_generator_llm_gateway.dart:13)
  if (_streamingGateway != null) {                                 (:524)
      void consume(String chunk) { ... GenerationPatchParser.parsePatchLine ... accumulator.applyPatch }  (:527-549)
      try {
        await _streamingGateway!.streamPartGeneration(..., onChunk: consume)   (:552-558)
        ...
        response = accumulator.toResponse()                        (:576)
      } catch (e) {
        if (e is PartGenerationParseException || e is GenerationPatchParseException
            || e is PatchSequenceGapException || e is PatchCursorMismatchException) {
          await callbacks?.onValidationStarted?.call(...)
          await callbacks?.onValidationFailed?.call(...)
        }
        rethrow;                                                    (:577-599)
      }
  } else {                                                          (:600)
      raw = await _completer(...)
      response = PartGenerationParser.parse(raw)                    (:608)  ← 与 prompt 协议不一致
      ...
  }

传输层:
  AiGeneratorLlmGateway.streamPartGeneration → LLMService.sendMessageStream
  LLMService._doSendMessageStreamDetailed:
      try {
        await for (chunk in ...) {
          if (!chunk.startsWith('data: ')) continue
          ...
          try {
            json = jsonDecode(data) ...                            (解码 provider 事件)
            content = delta['content']
            if (content != null && ...) { buffer.write(content); onChunk(content); }   (:443-444)
          } catch (_) { malformedEventCount++; }                   (:446)  ← 吞掉消费者异常
        }
      } catch (e) {
        if (e is GenerationCancelledException) rethrow;
        throw ApiError.fromException(e);                           (:450-453)
      }
```

## 4. Exact Bugs

### Finding M10 — 消费者异常在传输层被吞

#### Trigger
消费流式 NDJSON 时 `onChunk`（`consume`）抛出 `GenerationPatchParseException` /
`PatchSequenceGapException` / `PatchCursorMismatchException` / `StateError` 等（畸形 JSON、未知字段/op、
缺失 ID、重复 `start_part`、`complete_part` 后 append、cursor 不匹配、超长）。

#### Current Behavior
`onChunk(content)` 位于 provider 事件解码的 `try` 内，其异常被 `:446 catch (_)` 吞掉并计入
`malformedEventCount`。因此：
- coordinator `:577-599` 的类型化处理（`onValidationStarted` + `onValidationFailed`）永不执行；
- 该 chunk 之后的 for 循环被中断，`accumulator` 的 sequence 未推进，后续所有更高 sequence 的 patch
  触发 `PatchSequenceGapException` 并同样被吞；
- 流继续被消费；通常最终在 `accumulator.toResponse()`（`part_generation_coordinator.dart:576`）抛
  与真实原因无关的 `StateError('当前 Part 尚未收到 complete_part 结束标记')`。

**注意**：这不产生无效数据（`toResponse` 要求 `complete_part`，`PartGenerationValidator` 仍会拒绝空/
超长），但错误被完全掩埋，违反 `AGENTS.md` 的禁止吞异常要求。

#### Expected Behavior
消费者抛出的异常必须**原样**传播到 coordinator，触发其 typed 失败路径；传输层只吸收 provider 事件
解码错误（如非法 JSON 行 / 非预期结构）。

#### Evidence
```text
file: lib/services/llm_service.dart:443-448（onChunk 位于 try 内），:450-453（外层 catch 会把非取消
      异常重新包成 ApiError）
file: lib/application/resources/part_generation_coordinator.dart:524-599
既有测试: 无 PartGenerationStreamingGateway fake（TG1），流式分支未被执行
```

#### User / Data Impact
生成失败时用户看到含糊的“未收到 complete_part”错误；失败原因不可诊断；浪费 token；错误上报缺失。

---

### Finding N15 — 非流式 parser 与 prompt 协议漂移

#### Trigger
任何实现了 `LlmGateway` 但未实现 `PartGenerationStreamingGateway` 的适配器（或测试注入 `completer`）。

#### Current Behavior
该分支用 `PartGenerationParser.parse(raw)`，其允许字段集要求单个对象含 `content`
（`part_generation_parser.dart:29-45`），而 `part_generation_prompt_builder.dart:21-31` 要求 NDJSON patch
行（`op`/`sequence`/`cursor`/`text_delta`）。两者不可能同时满足。

#### Expected Behavior
两条分支使用同一协议（NDJSON patch），或删除非流式分支并要求 streaming gateway。

#### Evidence
```text
file: lib/application/resources/part_generation_parser.dart:29-45, 57
file: lib/application/resources/part_generation_prompt_builder.dart:21-31
file: lib/application/resources/part_generation_coordinator.dart:600-620
既有测试: part_generation_parser_test.dart / coordinator 测试走非流式 content 对象
```

#### User / Data Impact
一旦非流式路径在生产被使用（新适配器/回退），生成必然解析失败；测试因此无法代表生产。

---

### Related — 流式 parser 不容忍 Markdown fence

`GenerationPatchParser.parsePatchLine`（`generation_patch_parser.dart:79-101`）直接 `jsonDecode`，不接受
``` ```json ``` 包裹；而非流式 `PartGenerationParser._extractJsonPayload` 会剥离 fence。模型偶发输出
fence 时流式路径失败（当前因 M10 被吞）。属于同一“流式协议健壮性”边界，随本 Phase 一并处理。

## 5. Root Cause

**Symptom**：流式生成失败被误报为“未收到 complete_part”；测试全绿但流式路径从未运行。

**Root Cause**：传输层的 `try/catch` 边界画错——把“调用消费者回调”放进了“解码 provider 事件”的
try 内，使两种性质完全不同的错误（provider 噪声 vs 应用解析失败）共用同一个 `catch (_)`。同时
coordinator 为“非流式回退”保留了一套与 prompt 不一致的第二协议，导致生产路径与测试路径不同。

这是“协议与错误传播边界未统一”的系统性问题。

## 6. Required Contract After Remediation

1. provider 事件**解码**错误（非法 JSON 行、非预期事件结构）可被计数并跳过，不得中断。
2. 消费者回调（`onChunk`）抛出的异常**必须原样传播**（不重新分类、不包装成 `ApiError`），并停止继续
   读取流。
3. coordinator 必须能捕获并上报这些异常（`onValidationFailed`），且**绝不写入无效内容**（保持
   `toResponse` 与 `PartGenerationValidator` 的 fail-closed 行为）。
4. 流式与非流式分支必须共享同一协议（NDJSON patch）与同一解析器。
5. 流式分支必须被至少一个使用 fake `PartGenerationStreamingGateway` 的测试覆盖，且该 fake 的
   chunk 切分方式必须模拟真实分片（跨 chunk 断行、末尾无换行、空 chunk、单大 chunk）。

## 7. Implementation Plan

### Step 1 — 修正 `onChunk` 的 try 边界（M10）

```text
file: lib/services/llm_service.dart
symbol: _doSendMessageStreamDetailed (:243-...), _doSendAnthropicStreamDetailed (:493-...)
```

将消费者回调移出 provider 解码 `try`，并区分两种错误：

```dart
Object? consumerError;
StackTrace? consumerStack;

await for (final chunk in streamed) {
  ...
  if (!chunk.startsWith('data: ')) continue;
  final data = chunk.substring(6);
  if (data == '[DONE]') { responseCompleted = true; break; }

  String? content;
  try {
    final json = jsonDecode(data) as Map<String, dynamic>;
    ... // usage / finish_reason / reasoning
    content = (json['choices'] as List?)?.isNotEmpty == true
        ? (json['choices'][0]['delta']?['content'] as String?) : null;
  } catch (_) {
    malformedEventCount++;
    continue;                    // provider 噪声：跳过本事件
  }

  if (content != null && content.isNotEmpty && taskHandle?.isCancelled != true) {
    buffer.write(content);
    try {
      onChunk(content);          // 消费者异常必须传播
    } catch (e, st) {
      consumerError = e; consumerStack = st;
      break;                     // 停止读取；不下发更多 chunk
    }
  }
}
if (consumerError != null) {
  Error.throwWithStackTrace(consumerError, consumerStack!);
}
```

要点：
- 消费者异常在 `await for` 之外重新抛出，因此不会被 `:450-453` 的 `catch` 包装成 `ApiError`。
- `break` 会让 `await for` 取消订阅（R04 的 `.timeout` 包装同样随之取消）。
- 保留 `malformedEventCount` 仅用于 provider 解码噪声。
- Anthropic 分支同样处理（虽当前不可达，但保持一致，避免未来启用时行为分裂）。

### Step 2 — 统一非流式分支协议（N15）

```text
file: lib/application/resources/part_generation_coordinator.dart
symbol: 非流式分支 (:600-620)
```

将 `PartGenerationParser.parse(rawCompletion)` 替换为与流式一致的 NDJSON 处理：

```dart
final raw = await _completer(...);
final patches = GenerationPatchParser.parseNdjson(raw);   // generation_patch_parser.dart:222
for (final patch in patches) {
  accumulator.applyPatch(patch);
  await callbacks?.onPatchReceived?.call(...);
}
response = accumulator.toResponse();
```

- 异常处理与流式分支共享同一 catch（把两个分支的 catch 合并为一个，匹配
  `GenerationPatchParseException | PatchSequenceGapException | PatchCursorMismatchException`）。
- `GenerationPatchParser.parseNdjson` 已存在（`:222`），复用，不新增解析器。

> 备选方案见 §8.2。无论选择哪种，都必须让生产路径与测试路径一致。

### Step 3 — 流式 parser 容忍 fence（Related）

```text
file: lib/application/resources/generation_patch_parser.dart
symbol: parsePatchLine (:79-101)
```

在 `jsonDecode` 前剥离包裹行：
- 若 `trimmed` 以 ```` ``` ```` 开头，去掉 fence 行（```json / ```）；若以 ```` ``` ```` 结尾，去掉。
- 对 `parseNdjson`（`:222`）同样过滤 fence 行与空行。

保持严格字段白名单（`_allowedPatchKeys`）不变；fence 只影响 JSON 提取，不放松校验。

### Step 4 — 流式测试 fake（TG1）

新增测试复用 `test/helpers/` 现有夹具模式，实现 `PartGenerationStreamingGateway`：

```text
test/helpers/streaming_part_generation_fakes.dart（或复用现有 helper 追加）
  FakePartGenerationStreamingGateway:
    - 可配置 chunk 序列
    - 支持：跨 chunk 断行、末尾无换行、空 chunk、单大 chunk、注入异常
```

- 覆盖正常路径与所有失败类型（见 §12）。
- 使用 `PartGenerationCoordinator(gateway: fakeStreamingGateway, ...)`（生产形态），而不再依赖
  `completer` 的 content 对象。

## 8. Design Decisions

### 8.1 M10 用“传播原始异常”还是“转换为统一领域错误”

- **方案 A（推荐）**：原样传播消费者异常（`Error.throwWithStackTrace`）。
- 方案 B：在传输层把消费者异常包装为统一错误类型。

**选择 A**。理由：coordinator 的 catch 依赖具体异常类型（`GenerationPatchParseException` 等）触发
`onValidationFailed`；包装会破坏该契约。传输层不应知道上层的解析语义。**不采用 B。**

### 8.2 N15 用“统一 NDJSON”还是“删除非流式分支”

- **方案 A（推荐）**：两条分支统一使用 `GenerationPatchParser`（NDJSON）。
- 方案 B：删除非流式分支，强制 streaming gateway。

**选择 A**。理由：保留对自定义 gateway 的兼容；改动集中在 coordinator；不删除公共 API（删除属
Phase 13 cleanup 的候选，需独立复核）。**不采用 B**（但若独立审核认为非流式分支无任何合法消费者，
可在 R13 评估删除）。

### 8.3 fence 容忍

**选择在 parser 层容忍**。理由：模型不稳定性是现实；非流式路径已有该容错，统一比让 prompt 承担全部
责任更稳。**不采用“只改 prompt”。**

## 9. Database Impact

```text
No schema change required.
```

不新增表/列，不修改 `schemaVersion`，不修改 migration。回滚为纯代码 revert。

## 10. Concurrency / Sequence

### 10.1 当前（异常被吞）

```text
stream chunks
  ↓
onChunk → GenerationPatchParser throws
  ↓
llm_service catch (_) { malformedEventCount++ }   ← 吞掉
  ↓
stream continues; later toResponse() throws generic StateError
coordinator typed handler NEVER runs
```

### 10.2 修复后（异常传播）

```text
stream chunks
  ↓
onChunk throws
  ↓
capture consumerError; break;
  ↓
Error.throwWithStackTrace(consumerError)   (跳过 ApiError 包装)
  ↓
coordinator catch matches type
  → onValidationStarted + onValidationFailed
  → rethrow → attempt marked failed
  ↓
no invalid content committed
```

### 10.3 不变量

```text
不变量1: onChunk 抛出的异常类型在 coordinator 处保持不变。
不变量2: 解析失败后不再继续消费流，也不提交内容。
不变量3: provider 事件噪声（非法 JSON 行）不触发失败。
不变量4: 流式与非流式分支对同一 NDJSON 输入产生相同 accumulator 结果。
```

## 11. Files Expected To Change

```text
Production（Expected）:
- lib/services/llm_service.dart                                （Step 1）
- lib/application/resources/part_generation_coordinator.dart    （Step 2）
- lib/application/resources/generation_patch_parser.dart        （Step 3）

Tests（Expected，新建）:
- test/helpers/streaming_part_generation_fakes.dart
- test/application/resources/streaming_part_generation_flow_test.dart
- test/application/resources/generation_patch_parser_fence_test.dart

Tests（Possible，更新）:
- test/application/resources/part_generation_coordinator_test.dart（改用 streaming fake）
- test/application/resources/streaming_resource_generation_service_test.dart
- test/application/resources/generation_patch_parser_test.dart

Docs:
- docs/post-phase12-remediation/STATUS.md

Forbidden / should not be touched:
- 传输超时/重试预算（R04；本 Phase 不改 timeout/retry）
- 流式会话生命周期（R01）
- 内容写入 CAS（R03）
- PartGenerationValidator（保持 fail-closed；本 Phase 不改其规则）
```

## 12. Test Plan

### TEST R08-01（流式正常路径）
```text
Given: FakePartGenerationStreamingGateway 发送完整 NDJSON（start_part/append_text/complete_part）
When:  coordinator 生成一个 Part
Then:  accumulator 得到正确内容；commit 成功
```

### TEST R08-02（跨 chunk 断行 / 末尾无换行）
```text
Given: fake 把一行 JSON 拆到两个 chunk，且最后一行无 '\n'
When:  生成
Then:  仍能正确解析并提交（pending 尾部 flush 生效）
```

### TEST R08-03（解析异常传播）
```text
Given: fake 发送一条畸形 JSON 行
When:  生成
Then:  onValidationFailed 被调用
       attempt 标记失败
       不提交内容
       不出现无关的“未收到 complete_part”错误
```

### TEST R08-04（sequence gap / cursor mismatch）
```text
Given: fake 发送 sequence 跳跃 / cursor 不匹配
When:  生成
Then:  分别触发 onValidationFailed，且不提交
```

### TEST R08-05（provider 噪声不触发失败）
```text
Given: 流中混入非 `data: ` 行与非法 JSON 的 data 行
When:  生成
Then:  噪声被跳过；若其余 patch 完整则提交成功
```

### TEST R08-06（fence 容忍）
```text
Given: NDJSON 被 ```json fence 包裹
When:  parseNdjson / parsePatchLine
Then:  正确解析（字段白名单仍严格）
```

### TEST R08-07（协议一致）
```text
Given: 同一 NDJSON 输入
When:  分别走流式 fake 与非流式 completer
Then:  两者产生相同 accumulator 结果（同一 parser）
```

## 13. Mutation / Negative Verification

```text
Mutation 1: 把 onChunk 移回 provider 解码 try 内
→ TEST R08-03 必须 FAIL

Mutation 2: 在消费者异常传播前用 ApiError.fromException 包装
→ TEST R08-03 必须 FAIL（coordinator 类型不再匹配）

Mutation 3: 恢复非流式分支使用 PartGenerationParser.parse
→ TEST R08-07 必须 FAIL

Mutation 4: 移除 parsePatchLine 的 fence 剥离
→ TEST R08-06 必须 FAIL
```

## 14. Acceptance Criteria

```text
AC-R08-01 消费者异常原样到达 coordinator，触发 onValidationFailed。
AC-R08-02 解析失败后停止消费并拒绝提交（无无效内容）。
AC-R08-03 provider 事件噪声不导致失败。
AC-R08-04 流式与非流式分支共享 NDJSON 协议且结果一致。
AC-R08-05 流式分支被真实 fake gateway 覆盖（TG1 关闭）。
AC-R08-06 全量 flutter test 通过。
```

## 15. Required Verification Commands

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test test/application/resources/streaming_part_generation_flow_test.dart
flutter test test/application/resources/generation_patch_parser_fence_test.dart
flutter test test/application/resources/part_generation_coordinator_test.dart
flutter test test/application/resources/generation_patch_parser_test.dart
flutter test
git diff --check
git status --short
```

## 16. Out of Scope

- 不改超时/重试（R04）；
- 不改会话生命周期/恢复（R01）；
- 不改内容写入 CAS（R03）；
- 不改 `PartGenerationValidator` 规则；
- 不删除 `PartGenerationParser`（R13 cleanup 候选，需独立复核）。

## 17. Rollback / Failure Safety

- 修复后，解析/校验失败 → attempt failed、无内容提交、错误可诊断；重试由既有机制处理。
- 若消费者异常被错误地包装，测试会失败（Mutation 2），可及时回滚。
- 回滚为纯代码 revert。

## 18. Handoff Notes

- 本 Phase 必须在 R01、R04 之后，避免同时修改 `llm_service.dart` 与 `part_generation_coordinator.dart`。
- R13 可评估删除 `PartGenerationParser` / `PartGenerationResponse`（若确认无消费者）。
