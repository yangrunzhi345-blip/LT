# Visual Polish / Art Direction Audit

Baseline: `5c8f5ae`. Scope: presentation only — typography, spacing, density,
surface hierarchy, navigation treatment, toolbar hierarchy, list-row composition,
empty states, borders, selection, button sizing, metadata formatting, responsive
visual tuning, micro-interactions.

Not in scope (unchanged): navigation authority, Runtime/SceneState authority,
resource lifecycle, controllers, Timeline persistence, LLM/streaming, SQLite
schema, Message→Turn mapping, Narrative serif fonts.

## Direction

Editorial Workbench: compact, quiet, dense, typographic, precise.
Hierarchy comes from typography, alignment, spacing and surface — not from
cards, pills, badges or colour.

## Before: observed problems

### Navigation
- The workbench sidebar defaults to the collapsed icon rail
  (`isMainSidebarExpanded = false`), so a ~950 px window showed a VS Code-like
  activity rail instead of readable workspace navigation.
- Selected state used a full `primaryContainer` block on `ListTile` and a filled
  circular `IconButton` background in the rail — loud, and the accent covered a
  large area.
- No intermediate layout: full sidebar or 64 px rail, nothing between.

### Resource Library
- Filters were `ChoiceChip` pills at < 1000 px and a vertical `ListTile` column
  at >= 1000 px — two unrelated visual languages.
- Status and Sort rendered as two grey `Chip`s, competing with the content.
- Search used the global `InputDecoration` (filled, large padding, 10 px radius).
- Rows were four stacked text blocks of nearly equal weight with no clear
  title / metadata / body / timestamp hierarchy, and the timestamp was the raw
  ISO string (`2026-09-21T18:27:27.765301`).
- Header stacked title + mode switch + actions + status/sort + search, so the
  top of the page was crowded while the list area looked empty.

### Trash
- The page header showed the title and the inner view header repeated the same
  title, with an isolated Refresh icon between them (title printed twice).
- Empty state was a left-aligned `Text` that read like a placeholder.

### Typography
- `_buildTextTheme` defined only 8 styles; `titleSmall`, `labelLarge`,
  `labelMedium` and `headlineSmall` fell back to Material defaults, so section
  headings and metadata were inconsistent across screens.
- Many headers used `FontWeight.w700`/`w800`; CJK at small sizes looked heavy.

### Surfaces
- `ColorScheme.fromSeed(surface: ...)` derived all container levels from one
  seed, so dark mode collapsed into a single indistinguishable grey block; light
  mode leaned on card borders instead of a real three-level ladder.

## Implemented changes

### Navigation treatment
- Added explicit sidebar modes driven by available workspace width:
  `full` (>= 1100), `compact text` (600–1099), `rail` (only when the user
  explicitly collapses, or on the narrowest layouts).
- Sidebar now defaults to expanded, so desktop navigation shows readable
  destinations instead of an icon rail.
- Selected state: 10% accent tint + 2 px leading indicator + accent icon +
  stronger label, at 32 px row height and 6 px radius — visible, quiet, small.
- Destinations are plain rows (no `ListTile` default padding/insets), sections
  separated by quiet headings and a divider before Settings.

### Typography hierarchy
- Defined the full text theme: `headlineSmall`, `titleSmall`, `labelLarge`,
  `labelMedium` added so section and metadata styles stop falling back.
- Page title stays 20 px / `w600`; section titles 13–14 px / `w600`; list titles
  14 px / `w600`; body 13–14 px / `w400`; metadata 11–12 px / `w400–500`.
- Removed `w700`/`w800` from headers and eyebrows.

### Density system
- Control radius 10 → 6; container/dialog radius 14 → 12.
- Compact buttons and inputs (30–34 px), toolbar 36–40 px, list rows 10–12 px
  vertical padding, settings rows 40–48 px.

### Surface hierarchy
- Explicit three-level surface ladder for both themes (background / panel /
  raised) with a single border token, applied through the `ColorScheme` rather
  than hardcoded per widget. Accent is limited to selection, focus, primary
  action and semantic state.

### Resource Library
- One compact toolbar: text tabs for the category filter and lightweight
  `Status: …` / `Sort: …` dropdowns at ~30 px height, no pills.
- Search is 34–36 px with a 6 px radius and a subtle border, accent only on
  focus.
- Rows compose title → metadata → summary (≤2 lines) → locale-aware timestamp.
- Master/detail: 240 px list column, 1 px divider, detail padding so the detail
  reads as the secondary workspace.

### Date formatting
- Added `AppDateFormats.compactTimestamp` using the existing `intl` dependency
  and the active locale (`9月21日 18:27` / `Sep 21, 18:27`), including the year
  only when it differs from the current year.

### Empty states
- `AppEmptyState` now uses a small SVG (28 px), a 14–16 px title and a 12–13 px
  muted description, centred, with no circle backdrop or card.
- Trash uses the same component, centred in the content area.

## Remaining limitations
- The narrative reading font remains the UI sans stack; a serif reading face is
  a separate enhancement.
- Message → Turn navigation remains unimplemented (no reliable mapping).

## Verification
- `flutter analyze`: no issues.
- New regression coverage in `test/widget/visual_polish_test.dart`:
  - `AppBreakpoints.sidebarMode` keeps text navigation at 950 px and only uses
    the rail when collapsed or narrow;
  - `AppDateFormats.compactTimestamp` is locale-aware and never emits the raw
    persisted value, adding the year only outside the current year;
  - the sidebar shows readable destinations at 950/1280 px and a tooltip rail
    only when explicitly collapsed;
  - `AppEmptyState` uses a glyph <= 32 px (no circle, no card);
  - the page header stays overflow-free at 320 px, and the tab button reports
    `isSelected` semantics.
- Extended `resource_library_phase5_test.dart`: rows never show the raw
  timestamp, filters are `WorkbenchTabButton`s (no `ChoiceChip` /
  `SegmentedButton`), and master/detail sits side by side at 960 px with a
  <= 40 px search field.
- `resource_trash_sheet_test.dart` asserts the embedded view does not repeat the
  page title.
- Full `flutter test` suite is recorded in
  `narrative-workbench-rearchitecture.md`.

## Remaining visual limitations
- `ChoiceChip` remains in a number of *contextual, compact single-choice*
  controls (session inspector presets, model/provider selection, wizard steps,
  settings sub-choices, dice check). They are legitimate dense selectors rather
  than page-level filters, so they were deliberately left as chips instead of
  being mechanically converted.
- The narrative reading face is still the UI sans stack (serif reading font is a
  separate enhancement).
