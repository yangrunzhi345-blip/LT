import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../models/adventure_config.dart';
import '../models/adventure_response.dart';
import '../models/adventure_runtime_state.dart';
import '../models/custom_attribute_item.dart';
import '../models/custom_status_change.dart';
import '../models/custom_status_evaluation.dart';
import '../models/combat_state.dart' show CombatAction;
import '../models/completion_params.dart';
import '../models/game_state.dart';
import '../models/message.dart';
import '../models/llm_task.dart';
import '../models/model_capabilities.dart';
import '../models/scene_dialogue.dart';
import '../models/scene_dialogue_effects.dart';
import '../models/scene_state.dart';
import '../models/supporting_character.dart';
import '../models/turn_settlement.dart';
import '../models/worldview_details.dart';
import '../application/narrative/user_intent.dart';
import '../services/api_error.dart';
import '../services/auto_backup_service.dart';
import '../services/llm_service.dart';
import '../services/llm_task_policy.dart';
import '../services/web_search_service.dart';
import '../domain/events/app_event.dart';
import '../domain/events/app_event_codec.dart';
import '../services/repositories/adventure_repository.dart';
import '../services/custom_status_merger.dart';
import '../services/scene_consistency_validator.dart';
import 'chat_engine_host.dart';
import 'chat_engine_internals/prompt_builder.dart';
import 'chat_engine_internals/response_length_guard.dart';
import 'chat_engine_internals/stream_handler.dart';
import 'chat_engine_internals/summary_service.dart';
import 'chat_engine_internals/turn_settlement_prompt.dart';
import '../managers/combat_manager.dart';
import '../utils/chinese_character_counter.dart';

class ContextExecutionResult {
  final String content;
  final String? reasoningContent;
  const ContextExecutionResult({required this.content, this.reasoningContent});
}

enum ContextTaskType {
  adventureResponse,
  adventureLengthSupplement,
  adventureTurnSettlement,
  adventureOptionRepair,
  adventureSummary,
}

/// P1-03: 聊天状态枚举 — 替代 _isLoading/_isStreaming 双 bool，消除并发守卫空窗期
///
/// `settling` is a **post-narrative** state: the prose the player reads is
/// already final and frozen, and only the settlement request is still running.
/// Keeping it a distinct enum value (instead of a third bool) preserves the
/// single state machine: `isStreaming` keeps meaning "narrative is still being
/// written", and `sendMessage` stays blocked because the status is not `idle`.
enum ChatStatus { idle, loading, streaming, settling }

/// UI-only presentation phase of the assistant reply that has already been
/// generated but is **not durably committed yet**.
///
/// This state never enters `_host.messages` and never reaches the repository —
/// it exists so the narrative the player is reading survives the
/// narrative → settlement boundary instead of being swapped for a hint and
/// re-appearing after the commit.
enum PendingAssistantPhase {
  /// Nothing pending: the last turn is fully committed (or failed).
  none,

  /// The final narrative is frozen and shown; the settlement request is
  /// running and its hint is rendered as a footer below the prose.
  settling,

  /// The settlement result (status + options) has been appended after the
  /// frozen narrative; only the durable commit is still in flight.
  settled,
}

enum SceneDialoguePhase {
  created,
  streaming,
  parsing,
  settling,
  repairing,
  committing,
  completed,
  cancelled,
  failed,
  stale,
}

/// Outcome of one turn-settlement attempt.
///
/// [status] is a stable diagnostic token, so the persisted
/// `scene_dialogue_turns.diagnostics_json` can show why a turn fell back.
class _SettlementOutcome {
  final TurnSettlement? settlement;

  /// `applied` | `skipped_no_adventure` | `stale` | `stale_revision` |
  /// `failed_json` | `failed_request`.
  final String status;
  final int attempts;
  final List<String> diagnostics;

  const _SettlementOutcome({
    this.settlement,
    required this.status,
    this.attempts = 0,
    this.diagnostics = const [],
  });

  bool get applied => settlement != null;
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
  final TurnSettlementPromptBuilder _settlementPromptBuilder =
      TurnSettlementPromptBuilder();

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
  ///
  /// 评估协议（`custom_status_evaluations`）中 `changed=true` 的项会在暂存时
  /// 转成 Delta 排在最前面，旧协议项随后；合并器按解析后的目标去重，因此同一个
  /// 状态在一轮里只会结算一次。
  List<CustomStatusChange> _pendingCustomStatusChanges = const [];

  /// 评估协议原文。`null` 表示本轮没有出现该字段（走旧协议），与「出现但为空」
  /// 语义不同，后者用于识别「模型漏评估了哪些状态」。
  List<CustomStatusEvaluation>? _pendingCustomStatusEvaluations;

  /// 解析阶段（`AdventureResponse.fromJson`）产生的诊断。
  List<String> _pendingStatusParseDiagnostics = const [];

  /// Legacy full-snapshot fallback. Staged by the narrative parse and applied
  /// **only** when the turn settlement request failed outright; a successful
  /// settlement clears it so one delta can never be applied twice.
  List<CustomAttributeItem> _pendingLegacyCustomStatus = const [];

  /// Runtime changes produced by the settlement request. The narrative payload
  /// is only consulted as a labelled legacy fallback.
  List<RuntimeStateChangeProposal> _pendingRuntimeChanges = const [];

  /// Narrative-payload compatibility data, used exclusively by the legacy
  /// fallback path (`_applySettlementFailure`).
  List<RuntimeStateChangeProposal> _pendingNarrativeRuntimeChanges = const [];
  List<String> _pendingNarrativeStatusDiagnostics = const [];
  List<CustomStatusEvaluation>? _pendingNarrativeEvaluations;
  List<CustomStatusChange> _pendingNarrativeStatusChanges = const [];

  /// Diagnostics describing the settlement attempt itself.
  List<String> _pendingSettlementDiagnostics = const [];

  /// Options found in the narrative payload (fallback candidate only).
  List<String> _narrativeOptions = const [];

  /// Settlement streaming accumulator.
  ///
  /// This is the **only** place settlement chunks go. It must never touch
  /// [_streamingContent], [_streamNotifier] or [_typewriter]: the narrative
  /// bubble is already final when settlement starts, and appending raw JSON to
  /// it would leak `{"options":...}` into the player-visible prose.
  String _settlementStreamingContent = '';

  /// UI-only presentation of the not-yet-committed assistant turn.
  ///
  /// [PendingAssistantPhase.settling] holds the frozen narrative only;
  /// [PendingAssistantPhase.settled] holds the exact string the committed
  /// message will carry (narrative + structured payload), produced by the same
  /// `_injectOptionsIntoAiContent` / `_normalizeCustomStatusInAiContent`
  /// authority — so the commit swaps pixels for identical pixels.
  PendingAssistantPhase _pendingAssistantPhase = PendingAssistantPhase.none;
  String _pendingAssistantContent = '';

  /// Per-status settlement diagnostics, so a debug log can tell an
  /// "AI judged no change" turn apart from "the system ate the change".
  List<String> _pendingSettlementStatusDiagnostics = const [];

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

  /// Settlement is an auxiliary task with a hard latency budget. It keeps its
  /// own small output cap instead of inheriting the narrative's token budget;
  /// the authoritative value lives in `LlmTaskPolicyTable` and this constant
  /// only exists so the request can be clamped to the active model.
  static const int _settlementMaxTokens = 1024;

