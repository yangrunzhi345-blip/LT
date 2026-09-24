import '../../domain/resources/resource_contracts.dart';
import '../../domain/resources/resource_repository.dart'
    hide ResourceCreationSession;
import '../../domain/resources/resource_revision.dart';
import '../../domain/resources/streaming_generation_runtime_contracts.dart';
import 'assembly_readiness_repository.dart';
import 'resource_creation_contracts.dart';
import 'resource_revision_repository.dart';
import 'streaming_generation_session_repository.dart';

enum ResourceLifecycleState {
  missing,
  draft,
  planning,
  generating,
  validating,
  paused,
  recovering,
  ready,
  failed,
  archived,
}

final class ResourceLifecycleProjectionResult {
  const ResourceLifecycleProjectionResult({
    required this.resourceId,
    required this.state,
    this.resource,
    this.creationSession,
    this.generationSession,
    this.latestRevision,
    this.assemblyReadiness,
  });

  final ResourceId resourceId;
  final ResourceLifecycleState state;
  final Resource? resource;
  final ResourceCreationSession? creationSession;
  final StreamingGenerationSession? generationSession;
  final ResourceRevision? latestRevision;
  final AssemblyReadinessRecord? assemblyReadiness;

  bool get exists => resource != null;
  bool get isEditable =>
      state == ResourceLifecycleState.ready ||
      state == ResourceLifecycleState.draft;
  bool get isAssemblyReady =>
      assemblyReadiness?.state == ReadinessState.ready &&
      assemblyReadiness?.hasAssemblyRevision == true;

  /// A resource is consumable only when its validated assembly revision is
  /// published. Creation and generation terminal states alone are not enough.
  bool get isConsumable =>
      isAssemblyReady && state == ResourceLifecycleState.ready;
}

/// Read-only composition of existing lifecycle authorities.
final class ResourceLifecycleProjection {
  ResourceLifecycleProjection({
    required ResourceTreeReader resourceReader,
    required ResourceCreationSessionReader creationReader,
    required IStreamingGenerationSessionRepository generationReader,
    required IResourceRevisionRepository revisionReader,
    required IAssemblyReadinessRepository readinessReader,
  })  : _resourceReader = resourceReader,
        _creationReader = creationReader,
        _generationReader = generationReader,
        _revisionReader = revisionReader,
        _readinessReader = readinessReader;

  final ResourceTreeReader _resourceReader;
  final ResourceCreationSessionReader _creationReader;
  final IStreamingGenerationSessionRepository _generationReader;
  final IResourceRevisionRepository _revisionReader;
  final IAssemblyReadinessRepository _readinessReader;

  Future<ResourceLifecycleProjectionResult> read(ResourceId resourceId) async {
    final resource = await _resourceReader.findResource(resourceId);
    final creation = await _creationReader.latestCreationSessionForResource(
      resourceId,
    );
    final generation = await _generationReader.findLatestSessionForResource(
      resourceId.value,
    );
    final revision = await _revisionReader.readHead(
      resourceId,
      ResourceRevisionKind.latestHead,
    );
    final readiness = await _readinessReader.read(resourceId.value);
    return evaluate(
      resourceId: resourceId,
      resource: resource,
      creationSession: creation,
      generationSession: generation,
      latestRevision: revision,
      assemblyReadiness: readiness,
    );
  }

  static ResourceLifecycleProjectionResult evaluate({
    required ResourceId resourceId,
    Resource? resource,
    ResourceCreationSession? creationSession,
    StreamingGenerationSession? generationSession,
    ResourceRevision? latestRevision,
    AssemblyReadinessRecord? assemblyReadiness,
  }) {
    final state = _state(
      resource: resource,
      creation: creationSession,
      generation: generationSession,
      readiness: assemblyReadiness,
    );
    return ResourceLifecycleProjectionResult(
      resourceId: resourceId,
      state: state,
      resource: resource,
      creationSession: creationSession,
      generationSession: generationSession,
      latestRevision: latestRevision,
      assemblyReadiness: assemblyReadiness,
    );
  }

  static ResourceLifecycleState _state({
    required Resource? resource,
    required ResourceCreationSession? creation,
    required StreamingGenerationSession? generation,
    required AssemblyReadinessRecord? readiness,
  }) {
    if (resource == null && creation == null && generation == null) {
      return ResourceLifecycleState.missing;
    }
    if (resource?.status == NodeStatus.archived) {
      return ResourceLifecycleState.archived;
    }
    if (creation?.status == CreationSessionStatus.failed ||
        generation?.status == StreamingLifecycleStatus.failed ||
        readiness?.state == ReadinessState.failed) {
      return ResourceLifecycleState.failed;
    }
    if (generation != null && generation.status.isInFlight) {
      return generation.status == StreamingLifecycleStatus.validating
          ? ResourceLifecycleState.validating
          : ResourceLifecycleState.generating;
    }
    if (generation?.status == StreamingLifecycleStatus.recovering) {
      return ResourceLifecycleState.recovering;
    }
    if (generation?.status == StreamingLifecycleStatus.paused ||
        generation?.status == StreamingLifecycleStatus.cancelled) {
      return ResourceLifecycleState.paused;
    }
    // Readiness is an independent authority for manually authored resources.
    // Consumability still requires a concrete assembly revision.
    if (readiness?.state == ReadinessState.ready) {
      return ResourceLifecycleState.ready;
    }
    if (creation?.status == CreationSessionStatus.planning ||
        (creation?.isAi == true &&
            (resource == null ||
                generation == null ||
                generation.status == StreamingLifecycleStatus.created))) {
      return ResourceLifecycleState.planning;
    }
    if (generation?.status == StreamingLifecycleStatus.completed) {
      return ResourceLifecycleState.validating;
    }
    return ResourceLifecycleState.draft;
  }
}
