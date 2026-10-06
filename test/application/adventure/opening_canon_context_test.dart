import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/adventure/opening_canon_context.dart';
import 'package:lt_dialogue/models/adventure_config.dart';

AdventureSelectedCharacter _character({
  required String id,
  required String name,
  bool isProtagonist = false,
  Map<String, dynamic>? card,
}) =>
    AdventureSelectedCharacter(
      id: id,
      characterId: id,
      characterName: name,
      isProtagonist: isProtagonist,
      narrativeRole: isProtagonist
          ? AdventureCharacterRole.protagonist
          : AdventureCharacterRole.supporting,
      characterCardJson: card,
    );

CanonEntity _find(OpeningCanonContext context, String name) =>
    context.entities.firstWhere((entity) => entity.name == name);

void main() {
  group('buildOpeningCanonContext', () {
    // CASE 1 — the reported regression: character A controls organization 洛恩,
    // and the card explicitly declares 洛恩 as an organization.
    test('keeps an organization an organization when A controls it', () {
      final config = AdventureConfig(
        selectedCharacters: [
          _character(
            id: 'A',
            name: 'A',
            isProtagonist: true,
            card: const {
              'name': 'A',
              'world_profile': {'faction': '洛恩'},
              'canonical_entities': [
                {
                  'name': '洛恩',
                  'type': 'organization',
                  'relation': 'A 是洛恩的实际掌控者',
                },
              ],
            },
          ),
        ],
      );

      final context = buildOpeningCanonContext(config);
      final loen = _find(context, '洛恩');
      expect(loen.type, CanonEntityType.organization);
      expect(loen.relation, contains('掌控者'));
      expect(_find(context, 'A').type, CanonEntityType.character);
    });

    // CASE 2 — a name that looks like a person's name must keep its declared
    // non-character type.
    test('does not treat person-like organization names as characters', () {
      final config = AdventureConfig(
        selectedCharacters: [
          _character(
            id: 'A',
            name: 'A',
            isProtagonist: true,
            card: const {
              'name': 'A',
              'canonical_entities': [
                {'name': '艾琳', 'type': 'organization'},
                {'name': '洛恩', 'type': 'organization'},
                {'name': '米娅', 'type': 'organization'},
              ],
            },
          ),
        ],
      );

      final context = buildOpeningCanonContext(config);
      for (final name in const ['艾琳', '洛恩', '米娅']) {
        expect(_find(context, name).type, CanonEntityType.organization,
            reason: '$name must stay an organization');
      }
    });

    // CASE 3 — A --controls--> 洛恩 organization must never become a
    // character endpoint during context conversion.
    test('relationship link with an explicit type does not drift to character',
        () {
      final config = AdventureConfig(
        selectedCharacters: [
          _character(
            id: 'A',
            name: 'A',
            isProtagonist: true,
            card: const {
              'name': 'A',
              'relationship_links': [
                {
                  'targetName': '洛恩',
                  'targetType': 'organization',
                  'relationType': 'controls',
                  'description': 'A 掌控洛恩组织',
                },
              ],
            },
          ),
        ],
      );

      final context = buildOpeningCanonContext(config);
      final loen = _find(context, '洛恩');
      expect(loen.type, CanonEntityType.organization);
      expect(
        context.entities
            .where((entity) => entity.name == '洛恩')
            .map((entity) => entity.type),
        isNot(contains(CanonEntityType.character)),
      );
    });

    // CASE 4 — a legacy card with no structured declarations still works and
    // simply contributes its own character identity.
    test('legacy card without canonical_entities still resolves', () {
      final config = AdventureConfig(
        selectedCharacters: [
          _character(
            id: 'p1',
            name: '莉安',
            isProtagonist: true,
            card: const {
              'name': '莉安',
              'profession': '游侠',
              'personality': '敏锐冷静',
            },
          ),
        ],
      );

      final context = buildOpeningCanonContext(config);
      expect(context.entities, hasLength(1));
      expect(context.entities.single.name, '莉安');
      expect(context.entities.single.type, CanonEntityType.character);
    });

    // CASE 5 — types already carried by world_profile / relationship_links are
    // extracted.
    test('extracts structured world_profile and relationship_links types', () {
      final config = AdventureConfig(
        selectedCharacters: [
          _character(
            id: 'A',
            name: 'A',
            isProtagonist: true,
            card: const {
              'name': 'A',
              // Nested `data` wrapper, as written by the v2 card model.
              'data': {
                'world_profile': {
                  'faction': '银月议会',
                  'home_location': '银月城',
                },
                'relationship_links': [
                  {'targetName': '暗影匕首', 'targetType': 'item'},
                ],
              },
            },
          ),
        ],
      );

      final context = buildOpeningCanonContext(config);
      expect(_find(context, '银月议会').type, CanonEntityType.organization);
      expect(_find(context, '银月城').type, CanonEntityType.location);
      expect(_find(context, '暗影匕首').type, CanonEntityType.item);
    });

    test('unrecognized declared types fall back to unknown, never character',
        () {
      final config = AdventureConfig(
        selectedCharacters: [
          _character(
            id: 'A',
            name: 'A',
            isProtagonist: true,
            card: const {
              'name': 'A',
              'canonical_entities': [
                {'name': '某种存在', 'type': '完全未知的类型'},
              ],
            },
          ),
        ],
      );

      final context = buildOpeningCanonContext(config);
      expect(_find(context, '某种存在').type, CanonEntityType.unknown);
    });

    test('placeholder faction values are not emitted as entities', () {
      final config = AdventureConfig(
        selectedCharacters: [
          _character(
            id: 'A',
            name: 'A',
            isProtagonist: true,
            card: const {
              'name': 'A',
              'world_profile': {'faction': '无'},
            },
          ),
        ],
      );

      final context = buildOpeningCanonContext(config);
      expect(context.entities.map((e) => e.name), isNot(contains('无')));
    });

    test('selected roster and NPC snapshots carry character / npc types', () {
      final config = AdventureConfig(
        selectedCharacters: [
          _character(id: 'p1', name: '莉安', isProtagonist: true),
          _character(id: 'c2', name: '凯尔'),
        ],
        npcSnapshots: [
          AdventureNpcSnapshot(
            assetId: 'npc_1',
            name: '老约克',
            npcJson: const {'name': '老约克', 'role': '酒馆老板'},
          ),
        ],
      );

      final context = buildOpeningCanonContext(config);
      expect(_find(context, '莉安').type, CanonEntityType.character);
      expect(_find(context, '凯尔').type, CanonEntityType.character);
      expect(_find(context, '老约克').type, CanonEntityType.npc);
    });
  });
}