  /// One settlement request, plus at most one fast repair attempt. Settlement
  /// must never degrade into an unbounded retry loop — the narrative is already
  /// on screen and is never regenerated for a settlement failure.
  static const int _maxSettlementAttempts = 2;

  // ─── 公开 Getter ───

  List<Message> get messages => _host.messages;
  ChatStatus get status => _status;
  bool get isLoading => _status == ChatStatus.loading;
  String get streamingContent => _streamingContent;
  bool get isStreaming => _status == ChatStatus.streaming;

  /// True only while the post-narrative settlement request is running. The
  /// narrative itself is already complete and frozen at this point.
  bool get isSettling => _status == ChatStatus.settling;

  /// Presentation state of the generated-but-not-committed assistant turn.
  /// See [PendingAssistantPhase] for the lifecycle contract.
  PendingAssistantPhase get pendingAssistantPhase => _pendingAssistantPhase;

  /// Frozen narrative (settling) or narrative + structured tail (settled).
  /// Empty unless [pendingAssistantPhase] is not [PendingAssistantPhase.none].
  String get pendingAssistantContent => _pendingAssistantContent;

  bool get hasPendingAssistant =>
      _pendingAssistantPhase != PendingAssistantPhase.none;
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

  /// **Narrative parse** — stages compatibility data only.
  ///
  /// The narrative payload is no longer the settlement authority. It still has
  /// to be parsed because it carries data the settlement request must not
  /// invent (scene effects such as combat starts or item grants, the
  /// protagonist's `game_state` patch, scene candidates) and because it is the
  /// labelled legacy fallback when settlement fails.
  ///
  /// `options`, `custom_status_evaluations`, `custom_status_changes` and
  /// `runtime_state_changes` from the narrative are deliberately **not**
  /// staged as authoritative: settlement owns them, and staging both would
  /// double-apply the same delta (50 → 60 instead of 50 → 55).
  Future<void> _applyNarrativeResponse(String content) async {
    final response = await compute(parseResponseInIsolate, content);
    final gs = _host.gameState;
    final effects = SceneDialogueEffects.fromJson(_sceneResponseMap(content));
    _pendingSceneEffects = effects;

    _pendingCustomStatusChanges = const [];
    _pendingCustomStatusEvaluations = null;
    _pendingStatusParseDiagnostics = const [];
    _pendingSettlementStatusDiagnostics = const [];
    _pendingRuntimeChanges = const [];
    _pendingSettlementDiagnostics = const [];
    _pendingNarrativeRuntimeChanges = const [];
    _pendingNarrativeStatusDiagnostics = const [];
    _pendingNarrativeEvaluations = null;
    _pendingNarrativeStatusChanges = const [];
    _narrativeOptions = const [];

    if (response == null) {
      _stagePendingState(effects.applyState(gs));
      _pendingLegacyCustomStatus = const [];
      _parsedOptions = _lastValidOptions.isNotEmpty
          ? List<String>.from(_lastValidOptions)
          : _buildFallbackOptions(gs, null);
      return;
    }

    final patch = response.patch;
    _stagePendingState(effects.applyState(gs.copyWith(
      hp: patch.hp ?? gs.hp,
      maxHp: patch.maxHp ?? gs.maxHp,
      energy: patch.energy ?? gs.energy,
      maxEnergy: patch.maxEnergy ?? gs.maxEnergy,
      gold: patch.gold ?? gs.gold,
      inventory: patch.inventory ?? gs.inventory,
      currentScene: patch.scene ?? gs.currentScene,
    )));

    final payload = _sceneResponseMap(content);
    final narrativeRuntimeDiagnostics = <String>[];
    _pendingNarrativeRuntimeChanges = RuntimeStateChangeProposal.parse(
      payload?['runtime_state_changes'],
      diagnostics: narrativeRuntimeDiagnostics,
    );
    _pendingLegacyCustomStatus = response.customStatus;
    _pendingNarrativeEvaluations = response.customStatusEvaluations;
    _pendingNarrativeStatusChanges = response.customStatusChanges;
    _pendingNarrativeStatusDiagnostics = List<String>.unmodifiable([
      ...response.parseDiagnostics,
      ...narrativeRuntimeDiagnostics,
    ]);
    _narrativeOptions = List<String>.from(response.options);

    if (response.options.isNotEmpty) {
      _parsedOptions = List<String>.from(response.options);
    } else {
      final scene =
          response.scene.isNotEmpty ? response.scene : gs.currentScene;
      _parsedOptions = _lastValidOptions.isNotEmpty
          ? List<String>.from(_lastValidOptions)
          : _buildFallbackOptions(gs, scene);
    }
  }

  /// **Settlement authority** — stages the turn's options and state.
  ///
  /// Runs after the narrative is completely finished (all length supplements
  /// merged), so it sees the final prose. The legacy narrative snapshot is
  /// cleared here so it can never be applied on top of a settlement delta.
  void _applySettlement(TurnSettlement settlement) {
    final evaluations = settlement.customStatusEvaluations;
    _pendingCustomStatusEvaluations = evaluations;
    _pendingStatusParseDiagnostics =
        List<String>.unmodifiable(settlement.parseDiagnostics);
    _pendingCustomStatusChanges = [
      if (evaluations != null)
        for (final evaluation in evaluations)
          if (evaluation.changed) evaluation.toChange(),
      ...settlement.customStatusChanges,
    ];
    _pendingLegacyCustomStatus = const [];
    _pendingRuntimeChanges = settlement.runtimeChanges;
    // 逐状态诊断：模型到底评估了什么、判定变没变。与后续 applied/rejected
    // 诊断对照，即可定位「AI 判定没变」还是「系统把变化吃掉了」。
    _pendingSettlementStatusDiagnostics = List.unmodifiable([
      if (evaluations != null)
        for (final evaluation in evaluations)
          ..._settlementEvaluationDiagnostics(evaluation),
    ]);
    debugPrint('[ChatEngine] settlement status diagnostics: '
        '${_pendingSettlementStatusDiagnostics.join(', ')}');
  }

  List<String> _settlementEvaluationDiagnostics(
      CustomStatusEvaluation evaluation) {
    final entity = evaluation.characterId ?? evaluation.characterName ?? '?';
    final attribute = evaluation.attributeId ?? evaluation.attributeName ?? '?';
    if (!evaluation.changed) {
      return ['settlement:evaluated:$entity:$attribute:false'];
    }
    return [
      'settlement:evaluated:$entity:$attribute:true',
      'settlement:changed:$entity:$attribute:'
          '${evaluation.operation?.name ?? 'set'}:${evaluation.value}',
    ];
  }

