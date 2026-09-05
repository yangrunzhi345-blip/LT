import 'supporting_character.dart';
import 'character_card.dart';
import 'custom_attribute_item.dart';

class AdventureCharacterRole {
  static const protagonist = 'protagonist';
  static const maleLead = 'maleLead';
  static const femaleLead = 'femaleLead';
  static const maleOne = 'maleOne';
  static const femaleOne = 'femaleOne';
  static const maleTwo = 'maleTwo';
  static const femaleTwo = 'femaleTwo';
  static const supporting = 'supporting';
  static const companion = 'companion';
  static const villain = 'villain';
  static const mentor = 'mentor';
  static const family = 'family';
  static const custom = 'custom';

  static const labels = <String, String>{
    protagonist: '主角',
    maleLead: '男主',
    femaleLead: '女主',
    maleOne: '男一',
    femaleOne: '女一',
    maleTwo: '男二',
    femaleTwo: '女二',
    supporting: '重要配角',
    companion: '同伴',
    villain: '反派',
    mentor: '导师',
    family: '亲友',
    custom: '自定义',
  };

  static String normalize(String? value) =>
      labels.containsKey(value) ? value! : supporting;

  static String labelOf(String value, {String customName = ''}) {
    final normalized = normalize(value);
    if (normalized == custom && customName.trim().isNotEmpty) {
      return customName.trim();
    }
    return labels[normalized] ?? labels[supporting]!;
  }
}

class AdventureRelationType {
  static const unset = 'unset';
  static const friend = 'friend';
  static const family = 'family';
  static const enemy = 'enemy';
  static const companion = 'companion';
  static const lover = 'lover';
  static const mentor = 'mentor';
  static const rival = 'rival';
  static const employer = 'employer';
  static const stranger = 'stranger';
  static const custom = 'custom';

  static const labels = <String, String>{
    unset: '未设定',
    friend: '朋友',
    family: '亲人',
    enemy: '敌人',
    companion: '同伴',
    lover: '恋人',
    mentor: '师徒',
    rival: '竞争对手',
    employer: '雇佣关系',
    stranger: '陌生人',
    custom: '自定义关系',
  };

  static String normalize(String? value) =>
      labels.containsKey(value) ? value! : unset;

  static String labelOf(String value, {String customName = ''}) {
    final normalized = normalize(value);
    if (normalized == custom && customName.trim().isNotEmpty) {
      return customName.trim();
    }
    return labels[normalized] ?? labels[unset]!;
  }
}

class AdventureSelectedCharacter {
  String id;
  String characterId;
  String characterName;
  String characterAvatar;
  bool isProtagonist;
  String narrativeRole;
  String customRoleName;
  int sortOrder;
  String createdAt;
  String updatedAt;
  Map<String, dynamic>? characterCardJson;

  AdventureSelectedCharacter({
    required this.id,
    required this.characterId,
    required this.characterName,
    this.characterAvatar = '',
    this.isProtagonist = false,
    this.narrativeRole = AdventureCharacterRole.supporting,
    this.customRoleName = '',
    this.sortOrder = 0,
    String? createdAt,
    String? updatedAt,
    this.characterCardJson,
  })  : createdAt = createdAt ?? DateTime.now().toIso8601String(),
        updatedAt = updatedAt ?? DateTime.now().toIso8601String();

  String get effectiveRole =>
      AdventureCharacterRole.labelOf(narrativeRole, customName: customRoleName);

  Map<String, dynamic> toJson() => {
        'id': id,
        'characterId': characterId,
        'characterName': characterName,
        'characterAvatar': characterAvatar,
        'isProtagonist': isProtagonist,
        'narrativeRole': narrativeRole,
        'customRoleName': customRoleName,
        'sortOrder': sortOrder,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'characterCardJson': characterCardJson,
      };

  factory AdventureSelectedCharacter.fromJson(Map<String, dynamic> json) {
    final characterId = json['characterId'] as String? ??
        json['character_id'] as String? ??
        json['id'] as String? ??
        '';
    return AdventureSelectedCharacter(
      id: json['id'] as String? ?? characterId,
      characterId: characterId,
      characterName: json['characterName'] as String? ??
          json['character_name'] as String? ??
          json['name'] as String? ??
          '',
      characterAvatar:
          json['characterAvatar'] as String? ?? json['avatar'] as String? ?? '',
      isProtagonist: json['isProtagonist'] as bool? ?? false,
      narrativeRole: AdventureCharacterRole.normalize(
          json['narrativeRole'] as String? ?? json['role'] as String?),
      customRoleName: json['customRoleName'] as String? ?? '',
      sortOrder: json['sortOrder'] as int? ?? 0,
      createdAt: json['createdAt'] as String?,
      updatedAt: json['updatedAt'] as String?,
      characterCardJson: json['characterCardJson'] as Map<String, dynamic>?,
    );
  }

