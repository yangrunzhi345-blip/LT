/// Delta 协议下的单条状态变更。
///
/// AI 只返回本轮真正发生变化的状态，程序以本地完整状态为基线应用这些变更。
/// `character_id` / `attribute_id` 是稳定引用；历史数据没有稳定 ID 时，可回退到
/// `character_name` / `attribute_name` 名称匹配。
enum CustomStatusChangeOperation { set, delta }

class CustomStatusChange {
  static const int maximumChangesPerTurn = 64;

  final String? characterId;
  final String? attributeId;
  final String? characterName;
  final String? attributeName;
  final CustomStatusChangeOperation operation;
  final Object? value;

  const CustomStatusChange({
    this.characterId,
    this.attributeId,
    this.characterName,
    this.attributeName,
    required this.operation,
    required this.value,
  });

  /// 解析 `custom_status_changes` 原始负载，丢弃非法项并写入 diagnostics。
  static List<CustomStatusChange> parse(
    Object? raw, {
    required List<String> diagnostics,
  }) {
    if (raw == null) return const [];
    if (raw is! List) {
      diagnostics.add('custom_status_changes:type');
      return const [];
    }
    final changes = <CustomStatusChange>[];
    for (final item in raw.take(maximumChangesPerTurn)) {
      if (item is! Map) {
        diagnostics.add('custom_status_changes:item');
        continue;
      }
      final map = Map<String, dynamic>.from(item);
      final characterId =
          normalizeRef(map['character_id'] ?? map['characterId']);
      final attributeId =
          normalizeRef(map['attribute_id'] ?? map['attributeId']);
      final characterName =
          normalizeRef(map['character_name'] ?? map['characterName']);
      final attributeName =
          normalizeRef(map['attribute_name'] ?? map['attributeName']);
      final operation = parseOperation(map['operation']);
      final value = map['value'];

      final hasAttributeRef = attributeId != null || attributeName != null;
      final isValidValue = isValidValueFor(operation, value);
      if (operation == null || !hasAttributeRef || !isValidValue) {
        diagnostics.add('custom_status_changes:invalid');
        continue;
      }

      changes.add(CustomStatusChange(
        characterId: characterId,
        attributeId: attributeId,
        characterName: characterName,
        attributeName: attributeName,
        operation: operation,
        value: _copyValue(value),
      ));
    }
    if (raw.length > maximumChangesPerTurn) {
      diagnostics.add('custom_status_changes:limit');
    }
    return List.unmodifiable(changes);
  }

  /// 解析 operation 字段。缺失/空串按历史行为默认为 `set`；无法识别返回 null。
  ///
  /// 公开给 `CustomStatusEvaluation` 复用，保证两套协议对 operation 的判定一致。
  static CustomStatusChangeOperation? parseOperation(Object? value) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) return CustomStatusChangeOperation.set;
    for (final op in CustomStatusChangeOperation.values) {
      if (op.name == text) return op;
    }
    return null;
  }

  /// 校验 value 与 operation 是否匹配。公开给 `CustomStatusEvaluation` 复用。
  static bool isValidValueFor(
      CustomStatusChangeOperation? operation, Object? value) {
    if (value == null) return false;
    if (value is num) return true;
    if (value is String) {
      final text = value.trim();
      if (text.isEmpty) return false;
      if (text.length > 1000) return false;
      // delta 只能作用于数值（允许模型把数字写成字符串）。
      if (operation == CustomStatusChangeOperation.delta) {
        return parseNumericDelta(value) != null;
      }
      return true;
    }
    return false;
  }

  /// 把 delta 值解析成整数增量。
  ///
  /// 模型经常把数字写成带引号的字符串（`"3"` / `"+3"` / `"-2"`），这类输入
  /// 之前会被整体丢弃，导致状态面板保持旧值。返回 null 表示不是合法增量。
  static int? parseNumericDelta(Object? value) {
    if (value is num) return value.toInt();
    if (value is! String) return null;
    var text = value.trim();
    if (text.isEmpty || text.length > 1000) return null;
    if (text.startsWith('+')) text = text.substring(1).trim();
    return int.tryParse(text);
  }

  /// 归一化引用字段：空串按缺失处理。
  static String? normalizeRef(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  static Object? _copyValue(Object? value) => value;
}
