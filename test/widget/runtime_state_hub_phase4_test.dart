import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lt_dialogue/core/theme/app_theme.dart';
import 'package:lt_dialogue/core/widgets/app_card.dart';
import 'package:lt_dialogue/core/widgets/app_empty_state.dart';
import 'package:lt_dialogue/features/adventure/presentation/home/widgets/dashboard_state_section.dart';
import 'package:lt_dialogue/features/adventure/presentation/session/widgets/status_hud_bar.dart';
import 'package:lt_dialogue/features/adventure/presentation/state/runtime_state_hub_page.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations_zh.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/models/adventure_runtime_state.dart';
import 'package:lt_dialogue/core/router/app_router.dart';
import 'package:lt_dialogue/models/message.dart';
import 'package:lt_dialogue/models/runtime_state_history.dart';
import 'package:lt_dialogue/models/scene_state.dart';
import 'package:lt_dialogue/models/supporting_character.dart';
import 'package:lt_dialogue/models/turn_state_history.dart';
import 'package:lt_dialogue/models/typed_runtime_state.dart';
import 'package:lt_dialogue/providers/chat_provider.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/repositories/adventure_repository.dart';

import '../helpers/responsive_test_helper.dart';

class _FakeAdventureRepository implements IAdventureRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;

  Completer<void>? pendingLoad;
  RuntimeStateSnapshot? mockSnapshot;
  SceneState? mockSceneState;
  List<AdventureSelectedCharacter> mockDynamicCharacters = [];
  List<RuntimeTimelineEntry> mockTimeline = [];
  List<TurnStateChangeGroup> mockTurns = [];
  List<RuntimeStateCheckpoint> mockCheckpoints = [];
  bool shouldThrow = false;
  int turnHistoryCallCount = 0;

  @override
  Future<RuntimeStateSnapshot> getCurrentRuntimeState({
    required int adventureId,
    required int branchId,
    RuntimeEntityType? entityType,
    String? entityId,
  }) async {
    if (pendingLoad != null) await pendingLoad!.future;
    if (shouldThrow) throw Exception('Simulated repository error');
    return mockSnapshot ??
        RuntimeStateSnapshot(
          adventureId: adventureId,
          branchId: branchId,
          revision: 1,
        );
  }

  @override
  Future<SceneState?> getSceneState(int adventureId, int branchId) async {
    if (shouldThrow) throw Exception('Simulated repository error');
    return mockSceneState;
  }

  @override
  Future<List<AdventureSelectedCharacter>> getAdventureCharacterMemberships(
    int adventureId,
    int branchId,
  ) async {
    return mockDynamicCharacters;
  }

  @override
  Future<List<RuntimeTimelineEntry>> getRuntimeTimeline({
    required int adventureId,
    required int branchId,
    int? beforeRevision,
    RuntimeEntityType? entityType,
    String? entityId,
    String? eventTypeId,
    int limit = 50,
  }) async {
    return mockTimeline;
  }

  @override
  Future<List<TurnStateChangeGroup>> getTurnStateHistory({
    required int adventureId,
    required int branchId,
    int? beforeTurnRowId,
    int limit = 30,
    Set<RuntimeEntityType>? entityTypes,
    String? entityId,
  }) async {
    turnHistoryCallCount++;
    if (shouldThrow) throw Exception('Simulated repository error');
    if (beforeTurnRowId != null) {
      return mockTurns
          .where((t) => t.turnRowId < beforeTurnRowId)
          .take(limit)
          .toList();
    }
    return mockTurns.take(limit).toList();
  }

  @override
  Future<List<RuntimeStateCheckpoint>> getRuntimeCheckpoints({
    required int adventureId,
    required int branchId,
    int? beforeRevision,
    int limit = 100,
  }) async {
    return mockCheckpoints;
  }

  @override
  Future<List<Message>> getTurnMessages({
    required int adventureId,
    required int branchId,
    String? assistantMessageId,
  }) async {
    return const [];
  }
}

class _TestPhase4ChatProvider extends ChatProvider {
  int? mockAdventureId = 1;
  int mockBranchId = 0;
  AdventureConfig? mockConfig = AdventureConfig(name: '艾尔登传说');
  List<Map<String, dynamic>> mockAdventureList = [
    {'id': 1, 'title': '艾尔登传说'}
  ];

  @override
  int? get currentAdventureId => mockAdventureId;

  @override
  int get currentBranchId => mockBranchId;

  @override
  AdventureConfig? get adventureConfig => mockConfig;

  @override
  List<Map<String, dynamic>> get adventureList => mockAdventureList;
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  late Directory tempDir;
  final l10n = AppLocalizationsZh();

