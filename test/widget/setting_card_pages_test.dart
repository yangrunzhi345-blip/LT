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
    // Entering text in the last field scrolls it into view, which moves the
    // action row off-screen; scroll back before tapping save.
    await tester.ensureVisible(find.byKey(const Key('setting-card-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('setting-card-save')));
    await tester.pumpAndSettle();

    expect(repository.cards['c1']!.content, '更新后的设定');
    expect(tester.takeException(), isNull);
  });

  testWidgets('create page writes a card at 320px', (tester) async {
    // Tall enough to keep the action row on screen; 320 is the width under test
    // for horizontal overflow.
    setViewport(tester, width: 320, height: 900);
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
    await tester.tap(find.byKey(const Key('setting-card-create-manual')));
    await tester.pumpAndSettle();

    expect(repository.cards.values.single.name, '银月大陆');
    expect(repository.cards.values.single.mode, 'adventure');
    expect(tester.takeException(), isNull);
  });

  testWidgets('create page forwards the detailed length target',
      (tester) async {
    setViewport(tester, width: 320, height: 568);
    final repository = MemorySettingCardRepository();
    final gateway = FakeSettingCardGateway(
      worldviewResponse: <String, dynamic>{
        'name': '星海大陆',
        'description': '群星坠落之地。',
      },
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        settingCardRepositoryProvider.overrideWithValue(repository),
        llmGatewayProvider.overrideWithValue(gateway),
      ],
      child: const MaterialApp(
        locale: Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingCardCreatePage(mode: ResourceLibraryMode.adventure),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('setting-card-create-length-detailed')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('setting-card-create-instruction')),
      '写一个星海世界',
    );
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -1200),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('setting-card-create-ai')));
    await tester.pumpAndSettle();

    expect(gateway.targetCharacterArgs.last, 12000);
    expect(tester.takeException(), isNull);
  });

  testWidgets('detail page restores the pre-generation snapshot',
      (tester) async {
    setViewport(tester, width: 320, height: 568);
    final repository = MemorySettingCardRepository();
    repository.cards['c1'] = const SettingCard(
      id: 'c1',
      kind: SettingCardKind.character,
      name: '林恩',
      summary: '新摘要',
      content: '新正文',
      metadata: <String, Object?>{
        'previous_content_snapshot': <String, Object?>{
          'content': '旧正文',
          'summary': '旧摘要',
          'saved_at': '2026-01-01T00:00:00.000',
        },
      },
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

    expect(
      find.byKey(const Key('setting-card-restore-previous')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester
        .ensureVisible(find.byKey(const Key('setting-card-restore-previous')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('setting-card-restore-previous')));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('恢复重生成前版本'),
    ));
    await tester.pumpAndSettle();

    expect(repository.cards['c1']!.content, '旧正文');
    expect(repository.cards['c1']!.summary, '旧摘要');
    expect(
      repository.cards['c1']!.metadata.containsKey('previous_content_snapshot'),
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('create page forwards a custom length target', (tester) async {
    setViewport(tester, width: 320, height: 568);
    final repository = MemorySettingCardRepository();
    final gateway = FakeSettingCardGateway(
      worldviewResponse: <String, dynamic>{
        'name': '星海大陆',
        'description': '群星坠落之地。',
      },
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        settingCardRepositoryProvider.overrideWithValue(repository),
        llmGatewayProvider.overrideWithValue(gateway),
      ],
      child: const MaterialApp(
        locale: Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingCardCreatePage(mode: ResourceLibraryMode.adventure),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('setting-card-create-length-custom')),
    );
    await tester.pumpAndSettle();

    final customField =
        find.byKey(const Key('setting-card-create-length-custom-characters'));
    await tester.ensureVisible(customField);
    await tester.pumpAndSettle();
    await tester.enterText(customField, '7000');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.enterText(
      find.byKey(const Key('setting-card-create-instruction')),
      '写一个星海世界',
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('setting-card-create-ai')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('setting-card-create-ai')));
    await tester.pumpAndSettle();

    expect(gateway.targetCharacterArgs.last, 7000);
    expect(tester.takeException(), isNull);
  });

  testWidgets('create page blocks an out-of-range custom length',
      (tester) async {
    setViewport(tester, width: 320, height: 900);
    final repository = MemorySettingCardRepository();
    final gateway = FakeSettingCardGateway();

    await tester.pumpWidget(ProviderScope(
      overrides: [
        settingCardRepositoryProvider.overrideWithValue(repository),
        llmGatewayProvider.overrideWithValue(gateway),
      ],
      child: const MaterialApp(
        locale: Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingCardCreatePage(mode: ResourceLibraryMode.adventure),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('setting-card-create-length-custom')),
    );
    await tester.pumpAndSettle();
    final customField =
        find.byKey(const Key('setting-card-create-length-custom-characters'));
    await tester.ensureVisible(customField);
    await tester.pumpAndSettle();
    await tester.enterText(customField, '500');
    await tester.pumpAndSettle();

    // The field explains the supported range before the form is submitted.
    expect(find.text('请输入 1000–50000 之间的目标字数'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('setting-card-create-instruction')),
      '写一个星海世界',
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('setting-card-create-ai')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('setting-card-create-ai')));
    await tester.pumpAndSettle();

    expect(gateway.worldviewCalls, 0);
    expect(repository.cards, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('generate dialog disables confirm for an unusable custom target',
      (tester) async {
    setViewport(tester, width: 320, height: 568);
    final repository = MemorySettingCardRepository();
    repository.cards['c1'] = const SettingCard(
      id: 'c1',
      kind: SettingCardKind.worldview,
      name: '星海大陆',
      summary: '群星坠落之地。',
      content: '最初的设定',
      createdAt: '2026-01-01T00:00:00.000',
      updatedAt: '2026-01-01T00:00:00.000',
    );
    final gateway = FakeSettingCardGateway();

    await tester.pumpWidget(ProviderScope(
      overrides: [
        settingCardRepositoryProvider.overrideWithValue(repository),
        llmGatewayProvider.overrideWithValue(gateway),
      ],
      child: const MaterialApp(
        locale: Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingCardDetailPage(cardId: 'c1'),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('setting-card-generate')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('setting-card-generate')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('setting-card-length-custom')));
    await tester.pumpAndSettle();
    final customField =
        find.byKey(const Key('setting-card-length-custom-characters'));
    await tester.ensureVisible(customField);
    await tester.pumpAndSettle();
    await tester.enterText(customField, '30000');
    await tester.pumpAndSettle();

    FilledButton confirm() => tester.widget<FilledButton>(
          find.byKey(const Key('setting-card-generate-confirm')),
        );
    // A worldview accepts 30,000, so confirm stays usable.
    expect(confirm().onPressed, isNotNull);

    await tester.enterText(customField, '200');
    await tester.pumpAndSettle();
    expect(confirm().onPressed, isNull);
    expect(tester.takeException(), isNull);
  });
}
