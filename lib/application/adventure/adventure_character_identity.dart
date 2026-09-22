import '../../models/adventure_config.dart';
import '../../models/supporting_character.dart';

/// Single source of truth for「这个角色是谁」在 Adventure 内部的身份规则。
///
/// `selectedCharacters` 是新版组装 roster 的权威来源，而
/// `supportingCharacters` 是自定义检测状态层仍在读写的兼容快照。运行期实体
/// (`adventure_runtime_entities`)、runtime overlay、以及提示词里的
/// `character_id` 都以「每个角色一个稳定 ID」为前提，因此所有层必须用同一套
/// 规则推导这个 ID，否则状态定义与运行期覆盖值会挂到不同身份上：
///
/// `characterId` → 选择行 `id` →（仅历史数据）由名称派生的确定性 ID。
final class AdventureCharacterIdentity {
  const AdventureCharacterIdentity._();

  /// 运行期实体、overlay、校验与提示词共用的稳定 ID。
  static String effectiveId(AdventureSelectedCharacter selected) {
    final characterId = selected.characterId.trim();
    if (characterId.isNotEmpty) return characterId;
    return selected.id.trim();
  }

  /// 该选择行可能已经被持久化使用的全部 ID。
  ///
  /// 新数据一律使用 [effectiveId]；只有历史数据可能落在另一个候选值上，因此
  /// 查找时允许两个候选都命中，写入时仍会收敛到 [effectiveId]。
  static Set<String> candidateIds(AdventureSelectedCharacter selected) => {
        if (selected.characterId.trim().isNotEmpty) selected.characterId.trim(),
        if (selected.id.trim().isNotEmpty) selected.id.trim(),
      };

  /// 该选择行是否带有可用的稳定 ID。
  ///
  /// 只有完全没有稳定 ID 的历史选择行才允许退化为名称匹配；否则两个同名角色
  /// 会静默共用同一个快照，一个角色的状态会串到另一个角色身上。
  static bool hasStableId(AdventureSelectedCharacter selected) =>
      candidateIds(selected).isNotEmpty;

  /// 解析冻结时记录的「主角 ↔ 该角色」关系标签，无法可靠解析时返回空串。
  static String resolveRelation({
    required AdventureConfig config,
    required AdventureSelectedCharacter selected,
  }) {
    final targetIds = candidateIds(selected);
    if (targetIds.isEmpty) return '';
    final protagonist = config.protagonistCharacter;
    if (protagonist == null) return '';
    final protagonistIds = candidateIds(protagonist);
    if (protagonistIds.isEmpty) return '';
    for (final relationship in config.characterRelationships) {
      final source = relationship.sourceCharacterId.trim();
      final target = relationship.targetCharacterId.trim();
      final isProtagonistToTarget =
          protagonistIds.contains(source) && targetIds.contains(target);
      final isTargetToProtagonist =
          targetIds.contains(source) && protagonistIds.contains(target);
      if (!isProtagonistToTarget && !isTargetToProtagonist) continue;
      if (AdventureRelationType.normalize(relationship.relationType) ==
          AdventureRelationType.unset) {
        return '';
      }
      return relationship.effectiveRelation;
    }
    return '';
  }

  /// 在 [characters] 中定位该选择行对应的持久化快照下标，找不到返回 -1。
  static int indexOfSupporting(
    List<SupportingCharacter> characters,
    AdventureSelectedCharacter selected,
  ) {
    for (final id in candidateIds(selected)) {
      final index = characters.indexWhere((c) => c.id.trim() == id);
      if (index >= 0) return index;
    }
    return -1;
  }
}
