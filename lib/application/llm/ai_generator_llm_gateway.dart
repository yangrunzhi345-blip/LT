import '../../models/completion_params.dart';
import '../../models/generation_mode.dart';
import '../../models/scene_batch_candidate.dart';
import '../../services/ai_generator_service.dart';
import '../../services/llm_service.dart';
import 'llm_gateway.dart';

/// 将现有 AI 生成服务适配到应用层 Gateway。
class AiGeneratorLlmGateway implements LlmGateway {
  final AiGeneratorService Function() _generatorResolver;
  final bool Function()? _isConfiguredResolver;
  final LLMService Function()? _llmResolver;

  AiGeneratorLlmGateway(
    this._generatorResolver, {
    bool Function()? isConfiguredResolver,
    LLMService Function()? llmResolver,
  })  : _isConfiguredResolver = isConfiguredResolver,
        _llmResolver = llmResolver;

  @override
  bool get isConfigured => _isConfiguredResolver?.call() ?? true;

  AiGeneratorService get _generator => _generatorResolver();

  @override
  Future<Map<String, String>> generateConversationCharacter(String source) =>
      _generator.textToConversationCharacterCard(source);

  @override
  Future<Map<String, String>> generateResourceCharacter({
    required String source,
    required String worldview,
    required List<Map<String, String>> associatedCharacters,
    LlmGenerationMode? generationMode,
  }) =>
      _generator.textToCharacterCard(
        source,
        worldview: worldview,
        associatedCharacters: associatedCharacters,
        generationMode: generationMode,
      );

  @override
  Future<Map<String, dynamic>> generateDetailedResourceCharacter({
    required String source,
    String worldview = '',
    List<Map<String, String>> associatedCharacters = const [],
    int? targetTotalCharacters,
    void Function(int currentStage, int totalStages, String stageName)?
        onProgress,
    LlmGenerationMode? generationMode,
  }) =>
      _generator.textToDetailedCharacterCard(
        source,
        worldview: worldview,
        associatedCharacters: associatedCharacters,
        targetTotalCharacters: targetTotalCharacters,
        onProgress: onProgress,
        generationMode: generationMode,
      );

  @override
  Future<List<Map<String, String>>> generateResourceNpcs({
    required String source,
    required String worldview,
    required List<Map<String, String>> associatedCharacters,
  }) =>
      _generator.textToNpcs(
        userPrompt: source,
        worldview: worldview,
        associatedCharacters: associatedCharacters,
      );

  @override
  Future<List<String>> identifyCharacterNames(String source) =>
      _generator.identifyCharacterNames(source);

  @override
  Future<Map<String, dynamic>> generateSceneBatchCharacter({
    required String source,
    required String label,
    required String worldview,
    required List<Map<String, dynamic>> relatedCharacters,
    required SceneBatchCandidate candidate,
    required int minimumTotalLength,
    required int maximumTotalLength,
    required String detailInstruction,
  }) =>
      _generator.generateSceneBatchCharacter(
        source: source,
        label: label,
        worldview: worldview,
        relatedCharacters: relatedCharacters,
        candidate: candidate,
        minimumTotalLength: minimumTotalLength,
        maximumTotalLength: maximumTotalLength,
        detailInstruction: detailInstruction,
      );

  @override
  Future<Map<String, String>> generateWorldview(
    String source, {
    LlmGenerationMode? generationMode,
  }) =>
      _generator.textToWorldview(source, generationMode: generationMode);

  @override
  Future<Map<String, dynamic>> generateDetailedWorldview(
    String source, {
    int? targetTotalCharacters,
    void Function(WorldviewGenerationProgress progress)? onProgress,
    LlmGenerationMode? generationMode,
  }) =>
      _generator.textToDetailedWorldview(
        source,
        targetTotalCharacters: targetTotalCharacters,
        onProgress: onProgress == null
            ? null
            : (value) => onProgress(
                  WorldviewGenerationProgress(
                    completedQuestions: value.completedQuestions,
                    totalQuestions: value.question.totalQuestions,
                    partialText: value.partialText,
                    questionCompleted: value.questionCompleted,
                    currentCharacters: value.currentCharacters,
                    targetCharacters: value.targetCharacters,
                    supplementRound: value.supplementRound,
                  ),
                ),
        generationMode: generationMode,
      );

  @override
  Future<Map<String, String>> imageToWorldview(String base64Image) =>
      _generator.imageToWorldview(base64Image);

  @override
  Future<Map<String, String>> imageToCharacterCard(
    String base64Image, {
    String worldview = '',
  }) =>
      _generator.imageToCharacterCard(base64Image, worldview: worldview);

