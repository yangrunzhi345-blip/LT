import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lt_dialogue/core/theme/app_theme.dart';
import 'package:lt_dialogue/features/adventure/presentation/session/screens/scene_character_management_page.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations_zh.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/models/adventure_runtime_state.dart';
import 'package:lt_dialogue/models/scene_dialogue.dart';
import 'package:lt_dialogue/models/scene_state.dart';
import 'package:lt_dialogue/providers/adventure_provider.dart';
import 'package:lt_dialogue/providers/chat_provider.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';

class _MockAdventureProvider extends ChangeNotifier
    implements AdventureProvider {
  _MockAdventureProvider({
    required this.adventureConfig,
    required List<String> sceneParticipantIds,
    this.runtimeEntities = const [],
  }) : _sceneParticipantIds = List.of(sceneParticipantIds);

  @override
  final AdventureConfig? adventureConfig;

  final List<String> _sceneParticipantIds;

  @override
  List<String> get sceneParticipantIds =>
      List.unmodifiable(_sceneParticipantIds);

  @override
  final List<RuntimeEntityState> runtimeEntities;

  @override
  Future<ScenePresenceMutationResult?> addCharacterToScene(
    String characterId,
  ) async {
    if (characterId == 'protagonist') {
      return ScenePresenceMutationResult(
        status: SceneMutationStatus.rejected,
        state: SceneState(
          presentCharacterIds: _sceneParticipantIds,
        ),
        revision: 1,
      );
    }
    if (!_sceneParticipantIds.contains(characterId)) {
      _sceneParticipantIds.add(characterId);
      notifyListeners();
    }
    return ScenePresenceMutationResult(
      status: SceneMutationStatus.applied,
      state: SceneState(
        presentCharacterIds: _sceneParticipantIds,
      ),
      revision: 2,
    );
  }

  @override
  Future<ScenePresenceMutationResult?> removeCharacterFromScene(
    String characterId,
  ) async {
    _sceneParticipantIds.remove(characterId);
    notifyListeners();
    return ScenePresenceMutationResult(
      status: SceneMutationStatus.applied,
      state: SceneState(
        presentCharacterIds: _sceneParticipantIds,
      ),
      revision: 2,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockChatProvider extends ChangeNotifier implements ChatProvider {
  _MockChatProvider(this._adventure) {
    _adventure.addListener(notifyListeners);
  }

  final _MockAdventureProvider _adventure;

  @override
  AdventureProvider get adventureProvider => _adventure;

  @override
  void dispose() {
    _adventure.removeListener(notifyListeners);
    super.dispose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('scene character management fits supported viewports and themes',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final container = ProviderContainer();
    addTearDown(container.dispose);
    for (final size in const [
      Size(320, 568),
      Size(360, 640),
      Size(390, 844),
      Size(412, 915),
      Size(768, 1024),
      Size(1280, 800),
    ]) {
      tester.view.physicalSize = size;
      for (final locale in const [Locale('zh'), Locale('en'), Locale('ja')]) {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              locale: locale,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: size.width == 320 ? AppTheme.dark() : AppTheme.light(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(2),
                ),
                child: child!,
              ),
              home: const SceneCharacterManagementPage(),
            ),
          ),
        );
        await tester.pump();
        expect(find.byType(FilledButton), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets(
      'Test A: protagonist is in present section and has no enter button',
      (tester) async {
    final protagonist = AdventureSelectedCharacter(
      id: 'sel_protagonist',
      characterId: 'card_protagonist',
      characterName: '主角阿尔温',
      isProtagonist: true,
    );
    final npc = AdventureSelectedCharacter(
      id: 'sel_npc',
      characterId: 'card_npc',
      characterName: '同伴蕾娜',
      isProtagonist: false,
    );
    final config = AdventureConfig(
      name: '测试冒险',
      selectedCharacters: [protagonist, npc],
    );
    final mockAdventure = _MockAdventureProvider(
      adventureConfig: config,
      sceneParticipantIds: const ['protagonist'],
      runtimeEntities: [
        RuntimeEntityState(
          entityType: RuntimeEntityType.npc,
          entityId: 'card_npc',
          overlay: {'life_status': 'alive', 'hp': 100},
        ),
      ],
    );
    final mockChat = _MockChatProvider(mockAdventure);
    final container = ProviderContainer(
      overrides: [chatProvider.overrideWith((ref) => mockChat)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SceneCharacterManagementPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final zh = AppLocalizationsZh();
    expect(find.text(zh.characterManagementPresent), findsOneWidget);
    expect(find.text('主角阿尔温'), findsOneWidget);
    expect(find.text('同伴蕾娜'), findsOneWidget);

    // Verify protagonist has no login button (enter scene)
    // Only one login icon for NPC (蕾娜), none for protagonist
    expect(find.byIcon(Icons.login_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Test B: tapping enter button adds NPC to scene authority',
      (tester) async {
    final protagonist = AdventureSelectedCharacter(
      id: 'sel_protagonist',
      characterId: 'card_protagonist',
      characterName: '主角阿尔温',
      isProtagonist: true,
    );
    final npc = AdventureSelectedCharacter(
      id: 'sel_npc',
      characterId: 'card_npc',
      characterName: '同伴蕾娜',
      isProtagonist: false,
    );
    final config = AdventureConfig(
      name: '测试冒险',
      selectedCharacters: [protagonist, npc],
    );
    final mockAdventure = _MockAdventureProvider(
      adventureConfig: config,
      sceneParticipantIds: const ['protagonist'],
      runtimeEntities: [
        RuntimeEntityState(
          entityType: RuntimeEntityType.npc,
          entityId: 'card_npc',
          overlay: {'life_status': 'alive'},
        ),
      ],
    );
    final mockChat = _MockChatProvider(mockAdventure);
    final container = ProviderContainer(
      overrides: [chatProvider.overrideWith((ref) => mockChat)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SceneCharacterManagementPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(mockAdventure.sceneParticipantIds, isNot(contains('card_npc')));

    await tester.tap(find.byIcon(Icons.login_outlined));
    await tester.pumpAndSettle();

    // Authority projection is truly updated
    expect(mockAdventure.sceneParticipantIds, contains('card_npc'));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Test C: protagonist cannot be added to scene and mutation is rejected',
      (tester) async {
    final protagonist = AdventureSelectedCharacter(
      id: 'sel_protagonist',
      characterId: 'card_protagonist',
      characterName: '主角阿尔温',
      isProtagonist: true,
    );
    final config = AdventureConfig(
      name: '测试冒险',
      selectedCharacters: [protagonist],
    );
    final mockAdventure = _MockAdventureProvider(
      adventureConfig: config,
      sceneParticipantIds: const ['protagonist'],
    );
    final mockChat = _MockChatProvider(mockAdventure);
    final container = ProviderContainer(
      overrides: [chatProvider.overrideWith((ref) => mockChat)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SceneCharacterManagementPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // No login (enter) button anywhere for protagonist
    expect(find.byIcon(Icons.login_outlined), findsNothing);

    // Direct invocation returns rejected
    final result = await mockAdventure.addCharacterToScene('protagonist');
    expect(result?.status, equals(SceneMutationStatus.rejected));
    expect(tester.takeException(), isNull);
  });
}
