import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/legacy_resource_mapper.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository.dart';

/// Golden-fixture tests for the deterministic legacy → content-tree mapper.
///
/// The fixtures mirror the shapes the app really stores (detailed worldviews
/// with modules/items, chara_card_v2 envelopes, flat cards, NPC rows, damaged
/// payloads), rather than hand-simplified stubs.
void main() {
  const mapper = LegacyResourceMapper();

  String partText(ResourceTreeDraft draft) => draft.sections
      .expand((section) => section.parts)
      .map((part) => part.content)
      .join('\n');

  Iterable<String> partTitles(ResourceTreeDraft draft) => draft.sections
      .expand((section) => section.parts)
      .map((part) => part.title);

  group('worldview mapping', () {
    test('simple worldview keeps name, description and overview text', () {
      final description = '银月大陆是北境的学术重镇。' * 12;
      final draft = mapper.mapWorldview(<String, Object?>{
        'id': 'wv_simple',
        'name': '银月大陆',
        'description': description,
        'entries_json': '[]',
        'detail_json': jsonEncode(<String, Object?>{
          'format_version': 2,
          'mode': 'simple',
          'modules': <String, Object?>{
            'overview': <String, Object?>{
              'summary': description,
              'status': 'confirmed',
            },
          },
        }),
        'authoring_method': 'manual',
        'mode': 'adventure',
      });

      expect(draft.type, ResourceType.worldview);
      expect(draft.name, '银月大陆');
      expect(draft.summary, description);
      expect(draft.sections.map((s) => s.title), ['概览']);
      expect(draft.sections.single.parts.single.content, description);
      expect(
        draft.metadata[LegacyResourceMapper.metadataLegacySourceTable],
        LegacySourceTables.worldviewPresets,
      );
      expect(
        draft.metadata[LegacyResourceMapper.metadataLegacySourceId],
        'wv_simple',
      );
      expect(
        (draft.metadata[LegacyResourceMapper.metadataLegacySourceHash]
                as String)
            .isNotEmpty,
        isTrue,
      );
    });

    test('detailed worldview maps every module in display order', () {
      final modules = <String, Object?>{
        for (final key in LegacyResourceMapper.worldviewModuleTitles.keys)
          key: <String, Object?>{
            key == 'overview' ? 'summary' : 'content': '$key 正文内容',
            'status': 'confirmed',
          },
      };
      final draft = mapper.mapWorldview(<String, Object?>{
        'id': 'wv_detailed',
        'name': '详细世界观',
        'description': '描述',
        'entries_json': '[]',
        'detail_json': jsonEncode(<String, Object?>{
          'format_version': 2,
          'mode': 'detailed',
          'modules': modules,
        }),
      });

      expect(
        draft.sections.map((section) => section.title),
        LegacyResourceMapper.worldviewModuleTitles.values.toList(),
      );
      for (final entry in LegacyResourceMapper.worldviewModuleTitles.entries) {
        final section = draft.sections
            .firstWhere((candidate) => candidate.title == entry.value);
        expect(
          section.parts
              .any((part) => part.content.contains('${entry.key} 正文内容')),
          isTrue,
          reason: 'module ${entry.key} must keep its text',
        );
        expect(section.parts.first.status, NodeStatus.confirmed);
      }
    });

    test('module items become their own parts', () {
      final draft = mapper.mapWorldview(<String, Object?>{
        'id': 'wv_items',
        'name': 'W',
        'description': 'D',
        'entries_json': '[]',
        'detail_json': jsonEncode(<String, Object?>{
          'modules': <String, Object?>{
            'locations': <String, Object?>{
              'content': '总述',
              'status': 'confirmed',
              'items': <Object?>[
                {'name': '银月城', 'description': '学术重镇'},
                {'name': '白港', 'description': '贸易海港'},
              ],
            },
          },
        }),
      });

      final titles = draft.sections.single.parts.map((p) => p.title).toList();
      expect(titles, containsAll(['地点与地理', '银月城', '白港']));
      final silver =
          draft.sections.single.parts.firstWhere((part) => part.title == '银月城');
      expect(silver.content, contains('学术重镇'));
    });

    test('unknown modules and unknown top-level keys land in 其他资料', () {
      final draft = mapper.mapWorldview(<String, Object?>{
        'id': 'wv_unknown',
        'name': 'W',
        'description': 'D',
        'entries_json': '[]',
        'detail_json': jsonEncode(<String, Object?>{
          'modules': <String, Object?>{
            'overview': {'summary': '概览文本', 'status': 'confirmed'},
            'extra_lore': {'content': '未识别模块的正文'},
          },
          'legacy_notes': '未识别的顶层字段',
        }),
      });

      final other = draft.sections.firstWhere(
          (section) => section.title == LegacyResourceMapper.otherSectionTitle);
      final text = other.parts.map((part) => part.content).join('\n');
      expect(text, contains('未识别模块的正文'));
      expect(text, contains('未识别的顶层字段'));
    });

    test('world-book entries keep content in parts and config in metadata', () {
      final draft = mapper.mapWorldview(<String, Object?>{
        'id': 'wv_entries',
        'name': 'W',
        'description': 'D',
        'detail_json': '{"modules":{}}',
        'entries_json': jsonEncode(<Object?>[
          {
            'keys': ['银月城', '月城'],
            'content': '银月城是北境学术重镇。',
            'probability': 80,
            'sticky': 1,
            'insertion_order': 3,
            'enabled': true,
          },
        ]),
      });

      final section =
          draft.sections.firstWhere((candidate) => candidate.title == '世界书条目');
      expect(section.parts.single.title, '银月城、月城');
      expect(section.parts.single.content, '银月城是北境学术重镇。');

      final configs = draft.metadata[LegacyResourceMapper.metadataWorldEntries]
          as List<Object?>;
      expect(configs, hasLength(1));
      final config = configs.single as Map<String, Object?>;
      expect(config['probability'], 80);
      expect(config['sticky'], 1);
      expect(config['insertion_order'], 3);
      expect(config.containsKey('content'), isFalse);
    });

    test('empty modules do not create empty sections', () {
      final draft = mapper.mapWorldview(<String, Object?>{
        'id': 'wv_empty',
        'name': 'W',
        'description': '',
        'entries_json': '[]',
        'detail_json': jsonEncode(<String, Object?>{
          'modules': <String, Object?>{
            'overview': {'summary': '只有概览', 'status': 'confirmed'},
            'glossary': {'content': '   ', 'status': 'draft'},
            'timeline': <String, Object?>{},
          },
        }),
      });

      expect(draft.sections.map((section) => section.title), ['概览']);
    });

    test('damaged detail_json raises instead of becoming an empty object', () {
      expect(
        () => mapper.mapWorldview(<String, Object?>{
          'id': 'wv_broken',
          'name': 'W',
          'description': 'D',
          'detail_json': '{"modules": {"overview": ',
          'entries_json': '[]',
        }),
        throwsA(isA<LegacyMappingException>()),
      );
    });
  });

  group('character mapping', () {
    Map<String, Object?> cardRow(String id, Map<String, Object?> data) => {
          'id': id,
          'name': data['name'],
          'json_data': jsonEncode({
            'spec': 'chara_card_v2',
            'spec_version': '2.0',
            'data': data,
          }),
          'source': 'chub.ai',
          'matching_worldview_id': 'wv_123',
          'authoring_method': 'aiReference',
          'ai_generation_depth': 'detailed',
        };

    final richCard = <String, Object?>{
      'name': '艾莲娜',
      'description': '北境的学者。' * 20,
      'background': '北境的学者。' * 20,
      'personality': '冷静而好奇',
      'appearance': '银发',
      'bodyDescription': '纤细',
      'scenario': '在图书馆相遇',
      'first_mes': '「你也来找那本书？」',
      'mes_example': '{{user}}: 你好\n{{char}}: 嗯。',
      'system_prompt': '保持学者口吻',
      'post_history_instructions': '不要跳出角色',
      'creator_notes': '作者备注文本',
      'alternate_greetings': ['备用一', '备用二'],
      'tags': ['玄幻', '学院'],
      'creator': 'aurora',
      'character_version': '1.2',
      'gender': '女',
      'age': '24',
      'profession': '学者',
      'world_profile': {
        'faction': '银月学院',
        'home_location': '北境',
        'public_goal': '寻找禁书',
        'hidden_motivation': '为老师复仇',
        'secrets': ['她其实是继承人'],
        'ability_source': '源能',
        'ability_cost': '记忆',
        'taboos': ['不可说谎'],
        'relationship_notes': '与主角是旧识',
      },
      'custom_attributes': [
        {'name': '魔力', 'value': 'A 级', 'importance': 'high'},
        {'name': '弱点', 'value': '怕黑', 'importance': 'normal'},
      ],
      'unknown_field': '未识别但必须保留的字段内容',
    };

    test('chara_card_v2 fields map to semantic sections', () {
      final draft = mapper.mapCharacter(cardRow('card_1', richCard));

      expect(draft.type, ResourceType.character);
      expect(draft.name, '艾莲娜');
      final titles = draft.sections.map((section) => section.title).toList();
      expect(
        titles,
        containsAll([
          '概述',
          '人格',
          '外貌',
          '剧情',
          '行为指令',
          '基本档案',
          '世界关系',
          '备用开场',
          '自定义属性',
          LegacyResourceMapper.otherSectionTitle,
        ]),
      );
    });

    test('runtime prose keeps exactly one copy and metadata only references it',
        () {
      final draft = mapper.mapCharacter(cardRow('card_1', richCard));
      final refs = draft.metadata[LegacyResourceMapper.metadataRuntimeNodeRefs]
          as Map<String, Object?>;

      // The prompt text exists only in the Part...
      for (final field in const ['first_mes', 'system_prompt', 'personality']) {
        final partId = refs[field] as String?;
        expect(partId, isNotNull, reason: '$field must have a node reference');
        final owning = draft.sections
            .expand((section) => section.parts)
            .where((part) => part.id?.value == partId);
        expect(owning, hasLength(1),
            reason: '$field must map to exactly one Part');
      }

      // ...and never as prose inside metadata.
      final metadataJson = jsonEncode(draft.metadata);
      expect(metadataJson.contains('你也来找那本书'), isFalse);
      expect(metadataJson.contains('保持学者口吻'), isFalse);
    });

    test('aliases do not duplicate content', () {
      final draft = mapper.mapCharacter(cardRow('card_2', richCard));
      final descriptionParts = draft.sections
          .expand((section) => section.parts)
          .where((part) => part.title == '概述');
      expect(descriptionParts, hasLength(1));
    });

    test('custom attributes keep order and importance next to their node', () {
      final draft = mapper.mapCharacter(cardRow('card_3', richCard));
      final section =
          draft.sections.firstWhere((candidate) => candidate.title == '自定义属性');
      expect(section.parts.map((part) => part.title), ['魔力', '弱点']);

      final refs = draft.metadata[LegacyResourceMapper.metadataCustomAttributes]
          as List<Object?>;
      expect(refs, hasLength(2));
      final first = refs.first as Map<String, Object?>;
      expect(first['order'], 0);
      expect(first['importance'], 'high');
      expect(first['part_id'], section.parts.first.id!.value);
      // The attribute value is not duplicated into metadata.
      expect(jsonEncode(refs).contains('A 级'), isFalse);
    });

    test('provenance, source and matching worldview are preserved', () {
      final draft = mapper.mapCharacter(cardRow('card_4', richCard));
      expect(
        draft.metadata[LegacyResourceMapper.metadataMatchingWorldviewId],
        'wv_123',
      );
      expect(draft.metadata['authoring_method'], 'aiReference');
      expect(draft.metadata['ai_generation_depth'], 'detailed');
      expect(draft.metadata[LegacyResourceMapper.metadataSource], 'chub.ai');
      expect(draft.metadata[LegacyResourceMapper.metadataCreator], 'aurora');
      expect(draft.metadata[LegacyResourceMapper.metadataTags], ['玄幻', '学院']);
    });

    test('unknown fields are preserved in the fallback section', () {
      final draft = mapper.mapCharacter(cardRow('card_5', richCard));
      final other = draft.sections.firstWhere(
        (section) => section.title == LegacyResourceMapper.otherSectionTitle,
      );
      expect(
        other.parts.any((part) => part.content == '未识别但必须保留的字段内容'),
        isTrue,
      );
    });

    test('flat (non data-wrapped) cards are supported', () {
      final draft = mapper.mapCharacter(<String, Object?>{
        'id': 'card_flat',
        'name': '扁平角色',
        'json_data': jsonEncode(<String, Object?>{
          'name': '扁平角色',
          'description': '扁平卡描述文本',
          'personality': '直率',
          'first_mes': '你好',
          'spec': 'chara_card_v2',
        }),
        'matching_worldview_id': '',
      });

      expect(draft.name, '扁平角色');
      final text = partText(draft);
      expect(text, contains('扁平卡描述文本'));
      expect(text, contains('直率'));
      expect(text, contains('你好'));
      // Envelope bookkeeping must not become content.
      expect(text.contains('chara_card_v2'), isFalse);
      expect(partTitles(draft), isNot(contains('spec')));
    });

    test('damaged json_data raises and empty json_data still yields a resource',
        () {
      expect(
        () => mapper.mapCharacter(<String, Object?>{
          'id': 'card_broken',
          'name': '坏卡',
          'json_data': '{"name": "坏卡"',
        }),
        throwsA(isA<LegacyMappingException>()),
      );

      final empty = mapper.mapCharacter(<String, Object?>{
        'id': 'card_empty',
        'name': '空卡',
        'json_data': '{}',
      });
      expect(empty.name, '空卡');
      expect(empty.sections, isEmpty);
    });

    test('NPC rows map with the npc resource type', () {
      final draft = mapper.mapNpc(<String, Object?>{
        'id': 'npc_1',
        'name': '酒馆老板',
        'json_data': jsonEncode(<String, Object?>{
          'name': '酒馆老板',
          'description': '健谈的中年人',
          'personality': '热情',
        }),
        'source': '场景生成',
        'matching_worldview_id': 'wv_123',
      });

      expect(draft.type, ResourceType.npc);
      expect(draft.name, '酒馆老板');
      expect(partText(draft), contains('健谈的中年人'));
      expect(
        draft.metadata[LegacyResourceMapper.metadataMatchingWorldviewId],
        'wv_123',
      );
    });

    test('every non-empty body field is represented in the tree', () {
      final draft = mapper.mapCharacter(cardRow('card_6', richCard));
      final text = partText(draft).replaceAll(RegExp(r'\s+'), '');
      final bodyValues = <String>[
        richCard['description'] as String,
        richCard['personality'] as String,
        richCard['appearance'] as String,
        richCard['bodyDescription'] as String,
        richCard['scenario'] as String,
        richCard['first_mes'] as String,
        richCard['mes_example'] as String,
        richCard['system_prompt'] as String,
        richCard['post_history_instructions'] as String,
        richCard['creator_notes'] as String,
        ...(richCard['alternate_greetings'] as List).cast<String>(),
        ...(richCard['world_profile'] as Map).values.expand(
              (value) => value is List
                  ? value.cast<String>()
                  : <String>[value as String],
            ),
        ...(richCard['custom_attributes'] as List)
            .map((attribute) => (attribute as Map)['value'] as String),
        richCard['unknown_field'] as String,
      ];

      for (final value in bodyValues) {
        expect(
          text.contains(value.replaceAll(RegExp(r'\s+'), '')),
          isTrue,
          reason: 'body value lost during mapping: $value',
        );
      }
    });
  });

  group('determinism', () {
    test('mapping the same row twice yields identical ids and content', () {
      final row = <String, Object?>{
        'id': 'wv_stable',
        'name': 'W',
        'description': 'D',
        'entries_json': '[]',
        'detail_json':
            '{"modules":{"overview":{"summary":"文本","status":"confirmed"}}}',
      };
      final first = mapper.mapWorldview(row);
      final second = mapper.mapWorldview(row);

      expect(first.id, second.id);
      expect(
        jsonEncode(first.sections
            .map((section) => {
                  'id': section.id?.value,
                  'parts': section.parts
                      .map((part) => {'id': part.id?.value, 'c': part.content})
                      .toList(),
                })
            .toList()),
        jsonEncode(second.sections
            .map((section) => {
                  'id': section.id?.value,
                  'parts': section.parts
                      .map((part) => {'id': part.id?.value, 'c': part.content})
                      .toList(),
                })
            .toList()),
      );
    });

    test('source hash follows content and ignores nothing relevant', () {
      final base = <String, Object?>{
        'id': 'wv_hash',
        'name': 'W',
        'description': 'D',
        'entries_json': '[]',
        'detail_json': '{"modules":{}}',
      };
      final changed = Map<String, Object?>.from(base)..['description'] = 'D2';

      expect(
        LegacyResourceMapper.sourceHash(
            LegacySourceTables.worldviewPresets, base),
        LegacyResourceMapper.sourceHash(
            LegacySourceTables.worldviewPresets, base),
      );
      expect(
        LegacyResourceMapper.sourceHash(
            LegacySourceTables.worldviewPresets, base),
        isNot(LegacyResourceMapper.sourceHash(
            LegacySourceTables.worldviewPresets, changed)),
      );
    });

    test('resource id is deterministic per source row', () {
      expect(
        LegacyResourceMapper.resourceIdFor(
            LegacySourceTables.characterCards, 'card_1'),
        LegacyResourceMapper.resourceIdFor(
            LegacySourceTables.characterCards, 'card_1'),
      );
      expect(
        LegacyResourceMapper.resourceIdFor(
            LegacySourceTables.characterCards, 'card_1'),
        isNot(LegacyResourceMapper.resourceIdFor(
            LegacySourceTables.npcCards, 'card_1')),
      );
    });
  });
}
