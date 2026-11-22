# P0 Adventure reasoning / multi-stage investigation

> **历史 Agent 调查报告（Historical agent investigation report）。**
>
> 本文件是一次性 P0 调查的时点记录；其 "STATUS 仍为 PARTIALLY_FIXED" 与"剩余实施要求与
> 验收门槛"是当时结论。后续 [`p0-reasoning-only-narrative-recovery.md`](./p0-reasoning-only-narrative-recovery.md)
> 记录并完成了该调查要求的 L5 narrative → settlement → commit 证据，结论为 **FIXED**。
> 本文不是当前状态或操作手册。

## Baseline and evidence boundary

- Start HEAD / origin/main: `b52a1f33296970eea6824f9e5b4bc97d510ca9bf`;
  branch `main`, clean worktree. No reset, clean or stash.
- Source specification: user attachment `pasted-text-1.txt`, sections 0–81.
- Required production files and the seven named reliability test files have
  been read. Reuse their HTTP/SSE seam, ChatDependencies host fixture and
  repository commit authority. No schema change.
- Screenshot B is user-provided evidence of visible reasoning, empty narrative,
  streaming status and a usable Stop control. It supplies no exception, attempt,
  finish reason or turn identity. Historical duplicate log provenance cannot be
  reconstructed from two unlabelled lines.

## Invariants

1. One option click creates one intent; concurrent dispatch creates at most one
   logical turn. A retry reuses the unresponded user bubble.
2. After a consumer accepts visible reasoning OR content, transport may not
   silently replay the request. Usage, keepalive and malformed events do not
   count as visible output. A callback exception retains its type and stack.
3. Transport owns bounded retries and deadlines; reasoning resets idle activity
   but never disables the overall deadline. Cancellation releases permits.
4. A completed narrative prefix may survive a later-stage failure as a
   presentation-only draft; incomplete turns never apply state or commit.
5. Settlement and option repair retain their existing degradation authorities.
   Durable commit occurs at most once; cancellation after durability cannot
   undo it. Stale callbacks cannot touch a new request or disposed notifiers.
6. Prompts retain previous assistant narrative and historical repeated user
   actions, include the current input exactly once, and report the real round.
7. Network UI is reserved for transport; protocol/content/internal failures
   receive human-readable localized copy. No prompt, reasoning, narrative,
   credentials or provider response body in diagnostics.

## Audit findings and evidence boundary

- B1: `LLMService.sendMessageStreamDetailedTyped` passes reasoning directly to
  the consumer without updating the accepted-delta retry guard. Test two
  reasoning deltas then SocketException against the real SSE implementation.
- B2: `ChatEngine.sendMessage` maps every non-ApiError to network, including its
  own StateError from incomplete reasoning-only responses. Test result
  completion/finish reason and consumer failures independently.
- B3: the top-level catch clears all narrative/reasoning on a later-stage
  failure. Retain validated completed prefix for reading without persistence;
  failed current-stage content must not become an authoritative turn.
- M1: `ApiError.fromException` labels socket/TLS as timeout and uses string
  matching. Preserve typed transport versus timeout classification and cause.
- M2: runtime preparation awaits occur before the turn's try/finally and before
  task identity is installed; a repository failure can strand `loading` and a
  stop/reset can race initialization. Include preparation in convergence.
- M3: planner source history filters all matching user text while the actual
  history removes only its last matching user. Align those projections only
  after continuity tests; current code does NOT prove assistant history loss.
- M4: PromptBuilder adds one even when current user was already appended.
  AppConfig currently does not read round, so this does NOT explain the model's
  first-message remark. Test round semantics and retain conditional first-turn
  instructions.
- M5: MessagingProvider holds a late-final engine; a repeated init constructs
  a new engine then throws on assignment. Make initialization idempotent and
  observe create/dispose; do not claim hot reload caused the historical logs.

## Implementation scope and phases

