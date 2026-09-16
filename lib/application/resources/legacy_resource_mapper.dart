import 'dart:convert';

import '../../domain/resources/resource_contracts.dart';
import '../../services/character_card_storage_adapter.dart';
import '../../services/repositories/resource_tree_repository.dart';
import '../../utils/content_hasher.dart';

/// Legacy source tables the Phase 2 migration reads.
abstract final class LegacySourceTables {
  static const String worldviewPresets = 'worldview_presets';
  static const String characterCards = 'character_cards';
  static const String npcCards = 'npc_cards';

  static const List<String> all = [
    worldviewPresets,
    characterCards,
    npcCards,
  ];

  /// Every source table that carries legacy resource rows, in migration order.
  static bool isCardTable(String table) =>
      table == characterCards || table == npcCards;
}

/// Raised when a legacy row cannot be mapped into the content tree.
///
/// The legacy row is never modified or deleted: a mapping failure only produces
/// a diagnosable migration record.
class LegacyMappingException implements Exception {
  const LegacyMappingException(this.message);

  final String message;

  @override
  String toString() => 'LegacyMappingException: $message';
}

/// Deterministic, pure mapping from legacy resource rows to content-tree
/// drafts.
///
/// Rules frozen by Phase 2:
/// - Nothing is dropped: every non-empty legacy business field lands in a Part,
///   and anything unrecognised lands in the `其他资料` bucket.
/// - Body text only ever becomes Part content; runtime values that are not
///   prose (ids, tags, provenance, world-entry trigger config) become metadata.
/// - Runtime prose (`first_mes`, `system_prompt`, ...) has exactly one copy —
///   the Part — and metadata only stores a reference to that node, so no second
///   competing fact source exists.
/// - Empty fields never create an empty Section.
/// - Damaged JSON raises instead of being replaced by `{}`.
class LegacyResourceMapper {
  const LegacyResourceMapper();

  /// Bumped only when mapping semantics change: it is part of the migration
  /// audit key, so a new version re-evaluates every source row.
  static const int migrationVersion = 1;

  /// Section title for data whose legacy field name is not recognised.
  /// Part titles used for character prose, keyed by canonical field name.
  ///
  /// Public so the tree → legacy view projection reads the same titles this
  /// mapper writes instead of re-deriving them.
  static const Map<String, String> characterPartTitles = {
    'description': '概述',
    'personality': '性格',
    'appearance': '外貌',
    'bodyDescription': '身体描述',
    'scenario': '场景设定',
    'first_mes': '开场白',
    'mes_example': '对话示例',
    'system_prompt': '系统提示',
    'post_history_instructions': '历史后指令',
    'creator_notes': '作者备注',
    'ability': '能力',
    'weakness': '弱点',
    'equipment': '装备',
  };

  /// Section titles used for character content, in display order.
  static const Map<String, List<String>> characterSections = {
    '概述': ['description'],
    '人格': ['personality'],
    '外貌': ['appearance', 'bodyDescription'],
    '剧情': ['scenario', 'first_mes', 'mes_example'],
    '行为指令': ['system_prompt'],
    '能力': ['ability', 'weakness', 'equipment'],
    '其他创作资料': ['creator_notes', 'post_history_instructions'],
  };

  static const String characterProfileSectionTitle = '基本档案';
  static const String characterWorldSectionTitle = '世界关系';
  static const String characterAttributesSectionTitle = '自定义属性';
  static const String characterGreetingsSectionTitle = '备用开场';
  static const String worldviewEntriesSectionTitle = '世界书条目';

  /// Section title for data whose legacy field name is not recognised.
  static const String otherSectionTitle = '其他资料';

  /// Reverse lookup of [characterPartTitles], for the view projection.
  static String? characterFieldForPartTitle(String title) {
    for (final entry in characterPartTitles.entries) {
      if (entry.value == title) return entry.key;
    }
    return null;
  }

  /// Reverse lookup of [worldviewModuleTitles], for the view projection.
  static String? worldviewModuleForTitle(String title) {
    for (final entry in worldviewModuleTitles.entries) {
      if (entry.value == title) return entry.key;
    }
    return null;
  }

