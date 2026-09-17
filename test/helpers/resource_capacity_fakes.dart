import 'package:lt_dialogue/application/resources/compression_coordinator.dart';
import 'package:lt_dialogue/domain/resources/resource_capacity.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/features/resource_studio/application/use_cases/resource_capacity_runtime.dart';
import 'package:lt_dialogue/features/resource_studio/domain/models/resource_capacity_view_state.dart';

/// In-memory [ResourceCapacityRuntime] for widget tests.
///
/// Widget tests must not open SQLite or an LLM gateway, so this fake keeps the
/// panel behind the same narrow boundary production uses while letting a test
/// choose the measured numbers, the queue depth and the failure mode.
final class FakeResourceCapacityRuntime implements ResourceCapacityRuntime {
  FakeResourceCapacityRuntime({
    this.totalCharacters = 1234,
    this.type = ResourceType.character,
    this.queuedCount = 1,
    this.candidateCount = 1,
    this.potentialSavedCharacters = 300,
    this.runResult = const CompressionRunProgress(
      totalJobs: 1,
      processedJobs: 1,
      succeededJobs: 1,
      failedJobs: 0,
    ),
  });

  int totalCharacters;
  ResourceType type;
  int queuedCount;
  int candidateCount;
  int potentialSavedCharacters;
  CompressionRunProgress runResult;

  /// When set, every runtime call throws this instead of succeeding.
  Object? error;

  final List<String> summarizeCalls = <String>[];
  final List<String> refreshCalls = <String>[];
  final List<String> queueCalls = <String>[];
  int runCalls = 0;

  ResourceCapacitySummary get summary => ResourceCapacitySummary(
        snapshot: ResourceCapacitySnapshot(
          resourceId: const ResourceId('res_fake'),
          type: type,
          totalCharacters: totalCharacters,
          activeCharacters: totalCharacters,
          archivedCharacters: 0,
          estimatedTokens: ResourceCapacityMath.tokensForCharacters(
            totalCharacters,
          ),
          sectionCount: 2,
          partCount: 4,
          historicalRevisionCount: 0,
          status: ResourceCapacityMath.statusFor(type, totalCharacters),
        ),
        candidateCount: candidateCount,
        queuedJobs: queuedCount,
        potentialSavedCharacters: potentialSavedCharacters,
      );

  @override
  Future<ResourceCapacitySummary> summarize(String resourceId) async {
    summarizeCalls.add(resourceId);
    if (error != null) throw error!;
    return summary;
  }

  @override
  Future<ResourceCapacitySummary> refresh(String resourceId) async {
    refreshCalls.add(resourceId);
    if (error != null) throw error!;
    return summary;
  }

  @override
  Future<int> queueCompression(String resourceId) async {
    queueCalls.add(resourceId);
    if (error != null) throw error!;
    return queuedCount;
  }

  @override
  Future<CompressionRunProgress> runQueuedCompression({int maxJobs = 4}) async {
    runCalls++;
    if (error != null) throw error!;
    return runResult;
  }

  @override
  void dispose() {}
}
