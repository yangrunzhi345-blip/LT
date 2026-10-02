import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lt_dialogue/core/theme/app_theme.dart';
import 'package:lt_dialogue/features/adventure/presentation/session/screens/tracked_state_management_page.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/models/adventure_runtime_state.dart';
import 'package:lt_dialogue/models/adventure_tracked_state.dart';
import 'package:lt_dialogue/models/supporting_character.dart';
import 'package:lt_dialogue/models/tracked_state_definition.dart';
import 'package:lt_dialogue/providers/adventure_provider.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';
import 'package:lt_dialogue/services/repositories/adventure_repository.dart';
import 'package:lt_dialogue/services/repositories/library_repository.dart';
import 'package:lt_dialogue/services/repositories/world_entry_repository.dart';

class _Fake {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeRepo extends _Fake implements IAdventureRepository {}

class _FakeWorldRepo extends _Fake implements IWorldEntryRepository {}

class _FakeLibraryRepo extends _Fake implements ILibraryRepository {}

AdventureConfig _rosterConfig() => AdventureConfig(
      name: 'Alice',
      selectedCharacters: [
        AdventureSelectedCharacter(
          id: 'alice',
          characterId: 'alice',
          characterName: 'Alice',
          isProtagonist: true,
        ),
        AdventureSelectedCharacter(
          id: 'bob',
          characterId: 'bob',
          characterName: 'Bob',
        ),
      ],
      supportingCharacters: [
        SupportingCharacter(id: 'carol', name: 'Carol'),
      ],
      npcSnapshots: [
        AdventureNpcSnapshot(assetId: 'guard', name: '守门人', npcJson: const {}),
      ],
      trackedStateDefinitions: const [
        AdventureTrackedStateDefinition(
          entityType: RuntimeEntityType.world,
          entityId: AdventureRuntimeEntityIds.world,
          definition: TrackedStateDefinition(id: 'war', name: '战争紧张度'),
        ),
      ],
    );

void main() {
  testWidgets(
      'management roster covers world, characters, selected-only and NPC',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final adventure = AdventureProvider(
      adventureRepo: _FakeRepo(),
      worldEntryRepo: _FakeWorldRepo(),
      libraryRepo: _FakeLibraryRepo(),
    );
    adventure.startNewAdventureConfig(_rosterConfig());

    final container = ProviderContainer(overrides: [
      adventureProvider.overrideWith((ref) => adventure),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.light(),
        home: const TrackedStateManagementPage(),
      ),
    ));
    await tester.pumpAndSettle();

    // Every roster source is present, world first, and none is downgraded.
    // (「世界」 appears as both the group label and the world tile label.)
    expect(find.text('世界'), findsAtLeastNWidgets(1));
    expect(
      find.byKey(const ValueKey('tracked-entity-world-world')),
      findsOneWidget,
    );
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Carol'), findsOneWidget);
    expect(find.text('守门人'), findsOneWidget);

    // World is selectable and editable — no character-only gate.
    await tester.tap(find.byKey(const ValueKey('tracked-entity-world-world')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // NPC is selectable and editable.
    await tester.tap(find.byKey(const ValueKey('tracked-entity-npc-guard')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
