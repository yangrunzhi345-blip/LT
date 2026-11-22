import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/domain/setting_cards/setting_card.dart';
import 'package:lt_dialogue/features/resource_library/presentation/screens/setting_card_create_page.dart';
import 'package:lt_dialogue/features/resource_library/presentation/screens/setting_card_detail_page.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';
import 'package:lt_dialogue/models/resource_library_mode.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';

import '../helpers/responsive_test_helper.dart';
import '../helpers/setting_card_fakes.dart';

void main() {
  testWidgets('detail page renders and saves at 320px', (tester) async {
    setViewport(tester, width: 320, height: 568);
    final repository = MemorySettingCardRepository();
    repository.cards['c1'] = const SettingCard(
      id: 'c1',
      kind: SettingCardKind.character,
      name: '林恩',
      summary: '游侠',
      content: '最初的设定',
      createdAt: '2026-01-01T00:00:00.000',
      updatedAt: '2026-01-01T00:00:00.000',
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        settingCardRepositoryProvider.overrideWithValue(repository),
      ],
      child: const MaterialApp(
        locale: Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingCardDetailPage(cardId: 'c1'),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('setting-card-name')), findsOneWidget);
    expect(find.byKey(const Key('setting-card-content')), findsOneWidget);
    expect(find.byKey(const Key('setting-card-save')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.enterText(
        find.byKey(const Key('setting-card-content')), '更新后的设定');
    await tester.pump();
    await tester.tap(find.byKey(const Key('setting-card-save')));
    await tester.pumpAndSettle();

    expect(repository.cards['c1']!.content, '更新后的设定');
    expect(tester.takeException(), isNull);
  });

  testWidgets('create page writes a card at 320px', (tester) async {
    setViewport(tester, width: 320, height: 568);
    final repository = MemorySettingCardRepository();

    await tester.pumpWidget(ProviderScope(
      overrides: [
        settingCardRepositoryProvider.overrideWithValue(repository),
      ],
      child: const MaterialApp(
        locale: Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingCardCreatePage(
          mode: ResourceLibraryMode.adventure,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('setting-card-create-name')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.enterText(
        find.byKey(const Key('setting-card-create-name')), '银月大陆');
    // The reference editor above the instruction field pushes the action row
    // below the 320px fold, so scroll it into view before tapping.
    await tester
        .ensureVisible(find.byKey(const Key('setting-card-create-manual')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('setting-card-create-manual')));
    await tester.pumpAndSettle();

    expect(repository.cards.values.single.name, '银月大陆');
    expect(repository.cards.values.single.mode, 'adventure');
    expect(tester.takeException(), isNull);
  });
}
