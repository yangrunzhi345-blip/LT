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
import '../models/chat_failure.dart';
import '../core/debug/generation_diagnostics.dart';
import '../models/game_state.dart';
import '../models/message.dart';
import '../models/llm_task.dart';
import '../models/model_capabilities.dart';
import '../models/scene_dialogue.dart';
import '../models/scene_dialogue_effects.dart';
import '../models/scene_state.dart';
import '../models/supporting_character.dart';
import '../models/turn_settlement.dart';
import '../models/tracked_state_evaluation.dart';
import '../models/typed_runtime_state.dart';
import '../models/worldview_details.dart';
import '../application/adventure/adventure_tracked_state_registry.dart';
import '../application/adventure/adventure_speaker_context.dart';
import '../application/adventure/tracked_state_candidate_planner.dart';
import '../application/adventure/tracked_state_snapshot.dart';
import '../application/narrative/user_intent.dart';
import '../services/auto_backup_service.dart';
import '../services/llm_service.dart';
import '../services/llm_task_policy.dart';
import '../services/web_search_service.dart';
import '../domain/events/app_event.dart';
import '../domain/events/app_event_codec.dart';
import '../services/repositories/adventure_repository.dart';
import '../services/custom_status_merger.dart';
import '../services/runtime_state_validator.dart';
import '../services/scene_consistency_validator.dart';
import '../services/scene_entry_authorizer.dart';
import 'chat_engine_host.dart';
import 'chat_engine_internals/prompt_builder.dart';
import 'chat_engine_internals/response_length_guard.dart';
import 'chat_engine_internals/stream_handler.dart';
import 'chat_engine_internals/summary_service.dart';
import 'chat_engine_internals/turn_settlement_prompt.dart';
import '../managers/combat_manager.dart';
import '../utils/chinese_character_counter.dart';
import '../utils/content_hasher.dart';
import '../services/generation_request_scheduler.dart';

class ContextExecutionResult {
  final String content;
  final String? reasoningContent;
  final LLMFinishReason finishReason;
  const ContextExecutionResult({
    required this.content,
    this.reasoningContent,
    this.finishReason = LLMFinishReason.unknown,
  });
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

  /// Completed stage prefix retained for reading after failure; never persisted.
  failed,
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
  static const errorTypeGeneration = 'generation';
  static const errorTypeInternal = 'internal';

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

  /// Candidate-planner diagnostics (e.g. fair-cap truncation). Never silently
  /// drops a non-protagonist entity without recording it.
  List<String> _pendingCandidateDiagnostics = const [];

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
  /// `_rewriteAssistantPresentationPayload`
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

