# Phase 6 Resource Studio Gap Analysis

Date: 2026-09-17  
Baseline: `371d672` / candidate implementation `4fe587e`

## Scope and source documents

This audit compares the repository with:

- `docs/adaptive-resource-system/phase-06-streaming-resource-studio.md`
- `docs/adaptive-resource-system/phase-06-independent-acceptance.md`
- `docs/adaptive-resource-system/STATUS.md`

Phase 6 is currently `FAILED` because the runtime foundation was delivered
without the user-facing Resource Studio product.

## Existing capabilities

### Domain and persistence

- `lib/domain/resources/streaming_generation_runtime_contracts.dart` defines
  lifecycle statuses, transitions, session data, and runtime events.
- `lib/domain/resources/resource_generation_patch.dart` and the Phase 5
  parser/accumulator validate incremental Part patches.
- `lib/application/resources/streaming_generation_session_repository.dart`
  persists runtime sessions.
- `lib/services/database_service.dart` creates and migrates the v37 session
  schema.

### Application runtime

- `PartGenerationCoordinator` schedules Phase 5 Part tasks, parses streaming
  patches, validates responses, and commits completed Parts.
- `StreamingResourceGenerationService` exposes start, pause, resume, cancel,
  retry, and interruption recovery operations.
- `lib/controllers/streaming_resource_generation_controller.dart` exposes the
  service event stream and commands as a headless controller.
- The remediation commit serializes a session to one active Part, orders
  lifecycle callbacks, owns task handles, and protects session invariants.

### Existing adjacent architecture

- Feature-oriented Flutter folders exist under `lib/features/`, including
  `resource_library` and `settings`.
- The app has a central `lib/core/router/app_router.dart`, Riverpod providers,
  existing Material 3 theme infrastructure, and resource tree repositories.
- `TypewriterController` and
  `GenerationLimits.streamingPreviewThrottle` provide reusable streaming
  presentation patterns.
- Phase 6 runtime, repository, migration, and controller tests currently pass
  the targeted 28-test regression command.

## Missing capabilities

### Product surface

- No `lib/features/resource_studio/` feature exists.
- No Resource Studio page or widgets render resource header, Section/Part
  structure, generated text, progress, validation, or errors.
- No UI controls invoke continue, pause, resume, cancel, retry, or recovery.
- No creation-completion navigation enters a Studio session.

### State and event pipeline

- No Studio-specific immutable view state exists for loading, generating,
  validating, completed, paused, failed, or retrying states.
- No StateNotifier/controller translates `GenerationRuntimeEvent` into UI
  state. The current controller is headless and has no production construction
  point.
- No per-Part presentation model or bounded patch-to-UI notifier exists.
- No dispose/old-generation guard is tested at the widget state boundary.

### Navigation and production wiring

- Repository search finds only test construction sites for
  `StreamingResourceGenerationService` and
  `StreamingResourceGenerationController`.
- `app_router.dart` has no Studio route.
- Resource creation flows do not hand a generation/session ID to a Studio
  entry point, and cold-start session restoration is absent.

### Responsive validation

- No Studio widget tests cover 320, 360, 390, 412, 768, or desktop viewports.
- No tests cover long titles, 200% text scale, SafeArea, keyboard insets,
  drawer/bottom-panel behavior, or overflow exceptions.
- No tests prove loading, generating, validating, error, or retry layouts.

## Missing files / expected additions

The exact names can follow project conventions, but the feature should include
at least:

```text
lib/features/resource_studio/
  resource_studio.dart
  presentation/
    pages/resource_studio_page.dart
    widgets/resource_studio_header.dart
    widgets/resource_studio_outline.dart
    widgets/resource_studio_part_card.dart
    widgets/resource_studio_status_view.dart
    controllers/resource_studio_controller.dart
    state/resource_studio_state.dart
  application/use_cases/restore_resource_generation.dart
  domain/models/resource_studio_view_model.dart
```

Likely shared changes include a typed Studio route/navigation helper and a
production dependency factory. Tests should mirror the feature structure and
include controller/state unit tests plus responsive widget tests.

## Missing call chain

The required path currently stops at the headless runtime:

```text
AI creation completion
  -X-> Studio route/page
  -X-> StateNotifier/controller
  -X-> per-Part view state
  -X-> responsive widgets
```

The implemented lower path is:

```text
StreamingResourceGenerationController (tests only)
  -> StreamingResourceGenerationService
  -> PartGenerationCoordinator
  -> GenerationPatchParser/Accumulator
  -> validation and atomic task commit
  -> resource tree persistence
```

The implementation must bridge these paths without letting events mutate
widgets directly:

```text
GenerationRuntimeEvent
  -> ResourceStudioController / StateNotifier
  -> immutable ResourceStudioState
  -> ResourceStudioPage and Part widgets
```

## Recommended implementation plan

1. Define immutable Studio state and per-Part presentation models, including
   generation/session IDs and terminal/error states.
2. Add a feature-scoped controller that subscribes to the runtime event stream,
   applies the existing 30 ms / 180 ms presentation throttling policy, performs
   final flushes, ignores stale generations, and exposes command methods.
3. Add a production dependency factory using the existing repositories,
   coordinator, service, and Riverpod conventions.
4. Build the Studio page with `LayoutBuilder`: drawer/bottom panel below
   600 px, switchable compact layout from 600–899 px, and constrained
   two-column desktop layout at 900 px and above. Keep dynamic text wrapped or
   ellipsized only where semantically safe.
5. Add the creation-completion route and a cold-start restore path keyed by
   resource/generation session ID.
6. Add widget and controller tests for all required state branches, stale
   events, dispose, final flush, commands, and viewport sizes.
7. Run formatting, analysis, targeted tests, full tests, and an independent
   acceptance pass before changing `STATUS.md`.

## Acceptance mapping

| Requirement | Evidence required |
| --- | --- |
| Studio exists and is reachable | Production route and creation navigation test; cold-start route test |
| Resource/Section/Part presentation | Widget tests with representative tree and long text |
| Runtime event pipeline | Controller tests proving event → state → widget, with no direct widget mutation |
| Progress/validation/error/retry | State transition tests and visible widget assertions |
| Pause/resume/cancel/recovery | Command tests with service fakes and restored session test |
| Streaming throttling/final flush | High-frequency patch, final flush, stale generation, and dispose tests |
| Responsive layout | 320×568, 360×640, 390×844, 412×915, 768×1024, and desktop tests with `takeException() == null` |
| Quality gates | `dart format --output=none --set-exit-if-changed .`, `flutter analyze`, and full `flutter test` |

Until every row has direct evidence, Phase 6 must remain non-accepted and
Phase 7 must remain blocked.
