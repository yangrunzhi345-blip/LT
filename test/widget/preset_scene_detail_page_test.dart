import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lt_dialogue/features/adventure/presentation/templates/screens/preset_scene_detail_page.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations_zh.dart';

import '../helpers/responsive_test_helper.dart';

void main() {
  group('PresetSceneDetailPage', () {
    final l10n = AppLocalizationsZh();

    testWidgets('should render long content without overflow at 320px',
        (tester) async {
      setViewport(tester, width: 320, height: 568);
      tester.view.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(
        tester.view.platformDispatcher.clearTextScaleFactorTestValue,
      );

      final preset = PresetSceneDetailData(
        characterSummary: '一位名字很长的主角用于验证窄屏布局 · 未知 · 128 · '
            '在漫长旅途中负责记录所有历史的档案管理员',
        background: '很长的角色背景。' * 20,
        worldview: '很长的世界观设定。' * 40,
        openingScene: '很长的开场序章。' * 40,
        options: ['一个很长的行动选项。' * 12, '另一个行动选项。' * 12],
        supportingCharacters: const [],
      );

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: PresetSceneDetailPage(
            name: '一个很长的预存剧本名称用于验证标题布局',
            preset: preset,
          ),
        ),
      );

      expect(find.byType(PresetSceneDetailPage), findsOneWidget);
      expect(find.text(l10n.presetCustomizeAction), findsOneWidget);
      expect(find.text(l10n.startAdventureAction), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('should return the selected page action', (tester) async {
      setViewport(tester, width: 390, height: 844);
      PresetSceneDetailAction? result;
      const preset = PresetSceneDetailData(
        characterSummary: '测试角色 · 未知 · 20 · 旅人',
        background: '',
        worldview: '测试世界观',
        openingScene: '',
        options: [],
        supportingCharacters: [],
      );

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result =
                    await Navigator.of(context).push<PresetSceneDetailAction>(
                  MaterialPageRoute(
                    builder: (_) => const PresetSceneDetailPage(
                      name: '测试剧本',
                      preset: preset,
                    ),
                  ),
                );
              },
              child: const Text('打开详情'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开详情'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.presetCustomizeAction));
      await tester.pumpAndSettle();

      expect(result, PresetSceneDetailAction.customize);
      expect(tester.takeException(), isNull);
    });
  });
}