  /// Metadata keys produced by this mapper.
  static const String metadataLegacySourceTable = 'legacy_source_table';
  static const String metadataLegacySourceId = 'legacy_source_id';
  static const String metadataLegacySourceHash = 'legacy_source_hash';
  static const String metadataRuntimeNodeRefs = 'runtime_node_refs';
  static const String metadataWorldEntries = 'legacy_world_entries';
  static const String metadataCustomAttributes = 'legacy_custom_attributes';
  static const String metadataMatchingWorldviewId = 'matching_worldview_id';
  static const String metadataSource = 'source';
  static const String metadataMode = 'mode';
  static const String metadataCharacterVersion = 'character_version';
  static const String metadataCreator = 'creator';
  static const String metadataTags = 'tags';

  /// Metadata keys the legacy format uses for bookkeeping, not content.
  static const Set<String> _nonContentKeys = {
    'status',
    'format_version',
    'mode',
    'generation',
    'question_index',
    'total_questions',
    'part',
    'total_parts',
    'source_hash',
    'target_total_characters',
  };

  /// Character-card fields that belong to the runtime as discrete values.
  ///
  /// They still exist as Parts; metadata only stores the node reference so
  /// Phase 10 can build runtime from metadata without duplicating the text.
  static const Map<String, List<String>> _runtimeProseFields = {
    'description': ['description', 'background'],
    'personality': ['personality'],
    'scenario': ['scenario'],
    'first_mes': ['first_mes', 'firstMessage'],
    'mes_example': ['mes_example', 'exampleDialogues'],
    'system_prompt': ['system_prompt', 'systemPrompt'],
  };

  /// Prose fields grouped into semantic Sections, in display order.
  static const Map<String, List<String>> _proseSections = characterSections;

  /// Card-envelope bookkeeping that is not authored content, so a flat
  /// (non `data`-wrapped) card does not turn these into Parts.
  static const Set<String> _cardBookkeepingKeys = {
    'spec',
    'spec_version',
    'name',
    'data',
    'avatar',
    'create_date',
    'talkativeness',
    'fav',
  };

  /// Aliases for every field the mapper understands, so a field is never
  /// emitted twice under two spellings.
  static const Map<String, List<String>> _fieldAliases = {
    'name': ['name'],
    'description': ['description', 'background'],
    'personality': ['personality'],
    'appearance': ['appearance'],
    'bodyDescription': ['bodyDescription', 'body_description'],
    'scenario': ['scenario'],
    'first_mes': ['first_mes', 'firstMessage'],
    'mes_example': ['mes_example', 'exampleDialogues'],
    'system_prompt': ['system_prompt', 'systemPrompt'],
    'post_history_instructions': [
      'post_history_instructions',
      'postHistoryInstructions',
    ],
    'creator_notes': ['creator_notes', 'creatorNotes'],
    'alternate_greetings': ['alternate_greetings', 'alternateGreetings'],
    'ability': ['ability'],
    'weakness': ['weakness'],
    'equipment': ['equipment'],
    'tags': ['tags'],
    'creator': ['creator'],
    'character_version': ['character_version', 'characterVersion'],
    'gender': ['gender'],
    'age': ['age'],
    'profession': ['profession', 'occupation', 'role'],
    'custom_attributes': ['custom_attributes', 'customAttributes'],
    'world_profile': ['world_profile', 'worldProfile'],
    'import_source': ['import_source', 'importSource'],
  };

  /// Part titles for world-profile prose, keyed by canonical field name.
  /// Public so the view projection reads the same labels this mapper writes.
  static const Map<String, String> worldProfilePartTitles = {
    'faction': '阵营',
    'home_location': '故乡',
    'public_goal': '公开目标',
    'hidden_motivation': '隐秘动机',
    'secrets': '秘密',
    'ability_source': '能力来源',
    'ability_cost': '能力代价',
    'taboos': '禁忌',
    'relationship_notes': '关系备注',
  };

  static const Map<String, List<String>> _worldProfileAliases = {
    'faction': ['faction'],
    'home_location': ['home_location', 'homeLocation'],
    'public_goal': ['public_goal', 'publicGoal'],
    'hidden_motivation': ['hidden_motivation', 'hiddenMotivation'],
    'secrets': ['secrets'],
    'ability_source': ['ability_source', 'abilitySource'],
    'ability_cost': ['ability_cost', 'abilityCost'],
    'taboos': ['taboos'],
    'relationship_notes': ['relationship_notes', 'relationshipNotes'],
  };

