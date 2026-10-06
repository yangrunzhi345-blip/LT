import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lt_dialogue/core/theme/app_theme.dart';
import 'package:lt_dialogue/features/adventure/presentation/session/widgets/session_inspector.dart';
import 'package:lt_dialogue/features/adventure/presentation/session/widgets/status_hud_bar.dart';
import 'package:lt_dialogue/features/adventure/presentation/session/screens/tracked_state_management_page.dart';
import 'package:lt_dialogue/features/adventure/presentation/state/runtime_state_hub_page.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations_zh.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/models/adventure_runtime_state.dart';
import 'package:lt_dialogue/models/adventure_tracked_state.dart';
import 'package:lt_dialogue/models/game_state.dart';
import 'package:lt_dialogue/models/scene_state.dart';
import 'package:lt_dialogue/models/supporting_character.dart';
import 'package:lt_dialogue/models/tracked_state_definition.dart';
import 'package:lt_dialogue/models/typed_runtime_state.dart';
import 'package:lt_dialogue/providers/adventure_provider.dart';
import 'package:lt_dialogue/providers/chat_provider.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/repositories/adventure_repository.dart';
import 'package:lt_dialogue/services/repositories/library_repository.dart';
import 'package:lt_dialogue/services/repositories/world_entry_repository.dart';

import '../helpers/responsive_test_helper.dart';

class _Noop {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeAdventureRepo extends _Noop implements IAdventureRepository {}

class _FakeWorldRepo extends _Noop implements IWorldEntryRepository {}

class _FakeLibraryRepo extends _Noop implements ILibraryRepository {}

/// AdventureProvider with externally injected config + runtime overlays, so a
/// widget test can present exactly one runtime projection.
class _TestAdventure extends AdventureProvider {
  _TestAdventure({
    this.config,
    this.entities = const [],
    GameState? gameState,
    SceneState sceneState = const SceneState(),
  })  : _gameState = gameState ??
            GameState(hp: 92, maxHp: 100, mp: 61, maxMp: 80, gold: 243),
        _sceneState = sceneState,
        super(
          adventureRepo: _FakeAdventureRepo(),
          worldEntryRepo: _FakeWorldRepo(),
          libraryRepo: _FakeLibraryRepo(),
        );

  final AdventureConfig? config;
  final List<RuntimeEntityState> entities;
  final GameState _gameState;
  final SceneState _sceneState;

  @override
  AdventureConfig? get adventureConfig => config;

  @override
  List<RuntimeEntityState> get runtimeEntities => entities;

  @override
  GameState get gameState => _gameState;

  @override
  SceneState get sceneState => _sceneState;

  @override
  String get currentTitle => '';
}

class _TestChat extends ChatProvider {
  _TestChat(this._adventure, {this.index = -1});

  final AdventureProvider _adventure;
  final int index;

  @override
  AdventureProvider get adventureProvider => _adventure;

  @override
  AdventureConfig? get adventureConfig => _adventure.adventureConfig;

