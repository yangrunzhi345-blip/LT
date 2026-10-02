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

import '../helpers/read_aloud_fakes.dart';
import '../helpers/responsive_test_helper.dart';
import '../helpers/tts_fakes.dart';

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

  ({Widget app, FakeTtsDownloadClient client}) buildApp() {
    final repo = _MemorySettingsRepository();
    final client = FakeTtsDownloadClient(payload: Uint8List(0));
    final runtime = TtsRuntime.production(
      settingsRepo: repo,
      rootProvider: () async => tempDir,
      systemEngineFactory: FakeReadAloudEngine.new,
      neuralEngineFactory: FakeNeuralTtsEngine.new,
      audioPlayerFactory: FakeNeuralAudioPlayer.new,
      downloadClientFactory: () => client,
      extractor: const FakeTtsArchiveExtractor(),
    );
    final container = ProviderContainer(
      overrides: [
        settingsRepoProvider.overrideWithValue(repo),
        ttsRuntimeProvider.overrideWithValue(runtime),
      ],
    );
    addTearDown(container.dispose);
    return (
      app: UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
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
    );
  }

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
}