  /// Module display order and titles for detailed worldviews.
  ///
  /// Order matches `WorldviewDetails.moduleKeys`; titles match the labels the
  /// resource library already shows for those modules.
  static const Map<String, String> worldviewModuleTitles = {
    'overview': '概览',
    'world_rules': '规则与边界',
    'world_state': '当前世界现状',
    'locations': '地点与地理',
    'factions': '势力与组织',
    'customs_and_life': '风俗与生活',
    'timeline': '历史与时间线',
    'glossary': '术语表',
    'creative_constraints': '创作约束',
  };

  /// Deterministic resource id for a legacy row.
  ///
  /// The deterministic id is what makes re-running the migration safe: a second
  /// insert fails on the primary key instead of producing a second tree.
  static ResourceId resourceIdFor(String sourceTable, String sourceId) =>
      ResourceId('res_legacy_${sourceTable}_$sourceId');

  /// Content hash of a legacy row, used for the migration audit.
  ///
  /// Only content-bearing columns participate, so unrelated bookkeeping writes
  /// do not mark a migrated resource as stale.
  static String sourceHash(String sourceTable, Map<String, Object?> row) {
    if (sourceTable == LegacySourceTables.worldviewPresets) {
      return ContentHasher.hash(<String, Object?>{
        'name': _text(row['name']),
        'description': _text(row['description']),
        'detail_json': _text(row['detail_json']),
        'entries_json': _text(row['entries_json']),
        'mode': _text(row['mode']),
        'authoring_method': _text(row['authoring_method']),
        'ai_generation_depth': _text(row['ai_generation_depth']),
      });
    }
    return ContentHasher.hash(<String, Object?>{
      'name': _text(row['name']),
      'json_data': _text(row['json_data']),
      'source': _text(row['source']),
      'matching_worldview_id': _text(row['matching_worldview_id']),
      'authoring_method': _text(row['authoring_method']),
      'ai_generation_depth': _text(row['ai_generation_depth']),
    });
  }

  // ─── Worldview ───