  @override
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
  }) =>
      _generator.textToNpcs(
        userPrompt: userPrompt,
        worldview: worldview,
        protagonistName: protagonistName,
        protagonistRole: protagonistRole,
        protagonistPersonality: protagonistPersonality,
        protagonistBackground: protagonistBackground,
        protagonistBodyDescription: protagonistBodyDescription,
        protagonistAppearance: protagonistAppearance,
        selectedCharacters: selectedCharacters,
        characterRelationships: characterRelationships,
        existingNpcs: existingNpcs,
        associatedCharacters: associatedCharacters,
      );

  @override
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
  }) =>
      _generator.textToOpening(
        userPrompt: userPrompt,
        worldview: worldview,
        protagonistName: protagonistName,
        protagonistRole: protagonistRole,
        protagonistPersonality: protagonistPersonality,
        protagonistBackground: protagonistBackground,
        protagonistBodyDescription: protagonistBodyDescription,
        protagonistAppearance: protagonistAppearance,
        selectedCharacters: selectedCharacters,
        characterRelationships: characterRelationships,
        npcs: npcs,
      );

  @override
  Future<String> rawCompletion({
    required String systemPrompt,
    required String instruction,
    int maximumOutputTokens = 4096,
    double temperature = .7,
  }) async {
    final resolver = _llmResolver;
    if (resolver == null) {
      throw StateError('该操作需要配置 LLM 解析器');
    }
    final isJson = systemPrompt.toLowerCase().contains('json') ||
        instruction.toLowerCase().contains('json');
    final buffer = StringBuffer();
    await resolver().sendMessageStream(
      [
        if (systemPrompt.isNotEmpty)
          {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': instruction},
      ],
      (chunk) => buffer.write(chunk),
      () {},
      // 原始 JSON/文本补全属于辅助抽取：显式关闭思考，交互聊天仍走用户设置。
      params: CompletionParams(
        temperature: temperature,
        maxTokens: maximumOutputTokens,
        enableThinking: false,
        responseFormat: isJson ? const {'type': 'json_object'} : null,
      ),
    );
    return buffer.toString();
  }

  @override
  Future<Map<String, dynamic>> textToCreationWorld(String userPrompt) =>
      _generator.textToCreationWorld(userPrompt);

  @override
  Future<Map<String, dynamic>> textToCreationCharacter(
    String userPrompt, {
    String worldview = '',
    List<Map<String, dynamic>> associatedCharacters = const [],
    GenerationTaskHandle? taskHandle,
    int maximumOutputTokens = 8192,
  }) =>
      _generator.textToCreationCharacter(
        userPrompt,
        worldview: worldview,
        associatedCharacters: associatedCharacters,
        taskHandle: taskHandle,
        maximumOutputTokens: maximumOutputTokens,
      );

  @override
  Future<List<Map<String, dynamic>>> textToCreationNpcs(
    String userPrompt, {
    String worldview = '',
    List<Map<String, dynamic>> associatedCharacters = const [],
  }) =>
      _generator.textToCreationNpcs(
        userPrompt,
        worldview: worldview,
        associatedCharacters: associatedCharacters,
      );

  @override
  Future<String> generateNarrativeMap({
    required String worldviewSummary,
    required String worldviewDetail,
    required String openingScene,
  }) {
    const systemPrompt = '你是世界地图设计助手。根据冒险的世界观设定，设计一张合理的世界地图。严格输出JSON。';
    final instruction = '''
## 世界观概览
$worldviewSummary

## 世界观详细设定
$worldviewDetail

## 开场场景
$openingScene

## 要求
1. 根据世界观中的地点描述和地理设定，设计 8-15 个地点
2. 地点名称要符合世界观（2-6 个中文字）
3. 每个地点指定地形类型 terrain：plains/forest/ocean/river/mountain/snowMountain/desert/swamp/city/village/kingdom/ruins/volcano/grassland/tundra
4. 每个地点指定功能类型 nodeType：city/settlement/building/forest/mountain/water/dungeon/ruin/portal/camp/shop/wild/road/unknown
5. 位置 x,y 在 0.0-1.0 之间，反映地点间的相对地理方位
6. 如果世界观中有 locations 模块，优先使用其中的地点
7. 地点之间建立合理的道路/路径连接
8. 第一个地点为起始位置（isCurrent: true），应与开场场景一致

## 输出格式
{
  "locations": [
    {"name":"...","terrain":"forest","nodeType":"settlement","description":"...","x":0.3,"y":0.7,"isCurrent":false}
  ],
  "connections": [
    {"from":"地点A","to":"地点B","type":"road","bidirectional":true,"travelTime":10,"energyCost":5}
  ]
}
只输出 JSON，不要其他内容。
''';
    return rawCompletion(
      systemPrompt: systemPrompt,
      instruction: instruction,
      maximumOutputTokens: 4096,
      temperature: 0.7,
    );
  }
}
