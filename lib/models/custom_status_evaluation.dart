import 'custom_status_change.dart';

/// 单条「状态评估」，来自模型的 `custom_status_evaluations` 协议。
///
/// 与 `custom_status_changes`（只列出发生变化的状态）的区别：每一轮都必须为
/// **全部**被追踪状态各给出一条评估，因此程序可以区分「本轮确实没变化」
/// （`changed=false`）与「模型忘了检测」（该状态整条缺失 → `unevaluated_attribute`）。
///
/// 结算规则：
/// - `changed=true` 必须落为一次状态变更；若目标非法或值非法，记诊断而不是静默丢弃。
/// - `changed=false` 不得改动状态。
/// - 一切写入仍走 parse → validate → commit，禁止直接修改。
class CustomStatusEvaluation {
  /// 与 Delta 协议同源：`CustomStatusChange.maximumChangesPerTurn`。
  static const int maximumEvaluationsPerTurn =
      CustomStatusChange.maximumChangesPerTurn;

  final String? characterId;
  final String? attributeId;
  final String? characterName;
  final String? attributeName;
  final bool changed;

  /// 仅当 `changed=true` 时非空。
  final CustomStatusChangeOperation? operation;
  final Object? value;
  final String reason;

  const CustomStatusEvaluation({
    this.characterId,
    this.attributeId,
    this.characterName,
    this.attributeName,
    required this.changed,
    this.operation,
    this.value,
    this.reason = '',
  });

  /// 用于诊断与去重的引用：优先状态引用，其次角色引用。
  String get ref =>
      attributeId ?? attributeName ?? characterId ?? characterName ?? '?';

  /// 把一条 `changed=true` 的评估转成正式的 Delta 变更。
  ///
  /// 只有解析成功的 `changed=true` 项才会走到这里，因此 [operation] 与
  /// [value] 必然非空。
  CustomStatusChange toChange() => CustomStatusChange(
        characterId: characterId,
        attributeId: attributeId,
        characterName: characterName,
        attributeName: attributeName,
        operation: operation!,
        value: value,
        reason: reason,
      );

  /// 解析 `custom_status_evaluations` 原始负载。
  ///
  /// 每一类失败都会写入 [diagnostics]，绝不静默丢弃。
  static List<CustomStatusEvaluation> parse(
    Object? raw, {
    required List<String> diagnostics,
  }) {
    if (raw == null) return const [];
    if (raw is! List) {
      diagnostics.add('custom_status_evaluations:type');
      return const [];
    }

    final evaluations = <CustomStatusEvaluation>[];
    for (final item in raw.take(maximumEvaluationsPerTurn)) {
      if (item is! Map) {
        diagnostics.add('custom_status_evaluations:item');
        continue;
      }
      final map = Map<String, dynamic>.from(item);
      final characterId = CustomStatusChange.normalizeRef(
          map['character_id'] ?? map['characterId']);
      final attributeId = CustomStatusChange.normalizeRef(
          map['attribute_id'] ?? map['attributeId']);
      final characterName = CustomStatusChange.normalizeRef(
          map['character_name'] ?? map['characterName']);
      final attributeName = CustomStatusChange.normalizeRef(
          map['attribute_name'] ?? map['attributeName']);
      final reason = map['reason']?.toString().trim() ?? '';
      final ref =
          attributeId ?? attributeName ?? characterId ?? characterName ?? '?';

      final operation = CustomStatusChange.parseOperation(map['operation']);
      final value = map['value'];
      final changed = _parseChanged(
        map['changed'],
        hasMutation: map.containsKey('operation') || map.containsKey('value'),
      );
      if (changed == null) {
        diagnostics.add('invalid_evaluation:$ref');
        continue;
      }

      if (!changed) {
        if (attributeId == null && attributeName == null) {
          // 没有目标的状态评估是无意义的：无法据此判断哪个状态被检测过。
          diagnostics.add('invalid_evaluation:$ref');
          continue;
        }
        evaluations.add(CustomStatusEvaluation(
          characterId: characterId,
          attributeId: attributeId,
          characterName: characterName,
          attributeName: attributeName,
          changed: false,
          reason: reason,
        ));
        continue;
      }

      if (attributeId == null && attributeName == null) {
        diagnostics.add('invalid_evaluation:$ref');
        continue;
      }
      if (operation == null) {
        diagnostics.add('invalid_operation:$ref');
        continue;
      }
      if (!CustomStatusChange.isValidValueFor(operation, value)) {
        diagnostics.add(operation == CustomStatusChangeOperation.delta
            ? 'invalid_delta_value:$ref'
            : 'invalid_value:$ref');
        continue;
      }

      evaluations.add(CustomStatusEvaluation(
        characterId: characterId,
        attributeId: attributeId,
        characterName: characterName,
        attributeName: attributeName,
        changed: true,
        operation: operation,
        value: value,
        reason: reason,
      ));
    }

    if (raw.length > maximumEvaluationsPerTurn) {
      diagnostics.add('custom_status_evaluations:limit');
    }
    return List.unmodifiable(evaluations);
  }

  /// 宽容解析 `changed`：接受 bool / 0-1 数字 / 中英文常见写法。
  ///
  /// `changed` 整条缺失时，若该项已经带了 operation/value，则视为 `true`
  /// （模型的意图显然是「有变化」）；否则无法判定，返回 null 记诊断。
  static bool? _parseChanged(Object? value, {required bool hasMutation}) {
    if (value == null) return hasMutation ? true : null;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = value.toString().trim().toLowerCase();
    if (text.isEmpty) return hasMutation ? true : null;
    const truthy = {'true', 'yes', '1', '是', '有', '变化', '有变化'};
    const falsy = {'false', 'no', '0', '否', '无', '不变', '无变化'};
    if (truthy.contains(text)) return true;
    if (falsy.contains(text)) return false;
    return null;
  }
}
