import 'dart:convert';

import '../../../../../models/adventure_config.dart';
import '../../../../../models/character_card_entry.dart';

/// 向导中统一的角色设计模型
class WizardCharacterItem {
  String id;
  String name;
  String gender;
  String age;
  String profession;
  String personality;
  String background;
  bool isProtagonist;
  String narrativeRole;
  String customRoleName;
  CharacterCardEntry? libraryEntry;
  Map<String, dynamic>? rawJson;

  WizardCharacterItem({
    required this.id,
    required this.name,
    this.gender = '',
    this.age = '',
    this.profession = '',
    this.personality = '',
    this.background = '',
    this.isProtagonist = false,
    this.narrativeRole = AdventureCharacterRole.supporting,
    this.customRoleName = '',
    this.libraryEntry,
    this.rawJson,
  });

  String get effectiveRole =>
      AdventureCharacterRole.labelOf(narrativeRole, customName: customRoleName);

  WizardCharacterItem copyWith({
    String? id,
    String? name,
    String? gender,
    String? age,
    String? profession,
    String? personality,
    String? background,
    bool? isProtagonist,
    String? narrativeRole,
    String? customRoleName,
    CharacterCardEntry? libraryEntry,
    Map<String, dynamic>? rawJson,
  }) {
    return WizardCharacterItem(
      id: id ?? this.id,
      name: name ?? this.name,
      gender: gender ?? this.gender,
      age: age ?? this.age,
      profession: profession ?? this.profession,
      personality: personality ?? this.personality,
      background: background ?? this.background,
      isProtagonist: isProtagonist ?? this.isProtagonist,
      narrativeRole: narrativeRole ?? this.narrativeRole,
      customRoleName: customRoleName ?? this.customRoleName,
      libraryEntry: libraryEntry ?? this.libraryEntry,
      rawJson: rawJson ?? this.rawJson,
    );
  }

  Map<String, dynamic> toLibraryRecordMap() {
    return {
      'id': id,
      'name': name,
      'json_data': rawJson != null
          ? jsonEncode(rawJson)
          : jsonEncode({
              'name': name,
              'gender': gender,
              'age': age,
              'profession': profession,
              'personality': personality,
              'description': background,
            }),
      'matching_worldview_id': libraryEntry?.matchingWorldviewId ?? '',
    };
  }
}

/// 向导中统一的角色关系模型
class WizardRelationshipItem {
  String id;
  String sourceCharacterId;
  String targetCharacterId;
  String relationType;
  String customRelationName;
  String description;

  WizardRelationshipItem({
    required this.id,
    required this.sourceCharacterId,
    required this.targetCharacterId,
    this.relationType = AdventureRelationType.companion,
    this.customRelationName = '',
    this.description = '',
  });

  String get effectiveRelation =>
      AdventureRelationType.labelOf(relationType, customName: customRelationName);
}
