import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../models/adventure_response.dart';
import '../models/adventure_runtime_state.dart';
import '../models/custom_attribute_item.dart';
import '../models/combat_state.dart' show CombatAction;
import '../models/completion_params.dart';
import '../models/game_state.dart';
import '../models/message.dart';
import '../models/llm_task.dart';
import '../models/model_capabilities.dart';
import '../models/quest.dart';
import '../models/scene_dialogue.dart';
import '../models/scene_dialogue_effects.dart';
import '../models/worldview_details.dart';
import '../application/narrative/user_intent.dart';
import '../services/api_error.dart';
import '../services/auto_backup_service.dart';
import '../services/llm_service.dart';
import '../services/llm_task_policy.dart';
import '../services/web_search_service.dart';
import '../services/repositories/adventure_repository.dart';
import '../services/scene_consistency_validator.dart';
import 'chat_engine_host.dart';
import 'chat_engine_internals/prompt_builder.dart';
import 'chat_engine_internals/response_length_guard.dart';
import 'chat_engine_internals/stream_handler.dart';
import 'chat_engine_internals/summary_service.dart';
import '../managers/combat_manager.dart';

class ContextExecutionResult {
  final String content;
  final String? reasoningContent;
  const ContextExecutionResult({required this.content, this.reasoningContent});
}

enum ContextTaskType {
  adventureResponse,
  adventureLengthSupplement,
  adventureOptionRepair,
  adventureSummary,
}

/// P1-03: 聊天状态枚举 — 替代 _isLoading/_isStreaming 双 bool，消除并发守卫空窗期
enum ChatStatus { idle, loading, streaming }

enum SceneDialoguePhase {
  created,
  streaming,
  parsing,
  repairing,
  committing,
  completed,
  cancelled,
  failed,
  stale,
}

class ChatEngine {
  // ─── 依赖 ───

  final ChatEngineHost _host;
  final VoidCallback notifyParent;
  final IAdventureRepository _adventureRepo;

  /// 直接通知 ChatProvider 的回调，作为子 Provider 通知链的可靠直达路径。
  VoidCallback? _notifyRoot;

  // ─── 子模块 ───

  final PromptBuilder _promptBuilder = PromptBuilder();
  final NarrativeLengthGuard _lengthGuard = const NarrativeLengthGuard();
  final TypewriterController _typewriter = TypewriterController();
  final SummaryService _summaryService;

  // ─── 错误类型常量 ───

  static const errorTypeNetwork = 'network';
  static const errorTypeApi = 'api';
  static const errorTypeTimeout = 'timeout';
  static const errorTypeAuth = 'auth';
  static const errorTypeRate = 'rate';

  // ─── 聊天状态字段 ───

  /// P1-03: 单一状态枚举，替代 _isLoading/_isStreaming 双 bool
  ChatStatus _status = ChatStatus.idle;
  String _streamingContent = '';
  String? _lastFailedContent;
  String? _lastErrorType;
  String? _lastErrorDetail;
  List<String> _parsedOptions = [];
  List<String> _lastValidOptions = [];
  final ValueNotifier<String> _streamNotifier = ValueNotifier<String>('');
  final ValueNotifier<String> _reasoningStreamNotifier =
      ValueNotifier<String>('');
  final ValueNotifier<bool> _isThinkingNotifier = ValueNotifier<bool>(false);
  String _reasoningContent = '';
  int _lastSummaryAt = 0;
  DateTime? _lastSummaryTime;
  int _consecutiveErrors = 0;
  String? _pendingSearchResults;
  bool _cancelRequested = false;
  bool _isRepairingOptions = false;
  int _generation = 0;
  bool _disposed = false;
  String? _activeRequestId;
  GenerationTaskHandle? _activeTaskHandle;
  SceneDialoguePhase _scenePhase = SceneDialoguePhase.completed;
  GameState? _pendingGameState;
  SceneDialogueEffects _pendingSceneEffects = const SceneDialogueEffects();
  SceneDialogueContextSnapshot? _lastSceneSnapshot;
  List<RuntimeEntityState> _runtimeEntities = const [];
  List<String> _runtimeArchiveFacts = const [];
  List<SceneSettingCandidate> _lastSceneCandidates = const [];

  // v2.4: 抗衰减与未达标追踪
  int _lastAiWordCount = 0;
  bool _decayWarningNextRound = false;
  bool _underflowWarningNextRound = false;
  int _underflowDeficit = 0;
  int _underflowLastActual = 0;

  static const CompletionParams _optionRepairParams = CompletionParams(
    temperature: 0.45,
    topP: 0.8,
    frequencyPenalty: 0.0,
    presencePenalty: 0.0,
    maxTokens: 2048,
    enableThinking: false,
  );

  // ─── 公开 Getter ───

  List<Message> get messages => _host.messages;
  ChatStatus get status => _status;
  bool get isLoading => _status == ChatStatus.loading;
  String get streamingContent => _streamingContent;
  bool get isStreaming => _status == ChatStatus.streaming;
  bool get isRepairingOptions => _isRepairingOptions;
  String? get lastFailedContent => _lastFailedContent;
  String? get lastErrorType => _lastErrorType;
  String? get lastErrorDetail => _lastErrorDetail;
  bool get canRetry => _lastFailedContent != null;
  List<String> get parsedOptions => _parsedOptions;
  ValueNotifier<String> get streamNotifier => _streamNotifier;
  ValueNotifier<String> get reasoningStreamNotifier => _reasoningStreamNotifier;
  ValueNotifier<bool> get isThinkingNotifier => _isThinkingNotifier;
  String get reasoningContent => _reasoningContent;
  SceneDialoguePhase get sceneDialoguePhase => _scenePhase;
  SceneDialogueContextSnapshot? get lastSceneSnapshot => _lastSceneSnapshot;
  List<SceneSettingCandidate> get lastSceneCandidates => _lastSceneCandidates;
  String? chatSummary;

  // ─── 构造函数 ───

  ChatEngine({
    required ChatEngineHost host,
    required this.notifyParent,
    required IAdventureRepository adventureRepo,
  })  : _host = host,
        _adventureRepo = adventureRepo,
        _summaryService = SummaryService(
          adventureRepo: adventureRepo,
          host: host,
        );

  /// 设置直达 ChatProvider 的通知回调（由 ChatProvider 在初始化时调用）
  void setNotifyRoot(VoidCallback cb) => _notifyRoot = cb;

  /// 同时通知 MessagingProvider（间接链）和 ChatProvider（直达链）。
  /// 确保 Release 模式下即使间接链静默丢失，ChatProvider 也能收到通知。
  void _notifyAll() {
    notifyParent();
    _notifyRoot?.call();
  }

  // ─── 公开构建方法 ───

  List<Map<String, String>> buildMessages(String content) {
    return _promptBuilder.buildMessages(
      _host,
      content,
      _host.messages,
      chatSummary,
      _pendingSearchResults,
      runtimeEntities: _runtimeEntities,
      archiveRetrievalFacts: _runtimeArchiveFacts,
    );
  }

  List<Map<String, String>> getFullPromptPreview() {
    return _promptBuilder.getFullPromptPreview(
      _host,
      _host.messages,
      chatSummary,
    );
  }

  // ─── 状态清理 ───

  void clearParsedOptions() {
    _parsedOptions = [];
    _lastValidOptions = [];
  }

  // ─── 拆分响应解析 ───

  /// P3-02: JSON 解析移至后台 Isolate，避免阻塞 UI 线程
  Future<bool> _applySplitResponse(String content) async {
    final response = await compute(parseResponseInIsolate, content);
    if (response == null) {
      _parsedOptions = _lastValidOptions.isNotEmpty
          ? List<String>.from(_lastValidOptions)
          : _buildFallbackOptions(_host.gameState, null);
      return true;
    }

    final gs = _host.gameState;
    final patch = response.patch;
    _pendingSceneEffects =
        SceneDialogueEffects.fromJson(_sceneResponseMap(content));
    final newState = _pendingSceneEffects.applyState(gs.copyWith(
      hp: patch.hp ?? gs.hp,
      maxHp: patch.maxHp ?? gs.maxHp,
      energy: patch.energy ?? gs.energy,
      maxEnergy: patch.maxEnergy ?? gs.maxEnergy,
      gold: patch.gold ?? gs.gold,
      inventory: patch.inventory ?? gs.inventory,
      currentScene: patch.scene ?? gs.currentScene,
    ));

    if (response.customStatus.isNotEmpty) {
      _syncCustomStatusUpdates(response.customStatus);
    }

    if (response.options.length >= 3) {
      _parsedOptions = List<String>.from(response.options);
      _lastValidOptions = List<String>.from(response.options);
    } else {
      final scene =
          response.scene.isNotEmpty ? response.scene : gs.currentScene;
      if (response.options.isNotEmpty) {
        _parsedOptions = List<String>.from(response.options);
      } else {
        _parsedOptions = _lastValidOptions.isNotEmpty
            ? List<String>.from(_lastValidOptions)
            : _buildFallbackOptions(gs, scene);
      }
      return true;
    }

    if (_host.currentAdventureId != null) {
      newState.adventureId = _host.currentAdventureId!;
    }
    // Do not make formal state visible before the whole turn (including an
    // optional option repair) is ready to commit.
    _pendingGameState = newState;
    return false;
  }

  List<String> _buildFallbackOptions(GameState state, String? scene) {
    final sceneName = scene != null && scene.trim().isNotEmpty
        ? scene.trim()
        : state.currentScene.trim();
    if (sceneName.isNotEmpty) {
      return [
        '继续探索$sceneName',
        '仔细观察周围环境',
        '检查随身物品和装备',
      ];
    }
    return [
      '继续前进',
      '观察周围环境',
      '查看当前状态',
    ];
  }

  /// v2.4: 统计中文字数（公开静态方法，供测试调用）
  static int countChinese(String text) {
    int count = 0;
    for (int i = 0; i < text.length; i++) {
      final code = text.codeUnitAt(i);
      if ((code >= 0x4E00 && code <= 0x9FFF) ||
          (code >= 0x3400 && code <= 0x4DBF)) {
        count++;
      }
    }
    return count;
  }