1. Reproduce B1 and B2 BEFORE production edits using existing harnesses.
2. Instrument GenerationDiagnostics: engine lifecycle; UI intent; turn
   request/generation/adventure/branch/provider/model; prompt roles/counts,
   lengths/hash/history IDs/round; stages; transport attempts and acceptance;
   headers/first event/reasoning/content/DONE/finish/closure; settlement,
   length guard, commit and final scheduler snapshot. Capture stacks only in
   debug diagnostics and never interpolate raw exceptions.
3. Suppress replay after accepted visible output; use typed chat failure and
   explicit protocol-incomplete exceptions; preserve no-output retries.
4. Fix proven lifecycle/history/recovery defects within this pipeline; retain
   existing settlement, length guard, state validation and commit authority.
5. Validate and review the final diff against this same specification.

Affected files: LLMService, ApiError, generation handle/diagnostics if needed,
ChatEngine and its prompt builder, NarrativeContext, MessagingProvider,
ErrorCard and six ARB locales, SessionMessageList/option dispatch only if tests
prove needed. Tests extend existing files; new focused failure tests may reuse
the host fixture. No dependencies or model-name-specific patch.

Forbidden: increasing timeouts/retries, lowering L5, disabling reasoning or
multi-stage, unrelated UI redesign, clearing real user databases, leaking
private payloads, creating a second settlement/retry architecture.

## Required validation and deliverables

- Deterministic matrix A–W from attachment section 60; track exception class,
  turns, attempts, callbacks, user/assistant/state commits, revisions, permits
  and final ChatStatus at the appropriate production layer.
- Option single click and rapid double click; screenshot B streaming/stop;
  failure UI responsive at 320/360/390/412 and desktop, enlarged text.
- Named seven targeted suites plus reasoning failure/classification tests.
- `dart format .`, `flutter analyze`, full `flutter test`, `git diff --check`.
- Real `flutter run -d linux`: matching Adventure, provider/model, L5 option,
  normal generation/settlement/commit, Stop during reasoning; fake-client
  connection and post-reasoning disconnect without changing system network.
- Final report uses attachment section 80 fields. Every acceptance gate in
  section 81 needs authoritative evidence; otherwise PARTIALLY_FIXED/BLOCKED,
  never FIXED. Missing historical identity is explicitly unverified.
- Commit only after proven root cause and targeted/full tests pass; then push
  origin/main and verify HEAD equality and clean worktree.

## Progress

- B1/B2 reproduced before edits: two reasoning callbacks, zero content,
  three HTTP attempts; injected StateError classified as network. Red failures recorded in the initial tool output and focused test sources. Regressions now pass with one attempt and internal classification.
- Preparation failure, late-stage prefix loss, delayed cancellation, repeated
  init and planner filtering each reproduced before their fixes.
- First full run: 2781 passed / 1 skipped; analyze clean; format 703 files.
  Further real-device findings below require rerunning validation.

### Real Linux reproduction, 2026-10-02

- Existing `flutter run -d linux` process; Adventure 7 / branch 0,
  deepseek / deepseek-flash, L5, user maxTokens 4096, thinking true, effort max.
- Attached and restarted (no database deletion); new engine 516056051.
- One accessibility option Tap -> one OPTION_INTENT -> one START and
  MULTI_STAGE_START, request scene-1790927196934554-2, generation 2.
- stage1 HTTP 200, attempt1, 5644 reasoning deltas / 8548 characters,
  zero content; finish stop + DONE. Empty response was incorrectly treated as
  completed narrative and included an empty assistant in stage2 history.
- stage2 HTTP 200, attempt1, 3977 reasoning deltas / 6061 characters,
  zero content; finish length + DONE. LLMResponseIncompleteException ->
  protocolIncomplete -> localized generation failure. Zero commits, idle,
  all scheduler active/waiter counts zero.
- Prompt stage1 roles [system, assistant, user], lengths [5105,216,247],
  previous assistant opening present, current user once, round1 (opening was
  generated without a player user turn). Cannot attribute the model's remark
  to lost history. No transparent transport retry occurred in this real run.