  /// Maps one `worldview_presets` row.
  ResourceTreeDraft mapWorldview(Map<String, Object?> row) {
    final sourceId = _text(row['id']);
    if (sourceId.isEmpty) {
      throw const LegacyMappingException('worldview 缺少 id');
    }
    final name = _text(row['name']);
    final description = _text(row['description']);
    final detail = _decodeObject(
      row['detail_json'],
      label: 'worldview.detail_json',
    );

    final sections = <ResourceTreeSectionDraft>[];
    final modules = detail['modules'];
    final handled = <String>{'modules', 'format_version', 'mode'};

    if (modules is Map) {
      for (final key in worldviewModuleTitles.keys) {
        if (!modules.containsKey(key)) continue;
        final section = _worldviewModuleSection(
          sourceId: sourceId,
          moduleKey: key,
          value: modules[key],
          sectionIndex: sections.length,
        );
        if (section != null) sections.add(section);
      }
    }

    // Anything the fixed module list does not recognise is preserved here
    // instead of being dropped.
    final leftovers = <String, Object?>{};
    if (modules is Map) {
      for (final entry in modules.entries) {
        final key = entry.key.toString();
        if (worldviewModuleTitles.containsKey(key)) continue;
        if (_hasVisibleText(entry.value)) {
          leftovers[key] = entry.value;
        }
      }
    }
    for (final entry in detail.entries) {
      if (handled.contains(entry.key.toString())) continue;
      if (_hasVisibleText(entry.value)) {
        leftovers[entry.key.toString()] = entry.value;
      }
    }
    if (leftovers.isNotEmpty) {
      final parts = <ResourceTreePartDraft>[];
      for (final entry in leftovers.entries) {
        _collectParts(
          value: entry.value,
          path: <String>[entry.key],
          parts: parts,
          sectionStatus: NodeStatus.draft,
        );
      }
      if (parts.isNotEmpty) {
        sections.add(ResourceTreeSectionDraft(
          title: otherSectionTitle,
          parts: parts,
        ));
      }
    }

    // Legacy world-book entries: body text becomes Parts, trigger config stays
    // machine-readable in metadata so runtime can still rebuild WorldEntry.
    final entries = _decodeArray(
      row['entries_json'],
      label: 'worldview.entries_json',
    );
    final entryRefs = <Map<String, Object?>>[];
    final entryParts = <ResourceTreePartDraft>[];
    for (var index = 0; index < entries.length; index++) {
      final entry = entries[index];
      if (entry is! Map) continue;
      final content = _text(entry['content']);
      if (content.isEmpty) continue;
      final keys = _stringList(entry['keys']);
      final title = keys.isEmpty ? '条目 ${index + 1}' : keys.join('、');
      entryParts.add(ResourceTreePartDraft(
        title: title,
        content: content,
        status: _nodeStatus(entry['status']) ?? NodeStatus.draft,
      ));
      final config = <String, Object?>{'index': index};
      for (final field in const [
        'keys',
        'insertion_order',
        'probability',
        'cooldown',
        'sticky',
        'use_regex',
        'insert_position',
        'recursive',
        'enabled',
      ]) {
        if (entry.containsKey(field)) config[field] = entry[field];
      }
      entryRefs.add(config);
    }
    if (entryParts.isNotEmpty) {
      sections.add(ResourceTreeSectionDraft(
        title: '世界书条目',
        parts: entryParts,
      ));
    }

    final metadata = <String, Object?>{
      metadataLegacySourceTable: LegacySourceTables.worldviewPresets,
      metadataLegacySourceId: sourceId,
      metadataMatchingWorldviewId: _text(row['matching_worldview_id']),
      metadataSource: _text(row['source']),
      metadataMode: _text(row['mode']),
    };
    if (entryRefs.isNotEmpty) metadata[metadataWorldEntries] = entryRefs;

    return ResourceTreeDraft(
      id: resourceIdFor(LegacySourceTables.worldviewPresets, sourceId),
      type: ResourceType.worldview,
      name: name.isEmpty ? sourceId : name,
      summary: description,
      metadata: _withProvenance(
        metadata: metadata,
        row: row,
        sourceTable: LegacySourceTables.worldviewPresets,
        sourceId: sourceId,
      ),
      sections: sections,
    );
  }

  ResourceTreeSectionDraft? _worldviewModuleSection({
    required String sourceId,
    required String moduleKey,
    required Object? value,
    required int sectionIndex,
  }) {
    if (!_hasVisibleText(value)) return null;
    final status =
        _nodeStatus(value is Map ? value['status'] : null) ?? NodeStatus.draft;
    final parts = <ResourceTreePartDraft>[];
    if (value is Map) {
      // `overview` uses `summary`; every other module uses `content`.
      final primary = _firstNonEmpty(value, const ['content', 'summary']);
      if (primary.isNotEmpty) {
        parts.add(ResourceTreePartDraft(
          title: worldviewModuleTitles[moduleKey]!,
          content: primary,
          status: status,
        ));
      }
      final items = value['items'];
      if (items is List) {
        for (var index = 0; index < items.length; index++) {
          final item = items[index];
          if (!_hasVisibleText(item)) continue;
          parts.add(ResourceTreePartDraft(
            title: _itemTitle(item, index),
            content: _joinVisibleTexts(item),
            status: status,
          ));
        }
      }
      for (final entry in value.entries) {
        final key = entry.key.toString();
        if (_nonContentKeys.contains(key) ||
            key == 'content' ||
            key == 'summary' ||
            key == 'items') {
          continue;
        }
        if (!_hasVisibleText(entry.value)) continue;
        _collectParts(
          value: entry.value,
          path: <String>[key],
          parts: parts,
          sectionStatus: status,
        );
      }
    } else {
      parts.add(ResourceTreePartDraft(
        title: worldviewModuleTitles[moduleKey]!,
        content: _joinVisibleTexts(value),
        status: status,
      ));
    }
    if (parts.isEmpty) return null;
    return ResourceTreeSectionDraft(
      title: worldviewModuleTitles[moduleKey]!,
      parts: parts,
    );
  }

  // ─── Character / NPC ───

  /// Maps one `character_cards` row.
  ResourceTreeDraft mapCharacter(Map<String, Object?> row) => _mapCard(
        row: row,
        sourceTable: LegacySourceTables.characterCards,
        type: ResourceType.character,
      );

