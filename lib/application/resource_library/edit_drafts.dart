import 'dart:convert';

import '../../models/worldview_details.dart';
import '../../services/character_card_storage_adapter.dart';
import '../../utils/structured_json_codec.dart';

/// 世界观手动编辑草稿：集中表单字段、默认值与存储 JSON 的解析/构造，
/// 页面只采集输入与展示错误。
class WorldviewEditDraft {
  String? id;
  String name;
  String description;
  WorldviewEditingMode mode;

  /// 详细模式的模块文本（不含 overview，overview 由 [description] 承担）。
  final Map<String, String> moduleTexts;
  String source;
  String entriesJson;

  WorldviewEditDraft({
    this.id,
    this.name = '',
    this.description = '',
    this.mode = WorldviewEditingMode.simple,
    Map<String, String>? moduleTexts,
    this.source = '',
    this.entriesJson = '[]',
  }) : moduleTexts = moduleTexts ?? <String, String>{};

  /// 从资料库行构造草稿；[editingMode] 仅用于新建时的默认模式。
  factory WorldviewEditDraft.fromExisting(Map<String, dynamic>? existing,
      {WorldviewEditingMode editingMode = WorldviewEditingMode.simple}) {
    final details = WorldviewDetails.fromJson(
      decodeDetailJson(existing?['detail_json']),
      fallbackDescription: existing?['description'] as String? ?? '',
    );
    return WorldviewEditDraft(
      id: existing?['id'] as String?,
      name: existing?['name'] as String? ?? '',
      description: existing?['description'] as String? ?? '',
      mode: existing == null ? editingMode : details.mode,
      moduleTexts: <String, String>{
        for (final key
            in WorldviewDetails.moduleKeys.where((key) => key != 'overview'))
          key: _moduleText(details.modules[key]),
      },
      source: existing?['source'] as String? ?? '',
      entriesJson: existing?['entries_json'] as String? ?? '[]',
    );
  }

  /// 构造保存用的详细设定负载（overview 取描述，其余模块取表单文本）。
  WorldviewDetails toDetails() => WorldviewDetails(
        mode: mode,
        modules: <String, dynamic>{
          'overview': <String, dynamic>{
            'summary': description.trim(),
            'status': WorldviewFactStatus.confirmed.name,
          },
          for (final entry in moduleTexts.entries)
            entry.key: <String, dynamic>{
              'content': entry.value.trim(),
              'status': WorldviewFactStatus.confirmed.name,
            },
        },
      );

  /// 解码 detail_json 存储值（列表展示与编辑回显共用）。
  static Map<String, dynamic>? decodeDetailJson(dynamic value) =>
      StructuredJsonCodec.tryDecodeStoredObject(value);

  static String _moduleText(dynamic value) {
    if (value is String) return value;
    if (value is Map) return _moduleItemText(value);
    if (value is List) {
      return value.map(_moduleText).where((text) => text.isNotEmpty).join('\n');
    }
    return '';
  }

  static String _moduleItemText(dynamic value) {
    if (value is String) return value.trim();
    if (value is! Map) return '';
    final content = value['content'] ?? value['summary'];
    if (content is String && content.trim().isNotEmpty) return content.trim();
    if (content is Map || content is List) {
      final nested = _moduleText(content);
      if (nested.isNotEmpty) return nested;
    }
    final name = value['name'] ?? value['term'] ?? value['time'];
    final detail =
        value['description'] ?? value['definition'] ?? value['event'];
    if (name is String && detail is String) return '$name：$detail';
    if (detail is String && detail.trim().isNotEmpty) return detail.trim();
    final nested = value.entries
        .where((entry) => entry.key.toString() != 'status')
        .map((entry) => _moduleText(entry.value))
        .where((text) => text.isNotEmpty)
        .join('\n');
    return nested;
  }
}

/// 模块 key 的展示标签。
String worldViewModuleLabel(String key) => switch (key) {
      'world_rules' => '规则与边界',
      'world_state' => '当前世界现状',
      'locations' => '地点与地理',
      'factions' => '势力与组织',
      'customs_and_life' => '风俗与生活',
      'timeline' => '历史与时间线',
      'glossary' => '术语表',
      'creative_constraints' => '创作约束',
      _ => key,
    };

/// NPC 手动编辑草稿：集中默认值、存储 JSON 解析与构造。
class NpcEditDraft {
  String? id;
  String name;
  String gender;
  String age;
  String profession;
  String personality;
  String appearance;
  String worldviewId;
  String source;

  /// 原始 json_data 内容，保存时保留未编辑字段。
  final Map<String, dynamic> originalJson;

  NpcEditDraft({
    this.id,
    this.name = '',
    this.gender = '女',
    this.age = '',
    this.profession = '',
    this.personality = '',
    this.appearance = '',
    this.worldviewId = '',
    this.source = '手动创建',
    Map<String, dynamic>? originalJson,
  }) : originalJson = originalJson ?? <String, dynamic>{};

  factory NpcEditDraft.fromExisting(Map<String, dynamic>? existing) {
    final json = existing == null
        ? <String, dynamic>{}
        : StructuredJsonCodec.tryDecodeStoredObject(existing['json_data']) ??
            <String, dynamic>{};
    return NpcEditDraft(
      id: existing?['id'] as String?,
      name: existing?['name'] as String? ?? json['name'] as String? ?? '',
      gender: json['gender'] as String? ?? '女',
      age: json['age']?.toString() ?? '',
      profession:
          json['profession'] as String? ?? json['role'] as String? ?? '',
      personality: json['personality'] as String? ?? '',
      appearance: json['appearance'] as String? ?? '',
      worldviewId: existing?['matching_worldview_id'] as String? ?? '',
      source: existing?['source'] as String? ?? '手动创建',
      originalJson: json,
    );
  }

