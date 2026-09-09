/// How an asset's factual content was authored.
enum ResourceAuthoringMethod { manual, aiReference }

/// The explicit generation pipeline used for AI-assisted authoring.
enum AiGenerationDepth { simple, detailed }

/// Management metadata describing where an asset came from.
///
/// This metadata is stored beside asset content and must not be injected into
/// narrative prompts as character or worldview facts.
class ResourceProvenance {
  final ResourceAuthoringMethod method;
  final AiGenerationDepth? aiDepth;
  final String originWorldviewId;

  const ResourceProvenance({
    required this.method,
    this.aiDepth,
    this.originWorldviewId = '',
  }) : assert(
          method == ResourceAuthoringMethod.aiReference || aiDepth == null,
          'Manual resources cannot have an AI generation depth.',
        );

  String get methodStorageValue => method.name;
  String get aiDepthStorageValue => aiDepth?.name ?? '';
}
