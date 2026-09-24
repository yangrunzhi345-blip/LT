import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lt_dialogue/core/widgets/app_read_aloud.dart';
import 'package:lt_dialogue/domain/read_aloud/read_aloud_contracts.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations_zh.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';
import 'package:lt_dialogue/services/read_aloud/read_aloud_controller.dart';
import 'package:lt_dialogue/services/read_aloud/text_segmenter.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';

import '../helpers/read_aloud_fakes.dart';
import '../helpers/responsive_test_helper.dart';

void main() {
  final l10n = AppLocalizationsZh();
  late FakeReadAloudEngine engine;

  ReadAloudController buildController({
    bool supported = true,
    bool supportsPause = true,
    bool enabled = true,
    TextSegmenter segmenter = const TextSegmenter(),
  }) {
    engine = FakeReadAloudEngine(
      supported: supported,
      supportsPause: supportsPause,
    );
    return ReadAloudController(
      engine: engine,
      segmenter: segmenter,
      initialPreferences: ReadAloudPreferences(enabled: enabled),
    );
  }

  Widget app(ReadAloudController controller, Widget child) {
    return ProviderScope(
      overrides: [
        readAloudControllerProvider.overrideWith(
          (ref) => controller,
          disposeNotifier: false,
        ),
      ],
      child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: Center(child: child))),
    );
  }

  Finder iconButton() => find.byType(IconButton);

  group('AppReadAloudButton', () {
    testWidgets('点击开始朗读，再点击停止，并且状态来自全局 Authority', (tester) async {
      final controller = buildController();
      await tester.pumpWidget(
        app(
          controller,
          const AppReadAloudButton(
            sourceId: 'src-1',
            sourceType: ReadAloudSourceType.generic,
            text: '第一句正文。第二句正文。',
          ),
        ),
      );

      expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget);
      expect(find.byIcon(Icons.stop_circle_outlined), findsNothing);

      await tester.tap(iconButton());
      await tester.pump();
      await tester.pump();

      expect(engine.spokenTexts, ['第一句正文。 第二句正文。']);
      expect(controller.state.status, ReadAloudStatus.playing);
      expect(controller.state.sourceId, 'src-1');
      expect(find.byIcon(Icons.stop_circle_outlined), findsOneWidget);

      await tester.tap(iconButton());
      await tester.pump();
      await tester.pump();

      expect(controller.state.status, ReadAloudStatus.stopped);
      expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget);
    });

    testWidgets('平台不支持时不渲染朗读入口（不留下死按钮）', (tester) async {
      final controller = buildController(supported: false);
      await tester.pumpWidget(
        app(
          controller,
          const AppReadAloudButton(
            sourceId: 'src-1',
            sourceType: ReadAloudSourceType.generic,
            text: '正文',
          ),
        ),
      );

      expect(iconButton(), findsNothing);
    });

    testWidgets('朗读总开关关闭时按钮禁用并说明原因', (tester) async {
      final controller = buildController(enabled: false);
      await tester.pumpWidget(
        app(
          controller,
          const AppReadAloudButton(
            sourceId: 'src-1',
            sourceType: ReadAloudSourceType.generic,
            text: '正文',
          ),
        ),
      );

      final button = tester.widget<IconButton>(iconButton());
      expect(button.onPressed, isNull);
      expect(button.tooltip, l10n.readAloudDisabledInSettings);
    });

    testWidgets('多来源（连续朗读）会按顺序朗读全部分段', (tester) async {
      final controller = buildController(
        segmenter: const TextSegmenter(maxLength: 8),
      );
      await tester.pumpWidget(
        app(
          controller,
          const AppReadAloudButton(
            sourceId: 'resource-1',
            sourceType: ReadAloudSourceType.studioResource,
            sources: [
              ReadAloudSource(id: 'part-1', text: '第一段内容。', label: 'Part 1'),
              ReadAloudSource(id: 'part-2', text: '第二段内容。', label: 'Part 2'),
            ],
          ),
        ),
      );

      await tester.tap(iconButton());
      await tester.pump();
      await tester.pump();

      expect(controller.state.segmentCount, 2);
      expect(controller.state.currentChunkId, 'part-1');
    });
  });

  group('AppReadAloudControls', () {
    testWidgets('只在会话匹配时渲染，并跟随 Authority 状态', (tester) async {
      final controller = buildController(
        segmenter: const TextSegmenter(maxLength: 8),
      );

      await tester.pumpWidget(
        app(controller, const AppReadAloudControls(sourceId: 'src-1')),
      );
      // 没有会话：不渲染。
      expect(iconButton(), findsNothing);

      await tester.pumpWidget(
        app(controller, const AppReadAloudControls(sourceId: 'other')),
      );
      await controller.playText('第一句。第二句。', sourceId: 'src-1');
      await tester.pump();
      // 会话不是自己：不渲染。
      expect(iconButton(), findsNothing);

      await tester.pumpWidget(
        app(controller, const AppReadAloudControls(sourceId: 'src-1')),
      );
      await tester.pump();
      expect(find.text(l10n.readAloudSegmentProgress(1, 2)), findsOneWidget);

      await controller.stop();
      await tester.pump();
      await tester.pump();
      expect(iconButton(), findsNothing);
    });

    testWidgets('下一段/上一段在边界内推进且不越界', (tester) async {
      final controller = buildController(
        segmenter: const TextSegmenter(maxLength: 8),
      );
      await controller.playText('第一句。第二句。', sourceId: 'src-1');
      await tester.pumpWidget(
        app(controller, const AppReadAloudControls(sourceId: 'src-1')),
      );
      await tester.pump();

      await tester.tap(find.byTooltip(l10n.readAloudNext));
      await tester.pump();
      await tester.pump();
      expect(controller.state.segmentIndex, 1);
      expect(find.text(l10n.readAloudSegmentProgress(2, 2)), findsOneWidget);

      await tester.tap(find.byTooltip(l10n.readAloudPrevious));
      await tester.pump();
      await tester.pump();
      expect(controller.state.segmentIndex, 0);
    });

    testWidgets('暂停/继续按钮反映真实状态', (tester) async {
      final controller = buildController();
      await controller.playText('只有一段。', sourceId: 'src-1');
      await tester.pumpWidget(
        app(controller, const AppReadAloudControls(sourceId: 'src-1')),
      );
      await tester.pump();

      await tester.tap(find.byTooltip(l10n.readAloudPause));
      await tester.pump();
      await tester.pump();
      expect(controller.state.status, ReadAloudStatus.paused);
      expect(find.byTooltip(l10n.readAloudResume), findsOneWidget);

      await tester.tap(find.byTooltip(l10n.readAloudResume));
      await tester.pump();
      await tester.pump();
      expect(controller.state.status, ReadAloudStatus.playing);
    });

    testWidgets('320px 窄屏下朗读控件不产生布局异常', (tester) async {
      final controller = buildController();
      await controller.playText(
        '一个用于验证窄屏布局的较长正文段落，需要在极窄宽度下也不溢出。',
        sourceId: 'src-1',
      );

      for (final size in requiredUiViewports) {
        setViewport(tester, width: size.width, height: size.height);
        await tester.pumpWidget(
          app(controller, const AppReadAloudControls(sourceId: 'src-1')),
        );
        await tester.pump();
        expect(tester.takeException(), isNull, reason: '朗读控件在 $size 下不应有布局异常');
      }
    });
  });
}
