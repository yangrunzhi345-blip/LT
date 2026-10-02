import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guard: the tracked-state UI must stay **visible, reachable and manageable**.
///
/// The underlying runtime authority is already covered elsewhere; this guard is
/// about discoverability. It fails the build if the tracked view loses its
/// first-class navigation entry, if the empty state stops offering a management
/// action, or if a resource detail stops surfacing its definitions.
void main() {
  group('Tracked state UI reachability', () {
    test('the runtime hub exposes tracked as a first-class view', () {
      final hub = File(
        'lib/features/adventure/presentation/state/runtime_state_hub_page.dart',
      ).readAsStringSync();
      expect(hub, contains('_RuntimeStateView.tracked'));
      expect(hub, contains('RuntimeStateHubInitialView'));
      expect(hub, contains('_buildTrackedView'));
      expect(hub, contains('TrackedStateManagementPage'));
    });

    test('the tracked panel keeps its management action even when empty', () {
      final panel = File(
        'lib/features/adventure/presentation/state/tracked_state_overview_panel.dart',
      ).readAsStringSync();
      // Empty state must carry the call to action; never a bare text early return.
      expect(panel, contains('AppEmptyState'));
      expect(panel, contains('onAction: onManage'));
      expect(panel, contains('trackedStateAddFirstAction'));
      // The non-empty path still renders the management action.
      expect(panel, contains('trackedStateManageAction'));
      expect(panel, contains('_managementAction'));
    });

    test('the management roster covers every entity source', () {
      final page = File(
        'lib/features/adventure/presentation/session/screens/tracked_state_management_page.dart',
      ).readAsStringSync();
      expect(page, contains('selectedCharacters'));
      expect(page, contains('supportingCharacters'));
      expect(page, contains('npcSnapshots'));
      expect(page, contains('AdventureRuntimeEntityIds.world'));
    });

    test('the session inspector links to the tracked view', () {
      final inspector = File(
        'lib/features/adventure/presentation/session/widgets/session_inspector.dart',
      ).readAsStringSync();
      expect(inspector, contains('RuntimeStateHubInitialView.tracked'));
      expect(inspector, contains('trackedStateStatusTitle'));
    });

    test('resource detail surfaces definitions, never a current value', () {
      final detail = File(
        'lib/features/resource_library/presentation/screens/resource_library_detail_page.dart',
      ).readAsStringSync();
      expect(detail, contains('_buildTrackedDefinitionsSection'));
      expect(detail, contains('_trackedStateDefinitions'));
      expect(detail, contains('trackedStateMonitorLabel'));
      // Definitions are definitions: no runtime overlay is read in the detail.
      expect(detail, isNot(contains('RuntimeEntityState')));
    });
  });
}
