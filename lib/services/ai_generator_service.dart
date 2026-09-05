import 'dart:convert';
import '../core/config/generation_limits.dart';
import '../models/completion_params.dart';
import '../utils/ai_adventure_utils.dart';
import '../utils/content_hasher.dart';
import '../utils/structured_json_codec.dart';
import 'detailed_worldview_context_policy.dart';
import 'detailed_worldview_generation_coordinator.dart';
import 'llm_service.dart';

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

class AiGeneratorService {
  static final Map<String, _DetailedWorldviewFlight> _detailedFlights = {};
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
  Future<Map<String, String>> textToWorldview(String userPrompt) async {
    final prompt = _f3Prompt.replaceFirst('{userPrompt}', userPrompt);
    final response = await _callText(prompt);
    return _parseWorldviewResponse(response);
  }

  /// Generates a reviewable candidate; callers must explicitly confirm it.
  Future<Map<String, dynamic>> textToDetailedWorldview(String userPrompt,
      {int? targetTotalCharacters,
      void Function(DetailedWorldviewGenerationProgress progress)?
          onProgress}) async {
    if (targetTotalCharacters != null) {
      final target = targetTotalCharacters
          .clamp(
            GenerationLimits.detailedWorldviewMinimumCharacters,
            GenerationLimits.detailedWorldviewMaximumCharacters,
          )
          .toInt();
      final key = '${ContentHasher.hashString(userPrompt)}:$target';
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
      final future = _generateDetailedWorldview(
        userPrompt,
        target,
        onProgress: (progress) {
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
    return textToDetailedWorldviewMultiTurn(
      userPrompt,
      onDetailedProgress: onProgress,
    );
  }

  /// 优化版世界观详细模式生成：同一上下文多段调用（4段式会话流），默认强约束 JSON 契约。
  Future<Map<String, dynamic>> textToDetailedWorldviewMultiTurn(
    String sourceText, {
    void Function(int currentTurn, int totalTurns, String stageName)? onProgress,
    void Function(DetailedWorldviewGenerationProgress progress)? onDetailedProgress,
  }) async {
    final sessionMessages = <Map<String, dynamic>>[
      {
        'role': 'system',
        'content': '你是一位史诗级世界观架构专家。你将通过多阶段推演，逐步构思出一个逻辑严谨、细节丰满、拥有独特法则与深度冲突的世界设定。'
            '在每一轮对话中，你必须严格输出合法的 JSON 格式，不要包含任何非 JSON 的解释文字或 Markdown 标签之外的内容。',
      },
    ];

    Future<Map<String, dynamic>> executeTurn({
      required String userInstruction,
      required int turnIndex,
      required String stageName,
    }) async {
      onProgress?.call(turnIndex, 4, stageName);
      if (onDetailedProgress != null) {
        onDetailedProgress(DetailedWorldviewGenerationProgress(
          question: DetailedWorldviewQuestion(
            questionIndex: turnIndex,
            totalQuestions: 4,
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

      sessionMessages.add({
        'role': 'user',
        'content': userInstruction,
      });

      final response = await _callMessages(
        sessionMessages,
        maximumOutputTokens: 8192,
      );

      var parsed = StructuredJsonCodec.tryDecodeObject(response, repair: true);
      if (parsed == null) {
        final repair = await _callText(
          '以下文本未能成功解析为 JSON，请将其严格整理修复为合法单层 JSON 对象，不要添加任何额外解释：\n$response',
          maximumOutputTokens: 8192,
        );
        parsed = StructuredJsonCodec.tryDecodeObject(repair, repair: true);
      }
      if (parsed == null) {
        throw FormatException('世界观阶段 $turnIndex ($stageName) 生成返回了无效的 JSON');
      }

      sessionMessages.add({
        'role': 'assistant',
        'content': jsonEncode(parsed),
      });

      return parsed;
    }

    // Turn 1: 核心基石、宏观法则与世界现状
    final t1Prompt = '''
基于用户的核心材料与设想，构思世界观的基石、宏观物理与超自然法则体系、以及当前文明与世界的全局现状。
用户核心材料：$sourceText

请严格输出单层 JSON 格式：
{
  "name": "世界名称（精炼有辨识度，2-8字）",
  "description": "世界宏观概述与核心魅力（250~450字，涵盖历史渊源、文明演进与根本矛盾）",
  "world_rules": "世界的底层法则、物理/超自然定律、力量运作体系与代价禁忌（250~450字）",
  "world_state": "当前世界的文明格局、时代面貌、正在蔓延的巨大危机或历史转折点（250~450字）"
}
''';
    final t1Data = await executeTurn(
      userInstruction: t1Prompt,
      turnIndex: 1,
      stageName: '宏观基石与法则现状',
    );
    final name = (t1Data['name'] as String?)?.trim() ?? '未命名世界';
    final description = (t1Data['description'] as String?)?.trim() ?? sourceText;
    final worldRules = (t1Data['world_rules'] as String?)?.trim() ?? '遵循基础自然法则与超凡秩序。';
    final worldState = (t1Data['world_state'] as String?)?.trim() ?? '文明正处于关键的动荡转折期。';

    // Turn 2: 核心地理据点与风貌
    final t2Prompt = '''
基于上文已经确立的世界「$name」及其物理法则与世界现状，请深入推演该世界的地理风貌与核心据点/区域。
要求据点环境与上述力量法则紧密呼应，提供丰富的冒险探索空间。

请严格输出 JSON 格式：
{
  "locations": [
    {
      "name": "地点名称",
      "terrain": "地形或环境类型（如浮空孤岛/深渊遗迹/永夜森林/机械巨构）",
      "description": "地理风貌、生态环境、危险评级与探索价值（150~250字）"
    }
  ]
}
（请至少提供 3 到 5 个具有代表性、探索潜力巨大的核心地点）
''';
    final t2Data = await executeTurn(
      userInstruction: t2Prompt,
      turnIndex: 2,
      stageName: '地理据点与风貌',
    );
    final rawLocations = t2Data['locations'];
    final List<Map<String, dynamic>> locationsList = [];
    final locationsBuffer = StringBuffer();
    if (rawLocations is List) {
      for (var i = 0; i < rawLocations.length; i++) {
        final loc = rawLocations[i];
        if (loc is Map) {
          final lMap = Map<String, dynamic>.from(loc);
          locationsList.add(lMap);
          final lName = lMap['name'] ?? '据点${i + 1}';
          final lTerrain = lMap['terrain'] != null ? '【${lMap['terrain']}】' : '';
          final lDesc = lMap['description'] ?? '';
          locationsBuffer.writeln('${i + 1}. $lName $lTerrain：$lDesc');
        }
      }
    }
    final locationsText = locationsBuffer.toString().trim().isNotEmpty
        ? locationsBuffer.toString().trim()
        : '包含多个未探索的广袤地域与古代遗迹。';

    // Turn 3: 核心势力与民俗生活
    const t3Prompt = '''
基于上文的世界观设定、法则体系与地理据点，请推演活跃在该世界的核心势力格局与民间社会生活风貌。
要求势力之间具备错综复杂的利益冲突与理念对立。

请严格输出 JSON 格式：
{
  "factions": [
    {
      "name": "势力/组织名称",
      "type": "类型（如教廷神权/商会联盟/隐秘结社/帝国军阀）",
      "ideology": "宗旨与核心理念",
      "description": "势力架构、拥有的资源权力与对外界的影响（150~250字）"
    }
  ],
  "customs_and_life": "普通民众的生活面貌、社会风俗节庆、贸易与经济方式、信仰禁忌（250~450字）"
}
（请至少提供 3 到 4 个核心势力，并详述民俗生活）
''';
    final t3Data = await executeTurn(
      userInstruction: t3Prompt,
      turnIndex: 3,
      stageName: '势力格局与民俗生活',
    );
    final rawFactions = t3Data['factions'];
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
          final fIdeo = fMap['ideology'] != null ? '，宗旨：${fMap['ideology']}' : '';
          final fDesc = fMap['description'] ?? '';
          factionsBuffer.writeln('${i + 1}. $fName$fType$fIdeo：$fDesc');
        }
      }
    }
    final factionsText = factionsBuffer.toString().trim().isNotEmpty
        ? factionsBuffer.toString().trim()
        : '各大古老势力与新兴宗派在暗中角力。';
    final customsText = (t3Data['customs_and_life'] as String?)?.trim() ??
        '民间保留着古老的祭祀传统，商旅依靠陆上驼队与飞艇穿梭于城邦之间。';

    // Turn 4: 编年大事件、专有名词与创作约束
    const t4Prompt = '''
基于上文全部世界设定，为了使基于该世界的故事创作保持严谨性与历史厚重感，请完善本世界的历史编年大事件、核心专有名词表以及创作者必须遵守的铁律。

请严格输出 JSON 格式：
{
  "timeline": [
    {
      "era": "纪元或时代",
      "event": "重大转折历史事件（100~200字）"
    }
  ],
  "glossary": [
    {
      "term": "专有名词",
      "definition": "概念定义与世界功能（50~100字）"
    }
  ],
  "creative_constraints": "创作者与冒险推演在此世界中必须恪守的不可违背铁律（如魔法不可复活亡者、界外物质具有侵蚀性等）（200~400字）"
}
（请至少提供 3 项历史大事件，3 个专有名词，以及详尽的创作约束）
''';
    final t4Data = await executeTurn(
      userInstruction: t4Prompt,
      turnIndex: 4,
      stageName: '编年术语与创作铁律',
    );
    final rawTimeline = t4Data['timeline'];
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

    final rawGlossary = t4Data['glossary'];
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

    final constraintsText = (t4Data['creative_constraints'] as String?)?.trim() ??
        '法则不可随意打破，一切力量均遵循等价代价。';

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

    if (onDetailedProgress != null) {
      onDetailedProgress(const DetailedWorldviewGenerationProgress(
        question: DetailedWorldviewQuestion(
          questionIndex: 4,
          totalQuestions: 4,
          module: 'complete',
          modules: [],
          part: 1,
          totalParts: 1,
          targetCharacters: 1000,
          maximumCharacters: 2500,
          dependsOnPreviousPart: true,
        ),
        completedQuestions: 4,
        partialText: '完成生成',
        questionCompleted: true,
      ));
    }

    return {
      'name': name,
      'description': description,
      'detail_json': detailJson,
    };
  }

  Future<Map<String, dynamic>> _generateDetailedWorldview(
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
      } catch (_) {
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
      } catch (_) {}
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
      List<Map<String, String>> associatedCharacters = const []}) async {
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
    final roleInstruction = isCompanion
        ? '，作为冒险队伍中的重要伙伴或核心搭档'
        : '，作为玩家在冒险中扮演的主角';

    var genderHint = '';
    final trimmedPrompt = userPrompt.trim();
    if (trimmedPrompt.contains('女主') || trimmedPrompt.contains('女主角') || trimmedPrompt.contains('女性')) {
      genderHint = '\n⚠️【性别明确指定】用户指定该角色为【女性角色/女主角/核心女伴】，gender 字段必须为"女"！\n';
    } else if (trimmedPrompt.contains('男主') || trimmedPrompt.contains('男主角') || trimmedPrompt.contains('男性')) {
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
    final response = await _callText(prompt);
    final result = _parseCharacterCardResponse(response);
    var name = result['name']?.trim() ?? '';
    if (existingNames.contains(name)) {
      final prof = result['profession']?.trim() ?? '';
      result['name'] = prof.isNotEmpty ? '$name·$prof' : '$name(副)';
    }
    return result;
  }

  /// 优化版角色设计详细模式生成：同一上下文多段调用（3段式会话流），默认强约束 JSON 契约。
  Future<Map<String, dynamic>> textToDetailedCharacterCard(
    String userPrompt, {
    String worldview = '',
    List<Map<String, String>> associatedCharacters = const [],
    void Function(int currentStage, int totalStages, String stageName)? onProgress,
  }) async {
    final sessionMessages = <Map<String, dynamic>>[
      {
        'role': 'system',
        'content': '你是一位顶级的文字冒险角色设计师。你将通过多阶段推演，逐步塑造出一个血肉丰满、拥有深度心理矛盾与独特弧光的生动角色。'
            '在每一轮对话中，你必须严格输出合法的 JSON 格式，不要包含任何非 JSON 的解释文字或 Markdown 标签之外的内容。',
      },
    ];

    Future<Map<String, dynamic>> executeTurn({
      required String userInstruction,
      required int turnIndex,
      required String stageName,
    }) async {
      onProgress?.call(turnIndex, 3, stageName);
      sessionMessages.add({
        'role': 'user',
        'content': userInstruction,
      });

      final response = await _callMessages(
        sessionMessages,
        maximumOutputTokens: 8192,
      );

      var parsed = StructuredJsonCodec.tryDecodeObject(response, repair: true);
      if (parsed == null) {
        final repair = await _callText(
          '以下文本未能成功解析为 JSON，请将其严格整理修复为合法单层 JSON 对象，不要添加任何额外解释：\n$response',
          maximumOutputTokens: 8192,
        );
        parsed = StructuredJsonCodec.tryDecodeObject(repair, repair: true);
      }
      if (parsed == null) {
        throw FormatException('角色设计阶段 $turnIndex ($stageName) 生成返回了无效的 JSON');
      }

      sessionMessages.add({
        'role': 'assistant',
        'content': jsonEncode(parsed),
      });

      return parsed;
    }

    final wvSection = worldview.trim().isNotEmpty
        ? '【契合世界观背景设定】\n$worldview\n'
        : '';
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

    // Turn 1: 身份锚定与矛盾心理原型
    final t1Prompt = '''
基于以下世界观背景与要求，设计角色的核心身份定位与矛盾心理原型：
$wvSection$assocSection用户需求：$userPrompt

请严格输出单层 JSON 格式：
{
  "name": "角色中文姓名（符合世界观文化，严禁与已有角色重名）",
  "gender": "男 或 女 或 其他",
  "age": "年龄（如：24 或 120岁）",
  "profession": "职业或社会身份（必须契合世界观）",
  "archetype": "核心人物原型（如：背负宿命的叛逆者、渴望救赎的守护者）",
  "personality": "深入性格剖析：包括表面处世态度、真实本性、价值准则与内心深处的矛盾弱点（150~300字）"
}
''';
    final t1Data = await executeTurn(
      userInstruction: t1Prompt,
      turnIndex: 1,
      stageName: '身份锚定与性格原型',
    );
    var name = (t1Data['name'] as String?)?.trim() ?? '未命名角色';
    if (existingNames.contains(name)) {
      final prof = (t1Data['profession'] as String?)?.trim() ?? '';
      name = prof.isNotEmpty ? '$name·$prof' : '$name(副)';
    }
    final gender = (t1Data['gender'] as String?)?.trim() ?? '女';
    final age = (t1Data['age']?.toString())?.trim() ?? '20';
    final profession = (t1Data['profession'] as String?)?.trim() ?? '冒险者';
    final personality = (t1Data['personality'] as String?)?.trim() ?? '沉着冷静但内心炽热。';

    // Turn 2: 外貌肖像与身材体格特征
    final t2Prompt = '''
基于上文已确定的角色身份「$name（$gender，$age，$profession）」及其矛盾性格，请细化角色的生动外貌肖像与身材体格特征。
要求服饰打扮、五官气质与体态生理特征必须与其职业、性格经历及世界观文化高度呼应。

请严格输出单层 JSON 格式：
{
  "appearance": "面容五官、发型发色、眼神气质、神情常态、常穿服饰与随身标志性信物/装备（150~300字）",
  "bodyDescription": "身高身姿、体格力量感、肤色体态、特殊伤疤/刺青/生理异质或改造印记（100~200字）"
}
''';
    final t2Data = await executeTurn(
      userInstruction: t2Prompt,
      turnIndex: 2,
      stageName: '外貌肖像与体态特征',
    );
    final appearance = (t2Data['appearance'] as String?)?.trim() ?? '眼神锐利，身着轻便的长袍。';
    final bodyDescription = (t2Data['bodyDescription'] as String?)?.trim() ?? '身姿挺拔，行动矫健。';

    // Turn 3: 身世过往、深层动机、能力来源与代价、阵营与禁忌
    final assocTurn3Guidance = associatedCharacters.isNotEmpty
        ? '\n⚠️【重要：羁绊背景融合】新角色与已有角色存在重要羁绊关联（${associatedCharacters.map((c) => '${c['name']}（设定关系：${c['relation'] ?? c['relationship'] ?? '同伴'}）').join('、')}）。请在 description（身世背景经历）中自然交待彼此相识或过往纠葛渊源，并在 relationship_notes（人际关系）中明确体现对该关联角色的深刻态度、羁绊与互动纠葛！\n'
        : '';
    final t3Prompt = '''
基于上述已经确定的角色身份、性格与外貌体态，请深入推演角色的身世过往、深层欲望动机、能力来源与代价、以及在世界中的阵营与禁忌。
要求与既有世界观深度融合。$assocTurn3Guidance
请严格输出单层 JSON 格式：
{
  "description": "生平背景经历：过去的成长环境、决定命运的重大转折点、现在的处境与羁绊（200~400字）",
  "public_goal": "公开宣称的行动使命或目标（30~80字）",
  "hidden_motivation": "内心深处驱动自己的隐秘渴望、执念或恐惧（30~80字）",
  "ability_source": "所拥有的特殊能力/专长/技能的来源、师承或磨砺背景（50~150字）",
  "ability_cost": "施展能力或生存必须付出的代价、代价反噬、生理心理弱点或局限（40~100字）",
  "faction": "所属势力组织或立场阵营（如：王国密探 / 荒原猎人行会 / 独立流浪者）",
  "home_location": "出生地、故乡或经常活动的常驻据点",
  "taboos": ["不可触碰的行为禁忌或誓言雷区1", "不可触碰的行为禁忌或誓言雷区2"],
  "relationship_notes": "在世界中与关键势力、地点或关联角色的纠葛与态度（50~150字）"
}
''';
    final t3Data = await executeTurn(
      userInstruction: t3Prompt,
      turnIndex: 3,
      stageName: '身世经历与深层设定',
    );
    final description = (t3Data['description'] as String?)?.trim() ??
        (t3Data['background'] as String?)?.trim() ??
        '从荒野走出的流浪者，正在寻找属于自己的答案。';
    final publicGoal = (t3Data['public_goal'] as String?)?.trim() ?? '完成眼前的委托与探寻';
    final hiddenMotivation = (t3Data['hidden_motivation'] as String?)?.trim() ?? '查明家族覆灭的真相';
    final abilitySource = (t3Data['ability_source'] as String?)?.trim() ?? '多年的实战生死磨砺';
    final abilityCost = (t3Data['ability_cost'] as String?)?.trim() ?? '能力消耗巨大，需定期休整';
    final faction = (t3Data['faction'] as String?)?.trim() ?? '独立冒险者';
    final homeLocation = (t3Data['home_location'] as String?)?.trim() ?? '边陲城镇';
    final rawTaboos = t3Data['taboos'];
    final List<String> taboosList = [];
    if (rawTaboos is List) {
      for (final t in rawTaboos) {
        if (t != null && t.toString().trim().isNotEmpty) {
          taboosList.add(t.toString().trim());
        }
      }
    }
    if (taboosList.isEmpty) {
      taboosList.add('绝不背弃生死相托的同伴');
    }
    final relationshipNotes = (t3Data['relationship_notes'] as String?)?.trim() ??
        '与旅途中的同伴保持着谨慎但真诚的信赖。';

    return {
      'name': name,
      'gender': gender,
      'age': age,
      'profession': profession,
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

  /// 场景资料库批量生成角色/NPC。该能力通过应用层 LLM Gateway 暴露，UI
  /// 不再直接拼接提示词或访问 LLMService。
  Future<Map<String, dynamic>> generateSceneBatchCharacters({
    required String source,
    required String label,
    required String worldview,
    required List<Map<String, dynamic>> relatedCharacters,
    required List<String> selectedNames,
    required int minimumTotalLength,
    required int maximumTotalLength,
    required String detailInstruction,
  }) async {
    final response = await _callText(
      '你是小说资料编辑。仅依据用户原文提取所有明确出现的$label，不得编造。'
      '世界观：$worldview\n原文：$source\n'
      '允许关联的已有角色：${jsonEncode(relatedCharacters)}\n'
      '仅生成已确认的角色：${selectedNames.join('、')}。每张资料总字数必须为 '
      '$minimumTotalLength-$maximumTotalLength。\n$detailInstruction\n'
      '只输出 JSON：{"items":[{"name":"","gender":"","age":"",'
      '"profession":"","personality":"","description":"",'
      '"appearance":"","relationship_summary":"","relationship_links":[]}]}。'
      'relationship_links 每项必须含 targetName、relationType、description，'
      '仅可记录原文明确的关系；没有则为空数组。',
      maximumOutputTokens: 8192,
    );
    final parsed = AiAdventureUtils.parseJson(response);
    if (parsed == null || parsed['items'] is! List) {
      throw const FormatException('批量资料生成结果格式无效');
    }
    return Map<String, dynamic>.from(parsed);
  }

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
      params: const CompletionParams(temperature: 0.7, maxTokens: 8192),
    );
    return buffer.toString();
  }

  Future<String> _callText(
    String prompt, {
    int maximumOutputTokens = 8192,
    double temperature = .8,
    GenerationTaskHandle? taskHandle,
    void Function(String chunk)? onChunk,
  }) async {
    final messages = [
      {'role': 'user', 'content': AiAdventureUtils.sanitizeForJson(prompt)}
    ];

    final isJson = prompt.toLowerCase().contains('json');
    final buffer = StringBuffer();
    await _llm.sendMessageStream(
      messages,
      (chunk) {
        buffer.write(chunk);
        onChunk?.call(chunk);
      },
      () {},
      params: CompletionParams(
        temperature: temperature,
        maxTokens: maximumOutputTokens,
        responseFormat: isJson ? const {'type': 'json_object'} : null,
      ),
      taskHandle: taskHandle,
    );
    return buffer.toString();
  }

  Future<String> _callMessages(
    List<Map<String, dynamic>> messages, {
    int maximumOutputTokens = 8192,
    double temperature = .7,
    GenerationTaskHandle? taskHandle,
    void Function(String chunk)? onChunk,
  }) async {
    final sanitizedMessages = messages.map((m) {
      final role = m['role']?.toString() ?? 'user';
      final content = m['content']?.toString() ?? '';
      return {
        'role': role,
        'content': AiAdventureUtils.sanitizeForJson(content),
      };
    }).toList();

    final isJson = messages.any((m) =>
        (m['content']?.toString() ?? '').toLowerCase().contains('json'));
    final buffer = StringBuffer();
    await _llm.sendMessageStream(
      sanitizedMessages,
      (chunk) {
        buffer.write(chunk);
        onChunk?.call(chunk);
      },
      () {},
      params: CompletionParams(
        temperature: temperature,
        maxTokens: maximumOutputTokens,
        responseFormat: isJson ? const {'type': 'json_object'} : null,
      ),
      taskHandle: taskHandle,
    );
    return buffer.toString();
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
