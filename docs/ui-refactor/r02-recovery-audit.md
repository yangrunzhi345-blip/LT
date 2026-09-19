# R02-D/E/F Recovery Audit

## Baseline and current completion

- Audit baseline: `755f75a63948d442c17f8ab276facf44ce5ef37a` on `main` (R02-A/B/C committed).
- Existing uncommitted R02-D work at takeover: `app_router.dart`, `session_app_bar.dart`, `chat_dialogs.dart`, new `model_select_page.dart`, `message_edit_page.dart`, and `r02d_navigation_test.dart`. These edits are preserved and reviewed as existing work.
- R02-D is partial: model, edit and inventory entry points have page implementations, but no completed lifecycle or navigation acceptance. R02-E and R02-F have no committed migration.

## Quality issues, duplication and potential bugs

1. `ModelSelectPage` immediately writes provider and model before regeneration, does not guard repeated submission, displays stale recent models after provider changes, and swallows errors with `debugPrint` only. The old caller's provider argument is ignored; the former one-tap provider switch becomes a two-step page without an explicit result contract at the call site.
2. `MessageEditPage` and the chat entry points use `dynamic` even though messages are typed `Message`. Its save path reports success even when the message is no longer in the active conversation. Message editing and regeneration logic are still coupled to `chat_dialogs.dart`.
3. `MainGate` calls `showApiSettings` after startup connection failure or missing key, despite the required normal app entry followed by a Settings hint. The same old dialog has numerous other callers. `SettingsScreen` already hosts `ProviderConfigSection`, so building a second provider form would duplicate persistence and testing logic.
4. `app_dialogs.dart` still owns long-form chat import/export UI; `prompt_settings_screen.dart` has two long-text preset sheets; `PromptPreviewModal` is a long-content sheet. Their controller lifetime, asynchronous import, keyboard behavior and copy/export affordances need page ownership.
5. `_ManagementDialog` is a fixed 500x400 list dialog and deletes the selection after dismissing itself, with no explicit bulk-delete confirmation or visible in-progress/error state. This is unsuitable at 320px and risks opaque partial failure.
6. `AppDropdown` still uses `OverlayEntry`; `AppSelect` uses a small picker sheet/menu; `PopupMenuButton` in chat/session/studio is a lightweight action menu. These are controls, not complex business workflows. Existing bare `AlertDialog` confirmations should converge on `AppConfirmDialog` where touched; destructive data actions must retain confirmation semantics.

## Removal inventory and repair plan

1. Conversation: finish one typed `ModelSelectPage`, one typed `MessageEditPage`, and reuse `InventoryScreen`; verify provider/model writes, page results, stale messages, and narrow viewports. Remove migrated model/edit/inventory sheets and unused helpers, then commit R02-D.
2. Settings/data: reuse `ProviderConfigSection` through dedicated settings pages; replace the startup API popup with a non-blocking Settings indication. Move chat import/export and prompt preset import/export/preview to pages without changing repository or LLM write paths. Verify connection/save and data import/export; commit R02-E.
3. Sidebar/final: replace `_ManagementDialog` with `ConversationManagePage` and typed selected IDs; confirm bulk deletion before changing data. Classify every remaining `showDialog`, `AlertDialog`, `showModalBottomSheet`, `Dialog`, `PopupMenu`, and `OverlayEntry` occurrence by interaction purpose, migrate complex flows or explicitly document justified lightweight controls and confirmations. Add `test/widget/r02-final-navigation-test.dart`, run formatter, analyzer and full tests, publish the final acceptance inventory, and commit R02-F.

## Scope and acceptance

No database schema, provider persistence semantics, LLM protocol or top-level section architecture changes. The three requested commits remain separate and are not squashed. Every new or changed mobile page must pass viewport tests at 320x568, 360x640, 390x844 (and the project-wide responsive matrix when appropriate); no complex business process may remain in a Dialog or BottomSheet. The final report must identify all remaining lightweight modals by file and purpose rather than claiming a zero-modal application.
