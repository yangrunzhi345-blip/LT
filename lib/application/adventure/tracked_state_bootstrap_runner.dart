import 'package:flutter/foundation.dart';

import '../../models/adventure_config.dart';
import '../../models/adventure_runtime_state.dart';
import '../../models/completion_params.dart';
import '../../models/model_capabilities.dart';
import '../../models/scene_state.dart';
import '../../services/llm_service.dart';
import '../../services/repositories/adventure_repository.dart';
import 'adventure_tracked_state_registry.dart';
import 'tracked_state_bootstrap.dart';
import 'tracked_state_candidate_planner.dart';

/// Outcome of one opening bootstrap attempt.
enum TrackedStateBootstrapStatus {
  /// A runtime commit was written (or proposals existed and were committed).
  committed,

  /// Nothing to do (no definitions / no scene / no candidates / no API key),
  /// or the attempt was abandoned because its adventure is no longer current.
  skipped,

  /// The model request or commit failed. The adventure is untouched.
  failed,
}

/// Structured result of [TrackedStateBootstrapRunner.run].
///
/// Deliberately carries no UI. The caller decides what (if anything) to show;
/// by contract the answer is "nothing" — bootstrap is silent.
final class TrackedStateBootstrapResult {
  final TrackedStateBootstrapStatus status;

  /// `no_definitions` / `no_opening_scene` / `no_candidates` /
  /// `api_unavailable` / `abandoned` / `failed_request` / `stale_revision` /
  /// empty.
  final String reason;
  final int candidateCount;
  final int proposalCount;
  final int committedCount;
  final int revisionBefore;
  final int revisionAfter;
  final List<String> diagnostics;

  const TrackedStateBootstrapResult({
    required this.status,
    this.reason = '',
    this.candidateCount = 0,
    this.proposalCount = 0,
    this.committedCount = 0,
    this.revisionBefore = 0,
    this.revisionAfter = 0,
    this.diagnostics = const [],
  });

  bool get didCommit => committedCount > 0;
}

/// Orchestrates one opening-scene bootstrap for tracked state.
///
/// Ownership split (see AGENTS.md and the tracked-state design):
/// * This runner owns the **AI orchestration** — candidate planning, the small
///   auxiliary LLM request, parsing and commit.
/// * The repository stays the **runtime commit authority** (it re-validates
///   through [RuntimeStateValidator]).
/// * `AdventureProvider` owns runtime persistence/cache refresh and must never
///   gain an LLM dependency; the caller refreshes its cache after a commit.
///
/// This is **not** a narrative turn. It never calls `sendMessage`, never writes
/// a `messages` row and never writes a `scene_dialogue_turns` row. It is
/// fail-open: a failure leaves the already-created adventure fully usable.
final class TrackedStateBootstrapRunner {
  final IAdventureRepository repository;
  final LLMService llmService;

  /// Hard output budget for the auxiliary request. The response is a sparse
  /// array of evidenced monitors, never prose.
  static const int maximumOutputTokens = 512;

  const TrackedStateBootstrapRunner({
    required this.repository,
    required this.llmService,
  });

  ModelCapabilities get _capability =>
      ModelCapabilityRegistry.resolve(llmService.config.model);

  /// Stable idempotency key: the same adventure/branch bootstraps at most once.
  ///
  /// Never time-based — a retried opening must not create a second revision.
  static String requestIdFor(int adventureId, int branchId) =>
      'tracked-state-bootstrap:$adventureId:$branchId';

