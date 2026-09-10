import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// 自定义属性项重要程度
enum CustomAttributeImportance {
  /// 参考
  reference('参考'),

  /// 重要参考
  important('重要参考'),

  /// 很重要参考
  veryImportant('很重要参考'),

  /// 不可忽略项
  critical('不可忽略项');

  final String label;
  const CustomAttributeImportance(this.label);

  static CustomAttributeImportance fromString(String? value) {
    if (value == null || value.trim().isEmpty) {
      return CustomAttributeImportance.reference;
    }
    final clean = value.trim();
    for (final val in CustomAttributeImportance.values) {
      if (val.label == clean || val.name == clean) return val;
    }
    return CustomAttributeImportance.reference;
  }

  /// 重要度对应的高亮颜色
  Color get color => switch (this) {
        CustomAttributeImportance.reference => const Color(0xFF8A9099),
        CustomAttributeImportance.important => AppColors.teal,
        CustomAttributeImportance.veryImportant => const Color(0xFFE67E22),
        CustomAttributeImportance.critical => const Color(0xFFE74C3C),
      };

  /// 重要度前缀图标
  IconData get icon => switch (this) {
        CustomAttributeImportance.reference => Icons.info_outline_rounded,
        CustomAttributeImportance.important => Icons.bookmark_outline_rounded,
        CustomAttributeImportance.veryImportant => Icons.star_outline_rounded,
        CustomAttributeImportance.critical => Icons.priority_high_rounded,
      };
}

/// 角色卡与 NPC 的自添加项 / 自定义检测状态
class CustomAttributeItem with Equatable {
  final String id;
  final String name;
  final String value;
  final CustomAttributeImportance importance;
  final int? currentValue;
  final int? maxValue;
  final String? icon;
  final String? description;
  final String? characterName;

  const CustomAttributeItem({
    required this.id,
    required this.name,
    required this.value,
    this.importance = CustomAttributeImportance.reference,
    this.currentValue,
    this.maxValue,
    this.icon,
    this.description,
    this.characterName,
  });

  @override
  List<Object?> get props => [
        id,
        name,
        value,
        importance,
        currentValue,
        maxValue,
        icon,
        description,
        characterName,
      ];

