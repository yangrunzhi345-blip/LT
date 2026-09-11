import '../models/custom_attribute_item.dart';
import '../models/custom_status_change.dart';
import '../models/supporting_character.dart';

/// 一次状态合并的输出。
class CustomStatusMergeResult {
  final List<CustomAttributeItem> protagonistAttributes;
  final List<SupportingCharacter> supportingCharacters;
  final List<String> diagnostics;

  const CustomStatusMergeResult({
    required this.protagonistAttributes,
    required this.supportingCharacters,
    this.diagnostics = const [],
  });
}

/// 纯函数合并器：把 AI 返回的 Delta（或旧版完整快照）应用到本地完整状态基线。
///
/// 不依赖 ChatEngine，便于单元测试与复用。稳定 ID 优先匹配，名称匹配仅作 fallback。
class CustomStatusMerger {
  const CustomStatusMerger._();

  /// 应用 Delta（`custom_status_changes`）。
  ///
  /// 仅更新出现在 changes 中的状态，未出现项保持原值不变。未知目标记入
  /// diagnostics，不误更新其他状态。
  static CustomStatusMergeResult applyChanges({
    required String protagonistName,
    required String? protagonistId,
    required List<CustomAttributeItem> protagonistAttributes,
    required List<SupportingCharacter> supportingCharacters,
    required List<CustomStatusChange> changes,
  }) {
    final diagnostics = <String>[];
    final protoList = List<CustomAttributeItem>.from(protagonistAttributes);
    final scList = List<SupportingCharacter>.from(supportingCharacters);

    for (final change in changes) {
      final target = _resolveTarget(
        change: change,
        protagonistName: protagonistName,
        protagonistId: protagonistId,
        protagonistAttributes: protoList,
        supportingCharacters: scList,
      );
      if (target == null) {
        diagnostics
            .add('unknown:${change.characterId ?? change.characterName ?? '?'}:'
                '${change.attributeId ?? change.attributeName ?? '?'}');
        continue;
      }
      final updated = _applyChange(target.attribute, change);
      if (updated == null) {
        diagnostics.add('invalid_op:${target.attribute.name}');
        continue;
      }
      if (target.isProtagonist) {
        protoList[target.attrIndex] = updated;
      } else {
        final sc = scList[target.characterIndex];
        final newAttrs = List<CustomAttributeItem>.from(sc.customAttributes);
        newAttrs[target.attrIndex] = updated;
        scList[target.characterIndex] = sc.copyWith(customAttributes: newAttrs);
      }
    }

    return CustomStatusMergeResult(
      protagonistAttributes: protoList,
      supportingCharacters: scList,
      diagnostics: diagnostics,
    );
  }

