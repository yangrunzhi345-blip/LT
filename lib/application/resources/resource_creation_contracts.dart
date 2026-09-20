import '../../domain/resources/resource_contracts.dart';
import '../../domain/resources/resource_blueprint.dart';
import '../../domain/resources/resource_limits.dart';
import '../../services/repositories/resource_tree_repository.dart';

final class ResourceStudioCreationDraft {
  const ResourceStudioCreationDraft({
    required this.type,
    required this.name,
    required this.referenceSource,
    required this.targetCharacters,
    this.origin = 'resource-studio',
    this.libraryMode = 'adventure',
    this.idempotencyKey,
    this.targetResourceId,
    this.originWorldviewId = '',
  });

  final ResourceType type;
  final String name;
  final ReferenceSource referenceSource;
  final int targetCharacters;
  final String origin;
  final String libraryMode;
  final String? idempotencyKey;

  /// Existing resource to replace through Blueprint + Runtime generation.
  ///
  /// The orchestrator captures its persisted source token before planning;
  /// Blueprint confirmation rejects the replacement if the resource changes.
  final ResourceId? targetResourceId;

  /// The native/origin worldview for a character or NPC.
  final String originWorldviewId;
}

/// Input shared by every AI resource-creation entry point.
///
/// The caller owns [idempotencyKey]. Reusing it for the same logical submit
/// lets retries and double taps continue the persisted creation instead of
/// allocating another resource.
final class ResourceAiCreationDraft {
  const ResourceAiCreationDraft({
    required this.resourceType,
    required this.name,
    required this.referenceSource,
    required this.targetCharacters,
    required this.idempotencyKey,
    required this.origin,
    required this.libraryMode,
    this.targetResourceId,
    this.originWorldviewId = '',
  });

  final ResourceType resourceType;
  final String name;
  final ReferenceSource referenceSource;
  final int targetCharacters;
  final String idempotencyKey;
  final String origin;
  final String libraryMode;
  final ResourceId? targetResourceId;

  /// The native/origin worldview for a character or NPC.
  final String originWorldviewId;
}

/// Persisted planning result exposed for workflows that review Blueprint Parts
/// before generation starts, such as Scene Batch candidate selection.
final class ResourceAiCreationPlan {
  const ResourceAiCreationPlan({
    required this.creationSessionId,
    required this.blueprint,
  });

  final String creationSessionId;
  final ResourceBlueprint blueprint;
}

/// Stable persisted identities produced by AI creation orchestration.
final class ResourceAiCreationIdentity {
  const ResourceAiCreationIdentity({
    required this.creationSessionId,
    required this.resourceId,
    required this.generationSessionId,
  });

  final String creationSessionId;
  final ResourceId resourceId;
  final String generationSessionId;
}

/// Encodes orchestration-only values in the frozen v44 `origin` column.
///
/// This keeps library mode and existing-resource CAS identity restart-safe
/// without adding an Import-specific table or changing the database schema.
final class ResourceCreationOriginEnvelope {
  const ResourceCreationOriginEnvelope({
    required this.origin,
    required this.libraryMode,
    this.targetResourceId = '',
    this.expectedSourceToken = '',
    this.originWorldviewId = '',
  });

  static const String _separator = '|';
  static const String _libraryModeKey = 'library_mode';
  static const String _targetResourceKey = 'target_resource_id';
  static const String _sourceTokenKey = 'source_token';
  static const String _originWorldviewKey = 'origin_worldview_id';

  final String origin;
  final String libraryMode;
  final String targetResourceId;
  final String expectedSourceToken;
  final String originWorldviewId;

  String encode() {
    final fields = <String, String>{
      _libraryModeKey: libraryMode,
      if (targetResourceId.isNotEmpty) _targetResourceKey: targetResourceId,
      if (expectedSourceToken.isNotEmpty) _sourceTokenKey: expectedSourceToken,
      if (originWorldviewId.isNotEmpty) _originWorldviewKey: originWorldviewId,
    };
    return <String>[
      Uri.encodeComponent(origin),
      for (final entry in fields.entries)
        '${entry.key}=${Uri.encodeComponent(entry.value)}',
    ].join(_separator);
  }

