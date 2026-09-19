# Phase 11 Final Independent Acceptance

Date: 2026-09-19  
Audited HEAD: `e51f31c2627fc353f61ea2e71ab7917b054b0b2a`  
Implementation commit: `2f9fdb8` (`fix(resources): recover and complete phase 11 after interrupted run`)  
Docs commit: `e51f31c` (`docs(status): record phase 11 recovery and completion`)  
Previous acceptance: **FAILED** in Round 1, Round 2, Round 3 and Round 4 (history preserved in `STATUS.md` and `phase-11-remediation-report.md`)  
Final verdict: **ACCEPTED**

This is an adversarial, independent acceptance. It does not restate the
execution report; it re-read the specification, the four failed audit rounds,
the recovery report, production code and tests, then actively tried to falsify
the Phase 11 claims with mutation experiments and functional probes in an
isolated worktree (`/tmp`, removed afterwards). No production or test file was
modified in the formal worktree.

## Baseline

| Item | Value |
| --- | --- |
| Branch | `main` |
| HEAD | `e51f31c2627fc353f61ea2e71ab7917b054b0b2a` |
| `origin/main` | `e51f31c` (ahead/behind `0/0`) |
| Worktree | clean except untracked `.agents/skills/*` + `skills-lock.json` (agent tooling, not Phase 11 source) |
| Toolchain | Flutter 3.44.8 / Dart 3.12.2 (previous rounds were blocked by a read-only SDK cache; this run executed the real gates) |

## Historical context

Phase 11 was rejected four times; the failures are not superseded here:

- Round 1 FAILED — P11-M1/P11-M2/P11-M3 (request race, active-generation status shadowed by stale readiness, `Part` term leak).
- Round 2 FAILED — P11-M4 (`source_changed` tree/legacy double projection).
- Round 3 FAILED — P11-R3-M1/P11-R3-M2 (Studio error term leaks, trash race) + P11-R3-C1 (MINOR, production-assembly coverage gap).
- Round 4 FAILED — P11-M1 (persisted `validationMessage` still leaked terms) + P11-M2 (MINOR, production-assembly coverage gap) + P11-V1 (verification blocked).

The interrupted run left the Round 5 remediation (P11-B1/M1/M2/C1/C2)
uncommitted; the recovery agent preserved and committed it. This review
validates that recovery on its merits.

## Acceptance criteria