  /// Fallback for a turn whose settlement never produced a usable result.
  ///
  /// Fail-closed first: nothing is invented. The narrative payload is then
  /// re-used as an **explicitly labelled** legacy fallback, because it is the
  /// only remaining evidence of what the turn changed. It still travels through
  /// `CustomStatusMerger` and `RuntimeStateValidator` inside the commit
  /// transaction, and the fallback is recorded in the turn diagnostics.
  ///
  /// A stale settlement gets nothing at all: it belongs to a superseded turn,
  /// and writing any of it would let turn N overwrite turn N+1.
  void _applySettlementFailure(String status) {
    final isStale = status == 'stale' || status == 'stale_revision';
    final useLegacyRuntime =
        !isStale && _pendingNarrativeRuntimeChanges.isNotEmpty;
    _pendingCustomStatusEvaluations =
        isStale ? null : _pendingNarrativeEvaluations;
    _pendingCustomStatusChanges = isStale
        ? const []
        : [
            if (_pendingNarrativeEvaluations case final evaluations?)
              for (final evaluation in evaluations)
                if (evaluation.changed) evaluation.toChange(),
            ..._pendingNarrativeStatusChanges,
          ];
    _pendingRuntimeChanges =
        useLegacyRuntime ? _pendingNarrativeRuntimeChanges : const [];
    _pendingStatusParseDiagnostics =
        List<String>.unmodifiable(_pendingNarrativeStatusDiagnostics);
    _pendingSettlementDiagnostics = List<String>.unmodifiable([
      'turn_settlement:$status',
      if (useLegacyRuntime) 'legacy_runtime_state_fallback',
      if (!isStale && _pendingCustomStatusChanges.isNotEmpty)
        'legacy_custom_status_fallback',
    ]);
    if (isStale) {
      _pendingLegacyCustomStatus = const [];
    }
  }

  /// Freezes the final narrative as the pending assistant presentation.
  ///
  /// Called after every length supplement was merged and the typewriter has
  /// drained, immediately before the settlement request starts. From here on
  /// the prose can no longer change: no clearing, no re-typing, no replay.
  void _freezePendingAssistantNarrative(String finalNarrative) {
    _pendingAssistantContent = finalNarrative;
    _pendingAssistantPhase = PendingAssistantPhase.settling;
  }

  /// Appends the settlement result (status + options) after the frozen
  /// narrative. [content] is the exact string the committed message will
  /// carry, so the later widget swap is pixel-identical.
  void _stagePendingAssistantTail(String content) {
    if (_pendingAssistantPhase == PendingAssistantPhase.none) return;
    _pendingAssistantContent = content;
    _pendingAssistantPhase = PendingAssistantPhase.settled;
  }

  /// Releases the pending presentation. Must only be called after the
  /// committed message is already in `_host.messages`, so the frame that
  /// drops the pending bubble is the same frame that shows the final bubble.
  void _clearPendingAssistantPresentation() {
    _pendingAssistantContent = '';
    _pendingAssistantPhase = PendingAssistantPhase.none;
  }

  /// Test seam: injects (or clears, with [PendingAssistantPhase.none]) the
  /// pending presentation state so widget tests can exercise the
  /// streaming → settling → committed continuity without a live LLM.
  /// Never call from production code.
  @visibleForTesting
  void debugSetPendingAssistantPresentation({
    String content = '',
    PendingAssistantPhase phase = PendingAssistantPhase.none,
  }) {
    _pendingAssistantContent = content;
    _pendingAssistantPhase = phase;
  }

  /// Runs the single post-narrative settlement request.
  ///
  /// Contract (never relax):
  /// * It runs **once** per user turn, strictly after the final narrative.
  /// * Chunks accumulate in [_settlementStreamingContent] only.
  /// * It never throws — a failed settlement degrades the turn instead of
  ///   destroying prose the player can already read.
  /// * A result is discarded unless the request, generation, adventure, branch
  ///   **and** runtime HEAD revision are all still the ones it was issued for.
  Future<_SettlementOutcome> _runTurnSettlement({
    required String finalNarrative,
    required String userInput,
    required String requestId,
    required int requestGeneration,
    required int? adventureId,
    required int branchId,
    required int expectedRuntimeRevision,
  }) async {
    if (adventureId == null) {
      return const _SettlementOutcome(
          status: 'skipped_no_adventure', attempts: 0);
    }

    _freezePendingAssistantNarrative(finalNarrative);
    _status = ChatStatus.settling;
    _scenePhase = SceneDialoguePhase.settling;
    _settlementStreamingContent = '';
    _notifyAll();

    for (var attempt = 1; attempt <= _maxSettlementAttempts; attempt++) {
      if (!_isRequestCurrent(
          requestId, requestGeneration, adventureId, branchId)) {
        return _SettlementOutcome(status: 'stale', attempts: attempt);
      }
      final diagnostics = <String>[];
      try {
        final execution = await _executeAdventureContext(
          messages: _settlementPromptBuilder.buildMessages(
            userInput: userInput,
            finalNarrative: finalNarrative,
            scene: _host.gameState.currentScene,
            runtimeRevision: expectedRuntimeRevision,
            trackedStatuses: _trackedSettlementStatuses(),
            runtimeFacts: _settlementRuntimeFacts(),
          ),
          taskType: ContextTaskType.adventureTurnSettlement,
          intent: userInput,
          maximumOutputTokens: math.min(
            _settlementMaxTokens,
            _host.modelContextCapability.maximumOutputTokens,
          ),
          requestId: '$requestId:settlement$attempt',
          taskHandle: _activeTaskHandle,
          onChunk: (chunk) {
            if (!_isRequestCurrent(
                requestId, requestGeneration, adventureId, branchId)) {
              return;
            }
            _settlementStreamingContent += chunk;
          },
        );
        if (!_isRequestCurrent(
            requestId, requestGeneration, adventureId, branchId)) {
          return _SettlementOutcome(status: 'stale', attempts: attempt);
        }
        // Revision authority always lives in the repository, never in the
        // model output: a turn that landed in between makes this one stale.
        final head = await _adventureRepo.getRuntimeHead(adventureId, branchId);
        if (head.revision != expectedRuntimeRevision) {
          return _SettlementOutcome(
              status: 'stale_revision', attempts: attempt);
        }

        final settled =
            TurnSettlement.parse(execution.content, diagnostics: diagnostics);
        if (settled == null) {
          if (attempt < _maxSettlementAttempts) continue;
          return _SettlementOutcome(
              status: 'failed_json',
              attempts: attempt,
              diagnostics: diagnostics);
        }
        if (!settled.hasUsableOptions && attempt < _maxSettlementAttempts) {
          // Missing options is the one settlement defect worth a second, fast
          // attempt — everything else is accepted as-is and falls back.
          continue;
        }
        return _SettlementOutcome(
          settlement: settled,
          status: 'applied',
          attempts: attempt,
          diagnostics: diagnostics,
        );
      } catch (error) {
        if (!_isRequestCurrent(
            requestId, requestGeneration, adventureId, branchId)) {
          return _SettlementOutcome(status: 'stale', attempts: attempt);
        }
        if (attempt < _maxSettlementAttempts) continue;
        return _SettlementOutcome(
          status: 'failed_request',
          attempts: attempt,
          diagnostics: diagnostics,
        );
      }
    }
    return const _SettlementOutcome(
        status: 'failed_json', attempts: _maxSettlementAttempts);
  }