- Trace source: GenerationDiagnostics marker queue inspected read-only using
  VM service. Safe trace captured to `/tmp/lt-p0-linux-trace.log`; no payload.

### Additional implementation requirements from real evidence

- Empty stop/completed narrative must fail content validation before any
  continuation; preserve reasoning as presentation only and never commit.
- L5 stage caps (5712 then 3980) account only for narrative. Model capability
  includedInOutput means reasoning consumes the same cap. Use the existing
  narrative thinking floor (8192) as a separate reasoning allowance, combined
  with the unchanged per-stage narrative allowance and bounded by the model
  output limit. Preserve the user's thinking toggle and effort; no model-name
  branch, retry/time-limit increase or narrative length reduction.
- Put this arithmetic in the existing SceneDialogueOutputBudget and reuse it
  in stage requests and initial prompt reservation. Actual context reservation
  must cover the combined request cap; maintain the conservative 32768 input
  context window. Test thinking/non-thinking and physical cap behavior.
- Vendor references (verified):
  https://api-docs.deepseek.com/api/create-chat-completion/ (max tokens/defaults)
  https://api-docs.deepseek.com/guides/thinking_mode/ (separate output fields).
  These support budget/protocol semantics, not a claim that the historical
  two unlabelled logs came from this newly observed turn.
- Original two logs remain unidentifiable: neither line contains an engine,
  request or generation identity. New traces must not be retroactively assigned
  to those lines.

## 最终调查报告（附件第 80 节）

### STATUS / BASELINE

**PARTIALLY_FIXED**。已证明并修复本地可靠性缺陷，但真实 L5 正常正文、
结算、提交链路尚未成功。原始两条无身份 multi-stage 日志也无法还原。
这两项验收缺口禁止报告 FIXED。

- 起始 HEAD 与 origin/main：`b52a1f33296970eea6824f9e5b4bc97d510ca9bf`，
  高于附件所列 `56040b8`；main 起始工作树干净。
- 最终代码基线：包含本报告的 `fix(chat)` 提交；最终 hash、push 结果及
  HEAD 与 origin/main 的比较由提交后的聊天回执记录，避免预写成功。
- 修改范围限于 Adventure prompt、stream/retry/cancel、错误呈现、生命周期
  与现有测试 harness。无 schema、依赖、版本号或输入布局变更。

### REPRODUCTION / SCREENSHOT B EVIDENCE

2026-10-02，在用户已有 `flutter run -d linux` 应用中复验：Adventure 7 / branch 0，
deepseek / deepseek-flash，L5 范围 4500–10000、目标 6500；thinking=true、
reasoning effort=max、用户 maxTokens=4096。点击附件中的同一旅店老板选项。
通过 Flutter attach 加载修复，并以一次 hot restart 加载新增类；未清空数据库。

截图 B 状态确实可复现：HTTP 200、reasoning 非空、content=0、StreamingBubble
显示深度思考、红色 Stop 可操作、ChatStatus=streaming、request 仍活跃。
reasoning 持续输出期间属于活跃生成，不能据此判定卡死或无法建连。

### ROOT CAUSE / ERROR CLASSIFICATION

1. **可见 reasoning 后隐式重发**：
   `LLMService.sendMessageStreamDetailedTyped` 的原 guard 只在 content callback
   成功后置位，reasoning 直接传给 consumer。两次 reasoning 后 SocketException
   的红测试记录三个 HTTP attempts。现在分别跟踪 acceptedReasoning 与
   acceptedContent，任一可见输出被接受后禁止透明 replay。无输出的可重试
   transport failure 仍按原三次上限处理。
2. **协议/内部失败误报网络**：
   `ChatEngine.sendMessage` 原 catch 将所有非 ApiError 映射为 network。
   注入 StateError 的红测试证明误报。现在 `ChatFailureClass` 区分 transport、
   timeout、authentication、rateLimit、server、invalidRequest、protocolIncomplete、
   contentInvalid、internal、cancelled、stale。ErrorCard 只有显式 network 类型
   显示网络文案；未知类型回落为处理失败。六种语言均同步，无原始异常 UI。