  CustomAttributeItem copyWith({
    String? id,
    String? name,
    String? value,
    CustomAttributeImportance? importance,
    int? currentValue,
    int? maxValue,
    String? icon,
    String? description,
    String? characterName,
  }) {
    return CustomAttributeItem(
      id: id ?? this.id,
      name: name ?? this.name,
      value: value ?? this.value,
      importance: importance ?? this.importance,
      currentValue: currentValue ?? this.currentValue,
      maxValue: maxValue ?? this.maxValue,
      icon: icon ?? this.icon,
      description: description ?? this.description,
      characterName: characterName ?? this.characterName,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'value': value,
        'importance': importance.label,
        if (currentValue != null) 'currentValue': currentValue,
        if (maxValue != null) 'maxValue': maxValue,
        if (icon != null) 'icon': icon,
        if (description != null) 'description': description,
        if (characterName != null && characterName!.trim().isNotEmpty)
          'characterName': characterName!.trim(),
      };

  factory CustomAttributeItem.fromJson(Map<String, dynamic> json) {
    final curVal = json['currentValue'] is int
        ? json['currentValue'] as int
        : (json['current_value'] is int
            ? json['current_value'] as int
            : int.tryParse(json['currentValue']?.toString() ??
                json['current_value']?.toString() ??
                ''));
    final maxVal = json['maxValue'] is int
        ? json['maxValue'] as int
        : (json['max_value'] is int
            ? json['max_value'] as int
            : int.tryParse(json['maxValue']?.toString() ??
                json['max_value']?.toString() ??
                ''));
    return CustomAttributeItem(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      value: json['value']?.toString() ?? '',
      importance: CustomAttributeImportance.fromString(
        json['importance']?.toString(),
      ),
      currentValue: curVal,
      maxValue: maxVal,
      icon: json['icon']?.toString(),
      description: json['description']?.toString(),
      characterName: json['characterName']?.toString() ??
          json['character_name']?.toString() ??
          json['character']?.toString(),
    );
  }

  /// 是否为具备数值进度条的状态
  bool get isNumeric {
    if (currentValue != null && maxValue != null && maxValue! > 0) return true;
    if (currentValue != null) return true;
    final parsed = _tryParseFraction();
    return parsed != null && parsed.$2 > 0;
  }

  (int, int)? _tryParseFraction() {
    final clean = value.trim();
    final slashIdx = clean.indexOf('/');
    if (slashIdx > 0 && slashIdx < clean.length - 1) {
      final left = int.tryParse(clean.substring(0, slashIdx).trim());
      final right = int.tryParse(clean.substring(slashIdx + 1).trim());
      if (left != null && right != null && right > 0) {
        return (left, right);
      }
    }
    // 仅在明确设置了 currentValue 时才将纯数字解析为数值（兼容旧数据），
    // 避免阶段描述型文本（如 "1" 或 "100"）被误判定为数值槽
    if (currentValue != null) {
      final singleNum = int.tryParse(clean);
      if (singleNum != null) {
        return (singleNum, maxValue ?? 100);
      }
    }
    return null;
  }

  int get effectiveCurrentValue {
    if (currentValue != null) return currentValue!;
    final parsed = _tryParseFraction();
    return parsed?.$1 ?? 0;
  }

  int get effectiveMaxValue {
    if (maxValue != null && maxValue! > 0) return maxValue!;
    final parsed = _tryParseFraction();
    return parsed?.$2 ?? 100;
  }

  double get ratio {
    final max = effectiveMaxValue;
    if (max <= 0) return 1.0;
    return (effectiveCurrentValue / max).clamp(0.0, 1.0);
  }

  /// 智能推断的图标
  String get effectiveIcon {
    if (icon != null && icon!.trim().isNotEmpty) return icon!.trim();
    final lower = name.toLowerCase();
    if (lower.contains('san') ||
        lower.contains('理智') ||
        lower.contains('精神') ||
        lower.contains('心智')) {
      return '🧠';
    }
    if (lower.contains('好感') ||
        lower.contains('心动') ||
        lower.contains('爱意') ||
        lower.contains('羁绊')) {
      return '❤️';
    }
    if (lower.contains('毒') ||
        lower.contains('感染') ||
        lower.contains('污染') ||
        lower.contains('侵蚀') ||
        lower.contains('变异')) {
      return '☣️';
    }
    if (lower.contains('饱食') ||
        lower.contains('饥饿') ||
        lower.contains('食量') ||
        lower.contains('体力')) {
      return '🍖';
    }
    if (lower.contains('魔力') ||
        lower.contains('怒气') ||
        lower.contains('火') ||
        lower.contains('狂暴')) {
      return '🔥';
    }
    if (lower.contains('灵力') ||
        lower.contains('法力') ||
        lower.contains('水分') ||
        lower.contains('口渴')) {
      return '💧';
    }
    if (lower.contains('护甲') ||
        lower.contains('护盾') ||
        lower.contains('防御') ||
        lower.contains('抗性')) {
      return '🛡️';
    }
    if (lower.contains('压力') ||
        lower.contains('过载') ||
        lower.contains('雷') ||
        lower.contains('充能')) {
      return '⚡';
    }
    if (lower.contains('堕落') ||
        lower.contains('深渊') ||
        lower.contains('认知') ||
        lower.contains('直觉')) {
      return '👁️';
    }
    return '🔍';
  }

  /// 供 LLM 提示词注入的结构化文本
  String toPromptText() {
    final cleanName = name.trim();
    final cleanValue =
        isNumeric ? '$effectiveCurrentValue/$effectiveMaxValue' : value.trim();
    final desc = description?.trim() ?? '';
    final extra = desc.isNotEmpty ? '（检测说明：$desc）' : '';
    if (cleanName.isEmpty && cleanValue.isEmpty) return '';
    if (cleanName.isEmpty) return '【${importance.label}】$cleanValue$extra';
    if (cleanValue.isEmpty) return '【${importance.label}】$cleanName$extra';
    return '【${importance.label}】$cleanName：$cleanValue$extra';
  }
}