  factory ResourceCreationOriginEnvelope.decode(String encoded) {
    final segments = encoded.split(_separator);
    final values = <String, String>{};
    for (final segment in segments.skip(1)) {
      final separator = segment.indexOf('=');
      if (separator <= 0) continue;
      values[segment.substring(0, separator)] =
          Uri.decodeComponent(segment.substring(separator + 1));
    }
    return ResourceCreationOriginEnvelope(
      origin: Uri.decodeComponent(segments.first),
      libraryMode: values[_libraryModeKey] ?? 'adventure',
      targetResourceId: values[_targetResourceKey] ?? '',
      expectedSourceToken: values[_sourceTokenKey] ?? '',
      originWorldviewId: values[_originWorldviewKey] ?? '',
    );
  }
}

/// Which stage a creation session has reached.
///
/// Phase 0 froze no pipeline status, so Phase 3 owns this enum. Its
/// planning/completed/failed/cancelled sub-graph is deliberately identical to
/// `ResourceStateMachines.generation`, and `ResourceCreationStateMachine`
/// asserts that overlap instead of inventing a second set of terminal rules.
enum CreationSessionStatus {
  draft,
  validating,
  persisted,
  planning,
  completed,
  failed,
  cancelled;

  String get storageValue => name;

  static CreationSessionStatus fromStorage(String? value) {
    for (final status in CreationSessionStatus.values) {
      if (status.storageValue == value) return status;
    }
    return CreationSessionStatus.draft;
  }

  bool get isTerminal =>
      this == CreationSessionStatus.completed ||
      this == CreationSessionStatus.failed ||
      this == CreationSessionStatus.cancelled;
}

/// Single transition authority for creation sessions.
abstract final class ResourceCreationStateMachine {
  static const Map<CreationSessionStatus, Set<CreationSessionStatus>> table = {
    CreationSessionStatus.draft: {
      CreationSessionStatus.draft,
      CreationSessionStatus.validating,
      CreationSessionStatus.cancelled,
    },
    CreationSessionStatus.validating: {
      CreationSessionStatus.validating,
      CreationSessionStatus.persisted,
      CreationSessionStatus.planning,
      CreationSessionStatus.failed,
      CreationSessionStatus.cancelled,
    },
    // A persisted manual resource is finished; an AI session moves on to
    // planning, which Phase 4 executes.
    CreationSessionStatus.persisted: {
      CreationSessionStatus.persisted,
      CreationSessionStatus.completed,
      CreationSessionStatus.planning,
    },
    CreationSessionStatus.planning: {
      CreationSessionStatus.planning,
      CreationSessionStatus.completed,
      CreationSessionStatus.failed,
      CreationSessionStatus.cancelled,
    },
    CreationSessionStatus.completed: {
      CreationSessionStatus.completed,
      CreationSessionStatus.planning,
    },
    CreationSessionStatus.failed: {
      CreationSessionStatus.failed,
      CreationSessionStatus.validating,
    },
    CreationSessionStatus.cancelled: {
      CreationSessionStatus.cancelled,
      CreationSessionStatus.validating,
    },
  };

  static bool canTransition(
          CreationSessionStatus from, CreationSessionStatus to) =>
      table[from]!.contains(to);

  static CreationSessionStatus advance(
    CreationSessionStatus from,
    CreationSessionStatus to,
  ) {
    if (!canTransition(from, to)) {
      throw ResourceCreationException(
        '非法的创建会话状态转换：${from.storageValue} → ${to.storageValue}',
      );
    }
    return to;
  }

  /// The four statuses that share their spelling and terminal semantics with
  /// the frozen `GenerationStatus`.
  ///
  /// Creation sessions add `draft` / `validating` / `persisted` in front, and a
  /// failed or cancelled session retries through `validating` rather than
  /// `planning`, so this is a deliberate mapping rather than an identical table.
  static const Map<CreationSessionStatus, GenerationStatus> frozenEquivalents =
      {
    CreationSessionStatus.planning: GenerationStatus.planning,
    CreationSessionStatus.completed: GenerationStatus.completed,
    CreationSessionStatus.failed: GenerationStatus.failed,
    CreationSessionStatus.cancelled: GenerationStatus.cancelled,
  };

