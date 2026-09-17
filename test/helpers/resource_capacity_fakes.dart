import 'package:lt_dialogue/application/resources/compression_coordinator.dart';
import 'package:lt_dialogue/domain/resources/resource_capacity.dart';
import 'package:lt_dialogue/domain/resources/resource_compression.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/features/resource_studio/application/use_cases/resource_capacity_runtime.dart';
import 'package:lt_dialogue/features/resource_studio/domain/models/resource_capacity_view_state.dart';
import 'package:lt_dialogue/models/generation_task_handle.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Leaves a compression job in `running` exactly as a crashed worker would.
///
/// Recovery fixtures need this row shape; writing it here (rather than through
/// the coordinator) is the point: it simulates a process that died without a
/// chance to run its own terminal transition.
Future<void> markCompressionJobRunningForTest(
  Database db,
  String jobId, {
  required int attempts,
}) async {
  await db.update(
    'resource_compression_jobs',
    {
      'status': CompressionJobStatus.running.storageValue,
      'attempts': attempts,
      'updated_at': '2026-09-17T00:00:00.000',
    },
    where: 'job_id = ?',
    whereArgs: [jobId],
  );
}

/// Reads one compression job row.
Future<Map<String, Object?>> readCompressionJobForTest(
  Database db,
  String jobId,
) async {
  final rows = await db.query(
    'resource_compression_jobs',
    where: 'job_id = ?',
    whereArgs: [jobId],
    limit: 1,
  );
  return rows.first;
}

/// Scripted compression LLM boundary shared by the Phase 8 tests.
///
/// Tests drive the real parser, validator and coordinator through this port, so
/// no test has to re-implement `LlmGateway` and every test exercises the same
/// production parsing path.
final class FakeCompressionLlm implements CompressionLlmPort {
  final List<String> instructions = <String>[];
  final List<String> systemPrompts = <String>[];

  /// Response returned on the next call.
  String response = '';

  /// When set, the next call throws this instead of returning [response].
  Object? error;

  /// Number of calls made.
  int calls = 0;

  @override
  Future<String> compress({
    required String systemPrompt,
    required String instruction,
    GenerationTaskHandle? taskHandle,
  }) async {
    calls++;
    instructions.add(instruction);
    systemPrompts.add(systemPrompt);
    if (error != null) throw error!;
    return response;
  }
}

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
    this.retryableFailedJobs = 0,
    this.latestFailureReason = '',
    this.recoveredJobs = 0,
    this.autoQueuedJobs = 0,
    this.retryRequeuedJobs = 1,
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
  int retryableFailedJobs;
  String latestFailureReason;

  /// Returned by [recoverInterruptedJobs].
  int recoveredJobs;

  /// Returned by [autoQueueCompressionIfNeeded] — 0 means "no trigger".
  int autoQueuedJobs;

  /// Returned by [retryFailedCompression].
  int retryRequeuedJobs;

  CompressionRunProgress runResult;

  /// When set, every runtime call throws this instead of succeeding.
  Object? error;

  /// When set, only the background workflow ([recoverInterruptedJobs],
  /// [autoQueueCompressionIfNeeded]) throws — used to prove a trigger failure
  /// cannot break the panel.
  Object? workflowError;

  final List<String> summarizeCalls = <String>[];
  final List<String> refreshCalls = <String>[];
  final List<String> queueCalls = <String>[];
  final List<String> autoQueueCalls = <String>[];
  final List<String> retryCalls = <String>[];
  int runCalls = 0;
  int recoverCalls = 0;

  /// Summary for [resourceId], echoing the requested id the way the production
  /// runtime does (it reports the id it actually measured).
  ResourceCapacitySummary summaryFor(String resourceId) =>
      ResourceCapacitySummary(
        snapshot: ResourceCapacitySnapshot(
          resourceId: ResourceId(resourceId),
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
        retryableFailedJobs: retryableFailedJobs,
        latestFailureReason: latestFailureReason,
      );

  @override
  Future<ResourceCapacitySummary> summarize(String resourceId) async {
    summarizeCalls.add(resourceId);
    if (error != null) throw error!;
    return summaryFor(resourceId);
  }

  @override
  Future<ResourceCapacitySummary> refresh(String resourceId) async {
    refreshCalls.add(resourceId);
    if (error != null) throw error!;
    return summaryFor(resourceId);
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
  Future<int> recoverInterruptedJobs() async {
    recoverCalls++;
    if (error != null) throw error!;
    if (workflowError != null) throw workflowError!;
    return recoveredJobs;
  }

  @override
  Future<int> autoQueueCompressionIfNeeded(String resourceId) async {
    autoQueueCalls.add(resourceId);
    if (error != null) throw error!;
    if (workflowError != null) throw workflowError!;
    return autoQueuedJobs;
  }

  @override
  Future<int> retryFailedCompression(String resourceId) async {
    retryCalls.add(resourceId);
    if (error != null) throw error!;
    return retryRequeuedJobs;
  }

  @override
  void dispose() {}
}