3. **真实 stage2 异常**：request `scene-1790927196934554-2` 的 stage1 是
   `stop + DONE + 空正文`，原实现允许进入 stage2；stage2 是
   `length + DONE + 空正文`，在 `_executeAdventureContext` 抛出
   `LLMResponseIncompleteException`，归为 protocolIncomplete。故障发生在
   已收到 reasoning 后，不能用“网络连接失败”解释。
4. **空正文错误推进**：新增红测试证明空正文会继续多幕及补写。现在
   `stop/completed` 的空 narrative 在第一幕抛 FormatException / contentInvalid，
   保留 reasoning 供查看，不进入下一阶段，不提交。
5. **incomplete partial 被当成功**：原实现会接受 500 字、unknown/interrupted
   且 responseCompleted=false 的结果。现在只有明确输出上限、completed 且满足
   现有长度条件的结果可接力；意外流关闭不进入 settlement/commit。
6. **失败后内容与状态收敛**：完成的 stage prefix 原先全部清空；现在仅保留
   已完成前缀作为 failed presentation draft，失败幕的 partial 丢弃，状态不落地。
   runtime preparation 也纳入 turn try/finally，异常不再留下 loading。
7. **取消与过期结果**：连接或 silent SSE 原先等待 timeout；现在取消会唤醒
   connect/stream await。旧请求不能清空新请求，旧 Adventure 的迟到 durable
   commit 不能覆盖新工作区；同一工作区提交后的迟到 Stop 仍尊重数据库事实。
8. **历史、round、初始化**：planner 原先删除所有同文本历史 user，实际 compiler
   历史原本只去掉当前尾项；统一两者。round 去掉已追加输入的 +1 偏移。
   `AppConfig.adventurePrompt` 当前不读取 round，故此偏移不能解释模型的 first
   message 说法。重复 init 原先先创建第二引擎再 LateInitializationError，现在复用。
9. **output reserve 漏算**：capability 的 includedInOutput 表示 reasoning 和 prose
   共享输出预算，原 L5 stage1 只有 5712、stage2 3980。使用既有 reasoning floor
   加上 narrative allowance，并受模型物理输出上限约束；stage1 变为 13904，
   PromptBuilder 同步预留，保留 32768 的保守 context window。没有提高 timeout、
   retry 次数、降低 L5、关闭 thinking 或改变 effort。

**预算修正不能解释全部现场。** 扩大后 request `scene-1790927909728639-3`
在 stage1 返回 stop、5113 reasoning 字符、0 content，远未到输出上限。
另一次 `scene-1790928752045957-4` 用完整 13904 上限仍只收到 reasoning，
以 length 结束。尚无证据把所有空正文归因于预算或给出服务端根因。

### REASONING RETRY / TRANSPORT TRACE

| request / stage | HTTP / attempts | reasoning deltas / 字符 | content | 首 reasoning / 总时长 | finish / DONE | 结果 |
| --- | --- | --- | --- | --- | --- | --- |
| `…7196934554-2:stage1` | 200 / 1 | 5644 / 8548 | 0 | 见安全 trace / 37.895s | stop / true | 修正前允许空幕推进 |
| `…7196934554-2:stage2` | 200 / 1 | 3977 / 6061 | 0 | 见安全 trace / 26.021s | length / true | protocolIncomplete，0 commit |
| `…7909728639-3:stage1` | 200 / 1 | 3286 / 5113 | 0 | 见安全 trace / 22.280s | stop / true | contentInvalid，0 commit |
| `…8752045957-4:stage1` | 200 / 1 | 13888 / 43605 | 0 | 2.464s / 84.728s | length / true | protocolIncomplete，0 commit |
| `…9184854981-5:stage1` | 200 / 1 | 2806 / 11255 | 0 | 3.032s / 17.963s | unknown / false | 人工 Stop，cancelled |
| `…9691952654-7:stage1` | 200 / 1 | 2820 / 11231 | 0 | 3.171s / 19.899s | unknown / false | 最终代码人工 Stop，cancelled |

