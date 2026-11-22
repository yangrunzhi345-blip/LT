import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/setting_cards/setting_card_library_runtime.dart';
import 'package:lt_dialogue/application/setting_cards/setting_card_service.dart';
import 'package:lt_dialogue/domain/setting_cards/setting_card.dart';
import 'package:lt_dialogue/features/resource_library/presentation/screens/resource_library_screen.dart';
import 'package:lt_dialogue/features/resource_library/presentation/screens/setting_card_create_page.dart';
import 'package:lt_dialogue/features/resource_library/presentation/screens/setting_card_detail_page.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';

import '../helpers/localization_test_helper.dart';
import '../helpers/responsive_test_helper.dart';
import '../helpers/setting_card_fakes.dart';

const _longName =
    '一个用于验证长中文和 Long English Setting Card Name Without Internal Identifiers 的设定卡标题';
const _longSummary = '很长的简介，用来验证列表在窄屏和放大字体下仍然可读且不会产生横向溢出。';

/// Cards are the only library source now: the list, the detail page and the
/// create page all read and write the same store.
SettingCardService _seedService(MemorySettingCardRepository repository) {
  repository.cards['card_world'] = const SettingCard(
    id: 'card_world',
    kind: SettingCardKind.worldview,
    name: _longName,
    summary: _longSummary,
    content: '## 概述\n\n长夜将至，银月悬空。',
    mode: 'adventure',
    createdAt: '2026-09-18T09:00:00.000',
    updatedAt: '2026-09-18T09:00:00.000',
  );
  repository.cards['card_character'] = const SettingCard(
    id: 'card_character',
    kind: SettingCardKind.character,
    name: '林舟',
    summary: '守夜人',
    mode: 'adventure',
    createdAt: '2026-09-17T09:00:00.000',
    updatedAt: '2026-09-17T09:00:00.000',
  );
  return SettingCardService(repository: repository);
}

Future<MemorySettingCardRepository> _pumpLibrary(
  WidgetTester tester, {
  double textScale = 1,
  MemorySettingCardRepository? repository,
  bool seed = true,
}) async {
  final cards = repository ?? MemorySettingCardRepository();
  final service =
      seed ? _seedService(cards) : SettingCardService(repository: cards);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        settingCardServiceProvider.overrideWithValue(service),
        resourceLibraryRuntimeProvider
            .overrideWithValue(SettingCardLibraryRuntime(service: service)),
      ],
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: const ResourceLibraryScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return cards;
}

