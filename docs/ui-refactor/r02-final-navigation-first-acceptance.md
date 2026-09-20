# R02 Final Navigation-first Acceptance

## 1. Recovery Baseline

- Repository: `yangrunzhi345-blip/LT`; branch: `main`.
- Recovery start HEAD: `02ad59695b8bc19dce8f4affc42b7326c24f8fc7`.
- The takeover worktree was clean. The interrupted work already existed in the
  three commits `86c6511`, `0d476f0`, and `02ad596`.
- Recovery implementation HEAD: `dce9953`.
- Initial assessment: R02-D/E/F page migrations were largely wired to production
  entry points, but the COMPLETE verdict was not supportable because dropdown
  overlays and message persistence defects remained.

## 2. Interrupted Work Recovered

The existing route-based model selection, message editing, inventory, settings,
data transfer, prompt preview, conversation management, resource review, and
scene selection pages were retained. Recovery work completed rather than
reimplemented those flows:

- converged the legacy dropdown facade on the `LtSelect` implementation;
- made edit/regeneration history changes durable and branch-local;
- made provider/model switching one coherent persistence operation;
- added failure/loading guards and invalid-regeneration checks;
- protected JSONL import after stable message IDs became durable;
- extended regression tests for the repaired behavior.

## 3. R02-D Result

- Model switching and regenerate-with-model use `ModelSelectPage`.
- Provider/model configuration is saved once; a missing preceding user message
  is rejected before persistence.
- Message editing uses `MessageEditPage`, awaits the repository operation, and
  reports errors without closing the route.
- User-message edits and reply regeneration atomically truncate persisted branch
  history before a replacement request starts.
- Inventory reuses `InventoryScreen`; no sheet/page duplicate remains.

Result: complete.

## 4. R02-E Result

- Startup enters the application normally and provides a non-blocking Settings
  action when configuration is missing or connectivity fails.
- API, model, advanced, import, export, diagnostics, prompt preset transfer, and
  prompt preview workflows use pages and their existing providers/services.
- API key, endpoint, provider, model, and validation behavior remain on the
  existing settings persistence path.

Result: complete.

## 5. R02-F Result

- Sidebar conversation management uses `ConversationManagePage`; the old fixed
  `_ManagementDialog` is absent.
- Complex resource, review, recycle-bin, preset detail, detected-status, dice,
  and batch-candidate workflows use routes or inline UI.
- All production legacy dropdown callers now reach the shared `AppSelect`
  picker kernel; `AppMultiSelectDropdown` uses `MenuAnchor` on desktop.
- Final source scan found no production `OverlayEntry`.

Result: complete.

## 6. Gemini / Interrupted Implementation Defects

Only defects confirmed from code and tests are recorded:

| Severity | Defect | Resolution |
| --- | --- | --- |
| BLOCKER | Two reachable custom `OverlayEntry` dropdown implementations contradicted the R02 plan | Replaced by `AppSelect`/`MenuAnchor` facade; zero remaining occurrences |
| MAJOR | Message edit/regeneration truncated memory but not SQLite | Added branch-local repository transactions and stable client IDs |
| MAJOR | Provider/model selection could persist a half-update | Added one atomic `setProviderAndModel` path |
| MAJOR | Orphan assistant regeneration saved settings before silently failing | Validate the preceding user message before saving |
| MAJOR | Stable IDs could make multi-row JSONL imports collide | Use a batch ID plus record index and verify both rows reload |
| MINOR | Desktop popup anchoring and multi-select width compatibility were incomplete | Use Overlay-relative geometry and forward `menuWidth` |

Historical regeneration does not rewind game/runtime state. That behavior
predates R02, and the current schema lacks a complete per-message state snapshot
for a safe rollback. It is a separate domain design item rather than an open
R02 navigation defect.

## 7. Removed Modal Inventory

The complete R02 result removes these complex modal carriers:

| Area | Removed carrier | Navigation/inline replacement |
| --- | --- | --- |
| Conversation | model switch/regenerate sheets | `ModelSelectPage` |
| Conversation | message edit dialog | `MessageEditPage` |
| Conversation | inventory sheet | `InventoryScreen` |
| Conversation | detected-status and dice dialogs | page routes |
| Settings/startup | API/model/advanced dialogs and startup blocker | settings pages plus non-blocking action |
| Data/prompt | import/export/preset/preview modals | dedicated pages |
| Sidebar | `_ManagementDialog` | `ConversationManagePage` |
| Resources | creation, trash, long review, candidate-list modals | creation/review/trash/selection pages |
| Templates | long preset detail dialog | `PresetSceneDetailPage` |
| Controls | two custom dropdown `OverlayEntry` implementations | `AppSelect` popup route / bounded picker and `MenuAnchor` |

Compatibility function names such as `showEditDialog`, `showImportDialog`, and
`_showCreateDialog` remain where they now push routes; they do not construct a
business dialog.

## 8. Remaining Allowed Modal Inventory

Final scan command:

```bash
rg -n -U "show(Dialog|ModalBottomSheet|GeneralDialog)|AlertDialog|SimpleDialog|Dialog\\(|PopupMenuButton|OverlayEntry" lib --glob '*.dart'
```

`OverlayEntry`: 0. The remaining modal controls are:

| Location | Purpose | Admission reason |
| --- | --- | --- |
| `core/widgets/app_confirm_dialog.dart` | shared yes/no confirmation | canonical no-input confirmation |
| `resource_studio_page.dart` | create section title | one-field naming input explicitly allowed by the plan |
| `resource_studio_section_controls.dart` | rename section | one-field naming input explicitly allowed by the plan |
| `assembly_readiness_dialogs.dart` | short readiness block and stale-version choice | short read-only notice / confirmation explicitly retained by the plan |
| `scene_batch_import_page.dart` | concise vs detailed import mode | bounded two-option B-class choice explicitly retained by risk R-N3 |
| `app_select.dart` | mobile single-value picker | control-level bounded picker, not a business workflow |
| `app_dropdown.dart` | mobile multi-value picker | control-level bounded picker, not a business workflow |
| `chat_dialogs.dart` | message quick actions | lightweight action menu; editing itself pushes a page |
| `resource_studio_section_controls.dart` | section context actions | lightweight `PopupMenuButton` |
| `session_app_bar.dart` | session overflow actions | lightweight `PopupMenuButton`; complex actions push pages |
| `quick_menu.dart`, `status_dropdown.dart` | compact context actions | lightweight `PopupMenuButton` |

Note: the preset-scene card action menu was later converged onto the shared
`AppActionMenu<T>` UI-Foundation control (no raw `PopupMenuButton`); see
`docs/ui-refactor/r02-unified-actions-and-generation-navigation.md`. The four
remaining `PopupMenuButton` sites above are the tracked migration backlog.

## 9. Mobile Regression

- R02-D pages are covered at `320x568`, `360x640`, `390x844`, `412x915`,
  `768x1024`, and `1280x800` with no layout exception.
- Final navigation tests cover the required phone matrix, long titles, increased
  text scale, route return behavior, and destructive-cancel behavior.
- Dropdown tests cover a 320 px mobile sheet, nullable selection, desktop
  anchoring, continuous multi-select, explicit menu width, and unbounded-scroll
  parents.
- Production dropdown callers are exercised by custom-attribute, settings,
  assembly, and adventure-wizard widget suites.

## 10. Full Regression

Final verification on 2026-09-20:

| Command | Result |
| --- | --- |
| `dart format .` | 542 files, 0 changes |
| `flutter analyze` | no issues found |
| focused R02 and affected-call-site suite | 128 passed, 0 failed |
| `flutter test -r compact` | 1830 passed, 0 failed |
| `git diff --check` | passed |

Added or updated regression coverage includes message edit/history truncation,
client ID restoration, JSONL ID uniqueness, coherent provider/model persistence,
invalid regeneration, adaptive dropdown behavior, and the affected production
dropdown interaction.

## 11. Final Verdict

**COMPLETE**

R02-D/E/F satisfy the navigation-first contract. No BLOCKER or MAJOR remains in
the accepted scope, no complex business workflow remains in a dialog/sheet, and
the remaining modals are limited to plan-approved confirmations, single-field
naming, short choices/notices, and control-level menus/pickers.
