import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/features/adventure/presentation/state/tracked_state_overview_panel.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/models/adventure_runtime_state.dart';
import 'package:lt_dialogue/models/adventure_tracked_state.dart';
import 'package:lt_dialogue/models/tracked_state_definition.dart';

import '../helpers/responsive_test_helper.dart';

final _config = AdventureConfig(
  name: 'Alice',
  trackedStateDefinitions: const [
    AdventureTrackedStateDefinition(
      entityType: RuntimeEntityType.character,
      entityId: 'bob',
      definition: TrackedStateDefinition(id: 'fear', name: '恐惧程度'),
    ),
    AdventureTrackedStateDefinition(
      entityType: RuntimeEntityType.world,
      entityId: AdventureRuntimeEntityIds.world,
      definition: TrackedStateDefinition(id: 'war_tension', name: '战争紧张度'),
    ),
  ],
);

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: TrackedStateOverviewPanel(
        config: _config,
        entities: [
          RuntimeEntityState(
            entityType: RuntimeEntityType.character,
            entityId: 'bob',
            overlay: const {'custom_attributes.fear': 30},
          ),
        ],
        entityNames: const {
          'bob': 'Bob',
          AdventureRuntimeEntityIds.world: '艾尔德兰',
        },
      ),
    ),
  ));
}

void main() {
  testWidgets('renders per-entity monitors with values and untriggered state',
      (tester) async {
    await _pump(tester);

    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('恐惧程度'), findsOneWidget);
    expect(find.text('30'), findsOneWidget);
    // The world monitor has no runtime value yet: it must read as untriggered,
    // not as a fabricated zero.
    expect(find.text('战争紧张度'), findsOneWidget);
    expect(find.text('0'), findsNothing);
  });

  testWidgets('does not overflow at 320 px', (tester) async {
    setViewport(tester, width: 320, height: 568);
    await _pump(tester);

    expect(tester.takeException(), isNull);
  });
}
