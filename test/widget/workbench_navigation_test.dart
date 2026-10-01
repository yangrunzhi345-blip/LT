import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:lt_dialogue/core/theme/app_theme.dart';
import 'package:lt_dialogue/core/widgets/app_svg_icon.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations_zh.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/models/app_section.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/widgets/main_sidebar.dart';

import '../helpers/responsive_test_helper.dart';

void main() {
  final l10n = AppLocalizationsZh();
  late Directory directory;
  late ProviderContainer container;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({'main_sidebar_expanded': true});
    directory = await Directory.systemTemp.createTemp('lt_workbench_test_');
    DatabaseService.customDbDir = directory.path;
    await DatabaseService.resetDatabase();
    container = ProviderContainer();
  });
  tearDown(() async {
    container.dispose();
    await DatabaseService.resetDatabase();
    DatabaseService.customDbDir = null;
    await directory.delete(recursive: true);
  });

  Future<void> mount(WidgetTester tester, Size size,
      {bool dark = false}) async {
    setViewport(tester, width: size.width, height: size.height);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: dark ? AppTheme.dark() : AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: Scaffold(
          body: Row(children: [
            MainSidebar(
                scaffoldKey: GlobalKey<ScaffoldState>(),
                permanent: size.width >= 600),
            if (size.width >= 600)
              const Expanded(child: Text('Workspace content')),
          ]),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  group('MainSidebar workbench navigation', () {
    for (final size in [
      ...requiredUiViewports,
      const Size(375, 812),
      const Size(1024, 768),
      const Size(1440, 900)
    ]) {
      testWidgets('should navigate and expand without overflow at $size',
          (tester) async {
        await mount(tester, size, dark: size.width == 375);
        final chat = container.read(chatProvider);
        final runtimeLink = find.text(l10n.runtimeStateCurrent);
        await tester.ensureVisible(runtimeLink);
        await tester.tap(runtimeLink);
        await tester.pumpAndSettle();
        expect(chat.currentSection, AppSection.runtimeState);
        final library = find.text(l10n.navLibrary);
        await tester.ensureVisible(library);
        await tester.tap(library);
        await tester.pumpAndSettle();
        expect(chat.currentSection, AppSection.resources);
        expect(tester.takeException(), isNull);
        if (size.width >= 600) {
          await tester.tap(find.byKey(const Key('sidebar-toggle')));
          await tester.pumpAndSettle();
          expect(find.byTooltip(l10n.runtimeStateCurrent), findsOneWidget);
          expect(find.byType(AppSvgIcon), findsWidgets);
          expect(find.byType(OverflowBox), findsNothing);
          await tester.tap(find.byTooltip(l10n.runtimeStateCurrent));
          await tester.pumpAndSettle();
          expect(chat.currentSection, AppSection.runtimeState);
          expect(tester.takeException(), isNull);
        }
      });
    }

    testWidgets(
        'should reach current characters and resume the same story in one click',
        (tester) async {
      final chat = container.read(chatProvider);
      final id = await tester
          .runAsync(() => container.read(adventureRepoProvider).createAdventure(
                '一个很长的冒险标题用于验证侧栏动态文本不会挤出删除按钮和导航操作',
                AdventureConfig(name: '测试'),
              ));
      await tester.runAsync(() => chat.openAdventure(id!));
      await tester.runAsync(chat.loadAdventureList);
      await mount(tester, const Size(1440, 900));
      await tester.tap(find.text(l10n.sceneCharactersTitle));
      await tester.pumpAndSettle();
      expect(chat.currentSection, AppSection.sceneCharacters);
      expect(chat.currentAdventureId, id);
      await tester.tap(find.text(l10n.workbenchStory));
      await tester.pumpAndSettle();
      expect(chat.currentSection, AppSection.adventure);
      expect(chat.isAdventureChatOpen, isTrue);
      expect(chat.currentAdventureId, id);
      expect(tester.takeException(), isNull);
    });
  });
}