void main() {
  group('ResourceLibraryScreen Phase 11', () {
    for (final viewport in requiredUiViewports) {
      testWidgets(
        'should render at ${viewport.width}x${viewport.height} without overflow',
        (tester) async {
          setViewport(
            tester,
            width: viewport.width,
            height: viewport.height,
          );
          await _pumpLibrary(tester);

          expect(tester.takeException(), isNull);
          expect(
              find.byKey(const Key('resource-create-button')), findsOneWidget);
          expect(
              find.byKey(const Key('resource-search-field')), findsOneWidget);
          expect(
            find.byKey(const ValueKey<String>('resource-card-card_world')),
            findsOneWidget,
          );
          expect(find.text('已保存'), findsWidgets);
          expect(find.text('可用于冒险'), findsWidgets);
        },
      );
    }

    testWidgets('should open the card creation page from the create button',
        (tester) async {
      setViewport(tester, width: 320, height: 568);
      await _pumpLibrary(tester);

      await tester.tap(find.byKey(const Key('resource-create-button')));
      await tester.pumpAndSettle();

      expect(find.byType(SettingCardCreatePage), findsOneWidget);
      expect(find.byKey(const Key('setting-card-create-name')), findsOneWidget);
      expect(
          find.byKey(const Key('setting-card-create-manual')), findsOneWidget);
      expect(find.textContaining('导入'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('should search and filter cards', (tester) async {
      setViewport(tester, width: 390, height: 844);
      await _pumpLibrary(tester);

      await tester.enterText(
        find.byKey(const Key('resource-search-field')),
        '守夜人',
      );
      await tester.pumpAndSettle();
      expect(find.text('林舟'), findsOneWidget);
      expect(find.text(_longName), findsNothing);

      await tester.enterText(
        find.byKey(const Key('resource-search-field')),
        '',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
        of: find.byKey(const Key('resource-filter')),
        matching: find.text('世界观'),
      ));
      await tester.pumpAndSettle();
      expect(find.text(_longName), findsOneWidget);
      expect(find.text('林舟'), findsNothing);
    });

    testWidgets('should navigate from a card to the card detail page',
        (tester) async {
      setViewport(tester, width: 390, height: 844);
      await _pumpLibrary(tester);
      await tester.tap(
        find.byKey(const ValueKey<String>('resource-card-card_world')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SettingCardDetailPage), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('setting-card-detail-card_world')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('setting-card-name')), findsOneWidget);
      expect(find.byKey(const Key('setting-card-summary')), findsOneWidget);
      expect(find.byKey(const Key('setting-card-content')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    for (final viewport in requiredUiViewports.take(4)) {
      testWidgets(
        'detail actions fit at ${viewport.width}x${viewport.height}',
        (tester) async {
          setViewport(
            tester,
            width: viewport.width,
            height: viewport.height,
          );
          await _pumpLibrary(tester);
          await tester.tap(
            find.byKey(
              const ValueKey<String>('resource-card-card_world'),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.byKey(const Key('setting-card-save')), findsOneWidget);
          expect(find.byKey(const Key('setting-card-delete')), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('cancel keeps the card and does not delete it', (tester) async {
      setViewport(tester, width: 390, height: 844);
      final cards = await _pumpLibrary(tester);
      await tester.tap(
        find.byKey(const ValueKey<String>('resource-card-card_world')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('setting-card-delete')));
      await tester.pumpAndSettle();

      expect(find.text('删除设定卡'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(cards.cards['card_world']!.isDeleted, isFalse);
      expect(find.byType(SettingCardDetailPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('confirmed delete returns to the list and removes the card',
        (tester) async {
      setViewport(tester, width: 390, height: 844);
      final cards = await _pumpLibrary(tester);
      await tester.tap(
        find.byKey(const ValueKey<String>('resource-card-card_world')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('setting-card-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();

      expect(cards.cards['card_world']!.isDeleted, isTrue);
      expect(find.byType(SettingCardDetailPage), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('resource-card-card_world')),
        findsNothing,
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('app-feedback-message'))).data,
        '已移入回收站',
      );
      expect(tester.takeException(), isNull);
      // Let the transient feedback timer retire before the test ends.
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets(
        'manual creation opens the card detail and Back returns to list',
        (tester) async {
      setViewport(tester, width: 390, height: 844);
      final cards = await _pumpLibrary(
        tester,
        repository: MemorySettingCardRepository(),
        seed: false,
      );
      expect(find.text('还没有资源'), findsOneWidget);

      await tester.tap(find.byKey(const Key('resource-create-button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('setting-card-create-name')),
        '手工设定卡',
      );
      final manual = find.byKey(const Key('setting-card-create-manual'));
      await tester.ensureVisible(manual);
      await tester.pumpAndSettle();
      await tester.tap(manual);
      await tester.pumpAndSettle();

      expect(find.byType(SettingCardDetailPage), findsOneWidget);
      expect(find.byKey(const Key('setting-card-name')), findsOneWidget);
      expect(cards.cards.values.single.name, '手工设定卡');

      await localizedPageBack(tester);
      await tester.pumpAndSettle();

      expect(find.byType(SettingCardDetailPage), findsNothing);
      expect(find.text('手工设定卡'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('save card content persists it', (tester) async {
      setViewport(tester, width: 390, height: 844);
      final cards = await _pumpLibrary(tester);
      await tester.tap(
        find.byKey(const ValueKey<String>('resource-card-card_world')),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('setting-card-content')),
        '更新后的设定正文',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('setting-card-save')));
      await tester.pumpAndSettle();

      expect(cards.cards['card_world']!.content, '更新后的设定正文');
      expect(
        tester.widget<Text>(find.byKey(const Key('app-feedback-message'))).data,
        '已保存',
      );
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('should survive large text and keyboard in creation flow',
        (tester) async {
      setViewport(tester, width: 320, height: 568);
      tester.view.viewInsets = const FakeViewPadding(bottom: 240);
      addTearDown(tester.view.resetViewInsets);
      await _pumpLibrary(tester, textScale: 1.6);
      await tester.tap(find.byKey(const Key('resource-create-button')));
      await tester.pumpAndSettle();

      expect(find.byType(SettingCardCreatePage), findsOneWidget);
      final name = find.byKey(const Key('setting-card-create-name'));
      await tester.ensureVisible(name);
      await tester.pumpAndSettle();
      expect(name, findsOneWidget);
      expect(
        MediaQuery.viewInsetsOf(
                tester.element(find.byType(SettingCardCreatePage)))
            .bottom,
        240,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('should not leak implementation terminology', (tester) async {
      setViewport(tester, width: 390, height: 844);
      await _pumpLibrary(tester);
      final forbidden = <String>[
        'Part',
        'revision ID',
        'JSON',
        'absolute limit',
        'compression job',
        'assembly revision',
      ];
      for (final term in forbidden) {
        expect(find.textContaining(term), findsNothing);
      }
    });
  });
}
