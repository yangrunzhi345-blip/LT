import '../../models/adventure_config.dart';
import '../../models/custom_attribute_item.dart';
import '../../models/supporting_character.dart';
import 'adventure_character_identity.dart';

/// Adventure 自有角色检测状态定义的唯一持久化权威。
///
/// 定义层只存在两处：主角落在 [AdventureConfig.customAttributes]，同伴落在
/// [SupportingCharacter.customAttributes]。这里只写入 Adventure 自己的冻结/运行
/// 快照，绝不回写资料库角色卡；剧情产生的运行值属于
/// `adventure_runtime_entities`，会在落库前由
/// `AdventureRuntimeStateResolver.baselineForPersistence` 还原，不在这里维护。
final class AdventureCharacterStatusStore {
  const AdventureCharacterStatusStore._();

  /// 为 [items] 绑定所属角色名，使 `allTrackedCustomAttributes` 与提示词都能
  /// 把每个状态归属到正确角色。已经带角色名的项保持不变。
  static List<CustomAttributeItem> bindCharacterName(
    List<CustomAttributeItem> items,
    String characterName,
  ) {
    final name = characterName.trim();
    return items
        .map((item) => item.characterName?.trim().isNotEmpty ?? false
            ? item
            : item.copyWith(characterName: name))
        .toList();
  }

  /// 解析同时镜像到 [SupportingCharacter.affinity] 的「好感度」槽位。
  ///
  /// 列表里没有好感度类状态时返回 null，调用方应保留原 affinity，避免误清零。
  static int? resolveAffinity(List<CustomAttributeItem> items) {
    for (final item in items) {
      final lower = item.name.toLowerCase();
      if (!item.name.contains('好感') && !lower.contains('affinity')) {
        continue;
      }
      if (item.currentValue != null) return item.currentValue!.clamp(0, 100);
      if (item.isNumeric) return item.effectiveCurrentValue.clamp(0, 100);
    }
    return null;
  }

  /// 把 [customAttributes] 写入当前选中同伴的持久化快照。
  ///
  /// 已存在快照时原地更新；不存在时新建一个 Adventure 自有的
  /// [SupportingCharacter] 快照追加进 `supportingCharacters`。新版组装冒险
  /// 可以只有 `selectedCharacters` 而没有对应快照，此时必须补建，否则这次编辑
  /// 不会进入 `adventures.config`。
  static AdventureConfig writeCompanionCustomAttributes({
    required AdventureConfig config,
    required AdventureSelectedCharacter? selected,
    required String fallbackId,
    required String name,
    required String role,
    required List<CustomAttributeItem> customAttributes,
  }) {
    final tagged = bindCharacterName(customAttributes, name);
    final affinity = resolveAffinity(tagged);
    final characters =
        List<SupportingCharacter>.from(config.supportingCharacters);
    final index = _locate(
      characters,
      selected: selected,
      fallbackId: fallbackId,
      name: name,
    );
    if (index >= 0) {
      final existing = characters[index];
      characters[index] = existing.copyWith(
        id: _convergeId(existing.id, selected),
        customAttributes: tagged,
        affinity: affinity ?? existing.affinity,
      );
    } else {
      characters.add(_newSnapshot(
        config: config,
        selected: selected,
        fallbackId: fallbackId,
        name: name,
        role: role,
        customAttributes: tagged,
        affinity: affinity,
      ));
    }
    return config.copyWith(supportingCharacters: characters);
  }

  /// 定位持久化快照：稳定 ID 优先，只有完全没有稳定 ID 的历史选择行才允许按
  /// 名称匹配。
  static int _locate(
    List<SupportingCharacter> characters, {
    required AdventureSelectedCharacter? selected,
    required String fallbackId,
    required String name,
  }) {
    if (selected != null) {
      final index =
          AdventureCharacterIdentity.indexOfSupporting(characters, selected);
      if (index >= 0) return index;
    }
    final fallback = fallbackId.trim();
    if (fallback.isNotEmpty) {
      final index = characters.indexWhere((c) => c.id.trim() == fallback);
      if (index >= 0) return index;
    }
    // 旧数据兼容：该选择行从未有稳定 ID 时，名称是旧数据唯一的键。
    if (selected != null && !AdventureCharacterIdentity.hasStableId(selected)) {
      final trimmed = name.trim();
      if (trimmed.isNotEmpty) {
        return characters.indexWhere((c) => c.name.trim() == trimmed);
      }
    }
    return -1;
  }

  /// 让持久化快照的 ID 收敛到运行期实体使用的稳定 ID。
  ///
  /// 历史数据可能把快照写在 `selected.id` 上而运行期实体写在
  /// `selected.characterId` 上；不收敛就会出现「状态定义与 overlay 无法关联」。
  static String _convergeId(
    String existingId,
    AdventureSelectedCharacter? selected,
  ) {
    if (selected == null) return existingId;
    final canonical = AdventureCharacterIdentity.effectiveId(selected);
    return canonical.isNotEmpty ? canonical : existingId;
  }

  static SupportingCharacter _newSnapshot({
    required AdventureConfig config,
    required AdventureSelectedCharacter? selected,
    required String fallbackId,
    required String name,
    required String role,
    required List<CustomAttributeItem> customAttributes,
    required int? affinity,
  }) {
    final id =
        _persistentId(selected, fallbackId: fallbackId, name: name, role: role);
    final card = selected?.characterCardJson;
    // 复用模型自己的解析器，而不是逐字段手工搬运角色卡；快照只覆盖身份、
    // 本次编辑的状态列表，以及冻结关系表里能可靠解析出的 relation。
    final base = card != null
        ? SupportingCharacter.fromJson({
            ...card,
            'id': id,
            'name': name,
            'role': role,
          })
        : SupportingCharacter(id: id, name: name, role: role);
    final derivedRelation = selected == null
        ? ''
        : AdventureCharacterIdentity.resolveRelation(
            config: config,
            selected: selected,
          );
    return base.copyWith(
      id: id,
      name: name,
      role: role,
      relation: derivedRelation.isNotEmpty ? derivedRelation : base.relation,
      affinity: affinity ?? base.affinity,
      customAttributes: customAttributes,
    );
  }

  static String _persistentId(
    AdventureSelectedCharacter? selected, {
    required String fallbackId,
    required String name,
    required String role,
  }) {
    if (selected != null) {
      final id = AdventureCharacterIdentity.effectiveId(selected);
      if (id.isNotEmpty) return id;
      return SupportingCharacter.legacyIdFor(name: name, role: role);
    }
    final trimmed = fallbackId.trim();
    if (trimmed.isNotEmpty) return trimmed;
    return SupportingCharacter.legacyIdFor(name: name, role: role);
  }
}