| AC | Spec source | Evidence | Result |
| --- | --- | --- | --- |
| Single "新建" entry, choices are only AI/manual | `phase-11-library-ux.md` | `resource-create-button` defined once in `lib`; `resource_library_phase11_test.dart` "should expose only AI and manual creation choices" asserts `AI 创建`/`手动创建` and no `导入` | PASS |
| Paste/file/existing only in the AI creation reference step | `phase-11-library-ux.md` | Production test drives `粘贴参考内容` inside the AI dialog; choices sheet has no import entry; reference step is inside the creation flow | PASS |
| No overflow at 320/360/390/412/768/desktop, long CN/EN text, large font | `phase-11-library-ux.md` | `resource_library_phase11_test.dart` loops `requiredUiViewports` (320×568…1280×800); `resource_trash_sheet_test.dart` loops the same; production test adds 320×568 + textScale 1.6 + 240 keyboard inset, asserting `takeException() == null` and a real submit | PASS |
| Search / filter / detail / trash-restore / readiness each have a widget test | `phase-11-library-ux.md` | search+filter and card→detail in `resource_library_phase11_test.dart`; readiness (`已准备完成`) and detail in `resource_library_production_test.dart`; restore control in `resource_trash_sheet_test.dart`; restore race/lifecycle in `resource_trash_controller_test.dart` | PASS |
| No internal terminology in UI | `phase-11-library-ux.md` | Only display site of `validationMessage` is mapped (`resource_studio_section_controls.dart:221`); production test asserts no `Section`/`Part`/`ResourceTree` for empty section, missing body, oversize; `resource_library_phase11_test.dart` forbids `Part`/`revision ID`/`JSON`/`absolute limit`/`compression job`/`assembly revision`; presentation-string grep finds no raw internal terms | PASS |
| Old deep links redirect into the unified flow | `phase-11-library-ux.md` | `AppRouter.onGenerateRoute` handles `resource-library`/`resources`/`resource-studio` and no-param `studio`; independent probe verified all six redirects behave correctly (see F1 for the missing regression test) | PASS |
| P11-B1: manual creation persists a real empty body part in one transaction | Round 5 plan | `resource_creation_pipeline.dart:639` adds `ResourceTreePartDraft(title:'正文', content:'')`; `runInTransaction`→`createResourceTreeInTransaction`→`_insertTree` inserts sections and parts in the same transaction; production test creates/edits/saves/reopens worldview, character and NPC and reads the tree back | PASS |
| P11-M1: persisted validation messages go through the unified mapper | Round 5 plan | `resource_studio_user_message.dart:13-14` adds `ResourceTree`/`sections?`; `resource_studio_section_controls.dart:221` maps at the display boundary | PASS |
| P11-M2: reload only while mounted; detail future not completed early; search/filter preserved | Round 5 plan | `resource_library_screen.dart:234/256/264` `if (mounted) await _controller.load()`; `resource_library_detail_page.dart:46-53` pushes the editor then pops the detail after it closes; production test asserts search text and filter survive the round trip | PASS |
| P11-C1: production-assembly test does not replace the runtime | Round 5 plan | `resource_library_production_test.dart` uses `AppRouter.onGenerateRoute`, real `ProviderScope`, real SQLite; the only override is `llmGatewayProvider` (external model). `resourceLibraryRuntimeProvider` is defined once (`riverpod_providers.dart:529`) and assembled from real crud/studio/readiness providers | PASS |
| P11-C2: tests copy from the real MediaQuery (size/padding/viewInsets) | Round 5 plan | Production test `builder` uses `MediaQuery.of(context).copyWith(...)`, asserts `sizeOf == 320×568`, `paddingOf.top == 24`, `viewInsetsOf(dialog).bottom == 240`, then scrolls, types and submits | PASS |
| Phase 9 R2-M2 deferred item (tree/legacy dedup) | `phase-09-*` handoff | Remediated in Round 2; `library_repository_tree_union_test.dart` passes within the full suite | PASS |

## Production path review

- **Creation**: `ResourceLibraryScreen._startCreation` → `ResourceLibraryController.createManual` → `ProductionResourceLibraryRuntime.createManual` → `ResourceStudioRuntime.createManual` (sets `createInitialEmptySection: true`) → `ResourceCreationPipeline` → `ResourceTreeRepositoryImpl.runInTransaction`. Resource + Section + Body Part share one SQLite commit boundary (`_insertTree` inserts `_sections` then `_parts` on the same `txn`). No in-memory-only part.
- **Navigation**: library awaits its pushed detail route; the detail page pushes the Studio and pops only after the editor closes, so the library's awaited future completes only when editing is truly done. The remaining `pushReplacement` calls (`resource_studio_page.dart:655/672`) live in the Studio session picker, which is only rendered when no tree is loaded, i.e. not on the library-awaited route.
- **Wiring**: one definition each of `resourceLibraryRuntimeProvider`, `resourceTrashRuntimeProvider`, `libraryRepoProvider`; the library runtime is built from `resourceCrudControllerProvider`, `resourceStudioRuntimeProvider`, `assemblyReadinessRepositoryProvider`. No duplicate repository/provider fork and no test-only production wiring in `lib`.
- **Terminology**: the only `validationMessage` rendering in `lib/features` is mapped; no presentation string literal contains the forbidden terms.

## Mutation / adversarial tests

Executed in an isolated `/tmp` worktree at `e51f31c` (baseline production test 8/8 passed there); each mutation reverted afterwards.