  Map<String, dynamic>? _tryDecodeJson(String text) {
    try {
      return jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  // ─── 发送消息（核心方法） ───

  Future<void> sendMessage(
    String content, {
    Future<String> Function(String content)? promptTransformer,
  }) async {
    if (_status != ChatStatus.idle) {
      debugPrint('[ChatEngine] sendMessage blocked — '
          'status=$_status');
      return; // 防止并发调用损坏状态
    }
    if (_host.apiKey.isEmpty) {
      _host.messages.add(Message(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        content: '⚠️ 请先配置 API 密钥',
        isUser: false,
      ));
      _notifyAll();
      return;
    }

    // v2.0: Combat interception — during combat, player input is a combat action
    final combatMgr = _host.gameEngine?.combatMgr;
    if (combatMgr != null && combatMgr.isActive) {
      _handleCombatInput(content, combatMgr);
      return;
    }

    // v2.1: Rest action — recover HP/MP/Energy without LLM call
    if (content.trim() == '[休息]' || content.trim().startsWith('[休息]')) {
      _handleRest();
      return;
    }

    // 立即设置 _status = ChatStatus.loading。
    // 必须在任何 await 之前执行，否则 async 等待期间其他调用可能进入。
    _status = ChatStatus.loading;
    final requestId =
        'scene-${DateTime.now().microsecondsSinceEpoch}-${++_generation}';
    final requestGeneration = _generation;
    final adventureId = _host.currentAdventureId;
    final branchId = _host.currentBranchId;
    final runtimeRevision = adventureId == null
        ? 0
        : (await _adventureRepo.getRuntimeHead(adventureId, branchId)).revision;
    _runtimeEntities = adventureId == null
        ? const []
        : await _adventureRepo.getRuntimeEntities(adventureId, branchId);
    _runtimeArchiveFacts = adventureId == null
        ? const []
        : await _loadRuntimeArchiveFacts(content, adventureId, branchId);
    _activeRequestId = requestId;
    _activeTaskHandle = GenerationTaskHandle(
        taskId: requestId, generationEpoch: requestGeneration);
    _scenePhase = SceneDialoguePhase.created;
    final sceneSnapshot = _freezeSceneContext(
      content,
      requestId,
      runtimeRevision: runtimeRevision,
      retrievalFacts: _runtimeArchiveFacts,
    );
    _lastSceneSnapshot = sceneSnapshot;

    if (content.trim().startsWith('/search ')) {
      try {
        final query = content.trim().substring(8);
        final webSearch = WebSearchService();
        final results = await webSearch.search(query);
        _pendingSearchResults = webSearch.formatForPrompt(results);
      } catch (_) {
        _pendingSearchResults = null; // 搜索失败不阻断消息发送
      }
    } else {
      _pendingSearchResults = null;
    }

    // ─── 1. 原地覆盖与去重保护（处理重试、重新生成、未响应消息覆盖）───
    // 清理尾部残留的错误卡片（若有）
    while (_host.messages.isNotEmpty && _host.messages.last.isError) {
      _host.messages.removeLast();
    }

    Message userMsg;
    // 检查末尾是否已有尚未得到 AI 回复的用户消息
    if (_host.messages.isNotEmpty && _host.messages.last.isUser) {
      // 收集末尾所有连续未响应的用户消息索引
      final unrespondedIndices = <int>[];
      for (int i = _host.messages.length - 1; i >= 0; i--) {
        if (_host.messages[i].isUser) {
          unrespondedIndices.add(i);
        } else {
          break;
        }
      }

      // 如果末尾用户消息与当前发送内容一致（重试、重新生成、或再次点击同选项）
      if (_host.messages.last.content.trim() == content.trim()) {
        // 如果之前因连续重试堆积了多条重复的用户气泡，清理多余项，仅保留第一条
        while (unrespondedIndices.length > 1) {
          final idx = unrespondedIndices.removeAt(0);
          _host.messages.removeAt(idx);
        }
        // 原地复用现有的用户消息气泡，绝不新追加重复气泡！
        userMsg = _host.messages.last;
      } else {
        // 用户改发了新内容（如失败后切换了其他选项）：原地移除旧的未响应消息，替换为新消息
        for (final idx in unrespondedIndices) {
          _host.messages.removeAt(idx);
        }
        userMsg = Message(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          content: content,
          isUser: true,
        );
        _host.messages.add(userMsg);
      }
    } else {
      userMsg = Message(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        content: content,
        isUser: true,
      );
      _host.messages.add(userMsg);
    }
    _notifyAll(); // 立即通知 UI，不等 DB 操作

    _status = ChatStatus.streaming;
    _streamingContent = '';
    _lastFailedContent = content;
    _cancelRequested = false;
    clearError();
    _typewriter.cancel();
    _streamNotifier.value = '';
    _reasoningContent = '';
    _reasoningStreamNotifier.value = '';
    _isThinkingNotifier.value = false;

    _status = ChatStatus.streaming;
    _streamingContent = '';
    _notifyAll();

    try {
      if (!_isRequestCurrent(
          requestId, requestGeneration, adventureId, branchId)) {
        return;
      }
      // v2.4: Per-round word count reminder + decay detection
      var controlContext = '';
      if (promptTransformer != null) {
        final transformed = await promptTransformer(content).catchError((_) {
          return content;
        });
        if (transformed.trim().isNotEmpty &&
            transformed.trim() != content.trim()) {
          controlContext = transformed;
        }
      }
      // 每轮唯一的字数数值锚点（v2.4）：系统提示词只做档位定义不重复数值，
      // 具体字数要求只在本轮用户消息携带一次，避免同一请求内指令叠加污染。
      controlContext =
          '$controlContext\n${sceneSnapshot.budget.promptRequirement}'.trim();
      if (sceneSnapshot.budget.minChineseChars >= 2000) {
        controlContext = '$controlContext\n'
            '⚠️ 深度长篇叙事模式核心准则：\n'
            '1. 叙事结构采用【一波三折·双重波折】：第一波动作与言语试探结束后，严禁草率收笔，必须立刻引出第二重突发变故/隐藏动机爆发与更深入对质，最后才合力破局与沉淀余波！以 3200 字符充实铺陈为基准展开；\n'
            '2. 状态结算：结尾 JSON 中必须输出 custom_status 字段（严禁省略！），并根据本轮互动真实增减结算主角与配角的好感度数值（严禁静止不动，正常变动 ±1 ~ ±5）！坚决跨过 ${sceneSnapshot.budget.minChineseChars} 纯汉字硬指标！';
      }
      if (_underflowWarningNextRound) {
        controlContext =
            '$controlContext\n🔴 系统指令（硬性指标·重申）：上一轮【纯汉字正文】仅 $_underflowLastActual 字，尚未跨过 ${sceneSnapshot.budget.minChineseChars} 纯汉字底线（净缺口 $_underflowDeficit 字）！本轮必须严格跨过底线！';
        _underflowWarningNextRound = false;
        _decayWarningNextRound = false;
      } else if (_decayWarningNextRound) {
        controlContext =
            '$controlContext\n🔴 系统检测：上轮纯叙事正文字数显著下降。本轮请推进多幕情节与深入对白，恢复当前档位要求的叙事细节。';
        _decayWarningNextRound = false;
      }

      String json;
      String reasoningContentCombined = '';

      final targetStages = (sceneSnapshot.budget.minChineseChars >= 2000)
          ? (sceneSnapshot.budget.minChineseChars >= 4500 ? 3 : 2)
          : 1;
      List<Map<String, String>> lengthGuardBaseMessages;

      if (targetStages > 1) {
        final minRequiredWords = sceneSnapshot.budget.minChineseChars;
        final maxAllowedStages = targetStages + 1;
        debugPrint(
            '[ChatEngine] 启用后台多阶段流水线生成: 目标 $targetStages 幕接力拼接, 最大保底 $maxAllowedStages 幕 (档位: ${_host.dialogueLevel.id}, 目标纯汉字: $minRequiredWords 字)');
        final stageNarratives = <String>[];
        var currentContextMessages = _promptBuilder.buildMessages(
          _host,
          content,
          _host.messages,
          chatSummary,
          _pendingSearchResults,
          runtimeRevision: sceneSnapshot.runtimeRevision,
          runtimeEntities: _runtimeEntities,
          archiveRetrievalFacts: _runtimeArchiveFacts,
          controlContext: controlContext,
        );
        lengthGuardBaseMessages = List.unmodifiable(currentContextMessages);

        // 构建当前监测状态的简要参考，直接注入最终阶段指令，确保 AI 真实动态结算
        final trackedAttrs =
            _host.adventureConfig?.allTrackedCustomAttributes ??
                _host.adventureConfig?.customAttributes ??
                const [];
        final statusHint = trackedAttrs.isNotEmpty
            ? '当前监测状态参考（${trackedAttrs.map((a) => '${a.characterName != null && a.characterName!.isNotEmpty ? "[${a.characterName}] " : ""}${a.name}:${a.isNumeric ? '${a.effectiveCurrentValue}/${a.effectiveMaxValue}' : a.value}').join('、')}），必须根据本轮互动真实增减结算数值（严禁静止不动，正常变动 ±1 ~ ±5）！'
            : '必须结合本轮互动真实动态结算相关数值。';

        String lastStageJson = '';
        for (int stage = 1; stage <= maxAllowedStages; stage++) {
          if (!_isRequestCurrent(
              requestId, requestGeneration, adventureId, branchId)) {
            throw const GenerationCancelledException();
          }

          final currentAccumulatedWords =
              countChinese(stageNarratives.join('\n\n'));
          final isExtensionStage = stage > targetStages;
          final isFinalStage = isExtensionStage || stage == targetStages;

          final String stageInstruction;
          if (stage == 1) {
            stageInstruction = '【分幕流水线·第 1 幕（入境铺垫与第一重波折）指令】：\n'
                '本轮为深度长篇叙事的首发半程。请展开至少 4-5 个饱满段落，全方位推进：\n'
                '① 玩家行动后的深层环境渲染与视听细节（1段）；\n'
                '② 双方角色间至少 5-7 轮推拉交锋与潜台词试探（2段）；\n'
                '③ 突发异变或隐藏动机爆发，使冲突升级至白热化对峙（1-2段）。\n'
                '⚠️ 篇幅硬性指标：本幕叙事正文必须写满 1300~1500 纯汉字，在危机最高潮悬念处暂停留白！\n'
                '⚠️ 思考长度限制：思考链不超过 300~500 字。\n'
                '⚠️ 严禁提前草率收束！绝对严禁输出 ---JSON--- 及任何选项或状态数据！写满细节后直接以正文停笔。';
          } else if (!isFinalStage) {
            final deficit =
                math.max(0, minRequiredWords - currentAccumulatedWords);
            final neededStageWords = math.max(
                1300, (deficit / (targetStages - stage + 1)).ceil() + 100);
            stageInstruction = '【分幕流水线·第 $stage 幕（第二重波折·危机激化与深度对质）指令】：\n'
                '前 ${stage - 1} 幕已推进 $currentAccumulatedWords 纯汉字。请紧接上文，继续推进事态激化与更深入的多轮对质（撰写至少 $neededStageWords 纯汉字正文，约 4-5 个充实段落）。\n'
                '⚠️ 思考长度限制：思考链不超过 150~250 字。\n'
                '在关键转折或决战前夕处暂停留白，绝对严禁输出 ---JSON--- 及任何选项或状态数据！写满细节后直接停笔。';
          } else if (isExtensionStage) {
            final deficit =
                math.max(0, minRequiredWords - currentAccumulatedWords);
            final neededStageWords = math.max(800, deficit + 150);
            stageInstruction = '【分幕流水线·第 $stage 幕（终局余波·深层暗流与最终结算·保底续写）指令】：\n'
                '前 ${stage - 1} 幕已累计推进 $currentAccumulatedWords 纯汉字，距离全篇 $minRequiredWords 纯汉字硬指标尚有缺口！\n'
                '请紧接上一幕剧情，立刻展开第三重深层余波、事后重大暗流与微观情感对质，再充实撰写至少 $neededStageWords 纯汉字叙事（2-3个充实段落）。\n'
                '叙事彻底完结后，立即输出一行分隔符 `---JSON---`，然后紧跟一行合法 JSON。\n'
                '⚠️ 【状态结算强制要求】：JSON 必须包含 options 数组及 custom_status 字段（严禁省略！）。$statusHint';
          } else {
            final deficit =
                math.max(0, minRequiredWords - currentAccumulatedWords);
            final neededStageWords = math.max(1400, deficit + 150);
            stageInstruction = '【分幕流水线·第 $stage 幕（第二重波折·终局决断与结算）指令】：\n'
                '前 ${stage - 1} 幕已推进 $currentAccumulatedWords 纯汉字。为确保全篇坚决跨过 $minRequiredWords 纯汉字硬指标，本幕你必须紧接上文展开第二重波折对质与绝境破局，撰写至少 $neededStageWords 纯汉字（约 4-5 个充实段落）：\n'
                '① 危机激化升级与尖锐言语对质（2段）；\n'
                '② 绝境破局动作拉锯与阶段定局（2段）；\n'
                '③ 事态平息后的重大暗流与情感沉淀（1段）。\n'
                '叙事彻底完结后，立即输出一行分隔符 `---JSON---`，然后紧跟一行合法 JSON。\n'
                '⚠️ 【状态结算强制要求】：JSON 必须包含 options 数组及 custom_status 字段（严禁省略！）。$statusHint';
          }

          if (stage > 1) {
            currentContextMessages =
                List<Map<String, String>>.from(currentContextMessages)
                  ..add({'role': 'assistant', 'content': stageNarratives.last})
                  ..add({'role': 'user', 'content': stageInstruction});
            _streamingContent = '${stageNarratives.join('\n\n')}\n\n';
            _typewriter.feed(_streamingContent, _streamNotifier, notifyParent);
            if (_reasoningContent.isNotEmpty) {
              _reasoningContent += '\n\n---\n[第 $stage 幕思考]\n';
              _reasoningStreamNotifier.value = _reasoningContent;
            }
          } else {
            final lastUserMsg = currentContextMessages.last;
            currentContextMessages =
                List<Map<String, String>>.from(currentContextMessages)
                  ..[currentContextMessages.length - 1] = {
                    'role': 'user',
                    'content': '$stageInstruction\n\n${lastUserMsg['content']}',
                  };
          }

          final stageExecution = await _executeAdventureContext(
            messages: currentContextMessages,
            taskType: ContextTaskType.adventureResponse,
            intent: content,
            maximumOutputTokens:
                math.max(8192, _host.completionParams.maxTokens),
            allowPartial: true,
            requestId: '$requestId:stage$stage',
            taskHandle: _activeTaskHandle,
            onChunk: (chunk) {
              if (!_isRequestCurrent(
                  requestId, requestGeneration, adventureId, branchId)) {
                return;
              }
              if (_isThinkingNotifier.value) {
                _isThinkingNotifier.value = false;
              }
              _streamingContent += chunk;
              _typewriter.feed(
                  _streamingContent, _streamNotifier, notifyParent);
            },
            onReasoningChunk: (reasoningChunk) {
              if (!_isRequestCurrent(
                  requestId, requestGeneration, adventureId, branchId)) {
                return;
              }
              if (!_isThinkingNotifier.value) {
                _isThinkingNotifier.value = true;
              }
              _reasoningContent += reasoningChunk;
              _reasoningStreamNotifier.value = _reasoningContent;
              notifyParent();
            },
          );

          if (!_isRequestCurrent(
              requestId, requestGeneration, adventureId, branchId)) {
            throw const GenerationCancelledException();
          }

          final rc = stageExecution.reasoningContent;
          if (rc != null && rc.isNotEmpty) {
            reasoningContentCombined = reasoningContentCombined.isEmpty
                ? rc
                : '$reasoningContentCombined\n\n[第 $stage 幕思考]\n$rc';
          }

          final stageRaw = stageExecution.content;
          final sepIdx = stageRaw.indexOf('---JSON---');
          final stageNarrative =
              (sepIdx >= 0 ? stageRaw.substring(0, sepIdx) : stageRaw).trim();
          stageNarratives.add(stageNarrative);

          final totalWordsSoFar = countChinese(stageNarratives.join('\n\n'));
          if (stage >= targetStages) {
            final hasJson = sepIdx >= 0;
            final isWordCountPassed = totalWordsSoFar >= minRequiredWords;
            if (isWordCountPassed || stage == maxAllowedStages) {
              if (!isWordCountPassed && stage == maxAllowedStages) {
                debugPrint(
                    '[ChatEngine] 已达最大保底幕数 ($maxAllowedStages 幕)，结束多幕接力 (总纯汉字: $totalWordsSoFar 字)');
              } else {
                debugPrint(
                    '[ChatEngine] 第 $stage 幕完成且字数达标: $totalWordsSoFar 纯汉字 >= $minRequiredWords 字，顺利结幕');
              }
              if (hasJson) {
                lastStageJson = stageRaw.substring(sepIdx);
              }
              break;
            } else {
              debugPrint(
                  '[ChatEngine] 分幕字数尚未达标 (当前累计纯汉字: $totalWordsSoFar 字，目标: $minRequiredWords 字，净缺口: ${minRequiredWords - totalWordsSoFar} 字)，自动无缝触发第 ${stage + 1} 幕续写保底！');
              lastStageJson = '';
            }
          }
        }

        json = '${stageNarratives.join('\n\n')}\n$lastStageJson';
      } else {
        final apiMessages = _promptBuilder.buildMessages(
          _host,
          content,
          _host.messages,
          chatSummary,
          _pendingSearchResults,
          runtimeRevision: sceneSnapshot.runtimeRevision,
          runtimeEntities: _runtimeEntities,
          archiveRetrievalFacts: _runtimeArchiveFacts,
          controlContext: controlContext,
        );
        lengthGuardBaseMessages = List.unmodifiable(apiMessages);
        final execution = await _executeAdventureContext(
          messages: apiMessages,
          taskType: ContextTaskType.adventureResponse,
          intent: content,
          maximumOutputTokens: _host.completionParams.enableThinking
              ? math.max(8192, _host.completionParams.maxTokens)
              : sceneSnapshot.budget
                  .outputTokensFor(_host.completionParams.maxTokens),
          requestId: requestId,
          taskHandle: _activeTaskHandle,
          onChunk: (chunk) {
            if (!_isRequestCurrent(
                requestId, requestGeneration, adventureId, branchId)) {
              return;
            }
            if (_isThinkingNotifier.value) {
              _isThinkingNotifier.value = false;
            }
            _streamingContent += chunk;
            _typewriter.feed(_streamingContent, _streamNotifier, notifyParent);
          },
          onReasoningChunk: (reasoningChunk) {
            if (!_isRequestCurrent(
                requestId, requestGeneration, adventureId, branchId)) {
              return;
            }
            if (!_isThinkingNotifier.value) {
              _isThinkingNotifier.value = true;
            }
            _reasoningContent += reasoningChunk;
            _reasoningStreamNotifier.value = _reasoningContent;
            notifyParent();
          },
        );
        json = execution.content;
        reasoningContentCombined = execution.reasoningContent ?? '';
      }

      if (!_isRequestCurrent(
          requestId, requestGeneration, adventureId, branchId)) {
        throw const GenerationCancelledException();
      }
      // Protocol normalization: rewrite the raw model output into the canonical
      // `narrative + ---JSON--- + payload` form (or payload-only).  A payload
      // can never remain embedded in the narrative, which is what previously
      // leaked `{"scene":...}` into the visible body.
      json = AdventureResponse.canonicalize(json);
      final lengthGuardResult = await _ensureNarrativeLength(
        rawResponse: json,
        baseMessages: lengthGuardBaseMessages,
        snapshot: sceneSnapshot,
        requestId: requestId,
        requestGeneration: requestGeneration,
        adventureId: adventureId,
        branchId: branchId,
      );
      // Re-canonicalize after the optional supplement: a continuation that only
      // returned settlement JSON must not be merged into the narrative.
      json = AdventureResponse.canonicalize(lengthGuardResult.content);
      // Replace the transient streamed concatenation with the canonical
      // narrative-plus-single-payload ordering before the bubble drains.
      _streamingContent = json;
      _typewriter.feed(_streamingContent, _streamNotifier, notifyParent);
      if (!_isRequestCurrent(
          requestId, requestGeneration, adventureId, branchId)) {
        throw const GenerationCancelledException();
      }
      // The model may be committed while the visual typewriter catches up.
      _typewriter.onStreamEnd(_streamNotifier, notifyParent);

      // ─── 4. 解析游戏状态和选项（P3-02: Isolate 后台解析） ───
      // 必须在切到 idle 并通知 UI 前完成，否则选项面板会短暂显示通用兜底选项。
      _scenePhase = SceneDialoguePhase.parsing;
      final needsOptionRepair = await _applySplitResponse(json);
      if (!_isRequestCurrent(
          requestId, requestGeneration, adventureId, branchId)) {
        throw const GenerationCancelledException();
      }
      final aiContent = needsOptionRepair
          ? _injectOptionsIntoAiContent(json, _parsedOptions)
          : _normalizeCustomStatusInAiContent(json);

      var aiMsg = Message(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        content: aiContent,
        reasoningContent: reasoningContentCombined,
        isUser: false,
      );
      _streamingContent = '';
      _isRepairingOptions = needsOptionRepair;

      // 在 ListView 重建（StreamingBubble 已移除）后再清空 streamNotifier
      _streamNotifier.value = '';
      _reasoningContent = '';
      _reasoningStreamNotifier.value = '';
      _isThinkingNotifier.value = false;

      final responseMap = _sceneResponseMap(json);
      final candidates = SceneSettingCandidate.parse(
          responseMap?['scene_candidates'], requestId);
      _lastSceneCandidates = List.unmodifiable(candidates);
      final marker = json.indexOf('---JSON---');
      final continuity = const SceneConsistencyValidator().validate(
        snapshot: sceneSnapshot,
        narrative: marker < 0 ? json : json.substring(0, marker),
        payload: responseMap,
      );

      if (_isRepairingOptions) {
        _scenePhase = SceneDialoguePhase.repairing;
        await _repairMissingOptions(json, content,
            requestId: requestId,
            generation: requestGeneration,
            adventureId: adventureId,
            branchId: branchId);
        if (!_isRequestCurrent(
            requestId, requestGeneration, adventureId, branchId)) {
          throw const GenerationCancelledException();
        }
        aiMsg = aiMsg.copyWith(
            content: _injectOptionsIntoAiContent(json, _parsedOptions));
        _isRepairingOptions = false;
      }

      // v2.4: 抗衰减与未达标补强 — 追踪本轮字数，检测衰减趋势与未达标缺口
      final adSepIdx = json.indexOf('---JSON---');
      final adNarrative = adSepIdx >= 0 ? json.substring(0, adSepIdx) : json;
      final currentWordCount = countChinese(adNarrative);
      if (_lastAiWordCount > 0 && currentWordCount > 0) {
        final drop = (_lastAiWordCount - currentWordCount) / _lastAiWordCount;
        if (drop > 0.25) {
          _decayWarningNextRound = true;
          debugPrint(
              '[AntiDecay] 字数衰减: $_lastAiWordCount→$currentWordCount (${(drop * 100).round()}%)，下轮强化提醒');
        }
      }
      if (!lengthGuardResult.passed(sceneSnapshot.budget.minChineseChars)) {
        _underflowWarningNextRound = true;
        _underflowDeficit =
            sceneSnapshot.budget.minChineseChars - currentWordCount;
        _underflowLastActual = currentWordCount;
        debugPrint(
            '[LengthGuard] final=$currentWordCount required=${sceneSnapshot.budget.minChineseChars} failed; next-round fallback deficit=$_underflowDeficit');
      } else {
        _underflowWarningNextRound = false;
      }
      _lastAiWordCount = currentWordCount;

      // ─── 关键修复：在 DB 持久化前保持 idle，消除 "死区" ───
      // 问题：选项芯片已显示，但 _status 仍为 loading/streaming
      // 导致用户点击选项时被并发守卫静默拦截，消息无法发送
      // Android sqflite 原生调用慢（100ms+），DB 持久化期间用户已可交互
      _scenePhase = SceneDialoguePhase.committing;
      var effects = _pendingSceneEffects;
      final config = _host.adventureConfig;
      final affinityMgr = _host.gameEngine?.affinityMgr;
      if (config != null && affinityMgr != null) {
        effects = effects.withAffinityChanges(
            affinityMgr.analyzeKeywords(content, config.supportingCharacters));
      }
      final state = effects.applyState(_pendingGameState ?? _host.gameState);
      final projectedSceneState = _promptBuilder.lastSceneState;
      final runtimeDiagnostics = <String>[];
      final runtimeChanges = RuntimeStateChangeProposal.parse(
        _sceneResponseMap(content)?['runtime_state_changes'],
        diagnostics: runtimeDiagnostics,
      );
      final runtimeDraft = runtimeChanges.isEmpty
          ? null
          : RuntimeStateCommitDraft(
              expectedRevision: sceneSnapshot.runtimeRevision,
              changes: runtimeChanges,
              summary: 'Narrative runtime changes',
              contextSnapshotId: sceneSnapshot.id,
              sourceMessageId: aiMsg.id,
            );
      final committedSceneState = projectedSceneState?.copyWith(
        location: state.currentScene.isEmpty
            ? projectedSceneState.location
            : state.currentScene,
        presentCharacterIds: _host.sceneParticipantIds
            .where((id) => projectedSceneState.presentCharacterIds.contains(id))
            .toList(growable: false),
      );
      SceneDialogueCommitResult result = SceneDialogueCommitResult(
        applied: true,
        gameState: state,
        effects: effects,
        sceneState: committedSceneState,
      );
      if (adventureId != null) {
        result =
            await _adventureRepo.commitSceneDialogueTurn(SceneDialogueCommit(
          requestId: requestId,
          adventureId: adventureId,
          branchId: branchId,
          userMessage: userMsg,
          assistantMessage: aiMsg,
          gameState: state,
          sceneState: committedSceneState,
          contextSnapshotId: sceneSnapshot.id,
          diagnostics: {
            'budget_tokens': sceneSnapshot.budget.recommendedTokens,
            if (_promptBuilder.lastContextTrace case final trace?)
              'context_trace': trace.toDiagnostics(),
            'retrieval_degraded': sceneSnapshot.diagnostics.isNotEmpty,
            'continuity': continuity.isConsistent ? 'passed' : 'warning',
            if (!continuity.isConsistent) 'warnings': continuity.warnings,
            'length_guard_triggered': lengthGuardResult.supplementAttempted,
            'length_initial_chinese_chars':
                lengthGuardResult.initialChineseChars,
            'length_required_chinese_chars':
                sceneSnapshot.budget.minChineseChars,
            'length_target_chinese_chars':
                sceneSnapshot.budget.targetChineseChars,
            'length_supplement_chinese_chars':
                lengthGuardResult.supplementChineseChars,
            'length_final_chinese_chars': lengthGuardResult.finalChineseChars,
            'length_supplement_succeeded':
                lengthGuardResult.supplementSucceeded,
            if (lengthGuardResult.supplementAttempted)
              'length_supplement_thinking': false,
            'length_final_passed':
                lengthGuardResult.passed(sceneSnapshot.budget.minChineseChars),
            if (runtimeDiagnostics.isNotEmpty)
              'ignored_runtime_state_changes': runtimeDiagnostics,
          },
          candidates: candidates,
          effects: effects,
          runtimeStateDraft: runtimeDraft,
        ));
      }
      if (!_isRequestCurrent(
          requestId, requestGeneration, adventureId, branchId)) {
        throw const GenerationCancelledException();
      }
      await _host.applySceneDialogueCommitResult(result);
      // 提交完成前，检查并清理可能残留的连续重复用户气泡
      for (int i = _host.messages.length - 1; i > 0; i--) {
        if (_host.messages[i].isUser &&
            _host.messages[i - 1].isUser &&
            _host.messages[i].content.trim() ==
                _host.messages[i - 1].content.trim()) {
          _host.messages.removeAt(i);
        }
      }
      _host.messages.add(aiMsg);
      _host.messages.addAll(result.additionalMessages);
      if (result.applied && result.effects.startsCombat) {
        final enemies = CombatManager.enemiesFromJson(result.effects.enemies);
        if (enemies.isNotEmpty) {
          _host.gameEngine?.combatMgr.enter(enemies, result.gameState);
        }
      }
      _status = ChatStatus.idle;
      _scenePhase = SceneDialoguePhase.completed;
      _notifyAll();

      // ─── 响应监控日志 ───
      final sepIdx = json.indexOf('---JSON---');
      final narrativeLen =
          sepIdx >= 0 ? json.substring(0, sepIdx).trim().length : json.length;
      final jsonLen = sepIdx >= 0 ? json.substring(sepIdx).length : 0;
      final totalLen = json.length;
      final estimateTokens = (totalLen / 1.5).round();
      final roundNum = _host.messages.where((m) => m.isUser).length;
      debugPrint('');
      debugPrint('╔══════════════════════════════════════╗');
      debugPrint('║  📊 AI 响应监控  —  第 $roundNum 轮');
      debugPrint('╠══════════════════════════════════════╣');
      debugPrint('║  总字符数:  ${totalLen.toString().padLeft(6)}         ');
      debugPrint('║  叙事字符:  ${narrativeLen.toString().padLeft(6)} 字符    ');
      debugPrint('║  纯汉字数:  ${currentWordCount.toString().padLeft(6)} 字      ');
      debugPrint('║  JSON部分:  ${jsonLen.toString().padLeft(6)} 字      ');
      debugPrint(
          '║  估算tokens: ${estimateTokens.toString().padLeft(5)}         ');
      debugPrint(
          '║  字数目标:  ≥${sceneSnapshot.budget.minChineseChars} 纯汉字         ');
      debugPrint(
          '║  达标:      ${lengthGuardResult.passed(sceneSnapshot.budget.minChineseChars) ? '✅ 是' : '❌ 否'}  ');
      debugPrint('╚══════════════════════════════════════╝');
      debugPrint('');

      _consecutiveErrors = 0;
      // 每 10 条消息触发一次自动备份
      AutoBackupService.onMessageSent();
      final tts = _host.tts;
      if (tts != null && tts.autoRead && json.isNotEmpty) {
        tts.speak(json);
      }
      _host.advanceSelectedCharacterIfAutoEnabled();
      _maybeSummarize();
    } catch (e) {
      _typewriter.cancel();
      _streamingContent = '';
      _streamNotifier.value = '';
      _reasoningContent = '';
      _reasoningStreamNotifier.value = '';
      _isThinkingNotifier.value = false;

      // 立即重置 status，确保用户可重试
      _status = ChatStatus.idle;

      // 用户主动取消 — 不添加错误消息，静默清理
      if (_cancelRequested ||
          !_isRequestCurrent(
              requestId, requestGeneration, adventureId, branchId)) {
        _cancelRequested = false;
        _scenePhase = SceneDialoguePhase.cancelled;
        // 移除用户刚发送的消息（因为 AI 没有回复）
        final msgs = _host.messages;
        if (msgs.isNotEmpty && msgs.last.isUser) {
          msgs.removeLast();
        }
        _notifyAll(); // 通知 UI 消息已移除
      } else {
        _scenePhase = SceneDialoguePhase.failed;
        _consecutiveErrors++;
        String errorMsg;

        if (e is ApiError) {
          _lastErrorType = switch (e.type) {
            ApiErrorType.networkTimeout => errorTypeTimeout,
            ApiErrorType.unauthorized => errorTypeAuth,
            ApiErrorType.rateLimited => errorTypeRate,
            _ => errorTypeApi,
          };
          _lastErrorDetail = e.userMessage;
        } else {
          _lastErrorType = errorTypeNetwork;
          _lastErrorDetail = e.toString().split('\n').first;
        }

        if (e is ApiError) {
          errorMsg = '⚠️ ${e.userMessage}';
          if (e.type == ApiErrorType.unauthorized) {
            errorMsg += '\n\n💡 请在设置中更新 API Key（左上角菜单 → API 设置）';
          } else if (e.type == ApiErrorType.rateLimited) {
            errorMsg += '\n\n💡 请等待几秒后自动恢复，或切换模型降低频率';
          }
        } else {
          errorMsg =
              '⚠️ 请求失败\n\n${e.toString().split('\n').first}\n\n💡 请检查网络连接和 API 设置后重试';
        }
        if (_consecutiveErrors >= 3) {
          errorMsg +=
              '\n\n🔧 连续 $_consecutiveErrors 次失败\n建议：检查 API Key 有效性、切换模型、或检查网络';
        }

        _host.messages.add(Message(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          content: errorMsg,
          isUser: false,
          errorType: _lastErrorType,
        ));
      }
    } finally {
      // 安全网：确保 _status 在任何路径下都被重置
      //（try/catch 中已提前设置，此处不重复 notifyParent 只在未通知时补发）
      if (_status != ChatStatus.idle) {
        _status = ChatStatus.idle;
      }
      if (_activeRequestId == requestId) {
        _activeRequestId = null;
        _activeTaskHandle = null;
      }
      _notifyAll();
    }
  }

  Future<void> _repairMissingOptions(
    String aiContent,
    String userContent, {
    required String requestId,
    required int generation,
    required int? adventureId,
    required int branchId,
  }) async {
    try {
      // 当前候选可能是解析失败后沿用的上一轮选项；把它们一并交给修复模型
      // 作为避雷名单，避免修复结果再次与历史选项雷同。
      final optionsToAvoid = <String>{..._parsedOptions, ..._lastValidOptions}
          .toList(growable: false);
      final prompt = _buildOptionRepairPrompt(aiContent, userContent,
          optionsToAvoid: optionsToAvoid);
      final result = (await _executeAdventureContext(
        messages: [
          {
            'role': 'system',
            'content': '你是文字冒险游戏的行动选项修复器。只根据当前剧情生成短小、具体、可点击的行动选项，不续写剧情。',
          },
          {'role': 'user', 'content': prompt},
        ],
        taskType: ContextTaskType.adventureOptionRepair,
        intent: prompt,
        maximumOutputTokens: _optionRepairParams.maxTokens,
        overrideParams: _optionRepairParams,
        requestId: '$requestId:options',
        taskHandle: _activeTaskHandle,
      ))
          .content;
      if (!_isRequestCurrent(requestId, generation, adventureId, branchId)) {
        return;
      }
      final options = _parseRepairedOptions(result);
      if (options.isNotEmpty) {
        _parsedOptions = List<String>.from(options);
        _lastValidOptions = List<String>.from(options);
      }
      try {
        final cleaned = AdventureResponse.cleanJsonBlock(result);
        final decoded = jsonDecode(cleaned);
        if (decoded is Map<String, dynamic> &&
            decoded['custom_status'] != null) {
          _syncCustomStatusUpdates(decoded['custom_status']);
        }
      } catch (_) {}
    } catch (e) {
      debugPrint('[ChatEngine] 修复/补充 JSON 失败: $e');
    }
  }

  void _syncCustomStatusUpdates(dynamic rawStatus) {
    if (rawStatus == null || _host.adventureConfig == null) return;
    final config = _host.adventureConfig!;
    final List<CustomAttributeItem> statusUpdates;
    if (rawStatus is List<CustomAttributeItem>) {
      statusUpdates = rawStatus;
    } else {
      statusUpdates = AdventureResponse.parseCustomStatus(rawStatus);
    }
    if (statusUpdates.isEmpty) return;

    final protagonistName = config.name.trim();
    final curAttrs = config.customAttributes;
    final supportingChars = config.supportingCharacters;

    bool isCharacterMatch(String? candidate, String targetFullName,
        {required bool isProtagonist}) {
      if (candidate == null || candidate.trim().isEmpty) {
        return isProtagonist;
      }
      final c = candidate.trim().toLowerCase();
      final target = targetFullName.trim().toLowerCase();
      if (c == target) return true;
      if (isProtagonist && (c == '主角' || c == '玩家' || c == '自身' || c == '我')) {
        return true;
      }
      if (!isProtagonist && (c == '同伴' || c == '配角' || c == '队友')) {
        return true;
      }
      final targetFirstName = target.split('·').first.trim();
      if (targetFirstName.isNotEmpty &&
          (c == targetFirstName ||
              c.contains(targetFirstName) ||
              targetFirstName.contains(c))) {
        return true;
      }
      return target.contains(c) || c.contains(target);
    }

    // 1. 更新主角自定义检测状态
    final updatedProtagonistAttrs = curAttrs.map((cur) {
      final matched = statusUpdates.where((s) {
        if (s.name.trim() != cur.name.trim()) return false;
        return isCharacterMatch(s.characterName, protagonistName,
            isProtagonist: true);
      }).firstOrNull;

      if (matched != null) {
        return _applyAttributeUpdate(cur, matched);
      }
      return cur;
    }).toList();

    // 2. 更新存活配角的自定义检测状态及好感度
    final updatedSupportingChars = supportingChars.map((sc) {
      if (!sc.isAlive) return sc;
      final scName = sc.name.trim();
      var scAffinity = sc.affinity;

      // 检查直接针对该配角的好感度更新项
      final directAffinityUpdate = statusUpdates.where((s) {
        final n = s.name.trim().toLowerCase();
        if (!n.contains('好感') && !n.contains('affinity')) return false;
        return isCharacterMatch(s.characterName, scName, isProtagonist: false);
      }).firstOrNull;
      if (directAffinityUpdate != null) {
        if (directAffinityUpdate.currentValue != null) {
          scAffinity = directAffinityUpdate.currentValue!.clamp(0, 100);
        } else if (directAffinityUpdate.isNumeric) {
          scAffinity = directAffinityUpdate.effectiveCurrentValue.clamp(0, 100);
        }
      }

      final updatedAttrs = sc.customAttributes.map((cur) {
        final matched = statusUpdates.where((s) {
          if (s.name.trim() != cur.name.trim()) return false;
          return isCharacterMatch(s.characterName, scName,
              isProtagonist: false);
        }).firstOrNull;

        if (matched != null) {
          final updated = _applyAttributeUpdate(cur, matched);
          // Persistent affinity belongs to Runtime State commits. A generated
          // custom-status display must not silently mutate frozen baseline.
          return updated;
        }
        return cur;
      }).toList();

      return sc.copyWith(
        customAttributes: updatedAttrs,
        affinity: scAffinity,
      );
    }).toList();

    debugPrint(
        '[ChatEngine] _syncCustomStatusUpdates: 更新完成. 主角状态: ${updatedProtagonistAttrs.map((a) => '${a.name}=${a.effectiveCurrentValue}').join(', ')}; 配角: ${updatedSupportingChars.map((s) => '${s.name}(好感:${s.affinity})').join(', ')}');

    _host.updateAdventureConfig(
      config.copyWith(
        customAttributes: updatedProtagonistAttrs,
        supportingCharacters: updatedSupportingChars,
      ),
    );
  }

  CustomAttributeItem _applyAttributeUpdate(
      CustomAttributeItem cur, CustomAttributeItem update) {
    final newCurrent = update.currentValue ?? cur.currentValue;
    final newMax = update.maxValue ?? cur.maxValue;
    String newValue = update.value.isNotEmpty ? update.value : cur.value;
    if (cur.isNumeric && newCurrent != null && !newValue.contains('/')) {
      final maxVal = newMax ?? cur.effectiveMaxValue;
      newValue = '$newCurrent/$maxVal';
    }
    return cur.copyWith(
      currentValue: newCurrent,
      maxValue: newMax,
      value: newValue,
    );
  }

  /// Executes the single, internal continuation permitted for an underlength
  /// response. It runs before parsing and committing, so the supplement is
  /// never a user message or a second scene transaction.
  Future<NarrativeLengthGuardResult> _ensureNarrativeLength({
    required String rawResponse,
    required List<Map<String, String>> baseMessages,
    required SceneDialogueContextSnapshot snapshot,
    required String requestId,
    required int requestGeneration,
    required int? adventureId,
    required int branchId,
  }) async {
    final initial = _lengthGuard.withoutSupplement(rawResponse);
    final minimum = snapshot.budget.minChineseChars;
    if (initial.passed(minimum)) {
      debugPrint('[LengthGuard] initial=${initial.initialChineseChars} '
          'required=$minimum passed=true');
      return initial;
    }

    if (!_isRequestCurrent(
        requestId, requestGeneration, adventureId, branchId)) {
      throw const GenerationCancelledException();
    }

    final initialParts = _lengthGuard.split(rawResponse);
    final prompt = _lengthGuard.buildSupplementPrompt(
      initial: initialParts,
      currentChineseChars: initial.initialChineseChars,
      minimumChineseChars: minimum,
    );
    final additionalChars = _lengthGuard.requestedAdditionalChars(
      currentChineseChars: initial.initialChineseChars,
      minimumChineseChars: minimum,
    );
    // Chinese output tokenisation varies by provider. Reserve both the
    // established scene budget and a deficit-derived amount, bounded by the
    // frozen model capability so a supplement cannot exceed it.
    final requestedTokens = math.max(
      snapshot.budget.outputTokensFor(_host.completionParams.maxTokens),
      (additionalChars * 1.5).ceil(),
    );
    final maximumOutputTokens = requestedTokens
        .clamp(1, _host.modelContextCapability.maximumOutputTokens)
        .toInt();
    // For a payload-only response the narrative is empty, so the payload
    // itself is the assistant context the supplement must continue from.
    final assistantContext = initialParts.narrative.isNotEmpty
        ? initialParts.narrative
        : rawResponse.trim();
    final continuationMessages = List<Map<String, String>>.from(baseMessages);
    if (assistantContext.isNotEmpty) {
      continuationMessages
          .add({'role': 'assistant', 'content': assistantContext});
    }
    continuationMessages.add({'role': 'user', 'content': prompt});
    final supplementParams = _lengthGuard.supplementParams(
      _host.completionParams,
      maximumOutputTokens: maximumOutputTokens,
    );

    debugPrint('[LengthGuard] initial=${initial.initialChineseChars} '
        'required=$minimum deficit=${minimum - initial.initialChineseChars}; '
        'requesting one same-turn supplement thinking=false target='
        '${_lengthGuard.desiredTotalChars(minimum)}');
    try {
      // The main request may have displayed reasoning. Keep that content, but
      // make the transition to continuation prose explicit for the same bubble.
      _isThinkingNotifier.value = false;
      final supplement = await _executeAdventureContext(
        messages: continuationMessages,
        taskType: ContextTaskType.adventureLengthSupplement,
        intent: snapshot.userInput,
        maximumOutputTokens: maximumOutputTokens,
        requestId: '$requestId:length-supplement',
        taskHandle: _activeTaskHandle,
        allowPartial: true,
        overrideParams: supplementParams,
        onChunk: (chunk) {
          if (!_isRequestCurrent(
              requestId, requestGeneration, adventureId, branchId)) {
            return;
          }
          if (_isThinkingNotifier.value) {
            _isThinkingNotifier.value = false;
          }
          _streamingContent += chunk;
          _typewriter.feed(_streamingContent, _streamNotifier, notifyParent);
        },
      );
      if (!_isRequestCurrent(
          requestId, requestGeneration, adventureId, branchId)) {
        throw const GenerationCancelledException();
      }
      final merged = _lengthGuard.merge(
        initialRawResponse: rawResponse,
        supplementRawResponse: supplement.content,
        supplementSucceeded: true,
      );
      debugPrint('[LengthGuard] supplement=${merged.supplementChineseChars} '
          'final=${merged.finalChineseChars} passed=${merged.passed(minimum)}');
      return merged;
    } on GenerationCancelledException {
      rethrow;
    } catch (error) {
      if (!_isRequestCurrent(
          requestId, requestGeneration, adventureId, branchId)) {
        throw const GenerationCancelledException();
      }
      // The initial response is still usable. A failed optional supplement
      // falls back to the next-round warning rather than discarding the turn.
      debugPrint('[LengthGuard] supplement failed; preserving initial response '
          '(${error.runtimeType})');
      return NarrativeLengthGuardResult(
        content: rawResponse,
        initialChineseChars: initial.initialChineseChars,
        supplementChineseChars: 0,
        finalChineseChars: initial.finalChineseChars,
        supplementAttempted: true,
        supplementSucceeded: false,
      );
    }
  }

  /// Maps an adventure sub-request to its semantic [LlmTask] and resolves the
  /// request params from the active model capability plus the user's settings.
  CompletionParams _paramsForContextTask(ContextTaskType? taskType) {
    final task = switch (taskType) {
      ContextTaskType.adventureLengthSupplement => LlmTask.narrativeSupplement,
      ContextTaskType.adventureOptionRepair => LlmTask.structuredExtraction,
      ContextTaskType.adventureSummary => LlmTask.summary,
      ContextTaskType.adventureResponse || null => LlmTask.adventureNarrative,
    };
    return const LlmTaskResolver().resolve(
      task: task,
      capabilities: ModelCapabilityRegistry.resolve(_host.modelName),
      userParams: _host.completionParams,
    );
  }

  Future<ContextExecutionResult> _executeAdventureContext({
    required List<Map<String, String>> messages,
    required int maximumOutputTokens,
    required String requestId,
    GenerationTaskHandle? taskHandle,
    void Function(String chunk)? onChunk,
    void Function(String reasoningChunk)? onReasoningChunk,
    ContextTaskType? taskType,
    String? intent,
    bool allowPartial = false,
    CompletionParams? overrideParams,
  }) async {
    // Normal adventure sub-requests resolve through the Task→Policy layer;
    // deterministic repairs (option repair, length supplement) pass an explicit
    // override whose thinking mode already matches its policy task.
    final baseParams = overrideParams ?? _paramsForContextTask(taskType);
    final result = await _host.llmService.sendMessageStreamDetailed(
      messages,
      (chunk) {
        if (onChunk != null) onChunk(chunk);
      },
      () {},
      onReasoningChunk: onReasoningChunk,
      params: baseParams.copyWith(
        maxTokens: maximumOutputTokens,
      ),
      taskHandle: taskHandle,
    );
    final content = result.content;
    final trimmed = content.trim();
    final isNormalComplete =
        result.responseCompleted && result.finishReason.allowsParsing;

    if (!isNormalComplete) {
      // 1. 显式允许部分结果（如分幕流水线），只要生成有效字符（>=50字）即可平滑接力
      if (allowPartial && trimmed.length >= 50) {
        debugPrint(
            '[ChatEngine] _executeAdventureContext: 分阶段流水线已产出 ${trimmed.length} 字有效正文，继续后续接力 (finishReason: ${result.finishReason.stableValue})');
        return ContextExecutionResult(
          content: content,
          reasoningContent: result.reasoningContent,
        );
      }

      // 2. 正文叙事任务：若已产生实质性长文本（>=100字），即使被 length 截断或偶发流断开，
      // 也不抛异常抹除用户屏幕上的内容，而是交付下游由 _applySplitResponse 和 _repairMissingOptions 兜底修复选项和状态
      if (taskType == ContextTaskType.adventureResponse &&
          trimmed.length >= 100) {
        debugPrint(
            '[ChatEngine] _executeAdventureContext: 叙事正文已产出 ${trimmed.length} 字，转入下游容错与自动选项修复 (finishReason: ${result.finishReason.stableValue})');
        return ContextExecutionResult(
          content: content,
          reasoningContent: result.reasoningContent,
        );
      }

      throw StateError('模型响应未完整完成，不能使用部分结果');
    }

    return ContextExecutionResult(
      content: result.content,
      reasoningContent: result.reasoningContent,
    );
  }

  bool _isRequestCurrent(
    String requestId,
    int generation,
    int? adventureId,
    int branchId,
  ) =>
      !_disposed &&
      !_cancelRequested &&
      _activeRequestId == requestId &&
      _generation == generation &&
      _host.currentAdventureId == adventureId &&
      _host.currentBranchId == branchId &&
      !(_activeTaskHandle?.isCancelled ?? false);

  String _buildOptionRepairPrompt(String aiContent, String userContent,
      {List<String> optionsToAvoid = const []}) {
    final state = _host.gameState;
    final scene = state.currentScene.isNotEmpty ? state.currentScene : '当前场景';
    final customAttrs = _host.adventureConfig?.allTrackedCustomAttributes ??
        _host.adventureConfig?.customAttributes ??
        const [];
    final recent = _truncateForOptionRepair(
      AdventureResponse.streamingDisplayText(aiContent).trim(),
      2600,
    );
    final player = _truncateForOptionRepair(userContent.trim(), 400);
    final recentMessages = _host.messages.length > 6
        ? _host.messages.sublist(_host.messages.length - 6)
        : _host.messages;
    final history = _truncateForOptionRepair(
      recentMessages
          .map((m) => '${m.isUser ? '用户' : 'AI'}：${m.content}')
          .join('\n'),
      1800,
    );
    final avoidSection = optionsToAvoid.isEmpty
        ? ''
        : '\n以下是最近已经出现过的选项，新选项不得与它们重复或高度相似：\n'
            '${optionsToAvoid.map((option) => '- $option').join('\n')}\n';

    final distinctCharacters = customAttrs
        .map((a) => a.characterName?.trim())
        .where((n) => n != null && n.isNotEmpty)
        .toSet();
    final isMultiChar = distinctCharacters.length > 1;

    final String customSection;
    final String jsonExample;
    if (customAttrs.isEmpty) {
      customSection = '';
      jsonExample = '{"options":["选项1","选项2","选项3","选项4"]}';
    } else if (isMultiChar) {
      final exampleMap = <String, Map<String, dynamic>>{};
      for (final attr in customAttrs) {
        final cName = attr.characterName ?? '角色';
        exampleMap.putIfAbsent(cName, () => {})[attr.name] =
            attr.isNumeric ? attr.effectiveCurrentValue : '最新数值或阶段';
      }
      final exampleJson = jsonEncode(exampleMap);
      customSection = '\n当前自定义检测状态（按角色区分）：\n'
          '${customAttrs.map((a) => '- [${a.characterName}] ${a.toPromptText()}').join('\n')}\n'
          '若剧情导致上述状态变化，请在 JSON 中附加 "custom_status": $exampleJson；未变化则无需附加。\n';
      jsonExample =
          '{"options":["选项1","选项2","选项3","选项4"], "custom_status":$exampleJson}';
    } else {
      final firstChar = customAttrs.first.characterName;
      final prefix =
          firstChar != null && firstChar.isNotEmpty ? '[$firstChar] ' : '';
      customSection = '\n当前自定义检测状态：\n'
          '${customAttrs.map((a) => '- $prefix${a.toPromptText()}').join('\n')}\n'
          '若剧情导致上述状态变化，请在 JSON 中附加 "custom_status": {"${customAttrs.first.name}": 最新数值或阶段}；未变化则无需附加。\n';
      jsonExample =
          '{"options":["选项1","选项2","选项3","选项4"], "custom_status":{"${customAttrs.first.name}":最新数值或阶段}}';
    }

    return '''
请为当前文字冒险回复补充生成一段 JSON 数据（包含 3 到 4 个行动选项${customAttrs.isNotEmpty ? '与自定义检测状态' : ''}）。

要求：
- 每个选项为 15 到 50 个中文字，不得少于 15 字或超过 50 字。
- 选项必须贴合当前剧情、当前危机、当前人物关系。
- 不要使用「继续探索」「观察环境」「查看状态」「休息片刻」这类泛化模板，除非当前剧情确实没有更具体分支。
- 不要解释，不要写剧情，不要输出 Markdown。
- 只输出合法 JSON：$jsonExample
$customSection$avoidSection
当前场景：$scene
玩家刚才行动：$player
最近对话：
$history

AI 刚才的剧情回复：
$recent
''';
  }

  String _truncateForOptionRepair(String text, int maxChars) {
    if (text.length <= maxChars) return text;
    return text.substring(text.length - maxChars);
  }

  List<String> _parseRepairedOptions(String result) {
    final cleaned = AdventureResponse.cleanJsonBlock(result);
    final candidates = <String>[];

    void addOption(dynamic value) {
      final option = value?.toString().trim() ?? '';
      if (option.isEmpty) return;
      candidates.add(option);
    }

    try {
      final decoded = jsonDecode(cleaned);
      if (decoded is Map<String, dynamic>) {
        final options = decoded['options'];
        if (options is List) {
          for (final option in options) {
            addOption(option);
          }
        }
      } else if (decoded is List) {
        for (final option in decoded) {
          addOption(option);
        }
      }
    } catch (_) {
      final lines = cleaned
          .split(RegExp(r'[\n\r]+'))
          .map((line) => line
              .replaceFirst(RegExp(r'^\s*[-*]\s*'), '')
              .replaceFirst(RegExp(r'^\s*\d+[.、]\s*'), '')
              .trim())
          .where((line) => line.isNotEmpty);
      for (final line in lines) {
        addOption(line);
      }
    }

    final unique = <String>[];
    final seen = <String>{};
    for (final option in candidates) {
      final normalized = option.replaceAll(RegExp(r'\s+'), '');
      if (seen.add(normalized)) unique.add(option);
      if (unique.length == 6) break;
    }
    return unique.length >= 3 ? unique : const [];
  }

  String _injectOptionsIntoAiContent(String aiContent, List<String> options) {
    final scene = _host.gameState.currentScene.trim();
    final customAttrs = _host.adventureConfig?.allTrackedCustomAttributes ??
        _host.adventureConfig?.customAttributes ??
        const [];
    final fallbackJson = <String, dynamic>{
      'scene': scene.isNotEmpty ? scene : '当前场景',
      'hp': _host.gameState.hp,
      'max_hp': _host.gameState.maxHp,
      'energy': _host.gameState.energy,
      'max_energy': _host.gameState.maxEnergy,
      'gold': _host.gameState.gold,
      'inventory': List<String>.from(_host.gameState.inventory),
      'options': options,
      if (customAttrs.isNotEmpty)
        'custom_status': customAttrs.map((a) => a.toJson()).toList(),
    };

    final sepMatch = RegExp(r'\n?\s*---JSON---\s*\n?').firstMatch(aiContent);
    if (sepMatch == null) {
      return '${aiContent.trim()}\n---JSON---\n${jsonEncode(fallbackJson)}';
    }

    final narrative = aiContent.substring(0, sepMatch.start).trimRight();
    final jsonText = aiContent.substring(sepMatch.end).trim();
    try {
      final cleaned = AdventureResponse.cleanJsonBlock(jsonText);
      final decoded = jsonDecode(cleaned);
      if (decoded is Map<String, dynamic>) {
        final merged = Map<String, dynamic>.from(decoded);
        merged['options'] = options;
        final mergedScene = merged['scene']?.toString().trim() ?? '';
        merged['scene'] = scene.isNotEmpty
            ? scene
            : (mergedScene.isNotEmpty ? mergedScene : '当前场景');
        merged['hp'] = merged['hp'] ?? _host.gameState.hp;
        merged['max_hp'] = merged['max_hp'] ?? _host.gameState.maxHp;
        merged['energy'] = merged['energy'] ?? _host.gameState.energy;
        merged['max_energy'] =
            merged['max_energy'] ?? _host.gameState.maxEnergy;
        merged['gold'] = merged['gold'] ?? _host.gameState.gold;
        merged['inventory'] =
            merged['inventory'] ?? List<String>.from(_host.gameState.inventory);
        if (customAttrs.isNotEmpty) {
          merged['custom_status'] = customAttrs.map((a) => a.toJson()).toList();
        } else {
          merged.remove('custom_status');
          merged.remove('custom_attributes');
        }
        return '$narrative\n---JSON---\n${jsonEncode(merged)}';
      }
    } catch (_) {
      // fall back to a synthetic JSON block below.
    }

    return '$narrative\n---JSON---\n${jsonEncode(fallbackJson)}';
  }

  /// 保证 AI 正文中的 JSON 段包含所有追踪角色的最新自定义检测状态快照
  String _normalizeCustomStatusInAiContent(String content) {
    final config = _host.adventureConfig;
    final tracked = config?.allTrackedCustomAttributes ??
        config?.customAttributes ??
        const [];
    if (tracked.isEmpty) return content;

    final sepMatch = RegExp(r'\n?\s*---JSON---\s*\n?').firstMatch(content);
    if (sepMatch == null) return content;

    final narrative = content.substring(0, sepMatch.start).trimRight();
    final jsonText = content.substring(sepMatch.end).trim();
    try {
      final cleaned = AdventureResponse.cleanJsonBlock(jsonText);
      final decoded = jsonDecode(cleaned);
      if (decoded is Map<String, dynamic>) {
        final merged = Map<String, dynamic>.from(decoded);
        merged['custom_status'] = tracked.map((a) => a.toJson()).toList();
        return '$narrative\n---JSON---\n${jsonEncode(merged)}';
      }
    } catch (_) {}
    return content;
  }

  // ─── v2.1: Rest action ───

  void _handleRest() {
    final gs = _host.gameState;
    final hpHeal = (gs.maxHp * 0.3).round();
    final mpHeal = (gs.maxMp * 0.3).round();
    const enHeal = 20;
    final newHp = (gs.hp + hpHeal).clamp(0, gs.maxHp);
    final newMp = (gs.mp + mpHeal).clamp(0, gs.maxMp);
    final newEn = (gs.energy + enHeal).clamp(0, gs.maxEnergy);

    _host.updateGameState(gs.copyWith(
      hp: newHp,
      mp: newMp,
      energy: newEn,
    ));

    _host.messages.add(Message(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      content:
          '💤 你休息了一会儿，恢复了 ${newHp - gs.hp} HP / ${newMp - gs.mp} MP / ${newEn - gs.energy} 能量。',
      isUser: true,
    ));
    _host.messages.add(Message(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      content: '（你感觉精神好多了。要继续剧情吗？）',
      isUser: false,
    ));
    _notifyAll();
  }

  // ─── v2.1: Level-up check ───

  /// 检查并处理升级。返回升级次数（支持跳级）。
  int checkLevelUp() {
    final gs = _host.gameState;
    int levelsGained = 0;

    while (gs.experience >= gs.expToNextLevel) {
      final overflowExp = gs.experience - gs.expToNextLevel;
      final newLevel = gs.level + 1;
      _host.updateGameState(gs.copyWith(
        level: newLevel,
        experience: overflowExp,
        hp: gs.maxHp + 5, // 升级满血 + 上限提升
        maxHp: gs.maxHp + 5,
        mp: gs.maxMp + 3, // 升级满蓝 + 上限提升
        maxMp: gs.maxMp + 3,
        baseAtk: gs.baseAtk + 1,
        baseDef: gs.baseDef + 1,
        baseSpeed: gs.baseSpeed + 1,
        skillPoints: gs.skillPoints + 2,
      ));
      levelsGained++;

      // Log the level-up
      _host.messages.add(Message(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        content: '🌟 升级！现在是 Lv.$newLevel\n'
            'HP/MP 完全恢复 | 全属性 +1 | 获得 2 技能点',
        isUser: false,
      ));
    }

    if (levelsGained > 0) _notifyAll();
    return levelsGained;
  }

  // ─── v2.0: Combat input handling ───

  void _handleCombatInput(String content, dynamic combatMgr) {
    final action = _parseCombatAction(content);
    final result = combatMgr.playerAct(action);
    _host.messages.add(Message(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      content: '⚔️ $content\n\n${result.description}',
      isUser: true,
    ));
    _notifyAll();

    // Enemy turn
    if (combatMgr.isActive) {
      final enemyResults = combatMgr.enemyTurn();
      for (final er in enemyResults) {
        _host.messages.add(Message(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          content: '${er.actorName} ${er.action} → ${er.description}',
          isUser: false,
        ));
      }
      _notifyAll();
    }

    // v2.1: Check level-up after combat victory
    if (result.isVictory || (combatMgr.activeCombat?.isVictory ?? false)) {
      checkLevelUp();
    }
  }

  CombatAction _parseCombatAction(String content) {
    final c = content.trim();
    if (c.contains('攻击') || c.contains('attack')) return CombatAction.attack;
    if (c.contains('技能') || c.contains('skill')) return CombatAction.skill;
    if (c.contains('防御') || c.contains('defend')) return CombatAction.defend;
    if (c.contains('道具') || c.contains('item') || c.contains('药')) {
      return CombatAction.item;
    }
    if (c.contains('逃跑') || c.contains('flee')) return CombatAction.flee;
    return CombatAction.attack; // default
  }

  // ─── 摘要 ───

  void _maybeSummarize() {
    final summaryGeneration = _generation;
    _summaryService.maybeSummarize(
      host: _host,
      messages: _host.messages,
      generation: summaryGeneration,
      isCurrent: _isSummaryCurrent,
      lastSummaryAt: _lastSummaryAt,
      lastSummaryTime: _lastSummaryTime,
      onGenerate: (msgs, upToIndex, adventureId, branchId, generation) async {
        // v2.13: 构建当前状态快照 + 获取上期快照，供摘要 LLM 对比
        final gs = _host.gameState;
        final gameEng = _host.gameEngine;

        List<Quest>? activeQuests;
        if (gameEng != null) {
          activeQuests = gameEng.questMgr.activeQuests;
        }

        Map<String, int>? affinities;
        final config = _host.adventureConfig;
        if (config != null && gameEng != null) {
          affinities = {};
          for (final npc
              in config.supportingCharacters.where((n) => n.isAlive)) {
            affinities[npc.name] = npc.affinity;
          }
        }

        final stateSnapshot =
            SummaryService.buildStateSnapshot(gs, activeQuests, affinities);

        String? previousStateSnapshot;
        final prev = await _adventureRepo.getLatestSummaryWithSnapshot(
          adventureId,
          branchId: branchId,
        );
        if (!_isSummaryCurrent(adventureId, branchId, generation)) return;
        previousStateSnapshot = prev?['state_snapshot'] as String?;

        await _summaryService.generateSummary(
          msgs: msgs,
          upToIndex: upToIndex,
          host: _host,
          adventureId: adventureId,
          branchId: branchId,
          generation: generation,
          isCurrent: _isSummaryCurrent,
          stateSnapshot: stateSnapshot,
          previousStateSnapshot: previousStateSnapshot,
          onSuccess: (summary) {
            chatSummary = summary;
            _lastSummaryAt = _host.messages.length;
            _lastSummaryTime = DateTime.now();
          },
          onNotify: notifyParent,
        );
      },
    );
  }

  bool _isSummaryCurrent(int adventureId, int branchId, int generation) =>
      !_disposed &&
      _generation == generation &&
      _host.currentAdventureId == adventureId &&
      _host.currentBranchId == branchId;

  // ─── P0-1: 错误重试 ───

  Future<void> retryLast(
      {LLMProvider? overrideProvider, String? overrideModel}) async {
    if (_lastFailedContent == null) return;
    if (overrideProvider != null) {
      await _host.changeProvider(overrideProvider);
    }
    if (overrideModel != null) {
      await _host.changeModel(overrideModel);
    }
    final content = _lastFailedContent!;
    _lastFailedContent = null;
    // Remove the existing error message before retry
    removeLastIfError();
    clearError();
    await sendMessage(content);
  }

  /// 取消当前正在进行的流式请求
  void cancelStreaming() {
    if (_status == ChatStatus.streaming || _status == ChatStatus.loading) {
      _cancelRequested = true;
      _generation++;
      _activeTaskHandle?.cancel();
      _typewriter.cancel();
    }
  }

  Future<List<String>> _loadRuntimeArchiveFacts(
    String input,
    int adventureId,
    int branchId,
  ) async {
    final intent = const IntentResolver().resolve(input);
    if (!intent.asksHistory) return const [];
    final config = _host.adventureConfig;
    final relevantIds = <String>{..._host.sceneParticipantIds};
    for (final character in config?.supportingCharacters ?? const []) {
      if (input.contains(character.name)) relevantIds.add(character.id);
    }
    final facts = <String>[];
    for (final entityId in relevantIds.take(3)) {
      final changes = await _adventureRepo.getRecentStateChangesForEntity(
        adventureId,
        branchId,
        RuntimeEntityType.character,
        entityId,
        limit: 3,
      );
      for (final change in changes) {
        final reason = change['reason']?.toString().trim() ?? '';
        final revision = change['revision'];
        if (reason.isNotEmpty) facts.add('r$revision: $reason');
      }
    }
    return List.unmodifiable(facts.take(5));
  }

  SceneDialogueContextSnapshot _freezeSceneContext(
    String content,
    String requestId, {
    required int runtimeRevision,
    required List<String> retrievalFacts,
  }) {
    final config = _host.adventureConfig;
    final protagonist = SceneParticipantRef(
      id: 'protagonist',
      name: config?.name.trim().isNotEmpty == true ? config!.name : '主角',
      kind: 'protagonist',
      publicProfile: {
        if (config?.protagonistClass.trim().isNotEmpty == true)
          'identity': config!.protagonistClass,
        if (config?.personality.trim().isNotEmpty == true)
          'personality': config!.personality,
      },
    );
    final presentIds = _host.sceneParticipantIds.toSet();
    final actorId = _host.scenePresence?.actorId ?? 'protagonist';
    final selectedNpc = config?.supportingCharacters
        .where((npc) =>
            npc.id == actorId && npc.isAlive && presentIds.contains(npc.id))
        .firstOrNull;
    final actor = selectedNpc == null
        ? protagonist
        : SceneParticipantRef(
            id: selectedNpc.id,
            name: selectedNpc.name,
            kind: 'npc',
            isAlive: selectedNpc.isAlive,
            publicProfile: {
              if (selectedNpc.role.isNotEmpty) 'identity': selectedNpc.role,
              if (selectedNpc.personality.isNotEmpty)
                'personality': selectedNpc.personality,
            },
          );
    final present = <SceneParticipantRef>[protagonist];
    if (config != null) {
      for (final npc in config.supportingCharacters) {
        if (npc.isAlive && presentIds.contains(npc.id)) {
          present.add(SceneParticipantRef(
              id: npc.id,
              name: npc.name,
              kind: 'npc',
              isAlive: true,
              publicProfile: {
                if (npc.role.isNotEmpty) 'identity': npc.role,
                if (npc.personality.isNotEmpty) 'personality': npc.personality,
              }));
        }
      }
    }
    final snapshot = config?.worldviewSnapshot;
    final details = WorldviewDetails.fromJson(
        snapshot?['detail_json'] is Map
            ? Map<String, dynamic>.from(snapshot!['detail_json'] as Map)
            : null,
        fallbackDescription: config?.worldview ?? '');
    final copiedMessages = _host.messages.reversed
        .take(12)
        .toList()
        .reversed
        .map((m) => Message(
            id: m.id,
            content: m.content,
            reasoningContent: m.reasoningContent,
            isUser: m.isUser,
            timestamp: m.timestamp,
            isHtml: m.isHtml,
            isEdited: m.isEdited,
            errorType: m.errorType))
        .toList(growable: false);
    return SceneDialogueContextSnapshot(
      id: 'snapshot-$requestId',
      userInput: content,
      gameState: Map<String, dynamic>.from(_host.gameState.toMap()),
      currentLocation: _host.gameState.currentScene,
      actor: actor,
      presentParticipants: List.unmodifiable(present),
      confirmedWorldview: details.confirmedModules(),
      recentMessages: List.unmodifiable(copiedMessages),
      summary: chatSummary,
      budget: SceneDialogueOutputBudget.resolve(_host.dialogueLevel,
          quickMode: _host.quickMode),
      runtimeRevision: runtimeRevision,
      retrievalFacts: retrievalFacts,
    );
  }

  Map<String, dynamic>? _sceneResponseMap(String content) {
    final marker = content.indexOf('---JSON---');
    if (marker < 0) return null;
    return _tryDecodeJson(AdventureResponse.cleanJsonBlock(
        content.substring(marker + 10).trim()));
  }

  /// v2.4: 重置所有聊天状态（冒险切换/删除时调用，防止残留状态导致bug）
  void resetState() {
    _cancelRequested = true;
    _generation++;
    _activeTaskHandle?.cancel();
    _typewriter.cancel();
    _status = ChatStatus.idle;
    _streamingContent = '';
    _parsedOptions = [];
    _lastValidOptions = [];
    _lastFailedContent = null;
    _lastErrorType = null;
    _lastErrorDetail = null;
    _pendingSearchResults = null;
    _isRepairingOptions = false;
    _streamNotifier.value = '';
    _reasoningContent = '';
    _reasoningStreamNotifier.value = '';
    _isThinkingNotifier.value = false;
    _lastAiWordCount = 0;
    _decayWarningNextRound = false;
    _underflowWarningNextRound = false;
    _underflowDeficit = 0;
    _underflowLastActual = 0;
    _pendingGameState = null;
    _pendingSceneEffects = const SceneDialogueEffects();
  }

  void clearError() {
    _lastErrorType = null;
    _lastErrorDetail = null;
    _notifyAll();
  }

  // ─── P0-7: 消息编辑 ───

  Future<void> editMessage(int index, String newContent) async {
    final msgs = _host.messages;
    if (index < 0 || index >= msgs.length) return;
    final msg = msgs[index];
    msgs[index] = msg.copyWith(content: newContent, isEdited: true);
    if (_host.currentAdventureId != null) {
      await _adventureRepo.updateMessageContent(
          _host.currentAdventureId!, msg.id, newContent);
    }
    _notifyAll();
  }

  void removeLastIfError() {
    final msgs = _host.messages;
    if (msgs.isNotEmpty && _lastErrorType != null) {
      final last = msgs.last;
      if (!last.isUser && last.isError) {
        msgs.removeLast();
        clearError();
        _notifyAll();
      }
    }
  }

  void dispose() {
    _disposed = true;
    _generation++;
    _activeTaskHandle?.cancel();
    _typewriter.cancel();
    _streamNotifier.dispose();
    _reasoningStreamNotifier.dispose();
    _isThinkingNotifier.dispose();
  }
}
