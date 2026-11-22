import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import 'package:lt_dialogue/application/resource_library/character_relationship_management.dart';
import 'package:lt_dialogue/application/setting_cards/setting_card_service.dart';
import 'package:lt_dialogue/core/theme/app_theme.dart';
import 'package:lt_dialogue/domain/resources/character_relationship.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/setting_cards/setting_card.dart';
import 'package:lt_dialogue/features/resource_library/presentation/widgets/setting_card_relationships_section.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';
import 'package:lt_dialogue/services/repositories/character_relationship_repository.dart';

import '../helpers/responsive_test_helper.dart';
import '../helpers/setting_card_fakes.dart';

SettingCard _card({
  required String id,
  required SettingCardKind kind,
  required String name,
  String originWorldviewId = '',
  String? legacyId,
}) =>
    SettingCard(
      id: id,
      kind: kind,
      name: name,
      mode: 'adventure',
      originWorldviewId: originWorldviewId,
      legacyId: legacyId,
      createdAt: '2026-01-01T00:00:00.000',
      updatedAt: '2026-01-01T00:00:00.000',
    );

final class _FakeRelationshipRepository
    implements CharacterRelationshipRepository {
  _FakeRelationshipRepository([List<CharacterRelationship>? initial])
      : relationships = List<CharacterRelationship>.from(
            initial ?? const <CharacterRelationship>[]);

  List<CharacterRelationship> relationships;
  final List<String> deletedIds = <String>[];
  final List<Map<String, Object?>> createArgs = <Map<String, Object?>>[];

  @override
  Future<List<CharacterRelationship>> listForResource(
          ResourceId resourceId) async =>
      relationships
          .where((relationship) =>
              relationship.endpointAResourceId == resourceId ||
              relationship.endpointBResourceId == resourceId)
          .toList();

  @override
  Future<CharacterRelationship> create({
    required ResourceId firstResourceId,
    required String firstRole,
    required ResourceId secondResourceId,
    required String secondRole,
    required CharacterRelationshipType relationType,
    String description = '',
  }) async {
    createArgs.add(<String, Object?>{
      'first': firstResourceId.value,
      'firstRole': firstRole,
      'second': secondResourceId.value,
      'secondRole': secondRole,
      'type': relationType,
      'description': description,
    });
    final created = CharacterRelationship(
      id: 'r-created',
      endpointAResourceId:
          firstResourceId.value.compareTo(secondResourceId.value) < 0
              ? firstResourceId
              : secondResourceId,
      endpointBResourceId:
          firstResourceId.value.compareTo(secondResourceId.value) < 0
              ? secondResourceId
              : firstResourceId,
      relationType: relationType,
      endpointARole: firstResourceId.value.compareTo(secondResourceId.value) < 0
          ? firstRole
          : secondRole,
      endpointBRole: firstResourceId.value.compareTo(secondResourceId.value) < 0
          ? secondRole
          : firstRole,
      description: description,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    relationships = [...relationships, created];
    return created;
  }

  @override
  Future<CharacterRelationship?> getById(String id) async {
    for (final relationship in relationships) {
      if (relationship.id == id) return relationship;
    }
    return null;
  }

  @override
  Future<void> delete(String id) async {
    deletedIds.add(id);
    relationships =
        relationships.where((relationship) => relationship.id != id).toList();
  }

  @override
  Future<CharacterRelationship?> findBetween(
          ResourceId first, ResourceId second) async =>
      null;

  @override
  Future<CharacterRelationship> update({
    required String id,
    required CharacterRelationshipType relationType,
    required String endpointARole,
    required String endpointBRole,
    required String description,
  }) =>
      throw UnimplementedError();

  @override
  Future<int> deleteForResourcePurge(
          DatabaseExecutor txn, ResourceId resourceId) =>
      throw UnimplementedError();

  @override
  Future<CharacterRelationship> createInTransaction(
    DatabaseExecutor txn, {
    required ResourceId firstResourceId,
    required String firstRole,
    required ResourceId secondResourceId,
    required String secondRole,
    required CharacterRelationshipType relationType,
    String description = '',
  }) =>
      throw UnimplementedError();
}

Widget _app({
  required SettingCard card,
  required _FakeRelationshipRepository relationships,
  required MemorySettingCardRepository cards,
}) =>
    ProviderScope(
      overrides: [
        characterRelationshipManagementProvider.overrideWithValue(
          CharacterRelationshipManagement(relationships),
        ),
        settingCardServiceProvider.overrideWithValue(
          SettingCardService(repository: cards),
        ),
      ],
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: SettingCardRelationshipsSection(card: card),
          ),
        ),
      ),
    );

