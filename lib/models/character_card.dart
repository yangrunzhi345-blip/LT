import 'dart:convert';
import 'dart:typed_data';
import 'package:equatable/equatable.dart';
import 'custom_attribute_item.dart';

class CharacterCard with Equatable {
  static const String spec = 'chara_card_v2';
  static const String specVersion = '2.0';

  final String name;
  final String description;
  final String personality;
  final String scenario;
  final String firstMessage;
  final String exampleDialogues;
  final String creatorNotes;
  final String systemPrompt;
  final String postHistoryInstructions;
  final List<String> alternateGreetings;
  final String characterVersion;
  final List<String> tags;
  final String creator;

  final String appearance;
  final String ability;
  final String weakness;
  final String equipment;
  final String bodyDescription;

  /// 自添加项 / 自定义属性
  final List<CustomAttributeItem> customAttributes;

  /// World-aware profile. Kept in the compatible card JSON rather than a
  /// separate table so an adventure can snapshot the exact selected card.
  final String faction;
  final String homeLocation;
  final String publicGoal;
  final String hiddenMotivation;
  final List<String> secrets;
  final String abilitySource;
  final String abilityCost;
  final List<String> taboos;
  final String relationshipNotes;

  /// 导入来源（如 'chub.ai' / '本地PNG' / '手动输入'）
  final String importSource;

  /// 原始 PNG 文件名（如有）
  final String? sourceFileName;

  /// 数据库存储 ID（由 CharacterManager 在加载时设置）
  String get dbId =>
      name.isNotEmpty || creator.isNotEmpty ? '${name}_$creator' : '';

  @override
  List<Object?> get props => [name, creator];

  CharacterCard({
    this.name = '',
    this.description = '',
    this.personality = '',
    this.scenario = '',
    this.firstMessage = '',
    this.exampleDialogues = '',
    this.creatorNotes = '',
    this.systemPrompt = '',
    this.postHistoryInstructions = '',
    List<String>? alternateGreetings,
    this.characterVersion = '1.0',
    List<String>? tags,
    this.creator = '',
    this.importSource = '',
    this.sourceFileName,
    this.appearance = '',
    this.ability = '',
    this.weakness = '',
    this.equipment = '',
    this.bodyDescription = '',
    this.faction = '',
    this.homeLocation = '',
    this.publicGoal = '',
    this.hiddenMotivation = '',
    List<String>? secrets,
    this.abilitySource = '',
    this.abilityCost = '',
    List<String>? taboos,
    this.relationshipNotes = '',
    List<CustomAttributeItem>? customAttributes,
  })  : alternateGreetings = List.unmodifiable(alternateGreetings ?? const []),
        tags = List.unmodifiable(tags ?? const []),
        secrets = List.unmodifiable(secrets ?? const []),
        taboos = List.unmodifiable(taboos ?? const []),
        customAttributes = List.unmodifiable(customAttributes ?? const []);

  Map<String, dynamic> toJson() => {
        'spec': spec,
        'spec_version': specVersion,
        'data': {
          'name': name,
          'description': description,
          'background': description,
          'personality': personality,
          'scenario': scenario,
          'first_mes': firstMessage,
          'mes_example': exampleDialogues,
          'creator_notes': creatorNotes,
          'system_prompt': systemPrompt,
          'post_history_instructions': postHistoryInstructions,
          'alternate_greetings': alternateGreetings,
          'character_version': characterVersion,
          'tags': tags,
          'creator': creator,
          'appearance': appearance,
          'bodyDescription': bodyDescription,
          'body_description': bodyDescription,
          'ability': ability,
          'weakness': weakness,
          'equipment': equipment,
          'custom_attributes':
              customAttributes.map((e) => e.toJson()).toList(),
          'world_profile': {
            'faction': faction,
            'home_location': homeLocation,
            'public_goal': publicGoal,
            'hidden_motivation': hiddenMotivation,
            'secrets': secrets,
            'ability_source': abilitySource,
            'ability_cost': abilityCost,
            'taboos': taboos,
            'relationship_notes': relationshipNotes,
          },
        },
      };