真实请求均无 firstContent。最后一次：headers=2.646s、firstEvent=2.657s、
lastReasoning=19.891s；停止后 ATTEMPT_FAILED=19.899s，END/idle 随即到达。
上述运行没有透明 transport retry。没有 DONE 的停止不能伪记为正常完成。

确定性 OLD：reasoning callbacks=2、content callbacks=0、HTTP attempts=3，
可见 reasoning 未触发 guard。NEW：同样输入 HTTP attempts=1，
retryDecision=false，reason=visible-reasoning-already-emitted。
content、reasoning、onDone callback 自身抛可重试 ApiError/SocketException
也保持原 exception/stack 且不重发；畸形 provider delta 与 consumer failure 分开。

### DUPLICATE MULTI-STAGE LOG

原始 log1/log2 的 engine/request/generation **均 UNVERIFIED**。它们没有 identity，
无法判断 A–G 中的实际来源；不能把新运行代替旧运行，也不能说 transport retry
重印了 ChatEngine 的入口日志，因为 retry 位于该入口之后的 LLMService。

新运行的证据：

- log1：engine=516056051，request=`scene-1790927196934554-2`，generation=2。
- log2：engine=516056051，request=`scene-1790927909728639-3`，generation=3。
- **这两条新日志**对应两次人工选项点击，属于 E：TWO LEGITIMATE USER TURNS。
  每次 OPTION_INTENT、START、MULTI_STAGE_START 各一次，不是两引擎或透明重发。
- Widget 证明一次 option Tap 的 provider.sendMessage=1；引擎 barrier 证明
  快速双 dispatch 只有一个 logical turn/requestId，没有 debounce。

### PROMPT HISTORY

最终真实 request `scene-1790929691952654-7`：count=3，roles=
`[system, assistant, user]`，lengths=`[5105,216,247]`；实际 compiled historyItems=
`[{id: opening-7, role: assistant}]`，historyCount=1，currentInputCount=1，round=1。
user 内容长度包含 stage instruction 与当前输入。序章没有 player user turn，
所以这是第一个 player round。first-round 条件指令保留，但历史没有被裁成空。
模型的英文判断不是历史丢失的证明。

测试同时证明第 1/2 round 正确、以前两个同文本命令保留、当前输入只追加一次、
assistant narrative projection 存在。diagnostics 只含 role/count/ID/长度/hash，
不记录 prompt/reasoning/narrative 原文、请求 Header、Key 或响应 body。
后续阶段与 helper trace 中的 historyItems/currentInputCount 表示该 turn 的初始
compiler 历史，不把后加的 stage instruction 冒称为新的玩家输入。

### TURN TRACE / ATOMICITY / RETRY / SCHEDULER

- 真实正常尝试：START → stage1；早期复现进入 stage2 后失败，空正文修正后
  第一幕即失败。STAGE3/4、LENGTH、SETTLEMENT、COMMIT **未到达**。
- L5 deterministic 成功 narrative + helper 失败：3 个 narrative stages →
  LENGTH → settlement 2 次失败 → option repair 1 次失败 →既有 fallback →
  单一 durable COMMIT。并未建立第二套 settlement。
- stage1 成功 / stage2 reasoning-only 或 partial failure：保留 3300 字完成前缀，
  无有效 assistant message、config 更新=0、gold 不变、status=idle。
- real DB 只读复核：Adventure7 messages=1（原序章）、scene_dialogue_turns=0、
  runtime_heads=(branch0, revision0)、checkpoints=0。没有失败或停止 turn 提交。
- 同模型与切换模型 retry：两次逻辑调用共一个 user bubble，ID 不变，最终一个
  新 assistant，无错误卡；不是透明 retry，也不重复 apply 前轮 delta。
- HTTP fake tests 验证 active、waiter、global active、global waiter 归零；每次真实
  END 的 global/deepseek active/waiter 也均为零。没有 observed permit leak。
