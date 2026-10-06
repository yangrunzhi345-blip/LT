import '../../models/adventure_config.dart';

/// Canonical entity types carried into the opening-generation context.
///
/// The opening prologue must never re-interpret an entity whose type is
/// already fixed by the worldview / character card / roster. When a card names
/// an organization, the model must keep writing it as an organization even if
/// the name looks like a person's name.
///
/// [unknown] is deliberately the fallback: an unclassified entity is safer
/// than a wrong classification, and the opening prompt binds entity type to
/// this explicit declaration only.
enum CanonEntityType {
  character('character'),
  npc('npc'),
  organization('organization'),
  faction('faction'),
  location('location'),
  item('item'),
  species('species'),
  ability('ability'),
  concept('concept'),
  unknown('unknown');

  const CanonEntityType(this.wire);

  /// Stable machine value exchanged with the LLM and read back from explicit
  /// `canonical_entities` declarations.
  final String wire;

  /// Accepts the machine value plus the common Chinese labels a card author or
  /// an explicit declaration may use. This maps an already-declared type to
  /// the enum; it never infers a type from a name or free text.
  static const Map<String, CanonEntityType> _aliases = {
    'character': character,
    '角色': character,
    '人物': character,
    'npc': npc,
    'npc角色': npc,
    'organization': organization,
    'organisation': organization,
    '组织': organization,
    '机构': organization,
    'faction': faction,
    '势力': faction,
    '阵营': faction,
    'location': location,
    '地点': location,
    '场所': location,
    '区域': location,
    'item': item,
    '物品': item,
    '道具': item,
    'species': species,
    '种族': species,
    '物种': species,
    'ability': ability,
    '能力': ability,
    '技能': ability,
    'concept': concept,
    '概念': concept,
    'unknown': unknown,
    '未知': unknown,
  };

  static CanonEntityType fromWire(Object? value) {
    final key = (value ?? '').toString().trim().toLowerCase();
    if (key.isEmpty) return unknown;
    return _aliases[key] ?? unknown;
  }
}

/// One entity with a Canon-fixed type, as seen by the opening generator.
class CanonEntity {
  const CanonEntity({
    required this.name,
    required this.type,
    this.source = '',
    this.relation = '',
  });

  final String name;
  final CanonEntityType type;

  /// Where the declaration came from, so the model can weigh it (e.g.
  /// `角色「A」的角色卡`). Never a raw schema path.
  final String source;

  /// Relationship to the declaring character, when the card states one.
  final String relation;

  Map<String, String> toContextMap() => {
        'name': name,
        'type': type.wire,
        if (source.isNotEmpty) 'source': source,
        if (relation.isNotEmpty) 'relation': relation,
      };
}

/// The immutable entity identity context handed to opening generation.
///
/// It is derived only from data the current wizard selection already owns, so
/// it never bypasses the assembly / readiness authority and never reads live
/// library rows the user did not pick.
class OpeningCanonContext {
  const OpeningCanonContext({this.entities = const []});

  final List<CanonEntity> entities;

  bool get isEmpty => entities.isEmpty;

  /// Wire representation consumed by [AdventureAiController.generateOpening].
  List<Map<String, String>> toContextMaps() =>
      entities.map((entity) => entity.toContextMap()).toList(growable: false);
}

