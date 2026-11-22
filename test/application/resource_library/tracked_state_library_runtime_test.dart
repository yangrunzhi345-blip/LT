import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/setting_cards/setting_card.dart';
import 'package:lt_dialogue/features/resource_library/application/use_cases/tracked_state_library_runtime.dart';
import 'package:lt_dialogue/models/resource_library_mode.dart';
import 'package:lt_dialogue/services/repositories/library_repository.dart';

import '../../helpers/setting_card_fakes.dart';

Map<String, dynamic> _definitionJson(String id, String name) =>
    <String, dynamic>{
      'id': id,
      'name': name,
      'value_kind': 'integer',
      'minimum': 0,
      'maximum': 100,
    };

Map<String, dynamic> _legacyCharacterRow(String id, String name, String at) =>
    <String, dynamic>{
      'id': id,
      'name': name,
      'updated_at': at,
      'json_data': jsonEncode(<String, dynamic>{
        'name': name,
        'tracked_state_definitions': [_definitionJson('legacy_def', '旧表定义')],
      }),
    };

SettingCard _card({
  required String id,
  required SettingCardKind kind,
  required String name,
  String mode = 'adventure',
  Map<String, Object?> metadata = const <String, Object?>{},
  String? legacyId,
}) =>
    SettingCard(
      id: id,
      kind: kind,
      name: name,
      mode: mode,
      metadata: metadata,
      legacyId: legacyId,
      createdAt: '2026-01-01T00:00:00.000',
      updatedAt: '2026-02-01T00:00:00.000',
    );

final class _FakeLibraryRepository implements ILibraryRepository {
  _FakeLibraryRepository({
    this.characters = const <Map<String, dynamic>>[],
  });

  final List<Map<String, dynamic>> characters;
  List<Map<String, dynamic>> npcs = const <Map<String, dynamic>>[];
  List<Map<String, dynamic>> worldviews = const <Map<String, dynamic>>[];

  @override
  Future<List<Map<String, dynamic>>> getCharacterCards({
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) async =>
      characters;

  @override
  Future<List<Map<String, dynamic>>> getNpcCards({
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) async =>
      npcs;

  @override
  Future<List<Map<String, dynamic>>> getWorldviewPresets({
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) async =>
      worldviews;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  test('loads card definitions, dedupes legacy ids and filters by mode',
      () async {
    final cards = MemorySettingCardRepository();
    await cards.save(_card(
      // Real migration shape: card id is derived, legacy id survives separately.
      id: 'res_legacy_character_cards_legacy-alice',
      legacyId: 'legacy-alice',
      kind: SettingCardKind.character,
      name: '艾莉丝（卡片副本）',
      metadata: {
        'structured_payload': {
          'tracked_state_definitions': [_definitionJson('card_def', '卡片定义')],
        },
      },
    ));
    await cards.save(_card(
      id: 'sc_bob',
      kind: SettingCardKind.character,
      name: '鲍勃',
      metadata: {
        'structured_payload': {
          'tracked_state_definitions': [_definitionJson('bob_def', '警觉')],
        },
      },
    ));
    await cards.save(_card(
      id: 'sc_world',
      kind: SettingCardKind.worldview,
      name: '银月大陆',
      mode: 'conversation',
      metadata: {
        'detail_json': {
          'tracked_state_definitions': [_definitionJson('war', '战争紧张度')],
        },
      },
    ));
    await cards.save(_card(
      id: 'sc_empty',
      kind: SettingCardKind.npc,
      name: '无名',
    ));

    final runtime = ProductionTrackedStateLibraryRuntime(
      repository: _FakeLibraryRepository(
        characters: [_legacyCharacterRow('legacy-alice', '艾莉丝', '2026-01-01')],
      ),
      cards: cards,
    );

    final entries = await runtime.load(ResourceLibraryMode.adventure);

    expect(
        entries.map((entry) => entry.resourceId), ['legacy-alice', 'sc_bob']);
    final legacy = entries.first;
    expect(legacy.definitions.single.id, 'legacy_def');
    expect(legacy.definitions.single.name, '旧表定义');

    final conversation = await runtime.load(ResourceLibraryMode.conversation);
    expect(
      conversation.map((entry) => entry.resourceId),
      containsAll(<String>['legacy-alice', 'sc_world']),
    );
    // A card created for the adventure library stays out of conversation mode.
    expect(
      conversation.map((entry) => entry.resourceId),
      isNot(contains('sc_bob')),
    );
    expect(
      conversation
          .firstWhere((entry) => entry.resourceId == 'sc_world')
          .definitions
          .single
          .id,
      'war',
    );
  });

  test('loadOwnerRow prefers a legacy row and synthesizes a card row otherwise',
      () async {
    final cards = MemorySettingCardRepository();
    await cards.save(_card(
      // Real migration shape: card id is derived, legacy id survives separately.
      id: 'res_legacy_character_cards_legacy-alice',
      legacyId: 'legacy-alice',
      kind: SettingCardKind.character,
      name: '艾莉丝（卡片副本）',
      metadata: {
        'structured_payload': {
          'tracked_state_definitions': [_definitionJson('card_def', '卡片定义')],
        },
      },
    ));
    await cards.save(_card(
      id: 'sc_bob',
      kind: SettingCardKind.npc,
      name: '鲍勃',
      metadata: {
        'structured_payload': {
          'tracked_state_definitions': [_definitionJson('bob_def', '警觉')],
        },
      },
    ));

    final runtime = ProductionTrackedStateLibraryRuntime(
      repository: _FakeLibraryRepository(
        characters: [_legacyCharacterRow('legacy-alice', '艾莉丝', '2026-01-01')],
      ),
      cards: cards,
    );

    final legacy = await runtime.loadOwnerRow(
      type: ResourceType.character,
      resourceId: 'legacy-alice',
      mode: ResourceLibraryMode.adventure,
    );
    expect(legacy, isNotNull);
    expect(legacy!['name'], '艾莉丝');
    expect(legacy.containsKey('setting_card_id'), isFalse);

    final synthetic = await runtime.loadOwnerRow(
      type: ResourceType.npc,
      resourceId: 'sc_bob',
      mode: ResourceLibraryMode.adventure,
    );
    expect(synthetic, isNotNull);
    expect(synthetic!['setting_card_id'], 'sc_bob');
    expect(synthetic['name'], '鲍勃');
    final payload = jsonDecode(synthetic['json_data'] as String) as Map;
    final definitions = payload['tracked_state_definitions'] as List;
    expect((definitions.single as Map)['id'], 'bob_def');
    expect(payload.containsKey('custom_attributes'), isTrue);

    expect(
      await runtime.loadOwnerRow(
        type: ResourceType.worldview,
        resourceId: 'sc_bob',
        mode: ResourceLibraryMode.adventure,
      ),
      isNull,
    );
    expect(
      await runtime.loadOwnerRow(
        type: ResourceType.character,
        resourceId: 'missing',
        mode: ResourceLibraryMode.adventure,
      ),
      isNull,
    );
  });
}