  /// Tracked status slots, keyed by the same stable identity the merger and
  /// the runtime validator use, so two same-named characters can never share a
  /// settlement.
  List<TurnSettlementTrackedStatus> _trackedSettlementStatuses() {
    final config = _host.adventureConfig;
    if (config == null) return const [];
    final protagonistId = config.protagonistCharacter?.characterId;
    final protagonistName =
        config.name.trim().isEmpty ? '主角' : config.name.trim();
    final tracked = <TurnSettlementTrackedStatus>[];

    void add(String entityId, String characterName,
        List<CustomAttributeItem> attributes) {
      for (final attribute in attributes) {
        tracked.add(TurnSettlementTrackedStatus(
          entityId: entityId,
          characterName: characterName,
          attributeId: attribute.identityRef,
          attributeName: attribute.name.trim(),
          displayValue: attribute.displayValue,
          isNumeric: attribute.isNumeric,
          description: attribute.description ?? '',
          importance: attribute.importance.label,
          currentValue:
              attribute.isNumeric ? attribute.effectiveCurrentValue : null,
          maxValue: attribute.isNumeric ? attribute.effectiveMaxValue : null,
        ));
      }
    }

    add(
        protagonistId != null && protagonistId.trim().isNotEmpty
            ? protagonistId.trim()
            : 'protagonist',
        protagonistName,
        config.customAttributes);
    for (final character in config.supportingCharacters) {
      if (!character.isAlive) continue;
      final id = character.id.trim();
      if (id.isEmpty) continue;
      add(id, character.name.trim(), character.customAttributes);
    }
    return List.unmodifiable(
        tracked.take(CustomStatusEvaluation.maximumEvaluationsPerTurn));
  }

  /// Compact runtime overlay facts, so settlement sees what the store already
  /// knows without receiving the whole chat history.
  List<String> _settlementRuntimeFacts() {
    final facts = <String>[];
    for (final entity in _runtimeEntities) {
      if (entity.overlay.isEmpty && entity.lifecycleStatus == 'active') {
        continue;
      }
      final entries = entity.overlay.entries
          .take(8)
          .map((entry) => '${entry.key}=${entry.value}');
      facts.add('${entity.entityId} (${entity.entityType.name}, '
          '${entity.lifecycleStatus}): ${entries.join(', ')}');
    }
    return List.unmodifiable(facts.take(12));
  }

  /// The narrative the player actually reads, used as settlement input.
  ///
  /// It is taken from the canonicalized response, i.e. after every length
  /// supplement was merged and after overflow convergence, so settlement never
  /// sees only the first segment of a supplemented turn.
  String _finalNarrativeOf(String content) =>
      AdventureResponse.parse(content).narrative.join('\n\n').trim();