Future<void> _pumpCards(
  WidgetTester tester, {
  required SettingCard card,
  required _FakeRelationshipRepository relationships,
  required MemorySettingCardRepository cards,
  double width = 800,
  double height = 1000,
}) async {
  setViewport(tester, width: width, height: height);
  await tester.pumpWidget(
    _app(card: card, relationships: relationships, cards: cards),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists counterpart names, relationship and roles',
      (tester) async {
    final cards = MemorySettingCardRepository();
    await cards
        .save(_card(id: 'sc_guard', kind: SettingCardKind.npc, name: '北门守卫'));
    final repo = _FakeRelationshipRepository([
      CharacterRelationship(
        id: 'r1',
        endpointAResourceId: const ResourceId('sc_guard'),
        endpointBResourceId: const ResourceId('sc_lynn'),
        relationType: CharacterRelationshipType.friend,
        endpointARole: 'guard',
        endpointBRole: 'resident',
        description: '常在北门聊天',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ),
    ]);

    await _pumpCards(
      tester,
      card: _card(id: 'sc_lynn', kind: SettingCardKind.character, name: '林恩'),
      relationships: repo,
      cards: cards,
    );

    expect(find.text('北门守卫'), findsOneWidget);
    expect(find.text('朋友 · resident / guard'), findsOneWidget);
    expect(find.text('常在北门聊天'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('adds a relationship and refreshes the list', (tester) async {
    final cards = MemorySettingCardRepository();
    await cards
        .save(_card(id: 'sc_guard', kind: SettingCardKind.npc, name: '北门守卫'));
    final repo = _FakeRelationshipRepository();

    await _pumpCards(
      tester,
      card: _card(id: 'sc_lynn', kind: SettingCardKind.character, name: '林恩'),
      relationships: repo,
      cards: cards,
    );

    await tester
        .tap(find.byKey(const Key('setting-card-relationship-counterpart')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('北门守卫').last);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('setting-card-relationship-subject-role')),
      'resident',
    );
    await tester.enterText(
      find.byKey(const Key('setting-card-relationship-counterpart-role')),
      'guard',
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('setting-card-relationship-save')));
    await tester.pumpAndSettle();

    expect(repo.createArgs, hasLength(1));
    expect(repo.createArgs.single['first'], 'sc_guard');
    expect(repo.createArgs.single['firstRole'], 'guard');
    expect(repo.createArgs.single['second'], 'sc_lynn');
    expect(repo.createArgs.single['secondRole'], 'resident');
    expect(repo.createArgs.single['type'], CharacterRelationshipType.friend);

    expect(find.text('北门守卫'), findsOneWidget);
    expect(find.text('朋友 · resident / guard'), findsOneWidget);
  });

  testWidgets('blocks a cross-world counterpart and disables saving',
      (tester) async {
    final cards = MemorySettingCardRepository();
    await cards.save(_card(
      id: 'sc_guard',
      kind: SettingCardKind.npc,
      name: '北门守卫',
      originWorldviewId: 'world_b',
    ));
    final repo = _FakeRelationshipRepository();

    await _pumpCards(
      tester,
      card: _card(
        id: 'sc_lynn',
        kind: SettingCardKind.character,
        name: '林恩',
        originWorldviewId: 'world_a',
      ),
      relationships: repo,
      cards: cards,
    );

    await tester
        .tap(find.byKey(const Key('setting-card-relationship-counterpart')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('北门守卫').last);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('setting-card-relationship-subject-role')),
      'resident',
    );
    await tester.enterText(
      find.byKey(const Key('setting-card-relationship-counterpart-role')),
      'guard',
    );
    await tester.pump();

    expect(find.text('不能与其它世界观的角色建立关系'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('setting-card-relationship-save')),
    );
    expect(button.onPressed, isNull);
    expect(repo.createArgs, isEmpty);
  });

  testWidgets('treats a legacy worldview id and its card id as the same world',
      (tester) async {
    final cards = MemorySettingCardRepository();
    await cards.save(_card(
      id: 'res_legacy_worldview_presets_w1',
      legacyId: 'w1',
      kind: SettingCardKind.worldview,
      name: '银月大陆',
    ));
    await cards.save(_card(
      id: 'sc_guard',
      kind: SettingCardKind.npc,
      name: '北门守卫',
      // Migrated rows keep the raw legacy id.
      originWorldviewId: 'w1',
    ));
    final repo = _FakeRelationshipRepository();

    await _pumpCards(
      tester,
      card: _card(
        id: 'sc_lynn',
        kind: SettingCardKind.character,
        name: '林恩',
        // New cards bind the setting-card id of the same worldview.
        originWorldviewId: 'res_legacy_worldview_presets_w1',
      ),
      relationships: repo,
      cards: cards,
    );

    await tester
        .tap(find.byKey(const Key('setting-card-relationship-counterpart')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('北门守卫').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('setting-card-relationship-subject-role')),
      'resident',
    );
    await tester.enterText(
      find.byKey(const Key('setting-card-relationship-counterpart-role')),
      'guard',
    );
    await tester.pump();

    expect(find.text('不能与其它世界观的角色建立关系'), findsNothing);
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('setting-card-relationship-save')),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets('deletes a relationship through the management boundary',
      (tester) async {
    final cards = MemorySettingCardRepository();
    await cards
        .save(_card(id: 'sc_guard', kind: SettingCardKind.npc, name: '北门守卫'));
    final repo = _FakeRelationshipRepository([
      CharacterRelationship(
        id: 'r1',
        endpointAResourceId: const ResourceId('sc_guard'),
        endpointBResourceId: const ResourceId('sc_lynn'),
        relationType: CharacterRelationshipType.friend,
        endpointARole: 'guard',
        endpointBRole: 'resident',
        description: '',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ),
    ]);

    await _pumpCards(
      tester,
      card: _card(id: 'sc_lynn', kind: SettingCardKind.character, name: '林恩'),
      relationships: repo,
      cards: cards,
    );

    await tester
        .tap(find.byKey(const ValueKey('setting-card-relationship-delete-r1')));
    await tester.pumpAndSettle();

    expect(repo.deletedIds, ['r1']);
    expect(find.byKey(const ValueKey('setting-card-relationship-r1')),
        findsNothing);
  });

  testWidgets('renders nothing for a worldview card', (tester) async {
    final cards = MemorySettingCardRepository();
    await _pumpCards(
      tester,
      card:
          _card(id: 'sc_world', kind: SettingCardKind.worldview, name: '银月大陆'),
      relationships: _FakeRelationshipRepository(),
      cards: cards,
    );

    expect(find.byType(SettingCardRelationshipsSection), findsOneWidget);
    expect(find.text('关系'), findsNothing);
  });

  testWidgets('does not overflow at 320 px with enlarged text', (tester) async {
    final cards = MemorySettingCardRepository();
    await cards
        .save(_card(id: 'sc_guard', kind: SettingCardKind.npc, name: '北门守卫'));
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await _pumpCards(
      tester,
      card: _card(id: 'sc_lynn', kind: SettingCardKind.character, name: '林恩'),
      relationships: _FakeRelationshipRepository(),
      cards: cards,
      width: 320,
      height: 568,
    );

    expect(tester.takeException(), isNull);
  });
}
