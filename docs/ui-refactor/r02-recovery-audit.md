# R02-D/E/F Recovery Audit

## Baseline

- Recovery start: `02ad59695b8bc19dce8f4affc42b7326c24f8fc7` on `main`.
- Existing R02 commits: `86c6511` (conversation), `0d476f0` (settings), and
  `02ad596` (navigation-first final phase).
- The worktree was clean at takeover. The recovery changes were built on top of
  those commits and preserved their route/page implementations.
- Recovery implementation commit: `dce9953 fix(ui): recover and complete R02
  navigation migration`.

## Confirmed Defects

1. The previous COMPLETE verdict was invalid because `app_dropdown.dart` still
   contained two production `OverlayEntry` implementations. Multiple callers
   still reached them, contrary to the plan requirement that all legacy
   dropdown callers converge on the `LtSelect` kernel.
2. Editing an assistant reply changed memory only. Editing a user message or
   regenerating a reply truncated memory only. Reopening the adventure restored
   the old SQLite history and could show both the old and regenerated replies.
3. `ModelSelectPage` persisted provider and model in two separate writes. A
   failure in the second write left a half-updated LLM configuration.
4. Regeneration for an assistant message with no preceding user message saved
   the selected model and then silently did nothing.
5. Persisting stable `client_message_id` values exposed a latent JSONL import
   collision: imported rows previously used the current millisecond as their
   in-memory ID. A batch can create more than one row in the same millisecond.
6. During facade convergence, desktop menu anchoring needed Overlay-relative
   coordinates and the legacy multi-select `menuWidth` contract needed to be
   forwarded to `MenuAnchor`.

## Repairs

- `AppDropdown` is now a source-compatible facade over `AppSelect`; the
  multi-select variant uses `MenuAnchor`. Mobile pickers remain bounded control
  sheets, while desktop single-select uses Flutter's popup route. Production
  `OverlayEntry` usage is zero.
- Message rows now preserve stable client IDs. Repository transactions update a
  user message and remove later branch history atomically, or remove the
  regeneration range atomically. Memory is changed only after persistence
  succeeds.
- `MessageEditPage` awaits saves, blocks duplicate submission, keeps the page
  open on failure, and regenerates only after the edit/truncation transaction.
- Provider and model selection now uses one `saveLlmConfiguration` transaction.
  Invalid regeneration is rejected before any setting is saved.
- JSONL import IDs use one microsecond batch ID plus a record index.

## Verification

- Focused R02/navigation, responsive, dropdown, custom-attribute, assembly,
  repository, and settings tests: 128 passed.
- `dart format .`: 542 files checked, 0 changes.
- `flutter analyze`: no issues found.
- `flutter test -r compact`: 1830 passed, 0 failed.
- Final modal scan: 0 `OverlayEntry`; remaining dialogs, sheets, and popup menus
  all satisfy the admission rules in the R02 plan.

## Scope Boundary

Regenerating an older message retains the project's pre-existing game/runtime
state semantics. The schema has current runtime heads and change records but no
complete state snapshot tied to every message anchor, so a trustworthy
time-travel rollback would require a separate persistence design and migration.
R02 does not invent a partial rollback. This does not leave a complex modal or
break the navigation-first acceptance contract.
