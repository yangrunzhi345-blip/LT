import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/features/adventure/presentation/state/runtime_state_hub_page.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations_zh.dart';
import 'package:lt_dialogue/models/adventure_runtime_state.dart';
import 'package:lt_dialogue/models/turn_state_history.dart';
import 'package:lt_dialogue/models/typed_runtime_state.dart';

void main() {
  final l10n = AppLocalizationsZh();

  final forbiddenTokens = <String>[
    'res_cre_',
    'char_internal',
    'entityId',
    'attributeId',
    'statePath',
    'revision',
    'commitId',
    'requestId',
    'branchId',
    'runtimeId',
    'file:///',
    '/home/',
    'SELECT',
    'INSERT',
    'UPDATE',
    'StackTrace',
    'Exception:',
    '{"raw_json',
  ];

  void assertNoForbiddenTokens(WidgetTester tester) {
    for (final token in forbiddenTokens) {
      expect(
        find.textContaining(token),
        findsNothing,
        reason: 'Forbidden token "$token" leaked to UI',
      );
    }
  }

  testWidgets(
      'TurnStateDetailPage sanitizes technical protocol and database data completely',
      (tester) async {
    const rawEntityId = 'res_cre_char_internal_9988';
    const rawCommitId = 'commit_hex_abcdef1234567890';
    const rawRequestId = 'req_internal_uuid_4567';
    const rawPath = 'custom_attributes.detected_trait_4455';

    final maliciousTurn = TurnStateChangeGroup(
      adventureId: 101,
      branchId: 1,
      turnId: 'turn-999',
      turnRowId: 999,
      turnNumber: 5,
      requestId: rawRequestId,
      occurredAt: DateTime(2026, 9, 26, 15, 30),
      revisionStart: 10,
      revisionEnd: 12,
      changes: [
        const TurnStateChange(
          entityType: RuntimeEntityType.character,
          entityId: rawEntityId,
          path: rawPath,
          before: {'raw_json_before': true},
          after: '{"raw_json_after": 42}',
          reason: 'SELECT * FROM adventure_state_commits WHERE id = 1',
          commitId: rawCommitId,
          revision: 11,
          causeType: 'scene_dialogue',
        ),
        const TurnStateChange(
          entityType: RuntimeEntityType.location,
          entityId: 'res_cre_location_99',
          path: 'condition',
          before: 'file:///home/yrz/LT/test.db',
          after: 'Exception: database locked',
          reason: 'StackTrace: #0 runWorker() at /home/yrz/LT/main.dart',
          commitId: rawCommitId,
          revision: 12,
          causeType: 'system_rule',
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: TurnStateDetailPage(turn: maliciousTurn),
        ),
      ),
    );
    await tester.pumpAndSettle();

    assertNoForbiddenTokens(tester);

    // Assert that safe localized labels were used instead
    expect(find.text(l10n.runtimeStateTurnLabel(5)), findsAtLeastNWidgets(1));
    expect(find.text(l10n.runtimeStateTurnSummary), findsOneWidget);
    expect(find.text(l10n.runtimeStateCharacterChanges), findsOneWidget);
    expect(find.text(l10n.runtimeStateWorldChanges), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'RuntimeEntityStatePage sanitizes raw IDs, maps, and technical paths',
      (tester) async {
    const rawId = 'res_cre_char_internal_001';
    final entity = RuntimeEntityState(
      entityType: RuntimeEntityType.character,
      entityId: rawId,
      overlay: {
        'hp': 80,
        'faction_id': 'res_cre_faction_002',
        'controller_id': 'res_cre_controller_003',
        'custom_attributes.detected_luck': '{"raw_json": 100}',
        'status': {'complex': 'map_data'},
      },
      lifecycleStatus: 'active',
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: RuntimeEntityStatePage(entity: entity),
        ),
      ),
    );
    await tester.pumpAndSettle();

    assertNoForbiddenTokens(tester);

    expect(find.text('80'), findsOneWidget);
    expect(find.text(l10n.characterStatusTitle), findsAtLeastNWidgets(1));
    expect(find.text(l10n.runtimeStateFieldHp), findsOneWidget);
    expect(find.text(l10n.runtimeStateConfigured), findsAtLeastNWidgets(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'RuntimeTimelineDetailPage sanitizes internal diff metadata and reasons',
      (tester) async {
    final entry = RuntimeTimelineEntry(
      commitId: 'commit_hex_internal_9999',
      adventureId: 1,
      branchId: 0,
      revision: 4,
      occurredAt: DateTime(2026, 9, 26, 12, 0),
      summary: 'UPDATE adventure_runtime_entities SET revision = 4',
      sourceMessageId: 'req_internal_msg_1',
      causeType: 'scene_dialogue',
      isLegacy: false,
      events: const [],
      diffs: const [
        RuntimeStateDiff(
          entityId: 'res_cre_character_42',
          entityType: RuntimeEntityType.character,
          path: 'custom_attributes.detected_stamina',
          before: 'file:///home/yrz/db.sqlite',
          after: 95,
          commitId: 'commit_hex_internal_9999',
          revision: 4,
          source: RuntimeEventSource.aiProposal,
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: RuntimeTimelineDetailPage(entry: entry),
        ),
      ),
    );
    await tester.pumpAndSettle();

    assertNoForbiddenTokens(tester);
    expect(tester.takeException(), isNull);
  });
}
