# Context management audit and 300-turn pressure test

## Baseline and scope

- Baseline: `main` at `326726b` before this audit's worktree changes.
- Scope: Runtime HEAD/archive, SceneState, summaries, World Context,
  PromptCompiler/ContextOrchestrator, ContextTrace, and branch isolation.
- Excluded by design: vector database, embeddings, FAISS/Chroma, and changes
  to the Frozen Baseline / Runtime HEAD / ContextOrchestrator principles.

## Automated evidence

`test/unit/context_long_story_stress_test.dart` commits 300 transactional turns
against a real SQLite database. The arc has four locations, three companions,
Eileen's death at turn 100, an active-to-resolved relic task, 300 Runtime HEAD
revisions, and a divergent faction fact on a cloned branch. It verifies that:

- the root HEAD remains at revision 300 while the child reaches 301;
- a dead character is absent from the final SceneState and remains `dead` in
  the root Runtime HEAD;
- root and child SceneState, overlays, and faction facts are isolated;
- only 12 recent messages are projected, historical retrieval survives, a
  relevant world entry is selected, and estimated context stays bounded.

The targeted command passed with 51 tests:

```text
flutter test test/unit/narrative_runtime_test.dart \
  test/unit/llm_helper_thinking_policy_test.dart \
  test/unit/database_and_repositories_test.dart \
  test/unit/context_long_story_stress_test.dart
```

Existing repository tests additionally cover Runtime revision conflicts,
transaction atomicity, idempotent request IDs, malformed-row isolation,
no-op revisions, and branch clone/isolation.

## Fixed during this audit

### P0 — no open data-loss or cross-branch corruption defect found

No P0 finding remains in the exercised persistence path. Runtime commits use a
single SQLite transaction and an `expectedRevision` mismatch aborts the turn;
the archive query is branch-scoped and cannot write back into the HEAD.

### P1 — branch summary progress was read from branch 0 (fixed)

- Phenomenon: a non-root branch could use branch 0's `up_to_id`, skipping its
  own early messages when creating a summary.
- Root cause: `SummaryService.maybeSummarize` called
  `getLatestSummaryUpToId(adventureId)` without the captured `branchId`.
- Impact: branch summaries could omit facts and then feed incomplete history
  into the branch prompt.
- Reproduction: create a summary on branch 0, then start a branch with enough
  messages to summarize.
- Fix: pass `branchId: capturedBranchId`; regression coverage is in
  `llm_helper_thinking_policy_test.dart`.

### P1 — explicit and legacy Runtime changes could collide (fixed)

- Phenomenon: a canonical `runtime_state_changes` affinity update and legacy
  `affinityChanges` for the same character/path produced a duplicate proposal.
- Root cause: `_mergeRuntimeDrafts` concatenated both lists, while
  `RuntimeStateValidator` correctly rejects duplicate entity/path writes.
- Impact: a valid scene turn could fail atomically rather than committing its
  canonical Runtime fact.
- Reproduction: submit an explicit affinity increment and a legacy affinity
  effect for the same character in one `SceneDialogueCommit`.
- Fix: explicit draft entries take precedence; legacy compatibility entries
  with the same entity/path are suppressed. The repository regression asserts
  the canonical `+5`, rather than a duplicate or legacy `+10`, is persisted.

### P1 — actual runtime policy was not budgeted (fixed for normal policy size)

- Phenomenon: the orchestration budget reserved a fixed 800 tokens instead of
  the actual system/runtime policy size.
- Root cause: policy assembly happens in `PromptBuilder`, but only a constant
  was charged in `ContextOrchestrator`.
- Impact: long custom system prompts could crowd out optional context without
  a corresponding trace entry.
- Fix: `PromptBuilder` passes `TokenEstimator(prompt).tokens`; the orchestrator
  reserves it before persona, summary, and history and reports
  `runtime_policy` in `ContextTrace`.

### P2 — ContextTrace is now actionable

Trace now records Runtime selected count and each persisted world-entry filter
reason (`duplicate`, `irrelevant`, or `token_budget`) in addition to existing
token counts, summary truncation, history count, archive activation, and
conflict rules. The trace continues to be persisted in turn diagnostics.

