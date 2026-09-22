import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lt_dialogue/domain/read_aloud/read_aloud_contracts.dart';
import 'package:lt_dialogue/core/widgets/app_read_aloud.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';
import 'package:lt_dialogue/services/read_aloud/linux_tts_backend.dart';
import 'package:lt_dialogue/services/read_aloud/linux_tts_engine.dart';
import 'package:lt_dialogue/services/read_aloud/read_aloud_controller.dart';

void main() {
  testWidgets('Linux TTS capability makes AppReadAloudButton visible',
      (tester) async {
    final engine = LinuxReadAloudEngine(backend: _AvailableBackend());
    final controller = ReadAloudController(
      engine: engine,
      initialPreferences: const ReadAloudPreferences(enabled: true),
    );
    await controller.init();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          readAloudControllerProvider.overrideWith(
            (ref) => controller,
            disposeNotifier: false,
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: AppReadAloudButton(
              sourceId: 'linux-source',
              sourceType: ReadAloudSourceType.generic,
              text: 'Linux 正文',
            ),
          ),
        ),
      ),
    );

    expect(controller.capability.supported, isTrue);
    expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.volume_up_rounded));
    await tester.pumpAndSettle();
    expect(controller.state.status, ReadAloudStatus.completed);
    expect(tester.takeException(), isNull);
    controller.dispose();
  });
}

final class _AvailableBackend implements LinuxTtsBackend {
  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<List<String>> availableLanguages() async => const <String>[];

  @override
  Future<void> speak(
    String text, {
    required double rate,
    required double pitch,
    required double volume,
    String? language,
  }) async {}

  @override
  Future<void> stop() async {}

  @override
  void dispose() {}
}
