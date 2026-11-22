import '../../domain/resources/resource_contracts.dart';

/// Readiness value types kept after the assembly pipeline retired.
///
/// The card-backed library has no assembly revisions to prepare, but the
/// adventure start gate still returns a typed preparation outcome, so the
/// smallest stable value types live here instead of pulling the deleted
/// coordinator / repository back in.

/// Outcome of one preparation run.
final class AssemblyPrepareOutcome {
  const AssemblyPrepareOutcome({
    required this.record,
    this.awaitedCompression = false,
    this.published = false,
    this.superseded = false,
  });

  /// The readiness row as of the end of the run.
  final AssemblyReadinessRecord record;

  /// True when the head was waiting for compression.
  final bool awaitedCompression;

  /// True when this run published an assembly revision and reached `ready`.
  final bool published;

  /// True when the head moved while this run was working.
  final bool superseded;
}

/// Persisted readiness of one resource.
///
/// Only the fields kept code reads survive: identity, state and the last
/// published assembly revision (plus the last failure message).
final class AssemblyReadinessRecord {
  const AssemblyReadinessRecord({
    required this.resourceId,
    required this.state,
    this.assemblyRevisionId = '',
    this.assemblyContentHash = '',
    this.validationMessage = '',
    this.failureReason = '',
  });

  final String resourceId;
  final ReadinessState state;

  /// The assembly revision that is currently consumable, when one exists.
  final String assemblyRevisionId;
  final String assemblyContentHash;

  /// Human-readable progress note.
  final String validationMessage;

  /// Why the last run failed; empty when not failed.
  final String failureReason;

  bool get hasAssemblyRevision => assemblyRevisionId.isNotEmpty;
}
