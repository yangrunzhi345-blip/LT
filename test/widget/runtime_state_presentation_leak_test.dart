import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lt_dialogue/features/adventure/presentation/state/runtime_state_hub_page.dart';
import 'package:lt_dialogue/models/adventure_runtime_state.dart';

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
}
