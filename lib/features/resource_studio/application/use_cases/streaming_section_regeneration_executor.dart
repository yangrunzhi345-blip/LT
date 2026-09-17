import 'dart:async';

import '../../../../application/resources/section_regeneration.dart';
import '../../../../application/resources/streaming_generation_session_repository.dart';
import '../../../../controllers/streaming_resource_generation_controller.dart';
import '../../../../domain/resources/section_generation_binding.dart';
import '../../../../domain/resources/streaming_generation_runtime_contracts.dart';

/// Production [SectionRegenerationExecutor].
///
/// Delegates to the existing Phase 5 streaming runtime: one Part is retried
/// through [StreamingResourceGenerationController.retryPart], which owns the
/// incremental patch protocol, attempt tokens, validation and commit. None of
/// that is re-implemented here.
///
/// While the Part runs, this executor observes the runtime event stream and
/// validates every incremental patch against a [SectionGenerationBinding]
/// built from the part being regenerated. A patch carrying another section's
/// id is therefore rejected at the section boundary as well as inside the
/// Phase 5 accumulator — Phase 7 never accepts cross-section content.
final class StreamingSectionRegenerationExecutor
    implements SectionRegenerationExecutor {
  StreamingSectionRegenerationExecutor({
    required StreamingResourceGenerationController controller,
    required IStreamingGenerationSessionRepository sessionRepository,
  })  : _controller = controller,
        _sessionRepository = sessionRepository;

  final StreamingResourceGenerationController _controller;
  final IStreamingGenerationSessionRepository _sessionRepository;

  @override
  Future<SectionRegenerationOutcome> regenerate(
    SectionRegenerationRequest request,
  ) async {
    final session = await _sessionRepository.findLatestSessionForResource(
      request.resourceId.value,
    );
    if (session == null) {
      return SectionRegenerationOutcome(
        resourceId: request.resourceId,
        sectionId: request.sectionId,
        partId: request.partId,
        generationId: '',
        success: false,
        errorMessage: '未找到资源 ${request.resourceId.value} 的生成会话，无法重新生成',
      );
    }

    String? protocolGenerationId;
    SectionGenerationBinding? binding;
    String? bindingError;
    var characterCount = 0;

    final subscription = _controller.events.listen((event) {
      if (event.resourceId != request.resourceId) return;

      if (event is PartStarted && event.partId == request.partId) {
        protocolGenerationId = event.generationId;
        binding = SectionGenerationBinding(
          generationId: event.generationId,
          resourceId: request.resourceId,
          sectionId: request.sectionId,
          partId: request.partId,
        );
        return;
      }

      if (event is PatchReceived && event.partId == request.partId) {
        protocolGenerationId ??= event.generationId;
        binding ??= SectionGenerationBinding(
          generationId: event.generationId,
          resourceId: request.resourceId,
          sectionId: request.sectionId,
          partId: request.partId,
        );
        try {
          binding!.validatePatch(event.patch);
        } on SectionGenerationBindingException catch (error) {
          // Keep the first mismatch: the run will be reported as failed even
          // if the underlying runtime later manages to commit something.
          bindingError ??= error.toString();
        }
        return;
      }

      if (event is PartCompleted && event.partId == request.partId) {
        characterCount = event.characterCount;
      }
    });

    var success = false;
    var errorMessage = '';
    try {
      success = await _controller.retryPart(
        sessionId: session.sessionId,
        partId: request.partId.value,
      );
    } catch (error) {
      success = false;
      errorMessage = error.toString();
    } finally {
      await subscription.cancel();
    }

    final mismatch = bindingError;
    if (mismatch != null) {
      return SectionRegenerationOutcome(
        resourceId: request.resourceId,
        sectionId: request.sectionId,
        partId: request.partId,
        generationId: protocolGenerationId ?? '',
        success: false,
        characterCount: characterCount,
        errorMessage: mismatch,
      );
    }

    return SectionRegenerationOutcome(
      resourceId: request.resourceId,
      sectionId: request.sectionId,
      partId: request.partId,
      generationId: protocolGenerationId ?? '',
      success: success,
      characterCount: characterCount,
      errorMessage:
          success ? '' : (errorMessage.isEmpty ? 'Part 生成未完成' : errorMessage),
    );
  }
}
