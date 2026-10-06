# Assistant presentation payload repair

Status: ACCEPTED
Acceptance Mode: Integrated Single-Agent Full-Cycle

## Baseline and scope

HEAD / origin/main: 359f6c381a6e0fa5d336cfcba01f4d08ef232ec7; clean main.
Original repair authority: attached final repair specification; no commit / no push at the repair acceptance checkpoint. The subsequent user instruction “提交到github” explicitly authorizes committing and pushing the accepted changes.
Scope: frozen tracked authority → assistant presentation → persisted message → parser → existing renderer.
No schema, freeze, CAS, candidate planner, header, inspector, runtime hub or UI layout changes.

## Current reality audit

ChatEngine normalizes model output at lines 1396 and 1410 before settlement.
The separator-only status helper is inconsistent with the formal parser but raw inline-tail input does not directly reach it on the normal path. Do not claim this hypothesis as the verified normal-turn root cause.
Verified opening path: ChatProvider seeds opening Message, then bootstrap commits runtime values and refreshes runtime cache. AdventureProvider.seedOpeningScene writes only scene/options; nothing attaches the bootstrap snapshot. This is a production authority-to-message break.

## Implementation and gates

1. Reproduce opening omission through real provider/bootstrap/SQLite reopen. Verify normal-turn input matrix against baseline.
2. Add one AdventureResponse rewrite primitive built on parse/canonicalize, preserving narrative and existing payload fields; merge local options/snapshot; strip raw custom status aliases and consumed deltas/evaluations, including empty authoritative snapshots.
3. Replace both ChatEngine helpers with one presentation rewrite authority. Keep tracked snapshot builder and validated runtime chain unchanged. Keep diagnostics to counts/types.
4. Run bootstrap before the new opening Message is seeded and before input opens. Read frozen config/current seeded runtime once and insert snapshot with the Message; untriggered definitions carry no invented values. Never refresh historical messages on load. Guard workspace switches across the bootstrap await.
5. Contract tests for all parser shapes, malformed/plain negative cases, production matrix with DB reopen, producer→renderer order, historical stability, bootstrap paths and history/TTS isolation.
6. Run specified targeted suites, format lib/test, analyze, full flutter test, diff-check, integrated adversarial review and restored mutation probes.

## Acceptance

All user requirements in attachment must have current-state evidence. BLOCKER/MAJOR must be zero. SQLite reopen and renderer tests must exercise real ChatEngine and repository; LLM transport alone may be scripted. Existing layout/header remain unchanged. Full test/analyze/diff-check pass. Report exact baseline, protocol divergence, actual root cause and tests. No commit or push during the repair stage; publication requires subsequent explicit user authorization.

## Integrated Review evidence (2026-10-06)

### BASELINE

- HEAD = origin/main = `359f6c381a6e0fa5d336cfcba01f4d08ef232ec7` after `git fetch origin`.
- Branch main; initial worktree clean. No user modifications overwritten.
- Baseline includes `359f6c3`, `27a7805`, `b686aff` as requested.

### ROOT CAUSE

1. **Verified missing snapshot:** `ChatProvider._startAdventureWithConfigUnlocked` called `AdventureProvider.seedOpeningScene` before `_runOpeningTrackedStateBootstrap`. `seedOpeningScene` persisted only `scene/options`. Bootstrap committed accepted state and refreshed the Runtime Hub cache, but never rewrote the seeded Message. Two new real provider/bootstrap tests failed on baseline with `customStatus == []`, both with bootstrap evidence and without it. The successful evidence case matches the reported Hub-value/body-empty behavior.
2. **Verified untrusted snapshot echo:** `_normalizeCustomStatusInAiContent` returned immediately when `customStatus.isEmpty`. Under `needsOptionRepair == false && optionsFromSettlement == false`, raw model `custom_status` survived even though authoritative definitions/snapshot were empty. Replacing only ChatEngine with HEAD while retaining the negative production regression reproduced the failure: `伪造状态 / 不可信` survived SQLite reload.
3. **Hypothesis ruled out for normal turns:** the old normalizer returned on `sepMatch == null`, but normal ChatEngine calls `AdventureResponse.canonicalize` both before and after the length guard. The new 13-case production matrix passed with the original HEAD ChatEngine, including inline-tail + narrative options. Therefore separator absence is a verified helper contract defect, not a demonstrated normal-turn cause on this baseline. No real-device database was supplied to identify which message in the screenshot took which path.

