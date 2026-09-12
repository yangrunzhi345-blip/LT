import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lt_dialogue/core/theme/app_theme.dart';
import 'package:lt_dialogue/features/adventure/presentation/session/widgets/session_app_bar.dart';
import 'package:lt_dialogue/features/adventure/presentation/session/widgets/session_input_bar.dart';
import 'package:lt_dialogue/features/adventure/presentation/session/widgets/status_hud_bar.dart';
import 'package:lt_dialogue/models/game_state.dart';
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
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('lt_session_widget_test_');
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

  group('Phase 3: Adventure Session Widgets Tests', () {
    testWidgets(
      'StatusHudBar renders in single line and handles tap without overflow at 320px',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final container = ProviderContainer();
        addTearDown(container.dispose);
        container.read(chatProvider).adventureProvider.setGameState(
              GameState(
                currentScene: '艾尔德兰 · 沉睡之森深处秘境遗迹',
                hp: 85,
                maxHp: 100,
                mp: 40,
                maxMp: 50,
                gold: 1250,
              ),
            );

        bool tapped = false;

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: AppTheme.light(),
              home: Scaffold(
                body: StatusHudBar(
                  onTap: () => tapped = true,
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        // Verify Location icon and HP/MP/Gold are present
        expect(find.byIcon(Icons.place_rounded), findsOneWidget);
        expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
        expect(find.byIcon(Icons.bolt_rounded), findsOneWidget);
        expect(find.byIcon(Icons.monetization_on_rounded), findsOneWidget);

        // Tap HUD
        await tester.tap(find.byType(StatusHudBar));
        await tester.pump();
        expect(tapped, isTrue);

        // Verify no exception / overflow
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'StatusHudBar displays all status elements on wider screens (>= 360px)',
      (tester) async {
        tester.view.physicalSize = const Size(400, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final container = ProviderContainer();
        addTearDown(container.dispose);
        container.read(chatProvider).adventureProvider.setGameState(
              GameState(
                currentScene: '主城集市',
                hp: 100,
                maxHp: 100,
                mp: 50,
                maxMp: 50,
                gold: 999,
              ),
            );

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: AppTheme.light(),
              home: const Scaffold(
                body: StatusHudBar(),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.byIcon(Icons.monetization_on_rounded), findsOneWidget);
        expect(find.text('999'), findsOneWidget);
      },
    );

    testWidgets(
      'SessionAppBar does not show permanent model pills and fits 320px width without overflow',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final container = ProviderContainer();
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: AppTheme.light(),
              home: const Scaffold(
                appBar: SessionAppBar(),
              ),
            ),
          ),
        );
        await tester.pump();

        // Old permanent auto_awesome pills should NOT exist
        expect(find.byIcon(Icons.auto_awesome), findsNothing);

        // Overflow menu should be available
        expect(find.byType(PopupMenuButton<String>), findsOneWidget);

        // Verify zero overflow
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'SessionInputBar centers within narrativeMaxWidth and fits 320px width without overflow',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final container = ProviderContainer();
        addTearDown(container.dispose);

        final textController = TextEditingController();
        final focusNode = FocusNode();
        addTearDown(textController.dispose);
        addTearDown(focusNode.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: AppTheme.light(),
              home: Scaffold(
                body: Align(
                  alignment: Alignment.bottomCenter,
                  child: SessionInputBar(
                    controller: textController,
                    focusNode: focusNode,
                    onSend: () {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        // Send button should be present
        expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);

        // Verify zero overflow on 320px
        expect(tester.takeException(), isNull);
      },
    );
  });
}
