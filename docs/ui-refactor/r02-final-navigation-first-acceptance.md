# R02 Navigation-first UI Migration Final Acceptance

## Baseline

- Repository: `yangrunzhi345-blip/LT`
- Branch: `main`
- Recovery baseline: `755f75a63948d442c17f8ab276facf44ce5ef37a`
- Conversation commit: `86c6511 fix(ui): recover and complete R02 conversation migration`
- Settings/data commit: `0d476f0 fix(ui): recover and complete R02 settings migration`
- Final phase commit message: `feat(ui): complete navigation-first migration`
- Scope: UI carrier and navigation migration only. No database schema, LLM protocol, persistence semantics, or top-level section architecture was changed.

## Recovery Audit Findings

The interrupted Gemini/previous-Agent implementation was not complete enough to accept:

1. `ModelSelectPage` and `MessageEditPage` were page shells without closed result/lifecycle contracts. Model selection could swallow errors and accept repeated submissions; message editing used `dynamic` and could report success for a stale message.
2. Model/provider state, regeneration results, stale messages, and route return values were not consistently handled.
3. Startup still invoked `showApiSettings`, so a missing key or failed connection could interrupt normal app entry with an API dialog.
4. Settings, chat data transfer, prompt preset transfer, prompt preview, and sidebar conversation management still depended on legacy dialog/sheet flows.
5. `_ManagementDialog` used a fixed `500 x 400` surface, closed before deletion, and had no explicit destructive confirmation, progress state, or visible error state.
6. The R02-B documentation claimed resource creation was migrated while `ResourceStudioPage` still contained `_ResourceCreationDialog`.
7. The remaining project-wide modal inventory had not been classified, so complex preview, multi-select, character-status, dice, and preset-scene flows were still hidden inside dialogs/sheets.

The detailed recovery baseline is recorded in `docs/ui-refactor/r02-recovery-audit.md`.

## Migration Summary

### Conversation

- Added typed `ModelSelectPage` results, duplicate-submit protection, visible failures, provider/model consistency, and regeneration completion handling.
- Added typed `MessageEditPage`; stale messages no longer produce false success.
- Replaced model switch/regenerate sheets, message edit dialog, and inventory sheet with routes and the shared `InventoryScreen`.
- Moved custom detected-status editing and dice checks to pages; dice results return through a typed route result.

### Settings and data

- Added `SettingsPage`, `ApiSettingsPage`, `ModelSettingsPage`, and `AdvancedSettingsPage` while reusing the existing settings sections and providers.
- Startup now enters the app normally and presents a non-blocking Settings action when credentials or connectivity are missing.
- Added page-based chat `ImportPage`/`ExportPage`, prompt preset import/export, and `PromptPreviewPage` without changing repository write paths.

### Sidebar and resources

- Added `ConversationManagePage` with live provider state, batch selection, explicit confirmation, disabled/progress state during deletion, and visible failures; removed `_ManagementDialog`.
- Reused `ResourceAiCreatePage` from Resource Studio and removed `_ResourceCreationDialog`.
- Converted the recycle bin to `ResourceTrashPage` navigation.
- Converted preset-scene long detail, AI worldview/card draft review, and scene batch candidate multi-select to routes with typed results.
- Consolidated destructive and overwrite confirmations on `AppConfirmDialog`.

## Removed Dialog Inventory

The following complex dialog/sheet workflows no longer exist as modal business processes:

| Area | Removed modal workflow | Navigation result |
| --- | --- | --- |
| Conversation | model switch and regenerate model sheets | `ModelSelectPage` |
| Conversation | message edit dialog | `MessageEditPage` |
| Conversation | inventory sheet | shared `InventoryScreen` |
| Conversation | detected-status editor sheet | full-screen route |
| Conversation | dice check dialog | `DiceCheckPage` |
| Settings | API/model/advanced settings dialogs | dedicated settings pages |
| Startup | automatic API settings dialog | normal entry plus Settings snackbar action |
| Data | chat import/export dialogs | `ImportPage` / `ExportPage` |
| Prompt | preset import/export sheets and prompt preview sheet | page routes |
| Sidebar | fixed-size `_ManagementDialog` | `ConversationManagePage` |
| Resources | manual/AI resource creation dialogs | shared creation pages |
| Resources | Resource Studio `_ResourceCreationDialog` | `ResourceAiCreatePage` route result |
| Resources | recycle-bin sheet | `ResourceTrashPage` |
| Resources | AI worldview/card long preview dialogs | `ResourceImportReviewPage` |
| Resources | scene batch candidate list dialog | `SceneBatchCandidateSelectPage` |
| Templates | long preset-scene detail dialog | `PresetSceneDetailPage` |

