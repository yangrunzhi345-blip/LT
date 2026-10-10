import 'package:flutter/widgets.dart';

/// Single source of truth for the stable Flutter Keys the LT UI automation
/// driver relies on.
///
/// Every key here corresponds to a `Key`/`ValueKey` attached to a real widget in
/// `lib/`. Automation must never depend on pixel coordinates, localized button
/// text or widget-tree order; it locates controls through these keys only.
///
/// The registry is intentionally declarative: adding a screen means adding its
/// keys here, which keeps the driver and the app auditable against one list.
abstract final class LtUiKeys {
  // ── Resource library ────────────────────────────────────────────────
  static const Key libraryWorkspace = Key('resource-workspace');
  static const Key libraryList = Key('resource-list');
  static const Key libraryCreateButton = Key('resource-create-button');
  static const Key librarySearchField = Key('resource-search-field');
  static const Key libraryFilter = Key('resource-filter');
  static const Key librarySortSelect = Key('resource-sort-select');
  static const Key libraryStatusFilter = Key('resource-status-filter');

  /// Stable per-resource key: `resource-detail-<resourceId>`.
  static Key libraryDetail(String resourceId) =>
      Key('resource-detail-$resourceId');

  // ── Resource creation entry ─────────────────────────────────────────
  static const Key createTypeSelect = Key('resource-create-type-select');
  static const Key createChoiceAi = Key('create-choice-ai');
  static const Key createChoiceManual = Key('create-choice-manual');

  // ── Worldview / character / NPC AI creation ─────────────────────────
  static const Key aiCreateTypeSelect = Key('ai-create-type-select');
  static const Key aiCreateNameField = Key('ai-create-name-field');
  static const Key aiCreatePasteField = Key('ai-create-paste-field');
  static const Key aiCreateReferenceSegmented =
      Key('ai-create-reference-segmented');
  static const Key aiCreateExistingSelect = Key('ai-create-existing-select');
  static const Key aiCreateOriginWorldviewSelect =
      Key('ai-create-origin-worldview-select');
  static const Key aiCreateTargetSlider = Key('ai-create-target-slider');
  static const Key aiCreateTargetValue = Key('ai-create-target-value');
  static const Key aiCreateSubmitButton = Key('ai-create-submit-button');
  static const Key aiCreatePlanButton = Key('ai-create-plan-button');

  /// Numeric target-word input and its explicit apply affordance.
  static const Key targetWordsInput =
      ValueKey('ai_creation_target_words_input');
  static const Key targetWordsConfirm =
      ValueKey('ai_creation_target_words_confirm');

  // ── Resource Studio (generation / save / retry) ─────────────────────
  static const Key studioSaveAction = Key('studio-save-action');
  static const Key studioRetryFailedParts = Key('studio-retry-failed-parts');
  static const Key studioOutline = Key('resource_studio_outline');
  static const Key studioInspector = Key('resource-studio-inspector');

  // ── Adventure assembly wizard ───────────────────────────────────────
  static const Key assemblyStartAdventure =
      Key('assembly-start-adventure-button');
  static const Key assemblySavePreview = Key('assembly-save-preview-button');
  static const Key assemblyNextPhase = Key('assembly-next-phase-button');
  static const Key assemblyPrevPhase = Key('assembly-prev-phase-button');
  static const Key assemblyOpenWorldSelection =
      Key('assembly-open-world-selection-button');
  static const Key assemblyOpenCharacterSelection =
      Key('assembly-open-character-selection-button');
  static const Key assemblyOpenNpcSelection =
      Key('assembly-open-npc-selection-button');
  static const Key assemblyOpenPreview =
      Key('assembly-open-preview-page-button');
  static const Key assemblyWorldviewNameInput =
      Key('assembly-worldview-name-input');
  static const Key assemblyOpeningSceneInput =
      Key('assembly-opening-scene-input');
  static const Key assemblyOpeningAiGenerate =
      Key('assembly-opening-ai-generate-button');
  static const Key assemblyOpeningAiProgress =
      Key('assembly-opening-ai-progress');
  static const Key assemblyOpeningAiError = Key('assembly-opening-ai-error');
  static const Key assemblyPreviewStartButton =
      Key('assembly-preview-start-button');
  static const Key assemblyPreviewSaveButton =
      Key('assembly-preview-save-button');
  static const Key assemblyPreviewRetryButton =
      Key('assembly-preview-retry-button');

  // ── Resource selection pages (worldview / character / NPC) ──────────
  static const Key selectionSearchInput =
      Key('resource-selection-search-input');
  static const Key selectionConfirmButton =
      Key('resource-selection-confirm-button');

  /// Stable per-item key: `resource-selection-item-<itemId>`.
  static Key selectionItem(String itemId) =>
      Key('resource-selection-item-$itemId');

  // ── Adventure session dialogue ──────────────────────────────────────
  static const Key sessionInput = Key('adventure-session-input');
  static const Key sessionSendButton = Key('adventure-session-send-button');
  static const Key sessionStopButton = Key('adventure-session-stop-button');
  static const Key sessionPendingAssistant = Key('pending_assistant');

  /// Stable per-message key prefixes used by the session transcript.
  static Key userMessage(String messageId) => Key('usr_$messageId');
  static Key assistantMessage(String messageId) => Key('ai_$messageId');
}
