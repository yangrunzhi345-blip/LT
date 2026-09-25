import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/core/theme/app_theme.dart';
import 'package:lt_dialogue/features/adventure/presentation/state/runtime_state_hub_page.dart';
import 'package:lt_dialogue/models/adventure_runtime_state.dart';
import 'package:lt_dialogue/models/runtime_state_history.dart';
import 'package:lt_dialogue/models/typed_runtime_state.dart';

void main() {
  testWidgets('runtime state hub fits supported viewports without exceptions',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final container = ProviderContainer();
    addTearDown(container.dispose);

    for (final size in const [
      Size(320, 568),
      Size(360, 640),
      Size(390, 844),
      Size(412, 915),
      Size(768, 1024),
    ]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(1.3)),
              child: RuntimeStateHubPage(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: 'viewport $size');
    }
  });

  testWidgets('history pages remain usable at the minimum viewport',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final checkpoint = RuntimeStateCheckpoint(
      id: 'test',
      adventureId: 1,
      branchId: 0,
      revision: 0,
      name: 'A very long checkpoint name for responsive layout testing',
      note: 'A long note that must remain readable on a narrow viewport.',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    final pages = <Widget>[
      const RuntimeInitialStatePage(),
      const RuntimeStateCheckpointCreatePage(revision: 0),
      RuntimeStateCheckpointDetailPage(checkpoint: checkpoint),
      const RuntimeStateComparePage(historicalRevision: 0),
      RuntimeEntityHistoryPage(
        entity: RuntimeEntityState(
          entityType: RuntimeEntityType.character,
          entityId: 'a-long-character-id',
        ),
      ),
    ];
    for (final page in pages) {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: page),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
    }
  });
}