- 真实 Stop 清除 cancelled user/draft/reasoning，无错误卡、无下一 stage，输入恢复
  send。Fake 同时覆盖 narrative、stage2、settlement Stop 与迟到 callbacks。

### TEST MATRIX / TESTS

计数在实际所属层验证：HTTP seam 验证 attempt/delta/deadline/permit，engine host
与 controlled repository 验证 logical turn、message、state、commit、最终 status，
Widget 验证 option dispatch、reasoning/Stop 和本地化布局。引擎 override 的调用次数
不冒充真实 HTTP attempts；真实现场和 fake 证据分列。

| 附件矩阵 | 验证来源与结果 |
| --- | --- |
| A/B/C/D/E 无输出 Socket/TLS/401/429/503 | llm_streaming_reliability：attempts 3/3/1/3/3，零 callbacks，分类正确，permits=0 |
| F headers 无 SSE | R04-A A2：first-event timeout；无挂起 |
| G/H/I reasoning 后 reset/idle/reasoning+content reset | P0 transport matrix + reasoning-only replay：1 attempt；可见输出不重发 |
| J/K 500 字 close / unknown / interrupted | streaming + atomicity：protocolIncomplete，不 commit |
| L length | parser 保留 completion/finish metadata；仅明确 cap 的有效正文允许既有接力 |
| M/N 第一幕完成、第二幕 reasoning/partial 失败 | atomicity：完成 prefix 保留，失败幕丢弃，无状态提交 |
| O/P 全 narrative 成功、settlement / repair 失败 | cancellation_commit_boundary + turn_settlement + atomicity：既有 fallback，单次 commit |
| Q/R/S reasoning/narrative/settlement Stop | cancellation_commit_boundary + real SSE cancellation：无错误、无 commit、stale callbacks 丢弃 |
| T option 双点击 | phase3 Widget 单 Tap=1 send；atomicity 快速双 dispatch=1 turn |
| U/V 同模型/切换模型 retry | atomicity：user ID 复用，消息/状态不重复 |
| W re-init / hot reload | phase3：重复 init 复用 engine/notifiers；真实 hot reload 后同 engine 再 Stop 通过 |

新增集中测试：`chat_engine_error_classification_test.dart`、
`chat_failure_card_test.dart`；reasoning-failure 场景直接扩展既有 streaming 和
atomicity harness，没有另建可靠性架构。同步扩展 prompt/history/budget、
cancellation/durable boundary、session phase3；原七个指定 suite 均运行。
新增错误卡验证 generation/internal/unknown 在 320/360/390/412/1024、字体 1/2，
六种 locale 在 320 + 字体2；截图 B 在 320 也验证 reasoning 与 Stop。

### MANUAL LINUX / VALIDATION / GIT

- 正常 L5：**未通过**，reasoning 成功，正文未到；不能宣称完整修复。
- 人工 reasoning Stop：两次通过，包括最终逻辑的 hot reload。
- 连接前失败及 reasoning 后断流：真实 LLMService + Fake Client 覆盖，
  未修改用户系统网络。
- `dart format .`：703 文件，最终 0 changed。
- `flutter analyze`：No issues found。
- 最终 targeted：244 passed（原七 suite、新分类/布局、turn_settlement）。
- 最终 full：隔离工作树 2826 passed / 1 skipped，All tests passed（2m26s）。
- `git diff --check`：通过；提交前再复核 status/diff。
- 本机第一次最终全量为 2825 passed / 1 skipped / 1 failed，暴露 Case J 的 stale
  settlement status 未归 idle；修正后定向 28 项通过，再做最终全量。
- 该次测试调用现有 AutoBackupService，触发真实目录中的备份轮换，较早备份被
  删除。没有恢复、清空或删除真实主数据库；只读确认上述 Adventure 数据未变。
  后续验证使用隔离 Git worktree `/tmp/lt-p0-validation-worktree`，避免再触达
  用户应用的默认数据目录。此副作用不能被“消息没变”掩盖。