  /// Keeps the first proposal per `entity:path`.
  ///
  /// [`RuntimeStateValidator.accept`] throws on a conflicting duplicate, and a
  /// throw inside the commit would discard a narrative the player can already
  /// read. Folding duplicates here is the fail-closed alternative.
  List<RuntimeStateChangeProposal> _dedupeRuntimeChanges(
    List<RuntimeStateChangeProposal> changes, {
    required List<String> diagnostics,
  }) {
    final seen = <String>{};
    final kept = <RuntimeStateChangeProposal>[];
    for (final change in changes) {
      final key = '${change.entityType.name}:${change.entityId}:${change.path}';
      if (!seen.add(key)) {
        diagnostics.add('runtime_state_change:duplicate:$key');
        continue;
      }
      kept.add(change);
    }
    return kept;
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
  ///
  /// Delegates to the single canonical counter so the generation-time and
  /// post-generation length guards agree on what a Chinese character is.
  static int countChinese(String text) => ChineseCharacterCounter.count(text);

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
    _pendingCustomStatusEvaluations = null;
    _pendingStatusParseDiagnostics = const [];
    _pendingSettlementStatusDiagnostics = const [];
    _pendingLegacyCustomStatus = const [];
    _pendingRuntimeChanges = const [];
    _pendingNarrativeRuntimeChanges = const [];
    _pendingNarrativeStatusDiagnostics = const [];
    _pendingSettlementDiagnostics = const [];
    _narrativeOptions = const [];
    _settlementStreamingContent = '';
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

    // R02-A: `false` until `commitSceneDialogueTurn` returns durably. From that
    // point on the database result is authoritative and a late cancellation may
    // only stop side effects that have not happened yet — it must never fake a
    // rollback of a turn the database already accepted.
    var turnCommitted = false;

    /// True once the committed turn has been reconciled into host memory.
    var memoryReconciled = false;

    /// The durable result of this turn, kept for post-commit recovery.
    SceneDialogueCommitResult? committedResult;

    /// The assistant message that was persisted by the commit.
    Message? committedAssistantMessage;

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
            '⚠️ 深度长篇叙事模式核心准则（最高优先级）：\n'
            '1. 叙事节拍铁律：一轮回复只推进一个叙事节拍，只呈现玩家本次行动的直接即时结果、环境反馈、心理波动与对白交锋；严禁替玩家执行未声明的后续行动，严禁跨越长时间段，严禁自行收束场景或写出结局——剧情一旦需要玩家输入/选择/行动，必须立即停笔。以 ${sceneSnapshot.budget.targetChineseChars} 字符充实铺陈为基准展开，但长篇篇幅只能靠环境烘托、心理刻画、对白细节与瞬时信息密度充实，绝不允许用增加时间跨度、事件数量或结局来凑字数！\n'
            '2. 状态结算：必须逐项输出 custom_status_evaluations，为每个被追踪状态给出 changed 判定（即使没变化也要列出并注明 reason）；changed=true 时同时给出 operation 与 value（数值用 set 或 delta，文本/阶段用 set）。旧字段 custom_status_changes 仍兼容但以评估协议为准；禁止无剧情依据的强行变化！坚决跨过 ${sceneSnapshot.budget.minChineseChars} 纯汉字硬指标！';
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
            ? '当前监测状态参考（${trackedAttrs.map((a) => '${a.characterName != null && a.characterName!.isNotEmpty ? "[${a.characterName}] " : ""}${a.name}=${a.displayValue}').join('、')}）。必须逐项输出 custom_status_evaluations：为上述每一个状态各给一条评估，changed=false 的也要列出并注明 reason；changed=true 时必须给出 operation 与 value（数值用 set 或 delta，文本/阶段用 set）。'
            : '必须逐项输出 custom_status_evaluations：为每个被追踪状态各给一条评估，changed=false 的也要列出并注明 reason；changed=true 时必须给出 operation 与 value（数值用 set 或 delta，文本/阶段用 set）。';

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
      // The settlement (and with it the frozen presentation) only starts once
      // the player has actually seen the final narrative, so the frozen bubble
      // replaces an identical screen — never a partially typed one.
      await _typewriter.onStreamEnd(_streamNotifier, notifyParent);
      if (!_isRequestCurrent(
          requestId, requestGeneration, adventureId, branchId)) {
        throw const GenerationCancelledException();
      }

      // ─── A. 叙事解析（P3-02: Isolate 后台解析）───
      // 只暂存兼容数据：正文 payload 不再是本轮状态结算的权威。
      _scenePhase = SceneDialoguePhase.parsing;
      await _applyNarrativeResponse(json);
      if (!_isRequestCurrent(
          requestId, requestGeneration, adventureId, branchId)) {
        throw const GenerationCancelledException();
      }

      // ─── B. Turn Settlement：本轮 options 与状态的生产权威 ───
      // 严格在整轮正文（含所有补写与收敛）彻底完成之后才发起，且每轮只发起一次。
      final settlementOutcome = await _runTurnSettlement(
        finalNarrative: _finalNarrativeOf(json),
        userInput: content,
        requestId: requestId,
        requestGeneration: requestGeneration,
        adventureId: adventureId,
        branchId: branchId,
        expectedRuntimeRevision: sceneSnapshot.runtimeRevision,
      );
      if (!_isRequestCurrent(
          requestId, requestGeneration, adventureId, branchId)) {
        throw const GenerationCancelledException();
      }
      _scenePhase = SceneDialoguePhase.parsing;
      final settlement = settlementOutcome.settlement;
      if (settlement != null) {
        _applySettlement(settlement);
      } else {
        _applySettlementFailure(settlementOutcome.status);
      }

      final settlementOptions = settlement?.options ?? const <String>[];
      final optionsFromSettlement =
          settlementOptions.length >= TurnSettlement.minimumUsableOptions;
      if (optionsFromSettlement) {
        _parsedOptions = List<String>.from(settlementOptions);
      } else {
        // Settlement options (possibly empty) first, then the narrative
        // payload's options, then the last valid set, then the scene fallback.
        _parsedOptions = _resolveTurnOptions(settlementOptions.isNotEmpty
            ? settlementOptions
            : (_narrativeOptions.isEmpty ? null : _narrativeOptions));
      }
      // §12: a successful settlement closes the options question. Repairing
      // afterwards would put a third request (`adventureOptionRepair`) behind
      // the narrative and the settlement, and its output is options only — so
      // it is reserved for a turn where neither the settlement nor the
      // narrative payload actually supplied a usable option set. (The scene
      // fallback always yields three generic options; that is a last resort,
      // not a reason to skip the repair request.)
      final hasUsableOptionSource = optionsFromSettlement ||
          _narrativeOptions.length >= TurnSettlement.minimumUsableOptions;
      final needsOptionRepair =
          !settlementOutcome.applied && !hasUsableOptionSource;
      if (!needsOptionRepair) {
        _lastValidOptions = List<String>.from(_parsedOptions);
      }

      final aiContent = needsOptionRepair || optionsFromSettlement
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
      // 纯函数投影：主响应状态结算后的 config（尚未写入 host）与状态诊断。
      final statusProjection = _projectPendingCustomStatus();
      final settledConfig = statusProjection.config;
      final statusDiagnostics = statusProjection.diagnostics;

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
      // 同一个字符串同时作为 pending presentation 的结构化尾部：settled 阶段
      // 玩家看到的内容与提交后的 Message 语义完全一致。
      final settledContent = needsOptionRepair || optionsFromSettlement
          ? _injectOptionsIntoAiContent(json, _parsedOptions,
              config: settledConfig)
          : _normalizeCustomStatusInAiContent(json, config: settledConfig);
      aiMsg = aiMsg.copyWith(content: settledContent);
      _stagePendingAssistantTail(settledContent);
      _notifyAll();
      final projectedSceneState = _promptBuilder.lastSceneState;
      // The runtime draft now comes from the settlement request. The narrative
      // payload is only consulted as a labelled legacy fallback, and any
      // settlement-side note travels with the parse diagnostics.
      final runtimeDiagnostics = <String>[..._pendingSettlementDiagnostics];
      final runtimeChanges = _pendingRuntimeChanges;
      final customStatusRuntimeChanges = settledConfig == null
          ? const <RuntimeStateChangeProposal>[]
          : _customStatusRuntimeChanges(
              current: _host.adventureConfig!,
              projected: settledConfig,
            );
      final customStatusPaths = {
        for (final change in customStatusRuntimeChanges)
          '${change.entityType.name}:${change.entityId}:${change.path}',
      };
      final allRuntimeChanges = <RuntimeStateChangeProposal>[
        ...customStatusRuntimeChanges,
        ...runtimeChanges.where(
          (change) => !customStatusPaths.contains(
            '${change.entityType.name}:${change.entityId}:${change.path}',
          ),
        ),
      ];
      // `RuntimeStateValidator` rejects conflicting duplicate paths by throwing,
      // which would abort an otherwise valid turn. De-duplicating here keeps
      // the atomic commit intact and turns the defect into a diagnostic.
      final dedupedRuntimeChanges = _dedupeRuntimeChanges(allRuntimeChanges,
          diagnostics: runtimeDiagnostics);
      final runtimeDraft = dedupedRuntimeChanges.isEmpty
          ? null
          : RuntimeStateCommitDraft(
              expectedRevision: sceneSnapshot.runtimeRevision,
              changes: List.unmodifiable(dedupedRuntimeChanges),
              summary: 'Turn settlement runtime changes',
              contextSnapshotId: sceneSnapshot.id,
              sourceMessageId: aiMsg.id,
            );
      final sceneStateDiagnostics = <String>[];
      final sceneStateProposal = SceneStateChangeProposal.parse(
        _sceneResponseMap(json)?['scene_state_changes'],
        diagnostics: sceneStateDiagnostics,
      );
      final committedSceneState = projectedSceneState?.copyWith(
        location: state.currentScene.isEmpty
            ? projectedSceneState.location
            : state.currentScene,
      );
      // 本轮最终字数判定的唯一来源，提交诊断与下方的响应监控共用同一份结果。
      // `overflowDetected` 只是「原始响应曾超限并已被收敛」的历史事件，绝不代表
      // 最终仍然超限；最终是否达标只由 finalVerdict 决定。
      final lengthMinimum = sceneSnapshot.budget.minChineseChars;
      final lengthHardMaximum = sceneSnapshot.budget.hardMaximum;
      final lengthFinalVerdict =
          lengthGuardResult.verdict(lengthMinimum, lengthHardMaximum);
      final lengthFinalPassed =
          lengthFinalVerdict == NarrativeLengthVerdict.withinRange;

      SceneDialogueCommitResult result = SceneDialogueCommitResult(
        applied: true,
        gameState: state,
        effects: effects,
        sceneState: committedSceneState,
        statusDiagnostics: statusDiagnostics,
      );
      if (adventureId != null) {
        // R02-A: the last cancellation gate before the irreversible commit.
        // Everything above this line is still revertible in memory; the INSERT
        // transaction below is not. A request that is cancelled, superseded or
        // detached from its adventure/branch here is refused entry, so a
        // cancelled turn never reaches the database.
        if (!_isRequestCurrent(
            requestId, requestGeneration, adventureId, branchId)) {
          throw const GenerationCancelledException();
        }
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
            'length_required_chinese_chars': lengthMinimum,
            'length_target_chinese_chars':
                sceneSnapshot.budget.targetChineseChars,
            'length_hard_maximum_chinese_chars': lengthHardMaximum,
            'length_supplement_chinese_chars':
                lengthGuardResult.supplementChineseChars,
            'length_final_chinese_chars': lengthGuardResult.finalChineseChars,
            'length_supplement_succeeded':
                lengthGuardResult.supplementSucceeded,
            if (lengthGuardResult.supplementAttempted)
              'length_supplement_thinking': false,
            'length_final_passed': lengthFinalPassed,
            // within_range / underflow / overflow，与响应监控控制台输出同源。
            'length_final_verdict': lengthFinalVerdict.diagnosticToken,
            // 历史事件：原始响应曾超过硬上限并被自动收敛（不代表最终失败）。
            'length_overflow_detected': lengthGuardResult.overflowDetected,
            // Turn settlement is a separate, post-narrative request. Its
            // character count is reported for latency triage only — it is never
            // part of the narrative word count.
            'turn_settlement_status': settlementOutcome.status,
            'turn_settlement_attempts': settlementOutcome.attempts,
            'turn_settlement_options_applied': optionsFromSettlement,
            'turn_settlement_response_chars':
                _settlementStreamingContent.length,
            if (runtimeDiagnostics.isNotEmpty)
              'ignored_runtime_state_changes': runtimeDiagnostics,
            if (sceneStateDiagnostics.isNotEmpty)
              'ignored_scene_state_changes': sceneStateDiagnostics,
          },
          candidates: candidates,
          effects: effects,
          runtimeStateDraft: runtimeDraft,
          sceneStateProposal: sceneStateProposal,
          statusDiagnostics: statusDiagnostics,
        ));
        // The transaction returned: this turn is now an irreversible fact.
        turnCommitted = true;
        committedResult = result;
        committedAssistantMessage = aiMsg;
      }
      // R02-A: only a turn that has NOT been durably committed may be abandoned
      // for a cancellation. Once `turnCommitted` is set the database result wins
      // and the memory/UI state below is reconciled from it — never rolled back.
      if (!turnCommitted &&
          !_isRequestCurrent(
              requestId, requestGeneration, adventureId, branchId)) {
        throw const GenerationCancelledException();
      }
      // 原子提交：主响应的状态结算只在此处落地一次。提交成功后 DB 结果是唯一权威，
      // 内存只从该结果重建；迟到取消只能停止尚未发生的后置副作用，不得伪回滚。
      _clearPendingCustomStatus(settledConfig);
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
      // 无闪烁替换：committed message 已进入数据源，同一同步块内释放 pending，
      // 下一帧 pending bubble 与 AiBubble 的切换对玩家不可见。
      _clearPendingAssistantPresentation();
      // R02-A: memory now matches the durable turn; a later cancellation can no
      // longer require any repair here.
      memoryReconciled = true;
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
      final budgetMin = lengthMinimum;
      final budgetTarget = sceneSnapshot.budget.targetChineseChars;
      final budgetHardMax = lengthHardMaximum;
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
      // 达标只看最终 verdict：曾经 overflow 但已收敛不是失败。
      final isPassed = lengthFinalPassed;
      final isFinalOverflow =
          lengthFinalVerdict == NarrativeLengthVerdict.overflow;
      final wasConverged =
          lengthGuardResult.overflowDetected && !isFinalOverflow;
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
      if (isFinalOverflow) {
        debugPrint('║  ⚠️  OVERFLOW: 最终正文仍超过硬上限 $budgetHardMax 字');
      } else if (wasConverged) {
        debugPrint('║  ⚠️  原始响应超出硬上限：'
            '${lengthGuardResult.initialChineseChars} → '
            '${lengthGuardResult.finalChineseChars}，已自动收敛');
      }
      debugPrint('╚══════════════════════════════════════════╝');
      debugPrint('');

      // 每 10 条消息触发一次自动备份
      AutoBackupService.onMessageSent();
      final tts = _host.tts;
      // 自动朗读只朗读“用户当前看到的正文”：双段协议的 ---JSON--- 结算数据
      // 与隐藏的思维链都不允许被念出来。
      final visibleNarrative =
          AdventureResponse.streamingDisplayText(json).trim();
      if (tts != null && tts.autoRead && visibleNarrative.isNotEmpty) {
        tts.speak(visibleNarrative);
      }
      _host.advanceSelectedCharacterIfAutoEnabled();
      _maybeSummarize();
    } catch (e) {
      _typewriter.cancel();
      _streamingContent = '';
      _clearPendingAssistantPresentation();
      _streamNotifier.value = '';
      _reasoningContent = '';
      _reasoningStreamNotifier.value = '';
      _isThinkingNotifier.value = false;

      // 立即重置 status，确保用户可重试
      _status = ChatStatus.idle;

      // R02-A: a committed turn is authoritative. Once the database accepted it,
      // a cancellation — however late — must NOT delete the user message, restore
      // the old game state or surface an error as if the turn never happened.
      // Only memory reconciliation may still be completed here.
      if (turnCommitted) {
        // The turn is durable; the exception below can only concern post-commit
        // side effects. It is logged rather than allowed to masquerade as a
        // failed turn, because the database truth must not be reverted.
        debugPrint('[ChatEngine] post-commit side effect failed after durable '
            'turn; committed state preserved: $e');
        if (!memoryReconciled && committedResult != null) {
          // Best-effort repair of the in-memory projection. The durable turn is
          // already safe; a failure here is logged and will be re-read on the
          // next load rather than hidden.
          try {
            final durableResult = committedResult;
            await _host.applySceneDialogueCommitResult(durableResult);
            final committedAi = committedAssistantMessage;
            if (committedAi != null &&
                !_host.messages.any((m) => m.id == committedAi.id)) {
              _host.messages.add(committedAi);
              _host.messages.addAll(durableResult.additionalMessages);
            }
            memoryReconciled = true;
          } catch (reconcileError) {
            debugPrint('[ChatEngine] committed turn memory reconciliation '
                'failed, DB remains authoritative: $reconcileError');
          }
        }
        _cancelRequested = false;
        _scenePhase = SceneDialoguePhase.completed;
        _notifyAll();
      } else if (_cancelRequested ||
          !_isRequestCurrent(
              requestId, requestGeneration, adventureId, branchId)) {
        // 用户主动取消 — 不添加错误消息，静默清理
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
        if (e is ApiError) {
          _lastErrorType = switch (e.type) {
            ApiErrorType.networkTimeout => errorTypeTimeout,
            ApiErrorType.unauthorized => errorTypeAuth,
            ApiErrorType.rateLimited => errorTypeRate,
            _ => errorTypeApi,
          };
          _lastErrorDetail = e.message;
        } else {
          _lastErrorType = errorTypeNetwork;
          _lastErrorDetail = e.toString().split('\n').first;
        }

        _host.messages.add(Message(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          // ErrorCard owns localized copy from errorType. Keep diagnostics in
          // the controller log only; never persist technical exception text.
          content: '⚠️',
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
      if (hasPendingAssistant) {
        _clearPendingAssistantPresentation();
      }
      if (_activeRequestId == requestId) {
        _activeRequestId = null;
        _activeTaskHandle = null;
        // R02-A: a cancellation that arrived after the irreversible commit must
        // not leak into the next request. The turn finished normally, so the
        // transient cancel flag is cleared here as well as on the rollback path.
        if (turnCommitted) {
          _cancelRequested = false;
        }
      }
      _notifyAll();
    }
  }

  /// 辅助任务：只为已经生成成功的正文补齐行动选项。
  ///
  /// 这是 **options 兜底**，不再是本轮状态结算的入口：状态权威是
  /// `TurnSettlement`，本方法只在结算请求完全没有产出结果时才被调用。
  ///
  /// 约束（不可放宽）：
  /// * 唯一产物是 `options`。即使修复模型返回 `custom_status_changes`、
  ///   `custom_status`、`affinity_change`、`hp/gold/inventory` 等字段也一律忽略。
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

  /// 纯函数：把解析阶段暂存的评估/Delta（优先）/ legacy 完整快照投影成新的
  /// [AdventureConfig]，不写入 host。Delta 与 legacy 同时出现时只采用 Delta，
  /// 保证同一轮的状态只被结算一次。
  ///
  /// 同时汇总本轮的全部状态诊断（解析期 + 目标定位 + 未评估项）。因为它保持纯
  /// 函数，`sendMessage` 里的两次调用（提交前投影 / 实际落地）必然产出一致结果。
  ({AdventureConfig? config, List<String> diagnostics})
      _projectPendingCustomStatus() {
    final changes = _pendingCustomStatusChanges;
    final legacy = _pendingLegacyCustomStatus;
    final evaluations = _pendingCustomStatusEvaluations;
    final config = _host.adventureConfig;
    if (config == null) {
      return (config: null, diagnostics: const <String>[]);
    }

    final diagnostics = <String>{
      ..._pendingStatusParseDiagnostics,
      ..._pendingSettlementStatusDiagnostics,
    };
    final hasEvaluations = evaluations != null;

    if (changes.isNotEmpty) {
      final result = CustomStatusMerger.applyChanges(
        protagonistName: config.name.trim(),
        protagonistId: config.protagonistCharacter?.characterId,
        protagonistAttributes: config.customAttributes,
        supportingCharacters: config.supportingCharacters,
        changes: changes,
      );
      diagnostics.addAll(result.diagnostics);
      diagnostics.addAll(_settlementApplyDiagnostics(result.outcomes));
      if (hasEvaluations) {
        diagnostics.addAll(_unevaluatedAttributes(config, evaluations));
      }
      _logStatusDiagnostics(diagnostics);
      return (
        config: config.copyWith(
          customAttributes: result.protagonistAttributes,
          supportingCharacters: result.supportingCharacters,
        ),
        diagnostics: List.unmodifiable(diagnostics),
      );
    }

    // 旧版完整快照只在评估协议缺席时使用：评估协议一出现就是权威来源，
    // 它声明 changed=false 的状态不允许再被整份快照覆盖。
    if (!hasEvaluations && legacy.isNotEmpty) {
      final result = CustomStatusMerger.applyLegacySnapshot(
        protagonistName: config.name.trim(),
        protagonistAttributes: config.customAttributes,
        supportingCharacters: config.supportingCharacters,
        snapshot: legacy,
      );
      _logStatusDiagnostics(diagnostics);
      return (
        config: config.copyWith(
          customAttributes: result.protagonistAttributes,
          supportingCharacters: result.supportingCharacters,
        ),
        diagnostics: List.unmodifiable(diagnostics),
      );
    }

    if (hasEvaluations) {
      diagnostics.addAll(_unevaluatedAttributes(config, evaluations));
    }
    // 全部 changed=false：不得改动任何状态，也无需写盘。
    if (diagnostics.isEmpty) {
      return (config: null, diagnostics: const <String>[]);
    }
    _logStatusDiagnostics(diagnostics);
    return (config: null, diagnostics: List.unmodifiable(diagnostics));
  }

  /// 把合并器的逐条结算结果转成 `settlement:applied/rejected` 诊断。
  ///
  /// 与 `settlement:evaluated/changed` 对照即可回答：状态不变到底是模型判定的，
  /// 还是解析、目标定位或值校验把变化丢在了半路。
  List<String> _settlementApplyDiagnostics(
      List<CustomStatusChangeOutcome> outcomes) {
    return [
      for (final outcome in outcomes)
        if (outcome.applied)
          'settlement:applied:${outcome.entityRef}:${outcome.attributeRef}:'
              '${outcome.oldDisplayValue}->${outcome.newDisplayValue}'
        else
          'settlement:rejected:${outcome.entityRef}:${outcome.attributeRef}:'
              '${outcome.rejectReason ?? 'unknown'}',
    ];
  }

  /// 差集：本轮被追踪、却在评估列表里完全缺席的状态 = 模型漏检。
  ///
  /// 仅在评估协议出现时计算；旧协议没有「逐项声明」的语义，缺席即无变化。
  List<String> _unevaluatedAttributes(
    AdventureConfig config,
    List<CustomStatusEvaluation> evaluations,
  ) {
    final tracked = config.allTrackedCustomAttributes
        .take(CustomStatusEvaluation.maximumEvaluationsPerTurn)
        .toList();
    if (tracked.isEmpty) return const [];

    final evaluated = <String>{};
    for (final evaluation in evaluations) {
      final ref = evaluation.attributeId ?? evaluation.attributeName;
      if (ref == null) continue;
      for (final attr in tracked) {
        if (attr.id == ref || attr.name.trim() == ref) {
          evaluated.add(attr.identityRef);
        }
      }
    }

    final missing = <String>[];
    for (final attr in tracked) {
      final ref = attr.identityRef;
      if (ref.isEmpty || evaluated.contains(ref)) continue;
      missing.add('unevaluated_attribute:$ref');
    }
    return missing;
  }

  void _logStatusDiagnostics(Set<String> diagnostics) {
    if (diagnostics.isEmpty) return;
    debugPrint('[ChatEngine] custom status diagnostics: '
        '${diagnostics.join(', ')}');
  }

  /// Clears staged custom status after the atomic runtime transaction.
  void _clearPendingCustomStatus(AdventureConfig? settledConfig) {
    final changes = _pendingCustomStatusChanges;
    final legacy = _pendingLegacyCustomStatus;
    final hasEvaluations = _pendingCustomStatusEvaluations != null;
    if (changes.isEmpty && legacy.isEmpty && !hasEvaluations) return;
    _pendingCustomStatusChanges = const [];
    _pendingLegacyCustomStatus = const [];
    _pendingCustomStatusEvaluations = null;
    _pendingStatusParseDiagnostics = const [];
    if (settledConfig == null) return;
    _logCustomStatusUpdate(
        settledConfig.customAttributes, settledConfig.supportingCharacters);
  }

  List<RuntimeStateChangeProposal> _customStatusRuntimeChanges({
    required AdventureConfig current,
    required AdventureConfig projected,
  }) {
    final changes = <RuntimeStateChangeProposal>[];
    final protagonistId =
        current.protagonistCharacter?.characterId ?? 'protagonist';
    _appendCustomStatusRuntimeChanges(
      output: changes,
      entityId: protagonistId,
      entityName: current.name,
      isProtagonist: true,
      before: current.customAttributes,
      after: projected.customAttributes,
    );
    final currentCharacters = {
      for (final character in current.supportingCharacters)
        character.id: character,
    };
    for (final character in projected.supportingCharacters) {
      final prior = currentCharacters[character.id];
      if (prior == null) continue;
      _appendCustomStatusRuntimeChanges(
        output: changes,
        entityId: character.id,
        entityName: character.name,
        isProtagonist: false,
        before: prior.customAttributes,
        after: character.customAttributes,
      );
    }
    return List.unmodifiable(changes);
  }

  void _appendCustomStatusRuntimeChanges({
    required List<RuntimeStateChangeProposal> output,
    required String entityId,
    required String entityName,
    required bool isProtagonist,
    required List<CustomAttributeItem> before,
    required List<CustomAttributeItem> after,
  }) {
    final beforeById = {for (final item in before) item.identityRef: item};
    for (final item in after) {
      final prior = beforeById[item.identityRef];
      if (prior == null || prior.displayValue == item.displayValue) continue;
      output.add(RuntimeStateChangeProposal(
        entityType: RuntimeEntityType.character,
        entityId: entityId,
        changeKind: RuntimeChangeKind.primary,
        operation: RuntimeChangeOperation.set,
        path: RuntimeStateChangeProposal.customAttributePath(item.identityRef),
        value: item.isNumeric ? item.effectiveCurrentValue : item.value.trim(),
        reason: _customStatusReason(
          entityId,
          entityName,
          isProtagonist,
          item,
        ),
      ));
    }
  }

  String _customStatusReason(
    String entityId,
    String entityName,
    bool isProtagonist,
    CustomAttributeItem attribute,
  ) {
    for (final change in _pendingCustomStatusChanges) {
      final characterMatches = change.characterId != null
          ? change.characterId == entityId ||
              (isProtagonist && change.characterId == 'protagonist')
          : change.characterName == null ||
              change.characterName == entityName ||
              (isProtagonist &&
                  const {'主角', '玩家', '自身', '我'}.contains(change.characterName));
      final attributeMatches = change.attributeId == attribute.id ||
          change.attributeId == attribute.name ||
          change.attributeName == attribute.name;
      if (characterMatches && attributeMatches) {
        return change.reason.isEmpty
            ? 'Custom status changed by narrative response'
            : change.reason;
      }
    }
    return 'Legacy custom status changed by narrative response';
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
      ContextTaskType.adventureTurnSettlement => LlmTask.turnSettlement,
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
          '$budgetNote，紧接上文收束本轮叙事节拍，不要超过上限。\n'
          '收束只指结束本轮回复，不得跨越时间或代替玩家行动，也不得自行收束场景或写出结局。\n'
          '本幕叙事收束后，立即输出一行分隔符 `---JSON---`，然后紧跟一行合法 JSON。\n'
          '⚠️ 【状态结算强制要求】：JSON 必须包含 options 数组与 custom_status_evaluations（逐项评估每个被追踪状态，changed=false 也要列出）。$statusHint';
    }
    if (stage == 1) {
      return '【分幕流水线·第 1 幕（入境与展开）指令】：\n'
          '本轮为长篇叙事的首发阶段。请展开饱满叙事：环境渲染、角色反应、心理与对白细节（$rangeNote）。\n'
          '只推进一个叙事节拍，不得替玩家行动、不得跨越时间，也不得引出后续事件链。\n'
          '本幕叙事正文控制在约 $stageCharTarget 纯汉字以内，不要超出。\n'
          '⚠️ 严禁提前草率收束！绝对严禁输出 ---JSON--- 及任何选项或状态数据！写满后直接以正文停笔。';
    }
    return '【分幕流水线·第 $stage 幕（续写）指令】：\n'
        '前 ${stage - 1} 幕已推进 $currentChars 纯汉字（$rangeNote）。\n'
        '请紧接上文继续充实同一个叙事节拍，本幕叙事正文控制在约 $stageCharTarget 纯汉字以内，不要超出。\n'
        '只允许扩充环境、心理、对白细节与瞬时信息密度，不得增加事件数量、时间跨度或推进到结局。\n'
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
        merged.remove('custom_status_evaluations');
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
        merged.remove('custom_status_evaluations');
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
      content: AppEventCodec.encode(AppEvent(
        code: AppEventCode.restCompleted,
        payload: {
          'hp': newHp - gs.hp,
          'mp': newMp - gs.mp,
          'energy': newEn - gs.energy,
        },
      )),
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
        content: AppEventCodec.encode(AppEvent(
          code: AppEventCode.levelUp,
          payload: {'level': newLevel, 'skillPoints': 2},
        )),
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
      content:
          result.event == null ? content : AppEventCodec.encode(result.event!),
      isUser: true,
    ));
    _notifyAll();

    // Enemy turn
    if (combatMgr.isActive) {
      final enemyResults = combatMgr.enemyTurn();
      for (final er in enemyResults) {
        _host.messages.add(Message(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          content:
              er.event == null ? er.action : AppEventCodec.encode(er.event!),
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
      onGenerate: (msgs, upToIndex, adventureId, branchId, generation,
          boundaryId) async {
        // v2.13: 构建当前状态快照 + 获取上期快照，供摘要 LLM 对比
        final gs = _host.gameState;
        final gameEng = _host.gameEngine;

        Map<String, int>? affinities;
        final config = _host.adventureConfig;
        if (config != null && gameEng != null) {
          affinities = {};
          for (final npc
              in config.supportingCharacters.where((n) => n.isAlive)) {
            affinities[npc.name] = npc.affinity;
          }
        }

        final stateSnapshot = SummaryService.buildStateSnapshot(gs, affinities);

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
          boundaryMessageId: boundaryId,
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
    if (_status == ChatStatus.streaming ||
        _status == ChatStatus.loading ||
        _status == ChatStatus.settling) {
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
    _pendingCustomStatusEvaluations = null;
    _pendingStatusParseDiagnostics = const [];
    _pendingLegacyCustomStatus = const [];
    _pendingRuntimeChanges = const [];
    _pendingNarrativeRuntimeChanges = const [];
    _pendingNarrativeStatusDiagnostics = const [];
    _pendingSettlementDiagnostics = const [];
    _narrativeOptions = const [];
    _settlementStreamingContent = '';
    _clearPendingAssistantPresentation();
    _pendingSettlementStatusDiagnostics = const [];
  }

  void clearError() {
    _lastErrorType = null;
    _lastErrorDetail = null;
    _notifyAll();
  }

  // ─── P0-7: 消息编辑 ───

  Future<bool> editMessage(
    int index,
    String newContent, {
    bool deleteFollowing = false,
  }) async {
    final msgs = _host.messages;
    if (index < 0 || index >= msgs.length) return false;
    final msg = msgs[index];
    final adventureId = _host.currentAdventureId;
    if (adventureId != null) {
      if (deleteFollowing) {
        await _adventureRepo.updateMessageAndDeleteFollowing(
          adventureId: adventureId,
          branchId: _host.currentBranchId,
          messageId: msg.id,
          newContent: newContent,
        );
      } else {
        await _adventureRepo.updateMessageContent(
          adventureId,
          msg.id,
          newContent,
        );
      }
    }
    msgs[index] = msg.copyWith(content: newContent, isEdited: true);
    if (deleteFollowing && index + 1 < msgs.length) {
      msgs.removeRange(index + 1, msgs.length);
    }
    _notifyAll();
    return true;
  }

  Future<bool> prepareMessageRegeneration(int index) async {
    final msgs = _host.messages;
    if (index < 0 || index >= msgs.length) return false;
    final message = msgs[index];
    final inclusive = !message.isUser;
    final adventureId = _host.currentAdventureId;
    if (adventureId != null) {
      await _adventureRepo.deleteMessageHistory(
        adventureId: adventureId,
        branchId: _host.currentBranchId,
        messageId: message.id,
        inclusive: inclusive,
      );
    }
    final deleteFrom = inclusive ? index : index + 1;
    if (deleteFrom < msgs.length) {
      msgs.removeRange(deleteFrom, msgs.length);
    }
    _notifyAll();
    return true;
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