  /// True when every status this pipeline shares with the frozen contract
  /// spells itself the same way, so nothing is renamed or re-invented.
  static bool statusNamesMatchFrozen() {
    for (final entry in frozenEquivalents.entries) {
      if (entry.key.storageValue != entry.value.storageValue) return false;
    }
    return true;
  }

  /// A finished session can never silently return to an in-flight state.
  ///
  /// `failed` / `cancelled` may only restart through `validating`, and
  /// `completed` may only restart through `planning` — the same restart rule the
  /// frozen generation table uses.
  static bool terminalsOnlyExitThroughRetry() {
    for (final from in const [
      CreationSessionStatus.completed,
      CreationSessionStatus.failed,
      CreationSessionStatus.cancelled,
    ]) {
      // A finished session can never fall back to "no session yet" or to
      // "a resource is about to be written".
      if (canTransition(from, CreationSessionStatus.draft) ||
          canTransition(from, CreationSessionStatus.persisted)) {
        return false;
      }
    }
    // A completed session restarts by re-planning, never by re-validating.
    if (canTransition(
      CreationSessionStatus.completed,
      CreationSessionStatus.validating,
    )) {
      return false;
    }
    if (!canTransition(
      CreationSessionStatus.failed,
      CreationSessionStatus.validating,
    )) {
      return false;
    }
    if (!canTransition(
      CreationSessionStatus.cancelled,
      CreationSessionStatus.validating,
    )) {
      return false;
    }
    if (canTransition(
          CreationSessionStatus.completed,
          CreationSessionStatus.planning,
        ) &&
        !ResourceStateMachines.canTransitionGeneration(
          GenerationStatus.completed,
          GenerationStatus.planning,
        )) {
      return false;
    }
    return true;
  }
}

/// Raised for any creation-pipeline contract violation.
class ResourceCreationException implements Exception {
  const ResourceCreationException(this.message, {this.field = ''});

  final String message;

  /// Which request field failed validation, when applicable.
  final String field;

  @override
  String toString() => 'ResourceCreationException: $message';
}

/// Raised when an idempotency key is reused with a different request.
class ResourceCreationIdempotencyConflict extends ResourceCreationException {
  const ResourceCreationIdempotencyConflict(super.message);
}

/// Where the reference material of a creation came from.
///
/// This is a *reference source*, never a creation mode: text, file and existing
/// resource all flow through the same [ResourceCreationMethod], so no
/// `textImport` / `fileImport` / `worldviewImportMode` style enum is allowed.
enum ReferenceSourceKind {
  none,
  text,
  file,
  existingResource;

  String get storageValue => name;

  static ReferenceSourceKind fromStorage(String? value) {
    for (final kind in ReferenceSourceKind.values) {
      if (kind.storageValue == value) return kind;
    }
    return ReferenceSourceKind.none;
  }
}

/// Reference material for a creation, with minimal provenance.
///
/// The body is needed by the Phase 4 planner, so it is persisted; it must never
/// be logged, and [summary] is the only field safe to surface in diagnostics.
final class ReferenceSource {
  const ReferenceSource({
    this.kind = ReferenceSourceKind.none,
    this.label = '',
    this.body = '',
    this.existingResourceId = '',
    this.fileName = '',
    this.characterCount = 0,
  });

  /// No reference material at all.
  static const ReferenceSource none = ReferenceSource();

  /// Pasted text.
  factory ReferenceSource.text(String body, {String label = ''}) =>
      ReferenceSource(
        kind: ReferenceSourceKind.text,
        body: body,
        label: label,
        characterCount: body.length,
      );

  /// Uploaded file content.
  factory ReferenceSource.file(String body, {required String fileName}) =>
      ReferenceSource(
        kind: ReferenceSourceKind.file,
        body: body,
        label: fileName,
        fileName: fileName,
        characterCount: body.length,
      );

