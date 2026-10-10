# Character generation budget regression audit

Acceptance mode: Integrated Single-Agent Full-Cycle (user requests continuous audit, conditional repair, acceptance and delivery).
Status: ACCEPTED — Integrated Acceptance; local production-chain regression gates pass. Real model / device verification remains pending.

## Baseline and scope

Initial clean HEAD: b060462fd98bdf4af72da9cd106287981f3af7c8 on work.
Initial cached origin/main: 12ed66f7f2d160c4aabb6a0c7e50965059266119.
Fetch revealed production main f7c1dd44b98c18467f70aa1c68dcf067ad5d4c92; fast-forwarded without losing changes. Audit and regression run against that production baseline.

Scope: Part generation target/acceptance budget, actual aggregate commit accounting, persistence/import/association and downstream compression/assembly regression. Preserve historical fixes 20bc1ba / 3228414. No capacity expansion, JSON truncation, automatic adoption of compressed text, unrelated refactoring or release.

## Confirmed code finding / reproduction gate

7c2d7d9 added PartGenerationValidator targetBudget hard rejection and min(estimatedLength, remainingBudget) request authorization. Thus a 1201-unit valid body for a 1200-unit target is rejected before saving despite aggregate spare capacity. Production SQLite/coordinator boundary tests are added BEFORE repair to establish differential evidence.

## Repair requirements

Separate the prompt's desired Part target from the actual resource budget available to this replacement attempt. Accept complete, structurally valid bodies within remaining aggregate budget and the unchanged 3000-unit Part transport guard. Limit all generated aggregate content to the persisted generation target, still below the 20000 nominal / 24000 absolute character boundaries. Final aggregate enforcement remains atomic in the SQLite commit transaction, excluding the replacing Part and counting decoded UTF-16 text once. Concurrency may reject a late overspend safely; never overwrite confirmed siblings or revisions.

Expose actual remaining budget and hard acceptance limit in prompts; retries remain finite/configurable and target only failed Parts. Resource compression failures must stay explicit and cannot be masked by budget relaxation. Keep safe reference extraction and separate generation / optimization states.

## Validation gates

Production coordinator + real SQLite boundaries 1199/1200/1201/1260/1300/1320 with spare and exhausted budgets; totals 8000/12000/16000/20000; aggregate overrun, independent retries, mixed JSON/Unicode, malformed output, reload, legacy import, world/multiple character assembly, compression publication and recovery. Reuse existing production integration and Widget tests where they already cover these paths. Negative mutation of the soft target fix must make the new regression fail.

Required format, analyze, full Flutter tests, diff check and supported build. External model responses are synthetic; no claim about real model success rate or Android device behavior. ACCEPTED requires all local gates, zero unresolved BLOCKER/MAJOR. Commit only task files and normal push to origin/main after acceptance, followed by fetch and equality check.

## Additional proven lifecycle defect

Production port → real SQLite → LibraryRepository → capacity validation → reimport → readiness boundary probes found alias duplication. ResourceAdventureView mirrors description into background (1bc51ec). LegacyResourceMapper.take returns after consuming only the winning alias (9beebae); equal background is consequently saved in fallback Parts. An 8000-unit card becomes 16000 after one roundtrip. ResourceIntegrityValidator._cardBodyLength (0e0d16e) also counts both alias spellings: a valid 16000-unit projected card is rejected as 32000 before reimport. These are older defects, not introduced by 7c2d7d9.

Repair scope expanded within the authorized lifecycle audit: consume equal aliases in the mapper and count equal description/background once in integrity validation. Distinct authored alias text stays preserved and charged; no database migration, global text deduplication or retroactive rewrite of saved resources. Tests cover 8000/12000/16000/20000/24000 import, library parsing, optimization-invalid/body-valid independence, reimport and adventure freeze; equal/different aliases and 24001 rejection.

## Integrated Review and invariant checks

- Production DI (`riverpod_providers.dart:537–564`) supplies the SQLite budget reader and revision capture boundary to the actual coordinator; soft targets are not confined to tests.
- `PartGenerationRequest.maximumAcceptedCharacters` is min(actual remaining resource budget, 3000). Target remains min(planned Part size, remaining actual budget). Null remaining is reserved for callers without persisted planning; production persisted blueprints supply actual budget.
- `commitPartContent` is unchanged: actual decoded non-deleted/non-archived other-Part text is summed under the same transaction as CAS body write, revision capture and completion. A losing concurrent attempt cannot spend the same capacity, create a partial revision or overwrite a manual edit. Replacement excludes its own prior body.
- No change to ResourceLimits: generation targets 1000–20000; accepted card body up to 24000; overflow in existing unified trees still requires protected compression/assembly. Resource validation still rejects 24001, including identical aliases whose real text is over capacity.
- No JSON truncation, destructive migration, silent compression adoption or forced ready state. Distinct alias values stay preserved. Previously persisted duplicated Parts are not automatically deleted or rewritten; original user snapshots remain intact.
- Retry scheduler unchanged: configurable `maxRetriesPerPart` (default 2), dispatch accounting before attempts, durable failure convergence, completed-Part exclusion, source-token CAS and current-attempt guards. Every attempt re-reads real remaining budget. Prompt stays independent of ordinal; includes target, remaining aggregate and acceptance ceiling.
- 20bc1ba safe reference clamp is unchanged and exercised with ~50k worldview through production coordinator; 3228414 body-generation/optimization labels remain separate and are exercised by Studio Widget suites plus saved-body/invalid-optimization import probes.

## Regression coverage matrix

External model output is the only synthetic boundary in generation/compression tests. Production services, parsing, SQLite writes, snapshots, library projection, readiness and adventure/session persistence remain real. The production Adventure test also runs real HTTP/SSE transport against a loopback response server; this does not establish real external-model performance.