- 安全临时 trace：`/tmp/lt-p0-linux-trace.log`；截图（含用户内容，只保留本机）
  `/tmp/lt-p0-linux-stop-before.png`、`/tmp/lt-p0-linux-stop-after.png`，不提交截图。
- 最终 commit/push 仅在 proven fixes 的 targeted/full gates 均通过后执行。
  全部完成不等于附件所有验收项满足；STATUS 仍为 PARTIALLY_FIXED。

### 剩余实施要求与验收门槛

1. 需要原始那两次执行的带身份 trace，或可复现的双入口行为，才能归类历史
   duplicate logs。不要给无身份日志补造 engine/request/generation。
2. 需要真实同模型同 L5 成功完成 narrative→length→settlement→commit 的证据，
   并解释空 content（包括 stop 且远未到 cap）的原因。目前 trace 只能证明
   “返回 reasoning、没有 content”；不能把预算修正当充分根因。
3. 后续沿相同方案、真实 trace 与 commit diff 继续，保持原档位/effort，
   不用加 timeout、透明重发、关闭 reasoning、删历史或清库绕过问题。
4. 原始来源和真实正常生成这两项未解决前，禁止把本报告状态升级为 FIXED。

## 后续定向调查：原始 SSE 与解析输出的边界

- 基线：`b83ed79e91b967ec7f334c20ab0a93b8abfb9dc2`，main 与 origin/main 一致，
  开始时工作树干净。上轮已完成修复、测试与推送，属于有权威证据的进展。
- 用现有服务配置做一次不含用户资源的短文本诊断：同一 deepseek-flash、
  thinking enabled、effort max、max_tokens4096，1 次 HTTP200、17 reasoning
  deltas / 76 字符、1 content delta / 2 字符、stop + DONE；2.299s 结束。
  usage completion19 / reasoning17。只记录字段与长度，不输出凭证或响应原文。
  它证明 endpoint 当前能返回标准 content，不能证明 L5 prompt 正常。
- 范围：仅扩展现有 LLM attempt trace，在 provider choice 校验前统计 wire
  content/reasoning 字符、兼容结构 message.content 字符与 delta 值类型。
  这用于区分上游缺失 content 与 parser 丢弃；不新增 provider 请求路径或 fallback。
- 保留同一 L5、thinking/effort、stage output cap 与现有 timeout/retry。
  假 SSE 验证 wire/consumer 计数的正常和畸形边界；真实同选项一次复验。
- 若 wire content 为零且没有替代结构，不声称改 parser 可产生正文；继续保留
  原始日志身份缺口。验收仍需要真实 narrative→settlement→commit 的完整证据。
- 同一调用链进一步确认 prompt scope 冲突：AppConfig 的硬下限与完整两段 JSON
  格式、PromptBuilder 的禁止只写正文、engine 的 4500 字硬指标进入 system，
  同时 stage1 的 user 指令要求约 3250 且禁止 JSON。扩展现有 atomicity harness
  捕获真实编译 messages，先做红测试，再使 aggregate budget 与当前 stage 格式
  明确分离。保留第一轮条件、L5 数值、stage planner、settlement/commit authority。
  这是可证明的本地提示冲突，尚不能当作 provider 所有空正文的充分根因。

### 本轮新增证据与结果（2026-10-02）

STATUS 仍为 **PARTIALLY_FIXED**；真实正常 L5 和历史两条无身份日志的来源仍未验收。

1. 原始 SSE 计数已通过 VM 加载源码确认，避免把 attach 的成功提示当代码已生效。
   修正提示前 engine=16161914、request=scene-1790931431745199-2、generation=2：
   一次 HTTP200，首 reasoning 2.348s，13886 reasoning deltas / 40966 字符，
   wire reasoning 与 accepted reasoning 一致，wire content/message content/accepted
   content 均为 0，malformed=0，length + DONE，81.019s 结束。stage1 判为
   protocolIncomplete；没有 stage2、length guard、settlement 或 commit。