  /// Consecutive turns that ended below the word minimum via the explicit
  /// player-decision marker. The marker is a legitimate stop, but a model
  /// could otherwise use it to bypass the length contract entirely, so a
  /// streak escalates a reminder instead of silently accepting it.
  int _consecutiveDecisionStops = 0;

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
        ) {
    GenerationDiagnostics.instance
        .mark('[ChatEngine][CREATE]', {'engine': identityHashCode(this)});
  }

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
    // Preview must not replace an active turn's planned records or trace.
    return PromptBuilder().getFullPromptPreview(
      _host,
      _host.messages,
      chatSummary,
      runtimeRevision: _promptBuilder.lastRelationships.runtimeRevision,
      runtimeEntities: _runtimeEntities,
      archiveRetrievalFacts: _runtimeArchiveFacts,
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
    final parsedEffects =
        SceneDialogueEffects.fromJson(_sceneResponseMap(content));
    _pendingSceneEffects = parsedEffects;

    _pendingCustomStatusChanges = const [];
    _pendingCustomStatusEvaluations = null;
    _pendingStatusParseDiagnostics = const [];
    _pendingSettlementStatusDiagnostics = const [];
    _pendingRuntimeChanges = const [];
    _pendingSettlementDiagnostics = const [];
    _pendingCandidateDiagnostics = const [];
    _pendingNarrativeRuntimeChanges = const [];
    _pendingNarrativeStatusDiagnostics = const [];
    _pendingNarrativeEvaluations = null;
    _pendingNarrativeStatusChanges = const [];
    _narrativeOptions = const [];

    if (response == null) {
      _stagePendingState(parsedEffects.applyState(gs));
      _pendingLegacyCustomStatus = const [];
      _parsedOptions = _lastValidOptions.isNotEmpty
          ? List<String>.from(_lastValidOptions)
          : _buildFallbackOptions(gs, null);
      return;
    }

    final patch = response.patch;
    _stagePendingState(parsedEffects.applyState(gs.copyWith(
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
    _pendingNarrativeRuntimeChanges = _filterExcludedRuntimeChanges(
      RuntimeStateChangeProposal.parse(
        payload?['runtime_state_changes'],
        diagnostics: narrativeRuntimeDiagnostics,
      ),
      _promptBuilder.lastIntent,
      diagnostics: narrativeRuntimeDiagnostics,
    );
    // A player-excluded character must not gain state through the legacy
    // narrative path either (it is the fallback when settlement fails).
    final excludedNarrative = _filterExcludedNarrativeState(
      effects: parsedEffects,
      evaluations: response.customStatusEvaluations,
      changes: response.customStatusChanges,
      intent: _promptBuilder.lastIntent,
    );
    _pendingSceneEffects = excludedNarrative.effects;
    _pendingLegacyCustomStatus = response.customStatus;
    _pendingNarrativeEvaluations = excludedNarrative.evaluations;
    _pendingNarrativeStatusChanges = excludedNarrative.changes;
    _pendingNarrativeStatusDiagnostics = List<String>.unmodifiable([
      ...response.parseDiagnostics,
      ...narrativeRuntimeDiagnostics,
      ...excludedNarrative.diagnostics,
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
    final excluded = _excludedEntities(_promptBuilder.lastIntent);
    final evaluations = settlement.customStatusEvaluations
        ?.where((evaluation) => !_isExcludedStatusEntry(
              evaluation.characterId,
              evaluation.characterName,
              excluded,
            ))
        .toList(growable: false);
    final settlementDiagnostics = <String>[];
    for (final evaluation in settlement.customStatusEvaluations ??
        const <CustomStatusEvaluation>[]) {
      if (_isExcludedStatusEntry(
          evaluation.characterId, evaluation.characterName, excluded)) {
        settlementDiagnostics.add(
            'custom_status_evaluation:excluded:${evaluation.characterId ?? evaluation.characterName ?? '?'}');
      }
    }
    _pendingCustomStatusEvaluations = evaluations;
    _pendingStatusParseDiagnostics =
        List<String>.unmodifiable(settlement.parseDiagnostics);
    _pendingCustomStatusChanges = [
      if (evaluations != null)
        for (final evaluation in evaluations)
          if (evaluation.changed) evaluation.toChange(),
      ...settlement.customStatusChanges
          .where((change) => !_isExcludedStatusEntry(
                change.characterId,
                change.characterName,
                excluded,
              )),
    ];
    for (final change in settlement.customStatusChanges) {
      if (_isExcludedStatusEntry(
          change.characterId, change.characterName, excluded)) {
        settlementDiagnostics.add(
            'custom_status_change:excluded:${change.characterId ?? change.characterName ?? '?'}');
      }
    }
    _pendingLegacyCustomStatus = const [];
    // A player-excluded character must not gain state from this turn either.
    _pendingRuntimeChanges = _filterExcludedRuntimeChanges(
      settlement.runtimeChanges,
      _promptBuilder.lastIntent,
      diagnostics: settlementDiagnostics,
    );
    if (settlementDiagnostics.isNotEmpty) {
      _pendingSettlementDiagnostics = List<String>.unmodifiable([
        ..._pendingSettlementDiagnostics,
        ...settlementDiagnostics,
      ]);
    }
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

    // Planned once per turn so the same candidate set drives the settlement
    // request *and* the mandatory-evaluation completeness check.
    final candidates = _settlementCandidates(
      userInput: userInput,
      finalNarrative: finalNarrative,
    );

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
            candidates: candidates,
            runtimeFacts: _settlementRuntimeFacts(),
            relationships: _promptBuilder.lastRelationships,
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
        // P1: a `不可忽略项` must never be silently skipped by the sparse
        // protocol. One bounded follow-up recovers omitted evaluations; a
        // still-missing one degrades with a diagnostic instead of blocking.
        final completed = await _completeCriticalEvaluations(
          settled: settled,
          candidates: candidates,
          finalNarrative: finalNarrative,
          userInput: userInput,
          requestId: requestId,
          requestGeneration: requestGeneration,
          adventureId: adventureId,
          branchId: branchId,
        );
        if (!_isRequestCurrent(
            requestId, requestGeneration, adventureId, branchId)) {
          return _SettlementOutcome(status: 'stale', attempts: attempt);
        }
        return _SettlementOutcome(
          settlement: completed,
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

  /// Hard output budget for the bounded critical-evaluation follow-up.
  static const int _criticalEvaluationMaxTokens = 512;

  /// Ensures every critical (`不可忽略项`) candidate carries an explicit
  /// evaluation, issuing **at most one** focused follow-up request.
  ///
  /// Returns the settlement augmented with the recovered evaluations (and the
  /// proposals they imply). It never loops: a monitor the follow-up still does
  /// not cover is recorded as `unevaluated` and the turn continues — a failed
  /// evaluation must not block the adventure. Diagnostics are folded into the
  /// settlement's `parseDiagnostics`, which reach `statusDiagnostics`.
  Future<TurnSettlement> _completeCriticalEvaluations({
    required TurnSettlement settled,
    required List<TrackedStateCandidate> candidates,
    required String finalNarrative,
    required String userInput,
    required String requestId,
    required int requestGeneration,
    required int? adventureId,
    required int branchId,
  }) async {
    final diagnostics = <String>[];
    // Traceability: a critical monitor this turn's scene scope excluded is
    // reported explicitly, so an absent critical evaluation is either
    // recovered/degraded or named here as out of scope — never silently
    // invisible.
    final registry =
        AdventureTrackedStateRegistry.fromConfig(_host.adventureConfig);
    final plannedKeys = {
      for (final candidate in candidates) candidate.monitorKey,
    };
    for (final binding in registry.all) {
      if (binding.definition.importance != CustomAttributeImportance.critical) {
        continue;
      }
      final key = '${binding.entityType.name}:'
          '${binding.entityId}:${binding.definitionId}';
      if (!plannedKeys.contains(key)) {
        diagnostics.add('critical_evaluation:out_of_scope:$key');
      }
    }
    final critical =
        candidates.where((candidate) => candidate.isCritical).toList();
    if (critical.isEmpty) {
      return _withCriticalDiagnostics(settled, diagnostics);
    }
    final evaluated = _evaluatedMonitorKeys(settled);
    final missing = <TrackedStateCandidate>[
      for (final candidate in critical)
        if (!evaluated.contains(candidate.monitorKey)) candidate,
    ];
    for (final candidate in critical) {
      if (!missing.contains(candidate)) {
        diagnostics
            .add('critical_evaluation:evaluated:${candidate.monitorKey}');
      }
    }

    var recovered = const <TrackedStateEvaluation>[];
    var recoveredChanges = const <RuntimeStateChangeProposal>[];
    if (missing.isNotEmpty) {
      diagnostics.add('critical_evaluation:topup:${missing.length}');
      try {
        final execution = await _executeAdventureContext(
          messages: TurnSettlementPromptBuilder.buildCriticalEvaluationMessages(
            userInput: userInput,
            finalNarrative: finalNarrative,
            scene: _host.gameState.currentScene,
            candidates: missing,
          ),
          taskType: ContextTaskType.adventureTurnSettlement,
          intent: userInput,
          maximumOutputTokens: math.min(
            _criticalEvaluationMaxTokens,
            _host.modelContextCapability.maximumOutputTokens,
          ),
          requestId: '$requestId:critical-eval',
          taskHandle: _activeTaskHandle,
          onChunk: (_) {},
        );
        if (!_isRequestCurrent(
            requestId, requestGeneration, adventureId, branchId)) {
          return _withCriticalDiagnostics(settled, diagnostics);
        }
        final topUp =
            TurnSettlement.parse(execution.content, diagnostics: diagnostics);
        if (topUp != null) {
          recovered = topUp.trackedEvaluations ?? const [];
          recoveredChanges = topUp.runtimeChanges;
        }
      } catch (_) {
        // A failed follow-up never blocks the turn; it degrades to a
        // diagnostic.
        diagnostics.add('critical_evaluation:topup_failed');
      }
    }

    final mergedEvaluations = <TrackedStateEvaluation>[
      ...?settled.trackedEvaluations,
      ...recovered,
    ];
    // `changed` evaluations become the same validated proposals the sparse
    // path produces; `unchanged` / `undetermined` never write.
    final evaluationChanges = <RuntimeStateChangeProposal>[];
    for (final evaluation in mergedEvaluations) {
      switch (evaluation.status) {
        case TrackedEvaluationStatus.changed:
          final proposal = evaluation.toProposal();
          if (proposal == null) {
            diagnostics
                .add('critical_evaluation:invalid_change:${evaluation.key}');
          } else {
            evaluationChanges.add(proposal);
          }
        case TrackedEvaluationStatus.unchanged:
          diagnostics.add('critical_evaluation:unchanged:${evaluation.key}');
        case TrackedEvaluationStatus.undetermined:
          diagnostics.add('critical_evaluation:undetermined:${evaluation.key}');
      }
    }
    final merged = settled.copyWith(
      trackedEvaluations: List.unmodifiable(mergedEvaluations),
      runtimeChanges: List.unmodifiable([
        ...settled.runtimeChanges,
        ...recoveredChanges,
        ...evaluationChanges,
      ]),
    );
    final resolved = _evaluatedMonitorKeys(merged);
    for (final candidate in missing) {
      diagnostics.add(
        resolved.contains(candidate.monitorKey)
            ? 'critical_evaluation:resolved:${candidate.monitorKey}'
            : 'critical_evaluation:unevaluated:${candidate.monitorKey}',
      );
    }
    return _withCriticalDiagnostics(merged, diagnostics);
  }

  TurnSettlement _withCriticalDiagnostics(
    TurnSettlement settlement,
    List<String> diagnostics,
  ) =>
      diagnostics.isEmpty
          ? settlement
          : settlement.copyWith(
              parseDiagnostics: List.unmodifiable([
                ...settlement.parseDiagnostics,
                ...diagnostics,
              ]),
            );

  /// Monitor keys (`entityType:entityId:definitionId`) the settlement either
  /// explicitly evaluated or changed outright.
  Set<String> _evaluatedMonitorKeys(TurnSettlement settlement) {
    final keys = <String>{};
    for (final evaluation
        in settlement.trackedEvaluations ?? const <TrackedStateEvaluation>[]) {
      keys.add(evaluation.key);
    }
    for (final change in settlement.runtimeChanges) {
      final definitionId =
          RuntimeStateChangeProposal.customAttributeIdFromPath(change.path);
      if (definitionId == null) continue;
      keys.add('${change.entityType.name}:${change.entityId}:$definitionId');
    }
    return keys;
  }

  /// Candidate monitoring definitions for this turn's settlement request.
  ///
  /// Reads the frozen [AdventureTrackedStateRegistry] — never a protagonist-first
  /// path — and applies the fair [TrackedStateCandidatePlanner]. Scene presence
  /// narrows the candidate set; the world is always eligible but contributes
  /// nothing when it declares no definitions. Two same-named characters keep
  /// independent candidates because identity is the stable id.
  List<TrackedStateCandidate> _settlementCandidates({
    required String userInput,
    required String finalNarrative,
  }) {
    final config = _host.adventureConfig;
    if (config == null) {
      return const [];
    }
    final registry = AdventureTrackedStateRegistry.fromConfig(config);
    if (registry.isEmpty) {
      _pendingCandidateDiagnostics = const [];
      return const [];
    }
    final names = _entityNames(config);
    final diagnostics = <String>[];
    final candidates = const TrackedStateCandidatePlanner().plan(
      registry: registry,
      runtimeEntities: _runtimeEntities,
      presentEntityIds: _presentEntityIds(config),
      mentionedEntityIds: _mentionedEntityIds(
        names,
        userInput: userInput,
        finalNarrative: finalNarrative,
      ),
      entityNames: names,
      baselineValues: _legacyBaselineValues(config),
      diagnostics: diagnostics,
    );
    _pendingCandidateDiagnostics =
        diagnostics.isEmpty ? const [] : List<String>.unmodifiable(diagnostics);
    if (diagnostics.isNotEmpty) {
      debugPrint(
          '[ChatEngine] monitored candidates: ${diagnostics.join(', ')}');
    }
    return candidates;
  }

  /// Scene presence resolved to stable ids.
  ///
  /// The scene stores the literal `protagonist` for the player character in
  /// legacy adventures; it is normalized to the stable id so the planner does
  /// not accidentally drop the protagonist. This is identity normalization,
  /// not protagonist priority — every entity is treated identically after.
  Set<String> _presentEntityIds(AdventureConfig config) {
    final present = _host.sceneParticipantIds.toSet();
    final protagonistId =
        AdventureTrackedStateRegistry.protagonistEntityId(config);
    if (present.remove('protagonist')) present.add(protagonistId);
    return present;
  }

  /// Entities whose display name appears in this turn's input or final prose.
  Set<String> _mentionedEntityIds(
    Map<String, String> names, {
    required String userInput,
    required String finalNarrative,
  }) {
    final mentioned = <String>{};
    for (final entry in names.entries) {
      final name = entry.value.trim();
      if (name.length < 2) continue;
      if (finalNarrative.contains(name) || userInput.contains(name)) {
        mentioned.add(entry.key);
      }
    }
    return mentioned;
  }

  /// Legacy `custom_attributes` baseline values, so a pre-definition adventure
  /// still shows the current value in the prompt. Never written back anywhere.
  Map<String, Object?> _legacyBaselineValues(AdventureConfig config) {
    final values = <String, Object?>{};
    void add(String entityType, String entityId, String definitionId,
        Object? value) {
      if (entityId.isEmpty || definitionId.isEmpty || value == null) return;
      values['$entityType:$entityId:$definitionId'] = value;
    }

    final protagonistId =
        AdventureTrackedStateRegistry.protagonistEntityId(config);
    for (final attribute in config.customAttributes) {
      add(
        RuntimeEntityType.character.name,
        protagonistId,
        attribute.identityRef,
        attribute.isNumeric
            ? attribute.effectiveCurrentValue
            : attribute.value.trim(),
      );
    }
    for (final character in config.supportingCharacters) {
      for (final attribute in character.customAttributes) {
        add(
          RuntimeEntityType.character.name,
          character.id.trim(),
          attribute.identityRef,
          attribute.isNumeric
              ? attribute.effectiveCurrentValue
              : attribute.value.trim(),
        );
      }
    }
    return values;
  }

  /// Stable display names for candidate entities, keyed by stable id.
  Map<String, String> _entityNames(AdventureConfig config) =>
      AdventureTrackedStateRegistry.entityDisplayNames(config);

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

  /// The scene location the player currently sees, with the same fallback the
  /// turn snapshot uses (game state scene before any persisted location).
  String _currentSceneLocation() {
    final location = _host.sceneState.location;
    if (location.trim().isNotEmpty) return location;
    return _host.gameState.currentScene;
  }

  /// Presence list for the durable commit: the conflict-resolved projection
  /// plus any player-excluded id that was already present in the host scene.
  /// Exclusion is a per-turn prompt constraint (the character may not act
  /// this turn); it must never rewrite persisted presence. Ids the turn
  /// explicitly authorized to leave are not restored.
  List<String> _restoredPresentCharacterIds(
    SceneState projected,
    NarrativeIntent? intent,
    List<String> authorizedLeaves,
  ) {
    final excluded = (intent?.excludedCharacterIds ?? const <String>[]).toSet();
    if (excluded.isEmpty) return projected.presentCharacterIds;
    final leaving = authorizedLeaves.toSet();
    final restore = <String>{
      ..._host.sceneState.presentCharacterIds
          .where((id) => excluded.contains(id) && !leaving.contains(id)),
    };
    if (restore.isEmpty) return projected.presentCharacterIds;
    // Keep the stored order stable: projected order first, appended extras.
    final ordered = <String>[...projected.presentCharacterIds];
    for (final id in _host.sceneState.presentCharacterIds) {
      if (restore.contains(id) && !ordered.contains(id)) ordered.add(id);
    }
    return List.unmodifiable(ordered);
  }

  /// Builds the authorization context for this turn's scene-state proposal
  /// from the conservative intent reading and the turn's final narrative.
  ///
  /// Narrative basis uses roster names of at least two characters: shorter
  /// names match too much ordinary prose to be a reliable identity signal.
  /// Arrival keywords are recorded for diagnostics only — they never
  /// authorize an entry (see [SceneEntryAuthorizer]).
  SceneEntryAuthorization _sceneEntryAuthorization(
    NarrativeIntent? intent,
    String finalNarrative,
  ) {
    final config = _host.adventureConfig;
    final names = config == null
        ? const <String, String>{}
        : AdventureTrackedStateRegistry.entityDisplayNames(config);
    final narrativeNames = <String>{
      for (final entry in names.entries)
        if (entry.value.trim().length >= 2 &&
            finalNarrative.contains(entry.value.trim()))
          entry.value.trim(),
    };
    return SceneEntryAuthorization(
      excludedCharacterIds:
          (intent?.excludedCharacterIds ?? const <String>[]).toSet(),
      invitedCharacterIds:
          (intent?.invitedCharacterIds ?? const <String>[]).toSet(),
      dismissedCharacterIds:
          (intent?.dismissedCharacterIds ?? const <String>[]).toSet(),
      narrativeNames: narrativeNames,
      narrativeHasArrival:
          NarrativeArrivalVocabulary.arrival.hasMatch(finalNarrative),
      characterNames: names,
      allowsLocationChange: intent?.forbidsSceneChange != true,
      allowsTimeChange: intent?.forbidsTimeSkip != true,
    );
  }

  /// Drops runtime state changes for entities the player explicitly excluded
  /// this turn: an excluded character must not gain state either.
  List<RuntimeStateChangeProposal> _filterExcludedRuntimeChanges(
    List<RuntimeStateChangeProposal> changes,
    NarrativeIntent? intent, {
    required List<String> diagnostics,
  }) {
    final excluded = (intent?.excludedCharacterIds ?? const <String>[]).toSet();
    if (excluded.isEmpty || changes.isEmpty) return changes;
    final kept = <RuntimeStateChangeProposal>[];
    for (final change in changes) {
      if (excluded.contains(change.entityId)) {
        diagnostics
            .add('runtime_state_change:excluded_entity:${change.entityId}');
        continue;
      }
      kept.add(change);
    }
    return kept;
  }

  /// Ids and display names of the characters the player excluded this turn.
  ///
  /// The prompt promises an excluded character "不得以任何方式参与本轮互动",
  /// so every state channel that names a character has to honour it: tracked
  /// status evaluations/changes, affinity and death effects, and the local
  /// keyword affinity analysis.
  ({Set<String> ids, Set<String> names}) _excludedEntities(
      NarrativeIntent? intent) {
    final ids = (intent?.excludedCharacterIds ?? const <String>[]).toSet();
    if (ids.isEmpty) return (ids: const {}, names: const {});
    final config = _host.adventureConfig;
    final names = <String>{};
    if (config != null) {
      final displayNames =
          AdventureTrackedStateRegistry.entityDisplayNames(config);
      for (final id in ids) {
        final name = displayNames[id];
        if (name != null && name.trim().isNotEmpty) names.add(name.trim());
      }
    }
    return (ids: ids, names: names);
  }

  /// True when a status entry refers to an excluded entity (by stable id or
  /// display name).
  bool _isExcludedStatusEntry(
    String? characterId,
    String? characterName,
    ({Set<String> ids, Set<String> names}) excluded,
  ) {
    if (characterId != null && excluded.ids.contains(characterId)) return true;
    final name = characterName?.trim();
    return name != null && name.isNotEmpty && excluded.names.contains(name);
  }

  /// Removes excluded entities from a narrative payload's effects, tracked
  /// status evaluations and legacy status changes.
  ({
    SceneDialogueEffects effects,
    List<CustomStatusEvaluation>? evaluations,
    List<CustomStatusChange> changes,
    List<String> diagnostics,
  }) _filterExcludedNarrativeState({
    required SceneDialogueEffects effects,
    required List<CustomStatusEvaluation>? evaluations,
    required List<CustomStatusChange> changes,
    required NarrativeIntent? intent,
  }) {
    final excluded = _excludedEntities(intent);
    if (excluded.ids.isEmpty) {
      return (
        effects: effects,
        evaluations: evaluations,
        changes: changes,
        diagnostics: const [],
      );
    }
    final diagnostics = <String>[];
    for (final name in effects.deadCharacters) {
      if (excluded.names.contains(name)) {
        diagnostics.add('effect:character_dead:excluded:$name');
      }
    }
    for (final name in effects.affinityChanges.keys) {
      if (excluded.names.contains(name)) {
        diagnostics.add('effect:affinity_change:excluded:$name');
      }
    }
    final affinityChanges = <String, int>{
      for (final entry in effects.affinityChanges.entries)
        if (!excluded.names.contains(entry.key)) entry.key: entry.value,
    };
    final deadCharacters = <String>{
      ...effects.deadCharacters.where((name) => !excluded.names.contains(name)),
    };
    final filteredEvaluations = evaluations
        ?.where((evaluation) => !_isExcludedStatusEntry(
              evaluation.characterId,
              evaluation.characterName,
              excluded,
            ))
        .toList(growable: false);
    for (final evaluation in evaluations ?? const <CustomStatusEvaluation>[]) {
      if (_isExcludedStatusEntry(
          evaluation.characterId, evaluation.characterName, excluded)) {
        diagnostics.add(
            'custom_status_evaluation:excluded:${evaluation.characterId ?? evaluation.characterName ?? '?'}');
      }
    }
    final filteredChanges = changes
        .where((change) => !_isExcludedStatusEntry(
              change.characterId,
              change.characterName,
              excluded,
            ))
        .toList(growable: false);
    for (final change in changes) {
      if (_isExcludedStatusEntry(
          change.characterId, change.characterName, excluded)) {
        diagnostics.add(
            'custom_status_change:excluded:${change.characterId ?? change.characterName ?? '?'}');
      }
    }
    return (
      effects: SceneDialogueEffects(
        level: effects.level,
        experience: effects.experience,
        mp: effects.mp,
        maxMp: effects.maxMp,
        baseAtk: effects.baseAtk,
        baseDef: effects.baseDef,
        baseSpeed: effects.baseSpeed,
        skillPoints: effects.skillPoints,
        affinityChanges: affinityChanges,
        deadCharacters: deadCharacters,
        itemsGained: effects.itemsGained,
        enemies: effects.enemies,
        diagnostics: effects.diagnostics,
      ),
      evaluations: filteredEvaluations,
      changes: filteredChanges,
      diagnostics: List.unmodifiable(diagnostics),
    );
  }

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
      final path = RuntimeStateSchemaRegistry.canonicalPath(
          change.entityType, change.path);
      final key = '${change.entityType.name}:${change.entityId}:$path';
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

  // ─── 发送消息（核心方法） ───

  /// Runs one scene turn through explicit phases.
  ///
  /// The try/catch/finally stays here on purpose: durability
  /// (`turnCommitted`), cancellation and terminal UI cleanup are turn-level
  /// invariants, not details of any single phase.
  Future<void> sendMessage(
    String content, {
    Future<String> Function(String content)? promptTransformer,
  }) async {
    if (_interceptNonNarrativeInput(content)) return;

    final context = _beginTurn(content);
    try {
      final userMessage = _upsertUserMessage(content);
      _startStreamingPhase();

      final snapshot = await _freezeTurnContext(context, content);
      // A request superseded while loading context ends silently, exactly as
      // the previous inline `return` did; finally still resets the turn.
      if (snapshot == null) return;

      final controlContext = await _buildControlContext(
        content: content,
        snapshot: snapshot,
        promptTransformer: promptTransformer,
      );

      final narrative = await _runNarrativeGeneration(
        context,
        snapshot,
        content,
        controlContext,
      );
      final finalized = await _finalizeNarrative(context, snapshot, narrative);
      final settlement =
          await _runSettlementPhase(context, snapshot, finalized, content);

      final plan = _buildTurnCommitPlan(
        context,
        snapshot,
        finalized,
        settlement,
        content,
        userMessage,
      );

      if (!await _commitTurn(context, plan)) return;
      _runPostTurnHooks(snapshot, finalized, plan);
    } catch (error, stackTrace) {
      await _handleTurnFailure(error, stackTrace, context);
    } finally {
      _finalizeTurn(context);
    }
  }

  /// Handles inputs that must never start an LLM turn.
  bool _interceptNonNarrativeInput(String content) {
    if (_status != ChatStatus.idle) {
      debugPrint('[ChatEngine] sendMessage blocked — status=$_status');
      return true;
    }
    if (_host.apiKey.isEmpty) {
      _host.messages.add(Message(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        content: AppEventCodec.encode(
            const AppEvent(code: AppEventCode.apiKeyNotConfigured)),
        isUser: false,
      ));
      _notifyAll();
      return true;
    }
    final combatMgr = _host.gameEngine?.combatMgr;
    if (combatMgr != null && combatMgr.isActive) {
      _handleCombatInput(content, combatMgr);
      return true;
    }
    if (content.trim() == '[休息]' || content.trim().startsWith('[休息]')) {
      _handleRest();
      return true;
    }
    return false;
  }

  /// Claims the engine for this turn and resets every per-turn staging buffer.
  _TurnExecutionContext _beginTurn(String content) {
    _status = ChatStatus.loading;
    final requestId =
        'scene-${DateTime.now().microsecondsSinceEpoch}-${++_generation}';
    final context = _TurnExecutionContext(
      content: content,
      requestId: requestId,
      generation: _generation,
      adventureId: _host.currentAdventureId,
      branchId: _host.currentBranchId,
    );
    _activeRequestId = requestId;
    _activeTaskHandle = GenerationTaskHandle(
        taskId: requestId, generationEpoch: context.generation);
    _scenePhase = SceneDialoguePhase.created;
    _cancelRequested = false;
    _clearPendingAssistantPresentation();
    _lastFailedContent = content;
    GenerationDiagnostics.instance.mark('[ChatTurn][START]', {
      'engine': identityHashCode(this),
      'request': requestId,
      'generation': context.generation,
      'adventure': context.adventureId,
      'branch': context.branchId,
      'provider': _host.providerType.name,
      'model': _host.modelName,
      'dialogueLevel': _host.dialogueLevel.id,
    });
    // Every turn starts from empty staging: parsing only writes pending values
    // and commit applies them once, so a retry can never re-settle an old delta.
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
    return context;
  }

  /// Reuses or replaces the trailing unanswered user bubble.
  Message _upsertUserMessage(String content) {
    while (_host.messages.isNotEmpty && _host.messages.last.isError) {
      _host.messages.removeLast();
    }

    Message userMessage;
    if (_host.messages.isNotEmpty && _host.messages.last.isUser) {
      final unrespondedIndices = <int>[];
      for (var i = _host.messages.length - 1; i >= 0; i--) {
        if (_host.messages[i].isUser) {
          unrespondedIndices.add(i);
        } else {
          break;
        }
      }

      if (_host.messages.last.content.trim() == content.trim()) {
        // Retry / regenerate / re-tap of the same option: keep one bubble.
        while (unrespondedIndices.length > 1) {
          final index = unrespondedIndices.removeAt(0);
          _host.messages.removeAt(index);
        }
        userMessage = _host.messages.last;
      } else {
        // The player switched input after a failure: replace the stale bubbles.
        for (final index in unrespondedIndices) {
          _host.messages.removeAt(index);
        }
        userMessage = Message(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          content: content,
          isUser: true,
        );
        _host.messages.add(userMessage);
      }
    } else {
      userMessage = Message(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        content: content,
        isUser: true,
      );
      _host.messages.add(userMessage);
    }
    _notifyAll();
    return userMessage;
  }

  void _startStreamingPhase() {
    _status = ChatStatus.streaming;
    _streamingContent = '';
    clearError();
    _typewriter.cancel();
    _streamNotifier.value = '';
    _reasoningContent = '';
    _reasoningStreamNotifier.value = '';
    _isThinkingNotifier.value = false;
    _notifyAll();
  }

  /// Loads branch-local context and freezes this turn's scene snapshot.
  ///
  /// Returns null when a newer request superseded this one while loading; that
  /// is a silent end, not a failure.
  Future<SceneDialogueContextSnapshot?> _freezeTurnContext(
    _TurnExecutionContext context,
    String content,
  ) async {
    final adventureId = context.adventureId;
    final branchId = context.branchId;
    final runtimeRevision = adventureId == null
        ? 0
        : (await _adventureRepo.getRuntimeHead(adventureId, branchId)).revision;
    if (!context.isCurrent(this)) {
      throw const GenerationCancelledException();
    }
    final runtimeEntities = adventureId == null
        ? const <RuntimeEntityState>[]
        : await _adventureRepo.getRuntimeEntities(adventureId, branchId);
    if (!context.isCurrent(this)) {
      throw const GenerationCancelledException();
    }
    final archiveFacts = adventureId == null
        ? const <String>[]
        : await _loadRuntimeArchiveFacts(content, adventureId, branchId);
    if (!context.isCurrent(this)) {
      throw const GenerationCancelledException();
    }
    _runtimeEntities = runtimeEntities;
    _runtimeArchiveFacts = archiveFacts;

    final snapshot = _freezeSceneContext(
      content,
      context.requestId,
      runtimeRevision: runtimeRevision,
      retrievalFacts: archiveFacts,
    );
    _lastSceneSnapshot = snapshot;

    if (content.trim().startsWith('/search ')) {
      try {
        final query = content.trim().substring(8);
        final webSearch = WebSearchService();
        final results = await webSearch.search(query);
        _pendingSearchResults = webSearch.formatForPrompt(results);
      } catch (_) {
        _pendingSearchResults = null; // Web search is best-effort.
      }
    } else {
      _pendingSearchResults = null;
    }

    if (!context.isCurrent(this)) return null;
    return snapshot;
  }

  Future<String> _buildControlContext({
    required String content,
    required SceneDialogueContextSnapshot snapshot,
    required Future<String> Function(String content)? promptTransformer,
  }) async {
    var controlContext = '';
    if (promptTransformer != null) {
      // An optional caller hook; its failure must not abort the turn.
      final transformed = await promptTransformer(content).catchError((_) {
        return content;
      });
      if (transformed.trim().isNotEmpty &&
          transformed.trim() != content.trim()) {
        controlContext = transformed;
      }
    }

    final isMultiStageNarrative = snapshot.budget.usesMultiStage;
    final requirement = isMultiStageNarrative
        ? snapshot.budget.aggregatePromptRequirement
        : snapshot.budget.promptRequirement;
    controlContext = '$controlContext\n$requirement'.trim();
    if (isMultiStageNarrative) {
      controlContext = '$controlContext\n'
          '深度长篇叙事模式核心准则（最高优先级）：\n'
          '1. 叙事节拍铁律：整轮合并回复只推进一个叙事节拍，只呈现玩家本次行动的直接即时结果、环境反馈、心理波动与对白交锋；严禁替玩家执行未声明的后续行动，严禁跨越长时间段，严禁自行收束场景或写出结局——剧情一旦需要玩家输入/选择/行动，必须立即停笔。以整轮合并正文 ${snapshot.budget.targetChineseChars} 字符为目标展开，当前幕只遵循当前幕的篇幅。长篇篇幅只能靠环境烘托、心理刻画、对白细节与瞬时信息密度充实，绝不允许用增加时间跨度、事件数量或结局来凑字数！\n'
          '2. 仅终幕状态结算：必须逐项输出 custom_status_evaluations，为每个被追踪状态给出 changed 判定（即使没变化也要列出并注明 reason）；changed=true 时同时给出 operation 与 value（数值用 set 或 delta，文本/阶段用 set）。旧字段 custom_status_changes 仍兼容但以评估协议为准；禁止无剧情依据的强行变化！整轮合并正文必须达到 ${snapshot.budget.minChineseChars} 纯汉字底线，单幕不受该底线约束。';
    }
    if (_underflowWarningNextRound) {
      controlContext =
          '$controlContext\n🔴 系统指令（硬性指标·重申）：上一轮【纯汉字正文】仅 $_underflowLastActual 字，尚未跨过 ${snapshot.budget.minChineseChars} 纯汉字底线（净缺口 $_underflowDeficit 字）！本轮必须严格跨过底线！';
      _underflowWarningNextRound = false;
      _decayWarningNextRound = false;
    } else if (_decayWarningNextRound) {
      controlContext =
          '$controlContext\n🔴 系统检测：上轮纯叙事正文字数显著下降。本轮请充实环境、心理与对白细节，恢复当前档位要求的叙事细节密度，但不得以增加事件数量或时间跨度的方式凑字数。';
      _decayWarningNextRound = false;
    } else if (_consecutiveDecisionStops >= 2) {
      // The decision marker is legal, but a streak would let a model bypass
      // the length contract turn after turn.
      controlContext =
          '$controlContext\n🔴 系统提示：已连续 $_consecutiveDecisionStops 轮以 `---等待玩家---` 停笔且未达到字数底线。`---等待玩家---` 只允许在剧情确实到达需要玩家决定、回应或行动的位置时使用；若本轮剧情尚未到达决策点，必须写满 ${snapshot.budget.minChineseChars} 纯汉字底线，不得以停笔标记替代叙事篇幅。';
    }
    return controlContext;
  }

  /// Runs the narrative request(s) for this turn.
  Future<_NarrativeRunResult> _runNarrativeGeneration(
    _TurnExecutionContext context,
    SceneDialogueContextSnapshot snapshot,
    String content,
    String controlContext,
  ) async {
    final requestId = context.requestId;
    final requestGeneration = context.generation;
    final adventureId = context.adventureId;
    final branchId = context.branchId;

    _scenePhase = SceneDialoguePhase.streaming;
    var json = '';
    var reasoningContentCombined = '';

    final outputBudget = snapshot.budget;
    final minRequiredWords = outputBudget.minChineseChars;
    final targetWords = outputBudget.targetChineseChars;
    final hardMaxWords = outputBudget.hardMaximum;
    var playerStopRequested = false;
    late List<Map<String, String>> lengthGuardBaseMessages;

    if (outputBudget.usesMultiStage) {
      // Budget-driven multi-stage generation: each stage recomputes the
      // remaining budget, and the loop ends at the target, the hard maximum or
      // an explicit player-decision stop.
      const maxAllowedStages = 4;
      GenerationDiagnostics.instance.mark('[ChatTurn][MULTI_STAGE_START]', {
        'engine': identityHashCode(this),
        'request': requestId,
        'generation': requestGeneration,
        'min': minRequiredWords,
        'target': targetWords,
        'max': hardMaxWords,
      });
      final stageNarratives = <String>[];
      var currentContextMessages = _promptBuilder.buildMessages(
        _host,
        content,
        _host.messages,
        chatSummary,
        _pendingSearchResults,
        runtimeRevision: snapshot.runtimeRevision,
        runtimeEntities: _runtimeEntities,
        archiveRetrievalFacts: _runtimeArchiveFacts,
        controlContext: controlContext,
        frozenOutputBudget: snapshot.budget,
      );
      // buildMessages already returns an unmodifiable list and is never mutated
      // in place below, so no second defensive copy is needed.
      lengthGuardBaseMessages = currentContextMessages;

      final trackedAttrs = _host.adventureConfig?.allTrackedCustomAttributes ??
          _host.adventureConfig?.customAttributes ??
          const <CustomAttributeItem>[];
      final statusHint = trackedAttrs.isNotEmpty
          ? '当前监测状态参考（${trackedAttrs.map((a) => '${a.characterName != null && a.characterName!.isNotEmpty ? "[${a.characterName}] " : ""}${a.name}=${a.displayValue}').join('、')}）。必须逐项输出 custom_status_evaluations：为上述每一个状态各给一条评估，changed=false 的也要列出并注明 reason；changed=true 时必须给出 operation 与 value（数值用 set 或 delta，文本/阶段用 set）。'
          : '必须逐项输出 custom_status_evaluations：为每个被追踪状态各给一条评估，changed=false 的也要列出并注明 reason；changed=true 时必须给出 operation 与 value（数值用 set 或 delta，文本/阶段用 set）。';

      var lastStagePayload = '';
      for (var stage = 1; stage <= maxAllowedStages; stage++) {
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
        final stageOutputTokens = SceneDialogueOutputBudget.requestOutputTokens(
          narrativeTokens:
              SceneDialogueOutputBudget.stageOutputTokens(stageCharTarget),
          params: _paramsForContextTask(ContextTaskType.adventureResponse),
          capabilities: ModelCapabilityRegistry.resolve(_host.modelName),
        );
        GenerationDiagnostics.instance.mark('[ChatTurn][STAGE_PLAN]', {
          'engine': identityHashCode(this),
          'request': requestId,
          'generation': requestGeneration,
          'stage': stage,
          'charsBefore': currentChars,
          'stageCharTarget': stageCharTarget,
          'maxTokens': stageOutputTokens,
        });
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

        final stageExecution = await _executeAdventureNarrativeStage(
          messages: currentContextMessages,
          turnRequestId: requestId,
          requestGeneration: requestGeneration,
          adventureId: adventureId,
          branchId: branchId,
          stage: stage,
          isFinalStage: isFinal,
          narrativeTokens:
              SceneDialogueOutputBudget.stageOutputTokens(stageCharTarget),
          intent: content,
          maximumOutputTokens: stageOutputTokens,
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

        final rc = stageExecution.reasoningContent;
        if (rc != null && rc.isNotEmpty) {
          reasoningContentCombined = reasoningContentCombined.isEmpty
              ? rc
              : '$reasoningContentCombined\n\n[第 $stage 幕思考]\n$rc';
        }

        final stageRaw = stageExecution.content;
        // Parse structurally so separator variants cannot leak JSON into prose.
        final stageParsed = AdventureResponse.parse(stageRaw);
        final stageStopped = stageParsed.stoppedAtDecision;
        final stageNarrative = stageParsed.narrative.join('\n\n').trim();
        if (stageNarrative.isEmpty && stageStopped) {
          // Marker + payload (no prose) is a protocol deviation, but the
          // payload still carries a usable settlement.
          if (stageParsed.payload == null) {
            throw const FormatException(
                'Player-decision stop without narrative');
          }
          lastStagePayload = jsonEncode(stageParsed.payload!);
          playerStopRequested = true;
          debugPrint('[ChatEngine] 第 $stage 幕仅有停笔标记与结算数据，按 payload-only 停笔处理');
          break;
        }
        if (stageNarrative.isEmpty && !isFinal) {
          throw const FormatException('Non-final stage has no narrative');
        }
        stageNarratives.add(stageNarrative);
        context.completedNarrativePrefix = stageNarratives.join('\n\n');
        if (stageParsed.payload != null) {
          lastStagePayload = jsonEncode(stageParsed.payload);
        }
        if (stageStopped) {
          playerStopRequested = true;
          debugPrint(
              '[ChatEngine] 第 $stage 幕在玩家决策点停笔（${AdventureResponse.playerStopMarker}），本轮提前结束');
          break;
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
        runtimeRevision: snapshot.runtimeRevision,
        runtimeEntities: _runtimeEntities,
        archiveRetrievalFacts: _runtimeArchiveFacts,
        controlContext: controlContext,
        frozenOutputBudget: snapshot.budget,
      );
      lengthGuardBaseMessages = apiMessages;
      final execution = await _executeAdventureNarrativeStage(
        messages: apiMessages,
        turnRequestId: requestId,
        requestGeneration: requestGeneration,
        adventureId: adventureId,
        branchId: branchId,
        stage: 1,
        isFinalStage: true,
        narrativeTokens:
            snapshot.budget.outputTokensFor(_host.completionParams.maxTokens),
        intent: content,
        maximumOutputTokens: SceneDialogueOutputBudget.requestOutputTokens(
          narrativeTokens:
              snapshot.budget.outputTokensFor(_host.completionParams.maxTokens),
          params: _paramsForContextTask(ContextTaskType.adventureResponse),
          capabilities: ModelCapabilityRegistry.resolve(_host.modelName),
        ),
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
      playerStopRequested = AdventureResponse.parse(json).stoppedAtDecision;
      reasoningContentCombined = execution.reasoningContent ?? '';
    }

    return _NarrativeRunResult(
      json: json,
      reasoning: reasoningContentCombined,
      playerStopRequested: playerStopRequested,
      lengthGuardBaseMessages: lengthGuardBaseMessages,
    );
  }

  /// Canonicalizes the narrative, enforces its length contract and makes the
  /// final narrative visible before settlement starts.
  Future<_FinalizedNarrative> _finalizeNarrative(
    _TurnExecutionContext context,
    SceneDialogueContextSnapshot snapshot,
    _NarrativeRunResult run,
  ) async {
    if (!context.isCurrent(this)) {
      throw const GenerationCancelledException();
    }
    // Rewrite into the canonical narrative + single payload shape so embedded
    // JSON can never remain in the visible prose.
    var json = AdventureResponse.canonicalize(run.json);
    if (run.playerStopRequested && json.trim().isEmpty) {
      throw const FormatException('Player-decision stop without narrative');
    }
    GenerationDiagnostics.instance.mark('[ChatTurn][LENGTH_START]',
        {'request': context.requestId, 'contentChars': json.length});
    final lengthGuard = await _ensureNarrativeLength(
      rawResponse: json,
      baseMessages: run.lengthGuardBaseMessages,
      snapshot: snapshot,
      requestId: context.requestId,
      requestGeneration: context.generation,
      adventureId: context.adventureId,
      branchId: context.branchId,
      playerStopRequested: run.playerStopRequested,
    );
    json = AdventureResponse.canonicalize(lengthGuard.content);
    final finalNarrative = _finalNarrativeOf(json);

    _streamingContent = json;
    _typewriter.feed(_streamingContent, _streamNotifier, notifyParent);
    if (!context.isCurrent(this)) {
      throw const GenerationCancelledException();
    }
    // Settlement may only start after the player has seen the final narrative;
    // the frozen bubble then replaces an identical screen.
    await _typewriter.onStreamEnd(_streamNotifier, notifyParent);
    if (!context.isCurrent(this)) {
      throw const GenerationCancelledException();
    }

    _scenePhase = SceneDialoguePhase.parsing;
    await _applyNarrativeResponse(json);
    if (!context.isCurrent(this)) {
      throw const GenerationCancelledException();
    }
    return _FinalizedNarrative(
      json: json,
      finalNarrative: finalNarrative,
      reasoning: run.reasoning,
      lengthGuard: lengthGuard,
    );
  }

  /// Runs the single post-narrative settlement request and resolves options.
  Future<_SettlementPhaseResult> _runSettlementPhase(
    _TurnExecutionContext context,
    SceneDialogueContextSnapshot snapshot,
    _FinalizedNarrative finalized,
    String content,
  ) async {
    GenerationDiagnostics.instance
        .mark('[ChatTurn][SETTLEMENT_START]', {'request': context.requestId});
    final settlementOutcome = await _runTurnSettlement(
      finalNarrative: finalized.finalNarrative,
      userInput: content,
      requestId: context.requestId,
      requestGeneration: context.generation,
      adventureId: context.adventureId,
      branchId: context.branchId,
      expectedRuntimeRevision: snapshot.runtimeRevision,
    );
    if (!context.isCurrent(this)) {
      throw const GenerationCancelledException();
    }
    _scenePhase = SceneDialoguePhase.parsing;
    GenerationDiagnostics.instance.mark('[ChatTurn][SETTLEMENT_DONE]', {
      'request': context.requestId,
      'status': settlementOutcome.status,
      'attempts': settlementOutcome.attempts
    });
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
      _parsedOptions = _resolveTurnOptions(settlementOptions.isNotEmpty
          ? settlementOptions
          : (_narrativeOptions.isEmpty ? null : _narrativeOptions));
    }
    // A successful settlement closes the options question; repair is reserved
    // for turns where neither settlement nor narrative supplied usable options.
    final hasUsableOptionSource = optionsFromSettlement ||
        _narrativeOptions.length >= TurnSettlement.minimumUsableOptions;
    final needsOptionRepair =
        !settlementOutcome.applied && !hasUsableOptionSource;
    if (!needsOptionRepair) {
      _lastValidOptions = List<String>.from(_parsedOptions);
    }

    final aiContent = _rewriteAssistantPresentationPayload(finalized.json,
        options:
            needsOptionRepair || optionsFromSettlement ? _parsedOptions : null);

    var aiMessage = Message(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      content: aiContent,
      reasoningContent: finalized.reasoning,
      isUser: false,
    );
    _streamingContent = '';
    _isRepairingOptions = needsOptionRepair;
    _streamNotifier.value = '';
    _reasoningContent = '';
    _reasoningStreamNotifier.value = '';
    _isThinkingNotifier.value = false;

    final responseMap = _sceneResponseMap(finalized.json);
    final candidates = SceneSettingCandidate.parse(
        responseMap?['scene_candidates'], context.requestId);
    _lastSceneCandidates = List.unmodifiable(candidates);
    final marker = finalized.json.indexOf('---JSON---');
    final continuity = const SceneConsistencyValidator().validate(
      snapshot: snapshot,
      narrative:
          marker < 0 ? finalized.json : finalized.json.substring(0, marker),
      payload: responseMap,
      userInput: content,
      invitedCharacterIds:
          (_promptBuilder.lastIntent?.invitedCharacterIds ?? const <String>[])
              .toSet(),
    );

    if (_isRepairingOptions) {
      _scenePhase = SceneDialoguePhase.repairing;
      await _repairMissingOptions(finalized.json, content,
          requestId: context.requestId,
          generation: context.generation,
          adventureId: context.adventureId,
          branchId: context.branchId);
      if (!context.isCurrent(this)) {
        throw const GenerationCancelledException();
      }
      aiMessage = aiMessage.copyWith(
          content: _rewriteAssistantPresentationPayload(finalized.json,
              options: _parsedOptions));
      _isRepairingOptions = false;
    }

    // Anti-decay and underflow tracking for the next turn's control context.
    final separatorIndex = finalized.json.indexOf('---JSON---');
    final narrative = separatorIndex >= 0
        ? finalized.json.substring(0, separatorIndex)
        : finalized.json;
    final currentWordCount = countChinese(narrative);
    if (_lastAiWordCount > 0 &&
        currentWordCount > 0 &&
        !finalized.lengthGuard.stoppedAtDecision) {
      final drop = (_lastAiWordCount - currentWordCount) / _lastAiWordCount;
      if (drop > 0.25) {
        _decayWarningNextRound = true;
        debugPrint(
            '[AntiDecay] 字数衰减: $_lastAiWordCount→$currentWordCount (${(drop * 100).round()}%)，下轮强化提醒');
      }
    }
    if (!finalized.lengthGuard.passed(snapshot.budget.minChineseChars)) {
      _underflowWarningNextRound = true;
      _underflowDeficit = snapshot.budget.minChineseChars - currentWordCount;
      _underflowLastActual = currentWordCount;
      debugPrint(
          '[LengthGuard] final=$currentWordCount required=${snapshot.budget.minChineseChars} failed; next-round fallback deficit=$_underflowDeficit');
    } else {
      _underflowWarningNextRound = false;
    }
    _lastAiWordCount = currentWordCount;

    return _SettlementPhaseResult(
      outcome: settlementOutcome,
      optionsFromSettlement: optionsFromSettlement,
      assistantMessage: aiMessage,
      candidates: candidates,
      continuity: continuity,
      narrativeChineseChars: currentWordCount,
    );
  }

  /// Projects all accepted state into one atomic commit request.
  _TurnCommitPlan _buildTurnCommitPlan(
    _TurnExecutionContext context,
    SceneDialogueContextSnapshot snapshot,
    _FinalizedNarrative finalized,
    _SettlementPhaseResult settlementPhase,
    String content,
    Message userMessage,
  ) {
    final requestId = context.requestId;
    final adventureId = context.adventureId;
    final branchId = context.branchId;
    final json = finalized.json;

    // Options are already visible, so release the turn for interaction before
    // the (potentially slow) SQLite transaction.
    _scenePhase = SceneDialoguePhase.committing;
    final statusProjection = _projectPendingCustomStatus();
    final settledConfig = statusProjection.config;
    final statusDiagnostics = statusProjection.diagnostics;

    var effects = _pendingSceneEffects;
    final affinityMgr = _host.gameEngine?.affinityMgr;
    final affinityConfig = settledConfig ?? _host.adventureConfig;
    if (affinityConfig != null && affinityMgr != null) {
      // Excluded characters must not gain affinity from keyword analysis.
      final excludedNames = _excludedEntities(_promptBuilder.lastIntent).names;
      final analyzable = excludedNames.isEmpty
          ? affinityConfig.supportingCharacters
          : affinityConfig.supportingCharacters
              .where((npc) => !excludedNames.contains(npc.name))
              .toList(growable: false);
      effects = effects.withAffinityChanges(
          affinityMgr.analyzeKeywords(content, analyzable));
    }
    final state = effects.applyState(_pendingGameState ?? _host.gameState);

    final runtimeDiagnostics = <String>[
      ..._pendingSettlementDiagnostics,
      ..._pendingCandidateDiagnostics,
    ];
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
    // Duplicate paths are de-duplicated here so the validator can keep
    // rejecting true conflicts without aborting an otherwise valid turn.
    final dedupedRuntimeChanges = _dedupeRuntimeChanges(allRuntimeChanges,
        diagnostics: runtimeDiagnostics);

    final statusSnapshot = _buildTrackedStatusSnapshot(dedupedRuntimeChanges);
    final settledContent = _rewriteAssistantPresentationPayload(json,
        options: _parsedOptions,
        config: settledConfig,
        statusSnapshot: statusSnapshot);
    final assistantMessage =
        settlementPhase.assistantMessage.copyWith(content: settledContent);
    GenerationDiagnostics.instance.mark('[AssistantMessageCommit][PREPARED]', {
      'messageId': assistantMessage.id,
      'customStatus': statusSnapshot?.length ?? 0,
    });
    _stagePendingAssistantTail(settledContent);
    _notifyAll();
    final projectedSceneState = _promptBuilder.lastSceneState;

    final runtimeDraft = dedupedRuntimeChanges.isEmpty
        ? null
        : RuntimeStateCommitDraft(
            expectedRevision: snapshot.runtimeRevision,
            changes: List.unmodifiable(dedupedRuntimeChanges),
            summary: 'Turn settlement runtime changes',
            contextSnapshotId: snapshot.id,
            sourceMessageId: assistantMessage.id,
          );
    final sceneStateDiagnostics = <String>[];
    final parsedSceneStateProposal = SceneStateChangeProposal.parse(
      _sceneResponseMap(json)?['scene_state_changes'],
      diagnostics: sceneStateDiagnostics,
    );
    final sceneIntent = _promptBuilder.lastIntent;
    final sceneAuthorization = const SceneEntryAuthorizer().authorize(
      proposal: parsedSceneStateProposal,
      authorization:
          _sceneEntryAuthorization(sceneIntent, finalized.finalNarrative),
      currentLocation: _currentSceneLocation(),
      currentTime: _host.sceneState.time,
    );
    sceneStateDiagnostics.addAll(sceneAuthorization.diagnostics);
    final sceneStateProposal = sceneAuthorization.proposal;
    if (sceneStateProposal == null && parsedSceneStateProposal != null) {
      sceneStateDiagnostics.add('scene_state_changes:fully_unauthorized');
    }
    final committedSceneState = projectedSceneState?.copyWith(
      location: state.currentScene.isEmpty
          ? projectedSceneState.location
          : state.currentScene,
      // A per-turn exclusion is prompt semantics, not a presence change.
      presentCharacterIds: _restoredPresentCharacterIds(
        projectedSceneState,
        _promptBuilder.lastIntent,
        sceneStateProposal?.charactersLeave ?? const [],
      ),
    );

    final lengthMinimum = snapshot.budget.minChineseChars;
    final lengthHardMaximum = snapshot.budget.hardMaximum;
    final lengthFinalVerdict =
        finalized.lengthGuard.verdict(lengthMinimum, lengthHardMaximum);
    GenerationDiagnostics.instance.mark('[ChatTurn][LENGTH_DONE]', {
      'request': requestId,
      'finalChars': finalized.lengthGuard.finalChineseChars,
      'verdict': lengthFinalVerdict.diagnosticToken
    });
    final lengthFinalPassed =
        lengthFinalVerdict == NarrativeLengthVerdict.withinRange ||
            lengthFinalVerdict == NarrativeLengthVerdict.decisionStop;
    if (lengthFinalVerdict == NarrativeLengthVerdict.decisionStop) {
      _consecutiveDecisionStops++;
    } else {
      _consecutiveDecisionStops = 0;
    }

    final inMemoryResult = SceneDialogueCommitResult(
      applied: true,
      gameState: state,
      effects: effects,
      sceneState: committedSceneState,
      statusDiagnostics: statusDiagnostics,
    );
    final commit = adventureId == null
        ? null
        : SceneDialogueCommit(
            requestId: requestId,
            adventureId: adventureId,
            branchId: branchId,
            userMessage: userMessage,
            assistantMessage: assistantMessage,
            gameState: state,
            sceneState: committedSceneState,
            contextSnapshotId: snapshot.id,
            diagnostics: {
              'budget_tokens': snapshot.budget.recommendedTokens,
              if (_promptBuilder.lastContextTrace case final trace?)
                'context_trace': trace.toDiagnostics(),
              'retrieval_degraded': snapshot.diagnostics.isNotEmpty,
              'continuity': settlementPhase.continuity.isConsistent
                  ? 'passed'
                  : 'warning',
              if (!settlementPhase.continuity.isConsistent)
                'warnings': settlementPhase.continuity.warnings,
              'length_guard_triggered':
                  finalized.lengthGuard.supplementAttempted,
              'length_initial_chinese_chars':
                  finalized.lengthGuard.initialChineseChars,
              'length_required_chinese_chars': lengthMinimum,
              'length_target_chinese_chars': snapshot.budget.targetChineseChars,
              'length_hard_maximum_chinese_chars': lengthHardMaximum,
              'length_supplement_chinese_chars':
                  finalized.lengthGuard.supplementChineseChars,
              'length_final_chinese_chars':
                  finalized.lengthGuard.finalChineseChars,
              'length_supplement_succeeded':
                  finalized.lengthGuard.supplementSucceeded,
              if (finalized.lengthGuard.supplementAttempted)
                'length_supplement_thinking': false,
              'length_final_passed': lengthFinalPassed,
              'length_final_verdict': lengthFinalVerdict.diagnosticToken,
              'length_overflow_detected':
                  finalized.lengthGuard.overflowDetected,
              'length_stopped_at_decision':
                  finalized.lengthGuard.stoppedAtDecision,
              'consecutive_decision_stops': _consecutiveDecisionStops,
              'turn_settlement_status': settlementPhase.outcome.status,
              'turn_settlement_attempts': settlementPhase.outcome.attempts,
              'turn_settlement_options_applied':
                  settlementPhase.optionsFromSettlement,
              'turn_settlement_response_chars':
                  _settlementStreamingContent.length,
              if (runtimeDiagnostics.isNotEmpty)
                'ignored_runtime_state_changes': runtimeDiagnostics,
              if (sceneStateDiagnostics.isNotEmpty)
                'ignored_scene_state_changes': sceneStateDiagnostics,
            },
            candidates: settlementPhase.candidates,
            effects: effects,
            runtimeStateDraft: runtimeDraft,
            sceneStateProposal: sceneStateProposal,
            statusDiagnostics: statusDiagnostics,
          );

    return _TurnCommitPlan(
      commit: commit,
      inMemoryResult: inMemoryResult,
      assistantMessage: assistantMessage,
      settledConfig: settledConfig,
      statusSnapshot: statusSnapshot,
      lengthVerdict: lengthFinalVerdict,
      lengthPassed: lengthFinalPassed,
      narrativeChineseChars: settlementPhase.narrativeChineseChars,
      runtimeRevision: snapshot.runtimeRevision,
    );
  }

  /// Commits the turn once, then reconciles host memory from the durable result.
  ///
  /// Returns false when a newer workspace owns the UI; the outer sendMessage
  /// then ends silently (turn-level finally still runs).
  Future<bool> _commitTurn(
    _TurnExecutionContext context,
    _TurnCommitPlan plan,
  ) async {
    var result = plan.inMemoryResult;
    final adventureId = context.adventureId;
    if (adventureId != null) {
      // Last cancellation gate before the irreversible INSERT transaction.
      if (!context.isCurrent(this)) {
        throw const GenerationCancelledException();
      }
      GenerationDiagnostics.instance.mark('[ChatTurn][COMMIT_START]', {
        'request': context.requestId,
        'runtimeRevision': plan.runtimeRevision,
      });
      result = await _adventureRepo.commitSceneDialogueTurn(plan.commit!);
      context.turnCommitted = true;
      GenerationDiagnostics.instance.mark('[AssistantMessageCommit][DONE]', {
        'messageId': plan.assistantMessage.id,
        'customStatus': plan.statusSnapshot?.length ?? 0,
      });
      GenerationDiagnostics.instance.mark('[ChatTurn][COMMIT_DONE]', {
        'request': context.requestId,
        'runtimeRevisionBefore': plan.runtimeRevision,
      });
      context.committedResult = result;
      context.committedAssistantMessage = plan.assistantMessage;
    }
    // Only an uncommitted turn may be abandoned by cancellation.
    if (!context.turnCommitted && !context.isCurrent(this)) {
      throw const GenerationCancelledException();
    }
    if (!context.owns(this)) {
      GenerationDiagnostics.instance.mark('[ChatTurn][STALE_COMMIT]', {
        'request': context.requestId,
        'committed': context.turnCommitted,
        'failureClass': ChatFailureClass.stale.name,
      });
      return false;
    }

    // DB is the single authority after commit; memory is rebuilt from it.
    _clearPendingCustomStatus(plan.settledConfig);
    await _host.applySceneDialogueCommitResult(result);
    if (!context.owns(this)) return false;

    for (var i = _host.messages.length - 1; i > 0; i--) {
      if (_host.messages[i].isUser &&
          _host.messages[i - 1].isUser &&
          _host.messages[i].content.trim() ==
              _host.messages[i - 1].content.trim()) {
        _host.messages.removeAt(i);
      }
    }
    _host.messages.add(plan.assistantMessage);
    _host.messages.addAll(result.additionalMessages);
    // Release the pending bubble in the same synchronous block as the commit
    // so the swap is invisible to the player.
    _clearPendingAssistantPresentation();
    context.memoryReconciled = true;
    if (result.applied && result.effects.startsCombat) {
      final enemies = CombatManager.enemiesFromJson(result.effects.enemies);
      if (enemies.isNotEmpty) {
        _host.gameEngine?.combatMgr.enter(enemies, result.gameState);
      }
    }
    _status = ChatStatus.idle;
    _scenePhase = SceneDialoguePhase.completed;
    _notifyAll();
    return true;
  }

  void _runPostTurnHooks(
    SceneDialogueContextSnapshot snapshot,
    _FinalizedNarrative finalized,
    _TurnCommitPlan plan,
  ) {
    _logTurnResponseMonitor(snapshot, finalized, plan);
    // Trigger an automatic backup every ten messages.
    AutoBackupService.onMessageSent();
    final tts = _host.tts;
    // Auto read only what the player sees: settlement payload and hidden
    // reasoning are never spoken.
    final visibleNarrative =
        AdventureResponse.streamingDisplayText(finalized.json).trim();
    if (tts != null && tts.autoRead && visibleNarrative.isNotEmpty) {
      tts.speak(
        visibleNarrative,
        sourceId: 'chat:${plan.assistantMessage.id}',
        speakerContext: buildAdventureSpeakerContext(_host.adventureConfig),
      );
    }
    _host.advanceSelectedCharacterIfAutoEnabled();
    _maybeSummarize();
  }

  void _logTurnResponseMonitor(
    SceneDialogueContextSnapshot snapshot,
    _FinalizedNarrative finalized,
    _TurnCommitPlan plan,
  ) {
    final budgetMin = snapshot.budget.minChineseChars;
    final budgetTarget = snapshot.budget.targetChineseChars;
    final budgetHardMax = snapshot.budget.hardMaximum;
    final parsed = AdventureResponse.parse(finalized.json);
    final payloadJson =
        parsed.payload != null ? jsonEncode(parsed.payload) : '';
    final jsonLen = payloadJson.length;
    final totalLen = finalized.json.length;
    final jsonRatio = totalLen > 0 ? (jsonLen / totalLen * 100) : 0.0;
    final lengthRatio =
        budgetMin > 0 ? (plan.narrativeChineseChars / budgetMin) : 0.0;
    final estimateTokens = (totalLen / 1.5).round();
    final roundNum = _host.messages.where((m) => m.isUser).length;
    final isFinalOverflow =
        plan.lengthVerdict == NarrativeLengthVerdict.overflow;
    final wasConverged =
        finalized.lengthGuard.overflowDetected && !isFinalOverflow;
    debugPrint('');
    debugPrint('╔══════════════════════════════════════════╗');
    debugPrint('║  📊 AI 响应监控  —  第 $roundNum 轮');
    debugPrint('╠══════════════════════════════════════════╣');
    debugPrint('║  字数范围:  $budgetMin / $budgetTarget / $budgetHardMax');
    debugPrint('║  实际:      ${plan.narrativeChineseChars}');
    debugPrint('║  倍率:      ${lengthRatio.toStringAsFixed(2)}x');
    debugPrint('║  JSON:      $jsonLen');
    debugPrint('║  JSON占比:  ${jsonRatio.toStringAsFixed(1)}%');
    debugPrint('║  估算tokens: $estimateTokens');
    debugPrint('║  达标:      ${plan.lengthPassed ? '✅ 是' : '❌ 否'}');
    if (isFinalOverflow) {
      debugPrint('║  ⚠️  OVERFLOW: 最终正文仍超过硬上限 $budgetHardMax 字');
    } else if (wasConverged) {
      debugPrint('║  ⚠️  原始响应超出硬上限：'
          '${finalized.lengthGuard.initialChineseChars} → '
          '${finalized.lengthGuard.finalChineseChars}，已自动收敛');
    }
    debugPrint('╚══════════════════════════════════════════╝');
    debugPrint('');
  }

  /// Turns every failure into either a durable-result reconciliation or one
  /// user-visible error category; it never rolls back a committed turn.
  Future<void> _handleTurnFailure(
    Object error,
    StackTrace stackTrace,
    _TurnExecutionContext context,
  ) async {
    if (!context.owns(this)) return;
    final failureClass = ChatFailureClass.classify(error);
    GenerationDiagnostics.instance.mark('[ChatTurn][FAILED]', {
      'engine': identityHashCode(this),
      'request': context.requestId,
      'generation': context.generation,
      'phase': _scenePhase.name,
      'runtimeType': error.runtimeType.toString(),
      'failureClass': failureClass.name,
      'stackTrace': stackTrace,
      'contentChars': _streamingContent.length,
      'reasoningChars': _reasoningContent.length,
    });
    _typewriter.cancel();
    _streamingContent = '';
    _clearPendingAssistantPresentation();
    _streamNotifier.value = '';
    if (!_cancelRequested &&
        context.isCurrent(this) &&
        (context.completedNarrativePrefix.isNotEmpty ||
            _reasoningContent.isNotEmpty)) {
      _pendingAssistantContent = context.completedNarrativePrefix;
      _pendingAssistantPhase = PendingAssistantPhase.failed;
    } else {
      _reasoningContent = '';
      _reasoningStreamNotifier.value = '';
    }
    _isThinkingNotifier.value = false;

    // Release the turn immediately so the player can retry.
    _status = ChatStatus.idle;

    if (context.turnCommitted) {
      // A durable turn can only fail in post-commit side effects; the database
      // result wins and memory is repaired best-effort from it.
      debugPrint('[ChatEngine] post-commit side effect failed after durable '
          'turn; committed state preserved: ${error.runtimeType}');
      if (!context.memoryReconciled && context.committedResult != null) {
        try {
          final durableResult = context.committedResult!;
          await _host.applySceneDialogueCommitResult(durableResult);
          final committedAi = context.committedAssistantMessage;
          if (committedAi != null &&
              !_host.messages.any((m) => m.id == committedAi.id)) {
            _host.messages.add(committedAi);
            _host.messages.addAll(durableResult.additionalMessages);
          }
          context.memoryReconciled = true;
        } catch (reconcileError) {
          debugPrint('[ChatEngine] committed turn memory reconciliation '
              'failed, DB remains authoritative: ${reconcileError.runtimeType}');
        }
      }
      _cancelRequested = false;
      _scenePhase = SceneDialoguePhase.completed;
      _notifyAll();
    } else if (failureClass == ChatFailureClass.cancelled ||
        _cancelRequested ||
        !context.isCurrent(this)) {
      // User cancellation: no error card, remove the unanswered user bubble.
      _cancelRequested = false;
      _scenePhase = SceneDialoguePhase.cancelled;
      final messages = _host.messages;
      if (messages.isNotEmpty && messages.last.isUser) {
        messages.removeLast();
      }
      _notifyAll();
    } else {
      _scenePhase = SceneDialoguePhase.failed;
      _lastErrorType = failureClass.presentationType;
      _lastErrorDetail = failureClass.name;
      _host.messages.add(Message(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        // ErrorCard owns localized copy from errorType.
        content: '',
        isUser: false,
        errorType: _lastErrorType,
      ));
    }
  }

  /// Terminal cleanup that must run for success, failure and cancellation.
  void _finalizeTurn(_TurnExecutionContext context) {
    if (_disposed || _activeRequestId != context.requestId) return;
    if (!context.owns(this)) {
      // The engine still owns transient buffers but lost the workspace.
      _scenePhase = SceneDialoguePhase.cancelled;
      _clearPendingAssistantPresentation();
      _streamingContent = '';
      _streamNotifier.value = '';
      _reasoningContent = '';
      _reasoningStreamNotifier.value = '';
      _isThinkingNotifier.value = false;
    }
    if (_status != ChatStatus.idle) {
      _status = ChatStatus.idle;
    }
    if (hasPendingAssistant &&
        _pendingAssistantPhase != PendingAssistantPhase.failed) {
      _clearPendingAssistantPresentation();
    }
    _activeRequestId = null;
    _activeTaskHandle = null;
    // A cancellation after the irreversible commit must not leak into the
    // next turn.
    if (context.turnCommitted) {
      _cancelRequested = false;
    }
    GenerationDiagnostics.instance.mark('[ChatTurn][END]', {
      'engine': identityHashCode(this),
      'request': context.requestId,
      'generation': context.generation,
      'phase': _scenePhase.name,
      'committed': context.turnCommitted,
      'status': _status.name,
      'scheduler': GenerationRequestScheduler.shared.debugSnapshot(),
    });
    _notifyAll();
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

  /// Builds the assistant message's `custom_status` presentation snapshot from
  /// the unified tracked-state authority.
  ///
  /// [acceptedChanges] is the exact set of runtime proposals this turn will
  /// commit. The snapshot is filtered through the same [RuntimeStateValidator]
  /// the commit uses and then projected onto the current overlay with the same
  /// frozen bounds, so the inline block can never show a value the runtime did
  /// not accept (a monitor capped at 100 can never read `120 / 100`). Returns
  /// `null` when there is no adventure config to read definitions from.
  List<Map<String, dynamic>>? _buildTrackedStatusSnapshot(
    List<RuntimeStateChangeProposal> acceptedChanges,
  ) {
    final config = _host.adventureConfig;
    if (config == null) return null;
    final validated = const RuntimeStateValidator().accept(
      acceptedChanges,
      config: config,
    );
    final snapshot = const TrackedStateSnapshotBuilder().build(
      config: config,
      runtimeEntities: _runtimeEntities,
      acceptedChanges: validated,
    );
    GenerationDiagnostics.instance.mark('[TrackedSnapshot]', {
      'definitions':
          AdventureTrackedStateRegistry.fromConfig(config).all.length,
      'items': snapshot.length,
    });
    return snapshot;
  }

  /// Legacy `custom_status` snapshot for callers that have no unified-definition
  /// projection (pre-settlement interim content and the option-repair path).
  List<Map<String, dynamic>> _legacyCustomStatusMaps(AdventureConfig? config) {
    final attributes = config?.allTrackedCustomAttributes ??
        _host.adventureConfig?.allTrackedCustomAttributes ??
        _host.adventureConfig?.customAttributes ??
        const <CustomAttributeItem>[];
    return [for (final attribute in attributes) attribute.toJson()];
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
    bool playerStopRequested = false,
  }) async {
    final initial = _lengthGuard.withoutSupplement(rawResponse);
    final minimum = snapshot.budget.minChineseChars;
    final hardMaximum = snapshot.budget.hardMaximum;
    // An explicit player-decision stop is a complete beat: never supplement
    // past the point where the player has to act.
    if (initial.passed(minimum) || playerStopRequested) {
      debugPrint('[LengthGuard] initial=${initial.initialChineseChars} '
          'required=$minimum hardMax=$hardMaximum passed=true'
          '${playerStopRequested ? ' (player decision stop)' : ''}');
      // The engine passes canonicalized content (marker already stripped), so
      // the turn-level flag is the authoritative stop signal here.
      final effective = playerStopRequested && !initial.stoppedAtDecision
          ? initial.copyWith(stoppedAtDecision: true)
          : initial;
      return _withOverflowGuard(effective, hardMaximum: hardMaximum);
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
      stoppedAtDecision: result.stoppedAtDecision,
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

  /// Recovers a completed reasoning-only stage once, under the same turn.
  Future<ContextExecutionResult> _executeAdventureNarrativeStage({
    required List<Map<String, String>> messages,
    required int maximumOutputTokens,
    required int narrativeTokens,
    required String requestId,
    required String turnRequestId,
    required int requestGeneration,
    required int? adventureId,
    required int branchId,
    required int stage,
    required bool isFinalStage,
    GenerationTaskHandle? taskHandle,
    void Function(String chunk)? onChunk,
    void Function(String reasoningChunk)? onReasoningChunk,
    String? intent,
    bool allowPartial = false,
  }) async {
    void ensureCurrent() {
      if (!_isRequestCurrent(
              turnRequestId, requestGeneration, adventureId, branchId) ||
          taskHandle?.isCancelled == true) {
        throw const GenerationCancelledException();
      }
    }

    ensureCurrent();
    try {
      final primary = await _executeAdventureContext(
        messages: messages,
        maximumOutputTokens: maximumOutputTokens,
        requestId: requestId,
        taskType: ContextTaskType.adventureResponse,
        taskHandle: taskHandle,
        onChunk: onChunk,
        onReasoningChunk: onReasoningChunk,
        intent: intent,
        allowPartial: allowPartial,
      );
      ensureCurrent();
      return primary;
    } on ReasoningOnlyResponseException catch (primary) {
      ensureCurrent();
      final trace = <String, Object?>{
        'engine': identityHashCode(this),
        'request': turnRequestId,
        'subRequest': requestId,
        'generation': requestGeneration,
        'stage': stage,
        'semanticRecoveryLimit': 1,
      };
      GenerationDiagnostics.instance.mark('[ChatTurn][REASONING_ONLY]', {
        ...trace,
        'semanticRecovery': 0,
        'reasoningChars': primary.result.reasoningContent?.length ?? 0,
        'contentChars': primary.result.content.length,
        'finishReason': primary.result.finishReason.stableValue,
      });

      final recoveryId = '$requestId:prose-recovery';
      final params = _paramsForContextTask(ContextTaskType.adventureResponse)
          .copyWith(enableThinking: false, reasoningEffort: 'low');
      final proseTokens = SceneDialogueOutputBudget.requestOutputTokens(
        narrativeTokens: narrativeTokens,
        params: params,
        capabilities: ModelCapabilityRegistry.resolve(_host.modelName),
      );
      final recoveryTrace = {
        ...trace,
        'subRequest': recoveryId,
        'semanticRecovery': 1,
        'thinkingEnabled': false,
        'reasoningEffort': 'low',
        'maxTokens': proseTokens,
      };
      _isThinkingNotifier.value = false;
      notifyParent();
      ensureCurrent();
      GenerationDiagnostics.instance
          .mark('[ChatTurn][PROSE_RECOVERY_START]', recoveryTrace);
      try {
        final recovered = await _executeAdventureContext(
          messages: [
            ...messages,
            {
              'role': 'user',
              'content': '【正文恢复指令】上一生成阶段未返回可显示的叙事正文。'
                  '现在直接输出本幕叙事正文，不要输出思考过程、解释或复述任务。'
                  '严格遵守原始上下文、当前分幕的篇幅、叙事范围与玩家行动边界。'
                  '${isFinalStage ? '本幕为终幕，仍按原指令输出正文及 ---JSON--- 和 JSON。' : '本幕为中间幕，只输出正文，不输出 JSON、选项或状态。'}',
            },
          ],
          maximumOutputTokens: proseTokens,
          requestId: recoveryId,
          taskType: ContextTaskType.adventureResponse,
          taskHandle: taskHandle,
          onChunk: onChunk,
          intent: intent,
          allowPartial: allowPartial,
          overrideParams: params,
        );
        ensureCurrent();
        GenerationDiagnostics.instance.mark('[ChatTurn][PROSE_RECOVERY_DONE]', {
          ...recoveryTrace,
          'contentChars': recovered.content.length,
          'finishReason': recovered.finishReason.stableValue,
        });
        return ContextExecutionResult(
          content: recovered.content,
          reasoningContent: primary.result.reasoningContent,
          finishReason: recovered.finishReason,
        );
      } catch (error, stack) {
        GenerationDiagnostics.instance
            .mark('[ChatTurn][PROSE_RECOVERY_FAILED]', {
          ...recoveryTrace,
          'runtimeType': error.runtimeType.toString(),
          'failureClass': ChatFailureClass.classify(error).name,
          'stackTrace': stack,
        });
        rethrow;
      }
    }
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
    final trace = <String, Object?>{
      'engine': identityHashCode(this),
      'request': _activeRequestId,
      'subRequest': requestId,
      'generation': taskHandle?.generationEpoch,
      'taskType': taskType?.name,
      'maxTokens': maximumOutputTokens,
      'thinkingEnabled': baseParams.enableThinking,
      'reasoningEffort': baseParams.reasoningEffort,
      'contentCharsBefore': _streamingContent.length,
      'reasoningCharsBefore': _reasoningContent.length,
    };
    GenerationDiagnostics.instance.mark('[ChatTurn][STAGE_START]', trace);
    if (GenerationDiagnostics.enabled) {
      GenerationDiagnostics.instance.mark('[PromptTrace]', {
        ...trace,
        'count': messages.length,
        'roles': messages.map((m) => m['role']).toList(),
        'lengths': messages.map((m) => (m['content'] ?? '').length).toList(),
        'hashes': messages
            .map((m) => ContentHasher.hashString(m['content'] ?? ''))
            .toList(),
        'historyItems': _promptBuilder.lastHistoryItems,
        'historyCount': _promptBuilder.lastHistoryItems.length,
        'currentInputCount': _promptBuilder.lastCurrentInputCount,
        'round': _promptBuilder.lastRound,
      });
    }
    var acceptedContent = false;
    var acceptedReasoning = false;
    final LLMStreamResult result;
    try {
      result = await _host.llmService.sendMessageStreamDetailed(
        messages,
        (chunk) {
          if (onChunk != null) {
            onChunk(chunk);
            acceptedContent = acceptedContent || chunk.isNotEmpty;
          }
        },
        () {},
        onReasoningChunk: onReasoningChunk == null
            ? null
            : (chunk) {
                onReasoningChunk(chunk);
                acceptedReasoning = acceptedReasoning || chunk.isNotEmpty;
              },
        params: baseParams.copyWith(
          maxTokens: maximumOutputTokens,
        ),
        taskHandle: taskHandle?.forRequest(requestId),
      );
    } catch (error, stack) {
      GenerationDiagnostics.instance.mark('[ChatTurn][STAGE_FAILED]', {
        ...trace,
        'runtimeType': error.runtimeType.toString(),
        'failureClass': ChatFailureClass.classify(error).name,
        'acceptedContent': acceptedContent,
        'acceptedReasoning': acceptedReasoning,
        'contentChars': _streamingContent.length,
        'reasoningChars': _reasoningContent.length,
        'stackTrace': stack,
      });
      rethrow;
    }
    GenerationDiagnostics.instance.mark('[ChatTurn][STAGE_DONE]', {
      ...trace,
      'contentChars': result.content.length,
      'reasoningChars': result.reasoningContent?.length ?? 0,
      'responseCompleted': result.responseCompleted,
      'finishReason': result.finishReason.stableValue,
      'completionTokens': result.completionTokens,
    });
    if (taskType == ContextTaskType.adventureResponse &&
        ReasoningOnlyResponseException.matches(result)) {
      throw ReasoningOnlyResponseException(result);
    }
    final content = result.content;
    final trimmed = content.trim();
    final isNormalComplete =
        result.responseCompleted && result.finishReason.allowsParsing;

    if (isNormalComplete &&
        trimmed.isEmpty &&
        taskType == ContextTaskType.adventureResponse) {
      GenerationDiagnostics.instance.mark('[ChatTurn][STAGE_FAILED]', {
        ...trace,
        'failureClass': 'contentInvalid',
        'finishReason': result.finishReason.stableValue,
        'contentChars': 0,
        'reasoningChars': result.reasoningContent?.length ?? 0
      });
      throw const FormatException('Narrative response is empty');
    }

    if (!isNormalComplete) {
      // 1. 显式允许部分结果（如分幕流水线），明确触及输出上限且生成有效字符（>=50字）才可平滑接力
      final isOutputLimit = result.responseCompleted &&
          (result.finishReason == LLMFinishReason.length ||
              result.finishReason == LLMFinishReason.maxTokens);
      if (allowPartial && isOutputLimit && trimmed.length >= 50) {
        debugPrint(
            '[ChatEngine] _executeAdventureContext: 分阶段流水线已产出 ${trimmed.length} 字有效正文，继续后续接力 (finishReason: ${result.finishReason.stableValue})');
        return ContextExecutionResult(
          content: content,
          reasoningContent: result.reasoningContent,
          finishReason: result.finishReason,
        );
      }

      // 2. 正文叙事任务：若已产生实质性长文本（>=100字），即使被明确的输出上限截断，
      // 也不抛异常抹除用户屏幕上的内容，而是交付下游由 _applySplitResponse 和 _repairMissingOptions 兜底修复选项和状态
      if (taskType == ContextTaskType.adventureResponse &&
          isOutputLimit &&
          trimmed.length >= 100) {
        debugPrint(
            '[ChatEngine] _executeAdventureContext: 叙事正文已产出 ${trimmed.length} 字，转入下游容错与自动选项修复 (finishReason: ${result.finishReason.stableValue})');
        return ContextExecutionResult(
          content: content,
          reasoningContent: result.reasoningContent,
          finishReason: result.finishReason,
        );
      }

      GenerationDiagnostics.instance.mark('[ChatTurn][STAGE_FAILED]', {
        ...trace,
        'failureClass': 'protocolIncomplete',
        'finishReason': result.finishReason.stableValue,
        'responseCompleted': result.responseCompleted,
        'contentChars': content.length,
        'reasoningChars': result.reasoningContent?.length ?? 0
      });
      throw LLMResponseIncompleteException(result);
    }

    return ContextExecutionResult(
      content: result.content,
      reasoningContent: result.reasoningContent,
      finishReason: result.finishReason,
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
          '二选一，不得同时做：\n'
          'A. 若本幕已经到达需要玩家决定、回应或行动的位置：在正文最后一行单独输出 `---等待玩家---` 并停笔，'
          '不要输出 `---JSON---`、选项或状态（系统会独立结算）。\n'
          'B. 若剧情仍在继续：收束本幕后立即输出一行分隔符 `---JSON---`，然后紧跟一行合法 JSON。\n'
          '⚠️ 【状态结算强制要求（仅分支 B）】：JSON 必须包含 options 数组与 custom_status_evaluations（逐项评估每个被追踪状态，changed=false 也要列出）。$statusHint';
    }
    if (stage == 1) {
      return '【分幕流水线·第 1 幕（入境与展开）指令】：\n'
          '本轮为长篇叙事的首发阶段。请展开饱满叙事：环境渲染、角色反应、心理与对白细节（$rangeNote）。\n'
          '只推进一个叙事节拍，不得替玩家行动、不得跨越时间，也不得引出后续事件链。\n'
          '若已经到达需要玩家决定或行动的位置，在正文最后一行单独输出 `---等待玩家---` 并停笔，本幕即为终幕。\n'
          '本幕叙事正文控制在约 $stageCharTarget 纯汉字以内，不要超出。\n'
          '⚠️ 严禁提前草率收束！绝对严禁输出 ---JSON--- 及任何选项或状态数据！写满后直接以正文停笔。';
    }
    return '【分幕流水线·第 $stage 幕（续写）指令】：\n'
        '前 ${stage - 1} 幕已推进 $currentChars 纯汉字（$rangeNote）。\n'
        '请紧接上文继续充实同一个叙事节拍，本幕叙事正文控制在约 $stageCharTarget 纯汉字以内，不要超出。\n'
        '只允许扩充环境、心理、对白细节与瞬时信息密度，不得增加事件数量、时间跨度或推进到结局。\n'
        '若已经到达需要玩家决定或行动的位置，在正文最后一行单独输出 `---等待玩家---` 并停笔，本幕即为终幕。\n'
        '⚠️ 严禁输出 ---JSON--- 及任何选项或状态数据！写满后直接以正文停笔。';
  }

  bool _ownsRequestContext(String requestId, int? adventureId, int branchId) =>
      !_disposed &&
      _activeRequestId == requestId &&
      _host.currentAdventureId == adventureId &&
      _host.currentBranchId == branchId;

  bool _isRequestCurrent(
    String requestId,
    int generation,
    int? adventureId,
    int branchId,
  ) =>
      _ownsRequestContext(requestId, adventureId, branchId) &&
      !_cancelRequested &&
      _generation == generation &&
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

  /// Rewrites options and the validated per-turn status through one protocol
  /// authority. An explicitly empty snapshot removes all model status echoes.
  String _rewriteAssistantPresentationPayload(String content,
      {List<String>? options,
      AdventureConfig? config,
      List<Map<String, dynamic>>? statusSnapshot}) {
    final customStatus = statusSnapshot ?? _legacyCustomStatusMaps(config);
    final scene = _host.gameState.currentScene.trim();
    final parsed = AdventureResponse.parse(content);
    final existingScene = parsed.payload?['scene']?.toString().trim() ?? '';
    final rewritten = AdventureResponse.rewritePayload(
      content,
      defaults: options == null
          ? const {}
          : {
              'hp': _host.gameState.hp,
              'max_hp': _host.gameState.maxHp,
              'energy': _host.gameState.energy,
              'max_energy': _host.gameState.maxEnergy,
              'gold': _host.gameState.gold,
              'inventory': List<String>.from(_host.gameState.inventory),
            },
      replacements: {
        if (options != null) ...{
          'options': options,
          'scene': scene.isNotEmpty
              ? scene
              : (existingScene.isNotEmpty ? existingScene : '当前场景'),
        },
        if (customStatus.isNotEmpty) 'custom_status': customStatus,
      },
      removals: const [
        'custom_status',
        'custom_attributes',
        'custom_status_changes',
        'custom_status_evaluations',
      ],
    );
    GenerationDiagnostics.instance.mark('[AssistantPayloadRewrite]', {
      'inputKind': parsed.kind.name,
      'inputHasSeparator': AdventureResponse.separatorPattern.hasMatch(content),
      'options': options?.length ?? 0,
      'customStatus': customStatus.length,
    });
    return rewritten;
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
      content: AppEventCodec.encode(
          const AppEvent(code: AppEventCode.restRecovered)),
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
          quickMode: _host.quickMode,
          // ADR-0003: the effective elastic percent is frozen here, at turn
          // start. Every later consumer (prompt, multi-stage loop, length
          // guard, overflow convergence) reads this snapshot, so a mid-turn
          // settings change can never reshape an in-flight turn.
          elasticPercent: _host.effectiveGenerationElasticPercent),
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
    _consecutiveDecisionStops = 0;
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
    GenerationDiagnostics.instance
        .mark('[ChatEngine][DISPOSE]', {'engine': identityHashCode(this)});
    _disposed = true;
    _generation++;
    _activeTaskHandle?.cancel();
    _typewriter.cancel();
    _streamNotifier.dispose();
    _reasoningStreamNotifier.dispose();
    _isThinkingNotifier.dispose();
  }
}

/// Identity and durability flags for one scene turn.
///
/// Mutable fields exist only for the two facts that must survive every phase:
/// whether the database accepted the turn, and whether memory was re-synced
/// from that durable result. All other stage data travels in typed results.
final class _TurnExecutionContext {
  _TurnExecutionContext({
    required this.content,
    required this.requestId,
    required this.generation,
    required this.adventureId,
    required this.branchId,
  });

  final String content;
  final String requestId;
  final int generation;
  final int? adventureId;
  final int branchId;

  /// True only after `commitSceneDialogueTurn` returned durably.
  bool turnCommitted = false;

  /// True once the committed result was applied back into host memory.
  bool memoryReconciled = false;

  SceneDialogueCommitResult? committedResult;
  Message? committedAssistantMessage;

  /// Multi-stage prose completed so far; used by the failure path to keep a
  /// partially generated narrative visible.
  String completedNarrativePrefix = '';

  bool isCurrent(ChatEngine engine) =>
      engine._isRequestCurrent(requestId, generation, adventureId, branchId);

  bool owns(ChatEngine engine) =>
      engine._ownsRequestContext(requestId, adventureId, branchId);
}

final class _NarrativeRunResult {
  const _NarrativeRunResult({
    required this.json,
    required this.reasoning,
    required this.playerStopRequested,
    required this.lengthGuardBaseMessages,
  });

  final String json;
  final String reasoning;
  final bool playerStopRequested;
  final List<Map<String, String>> lengthGuardBaseMessages;
}

final class _FinalizedNarrative {
  const _FinalizedNarrative({
    required this.json,
    required this.finalNarrative,
    required this.reasoning,
    required this.lengthGuard,
  });

  final String json;
  final String finalNarrative;
  final String reasoning;
  final NarrativeLengthGuardResult lengthGuard;
}

final class _SettlementPhaseResult {
  const _SettlementPhaseResult({
    required this.outcome,
    required this.optionsFromSettlement,
    required this.assistantMessage,
    required this.candidates,
    required this.continuity,
    required this.narrativeChineseChars,
  });

  final _SettlementOutcome outcome;
  final bool optionsFromSettlement;
  final Message assistantMessage;
  final List<SceneSettingCandidate> candidates;
  final SceneConsistencyResult continuity;
  final int narrativeChineseChars;
}

final class _TurnCommitPlan {
  const _TurnCommitPlan({
    required this.commit,
    required this.inMemoryResult,
    required this.assistantMessage,
    required this.settledConfig,
    required this.statusSnapshot,
    required this.lengthVerdict,
    required this.lengthPassed,
    required this.narrativeChineseChars,
    required this.runtimeRevision,
  });

  /// Null when the turn has no persisted adventure (in-memory preview).
  final SceneDialogueCommit? commit;
  final SceneDialogueCommitResult inMemoryResult;
  final Message assistantMessage;
  final AdventureConfig? settledConfig;
  final List<Map<String, dynamic>>? statusSnapshot;
  final NarrativeLengthVerdict lengthVerdict;
  final bool lengthPassed;
  final int narrativeChineseChars;
  final int runtimeRevision;
}