## Open findings

### P1 — SceneState is not fully derived from scene output

- Phenomenon: location is synchronized from `GameState.currentScene`, but
  time, character states, unresolved events, and goal lifecycle are carried
  from the previous projected state. Present characters are only intersected
  with the host's pre-existing participant IDs.
- Evidence: `ChatEngine` builds `committedSceneState` from
  `_promptBuilder.lastSceneState` and only overwrites location/presence.
- Impact: after an AI-described departure, death, or objective resolution,
  stale SceneState can continue to appear in prompts unless some other host
  path independently updates it. The 300-turn test validates persistence once
  state is supplied; it does not prove the model-output-to-SceneState extractor
  exists, because it currently does not.
- Reproduction: have a response state a companion left or a goal was completed,
  then inspect the next prompt's SceneState without manually changing host
  presence.
- Recommended repair location: introduce a validated, explicit scene-state
  delta in the structured response/parser and apply it during the same
  `commitSceneDialogueTurn` transaction. Define precedence with Runtime HEAD:
  death/lifecycle is Runtime-authoritative; SceneState only represents current
  presence and local scene facts.

### P1 — WorldContext has a real semantic-recall gap

- Phenomenon: relevance is exact lower-cased substring matching against keys,
  location, and character names; content matching is also literal location
  containment.
- Impact: synonyms, indirect descriptions, aliases, paraphrases, and Chinese
  word segmentation differences can omit relevant lore. For example, an entry
  keyed `宵禁` is not selected for a player asking about `夜间禁行` unless another
  literal key/location happens to match.
- Reproduction: create a non-sticky lore entry keyed `宵禁`, then query only
  `夜间禁行`; it is filtered as `irrelevant`.
- Recommended repair location: first add curated aliases/normalized keyword
  expansion and audit hit/miss traces in `WorldContextBuilder`. This is a real
  quality defect, not evidence that a vector store is immediately required.

### P2 — Archive recall is intentionally narrow

- Phenomenon: `asksHistory` is keyword/regex triggered. Retrieval considers at
  most three current/named character entities, three changes each, then five
  reasons total; factions, locations, relationships, and unnamed historical
  entities are not candidates.
- Impact: questions such as “why did the gate close?” or “when did the White
  Guard split?” can miss the relevant non-character commit. The five-fact cap
  can also drop causal sequence.
- Recommended repair location: expand deterministic entity resolution across
  known Runtime entity types and rank/deduplicate compact change summaries
  before the final cap. Keep it branch-scoped and read-only.

### P2 — extreme mandatory prompts still need an explicit product limit

The actual runtime policy is now charged, but a policy plus current user input
larger than the model input window cannot be made safe merely by removing
optional context. The product should define a visible custom-system-prompt
limit or an explicit validation/error path; never truncate the current player
input silently.

## Direct answers

1. **Is it sufficient for 300+ Adventure turns?** The persistence and bounded
   context mechanisms are stable under the exercised 300-turn arc, and the
   fixed defects remove two concrete branch/commit failures. It is not yet
   sufficient to claim reliable 300+ turn *narrative accuracy* in arbitrary
   stories, because SceneState evolution is incomplete and semantic recall is
   literal.
2. **Largest risk:** SceneState can retain departed/dead actors or old goals
   when the host is not separately updated, contradicting Runtime HEAD and the
   current scene.
3. **Real semantic recall defect?** Yes. It is deterministic literal matching,
   so synonym/indirect-expression misses are expected and reproducible.
4. **Need vector retrieval now?** No. First fix the explicit SceneState delta,
   add aliases/normalization, and measure trace hit/miss rates. Vector retrieval
   would not fix stale authoritative state and would add ranking/observability
   complexity before deterministic retrieval is exhausted.
5. **If vectors are later needed:** attach them to **World Context first**,
   where semantic matching is the identified gap and results remain immutable
   lore/facts. Keep Runtime Archive deterministic and revision/branch scoped;
   its main limitation is entity coverage and causal ranking, not embedding
   similarity.
