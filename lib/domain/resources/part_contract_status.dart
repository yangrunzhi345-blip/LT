import 'content_requirements.dart';
import 'resource_blueprint.dart';

/// U6-D: the read-only content-contract status of one Part, used to show a
/// non-destructive legacy review hint without inventing a contract.
///
/// The status is derived ONLY from authoritative evidence:
/// - the resource's own creation metadata (`authoring_method` +
///   `creation_session_id`), and
/// - the Part's contract on its confirmed blueprint.
///
/// It is never inferred from "no generation task", "the body is short", or
/// "the blueprint is missing" — those are explicitly not evidence of legacy.
enum PartContractStatus {
  /// The Part carries a confirmed [ContentRequirements] contract.
  confirmedContract,

  /// An authoritative historical AI blueprint exists and this Part's contract
  /// is null: a pre-U6 plan that predates content contracts. This is the ONLY
  /// status that shows the legacy review hint.
  legacyUnknownContract,

  /// A manually created or imported resource: not a U6 generation task, so no
  /// contract is expected and nothing is flagged.
  notApplicable,

  /// The association cannot be reliably confirmed (missing blueprint, unknown
  /// authoring method, or a Part absent from the blueprint). Fail-quiet: no
  /// hint, because an unreliable association must not be presented as legacy.
  unavailable,
}

/// Pure projection of per-Part contract status. No I/O, no inference.
abstract final class PartContractProjection {
  /// Whether the resource was produced by the AI reference pipeline, judged from
  /// its own persisted creation metadata (never from task presence or length).
  static bool isAiCreatedResource({
    required String? authoringMethod,
    required String? creationSessionId,
  }) =>
      authoringMethod == 'aiReference' &&
      creationSessionId != null &&
      creationSessionId.trim().isNotEmpty;

  /// Projects [partIds] (full Part ids, e.g. `res_x_part_1`) to their status.
  ///
  /// [confirmedBlueprint] must be the resource's confirmed blueprint, or null
  /// when it cannot be loaded. A non-AI resource is [notApplicable] regardless.
  static Map<String, PartContractStatus> project({
    required bool isAiResource,
    required ResourceBlueprint? confirmedBlueprint,
    required String resourceId,
    required Iterable<String> partIds,
  }) {
    final result = <String, PartContractStatus>{};
    if (!isAiResource) {
      for (final id in partIds) {
        result[id] = PartContractStatus.notApplicable;
      }
      return result;
    }
    if (confirmedBlueprint == null) {
      for (final id in partIds) {
        result[id] = PartContractStatus.unavailable;
      }
      return result;
    }
    final prefix = '${resourceId}_';
    for (final id in partIds) {
      final rawId = id.startsWith(prefix) ? id.substring(prefix.length) : id;
      final part = confirmedBlueprint.findPart(rawId);
      result[id] = part == null
          ? PartContractStatus.unavailable
          : (part.contentRequirements != null
              ? PartContractStatus.confirmedContract
              : PartContractStatus.legacyUnknownContract);
    }
    return result;
  }
}
