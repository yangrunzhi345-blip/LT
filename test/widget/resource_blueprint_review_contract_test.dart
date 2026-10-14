import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/resource_creation_contracts.dart';
import 'package:lt_dialogue/core/widgets/app_action_button.dart';
import 'package:lt_dialogue/domain/resources/content_requirements.dart';
import 'package:lt_dialogue/domain/resources/resource_blueprint.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/features/resource_library/presentation/screens/resource_blueprint_review_page.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';

import '../helpers/responsive_test_helper.dart';

/// U6-B: the blueprint review page must show each Part's client contract
/// (kind + minimum) and must refuse to start generation while any Part is
/// unresolved (no contract).
void main() {
  BlueprintPart part(String id, {ContentRequirements? contract}) =>
      BlueprintPart(
        id: id,
        sectionId: 'sec',
        title: '段落 $id',
        generationGoal: '生成正文',
        estimatedLength: 1000,
        contentRequirements: contract,
      );

  ContentRequirements narrative(int minimum) => ContentRequirements(
        kind: PartContentKind.narrative,
        minimumCharacters: minimum,
        validationProfile: PartValidationProfile.narrativeSectionsV1,
      );

  ResourceAiCreationPlan planWith(List<BlueprintPart> parts) =>
      ResourceAiCreationPlan(
        creationSessionId: 'cs',
        blueprint: ResourceBlueprint(
          blueprintId: 'bp',
          sessionId: 'cs',
          resourceType: ResourceType.worldview,
          suggestedName: '资源',
          summary: '',
          targetCapacity: 5000,
          contentContractVersion: 1,
          sections: [BlueprintSection(id: 'sec', title: '章节', parts: parts)],
        ),
      );

  const draft = ResourceStudioCreationDraft(
    type: ResourceType.worldview,
    name: '资源',
    referenceSource:
        ReferenceSource(kind: ReferenceSourceKind.text, body: '参考'),
    targetCharacters: 5000,
  );

  Widget wrap(ResourceAiCreationPlan plan, {double textScale = 1}) =>
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: ResourceBlueprintReviewPage(plan: plan, draft: draft),
        ),
      );

  bool confirmEnabled(WidgetTester tester) =>
      tester
          .widget<AppPrimaryButton>(
              find.byKey(const Key('blueprint-confirm-button')))
          .onPressed !=
      null;

  testWidgets('shows each part contract and enables confirm when resolved',
      (tester) async {
    setViewport(tester, width: 390, height: 844);
    await tester
        .pumpWidget(wrap(planWith([part('a', contract: narrative(400))])));
    await tester.pumpAndSettle();

    expect(find.textContaining('最低 400 字'), findsOneWidget);
    expect(
        find.byKey(const Key('blueprint-contract-gap-notice')), findsNothing);
    expect(confirmEnabled(tester), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('blocks confirm and warns when a part has no contract',
      (tester) async {
    setViewport(tester, width: 390, height: 844);
    await tester.pumpWidget(wrap(planWith([part('a')])));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const Key('blueprint-contract-gap-notice')), findsOneWidget);
    expect(find.textContaining('无内容契约'), findsOneWidget);
    expect(confirmEnabled(tester), isFalse, reason: '存在未确定契约的段落时不得开始生成');
    expect(tester.takeException(), isNull);
  });

  for (final scale in [1.0, 1.8]) {
    testWidgets('fits 320px with textScale $scale', (tester) async {
      setViewport(tester, width: 320, height: 568);
      await tester.pumpWidget(wrap(
        planWith([part('a', contract: narrative(400)), part('b')]),
        textScale: scale,
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('blueprint-contract-gap-notice')),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
