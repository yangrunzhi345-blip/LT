/// 一次生成任务的阶段进度。
///
/// 应用层（SettingCardService）、网关（LlmGateway）与服务层
/// （AiGeneratorService）共用同一模型，避免各层把阶段名、字数与补全轮次
/// 压扁成一段拼接字符串后再由 UI 反解析。
class GenerationStageProgress {
  const GenerationStageProgress({
    required this.stage,
    required this.totalStages,
    required this.stageName,
    this.currentCharacters = 0,
    this.targetCharacters,
    this.supplementRound = 0,
  });

  /// 当前阶段序号；仅用于展示进度比例，起点由调用方决定。
  final int stage;

  /// 阶段总数；0 表示调用方没有可分阶段的信息。
  final int totalStages;

  /// 面向用户的阶段名称，例如「外貌与体态」。
  final String stageName;

  /// 当前已生成的有效正文字数。
  final int currentCharacters;

  /// 目标正文字数；null 表示本次生成没有显式目标。
  final int? targetCharacters;

  /// 补全轮次，0 表示首次生成。
  final int supplementRound;

  double get fraction =>
      totalStages <= 0 ? 0 : (stage / totalStages).clamp(0.0, 1.0);
}
