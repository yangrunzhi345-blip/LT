import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/services/read_aloud/flutter_tts_engine.dart';
import 'package:lt_dialogue/services/read_aloud/read_aloud_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  group('ReadAloudPlatform 能力矩阵', () {
    test('Android / iOS / macOS / Windows 有系统 TTS 后端', () {
      for (final platform in <TargetPlatform>[
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.macOS,
        TargetPlatform.windows,
      ]) {
        debugDefaultTargetPlatformOverride = platform;
        expect(ReadAloudPlatform.hasSystemTtsBackend, isTrue,
            reason: '$platform 应当有后端');
      }
    });

    test('Linux 没有系统 TTS 后端（flutter_tts 未声明 Linux 平台）', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      expect(ReadAloudPlatform.hasSystemTtsBackend, isFalse);
      expect(ReadAloudPlatform.platformLabel, 'Linux');
    });

    test('不支持的平台创建显式不可用引擎，不静默成功', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      final engine = createDefaultReadAloudEngine();

      expect(engine, isA<UnsupportedReadAloudEngine>());
      expect(engine.capability.supported, isFalse);
      expect(engine.capability.supportsPause, isFalse);
      expect(engine.capability.reasonCode,
          ReadAloudPlatform.unsupportedReasonCode);
      expect(engine.capability.message, contains('Linux'));

      // 安全空操作，不崩溃。
      await engine.initialize();
      await engine.stop();
      expect(await engine.pause(), isFalse);
      expect(await engine.resume(), isFalse);

      // speak 明确失败，而不是假装朗读成功。
      expect(
        engine.speak('内容'),
        throwsA(isA<ReadAloudEngineException>()),
      );
    });

    test('支持的平台创建 flutter_tts 引擎且初始能力可用', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final engine = createDefaultReadAloudEngine();
      expect(engine, isA<FlutterTtsEngine>());
      expect(engine.capability.supported, isTrue);
      expect(engine.capability.supportsPause, isTrue);
      engine.dispose();
    });

    test('插件缺失时运行期降级为不可用，而不是抛出', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final engine = FlutterTtsEngine();
      // 测试环境没有平台实现：initialize 必须把能力降级。
      await engine.initialize();
      expect(engine.capability.supported, isFalse);
      expect(engine.capability.reasonCode,
          ReadAloudPlatform.pluginUnavailableReasonCode);
      engine.dispose();
    });
  });
}
