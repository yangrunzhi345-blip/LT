import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/resource_creation_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_blueprint.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/features/resource_library/presentation/screens/resource_ai_create_page.dart';
import 'package:lt_dialogue/features/resource_library/presentation/screens/resource_blueprint_review_page.dart';
import 'package:lt_dialogue/features/resource_library/presentation/screens/resource_manual_create_page.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';

import '../helpers/responsive_test_helper.dart';

void main() {
  group('Creation Workspace Phase 5 Navigation and Review Tests', () {
    final sampleBlueprint = ResourceBlueprint(
      blueprintId: 'bp_sample_01',
      sessionId: 'cre_sample_01',
      resourceType: ResourceType.worldview,
      suggestedName: '交界地编年史',
      summary: '黄金律法、半神与破碎战争的宏大纪事。',
      targetCapacity: 5000,
      sections: [
        BlueprintSection(
          id: 'sec_1',
          title: '黄金律法的起源',
          summary: '无上意志降下艾尔登流星，黄金树在交界地生根发芽。',
          parts: const [
            BlueprintPart(
              id: 'part_1',
              sectionId: 'sec_1',
              title: '艾尔登流星降临',
              generationGoal: '描述流星携带黄金兽到达交界地并形成原始黄金树。',
              estimatedLength: 1200,
            ),
            BlueprintPart(
              id: 'part_2',
              sectionId: 'sec_1',
              title: '玛莉卡登基与律法奠定',
              generationGoal: '讲述玛莉卡成为神祇并封印命定之死。',
              estimatedLength: 1300,
            ),
          ],
        ),
        BlueprintSection(
          id: 'sec_2',
          title: '阴谋之夜与破碎战争',
          summary: '黑刀之夜拉塔恩与玛莲妮亚的大战。',
          parts: const [
            BlueprintPart(
              id: 'part_3',
              sectionId: 'sec_2',
              title: '黑刀之夜',
              generationGoal: '葛德文被刺杀，死亡卢恩泄露。',
              estimatedLength: 1200,
            ),
          ],
        ),
      ],
    );

    final samplePlan = ResourceAiCreationPlan(
      creationSessionId: 'cre_sample_01',
      blueprint: sampleBlueprint,
    );

    final sampleDraft = ResourceStudioCreationDraft(
      type: ResourceType.worldview,
      name: '交界地编年史',
      referenceSource: ReferenceSource.text(
        '交界地的历史参考',
        label: '文本参考',
      ),
      targetCharacters: 5000,
    );

    for (final viewport in [
      const Size(320, 568),
      const Size(390, 844),
      const Size(768, 1024),
    ]) {
      testWidgets(
        'ResourceBlueprintReviewPage renders cleanly at ${viewport.width}x${viewport.height} without overflow',
        (tester) async {
          setViewport(tester, width: viewport.width, height: viewport.height);

          await tester.pumpWidget(
            ProviderScope(
              child: MaterialApp(
                locale: const Locale('zh'),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: ResourceBlueprintReviewPage(
                  plan: samplePlan,
                  draft: sampleDraft,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(find.text('蓝图规划确认'), findsOneWidget);
          expect(find.text('交界地编年史'), findsOneWidget);
          expect(find.text('黄金律法的起源'), findsOneWidget);
          expect(find.text('艾尔登流星降临'), findsOneWidget);
          expect(find.text('玛莉卡登基与律法奠定'), findsOneWidget);
          expect(find.text('阴谋之夜与破碎战争'), findsOneWidget);
          expect(find.text('黑刀之夜'), findsOneWidget);
          expect(find.text('蓝图规划已就绪，正文尚未生成'), findsOneWidget);
          expect(
            find.byKey(const Key('blueprint-confirm-button')),
            findsOneWidget,
          );
        },
      );
    }

    testWidgets('allows toggling part selection in Blueprint Review',
        (tester) async {
      setViewport(tester, width: 390, height: 844);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: ResourceBlueprintReviewPage(
              plan: samplePlan,
              draft: sampleDraft,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Checkbox for part_1 should be checked initially
      final checkBoxes = find.byType(Checkbox);
      expect(checkBoxes, findsNWidgets(3));

      // Tap first checkbox to uncheck
      await tester.tap(checkBoxes.first);
      await tester.pumpAndSettle();

      // Confirm button is still enabled as 2 parts remain selected
      final confirmBtn = tester.widget<FilledButton>(
        find.descendant(
          of: find.byKey(const Key('blueprint-confirm-button')),
          matching: find.byType(FilledButton),
        ),
      );
      expect(confirmBtn.onPressed, isNotNull);
    });

    testWidgets('ResourceAiCreatePage renders reference modes and validation',
        (tester) async {
      setViewport(tester, width: 390, height: 844);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            locale: Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: ResourceAiCreatePage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('AI 智能创建资源'), findsOneWidget);
      expect(find.byKey(const Key('ai-create-submit-button')), findsOneWidget);
      expect(find.byKey(const Key('ai-create-plan-button')), findsOneWidget);

      // Verify reference segmented modes: 粘贴, 文件, 已有资源
      expect(find.text('粘贴'), findsOneWidget);
      expect(find.text('文件'), findsOneWidget);
      expect(find.text('已有资源'), findsOneWidget);

      // Switch to file mode
      await tester.tap(find.text('文件'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ai-create-filename-field')), findsOneWidget);
    });

    testWidgets('ResourceManualCreatePage renders cleanly at 320x568',
        (tester) async {
      setViewport(tester, width: 320, height: 568);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            locale: Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: ResourceManualCreatePage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('手动创建资源'), findsOneWidget);
      expect(
          find.byKey(const Key('manual-create-submit-button')), findsOneWidget);
    });
  });
}
