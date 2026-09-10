import 'dart:convert';
import 'api_error.dart';
import '../models/completion_params.dart';
import '../models/generation_mode.dart';
import '../models/scene_batch_candidate.dart';
import '../utils/ai_adventure_utils.dart';
import '../utils/content_hasher.dart';
import '../utils/structured_json_codec.dart';
import 'detailed_worldview_context_policy.dart';
import 'detailed_worldview_generation_coordinator.dart';
import 'character_card_generation_guard.dart';
import 'detailed_character_generation_coordinator.dart';
import 'llm_service.dart';
import 'worldview_length_guard.dart';
import 'stage_schema_validator.dart';
import 'detailed_character_stage_normalizer.dart';
import 'package:flutter/foundation.dart';

class _DetailedWorldviewFlight {
  final Future<Map<String, dynamic>> future;
  final Set<void Function(DetailedWorldviewGenerationProgress progress)>
      listeners;

  const _DetailedWorldviewFlight(this.future, this.listeners);
}

/// 角色候选响应可以解码为 JSON，但不符合约定结构时抛出。
///
/// 异常只携带安全的分类信息，避免把模型原始响应带入日志或持久化会话。
class CharacterCandidateFormatException extends FormatException {
  const CharacterCandidateFormatException([super.message = '角色识别结果格式无效']);
}

/// Raised when a call that requires structured JSON receives an **incomplete**
/// response: the stream was truncated (length/maxTokens), interrupted, or never
/// completed. Such a response may look repairable, but repairing it only hides
/// that required fields were never emitted, so it must never become a card.
class StructuredOutputIncompleteException implements Exception {
  const StructuredOutputIncompleteException(
      [this.message = '模型结构化响应未完整完成，不能使用部分结果']);

  final String message;

  @override
  String toString() => message;
}

class AiGeneratorService {
  /// Transport attempts for a single non-structured LLM call (includes the
  /// first call). Only transient transport failures are retried here; content
  /// quality is recovered one layer up by re-running the failing stage, so the
  /// two budgets stay separate instead of multiplying silently.
  static const int defaultMaximumTransportAttempts = 3;

  /// Raised when a call that requires structured JSON receives an empty,
  /// invalid or unrepairable response.
  static const String structuredJsonFailureMessage = '结构化 JSON 响应为空、无效或无法修复';

  static final Map<String, _DetailedWorldviewFlight> _detailedFlights = {};
  static final Map<String, Future<Map<String, dynamic>>>
      _detailedCharacterFlights = {};
  final LLMService _llm;

  AiGeneratorService(this._llm);

  // ─── 公开 API ───

  /// F1: 图片 → 世界观
  Future<Map<String, String>> imageToWorldview(String imageBase64) async {
    final response = await _callVision(imageBase64, _f1Prompt);
    return _parseWorldviewResponse(response);
  }

  /// F2: 图片 → 角色卡
  /// [worldview] 当前世界观描述，确保生成的角色与世界观一致。
  Future<Map<String, String>> imageToCharacterCard(String imageBase64,
      {String worldview = ''}) async {
    final prompt = _f2Prompt.replaceFirst('{worldview}',
        worldview.isNotEmpty ? '当前世界观设定：\n$worldview\n\n请确保角色与世界观高度契合。' : '');
    final response = await _callVision(imageBase64, prompt);
    return _parseCharacterCardResponse(response);
  }

  /// F3: 文字 → 世界观
  Future<Map<String, String>> textToWorldview(
    String userPrompt, {
    LlmGenerationMode? generationMode,
  }) async {
    final prompt = _f3Prompt.replaceFirst('{userPrompt}', userPrompt);
    final response = await _callText(prompt, generationMode: generationMode);
    return _parseWorldviewResponse(response);
  }

  /// Generates a reviewable candidate using the optimized two-stage concurrent engine.
  Future<Map<String, dynamic>> textToDetailedWorldview(
    String userPrompt, {
    int? targetTotalCharacters,
    void Function(DetailedWorldviewGenerationProgress progress)? onProgress,
    LlmGenerationMode? generationMode,
  }) async {
    final key = ContentHasher.hashString(
      '$userPrompt\n#target=${targetTotalCharacters ?? 0}\n#mode=$generationMode',
    );
    final existing = _detailedFlights[key];
    if (existing != null) {
      if (onProgress != null) existing.listeners.add(onProgress);
      return existing.future;
    }
    final listeners =
        <void Function(DetailedWorldviewGenerationProgress progress)>{
      if (onProgress != null) onProgress,
    };
    late final _DetailedWorldviewFlight flight;
    final future = textToDetailedWorldviewMultiTurn(
      userPrompt,
      targetTotalCharacters: targetTotalCharacters,
      generationMode: generationMode,
      onDetailedProgress: (progress) {
        for (final listener in List.of(listeners)) {
          listener(progress);
        }
      },
    ).whenComplete(() {
      if (identical(_detailedFlights[key], flight)) {
        _detailedFlights.remove(key);
      }
    });
    flight = _DetailedWorldviewFlight(future, listeners);
    _detailedFlights[key] = flight;
    return future;
  }

  /// 尝试对因达到 Token 上限而被截断的 JSON 字符串进行括号与引号自动闭合修复
  static String _repairTruncatedJson(String source) {
    var text = source.trim();
    if (text.startsWith('```')) {
      final firstNewline = text.indexOf('\n');
      if (firstNewline != -1) text = text.substring(firstNewline + 1);
      if (text.endsWith('```')) {
        text = text.substring(0, text.length - 3).trim();
      }
    }
    final firstBrace = text.indexOf('{');
    if (firstBrace == -1) return source;
    text = text.substring(firstBrace);

    final stack = <String>[];
    var inString = false;
    var escaped = false;
    for (var i = 0; i < text.length; i++) {
      final c = text[i];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (c == r'\') {
          escaped = true;
        } else if (c == '"') {
          inString = false;
        }
      } else {
        if (c == '"') {
          inString = true;
        } else if (c == '{' || c == '[') {
          stack.add(c);
        } else if (c == '}' || c == ']') {
          if (stack.isNotEmpty) stack.removeLast();
        }
      }
    }
    var repaired = text;
    if (inString) repaired += '"';
    repaired = repaired.trimRight();

    if (repaired.endsWith(':')) {
      repaired += ' ""';
    }
    if (repaired.contains(RegExp(r',\s*\{\s*"[^":]*"\s*$'))) {
      repaired = repaired.replaceAll(RegExp(r',\s*\{\s*"[^":]*"\s*$'), '');
      if (stack.isNotEmpty && stack.last == '{') stack.removeLast();
    }
    repaired = repaired.replaceAll(RegExp(r',\s*"[^":]*"\s*$'), '');
    repaired = repaired.replaceAll(RegExp(r',\s*$'), '');

