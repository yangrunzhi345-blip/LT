import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lt_dialogue/core/theme/app_theme.dart';
import 'package:lt_dialogue/core/widgets/workbench_chrome.dart';
import 'package:lt_dialogue/features/adventure/presentation/session/screens/adventure_session_screen.dart';
import 'package:lt_dialogue/features/adventure/presentation/session/screens/model_select_page.dart';
import 'package:lt_dialogue/features/adventure/presentation/session/screens/session_inspector_page.dart';
import 'package:lt_dialogue/features/adventure/presentation/session/widgets/reply_length_control.dart';
import 'package:lt_dialogue/features/adventure/presentation/session/widgets/session_message_list.dart';
import 'package:lt_dialogue/features/prompt_settings/presentation/screens/context_weight_controls.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations_zh.dart';
import 'package:lt_dialogue/models/app_section.dart';
import 'package:lt_dialogue/models/message.dart';
import 'package:lt_dialogue/providers/chat_provider.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';
import 'package:lt_dialogue/screens/chat/widgets/inventory_screen.dart';
import 'package:lt_dialogue/services/database_service.dart';

import '../helpers/responsive_test_helper.dart';

/// A provider whose generation state can be driven without a network call.
class _TestChatProvider extends ChatProvider {
  bool _mockStreaming = false;

  @override
  bool get isStreaming => _mockStreaming;

  void setMockStreaming(bool value) {
    _mockStreaming = value;
    stateVersion.value++;
    notifyListeners();
  }
}

