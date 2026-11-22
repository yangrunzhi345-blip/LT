import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:lt_dialogue/application/setting_cards/setting_card_service.dart';
import 'package:lt_dialogue/core/router/app_router.dart';
import 'package:lt_dialogue/core/widgets/app_text_field.dart';
import 'package:lt_dialogue/core/widgets/main_sidebar.dart';
import 'package:lt_dialogue/core/widgets/workbench_chrome.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/setting_cards/setting_card.dart';
import 'package:lt_dialogue/features/resource_library/presentation/screens/resource_library_screen.dart';
import 'package:lt_dialogue/features/resource_library/presentation/screens/setting_card_create_page.dart';
import 'package:lt_dialogue/features/resource_library/presentation/screens/setting_card_detail_page.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';
import 'package:lt_dialogue/main.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/repositories/setting_card_repository_impl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/localization_test_helper.dart';
import '../helpers/responsive_test_helper.dart';

/// Locates a workbench sidebar destination (the label also appears as a page
/// title in the workspace, so the sidebar subtree is scoped explicitly).
Finder _sidebarLabel(String label) => find.descendant(
      of: find.byType(MainSidebar),
      matching: find.text(label),
    );

/// The production card store, backed by the real SQLite database.
SettingCardService _cardService() => SettingCardService(
      repository: SettingCardRepositoryImpl(
        getDb: () => DatabaseService.database,
      ),
    );

Future<List<Map<String, Object?>>> _settingCardRows(WidgetTester tester) async {
  final rows = await tester.runAsync(
    () async => (await DatabaseService.database).query('setting_cards'),
  );
  return rows!;
}

Finder _filterTab(String label) => find.descendant(
      of: find.byKey(const Key('resource-filter')),
      matching: find.text(label),
    );

Future<void> _pumpLibraryRoute(
  WidgetTester tester, {
  Finder? waitFor,
}) async {
  await tester.pumpWidget(
    const ProviderScope(
      child: MaterialApp(
        locale: Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        initialRoute: AppRouter.resourceLibraryPath,
        onGenerateRoute: AppRouter.onGenerateRoute,
      ),
    ),
  );
  await _waitFor(tester, waitFor ?? find.text('还没有资源'));
}

