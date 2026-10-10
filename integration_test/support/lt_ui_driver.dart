import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'lt_ui_keys.dart';

/// Raised when a bounded UI wait exhausts its deadline.
///
/// The message always names the finder so a broken page structure produces a
/// diagnosable failure instead of an opaque timeout.
class LtUiTimeoutException implements Exception {
  LtUiTimeoutException(this.message);

  final String message;

  @override
  String toString() => 'LtUiTimeoutException: $message';
}

/// Key-based UI driver for LT's core business flow.
///
/// Design rules:
/// - Every interaction locates its widget through [LtUiKeys] (stable
///   `find.byKey`), never through coordinates, localized text or widget order.
/// - Every wait is bounded by a deadline and polls with `pump`, so a missing
///   control fails with a clear diagnostic instead of a hang or a blind sleep.
/// - It wraps an existing [WidgetTester], so it works in host widget tests, in
///   `integration_test` on a real device, and against a faked LLM.
class LtUiDriver {
  LtUiDriver(
    this.tester, {
    this.defaultTimeout = const Duration(seconds: 20),
    this.pumpInterval = const Duration(milliseconds: 100),
  });

  final WidgetTester tester;
  final Duration defaultTimeout;
  final Duration pumpInterval;

  // ── primitives ──────────────────────────────────────────────────────

  Finder byKey(Key key) => find.byKey(key);

  int _iterations(Duration timeout) {
    final interval = pumpInterval.inMilliseconds;
    final total = timeout.inMilliseconds;
    final count = interval <= 0 ? total : (total / interval).ceil();
    return count < 1 ? 1 : count;
  }

  /// Pumps until [finder] matches or the bounded iteration budget is spent.
  Future<void> waitFor(
    Finder finder, {
    Duration? timeout,
    bool settle = false,
  }) async {
    final limit = timeout ?? defaultTimeout;
    for (var i = 0; i < _iterations(limit); i++) {
      await tester.pump(pumpInterval);
      if (finder.evaluate().isNotEmpty) {
        if (settle) await tester.pumpAndSettle();
        return;
      }
    }
    throw LtUiTimeoutException(
      'Timed out after ${limit.inMilliseconds}ms waiting for: $finder',
    );
  }

  Future<void> waitForKey(Key key, {Duration? timeout, bool settle = false}) =>
      waitFor(byKey(key), timeout: timeout, settle: settle);

  /// Pumps until [finder] stops matching or the bounded iteration budget ends.
  Future<void> waitForAbsent(
    Finder finder, {
    Duration? timeout,
  }) async {
    final limit = timeout ?? defaultTimeout;
    for (var i = 0; i < _iterations(limit); i++) {
      await tester.pump(pumpInterval);
      if (finder.evaluate().isEmpty) return;
    }
    throw LtUiTimeoutException(
      'Timed out after ${limit.inMilliseconds}ms waiting for absence of: '
      '$finder',
    );
  }

  Future<bool> isPresent(Key key) async {
    await tester.pump();
    return byKey(key).evaluate().isNotEmpty;
  }

