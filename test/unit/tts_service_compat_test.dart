import 'package:flutter_test/flutter_test.dart';

import 'package:lt_dialogue/domain/read_aloud/read_aloud_contracts.dart';
import 'package:lt_dialogue/services/read_aloud/read_aloud_controller.dart';
import 'package:lt_dialogue/services/tts_service.dart';

import '../helpers/read_aloud_fakes.dart';

void main() {
  group('TtsService 兼容门面', () {
    test('无控制器时保持纯函数能力且其余方法安全空操作', () async {
      final service = TtsService();

      // 旧 API 形状：不抛异常。
      await service.init();
      await service.speak('正文');
      await service.stop();
      await service.setRate(0.6);
      await service.setPitch(1.1);
      service.setEnabled(true);
      service.setAutoRead(true);
      service.dispose();

      expect(service.enabled, isFalse);
      expect(service.autoRead, isFalse);
      expect(service.stripForSpeech('**加粗** 正文'), '加粗 正文');
    });

    test('转发到全局 Authority，状态与偏好一致', () async {
      final engine = FakeReadAloudEngine();
      final controller = ReadAloudController(
        engine: engine,
        initialPreferences: const ReadAloudPreferences(enabled: true),
      );
      final service = TtsService(controller);

      expect(service.enabled, isTrue);
      expect(service.autoRead, isFalse);

      service.setAutoRead(true);
      await settleReadAloud();
      expect(controller.autoRead, isTrue);
      expect(service.autoRead, isTrue);

      await service.setRate(0.7);
      expect(controller.rate, 0.7);
      expect(service.rate, 0.7);
    });

    test('speak 复用同一清洗/分段链路，不朗读协议 JSON 与思维链', () async {
      final engine = FakeReadAloudEngine();
      final controller = ReadAloudController(
        engine: engine,
        initialPreferences: const ReadAloudPreferences(enabled: true),
      );
      final service = TtsService(controller);

      await service.speak(
        '灯塔亮了。\n---JSON---\n{"options":["前进"],"hp":10}',
      );

      expect(engine.spokenTexts, ['灯塔亮了。']);
      expect(controller.state.sourceType, ReadAloudSourceType.chat);
    });

    test('stripForSpeech 与全局清洗器行为一致（只有一套规则）', () {
      final service = TtsService();
      const raw = '# 标题\n- 列表项\n**强调** [链接](https://example.com)';
      final cleaned = service.stripForSpeech(raw);
      expect(cleaned, isNot(contains('#')));
      expect(cleaned, isNot(contains('**')));
      expect(cleaned, isNot(contains('https://')));
      expect(cleaned, contains('标题'));
      expect(cleaned, contains('列表项'));
      expect(cleaned, contains('强调'));
      expect(cleaned, contains('链接'));
    });

    test('dispose 不会释放共享的全局 Authority', () async {
      final engine = FakeReadAloudEngine();
      final controller = ReadAloudController(
        engine: engine,
        initialPreferences: const ReadAloudPreferences(enabled: true),
      );
      final service = TtsService(controller);

      service.dispose();

      expect(engine.disposed, isFalse);
      await controller.playText('仍然可用。', sourceId: 'src');
      expect(controller.state.status, ReadAloudStatus.playing);
      expect(engine.spokenTexts, ['仍然可用。']);
      controller.dispose();
    });
  });
}
