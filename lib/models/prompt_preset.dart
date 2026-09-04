import 'dart:convert';
import 'translation_mode.dart';
export 'translation_mode.dart';
import 'llm_provider.dart';
import 'completion_params.dart';
import 'package:equatable/equatable.dart';

class PromptPreset with Equatable {
  final String id;
  final String name;
  final String systemPrompt;
  final String authorsNote;
  final int authorsNoteDepth;
  final int authorsNoteFrequency;
  final TranslationMode translationMode;
  final LLMProvider? provider;
  final String? model;
  final CompletionParams? completionParams;
  final DateTime? createdAt;

  PromptPreset({
    String? id,
    this.name = '',
    this.systemPrompt = '',
    this.authorsNote = '',
    this.authorsNoteDepth = 3,
    this.authorsNoteFrequency = 3,
    this.translationMode = TranslationMode.off,
    this.provider,
    this.model,
    this.completionParams,
    DateTime? createdAt,
  })  : id = id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'system_prompt': systemPrompt,
        'authors_note': authorsNote,
        'authors_note_depth': authorsNoteDepth,
        'authors_note_frequency': authorsNoteFrequency,
        'translation_mode': translationMode.index,
        'provider': provider?.name,
        'model': model,
        'completion_params': completionParams?.toJson(),
        'created_at': createdAt?.toIso8601String(),
      };

  factory PromptPreset.fromJson(Map<String, dynamic> json) {
    return PromptPreset(
      id: json['id'] as String?,
      name: json['name'] as String? ?? '',
      systemPrompt: json['system_prompt'] as String? ?? '',
      authorsNote: json['authors_note'] as String? ?? '',
      authorsNoteDepth: json['authors_note_depth'] as int? ?? 3,
      authorsNoteFrequency: json['authors_note_frequency'] as int? ?? 3,
      translationMode:
          TranslationMode.values[json['translation_mode'] as int? ?? 0],
      provider: json['provider'] != null
          ? LLMProvider.values.firstWhere(
              (p) => p.name == json['provider'],
              orElse: () => LLMProvider.deepseek,
            )
          : null,
      model: json['model'] as String?,
      completionParams: json['completion_params'] != null
          ? CompletionParams.fromJson(
              json['completion_params'] as Map<String, dynamic>)
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
    );
  }

  PromptPreset copyWith({
    String? id,
    String? name,
    String? systemPrompt,
    String? authorsNote,
    int? authorsNoteDepth,
    int? authorsNoteFrequency,
    TranslationMode? translationMode,
    LLMProvider? provider,
    String? model,
    CompletionParams? completionParams,
    DateTime? createdAt,
  }) =>
      PromptPreset(
        id: id ?? this.id,
        name: name ?? this.name,
        systemPrompt: systemPrompt ?? this.systemPrompt,
        authorsNote: authorsNote ?? this.authorsNote,
        authorsNoteDepth: authorsNoteDepth ?? this.authorsNoteDepth,
        authorsNoteFrequency: authorsNoteFrequency ?? this.authorsNoteFrequency,
        translationMode: translationMode ?? this.translationMode,
        provider: provider ?? this.provider,
        model: model ?? this.model,
        completionParams: completionParams ?? this.completionParams,
        createdAt: createdAt ?? this.createdAt,
      );

  String toJsonString() => jsonEncode(toJson());

  factory PromptPreset.fromJsonString(String s) {
    return PromptPreset.fromJson(jsonDecode(s));
  }

  /// 导出全部预设为 JSON 字符串（用于分享/备份）
  static String exportAllToJson(List<PromptPreset> presets) {
    return const JsonEncoder.withIndent('  ')
        .convert(presets.map((p) => p.toJson()).toList());
  }

  /// 从 JSON 字符串批量导入预设
  static List<PromptPreset> importFromJson(String jsonStr) {
    final decoded = jsonDecode(jsonStr);
    List<dynamic> list;
    if (decoded is List) {
      list = decoded;
    } else if (decoded is Map && decoded.containsKey('presets')) {
      list = decoded['presets'] as List<dynamic>;
    } else {
      return [];
    }
    return list
        .map((e) => PromptPreset.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 对预设内容进行模板变量替换
  String expandTemplate(Map<String, String> variables) {
    var text = '$systemPrompt\n\n$authorsNote';
    for (final entry in variables.entries) {
      text = text.replaceAll('{${entry.key}}', entry.value);
    }
    return text;
  }

  @override
  List<Object?> get props => [id];
}

class PresetManager {
  static const _key = 'prompt_presets';

  static Future<List<PromptPreset>> loadPresets({
    required Future<String?> Function(String) getString,
  }) async {
    final jsonStr = await getString(_key);
    if (jsonStr == null || jsonStr.isEmpty) {
      return _defaultPresets();
    }
    try {
      final list = jsonDecode(jsonStr) as List<dynamic>;
      return list
          .map((e) => PromptPreset.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return _defaultPresets();
    }
  }

  static Future<void> savePresets(
    List<PromptPreset> presets, {
    required Future<void> Function(String, String) setString,
  }) async {
    final jsonStr = jsonEncode(presets.map((p) => p.toJson()).toList());
    await setString(_key, jsonStr);
  }

  static List<PromptPreset> _defaultPresets() => [
        PromptPreset(
          name: '默认冒险',
          systemPrompt: '',
          authorsNote: '',
        ),
        PromptPreset(
          name: '沉浸叙事',
          systemPrompt: '你是一位精通叙事艺术的故事大师。请使用丰富的环境描写、心理刻画和感官细节来推进剧情。',
          authorsNote: '保持沉浸式叙事风格，注重氛围营造。',
          authorsNoteDepth: 0,
        ),
        PromptPreset(
          name: '简洁快节奏',
          systemPrompt: '你是一位善于快节奏冒险的故事讲述者。请保持叙事紧凑，减少冗长描写，强调行动和决策。',
          authorsNote: '加快节奏，每段不超过100字。',
          authorsNoteDepth: 0,
          authorsNoteFrequency: 5,
        ),
      ];
}
