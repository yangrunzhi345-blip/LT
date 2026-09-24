import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/features/resource_studio/application/use_cases/resource_studio_runtime.dart';
import 'package:lt_dialogue/features/resource_studio/domain/models/resource_studio_state.dart';
import 'package:lt_dialogue/features/resource_studio/presentation/controllers/resource_studio_controller.dart';
import 'package:lt_dialogue/main.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  late Directory tempDir;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('lt_r01_wiring_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
    container = ProviderContainer();
  });

  tearDown(() async {
    container.dispose();
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('R01 production streaming recovery wiring', () {
    test('R01-04 production provider recovers without automatic generation',
        () async {
      await _seedInterrupted('provider');

      final service =
          container.read(streamingResourceGenerationServiceProvider);
      expect(
        container.read(streamingResourceGenerationServiceProvider),
        same(service),
      );
      expect(
        container.read(resourceStudioRuntimeProvider),
        isA<StreamingResourceStudioRuntime>(),
      );

      await container.read(streamingGenerationRecoveryProvider.future);

      final db = await DatabaseService.database;
      final session = (await db.query(
        'resource_generation_sessions',
        where: 'session_id = ?',
        whereArgs: ['session_provider'],
      ))
          .single;
      final task = (await db.query(
        'resource_generation_tasks',
        where: 'task_id = ?',
        whereArgs: ['task_provider'],
      ))
          .single;
      expect(session['status'], 'recovering');
      expect(task['status'], 'ready');

      final studio = ResourceStudioController(
        runtime: container.read(resourceStudioRuntimeProvider),
        sessionId: 'session_provider',
      );
      await studio.load();
      expect(studio.state.status, ResourceStudioStatus.ready);
      studio.dispose();
    });

    testWidgets('R01-04 MainGate triggers the production recovery provider',
        (tester) async {
      expect(container.exists(streamingGenerationRecoveryProvider), isFalse);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
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

      expect(container.exists(streamingGenerationRecoveryProvider), isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    test('Studio runtime disposal does not close the shared service stream',
        () async {
      final service =
          container.read(streamingResourceGenerationServiceProvider);
      container.read(resourceStudioRuntimeProvider);
      var streamClosed = false;
      final subscription = service.eventStream.listen(
        (_) {},
        onDone: () => streamClosed = true,
      );

      container.invalidate(resourceStudioRuntimeProvider);
      await container.pump();

      expect(streamClosed, isFalse);
      expect(
        container.read(streamingResourceGenerationServiceProvider),
        same(service),
      );
      expect(
        container.read(resourceStudioRuntimeProvider),
        isA<StreamingResourceStudioRuntime>(),
      );
      await subscription.cancel();
    });
  });
}

Future<void> _seedInterrupted(String suffix) async {
  final db = await DatabaseService.database;
  final now = DateTime(2026, 9, 19).toIso8601String();
  await db.insert('resource_generation_tasks', {
    'task_id': 'task_$suffix',
    'blueprint_id': 'blueprint_$suffix',
    'resource_id': 'resource_$suffix',
    'section_id': 'section_$suffix',
    'part_id': 'part_$suffix',
    'prompt_goal': 'R01 production recovery',
    'estimated_length': 200,
    'dependencies_json': '[]',
    'status': 'generating',
    'sort_order': 0,
    'current_attempt_id': 'attempt_$suffix',
    'error_message': '',
    'created_at': now,
    'updated_at': now,
  });
  await db.insert('resource_generation_sessions', {
    'session_id': 'session_$suffix',
    'resource_id': 'resource_$suffix',
    'blueprint_id': 'blueprint_$suffix',
    'creation_session_id': '',
    'status': 'generating_part',
    'current_part_id': 'part_$suffix',
    'current_task_id': 'task_$suffix',
    'current_attempt_id': 'attempt_$suffix',
    'completed_parts_count': 0,
    'total_parts_count': 1,
    'error_message': '',
    'created_at': now,
    'updated_at': now,
  });
}
