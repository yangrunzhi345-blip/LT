import '../../domain/resources/resource_contracts.dart';
import '../../domain/resources/streaming_generation_runtime_contracts.dart';
import '../../services/repositories/resource_tree_repository.dart';
import 'assembly_readiness_coordinator.dart';
import 'assembly_readiness_repository.dart';
import 'resource_lifecycle_projection.dart';

/// Whether [error] is a per-resource data fault that can be isolated into a
/// terminal `failed` snapshot.
///
/// Only "this stored resource cannot be projected" failures qualify: an
/// unmappable tree row, an unknown readiness/generation status, or a domain
/// contract violation while decoding stored rows. Everything else — a database
/// failure, a repository that is unavailable, or an invariant violation — is
/// **not** isolatable and must propagate so a genuinely broken library is never
/// masked as a collection of failed rows.
bool isIsolatableLifecycleReadError(Object error) {
  if (error is ResourceStateTransitionException) return false;
  return error is ResourceTreeCorruptedException ||
      error is ResourceContractException ||
      error is AssemblyReadinessException;
}

/// Read-side convergence of the resource lifecycle.
///
/// The projection alone can only *report* a non-ready state; it can never move
/// one. A generation session that reached `completed` but whose assembly
/// readiness row is missing (e.g. the completion hook was skipped, the app was
/// killed before preparation ran, or the resource predates the hook) or `stale`
/// therefore renders as the pending「质量校验中」state forever — there is no
/// active validator and nothing will ever converge it.
///
/// This boundary reuses the existing [AssemblyReadinessCoordinator] as the one
/// validation/readiness authority:
/// - if a preparation is already running it is awaited (coalesced), never
///   duplicated;
/// - if generation completed and readiness is missing/stale it runs one
///   preparation (single-flight + idempotent CAS in the coordinator);
/// - a `failed` readiness is a terminal state and is left for the explicit
///   revalidate action rather than retried on every read.
///
/// It never manufactures a `ready` state: the terminal state always comes from
/// a real preparation run persisted by the coordinator.
final class ResourceLifecycleReconciler {
  const ResourceLifecycleReconciler({
    required ResourceLifecycleProjection projection,
    required AssemblyReadinessCoordinator readiness,
  })  : _projection = projection,
        _readiness = readiness;

  final ResourceLifecycleProjection _projection;
  final AssemblyReadinessCoordinator _readiness;

  /// Reads the lifecycle, converging a stuck post-generation state first.
  ///
  /// The read is fault-isolated: a per-resource projection failure (a corrupt
  /// or legacy-incompatible row) yields a terminal `failed` snapshot instead of
  /// throwing, while a database/repository failure still propagates so a
  /// genuinely unreadable library surfaces as an error rather than silently
  /// hiding resources.
  Future<ResourceLifecycleProjectionResult> read(ResourceId resourceId) async {
    // Coalesce with an already running preparation instead of racing it. The
    // run owns the CAS token, so awaiting it yields the persisted terminal
    // state without a second validator.
    final pending = _readiness.pendingPreparation(resourceId.value);
    if (pending != null) {
      await _ignoreFailure(pending);
      return _readOrFailed(resourceId);
    }

    final result = await _readOrFailed(resourceId);
    if (!needsPreparation(result)) return result;

    await _prepare(resourceId);
    return _readOrFailed(resourceId);
  }

  /// Reads many resources, converging each before returning.
  Future<List<ResourceLifecycleProjectionResult>> readAll(
    Iterable<ResourceId> resourceIds,
  ) async {
    final results = <ResourceLifecycleProjectionResult>[];
    for (final id in resourceIds) {
      results.add(await read(id));
    }
    return results;
  }

  /// Explicit user revalidation of a resource whose readiness is terminal
  /// (`failed`). Bypasses the "leave failed alone" guard of [read] but goes
  /// through the same authority, so it can only ever persist a real result.
  Future<ResourceLifecycleProjectionResult> revalidate(
    ResourceId resourceId,
  ) async {
    final pending = _readiness.pendingPreparation(resourceId.value);
    if (pending != null) {
      await _ignoreFailure(pending);
    } else {
      await _prepare(resourceId);
    }
    return _readOrFailed(resourceId);
  }

  /// Whether [result] is a stuck post-generation state that needs one
  /// preparation run. Only a completed generation whose readiness is missing
  /// or stale qualifies; `preparing` may be a live run and `failed` is terminal.
  static bool needsPreparation(ResourceLifecycleProjectionResult result) {
    if (result.state != ResourceLifecycleState.validating) return false;
    if (result.generationSession?.status !=
        StreamingLifecycleStatus.completed) {
      return false;
    }
    final readiness = result.assemblyReadiness;
    return readiness == null || readiness.state == ReadinessState.stale;
  }

  Future<void> _prepare(ResourceId resourceId) async {
    try {
      await _readiness.prepare(resourceId);
    } catch (_) {
      // A preparation failure is persisted by the coordinator as a terminal
      // `failed` row; the following projection read reflects it. Never throw
      // into a list/detail read.
    }
  }

  /// Reads the projection, converting a per-resource data fault into a terminal
  /// `failed` snapshot. Database / repository failures and invariant violations
  /// are rethrown so a truly unreadable library is never masked as a row of
  /// failed resources.
  Future<ResourceLifecycleProjectionResult> _readOrFailed(
    ResourceId resourceId,
  ) async {
    try {
      return await _projection.read(resourceId);
    } catch (error) {
      if (!isIsolatableLifecycleReadError(error)) rethrow;
      return ResourceLifecycleProjectionResult(
        resourceId: resourceId,
        state: ResourceLifecycleState.failed,
      );
    }
  }

  static Future<void> _ignoreFailure(Future<Object?> future) async {
    try {
      await future;
    } catch (_) {
      // The persisted row is the authority; the projection re-read decides.
    }
  }
}