  /// Maps one `npc_cards` row.
  ResourceTreeDraft mapNpc(Map<String, Object?> row) => _mapCard(
        row: row,
        sourceTable: LegacySourceTables.npcCards,
        type: ResourceType.npc,
      );

  ResourceTreeDraft _mapCard({
    required Map<String, Object?> row,
    required String sourceTable,
    required ResourceType type,
  }) {
    final sourceId = _text(row['id']);
    if (sourceId.isEmpty) {
      throw LegacyMappingException('$sourceTable 行缺少 id');
    }
    final decoded =
        _decodeObject(row['json_data'], label: '$sourceTable.json_data');
    // An empty payload is degenerate, not damaged: it still yields a resource
    // (with no sections) so the resource count never shrinks.
    final data = decoded.isEmpty
        ? const <String, Object?>{}
        : CharacterCardStorageAdapter.fromStored(decoded).data;

    final name = _firstNonEmpty(data, _fieldAliases['name']!);
    final header = <String, Object?>{};
    final consumed = <String>{
      ..._cardBookkeepingKeys,
      ..._fieldAliases['name']!
    };

    String take(List<String> aliases) {
      for (final alias in aliases) {
        consumed.add(alias);
        final value = data[alias];
        if (value is String && value.trim().isNotEmpty) return value.trim();
        if (value != null && value is! Map && value is! List) {
          return value.toString().trim();
        }
      }
      return '';
    }

    final description = take(_fieldAliases['description']!);
    final personality = take(_fieldAliases['personality']!);
    final appearance = take(_fieldAliases['appearance']!);
    final bodyDescription = take(_fieldAliases['bodyDescription']!);
    final scenario = take(_fieldAliases['scenario']!);
    final firstMessage = take(_fieldAliases['first_mes']!);
    final exampleDialogues = take(_fieldAliases['mes_example']!);
    final systemPrompt = take(_fieldAliases['system_prompt']!);
    final postHistory = take(_fieldAliases['post_history_instructions']!);
    final creatorNotes = take(_fieldAliases['creator_notes']!);
    final ability = take(_fieldAliases['ability']!);
    final weakness = take(_fieldAliases['weakness']!);
    final equipment = take(_fieldAliases['equipment']!);
    final gender = take(_fieldAliases['gender']!);
    final age = take(_fieldAliases['age']!);
    final profession = take(_fieldAliases['profession']!);
    final creator = take(_fieldAliases['creator']!);
    final characterVersion = take(_fieldAliases['character_version']!);
    final importSource = take(_fieldAliases['import_source']!);

    final alternateGreetings =
        _firstList(data, _fieldAliases['alternate_greetings']!);
    final tags = _firstList(data, _fieldAliases['tags']!);
    consumed.addAll(_fieldAliases['alternate_greetings']!);
    consumed.addAll(_fieldAliases['tags']!);

    final sections = <ResourceTreeSectionDraft>[];
    final runtimeRefs = <String, Object?>{};

    String partId(String role) =>
        'part_legacy_${sourceTable}_${sourceId}_$role';
    String sectionId(String role) =>
        'sec_legacy_${sourceTable}_${sourceId}_$role';

    final proseValues = <String, String>{
      'description': description,
      'personality': personality,
      'appearance': appearance,
      'bodyDescription': bodyDescription,
      'scenario': scenario,
      'first_mes': firstMessage,
      'mes_example': exampleDialogues,
      'system_prompt': systemPrompt,
      'post_history_instructions': postHistory,
      'creator_notes': creatorNotes,
      'ability': ability,
      'weakness': weakness,
      'equipment': equipment,
    };

    for (final group in _proseSections.entries) {
      final parts = <ResourceTreePartDraft>[];
      for (final field in group.value) {
        final value = proseValues[field] ?? '';
        if (value.isEmpty) continue;
        parts.add(ResourceTreePartDraft(
          title: _prosePartTitle(field),
          content: value,
          status: NodeStatus.confirmed,
          id: PartId(partId(field)),
        ));
      }
      if (parts.isNotEmpty) {
        sections.add(ResourceTreeSectionDraft(
          title: group.key,
          status: NodeStatus.confirmed,
          parts: parts,
          id: SectionId(sectionId('prose_${sections.length}')),
        ));
      }
    }

    // Gender / age / profession are short factual values, not long body text.
    final profileParts = <ResourceTreePartDraft>[];
    for (final entry in <String, String>{
      '性别': gender,
      '年龄': age,
      '职业': profession,
    }.entries) {
      if (entry.value.isEmpty) continue;
      profileParts.add(ResourceTreePartDraft(
        title: entry.key,
        content: entry.value,
        status: NodeStatus.confirmed,
      ));
    }
    if (profileParts.isNotEmpty) {
      sections.add(ResourceTreeSectionDraft(
        title: '基本档案',
        status: NodeStatus.confirmed,
        parts: profileParts,
      ));
    }

    // World-aware profile: prose into Parts, camel/snake aliases unified.
    final profile = _firstMap(data, _fieldAliases['world_profile']!);
    consumed.addAll(_fieldAliases['world_profile']!);
    if (profile.isNotEmpty) {
      final parts = <ResourceTreePartDraft>[];
      for (final entry in _worldProfileAliases.entries) {
        final label = worldProfilePartTitles[entry.key]!;
        final value = _firstNonEmpty(profile, entry.value);
        if (value.isNotEmpty) {
          parts.add(ResourceTreePartDraft(
            title: label,
            content: value,
            status: NodeStatus.confirmed,
          ));
        }
        consumed.addAll(entry.value);
      }
      if (parts.isNotEmpty) {
        sections.add(ResourceTreeSectionDraft(
          title: '世界关系',
          status: NodeStatus.confirmed,
          parts: parts,
        ));
      }
    }

    if (alternateGreetings.isNotEmpty) {
      final parts = <ResourceTreePartDraft>[];
      for (var index = 0; index < alternateGreetings.length; index++) {
        final value = alternateGreetings[index].trim();
        if (value.isEmpty) continue;
        parts.add(ResourceTreePartDraft(
          title: '备用问候 ${index + 1}',
          content: value,
          status: NodeStatus.confirmed,
        ));
      }
      if (parts.isNotEmpty) {
        sections.add(ResourceTreeSectionDraft(
          title: '备用开场',
          status: NodeStatus.confirmed,
          parts: parts,
        ));
      }
    }

    // Custom attributes keep their order and type; the value text lives only in
    // the Part, metadata only references it.
    final attributes = _firstRawList(data, _fieldAliases['custom_attributes']!);
    consumed.addAll(_fieldAliases['custom_attributes']!);
    final attributeRefs = <Map<String, Object?>>[];
    final attributeParts = <ResourceTreePartDraft>[];
    for (var index = 0; index < attributes.length; index++) {
      final attribute = attributes[index];
      if (attribute is! Map) continue;
      final attributeName =
          _firstNonEmpty(attribute, const ['name', 'key', 'title']);
      final attributeValue =
          _firstNonEmpty(attribute, const ['value', 'content', 'text']);
      if (attributeValue.isEmpty) continue;
      final title = attributeName.isEmpty ? '属性 ${index + 1}' : attributeName;
      final ref = <String, Object?>{'order': index, 'name': title};
      for (final field in const ['importance', 'type', 'category']) {
        if (attribute.containsKey(field)) ref[field] = attribute[field];
      }
      attributeParts.add(ResourceTreePartDraft(
        title: title,
        content: attributeValue,
        status: NodeStatus.confirmed,
        id: PartId(partId('attr_$index')),
      ));
      ref['part_id'] = partId('attr_$index');
      attributeRefs.add(ref);
    }
    if (attributeParts.isNotEmpty) {
      sections.add(ResourceTreeSectionDraft(
        title: '自定义属性',
        status: NodeStatus.confirmed,
        parts: attributeParts,
      ));
    }

    // Anything left over: preserved verbatim under the fallback section.
    final leftovers = <String, Object?>{};
    for (final entry in data.entries) {
      final key = entry.key.toString();
      if (consumed.contains(key)) continue;
      if (_nonContentKeys.contains(key)) continue;
      if (_cardBookkeepingKeys.contains(key)) continue;
      if (!_hasVisibleText(entry.value)) continue;
      leftovers[key] = entry.value;
    }
    if (leftovers.isNotEmpty) {
      final parts = <ResourceTreePartDraft>[];
      for (final entry in leftovers.entries) {
        _collectParts(
          value: entry.value,
          path: <String>[entry.key],
          parts: parts,
          sectionStatus: NodeStatus.confirmed,
        );
      }
      if (parts.isNotEmpty) {
        sections.add(ResourceTreeSectionDraft(
          title: otherSectionTitle,
          status: NodeStatus.confirmed,
          parts: parts,
        ));
      }
    }

    header[metadataRuntimeNodeRefs] = runtimeRefs;
    for (final entry in _runtimeProseFields.entries) {
      // The Part is the only copy of the text; metadata stores its node id.
      if ((proseValues[entry.key] ?? '').isNotEmpty) {
        runtimeRefs[entry.key] = partId(entry.key);
      }
    }
    if (attributeRefs.isNotEmpty) {
      header[metadataCustomAttributes] = attributeRefs;
    }
    if (tags.isNotEmpty) header[metadataTags] = tags;
    if (creator.isNotEmpty) header[metadataCreator] = creator;
    if (characterVersion.isNotEmpty) {
      header[metadataCharacterVersion] = characterVersion;
    }
    final rowSource = _text(row['source']);
    final sourceValue = importSource.isNotEmpty ? importSource : rowSource;
    if (sourceValue.isNotEmpty) header[metadataSource] = sourceValue;
    header[metadataMatchingWorldviewId] = _text(row['matching_worldview_id']);

    final metadata = <String, Object?>{};
    for (final entry in header.entries) {
      final value = entry.value;
      if (value is Map && value.isEmpty) continue;
      metadata[entry.key] = value;
    }

    return ResourceTreeDraft(
      id: resourceIdFor(sourceTable, sourceId),
      type: type,
      name: name.isNotEmpty ? name : _text(row['name']),
      summary: description,
      metadata: _withProvenance(
        metadata: metadata,
        row: row,
        sourceTable: sourceTable,
        sourceId: sourceId,
      ),
      sections: sections,
    );
  }

