import 'dart:async';

import '../../../../application/resources/section_regeneration.dart';
import '../../../../application/resources/streaming_generation_session_repository.dart';
import '../../../../controllers/streaming_resource_generation_controller.dart';
import '../../../../domain/resources/section_generation_binding.dart';
import '../../../../domain/resources/streaming_generation_runtime_contracts.dart';

/// Production adapter exposing the shared streaming controller as the narrow
/// [SectionRegenerationRuntimePort] the executor consumes.
///
/// It deliberately forwards to the controller the Studio already listens to:
/// one generation service, one event stream, one set of Phase 5 tasks.
final class StreamingRegenerationRuntimeAdapter
    implements SectionRegenerationRuntimePort {
  StreamingRegenerationRuntimeAdapter({
    required StreamingResourceGenerationController controller,
    required IStreamingGenerationSessionRepository sessionRepository,
  })  : _controller = controller,
        _sessionRepository = sessionRepository;

  final StreamingResourceGenerationController _controller;
  final IStreamingGenerationSessionRepository _sessionRepository;

  @override
  Stream<GenerationRuntimeEvent> get events => _controller.events;

  @override
  Future<String?> latestSessionIdForResource(String resourceId) async {
    final session =
        await _sessionRepository.findLatestSessionForResource(resourceId);
    return session?.sessionId;
  }

  @override
  Future<bool> retryPart({
    required String sessionId,
    required String partId,
  }) =>
      _controller.retryPart(sessionId: sessionId, partId: partId);
}

/// Production [SectionRegenerationExecutor].
///
/// Delegates to the Phase 5 streaming runtime through
/// [SectionRegenerationRuntimePort]: one Part is retried via `retryPart`, which
/// owns the incremental patch protocol, attempt tokens, validation and commit.
/// None of that is re-implemented here.
///
/// While the Part runs, this executor observes the runtime event stream and
/// validates every incremental patch against a [SectionGenerationBinding]
/// built from the part being regenerated. A patch carrying another section,
/// resource or part is therefore rejected at the section boundary as well as
/// inside the Phase 5 accumulator — Phase 7 never accepts cross-section
/// content.
///
/// Generation identity: the runtime reports the *session* id in
/// `GenerationRuntimeEvent.generationId`, while each patch carries the Phase 5
/// *protocol* generation id minted per attempt. The binding is therefore seeded
/// from the first patch and then pinned: every later patch of the same run must
/// carry that protocol id, so a late patch from a superseded generation is
/// still rejected. Resource, section and part are checked against the request
/// on every patch.
final class StreamingSectionRegenerationExecutor
    implements SectionRegenerationExecutor {
  StreamingSectionRegenerationExecutor({
    required SectionRegenerationRuntimePort runtime,
  }) : _runtime = runtime;

  final SectionRegenerationRuntimePort _runtime;

  @override
  Future<SectionRegenerationOutcome> regenerate(
    SectionRegenerationRequest request,
  ) async {
    final sessionId = await _runtime.latestSessionIdForResource(
      request.resourceId.value,
    );
    if (sessionId == null) {
      return SectionRegenerationOutcome(
        resourceId: request.resourceId,
        sectionId: request.sectionId,
        partId: request.partId,
        generationId: '',
        success: false,
        errorMessage: '未找到该资源的生成会话，无法重新生成',
      );
    }

    String? protocolGenerationId;
    SectionGenerationBinding? binding;
    String? bindingError;
    var characterCount = 0;

    final subscription = _runtime.events.listen((event) {
      if (event.resourceId != request.resourceId) return;

      if (event is PatchReceived && event.partId == request.partId) {
        // Seed from the patch, then require the same protocol generation for
        // the rest of the run (see the class documentation).
        final runGenerationId =
            protocolGenerationId ?? event.patch.generationId;
        protocolGenerationId = runGenerationId;
        binding ??= SectionGenerationBinding(
          generationId: runGenerationId,
          resourceId: request.resourceId,
          sectionId: request.sectionId,
          partId: request.partId,
        );
        try {
          binding!.validatePatch(event.patch);
        } on SectionGenerationBindingException catch (error) {
          // Keep the first mismatch: the run is reported as failed even if the
          // underlying runtime later manages to commit something.
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
      success = await _runtime.retryPart(
        sessionId: sessionId,
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
          success ? '' : (errorMessage.isEmpty ? '段落生成未完成' : errorMessage),
    );
  }
}