/// The Inspector is a standalone pushed page on every viewport. This suite
/// locks that contract: no modal sheet, dialog, overlay or inline pane, and a
/// plain `push` so the live session underneath keeps its draft, scroll and
/// generation state.
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
    directory = await Directory.systemTemp.createTemp('lt_inspector_nav_');
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

  Future<void> mount(
    WidgetTester tester, {
    required double width,
    double height = 900,
    double scale = 1.0,
    bool dark = false,
    bool settle = true,
    ProviderContainer? withContainer,
  }) async {
    final active = withContainer ?? container;
    setViewport(tester, width: width, height: height);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: active,
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: dark ? AppTheme.dark() : AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: const AdventureSessionScreen(),
      ),
    ));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      // A live stream animates forever; settle would time out.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  Future<void> openInspector(WidgetTester tester, {bool settle = true}) async {
    await tester.tap(find.byKey(const Key('session-inspector-toggle')));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }
  }

  void expectStandalonePage(WidgetTester tester) {
    expect(find.byType(SessionInspectorPage), findsOneWidget);
    expect(find.byKey(const Key('session-inspector-page')), findsOneWidget);
    // No modal presentation of any kind.
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    // The live session stays mounted underneath the pushed page.
    expect(find.byType(AdventureSessionScreen, skipOffstage: false),
        findsOneWidget);
  }

  group('Inspector is a standalone page on every viewport', () {
    for (final width in const <double>[320, 375, 600, 960, 1100, 1280, 1440]) {
      testWidgets('opens a pushed page (not a sheet) at ${width}px',
          (tester) async {
        await mount(tester, width: width, height: 760);
        expect(find.byType(AdventureSessionScreen), findsOneWidget);

        await openInspector(tester);

        expectStandalonePage(tester);
        expect(find.byType(ModalBottomSheetRoute), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Entry points resolve to the Inspector page', () {
    testWidgets('AppBar toggle opens the page', (tester) async {
      await mount(tester, width: 1280);
      await openInspector(tester);
      expectStandalonePage(tester);
    });

    testWidgets('Context shortcut opens the page on the context section',
        (tester) async {
      await mount(tester, width: 1280);
      await tester.tap(find.byKey(const Key('session-context')));
      await tester.pumpAndSettle();

      expectStandalonePage(tester);
      expect(find.byType(ContextWeightControls), findsOneWidget);
      expect(
        tester
            .widget<WorkbenchTabButton>(
                find.byKey(const ValueKey('inspector-context')))
            .selected,
        isTrue,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('Section navigation happens inside one page', () {
    testWidgets('tabs switch content without pushing new routes',
        (tester) async {
      await mount(tester, width: 1280);
      await openInspector(tester);

      await tester.tap(find.byKey(const ValueKey('inspector-characters')));
      await tester.pumpAndSettle();
      expect(find.text(l10n.sceneCharactersPresent), findsWidgets);
      expect(find.byType(SessionInspectorPage, skipOffstage: false),
          findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('inspector-state')));
      await tester.pumpAndSettle();
      expect(
          find.textContaining('${l10n.runtimeStateFieldHp}:'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('inspector-context')));
      await tester.pumpAndSettle();
      expect(find.byType(ContextWeightControls), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('inspector-generation')));
      await tester.pumpAndSettle();
      expect(find.byType(ReplyLengthControl), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('inspector-scene')));
      await tester.pumpAndSettle();
      expect(find.byType(SessionInspectorPage, skipOffstage: false),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Back returns to the live session', () {
    testWidgets('back pops the page and keeps the session and messages',
        (tester) async {
      await mount(tester, width: 1280);
      container
          .read(chatProvider)
          .adventureProvider
          .setMessages([Message(id: 'a', content: '这段叙事应当保留', isUser: false)]);
      await tester.pump();

      await openInspector(tester);
      await tester.tap(find.byKey(const ValueKey('inspector-context')));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip(l10n.backAction));
      await tester.pumpAndSettle();

      expect(find.byType(SessionInspectorPage), findsNothing);
      expect(find.byType(AdventureSessionScreen), findsOneWidget);
      expect(find.text('这段叙事应当保留'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('reopening restores the last inspected section',
        (tester) async {
      await mount(tester, width: 1280);
      await openInspector(tester);
      await tester.tap(find.byKey(const ValueKey('inspector-context')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(l10n.backAction));
      await tester.pumpAndSettle();

      await openInspector(tester);

      expect(
        tester
            .widget<WorkbenchTabButton>(
                find.byKey(const ValueKey('inspector-context')))
            .selected,
        isTrue,
      );
      expect(find.byType(ContextWeightControls), findsOneWidget);
    });
  });

  group('Session presentation state survives the round trip', () {
    testWidgets('input draft is preserved', (tester) async {
      await mount(tester, width: 1280);
      final input = find.byType(TextField).last;
      await tester.enterText(input, '尚未发送的草稿');
      await tester.pump();
      final controller = tester.widget<TextField>(input).controller;

      await openInspector(tester);
      await tester.tap(find.byTooltip(l10n.backAction));
      await tester.pumpAndSettle();

      expect(
        tester.widget<TextField>(find.byType(TextField).last).controller,
        same(controller),
      );
      expect(controller!.text, '尚未发送的草稿');
    });

    testWidgets('reader scroll offset is preserved', (tester) async {
      // Messages must exist before mount so the list viewport attaches the
      // controller immediately.
      container.read(chatProvider).adventureProvider.setMessages(List.generate(
          40,
          (index) => Message(
              id: '$index',
              content: '叙事段落 $index。${'长文阅读测试。' * 60}',
              isUser: false)));
      await mount(tester, width: 1280, settle: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final reader =
          tester.widget<SessionMessageList>(find.byType(SessionMessageList));
      reader.scrollController.jumpTo(300);
      await tester.pump();
      expect(reader.scrollController.offset, closeTo(300, 1));

      await openInspector(tester, settle: false);
      await tester.tap(find.byTooltip(l10n.backAction));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final readerAfter =
          tester.widget<SessionMessageList>(find.byType(SessionMessageList));
      expect(readerAfter.scrollController, same(reader.scrollController));
      expect(reader.scrollController.offset, closeTo(300, 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('an in-flight stream is not cancelled', (tester) async {
      final fake = _TestChatProvider()..setMockStreaming(true);
      final fakeContainer = ProviderContainer(
          overrides: [chatProvider.overrideWith((ref) => fake)]);
      addTearDown(fakeContainer.dispose);

      await mount(tester,
          width: 1280, settle: false, withContainer: fakeContainer);
      expect(fake.isStreaming, isTrue);

      await openInspector(tester, settle: false);
      expect(fake.isStreaming, isTrue);

      await tester.tap(find.byTooltip(l10n.backAction));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(fake.isStreaming, isTrue);

      // The stream keeps publishing into the restored session.
      fake.streamNotifier.value = '旅店老板放下酒杯，压低了声音。';
      await tester.pump();
      expect(find.text('旅店老板放下酒杯，压低了声音。'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Deep links keep a correct route hierarchy', () {
    testWidgets('character / state shortcuts pop the Inspector then switch',
        (tester) async {
      await mount(tester, width: 1280);
      final chat = container.read(chatProvider);

      await openInspector(tester);
      await tester
          .tap(find.widgetWithText(TextButton, l10n.sceneCharactersTitle));
      await tester.pumpAndSettle();
      expect(find.byType(SessionInspectorPage), findsNothing);
      expect(chat.currentSection, AppSection.sceneCharacters);

      chat.setCurrentSection(AppSection.adventure);
      await tester.pump();
      await openInspector(tester);
      await tester.tap(find.byKey(const ValueKey('inspector-state')));
      await tester.pumpAndSettle();
      await tester.tap(
          find.widgetWithText(TextButton, l10n.runtimeStateHistoricalChange));
      await tester.pumpAndSettle();
      expect(find.byType(SessionInspectorPage), findsNothing);
      expect(chat.currentSection, AppSection.runtimeState);
      expect(tester.takeException(), isNull);
    });

    testWidgets('model selection pushes from and returns to the Inspector',
        (tester) async {
      await mount(tester, width: 1280);
      await openInspector(tester);
      await tester.tap(find.byKey(const ValueKey('inspector-generation')));
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('${l10n.switchModelAction}:'));
      await tester.pumpAndSettle();
      expect(find.byType(ModelSelectPage), findsOneWidget);
      expect(find.byType(SessionInspectorPage, skipOffstage: false),
          findsOneWidget);

      await tester.tap(find.byTooltip(l10n.backAction));
      await tester.pumpAndSettle();
      expect(find.byType(ModelSelectPage), findsNothing);
      expect(find.byType(SessionInspectorPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('inventory pushes from and returns to the Inspector',
        (tester) async {
      await mount(tester, width: 1280);
      await openInspector(tester);
      await tester.tap(find.byKey(const ValueKey('inspector-state')));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, l10n.inventoryTitle));
      await tester.pumpAndSettle();
      expect(find.byType(InventoryScreen), findsOneWidget);
      expect(find.byType(SessionInspectorPage, skipOffstage: false),
          findsOneWidget);

      await tester.tap(find.byTooltip(l10n.backAction));
      await tester.pumpAndSettle();
      expect(find.byType(InventoryScreen), findsNothing);
      expect(find.byType(SessionInspectorPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Inspector page responsive and theme robustness', () {
    for (final scale in const <double>[1.0, 1.5, 2.0]) {
      testWidgets('no overflow at 320px and ${scale}x text scale',
          (tester) async {
        await mount(tester, width: 320, height: 700, scale: scale);
        await openInspector(tester);
        expectStandalonePage(tester);

        await tester.tap(find.byKey(const ValueKey('inspector-context')));
        await tester.pumpAndSettle();
        expect(find.byType(ContextWeightControls), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    for (final dark in <bool>[false, true]) {
      testWidgets('renders in ${dark ? 'dark' : 'light'} theme',
          (tester) async {
        await mount(tester, width: 960, dark: dark);
        await openInspector(tester);
        expectStandalonePage(tester);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