  // ─── Shared helpers ───

  Map<String, Object?> _withProvenance({
    required Map<String, Object?> metadata,
    required Map<String, Object?> row,
    required String sourceTable,
    required String sourceId,
  }) {
    final authoring = _text(row['authoring_method']);
    final depth = _text(row['ai_generation_depth']);
    return <String, Object?>{
      ...metadata,
      'authoring_method':
          authoring.isEmpty ? CreationMethod.manual.storageValue : authoring,
      if (depth.isNotEmpty) 'ai_generation_depth': depth,
      metadataLegacySourceHash: sourceHash(sourceTable, row),
    };
  }

  String _prosePartTitle(String field) => characterPartTitles[field] ?? field;

  /// Emits one Part for every non-empty leaf of [value], titling it with the
  /// field path so nothing becomes anonymous.
  void _collectParts({
    required Object? value,
    required List<String> path,
    required List<ResourceTreePartDraft> parts,
    required NodeStatus sectionStatus,
  }) {
    if (value is Map) {
      for (final entry in value.entries) {
        final key = entry.key.toString();
        if (_nonContentKeys.contains(key)) continue;
        _collectParts(
          value: entry.value,
          path: [...path, key],
          parts: parts,
          sectionStatus: sectionStatus,
        );
      }
      return;
    }
    if (value is List) {
      for (var index = 0; index < value.length; index++) {
        final item = value[index];
        final label = item is Map
            ? _firstNonEmpty(item, const ['name', 'title', 'label'])
            : '';
        _collectParts(
          value: item,
          path: [...path, label.isEmpty ? '${index + 1}' : label],
          parts: parts,
          sectionStatus: sectionStatus,
        );
      }
      return;
    }
    final text = _text(value);
    if (text.isEmpty) return;
    parts.add(ResourceTreePartDraft(
      title: path.where((segment) => segment.isNotEmpty).join(' / '),
      content: text,
      status: sectionStatus,
    ));
  }