  /// 应用旧版完整快照（`custom_status`），保留历史「好感度→affinity」启发式。
  ///
  /// 与迁移前 `ChatEngine._syncCustomStatusUpdates` 行为一致。
  static CustomStatusMergeResult applyLegacySnapshot({
    required String protagonistName,
    required List<CustomAttributeItem> protagonistAttributes,
    required List<SupportingCharacter> supportingCharacters,
    required List<CustomAttributeItem> snapshot,
  }) {
    if (snapshot.isEmpty) {
      return CustomStatusMergeResult(
        protagonistAttributes:
            List<CustomAttributeItem>.from(protagonistAttributes),
        supportingCharacters:
            List<SupportingCharacter>.from(supportingCharacters),
      );
    }

    final updatedProtagonistAttrs = protagonistAttributes.map((cur) {
      final matched = snapshot
          .where((s) =>
              s.name.trim() == cur.name.trim() &&
              _namesMatch(s.characterName, protagonistName,
                  isProtagonist: true))
          .firstOrNull;
      return matched != null ? _applyLegacyUpdate(cur, matched) : cur;
    }).toList();

    final updatedSupportingChars = supportingCharacters.map((sc) {
      if (!sc.isAlive) return sc;
      final scName = sc.name.trim();
      var scAffinity = sc.affinity;

      final directAffinityUpdate = snapshot.where((s) {
        final n = s.name.trim().toLowerCase();
        if (!n.contains('好感') && !n.contains('affinity')) return false;
        return _namesMatch(s.characterName, scName, isProtagonist: false);
      }).firstOrNull;
      if (directAffinityUpdate != null) {
        if (directAffinityUpdate.currentValue != null) {
          scAffinity = directAffinityUpdate.currentValue!.clamp(0, 100);
        } else if (directAffinityUpdate.isNumeric) {
          scAffinity = directAffinityUpdate.effectiveCurrentValue.clamp(0, 100);
        }
      }

      final updatedAttrs = sc.customAttributes.map((cur) {
        final matched = snapshot
            .where((s) =>
                s.name.trim() == cur.name.trim() &&
                _namesMatch(s.characterName, scName, isProtagonist: false))
            .firstOrNull;
        return matched != null ? _applyLegacyUpdate(cur, matched) : cur;
      }).toList();

      return sc.copyWith(
        customAttributes: updatedAttrs,
        affinity: scAffinity,
      );
    }).toList();

    return CustomStatusMergeResult(
      protagonistAttributes: updatedProtagonistAttrs,
      supportingCharacters: updatedSupportingChars,
    );
  }

  // ─── Delta target resolution ───

  static _Target? _resolveTarget({
    required CustomStatusChange change,
    required String protagonistName,
    required String? protagonistId,
    required List<CustomAttributeItem> protagonistAttributes,
    required List<SupportingCharacter> supportingCharacters,
  }) {
    final characterIndex = _matchCharacter(
      change: change,
      protagonistName: protagonistName,
      protagonistId: protagonistId,
      supportingCharacters: supportingCharacters,
    );
    if (characterIndex == null) return null;

    if (characterIndex < 0) {
      final attrIndex = _findAttributeIndex(protagonistAttributes, change);
      if (attrIndex < 0) return null;
      return _Target(
        isProtagonist: true,
        characterIndex: -1,
        attrIndex: attrIndex,
        attribute: protagonistAttributes[attrIndex],
      );
    }

    final attrs = supportingCharacters[characterIndex].customAttributes;
    final attrIndex = _findAttributeIndex(attrs, change);
    if (attrIndex < 0) return null;
    return _Target(
      isProtagonist: false,
      characterIndex: characterIndex,
      attrIndex: attrIndex,
      attribute: attrs[attrIndex],
    );
  }

  /// 返回角色索引：-1 = 主角，>=0 = 配角索引，null = 未匹配。
  static int? _matchCharacter({
    required CustomStatusChange change,
    required String protagonistName,
    required String? protagonistId,
    required List<SupportingCharacter> supportingCharacters,
  }) {
    final cid = change.characterId;
    final cname = change.characterName;

    if (cid != null) {
      if (protagonistId != null && cid == protagonistId) return -1;
      for (var i = 0; i < supportingCharacters.length; i++) {
        if (supportingCharacters[i].id == cid) return i;
      }
      if (cname == null) return null; // id 未命中且无名称 fallback
    }
    if (cname != null) {
      if (_namesMatch(cname, protagonistName, isProtagonist: true)) {
        return -1;
      }
      for (var i = 0; i < supportingCharacters.length; i++) {
        if (_namesMatch(cname, supportingCharacters[i].name,
            isProtagonist: false)) {
          return i;
        }
      }
      return null;
    }
    // 既无 id 也无名称 → 默认主角
    return -1;
  }

  static int _findAttributeIndex(
      List<CustomAttributeItem> attrs, CustomStatusChange change) {
    final aid = change.attributeId;
    if (aid != null) {
      for (var i = 0; i < attrs.length; i++) {
        if (attrs[i].id.isNotEmpty && attrs[i].id == aid) return i;
      }
    }
    final aname = change.attributeName;
    if (aname != null) {
      for (var i = 0; i < attrs.length; i++) {
        if (attrs[i].name.trim() == aname.trim()) return i;
      }
    }
    return -1;
  }

