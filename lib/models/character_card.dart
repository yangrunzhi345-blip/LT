import 'dart:convert';
// `Uint8List` is also re-exported by `flutter/foundation.dart`, but the PNG
// parsing helpers must not depend on a Flutter import to see it: keep the
// direct dart: source so this model stays framework-independent.
// ignore: unnecessary_import
import 'dart:typed_data';
import 'package:equatable/equatable.dart';
import 'custom_attribute_item.dart';
import 'package:flutter/foundation.dart';

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
          'custom_attributes': customAttributes.map((e) => e.toJson()).toList(),
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
    // Fall back to the flat payload when there is no usable `data` wrapper:
    // some exports persist the card without it, and a `data` node of the wrong
    // type must degrade to the flat shape rather than throw.
    final nested = json['data'];
    final data = nested is Map ? _asMap(nested) : json;
    final profile = _asMap(data['world_profile']);
    return CharacterCard(
      name: _asText(data['name']),
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
      personality: _asText(data['personality']),
      scenario: _asText(data['scenario']),
      firstMessage: _asText(data['first_mes']),
      exampleDialogues: _asText(data['mes_example']),
      creatorNotes: _asText(data['creator_notes']),
      systemPrompt: _asText(data['system_prompt']),
      postHistoryInstructions: _asText(data['post_history_instructions']),
      alternateGreetings: _asTextList(data['alternate_greetings']),
      characterVersion: _asText(data['character_version']).isEmpty
          ? '1.0'
          : _asText(data['character_version']),
      tags: _asTextList(data['tags']),
      creator: _asText(data['creator']),
      appearance: _asText(data['appearance']),
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
      ability: _asText(data['ability']),
      weakness: _asText(data['weakness']),
      equipment: _asText(data['equipment']),
      faction: _asText(profile['faction']),
      homeLocation: _asText(profile['home_location']),
      publicGoal: _asText(profile['public_goal']),
      hiddenMotivation: _asText(profile['hidden_motivation']),
      secrets: _asTextList(profile['secrets']),
      abilitySource: _asText(profile['ability_source']),
      abilityCost: _asText(profile['ability_cost']),
      taboos: _asTextList(profile['taboos']),
      relationshipNotes: _asText(profile['relationship_notes']),
      customAttributes: () {
        final rawCustom = data['custom_attributes'] ?? data['customAttributes'];
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
    final decoded = jsonDecode(jsonString);
    if (decoded is Map) {
      return CharacterCard.fromJson(Map<String, dynamic>.from(decoded));
    }
    // A non-object top level carries no card fields; return an empty card
    // rather than throwing so callers can report a recoverable import failure.
    return CharacterCard();
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
      } catch (e, stack) {
        debugPrint('Error parsing PNG JSON: $e\n$stack');
      }
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
    // Route every external entry point (JSON, PNG, SillyTavern) through the
    // single tolerant parser so the accepted shape never depends on how the
    // card arrived. Previously this path used strict `as String?` casts and
    // silently diverged from `fromJson` for the same logical payload.
    return CharacterCard.fromJson(json).copyWith(
      importSource: source,
      sourceFileName: fileName.isNotEmpty ? fileName : null,
    );
  }

  static int _readUint32(Uint8List bytes, int offset) {
    return (bytes[offset] << 24) |
        (bytes[offset + 1] << 16) |
        (bytes[offset + 2] << 8) |
        bytes[offset + 3];
  }

  /// Reads a JSON node as a map, tolerating legacy rows whose nested node was
  /// persisted as a string, a list or `null`.
  static Map<String, dynamic> _asMap(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : const {};

  /// Reads one persisted field as text without assuming its runtime type.
  ///
  /// Historical rows and third-party exports regularly store numbers, booleans
  /// or lists where this model expects a string. A hard `as String?` cast turns
  /// a single bad row into a `TypeError` that kills the whole card list, so
  /// anything that is not scalar text falls back to an empty string.
  static String _asText(Object? value) => switch (value) {
        String text => text,
        num number => number.toString(),
        bool flag => flag.toString(),
        _ => '',
      };

  /// Reads a persisted list field as text items, ignoring non-iterable values.
  static List<String> _asTextList(Object? value) {
    if (value is! Iterable) return const [];
    return [
      for (final item in value)
        if (_asText(item).trim().isNotEmpty) _asText(item).trim(),
    ];
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