### PROTOCOL DIVERGENCE

- Formal Parser: canonical/variant separator, pure JSON with or without narrative, inline-tail JSON, fenced/repaired object.
- Old normalizer: first separator plus strict `jsonDecode`; no separator or empty snapshot returned original content.
- Old option injection: no separator appended a synthetic payload to the original input, risking inline/pure JSON becoming prose if called directly; strict decode failure discarded fields.
- Shared authority now: `AdventureResponse.rewritePayload` calls the formal `parse`; callers supply defaults/replacements/removals. Original payload fields survive unless explicitly locally owned. Plain prose stays prose without supplied structured presentation; malformed tails cannot become prose; removing all payload fields cannot resurrect the old payload.

### FIX / PRODUCTION PATH

- Normal turns retain `RuntimeStateValidator → TrackedStateSnapshotBuilder` unchanged.
- Both old helpers replaced by `_rewriteAssistantPresentationPayload`; final calls always provide resolved options and the validated per-turn snapshot, regardless of settlement/repair branch.
- Remove model `custom_status`, alias `custom_attributes`, consumed changes/evaluations before replacing with locally projected snapshot; explicit empty snapshot remains empty.
- Canonical output: narrative, one `---JSON---`, encoded merged payload (payload-only when narrative absent).
- Exact final string goes to `aiMsg.copyWith`, pending settled presentation, and real `commitSceneDialogueTurn`.
- New production tests close DatabaseService, create a fresh repository, reload SQLite messages, reparse, and feed the persisted Message directly into the unchanged AdventureMessageCard.
- Opening path now: freeze/seed entities → bootstrap commit/cache refresh → snapshot projection → opening message insert. No generated message is marked edited and no historical live-state refresh is introduced. Workspace-switch regression prevents seeding old opening text into a newly selected adventure.
- Count/type-only diagnostics: `[TrackedSnapshot]`, `[AssistantPayloadRewrite]`, `[AssistantMessageCommit][PREPARED/DONE]`; no prose/status values/credentials added to logs.

### INPUT SHAPES VERIFIED

Production matrix: canonical, inline tail, pure JSON with narrative, spaced separator, newline separator, each with narrative or settlement options; plain prose with repair. Every case verifies actual commit, no LLM error, request/settlement counts, options-source diagnostics, canonical persisted content, narrative/options/status, SQLite reopen, and no raw status/delta/evaluation echo.
Contract matrix additionally verifies payload-only, fenced/repaired JSON, payload field preservation, malformed/plain negative paths and empty authoritative removals.

### HISTORICAL SNAPSHOT / HEADER / LLM HISTORY / TTS

- Two real ChatEngine turns: later runtime value changes while the first message retains its original value after reopen. Its actual next-turn LLM assistant history contains narrative only.
- Opening tests: later runtime mutation, real adventure reload and duplicate seed attempt preserve original opening snapshot, including the original untriggered marker.
- Header, Inspector and Runtime Hub code/layout unchanged. Existing header/session tests validate no header tracked block while Inspector stays current.
- `llmHistoryProjection` and `streamingDisplayText` unchanged; contract/production assertions prove canonical output projects to narrative only.
- Producer→renderer regression verifies narrative Y < state Y < options Y at all six shared viewports (320, 360, 390, 412, 768, 1280 px).
- Same real persisted output is then rendered through NarrativeParagraphReadView; long-press/read-this-paragraph invokes the real ReadAloudController with an existing fake platform speech engine. Full spoken content equals narrative (ignoring speech planner sentence whitespace), excluding every status/option/JSON field.

### TESTS / PHASE GATES

- Baseline opening reproduction: 2 expected failures, empty customStatus.
- Baseline normal-turn matrix: 13 PASS (original ChatEngine temporarily inspected via controlled local replacement, restored byte-for-byte).
- Baseline empty-authority production negative: expected FAIL, raw model status leaked.
- Temporary mutation omitting the `custom_status` replacement: canonical rewrite contract FAIL as expected; source restored byte-for-byte.
- Specified seven suites + rewrite/bootstrap/opening suites: 181 PASS.
- Final new tests after negative/TTS/stale-workspace additions: 39 PASS.
- `dart format lib test`: PASS, no unrelated formatting changes.
- `flutter analyze`: PASS, no issues.
- `git diff --check`: PASS.
- Full `flutter test`: PASS, 3557 passed / 2 pre-existing environment skips / 0 failures, 3m13s. Skips: opt-in real neural TTS model validation (`LT_TTS_REAL_MODEL`) and Chrome-only backend registration. Neither skip was introduced or changed by this task.
- Final format verification: 840 files checked, 0 changed. Final HEAD/origin/main and diff-check reverified after all probes.