  /// Another library resource used as material.
  factory ReferenceSource.existingResource(String resourceId,
          {String label = ''}) =>
      ReferenceSource(
        kind: ReferenceSourceKind.existingResource,
        existingResourceId: resourceId,
        label: label,
      );

  final ReferenceSourceKind kind;
  final String label;

  /// Reference body. Never logged.
  final String body;

  /// Referenced resource id for [ReferenceSourceKind.existingResource].
  final String existingResourceId;

  final String fileName;
  final int characterCount;

  bool get isEmpty => kind == ReferenceSourceKind.none;

  bool get hasBody => body.trim().isNotEmpty;

  /// Diagnostics-safe description: no reference body text.
  String get diagnosticLabel => 'kind=${kind.storageValue} '
      'chars=$characterCount label=${label.isEmpty ? '-' : label}';

  @override
  String toString() => 'ReferenceSource($diagnosticLabel)';
}

/// The two creation semantics the user actually has.
///
/// The AI value reuses the Phase 0 frozen spelling `aiReference`; Phase 3 does
/// not add a third value and does not rename the frozen enum.
typedef ResourceCreationMethod = CreationMethod;

/// One creation request, produced by every entry point.
///
/// [idempotencyKey] is what makes repeated submits from a double click, a UI
/// rebuild or a retry collapse into a single logical resource.
final class ResourceCreationRequest {
  const ResourceCreationRequest({
    required this.resourceType,
    required this.method,
    required this.name,
    required this.idempotencyKey,
    this.referenceSource = ReferenceSource.none,
    this.summary = '',
    this.createInitialEmptySection = false,
    this.initialSectionTitle = '',
    this.initialSections = const <ResourceTreeSectionDraft>[],
    this.origin = '',
    this.libraryMode = 'adventure',
    this.resourceId,
    this.initialMetadata = const <String, Object?>{},
    this.targetCharacters,
  });

  final ResourceType resourceType;
  final CreationMethod method;
  final String name;
  final String idempotencyKey;
  final ReferenceSource referenceSource;
  final String summary;

  /// Manual creation may create one empty Section up front.
  final bool createInitialEmptySection;
  final String initialSectionTitle;

  /// Content already produced by the calling entry point.
  ///
  /// Manual creation defaults to an empty tree, but legacy entries (and the AI
  /// pages that still generate before Phase 4–6 take over) hand over the content
  /// they already built. It is written through the same single transaction, so
  /// routing an entry through the pipeline can never lose its content.
  final List<ResourceTreeSectionDraft> initialSections;

  /// Which entry point produced the request (diagnostics only).
  final String origin;

  /// Identity of an existing resource this request upserts.
  ///
  /// Legacy save paths are upserts: saving an existing worldview or card must
  /// update the same resource, not create a second one. When null the pipeline
  /// allocates an id for a brand-new resource.
  final String? resourceId;

  /// Metadata produced by the caller's mapping, merged under the pipeline's own
  /// provenance keys so an entry never loses runtime refs or source info.
  final Map<String, Object?> initialMetadata;

  /// Desired total prose size for AI creation.
  ///
  /// Null keeps non-AI and legacy callers on the resource type's nominal
  /// capacity. The pipeline resolves and persists the effective value before
  /// planning so retries cannot silently change the requested size.
  final int? targetCharacters;

  /// Which resource-library partition the resource belongs to
  /// (conversation / adventure / creation). Persisted in metadata so the
  /// library can list resources that only exist in the tree.
  final String libraryMode;

  /// AI creation only prepares a session; it never writes body text.
  bool get isAi => method == CreationMethod.aiReference;

  /// Diagnostics-safe view: never includes the reference body.
  String get diagnosticSummary => 'type=${resourceType.storageValue} '
      'method=${method.storageValue} origin=${origin.isEmpty ? '-' : origin} '
      'ref=[${referenceSource.diagnosticLabel}]';
}

/// Outcome of a pipeline submission.
final class ResourceCreationResult {
  const ResourceCreationResult({
    required this.status,
    required this.idempotencyKey,
    this.resourceId,
    this.sessionId,
    this.reusedExisting = false,
  });

