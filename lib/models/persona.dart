import 'dart:convert';
import 'package:equatable/equatable.dart';

class Persona with Equatable {
  final String id;
  final String name;
  final String description;
  final String personality;
  final String appearance;
  final String notes;
  final bool isDefault;

  Persona({
    String? id,
    this.name = '',
    this.description = '',
    this.personality = '',
    this.appearance = '',
    this.notes = '',
    this.isDefault = false,
  }) : id = id ?? DateTime.now().millisecondsSinceEpoch.toString();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'personality': personality,
        'appearance': appearance,
        'notes': notes,
        'is_default': isDefault,
      };

  factory Persona.fromJson(Map<String, dynamic> json) {
    return Persona(
      id: json['id'] as String?,
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      personality: json['personality'] as String? ?? '',
      appearance: json['appearance'] as String? ?? '',
      notes: json['notes'] as String? ?? '',
      isDefault: json['is_default'] as bool? ?? false,
    );
  }

  @override
  List<Object?> get props => [id];

  Persona copyWith({
    String? id,
    String? name,
    String? description,
    String? personality,
    String? appearance,
    String? notes,
    bool? isDefault,
  }) {
    return Persona(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      personality: personality ?? this.personality,
      appearance: appearance ?? this.appearance,
      notes: notes ?? this.notes,
      isDefault: isDefault ?? this.isDefault,
    );
  }

  String toPromptString() {
    final buf = StringBuffer();
    buf.writeln('=== 玩家角色设定 ===');
    if (name.isNotEmpty) buf.writeln('- 姓名：$name');
    if (description.isNotEmpty) buf.writeln('- 描述：$description');
    if (personality.isNotEmpty) buf.writeln('- 性格：$personality');
    if (appearance.isNotEmpty) buf.writeln('- 外貌：$appearance');
    if (notes.isNotEmpty) buf.writeln('- 备注：$notes');
    return buf.toString();
  }
}

class PersonaStorage {
  static const _key = 'personas';
  static const _activeKey = 'active_persona_id';

  static String encode(List<Persona> personas) =>
      jsonEncode(personas.map((p) => p.toJson()).toList());

  static List<Persona> decode(String jsonStr) {
    try {
      final list = jsonDecode(jsonStr) as List<dynamic>;
      return list
          .map((e) => Persona.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static String get storageKey => _key;
  static String get activeKey => _activeKey;
}
