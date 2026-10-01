import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lt_dialogue/application/narrative/context_weighting.dart';
import 'package:lt_dialogue/features/adventure/presentation/session/screens/adventure_session_screen.dart';
import 'package:lt_dialogue/features/adventure/presentation/session/widgets/session_inspector.dart';
import 'package:lt_dialogue/features/adventure/presentation/session/widgets/session_message_list.dart';
import 'package:lt_dialogue/features/prompt_settings/presentation/screens/context_weight_controls.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations_zh.dart';
import 'package:lt_dialogue/main.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/models/dialogue_level.dart';
import 'package:lt_dialogue/models/llm_provider.dart';
import 'package:lt_dialogue/models/message.dart';
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
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
      (_) async => null,
    );
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({'main_sidebar_expanded': true});
    directory = await Directory.systemTemp.createTemp('lt_session_workbench_');
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

  Future<void> mount(WidgetTester tester,
      {Widget? home, double scale = 1.5}) async {
    await tester.runAsync(
        () => container.read(chatProvider).settingsProvider.loadApiKey());
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData.dark(useMaterial3: true),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: home ?? const AdventureSessionScreen(),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> persist(WidgetTester tester, Future<void> Function() action,
      bool Function() isSaved) async {
    await action();
    for (var attempt = 0; attempt < 20 && !isSaved(); attempt++) {
      // Flush the real SQLite queue, then process UI continuations in the test zone.
      await tester.runAsync(
          () => container.read(settingsRepoProvider).getAllSettings());
      await tester.pump();
    }
    expect(isSaved(), isTrue,
        reason: 'The original settings authority must persist the change');
    await tester.pumpAndSettle();
  }

  for (final size in [
    ...requiredUiViewports,
    const Size(375, 812),
    const Size(1024, 768),
    const Size(1440, 900)
  ]) {
    testWidgets('Session Context is direct and responsive at $size',
        (tester) async {
      setViewport(tester, width: size.width, height: size.height);
      await mount(tester);
      await tester.tap(find.byKey(const Key('session-context')));
      await tester.pumpAndSettle();
      expect(find.byType(SessionInspector), findsOneWidget);
      expect(find.byType(ContextWeightControls), findsOneWidget);
      await persist(
          tester,
          () => tester.tap(find.byKey(const Key('context-preset-highControl'))),
          () =>
              container
                  .read(chatProvider)
                  .settingsProvider
                  .contextWeightProfile
                  .presetId ==
              'highControl');
      expect(
          container
              .read(chatProvider)
              .settingsProvider
              .contextWeightProfile
              .presetId,
          'highControl');
      await persist(
          tester,
          () => tester.tap(find.byKey(const Key('context-preset-custom'))),
          () =>
              container
                  .read(chatProvider)
                  .settingsProvider
                  .contextWeightProfile
                  .presetId ==
              'custom');
      final settings = container.read(chatProvider).settingsProvider;
      expect(settings.contextWeightProfile.weights,
          ContextWeightPresets.highControl.weights);
      final sliderFinder =
          find.byKey(const ValueKey('context-weight-userControl'));
      await tester.ensureVisible(sliderFinder);
      await tester.pumpAndSettle();
      final slider = tester.widget<Slider>(sliderFinder);
      slider.onChanged!(37);
      await tester.pump();
      await persist(tester, () async {
        tester.widget<Slider>(sliderFinder).onChangeEnd!(37);
      },
          () =>
              settings.contextWeightProfile[ContextSourceId.userControl] == 37);
      expect(settings.contextWeightProfile[ContextSourceId.userControl], 37);
      await tester.runAsync(settings.loadApiKey);
      await tester.pumpAndSettle();
      expect(settings.contextWeightProfile.presetId, 'custom');
      expect(settings.contextWeightProfile[ContextSourceId.userControl], 37);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Reply length persists after exactly open and select',
      (tester) async {
    setViewport(tester, width: 320, height: 640);
    await mount(tester);
    await tester.tap(find.byKey(const Key('session-reply-length')));
    await tester.pumpAndSettle();
    final option = find.byWidgetPredicate((widget) =>
        widget is PopupMenuItem<DialogueLevel> &&
        widget.value == DialogueLevel.l1);
    await persist(
        tester,
        () => tester.tap(option),
        () =>
            container.read(chatProvider).settingsProvider.dialogueLevel ==
            DialogueLevel.l1);
    final settings = container.read(chatProvider).settingsProvider;
    expect(settings.dialogueLevel, DialogueLevel.l1);
    await tester.runAsync(settings.loadApiKey);
    expect(settings.dialogueLevel, DialogueLevel.l1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Model open and selection applies without a confirm step',
      (tester) async {
    setViewport(tester, width: 1024, height: 900);
    await tester.runAsync(() => container
        .read(chatProvider)
        .setProviderAndModel(LLMProvider.deepseek, 'deepseek-v4-pro'));
    await mount(tester, scale: 1);
    expect(container.read(chatProvider).modelName, 'deepseek-v4-pro');
    await tester.tap(find.byKey(const Key('session-model')));
    await tester.pumpAndSettle();
    await persist(tester, () => tester.tap(find.text('deepseek-flash').first),
        () => container.read(chatProvider).modelName == 'deepseek-flash');
    expect(container.read(chatProvider).modelName, 'deepseek-flash');
    expect(find.byType(AdventureSessionScreen), findsOneWidget);
    expect(find.byKey(const Key('session-model')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Root focus keeps the Session, draft and reader controller',
      (tester) async {
    setViewport(tester, width: 1440, height: 900);
    final chat = container.read(chatProvider);
    final id = await tester.runAsync(() => container
        .read(adventureRepoProvider)
        .createAdventure('草稿和阅读位置测试', AdventureConfig(name: '测试')));
    await tester.runAsync(() => chat.openAdventure(id!));
    chat.adventureProvider.setMessages(List.generate(
        30,
        (index) => Message(
            id: '$index',
            content: '叙事段落 $index。${'长文阅读测试。' * 50}',
            isUser: false)));
    await mount(tester,
        home:
            const MainGate(showApiDialogOnInit: false, skipSplashOnInit: true),
        scale: 1);
    expect(find.byType(MainSidebar), findsOneWidget);
    final input = find.byType(TextField).last;
    await tester.enterText(input, '尚未发送的草稿');
    final reader =
        tester.widget<SessionMessageList>(find.byType(SessionMessageList));
    reader.scrollController.jumpTo(200);
    await tester.pump();
    final controller = tester.widget<TextField>(input).controller;
    await tester.tap(find.byKey(const Key('session-focus-reading')));
    await tester.pumpAndSettle();
    expect(find.byType(MainSidebar), findsNothing);
    expect(find.byType(SessionInspector), findsNothing);
    expect(tester.widget<TextField>(find.byType(TextField).last).controller,
        same(controller));
    expect(controller!.text, '尚未发送的草稿');
    expect(
        tester
            .widget<SessionMessageList>(find.byType(SessionMessageList))
            .scrollController,
        same(reader.scrollController));
    expect(reader.scrollController.offset, closeTo(200, 1));
    await tester.tap(find.byTooltip(l10n.workbenchExitFocusReading));
    await tester.pumpAndSettle();
    expect(find.byType(MainSidebar), findsOneWidget);
    expect(controller.text, '尚未发送的草稿');
    expect(reader.scrollController.offset, closeTo(200, 1));
    expect(tester.takeException(), isNull);
  });
}
