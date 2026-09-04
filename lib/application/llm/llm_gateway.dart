import '../../services/llm_service.dart';

/// 应用层唯一的 AI 生成边界。
///
/// UI 和 UseCase 不应知道当前模型、端点或 LLMService 的具体实现。
abstract interface class LlmGateway {
  bool get isConfigured;

  Future<Map<String, String>> generateConversationCharacter(String source);

  Future<Map<String, String>> generateResourceCharacter({
    required String source,
    required String worldview,
    required List<Map<String, String>> associatedCharacters,
  });

  Future<List<Map<String, String>>> generateResourceNpcs({
    required String source,
    required String worldview,
    required List<Map<String, String>> associatedCharacters,
  });

  Future<List<String>> identifyCharacterNames(String source);

  Future<Map<String, dynamic>> generateSceneBatchCharacters({
    required String source,
    required String label,
    required String worldview,
    required List<Map<String, dynamic>> relatedCharacters,
    required List<String> selectedNames,
    required int minimumTotalLength,
    required int maximumTotalLength,
    required String detailInstruction,
  });

  Future<Map<String, String>> generateWorldview(String source);

  Future<Map<String, dynamic>> generateDetailedWorldview(
    String source, {
    int? targetTotalCharacters,
    void Function(WorldviewGenerationProgress progress)? onProgress,
  });

  /// 从图片生成世界观。
  Future<Map<String, String>> imageToWorldview(String base64Image);

  /// 从图片生成角色卡。
  Future<Map<String, String>> imageToCharacterCard(
    String base64Image, {
    String worldview = '',
  });

  /// 批量生成 NPC（完整上下文版本）。
  Future<List<Map<String, String>>> textToNpcs({
    required String userPrompt,
    String worldview = '',
    String protagonistName = '',
    String protagonistRole = '',
    String protagonistPersonality = '',
    String protagonistBackground = '',
    String protagonistBodyDescription = '',
    String protagonistAppearance = '',
    List<Map<String, String>> selectedCharacters = const [],
    List<Map<String, String>> characterRelationships = const [],
    List<Map<String, String>> existingNpcs = const [],
    List<Map<String, String>> associatedCharacters = const [],
  });

  /// 生成开场场景与选项（完整上下文版本）。
  Future<Map<String, String>> textToOpening({
    required String userPrompt,
    String worldview = '',
    String protagonistName = '',
    String protagonistRole = '',
    String protagonistPersonality = '',
    String protagonistBackground = '',
    String protagonistBodyDescription = '',
    String protagonistAppearance = '',
    List<Map<String, String>> selectedCharacters = const [],
    List<Map<String, String>> characterRelationships = const [],
    List<Map<String, String>> npcs = const [],
  });

  /// 单轮 JSON 补全（替代页面直接调用 AdventureSetupContextService）。
  Future<String> rawCompletion({
    required String systemPrompt,
    required String instruction,
    int maximumOutputTokens = 4096,
    double temperature = .7,
  });

  /// 创作资料 AI 整理：世界观。
  Future<Map<String, dynamic>> textToCreationWorld(String userPrompt);

  /// 创作资料 AI 整理：角色卡。
  Future<Map<String, dynamic>> textToCreationCharacter(
    String userPrompt, {
    String worldview = '',
    List<Map<String, dynamic>> associatedCharacters = const [],
    GenerationTaskHandle? taskHandle,
    int maximumOutputTokens = 32768,
  });

  /// 创作资料 AI 整理：NPC 列表。
  Future<List<Map<String, dynamic>>> textToCreationNpcs(
    String userPrompt, {
    String worldview = '',
    List<Map<String, dynamic>> associatedCharacters = const [],
  });

  /// 根据世界观和开场场景生成冒险地图。
  Future<String> generateNarrativeMap({
    required String worldviewSummary,
    required String worldviewDetail,
    required String openingScene,
  });
}

/// 详细世界观生成的应用层进度模型，隔离基础设施中的协调器类型。
class WorldviewGenerationProgress {
  final int completedQuestions;
  final int totalQuestions;
  final String partialText;
  final bool questionCompleted;

  const WorldviewGenerationProgress({
    required this.completedQuestions,
    required this.totalQuestions,
    required this.partialText,
    this.questionCompleted = false,
  });

  double get fraction => totalQuestions <= 0
      ? 0
      : ((completedQuestions + (questionCompleted ? 1 : 0)) / totalQuestions)
          .clamp(0, 1);
}