  AdventureSelectedCharacter copyWith({
    String? characterName,
    String? characterAvatar,
    bool? isProtagonist,
    String? narrativeRole,
    String? customRoleName,
    int? sortOrder,
    Map<String, dynamic>? characterCardJson,
  }) =>
      AdventureSelectedCharacter(
        id: id,
        characterId: characterId,
        characterName: characterName ?? this.characterName,
        characterAvatar: characterAvatar ?? this.characterAvatar,
        isProtagonist: isProtagonist ?? this.isProtagonist,
        narrativeRole: narrativeRole ?? this.narrativeRole,
        customRoleName: customRoleName ?? this.customRoleName,
        sortOrder: sortOrder ?? this.sortOrder,
        createdAt: createdAt,
        updatedAt: DateTime.now().toIso8601String(),
        characterCardJson: characterCardJson ?? this.characterCardJson,
      );
}

class AdventureCharacterRelationship {
  String id;
  String sourceCharacterId;
  String targetCharacterId;
  String relationType;
  String customRelationName;
  String description;
  String createdAt;
  String updatedAt;

  AdventureCharacterRelationship({
    required this.id,
    required this.sourceCharacterId,
    required this.targetCharacterId,
    this.relationType = AdventureRelationType.unset,
    this.customRelationName = '',
    this.description = '',
    String? createdAt,
    String? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now().toIso8601String(),
        updatedAt = updatedAt ?? DateTime.now().toIso8601String();

  String get effectiveRelation => AdventureRelationType.labelOf(relationType,
      customName: customRelationName);

  static String stableId(String a, String b) {
    final pair = [a, b]..sort();
    return '${pair[0]}__${pair[1]}';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'sourceCharacterId': sourceCharacterId,
        'targetCharacterId': targetCharacterId,
        'relationType': relationType,
        'customRelationName': customRelationName,
        'description': description,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };

  factory AdventureCharacterRelationship.fromJson(Map<String, dynamic> json) {
    final source = json['sourceCharacterId'] as String? ??
        json['source_character_id'] as String? ??
        '';
    final target = json['targetCharacterId'] as String? ??
        json['target_character_id'] as String? ??
        '';
    final id = json['id'] as String? ?? stableId(source, target);
    return AdventureCharacterRelationship(
      id: id,
      sourceCharacterId: source,
      targetCharacterId: target,
      relationType:
          AdventureRelationType.normalize(json['relationType'] as String?),
      customRelationName: json['customRelationName'] as String? ?? '',
      description: json['description'] as String? ?? '',
      createdAt: json['createdAt'] as String?,
      updatedAt: json['updatedAt'] as String?,
    );
  }

  AdventureCharacterRelationship copyWith({
    String? relationType,
    String? customRelationName,
    String? description,
  }) =>
      AdventureCharacterRelationship(
        id: id,
        sourceCharacterId: sourceCharacterId,
        targetCharacterId: targetCharacterId,
        relationType: relationType ?? this.relationType,
        customRelationName: customRelationName ?? this.customRelationName,
        description: description ?? this.description,
        createdAt: createdAt,
        updatedAt: DateTime.now().toIso8601String(),
      );
}

class AdventureConfig {
  // 世界观
  String worldview;

  /// Immutable resource-library snapshot selected when this adventure began.
  Map<String, dynamic>? worldviewSnapshot;

  // 基础信息
  String name;
  String gender;
  String age;

  // 主角选型
  String protagonistClass;
  String protagonistBackground;

  // 配角
  List<SupportingCharacter> supportingCharacters;

  // 外貌·身材 (11 fields)
  String height;
  String skinTone;
  String facialFeatures;
  String hairStyle;
  String hairColor;
  String neckLength;
  String shoulders;
  String chest;
  String waist;
  String hips;
  String legLength;
  String feet;

  // 性格 · 人称 · 文风
  String personality;
  String narrativePerson;
  String styleEnhancement;

  // 角色卡 (SillyTavern 兼容)
  CharacterCard? characterCard;

  // 自由创建多角色选择
  List<AdventureSelectedCharacter> selectedCharacters;
  List<AdventureCharacterRelationship> characterRelationships;

  // 自动生成的身材描述
  String customBodyDescription;

  String get bodyDescription => customBodyDescription.isNotEmpty
      ? customBodyDescription
      : _generateBodyDescription();

  // 性格 · 人称 · 文风

  // 开场场景
  String openingScene;
  String? customOpeningScene;
  List<String> openingOptions;

  // 自定义与动态检测状态
  List<CustomAttributeItem> customAttributes;

  AdventureConfig({
    this.worldview = '',
    this.worldviewSnapshot,
    this.name = '',
    this.gender = '',
    this.age = '',
    this.protagonistClass = '',
    this.protagonistBackground = '',
    List<SupportingCharacter>? supportingCharacters,
    this.height = '',
    this.skinTone = '',
    this.facialFeatures = '',
    this.hairStyle = '',
    this.hairColor = '',
    this.neckLength = '',
    this.shoulders = '',
    this.chest = '',
    this.waist = '',
    this.hips = '',
    this.customBodyDescription = '',
    this.legLength = '',
    this.feet = '',
    this.personality = '',
    this.narrativePerson = '',
    this.styleEnhancement = '',
    this.characterCard,
    List<AdventureSelectedCharacter>? selectedCharacters,
    List<AdventureCharacterRelationship>? characterRelationships,
    this.openingScene = '',
    this.customOpeningScene,
    List<String>? openingOptions,
    List<CustomAttributeItem>? customAttributes,
  })  : supportingCharacters = supportingCharacters ?? [],
        selectedCharacters =
            _normalizedSelectedCharacters(selectedCharacters ?? []),
        characterRelationships = characterRelationships ?? [],
        openingOptions = openingOptions ?? ['探索前方的道路', '观察周围环境', '检查随身物品'],
        customAttributes = customAttributes ??
            (characterCard?.customAttributes.isNotEmpty == true
                ? List.from(characterCard!.customAttributes)
                : []);

  String get effectiveOpeningScene => customOpeningScene?.isNotEmpty == true
      ? customOpeningScene!
      : openingScene;

  String _generateBodyDescription() {
    final h = height;
    final c = chest;
    final w = waist;
    final hp = hips;
    final legs = legLength;
    final sh = shoulders;
    final sk = skinTone;
    final fc = facialFeatures;
    final hr = hairStyle;
    final hc = hairColor;
    final nk = neckLength;
    final ft = feet;

    String desc = '';

    if (h.isNotEmpty) {
      if (h.contains('娇小') || h.contains('矮')) {
        desc += '娇小玲珑的身材';
      } else if (h.contains('高挑') || h.contains('高')) {
        desc += '高挑修长的身姿';
      } else if (h.contains('中等')) {
        desc += '中等匀称的体型';
      } else {
        desc += '$h的身材';
      }
    }
    if (c.isNotEmpty) {
      if (c.contains('巨乳')) {
        desc += '，拥有傲人的巨乳';
      } else if (c.contains('丰满')) {
        desc += '，胸部丰满';
      } else if (c.contains('适中')) {
        desc += '，胸部适中';
      } else if (c.contains('平坦')) {
        desc += '，胸部平坦';
      } else {
        desc += '，$c';
      }
    }
    if (w.isNotEmpty) {
      if (w.contains('纤细') || w.contains('水蛇腰')) {
        desc += '，腰肢纤细';
      } else if (w.contains('粗壮')) {
        desc += '，腰部粗壮';
      } else {
        desc += '，$w';
      }
    }
    if (hp.isNotEmpty) {
      if (hp.contains('丰满') || hp.contains('翘臀')) {
        desc += '，臀部丰满挺翘';
      } else if (hp.contains('扁平')) {
        desc += '，臀部扁平';
      } else {
        desc += '，$hp';
      }
    }
    if (legs.isNotEmpty) {
      if (legs.contains('大长腿')) {
        desc += '，双腿修长笔直';
      } else if (legs.contains('短腿')) {
        desc += '，双腿较短';
      } else {
        desc += '，$legs';
      }
    }
    if (sh.isNotEmpty) desc += '，$sh';
    if (sk.isNotEmpty) desc += '，$sk肌肤';
    if (fc.isNotEmpty) desc += '，五官$fc';
    if (hr.isNotEmpty) {
      String hairStr = hr;
      if (hc.isNotEmpty) hairStr = '$hc色$hr';
      desc += '，$hairStr';
    }
    if (nk.isNotEmpty) desc += '，颈$nk';
    if (ft.isNotEmpty) desc += '，双足$ft';

    desc = desc.replaceAll(RegExp(r'^，'), '').trim();
    if (desc.isEmpty) return '';

    String tag;
    if ((h.contains('娇小')) &&
        (c.contains('巨乳') || c.contains('丰满')) &&
        (hp.contains('丰满') || hp.contains('翘臀'))) {
      tag = '，整体呈现典型的巨乳萝莉体型，可爱与性感交织';
    } else if ((h.contains('高挑') || h.contains('高')) &&
        (c.contains('适中') || c.contains('丰满')) &&
        legs.contains('大长腿')) {
      tag = '，散发着高冷御姐般的优雅气场';
    } else if (sh.contains('宽肩') && h.contains('高')) {
      tag = '，显得英姿飒爽，力量感十足';
    } else if (w.contains('水蛇腰') && (hp.contains('丰满') || hp.contains('翘臀'))) {
      tag = '，曲线玲珑，妩媚动人';
    } else {
      tag = '，独具魅力';
    }
    desc += tag;
    if (desc.length < 20) desc += '，细节之处尽显独特韵味。';
    return desc;
  }

  Map<String, dynamic> toJson() => {
        'worldview': worldview,
        'worldviewSnapshot': worldviewSnapshot,
        'name': name,
        'gender': gender,
        'age': age,
        'protagonistClass': protagonistClass,
        'protagonistBackground': protagonistBackground,
        'supportingCharacters':
            supportingCharacters.map((c) => c.toJson()).toList(),
        'height': height,
        'skinTone': skinTone,
        'facialFeatures': facialFeatures,
        'hairStyle': hairStyle,
        'hairColor': hairColor,
        'neckLength': neckLength,
        'shoulders': shoulders,
        'chest': chest,
        'waist': waist,
        'hips': hips,
        'legLength': legLength,
        'feet': feet,
        'customBodyDescription': customBodyDescription,
        // Legacy aliases remain readable by older exported presets.
        'bodyDescription': customBodyDescription,
        'custom_body_description': customBodyDescription,
        'personality': personality,
        'narrativePerson': narrativePerson,
        'styleEnhancement': styleEnhancement,
        'openingScene': openingScene,
        'customOpeningScene': customOpeningScene,
        'openingOptions': openingOptions,
        'characterCard': characterCard?.toJson(),
        'selectedCharacters':
            selectedCharacters.map((c) => c.toJson()).toList(),
        'characterRelationships':
            characterRelationships.map((r) => r.toJson()).toList(),
        'customAttributes': customAttributes.map((a) => a.toJson()).toList(),
      };

  factory AdventureConfig.fromJson(Map<String, dynamic> json) {
    final card = json['characterCard'] != null
        ? CharacterCard.fromJson(json['characterCard'] as Map<String, dynamic>)
        : null;
    var selected = (json['selectedCharacters'] as List<dynamic>?)
            ?.whereType<Map<String, dynamic>>()
            .map(AdventureSelectedCharacter.fromJson)
            .toList() ??
        [];
    final name = json['name'] as String? ?? '';
    if (selected.isEmpty && (card != null || name.isNotEmpty)) {
      selected = [
        AdventureSelectedCharacter(
          id: 'legacy_protagonist',
          characterId: 'legacy_protagonist',
          characterName: name.isNotEmpty ? name : card?.name ?? '',
          isProtagonist: true,
          narrativeRole: AdventureCharacterRole.protagonist,
          sortOrder: 0,
          characterCardJson: card?.toJson(),
        ),
      ];
    }

    final rawCustom = json['customAttributes'] ?? json['custom_attributes'];
    final customList = <CustomAttributeItem>[];
    if (rawCustom is List) {
      for (final item in rawCustom) {
        if (item is Map) {
          customList.add(CustomAttributeItem.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    } else if (card != null && card.customAttributes.isNotEmpty) {
      customList.addAll(card.customAttributes);
    }

    return AdventureConfig(
      worldview: json['worldview'] as String? ?? '',
      worldviewSnapshot: json['worldviewSnapshot'] is Map
          ? Map<String, dynamic>.from(json['worldviewSnapshot'] as Map)
          : null,
      name: name,
      gender: json['gender'] as String? ?? '',
      age: json['age'] as String? ?? '',
      protagonistClass: json['protagonistClass'] as String? ?? '',
      protagonistBackground: json['protagonistBackground'] as String? ?? '',
      supportingCharacters: (json['supportingCharacters'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map(SupportingCharacter.fromJson)
              .toList() ??
          const [],
      height: json['height'] as String? ?? '',
      skinTone: json['skinTone'] as String? ?? '',
      facialFeatures: json['facialFeatures'] as String? ?? '',
      hairStyle: json['hairStyle'] as String? ?? '',
      hairColor: json['hairColor'] as String? ?? '',
      neckLength: json['neckLength'] as String? ?? '',
      shoulders: json['shoulders'] as String? ?? '',
      chest: json['chest'] as String? ?? '',
      waist: json['waist'] as String? ?? '',
      hips: json['hips'] as String? ?? '',
      legLength: json['legLength'] as String? ?? '',
      feet: json['feet'] as String? ?? '',
      customBodyDescription: (json['customBodyDescription'] ??
                  json['custom_body_description'] ??
                  json['bodyDescription'] ??
                  json['body_description'])
              ?.toString() ??
          '',
      personality: json['personality'] as String? ?? '',
      narrativePerson: json['narrativePerson'] as String? ?? '',
      styleEnhancement: json['styleEnhancement'] as String? ?? '',
      openingScene: json['openingScene'] as String? ?? '',
      customOpeningScene: json['customOpeningScene'] as String?,
      openingOptions:
          (json['openingOptions'] as List<dynamic>?)?.cast<String>(),
      characterCard: card,
      selectedCharacters: selected,
      characterRelationships: (json['characterRelationships'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map(AdventureCharacterRelationship.fromJson)
              .toList() ??
          const [],
      customAttributes: customList,
    );
  }

  AdventureSelectedCharacter? get protagonistCharacter {
    for (final character in selectedCharacters) {
      if (character.isProtagonist) return character;
    }
    return selectedCharacters.isNotEmpty ? selectedCharacters.first : null;
  }

  static List<AdventureSelectedCharacter> _normalizedSelectedCharacters(
    List<AdventureSelectedCharacter> characters,
  ) {
    if (characters.isEmpty) return const [];
    final normalized = <AdventureSelectedCharacter>[];
    var protagonistSeen = false;
    for (final character in characters) {
      if (character.isProtagonist && !protagonistSeen) {
        protagonistSeen = true;
        normalized.add(character);
      } else if (character.isProtagonist) {
        normalized.add(character.copyWith(isProtagonist: false));
      } else {
        normalized.add(character);
      }
    }
    if (!protagonistSeen) {
      normalized[0] = normalized.first.copyWith(isProtagonist: true);
    }
    return normalized;
  }

  AdventureConfig copyWith({
    String? worldview,
    Map<String, dynamic>? worldviewSnapshot,
    String? name,
    String? gender,
    String? age,
    String? protagonistClass,
    String? protagonistBackground,
    List<SupportingCharacter>? supportingCharacters,
    String? personality,
    CharacterCard? characterCard,
    List<AdventureSelectedCharacter>? selectedCharacters,
    List<AdventureCharacterRelationship>? characterRelationships,
    List<CustomAttributeItem>? customAttributes,
  }) =>
      AdventureConfig(
        worldview: worldview ?? this.worldview,
        worldviewSnapshot: worldviewSnapshot ?? this.worldviewSnapshot,
        name: name ?? this.name,
        gender: gender ?? this.gender,
        age: age ?? this.age,
        protagonistClass: protagonistClass ?? this.protagonistClass,
        protagonistBackground:
            protagonistBackground ?? this.protagonistBackground,
        supportingCharacters: supportingCharacters ?? this.supportingCharacters,
        height: height,
        skinTone: skinTone,
        facialFeatures: facialFeatures,
        hairStyle: hairStyle,
        hairColor: hairColor,
        neckLength: neckLength,
        shoulders: shoulders,
        chest: chest,
        waist: waist,
        hips: hips,
        legLength: legLength,
        feet: feet,
        personality: personality ?? this.personality,
        narrativePerson: narrativePerson,
        styleEnhancement: styleEnhancement,
        characterCard: characterCard ?? this.characterCard,
        selectedCharacters: selectedCharacters ?? this.selectedCharacters,
        characterRelationships:
            characterRelationships ?? this.characterRelationships,
        customBodyDescription: customBodyDescription,
        openingScene: openingScene,
        customOpeningScene: customOpeningScene,
        openingOptions: openingOptions,
        customAttributes: customAttributes ?? List.from(this.customAttributes),
      );
}
