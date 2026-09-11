import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../models/adventure_config.dart';
import '../models/adventure_response.dart';
import '../models/adventure_runtime_state.dart';
import '../models/custom_attribute_item.dart';
import '../models/custom_status_change.dart';
import '../models/combat_state.dart' show CombatAction;
import '../models/completion_params.dart';
import '../models/game_state.dart';
import '../models/message.dart';
import '../models/llm_task.dart';
import '../models/model_capabilities.dart';
import '../models/quest.dart';
import '../models/scene_dialogue.dart';
import '../models/scene_dialogue_effects.dart';
import '../models/supporting_character.dart';
import '../models/worldview_details.dart';
import '../application/narrative/user_intent.dart';
import '../services/api_error.dart';
import '../services/auto_backup_service.dart';
import '../services/llm_service.dart';
import '../services/llm_task_policy.dart';
import '../services/web_search_service.dart';
import '../services/repositories/adventure_repository.dart';
import '../services/custom_status_merger.dart';
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

  /// Delta settlement staged by the parse phase. Applied once at commit.
  List<CustomStatusChange> _pendingCustomStatusChanges = const [];

  /// Legacy full-snapshot fallback, only used when the turn carries no delta.
  List<CustomAttributeItem> _pendingLegacyCustomStatus = const [];
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

  /// Parses one adventure response into a **staged, uncommitted** turn.
  ///
  /// The parse phase must stay side-effect free: nothing here may touch the
  /// formal [AdventureConfig] or game state. The auxiliary option repair runs
  /// after this call and can fail on the network, so a turn is only allowed to
  /// settle state once, at commit time.
  Future<bool> _applySplitResponse(String content) async {
    final response = await compute(parseResponseInIsolate, content);
    final gs = _host.gameState;
    final effects = SceneDialogueEffects.fromJson(_sceneResponseMap(content));
    _pendingSceneEffects = effects;

    if (response == null) {
      _stagePendingState(effects.applyState(gs));
      _pendingCustomStatusChanges = const [];
      _pendingLegacyCustomStatus = const [];
      _parsedOptions = _lastValidOptions.isNotEmpty
          ? List<String>.from(_lastValidOptions)
          : _buildFallbackOptions(gs, null);
      return true;
    }

    final patch = response.patch;
    final newState = effects.applyState(gs.copyWith(
      hp: patch.hp ?? gs.hp,
      maxHp: patch.maxHp ?? gs.maxHp,
      energy: patch.energy ?? gs.energy,
      maxEnergy: patch.maxEnergy ?? gs.maxEnergy,
      gold: patch.gold ?? gs.gold,
      inventory: patch.inventory ?? gs.inventory,
      currentScene: patch.scene ?? gs.currentScene,
    ));

    // Delta 优先，legacy 完整快照仅作为 fallback；二者只会在提交阶段结算一次。
    _pendingCustomStatusChanges = response.customStatusChanges;
    _pendingLegacyCustomStatus = response.customStatus;

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
      _stagePendingState(newState);
      return true;
    }

    _stagePendingState(newState);
    return false;
  }

  /// 暂存本轮 GameState；正式状态只在提交阶段落地。
  GameState _stagePendingState(GameState state) {
    if (_host.currentAdventureId != null) {
      state.adventureId = _host.currentAdventureId!;
    }
    _pendingGameState = state;
    return state;
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
    // 每轮从零暂存：解析阶段只写 pending，提交阶段才落地，避免上一轮 delta 被
    // 重复结算（重试、重新生成都会重新走一次 sendMessage）。
    _pendingGameState = null;
    _pendingSceneEffects = const SceneDialogueEffects();
    _pendingCustomStatusChanges = const [];
    _pendingLegacyCustomStatus = const [];
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
            '2. 状态结算：仅当本轮剧情确实导致状态变化时，才在结尾 JSON 的 custom_status_changes 中输出变化项（数值用 set 或 delta，文本/阶段用 set），未变化状态一律不输出；禁止无剧情依据的强行变化！坚决跨过 ${sceneSnapshot.budget.minChineseChars} 纯汉字硬指标！';
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

      final outputBudget = sceneSnapshot.budget;
      final minRequiredWords = outputBudget.minChineseChars;
      final targetWords = outputBudget.targetChineseChars;
      final hardMaxWords = outputBudget.hardMaximum;
      final useMultiStage = minRequiredWords >= 2000;
      List<Map<String, String>> lengthGuardBaseMessages;

      if (useMultiStage) {
        // Budget-driven multi-stage generation. There is no fixed act count:
        // every stage recomputes its remaining budget and the loop concludes as
        // soon as the target is reached or the hard maximum leaves no headroom.
        const maxAllowedStages = 4; // safety ceiling only
        debugPrint(
            '[ChatEngine] 启用后台多阶段流水线生成 (档位: ${_host.dialogueLevel.id}, 范围: $minRequiredWords~$hardMaxWords, 目标: $targetWords)');
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
            ? '当前监测状态参考（${trackedAttrs.map((a) => '${a.characterName != null && a.characterName!.isNotEmpty ? "[${a.characterName}] " : ""}${a.name}=${a.displayValue}').join('、')}）。仅当本轮剧情确实导致状态变化时，才在 JSON 的 custom_status_changes 中输出变化项（数值用 set 或 delta，文本/阶段用 set）；未变化的状态一律不输出。'
            : '仅当本轮剧情确实导致状态变化时，才在 JSON 的 custom_status_changes 中输出变化项（数值用 set 或 delta，文本/阶段用 set）；未变化的状态一律不输出。';

        String lastStagePayload = '';
        for (int stage = 1; stage <= maxAllowedStages; stage++) {
          if (!_isRequestCurrent(
              requestId, requestGeneration, adventureId, branchId)) {
            throw const GenerationCancelledException();
          }

          final currentChars = countChinese(stageNarratives.join('\n\n'));
          final plan = SceneDialogueOutputBudget.planStage(
            stage: stage,
            currentChars: currentChars,
            targetChars: targetWords,
            hardMaximum: hardMaxWords,
            maxStages: maxAllowedStages,
          );
          final stageCharTarget = plan.charTarget;
          final isFinal = plan.isFinal;

          final stageInstruction = _buildStageInstruction(
            stage: stage,
            stageCharTarget: stageCharTarget,
            isFinal: isFinal,
            currentChars: currentChars,
            minRequiredWords: minRequiredWords,
            targetWords: targetWords,
            hardMaxWords: hardMaxWords,
            statusHint: statusHint,
          );

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
                SceneDialogueOutputBudget.stageOutputTokens(stageCharTarget),
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
          // 统一使用 AdventureResponse 的结构解析，避免 indexOf('---JSON---')
          // 被 `--- JSON ---` / `---\nJSON---` 等变体绕过而把 JSON 泄漏进正文。
          final stageParsed = AdventureResponse.parse(stageRaw);
          final stageNarrative = stageParsed.narrative.join('\n\n').trim();
          stageNarratives.add(stageNarrative);
          if (stageParsed.payload != null) {
            lastStagePayload = jsonEncode(stageParsed.payload);
          }

          final totalWordsSoFar = countChinese(stageNarratives.join('\n\n'));
          if (isFinal) {
            debugPrint(
                '[ChatEngine] 第 $stage 幕结幕: 累计 $totalWordsSoFar 纯汉字 (范围 $minRequiredWords~$hardMaxWords, 目标 $targetWords, 硬余量 ${hardMaxWords - totalWordsSoFar})');
            break;
          }
          debugPrint(
              '[ChatEngine] 第 $stage 幕完成: 累计 $totalWordsSoFar 纯汉字 (剩余目标 ${targetWords - totalWordsSoFar}, 剩余上限 ${hardMaxWords - totalWordsSoFar})，继续下一幕');
        }

        json = '${stageNarratives.join('\n\n')}'
            '${lastStagePayload.isNotEmpty ? '\n${AdventureResponse.jsonSeparator}\n$lastStagePayload' : ''}';
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
      // 纯函数投影：主响应状态结算后的 config，尚未写入 host。
      final settledConfig = _projectPendingCustomStatus();

      var effects = _pendingSceneEffects;
      final affinityMgr = _host.gameEngine?.affinityMgr;
      final affinityConfig = settledConfig ?? _host.adventureConfig;
      if (affinityConfig != null && affinityMgr != null) {
        effects = effects.withAffinityChanges(affinityMgr.analyzeKeywords(
            content, affinityConfig.supportingCharacters));
      }
      // 本轮 pending 一定由解析阶段写入，不再回退到 host，避免沿用上一轮的残值。
      final state = effects.applyState(_pendingGameState ?? _host.gameState);
      // 消息里的 custom_status 快照必须反映本轮结算结果（UI 直接读它渲染监测状态）。
      aiMsg = aiMsg.copyWith(
        content: needsOptionRepair
            ? _injectOptionsIntoAiContent(json, _parsedOptions,
                config: settledConfig)
            : _normalizeCustomStatusInAiContent(json, config: settledConfig),
      );
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
      // 原子提交：主响应的状态结算只在此处落地一次。此后的取消路径只会抛
      // GenerationCancelledException，pending 已被清空，不会有第二次结算。
      _commitPendingCustomStatus();
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
      final budgetMin = sceneSnapshot.budget.minChineseChars;
      final budgetTarget = sceneSnapshot.budget.targetChineseChars;
      final budgetHardMax = sceneSnapshot.budget.hardMaximum;
      final monitorParsed = AdventureResponse.parse(json);
      final payloadJson = monitorParsed.payload != null
          ? jsonEncode(monitorParsed.payload)
          : '';
      final jsonLen = payloadJson.length;
      final totalLen = json.length;
      final jsonRatio = totalLen > 0 ? (jsonLen / totalLen * 100) : 0.0;
      final lengthRatio = budgetMin > 0 ? (currentWordCount / budgetMin) : 0.0;
      final estimateTokens = (totalLen / 1.5).round();
      final roundNum = _host.messages.where((m) => m.isUser).length;
      final isOverflow = lengthGuardResult.overflowDetected ||
          currentWordCount > budgetHardMax;
      final isPassed = lengthGuardResult.passed(budgetMin) && !isOverflow;
      debugPrint('');
      debugPrint('╔══════════════════════════════════════════╗');
      debugPrint('║  📊 AI 响应监控  —  第 $roundNum 轮');
      debugPrint('╠══════════════════════════════════════════╣');
      debugPrint('║  字数范围:  $budgetMin / $budgetTarget / $budgetHardMax');
      debugPrint('║  实际:      $currentWordCount');
      debugPrint('║  倍率:      ${lengthRatio.toStringAsFixed(2)}x');
      debugPrint('║  JSON:      $jsonLen');
      debugPrint('║  JSON占比:  ${jsonRatio.toStringAsFixed(1)}%');
      debugPrint('║  估算tokens: $estimateTokens');
      debugPrint('║  达标:      ${isPassed ? '✅ 是' : '❌ 否'}');
      if (isOverflow) {
        debugPrint('║  ⚠️  OVERFLOW: 超过硬上限 $budgetHardMax 字');
      }
      debugPrint('╚══════════════════════════════════════════╝');
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

  /// 辅助任务：只为已经生成成功的正文补齐行动选项。
  ///
  /// 约束（不可放宽）：
  /// * 唯一产物是 `options`。即使修复模型返回 `custom_status_changes`、
  ///   `custom_status`、`affinity_change`、`hp/gold/inventory` 等字段也一律忽略，
  ///   主响应才是本轮状态结算的唯一权威。
  /// * 任何失败（HandshakeException / SocketException / 超时 / 5xx / 非法输出）
  ///   都在这里降级，绝不向外抛。正文已经有效时，辅助请求无权毁掉整轮。
  Future<void> _repairMissingOptions(
    String aiContent,
    String userContent, {
    required String requestId,
    required int generation,
    required int? adventureId,
    required int branchId,
  }) async {
    List<String>? repaired;
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
      repaired = _parseRepairedOptions(result);
    } catch (error) {
      // 已生成的正文仍然有效：修复失败只降级为“用现有选项继续本轮”，
      // 不产生整轮网络错误，也不影响主响应的状态提交。
      debugPrint('[ChatEngine] option repair degraded: network error '
          '(${error.runtimeType})');
    }

    _parsedOptions = _resolveTurnOptions(repaired);
    if (_parsedOptions.length >= 3) {
      _lastValidOptions = List<String>.from(_parsedOptions);
    }
  }

  /// 降级阶梯：修复结果 → 本轮已解析选项 → 上一轮有效选项 → 场景兜底，
  /// 保证最终至少有 3 个可点击选项。
  List<String> _resolveTurnOptions(List<String>? repaired) {
    if (repaired != null && repaired.length >= 3) {
      return List<String>.from(repaired);
    }
    final merged = <String>[];
    final seen = <String>{};
    void add(String option) {
      final text = option.trim();
      if (text.isEmpty) return;
      if (seen.add(text.replaceAll(RegExp(r'\s+'), ''))) merged.add(text);
    }

    if (repaired != null) {
      for (final option in repaired) {
        add(option);
      }
    }
    for (final option in _parsedOptions) {
      add(option);
    }
    for (final option in _lastValidOptions) {
      add(option);
    }
    if (merged.length < 3) {
      for (final option in _buildFallbackOptions(_host.gameState, null)) {
        add(option);
      }
    }
    return merged.length > 4 ? merged.sublist(0, 4) : merged;
  }

  /// 纯函数：把解析阶段暂存的 Delta（优先）/ legacy 完整快照投影成新的
  /// [AdventureConfig]，不写入 host。Delta 与 legacy 同时出现时只采用 Delta，
  /// 保证同一轮的状态只被结算一次。
  AdventureConfig? _projectPendingCustomStatus() {
    final changes = _pendingCustomStatusChanges;
    final legacy = _pendingLegacyCustomStatus;
    final config = _host.adventureConfig;
    if (config == null) return null;

    if (changes.isNotEmpty) {
      final result = CustomStatusMerger.applyChanges(
        protagonistName: config.name.trim(),
        protagonistId: config.protagonistCharacter?.characterId,
        protagonistAttributes: config.customAttributes,
        supportingCharacters: config.supportingCharacters,
        changes: changes,
      );
      if (result.diagnostics.isNotEmpty) {
        debugPrint('[ChatEngine] custom status diagnostics: '
            '${result.diagnostics.join(', ')}');
      }
      return config.copyWith(
        customAttributes: result.protagonistAttributes,
        supportingCharacters: result.supportingCharacters,
      );
    }

    if (legacy.isNotEmpty) {
      final result = CustomStatusMerger.applyLegacySnapshot(
        protagonistName: config.name.trim(),
        protagonistAttributes: config.customAttributes,
        supportingCharacters: config.supportingCharacters,
        snapshot: legacy,
      );
      return config.copyWith(
        customAttributes: result.protagonistAttributes,
        supportingCharacters: result.supportingCharacters,
      );
    }
    return null;
  }

  /// 把暂存的自定义状态一次性写入正式 [AdventureConfig]。
  ///
  /// 写入前先清空 pending，因此重复调用是 no-op —— 选项修复失败、重试、重新
  /// 生成都不会让同一轮 Delta 结算第二次。
  void _commitPendingCustomStatus() {
    final changes = _pendingCustomStatusChanges;
    final legacy = _pendingLegacyCustomStatus;
    if (changes.isEmpty && legacy.isEmpty) return;
    final settled = _projectPendingCustomStatus();
    // 先清空再落地：任何后续路径都不可能重复结算本轮状态。
    _pendingCustomStatusChanges = const [];
    _pendingLegacyCustomStatus = const [];

    if (settled == null) return;
    _logCustomStatusUpdate(
        settled.customAttributes, settled.supportingCharacters);
    _host.updateAdventureConfig(settled);
  }

  void _logCustomStatusUpdate(List<CustomAttributeItem> protagonistAttrs,
      List<SupportingCharacter> supportingChars) {
    debugPrint(
        '[ChatEngine] custom status updated. 主角状态: ${protagonistAttrs.map((a) => '${a.name}=${a.displayValue}').join(', ')}; 配角: ${supportingChars.map((s) => '${s.name}(好感:${s.affinity})').join(', ')}');
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
    final hardMaximum = snapshot.budget.hardMaximum;
    if (initial.passed(minimum)) {
      debugPrint('[LengthGuard] initial=${initial.initialChineseChars} '
          'required=$minimum hardMax=$hardMaximum passed=true');
      return _withOverflowGuard(initial, hardMaximum: hardMaximum);
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
      return _withOverflowGuard(merged, hardMaximum: hardMaximum);
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

  /// Detects when the final narrative exceeded the hard maximum and safely
  /// converges it at a paragraph/sentence boundary, keeping the settlement
  /// payload intact. Generation budgeting is the primary defence; this is the
  /// last-resort safety net.
  NarrativeLengthGuardResult _withOverflowGuard(
    NarrativeLengthGuardResult result, {
    required int hardMaximum,
  }) {
    final parsed = AdventureResponse.parse(result.content);
    final narrative = parsed.narrative.join('\n\n');
    if (countChinese(narrative) <= hardMaximum) return result;

    final converged = _lengthGuard.convergeToMaximum(narrative, hardMaximum);
    final payload = parsed.payload;
    final String newContent;
    if (payload != null) {
      final payloadJson = jsonEncode(payload);
      newContent = converged.isEmpty
          ? '${AdventureResponse.jsonSeparator}\n$payloadJson'
          : '$converged\n${AdventureResponse.jsonSeparator}\n$payloadJson';
    } else {
      newContent = converged;
    }
    debugPrint('[LengthGuard] OVERFLOW: ${countChinese(narrative)} -> '
        '${countChinese(converged)} chars (hardMax=$hardMaximum)');
    return NarrativeLengthGuardResult(
      content: newContent,
      initialChineseChars: result.initialChineseChars,
      supplementChineseChars: result.supplementChineseChars,
      finalChineseChars: countChinese(converged),
      supplementAttempted: result.supplementAttempted,
      supplementSucceeded: result.supplementSucceeded,
      overflowDetected: true,
    );
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

  String _buildStageInstruction({
    required int stage,
    required int stageCharTarget,
    required bool isFinal,
    required int currentChars,
    required int minRequiredWords,
    required int targetWords,
    required int hardMaxWords,
    required String statusHint,
  }) {
    final rangeNote =
        '本轮范围 $minRequiredWords~$hardMaxWords 纯汉字，目标 $targetWords 字';
    if (isFinal) {
      final budgetNote = stageCharTarget > 0
          ? '本幕叙事正文控制在约 $stageCharTarget 纯汉字以内'
          : '已接近上限，不再扩写正文';
      return '【分幕流水线·第 $stage 幕（终幕·结算）指令】：\n'
          '前 ${stage - 1} 幕已推进 $currentChars 纯汉字（$rangeNote）。\n'
          '$budgetNote，紧接上文收束剧情，不要超过上限。\n'
          '叙事彻底完结后，立即输出一行分隔符 `---JSON---`，然后紧跟一行合法 JSON。\n'
          '⚠️ 【状态结算强制要求】：JSON 必须包含 options 数组；仅当本轮剧情确实导致状态变化时，才输出 custom_status_changes（未变化可省略）。$statusHint';
    }
    if (stage == 1) {
      return '【分幕流水线·第 1 幕（入境与展开）指令】：\n'
          '本轮为长篇叙事的首发阶段。请展开饱满叙事：环境渲染、角色互动、冲突引入与第一次波折（$rangeNote）。\n'
          '本幕叙事正文控制在约 $stageCharTarget 纯汉字以内，不要超出。\n'
          '⚠️ 严禁提前草率收束！绝对严禁输出 ---JSON--- 及任何选项或状态数据！写满后直接以正文停笔。';
    }
    return '【分幕流水线·第 $stage 幕（续写）指令】：\n'
        '前 ${stage - 1} 幕已推进 $currentChars 纯汉字（$rangeNote）。\n'
        '请紧接上文继续推进剧情，本幕叙事正文控制在约 $stageCharTarget 纯汉字以内，不要超出。\n'
        '⚠️ 严禁输出 ---JSON--- 及任何选项或状态数据！写满后直接以正文停笔。';
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

    // 修复请求只用于补齐选项：本轮状态结算的权威是主响应，任何随修复结果
    // 返回的状态字段都会被丢弃，因此这里不再向模型索取它们。
    return '''
请为当前文字冒险回复补充生成一段 JSON 数据（包含 3 到 4 个行动选项）。

要求：
- 每个选项为 15 到 50 个中文字，不得少于 15 字或超过 50 字。
- 选项必须贴合当前剧情、当前危机、当前人物关系。
- 不要使用「继续探索」「观察环境」「查看状态」「休息片刻」这类泛化模板，除非当前剧情确实没有更具体分支。
- 只输出行动选项，不要输出剧情、状态、数值、好感度或任何其它字段（其它字段一律忽略）。
- 不要解释，不要写剧情，不要输出 Markdown。
- 只输出合法 JSON：{"options":["选项1","选项2","选项3","选项4"]}
$avoidSection
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

  /// [config] 允许注入“本轮已结算但尚未写入 host”的状态快照。
  String _injectOptionsIntoAiContent(String aiContent, List<String> options,
      {AdventureConfig? config}) {
    final scene = _host.gameState.currentScene.trim();
    final customAttrs = config?.allTrackedCustomAttributes ??
        _host.adventureConfig?.allTrackedCustomAttributes ??
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

    final sepMatch = AdventureResponse.separatorPattern.firstMatch(aiContent);
    if (sepMatch == null) {
      return '${aiContent.trim()}\n${AdventureResponse.jsonSeparator}\n${jsonEncode(fallbackJson)}';
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
        // Delta 已并入本地完整快照，避免残留原始 Delta 字段。
        merged.remove('custom_status_changes');
        return '$narrative\n---JSON---\n${jsonEncode(merged)}';
      }
    } catch (_) {
      // fall back to a synthetic JSON block below.
    }

    return '$narrative\n---JSON---\n${jsonEncode(fallbackJson)}';
  }

  /// 保证 AI 正文中的 JSON 段包含所有追踪角色的最新自定义检测状态快照
  String _normalizeCustomStatusInAiContent(String content,
      {AdventureConfig? config}) {
    final customAttrs = config?.allTrackedCustomAttributes ??
        _host.adventureConfig?.allTrackedCustomAttributes ??
        _host.adventureConfig?.customAttributes ??
        const [];
    if (customAttrs.isEmpty) return content;

    final sepMatch = AdventureResponse.separatorPattern.firstMatch(content);
    if (sepMatch == null) return content;

    final narrative = content.substring(0, sepMatch.start).trimRight();
    final jsonText = content.substring(sepMatch.end).trim();
    try {
      final cleaned = AdventureResponse.cleanJsonBlock(jsonText);
      final decoded = jsonDecode(cleaned);
      if (decoded is Map<String, dynamic>) {
        final merged = Map<String, dynamic>.from(decoded);
        merged['custom_status'] = customAttrs.map((a) => a.toJson()).toList();
        // Delta 已并入本地完整快照，避免残留原始 Delta 字段。
        merged.remove('custom_status_changes');
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

  Map<String, dynamic>? _sceneResponseMap(String content) =>
      AdventureResponse.parse(content).payload;

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
    _pendingCustomStatusChanges = const [];
    _pendingLegacyCustomStatus = const [];
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