  final forbiddenTokens = <String>[
    'res_cre_',
    'char_internal',
    'entityId',
    'attributeId',
    'statePath',
    'revision',
    'commitId',
    'requestId',
    'branchId',
    'runtimeId',
    'file:///',
    '/home/',
    'SELECT',
    'INSERT',
    'UPDATE',
    'StackTrace',
    'Exception:',
    '{"raw_json',
  ];

  void assertNoForbiddenTokens(WidgetTester tester) {
    for (final token in forbiddenTokens) {
      expect(
        find.textContaining(token),
        findsNothing,
        reason: 'Forbidden token "$token" leaked to UI',
      );
    }
  }

  Finder findTab(String label) => find.descendant(
        of: find.byWidgetPredicate((w) => w is SegmentedButton),
        matching: find.text(label),
      );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('lt_phase4_hub_test_');
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

  Widget buildTestApp({
    required ProviderContainer container,
    ThemeData? theme,
    Locale locale = const Locale('zh'),
    double textScale = 1.0,
    Widget? home,
  }) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: theme ?? AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: home ?? const RuntimeStateHubPage(),
      ),
    );
  }

  group('Phase 4: RuntimeStateHubPage Rendering and Responsive Layouts', () {
    testWidgets('1. Normal rendering on Light and Dark theme (Req 1, 29, 30)',
        (tester) async {
      final fakeRepo = _FakeAdventureRepository();
      final fakeChat = _TestPhase4ChatProvider();
      final container = ProviderContainer(
        overrides: [
          adventureRepoProvider.overrideWithValue(fakeRepo),
          chatProvider.overrideWith((ref) => fakeChat),
        ],
      );
      addTearDown(container.dispose);

      // Light theme
      await tester.pumpWidget(
        buildTestApp(
          container: container,
          theme: AppTheme.light(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('艾尔登传说'), findsOneWidget);
      expect(find.text('主线剧情'), findsOneWidget);
      expect(find.text(l10n.runtimeStateOverview), findsAtLeastNWidgets(1));
      expect(tester.takeException(), isNull);

      // Dark theme
      await tester.pumpWidget(
        buildTestApp(
          container: container,
          theme: AppTheme.dark(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('艾尔登传说'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '2. Responsive layout down to 320px with 2.0x font scaling without RenderFlex overflow (Req 26, 27)',
        (tester) async {
      setViewport(tester, width: 320, height: 568);
      final fakeRepo = _FakeAdventureRepository();
      final fakeChat = _TestPhase4ChatProvider();
      final container = ProviderContainer(
        overrides: [
          adventureRepoProvider.overrideWithValue(fakeRepo),
          chatProvider.overrideWith((ref) => fakeChat),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        buildTestApp(
          container: container,
          textScale: 2.0,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(RuntimeStateHubPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '3. Multi-viewport testing across 320, 360, 390, 412, 768, 1280 (Req 28)',
        (tester) async {
      final fakeRepo = _FakeAdventureRepository();
      final fakeChat = _TestPhase4ChatProvider();
      final container = ProviderContainer(
        overrides: [
          adventureRepoProvider.overrideWithValue(fakeRepo),
          chatProvider.overrideWith((ref) => fakeChat),
        ],
      );
      addTearDown(container.dispose);

      for (final size in requiredUiViewports) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          buildTestApp(container: container),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull,
            reason: 'Failed at viewport $size');
      }
    });
  });

  group('Phase 4: Navigator Routing and Pop State Restoration', () {
    testWidgets(
        '4. Dashboard StateSection real Navigator routing pushes RuntimeStateHubPage (Req 2)',
        (tester) async {
      setViewport(tester, width: 390, height: 844);
      final fakeRepo = _FakeAdventureRepository();
      final fakeChat = _TestPhase4ChatProvider();
      final container = ProviderContainer(
        overrides: [
          adventureRepoProvider.overrideWithValue(fakeRepo),
          chatProvider.overrideWith((ref) => fakeChat),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) => Scaffold(
                body: DashboardStateSection(
                  onOpenStateHub: () {
                    AppRouter.push<void>(
                      context,
                      pageBuilder: (_) => const RuntimeStateHubPage(),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(AppCard));
      await tester.pumpAndSettle();

      expect(find.byType(RuntimeStateHubPage), findsOneWidget);
      expect(find.text('艾尔登传说'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '5. Session StatusHudBar real Navigator routing pushes RuntimeStateHubPage (Req 3)',
        (tester) async {
      setViewport(tester, width: 390, height: 844);
      final fakeRepo = _FakeAdventureRepository();
      final fakeChat = _TestPhase4ChatProvider();
      final container = ProviderContainer(
        overrides: [
          adventureRepoProvider.overrideWithValue(fakeRepo),
          chatProvider.overrideWith((ref) => fakeChat),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) => Scaffold(
                body: StatusHudBar(
                  onTap: () {
                    AppRouter.push<void>(
                      context,
                      pageBuilder: (_) => const RuntimeStateHubPage(),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(StatusHudBar));
      await tester.pumpAndSettle();

      expect(find.byType(RuntimeStateHubPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '6. Navigator back pop restores original hub state cleanly (Req 31)',
        (tester) async {
      final fakeRepo = _FakeAdventureRepository();
      final fakeChat = _TestPhase4ChatProvider();
      fakeRepo.mockTurns = [
        TurnStateChangeGroup(
          adventureId: 1,
          branchId: 0,
          turnId: 'turn-1',
          turnRowId: 1,
          turnNumber: 1,
          requestId: 'req-1',
          occurredAt: DateTime(2026, 9, 26, 12, 0),
          revisionStart: 1,
          revisionEnd: 2,
          changes: const [],
        ),
      ];

      final container = ProviderContainer(
        overrides: [
          adventureRepoProvider.overrideWithValue(fakeRepo),
          chatProvider.overrideWith((ref) => fakeChat),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(buildTestApp(container: container));
      await tester.pumpAndSettle();

      // Switch to turns tab
      await tester.tap(findTab(l10n.runtimeStateHistoricalChange));
      await tester.pumpAndSettle();

      // Tap on turn card to push detail page
      await tester.tap(find.text(l10n.runtimeStateTurnLabel(1)));
      await tester.pumpAndSettle();

      expect(find.byType(TurnStateDetailPage), findsOneWidget);

      // Pop back
      final navigator =
          tester.state<NavigatorState>(find.byType(Navigator).last);
      navigator.pop();
      await tester.pumpAndSettle();

      expect(find.byType(RuntimeStateHubPage), findsOneWidget);
      expect(find.byType(TurnStateDetailPage), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('Phase 4: World, Characters, Profiles & SceneState Authority', () {
    testWidgets(
        '7. Displays current world state with location, atmosphere, factions (Req 4)',
        (tester) async {
      final fakeRepo = _FakeAdventureRepository();
      final fakeChat = _TestPhase4ChatProvider();
      fakeRepo.mockSceneState = const SceneState(
        location: '王城罗德尔',
        time: '黄昏',
        presentCharacterIds: ['char_arthur'],
      );
      fakeRepo.mockSnapshot = RuntimeStateSnapshot(
        adventureId: 1,
        branchId: 0,
        revision: 2,
        entities: {
          'loc_rodel': RuntimeEntityState(
            entityType: RuntimeEntityType.location,
            entityId: 'loc_rodel',
            overlay: {
              'condition': '繁华',
              'environment': '晴空',
            },
          ),
          'fac_golden': RuntimeEntityState(
            entityType: RuntimeEntityType.faction,
            entityId: 'fac_golden',
            overlay: {
              'influence': '强盛',
            },
          ),
        },
      );

      final container = ProviderContainer(
        overrides: [
          adventureRepoProvider.overrideWithValue(fakeRepo),
          chatProvider.overrideWith((ref) => fakeChat),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(buildTestApp(container: container));
      await tester.pumpAndSettle();

      // In overview card, location and scene are visible
      expect(find.text('王城罗德尔'), findsAtLeastNWidgets(1));

      // Switch to World tab
      await tester.tap(findTab(l10n.worldviewModuleState));
      await tester.pumpAndSettle();

      expect(find.text(l10n.worldviewModuleState), findsAtLeastNWidgets(1));
      expect(find.text(l10n.runtimeStateFieldCondition), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '8. Displays current character state with typed values (Req 5, 25)',
        (tester) async {
      final fakeRepo = _FakeAdventureRepository();
      final fakeChat = _TestPhase4ChatProvider();
      fakeChat.mockConfig = AdventureConfig(
        name: '艾尔登传说',
        selectedCharacters: [
          AdventureSelectedCharacter(
            id: '1',
            characterId: 'char_arthur',
            characterName: '亚瑟',
            isProtagonist: true,
          ),
        ],
      );
      fakeRepo.mockSnapshot = RuntimeStateSnapshot(
        adventureId: 1,
        branchId: 0,
        revision: 2,
        entities: {
          'char_arthur': RuntimeEntityState(
            entityType: RuntimeEntityType.character,
            entityId: 'char_arthur',
            overlay: {
              'hp': 85,
              'mp': 50,
              'status': 'alive',
              'global_flag': true,
            },
            lifecycleStatus: 'active',
          ),
        },
      );

      final container = ProviderContainer(
        overrides: [
          adventureRepoProvider.overrideWithValue(fakeRepo),
          chatProvider.overrideWith((ref) => fakeChat),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(buildTestApp(container: container));
      await tester.pumpAndSettle();

      // Switch to characters tab
      await tester.tap(findTab(l10n.characterStatusTitle));
      await tester.pumpAndSettle();

      expect(find.text('亚瑟'), findsAtLeastNWidgets(1));
      expect(find.text('85'), findsOneWidget);
      expect(find.text('50'), findsOneWidget);
      expect(find.text(l10n.runtimeStateAlive), findsOneWidget);
      expect(find.text(l10n.runtimeStateTrue), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '9. Separates baseline profile from dynamic runtime state (Req 6)',
        (tester) async {
      final fakeRepo = _FakeAdventureRepository();
      final fakeChat = _TestPhase4ChatProvider();
      fakeChat.mockConfig = AdventureConfig(
        name: '艾尔登传说',
        selectedCharacters: [
          AdventureSelectedCharacter(
            id: '1',
            characterId: 'char_arthur',
            characterName: '亚瑟',
            isProtagonist: true,
          ),
        ],
      );
      fakeRepo.mockSnapshot = RuntimeStateSnapshot(
        adventureId: 1,
        branchId: 0,
        revision: 2,
        entities: {
          'char_arthur': RuntimeEntityState(
            entityType: RuntimeEntityType.character,
            entityId: 'char_arthur',
            overlay: {'hp': 90},
          ),
        },
      );

      final container = ProviderContainer(
        overrides: [
          adventureRepoProvider.overrideWithValue(fakeRepo),
          chatProvider.overrideWith((ref) => fakeChat),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(buildTestApp(container: container));
      await tester.pumpAndSettle();

      await tester.tap(findTab(l10n.characterStatusTitle));
      await tester.pumpAndSettle();

      // Baseline profile button exists separately
      expect(
          find.text(l10n.runtimeStateBaselineProfile), findsAtLeastNWidgets(1));
      // Dynamic state is clearly labelled
      expect(find.text(l10n.runtimeStateDynamicState), findsAtLeastNWidgets(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '10. Adheres strictly to SceneState.presentCharacterIds for in-scene badge (Req 14)',
        (tester) async {
      final fakeRepo = _FakeAdventureRepository();
      final fakeChat = _TestPhase4ChatProvider();
      fakeChat.mockConfig = AdventureConfig(
        name: '艾尔登传说',
        selectedCharacters: [
          AdventureSelectedCharacter(
            id: '1',
            characterId: 'char_arthur',
            characterName: '亚瑟',
            isProtagonist: true,
          ),
        ],
        supportingCharacters: [
          SupportingCharacter(
            id: 'char_merlin',
            name: '梅林',
            role: 'mentor',
            relation: '导师',
          ),
        ],
      );
      fakeRepo.mockSceneState = const SceneState(
        location: '王城罗德尔',
        presentCharacterIds: ['char_arthur'], // only arthur in scene!
      );
      fakeRepo.mockSnapshot = RuntimeStateSnapshot(
        adventureId: 1,
        branchId: 0,
        revision: 2,
        entities: {
          'char_arthur': RuntimeEntityState(
            entityType: RuntimeEntityType.character,
            entityId: 'char_arthur',
            overlay: {'hp': 100},
          ),
          'char_merlin': RuntimeEntityState(
            entityType: RuntimeEntityType.npc,
            entityId: 'char_merlin',
            overlay: {'hp': 80},
          ),
        },
      );

      final container = ProviderContainer(
        overrides: [
          adventureRepoProvider.overrideWithValue(fakeRepo),
          chatProvider.overrideWith((ref) => fakeChat),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(buildTestApp(container: container));
      await tester.pumpAndSettle();

      await tester.tap(findTab(l10n.characterStatusTitle));
      await tester.pumpAndSettle();

      // Exactly 1 character has the '在场' badge (Arthur)
      expect(find.text(l10n.runtimeStateInScene), findsOneWidget);
      expect(find.text('亚瑟'), findsAtLeastNWidgets(1));
      expect(find.text('梅林'), findsAtLeastNWidgets(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '11. Dead or departed entity status is correctly displayed (Req 13)',
        (tester) async {
      final fakeRepo = _FakeAdventureRepository();
      final fakeChat = _TestPhase4ChatProvider();
      fakeChat.mockConfig = AdventureConfig(
        name: '艾尔登传说',
        selectedCharacters: [
          AdventureSelectedCharacter(
            id: '1',
            characterId: 'char_arthur',
            characterName: '亚瑟',
            isProtagonist: true,
          ),
        ],
      );
      fakeRepo.mockSnapshot = RuntimeStateSnapshot(
        adventureId: 1,
        branchId: 0,
        revision: 2,
        entities: {
          'char_arthur': RuntimeEntityState(
            entityType: RuntimeEntityType.character,
            entityId: 'char_arthur',
            overlay: {
              'hp': 0,
              'life_status': 'dead',
            },
            lifecycleStatus: 'dead',
          ),
        },
      );

      final container = ProviderContainer(
        overrides: [
          adventureRepoProvider.overrideWithValue(fakeRepo),
          chatProvider.overrideWith((ref) => fakeChat),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(buildTestApp(container: container));
      await tester.pumpAndSettle();

      await tester.tap(findTab(l10n.characterStatusTitle));
      await tester.pumpAndSettle();

      expect(find.text(l10n.runtimeStateDead), findsAtLeastNWidgets(1));
      expect(tester.takeException(), isNull);
    });
  });

  group('Phase 4: Turn Grouping, Turn Detail, Diff & Categorization', () {
    testWidgets(
        '12. Groups state history by dialogue turn with Turn N labels and summary (Req 7)',
        (tester) async {
      final fakeRepo = _FakeAdventureRepository();
      final fakeChat = _TestPhase4ChatProvider();
      fakeRepo.mockTurns = [
        TurnStateChangeGroup(
          adventureId: 1,
          branchId: 0,
          turnId: 'turn-2',
          turnRowId: 2,
          turnNumber: 2,
          requestId: 'req-2',
          occurredAt: DateTime(2026, 9, 26, 12, 30),
          revisionStart: 3,
          revisionEnd: 4,
          changes: [
            const TurnStateChange(
              entityType: RuntimeEntityType.character,
              entityId: 'char_arthur',
              path: 'hp',
              before: 100,
              after: 85,
              reason: '受到巨龙攻击',
              commitId: 'c-2',
              revision: 4,
              causeType: 'scene_dialogue',
            ),
          ],
        ),
      ];

      final container = ProviderContainer(
        overrides: [
          adventureRepoProvider.overrideWithValue(fakeRepo),
          chatProvider.overrideWith((ref) => fakeChat),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(buildTestApp(container: container));
      await tester.pumpAndSettle();

      await tester.tap(findTab(l10n.runtimeStateHistoricalChange));
      await tester.pumpAndSettle();

      expect(find.text(l10n.runtimeStateTurnLabel(2)), findsOneWidget);
      expect(find.text(l10n.runtimeStateChangeCount(1)), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '13. Clicking Turn N pushes TurnStateDetailPage via Navigator (Req 8)',
        (tester) async {
      final fakeRepo = _FakeAdventureRepository();
      final fakeChat = _TestPhase4ChatProvider();
      fakeRepo.mockTurns = [
        TurnStateChangeGroup(
          adventureId: 1,
          branchId: 0,
          turnId: 'turn-2',
          turnRowId: 2,
          turnNumber: 2,
          requestId: 'req-2',
          occurredAt: DateTime(2026, 9, 26, 12, 30),
          revisionStart: 3,
          revisionEnd: 4,
          changes: [
            const TurnStateChange(
              entityType: RuntimeEntityType.character,
              entityId: 'char_arthur',
              path: 'hp',
              before: 100,
              after: 85,
              reason: '受到巨龙攻击',
              commitId: 'c-2',
              revision: 4,
              causeType: 'scene_dialogue',
            ),
          ],
        ),
      ];

      final container = ProviderContainer(
        overrides: [
          adventureRepoProvider.overrideWithValue(fakeRepo),
          chatProvider.overrideWith((ref) => fakeChat),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(buildTestApp(container: container));
      await tester.pumpAndSettle();

      await tester.tap(findTab(l10n.runtimeStateHistoricalChange));
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.runtimeStateTurnLabel(2)));
      await tester.pumpAndSettle();

      expect(find.byType(TurnStateDetailPage), findsOneWidget);
      expect(find.text(l10n.runtimeStateTurnSummary), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '14. Displays correct before -> after diff and only changed fields (Req 9, 10)',
        (tester) async {
      final fakeRepo = _FakeAdventureRepository();
      final fakeChat = _TestPhase4ChatProvider();
      fakeChat.mockConfig = AdventureConfig(
        name: '艾尔登传说',
        selectedCharacters: [
          AdventureSelectedCharacter(
            id: '1',
            characterId: 'char_arthur',
            characterName: '亚瑟',
            isProtagonist: true,
          ),
        ],
      );
      final turn = TurnStateChangeGroup(
        adventureId: 1,
        branchId: 0,
        turnId: 'turn-2',
        turnRowId: 2,
        turnNumber: 2,
        requestId: 'req-2',
        occurredAt: DateTime(2026, 9, 26, 12, 30),
        revisionStart: 3,
        revisionEnd: 4,
        changes: [
          const TurnStateChange(
            entityType: RuntimeEntityType.character,
            entityId: 'char_arthur',
            path: 'hp',
            before: 100,
            after: 85,
            reason: '受到巨龙攻击',
            commitId: 'c-2',
            revision: 4,
            causeType: 'scene_dialogue',
          ),
        ],
      );

      final container = ProviderContainer(
        overrides: [
          adventureRepoProvider.overrideWithValue(fakeRepo),
          chatProvider.overrideWith((ref) => fakeChat),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        buildTestApp(
          container: container,
          home: TurnStateDetailPage(turn: turn),
        ),
      );
      await tester.pumpAndSettle();

      // Diff displays formatDiff correctly: 100 → 85
      expect(find.text('100 → 85'), findsOneWidget);
      expect(find.text('受到巨龙攻击'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '15. Correctly categorizes world vs character changes within a turn (Req 12)',
        (tester) async {
      final fakeRepo = _FakeAdventureRepository();
      final fakeChat = _TestPhase4ChatProvider();
      fakeChat.mockConfig = AdventureConfig(
        name: '艾尔登传说',
        selectedCharacters: [
          AdventureSelectedCharacter(
            id: '1',
            characterId: 'char_arthur',
            characterName: '亚瑟',
            isProtagonist: true,
          ),
        ],
      );
      final turn = TurnStateChangeGroup(
        adventureId: 1,
        branchId: 0,
        turnId: 'turn-3',
        turnRowId: 3,
        turnNumber: 3,
        requestId: 'req-3',
        occurredAt: DateTime(2026, 9, 26, 13, 0),
        revisionStart: 5,
        revisionEnd: 6,
        changes: [
          const TurnStateChange(
            entityType: RuntimeEntityType.character,
            entityId: 'char_arthur',
            path: 'mp',
            before: 60,
            after: 30,
            reason: '施放圣光咒语',
            commitId: 'c-3',
            revision: 6,
            causeType: 'scene_dialogue',
          ),
          const TurnStateChange(
            entityType: RuntimeEntityType.world,
            entityId: 'world_main',
            path: 'atmosphere',
            before: '平静',
            after: '圣洁',
            reason: '光芒照耀全城',
            commitId: 'c-3',
            revision: 6,
            causeType: 'scene_dialogue',
          ),
        ],
      );

      final container = ProviderContainer(
        overrides: [
          adventureRepoProvider.overrideWithValue(fakeRepo),
          chatProvider.overrideWith((ref) => fakeChat),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        buildTestApp(
          container: container,
          home: TurnStateDetailPage(turn: turn),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(l10n.runtimeStateCharacterChanges), findsOneWidget);
      expect(find.text(l10n.runtimeStateWorldChanges), findsOneWidget);
      expect(find.text('60 → 30'), findsOneWidget);
      expect(find.text('平静 → 圣洁'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '16. Displays empty state when turn has no visible changes (Req 11)',
        (tester) async {
      final fakeRepo = _FakeAdventureRepository();
      final fakeChat = _TestPhase4ChatProvider();
      final emptyTurn = TurnStateChangeGroup(
        adventureId: 1,
        branchId: 0,
        turnId: 'turn-empty',
        turnRowId: 1,
        turnNumber: 1,
        requestId: 'req-1',
        occurredAt: DateTime(2026, 9, 26, 12, 0),
        revisionStart: 1,
        revisionEnd: 2,
        changes: const [],
      );

      final container = ProviderContainer(
        overrides: [
          adventureRepoProvider.overrideWithValue(fakeRepo),
          chatProvider.overrideWith((ref) => fakeChat),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        buildTestApp(
          container: container,
          home: TurnStateDetailPage(turn: emptyTurn),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(l10n.runtimeStateNoVisibleChanges),
          findsAtLeastNWidgets(1));
      expect(tester.takeException(), isNull);
    });
  });

  group('Phase 4: Branch Isolation and Pagination', () {
    testWidgets('17. Isolates state and turns by branch ID (Req 15)',
        (tester) async {
      final fakeRepo = _FakeAdventureRepository();
      final fakeChat = _TestPhase4ChatProvider();
      fakeChat.mockBranchId = 2;

      final container = ProviderContainer(
        overrides: [
          adventureRepoProvider.overrideWithValue(fakeRepo),
          chatProvider.overrideWith((ref) => fakeChat),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(buildTestApp(container: container));
      await tester.pumpAndSettle();

      expect(find.text(l10n.branchNumberLabel(2)), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('18. Paginates and loads more turns on scroll (Req 16)',
        (tester) async {
      final fakeRepo = _FakeAdventureRepository();
      final fakeChat = _TestPhase4ChatProvider();

      // Create 35 turn groups
      fakeRepo.mockTurns = List.generate(
        35,
        (i) => TurnStateChangeGroup(
          adventureId: 1,
          branchId: 0,
          turnId: 'turn-$i',
          turnRowId: 35 - i,
          turnNumber: 35 - i,
          requestId: 'req-$i',
          occurredAt: DateTime(2026, 9, 26, 12, i),
          revisionStart: i,
          revisionEnd: i + 1,
          changes: const [],
        ),
      );

      final container = ProviderContainer(
        overrides: [
          adventureRepoProvider.overrideWithValue(fakeRepo),
          chatProvider.overrideWith((ref) => fakeChat),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(buildTestApp(container: container));
      await tester.pumpAndSettle();

      await tester.tap(findTab(l10n.runtimeStateHistoricalChange));
      await tester.pumpAndSettle();

      expect(fakeRepo.turnHistoryCallCount, 1);

      // Drag to bottom of list to trigger pagination
      await tester.drag(find.byType(ListView), const Offset(0, -2000));
      await tester.pumpAndSettle();

      expect(fakeRepo.turnHistoryCallCount, greaterThanOrEqualTo(2));
      expect(tester.takeException(), isNull);
    });
  });

  group('Phase 4: Empty, Loading, and Error States', () {
    testWidgets(
        '19. Displays empty adventure state when no current adventure (Req 17)',
        (tester) async {
      final fakeRepo = _FakeAdventureRepository();
      final fakeChat = _TestPhase4ChatProvider();
      fakeChat.mockAdventureId = null;

      final container = ProviderContainer(
        overrides: [
          adventureRepoProvider.overrideWithValue(fakeRepo),
          chatProvider.overrideWith((ref) => fakeChat),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(buildTestApp(container: container));
      await tester.pumpAndSettle();

      expect(find.byType(AppEmptyState), findsOneWidget);
      expect(find.text(l10n.runtimeStateNoAdventure), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '20. Displays empty history state when turn history is empty (Req 18)',
        (tester) async {
      final fakeRepo = _FakeAdventureRepository();
      final fakeChat = _TestPhase4ChatProvider();
      fakeRepo.mockTurns = [];

      final container = ProviderContainer(
        overrides: [
          adventureRepoProvider.overrideWithValue(fakeRepo),
          chatProvider.overrideWith((ref) => fakeChat),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(buildTestApp(container: container));
      await tester.pumpAndSettle();

      await tester.tap(findTab(l10n.runtimeStateHistoricalChange));
      await tester.pumpAndSettle();

      expect(find.text(l10n.runtimeStateNoChanges), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('21. Displays loading indicator during state fetch (Req 19)',
        (tester) async {
      final fakeRepo = _FakeAdventureRepository();
      final fakeChat = _TestPhase4ChatProvider();
      final completer = Completer<void>();
      fakeRepo.pendingLoad = completer;

      final container = ProviderContainer(
        overrides: [
          adventureRepoProvider.overrideWithValue(fakeRepo),
          chatProvider.overrideWith((ref) => fakeChat),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(buildTestApp(container: container));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      completer.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('22. Displays error view on failure and allows retry (Req 20)',
        (tester) async {
      final fakeRepo = _FakeAdventureRepository();
      final fakeChat = _TestPhase4ChatProvider();
      fakeRepo.shouldThrow = true;

      final container = ProviderContainer(
        overrides: [
          adventureRepoProvider.overrideWithValue(fakeRepo),
          chatProvider.overrideWith((ref) => fakeChat),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(buildTestApp(container: container));
      await tester.pumpAndSettle();

      expect(find.text(l10n.pageLoadError), findsOneWidget);
      expect(find.text(l10n.retryAction), findsOneWidget);

      // Allow repo to succeed on retry
      fakeRepo.shouldThrow = false;
      await tester.tap(find.text(l10n.retryAction));
      await tester.pumpAndSettle();

      expect(find.text(l10n.pageLoadError), findsNothing);
      expect(find.text('艾尔登传说'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Phase 4: Multilingual, Ultra-long Stress, and Safety Sanity Check',
      () {
    testWidgets(
        '23. Handles ultra-long character names, world fields, and safe reasons at 320px without overflow (Req 21, 22, 23)',
        (tester) async {
      setViewport(tester, width: 320, height: 568);
      final fakeRepo = _FakeAdventureRepository();
      final fakeChat = _TestPhase4ChatProvider();

      const ultraLongName = '神圣极北冻原与深渊巨龙搏击并寻求上古遗失王冠的传奇勇士亚瑟';
      const ultraLongReason =
          '由于极北冰原深处的远古冰霜巨龙在风暴降临之夜突然苏醒并对王城防御魔法阵喷吐出刺骨严寒，导致城池守备与角色状态遭受重创。';

      fakeChat.mockConfig = AdventureConfig(
        name: '艾尔登传说',
        selectedCharacters: [
          AdventureSelectedCharacter(
            id: '1',
            characterId: 'char_arthur',
            characterName: ultraLongName,
            isProtagonist: true,
          ),
        ],
      );
      fakeRepo.mockSnapshot = RuntimeStateSnapshot(
        adventureId: 1,
        branchId: 0,
        revision: 2,
        entities: {
          'char_arthur': RuntimeEntityState(
            entityType: RuntimeEntityType.character,
            entityId: 'char_arthur',
            overlay: {
              'hp': 50,
            },
          ),
        },
      );
      final turn = TurnStateChangeGroup(
        adventureId: 1,
        branchId: 0,
        turnId: 'turn-long',
        turnRowId: 1,
        turnNumber: 1,
        requestId: 'req-long',
        occurredAt: DateTime(2026, 9, 26, 12, 0),
        revisionStart: 1,
        revisionEnd: 2,
        changes: [
          const TurnStateChange(
            entityType: RuntimeEntityType.character,
            entityId: 'char_arthur',
            path: 'hp',
            before: 100,
            after: 50,
            reason: ultraLongReason,
            commitId: 'c-long',
            revision: 2,
            causeType: 'scene_dialogue',
          ),
        ],
      );

      final container = ProviderContainer(
        overrides: [
          adventureRepoProvider.overrideWithValue(fakeRepo),
          chatProvider.overrideWith((ref) => fakeChat),
        ],
      );
      addTearDown(container.dispose);

      // Hub page with ultra-long character name at 320px
      await tester.pumpWidget(buildTestApp(container: container));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Turn detail page with ultra-long reason at 320px
      await tester.pumpWidget(
        buildTestApp(
          container: container,
          home: TurnStateDetailPage(turn: turn),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '24. Renders properly in multilingual environments: zh, en, ja, ko (Req 24)',
        (tester) async {
      final fakeRepo = _FakeAdventureRepository();
      final fakeChat = _TestPhase4ChatProvider();
      final container = ProviderContainer(
        overrides: [
          adventureRepoProvider.overrideWithValue(fakeRepo),
          chatProvider.overrideWith((ref) => fakeChat),
        ],
      );
      addTearDown(container.dispose);

      for (final locale in const [
        Locale('zh'),
        Locale('en'),
        Locale('ja'),
        Locale('ko'),
      ]) {
        await tester.pumpWidget(
          buildTestApp(
            container: container,
            locale: locale,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(RuntimeStateHubPage), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'Failed for $locale');
      }
    });

    testWidgets(
        '25. Zero leakage of internal protocol tokens, paths, SQL, or exceptions (Req 32)',
        (tester) async {
      final fakeRepo = _FakeAdventureRepository();
      final fakeChat = _TestPhase4ChatProvider();
      final maliciousTurn = TurnStateChangeGroup(
        adventureId: 101,
        branchId: 1,
        turnId: 'turn-malicious',
        turnRowId: 999,
        turnNumber: 5,
        requestId: 'req_internal_4567',
        occurredAt: DateTime(2026, 9, 26, 15, 30),
        revisionStart: 10,
        revisionEnd: 12,
        changes: [
          const TurnStateChange(
            entityType: RuntimeEntityType.character,
            entityId: 'res_cre_char_internal_9988',
            path: 'custom_attributes.detected_luck',
            before: 'file:///home/yrz/LT/test.db',
            after: 'Exception: database locked',
            reason: 'SELECT * FROM adventure_state_commits WHERE id = 1',
            commitId: 'commit_hex_abcdef1234567890',
            revision: 11,
            causeType: 'scene_dialogue',
          ),
        ],
      );

      final container = ProviderContainer(
        overrides: [
          adventureRepoProvider.overrideWithValue(fakeRepo),
          chatProvider.overrideWith((ref) => fakeChat),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        buildTestApp(
          container: container,
          home: TurnStateDetailPage(turn: maliciousTurn),
        ),
      );
      await tester.pumpAndSettle();

      assertNoForbiddenTokens(tester);
      expect(tester.takeException(), isNull);
    });
  });
}
