import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lt_dialogue/core/theme/app_theme.dart';
import 'package:lt_dialogue/features/adventure/presentation/session/screens/tracked_state_management_page.dart';
import 'package:lt_dialogue/features/adventure/presentation/state/runtime_state_hub_page.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations_zh.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/models/adventure_runtime_state.dart';
import 'package:lt_dialogue/models/message.dart';
import 'package:lt_dialogue/models/runtime_state_history.dart';
import 'package:lt_dialogue/models/scene_state.dart';
import 'package:lt_dialogue/models/turn_state_history.dart';
import 'package:lt_dialogue/models/typed_runtime_state.dart';
import 'package:lt_dialogue/providers/chat_provider.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/repositories/adventure_repository.dart';

class _FakeRepo implements IAdventureRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;

  @override
  Future<RuntimeStateSnapshot> getCurrentRuntimeState({
    required int adventureId,
    required int branchId,
    RuntimeEntityType? entityType,
    String? entityId,
  }) async =>
      RuntimeStateSnapshot(
          adventureId: adventureId, branchId: branchId, revision: 0);

  @override
  Future<SceneState?> getSceneState(int adventureId, int branchId) async =>
      const SceneState(presentCharacterIds: ['protagonist']);

  @override
  Future<List<AdventureSelectedCharacter>> getAdventureCharacterMemberships(
          int adventureId, int branchId) async =>
      const [];

  @override
  Future<List<RuntimeTimelineEntry>> getRuntimeTimeline({
    required int adventureId,
    required int branchId,
    int? beforeRevision,
    RuntimeEntityType? entityType,
    String? entityId,
    String? eventTypeId,
    int limit = 50,
  }) async =>
      const [];

  @override
  Future<List<TurnStateChangeGroup>> getTurnStateHistory({
    required int adventureId,
    required int branchId,
    int? beforeTurnRowId,
    int limit = 30,
    Set<RuntimeEntityType>? entityTypes,
    String? entityId,
  }) async =>
      const [];

  @override
  Future<List<RuntimeStateCheckpoint>> getRuntimeCheckpoints({
    required int adventureId,
    required int branchId,
    int? beforeRevision,
    int limit = 100,
  }) async =>
      const [];

  @override
  Future<List<Message>> getTurnMessages({
    required int adventureId,
    required int branchId,
    String? assistantMessageId,
  }) async =>
      const [];
}

class _FakeChat extends ChatProvider {
  _FakeChat({required this.mockConfig});

  final AdventureConfig mockConfig;

  @override
  int? get currentAdventureId => 1;

  @override
  int get currentBranchId => 0;

  @override
  AdventureConfig? get adventureConfig => mockConfig;

  @override
  List<Map<String, dynamic>> get adventureList => const [
        {'id': 1, 'title': '测试冒险'}
      ];
}

void main() {
  late Directory tempDir;
  final l10n = AppLocalizationsZh();

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('lt_tracked_nav_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Widget app(ProviderContainer container) => UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.light(),
          home: const RuntimeStateHubPage(
            initialView: RuntimeStateHubInitialView.tracked,
          ),
        ),
      );

  testWidgets('tracked is a first-level view with a reachable empty CTA',
      (tester) async {
    final container = ProviderContainer(overrides: [
      adventureRepoProvider.overrideWithValue(_FakeRepo()),
      chatProvider.overrideWith(
          (ref) => _FakeChat(mockConfig: AdventureConfig(name: '测试'))),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(app(container));
    await tester.pumpAndSettle();

    // The tracked view is a first-level navigation entry.
    expect(
      find.descendant(
        of: find.byWidgetPredicate((w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value == 'runtime-view-tracked'),
        matching: find.text(l10n.trackedStateStatusTitle),
      ),
      findsOneWidget,
    );

    // Empty state surfaces its own add-monitor call to action.
    expect(find.text(l10n.trackedStateNoDefinitions), findsOneWidget);
    final addAction = find.text(l10n.trackedStateAddFirstAction);
    expect(addAction, findsOneWidget);

    await tester.tap(addAction);
    await tester.pumpAndSettle();

    expect(find.byType(TrackedStateManagementPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('does not overflow at 320 px', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(overrides: [
      adventureRepoProvider.overrideWithValue(_FakeRepo()),
      chatProvider.overrideWith(
          (ref) => _FakeChat(mockConfig: AdventureConfig(name: '测试'))),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(app(container));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
