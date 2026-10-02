import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guard: the Resource Library「角色状态」surface is a **derived presentation**.
///
/// It must never become a fourth resource type, a new persistence authority, or
/// a runtime-state reader. These are the invariants the feature is built on.
void main() {
  group('Resource character status boundary', () {
    test('ResourceType stays exactly worldview / character / npc', () {
      final contracts = File('lib/domain/resources/resource_contracts.dart')
          .readAsStringSync();
      expect(contracts, contains('enum ResourceType {'));
      expect(contracts, contains('worldview,'));
      expect(contracts, contains('character,'));
      expect(contracts, contains('npc;'));
      // No fourth resource type was invented for the derived view.
      expect(contracts, isNot(contains('characterStatus')));
      expect(contracts, isNot(contains('character_status')));
    });

    test('the projection reads definitions only, never runtime state', () {
      final runtime = File(
        'lib/features/resource_library/application/use_cases/character_status_library_runtime.dart',
      ).readAsStringSync();
      // Source: the existing library repository, decoding tracked definitions.
      expect(runtime, contains('ILibraryRepository'));
      expect(runtime, contains('trackedStateDefinitions'));
      // No adventure runtime coupling, no writes.
      expect(runtime, isNot(contains('adventureProvider')));
      expect(runtime, isNot(contains('AdventureProvider')));
      expect(runtime, isNot(contains('RuntimeEntityState')));
      expect(runtime, isNot(contains('overlay')));
      expect(runtime, isNot(contains('commitRuntimeMutation')));
    });

    test('the surface never reads adventure runtime values', () {
      final surface = File(
        'lib/features/resource_library/presentation/widgets/character_status_library_surface.dart',
      ).readAsStringSync();
      expect(surface, isNot(contains('adventureProvider')));
      expect(surface, isNot(contains('runtimeEntities')));
      expect(surface, isNot(contains('RuntimeEntityState')));
      expect(surface, isNot(contains('overlay')));
      expect(surface, isNot(contains('revision')));
    });

    test('the controller owns no persistence authority', () {
      final controller = File(
        'lib/features/resource_library/presentation/controllers/character_status_library_controller.dart',
      ).readAsStringSync();
      expect(controller, contains('CharacterStatusLibraryRuntime'));
      // Read-only: it never saves a definition or writes storage.
      expect(controller, isNot(contains('saveCharacterCard')));
      expect(controller, isNot(contains('saveNpcCard')));
      expect(controller, isNot(contains('updateAdventureConfig')));
      expect(controller, isNot(contains('LibraryRepository')));
    });

    test('the library screen wires the derived view', () {
      final screen = File(
        'lib/features/resource_library/presentation/screens/resource_library_screen.dart',
      ).readAsStringSync();
      expect(screen, contains('ResourceLibraryFilter.characterStatus'));
      expect(screen, contains('CharacterStatusLibrarySurface'));
      expect(screen, contains('resourceCharacterStatusTab'));
      // The derived view still commits no resource of a new type.
      expect(screen, isNot(contains('ResourceType.characterStatus')));
    });
  });
}
