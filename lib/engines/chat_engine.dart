import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/adventure_response.dart';
import '../models/custom_attribute_item.dart';
import '../models/combat_state.dart' show CombatAction;
import '../models/completion_params.dart';
import '../models/game_state.dart';
import '../models/message.dart';
import '../models/quest.dart';
import '../models/scene_dialogue.dart';
import '../models/scene_dialogue_effects.dart';
import '../models/worldview_details.dart';
import '../services/api_error.dart';
import '../services/auto_backup_service.dart';
import '../services/llm_service.dart';
import '../services/web_search_service.dart';
import '../services/repositories/adventure_repository.dart';
import '../services/scene_consistency_validator.dart';
import 'chat_engine_host.dart';
import 'chat_engine_internals/prompt_builder.dart';
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
  List<SceneSettingCandidate> _lastSceneCandidates = const [];

  // v2.4: 抗衰减 — 追踪上轮字数 + 衰减检测
  int _lastAiWordCount = 0;
  bool _decayWarningNextRound = false;

  static const CompletionParams _optionRepairParams = CompletionParams(
    temperature: 0.45,
    topP: 0.8,
    frequencyPenalty: 0.0,
    presencePenalty: 0.0,
    maxTokens: 512,
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
    _activeRequestId = requestId;
    _activeTaskHandle = GenerationTaskHandle(
        taskId: requestId, generationEpoch: requestGeneration);
    _scenePhase = SceneDialoguePhase.created;
    final sceneSnapshot = _freezeSceneContext(content, requestId);
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

    // ─── 1. 添加用户消息并立即通知 UI（DB 持久化放后面，避免 Android sqflite 延迟阻塞 UI）───
    final userMsg = Message(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      content: content,
      isUser: true,
    );
    _host.messages.add(userMsg);
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
      var augmentedContent = content;
      if (promptTransformer != null) {
        augmentedContent = await promptTransformer(content).catchError((_) {
          return content;
        });
        if (augmentedContent.trim().isEmpty) {
          augmentedContent = content;
        }
      }
      // 每轮唯一的字数数值锚点（v2.4）：系统提示词只做档位定义不重复数值，
      // 具体字数要求只在本轮用户消息携带一次，避免同一请求内指令叠加污染。
      augmentedContent =
          '$augmentedContent\n${sceneSnapshot.budget.promptRequirement}';
      if (_decayWarningNextRound) {
        augmentedContent =
            '$augmentedContent\n🔴 系统检测：上轮字数显著下降。本轮请恢复当前档位要求的叙事细节。';
        _decayWarningNextRound = false;
      }

      final apiMessages = buildMessages(
          '$augmentedContent\n${_promptBuilder.buildFrozenSceneContext(sceneSnapshot)}');
      final execution = await _executeAdventureContext(
        messages: apiMessages,
        taskType: ContextTaskType.adventureResponse,
        intent: augmentedContent,
        maximumOutputTokens: sceneSnapshot.budget
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
      if (!_isRequestCurrent(
          requestId, requestGeneration, adventureId, branchId)) {
        throw const GenerationCancelledException();
      }
      final json = execution.content;
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
          : json;

      var aiMsg = Message(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        content: aiContent,
        reasoningContent: execution.reasoningContent,
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

      // v2.4: 抗衰减 — 追踪本轮字数，检测衰减趋势
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
      SceneDialogueCommitResult result = SceneDialogueCommitResult(
        applied: true,
        gameState: state,
        effects: effects,
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
          contextSnapshotId: sceneSnapshot.id,
          diagnostics: {
            'budget_tokens': sceneSnapshot.budget.recommendedTokens,
            'retrieval_degraded': sceneSnapshot.diagnostics.isNotEmpty,
            'continuity': continuity.isConsistent ? 'passed' : 'warning',
            if (!continuity.isConsistent) 'warnings': continuity.warnings,
          },
          candidates: candidates,
          effects: effects,
        ));
      }
      if (!_isRequestCurrent(
          requestId, requestGeneration, adventureId, branchId)) {
        throw const GenerationCancelledException();
      }
      await _host.applySceneDialogueCommitResult(result);
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
      debugPrint('║  叙事部分:  ${narrativeLen.toString().padLeft(6)} 字      ');
      debugPrint('║  JSON部分:  ${jsonLen.toString().padLeft(6)} 字      ');
      debugPrint(
          '║  估算tokens: ${estimateTokens.toString().padLeft(5)}         ');
      debugPrint(
          '║  字数目标:  ${_host.dialogueLevel.wordRangeLabel.padLeft(6)}         ');
      debugPrint(
          '║  达标:      ${narrativeLen >= _host.dialogueLevel.minWords ? '✅ 是' : '❌ 否'}  ');
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
        if (decoded is Map<String, dynamic> && decoded['custom_status'] != null) {
          _syncCustomStatusUpdates(decoded['custom_status']);
        }
      } catch (_) {}
    } catch (e) {
      debugPrint('[ChatEngine] 修复/补充 JSON 失败: $e');
    }
  }

  void _syncCustomStatusUpdates(dynamic rawStatus) {
    if (rawStatus == null || _host.adventureConfig == null) return;
    final curAttrs = _host.adventureConfig!.customAttributes;
    if (curAttrs.isEmpty) return;

    if (rawStatus is List<CustomAttributeItem>) {
      final updated = curAttrs.map((cur) {
        final matched = rawStatus
            .where((s) => s.name.trim() == cur.name.trim())
            .firstOrNull;
        if (matched != null) {
          return cur.copyWith(
            currentValue: matched.currentValue ?? cur.currentValue,
            maxValue: matched.maxValue ?? cur.maxValue,
            value: matched.value.isNotEmpty ? matched.value : cur.value,
          );
        }
        return cur;
      }).toList();
      _host.updateAdventureConfig(
        _host.adventureConfig!.copyWith(customAttributes: updated),
      );
      return;
    }

    if (rawStatus is Map) {
      final updated = curAttrs.map((attr) {
        for (final entry in rawStatus.entries) {
          if (entry.key.toString().trim() == attr.name.trim()) {
            final val = entry.value;
            if (val is num) {
              return attr.copyWith(currentValue: val.toInt());
            } else if (val is Map) {
              final m = Map<String, dynamic>.from(val);
              return attr.copyWith(
                currentValue: m['current_value'] is num
                    ? (m['current_value'] as num).toInt()
                    : (m['current'] is num ? (m['current'] as num).toInt() : attr.currentValue),
                maxValue: m['max_value'] is num
                    ? (m['max_value'] as num).toInt()
                    : (m['max'] is num ? (m['max'] as num).toInt() : attr.maxValue),
                value: m['value']?.toString() ?? attr.value,
              );
            } else if (val is String && val.trim().isNotEmpty) {
              return attr.copyWith(value: val.trim());
            }
          }
        }
        return attr;
      }).toList();
      _host.updateAdventureConfig(
        _host.adventureConfig!.copyWith(customAttributes: updated),
      );
    } else if (rawStatus is List) {
      final updated = curAttrs.map((attr) {
        for (final item in rawStatus) {
          if (item is Map) {
            final name = item['name']?.toString().trim();
            if (name == attr.name.trim()) {
              return attr.copyWith(
                currentValue: item['current_value'] is num
                    ? (item['current_value'] as num).toInt()
                    : (item['current'] is num ? (item['current'] as num).toInt() : attr.currentValue),
                maxValue: item['max_value'] is num
                    ? (item['max_value'] as num).toInt()
                    : (item['max'] is num ? (item['max'] as num).toInt() : attr.maxValue),
                value: item['value']?.toString() ?? attr.value,
              );
            }
          }
        }
        return attr;
      }).toList();
      _host.updateAdventureConfig(
        _host.adventureConfig!.copyWith(customAttributes: updated),
      );
    }
  }

  Future<ContextExecutionResult> _executeAdventureContext({
    required List<Map<String, String>> messages,
    required int maximumOutputTokens,
    required String requestId,
    GenerationTaskHandle? taskHandle,
    void Function(String chunk)? onChunk,
    void Function(String reasoningChunk)? onReasoningChunk,
    dynamic taskType,
    String? intent,
  }) async {
    final result = await _host.llmService.sendMessageStreamDetailed(
      messages,
      (chunk) {
        if (onChunk != null) onChunk(chunk);
      },
      () {},
      onReasoningChunk: onReasoningChunk,
      params: _host.completionParams.copyWith(
        maxTokens: maximumOutputTokens,
      ),
      taskHandle: taskHandle,
    );
    if (!result.responseCompleted || !result.finishReason.allowsParsing) {
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
    final customAttrs = _host.adventureConfig?.customAttributes ?? const [];
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
    final customSection = customAttrs.isEmpty
        ? ''
        : '\n当前自定义检测状态：\n${customAttrs.map((a) => '- ${a.toPromptText()}').join('\n')}\n'
            '若剧情导致上述状态变化，请在 JSON 中附加 "custom_status": {"状态名": 最新数值或阶段}；未变化则无需附加。\n';
    final jsonExample = customAttrs.isEmpty
        ? '{"options":["选项1","选项2","选项3","选项4"]}'
        : '{"options":["选项1","选项2","选项3","选项4"], "custom_status":{"${customAttrs.first.name}":最新数值或阶段}}';
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
    final customAttrs = _host.adventureConfig?.customAttributes ?? const [];
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
          if (merged['custom_status'] == null &&
              merged['custom_attributes'] == null) {
            merged['custom_status'] =
                customAttrs.map((a) => a.toJson()).toList();
          }
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

  SceneDialogueContextSnapshot _freezeSceneContext(
      String content, String requestId) {
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
        snapshot?['details'] is Map
            ? Map<String, dynamic>.from(snapshot!['details'] as Map)
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
