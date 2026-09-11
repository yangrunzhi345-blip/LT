import '../models/completion_params.dart';
import '../models/llm_task.dart';
import '../models/model_capabilities.dart';
import '../utils/ai_adventure_utils.dart';
import 'llm_service.dart';
import 'llm_task_policy.dart';

/// AI 导入整合服务
/// 使用 LLM 将外部文件（txt/JSONL/md/html）解析整合为目标格式
class AiImportService {
  final LLMService _llm;

  AiImportService(this._llm);

  /// D13: 导入聊天记录 → 提取为 Message 格式
  /// 返回解析出的 [{role, content, ...}]
  Future<List<Map<String, dynamic>>> importChat({
    required String rawContent,
    required String fileType,
  }) async {
    final prompt = chatImportPrompt
        .replaceFirst('{fileType}', fileType)
        .replaceFirst('{content}', _truncate(rawContent, 8000));

    final response = await _callText(prompt);

    final json = AiAdventureUtils.parseJson(response);
    final messages = json?['messages'];
    if (messages is! List) {
      throw const FormatException('AI 未返回有效的对话消息列表');
    }
    final result = <Map<String, dynamic>>[];
    for (final message in messages) {
      if (message is! Map ||
          (message['role'] != 'user' && message['role'] != 'assistant') ||
          message['content'] is! String) {
        throw const FormatException('AI 返回的对话消息格式无效');
      }
      result.add(Map<String, dynamic>.from(message));
    }
    return result;
  }

  /// D14: 导入资源文件 → 提取为世界观/角色卡/NPC
  /// [targetType] 可选: 'worldview', 'character', 'npc'
  Future<Map<String, String>> importResource({
    required String rawContent,
    required String fileType,
    required String targetType,
  }) async {
    String promptTemplate;
    switch (targetType) {
      case 'worldview':
        promptTemplate = worldviewImportPrompt;
        break;
      case 'character':
        promptTemplate = characterImportPrompt;
        break;
      case 'npc':
        promptTemplate = npcImportPrompt;
        break;
      default:
        promptTemplate = worldviewImportPrompt;
    }

    final prompt = promptTemplate
        .replaceFirst('{fileType}', fileType)
        .replaceFirst('{content}', _truncate(rawContent, 8000));

    final response = await _callText(prompt);

    final json = AiAdventureUtils.parseJson(response);
    if (json != null) {
      return json.map((k, v) => MapEntry(k, v?.toString() ?? ''));
    }
    throw const FormatException('AI 未返回可导入的结构化资料');
  }

  /// 截断内容以避免超出 token 限制
  String _truncate(String content, int maxChars) {
    if (content.length <= maxChars) return content;
    return '${content.substring(0, maxChars)}\n\n... (内容过长，已截断)';
  }

  Future<String> _callText(String prompt) async {
    final buffer = StringBuffer();
    await _llm.sendMessageStream(
      [
        {'role': 'user', 'content': prompt}
      ],
      (chunk) => buffer.write(chunk),
      () {},
      // 导入解析助手按提示词直接抽取结构化资料：任务策略关闭思考并启用 JSON。
      params: const LlmTaskResolver().resolve(
        task: LlmTask.importExtraction,
        capabilities: ModelCapabilityRegistry.resolve(_llm.config.model),
        userParams: const CompletionParams(maxTokens: 4096),
      ),
    );
    return buffer.toString();
  }

  // ─── Prompt 模板 ───

  static const chatImportPrompt = '''
你是一个对话格式解析器。请将以下 {fileType} 格式的聊天记录解析为结构化的消息列表。

严格输出以下 JSON 格式（不要包含 markdown 标记）：
{
  "messages": [
    {"role": "user", "content": "消息内容"},
    {"role": "assistant", "content": "消息内容"}
  ]
}

规则：
- 交替出现的发言者，第一个发言者为 user，第二个为 assistant，依次交替
- 如果原文中明确标注了角色名，请在 content 中保留
- 忽略格式标记和时间戳
- 只保留有意义的对话内容

原始内容：
{content}
''';

  static const worldviewImportPrompt = '''
你是一个世界观设定解析器。请从以下 {fileType} 格式的内容中提取或归纳出一个完整的世界观设定。

严格输出以下 JSON 格式（不要包含 markdown 标记）：
{
  "name": "世界观名称（2-10字）",
  "description": "世界观描述（200-500字，包含时代背景、地理环境、种族势力、魔法/科技体系等）"
}

规则：
- 如果内容是具体的故事/对话，从中归纳世界观特征
- 如果内容是设定文档，直接提取核心设定
- 描述要完整、连贯、适合作为文字冒险的世界背景

原始内容：
{content}
''';

  static const characterImportPrompt = '''
你是一个角色设定解析器。请从以下 {fileType} 格式的内容中提取或归纳出一个完整的角色设定。

严格输出以下 JSON 格式（不要包含 markdown 标记）：
{
  "name": "角色名",
  "gender": "男/女/其他",
  "age": "年龄段（如：18岁/青年/中年）",
  "profession": "职业/身份",
  "personality": "性格特征（20-50字）",
  "background": "背景故事（50-150字）",
  "appearance": "外貌描述（20-50字）"
}

规则：
- 如果内容提到多个角色，选择最主要的一个
- 如果信息不完整，合理推测补充
- 性格描述要具体，不要空洞

原始内容：
{content}
''';

  static const npcImportPrompt = '''
你是一个 NPC 设定解析器。请从以下 {fileType} 格式的内容中提取或归纳出所有 NPC 角色的设定。

严格输出以下 JSON 格式（不要包含 markdown 标记）：
{
  "npcs": [
    {
      "name": "NPC名称",
      "gender": "男/女/其他",
      "role": "身份/定位",
      "personality": "性格描述",
      "relation": "与主角的关系"
    }
  ]
}

规则：
- 提取所有有名字或有明确描述的非主角角色
- 关系字段描述该 NPC 与故事中主角/核心人物的关系
- 至少提取 1 个 NPC，最多 6 个
- 信息不完整的字段可以为空字符串

原始内容：
{content}
''';
}
