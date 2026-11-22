# P0 — Reasoning-only Adventure narrative recovery

## Baseline and scope

- Start HEAD / origin/main: `cab248e395884d92dfb545744dda0f67d68f4c56`.
- Start worktree: clean. Previous reliability fixes remain authoritative.
- Specification: user attachment `3c212670-676b-47be-9fa9-743577d8a095/pasted-text-1.txt`.
- Scope: completed reasoning-only Adventure narrative stages, safe wire diagnostics,
  controlled real-provider experiments, bounded semantic recovery and its tests.
- Excluded: history/round/compiler/scheduler rewrites, changing user effort, increasing
  output budgets, rendering reasoning as prose, replaying incomplete transport output.
  Historical unlabelled multi-stage logs are explicitly closed as untraceable.

## Confirmed failure and evidence boundary

Real HTTP200 + SSE reasoning + DONE returned empty raw/parsed content, with both stop
and length finishes. Budget expansion and aggregate/stage prompt scoping did not
restore prose. This proves a completed response without narrative, not its upstream
internal cause. Keep provider behaviour observations separate from local defects.

## Implementation requirements

1. Record actual wire model/max_tokens/thinking.type/effort and format/sampling field
   presence without message values, keys, headers or response text.
2. Run serial controlled experiments with one frozen captured stage context. Keep
   private messages in memory only; persist roles/lengths/hashes/params/counts/timing.
   Official DeepSeek docs map requested medium to high: report that alias explicitly.
3. A typed reasoning-only marker applies only to adventureResponse, completed result,
   stop/length/maxTokens, nonblank reasoning and blank content. Empty/incomplete,
   transport, timeout, cancelled and stale results never start semantic recovery.
4. One narrative-stage executor owns primary + at most one prose recovery. Same turn,
   stage and cancellation authority; distinct `:prose-recovery` subrequest. Recovery
   uses the original messages plus a short control instruction, never raw reasoning.
5. Recovery disables thinking, uses low effort and the existing prose-only stage cap.
   Preserve primary reasoning, switch its thinking notifier off, stream content through
   existing callbacks/typewriter. Return one result containing the recovered prose and
   original reasoning. Recovery cannot recursively recover itself.
6. Never add the empty primary assistant to stage history. Only accepted stage prose
   advances the stage loop; failure preserves completed prefix as presentation only.
   Existing length/settlement/option repair/durable commit authorities remain unchanged.

## Files and verification

Production: `llm_service.dart`, `chat_failure.dart`, `chat_engine.dart`, narrowly scoped
StreamingBubble status copy in `message_bubble.dart`; extend existing
streaming/atomicity/cancellation/session harnesses, do not create another reliability
architecture. If more isolation is needed, a focused suite may reuse existing support.

Tests: stop/length/maxTokens reasoning-only recovery, empty recovery (no third call),
recovery transport failure, primary transport/incomplete/cancel/stale exclusion, normal
thinking/non-thinking exclusion, stage2 prefix, final-stage JSON contract, recovery
Stop/stale callbacks, visible reasoning/notifier streaming, one user/commit/revision/
state application, scheduler permits. Run specified suites, format, analyze and full
tests in `/tmp/lt-p0-validation-worktree` to protect real application data.

## Acceptance and Git gate

Serial thinking matrix: off/low/medium/high/max. Prompt matrix: short/system+user/
system+previous assistant+user/full stage. Record sample limits; do not infer probability
from one observation. Confirm capability protocol against primary documentation.

Real Linux Adventure7, same option, L5, deepseek-flash, thinking=true/effort=max must
show reasoning → prose → stages → settlement → new options → one durable commit.
Also stop during reasoning/recovery. Only after deterministic tests and at least one
complete real L5 success may this task be committed/pushed. Otherwise leave the task
diff reviewable and report PARTIALLY_FIXED with exact remaining gates.

## Results

### Wire and controlled matrix

Actual source loading was checked through VM script contents before one real option
tap. Captured wire context remained in the diagnostic Python process's memory only,
then the original app request was allowed to finish before any diagnostic request.
All nine diagnostic requests ran serially, once each, with no automatic retry. Only
metadata were written to `/tmp/lt-p0-reasoning-control-matrix.jsonl`.

Actual shape: deepseek-flash, max_tokens13904, thinking enabled, effort max,
stream=true; response_format/temperature/top_p absent. Wire messages have roles
system/assistant/user and lengths 4859/216/247. SHA256 (URL-safe base64):

- system: `VKv8KNASJa3qvVMz5Fo0bxqgrUDXme7PCJkkWu-jcf0=`
- assistant: `F881jRHCg7k1dHIj-z4tqaa6nx2DsToO6vkXtsiNi5Y=`
- user: `kX8gJFSQVO6f_h0MslVm66GlDePtjQcM8Iyv5QGMcBY=`