  String _itemTitle(Object? item, int index) {
    if (item is Map) {
      final named = _firstNonEmpty(item, const ['name', 'title', 'label']);
      if (named.isNotEmpty) return named;
    }
    return '条目 ${index + 1}';
  }

  Object? _decodeJson(Object? raw, {required String label}) {
    if (raw == null) return null;
    if (raw is! String) return raw;
    final text = raw.trim();
    if (text.isEmpty) return null;
    try {
      return jsonDecode(text);
    } catch (error) {
      // Never fall back to {}: that would silently replace user content.
      throw LegacyMappingException('$label 不是有效 JSON：$error');
    }
  }

  Map<String, Object?> _decodeObject(Object? raw, {required String label}) {
    final decoded = _decodeJson(raw, label: label);
    if (decoded == null) return const <String, Object?>{};
    if (decoded is! Map) {
      throw LegacyMappingException('$label 必须是 JSON 对象');
    }
    return decoded
        .map((key, value) => MapEntry(key.toString(), value as Object?));
  }

  List<Object?> _decodeArray(Object? raw, {required String label}) {
    final decoded = _decodeJson(raw, label: label);
    if (decoded == null) return const <Object?>[];
    if (decoded is! List) {
      throw LegacyMappingException('$label 必须是 JSON 数组');
    }
    return decoded;
  }

