import 'dart:convert';

import '../../domain/resources/resource_contracts.dart';
import 'legacy_resource_mapper.dart';

/// Projects a unified content tree back into the legacy row shapes the existing
/// consumers still read.
///
/// Phase 3 writes new resources only into the tree, but Adventure assembly and
/// the resource library still consume `worldview_presets` / `character_cards` /
/// `npc_cards` shaped maps until Phase 10 / Phase 11 take over. This read-only
/// projection is the bridge; it never writes anything and never touches the
/// legacy tables.
///
/// Scope: it is used for resources that exist *only* in the tree (created
/// through the Phase 3 pipeline). Resources that also have a legacy row keep
/// returning that row unchanged, so existing data behaves exactly as before.
final class ResourceAdventureView {
  const ResourceAdventureView(this.tree);

  final ResourceTree tree;

  /// The legacy row for whichever table [type] belongs to.
  Map<String, Object?> toLegacyRow({
    required ResourceType type,
    required String mode,
    String updatedAt = '',
    String createdAt = '',
  }) {
    return switch (type) {
      ResourceType.worldview => toWorldviewRow(
          mode: mode,
          updatedAt: updatedAt,
          createdAt: createdAt,
        ),
      ResourceType.character || ResourceType.npc => toCardRow(
          mode: mode,
          updatedAt: updatedAt,
          createdAt: createdAt,
        ),
    };
  }

  /// `worldview_presets` row shape.
  Map<String, Object?> toWorldviewRow({
    required String mode,
    String updatedAt = '',
    String createdAt = '',
  }) {
    final modules = <String, Object?>{};
    final entries = <Object?>[];

    for (final section in tree.orderedSections) {
      final text = _sectionText(section);
      if (text.isEmpty) continue;
      final moduleKey =
          LegacyResourceMapper.worldviewModuleForTitle(section.title);
      if (section.title == LegacyResourceMapper.worldviewEntriesSectionTitle) {
        for (final part in tree.orderedPartsOf(section.id)) {
          if (part.content.trim().isEmpty) continue;
          entries.add(<String, Object?>{
            'keys': part.title
                .split('、')
                .map((key) => key.trim())
                .where((key) => key.isNotEmpty)
                .toList(),
            'content': part.content,
            'insertion_order': entries.length,
            'enabled': 1,
          });
        }
        continue;
      }
      if (moduleKey == null) {
        // Unknown sections are preserved as world entries rather than dropped.
        entries.add(<String, Object?>{
          'keys': <String>[section.title],
          'content': text,
          'insertion_order': entries.length,
          'enabled': 1,
        });
        continue;
      }
      modules[moduleKey] = <String, Object?>{
        moduleKey == 'overview' ? 'summary' : 'content': text,
        'status': section.status.storageValue,
      };
    }

    return <String, Object?>{
      'id': tree.resource.id.value,
      'name': tree.resource.name,
      'description': tree.resource.summary,
      'entries_json': jsonEncode(entries),
      'detail_json': jsonEncode(<String, Object?>{
        'format_version': 2,
        'mode': 'detailed',
        'modules': modules,
      }),
      'mode': mode,
      'authoring_method': _metadataString('authoring_method', 'manual'),
      'ai_generation_depth': _metadataString('ai_generation_depth', ''),
      'source': _metadataString('source', ''),
      'matching_worldview_id': _metadataString('matching_worldview_id', ''),
      'content_hash': '',
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  /// `character_cards` / `npc_cards` row shape.
  Map<String, Object?> toCardRow({
    required String mode,
    String updatedAt = '',
    String createdAt = '',
  }) {
    final data = <String, Object?>{};
    final profile = <String, Object?>{};
    final attributes = <Object?>[];
    final greetings = <Object?>[];
    final extras = <String, Object?>{};

    for (final section in tree.orderedSections) {
      final parts = tree.orderedPartsOf(section.id);
      if (section.title ==
          LegacyResourceMapper.characterAttributesSectionTitle) {
        for (final part in parts) {
          if (part.content.trim().isEmpty) continue;
          attributes.add(<String, Object?>{
            'name': part.title,
            'value': part.content,
          });
        }
        continue;
      }
      if (section.title ==
          LegacyResourceMapper.characterGreetingsSectionTitle) {
        for (final part in parts) {
          if (part.content.trim().isNotEmpty) greetings.add(part.content);
        }
        continue;
      }
      if (section.title == LegacyResourceMapper.characterProfileSectionTitle) {
        for (final part in parts) {
          switch (part.title) {
            case '性别':
              data['gender'] = part.content;
            case '年龄':
              data['age'] = part.content;
            case '职业':
              data['profession'] = part.content;
            default:
              if (part.content.trim().isNotEmpty) {
                extras[part.title] = part.content;
              }
          }
        }
        continue;
      }
      if (section.title == LegacyResourceMapper.characterWorldSectionTitle) {
        for (final part in parts) {
          final key = _worldProfileKeyFor(part.title);
          if (key == null) {
            if (part.content.trim().isNotEmpty) {
              extras[part.title] = part.content;
            }
            continue;
          }
          profile[key] = part.content;
        }
        continue;
      }
      for (final part in parts) {
        final field =
            LegacyResourceMapper.characterFieldForPartTitle(part.title);
        if (field == null) {
          // Unknown parts keep their title so nothing is dropped.
          if (part.content.trim().isNotEmpty) extras[part.title] = part.content;
          continue;
        }
        data[field] = part.content;
      }
    }

    if (profile.isNotEmpty) data['world_profile'] = profile;
    if (attributes.isNotEmpty) data['custom_attributes'] = attributes;
    if (greetings.isNotEmpty) data['alternate_greetings'] = greetings;
    if (extras.isNotEmpty) data['legacy_extra_fields'] = extras;
    data['name'] = tree.resource.name;
    if (tree.resource.summary.trim().isNotEmpty &&
        !data.containsKey('description')) {
      data['description'] = tree.resource.summary;
    }
    // Mirror the flat alias the card model writes, so consumers that read
    // `background` keep working.
    if (data.containsKey('description') && !data.containsKey('background')) {
      data['background'] = data['description'];
    }

    return <String, Object?>{
      'id': tree.resource.id.value,
      'name': tree.resource.name,
      'json_data': jsonEncode(<String, Object?>{
        'spec': 'chara_card_v2',
        'spec_version': '2.0',
        'data': data,
      }),
      'source': _metadataString('source', ''),
      'matching_worldview_id': _metadataString('matching_worldview_id', ''),
      'mode': mode,
      'weight': '',
      'authoring_method': _metadataString('authoring_method', 'manual'),
      'ai_generation_depth': _metadataString('ai_generation_depth', ''),
      'content_hash': '',
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  String _sectionText(ResourceSection section) => tree
      .orderedPartsOf(section.id)
      .map((part) => part.content.trim())
      .where((text) => text.isNotEmpty)
      .join('\n');

  String _metadataString(String key, String fallback) {
    final value = tree.resource.metadata[key];
    if (value == null) return fallback;
    final text = value.toString();
    return text.isEmpty ? fallback : text;
  }

  String? _worldProfileKeyFor(String partTitle) {
    for (final entry in LegacyResourceMapper.worldProfilePartTitles.entries) {
      if (entry.value == partTitle) return entry.key;
    }
    return null;
  }
}
