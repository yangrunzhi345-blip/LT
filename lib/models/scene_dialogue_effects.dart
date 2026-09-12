import 'game_state.dart';

class SceneInventoryGrant {
  final String name;
  final String type;
  final String icon;
  final int quantity;
  final String? ownerCharacterId;
  final Map<String, dynamic> data;

  const SceneInventoryGrant({
    required this.name,
    required this.type,
    required this.icon,
    required this.quantity,
    required this.data,
    this.ownerCharacterId,
  });
}

/// Validated, side-effect-only portion of a scene response.
///
/// Parsing is deliberately fail-closed per field: malformed optional effects
/// are ignored and recorded in [diagnostics], while the narrative turn can
/// still be committed.
class SceneDialogueEffects {
  final int? level;
  final int? experience;
  final int? mp;
  final int? maxMp;
  final int? baseAtk;
  final int? baseDef;
  final int? baseSpeed;
  final int? skillPoints;
  final Map<String, int> affinityChanges;
  final Set<String> deadCharacters;
  final List<SceneInventoryGrant> itemsGained;
  final List<Map<String, dynamic>> enemies;
  final List<String> diagnostics;

  const SceneDialogueEffects({
    this.level,
    this.experience,
    this.mp,
    this.maxMp,
    this.baseAtk,
    this.baseDef,
    this.baseSpeed,
    this.skillPoints,
    this.affinityChanges = const {},
    this.deadCharacters = const {},
    this.itemsGained = const [],
    this.enemies = const [],
    this.diagnostics = const [],
  });

  bool get startsCombat => enemies.isNotEmpty;

  GameState applyState(GameState state) => state.copyWith(
        level: level,
        experience: experience,
        mp: mp,
        maxMp: maxMp,
        baseAtk: baseAtk,
        baseDef: baseDef,
        baseSpeed: baseSpeed,
        skillPoints: skillPoints,
      );

  SceneDialogueEffects withAffinityChanges(Map<String, int> changes) {
    if (changes.isEmpty) return this;
    final merged = Map<String, int>.from(affinityChanges);
    for (final entry in changes.entries) {
      merged.update(entry.key, (value) => value + entry.value,
          ifAbsent: () => entry.value);
    }
    return SceneDialogueEffects(
      level: level,
      experience: experience,
      mp: mp,
      maxMp: maxMp,
      baseAtk: baseAtk,
      baseDef: baseDef,
      baseSpeed: baseSpeed,
      skillPoints: skillPoints,
      affinityChanges: Map.unmodifiable(merged),
      deadCharacters: deadCharacters,
      itemsGained: itemsGained,
      enemies: enemies,
      diagnostics: diagnostics,
    );
  }

  factory SceneDialogueEffects.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const SceneDialogueEffects();
    final diagnostics = <String>[];

    int? integer(String key, {int min = 0, int max = 100000000}) {
      final raw = json[key];
      if (raw == null) return null;
      if (raw is! num || raw.isNaN || raw.isInfinite) {
        diagnostics.add('$key:type');
        return null;
      }
      final value = raw.toInt();
      if (value < min || value > max) {
        diagnostics.add('$key:range');
        return null;
      }
      return value;
    }

    final affinity = <String, int>{};
    final affinityRaw = json['affinity_change'];
    if (affinityRaw is Map) {
      for (final entry in affinityRaw.entries.take(50)) {
        final name = entry.key.toString().trim();
        final value = entry.value;
        if (name.isEmpty || name.length > 200 || value is! num) {
          diagnostics.add('affinity_change:item');
          continue;
        }
        final delta = value.toInt();
        if (delta < -100 || delta > 100) {
          diagnostics.add('affinity_change:$name:range');
          continue;
        }
        affinity[name] = delta;
      }
    } else if (affinityRaw != null) {
      diagnostics.add('affinity_change:type');
    }

    final dead = <String>{};
    final deadRaw = json['character_dead'];
    if (deadRaw is String && deadRaw.trim().isNotEmpty) {
      dead.add(deadRaw.trim());
    } else if (deadRaw is List) {
      dead.addAll(deadRaw
          .whereType<String>()
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty && value.length <= 200)
          .take(50));
    } else if (deadRaw != null) {
      diagnostics.add('character_dead:type');
    }

    const itemTypes = {'consumable', 'equipment', 'material', 'quest'};
    final items = <SceneInventoryGrant>[];
    final itemsRaw = json['items_gained'];
    final itemValues = itemsRaw is List
        ? itemsRaw
        : itemsRaw is Map
            ? [itemsRaw]
            : const [];
    if (itemsRaw != null && itemsRaw is! List && itemsRaw is! Map) {
      diagnostics.add('items_gained:type');
    }
    for (final raw in itemValues.take(50)) {
      if (raw is! Map) {
        diagnostics.add('items_gained:item');
        continue;
      }
      final item = Map<String, dynamic>.from(raw);
      final name = item['name']?.toString().trim() ?? '';
      final type = item['type']?.toString().trim() ?? 'consumable';
      final data = item['data'] is Map
          ? Map<String, dynamic>.from(item['data'] as Map)
          : <String, dynamic>{};
      final quantityRaw = data['quantity'];
      final quantity = quantityRaw is num ? quantityRaw.toInt() : 1;
      if (name.isEmpty ||
          name.length > 200 ||
          !itemTypes.contains(type) ||
          quantity < 1 ||
          quantity > 100000) {
        diagnostics.add('items_gained:item');
        continue;
      }
      final owner = item['owner']?.toString().trim();
      items.add(SceneInventoryGrant(
        name: name,
        type: type,
        icon: data['icon']?.toString().trim().isNotEmpty == true
            ? data['icon'].toString().trim()
            : '📦',
        quantity: quantity,
        data: data,
        ownerCharacterId: owner == null || owner.isEmpty ? null : owner,
      ));
    }

    final enemies = <Map<String, dynamic>>[];
    if (json['combat'] == true) {
      final rawEnemies = json['enemies'];
      if (rawEnemies is List) {
        for (final raw in rawEnemies.take(20)) {
          if (raw is Map) enemies.add(Map<String, dynamic>.from(raw));
        }
      }
      if (enemies.isEmpty) diagnostics.add('combat:enemies');
    }

    return SceneDialogueEffects(
      level: integer('level', min: 1, max: 100000),
      experience: integer('experience'),
      mp: integer('mp'),
      maxMp: integer('max_mp', min: 1),
      baseAtk: integer('base_atk'),
      baseDef: integer('base_def'),
      baseSpeed: integer('base_speed'),
      skillPoints: integer('skill_points'),
      affinityChanges: Map.unmodifiable(affinity),
      deadCharacters: Set.unmodifiable(dead),
      itemsGained: List.unmodifiable(items),
      enemies: List.unmodifiable(enemies),
      diagnostics: List.unmodifiable(diagnostics),
    );
  }
}
