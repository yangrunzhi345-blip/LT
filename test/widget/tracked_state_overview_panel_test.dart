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
      entityType: RuntimeEntityType.npc,
      entityId: 'guard',
      definition: TrackedStateDefinition(id: 'alertness', name: '警戒程度'),
    ),
    AdventureTrackedStateDefinition(
      entityType: RuntimeEntityType.world,
      entityId: AdventureRuntimeEntityIds.world,
      definition: TrackedStateDefinition(
        id: 'war_tension',
        name: '战争紧张度',
        minimum: 0,
        maximum: 100,
      ),
    ),
  ],
);

final _entities = [
  RuntimeEntityState(
    entityType: RuntimeEntityType.character,
    entityId: 'bob',
    overlay: const {'custom_attributes.fear': 30},
  ),
];

const _names = {
  'bob': 'Bob',
  'guard': '守门人',
  AdventureRuntimeEntityIds.world: '艾尔德兰',
};

Future<void> _pump(
  WidgetTester tester, {
  AdventureConfig? config,
  List<RuntimeEntityState> entities = const [],
  VoidCallback? onManage,
  TrackedStateCategory category = TrackedStateCategory.all,
  bool compact = false,
}) async {
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: TrackedStateOverviewPanel(
        config: config ?? _config,
        entities: entities,
        entityNames: _names,
        onManage: onManage,
        category: category,
        compact: compact,
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders every entity type with values and untriggered state',
      (tester) async {
    await _pump(tester, entities: _entities);

    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('恐惧程度'), findsOneWidget);
    expect(find.text('30'), findsOneWidget);
    // NPC + world are first-class, not folded into「角色」.
    expect(find.text('守门人'), findsOneWidget);
    expect(find.text('警戒程度'), findsOneWidget);
    expect(find.text('艾尔德兰'), findsOneWidget);
    expect(find.text('战争紧张度'), findsOneWidget);
    // Untriggered reads as a status, never a fabricated zero.
    expect(find.text('Not triggered'), findsNWidgets(2));
    expect(find.text('0'), findsNothing);
  });

  testWidgets('numeric monitor with a range shows value and range',
      (tester) async {
    await _pump(tester, entities: [
      RuntimeEntityState(
        entityType: RuntimeEntityType.world,
        entityId: AdventureRuntimeEntityIds.world,
        overlay: const {'custom_attributes.war_tension': 72},
      ),
    ]);

    expect(find.text('72'), findsOneWidget);
    expect(find.text(' / 100'), findsOneWidget);
  });

  testWidgets('empty registry still offers a reachable management action',
      (tester) async {
    var tapped = false;
    await _pump(
      tester,
      config: AdventureConfig(name: 'Empty'),
      onManage: () => tapped = true,
    );

    expect(find.text('No monitored fields'), findsOneWidget);
    // The call to action must survive an empty state.
    final addAction = find.text('Add monitored field');
    expect(addAction, findsOneWidget);

    await tester.tap(addAction);
    await tester.pumpAndSettle();
    expect(tapped, isTrue);
  });

  testWidgets('non-empty panel still exposes the management action',
      (tester) async {
    var tapped = false;
    await _pump(tester, entities: _entities, onManage: () => tapped = true);

    final manageAction = find.text('Manage monitored fields');
    expect(manageAction, findsOneWidget);
    await tester.tap(manageAction);
    await tester.pumpAndSettle();
    expect(tapped, isTrue);
  });

  testWidgets('category filter narrows the entity types', (tester) async {
    await _pump(tester,
        entities: _entities, category: TrackedStateCategory.npc);

    expect(find.text('守门人'), findsOneWidget);
    expect(find.text('Bob'), findsNothing);
    expect(find.text('艾尔德兰'), findsNothing);
  });

  testWidgets('does not overflow at 320 px', (tester) async {
    setViewport(tester, width: 320, height: 568);
    await _pump(tester, entities: _entities, onManage: () {});

    expect(tester.takeException(), isNull);
  });

  testWidgets('does not overflow at 320 px when empty', (tester) async {
    setViewport(tester, width: 320, height: 568);
    await _pump(
      tester,
      config: AdventureConfig(name: 'Empty'),
      onManage: () {},
    );

    expect(tester.takeException(), isNull);
  });
}
