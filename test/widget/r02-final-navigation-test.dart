// The release acceptance artifact name is fixed by the R02 specification.
// ignore_for_file: file_names

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lt_dialogue/core/router/app_router.dart';
import 'package:lt_dialogue/features/adventure/presentation/session/screens/conversation_manage_page.dart';
import 'package:lt_dialogue/features/adventure/presentation/session/screens/model_select_page.dart';
import 'package:lt_dialogue/features/settings/presentation/screens/settings_pages.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/widgets/main_sidebar.dart';

import '../helpers/responsive_test_helper.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  late Directory databaseDirectory;
  setUpAll(() async {
    databaseDirectory = await Directory.systemTemp.createTemp('lt_r02_final_');
    DatabaseService.customDbDir = databaseDirectory.path;
    await DatabaseService.resetDatabase();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });
  tearDownAll(() async {
    await DatabaseService.resetDatabase();
    if (databaseDirectory.existsSync()) {
      databaseDirectory.deleteSync(recursive: true);
    }
  });

  group('R02 final navigation', () {
    for (final size in [
      const Size(320, 568),
      const Size(360, 640),
      const Size(390, 844),
      const Size(412, 915),
    ]) {
      testWidgets('should navigate conversation, settings, sidebar at $size',
          (tester) async {
        setViewport(tester, width: size.width, height: size.height);
        if (size.width == 320) {
          tester.view.platformDispatcher.textScaleFactorTestValue = 1.3;
          addTearDown(
              tester.view.platformDispatcher.clearTextScaleFactorTestValue);
        }
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final chat = await tester.runAsync(() async {
          final provider = container.read(chatProvider);
          await provider.loadApiKey();
          return provider;
        });
        final title = '$size ${'一段很长的冒险会话名称用于验证窄屏下的管理列表不会发生横向布局溢出' * 2}';
        final id = await tester.runAsync(() => container
            .read(adventureRepoProvider)
            .createAdventure(title, AdventureConfig(name: '测试')));
        await tester.runAsync(() => chat!.loadAdventureList());
        expect(id, isNotNull);

        await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            onGenerateRoute: AppRouter.onGenerateRoute,
            home: Builder(
                builder: (context) => Scaffold(
                      body: Column(children: [
                        TextButton(
                          onPressed: () => AppRouter.push<ModelSelectionResult>(
                            context,
                            pageBuilder: (_) => const ModelSelectPage(),
                          ),
                          child: const Text('会话模型'),
                        ),
                        TextButton(
                          onPressed: () => AppRouter.push<void>(
                            context,
                            pageBuilder: (_) => const SettingsPage(),
                          ),
                          child: const Text('打开设置'),
                        ),
                        TextButton(
                          onPressed: () => AppRouter.push<void>(
                            context,
                            pageBuilder: (_) => const ConversationManagePage(),
                          ),
                          child: const Text('管理会话'),
                        ),
                      ]),
                    )),
          ),
        ));
        await tester.tap(find.text('会话模型'));
        await tester.pumpAndSettle();
        expect(find.byType(ModelSelectPage), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('返回'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('打开设置'));
        await tester.pumpAndSettle();
        expect(find.byType(SettingsPage), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('返回'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('管理会话'));
        await tester.pumpAndSettle();
        expect(find.byType(ConversationManagePage), findsOneWidget);
        expect(find.text(title), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('should require confirmation before deleting selected data',
        (tester) async {
      setViewport(tester, width: 320, height: 568);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final chat = await tester.runAsync(() async {
        final provider = container.read(chatProvider);
        await provider.loadApiKey();
        return provider;
      });
      final id = await tester.runAsync(() => container
          .read(adventureRepoProvider)
          .createAdventure('待保留会话', AdventureConfig(name: '测试')));
      await tester.runAsync(() => chat!.loadAdventureList());
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ConversationManagePage()),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('conversation-manage-$id')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('conversation-manage-delete')));
      await tester.pumpAndSettle();
      expect(find.textContaining('确定删除选中的 1 段'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      final remaining = await tester.runAsync(
          () => container.read(adventureRepoProvider).getAdventureById(id!));
      expect(remaining, isNotNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('should open sidebar management as a route', (tester) async {
      setViewport(tester, width: 390, height: 844);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final chat = await tester.runAsync(() async {
        final provider = container.read(chatProvider);
        await provider.loadApiKey();
        return provider;
      });
      await tester.runAsync(() => container
          .read(adventureRepoProvider)
          .createAdventure('侧栏会话', AdventureConfig(name: '测试')));
      await tester.runAsync(() => chat!.loadAdventureList());
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: MainSidebar(
              scaffoldKey: GlobalKey<ScaffoldState>(),
              permanent: false,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('批量管理历史对话'));
      await tester.pumpAndSettle();
      expect(find.byType(ConversationManagePage), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
