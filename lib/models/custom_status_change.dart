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
      final characterId = _text(map['character_id'] ?? map['characterId']);
      final attributeId = _text(map['attribute_id'] ?? map['attributeId']);
      final characterName =
          _text(map['character_name'] ?? map['characterName']);
      final attributeName =
          _text(map['attribute_name'] ?? map['attributeName']);
      final operation = _parseOperation(map['operation']);
      final value = map['value'];

      final hasAttributeRef = attributeId != null || attributeName != null;
      final isValidValue = _isValidValue(operation, value);
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

  static CustomStatusChangeOperation? _parseOperation(Object? value) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) return CustomStatusChangeOperation.set;
    for (final op in CustomStatusChangeOperation.values) {
      if (op.name == text) return op;
    }
    return null;
  }

  static bool _isValidValue(
      CustomStatusChangeOperation? operation, Object? value) {
    if (value == null) return false;
    if (value is num) return true;
    if (value is String) {
      final text = value.trim();
      if (text.isEmpty) return false;
      if (text.length > 1000) return false;
      // delta 只能作用于数值。
      if (operation == CustomStatusChangeOperation.delta) return false;
      return true;
    }
    return false;
  }

  static String? _text(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  static Object? _copyValue(Object? value) => value;
}
