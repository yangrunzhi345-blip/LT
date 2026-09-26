import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:lt_dialogue/features/adventure/presentation/state/runtime_state_hub_page.dart';
import 'package:lt_dialogue/models/adventure_runtime_state.dart';
import 'package:lt_dialogue/models/typed_runtime_state.dart';

void main() {
  testWidgets('entity detail presents labels instead of runtime identifiers',
      (tester) async {
    const rawId = 'character-internal-42';
    await tester.pumpWidget(
      MaterialApp(
        home: RuntimeEntityStatePage(
          entity: RuntimeEntityState(
            entityType: RuntimeEntityType.character,
            entityId: rawId,
            overlay: {
              'hp': 12,
              'faction_id': 'faction-internal-7',
              'life_status': 'alive',
            },
            lifecycleStatus: 'active',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(rawId), findsNothing);
    expect(find.text('生命值'), findsOneWidget);
    expect(find.text('已配置'), findsOneWidget);
    expect(find.text('存活'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('timeline detail hides legacy runtime metadata', (tester) async {
    const rawEntityId = 'res_cre_1789986339088082_1';
    const rawPath = 'custom_attributes.detected_1789998678427';
    final entry = RuntimeTimelineEntry(
      commitId: 'commit-internal',
      adventureId: 1,
      branchId: 0,
      revision: 3,
      occurredAt: DateTime(2026, 9, 25, 23, 55),
      summary: 'Turn settlement runtime changes',
      sourceMessageId: null,
      causeType: 'scene_dialogue',
      isLegacy: false,
      events: const [],
      diffs: const [
        RuntimeStateDiff(
          entityId: rawEntityId,
          entityType: RuntimeEntityType.character,
          path: rawPath,
          before: 92,
          after: 90,
          commitId: 'commit-internal',
          revision: 3,
          source: RuntimeEventSource.aiProposal,
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: RuntimeTimelineDetailPage(entry: entry),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('res_cre_'), findsNothing);
    expect(find.textContaining('custom_attributes'), findsNothing);
    expect(find.textContaining('detected_'), findsNothing);
    expect(find.textContaining('scene_dialogue'), findsNothing);
    expect(find.textContaining('Turn settlement'), findsNothing);
    expect(find.textContaining('Narrative runtime'), findsNothing);
    expect(find.textContaining('未知状态'), findsNothing);
    expect(find.text('92 → 90'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
