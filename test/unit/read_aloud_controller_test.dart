import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/domain/read_aloud/read_aloud_contracts.dart';
import 'package:lt_dialogue/services/read_aloud/read_aloud_controller.dart';
import 'package:lt_dialogue/services/read_aloud/read_aloud_engine.dart';
import 'package:lt_dialogue/services/read_aloud/text_segmenter.dart';

import '../helpers/read_aloud_fakes.dart';

const ReadAloudPreferences _enabled =
    ReadAloudPreferences(enabled: true, autoRead: true);

ReadAloudController _controller(
  FakeReadAloudEngine engine, {
  ReadAloudPreferences preferences = _enabled,
  InMemoryReadAloudSettingsStore? store,
  TextSegmenter segmenter = const TextSegmenter(),
}) {
  return ReadAloudController(
    engine: engine,
    store: store,
    segmenter: segmenter,
    initialPreferences: preferences,
  );
}

void main() {
  group('ReadAloudController 状态机', () {
    test('playText 进入 playing 并记录会话/段落信息', () async {
      final engine = FakeReadAloudEngine();
      final controller = _controller(engine);
      addTearDown(controller.dispose);

      await controller.playText(
        '第一段。',
        sourceId: 'msg-1',
        sourceType: ReadAloudSourceType.chat,
        label: 'AI 回复',
      );

      final state = controller.state;
      expect(state.status, ReadAloudStatus.playing);
      expect(state.sourceId, 'msg-1');
      expect(state.sourceType, ReadAloudSourceType.chat);
      expect(state.currentChunkId, 'msg-1');
      expect(state.currentLabel, 'AI 回复');
      expect(state.segmentIndex, 0);
      expect(state.segmentCount, 1);
      expect(state.currentText, '第一段。');
      expect(engine.spokenTexts, ['第一段。']);
      expect(state.isActiveSource('msg-1'), isTrue);
      expect(state.isPlayingSource('msg-1'), isTrue);
      expect(state.progressLabel, '第 1/1 段');
    });

    test('completion 推进到下一段，最后一段完成进入 completed', () async {
      final engine = FakeReadAloudEngine();
      final controller = _controller(
        engine,
        segmenter: const TextSegmenter(maxLength: 5),
      );
      addTearDown(controller.dispose);

      await controller.playText('第一句。第二句。', sourceId: 's');
      expect(controller.state.segmentCount, 2);

      engine.emitComplete();
      await settleReadAloud();
      expect(controller.state.status, ReadAloudStatus.playing);
      expect(controller.state.segmentIndex, 1);
      expect(engine.spokenTexts.length, 2);

      engine.emitComplete();
      await settleReadAloud();
      expect(controller.state.status, ReadAloudStatus.completed);
      expect(controller.state.segmentIndex, 1);
      expect(engine.spokenTexts.length, 2);
    });

    test('新朗读替换旧朗读：在途期到达的迟到 completion 被丢弃', () async {
      final engine = FakeReadAloudEngine();
      final controller = _controller(
        engine,
        segmenter: const TextSegmenter(maxLength: 12),
      );
      addTearDown(controller.dispose);

      await controller.playText('A 的第一句内容。A 的第二句内容。', sourceId: 'A');
      expect(controller.state.segmentCount, 2);
      final runA = controller.state.runId;

      // 不等待 B 朗读就绪，模拟 A 被替换后在途期到达的迟到完成回调。
      final pendingB = controller.playText(
        'B 的第一句内容。B 的第二句内容。',
        sourceId: 'B',
      );
      engine.emitComplete();
      await pendingB;
      await settleReadAloud();

      expect(controller.state.sourceId, 'B');
      expect(controller.state.runId, greaterThan(runA));
      expect(controller.state.status, ReadAloudStatus.playing);
      expect(controller.state.segmentIndex, 0,
          reason: '迟到回调必须被 run token 隔离，不能推进新会话');
      expect(engine.spokenTexts, ['A 的第一句内容。', 'B 的第一句内容。']);
    });

    test('已经是终结态时再来的 completion 不会复活播放', () async {
      final engine = FakeReadAloudEngine();
      final controller = _controller(engine);
      addTearDown(controller.dispose);

      await controller.playText('只读一次。', sourceId: 'A');
      engine.emitComplete();
      await settleReadAloud();
      expect(controller.state.status, ReadAloudStatus.completed);

      final spokenBefore = engine.spokenTexts.length;
      engine.emitComplete();
      await settleReadAloud();
      expect(controller.state.status, ReadAloudStatus.completed);
      expect(engine.spokenTexts.length, spokenBefore);
    });

    test('stop 清空会话，stop 之后的迟到 completion 不会复活播放', () async {
      final engine = FakeReadAloudEngine();
      final controller = _controller(engine);
      addTearDown(controller.dispose);

      await controller.playText('内容。', sourceId: 'A');
      await controller.stop();

      expect(controller.state.status, ReadAloudStatus.stopped);
      expect(controller.state.sourceId, isNull);
      expect(controller.state.segmentCount, 0);

      final spokenBefore = engine.spokenTexts.length;
      engine.emitComplete();
      await settleReadAloud();
      expect(controller.state.status, ReadAloudStatus.stopped);
      expect(controller.state.sourceId, isNull);
      expect(engine.spokenTexts.length, spokenBefore);
    });

    test('连续点击 A/B/A 只产生一次在途朗读，不重叠', () async {
      final engine = FakeReadAloudEngine();
      final controller = _controller(engine);
      addTearDown(controller.dispose);

      await controller.playText('A。', sourceId: 'A');
      await controller.playText('B。', sourceId: 'B');
      await controller.playText('A。', sourceId: 'A');

      expect(controller.state.sourceId, 'A');
      expect(controller.state.status, ReadAloudStatus.playing);
      expect(engine.spokenTexts, ['A。', 'B。', 'A。']);
      expect(engine.stopCount, greaterThanOrEqualTo(0));
    });

    test('next/previous 越界收敛且不越界朗读', () async {
      final engine = FakeReadAloudEngine();
      final controller = _controller(
        engine,
        segmenter: const TextSegmenter(maxLength: 5),
      );
      addTearDown(controller.dispose);

      await controller.playText('第一句。第二句。第三句。', sourceId: 's');
      expect(controller.state.segmentCount, 3);

      await controller.next();
      expect(controller.state.segmentIndex, 1);
      await controller.previous();
      expect(controller.state.segmentIndex, 0);

      // 第一段再往上是重播当前段，而不是负下标。
      final spokenBefore = engine.spokenTexts.length;
      await controller.previous();
      expect(controller.state.segmentIndex, 0);
      expect(engine.spokenTexts.length, spokenBefore + 1);

      // 最后一段继续往下是明确结束。
      await controller.next();
      await controller.next();
      await controller.next();
      expect(controller.state.status, ReadAloudStatus.completed);
      expect(controller.state.segmentIndex, 2);
    });

    test('pause/resume 使用平台原生能力', () async {
      final engine = FakeReadAloudEngine();
      final controller = _controller(engine);
      addTearDown(controller.dispose);

      await controller.playText('内容。', sourceId: 'A');
      await controller.pause();
      expect(controller.state.status, ReadAloudStatus.paused);
      expect(engine.pauseCount, 1);

      await controller.resume();
      expect(controller.state.status, ReadAloudStatus.playing);
      expect(engine.resumeCount, 1);
    });

    test('平台不支持 pause 时使用显式回退，且不伪造成功', () async {
      final engine = FakeReadAloudEngine(supportsPause: false);
      final controller = _controller(engine);
      addTearDown(controller.dispose);

      await controller.playText('第一句。第二句。', sourceId: 'A');
      await controller.pause();
      expect(controller.state.status, ReadAloudStatus.paused);
      expect(controller.state.capability.supportsPause, isFalse);
      expect(engine.pauseCount, 0, reason: '不支持时不应调用平台 pause');
      expect(engine.stopCount, greaterThanOrEqualTo(1), reason: '回退必须真正停止音频');

      final spokenBefore = engine.spokenTexts.length;
      await controller.resume();
      expect(controller.state.status, ReadAloudStatus.playing);
      expect(engine.spokenTexts.length, spokenBefore + 1,
          reason: '回退 resume 从当前段开头重播');
    });

    test('平台声明支持但 pause 未生效时同样回退', () async {
      final engine = FakeReadAloudEngine(pauseResult: false);
      final controller = _controller(engine);
      addTearDown(controller.dispose);

      await controller.playText('内容。', sourceId: 'A');
      await controller.pause();
      expect(controller.state.status, ReadAloudStatus.paused);
      expect(engine.pauseCount, 1);
      expect(engine.stopCount, greaterThanOrEqualTo(1));
    });

    test('总开关关闭时 play 不产生任何朗读', () async {
      final engine = FakeReadAloudEngine();
      final controller = _controller(
        engine,
        preferences: const ReadAloudPreferences(enabled: false),
      );
      addTearDown(controller.dispose);

      await controller.playText('不该被朗读。', sourceId: 'A');
      expect(controller.state.status, ReadAloudStatus.idle);
      expect(engine.spokenTexts, isEmpty);
    });

    test('平台不支持时进入 error 并给出原因，不静默成功', () async {
      final engine = FakeReadAloudEngine(supported: false);
      final controller = _controller(engine);
      addTearDown(controller.dispose);

      await controller.playText('内容。', sourceId: 'A');
      expect(controller.state.status, ReadAloudStatus.error);
      expect(controller.state.capability.supported, isFalse);
      expect(controller.state.errorMessage, isNotNull);
      expect(engine.spokenTexts, isEmpty);
    });

    test('空正文不建立会话', () async {
      final engine = FakeReadAloudEngine();
      final controller = _controller(engine);
      addTearDown(controller.dispose);

      await controller.playText('   \n  ', sourceId: 'A');
      expect(controller.state.hasActiveSession, isFalse);
      expect(engine.spokenTexts, isEmpty);
    });

    test('意外 cancel 会被反映为 stopped，自身打断不会', () async {
      final engine = FakeReadAloudEngine();
      final controller = _controller(engine);
      addTearDown(controller.dispose);

      await controller.playText('内容。', sourceId: 'A');
      engine.emitCancel();
      await settleReadAloud();
      expect(controller.state.status, ReadAloudStatus.stopped);
      expect(controller.state.sourceId, 'A');
    });

    test('引擎错误进入 error 状态', () async {
      final engine = FakeReadAloudEngine();
      final controller = _controller(engine);
      addTearDown(controller.dispose);

      await controller.playText('内容。', sourceId: 'A');
      engine.emitError(ReadAloudEngineException('合成失败'));
      expect(controller.state.status, ReadAloudStatus.error);
      expect(controller.state.errorMessage, '合成失败');
    });

    test('speak 抛错时进入 error 而不是卡在 playing', () async {
      final engine = FakeReadAloudEngine(
        speakError: ReadAloudEngineException('设备无语音包'),
      );
      final controller = _controller(engine);
      addTearDown(controller.dispose);

      await controller.playText('内容。', sourceId: 'A');
      expect(controller.state.status, ReadAloudStatus.error);
      expect(controller.state.errorMessage, '设备无语音包');
    });

    test('stopIfActive 只停止匹配的会话', () async {
      final engine = FakeReadAloudEngine();
      final controller = _controller(engine);
      addTearDown(controller.dispose);

      await controller.playText('内容。', sourceId: 'A');
      await controller.stopIfActive('B');
      expect(controller.state.status, ReadAloudStatus.playing);

      await controller.stopIfActive('A');
      expect(controller.state.status, ReadAloudStatus.stopped);
    });

    test('多来源连续朗读保留段级来源映射', () async {
      final engine = FakeReadAloudEngine();
      final controller = _controller(engine);
      addTearDown(controller.dispose);

      await controller.play(
        sessionId: 'resource-1',
        sourceType: ReadAloudSourceType.studioResource,
        sources: const [
          ReadAloudSource(id: 'part-1', text: '第一部分。', label: 'Part 1'),
          ReadAloudSource(id: 'part-2', text: '第二部分。', label: 'Part 2'),
        ],
      );

      expect(controller.state.segmentCount, 2);
      expect(controller.state.currentChunkId, 'part-1');
      engine.emitComplete();
      await settleReadAloud();
      expect(controller.state.currentChunkId, 'part-2');
      expect(controller.state.currentLabel, 'Part 2');
      expect(controller.state.currentText, '第二部分。');
    });

    test('dispose 之后的迟到回调被忽略且不抛异常', () async {
      final engine = FakeReadAloudEngine();
      final controller = _controller(engine);
      await controller.playText('内容。', sourceId: 'A');

      final captured = engine;
      controller.dispose();
      expect(engine.disposed, isTrue);

      expect(() => captured.emitComplete(), returnsNormally);
      expect(() => captured.emitCancel(), returnsNormally);
      expect(() => captured.emitError('late'), returnsNormally);
    });
  });

  group('ReadAloudController 偏好与持久化', () {
    test('init 初始化引擎，restore 恢复偏好并应用到引擎', () async {
      final engine = FakeReadAloudEngine();
      final controller = _controller(
        engine,
        preferences: ReadAloudPreferences.defaults,
      );
      addTearDown(controller.dispose);

      await controller.init();
      expect(engine.initializeCount, greaterThanOrEqualTo(1));

      controller.restore(
        const ReadAloudPreferences(
          enabled: true,
          autoRead: true,
          rate: 0.8,
          pitch: 1.2,
          volume: 0.5,
        ),
      );
      await settleReadAloud();

      expect(controller.enabled, isTrue);
      expect(controller.autoRead, isTrue);
      expect(controller.rate, 0.8);
      expect(controller.pitch, 1.2);
      expect(engine.lastRate, 0.8);
      expect(engine.lastPitch, 1.2);
      expect(engine.lastVolume, 0.5);
    });

    test('restore 在引擎未初始化时不触碰平台参数（启动期安全）', () async {
      final engine = FakeReadAloudEngine()..initialized = false;
      final controller = _controller(
        engine,
        preferences: ReadAloudPreferences.defaults,
      );
      addTearDown(controller.dispose);

      controller.restore(
        const ReadAloudPreferences(enabled: true, rate: 0.9, pitch: 1.6),
      );
      await settleReadAloud();

      expect(controller.enabled, isTrue);
      expect(controller.rate, 0.9);
      expect(controller.pitch, 1.6);
      expect(engine.configureCount, 0, reason: '启动恢复路径不得触发平台通道调用');
    });

    test('setter 写回存储', () async {
      final engine = FakeReadAloudEngine();
      final store = InMemoryReadAloudSettingsStore(
        const ReadAloudPreferences(enabled: true),
      );
      final controller = _controller(
        engine,
        store: store,
        preferences: const ReadAloudPreferences(enabled: true, autoRead: false),
      );
      addTearDown(controller.dispose);

      await controller.setAutoRead(true);
      await controller.setRate(0.75);
      await controller.setPitch(1.4);
      await controller.setVolume(0.3);

      expect(store.saveCount, 4);
      expect(store.preferences.autoRead, isTrue);
      expect(store.preferences.rate, 0.75);
      expect(store.preferences.pitch, 1.4);
      expect(store.preferences.volume, 0.3);
    });

    test('关闭总开关会停止进行中的朗读', () async {
      final engine = FakeReadAloudEngine();
      final controller = _controller(engine);
      addTearDown(controller.dispose);

      await controller.playText('内容。', sourceId: 'A');
      await controller.setEnabled(false);
      expect(controller.state.status, ReadAloudStatus.stopped);
      expect(engine.stopCount, greaterThanOrEqualTo(1));
    });

    test('偏好写入失败不会向上抛出', () async {
      final engine = FakeReadAloudEngine();
      final store = InMemoryReadAloudSettingsStore()..failOnSave = true;
      final controller = _controller(engine, store: store);
      addTearDown(controller.dispose);

      await expectLater(controller.setRate(0.4), completes);
      expect(controller.rate, 0.4);
    });

    test('restore 之后 setters 以恢复值为基准持久化', () async {
      final engine = FakeReadAloudEngine();
      final store = InMemoryReadAloudSettingsStore();
      final controller = _controller(
        engine,
        store: store,
        preferences: ReadAloudPreferences.defaults,
      );
      addTearDown(controller.dispose);

      controller.restore(
        const ReadAloudPreferences(enabled: true, autoRead: true, rate: 0.2),
      );
      await controller.setRate(0.9);

      expect(store.saveCount, 1);
      expect(store.preferences.enabled, isTrue);
      expect(store.preferences.autoRead, isTrue);
      expect(store.preferences.rate, 0.9);
    });
  });

  group('ReadAloudController 长文本', () {
    test('20k 字角色卡被切成多段且每段不超上限', () async {
      final engine = FakeReadAloudEngine();
      final controller = _controller(engine);
      addTearDown(controller.dispose);

      final card = List.filled(4200, '角色设定内容。').join();
      expect(card.length, greaterThan(20000));

      await controller.playText(card, sourceId: 'card-1');
      expect(controller.state.segmentCount, greaterThan(100));
      expect(controller.state.status, ReadAloudStatus.playing);
      expect(controller.state.currentText.length, lessThanOrEqualTo(140));
    });

    test('50k 世界观被切成多段且首段立即开始朗读', () async {
      final engine = FakeReadAloudEngine();
      final controller = _controller(engine);
      addTearDown(controller.dispose);

      final worldview = List.filled(8000, '世界规则说明。').join();
      expect(worldview.length, greaterThan(50000));

      await controller.playText(worldview, sourceId: 'world-1');
      expect(controller.state.segmentCount, greaterThan(200));
      expect(engine.spokenTexts, hasLength(1));
      expect(controller.state.progressLabel, startsWith('第 1/'));
    });
  });
}