  factory CharacterCard.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>? ?? json;
    final profile = data['world_profile'] as Map<String, dynamic>? ?? const {};
    return CharacterCard(
      name: data['name'] as String? ?? '',
      description: _readString(data, const [
        'description',
        'background',
        'backstory',
        'backgroundStory',
        'background_story',
        'bio',
        'biography',
        'history',
      ]),
      personality: data['personality'] as String? ?? '',
      scenario: data['scenario'] as String? ?? '',
      firstMessage: data['first_mes'] as String? ?? '',
      exampleDialogues: data['mes_example'] as String? ?? '',
      creatorNotes: data['creator_notes'] as String? ?? '',
      systemPrompt: data['system_prompt'] as String? ?? '',
      postHistoryInstructions:
          data['post_history_instructions'] as String? ?? '',
      alternateGreetings:
          (data['alternate_greetings'] as List<dynamic>?)?.cast<String>() ?? [],
      characterVersion: data['character_version'] as String? ?? '1.0',
      tags: (data['tags'] as List<dynamic>?)?.cast<String>() ?? [],
      creator: data['creator'] as String? ?? '',
      appearance: data['appearance'] as String? ?? '',
      bodyDescription: _readString(data, const [
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
      ability: data['ability'] as String? ?? '',
      weakness: data['weakness'] as String? ?? '',
      equipment: data['equipment'] as String? ?? '',
      faction: profile['faction'] as String? ?? '',
      homeLocation: profile['home_location'] as String? ?? '',
      publicGoal: profile['public_goal'] as String? ?? '',
      hiddenMotivation: profile['hidden_motivation'] as String? ?? '',
      secrets: (profile['secrets'] as List?)?.map((e) => e.toString()).toList(),
      abilitySource: profile['ability_source'] as String? ?? '',
      abilityCost: profile['ability_cost'] as String? ?? '',
      taboos: (profile['taboos'] as List?)?.map((e) => e.toString()).toList(),
      relationshipNotes: profile['relationship_notes'] as String? ?? '',
      customAttributes: () {
        final rawCustom =
            data['custom_attributes'] ?? data['customAttributes'];
        if (rawCustom is List) {
          final list = <CustomAttributeItem>[];
          for (final item in rawCustom) {
            if (item is Map<String, dynamic>) {
              list.add(CustomAttributeItem.fromJson(item));
            } else if (item is Map) {
              list.add(CustomAttributeItem.fromJson(
                  Map<String, dynamic>.from(item)));
            }
          }
          return list;
        }
        return const <CustomAttributeItem>[];
      }(),
    );
  }

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());

  factory CharacterCard.fromJsonString(String jsonString) {
    return CharacterCard.fromJson(jsonDecode(jsonString));
  }

  CharacterCard copyWith({
    String? name,
    String? description,
    String? personality,
    String? scenario,
    String? firstMessage,
    String? exampleDialogues,
    String? creatorNotes,
    String? systemPrompt,
    String? postHistoryInstructions,
    List<String>? alternateGreetings,
    String? characterVersion,
    List<String>? tags,
    String? creator,
    String? appearance,
    String? bodyDescription,
    String? ability,
    String? weakness,
    String? equipment,
    String? importSource,
    String? sourceFileName,
    String? faction,
    String? homeLocation,
    String? publicGoal,
    String? hiddenMotivation,
    List<String>? secrets,
    String? abilitySource,
    String? abilityCost,
    List<String>? taboos,
    String? relationshipNotes,
    List<CustomAttributeItem>? customAttributes,
  }) {
    return CharacterCard(
      name: name ?? this.name,
      description: description ?? this.description,
      personality: personality ?? this.personality,
      scenario: scenario ?? this.scenario,
      firstMessage: firstMessage ?? this.firstMessage,
      exampleDialogues: exampleDialogues ?? this.exampleDialogues,
      creatorNotes: creatorNotes ?? this.creatorNotes,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      postHistoryInstructions:
          postHistoryInstructions ?? this.postHistoryInstructions,
      alternateGreetings: alternateGreetings ?? this.alternateGreetings,
      characterVersion: characterVersion ?? this.characterVersion,
      tags: tags ?? this.tags,
      creator: creator ?? this.creator,
      importSource: importSource ?? this.importSource,
      sourceFileName: sourceFileName ?? this.sourceFileName,
      appearance: appearance ?? this.appearance,
      bodyDescription: bodyDescription ?? this.bodyDescription,
      ability: ability ?? this.ability,
      weakness: weakness ?? this.weakness,
      equipment: equipment ?? this.equipment,
      faction: faction ?? this.faction,
      homeLocation: homeLocation ?? this.homeLocation,
      publicGoal: publicGoal ?? this.publicGoal,
      hiddenMotivation: hiddenMotivation ?? this.hiddenMotivation,
      secrets: secrets ?? this.secrets,
      abilitySource: abilitySource ?? this.abilitySource,
      abilityCost: abilityCost ?? this.abilityCost,
      taboos: taboos ?? this.taboos,
      relationshipNotes: relationshipNotes ?? this.relationshipNotes,
      customAttributes: customAttributes ?? this.customAttributes,
    );
  }

  // ─── P0-8: PNG 角色卡解析 ───

