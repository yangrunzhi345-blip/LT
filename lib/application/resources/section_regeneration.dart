/// Port through which Phase 7 triggers section-scoped regeneration.
///
/// The service never talks to the LLM directly and never builds JSON: it asks
/// an executor to re-run exactly one Part's Phase 5 generation task, and the
/// production executor delegates to the existing streaming runtime (which owns
/// the incremental protocol, attempt tokens, cancellation and persistence).
///
/// The port exists so the section-control service stays testable without a
/// gateway and so no second generation path can be introduced by accident.
library;

import '../../domain/resources/resource_contracts.dart';
import '../../domain/resources/resource_edit_command.dart';

/// One Part regeneration to run, resolved from a persisted Phase 5 task.
final class SectionRegenerationRequest {
  const SectionRegenerationRequest({
    required this.resourceId,
    required this.sectionId,
    required this.partId,
    required this.taskId,
    required this.blueprintId,
    required this.mode,
    this.instruction = '',
  });

  final ResourceId resourceId;
  final SectionId sectionId;
  final PartId partId;
  final String taskId;
  final String blueprintId;
  final AiRewriteMode mode;
  final String instruction;

  @override
  String toString() =>
      'SectionRegenerationRequest(part: ${partId.value}, task: $taskId, '
      'mode: ${mode.storageValue})';
}

/// Result of one Part regeneration.
final class SectionRegenerationOutcome {
  const SectionRegenerationOutcome({
    required this.resourceId,
    required this.sectionId,
    required this.partId,
    required this.generationId,
    required this.success,
    this.characterCount = 0,
    this.errorMessage = '',
  });

  final ResourceId resourceId;
  final SectionId sectionId;
  final PartId partId;
  final String generationId;
  final bool success;
  final int characterCount;
  final String errorMessage;

  @override
  String toString() => 'SectionRegenerationOutcome(part: ${partId.value}, '
      'gen: $generationId, success: $success)';
}

/// Executes one section-scoped regeneration through the Phase 5 runtime.
abstract interface class SectionRegenerationExecutor {
  Future<SectionRegenerationOutcome> regenerate(
    SectionRegenerationRequest request,
  );
}
