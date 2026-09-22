import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/services/read_aloud/linux_tts_backend.dart';
import 'package:lt_dialogue/services/read_aloud/linux_tts_engine.dart';

void main() {
  group('LinuxReadAloudEngine', () {
    test('should report an unavailable capability when spd-say is missing',
        () async {
      final engine = LinuxReadAloudEngine(
        backend: _FakeLinuxTtsBackend(available: false),
      );

      await engine.initialize();

      expect(engine.capability.supported, isFalse);
      expect(engine.capability.reasonCode,
          LinuxReadAloudEngine.unavailableReasonCode);
      expect(engine.capability.message, contains('spd-say'));
      await expectLater(engine.speak('内容'), throwsA(isA<Object>()));
      engine.dispose();
    });

    test('should speak with configured parameters and report completion',
        () async {
      final backend = _FakeLinuxTtsBackend();
      final engine = LinuxReadAloudEngine(backend: backend);
      var started = 0;
      var completed = 0;
      engine.onStart = () => started++;
      engine.onComplete = () => completed++;

      await engine.initialize();
      await engine.configure(
        rate: 0.7,
        pitch: 1.2,
        volume: 0.8,
        language: 'zh-CN',
      );
      await engine.speak('你好');
      await Future<void>.delayed(Duration.zero);

      expect(engine.capability.supported, isTrue);
      expect(await engine.availableLanguages(), ['zh-CN']);
      expect(engine.capability.supportsPause, isFalse);
      expect(started, 1);
      expect(completed, 1);
      expect(backend.spokenTexts, ['你好']);
      expect(backend.lastRate, 0.7);
      expect(backend.lastPitch, 1.2);
      expect(backend.lastVolume, 0.8);
      expect(backend.lastLanguage, 'zh-CN');
      expect(await engine.pause(), isFalse);
      expect(await engine.resume(), isFalse);
      engine.dispose();
    });

    test('should invalidate a late completion after stop', () async {
      final backend = _FakeLinuxTtsBackend()..speakGate = Completer<void>();
      final engine = LinuxReadAloudEngine(backend: backend);
      var completed = 0;
      engine.onComplete = () => completed++;
      await engine.initialize();

      final speaking = engine.speak('迟到文本');
      await Future<void>.delayed(Duration.zero);
      await engine.stop();
      backend.speakGate!.complete();
      await speaking;

      expect(completed, 0);
      engine.dispose();
    });
  });
}

final class _FakeLinuxTtsBackend implements LinuxTtsBackend {
  _FakeLinuxTtsBackend({this.available = true});

  final bool available;
  final List<String> spokenTexts = <String>[];
  double? lastRate;
  double? lastPitch;
  double? lastVolume;
  String? lastLanguage;
  Completer<void>? speakGate;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<List<String>> availableLanguages() async => const <String>['zh-CN'];

  @override
  Future<void> speak(
    String text, {
    required double rate,
    required double pitch,
    required double volume,
    String? language,
  }) async {
    spokenTexts.add(text);
    lastRate = rate;
    lastPitch = pitch;
    lastVolume = volume;
    lastLanguage = language;
    final gate = speakGate;
    if (gate != null) await gate.future;
  }

  @override
  Future<void> stop() async {}

  @override
  void dispose() {}
}