    final buffer = StringBuffer(repaired);
    while (stack.isNotEmpty) {
      final open = stack.removeLast();
      buffer.write(open == '{' ? '}' : ']');
    }
    return buffer.toString();
  }

  /// 优化版世界观详细模式生成：根据期望字数自适应采用两阶段/三阶段并发架构。
  Future<Map<String, dynamic>> textToDetailedWorldviewMultiTurn(
    String sourceText, {
    int? targetTotalCharacters,
    void Function(int currentTurn, int totalTurns, String stageName)?
        onProgress,
    void Function(DetailedWorldviewGenerationProgress progress)?
        onDetailedProgress,
    LlmGenerationMode? generationMode,
  }) async {
    final isEpic =
        (targetTotalCharacters != null && targetTotalCharacters > 35000);
    final isMassive =
        (targetTotalCharacters != null && targetTotalCharacters > 12000);
    final totalStages = isEpic ? 5 : (isMassive ? 3 : 2);

    final isExpanded =
        (targetTotalCharacters != null && targetTotalCharacters >= 6000);
    final descLen = isEpic
        ? '500~800字'
        : (isMassive ? '400~700字' : (isExpanded ? '300~600字' : '200~350字'));
    final rulesLen = isEpic
        ? '600~1000字'
        : (isMassive ? '500~800字' : (isExpanded ? '400~600字' : '250~400字'));
    final stateLen = isEpic
        ? '500~800字'
        : (isMassive ? '400~700字' : (isExpanded ? '300~600字' : '200~350字'));
    final locRequirement = isExpanded
        ? '（请至少提供 5 到 8 个代表性地点，每个据点详细描述 150~250字）'
        : '（请至少提供 3 到 5 个地点和 3 到 4 个势力）';
    final facRequirement =
        isExpanded ? '（请至少提供 4 到 6 个核心势力，每个势力详细描述 150~250字）' : '';
    final customsLen =
        isMassive ? '600~1200字' : (isExpanded ? '400~800字' : '250~450字');
    final timelineRequirement = isExpanded
        ? '（请至少提供 5 到 7 项历史大事件，每项 100~180字）'
        : '（请至少提供 3 项历史大事件，3 个专有名词，以及详尽的创作约束）';
    final glossaryRequirement =
        isExpanded ? '（请至少提供 5 到 8 个核心专有名词，每个 50~100字）' : '';
    final constraintsLen =
        isMassive ? '400~800字' : (isExpanded ? '300~500字' : '200~350字');

    // Helper to execute a single turn with LLM
    Future<Map<String, dynamic>> executeTurn({
      required String userInstruction,
      required int turnIndex,
      int currentTotalStages = 2,
      required String stageName,
      List<Map<String, dynamic>> confirmedResults =
          const <Map<String, dynamic>>[],
    }) async {
      if (onDetailedProgress != null) {
        onDetailedProgress(DetailedWorldviewGenerationProgress(
          question: DetailedWorldviewQuestion(
            questionIndex: turnIndex,
            totalQuestions: currentTotalStages,
            module: stageName,
            modules: const [],
            part: 1,
            totalParts: 1,
            targetCharacters: 1000,
            maximumCharacters: 2500,
            dependsOnPreviousPart: turnIndex > 1,
          ),
          completedQuestions: turnIndex - 1,
          partialText: stageName,
          questionCompleted: false,
        ));
      }

      // Every turn builds its own immutable snapshot: system prompt, the
      // already accepted results of earlier stages and the current user
      // instruction. Nothing is appended to a list another turn is using, so
      // a later stage can never inherit half-written context.
      final messages = <Map<String, dynamic>>[
        {
          'role': 'system',
          'content': '你是一位史诗级世界观架构与设定解析专家。'
              '【核心最高准则】：当用户提供了具体的世界观设定材料时，你必须高度忠实于用户的原文设定，严格优先提取、梳理并结构化用户材料中的全部设定（包括世界名称、地理大陆/据点、势力阵营、历史纪元、专有名词、法则代价与禁忌），严禁脱离原文凭空捏造、篡改或替换用户的设定！只有在原文未提及的空白细节处，才允许在完全遵循原文基调与逻辑的前提下进行合理补充。'
              '在每一轮对话中，你必须严格输出合法的 JSON 格式，不要包含任何非 JSON 的解释文字或 Markdown 标签之外的内容。',
        },
        for (final confirmed in confirmedResults)
          {'role': 'assistant', 'content': jsonEncode(confirmed)},
        {
          'role': 'user',
          'content': userInstruction,
        },
      ];

      // Bounded content retry for this stage only. A truncated/interrupted
      // structured turn must be re-requested here, not silently repaired into
      // a partial world section. Cancellation still aborts immediately.
      final maximumAttempts = RetryBudget.structuredJson.contentStageAttempts;
      String response;
      for (var attempt = 1;; attempt++) {
        try {
          response = await _callMessages(
            messages,
            maximumOutputTokens: 8192,
            generationMode: generationMode,
            expectJsonObject: true,
            maximumAttempts: RetryBudget.structuredJson.transportAttempts,
          );
          break;
        } on GenerationCancelledException {
          rethrow;
        } catch (_) {
          if (attempt >= maximumAttempts) rethrow;
        }
      }

      final parsed = StructuredJsonCodec.tryDecodeObject(response);
      if (parsed == null) {
        throw FormatException('世界观阶段 $turnIndex ($stageName) 生成返回了无效的 JSON');
      }
      return parsed;
    }

    // Stage 1: core foundation
    onProgress?.call(1, totalStages, '核心基石与法则体系');
    final t1Prompt = '''
基于用户提供的世界观核心材料，提炼与系统梳理世界观的基石、宏观物理与超自然法则体系、以及当前文明与世界的全局现状。
注意：必须高度忠实提取原文中明确设定的世界名称、底层能量与神话法则、纪元危机。

【用户核心材料】：
$sourceText

请严格输出单层 JSON 格式：
{
  "name": "世界名称（优先严格提取自原文，2-8字）",
  "description": "世界宏观概述与核心魅力（$descLen，忠实提炼原文的世界起源、宏大背景与根本矛盾）",
  "world_rules": "世界的底层法则、物理/超自然定律、力量运作体系与代价禁忌（$rulesLen，忠实提取原文的法则与本源）",
  "world_state": "当前世界的文明格局、时代面貌、核心危机或历史转折点（$stateLen，忠实提取原文的当前纪元格局）"
}
''';
    final t1Data = await executeTurn(
      userInstruction: t1Prompt,
      turnIndex: 1,
      currentTotalStages: totalStages,
      stageName: '宏观基石与法则现状',
    );
    final name = (t1Data['name'] as String?)?.trim() ?? '未命名世界';
    final description =
        (t1Data['description'] as String?)?.trim() ?? sourceText;
    final worldRules =
        (t1Data['world_rules'] as String?)?.trim() ?? '遵循基础自然法则与超凡秩序。';
    final worldState =
        (t1Data['world_state'] as String?)?.trim() ?? '文明正处于关键的动荡转折期。';

    final dynamic rawLocations;
    final dynamic rawFactions;
    final String customsText;
    final dynamic rawTimeline;
    final dynamic rawGlossary;
    final String constraintsText;

    if (isEpic) {
      // 5-stage mode for epic scale (> 35000, e.g. 50000 chars)
      // Dedicated sequential stages prevent concurrent socket contention and avoid token overflow
      onProgress?.call(2, 5, '空间地理与核心据点全貌');
      final t2LocationsPrompt = '''
基于已确立的世界「$name」与【用户核心材料原文】，提取并深入推演该世界的地理风貌、核心据点与大陆板块生态。

【已确立的宏观法则与现状】：
底层法则：$worldRules
世界现状：$worldState

【用户核心材料原文】：
$sourceText

【严格要求】：
1. 必须优先从【用户核心材料原文】中提取所有明确提到的地理大陆、海洋、城市、据点等；
2. 为每个据点提供详尽风貌、地质环境、危险评级与探索价值（每个据点 150~250 字）；
3. 严格输出单层 JSON 格式：
{
  "locations": [
    {
      "name": "地点名称（优先来自原文）",
      "terrain": "地形或环境类型",
      "description": "地理风貌、生态环境、危险评级与探索价值（提炼自原文并详尽展开，150~250字）"
    }
  ]
}
（请提供 8 到 14 个代表性地理据点，尽可能全面收录原文涉及的所有地点）
''';
      final s2Data = await executeTurn(
        userInstruction: t2LocationsPrompt,
        turnIndex: 2,
        currentTotalStages: 5,
        stageName: '空间地理据点',
      );
      rawLocations = s2Data['locations'];

      onProgress?.call(3, 5, '核心阵营与各大势力格局');
      final t3FactionsPrompt = '''
基于已确立的世界「$name」与【用户核心材料原文】，提取并深入推演该世界的核心势力、政权、宗派、氏族与阵营格局。

【已确立的宏观法则与现状】：
底层法则：$worldRules
世界现状：$worldState

【用户核心材料原文】：
$sourceText

【严格要求】：
1. 必须优先从【用户核心材料原文】中提取所有明确提到的势力、帝国、教会、氏族、议会、隐秘结社等；
2. 详述势力架构、权力资源、核心纲领宗旨与对世界的影响（每个势力 150~250 字）；
3. 严格输出单层 JSON 格式：
{
  "factions": [
    {
      "name": "势力/组织名称（优先来自原文）",
      "type": "类型（如帝国政权/神权教会/巨龙氏族/隐秘结社）",
      "ideology": "宗旨与核心理念（提炼自原文）",
      "description": "势力架构、拥有的资源权力与对外界的影响（提炼自原文并详尽展开，150~250字）"
    }
  ]
}
（请提供 6 到 12 个核心势力，尽可能全面收录原文涉及的所有势力）
''';
      final s3Data = await executeTurn(
        userInstruction: t3FactionsPrompt,
        turnIndex: 3,
        currentTotalStages: 5,
        stageName: '核心阵营势力',
      );
      rawFactions = s3Data['factions'];

      onProgress?.call(4, 5, '社会民俗与日常生活全貌');
      final t4CustomsPrompt = '''
基于已确立的世界「$name」与【用户核心材料原文】，宏篇推演与提炼该世界的社会民俗、民众生活全貌、信仰与风俗。

【已确立的宏观法则与现状】：
底层法则：$worldRules
世界现状：$worldState

【用户核心材料原文】：
$sourceText

【严格要求】：
1. 涵盖各族与各阶层民众的日常生活面貌、主要社会风俗节庆、贸易与经济命脉（如魔晶等）、禁忌与信仰体系；
2. 保持宏篇详尽叙述，字数要求 800~1500 字；
3. 严格输出单层 JSON 格式：
{
  "customs_and_life": "普通民众的生活面貌、社会风俗节庆、贸易与经济方式、信仰禁忌（800~1500字详尽宏篇叙述）"
}
''';
      final s4Data = await executeTurn(
        userInstruction: t4CustomsPrompt,
        turnIndex: 4,
        currentTotalStages: 5,
        stageName: '社会民俗与生活',
      );
      customsText = (s4Data['customs_and_life'] as String?)?.trim() ??
          '民间保留着古老的祭祀传统，商旅依靠陆上驼队与飞艇穿梭于城邦之间。';

      onProgress?.call(5, 5, '纪元历史编年与专有名词铁律');
      final t5TimelineGlossaryPrompt = '''
基于已确立的世界「$name」与【用户核心材料原文】，提取并完善本世界的历史纪元大事件、核心专有名词表以及创作铁律。

【已确立的宏观法则与现状】：
底层法则：$worldRules
世界现状：$worldState

【用户核心材料原文】：
$sourceText

【严格要求】：
1. 必须优先从【用户核心材料原文】中提取所有历史纪元事件（如创世纪元、神话大战、众神黄昏、人类原罪、魔女兴起等重大节点）；
2. 必须优先从【用户核心材料原文】中提取所有核心专有名词术语（如源流、天理、神族、魔女会、二十六王座、龙晶、魔晶等）；
3. 必须提取材料中设定的核心禁忌、阶位极限与创作者必须恪守的铁律；
4. 严格输出单层 JSON 格式：
{
  "timeline": [
    {
      "era": "纪元或时代（优先来自原文）",
      "event": "重大转折历史事件详细描述（提炼自原文，100~200字）"
    }
  ],
  "glossary": [
    {
      "term": "专有名词（优先来自原文）",
      "definition": "概念定义与世界功能（提炼自原文，50~100字）"
    }
  ],
  "creative_constraints": "创作者与冒险推演在此世界中必须恪守的不可违背铁律（400~800字，提炼自原文）"
}
（请提供 6 到 10 项纪元大事件，8 到 15 个专有名词，以及详尽的创作约束）
''';
      final s5Data = await executeTurn(
        userInstruction: t5TimelineGlossaryPrompt,
        turnIndex: 5,
        currentTotalStages: 5,
        stageName: '纪元编年与专有名词铁律',
      );
      rawTimeline = s5Data['timeline'];
      rawGlossary = s5Data['glossary'];
      constraintsText = (s5Data['creative_constraints'] as String?)?.trim() ??
          '法则不可随意打破，一切力量均遵循等价代价。';
    } else if (isMassive) {
      // 3-stage mode: Split Stage 2 into pure locations + pure factions
      onProgress?.call(2, 3, '空间地理与核心势力推演');
      final t2aLocationsPrompt = '''
基于已确立的世界「$name」与【用户核心材料原文】，提取并深入推演该世界的地理风貌、核心据点与大陆板块生态。

【已确立的宏观法则与现状】：
底层法则：$worldRules
世界现状：$worldState

【用户核心材料原文】：
$sourceText

【严格要求】：
1. 必须优先从【用户核心材料原文】中提取所有明确提到的地理大陆、海洋、城市、据点等；
2. 为每个据点提供详尽风貌、地质环境、危险评级与探索价值（每个据点 150~250 字）；
3. 严格输出单层 JSON 格式：
{
  "locations": [
    {
      "name": "地点名称（优先来自原文）",
      "terrain": "地形或环境类型",
      "description": "地理风貌、生态环境、危险评级与探索价值（提炼自原文并详尽展开，150~250字）"
    }
  ]
}
（请提供 6 到 10 个代表性地理据点，尽可能全面收录原文涉及的所有地点）
''';

      final t2bFactionsPrompt = '''
基于已确立的世界「$name」与【用户核心材料原文】，提取并深入推演该世界的核心势力、政权、宗派、氏族与阵营格局。

【已确立的宏观法则与现状】：
底层法则：$worldRules
世界现状：$worldState

【用户核心材料原文】：
$sourceText

【严格要求】：
1. 必须优先从【用户核心材料原文】中提取所有明确提到的势力、帝国、教会、氏族、议会、隐秘结社等；
2. 详述势力架构、权力资源、核心纲领宗旨与对世界的影响（每个势力 150~250 字）；
3. 严格输出单层 JSON 格式：
{
  "factions": [
    {
      "name": "势力/组织名称（优先来自原文）",
      "type": "类型（如帝国政权/神权教会/巨龙氏族/隐秘结社）",
      "ideology": "宗旨与核心理念（提炼自原文）",
      "description": "势力架构、拥有的资源权力与对外界的影响（提炼自原文并详尽展开，150~250字）"
    }
  ]
}
（请提供 5 到 8 个核心势力，尽可能全面收录原文涉及的所有势力）
''';

      // Stage 2: spatial locations and factions – each turn receives its own
      // immutable snapshot, and the factions stage explicitly replays the
      // confirmed locations result instead of mutating a shared list.
      final locationsResult = await executeTurn(
        userInstruction: t2aLocationsPrompt,
        turnIndex: 2,
        currentTotalStages: 3,
        stageName: '空间地理据点',
      );
      final factionsResult = await executeTurn(
        userInstruction: t2bFactionsPrompt,
        turnIndex: 2,
        currentTotalStages: 3,
        stageName: '核心阵营势力',
        confirmedResults: [locationsResult],
      );
      rawLocations = locationsResult['locations'];
      rawFactions = factionsResult['factions'];

      // Stage 3: pure customs + timeline/glossary/constraints
      onProgress?.call(3, 3, '社会民俗、纪元编年与铁律约束');
      final t3aCustomsPrompt = '''
基于已确立的世界「$name」与【用户核心材料原文】，宏篇推演与提炼该世界的社会民俗、民众生活全貌、信仰与风俗。

【已确立的宏观法则与现状】：
底层法则：$worldRules
世界现状：$worldState

【用户核心材料原文】：
$sourceText

【严格要求】：
1. 涵盖各族与各阶层民众的日常生活面貌、主要社会风俗节庆、贸易与经济命脉（如魔晶等）、禁忌与信仰体系；
2. 保持宏篇详尽叙述，字数要求 600~1200 字；
3. 严格输出单层 JSON 格式：
{
  "customs_and_life": "普通民众的生活面貌、社会风俗节庆、贸易与经济方式、信仰禁忌（600~1200字详尽宏篇叙述）"
}
''';

      final t3bTimelineGlossaryPrompt = '''
基于已确立的世界「$name」与【用户核心材料原文】，提取并完善本世界的历史纪元大事件、核心专有名词表以及创作铁律。

【已确立的宏观法则与现状】：
底层法则：$worldRules
世界现状：$worldState

【用户核心材料原文】：
$sourceText

【严格要求】：
1. 必须优先从【用户核心材料原文】中提取所有历史纪元事件（如创世纪元、神话大战、众神黄昏、人类原罪、魔女兴起等重大节点）；
2. 必须优先从【用户核心材料原文】中提取所有核心专有名词术语（如源流、天理、神族、魔女会、二十六王座、龙晶、魔晶等）；
3. 必须提取材料中设定的核心禁忌、阶位极限与创作者必须恪守的铁律；
4. 严格输出单层 JSON 格式：
{
  "timeline": [
    {
      "era": "纪元或时代（优先来自原文）",
      "event": "重大转折历史事件详细描述（提炼自原文，100~180字）"
    }
  ],
  "glossary": [
    {
      "term": "专有名词（优先来自原文）",
      "definition": "概念定义与世界功能（提炼自原文，50~100字）"
    }
  ],
  "creative_constraints": "创作者与冒险推演在此世界中必须恪守的不可违背铁律（400~800字，提炼自原文）"
}
（请提供 5 到 8 项纪元大事件，6 到 12 个专有名词，以及详尽的创作约束 400~800字）
''';

      final s3Results = await Future.wait([
        executeTurn(
            userInstruction: t3aCustomsPrompt,
            turnIndex: 3,
            currentTotalStages: 3,
            stageName: '社会民俗与生活'),
        executeTurn(
            userInstruction: t3bTimelineGlossaryPrompt,
            turnIndex: 3,
            currentTotalStages: 3,
            stageName: '纪元编年与专有名词铁律'),
      ]);
      customsText = (s3Results[0]['customs_and_life'] as String?)?.trim() ??
          '民间保留着古老的祭祀传统，商旅依靠陆上驼队与飞艇穿梭于城邦之间。';
      rawTimeline = s3Results[1]['timeline'];
      rawGlossary = s3Results[1]['glossary'];
      constraintsText =
          (s3Results[1]['creative_constraints'] as String?)?.trim() ??
              '法则不可随意打破，一切力量均遵循等价代价。';
    } else {
      // 2-stage mode for standard/moderate word count (<= 12000)
      onProgress?.call(2, 2, '细节扩展');
      // Prompt A: locations, factions, customs
      final t2aPrompt = '''
基于已确立的世界「$name」与【用户核心材料原文】，提取并深入整理该世界的地理风貌、核心据点以及活跃的核心势力与民俗生活。

【已确立的宏观法则与现状】：
底层法则：$worldRules
世界现状：$worldState

【用户核心材料原文】：
$sourceText

【提取与推演准则】：
1. 必须优先从【用户核心材料原文】中提取所有明确提到的地理大陆、海洋、城市、据点等；
2. 必须优先从【用户核心材料原文】中提取所有明确提到的势力、教会、帝国、氏族、议会等组织；
3. 严格保留原文给出的专有名词、阵营宗旨与环境特色，切勿遗漏或使用无关的随机设定替代；
4. 仅在原文未详述的细枝末节处结合上述世界法则进行合理填充。

请严格输出 JSON 格式：
{
  "locations": [
    {
      "name": "地点名称（优先来自原文）",
      "terrain": "地形或环境类型",
      "description": "地理风貌、生态环境、危险评级与探索价值（提炼自原文）"
    }
  ],
  "factions": [
    {
      "name": "势力/组织名称（优先来自原文）",
      "type": "类型（如帝国政权/神权教会/巨龙氏族/隐秘结社）",
      "ideology": "宗旨与核心理念（提炼自原文）",
      "description": "势力架构、拥有的资源权力与对外界的影响（提炼自原文）"
    }
  ],
  "customs_and_life": "普通民众的生活面貌、社会风俗节庆、贸易与经济方式、信仰禁忌（$customsLen，结合原文提炼）"
}
$locRequirement
$facRequirement
''';
      // Prompt B: timeline, glossary, constraints
      final t2bPrompt = '''
基于已确立的世界「$name」与【用户核心材料原文】，提取并完善本世界的历史编年大事件、核心专有名词表以及创作者必须遵守的铁律。

【已确立的宏观法则与现状】：
底层法则：$worldRules
世界现状：$worldState

【用户核心材料原文】：
$sourceText

【提取与推演准则】：
1. 必须优先从【用户核心材料原文】中提取所有历史大事件与纪元演变（如创世纪元、神话大战、重大转折历史节点等）；
2. 必须优先从【用户核心材料原文】中提取所有核心专有名词术语及对应释义（如特有能量、专属组织、特有矿物生物等）；
3. 必须提取材料中设定的核心禁忌、阶位限制与创作铁律；
4. 严格保留原文名称与设定，切勿遗漏或使用无关的随机设定替代。

请严格输出 JSON 格式：
{
  "timeline": [
    {
      "era": "纪元或时代（优先来自原文）",
      "event": "重大转折历史事件（提炼自原文）"
    }
  ],
  "glossary": [
    {
      "term": "专有名词（优先来自原文）",
      "definition": "概念定义与世界功能（提炼自原文）"
    }
  ],
  "creative_constraints": "创作者与冒险推演在此世界中必须恪守的不可违背铁律（如阶位极限、力量反噬、不可触碰的禁区等）（$constraintsLen，提炼自原文）"
}
$timelineRequirement
$glossaryRequirement
''';
      // Stage 2: 逐步执行，先生成地点与势力，再生成编年与约束，以避免并发上下文污染
      final t2aData = await executeTurn(
          userInstruction: t2aPrompt,
          turnIndex: 2,
          currentTotalStages: 2,
          stageName: '地点与势力');
      final t2bData = await executeTurn(
          userInstruction: t2bPrompt,
          turnIndex: 2,
          currentTotalStages: 2,
          stageName: '编年与约束');

      rawLocations = t2aData['locations'];
      rawFactions = t2aData['factions'];
      customsText = (t2aData['customs_and_life'] as String?)?.trim() ??
          '民间保留着古老的祭祀传统，商旅依靠陆上驼队与飞艇穿梭于城邦之间。';
      rawTimeline = t2bData['timeline'];
      rawGlossary = t2bData['glossary'];
      constraintsText = (t2bData['creative_constraints'] as String?)?.trim() ??
          '法则不可随意打破，一切力量均遵循等价代价。';
    }

    // Process locations
    final List<Map<String, dynamic>> locationsList = [];
    final locationsBuffer = StringBuffer();
    if (rawLocations is List) {
      for (var i = 0; i < rawLocations.length; i++) {
        final loc = rawLocations[i];
        if (loc is Map) {
          final lMap = Map<String, dynamic>.from(loc);
          locationsList.add(lMap);
          final lName = lMap['name'] ?? '据点${i + 1}';
          final lTerrain =
              lMap['terrain'] != null ? '【${lMap['terrain']}】' : '';
          final lDesc = lMap['description'] ?? '';
          locationsBuffer.writeln('${i + 1}. $lName $lTerrain：$lDesc');
        }
      }
    }
    final locationsText = locationsBuffer.toString().trim().isNotEmpty
        ? locationsBuffer.toString().trim()
        : '包含多个未探索的广袤地域与古代遗迹。';

    // Process factions
    final List<Map<String, dynamic>> factionsList = [];
    final factionsBuffer = StringBuffer();
    if (rawFactions is List) {
      for (var i = 0; i < rawFactions.length; i++) {
        final f = rawFactions[i];
        if (f is Map) {
          final fMap = Map<String, dynamic>.from(f);
          factionsList.add(fMap);
          final fName = fMap['name'] ?? '势力${i + 1}';
          final fType = fMap['type'] != null ? '（${fMap['type']}）' : '';
          final fIdeo =
              fMap['ideology'] != null ? '，宗旨：${fMap['ideology']}' : '';
          final fDesc = fMap['description'] ?? '';
          factionsBuffer.writeln('${i + 1}. $fName$fType$fIdeo：$fDesc');
        }
      }
    }
    final factionsText = factionsBuffer.toString().trim().isNotEmpty
        ? factionsBuffer.toString().trim()
        : '各大古老势力与新兴宗派在暗中角力。';

    // Process timeline, glossary, constraints
    final timelineBuffer = StringBuffer();
    if (rawTimeline is List) {
      for (var i = 0; i < rawTimeline.length; i++) {
        final tl = rawTimeline[i];
        if (tl is Map) {
          final era = tl['era'] ?? '时代${i + 1}';
          final ev = tl['event'] ?? '';
          timelineBuffer.writeln('【$era】$ev');
        }
      }
    }
    final timelineText = timelineBuffer.toString().trim().isNotEmpty
        ? timelineBuffer.toString().trim()
        : '经历了创世纪元、破晓之战与当前的新纪元。';
    final glossaryBuffer = StringBuffer();
    if (rawGlossary is List) {
      for (var i = 0; i < rawGlossary.length; i++) {
        final g = rawGlossary[i];
        if (g is Map) {
          final term = g['term'] ?? '术语${i + 1}';
          final def = g['definition'] ?? '';
          glossaryBuffer.writeln('· $term：$def');
        }
      }
    }
    final glossaryText = glossaryBuffer.toString().trim().isNotEmpty
        ? glossaryBuffer.toString().trim()
        : '包括源能、界标与命轨等专有名词。';

    final modules = <String, dynamic>{
      'overview': {
        'summary': description,
        'status': 'confirmed',
      },
      'world_rules': {
        'content': worldRules,
        'status': 'confirmed',
      },
      'world_state': {
        'content': worldState,
        'status': 'confirmed',
      },
      'locations': {
        'content': locationsText,
        'status': 'confirmed',
        'items': locationsList,
      },
      'factions': {
        'content': factionsText,
        'status': 'confirmed',
        'items': factionsList,
      },
      'customs_and_life': {
        'content': customsText,
        'status': 'confirmed',
      },
      'timeline': {
        'content': timelineText,
        'status': 'confirmed',
      },
      'glossary': {
        'content': glossaryText,
        'status': 'confirmed',
      },
      'creative_constraints': {
        'content': constraintsText,
        'status': 'confirmed',
      },
    };

    final detailJson = {
      'format_version': 2,
      'mode': 'detailed',
      'modules': modules,
    };

    if (onDetailedProgress != null && targetTotalCharacters == null) {
      onDetailedProgress(DetailedWorldviewGenerationProgress(
        question: DetailedWorldviewQuestion(
          questionIndex: totalStages,
          totalQuestions: totalStages,
          module: 'complete',
          modules: const [],
          part: 1,
          totalParts: 1,
          targetCharacters: 1000,
          maximumCharacters: 2500,
          dependsOnPreviousPart: true,
        ),
        completedQuestions: totalStages,
        partialText: '完成生成',
        questionCompleted: true,
      ));
    }

    final initial = <String, dynamic>{
      'name': name,
      'description': description,
      'detail_json': detailJson,
    };
    return _ensureDetailedWorldviewTarget(
      initial: initial,
      sourceText: sourceText,
      targetTotalCharacters: targetTotalCharacters,
      onDetailedProgress: onDetailedProgress,
      generationMode: generationMode,
    );
  }

  Future<Map<String, dynamic>> _ensureDetailedWorldviewTarget({
    required Map<String, dynamic> initial,
    required String sourceText,
    required int? targetTotalCharacters,
    void Function(DetailedWorldviewGenerationProgress progress)?
        onDetailedProgress,
    LlmGenerationMode? generationMode,
  }) async {
    if (targetTotalCharacters == null) return initial;
    final target = targetTotalCharacters.clamp(1, 50000).toInt();
    const guard = WorldviewLengthGuard();
    final detail = Map<String, dynamic>.from(initial['detail_json'] as Map);
    var current = guard.count(
      detailJson: detail,
      fallbackDescription: initial['description']?.toString() ?? '',
    );
    if (current >= target) return initial;

    // A guardrail against unbounded API use, not a success condition. Every
    // exit through this limit is an error because the requested target remains
    // unmet. A productive round normally adds several thousand characters.
    const maximumSupplementRounds = 16;
    for (var round = 1; round <= maximumSupplementRounds; round++) {
      final modules = _weakestWorldviewModules(detail, limit: 3);
      onDetailedProgress?.call(DetailedWorldviewGenerationProgress(
        question: DetailedWorldviewQuestion(
          questionIndex: round,
          totalQuestions: maximumSupplementRounds,
          module: modules.first,
          modules: modules,
          part: round,
          totalParts: maximumSupplementRounds,
          targetCharacters: target - current,
          maximumCharacters: target - current,
          dependsOnPreviousPart: true,
        ),
        completedQuestions: round - 1,
        partialText: '正在继续补全：${modules.join('、')}',
        currentCharacters: current,
        targetCharacters: target,
        supplementRound: round,
      ));
      final response = await _callMessages([
        {
          'role': 'system',
          'content': '你是世界观续写助手。只返回合法 JSON，不要返回 Markdown。',
        },
        {
          'role': 'user',
          'content': _worldviewSupplementPrompt(
            sourceText: sourceText,
            detail: detail,
            modules: modules,
            current: current,
            target: target,
          ),
        },
      ], maximumOutputTokens: 8192, generationMode: generationMode);
      final decoded =
          StructuredJsonCodec.tryDecodeObject(response, repair: true) ??
              StructuredJsonCodec.tryDecodeObject(
                _repairTruncatedJson(response),
                repair: true,
              );
      if (decoded == null) {
        throw const FormatException('世界观补全返回了无效 JSON');
      }
      _mergeWorldviewSupplement(detail, decoded, modules);
      final next = guard.count(
        detailJson: detail,
        fallbackDescription: initial['description']?.toString() ?? '',
      );
      if (next <= current) {
        throw StateError('世界观补全未增加有效正文，已停止以避免重复生成。');
      }
      current = next;
      if (current >= target) {
        initial['detail_json'] = detail;
        onDetailedProgress?.call(DetailedWorldviewGenerationProgress(
          question: DetailedWorldviewQuestion(
            questionIndex: round,
            totalQuestions: round,
            module: 'complete',
            modules: const [],
            part: round,
            totalParts: round,
            targetCharacters: target,
            maximumCharacters: target,
            dependsOnPreviousPart: true,
          ),
          completedQuestions: round,
          partialText: '已达到目标字数',
          questionCompleted: true,
          currentCharacters: current,
          targetCharacters: target,
          supplementRound: round,
        ));
        return initial;
      }
    }
    throw StateError('世界观补全达到安全上限后仍未达到目标字数。');
  }

  List<String> _weakestWorldviewModules(
    Map<String, dynamic> detail, {
    required int limit,
  }) {
    const guard = WorldviewLengthGuard();
    final modules = detail['modules'] as Map? ?? const <String, dynamic>{};
    final ranked = [
      for (final key in DetailedWorldviewQuestionPlanner.modules)
        (
          key: key,
          length: guard.count(detailJson: {
            'modules': {key: modules[key]},
          }),
        ),
    ]..sort((left, right) => left.length.compareTo(right.length));
    return ranked.take(limit).map((item) => item.key).toList(growable: false);
  }

  String _worldviewSupplementPrompt({
    required String sourceText,
    required Map<String, dynamic> detail,
    required List<String> modules,
    required int current,
    required int target,
  }) =>
      '''这是同一个世界观的续写/补全，不是重新生成。当前有效正文约 $current 字符，用户目标为 $target 字符，仍需至少补充 ${target - current} 字符。

不得修改已确认事实、世界名称或充分内容；不得复制已有段落凑字数；不得引入与用户原始材料冲突的新规则。优先展开已有事实的成因、影响、地区差异、历史背景、社会运行、势力互动、文化结果和规则边界。

用户原始资料：
$sourceText

当前需要扩充的模块：${modules.join('、')}
当前这些模块：
${jsonEncode({
            for (final key in modules) key: (detail['modules'] as Map?)?[key]
          })}

只返回结构化增量：
{"modules":{"${modules.first}":{"content":"新增正文"}}}
可包含上述其他模块，但只能补充它们的新增正文。''';

  void _mergeWorldviewSupplement(
    Map<String, dynamic> detail,
    Map<String, dynamic> increment,
    List<String> requestedModules,
  ) {
    final incoming = increment['modules'];
    if (incoming is! Map) {
      throw const FormatException('世界观补全缺少 modules 增量');
    }
    final modules = Map<String, dynamic>.from(detail['modules'] as Map);
    var mergedAny = false;
    for (final key in requestedModules) {
      final value = incoming[key];
      final addition = _moduleText(value);
      if (addition.isEmpty) continue;
      final previous = modules[key];
      final previousMap = previous is Map
          ? Map<String, dynamic>.from(previous)
          : <String, dynamic>{'content': previous?.toString() ?? ''};
      final contentKey =
          previousMap.containsKey('summary') ? 'summary' : 'content';
      final existing = previousMap[contentKey]?.toString() ?? '';
      final merged = _appendDistinctWorldviewText(existing, addition);
      if (merged == existing) continue;
      previousMap[contentKey] = merged;
      previousMap['status'] = 'confirmed';
      modules[key] = previousMap;
      mergedAny = true;
    }
    if (!mergedAny) {
      throw const FormatException('世界观补全没有请求模块的新增正文');
    }
    detail['modules'] = modules;
  }

  String _moduleText(Object? value) {
    if (value is String) return value.trim();
    if (value is Map) {
      return (value['content'] ?? value['summary'])?.toString().trim() ?? '';
    }
    return '';
  }

  String _appendDistinctWorldviewText(String existing, String addition) {
    final normalizedExisting = existing.replaceAll(RegExp(r'\s+'), '');
    final normalizedAddition = addition.replaceAll(RegExp(r'\s+'), '');
    if (normalizedAddition.isEmpty ||
        normalizedExisting.contains(normalizedAddition)) {
      return existing;
    }
    var overlap = 0;
    final maximum = normalizedExisting.length < normalizedAddition.length
        ? normalizedExisting.length
        : normalizedAddition.length;
    for (var size = maximum; size > 0; size--) {
      if (normalizedExisting.endsWith(normalizedAddition.substring(0, size))) {
        overlap = size;
        break;
      }
    }
    final suffix =
        overlap == 0 ? addition : normalizedAddition.substring(overlap);
    return existing.trim().isEmpty ? suffix : '$existing\n$suffix';
  }

  Future<Map<String, dynamic>> generateDetailedWorldviewCoordinatorForTesting(
      String sourceText, int targetTotalCharacters,
      {void Function(DetailedWorldviewGenerationProgress progress)?
          onProgress}) async {
    const planner = DetailedWorldviewQuestionPlanner();
    const coordinator = DetailedWorldviewGenerationCoordinator(
      planner: planner,
    );
    try {
      final result = await coordinator.generate(
        sourceText: sourceText,
        targetTotalCharacters: targetTotalCharacters,
        executeQuestion: (question) async {
          final prompt = _detailedQuestionPrompt(sourceText, question);
          final streamBuffer = StringBuffer();
          void onChunk(String chunk) {
            streamBuffer.write(chunk);
            onProgress?.call(DetailedWorldviewGenerationProgress(
              question: question,
              completedQuestions: question.questionIndex - 1,
              partialText: _extractStreamPreview(streamBuffer.toString()),
            ));
          }

          Future<String> requestQuestion(String instruction) => _callText(
                instruction,
                maximumOutputTokens: 8192,
                onChunk: onChunk,
              );

          String response;
          try {
            response = await requestQuestion(prompt);
          } catch (error) {
            if (!_isOutputTruncated(error)) rethrow;
            streamBuffer.clear();
            onProgress?.call(DetailedWorldviewGenerationProgress(
              question: question,
              completedQuestions: question.questionIndex - 1,
              partialText: '',
            ));
            response = await requestQuestion(
                _compactDetailedQuestionPrompt(sourceText, question));
          }
          final parsed = _parseDetailedQuestionResponse(response);
          if (parsed == null) {
            throw FormatException(
                '详细世界观第 ${question.questionIndex} 题返回了无效 JSON');
          }
          return parsed;
        },
        onProgress: onProgress,
      );
      return result;
    } catch (error) {
      rethrow;
    }
  }

  String _extractStreamPreview(String chunk) {
    final matches =
        RegExp(r'"content"\s*:\s*"((?:\\.|[^"\\])*)').allMatches(chunk);
    if (matches.isNotEmpty) {
      final encoded = '"${matches.last.group(1)!}"';
      try {
        return jsonDecode(encoded).toString();
      } catch (e, stack) {
        debugPrint('Error parsing NPC list: $e\n$stack');
        return matches.last.group(1)!.replaceAll(r'\n', '\n');
      }
    }

    // While the object-valued top-level `content` is still streaming, show
    // already-emitted human text instead of exposing JSON punctuation.
    final values = <String>[];
    for (final match
        in RegExp(r'"(?:name|description|content)"\s*:\s*"((?:\\.|[^"\\])*)')
            .allMatches(chunk)) {
      final encoded = '"${match.group(1)!}"';
      try {
        final value = jsonDecode(encoded).toString().trim();
        if (value.isNotEmpty && !values.contains(value)) values.add(value);
      } catch (e, stack) {
        debugPrint('Error parsing detailed question response: $e\n$stack');
      }
    }
    return values.join('\n');
  }

  /// Models occasionally wrap a valid object in prose or emit literal line
  /// breaks inside a JSON string. Keep this repair local to the current
  /// question; never send the invalid response back as a repair prompt.
  Map<String, dynamic>? _parseDetailedQuestionResponse(String response) {
    return StructuredJsonCodec.tryDecodeObject(response, repair: true);
  }

  /// Exposed for parser contract tests; generation always uses the private
  /// implementation above so malformed output is repaired per question.
  Map<String, dynamic>? parseDetailedWorldviewQuestionResponseForTesting(
          String response) =>
      _parseDetailedQuestionResponse(response);

  String _detailedQuestionPrompt(
      String sourceText, DetailedWorldviewQuestion question) {
    const contextPolicy = DetailedWorldviewContextPolicy();
    final moduleNames = question.modules.join('、');
    return '''你是详细世界观分片整理器。只处理本题模块：$moduleNames。
原始资料：${contextPolicy.briefSource(sourceText)}
本题编号：${question.questionIndex}/${question.totalQuestions}
当前主模块：${question.module}，分片：${question.part}/${question.totalParts}
本题目标约 ${question.targetCharacters} 个中文字，最多 ${question.maximumCharacters} 个中文字。
${question.dependsOnPreviousPart ? '这是连续分片，必须承接上一分片，不得重复已确认内容。' : '这是模块的首个分片。'}
只输出一个合法 JSON，不要 Markdown、candidates、完整世界观或解释文字：
{"question_index":${question.questionIndex},"total_questions":${question.totalQuestions},"module":"${question.module}","modules":${jsonEncode(question.modules)},"part":${question.part},"total_parts":${question.totalParts},"content":{"name":"","description":"","modules":{}},"status":"confirmed"}
content.modules 只能包含本题模块；未知内容留空或标记 draft，不得编造为 confirmed。''';
  }

  String _compactDetailedQuestionPrompt(
      String sourceText, DetailedWorldviewQuestion question) {
    final source =
        const DetailedWorldviewContextPolicy().briefSource(sourceText);
    return '''只输出一个合法 JSON 对象，不要 Markdown、解释或完整世界观。
问题 ${question.questionIndex}/${question.totalQuestions}，模块 ${question.modules.join('、')}，主模块 ${question.module}，分片 ${question.part}/${question.totalParts}。
content.modules 必须逐一填写上述全部模块且每个模块非空，总内容控制在 ${question.maximumCharacters} 字以内；status 必须为 confirmed。
原始资料：$source
JSON 契约：{"question_index":${question.questionIndex},"total_questions":${question.totalQuestions},"module":"${question.module}","modules":${jsonEncode(question.modules)},"part":${question.part},"total_parts":${question.totalParts},"content":{"modules":{}},"status":"confirmed"}''';
  }

  Future<Map<String, dynamic>> reviseWorldview({
    required Map<String, dynamic> worldview,
    required String instruction,
    String? moduleKey,
  }) async {
    final scope = moduleKey == null ? '整份世界观' : '仅模块：$moduleKey';
    final response = await _callText(
      '你是世界观编辑助手。$scope。只输出合法 JSON，不得改动未请求的模块。\n'
      '当前世界观：${jsonEncode(worldview)}\n用户修改要求：$instruction',
    );
    final parsed = AiAdventureUtils.parseJson(response);
    return parsed == null ? const {} : Map<String, dynamic>.from(parsed);
  }

  /// F4: 文字 → 角色卡
  /// [worldview] 当前世界观描述，确保生成的角色与世界观一致。
  /// [associatedCharacters] 关联的已有角色列表，新角色将与这些角色产生关系。
  Future<Map<String, String>> textToCharacterCard(String userPrompt,
      {String worldview = '',
      List<Map<String, String>> associatedCharacters = const [],
      LlmGenerationMode? generationMode}) async {
    final existingNames = associatedCharacters
        .map((c) => (c['name'] ?? '').trim())
        .where((n) => n.isNotEmpty)
        .toList();
    final noDupText = existingNames.isNotEmpty
        ? '\n⚠️【重要：严禁重名约束】当前已有角色姓名：${existingNames.join('、')}。新角色绝对不可使用上述任何已有姓名！必须构思独一无二的全新姓名！\n'
        : '';
    // 构建关联角色描述文本
    final associatedText = associatedCharacters.isNotEmpty
        ? '\n关联角色（新角色与这些角色存在关系）：\n${associatedCharacters.map((c) {
            final parts = <String>['名称：${c['name'] ?? ''}'];
            if ((c['gender'] ?? '').isNotEmpty) parts.add('性别：${c['gender']}');
            if ((c['profession'] ?? '').isNotEmpty) {
              parts.add('职业：${c['profession']}');
            }
            if ((c['personality'] ?? '').isNotEmpty) {
              parts.add('性格：${c['personality']}');
            }
            if ((c['background'] ?? '').isNotEmpty) {
              parts.add('背景：${c['background']}');
            }
            if ((c['bodyDescription'] ?? '').isNotEmpty) {
              parts.add('身材：${c['bodyDescription']}');
            }
            if ((c['appearance'] ?? '').isNotEmpty) {
              parts.add('外貌：${c['appearance']}');
            }
            if ((c['relation'] ?? c['relationship'] ?? '').isNotEmpty) {
              parts.add('与新角色的指定关系：${c['relation'] ?? c['relationship']}');
            }
            return '- ${parts.join('，')}';
          }).join('\n')}\n$noDupText\n请在生成时确保新角色与上述关联角色之间的关系自然合理。新角色的性格特征、职业定位与背景故事中必须深度契合上述指定关系与羁绊设定！\n'
        : '';

    final isCompanion = associatedCharacters.isNotEmpty;
    final roleInstruction =
        isCompanion ? '，作为冒险队伍中的重要伙伴或核心搭档' : '，作为玩家在冒险中扮演的主角';

    var genderHint = '';
    final trimmedPrompt = userPrompt.trim();
    if (trimmedPrompt.contains('女主') ||
        trimmedPrompt.contains('女主角') ||
        trimmedPrompt.contains('女性')) {
      genderHint = '\n⚠️【性别明确指定】用户指定该角色为【女性角色/女主角/核心女伴】，gender 字段必须为"女"！\n';
    } else if (trimmedPrompt.contains('男主') ||
        trimmedPrompt.contains('男主角') ||
        trimmedPrompt.contains('男性')) {
      genderHint = '\n⚠️【性别明确指定】用户指定该角色为【男性角色/男主角】，gender 字段必须为"男"！\n';
    }

    final prompt = _f4Prompt
        .replaceFirst('{roleInstruction}', roleInstruction)
        .replaceFirst('{genderHint}', genderHint)
        .replaceFirst('{userPrompt}', userPrompt)
        .replaceFirst(
            '{worldview}',
            worldview.isNotEmpty
                ? '\n当前世界观设定：\n$worldview\n\n请确保角色的出身、职业、性格、背景故事与世界观高度契合，角色必须是这个世界中自然存在的居民。'
                : '')
        .replaceFirst('{associatedCharacters}', associatedText);
    final response = await _callText(prompt, generationMode: generationMode);
    final result = _parseCharacterCardResponse(response);
    var name = result['name']?.trim() ?? '';
    if (existingNames.contains(name)) {
      final prof = result['profession']?.trim() ?? '';
      result['name'] = prof.isNotEmpty ? '$name·$prof' : '$name(副)';
    }
    return result;
  }

  /// 优化版角色设计详细模式生成：采用两阶段并行实现，提升生成效率。
  Future<Map<String, dynamic>> textToDetailedCharacterCard(
    String userPrompt, {
    String worldview = '',
    List<Map<String, String>> associatedCharacters = const [],
    int? targetTotalCharacters,
    void Function(int currentStage, int totalStages, String stageName)?
        onProgress,
    bool fastMode = false,
    LlmGenerationMode? generationMode,
  }) {
    if (targetTotalCharacters == null) {
      return _generateDetailedCharacterCard(
        userPrompt,
        worldview: worldview,
        associatedCharacters: associatedCharacters,
        onProgress: onProgress,
        fastMode: fastMode,
        generationMode: generationMode,
      );
    }
    final identity = ContentHasher.hashString(jsonEncode({
      'source': userPrompt,
      'targetCharacters': targetTotalCharacters,
      'worldview': worldview,
      'relationships': associatedCharacters,
      'fastMode': fastMode,
      'generationMode': generationMode?.name,
    }));
    final existing = _detailedCharacterFlights[identity];
    if (existing != null) return existing;

    late final Future<Map<String, dynamic>> flight;
    flight = _generateDetailedCharacterCard(
      userPrompt,
      worldview: worldview,
      associatedCharacters: associatedCharacters,
      targetTotalCharacters: targetTotalCharacters,
      onProgress: onProgress,
      fastMode: fastMode,
      generationMode: generationMode,
    ).whenComplete(() {
      if (identical(_detailedCharacterFlights[identity], flight)) {
        _detailedCharacterFlights.remove(identity);
      }
    });
    _detailedCharacterFlights[identity] = flight;
    return flight;
  }

  Future<Map<String, dynamic>> _generateDetailedCharacterCard(
    String userPrompt, {
    String worldview = '',
    List<Map<String, String>> associatedCharacters = const [],
    int? targetTotalCharacters,
    void Function(int currentStage, int totalStages, String stageName)?
        onProgress,
    bool fastMode = false,
    LlmGenerationMode? generationMode,
  }) async {
// Fast mode: single call using textToCharacterCard
    if (fastMode) {
      final basic = await textToCharacterCard(
        userPrompt,
        worldview: worldview,
        associatedCharacters: associatedCharacters,
        generationMode: generationMode,
      );
      final initial = <String, dynamic>{
        'name': basic['name'] ?? '',
        'gender': basic['gender'] ?? '',
        'age': basic['age'] ?? '',
        'profession': basic['profession'] ?? '',
        'archetype': '',
        'personality': basic['personality'] ?? '',
        'appearance': basic['appearance'] ?? '',
        'bodyDescription': '',
        'description': '',
        'background': basic['background'] ?? '',
        'world_profile': basic['world_profile'] ?? '{}',
      };
      if (targetTotalCharacters == null) return initial;
      return _completeDetailedCharacterCard(
        initial: initial,
        userPrompt: userPrompt,
        worldview: worldview,
        associatedCharacters: associatedCharacters,
        targetTotalCharacters: targetTotalCharacters,
        onProgress: onProgress,
        generationMode: generationMode,
      );
    }
    const systemPrompt =
        '你是一位顶级的文字冒险角色设计师。你将通过多阶段推演，逐步塑造出一个血肉丰满、拥有深度心理矛盾与独特弧光的生动角色。'
        '【核心最高准则】：当用户提供了具体的人物设定或生平背景材料时，你必须高度忠实于用户的原文设定，严格优先提取、梳理并结构化用户材料中的角色中文名、性别、年龄、职业/身份、性格特质与生平过往，严禁脱离原文凭空捏造、篡改或替换用户已明确设定的内容！只有在原文未提及的空白细节处，才允许在完全遵循原文基调与逻辑的前提下进行合理推演补充。'
        '在每一轮对话中，你必须严格输出合法的 JSON 格式，不要包含任何非 JSON 的解释文字或 Markdown 标签之外的内容。';

    // Runs one stage with its own immutable message snapshot.
    //
    // [confirmedResults] carries the already accepted results of the previous
    // stages, so a later stage always sees the confirmed history instead of a
    // list that another stage is still mutating.
    Future<DetailedCharacterStagePayload> executeTurn({
      required CharacterGenerationStage stage,
      required String stageName,
      required String userInstruction,
      required List<Map<String, dynamic>> confirmedResults,
      bool reportProgress = true,
    }) async {
      if (reportProgress) {
        onProgress?.call(1, 2, stageName);
      }
      final parsed = await _runCharacterStage(
        stage: stage,
        stageLabel: stageName,
        systemPrompt: systemPrompt,
        confirmedResults: confirmedResults,
        userInstruction: userInstruction,
        generationMode: generationMode,
      );
      if (reportProgress) {
        onProgress?.call(2, 2, stageName);
      }
      return parsed;
    }

    // ---------- Stage 1：身份与性格 ----------
    final wvSection =
        worldview.trim().isNotEmpty ? '【契合世界观背景设定】\n$worldview\n' : '';
    final existingNames = associatedCharacters
        .map((c) => (c['name'] ?? '').trim())
        .where((n) => n.isNotEmpty)
        .toList();
    final noDuplicateNameRule = existingNames.isNotEmpty
        ? '⚠️【重要：严禁重名约束】当前已有角色姓名：${existingNames.join('、')}。新设计的角色姓名绝对不可与上述角色重名！必须构思一个完全不同的独创姓名！\n'
        : '';
    final assocSection = associatedCharacters.isNotEmpty
        ? '【已有关联角色与指定羁绊】\n${associatedCharacters.map((c) {
            final name = c['name'] ?? '';
            final role = (c['profession'] ?? c['role'] ?? '').trim();
            final pers = (c['personality'] ?? '').trim();
            final rel = (c['relation'] ?? c['relationship'] ?? '').trim();
            final details = [
              if (role.isNotEmpty) role,
              if (pers.isNotEmpty) pers,
              if (rel.isNotEmpty) '与新角色设定关系：$rel',
            ].join('，');
            return details.isNotEmpty ? '- $name：$details' : '- $name';
          }).join('\n')}\n请在构思新角色时，务必使其人物原型、行为动机与上述关联角色（特别是指定关系）形成鲜明的戏剧互动张力！\n$noDuplicateNameRule'
        : '';

    final t1Prompt = '''
基于以下世界观背景与要求，提炼或设计角色的核心身份定位与矛盾心理原型：
$wvSection$assocSection【用户材料与需求】：
$userPrompt

【严格提取与设计要求】：
1. 若用户材料中明确提供了角色中文姓名、性别、年龄或职业，必须严格忠实提取原文，严禁擅自篡改或替换；
2. 仅在材料未指定之处，遵循世界观文化进行独创构思，严禁与已有角色重名；
3. 严格输出单层 JSON 格式：
{
  "name": "角色中文姓名（若材料中已提供姓名则必须严格使用原文姓名；若未提供则构思契合世界观的姓名）",
  "gender": "男 或 女 或 其他（优先严格提取自材料）",
  "age": "年龄（优先严格提取自材料，如：24 或 120岁）",
  "profession": "职业或社会身份（优先严格提取自材料，必须契合世界观）",
  "archetype": "核心人物原型（如：背负宿命的叛逆者、渴望救赎的守护者）",
  "personality": "深入性格剖析：包括表面处世态度、真实本性、价值准则与内心深处的矛盾弱点（150~350字，忠实提炼并整合原文）"
}
''';
    // The normalizer returns the concrete payload for each stage, so these
    // casts are total and never inspect a raw provider map.
    final t1 = await executeTurn(
      stage: CharacterGenerationStage.identity,
      stageName: '身份与性格',
      userInstruction: t1Prompt,
      confirmedResults: const [],
    ) as CharacterIdentityPayload;
    var name = t1.name;
    if (existingNames.contains(name)) {
      name = t1.profession.isNotEmpty ? '$name·${t1.profession}' : '$name(副)';
    }
    final gender = t1.gender;
    final age = t1.age;
    final profession = t1.profession;
    final archetype = t1.archetype;
    final personality = t1.personality;

    // ---------- Stage 2：并行外貌 & 背景 ----------
    final t2aPrompt = '''
基于已确定的角色身份「$name（$gender，$age，$profession）」及其矛盾性格，以及【用户材料与需求】，请提取并细化角色的生动外貌肖像与身材体格特征。服饰、五官、气质必须与其职业、性格、世界观文化高度呼应。

【用户材料与需求】：
$userPrompt

【提取与设计要求】：
1. 优先提取材料中描写的面容、发色、瞳色、常穿服饰、随身物件与身材体态；
2. 严格输出单层 JSON 格式：
{
  "appearance": "面容五官、发型发色、眼神气质、神情常态、常穿服饰与随身标志性信物/装备（150~350字，结合材料提炼）",
  "bodyDescription": "身高身姿、体格力量感、肤色体态、特殊伤疤/刺青/生理异质或改造印记（100~250字，结合材料提炼）"
}
''';
    // Build association info for turn 3 marker
    final turn3AssocInfo = associatedCharacters
        .map((c) {
          final name = c['name'] ?? '';
          final rel = c['relation'] ?? c['relationship'] ?? '';
          return name.isNotEmpty && rel.isNotEmpty ? '$name（设定关系：$rel）' : name;
        })
        .where((s) => s.isNotEmpty)
        .join('，');

    final t2bPrompt = '''
基于已确认的身份、性格与外貌，以及【用户材料与需求】，请深入推演角色的身世背景、深层动机、能力来源与代价、所属阵营、出生地、禁忌以及与关联角色的关系描述。请确保与世界观深度融合。

【用户材料与需求】：
$userPrompt

【重要：羁绊背景融合】关联角色信息：$turn3AssocInfo

【提取与设计要求】：
1. 必须严格优先提取用户材料中的生平经历、所属阵营、特长能力、宿命危机与关键人际关系，严禁抹除用户设定的关键剧情；
2. 严格输出单层 JSON 格式：
{
  "description": "生平背景经历：过去的成长环境、决定命运的重大转折点、现在的处境与羁绊（提炼自原文并详尽展开，200~500字）",
  "public_goal": "公开宣称的行动使命或目标（30~100字）",
  "hidden_motivation": "内心深处驱动自己的隐秘渴望、执念或恐惧（30~100字）",
  "ability_source": "所拥有的特殊能力/专长/技能的来源、师承或磨砺背景（50~200字）",
  "ability_cost": "施展能力或生存必须付出的代价、代价反噬、生理心理弱点或局限（40~150字）",
  "faction": "所属势力组织或立场阵营（优先提取自原文）",
  "home_location": "出生地、故乡或经常活动的常驻据点（优先提取自原文）",
  "taboos": ["禁忌1", "禁忌2"],
  "relationship_notes": "在世界中与关键势力、地点或关联角色的纠葛与态度（50~200字）"
}
''';
    // Stage 2 runs strictly sequentially: Stage2B must see the confirmed
    // Stage1 and Stage2A results, so the two turns can never share a mutable
    // message list the way the previous `Future.wait` design did.
    onProgress?.call(1, 2, '外貌与体态');
    final t2a = await executeTurn(
      stage: CharacterGenerationStage.appearance,
      stageName: '外貌与体态',
      userInstruction: t2aPrompt,
      confirmedResults: [t1.toCanonicalJson()],
      reportProgress: false,
    ) as CharacterAppearancePayload;
    onProgress?.call(2, 2, '背景与深层设定');
    final t2b = await executeTurn(
      stage: CharacterGenerationStage.backgroundWorld,
      stageName: '背景与深层设定',
      userInstruction: t2bPrompt,
      confirmedResults: [t1.toCanonicalJson(), t2a.toCanonicalJson()],
      reportProgress: false,
    ) as CharacterBackgroundPayload;
    onProgress?.call(2, 2, '外貌与背景');

    // Every field is read from a typed payload: the normalizer already
    // guarantees the canonical String/List<String> contract, so there is no
    // `as String?` cast left that could throw after validation passed.
    final appearance = t2a.appearance;
    final bodyDescription = t2a.bodyDescription;
    final description = t2b.description;
    final publicGoal = t2b.publicGoal;
    final hiddenMotivation = t2b.hiddenMotivation;
    final abilitySource = t2b.abilitySource;
    final abilityCost = t2b.abilityCost;
    final faction = t2b.faction;
    final homeLocation = t2b.homeLocation;
    final taboosList = t2b.taboos;
    final relationshipNotes = t2b.relationshipNotes;

    // ---------- Assemble Result ----------
    final initial = <String, dynamic>{
      'name': name,
      'gender': gender,
      'age': age,
      'profession': profession,
      'archetype': archetype,
      'personality': personality,
      'appearance': appearance,
      'bodyDescription': bodyDescription,
      'description': description,
      'background': description,
      'world_profile': {
        'faction': faction,
        'home_location': homeLocation,
        'public_goal': publicGoal,
        'hidden_motivation': hiddenMotivation,
        'ability_source': abilitySource,
        'ability_cost': abilityCost,
        'taboos': taboosList,
        'relationship_notes': relationshipNotes,
      },
    };
    if (targetTotalCharacters == null) return initial;
    return _completeDetailedCharacterCard(
      initial: initial,
      userPrompt: userPrompt,
      worldview: worldview,
      associatedCharacters: associatedCharacters,
      targetTotalCharacters: targetTotalCharacters,
      onProgress: onProgress,
      generationMode: generationMode,
    );
  }

  /// Calls one detailed-character stage and validates its schema.
  ///
  /// Every attempt builds a brand new message list, so a retry never mutates a
  /// snapshot another stage (or a concurrent generation) is still using. Only
  /// the current stage is re-run: the confirmed results of earlier stages are
  /// replayed as assistant turns instead of being regenerated.
  Future<DetailedCharacterStagePayload> _runCharacterStage({
    required CharacterGenerationStage stage,
    required String stageLabel,
    required String systemPrompt,
    required List<Map<String, dynamic>> confirmedResults,
    required String userInstruction,
    required LlmGenerationMode? generationMode,
  }) async {
    // Content budget: the first call plus the bounded retries below. Each
    // attempt uses the (smaller) transport budget for transient network
    // failures, so the two budgets stay finite and independently auditable.
    final maximumAttempts = RetryBudget.structuredJson.contentStageAttempts;
    for (var attempt = 1; attempt <= maximumAttempts; attempt++) {
      final messages = <Map<String, dynamic>>[
        {'role': 'system', 'content': systemPrompt},
        for (final result in confirmedResults)
          {'role': 'assistant', 'content': jsonEncode(result)},
        {'role': 'user', 'content': userInstruction},
      ];
      String response;
      try {
        response = await _callMessages(
          messages,
          maximumOutputTokens: 8192,
          generationMode: generationMode,
          expectJsonObject: true,
          maximumAttempts: RetryBudget.structuredJson.transportAttempts,
        );
      } on GenerationCancelledException {
        // A user cancellation must never be swallowed by a stage retry.
        rethrow;
      } catch (_) {
        continue;
      }
      final parsed = StructuredJsonCodec.tryDecodeObject(response);
      if (parsed == null) continue;
      final payload = DetailedCharacterStageNormalizer.normalize(stage, parsed);
      if (payload != null) return payload;
    }
    throw FormatException(
      '角色设计阶段 $stageLabel 在 $maximumAttempts 次尝试后'
      '仍未返回符合结构约定的 JSON',
    );
  }

  Future<Map<String, dynamic>> _completeDetailedCharacterCard({
    required Map<String, dynamic> initial,
    required String userPrompt,
    required String worldview,
    required List<Map<String, String>> associatedCharacters,
    required int targetTotalCharacters,
    void Function(int currentStage, int totalStages, String stageName)?
        onProgress,
    LlmGenerationMode? generationMode,
  }) async {
    const coordinator = DetailedCharacterGenerationCoordinator();
    return coordinator.complete(
      initial: initial,
      targetTotalCharacters: targetTotalCharacters,
      requestSupplement: (candidate, report) async {
        final response = await _callText(
          _characterSupplementPrompt(
            candidate: candidate,
            report: report,
            userPrompt: userPrompt,
            worldview: worldview,
            associatedCharacters: associatedCharacters,
          ),
          maximumOutputTokens: 8192,
          generationMode: generationMode,
          expectJsonObject: true,
          maximumAttempts: RetryBudget.structuredJson.transportAttempts,
        );
        final supplement = StructuredJsonCodec.tryDecodeObject(response);
        if (supplement == null) {
          throw const CharacterCandidateFormatException('角色补全返回了无效 JSON');
        }
        return supplement;
      },
      onProgress: (progress) => onProgress?.call(
        progress.phase == CharacterGenerationPhase.completed
            ? 10
            : 2 + progress.supplementRound,
        10,
        progress.phase == CharacterGenerationPhase.completed
            ? '详细角色卡已完成'
            : '当前有效内容 ${progress.currentCharacters} / '
                '${progress.targetCharacters}；仍需完善：'
                '${progress.weakModules.join('、')}',
      ),
    );
  }

  String _characterSupplementPrompt({
    required Map<String, dynamic> candidate,
    required CharacterCardGenerationReport report,
    required String userPrompt,
    required String worldview,
    required List<Map<String, String>> associatedCharacters,
  }) {
    final profile = candidate['world_profile'] is Map
        ? Map<String, dynamic>.from(candidate['world_profile'] as Map)
        : <String, dynamic>{};
    final relations = associatedCharacters
        .map((item) =>
            '${item['name'] ?? ''}：${item['relation'] ?? item['relationship'] ?? ''}')
        .where((item) => item != '：')
        .join('\n');
    return '''
这是同一张角色卡的增量补全，不是重新设计角色。只返回 JSON 增量，绝不输出 Markdown。

用户原文事实优先级最高；不得改写用户提供的姓名、性别、年龄、职业，也不得改写下列冻结身份：
- name: ${candidate['name'] ?? ''}
- gender: ${candidate['gender'] ?? ''}
- age: ${candidate['age'] ?? ''}
- profession: ${candidate['profession'] ?? ''}

当前有效正文：${report.currentCharacters}；目标：${report.targetCharacters}。
当前薄弱模块：${report.weakModules.join('、')}。
用户原文：$userPrompt
世界观硬约束：$worldview
关联角色及各自关系：$relations
已确认角色卡：${jsonEncode({...candidate, 'world_profile': profile})}

只补充薄弱模块，避免复述已有内容。world_profile 只写角色自己的世界定位，不得复制完整世界观。普通人可令 ability 为 not_applicable。
若薄弱模块包含 roleplayBehavior（或 scenario / first_mes / mes_example 任一缺失），必须在本次增量中至少给出 scenario、first_mes、mes_example 这三项中的【任意两项或全部三项】；仅返回其中一项会被判定为薄弱并触发再次补全。
这两项（或三项）去掉空白后的合计字符数必须不少于 180 字，每项都应是可以直接用于稳定 RP 的完整内容，不得是占位符或空串。
可返回字段：personality、description、appearance、bodyDescription、scenario、first_mes、mes_example、ability、weakness、equipment、custom_attributes、world_profile。world_profile 可含 faction、home_location、public_goal、hidden_motivation、secrets、ability_source、ability_cost、taboos、relationship_notes。
''';
  }

  /// 对话模式专用：根据用户要求整理长期聊天角色卡，不引入场景资料。
  Future<Map<String, String>> textToConversationCharacterCard(
      String userPrompt) async {
    final prompt = _conversationCharacterPrompt.replaceFirst(
      '{userPrompt}',
      userPrompt,
    );
    final response = await _callText(prompt);
    return _parseConversationCharacterResponse(response);
  }

  /// F6: 文字 → 开场场景 + 选项
  /// 根据用户偏好（最高优先级）、角色卡+NPC（第二优先级）、世界观（最低优先级），
  /// 生成开场场景叙述和初始行动选项。
  /// 权重体系为内部配置，UI不可见。
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
  }) async {
    final charExtra = [
      if (protagonistPersonality.isNotEmpty) '性格：$protagonistPersonality',
      if (protagonistAppearance.isNotEmpty) '外貌：$protagonistAppearance',
    ].join('\n');

    final selectedCharacterSection =
        _buildSelectedCharacterSection(selectedCharacters);
    final relationshipSection =
        _buildRelationshipSection(characterRelationships);

    // 构建 NPC 上下文（独立于角色卡，不可混用）
    final npcSection = npcs.isNotEmpty
        ? '\n出场NPC：\n${npcs.map((n) {
            final parts = <String>[];
            if ((n['name'] ?? '').isNotEmpty) parts.add('名称：${n['name']}');
            if ((n['role'] ?? '').isNotEmpty) parts.add('身份：${n['role']}');
            if ((n['personality'] ?? '').isNotEmpty) {
              parts.add('性格：${n['personality']}');
            }
            if ((n['relation'] ?? '').isNotEmpty) {
              parts.add('与主角关系：${n['relation']}');
            }
            return '- ${parts.join('，')}';
          }).join('\n')}\n**原则：NPC应按照用户偏好的要求出场布置，角色关系应符合设定。**'
        : '';

    final prompt = _f6Prompt
        .replaceFirst('{userPrompt}', userPrompt)
        .replaceFirst('{worldview}', worldview)
        .replaceFirst('{protagonistName}', protagonistName)
        .replaceFirst('{protagonistRole}', protagonistRole)
        .replaceFirst(
            '{protagonistExtra}', charExtra.isNotEmpty ? '\n$charExtra' : '')
        .replaceFirst('{selectedCharacters}', selectedCharacterSection)
        .replaceFirst('{characterRelationships}', relationshipSection)
        .replaceFirst('{npcs}', npcSection);

    final response = await _callText(prompt);
    return _parseOpeningResponse(response);
  }

  Map<String, String> _parseOpeningResponse(String response) {
    final json = AiAdventureUtils.parseJson(response);
    if (json != null) {
      final options = json['options'];
      String optionsText;
      if (options is List) {
        optionsText = options
            .asMap()
            .entries
            .map((e) => '${e.key + 1} ${e.value}')
            .join('\n');
      } else {
        optionsText = options?.toString() ?? '';
      }
      return {
        'scene': (json['scene'] as String?) ?? response.trim(),
        'options': optionsText,
      };
    }
    return {
      'scene': response.trim(),
      'options': '',
    };
  }

  /// F5: 文字 → 批量 NPC
  /// 根据世界观和主角信息，一次生成多个 NPC（3~6个）。
  /// [associatedCharacters] 关联的已有角色列表，新 NPC 将与这些角色产生关系。
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
  }) async {
    final existingDesc = existingNpcs.isEmpty
        ? ''
        : '\n已有的 NPC：\n${existingNpcs.map((n) => '- ${n["name"] ?? ""}（${n["role"] ?? ""}）').join("\n")}\n请生成与已有 NPC 不重复的新角色。';

    final charExtra = [
      if (protagonistPersonality.isNotEmpty) '性格：$protagonistPersonality',
      if (protagonistBackground.isNotEmpty) '背景：$protagonistBackground',
      if (protagonistBodyDescription.isNotEmpty)
        '身材：$protagonistBodyDescription',
      if (protagonistAppearance.isNotEmpty) '外貌：$protagonistAppearance',
    ].join('\n');

    final selectedCharacterSection =
        _buildSelectedCharacterSection(selectedCharacters);
    final relationshipSection =
        _buildRelationshipSection(characterRelationships);

    // 构建关联角色描述文本
    final associatedText = associatedCharacters.isNotEmpty
        ? '\n关联角色（新 NPC 与这些角色存在关系）：\n${associatedCharacters.map((c) {
            final parts = <String>['名称：${c['name'] ?? ''}'];
            if ((c['gender'] ?? '').isNotEmpty) parts.add('性别：${c['gender']}');
            if ((c['profession'] ?? '').isNotEmpty) {
              parts.add('职业：${c['profession']}');
            }
            if ((c['personality'] ?? '').isNotEmpty) {
              parts.add('性格：${c['personality']}');
            }
            if ((c['appearance'] ?? '').isNotEmpty) {
              parts.add('外貌：${c['appearance']}');
            }
            return '- ${parts.join('，')}';
          }).join('\n')}\n\n请在生成时确保新 NPC 与上述关联角色之间的关系自然合理。用户在提示词中会写明具体关系类型。\n'
        : '';

    final prompt = _f5Prompt
        .replaceFirst('{userPrompt}', userPrompt)
        .replaceFirst('{worldview}', worldview)
        .replaceFirst('{protagonistName}', protagonistName)
        .replaceFirst('{protagonistRole}', protagonistRole)
        .replaceFirst(
            '{protagonistExtra}', charExtra.isNotEmpty ? '\n$charExtra' : '')
        .replaceFirst('{selectedCharacters}', selectedCharacterSection)
        .replaceFirst('{characterRelationships}', relationshipSection)
        .replaceFirst('{existingNpcs}', existingDesc)
        .replaceFirst('{associatedCharacters}', associatedText);

    final response = await _callText(prompt);
    return _parseNpcsResponse(response);
  }

  /// 创作资料库专用结构化导入。与冒险模式的简化字段保持独立，避免接口漂移。
  Future<Map<String, dynamic>> textToCreationWorld(String userPrompt) async {
    final response = await _callText(
        _creationWorldPrompt.replaceFirst('{source}', userPrompt));
    return _parseCreationObject(response);
  }

  Future<Map<String, dynamic>> textToCreationCharacter(
    String userPrompt, {
    String worldview = '',
    List<Map<String, dynamic>> associatedCharacters = const [],
    GenerationTaskHandle? taskHandle,
    int maximumOutputTokens = 8192,
  }) async {
    final related =
        associatedCharacters.map((item) => jsonEncode(item)).join('\n');
    final prompt = _creationCharacterPrompt
        .replaceFirst('{source}', userPrompt)
        .replaceFirst('{worldview}', worldview)
        .replaceFirst('{related}', related);
    final response = await _callText(
      prompt,
      maximumOutputTokens: maximumOutputTokens,
      taskHandle: taskHandle,
    );
    return _parseCreationObject(response);
  }

  Future<List<String>> identifyCharacterNames(
    String source, {
    GenerationTaskHandle? taskHandle,
    int maximumOutputTokens = 1024,
  }) async {
    final response = await _callText(
      '你是角色名称识别器兼角色名称审查器。先提取原文明确出现的人名到 facts；再给出'
      '可由别名、称谓或上下文推断的角色到 fuzzy。不要把地点、组织、称号或'
      '泛指人群当角色。只输出合法 JSON，不要解释。\n'
      '用户资料：$source\n'
      '{"facts":["明确姓名"],"fuzzy":[{"name":"推断姓名"}]}',
      maximumOutputTokens: maximumOutputTokens,
      taskHandle: taskHandle,
    );
    final parsed = AiAdventureUtils.parseJson(response);
    if (parsed == null) return const [];
    final names = <String>[];
    final seen = <String>{};
    void add(Object? value) {
      final name = switch (value) {
        String s => s.trim(),
        Map m when m['name'] is String => (m['name'] as String).trim(),
        _ => '',
      };
      if (name.isEmpty) return;
      final key = name.replaceAll(RegExp(r'\s+'), '').toLowerCase();
      if (seen.add(key)) names.add(name);
    }

    final facts = parsed['facts'] ?? parsed['names'];
    if (facts is List) {
      for (final f in facts) {
        add(f);
      }
    }
    final fuzzy = parsed['fuzzy'];
    if (fuzzy is List) {
      for (final f in fuzzy) {
        add(f);
      }
    }
    return names;
  }

  /// 场景资料库单候选生成角色/NPC。
  ///
  /// 批量导入由应用层逐候选调用本方法，使单张长卡独占一次结构化响应，避免
  /// 一次请求生成多张 5000 字卡片导致的截断与整批失败。[maximumTotalLength]
  /// 决定输出预算，`expectJsonObject` 保证截断/未完成的响应被拒绝而不是当作
  /// 半成品保存。
  Future<Map<String, dynamic>> generateSceneBatchCharacter({
    required String source,
    required String label,
    required String worldview,
    required List<Map<String, dynamic>> relatedCharacters,
    required SceneBatchCandidate candidate,
    required int minimumTotalLength,
    required int maximumTotalLength,
    required String detailInstruction,
  }) async {
    final response = await _callText(
      '你是小说资料编辑。仅依据用户原文提取$label：${candidate.displayName}'
      '（sourceId=${candidate.sourceId}），不得编造。'
      '世界观：$worldview\n原文：$source\n'
      '允许关联的已有角色：${jsonEncode(relatedCharacters)}\n'
      '该资料总字数必须为 $minimumTotalLength-$maximumTotalLength，'
      '且 sourceId 必须原样回传。\n$detailInstruction\n'
      '只输出 JSON：{"sourceId":"${candidate.sourceId}","name":"","gender":"",'
      '"age":"","profession":"","personality":"","description":"",'
      '"appearance":"","relationship_summary":"","relationship_links":[]}。'
      'relationship_links 每项必须含 targetResourceId、relationType、description，'
      '其中 targetResourceId 只能取自上文的已有角色 id，仅可记录原文明确的关系；没有则为空数组。',
      maximumOutputTokens: _sceneBatchOutputBudget(maximumTotalLength),
      expectJsonObject: true,
    );
    final parsed = AiAdventureUtils.parseJson(response);
    if (parsed == null) {
      throw const FormatException('批量资料生成结果格式无效');
    }
    return Map<String, dynamic>.from(parsed);
  }

  /// 单张卡片的输出预算：中文约每字 1–2 token，另留 JSON 结构开销。
  /// 上限避免单次请求预算无限膨胀。
  int _sceneBatchOutputBudget(int maximumTotalLength) =>
      (maximumTotalLength * 2 + 1024).clamp(2048, 16384);

  Future<List<Map<String, dynamic>>> textToCreationNpcs(
    String userPrompt, {
    String worldview = '',
    List<Map<String, dynamic>> associatedCharacters = const [],
  }) async {
    final prompt = _creationNpcPrompt
        .replaceFirst('{source}', userPrompt)
        .replaceFirst('{worldview}', worldview)
        .replaceFirst(
            '{related}', associatedCharacters.map(jsonEncode).join('\n'));
    final response = await _callText(prompt);
    final parsed = AiAdventureUtils.parseJson(response);
    final list = parsed?['npcs'];
    if (list is List) {
      return list
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .where((item) => (item['name']?.toString() ?? '').trim().isNotEmpty)
          .toList();
    }
    return const [];
  }

  Map<String, dynamic> _parseCreationObject(String response) {
    final parsed = AiAdventureUtils.parseJson(response);
    if (parsed == null) return {'name': '', 'summary': response.trim()};
    return Map<String, dynamic>.from(parsed);
  }

  /// 解析批量 NPC JSON 数组响应
  List<Map<String, String>> _parseNpcsResponse(String response) {
    final json = AiAdventureUtils.parseJson(response);
    if (json != null && json['npcs'] is List) {
      final list = (json['npcs'] as List)
          .whereType<Map<String, dynamic>>()
          .map((npc) => {
                'name': (npc['name'] as String?) ?? '',
                'gender': (npc['gender'] as String?) ?? '',
                'role': (npc['role'] as String?) ?? '',
                'personality': (npc['personality'] as String?) ?? '',
                'relation': (npc['relation'] as String?) ?? '',
              })
          .where((npc) => (npc['name'] ?? '').isNotEmpty)
          .toList();
      if (list.isNotEmpty) return list;
    }
    // 尝试作为 JSON 数组解析
    try {
      final arr = jsonDecode(response) as List<dynamic>;
      return arr
          .whereType<Map<String, dynamic>>()
          .map((npc) => {
                'name': (npc['name'] as String?) ?? '',
                'gender': (npc['gender'] as String?) ?? '',
                'role': (npc['role'] as String?) ?? '',
                'personality': (npc['personality'] as String?) ?? '',
                'relation': (npc['relation'] as String?) ?? '',
              })
          .where((npc) => (npc['name'] ?? '').isNotEmpty)
          .toList();
    } catch (_) {}
    return [];
  }

  // ─── 核心调用 ───

  Future<String> _callVision(String base64, String prompt) async {
    final content = jsonEncode([
      {
        'type': 'image_url',
        'image_url': {'url': 'data:image/jpeg;base64,$base64'}
      },
      {'type': 'text', 'text': prompt}
    ]);

    final messages = [
      {'role': 'user', 'content': content}
    ];

    final buffer = StringBuffer();
    await _llm.sendMessageStream(
      messages,
      (chunk) => buffer.write(chunk),
      () {},
      // 图片信息抽取是短辅助任务：显式关闭思考。
      params: const CompletionParams(
        temperature: 0.7,
        maxTokens: 8192,
        enableThinking: false,
      ),
    );
    return buffer.toString();
  }

  /// Validates and normalises one streamed LLM response.
  ///
  /// [expectJsonObject] marks calls whose caller requires a structured JSON
  /// object (generation stages, supplements). Such a response must be **fully
  /// completed** before any repair is attempted: closing a brace proves only
  /// that the prefix is syntactically recoverable, not that the model emitted
  /// every field. A truncated/interrupted structured response therefore throws
  /// [StructuredOutputIncompleteException] so the current stage's bounded
  /// content retry re-requests it instead of canonicalising a half-written
  /// object into a card.
  ///
  /// Once complete, the response is returned as **canonical JSON**, so the
  /// value can always be decoded again downstream. Prose calls keep the
  /// previous behaviour and return the raw text.
  String _resolveContent(
    LLMStreamResult result, {
    required bool expectJsonObject,
  }) {
    final content = result.content;
    // P0-2: a structured response must be fully completed before any repair.
    // `isTruncated` (length/maxTokens) is already a subset of the non-parseable
    // reasons, but it is listed explicitly so the truncation contract stays
    // visible at the call site and cannot regress silently if `allowsParsing`
    // ever widens. This mirrors the generic LLMService stream guard.
    if (expectJsonObject &&
        (!result.responseCompleted ||
            !result.finishReason.allowsParsing ||
            result.finishReason.isTruncated)) {
      throw const StructuredOutputIncompleteException();
    }
    final parsed = content.trim().isEmpty
        ? null
        : (StructuredJsonCodec.tryDecodeObject(content, repair: true) ??
            StructuredJsonCodec.tryDecodeObject(
              _repairTruncatedJson(content),
              repair: true,
            ));
    if (expectJsonObject) {
      if (parsed == null || parsed.isEmpty) {
        throw StateError(structuredJsonFailureMessage);
      }
      return jsonEncode(parsed);
    }
    if (content.trim().isNotEmpty && parsed != null && parsed.isNotEmpty) {
      return content;
    }
    if (!result.responseCompleted ||
        !result.finishReason.allowsParsing ||
        result.finishReason.isTruncated) {
      throw StateError('模型响应未完整完成，不能使用部分结果');
    }
    return content;
  }

  Future<String> _callText(
    String prompt, {
    int maximumOutputTokens = 8192,
    double temperature = .8,
    GenerationTaskHandle? taskHandle,
    void Function(String chunk)? onChunk,
    LlmGenerationMode? generationMode,
    bool expectJsonObject = false,
    int maximumAttempts = defaultMaximumTransportAttempts,
  }) async {
    final messages = [
      {'role': 'user', 'content': AiAdventureUtils.sanitizeForJson(prompt)}
    ];

    final isJson = prompt.toLowerCase().contains('json');
    return RetryManager.withRetry(
      () async {
        final result = await _llm.sendMessageStreamDetailed(
          messages,
          (chunk) {
            onChunk?.call(chunk);
          },
          () {},
          params: CompletionParams(
            temperature: temperature,
            maxTokens: maximumOutputTokens,
            enableThinking: generationMode == LlmGenerationMode.deepThinking,
            responseFormat: isJson ? const {'type': 'json_object'} : null,
          ),
          taskHandle: taskHandle,
        );
        return _resolveContent(result, expectJsonObject: expectJsonObject);
      },
      maximumAttempts: maximumAttempts,
      // Transport layer retries only transient network failures. Content
      // failures (empty/invalid/truncated JSON, schema or semantic errors)
      // deliberately fall through to the caller's content budget so the two
      // budgets never overlap. Cancellation is never retried.
      shouldRetry: (err) {
        if (err is GenerationCancelledException) return false;
        return TransportRetryPolicy.shouldRetry(err);
      },
    );
  }

  Future<String> _callMessages(
    List<Map<String, dynamic>> messages, {
    int maximumOutputTokens = 8192,
    double temperature = .7,
    GenerationTaskHandle? taskHandle,
    void Function(String chunk)? onChunk,
    LlmGenerationMode? generationMode,
    bool expectJsonObject = false,
    int maximumAttempts = defaultMaximumTransportAttempts,
  }) async {
    final sanitizedMessages = messages.map((m) {
      final role = m['role']?.toString() ?? 'user';
      final content = m['content']?.toString() ?? '';
      return {
        'role': role,
        'content': AiAdventureUtils.sanitizeForJson(content),
      };
    }).toList();

    final isJson = messages.any(
        (m) => (m['content']?.toString() ?? '').toLowerCase().contains('json'));

    return RetryManager.withRetry(
      () async {
        final result = await _llm.sendMessageStreamDetailed(
          sanitizedMessages,
          (chunk) {
            onChunk?.call(chunk);
          },
          () {},
          params: CompletionParams(
            temperature: temperature,
            maxTokens: maximumOutputTokens,
            enableThinking: generationMode == LlmGenerationMode.deepThinking,
            responseFormat: isJson ? const {'type': 'json_object'} : null,
          ),
          taskHandle: taskHandle,
        );
        return _resolveContent(result, expectJsonObject: expectJsonObject);
      },
      maximumAttempts: maximumAttempts,
      shouldRetry: (err) {
        if (err is GenerationCancelledException) return false;
        return TransportRetryPolicy.shouldRetry(err);
      },
    );
  }

  bool _isOutputTruncated(Object error) =>
      error.toString().contains('outputTruncated');

  // ─── 响应解析 ───

  Map<String, String> _parseWorldviewResponse(String response) {
    final json = AiAdventureUtils.parseJson(response);
    if (json != null) {
      return {
        'name': (json['name'] as String?) ?? '未命名世界观',
        'description': (json['description'] as String?) ?? response.trim(),
      };
    }
    return {
      'name': 'AI 生成的世界观',
      'description': response.trim(),
    };
  }

  Map<String, String> _parseCharacterCardResponse(String response) {
    final json = AiAdventureUtils.parseJson(response);
    if (json != null) {
      final rawProfile = json['world_profile'];
      final profile = rawProfile is Map
          ? Map<String, dynamic>.from(rawProfile)
          : const <String, dynamic>{};
      return {
        'name': (json['name'] as String?) ?? '未命名角色',
        'gender': (json['gender'] as String?) ?? '女',
        'age': (json['age']?.toString()) ?? '',
        'profession': (json['profession'] as String?) ?? '',
        'personality': (json['personality'] as String?) ?? '',
        'background': (json['background'] as String?) ?? '',
        'appearance': (json['appearance'] as String?) ?? '',
        'world_profile': jsonEncode({
          'faction': _profileText(profile, 'faction', '独立行动者'),
          'home_location': _profileText(profile, 'home_location', '待在剧情中确定'),
          'public_goal': _profileText(profile, 'public_goal', '追寻个人目标'),
          'hidden_motivation':
              _profileText(profile, 'hidden_motivation', '尚未对外公开'),
          'ability_source': _profileText(profile, 'ability_source', '个人训练与经历'),
          'ability_cost': _profileText(profile, 'ability_cost', '需承担行动风险与消耗'),
          'taboos': _profileList(profile['taboos']),
          'relationship_notes':
              _profileText(profile, 'relationship_notes', '关系将在剧情中逐步展开'),
        }),
      };
    }
    return {
      'name': 'AI 生成的角色',
      'gender': '女',
      'age': '',
      'profession': '',
      'personality': response.trim(),
      'background': '',
      'appearance': '',
      'world_profile': jsonEncode({
        'faction': '独立行动者',
        'home_location': '待在剧情中确定',
        'public_goal': '追寻个人目标',
        'hidden_motivation': '尚未对外公开',
        'ability_source': '个人训练与经历',
        'ability_cost': '需承担行动风险与消耗',
        'taboos': ['暂无明确禁忌'],
        'relationship_notes': '关系将在剧情中逐步展开',
      }),
    };
  }

  String _profileText(
      Map<String, dynamic> profile, String key, String fallback) {
    final value = profile[key]?.toString().trim() ?? '';
    return value.isEmpty ? fallback : value;
  }

  List<String> _profileList(dynamic rawTaboos) {
    final taboos = rawTaboos is List
        ? rawTaboos
            .map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty)
            .toList()
        : rawTaboos?.toString().trim().isNotEmpty == true
            ? [rawTaboos.toString().trim()]
            : <String>[];
    return taboos.isEmpty ? ['暂无明确禁忌'] : taboos;
  }

  Map<String, String> _parseConversationCharacterResponse(String response) {
    final json = AiAdventureUtils.parseJson(response);
    if (json != null) {
      return {
        'name': (json['name'] as String?) ?? '',
        'role': (json['role'] as String?) ?? '',
        'user_call_name': (json['user_call_name'] as String?) ?? '',
        'personality': (json['personality'] as String?) ?? '',
        'speaking_style': (json['speaking_style'] as String?) ?? '',
        'background': (json['background'] as String?) ?? '',
        'scenario': (json['scenario'] as String?) ?? '',
        'system_prompt': (json['system_prompt'] as String?) ?? '',
      };
    }
    return {
      'name': '',
      'role': '',
      'user_call_name': '',
      'personality': response.trim(),
      'speaking_style': '',
      'background': '',
      'scenario': '',
      'system_prompt': '',
    };
  }

  // ─── 提示词 ───

  static const _f1Prompt =
      '你是一个专业的文字冒险世界观设计师。请仔细观察这张图片，根据图片中的视觉元素（场景、建筑、色调、氛围、人物等），设计一个详细的文字冒险世界观。\n\n请用 JSON 格式回复，不要包含其他内容：\n{\n  "name": "世界观名称（10字以内，有吸引力）",\n  "description": "世界观描述（200~500字，必须包含：世界背景与历史、核心冲突或危机、主要势力或阵营、地理特征、魔法或科技体系、独特的规则、冒险切入点）"\n}\n\n重要：description 必须 ≥200 字，内容具体可玩，有冲突驱动。必须是纯 JSON。';

  static const _f2Prompt =
      '你是一个专业的文字冒险角色设计师。请仔细观察这张图片中的人物，根据其外貌、服装、表情、姿态、配饰等视觉特征，设计一个完整的角色卡。\n'
      '{worldview}'
      '\n请用 JSON 格式回复，不要包含其他内容：\n'
      '{\n'
      '  "name": "角色姓名（2-4字，符合图片风格）",\n'
      '  "gender": "男 或 女 或 其他",\n'
      '  "age": "年龄数字",\n'
      '  "profession": "职业/身份（10字以内，必须与世界观设定匹配）",\n'
      '  "personality": "性格描述（30~80字）",\n'
      '  "background": "背景故事（100~300字，必须融入世界观的核心元素、历史或冲突）",\n'
      '  "appearance": "外貌描述（30~100字，必须基于图片实际内容如实描述）"\n'
      '}\n\n重要：所有字段必须填写。appearance 必须如实描述图片中可见的外貌特征。角色的职业、背景必须与世界观一致。必须是纯 JSON。';

  static const _f3Prompt =
      '你是一个专业的文字冒险世界观设计师。根据用户的描述，设计一个详细的文字冒险世界观。\n\n用户需求：{userPrompt}\n\n请用 JSON 格式回复，不要包含其他内容：\n{\n  "name": "世界观名称（10字以内，有吸引力）",\n  "description": "世界观描述（200~500字，包含：世界背景、核心冲突、主要势力、地理特征、魔法/科技体系、独特规则、冒险切入点）"\n}\n\n必须是纯 JSON。';

  static const _conversationCharacterPrompt =
      '你是 LT 灵境 的对话角色设计助手。请根据用户要求，设计一个用于长期聊天的 AI 角色卡。'
      '这是通用对话角色，不属于文字冒险，不需要世界观、年龄、外貌、NPC关系或冒险背景。'
      '\n\n用户要求：{userPrompt}\n\n'
      '请严格只返回 JSON，不要输出 Markdown 或解释文字：\n'
      '{\n'
      '  "name": "角色名称（简洁、易记）",\n'
      '  "role": "身份定位（如语言教练、写作顾问、陪伴助手）",\n'
      '  "user_call_name": "如何称呼用户（如用户、创作者、指挥官、老师；不确定则填用户）",\n'
      '  "personality": "性格与行为特点（具体说明处理问题的方式）",\n'
      '  "speaking_style": "说话方式（语气、结构、是否使用示例等）",\n'
      '  "background": "背景设定（角色了解什么、能力边界是什么）",\n'
      '  "scenario": "对话情境（通常如何与用户交流）",\n'
      '  "system_prompt": "额外行为指令（必须遵守的规则）"\n'
      '}';

  static const _f4Prompt =
      '你是一个专业的文字冒险角色设计师。根据世界观设定和用户描述，设计一个完整的角色卡{roleInstruction}。\n'
      '{genderHint}'
      '\n用户需求：{userPrompt}'
      '{worldview}'
      '{associatedCharacters}'
      '\n请用 JSON 格式回复，不要包含其他内容：\n'
      '{\n'
      '  "name": "角色姓名（2-4字，符合世界观文化背景，绝对严禁与已有角色重名）",\n'
      '  "gender": "男 或 女 或 其他",\n'
      '  "age": "年龄数字（必须符合世界观设定下的合理年龄）",\n'
      '  "profession": "职业/身份（10字以内，必须是世界观中真实存在的职业）",\n'
      '  "personality": "性格描述（30~80字，性格应反映世界观环境对人的塑造）",\n'
      '  "background": "背景故事（100~300字，必须融入世界观的核心冲突、历史事件或特色元素，解释角色为何踏上冒险）",\n'
      '  "appearance": "外貌描述（30~100字，外貌特征应符合世界观种族/地域/文化设定）",\n'
      '  "world_profile": {\n'
      '    "faction": "所属势力或独立身份（不可为空）",\n'
      '    "home_location": "活动地点或家乡（不可为空）",\n'
      '    "public_goal": "公开目标（不可为空）",\n'
      '    "hidden_motivation": "隐藏动机（不可为空）",\n'
      '    "ability_source": "能力来源（不可为空）",\n'
      '    "ability_cost": "能力代价或限制（不可为空）",\n'
      '    "taboos": ["禁忌或不可触碰的规则（至少一项）"],\n'
      '    "relationship_notes": "与世界中势力、地点或已有角色的关系备注（不可为空）"\n'
      '  }\n'
      '}\n\n必须是纯 JSON，所有字段必须填写，world_profile 的每个字段也必须填写。角色必须自然融入世界观，不能是异世界穿越者（除非世界观明确允许）。';

  /// F5: 批量 NPC 生成
  static const _f5Prompt =
      '你是一个专业的文字冒险NPC设计师。根据世界观、主角信息和用户偏好，一次性设计 3~6 个重要的配角（NPC）。\n'
      '\n'
      '世界观：{worldview}\n'
      '主角：{protagonistName}（{protagonistRole}）{protagonistExtra}\n'
      '{selectedCharacters}'
      '{characterRelationships}'
      '用户偏好：{userPrompt}\n'
      '{existingNpcs}\n'
      '{associatedCharacters}\n'
      '要求：\n'
      '1. **世界观一致性**：所有 NPC 的身份、职业、外貌与世界观设定必须严格一致，不能出现世界观中不存在的职业或身份；**所有角色姓名严禁相互重复或与已有角色重名**\n'
      '2. **角色多样性**：角色之间要有不同的性格和立场，避免同质化\n'
      '3. **冲突驱动**：至少有 1 个盟友 + 1 个对手/冲突来源，冲突应与世界观的核心矛盾相关\n'
      '4. **性格具体化**：每个角色的性格描述要具体（20~40字），不能只有标签，要体现世界观环境对其性格的塑造\n'
      '5. **关系合理化**：关系字段写与主角的关系（如"童年好友"、"宿敌"、"导师"），关系应有世界观背景支撑\n'
      '6. **字段限制**：不要输出额外经历字段、体型字段或其他角色卡专属字段，NPC 仅保留必要的身份、性格、关系与外貌信息\n'
      '\n'
      '请用 JSON 格式回复，不要包含其他内容：\n'
      '{\n'
      '  "npcs": [\n'
      '    {\n'
      '      "name": "角色名（2-4字，符合世界观文化风格）",\n'
      '      "gender": "男 或 女 或 其他",\n'
      '      "role": "身份/职业（10字以内，必须是世界观中存在的身份）",\n'
      '      "personality": "性格描述（20~40字，要具体，体现世界观对人的塑造）",\n'
      '      "relation": "与主角的关系（5-15字，解释为何在此世界观下建立此关系）"\n'
      '    }\n'
      '  ]\n'
      '}\n'
      '\n'
      '必须是纯 JSON，npcs 数组包含 3~6 个角色。';

  /// F6: 开场场景 + 选项
  /// 权重体系（内部配置，UI不可见）：
  ///   1. 用户偏好 = 最高优先级（可能覆盖世界观设定）
  ///   2. 角色卡 + NPC = 第二优先级
  ///   3. 世界观 = 最低优先级（仅作场景氛围参考）
  static const _f6Prompt = '你是一个专业的文字冒险开场设计师。根据以下信息设计冒险开场，**必须严格按照优先级顺序执行**：\n'
      '\n'
      '━━━━━━━━━━━━━━━━━━━━\n'
      '🔴 【最高优先级 - 用户偏好】（绝对权威，必须100%遵守）\n'
      '━━━━━━━━━━━━━━━━━━━━\n'
      '用户偏好：{userPrompt}\n'
      '**核心原则：用户偏好是最高准则。即使用户的偏好与世界观设定有出入甚至矛盾，也必须以用户偏好为准，覆盖或调整世界观设定来适配用户需求。**\n'
      '\n'
      '━━━━━━━━━━━━━━━━━━━━\n'
      '🟡 【第二优先级 - 角色设定】（角色行为和性格必须符合设定，但不可凌驾于用户偏好）\n'
      '━━━━━━━━━━━━━━━━━━━━\n'
      '主角：{protagonistName}（{protagonistRole}）{protagonistExtra}\n'
      '{selectedCharacters}'
      '{characterRelationships}'
      '{npcs}\n'
      '**原则：角色的身份、性格、背景是开场的核心驱动力，但若与用户偏好冲突，优先满足用户偏好。**\n'
      '\n'
      '━━━━━━━━━━━━━━━━━━━━\n'
      '🟢 【最低优先级 - 世界观】（仅作为场景氛围和背景元素的参考，可以被用户偏好和角色设定覆盖）\n'
      '━━━━━━━━━━━━━━━━━━━━\n'
      '世界观：{worldview}\n'
      '**原则：世界观仅提供场景的视觉风格、文化氛围、地理环境等背景元素。当世界观与用户偏好或角色设定冲突时，以更高层级为准。世界观不是不可打破的规则，而是可以被调整的参考框架。**\n'
      '\n'
      '综合要求：\n'
      '1. **用户偏好优先**：开场必须首先满足用户偏好的要求，即使需要突破或修改世界观设定\n'
      '2. **角色驱动**：主角和NPC的性格、关系、背景是推动开场剧情的核心引擎\n'
      '3. **冲突暗示**：场景中要暗示核心冲突或危机，给玩家一个明确的行动动机或悬念\n'
      '4. **场景具体化**：叙述要生动具体（150~400字），包含具体的环境描写和情境设定\n'
      '5. **选项多样化**：提供 2~4 个初始行动选项，涵盖探索、对话、战斗、调查等不同类型\n'
      '\n'
      '请用 JSON 格式回复，不要包含其他内容：\n'
      '{\n'
      '  "scene": "开场场景叙述（150~400字，充分展现世界观的特色元素）",\n'
      '  "options": ["选项1", "选项2", "选项3"]\n'
      '}\n'
      '\n'
      '必须是纯 JSON。';

  static const _creationWorldPrompt = '''你是长篇小说世界观编辑。请把用户资料整理成可长期复用的创作世界观资料。
用户资料：{source}
只输出 JSON，不要 Markdown：{"name":"","summary":"","aliases":[],"genre":"","tone":"","era":"","techLevel":"","corePremise":"","coreRules":"","geography":"","factions":"","history":"","powerSystem":"","societyCulture":"","currentConflict":"","continuityRules":"","tags":[]}''';

  static const _creationCharacterPrompt = '''你是长篇小说角色编辑。请把用户资料整理为结构化角色卡。
世界观：{worldview}
关联角色：{related}
用户资料：{source}
只输出 JSON，不要 Markdown：{"name":"","summary":"","aliases":[],"gender":"","age":"","occupation":"","characterRole":"","narrativeWeight":"","identity":"","personality":"","values":"","desire":"","fear":"","strengths":"","weaknesses":"","relationships":"","characterArc":"","secret":"","voice":"","plotFunction":"","firstAppearance":"","background":"","appearance":"","tags":[]}''';

  static const _creationNpcPrompt = '''你是长篇小说 NPC 编辑。请把用户资料整理为可复用 NPC 列表。
世界观：{worldview}
关联角色：{related}
用户资料：{source}
只输出 JSON，不要 Markdown：{"npcs":[{"name":"","summary":"","aliases":[],"gender":"","age":"","occupation":"","npcFunction":"","motivation":"","relationToCast":"","keyInformation":"","behaviorVoice":"","sceneUsage":"","briefExperience":"","tags":[]}]}''';

  String _buildSelectedCharacterSection(
      List<Map<String, String>> selectedCharacters) {
    if (selectedCharacters.isEmpty) return '';
    final buf = StringBuffer();
    buf.writeln('已选角色卡（独立于NPC，不可当作NPC）：');
    for (final character in selectedCharacters) {
      final parts = <String>[];
      final name = _firstNonEmpty(character, const ['name']);
      if (name.isEmpty) continue;
      parts.add('名称：$name');
      final isProtagonist =
          (character['isProtagonist'] ?? '').toLowerCase() == 'true';
      if (isProtagonist) parts.add('主角：是');
      final role = _firstNonEmpty(character, const [
        'role',
        'narrativeRole',
        'effectiveRole',
        'customRoleName',
      ]);
      if (role.isNotEmpty) parts.add('身份：$role');
      final body = _firstNonEmpty(character, const [
        'bodyDescription',
        'body_description',
      ]);
      if (body.isNotEmpty) parts.add('身材描述：$body');
      final appearance = _firstNonEmpty(character, const ['appearance']);
      if (appearance.isNotEmpty) parts.add('外貌描述：$appearance');
      final personality = _firstNonEmpty(character, const ['personality']);
      if (personality.isNotEmpty) parts.add('性格：$personality');
      final background = _firstNonEmpty(character, const [
        'background',
        'description',
      ]);
      if (background.isNotEmpty) parts.add('背景故事：$background');
      final customAttrs =
          character['customAttributes'] ?? character['custom_attributes'];
      if (customAttrs != null && customAttrs.isNotEmpty) {
        parts.add('自添加项：$customAttrs');
      }
      buf.writeln('- ${parts.join('，')}');
    }
    return buf.isEmpty ? '' : '${buf.toString()}\n';
  }

  String _buildRelationshipSection(
    List<Map<String, String>> characterRelationships,
  ) {
    if (characterRelationships.isEmpty) return '';
    final buf = StringBuffer();
    buf.writeln('角色关系（仅角色卡之间的关系，不属于NPC）：');
    for (final relation in characterRelationships) {
      final source = _firstNonEmpty(relation, const [
        'sourceName',
        'sourceCharacterName',
        'sourceCharacterId',
      ]);
      final target = _firstNonEmpty(relation, const [
        'targetName',
        'targetCharacterName',
        'targetCharacterId',
      ]);
      if (source.isEmpty || target.isEmpty) continue;
      final relationType = _firstNonEmpty(relation, const [
        'relationType',
        'effectiveRelation',
        'relation',
      ]);
      final description = _firstNonEmpty(relation, const ['description']);
      final line = StringBuffer('- $source 与 $target：');
      if (relationType.isNotEmpty) line.write(relationType);
      if (description.isNotEmpty) {
        if (relationType.isNotEmpty) line.write('，');
        line.write(description);
      }
      buf.writeln(line.toString());
    }
    return buf.isEmpty ? '' : '${buf.toString()}\n';
  }

  String _firstNonEmpty(Map<String, String> data, List<String> keys) {
    for (final key in keys) {
      final value = (data[key] ?? '').trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }
}
