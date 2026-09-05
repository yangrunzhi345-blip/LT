import 'dart:convert';
import 'custom_attribute_item.dart';

class SupportingCharacter {
  /// Persisted identity. Old JSON is deterministically upgraded on read.
  String id;
  String name;
  String relation;
  String personality;
  String role;
  String gender;
  String height;
  String skinTone;
  String facialFeatures;
  String hairStyle;
  String hairColor;
  String chest;
  String waist;
  String hips;
  String legLength;
  int affinity;
  bool isAlive;
  List<CustomAttributeItem> customAttributes;

  SupportingCharacter({
    String? id,
    this.name = '',
    this.relation = '',
    this.personality = '',
    this.role = '',
    this.gender = '',
    this.height = '',
    this.skinTone = '',
    this.facialFeatures = '',
    this.hairStyle = '',
    this.hairColor = '',
    this.chest = '',
    this.waist = '',
    this.hips = '',
    this.legLength = '',
    this.affinity = 50,
    this.isAlive = true,
    List<CustomAttributeItem>? customAttributes,
  })  : id = id ?? 'npc-${DateTime.now().microsecondsSinceEpoch}',
        customAttributes = customAttributes ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'relation': relation,
        'personality': personality,
        'role': role,
        'gender': gender,
        'height': height,
        'skinTone': skinTone,
        'facialFeatures': facialFeatures,
        'hairStyle': hairStyle,
        'hairColor': hairColor,
        'chest': chest,
        'waist': waist,
        'hips': hips,
        'legLength': legLength,
        'affinity': affinity,
        'isAlive': isAlive,
        'custom_attributes': customAttributes.map((a) => a.toJson()).toList(),
      };

  factory SupportingCharacter.fromJson(Map<String, dynamic> json) {
    final rawCustom = json['custom_attributes'] ?? json['customAttributes'];
    final customList = <CustomAttributeItem>[];
    if (rawCustom is List) {
      for (final item in rawCustom) {
        if (item is Map<String, dynamic>) {
          customList.add(CustomAttributeItem.fromJson(item));
        } else if (item is Map) {
          customList.add(
              CustomAttributeItem.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    return SupportingCharacter(
      id: (json['id'] as String?)?.trim().isNotEmpty == true
          ? json['id'] as String
          : 'legacy-npc-${base64Url.encode(utf8.encode('${json['name'] ?? ''}|${json['role'] ?? ''}')).replaceAll('=', '')}',
      name: json['name'] as String? ?? '',
      relation: json['relation'] as String? ?? '',
      personality: json['personality'] as String? ?? '',
      role: json['role'] as String? ?? '',
      gender: json['gender'] as String? ?? '',
      height: json['height'] as String? ?? '',
      skinTone: json['skinTone'] as String? ?? '',
      facialFeatures: json['facialFeatures'] as String? ?? '',
      hairStyle: json['hairStyle'] as String? ?? '',
      hairColor: json['hairColor'] as String? ?? '',
      chest: json['chest'] as String? ?? '',
      waist: json['waist'] as String? ?? '',
      hips: json['hips'] as String? ?? '',
      legLength: json['legLength'] as String? ?? '',
      affinity: json['affinity'] as int? ?? 50,
      isAlive: json['isAlive'] as bool? ?? true,
      customAttributes: customList,
    );
  }

  SupportingCharacter copyWith({
    String? id,
    String? name,
    String? relation,
    String? personality,
    String? role,
    String? gender,
    String? height,
    String? skinTone,
    String? facialFeatures,
    String? hairStyle,
    String? hairColor,
    String? chest,
    String? waist,
    String? hips,
    String? legLength,
    int? affinity,
    bool? isAlive,
    List<CustomAttributeItem>? customAttributes,
  }) =>
      SupportingCharacter(
        id: id ?? this.id,
        name: name ?? this.name,
        relation: relation ?? this.relation,
        personality: personality ?? this.personality,
        role: role ?? this.role,
        gender: gender ?? this.gender,
        height: height ?? this.height,
        skinTone: skinTone ?? this.skinTone,
        facialFeatures: facialFeatures ?? this.facialFeatures,
        hairStyle: hairStyle ?? this.hairStyle,
        hairColor: hairColor ?? this.hairColor,
        chest: chest ?? this.chest,
        waist: waist ?? this.waist,
        hips: hips ?? this.hips,
        legLength: legLength ?? this.legLength,
        affinity: affinity ?? this.affinity,
        isAlive: isAlive ?? this.isAlive,
        customAttributes: customAttributes ?? List.from(this.customAttributes),
      );

  String get bodyDescription {
    final parts = <String>[];
    if (height.isNotEmpty) parts.add(height);
    if (chest.isNotEmpty) parts.add('胸部$chest');
    if (waist.isNotEmpty) parts.add('腰$waist');
    if (hips.isNotEmpty) parts.add('臀$hips');
    if (legLength.isNotEmpty) parts.add(legLength);
    if (skinTone.isNotEmpty) parts.add('$skinTone肤');
    if (hairStyle.isNotEmpty || hairColor.isNotEmpty) {
      final hair = [hairColor, hairStyle].where((s) => s.isNotEmpty).join('');
      if (hair.isNotEmpty) parts.add(hair);
    }
    if (facialFeatures.isNotEmpty) parts.add('五官$facialFeatures');
    return parts.join('，');
  }

  String get description {
    final parts = <String>[];
    if (role.isNotEmpty) parts.add('定位：$role');
    if (relation.isNotEmpty) parts.add('关系：$relation');
    if (gender.isNotEmpty) parts.add('性别：$gender');
    if (personality.isNotEmpty) parts.add('性格：$personality');
    if (bodyDescription.isNotEmpty) parts.add('外貌：$bodyDescription');
    if (customAttributes.isNotEmpty) {
      final customDesc = customAttributes
          .map((a) => '【${a.importance.label}】${a.name}：${a.value}')
          .join('；');
      parts.add('自添加专属设定：$customDesc');
    }
    if (parts.isEmpty) return name;
    return '$name — ${parts.join('，')}';
  }
}
