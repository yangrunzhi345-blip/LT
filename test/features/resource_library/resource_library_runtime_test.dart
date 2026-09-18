import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/assembly_readiness_repository.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/streaming_generation_runtime_contracts.dart';
import 'package:lt_dialogue/features/resource_library/application/use_cases/resource_library_runtime.dart';
import 'package:lt_dialogue/features/resource_library/domain/models/resource_library_view_state.dart';

void main() {
  final now = DateTime(2026, 9, 18);

  StreamingGenerationSession session(StreamingLifecycleStatus status) =>
      StreamingGenerationSession(
        sessionId: 'session-1',
        resourceId: const ResourceId('resource-1'),
        blueprintId: 'blueprint-1',
        status: status,
        createdAt: now,
        updatedAt: now,
      );

  AssemblyReadinessRecord readiness(ReadinessState state) =>
      AssemblyReadinessRecord(
        resourceId: 'resource-1',
        state: state,
      );

  group('resolveResourceDisplayStatus', () {
    test('should show generating before an older ready readiness record', () {
      expect(
        resolveResourceDisplayStatus(
          hasTree: true,
          session: session(StreamingLifecycleStatus.generatingPart),
          readiness: readiness(ReadinessState.ready),
        ),
        ResourceDisplayStatus.generating,
      );
    });

    test('should show readiness after generation completes', () {
      expect(
        resolveResourceDisplayStatus(
          hasTree: true,
          session: session(StreamingLifecycleStatus.completed),
          readiness: readiness(ReadinessState.stale),
        ),
        ResourceDisplayStatus.optimizationSuggested,
      );
    });

    test('should show saved without a session or readiness record', () {
      expect(
        resolveResourceDisplayStatus(
          hasTree: true,
          session: null,
          readiness: null,
        ),
        ResourceDisplayStatus.saved,
      );
    });
  });
}
