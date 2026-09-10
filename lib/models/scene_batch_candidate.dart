/// 场景资料库批量导入的稳定候选身份。
///
/// 识别阶段为每个候选分配一个不可变的 [sourceId]，后续的用户选择、生成提示、
/// 结果过滤、关系绑定全部以 [sourceId] 作为唯一身份键。展示名 [displayName] 只
/// 用于界面展示与提示词上下文，允许模型改写，绝不作为跨阶段的主键。
class SceneBatchCandidate {
  final String sourceId;
  final String displayName;

  const SceneBatchCandidate({
    required this.sourceId,
    required this.displayName,
  });

  /// 送给生成阶段的精简上下文，模型必须原样回传 `sourceId`。
  Map<String, String> toPromptMap() => {
        'sourceId': sourceId,
        'displayName': displayName,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SceneBatchCandidate && other.sourceId == sourceId;

  @override
  int get hashCode => sourceId.hashCode;

  @override
  String toString() => '$sourceId:$displayName';
}