  /// 构造存储 JSON：覆盖表单字段，保留原卡其他内容。
  String toStoredJson() => jsonEncode(
        Map<String, dynamic>.from(originalJson)
          ..addAll(<String, dynamic>{
            'name': name,
            'gender': gender,
            'age': age,
            'profession': profession,
            'personality': personality,
            'appearance': appearance,
          }),
      );
}

/// 角色卡手动编辑草稿：集中多别名兼容解析、默认值与 overlay 合并，
/// 页面不再直接触碰 [CharacterCardStorageAdapter]。
class CharacterCardEditDraft {
  String? id;
  String name;
  String gender;
  String customGender;
  String age;
  String profession;
  String personality;
  String description;
  String appearance;
  String bodyDescription;
  String faction;
  String homeLocation;
  String publicGoal;
  String hiddenMotivation;
  String abilitySource;
  String abilityCost;
  List<String> taboos;
  String relationshipNotes;
  String worldviewId;
  String source;

  /// 原始 json_data 字符串，保存时经 adapter overlay 合并。
  final String originalJson;

  CharacterCardEditDraft({
    this.id,
    this.name = '',
    this.gender = '女',
    this.customGender = '',
    this.age = '',
    this.profession = '',
    this.personality = '',
    this.description = '',
    this.appearance = '',
    this.bodyDescription = '',
    this.faction = '',
    this.homeLocation = '',
    this.publicGoal = '',
    this.hiddenMotivation = '',
    this.abilitySource = '',
    this.abilityCost = '',
    List<String>? taboos,
    this.relationshipNotes = '',
    this.worldviewId = '',
    this.source = '手动创建',
    this.originalJson = '{}',
  }) : taboos = taboos ?? <String>[];

  /// 与编辑器语义一致：下拉选择「其他」或原始值为自定义文本时，
  /// 保存均以 [customGender] 为准。
  bool get isCustomGender =>
      gender == '其他' || (!['男', '女', '其他'].contains(gender));

  String get taboosText => taboos.join('、');

  set taboosText(String value) => taboos = value
      .split('、')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList();

  factory CharacterCardEditDraft.fromExisting(
      Map<String, dynamic>? existingCard,
      {String? existingId}) {
    final adapter = CharacterCardStorageAdapter.fromStored(
        existingCard?['json_data'] as String? ?? '{}');
    final cardData = adapter.data;
    final gender = cardData['gender'] as String? ?? '女';
    final worldProfile =
        cardData['world_profile'] as Map<String, dynamic>? ?? const {};
    return CharacterCardEditDraft(
      id: existingId ?? existingCard?['id'] as String?,
      name:
          existingCard?['name'] as String? ?? cardData['name'] as String? ?? '',
      gender: gender,
      customGender: ['男', '女', '其他'].contains(gender) ? '' : gender,
      age: cardData['age']?.toString() ?? '',
      profession: cardData['profession'] as String? ??
          cardData['occupation'] as String? ??
          '',
      personality: cardData['personality'] as String? ?? '',
      description: cardData['description'] as String? ??
          cardData['background'] as String? ??
          '',
      appearance: cardData['appearance'] as String? ?? '',
      bodyDescription: _firstNonEmpty(cardData, const [
        'bodyDescription',
        'body_description',
        'physique',
        'figureDescription',
        'bodyShape',
        'bodyType',
        'physicalDescription',
        'appearanceDetail',
        'lookDescription',
      ]),
      faction: worldProfile['faction']?.toString() ?? '',
      homeLocation: worldProfile['home_location']?.toString() ?? '',
      publicGoal: worldProfile['public_goal']?.toString() ?? '',
      hiddenMotivation: worldProfile['hidden_motivation']?.toString() ?? '',
      abilitySource: worldProfile['ability_source']?.toString() ?? '',
      abilityCost: worldProfile['ability_cost']?.toString() ?? '',
      taboos: (worldProfile['taboos'] as List?)
              ?.map((item) => item.toString())
              .toList() ??
          <String>[],
      relationshipNotes: worldProfile['relationship_notes']?.toString() ?? '',
      worldviewId: existingCard?['matching_worldview_id'] as String? ?? '',
      source: existingCard?['source'] as String? ?? '手动创建',
      originalJson: existingCard?['json_data'] as String? ?? '{}',
    );
  }

  /// 构造存储 JSON：经 adapter overlay 保留原卡未编辑内容。
  String toStoredJson() {
    final adapter = CharacterCardStorageAdapter.fromStored(originalJson);
    return jsonEncode(adapter.overlay(
      fields: <String, dynamic>{
        'name': name,
        'gender': isCustomGender ? customGender : gender,
        'age': age,
        'profession': profession,
        'personality': personality,
        'description': description,
        'appearance': appearance,
        'bodyDescription': bodyDescription,
      },
      worldProfile: <String, dynamic>{
        'faction': faction,
        'home_location': homeLocation,
        'public_goal': publicGoal,
        'hidden_motivation': hiddenMotivation,
        'ability_source': abilitySource,
        'ability_cost': abilityCost,
        'taboos': taboos,
        'relationship_notes': relationshipNotes,
      },
    ));
  }

  static String _firstNonEmpty(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString();
      }
    }
    return '';
  }
}