  Future<void> tapKey(Key key, {Duration? timeout}) async {
    await waitForKey(key, timeout: timeout);
    final finder = byKey(key).first;
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder, warnIfMissed: false);
    await tester.pump(pumpInterval);
  }

  Future<void> enterTextKey(Key key, String text, {bool submit = false}) async {
    await waitForKey(key);
    final finder = byKey(key).first;
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.enterText(finder, text);
    await tester.pump();
    if (submit) {
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump(pumpInterval);
    }
  }

  /// Reads a `Text` widget's data by key, or null when it is not a `Text`.
  Future<String?> readText(Key key) async {
    await waitForKey(key);
    final widget = tester.widget(byKey(key).first);
    return widget is Text ? widget.data : null;
  }

  /// Reads the current text of a text field located by [key].
  Future<String> readFieldText(Key key) async {
    await waitForKey(key);
    final editable = find.descendant(
      of: byKey(key).first,
      matching: find.byType(EditableText),
    );
    final state = tester.state<EditableTextState>(editable.first);
    return state.widget.controller.text;
  }

  /// Reads a Material [Slider]'s committed value located by [key].
  Future<double> readSliderValue(Key key) async {
    await waitForKey(key);
    return tester.widget<Slider>(byKey(key).first).value;
  }

  // ── resource library ────────────────────────────────────────────────

  Future<void> openLibrary() => waitForKey(LtUiKeys.libraryCreateButton);

  Future<void> openCreateFlow() => tapKey(LtUiKeys.libraryCreateButton);

  Future<void> chooseAiCreate() => tapKey(LtUiKeys.createChoiceAi);

  Future<void> openResourceDetail(String resourceId) =>
      tapKey(LtUiKeys.libraryDetail(resourceId));

  // ── AI create form ──────────────────────────────────────────────────

  Future<void> enterResourceName(String name) =>
      enterTextKey(LtUiKeys.aiCreateNameField, name);

  Future<void> enterReference(String text) =>
      enterTextKey(LtUiKeys.aiCreatePasteField, text);

  /// Types [words] into the numeric budget input and applies it.
  ///
  /// This is the coordinate-free path that replaces the manual Slider drag.
  Future<void> setTargetWords(int words) async {
    await enterTextKey(LtUiKeys.targetWordsInput, '$words');
    await tapKey(LtUiKeys.targetWordsConfirm);
  }

  Future<int> readTargetWords() async {
    final text = await readText(LtUiKeys.aiCreateTargetValue) ?? '';
    final match = RegExp(r'\d+').firstMatch(text);
    return match == null ? -1 : int.parse(match.group(0)!);
  }

  Future<String> readTargetWordsInput() =>
      readFieldText(LtUiKeys.targetWordsInput);

  Future<int> readTargetSlider() async =>
      (await readSliderValue(LtUiKeys.aiCreateTargetSlider)).round();

  Future<void> submitCreate() => tapKey(LtUiKeys.aiCreateSubmitButton);

  Future<void> planBlueprint() => tapKey(LtUiKeys.aiCreatePlanButton);

  // ── Resource Studio ─────────────────────────────────────────────────

  Future<void> waitForStudio() => waitForKey(LtUiKeys.studioSaveAction);

  Future<void> saveStudio() => tapKey(LtUiKeys.studioSaveAction);

  Future<void> retryFailedParts() => tapKey(LtUiKeys.studioRetryFailedParts);

  // ── Adventure assembly wizard ───────────────────────────────────────

  Future<void> openWorldviewSelection() =>
      tapKey(LtUiKeys.assemblyOpenWorldSelection);

  Future<void> openCharacterSelection() =>
      tapKey(LtUiKeys.assemblyOpenCharacterSelection);

  /// Selects one or more worldview/character/NPC items by their stable ids and
  /// confirms, inside an already-open resource-selection page.
  Future<void> selectFromOpenPicker(Iterable<String> itemIds) async {
    await waitForKey(LtUiKeys.selectionConfirmButton);
    for (final id in itemIds) {
      await tapKey(LtUiKeys.selectionItem(id));
    }
    await tapKey(LtUiKeys.selectionConfirmButton);
  }

  Future<void> selectWorldview(String worldviewId) async {
    await openWorldviewSelection();
    await selectFromOpenPicker([worldviewId]);
  }

  Future<void> selectCharacters(Iterable<String> characterIds) async {
    await openCharacterSelection();
    await selectFromOpenPicker(characterIds);
  }

  Future<void> nextAssemblyPhase() => tapKey(LtUiKeys.assemblyNextPhase);

  Future<void> previousAssemblyPhase() => tapKey(LtUiKeys.assemblyPrevPhase);

  /// Generates the prologue with the configured model and waits for it to
  /// finish (progress indicator gone, error absent).
  Future<void> generateOpening({Duration? timeout}) async {
    await tapKey(LtUiKeys.assemblyOpeningAiGenerate);
    await waitForAbsent(byKey(LtUiKeys.assemblyOpeningAiProgress),
        timeout: timeout ?? const Duration(minutes: 3));
    if (await isPresent(LtUiKeys.assemblyOpeningAiError)) {
      throw LtUiTimeoutException('Opening generation reported an error');
    }
  }

  Future<void> startAdventure() => tapKey(LtUiKeys.assemblyStartAdventure);

  Future<void> waitForAdventureSession() =>
      waitForKey(LtUiKeys.sessionInput, timeout: const Duration(seconds: 60));

  // ── Adventure session ───────────────────────────────────────────────

  Future<void> sendMessage(String text) async {
    await enterTextKey(LtUiKeys.sessionInput, text);
    await tapKey(LtUiKeys.sessionSendButton);
  }

  /// Waits until the assistant finishes streaming (the send button returns and
  /// no stop button is present).
  Future<void> waitForAssistantReply({Duration? timeout}) async {
    await waitForAbsent(byKey(LtUiKeys.sessionStopButton),
        timeout: timeout ?? const Duration(minutes: 3));
    await waitForKey(LtUiKeys.sessionSendButton,
        timeout: timeout ?? const Duration(minutes: 3));
  }
}