  @override
  int get selectedCharacterIndex => index;
}

const _curse = TrackedStateDefinition(
  id: 'curse_corruption',
  name: '精神污染',
  valueKind: RuntimeStateValueKind.integer,
  minimum: 0,
  maximum: 100,
);
const _trust = TrackedStateDefinition(
  id: 'trust',
  name: '信任度',
  valueKind: RuntimeStateValueKind.integer,
);
const _wounded = TrackedStateDefinition(
  id: 'wounded',
  name: '受伤状态',
  valueKind: RuntimeStateValueKind.boolean,
);
const _stance = TrackedStateDefinition(
  id: 'war_stance',
  name: '战争立场',
  valueKind: RuntimeStateValueKind.enumValue,
  enumValues: {'和平', '中立', '敌对'},
);
const _fear = TrackedStateDefinition(
  id: 'fear',
  name: '恐惧',
  valueKind: RuntimeStateValueKind.integer,
  minimum: 0,
  maximum: 100,
);

AdventureConfig _config({bool withDefinitions = true}) => AdventureConfig(
      name: '李维',
      selectedCharacters: [
        AdventureSelectedCharacter(
          id: 'lc',
          characterId: 'lc',
          characterName: '林澈',
          isProtagonist: true,
        ),
        AdventureSelectedCharacter(
          id: 'alice',
          characterId: 'alice',
          characterName: 'Alice',
        ),
        AdventureSelectedCharacter(
          id: 'bob',
          characterId: 'bob',
          characterName: 'Bob',
        ),
      ],
      supportingCharacters: [
        SupportingCharacter(id: 'alice', name: 'Alice'),
        SupportingCharacter(id: 'bob', name: 'Bob'),
      ],
      trackedStateDefinitions: withDefinitions
          ? const [
              AdventureTrackedStateDefinition(
                entityType: RuntimeEntityType.character,
                entityId: 'lc',
                definition: _curse,
              ),
              AdventureTrackedStateDefinition(
                entityType: RuntimeEntityType.character,
                entityId: 'lc',
                definition: _trust,
              ),
              AdventureTrackedStateDefinition(
                entityType: RuntimeEntityType.character,
                entityId: 'lc',
                definition: _wounded,
              ),
              AdventureTrackedStateDefinition(
                entityType: RuntimeEntityType.character,
                entityId: 'lc',
                definition: _stance,
              ),
              AdventureTrackedStateDefinition(
                entityType: RuntimeEntityType.character,
                entityId: 'alice',
                definition: _fear,
              ),
              AdventureTrackedStateDefinition(
                entityType: RuntimeEntityType.character,
                entityId: 'bob',
                definition: _fear,
              ),
            ]
          : const [],
    );

void main() {
  final l10n = AppLocalizationsZh();
  late Directory tempDir;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('lt_tracked_summary_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    DatabaseService.customDbDir = null;
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  ProviderContainer containerFor(_TestAdventure adventure, {int index = -1}) {
    final container = ProviderContainer(overrides: [
      chatProvider.overrideWith((ref) => _TestChat(adventure, index: index)),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  Future<void> pumpHud(
    WidgetTester tester, {
    required ProviderContainer container,
    double width = 900,
    double height = 600,
    double scale = 1.0,
    VoidCallback? onTap,
  }) async {
    setViewport(tester, width: width, height: height);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: StatusHudBar(onTap: onTap),
        ),
      ),
    ));
    await tester.pump();
  }

  Future<void> pumpInspector(
    WidgetTester tester, {
    required ProviderContainer container,
    double width = 900,
    double height = 800,
    double scale = 1.0,
  }) async {
    setViewport(tester, width: width, height: height);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: SessionInspectorContent(
            section: SessionInspectorSection.state,
            onCharacters: () {},
            onState: () {},
            onInventory: () {},
            onModel: () {},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// The header owns only scene/vitals. Tracked state must never appear here —
  /// it belongs to each message's per-turn snapshot (and to the Inspector/Hub
  /// for the current value).
  void expectNoTrackedState(WidgetTester tester) {
    expect(find.textContaining(l10n.trackedStateStatusTitle), findsNothing,
        reason: '「检测状态」标题不得出现在 Session Header');
    expect(find.textContaining('精神污染'), findsNothing);
    expect(find.textContaining('信任度'), findsNothing);
    expect(find.textContaining('受伤状态'), findsNothing);
    expect(find.textContaining(l10n.trackedStateUntriggered), findsNothing,
        reason: '「尚未触发」属于正文状态块，不属于 Header');
    expect(find.textContaining(l10n.trackedStateNoDefinitions), findsNothing);
  }

  group('Session header excludes tracked state', () {
    testWidgets('Case B: header shows vitals only, never tracked state',
        (tester) async {
      final container = containerFor(_TestAdventure(
        config: _config(),
        entities: [
          RuntimeEntityState(
            entityType: RuntimeEntityType.character,
            entityId: 'lc',
            overlay: const {'custom_attributes.curse_corruption': 18},
          ),
        ],
      ));
      await pumpHud(tester, container: container);

      expect(find.byType(StatusHudBar), findsOneWidget);
      expect(
          find.textContaining('${l10n.runtimeStateFieldHp} '), findsOneWidget);
      expect(
          find.textContaining('${l10n.runtimeStateFieldMp} '), findsOneWidget);
      expect(find.textContaining('${l10n.workbenchGold} '), findsOneWidget);
      expectNoTrackedState(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('header stays clean when the adventure has no definitions',
        (tester) async {
      final container =
          containerFor(_TestAdventure(config: _config(withDefinitions: false)));
      await pumpHud(tester, container: container);

      expect(
          find.textContaining('${l10n.runtimeStateFieldHp} '), findsOneWidget);
      expectNoTrackedState(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping the header still triggers the vitals callback',
        (tester) async {
      var tapped = false;
      final container = containerFor(_TestAdventure(config: _config()));
      await pumpHud(tester, container: container, onTap: () => tapped = true);

      await tester.tap(find.byType(StatusHudBar));
      await tester.pump();
      expect(tapped, isTrue);
    });

    for (final size in requiredUiViewports) {
      for (final scale in const <double>[1.0, 1.6, 2.0]) {
        testWidgets(
            'header clean + no overflow at ${size.width.toInt()}x${size.height.toInt()} @${scale}x',
            (tester) async {
          final container = containerFor(_TestAdventure(
            config: _config(),
            entities: [
              RuntimeEntityState(
                entityType: RuntimeEntityType.character,
                entityId: 'lc',
                overlay: const {'custom_attributes.curse_corruption': 18},
              ),
            ],
          ));
          await pumpHud(
            tester,
            container: container,
            width: size.width,
            height: size.height,
            scale: scale,
          );
          expectNoTrackedState(tester);
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  group('Session Inspector tracked block', () {
    testWidgets('state section shows the tracked fields and both actions',
        (tester) async {
      final container = containerFor(_TestAdventure(
        config: _config(),
        entities: [
          RuntimeEntityState(
            entityType: RuntimeEntityType.character,
            entityId: 'lc',
            overlay: const {'custom_attributes.curse_corruption': 18},
          ),
        ],
      ));
      await pumpInspector(tester, container: container);

      expect(find.text('${l10n.runtimeStateFieldHp}: 92/100'), findsOneWidget);
      expect(find.text('${l10n.runtimeStateFieldMp}: 61/80'), findsOneWidget);
      expect(find.text('精神污染'), findsOneWidget);
      expect(find.text('18'), findsOneWidget);
      expect(find.text(l10n.trackedStateUntriggered), findsWidgets);
      expect(find.text(l10n.trackedStateViewAllAction), findsOneWidget);
      expect(find.text(l10n.trackedStateManageAction), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('view-all opens the tracked hub view', (tester) async {
      final container = containerFor(_TestAdventure(config: _config()));
      await pumpInspector(tester, container: container);

      await tester.tap(find.text(l10n.trackedStateViewAllAction));
      await tester.pumpAndSettle();

      expect(find.byType(RuntimeStateHubPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('manage opens the management page', (tester) async {
      final container = containerFor(_TestAdventure(config: _config()));
      await pumpInspector(tester, container: container);

      await tester.tap(find.text(l10n.trackedStateManageAction));
      await tester.pumpAndSettle();

      expect(find.byType(TrackedStateManagementPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('no definitions still shows an explicit empty block',
        (tester) async {
      final container =
          containerFor(_TestAdventure(config: _config(withDefinitions: false)));
      await pumpInspector(tester, container: container);

      expect(find.text(l10n.trackedStateNoDefinitions), findsOneWidget);
      expect(find.text(l10n.trackedStateManageAction), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    for (final scale in const <double>[1.0, 1.6, 2.0]) {
      testWidgets('no overflow at 320 px @${scale}x', (tester) async {
        final container = containerFor(_TestAdventure(
          config: _config(),
          entities: [
            RuntimeEntityState(
              entityType: RuntimeEntityType.character,
              entityId: 'lc',
              overlay: const {'custom_attributes.curse_corruption': 18},
            ),
          ],
        ));
        await pumpInspector(tester,
            container: container, width: 320, height: 700, scale: scale);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