  Future<TrackedStateBootstrapResult> run({
    required int adventureId,
    required int branchId,
    required AdventureConfig config,
    required SceneState sceneState,
    required List<RuntimeEntityState> runtimeEntities,
    Map<String, String>? entityNames,

    /// Re-checked after the model returns; when it reports the adventure is no
    /// longer current, the response is discarded instead of written.
    bool Function()? isStillCurrent,
  }) async {
    if (config.trackedStateDefinitions.isEmpty) {
      return _log(const TrackedStateBootstrapResult(
        status: TrackedStateBootstrapStatus.skipped,
        reason: 'no_definitions',
      ));
    }
    final openingScene = config.effectiveOpeningScene.trim();
    if (openingScene.isEmpty) {
      return _log(const TrackedStateBootstrapResult(
        status: TrackedStateBootstrapStatus.skipped,
        reason: 'no_opening_scene',
      ));
    }
    if (llmService.config.apiKey.trim().isEmpty) {
      // Missing credentials never turns an already-created adventure into a
      // half-built failure; bootstrap simply does not run.
      return _log(const TrackedStateBootstrapResult(
        status: TrackedStateBootstrapStatus.skipped,
        reason: 'api_unavailable',
      ));
    }

    final names =
        entityNames ?? AdventureTrackedStateRegistry.entityDisplayNames(config);
    final candidates = TrackedStateBootstrap.candidatesFor(
      config: config,
      runtimeEntities: runtimeEntities,
      presentEntityIds: presentEntityIds(config, sceneState),
      entityNames: names,
    );
    if (candidates.isEmpty) {
      return _log(const TrackedStateBootstrapResult(
        status: TrackedStateBootstrapStatus.skipped,
        reason: 'no_candidates',
      ));
    }

    final head = await repository.getRuntimeHead(adventureId, branchId);
    final revisionBefore = head.revision;
    debugPrint('[TrackedStateBootstrap][START] '
        '{adventureId: $adventureId, branchId: $branchId, '
        'candidateCount: ${candidates.length}, runtimeRevision: $revisionBefore}');

    final diagnostics = <String>[];
    final String content;
    try {
      content = await _request(openingScene, candidates);
    } catch (error) {
      final result = TrackedStateBootstrapResult(
        status: TrackedStateBootstrapStatus.failed,
        reason: 'failed_request',
        candidateCount: candidates.length,
        revisionBefore: revisionBefore,
        revisionAfter: revisionBefore,
        diagnostics: ['tracked_state_bootstrap:failed:${error.runtimeType}'],
      );
      return _log(_failed('failed_request', error, result));
    }

    if (isStillCurrent != null && !isStillCurrent()) {
      return _log(TrackedStateBootstrapResult(
        status: TrackedStateBootstrapStatus.skipped,
        reason: 'abandoned',
        candidateCount: candidates.length,
        revisionBefore: revisionBefore,
        diagnostics: const ['tracked_state_bootstrap:abandoned'],
      ));
    }

    final proposals = TrackedStateBootstrap.parse(
      content,
      config: config,
      diagnostics: diagnostics,
    );
    if (proposals.isEmpty) {
      return _log(TrackedStateBootstrapResult(
        status: TrackedStateBootstrapStatus.skipped,
        reason: 'no_evidence',
        candidateCount: candidates.length,
        revisionBefore: revisionBefore,
        revisionAfter: revisionBefore,
        diagnostics: List.unmodifiable(diagnostics),
      ));
    }

    try {
      final result = await repository.commitRuntimeMutation(
        RuntimeStateMutation(
          requestId: requestIdFor(adventureId, branchId),
          adventureId: adventureId,
          branchId: branchId,
          draft: RuntimeStateCommitDraft(
            expectedRevision: revisionBefore,
            changes: proposals,
            summary: 'Opening tracked state bootstrap',
            source: RuntimeEventSource.systemRule,
            causeType: 'opening_bootstrap',
          ),
          causeType: 'opening_bootstrap',
        ),
      );
      final committed = result.revision > revisionBefore ? proposals.length : 0;
      final outcome = TrackedStateBootstrapResult(
        status: TrackedStateBootstrapStatus.committed,
        candidateCount: candidates.length,
        proposalCount: proposals.length,
        committedCount: committed,
        revisionBefore: revisionBefore,
        revisionAfter: result.revision,
        diagnostics: List.unmodifiable(diagnostics),
      );
      debugPrint('[TrackedStateBootstrap][DONE] '
          '{adventureId: $adventureId, candidateCount: ${candidates.length}, '
          'parsedCount: ${proposals.length}, committedCount: $committed, '
          'revisionBefore: $revisionBefore, revisionAfter: ${result.revision}}');
      return outcome;
    } on RuntimeHeadConflict catch (error) {
      // A stale revision means the opening output targets a runtime snapshot
      // that no longer exists. Never replay old output onto a new revision.
      return _log(_failed(
          'stale_revision',
          error,
          TrackedStateBootstrapResult(
            status: TrackedStateBootstrapStatus.failed,
            reason: 'stale_revision',
            candidateCount: candidates.length,
            proposalCount: proposals.length,
            revisionBefore: revisionBefore,
            revisionAfter: revisionBefore,
            diagnostics: const ['tracked_state_bootstrap:stale_revision'],
          )));
    } catch (error) {
      return _log(_failed(
          'failed_commit',
          error,
          TrackedStateBootstrapResult(
            status: TrackedStateBootstrapStatus.failed,
            reason: 'failed_commit',
            candidateCount: candidates.length,
            proposalCount: proposals.length,
            revisionBefore: revisionBefore,
            revisionAfter: revisionBefore,
            diagnostics: [
              'tracked_state_bootstrap:failed:${error.runtimeType}'
            ],
          )));
    }
  }

  /// Scene presence resolved to stable ids, exactly like settlement.
  ///
  /// The scene stores the literal `protagonist` for the player character; it is
  /// normalized to the stable id. World candidates are added by the planner,
  /// so no per-entity-type logic is duplicated here.
  static Set<String> presentEntityIds(
    AdventureConfig config,
    SceneState sceneState,
  ) {
    final present = sceneState.presentCharacterIds.toSet();
    final protagonistId =
        AdventureTrackedStateRegistry.protagonistEntityId(config);
    if (present.remove('protagonist')) present.add(protagonistId);
    return present;
  }

  Future<String> _request(
    String openingScene,
    List<TrackedStateCandidate> candidates,
  ) async {
    final messages = TrackedStateBootstrap.buildMessages(
      openingScene: openingScene,
      candidates: candidates,
    );
    final capability = _capability;
    final params = CompletionParams(
      temperature: 0.1,
      topP: 0.8,
      maxTokens: maximumOutputTokens < capability.maximumOutputTokens
          ? maximumOutputTokens
          : capability.maximumOutputTokens,
      enableThinking: false,
      responseFormat:
          capability.supportsJsonOutput ? const {'type': 'json_object'} : null,
    );
    final result = await llmService.sendMessageStreamDetailed(
      messages,
      (_) {},
      () {},
      params: params,
    );
    if (!result.responseCompleted ||
        !result.finishReason.allowsParsing ||
        result.finishReason.isTruncated) {
      throw LLMResponseIncompleteException(result);
    }
    return result.content;
  }

  TrackedStateBootstrapResult _log(TrackedStateBootstrapResult result) {
    if (result.status == TrackedStateBootstrapStatus.skipped) {
      debugPrint('[TrackedStateBootstrap][SKIP] '
          '{reason: ${result.reason}, '
          'candidateCount: ${result.candidateCount}}');
    }
    return result;
  }

  TrackedStateBootstrapResult _failed(
    String failureClass,
    Object error,
    TrackedStateBootstrapResult result,
  ) {
    debugPrint('[TrackedStateBootstrap][FAILED] '
        '{failureClass: $failureClass, runtimeType: ${error.runtimeType}}');
    return result;
  }
}