/// Derives the Canon entity list from the current assembly selection.
///
/// Extraction priority (highest confidence first); a name is registered once,
/// so an earlier, more explicit declaration always wins:
///
/// 1. Explicit structured `canonical_entities` on a selected character card.
/// 2. The selected roster itself (all characters) and the NPC snapshots.
/// 3. Structured `world_profile.faction` / `world_profile.home_location`.
///
/// Free text (`description`, `relationship_notes`, `personality`, ...) is
/// deliberately not parsed into types — deriving a type from prose would be a
/// low-confidence guess. Those fields still reach the model through the
/// character context; only typed entity identity comes from this builder.
OpeningCanonContext buildOpeningCanonContext(AdventureConfig config) {
  final entities = <CanonEntity>[];
  final seenNames = <String>{};

  void add(
    Object? rawName,
    CanonEntityType type, {
    String source = '',
    String relation = '',
  }) {
    final name = (rawName ?? '').toString().trim();
    if (name.isEmpty || _isPlaceholderName(name)) return;
    if (!seenNames.add(name)) return;
    entities.add(
      CanonEntity(name: name, type: type, source: source, relation: relation),
    );
  }

  // 1. Explicit structured declarations on each selected character card.
  for (final character in config.selectedCharacters) {
    final data = _cardData(character.characterCardJson);
    final declared = data['canonical_entities'] ?? data['canonicalEntities'];
    if (declared is List) {
      for (final raw in declared) {
        if (raw is! Map) continue;
        add(
          raw['name'],
          CanonEntityType.fromWire(raw['type'] ?? raw['entity_type']),
          source: '角色「${character.characterName}」的角色卡',
          relation:
              (raw['relation'] ?? raw['relationship'] ?? '').toString().trim(),
        );
      }
    }
    // A relationship link only contributes a type when it declares one
    // explicitly; a link without a type field is never guessed.
    final links = data['relationship_links'] ?? data['relationshipLinks'];
    if (links is List) {
      for (final raw in links) {
        if (raw is! Map) continue;
        final rawType = raw['targetType'] ??
            raw['target_type'] ??
            raw['entityType'] ??
            raw['entity_type'] ??
            raw['type'];
        if (rawType == null) continue;
        add(
          raw['targetName'] ?? raw['target_name'] ?? raw['name'],
          CanonEntityType.fromWire(rawType),
          source: '角色「${character.characterName}」的关系链接',
          relation: (raw['relationType'] ??
                  raw['relation_type'] ??
                  raw['description'] ??
                  '')
              .toString()
              .trim(),
        );
      }
    }
  }

  // 2. The selected roster and NPC assets carry a definitive identity type.
  for (final character in config.selectedCharacters) {
    add(
      character.characterName,
      CanonEntityType.character,
      source: '已选角色卡',
      relation: character.isProtagonist ? '主角' : character.effectiveRole,
    );
  }
  for (final npc in config.npcSnapshots) {
    final json = npc.npcJson;
    add(
      npc.name.isNotEmpty ? npc.name : json['name'],
      CanonEntityType.npc,
      source: 'NPC 资源',
      relation: (json['role'] ?? json['profession'] ?? json['occupation'] ?? '')
          .toString()
          .trim(),
    );
  }

  // 3. Structured world-profile fields that name a non-character entity.
  for (final character in config.selectedCharacters) {
    final data = _cardData(character.characterCardJson);
    final profile = data['world_profile'] ?? data['worldProfile'];
    if (profile is! Map) continue;
    add(
      profile['faction'],
      CanonEntityType.organization,
      source: '角色「${character.characterName}」的阵营',
      relation: '角色「${character.characterName}」的阵营 / 势力归属',
    );
    add(
      profile['home_location'],
      CanonEntityType.location,
      source: '角色「${character.characterName}」的故乡',
      relation: '角色「${character.characterName}」的故乡',
    );
  }

  return OpeningCanonContext(entities: List.unmodifiable(entities));
}

/// Expands the `data` wrapper a SillyTavern / v2 card may carry, tolerating
/// legacy flat shapes. Mirrors the unwrap used by the resource-card reader so
/// the same persisted card yields the same fields everywhere.
Map<String, dynamic> _cardData(Map<String, dynamic>? raw) {
  if (raw == null) return const <String, dynamic>{};
  final nested = raw['data'];
  return nested is Map ? Map<String, dynamic>.from(nested) : raw;
}

/// Values that name "no entity" rather than an entity.
const Set<String> _placeholderNames = {
  '无',
  '无组织',
  '无阵营',
  '未知',
  'none',
  'null',
  'n/a',
  'na',
  'unknown',
  '-',
  '--',
  '—',
};

bool _isPlaceholderName(String name) =>
    _placeholderNames.contains(name.toLowerCase());
