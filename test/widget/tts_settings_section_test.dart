import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/features/settings/presentation/widgets/enhanced_tts_settings.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';
import 'package:lt_dialogue/services/repositories/settings_repository.dart';
import 'package:lt_dialogue/services/tts/tts_runtime.dart';
import 'package:lt_dialogue/services/read_aloud/read_aloud_controller.dart';
import 'package:lt_dialogue/domain/tts/tts_models.dart';
import 'package:lt_dialogue/domain/tts/tts_voices.dart';
import 'package:lt_dialogue/domain/read_aloud/read_aloud_contracts.dart';

import '../helpers/read_aloud_fakes.dart';
import '../helpers/responsive_test_helper.dart';
import '../helpers/tts_fakes.dart';
import '../helpers/tts_casting_fixture.dart';

class _MemorySettingsRepository implements ISettingsRepository {
  final Map<String, String> values = <String, String>{};

  @override
  Future<Map<String, String>> getAllSettings() async =>
      Map<String, String>.from(values);

  @override
  Future<void> setSettings(Map<String, String> input) async {
    values.addAll(input);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('lt_tts_settings_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  ({
    Widget app,
    FakeTtsDownloadClient client,
    TtsRuntime runtime,
    ProviderContainer container
  }) buildApp(
      {bool systemSupported = true,
      ReadAloudController? controllerOverride,
      double textScale = 1}) {
    final repo = _MemorySettingsRepository();
    final client = FakeTtsDownloadClient(payload: Uint8List(0));
    final runtime = TtsRuntime.production(
      settingsRepo: repo,
      rootProvider: () async => tempDir,
      systemEngineFactory: () =>
          FakeReadAloudEngine(supported: systemSupported),
      neuralEngineFactory: FakeNeuralTtsEngine.new,
      audioPlayerFactory: FakeNeuralAudioPlayer.new,
      downloadClientFactory: () => client,
      extractor: const FakeTtsArchiveExtractor(),
    );
    final container = ProviderContainer(
      overrides: [
        settingsRepoProvider.overrideWithValue(repo),
        ttsRuntimeProvider.overrideWithValue(runtime),
        if (controllerOverride != null)
          readAloudControllerProvider.overrideWith((ref) => controllerOverride,
              disposeNotifier: false),
      ],
    );
    addTearDown(container.dispose);
    return (
      app: UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('zh'),
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: EnhancedTtsSettingsSection(),
              ),
            ),
          ),
        ),
      ),
      client: client,
      runtime: runtime,
      container: container,
    );
  }

  testWidgets(
      'should show an unavailable voice without exposing its internal id',
      (tester) async {
    final built = buildApp();
    await built.runtime.bindings.setMode(TtsBackendKind.neural);
    await built.runtime.bindings.setNarratorVoice('unknown-family:s999');
    await tester.pumpWidget(built.app);
    await tester.pumpAndSettle();
    expect(find.text('unknown-family:s999'), findsNothing);
    expect(find.text('该声音当前不可用。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('should stop only picker preview on dismissal', (tester) async {
    final casting = TtsCastingFixture(installed: false);
    addTearDown(casting.dispose);
    final built = buildApp(controllerOverride: casting.controller);
    await built.runtime.bindings.setMode(TtsBackendKind.neural);
    await tester.pumpWidget(built.app);
    await tester.pumpAndSettle();
    final controller = built.container.read(readAloudControllerProvider);
    await controller.playText('Story before preview.', sourceId: 'story');
    await tester.tap(find.byKey(const ValueKey('tts-voice-choose')).first);
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('tts-voice-preview-kokoro-v1_1:s0')));
    await tester.pumpAndSettle();
    expect(controller.state.sourceId, 'tts-voice-preview');
    await tester
        .tap(find.byKey(const ValueKey('tts-voice-preview-kokoro-v1_1:s1')));
    await tester.pumpAndSettle();
    expect(controller.state.status, ReadAloudStatus.playing);
    await tester.tap(find.byKey(const ValueKey('tts-voice-cancel')));
    await tester.pumpAndSettle();
    expect(controller.state.status, ReadAloudStatus.stopped);
    await tester.tap(find.byKey(const ValueKey('tts-voice-choose')).first);
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('tts-voice-preview-kokoro-v1_1:s0')));
    await tester.pumpAndSettle();
    await controller.playText('New story.', sourceId: 'new-story');
    await tester.tap(find.byKey(const ValueKey('tts-voice-cancel')));
    await tester.pumpAndSettle();
    expect(controller.state.sourceId, 'new-story');
    expect(controller.state.status, ReadAloudStatus.playing);
    expect(built.client.requestCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'should report unavailable system independently of neural capability',
      (tester) async {
    for (final size in requiredUiViewports) {
      setViewport(tester, width: size.width, height: size.height);
      final casting = TtsCastingFixture(systemSupported: false);
      addTearDown(casting.dispose);
      final built = buildApp(
          systemSupported: false, controllerOverride: casting.controller);
      expect(casting.controller.capability.supported, isTrue);
      expect(casting.controller.systemCapability.supported, isFalse);
      await built.runtime.bindings.setMode(TtsBackendKind.neural);
      await tester.pumpWidget(built.app);
      await tester.pumpAndSettle();
      expect(find.text('此平台没有可用的系统语音后端'), findsOneWidget);
      expect(find.text('系统语音可用'), findsNothing);
      expect(tester.takeException(), isNull, reason: '$size');
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('defaults to system mode and never downloads automatically',
      (tester) async {
    final built = buildApp();
    await tester.pumpWidget(built.app);
    await tester.pump(const Duration(milliseconds: 50));

    expect(tester.takeException(), isNull);
    // No HTTP request is made merely by rendering the settings surface.
    expect(built.client.requestCount, 0);
    expect(built.client.requestedUris, isEmpty);
  });

  testWidgets('opening the model manager shows the model page', (tester) async {
    final built = buildApp();
    await tester.pumpWidget(built.app);
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.byKey(const ValueKey('tts-manage-models')));
    await tester.pumpAndSettle();

    expect(find.byType(Scaffold), findsWidgets);
    expect(find.text('语音模型'), findsWidgets);
    expect(built.client.requestCount, 0);
  });

  testWidgets('enhanced settings are overflow-free at required viewports',
      (tester) async {
    for (final size in requiredUiViewports) {
      setViewport(tester, width: size.width, height: size.height);
      final built = buildApp();
      await tester.pumpWidget(built.app);
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull,
          reason: 'overflow at ${size.width}x${size.height}');
    }
  });

  testWidgets('zero installed models reports the empty neural status',
      (tester) async {
    final built = buildApp();
    await tester.pumpWidget(built.app);
    await tester.pump(const Duration(milliseconds: 50));

    // The neural status line is present and there are no model downloads.
    expect(find.byKey(const ValueKey('tts-manage-models')), findsOneWidget);
    expect(built.client.requestCount, 0);
  });

  testWidgets(
      'should distinguish system and auto without downloading at all viewports',
      (tester) async {
    for (final size in requiredUiViewports) {
      setViewport(tester, width: size.width, height: size.height);
      final built = buildApp(textScale: 1.5);
      await built.runtime.bindings.setMode(TtsBackendKind.neural);
      await tester.pumpWidget(built.app);
      await tester.pumpAndSettle();
      await tester
          .ensureVisible(find.byKey(const ValueKey('tts-voice-choose')).first);
      await tester.tap(find.byKey(const ValueKey('tts-voice-choose')).first);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('tts-voice-list')), findsOneWidget);
      expect(built.client.requestCount, 0);
      await tester.tap(find.byKey(const ValueKey('tts-voice-system')));
      await tester.pumpAndSettle();
      expect(built.runtime.bindings.preferences.narratorVoiceId,
          VoiceBinding.systemVoiceId);
      await tester
          .ensureVisible(find.byKey(const ValueKey('tts-voice-choose')).last);
      await tester.tap(find.byKey(const ValueKey('tts-voice-choose')).last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tts-voice-system')));
      await tester.pumpAndSettle();
      expect(built.runtime.bindings.preferences.defaultCharacterVoiceId,
          VoiceBinding.systemVoiceId);
      await tester.tap(find.byKey(const ValueKey('tts-voice-choose')).last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tts-voice-auto')));
      await tester.pumpAndSettle();
      expect(
          built.runtime.bindings.preferences.defaultCharacterVoiceId, isNull);
      expect(built.client.requestCount, 0);
      expect(tester.takeException(), isNull, reason: 'picker at $size');
      await tester.pumpWidget(const SizedBox());
    }
  });
}
