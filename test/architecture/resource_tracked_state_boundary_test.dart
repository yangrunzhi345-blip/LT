import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guard: the Resource Library「检测项目」surface is a **derived presentation**.
///
/// It must never become a fourth resource type, a new persistence authority, or
/// a runtime-state reader. Definition editing must go through the owner's
/// existing save authority, including for NPCs.
void main() {
  group('Resource tracked state boundary', () {
    test('ResourceType stays exactly worldview / character / npc', () {
      final contracts = File('lib/domain/resources/resource_contracts.dart')
          .readAsStringSync();
      expect(contracts, contains('enum ResourceType {'));
      expect(contracts, contains('worldview,'));
      expect(contracts, contains('character,'));
      expect(contracts, contains('npc;'));
      // No fourth resource type was invented for the derived view.
      expect(contracts, isNot(contains('trackedState')));
      expect(contracts, isNot(contains('characterStatus')));
      expect(contracts, isNot(contains('monitor')));
    });

    test('the projection reads definitions only, never runtime state', () {
      final runtime = File(
        'lib/features/resource_library/application/use_cases/tracked_state_library_runtime.dart',
      ).readAsStringSync();
      // Source: the existing library repository, decoding tracked definitions
      // through the shared typed parsers for all three owner types.
      expect(runtime, contains('ILibraryRepository'));
      expect(runtime, contains('getCharacterCards'));
      expect(runtime, contains('getNpcCards'));
      expect(runtime, contains('getWorldviewPresets'));
      expect(runtime, contains('WorldviewEditDraft.fromExisting'));
      expect(runtime, contains('trackedStateDefinitions'));
      // No adventure runtime coupling, no writes, no new persistence.
      expect(runtime, isNot(contains('adventureProvider')));
      expect(runtime, isNot(contains('AdventureProvider')));
      expect(runtime, isNot(contains('RuntimeEntityState')));
      expect(runtime, isNot(contains('overlay')));
      expect(runtime, isNot(contains('commitRuntimeMutation')));
      expect(runtime, isNot(contains('CREATE TABLE')));
    });

    test('the surface never reads adventure runtime values', () {
      final surface = File(
        'lib/features/resource_library/presentation/widgets/tracked_state_library_surface.dart',
      ).readAsStringSync();
      expect(surface, isNot(contains('adventureProvider')));
      expect(surface, isNot(contains('runtimeEntities')));
      expect(surface, isNot(contains('RuntimeEntityState')));
      expect(surface, isNot(contains('overlay')));
      expect(surface, isNot(contains('revision')));
      expect(surface, isNot(contains('current_value')));
    });

    test('the controller owns no persistence authority', () {
      final controller = File(
        'lib/features/resource_library/presentation/controllers/tracked_state_library_controller.dart',
      ).readAsStringSync();
      expect(controller, contains('TrackedStateLibraryRuntime'));
      // Read-only: it never saves a definition or writes storage.
      expect(controller, isNot(contains('saveCharacterCard')));
      expect(controller, isNot(contains('saveNpcCard')));
      expect(controller, isNot(contains('saveWorldview')));
      expect(controller, isNot(contains('updateAdventureConfig')));
      expect(controller, isNot(contains('LibraryRepository')));
    });

    test('the focused editor edits all three owner types through their saves',
        () {
      final editor = File(
        'lib/features/resource_library/presentation/screens/resource_tracked_state_edit_page.dart',
      ).readAsStringSync();
      expect(editor, contains('TrackedStateDefinitionEditorSection'));
      // Existing save authorities — no raw UPDATE, no second authority.
      expect(editor, contains('saveCharacterCardDraft'));
      expect(editor, contains('saveNpcDraft'));
      expect(editor, contains('saveWorldviewDraft'));
      expect(editor, contains('ResourceType.npc')); // NPC is writable.
      expect(editor, isNot(contains('UPDATE ')));
      expect(editor, isNot(contains('current_value')));
      expect(editor, isNot(contains('currentValue')));
    });

    test('the library screen wires the derived view', () {
      final screen = File(
        'lib/features/resource_library/presentation/screens/resource_library_screen.dart',
      ).readAsStringSync();
      expect(screen, contains('ResourceLibraryFilter.trackedState'));
      expect(screen, contains('TrackedStateLibrarySurface'));
      expect(screen, contains('ResourceTrackedStateEditPage'));
      expect(screen, contains('resourceTrackedStateTab'));
      // The derived view still commits no resource of a new type.
      expect(screen, isNot(contains('ResourceType.trackedState')));
      expect(screen, isNot(contains('ResourceType.characterStatus')));
    });
  });
}