  static String _text(Object? value) {
    if (value == null) return '';
    if (value is String) return value.trim();
    if (value is num || value is bool) return value.toString();
    return '';
  }

  String _firstNonEmpty(Map source, List<String> keys) {
    for (final key in keys) {
      final value = source[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
      if (value is List && value.isNotEmpty) {
        final joined =
            value.map(_text).where((item) => item.isNotEmpty).join('\n');
        if (joined.isNotEmpty) return joined;
      }
      if (value is num || value is bool) return value.toString();
    }
    return '';
  }

  List<String> _firstList(Map source, List<String> keys) {
    for (final key in keys) {
      final value = source[key];
      if (value is List) {
        return value
            .map(_text)
            .where((item) => item.isNotEmpty)
            .toList(growable: false);
      }
    }
    return const <String>[];
  }

  /// Returns the first list-valued key verbatim, preserving element structure.
  List<Object?> _firstRawList(Map source, List<String> keys) {
    for (final key in keys) {
      final value = source[key];
      if (value is List) return List<Object?>.from(value);
    }
    return const <Object?>[];
  }

  Map<String, Object?> _firstMap(Map source, List<String> keys) {
    for (final key in keys) {
      final value = source[key];
      if (value is Map) {
        final result = <String, Object?>{};
        for (final entry in value.entries) {
          result[entry.key.toString()] = entry.value as Object?;
        }
        return result;
      }
    }
    return const <String, Object?>{};
  }

  List<String> _stringList(Object? value) {
    if (value is List) {
      return value
          .map(_text)
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }
    final single = _text(value);
    return single.isEmpty ? const <String>[] : <String>[single];
  }

  static bool _hasVisibleText(Object? value) {
    if (value == null) return false;
    if (value is String) return value.trim().isNotEmpty;
    if (value is num || value is bool) return true;
    if (value is List) return value.any(_hasVisibleText);
    if (value is Map) {
      for (final entry in value.entries) {
        if (_nonContentKeys.contains(entry.key.toString())) continue;
        if (_hasVisibleText(entry.value)) return true;
      }
      return false;
    }
    return false;
  }

  /// Concatenates every visible text leaf in order, so no text is lost when a
  /// structured value becomes one Part.
  static String _joinVisibleTexts(Object? value) {
    final texts = <String>[];
    void visit(Object? node) {
      if (node == null) return;
      if (node is String) {
        final trimmed = node.trim();
        if (trimmed.isNotEmpty) texts.add(trimmed);
        return;
      }
      if (node is num || node is bool) {
        texts.add(node.toString());
        return;
      }
      if (node is List) {
        node.forEach(visit);
        return;
      }
      if (node is Map) {
        for (final entry in node.entries) {
          if (_nonContentKeys.contains(entry.key.toString())) continue;
          visit(entry.value);
        }
      }
    }

    visit(value);
    return texts.join('\n');
  }

  static NodeStatus? _nodeStatus(Object? raw) {
    final value = raw?.toString();
    for (final status in NodeStatus.values) {
      if (status.storageValue == value) return status;
    }
    return null;
  }
}