| Required case | Evidence |
| --- | --- |
| Part equals target / +1 / +5–10% | SQLite coordinator matrix 1199/1200/1201/1260/1300/1320, spare vs exactly 1200 remaining |
| Aggregate equals generation target | Production generateAllParts at 8000/12000/16000/20000; plan, actual, snapshot and ready agree |
| Aggregate overspend | Concurrent 2100-unit outputs for 8000 target; only 6300 committed, one failed; existing atomic commit overrun test |
| Absolute boundary | Actual 24000 ready vs 24001 protected compression; card integrity 24000 accepted vs 24001 rejected |
| Valid JSON and multilingual text | JSON body with Chinese/Japanese/Korean/English, emoji, newline/Markdown and literal escapes; decoded body persisted unchanged |
| Invalid structure | Malformed NDJSON independent retry; decoder/parser/identity/allowlist suites |
| Optimization fails, body valid | Long imported body produces separate invalid Section verdict; saved content and subsequent freeze stay valid |
| Failed Part independent retry | Two failed attempts, three siblings completed unchanged; explicit retry saves once; repeated retry of completed Part rejected |
| Save and disk reload | Close/reopen SQLite, full body totals unchanged, readiness rebuild succeeds |
| Existing card reimport | 8000/12000/16000/20000/24000 via card parser → port → library → integrity → port → freeze, no duplicate count |
| Large worldview generation | worldview_reference_generation_test with bounded ~50k reference and historical edge cases |
| Multiple character association | Production world/two-character/NPC bindings and frozen adventure |
| Compression then adventure conversation | Real DI review/adoption → ready → freeze → unique chat session; loopback HTTP/SSE turn validation |
| Preparing recovery | Interrupted readiness, worker restart, >4 jobs, candidate insertion rollback, finite failure exhaustion, explicit retry |

## Validation record

- Pre-repair Part production probe: FAIL as intended, output 1201 rejected for target 1200 despite 8000 remaining.
- Pre-repair import probe: FAIL as intended, 8000 became 16000 after roundtrip; 16000 projected card rejected as 32000.
- Initial narrow budget/parser/prompt run: PASS 40.
- Lifecycle/history run: PASS 147. Later alias/import production + mapper + capacity run: PASS 51. These runs overlap; counts are not summed into a unique test total.
- Negative mutation probes: restoring each production-baseline Part validator / alias mapper / card capacity validator makes its new production regression FAIL (exit 1). All three repaired files restored in finally blocks.
- An intermediate full test run failed an existing prompt-ordinal invariance test after adding an ordinal-specific retry sentence; remove that sentence and preserve the invariant. The interrupted run is not a PASS.
- Final format: PASS, 847 files, 0 changed.
- Final analyze: PASS, zero issues, Flutter 3.44.0 / Dart 3.12.0.
- Linux debug build: PASS at `build/linux/x64/debug/bundle/lt_dialogue`. Initial link failure was missing isolated GStreamer/GLib search paths; command-only LIBRARY_PATH configuration resolved it.
- Environment setup used official pub.dev because storage.flutter-io.cn was denied by the proxy. Original dependency versions were preserved; generated localization and lockfile side effects were restored to the clean production baseline. No dependency/localization changes are included.
- Final `flutter test --no-pub --reporter expanded`: PASS 3686, SKIP 2 existing environment-specific cases, FAIL 0; exit 0, 11m12s. Skips are opt-in real TTS synthesis and Chrome-only Web backend behavior. No test was removed or newly skipped.
- `git diff --check`: PASS. Final Integrated Review: BLOCKER 0, MAJOR 0. All source mutations restored; the final full suite runs repaired production files.
- Delivery: one Conventional Commit for the task, normal push of HEAD to origin/main, followed by fetch and equality verification; exact commit and push result are recorded in the final response / Git log.

## Limitations

No external model credentials, device database or Android device was supplied. Real model adherence/success rate, live imported user assets and device generation/playback/conversation remain pending real-device validation. Synthetic regressions prove bounded local service behavior, not model quality. Existing already-duplicated stored resources are preserved rather than destructively migrated; any such user assets require review of their original text/revisions. Capacity accounting deliberately uses decoded Dart UTF-16 units (not Chinese-only or grapheme counts), now stated in generation prompts.


## Changed files and impact

Production (6 files):

- `lib/domain/resources/resource_generation_protocol.dart`: explicit remaining aggregate budget and bounded acceptance ceiling.
- `lib/application/resources/part_generation_coordinator.dart`: propagate the fresh remaining budget to each request; desired target remains bounded.
- `lib/application/resources/part_generation_prompt_builder.dart`: distinguish target, actual remainder and hard ceiling; explain decoded UTF-16 accounting.
- `lib/application/resources/part_generation_validator.dart`: accept complete bodies over the estimate only within actual remainder and unchanged transport bound.
- `lib/application/resources/legacy_resource_mapper.dart`: consume equal recognized aliases once, retain distinct text.
- `lib/services/resource_integrity_validator.dart`: exclude only the equal projected description/background mirror from duplicate capacity charge.

Regression (6 existing test files extended):

- `test/application/resources/generation_aggregate_budget_sqlite_test.dart`.
- `test/application/resources/adventure_start_sqlite_production_test.dart`.
- `test/application/resources/legacy_resource_mapper_test.dart`.
- `test/application/resources/part_generation_prompt_builder_test.dart`.
- `test/application/resources/part_generation_validator_test.dart`.
- `test/services/character_card_capacity_test.dart`.

This report is the thirteenth task file. No resource limit, database schema, compression/adoption/assembly source, UI source, dependency or localization change is included. 24 additional test cases were added; existing capacity rejection and malformed-output assertions are retained.