| Mutation | Expected | Observed | Conclusion |
| --- | --- | --- | --- |
| A: remove the initial body part (`parts: const []`) | P11-B1 tests fail | 4 failures (3 per-type production tests + `resource_creation_pipeline_test`) | B1 regression has teeth |
| B: render raw `entry.validationMessage` in section controls | P11-M1 tests fail | 2 failures (empty section leaks `Section`, oversize leaks `Part`) | M1 regression has teeth |
| C: restore `pushReplacement` in the detail page | P11-M2 tests fail | 3 failures (`已准备完成` never appears because the library reloads before readiness is written) | M2 regression has teeth |
| D: `ProductionResourceLibraryRuntime.load` returns `[]` | P11-C1 production test fails | 5 failures (no grid, no detail after submit) | The production test truly drives the real runtime, not a stub |

Functional probes (temporary, not committed):

- Router probe: `/resource-library`, `/resources`, `/resource-library/<id>`, `/studio` (no params), `/studio?resourceId=`, `/resource-studio?sessionId=` — all six resolved correctly (6/6), so legacy redirects work; only the committed regression test is missing (F1).
- Trash probe: with real providers and SQLite, a resource appears in `ProductionResourceLibraryRuntime.load`, disappears after a production delete, and reappears after `resourceTrashRuntimeProvider.restore` — the data the unified library renders follows restore (F3).

## Findings

- **BLOCKER**: none.
- **MAJOR**: none.
- **MINOR — F1**: legacy deep-link redirects have no committed regression test.
  - ID: P11-F1
  - Severity: MINOR
  - Evidence: `AppRouter.onGenerateRoute` implements `/resource-library`, `/resources`, `/resource-studio` and no-param `/studio`, but no file under `test/` references those spellings; the only committed production-routing test uses `/library`.
  - Root Cause: Round 3/4 production-assembly coverage gap; the Round 5 plan required a production-assembly test (delivered for create/edit/save/readiness) but did not enumerate the legacy routes.
  - Impact: a future regression that deletes a legacy branch would not be caught by the suite. The behavior itself is verified working today.
  - Required Fix: add a widget test navigating `AppRouter.onGenerateRoute` for `/resource-library`, `/resources`, `/resource-studio`, and `/studio` without params, asserting the unified library/Studio destination. Non-blocking; may be scheduled as Phase 12 hardening.
- **INFO — F2**: the "missing body" M1 case (`content: ''`) produces a raw message (`正文 尚未生成正文`) that already contains no internal term, so that case alone cannot detect removal of the mapper. The empty-section and oversize cases do detect it.
- **INFO — F3**: no single production-assembly widget test mounts `ResourceTrashSheet` through `ResourceLibraryScreen` to SQLite. Restore is covered by `resource_trash_sheet_test.dart` (widget), `resource_trash_controller_test.dart` (unit) and `phase9_production_delete_wiring_test.dart` (provider-level production wiring), and the independent trash probe confirms the production library list follows restore.

No BLOCKER or MAJOR was found, and no acceptance criterion lacks implementation, test and production-path evidence.

## Verification (independently reproduced)

| Gate | Result |
| --- | --- |
| `dart format --output=none --set-exit-if-changed .` | 504 files, **0 changed** |
| `flutter analyze` | **No issues found (0 issues)** |
| Phase 11 targeted (`production_test` + `phase11_test` + `trash_sheet_test` + `section_controls_test` + resource_library feature + creation pipeline) | **89 passed / 0 failed** |
| Production-assembly test alone | **8 passed / 0 failed** |
| Full `flutter test` | **1600 passed / 0 failed / 0 skipped** |
| `git diff --check` | **clean** |

The execution agent's reported numbers were reproduced exactly; they were not taken on trust.

## Repository safety

The formal worktree was not modified by this review; mutation/probe work happened in a separate worktree that was removed (`git worktree list` shows only the main tree). Untracked `.agents/skills/*` and `skills-lock.json` were left untouched. No `reset --hard`, `clean`, or history rewrite was performed.

## Verdict

No BLOCKER and no MAJOR findings; every Phase 11 acceptance criterion has implementation, test and production-path evidence. The one MINOR (F1) is a non-blocking regression-coverage gap for behavior that works.

```
Phase 11: ACCEPTED
Phase 12: UNBLOCKED
```