  /// PNG 文件签名（8 字节）
  static const _pngSignature = [137, 80, 78, 71, 13, 10, 26, 10];

  /// 从 PNG 字节数据中提取角色卡 JSON（tEXt 块中 keyword 为 chara 或 ccv3）
  static String? extractJsonFromPngBytes(Uint8List bytes) {
    if (bytes.length < 8) return null;
    for (int i = 0; i < 8; i++) {
      if (bytes[i] != _pngSignature[i]) return null;
    }

    int offset = 8;
    while (offset + 12 <= bytes.length) {
      final length = _readUint32(bytes, offset);
      offset += 4;
      final type = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      offset += 4;

      if (offset + length > bytes.length) break;

      if (type == 'tEXt' && length > 0) {
        final data = bytes.sublist(offset, offset + length);
        final nullPos = data.indexOf(0);
        if (nullPos > 0 && nullPos < data.length - 1) {
          final keyword = String.fromCharCodes(data.sublist(0, nullPos));
          if (keyword == 'chara' || keyword == 'ccv3') {
            final textBytes = data.sublist(nullPos + 1);
            try {
              return utf8.decode(textBytes);
            } catch (_) {
              return String.fromCharCodes(textBytes);
            }
          }
        }
      }

      offset += length + 4; // skip data + CRC
    }
    return null;
  }

  /// 从 PNG 字节数据中直接解析为 CharacterCard 列表（支持多角色卡 PNG）
  static List<CharacterCard> parseFromPngBytes(Uint8List bytes,
      {String sourceFileName = ''}) {
    final cards = <CharacterCard>[];
    final jsonStr = extractJsonFromPngBytes(bytes);
    if (jsonStr != null) {
      try {
        final json = jsonDecode(jsonStr);
        if (json is Map<String, dynamic>) {
          cards.add(
              _cardFromJson(json, source: 'PNG导入', fileName: sourceFileName));
        } else if (json is List) {
          for (final item in json) {
            if (item is Map<String, dynamic>) {
              cards.add(_cardFromJson(item,
                  source: 'PNG导入', fileName: sourceFileName));
            }
          }
        }
      } catch (_) {}
    }
    return cards;
  }

  /// 从 JSON 字符串解析角色卡（兼容标准 JSON 和 SillyTavern 格式）
  static CharacterCard? parseFromJson(String jsonStr,
      {String importSource = 'JSON导入'}) {
    try {
      final json = jsonDecode(jsonStr);
      if (json is Map<String, dynamic>) {
        return _cardFromJson(json, source: importSource);
      }
    } catch (_) {}
    return null;
  }

  static CharacterCard _cardFromJson(Map<String, dynamic> json,
      {String source = '', String fileName = ''}) {
    final data = json['data'] as Map<String, dynamic>? ?? json;
    return CharacterCard(
      name: (data['name'] as String?) ?? '',
      description: _readString(data, const [
        'description',
        'background',
        'backstory',
        'backgroundStory',
        'background_story',
        'bio',
        'biography',
        'history',
      ]),
      personality: (data['personality'] as String?) ?? '',
      scenario: (data['scenario'] as String?) ?? '',
      firstMessage: (data['first_mes'] as String?) ?? '',
      exampleDialogues: (data['mes_example'] as String?) ?? '',
      creatorNotes: (data['creator_notes'] as String?) ?? '',
      systemPrompt: (data['system_prompt'] as String?) ?? '',
      postHistoryInstructions:
          (data['post_history_instructions'] as String?) ?? '',
      alternateGreetings:
          (data['alternate_greetings'] as List<dynamic>?)?.cast<String>() ?? [],
      characterVersion: (data['character_version'] as String?) ?? '1.0',
      tags: (data['tags'] as List<dynamic>?)?.cast<String>() ?? [],
      creator: (data['creator'] as String?) ?? '',
      importSource: source,
      sourceFileName: fileName.isNotEmpty ? fileName : null,
      appearance: (data['appearance'] as String?) ?? '',
      bodyDescription: _readString(data, const [
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
      ability: (data['ability'] as String?) ?? '',
      weakness: (data['weakness'] as String?) ?? '',
      equipment: (data['equipment'] as String?) ?? '',
    );
  }

  static int _readUint32(Uint8List bytes, int offset) {
    return (bytes[offset] << 24) |
        (bytes[offset + 1] << 16) |
        (bytes[offset + 2] << 8) |
        bytes[offset + 3];
  }

  static String _readString(
    Map<String, dynamic> data,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = data[key];
      if (value != null) {
        final text = value.toString().trim();
        if (text.isNotEmpty) return text;
      }
    }
    return '';
  }
}
