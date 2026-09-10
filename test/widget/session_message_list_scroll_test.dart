import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lt_dialogue/core/theme/app_theme.dart';
import 'package:lt_dialogue/features/adventure/presentation/session/widgets/session_message_list.dart';
import 'package:lt_dialogue/models/message.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';
import 'package:lt_dialogue/services/database_service.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues(
        {'openai_api_key': 'test', 'deepseek_api_key': 'test'});
    tempDir = await Directory.systemTemp.createTemp('lt_scroll_test_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  group('SessionMessageList User-Controlled Scrolling Tests', () {
    testWidgets(
        'SessionMessageList renders messages and shows jump button when scrolled up',
        (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);

      late WidgetRef capturedRef;
      await tester.pumpWidget(
        ProviderScope(
          child: Consumer(
            builder: (context, ref, _) {
              capturedRef = ref;
              return MaterialApp(
                theme: AppTheme.light(),
                home: Scaffold(
                  body: SessionMessageList(
                    scrollController: scrollController,
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pump();

      final cp = capturedRef.read(chatProvider);

      for (int i = 0; i < 20; i++) {
        cp.messages.add(
          Message(
            id: 'msg_$i',
            content: '这是第 $i 句剧情文本，详细叙述着艾尔德兰世界的深邃历史与命运纠葛。' * 2,
            isUser: i % 2 == 0,
          ),
        );
      }
      cp.notifyListeners();
      await tester.pumpAndSettle();

      expect(scrollController.hasClients, isTrue);

      // Jump to bottom first
      scrollController.jumpTo(scrollController.position.maxScrollExtent);
      await tester.pumpAndSettle();

      // Scroll up away from bottom by dragging
      await tester.drag(find.byType(ListView), const Offset(0, 300));
      await tester.pumpAndSettle();

      // Scrolled up -> floating jump-to-bottom button should appear
      expect(find.byIcon(Icons.arrow_downward_rounded), findsOneWidget);

      // Tap floating jump-to-bottom button
      await tester.tap(find.byIcon(Icons.arrow_downward_rounded));
      await tester.pumpAndSettle();

      // After jump to bottom completes, button disappears
      expect(find.byIcon(Icons.arrow_downward_rounded), findsNothing);
    });

    testWidgets(
        'During streaming when autoScrollDuringGeneration is false, view does not force scroll away',
        (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);

      late WidgetRef capturedRef;
      await tester.pumpWidget(
        ProviderScope(
          child: Consumer(
            builder: (context, ref, _) {
              capturedRef = ref;
              return MaterialApp(
                theme: AppTheme.light(),
                home: Scaffold(
                  body: SessionMessageList(
                    scrollController: scrollController,
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pump();

      final cp = capturedRef.read(chatProvider);
      expect(cp.settingsProvider.autoScrollDuringGeneration, isFalse);

      for (int i = 0; i < 15; i++) {
        cp.messages.add(
          Message(
            id: 'm_$i',
            content: '测试消息 $i' * 10,
            isUser: i % 2 == 0,
          ),
        );
      }
      cp.notifyListeners();
      await tester.pumpAndSettle();

      // Scroll to a specific offset where the user is reading
      scrollController.jumpTo(100.0);
      await tester.pumpAndSettle();

      final readingOffset = scrollController.offset;
      expect(readingOffset, closeTo(100.0, 1.0));

      // Simulate streaming update tick
      cp.rebuildVersion.value++;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Because autoScrollDuringGeneration is false, offset must NOT jump to maxScrollExtent!
      expect(scrollController.offset, closeTo(readingOffset, 1.0),
          reason:
              'User reading position must be preserved without forced auto-scroll during generation');
    });
  });
}