All affected data and controller calls remain in their original application/runtime boundaries; only the presentation carrier and route result protocol changed.

## Remaining Modal Inventory

The final source scan used:

```bash
rg -n -U "show(Dialog|ModalBottomSheet)|AlertDialog|SimpleDialog|Dialog\\(|PopupMenuButton|OverlayEntry" lib --glob '*.dart'
```

The remaining occurrences are intentionally lightweight and meet the R02 admission rules:

| Location | Purpose | Acceptance reason |
| --- | --- | --- |
| `core/widgets/app_confirm_dialog.dart` | shared yes/no destructive or overwrite confirmation | no business input; standardized and scroll-safe |
| `assembly_readiness_dialogs.dart` | one-action readiness block message | short read-only blocking feedback |
| `resource_studio_page.dart` `_SectionTitleDialog` | create section name | one-field naming input |
| `resource_studio_section_controls.dart` `_RenameSectionDialog` | rename section | one-field naming input |
| `scene_batch_import_page.dart` mode picker | concise/detailed choice | small two-option choice; no long content or resource selection |
| `app_select.dart` mobile picker | select one value | lightweight control interaction, bounded to 70% viewport |
| `chat_dialogs.dart` message menu | message quick actions | lightweight action menu; edit itself routes to a page |
| session/template/studio/chat `PopupMenuButton` uses | compact overflow actions | lightweight contextual menus |
| `app_dropdown.dart` `OverlayEntry` | legacy anchored single/multi-select controls | not a business workflow; retained compatibility debt and explicitly not counted as migrated |

Compatibility function names such as `showEditDialog`, `showImportDialog`, and `showCreateCharacterCardDialog` remain at some call sites, but their implementations now push pages rather than construct dialogs.

## Architecture Result

- New child flows use `AppRouter.push`/`pushReplacement`, preserving the project transition and reduced-animation policy.
- `/conversations/manage` and the Settings/data routes are registered in `AppRouter.onGenerateRoute`.
- Page results are typed (`ModelSelectionResult`, draft contracts, `PresetSceneDetailAction`, selected scene candidates, and dice message result).
- `ResourceStudioCreationDraft` now lives in the application contract layer and is reused by both creation and Studio flows.
- Preset detail receives a presentation DTO instead of importing `lib/data`; the presentation boundary architecture test passes.
- No complex business process remains in a Dialog or BottomSheet after the final source scan.
- The legacy `AppDropdown` overlay remains a known control-level cleanup item. It does not block R02 navigation-first acceptance because it contains only selector UI, but future component work should converge its remaining call sites on `AppSelect`.

## Responsive and Regression Result

New and updated widget coverage includes:

- Required `test/widget/r02-final-navigation-test.dart`: 6 tests covering `320 x 568`, `360 x 640`, `390 x 844`, and `412 x 915`, long conversation titles, `1.3` text scale, real SQLite conversations, route navigation, and destructive-cancel behavior.
- Preset-scene detail: long content at 320 px and typed action result.
- Resource import review and batch candidate selection: long content at 320 px and typed selected candidates.
- Existing resource Studio, recycle-bin, assembly readiness, custom attribute, conversation, settings, and resource navigation suites were retained and updated only where the migrated control type or label changed.

Final verification on 2026-09-20:

| Command | Result |
| --- | --- |
| `dart format .` | 542 files checked, 0 additional changes |
| `flutter analyze` | no issues found |
| `flutter test` | 1824/1824 passed |
| `git diff --check` | passed |

## Acceptance Decision

R02 Navigation-first UI Migration is complete for the audited scope. Conversation, Settings/data, Sidebar, and all discovered complex project-wide modal workflows now use navigation pages; remaining modal/overlay entries are limited to the documented lightweight control, confirmation, naming, or short-feedback cases.