### FILES CHANGED

- `lib/models/adventure_response.dart`: shared rewrite primitive.
- `lib/engines/chat_engine.dart`: unified presentation rewrite and count diagnostics.
- `lib/providers/chat_provider.dart`: bootstrap precedes opening persistence; stale-workspace guard.
- `lib/providers/adventure_provider.dart`: opening snapshot uses existing builder and rewrite primitive.
- `test/unit/assistant_payload_rewrite_test.dart`: parser/rewriter contract and negative paths.
- `test/unit/turn_settlement_test.dart`: real producer/SQLite reopen/history/renderer/TTS coverage.
- `test/unit/tracked_state_bootstrap_wiring_test.dart`: opening persistence/history/staleness coverage.
- This spec/review record.

### FINDINGS / GIT STATUS

BLOCKER: 0. Full regression gate passed.
MAJOR: 0 unresolved implementation findings.
MINOR: 0 identified.
INFO: pre-fix messages missing historical snapshots are not reconstructed from current runtime; doing so would fabricate historical values. Screenshot-specific message provenance remains unavailable; do not assert it was definitely an opening message.
At the repair acceptance checkpoint: no commit, no push, HEAD unchanged; task modifications remained in the worktree. Subsequent publication is authorized by the user’s explicit “提交到github” instruction.

## Final requirement-by-requirement acceptance

| Attachment requirements | Authoritative completion evidence |
| --- | --- |
| 0 baseline and Git protection | fetch/status/rev-parse verified equal SHA, clean initial worktree, unchanged final HEAD; no reset/clean/stash/rebase/amend/commit/push |
| 1, 17, 18 existing layout, header, inspector/hub boundaries | no diff in renderer/header/Inspector/Hub; specified widget suites and full regression PASS |
| 2, 3 real cause and test blind spot | failed opening baseline tests; normal production matrix baseline 13 PASS rules out direct inline-tail separator hypothesis; empty-authority baseline negative FAIL |
| 4–7 unified rewrite and pure prose | one formal AdventureResponse primitive plus one engine caller; 22 contract cases cover accepted shapes, preserved fields, plain/malformed/empty payload |
| 8, 11–14, 22 production branch/shape matrix | 14 real production cases: five shapes × two option sources, repair, historical two-turn, empty authority, renderer/TTS; actual request counts and persisted settlement options-source diagnostic asserted |
| 9, 10, 28 persisted production closure | real ChatEngine and repository; final persisted content matches memory, DB closed/reopened, messages reloaded/reparsed; same output rendered by existing card |
| 15, 19 snapshot authority | snapshot builder/registry/validator files unchanged; committed settled/untriggered/out-of-range cases PASS; raw status echo negative PASS |
| 16 historical body | two-turn runtime change + SQLite reopen; opening live edit + actual reload; earlier persisted values remain unchanged |
| 20 history isolation | contract projection, production projection and actual second-turn LLM assistant history assertions PASS |
| 21 TTS isolation | streaming projection plus actual NarrativeParagraphReadView click → controller → fake speech backend, exact narrative-only non-whitespace content PASS |
| 23 renderer order | actual ChatEngine persisted Message, six viewport Y-order/no-exception assertions; original card widget tests unchanged and PASS |
| 24 opening semantics | successful bootstrap value, no-evidence untriggered row, later-history stability and stale-workspace tests PASS; existing bootstrap network-failure/no-definition/no-opening tests PASS |
| 25 diagnostics | counts/types only in engine snapshot/rewrite/prepared/committed markers; no sensitive story/state values |
| 26 commands and gates | specified targeted tests 181 PASS, final new tests 39 PASS, full suite 3557 PASS / 2 existing skips; format/analyze/diff-check PASS |
| 27 no scope expansion | four production files + three test files + this report; no schema/version/resource/runtime semantics/UI layout changes |
| 29 final report / no commit | all named report sections above, findings classified, Git changes retained uncommitted; no push |

All phase gates passed. Acceptance is integrated, not independent. No unresolved BLOCKER or MAJOR. The report does not claim a physical-device retest or that the unavailable screenshot message was definitely a prologue.
