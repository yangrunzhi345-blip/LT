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
    String response;
    try {
      response = await _callText(
          _detailedWorldviewPrompt.replaceFirst('{userPrompt}', userPrompt));
    } catch (error) {
      if (!_isOutputTruncated(error)) rethrow;
      try {
        response = await _callText(
          _compactDetailedWorldviewPrompt.replaceFirst(
              '{userPrompt}', userPrompt),
          maximumOutputTokens: 2048,
        );
      } catch (retryError) {
        if (_isOutputTruncated(retryError)) {
          throw StateError('详细世界观输出过长，请改用简洁模式或减少原文内容后重试。');
        }
        rethrow;
      }
    }
    var parsed = AiAdventureUtils.parseJson(response);
    if (!_isDetailedWorldviewPayload(parsed)) {
      final repair = await _callText(
        _detailedWorldviewRepairPrompt
            .replaceFirst('{userPrompt}', userPrompt)
            .replaceFirst('{invalidResponse}', response),
        maximumOutputTokens: 8192,
      );
      parsed = AiAdventureUtils.parseJson(repair);
    }
    if (!_isDetailedWorldviewPayload(parsed)) {
      throw StateError('详细世界观格式无效，请重试。系统需要包含 detail_json.modules 的完整设定。');
    }
    return Map<String, dynamic>.from(parsed!);
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
            return '- ${parts.join('，')}';
          }).join('\n')}\n\n请在生成时确保新角色与上述关联角色之间的关系自然合理。用户在提示词中会写明具体关系类型。\n'
        : '';

    final prompt = _f4Prompt
        .replaceFirst('{userPrompt}', userPrompt)
        .replaceFirst(
            '{worldview}',
            worldview.isNotEmpty
                ? '\n当前世界观设定：\n$worldview\n\n请确保角色的出身、职业、性格、背景故事与世界观高度契合，角色必须是这个世界中自然存在的居民。'
                : '')
        .replaceFirst('{associatedCharacters}', associatedText);
    final response = await _callText(prompt);
    return _parseCharacterCardResponse(response);
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
    int maximumOutputTokens = 32768,
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
      params: const CompletionParams(temperature: 0.7, maxTokens: 32768),
    );
    return buffer.toString();
  }

  Future<String> _callText(
    String prompt, {
    int maximumOutputTokens = 32768,
    double temperature = .8,
    GenerationTaskHandle? taskHandle,
    void Function(String chunk)? onChunk,
  }) async {
    final messages = [
      {'role': 'user', 'content': AiAdventureUtils.sanitizeForJson(prompt)}
    ];

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
      ),
      taskHandle: taskHandle,
    );
    return buffer.toString();
  }

  bool _isOutputTruncated(Object error) =>
      error.toString().contains('outputTruncated');

  bool _isDetailedWorldviewPayload(Map<String, dynamic>? value) =>
      value?['name'] is String &&
      value?['description'] is String &&
      value?['detail_json'] is Map &&
      (value?['detail_json'] as Map)['modules'] is Map;

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

  static const _detailedWorldviewPrompt = '''
你是世界观设定解析器。将用户材料整理为可审核的详细世界观，只输出 JSON：
{"name":"名称","description":"世界观概述","detail_json":{"format_version":2,"mode":"detailed","modules":{"overview":{"summary":"","status":"confirmed"},"world_rules":{"content":"","status":"confirmed"},"world_state":{"content":"","status":"confirmed"},"locations":[],"factions":[],"customs_and_life":{"content":"","status":"confirmed"},"timeline":[],"glossary":[],"creative_constraints":{"content":"","status":"confirmed"}}}}
所有字段合计目标 4500-5000 个中文字，绝不能超过 5000 字；只输出上述对象，禁止输出 candidates 数组、多个备选方案或 Markdown。
未知信息保留为空或标记 draft，不能编造为 confirmed。
原始材料：{userPrompt}
''';

  static const _detailedWorldviewRepairPrompt = '''
将以下材料整理为一个详细世界观。只输出一个合法 JSON 对象，禁止 candidates 数组、数组外解释或多个方案。总中文字目标 4500-5000，绝不超过5000。对象必须含 name、description、detail_json.modules，modules 必须包含 overview、world_rules、world_state、locations、factions、customs_and_life、timeline、glossary、creative_constraints。
原始材料：{userPrompt}
无效的上一版输出：{invalidResponse}
''';

  static const _compactDetailedWorldviewPrompt = '''
你是世界观设定解析器。上一版输出过长。将用户材料整理为紧凑、可审核的详细世界观，只输出一行合法 JSON，不要 Markdown：
{"name":"名称（不超过20字）","description":"不超过180字的摘要","detail_json":{"format_version":2,"mode":"detailed","modules":{"overview":{"summary":"不超过160字","status":"confirmed"},"world_rules":{"content":"不超过120字","status":"confirmed"},"world_state":{"content":"不超过120字","status":"confirmed"},"locations":[],"factions":[],"customs_and_life":{"content":"不超过100字","status":"confirmed"},"timeline":[],"glossary":[],"creative_constraints":{"content":"不超过100字","status":"confirmed"}}}}
每个数组最多 3 项，每项不超过 60 字；未知信息留空或标记 draft，不能编造为 confirmed。原始材料：{userPrompt}
''';

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
      '你是一个专业的文字冒险角色设计师。根据世界观设定和用户描述，设计一个完整的角色卡，作为玩家在冒险中扮演的主角。\n'
      '\n用户需求：{userPrompt}'
      '{worldview}'
      '{associatedCharacters}'
      '\n请用 JSON 格式回复，不要包含其他内容：\n'
      '{\n'
      '  "name": "角色姓名（2-4字，符合世界观文化背景）",\n'
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
      '1. **世界观一致性**：所有 NPC 的身份、职业、外貌与世界观设定必须严格一致，不能出现世界观中不存在的职业或身份\n'
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