  final CreationSessionStatus status;
  final String idempotencyKey;

  /// Set once a resource row exists (manual path, or a completed AI session).
  final ResourceId? resourceId;

  /// Set for the AI path: the persisted session Phase 4 will plan from.
  final String? sessionId;

  /// True when this call returned a previously created result instead of
  /// creating again.
  final bool reusedExisting;

  @override
  String toString() =>
      'ResourceCreationResult(${status.storageValue}, reused=$reusedExisting)';
}

/// One persisted creation session row.
final class ResourceCreationSession {
  const ResourceCreationSession({
    required this.sessionId,
    required this.idempotencyKey,
    required this.resourceType,
    required this.method,
    required this.name,
    required this.status,
    required this.referenceSource,
    required this.targetCharacters,
    this.origin = '',
    this.requestFingerprint = '',
    this.resourceId,
    this.errorMessage = '',
  });

  final String sessionId;
  final String idempotencyKey;
  final ResourceType resourceType;
  final CreationMethod method;
  final String name;
  final CreationSessionStatus status;
  final ReferenceSource referenceSource;
  final int targetCharacters;
  final String origin;
  final String requestFingerprint;
  final ResourceId? resourceId;
  final String errorMessage;

  /// Whether Phase 4 still has planning work to pick up.
  bool get awaitsPlanning =>
      status == CreationSessionStatus.planning ||
      (status == CreationSessionStatus.persisted && isAi);

  bool get isAi => method == CreationMethod.aiReference;

  ResourceCreationSession copyWith({
    CreationSessionStatus? status,
    ResourceId? resourceId,
    String? errorMessage,
  }) {
    return ResourceCreationSession(
      sessionId: sessionId,
      idempotencyKey: idempotencyKey,
      resourceType: resourceType,
      method: method,
      name: name,
      status: status ?? this.status,
      referenceSource: referenceSource,
      targetCharacters: targetCharacters,
      origin: origin,
      requestFingerprint: requestFingerprint,
      resourceId: resourceId ?? this.resourceId,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

/// Validates a creation request before anything is persisted.
///
/// All entry points share this, so validation can no longer diverge per screen.
abstract final class ResourceCreationValidator {
  static const int maximumNameLength = 200;

  static void validate(
    ResourceCreationRequest request, {
    required bool Function() hasAiCredentials,
  }) {
    if (request.name.trim().isEmpty) {
      throw const ResourceCreationException('资源名称不能为空', field: 'name');
    }
    if (request.name.trim().length > maximumNameLength) {
      throw const ResourceCreationException(
        '资源名称超过 $maximumNameLength 字',
        field: 'name',
      );
    }
    if (request.idempotencyKey.trim().isEmpty) {
      throw const ResourceCreationException(
        '缺少幂等键，无法防止重复创建',
        field: 'idempotencyKey',
      );
    }
    if (request.isAi && !hasAiCredentials()) {
      throw const ResourceCreationException(
        'AI 创建需要先配置可用的模型与 API Key',
        field: 'apiKey',
      );
    }
    if (request.isAi && request.targetCharacters != null) {
      final targetCharacters = request.targetCharacters!;
      final maximum =
          ResourceLimits.policyFor(request.resourceType).nominalCharacters;
      if (targetCharacters < ResourceLimits.minimumGenerationTargetCharacters ||
          targetCharacters > maximum) {
        throw ResourceCreationException(
          '目标字数必须在 '
          '${ResourceLimits.minimumGenerationTargetCharacters}–$maximum 之间',
          field: 'targetCharacters',
        );
      }
    }
    if (!request.isAi && request.referenceSource.hasBody) {
      // Manual creation with pasted material is legitimate: the material is
      // simply recorded as a reference source.
    }
  }

  /// Throws when a resource type cannot be created by the unified pipeline.
  static void validateResourceType(ResourceType type) {
    if (!ResourceType.values.contains(type)) {
      throw const ResourceCreationException('不支持的资源类型', field: 'type');
    }
  }
}