2. 提示冲突用现有 atomicity harness 捕获实际 compiled messages 后红测复现。
   修正 AppConfig、PromptBuilder 与 engine 的整轮/当前幕作用域；L5 仍为
   4500~10000、目标6500，首幕3250，token cap13904，thinking enabled、effort max。
   保留首轮条件、历史、分幕规划、长度校验和提交权威，没有放宽验收或增加重试。
3. 修正后真实 engine=240969619、request=scene-1790931934425069-2、generation=2：
   一次 HTTP200，首事件3.960s、首 reasoning4.799s，5250 reasoning deltas /
   8205 字符，wire/accepted reasoning 一致；wire content/message content/accepted
   content 均为 0、值类型为 String、malformed=0。stop + DONE，38.476s结束，
   stage1 的 FormatException/contentInvalid。仍未进入 stage2 或后续提交路径。
   因此提示冲突是已证明并修正的本地缺陷，**不是空正文的充分解释**。
4. 两次请求各只有一个 MULTI_STAGE_START；一次点击一个 intent/turn。END 都为
   idle、global/deepseek active=0、waiters=0、committed=false。只读真实 Adventure7
   数据仍为 messages=1、scene_dialogue_turns=0、runtime head=(branch0, revision0)、
   checkpoints=0。没有把 reasoning 或失败草稿持久化为有效回合。
5. 本轮复核还发现上次预算修正对未知模型的回归：registry 的 conservativeFallback
   输出占位1024被误当物理上限。新增红测试分别证明实际请求5712被压到1024、
   配置12000的 context reserve 被压到1024。修正仅在已确认能力上 clamp；未知模型
   请求保留既有正文预算，provider reserve 恢复 max(userMaxTokens,8192)。
   不修改 registry、已确认模型上限或真实 DeepSeek 的请求预算。
6. wire 诊断只记录字段类型/长度；有效事件与畸形 reasoning 事件都有测试，验证
   raw count 与 consumer count 可区分且 trace 不含 fixture prompt/reasoning/narrative。
   streamClosedNormally=null 表示收到 DONE 前后尚未观察到 upstream EOF；不能
   将它解释为异常关闭。responseCompleted/finishReason/DONE 分别记录。

验证以最终代码结果为准：先前 wire-only full=2828/1 skip、提示修正 full=2829/1 skip；
新增未知模型回归修正后再运行七个指定 suites 与分类/Widget/settlement，以及隔离全量。
最终计数与 Git 结果记录在下方，不能拿先前结果替代最终代码的验证。

- 最终 targeted：**249 passed**，十个 suites（包含原七个指定 suites）。
  `/tmp/lt-p0-followup-targeted-final.log`。
- 最终 full：**2831 passed / 1 skipped**，All tests passed（2m18s），
  `/tmp/lt-p0-followup-full-final.log`，在隔离 Git worktree 中运行。
- `dart format .`：703 files / 0 changed；`flutter analyze`：No issues found；
  `git diff --check` 通过。主工作树与验证工作树的变更代码/测试逐文件一致。
- 新增自定义模型测试曾暴露 asynchronous connectivity_plus MissingPluginException，
  延迟落在下一 Widget test；测试套件补齐 listen/cancel 平台通道模拟后定向与
  全量均通过。不改产品连接服务，不吞断言，不把 earlier flaky pass 当最终证据。
- Linux 应用完成最终 hot reload；VM 源码核对确认预算保护已加载。随后用 detach
  退出本轮 attach 工具，原用户应用进程仍运行，没有关闭或重建用户应用。
- 该节所在提交基于 b83ed79，只提交已通过红/绿测试的提示作用域修正、wire
  诊断与未知模型回归保护。提交后推送 origin/main；最终 SHA 由 Git 给出。
- 已询问原始双日志对应时段的终端与操作记录，尚无新增来源证据。
  本轮有实质进展，但不能升级为 FIXED，也不以反复付费重发取代缺失证据。
