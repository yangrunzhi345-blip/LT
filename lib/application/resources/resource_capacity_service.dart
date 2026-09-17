import '../../domain/resources/resource_capacity.dart';
import '../../domain/resources/resource_compression.dart';
import '../../domain/resources/resource_contracts.dart';
import 'resource_capacity_repository.dart';

/// Application entry point for resource capacity measurement.
///
/// The service is the only place that decides when a measurement is persisted,
/// so callers never have to remember to refresh the cache. Reads are always
/// backed by a single aggregate query; the persisted columns exist so list
/// screens can show a value without re-measuring every row.
final class ResourceCapacityService {
  ResourceCapacityService({
    required IResourceCapacityRepository repository,
    this.thresholds = CompressionThresholds.defaults,
  }) : _repository = repository;

  final IResourceCapacityRepository _repository;
  final CompressionThresholds thresholds;

  /// Measures [id] and refreshes its cached columns.
  Future<ResourceCapacitySnapshot> measure(ResourceId id) async {
    final snapshot = await _repository.measureResource(id);
    await _repository.persistResource(snapshot);
    return snapshot;
  }

  /// Measures without touching the cache.
  ///
  /// Used where a fresh value is needed but the caller must not write (for
  /// example when rendering during a read-only review).
  Future<ResourceCapacitySnapshot> measureReadOnly(ResourceId id) =>
      _repository.measureResource(id);

  /// Reads the last persisted measurement, or null when never measured.
  Future<ResourceCapacitySnapshot?> readCached(ResourceId id) =>
      _repository.readCachedResource(id);

  /// Measures every live resource with a fixture-independent number of queries.
  Future<List<ResourceCapacitySnapshot>> measureAll({ResourceType? type}) =>
      _repository.measureResources(type: type);

  /// Per-section measurements for one resource.
  Future<List<SectionCapacitySnapshot>> sections(ResourceId id) =>
      _repository.measureSections(id);

  /// Ranks the sections worth compressing first.
  Future<List<SectionCapacitySnapshot>> compressionTargets(
    ResourceId id, {
    int maxTargets = 8,
  }) async {
    final sections = await _repository.measureSections(id);
    return CompressionTriggers.selectSectionTargets(
      sections: sections,
      thresholds: thresholds,
      maxTargets: maxTargets,
    );
  }

  /// Trigger decision for a measured resource.
  CompressionTriggerDecision evaluateResource(
    ResourceCapacitySnapshot capacity,
  ) =>
      CompressionTriggers.evaluateResource(
        capacity: capacity,
        thresholds: thresholds,
      );

  /// Trigger decision for a context about to be sent to the model.
  CompressionTriggerDecision evaluateContext(int contextTokens) =>
      CompressionTriggers.evaluateContext(
        contextTokens: contextTokens,
        thresholds: thresholds,
      );
}
