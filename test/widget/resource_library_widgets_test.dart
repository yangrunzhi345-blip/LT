import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lt_dialogue/core/theme/app_theme.dart';
import 'package:lt_dialogue/features/resource_library/presentation/screens/resource_library_screen.dart';
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
    tempDir = await Directory.systemTemp.createTemp('lt_library_widget_test_');
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

  group('Phase 5: Resource Library Screen Tests', () {
    testWidgets(
      'ResourceLibraryScreen renders completely on 320px viewport with zero overflow',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: AppTheme.light(),
              home: const ResourceLibraryScreen(),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.byKey(const Key('resource-create-button')), findsOneWidget);
        expect(find.byKey(const Key('resource-search-field')), findsOneWidget);
        expect(find.text('NPC'), findsWidgets);

        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'ResourceLibraryScreen renders on wide desktop with all tabs and search',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: AppTheme.light(),
              home: const ResourceLibraryScreen(),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.byKey(const Key('resource-create-button')), findsOneWidget);
        expect(find.byKey(const Key('resource-search-field')), findsOneWidget);

        // Verify search field exists
        expect(find.byType(TextField), findsOneWidget);

        expect(tester.takeException(), isNull);
      },
    );
  });
}