/// Creates one card through the card creation page and waits for its detail.
Future<void> _createCard(
  WidgetTester tester, {
  required String name,
  String? type,
}) async {
  await tester.tap(find.byKey(const Key('resource-create-button')));
  await tester.pumpAndSettle();
  if (type != null) {
    await tester.tap(find.byKey(const Key('setting-card-create-type')));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
      of: find.byType(BottomSheet),
      matching: find.text(type),
    ));
    await tester.pumpAndSettle();
  }
  await tester.enterText(
    find.byKey(const Key('setting-card-create-name')),
    name,
  );
  final submit = find.byKey(const Key('setting-card-create-manual'));
  await tester.ensureVisible(submit);
  await tester.pumpAndSettle();
  await tester.tap(submit);
  await _waitFor(tester, find.byType(SettingCardDetailPage));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;
  late Directory directory;

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel(
                'dev.fluttercommunity.plus/connectivity_status'),
            (_) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('dev.fluttercommunity.plus/connectivity'),
            (_) async => ['wifi']);
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('lt_p11_widget_');
    DatabaseService.customDbDir = directory.path;
    await DatabaseService.resetDatabase();
    await DatabaseService.database;
  });
  tearDown(() async {
    await DatabaseService.resetDatabase();
    DatabaseService.customDbDir = null;
    await directory.delete(recursive: true);
  });

  group('Phase 11 production assembly', () {
    testWidgets(
        'should open the library from the sidebar and create a card through production wiring',
        (tester) async {
      setViewport(tester, width: 1280, height: 900);
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            locale: Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: MainGate(
              showApiDialogOnInit: false,
              skipSplashOnInit: true,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // The workbench sidebar is the single navigation authority: open the
      // library from it, not from a deep-link route.
      await tester.tap(_sidebarLabel('资料库'));
      await _waitFor(tester, find.text('还没有资源'));

      await _createCard(tester, name: '生产设定卡');

      final rows = await _settingCardRows(tester);
      expect(rows, hasLength(1));
      expect(rows.single['name'], '生产设定卡');
      expect(rows.single['kind'], 'worldview');
      expect(rows.single['mode'], 'adventure');
      expect(rows.single['deleted_at'], isNull);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('should create a card, open its detail, and return to the list',
        (tester) async {
      setViewport(tester, width: 390, height: 844);
      await _pumpLibraryRoute(tester);

      await _createCard(tester, name: '手工生产设定卡');

      expect(find.byKey(const Key('setting-card-name')), findsOneWidget);
      expect(
        tester
            .widget<AppTextField>(find.byKey(const Key('setting-card-name')))
            .controller
            ?.text,
        '手工生产设定卡',
      );

      await localizedPageBack(tester);
      await tester.pumpAndSettle();
      await _waitFor(tester, find.byType(ResourceLibraryScreen));
      await _waitFor(tester, find.text('手工生产设定卡'));

      expect(find.byType(SettingCardDetailPage), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('should save card content and reload it from SQLite',
        (tester) async {
      setViewport(tester, width: 390, height: 844);
      await _pumpLibraryRoute(tester);

      await _createCard(tester, name: '可保存设定卡');

      await tester.enterText(
        find.byKey(const Key('setting-card-content')),
        '真实保存的设定正文',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('setting-card-save')));
      await _waitFor(tester, find.text('已保存'));

      final saved = await _settingCardRows(tester);
      expect(saved.single['content'], '真实保存的设定正文');

      // Reopen the card from the library: the persisted body is what renders.
      await localizedPageBack(tester);
      await tester.pumpAndSettle();
      await _waitFor(tester, find.text('可保存设定卡'));
      await tester.tap(
        find.byKey(
          ValueKey<String>('resource-card-${saved.single['id']}'),
        ),
      );
      await _waitFor(tester, find.byType(SettingCardDetailPage));
      expect(
        tester
            .widget<AppTextField>(find.byKey(const Key('setting-card-content')))
            .controller
            ?.text,
        '真实保存的设定正文',
      );
      expect(tester.takeException(), isNull);

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('should delete a card from its detail and refresh the library',
        (tester) async {
      setViewport(tester, width: 390, height: 844);
      await tester.runAsync(
        () => _cardService().create(
          kind: SettingCardKind.character,
          name: '待删除的设定卡',
          mode: 'adventure',
        ),
      );
      await _pumpLibraryRoute(tester, waitFor: find.text('待删除的设定卡'));

      final rows = await _settingCardRows(tester);
      final cardId = rows.single['id']! as String;
      await tester.tap(
        find.byKey(ValueKey<String>('resource-card-$cardId')),
      );
      await _waitFor(tester, find.byType(SettingCardDetailPage));

      await tester.tap(find.byKey(const Key('setting-card-delete')));
      await tester.pumpAndSettle();
      expect(find.text('删除设定卡'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await _waitFor(tester, find.text('还没有资源'));

      final deleted = await _settingCardRows(tester);
      expect(deleted.single['deleted_at'], isNotNull);
      expect(find.byType(SettingCardDetailPage), findsNothing);
      expect(
        find.byKey(ValueKey<String>('resource-card-$cardId')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    for (final type in ResourceType.values) {
      final tabLabel = switch (type) {
        ResourceType.worldview => '世界观',
        ResourceType.character => '角色',
        ResourceType.npc => 'NPC',
      };
      testWidgets('should create, save and reload a ${type.name} card',
          (tester) async {
        setViewport(tester, width: 390, height: 844);
        await _pumpLibraryRoute(tester);

        await tester.enterText(
            find.byKey(const Key('resource-search-field')), '测试');
        await tester.pumpAndSettle();
        await tester.tap(_filterTab(tabLabel));
        await tester.pumpAndSettle();

        final name = '测试${type.name}';
        await _createCard(tester, name: name, type: tabLabel);

        await tester.enterText(
          find.byKey(const Key('setting-card-content')),
          '真实保存的${type.name}正文',
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('setting-card-save')));
        await _waitFor(tester, find.text('已保存'));

        final rows = await _settingCardRows(tester);
        expect(rows.single['kind'], type.name);
        expect(rows.single['content'], '真实保存的${type.name}正文');

        await localizedPageBack(tester);
        await tester.pumpAndSettle();
        await _waitFor(tester, find.text(name));

        final filter = tester.widget<WorkbenchTabButton>(
            find.byKey(ValueKey('resource-filter-${type.name}')));
        expect(filter.selected, isTrue);
        expect(find.byType(SettingCardCreatePage), findsNothing);
        expect(tester.takeException(), isNull);

        await tester.pump(const Duration(seconds: 5));
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      });
    }

    testWidgets('should submit with keyboard large text and safe area at 320',
        (tester) async {
      setViewport(tester, width: 320, height: 568);
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 16);
      tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 16);
      await tester.pumpWidget(ProviderScope(
          child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        initialRoute: AppRouter.resourceLibraryPath,
        onGenerateRoute: AppRouter.onGenerateRoute,
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!),
      )));
      await _waitFor(tester, find.text('还没有资源'));
      final libraryContext = tester.element(find.byType(ResourceLibraryScreen));
      expect(MediaQuery.sizeOf(libraryContext), const Size(320, 568));
      expect(MediaQuery.paddingOf(libraryContext).top, 24);

      await tester.tap(find.byKey(const Key('resource-create-button')));
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 240);
      await tester.pumpAndSettle();
      expect(
          MediaQuery.viewInsetsOf(
                  tester.element(find.byType(SettingCardCreatePage)))
              .bottom,
          240);

      final name = find.byKey(const Key('setting-card-create-name'));
      await tester.ensureVisible(name);
      await tester.pumpAndSettle();
      await tester.enterText(name, '长名称 Long Setting Card Name 用于小屏真实提交');
      final summary = find.byKey(const Key('setting-card-create-summary'));
      await tester.ensureVisible(summary);
      await tester.pumpAndSettle();
      await tester.enterText(summary, '安全区和软键盘同时存在时，滚动填写并提交。');

      // The soft keyboard shrinks the viewport below the action row, so scroll
      // the form to its end before submitting instead of relying on a hit test
      // that lands under the keyboard.
      final pageScrollable = find
          .descendant(
            of: find.byType(SettingCardCreatePage),
            matching: find.byType(Scrollable),
          )
          .first;
      // The focused field keeps itself visible, so drop focus before scrolling to
      // the action row.
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      final scrollableState = tester.state<ScrollableState>(pageScrollable);
      scrollableState.position.jumpTo(scrollableState.position.maxScrollExtent);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('setting-card-create-manual')));
      await _waitFor(tester, find.byType(SettingCardDetailPage));

      final rows = await _settingCardRows(tester);
      expect(rows.single['name'], '长名称 Long Setting Card Name 用于小屏真实提交');
      expect(rows.single['summary'], '安全区和软键盘同时存在时，滚动填写并提交。');
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}

// SQLite uses real asynchronous I/O; yield to it outside the fake widget clock
// and stop as soon as the observable UI condition is true.
Future<void> _waitFor(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) {
      await tester.pump(const Duration(milliseconds: 300));
      return;
    }
  }
  expect(finder, findsWidgets,
      reason: tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data)
          .join('\n'));
}