Original app request engine104403309/requestscene-1790942706782094-2/generation2:
one HTTP200 attempt, first reasoning2.210s, 2380 reasoning deltas/3688 chars, raw and
accepted content0, stop+DONE at16.700s; no stage2/settlement/commit, idle and permits0.

Frozen full-stage thinking matrix (all HTTP200, DONE, cap13904):

| Requested mode | Reasoning chars | Content chars | Completion / reasoning tokens | Finish | Latency |
| --- | ---: | ---: | ---: | --- | ---: |
| off | 0 | 1452 | 1034 / absent | stop | 10.092s |
| low | 1147 | 2859 | 2622 / 696 | stop | 18.258s |
| medium | 342 | 2207 | 1719 / 224 | stop | 13.096s |
| high | 12219 | 0 | 7865 / 7865 | stop | 35.589s |
| max | 20727 | 0 | 13900 / 13900 | length | 78.410s |

Only the logical thinking setting/effort changed: off disables thinking and removes
reasoning_effort as the product serializer does; on cases alter only effort. No
temperature, response format, message or budget changes. Official documentation
allows thinking+effort together and maps medium to high ([DeepSeek API](https://api-docs.deepseek.com/api/create-chat-completion/),
[thinking guide](https://api-docs.deepseek.com/guides/thinking_mode/)). Thus medium/high
are **not independent effective effort levels**. Their differing samples and one
observation per cell rule out claiming a deterministic threshold or failure rate.
User settings/default effort remain unchanged.

Prompt matrix (thinking enabled/max, cap13904; all HTTP200/DONE):

| Context | Reasoning chars | Content chars | Completion / reasoning tokens | Finish | Latency |
| --- | ---: | ---: | ---: | --- | ---: |
| short user: 300-char inn scene | 94 | 333 | 282 / 59 | stop | 3.862s |
| same short user + captured system | 11144 | 618 | 3765 / 3380 | stop | 18.771s |
| same + captured previous assistant | 4962 | 0 | 3072 / 3072 | stop | 18.111s |
| full captured stage1 | 32067 | 0 | 13903 / 13903 | length | 70.754s |

The first transitions add system and history respectively; the last replaces the
short user message with the original compiled stage instruction/current input.
No private resource/prompt/reasoning/body was persisted. Diagnostic char counts are
decoded Unicode codepoints; application traces use Dart string lengths.

Conclusion: reasoning-only is observed on completed high/max contextual narrative
requests, with both natural stop below cap and output-limit completion. It is not
exclusive to max, not a global lack of content support, not a missing-history or
parser-drop failure, and cab248e's prompt scope fix is insufficient. For length samples
all completion tokens were reasoning; for stop samples that occurred without using
the cap. The upstream internal reason for a natural stop with no final answer remains
unknown. Recovery therefore targets this exact response contract, not a guessed model
name, new prompt rewrite, larger cap, lower default effort or transport failure.

### Implementation and test evidence

New recovery tests were red on cab248e (expected two stage calls, actual one), including
an isolated-worktree reproduction. Primary stop/length/maxTokens now use the same
stage executor's single non-thinking recovery. Empty recovery, transport failures,
incomplete/unknown, Stop and stale exclusions are tested in the existing harness.
Final-stage format, stage2 prefix and durable single-commit/state/revision tests pass.
The named reasoning failure suite tests typed eligibility/privacy;
engine behaviour remains exercised through existing atomicity/cancellation harnesses.

### Real Linux L5 acceptance

**FIXED** at the application response-contract boundary. On 2026-10-02 the existing
Linux app, Adventure7/branch0, deepseek-flash, L5 (4500/6500/10000), thinking=true and
effort=max completed the original innkeeper option. Primary settings and budgets
remain unchanged. Engine104403309/requestscene-1790943766140321-3/generation3:

| Stage | Primary reasoning / content chars | Primary finish | Recovery cap | Recovery content / finish | Primary / recovery latency |
| --- | ---: | --- | ---: | --- | --- |
| 1 | 11926 / 0 | stop + DONE | 5712 | 3337 / stop + DONE | 46.498s / 17.739s |
| 2 | 1271 / 0 | stop + DONE | 2458 | 967 / stop + DONE | 7.293s / 6.268s |
| 3 | 4753 / 0 | stop + DONE | 2757 | 1073 / stop + DONE | 11.659s / 7.367s |
| 4 | 2469 / 2185 | stop + DONE | none | none | 14.512s / none |

Primary stage caps: 13904/10650/10949/11756. Each affected stage has one
REASONING_ONLY → PROSE_RECOVERY_START → FIRST_CONTENT → PROSE_RECOVERY_DONE chain.
Each recovery has its own `:stageN:prose-recovery` ID under the same root request.
The first recovery's first content arrived in2.296s. All eight HTTP subrequests
(four primary stages, three recoveries, one settlement) used **attempt1**, HTTP200;
transport replay count0, semantic recovery count3 total/at most1 per stage.
The next primary stage still used thinking enabled/max. Recovery's CompletionParams
effort is low; the existing serializer omits reasoning_effort when thinking is
disabled. No primary reasoning was inserted into any recovery message.

Final narrative6036 Chinese chars, within4500–10000; no length supplement.
Settlement `:settlement1` ran once (4.196s, cap1024, thinking disabled,
response_format present), returned210 chars and statusapplied. It supplied five
new options; no option-repair request. COMMIT_START+1306543.0ms,
COMMIT_DONE+1306573.2ms; END+1306584.1ms phasecompleted/committedtrue/statusidle.
Global and DeepSeek active/waiters all0.

Read-only SQLite checks: before this turn one opening assistant/zero user/zero turns;
after it two assistants (including the opening)/one user/one scene_dialogue_turn.
The new assistant contains narrative and preserved primary reasoning. The runtime
head stayed at revision0: this real settlement produced no applied runtime mutation.
Effect diagnostics report items0/affinity entries1/combat enemies0; entry count is
not proof of a nonzero state delta. Do not manufacture a revision increment for a
no-change turn. Three SQLite regression cases (recovery in stage1,2,4) separately
verify a real +5 custom-state delta, revision0→1, one user/assistant/turn/settlement/
commit, and value55 (not60) after reopening the database.

The first successful primary has roles[system,assistant,user], historyCount1,
currentInputCount1, round1, and exactly the same three hashes as the frozen matrix.
Only accepted prose enters subsequent stage history, without an empty primary
assistant or the temporary recovery instruction. UI inspection confirmed the new
narrative and preserved ReasoningBlock. A later accessibility snapshot confirmed
the five new options, so the visible old opening options were not mistaken for the
new settlement options. The user independently confirmed COMMIT_DONE and6036 chars.

### Cancellation and UI diagnostics

- Reasoning Stop: requestscene-1790944515616487-4/generation4, attempt1 accepted8063
  reasoning chars/content0 before cancellation. GenerationCancelledException,
  retryDecisionfalse; no recovery, settlement or commit. END phasecancelled,
  committedfalse, idle, all permits/waiters0.
- Recovery Stop: requestscene-1790944554925358-6/generation6. Primary completed with
  reasoning41250/content0/length+DONE; one recovery(cap5712) started. Stop at1.567s
  cancelled its first HTTP attempt before content, retryDecisionfalse. No recursive
  recovery, settlement or commit; END cancelled/committedfalse/idle/permits0.
  SQLite still held exactly the same three messages and one committed turn afterward.
- Deterministic cancellation also injects late reasoning/content callbacks after Stop
  during recovery, verifying no state application, durable commit, memory dispatch,
  error card or scheduler leak.
- UI transition tests preserve visible/expandable reasoning, show the localized
  writing-story status with thinkingNotifier=false, then stream prose into the same
  StreamingBubble. Tested at320/390/1024px without layout exceptions.
- GTK `impl_get_NActions` and `impl_SetTextContents` criticals in the user's console
  came from this agent's accessibility probes against nodes without those interfaces,
  after the successful turn. They are not LLM/commit failures. Probes were corrected
  to check advertised interfaces; the subsequent recovery Stop used the actual action
  node. GTK's EditableText setter did not change the field despite reporting true;
  no successful request is attributed to that diagnostic setter. Cancellation traces
  identify separate OPTION_INTENT requests, not duplicate sends from the success turn.

### Final verification and Git

- Targeted eleven-suite run:286 passed; final responsive/session suite:27 passed.
- Final full `flutter test`:2870 passed,1 skipped, all tests passed (isolated worktree).
- `dart format .`:704 files,0 changed. `flutter analyze`:No issues found.
- `git diff --check`:clean. Production diff reviewed for bounded recovery,
  cancellation identity, existing prose budgets, history/settlement/commit ownership
  and diagnostic privacy. No dependency/schema/version/asset changes.
- Full tests and SQLite integration tests ran in the isolated worktree with fixture
  databases. No real Adventure data was cleared or restored for verification.
- Commit/push receipt and final HEAD equality/clean status are recorded in the final
  user response after those operations complete; this report does not prewrite them.

The upstream internal cause of a natural stop with reasoning but no final content
remains outside the evidence boundary. One observation per matrix cell cannot establish
a deterministic effort threshold. A recovery can still fail with its real error class;
it is bounded and preserves the previous presentation/commit cancellation rules.
