import 'dart:convert';
import '../../models/character_card.dart';
import '../../models/adventure_config.dart';

class AdventureContextPolicy {
  /// 提取多重可能的属性名称
  static String _readCardText(Map<String, dynamic> data, List<String> keys) {
    for (final k in keys) {
      if (data[k] is String && data[k].toString().isNotEmpty) {
        return data[k].toString();
      }
    }
    return '';
  }

  /// 构建完整的角色上下文，供 AI 生成 NPC/开场时使用
  static Map<String, String> buildCharacterContext({
    AdventureSelectedCharacter? protagonistBinding,
    List<Map<String, dynamic>> characterCards = const [],
    String manualName = '',
    String manualAge = '',
    String manualRole = '',
    String manualPersonality = '',
    String manualBackground = '',
    String manualAppearance = '',
  }) {
    var name = '';
    var age = '';
    var role = '';
    var personality = '';
    var background = '';
    var bodyDescription = '';
    var appearance = '';

    if (protagonistBinding != null) {
      final cardRow = characterCards
          .where((c) => c['id'] == protagonistBinding.characterId)
          .firstOrNull;
      if (cardRow != null) {
        try {
          final data = jsonDecode(cardRow['json_data'] as String? ?? '{}')
              as Map<String, dynamic>;
          final cardData = data['data'] is Map<String, dynamic>
              ? data['data'] as Map<String, dynamic>
              : data;
          final card = CharacterCard.fromJson(data);
          name = card.name;
          age = cardData['age']?.toString() ?? '';
          role = cardData['profession'] as String? ??
              cardData['occupation'] as String? ??
              protagonistBinding.effectiveRole;
          personality = card.personality;
          background = card.description.isNotEmpty
              ? card.description
              : (cardData['background'] as String? ??
                  cardData['description'] as String? ??
                  '');
          bodyDescription = card.bodyDescription;
          appearance = card.appearance;
        } catch (_) {}
      } else {
        final data =
            protagonistBinding.characterCardJson ?? const <String, dynamic>{};
        final cardData = data['data'] is Map<String, dynamic>
            ? data['data'] as Map<String, dynamic>
            : data;
        name = protagonistBinding.characterName;
        age = cardData['age']?.toString() ?? '';
        role = cardData['profession'] as String? ??
            protagonistBinding.effectiveRole;
        personality = cardData['personality'] as String? ?? '';
        background = cardData['background'] as String? ??
            cardData['description'] as String? ??
            '';
        bodyDescription = _readCardText(cardData, const [
          'bodyDescription',
          'body_description',
          'physique',
          'figureDescription',
          'bodyShape',
          'bodyType',
          'physicalDescription',
          'appearanceDetail',
          'lookDescription',
        ]);
        appearance = cardData['appearance'] as String? ?? '';
      }
    } else {
      name = manualName;
      age = manualAge;
      role = manualRole;
      personality = manualPersonality;
      background = manualBackground;
      appearance = manualAppearance;
    }
    return {
      'name': name,
      'age': age,
      'role': role,
      'personality': personality,
      'background': background,
      'bodyDescription': bodyDescription,
      'appearance': appearance,
    };
  }
}