  static CustomAttributeItem? _applyChange(
      CustomAttributeItem cur, CustomStatusChange change) {
    switch (change.operation) {
      case CustomStatusChangeOperation.set:
        return _applySet(cur, change.value);
      case CustomStatusChangeOperation.delta:
        if (change.value is! num || !cur.isNumeric) return null;
        final delta = (change.value as num).toInt();
        final base = cur.currentValue ?? cur.effectiveCurrentValue;
        final max = cur.effectiveMaxValue;
        final newCur = (base + delta).clamp(0, max);
        return cur.copyWith(currentValue: newCur, value: '$newCur/$max');
    }
  }

  static CustomAttributeItem _applySet(CustomAttributeItem cur, Object? value) {
    if (value is num) {
      final max = cur.effectiveMaxValue;
      final newCur = value.toInt().clamp(0, max);
      final newValue = cur.isNumeric ? '$newCur/$max' : newCur.toString();
      return cur.copyWith(currentValue: newCur, value: newValue);
    }
    final text = value.toString().trim();
    if (text.isEmpty) return cur;
    if (cur.isNumeric) {
      final parsed = _parseNumericText(text);
      if (parsed != null) {
        final max = cur.effectiveMaxValue;
        final newCur = parsed.clamp(0, max);
        return cur.copyWith(currentValue: newCur, value: '$newCur/$max');
      }
    }
    // 文本/阶段状态：仅事实变化才覆盖，禁止同值措辞覆盖。
    if (text == cur.value.trim()) return cur;
    return cur.copyWith(value: text);
  }

  static int? _parseNumericText(String text) {
    final direct = int.tryParse(text.trim());
    if (direct != null) return direct;
    final slash = text.indexOf('/');
    if (slash > 0) {
      final left = int.tryParse(text.substring(0, slash).trim());
      if (left != null) return left;
    }
    return null;
  }

  // ─── Legacy snapshot apply ───

  static CustomAttributeItem _applyLegacyUpdate(
      CustomAttributeItem cur, CustomAttributeItem update) {
    final newCurrent = update.currentValue ?? cur.currentValue;
    final newMax = update.maxValue ?? cur.maxValue;
    String newValue = update.value.isNotEmpty ? update.value : cur.value;
    if (cur.isNumeric && newCurrent != null && !newValue.contains('/')) {
      final maxVal = newMax ?? cur.effectiveMaxValue;
      newValue = '$newCurrent/$maxVal';
    }
    return cur.copyWith(
      currentValue: newCurrent,
      maxValue: newMax,
      value: newValue,
    );
  }

  static bool _namesMatch(String? candidate, String targetFullName,
      {required bool isProtagonist}) {
    if (candidate == null || candidate.trim().isEmpty) return isProtagonist;
    final c = candidate.trim().toLowerCase();
    final target = targetFullName.trim().toLowerCase();
    if (c == target) return true;
    if (isProtagonist && (c == '主角' || c == '玩家' || c == '自身' || c == '我')) {
      return true;
    }
    if (!isProtagonist && (c == '同伴' || c == '配角' || c == '队友')) {
      return true;
    }
    final targetFirstName = target.split('·').first.trim();
    if (targetFirstName.isNotEmpty &&
        (c == targetFirstName ||
            c.contains(targetFirstName) ||
            targetFirstName.contains(c))) {
      return true;
    }
    return target.contains(c) || c.contains(target);
  }
}

class _Target {
  final bool isProtagonist;
  final int characterIndex;
  final int attrIndex;
  final CustomAttributeItem attribute;

  const _Target({
    required this.isProtagonist,
    required this.characterIndex,
    required this.attrIndex,
    required this.attribute,
  });
}
