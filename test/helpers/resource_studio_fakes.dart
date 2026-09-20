import 'dart:async';

import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/application/resources/resource_creation_contracts.dart';
import 'package:lt_dialogue/domain/resources/streaming_generation_runtime_contracts.dart';
import 'package:lt_dialogue/features/resource_studio/application/use_cases/resource_studio_runtime.dart';

/// Reusable in-memory [ResourceStudioRuntime] for widget tests.
///
/// Production code never sees this type; it exists so Studio widgets can be
/// exercised without SQLite or an LLM gateway.
final class FakeResourceStudioRuntime implements ResourceStudioRuntime {
  FakeResourceStudioRuntime({
    required this.tree,
    required this.session,
    this.nextSessionError,
  });

  final ResourceTree tree;
  StreamingGenerationSession session;
  final StreamController<GenerationRuntimeEvent> eventsController =
      StreamController<GenerationRuntimeEvent>.broadcast();
  bool createCalled = false;
  int? createdTargetCharacters;
  Object? nextSessionError;
  final List<String> resumeCalls = <String>[];
  final List<(String, String)> retryPartCalls = <(String, String)>[];

  @override
  Stream<GenerationRuntimeEvent> get events => eventsController.stream;

  @override
  Future<ResourceTree?> readTree(ResourceId resourceId) async => tree;

  @override
  Future<StreamingGenerationSession?> getSession(String sessionId) async {
    final error = nextSessionError;
    if (error != null) {
      nextSessionError = null;
      throw error;
    }
    return session.sessionId == sessionId ? session : null;
  }

  @override
  Future<StreamingGenerationSession?> getLatestSessionForResource(
    String resourceId,
  ) async =>
      session.resourceId.value == resourceId ? session : null;

  @override
  Future<StreamingGenerationSession?> ensureSession(
    ResourceId resourceId,
  ) async =>
      session.resourceId == resourceId ? session : null;

  @override
  Future<List<StreamingGenerationSession>> findActiveSessions() async =>
      [session];

  @override
  Future<List<Resource>> listResources() async => [tree.resource];

  @override
  Future<bool> start(String sessionId) async => true;

  @override
  Future<void> pause(String sessionId) async {}

  @override
  Future<bool> resume(String sessionId) async {
    resumeCalls.add(sessionId);
    return true;
  }

  @override
  Future<void> cancel(String sessionId) async {}

  @override
  Future<bool> retryPart(String sessionId, String partId) async {
    retryPartCalls.add((sessionId, partId));
    return true;
  }

  @override
  Future<bool> recover(String sessionId) async => true;

  @override
  Future<StreamingGenerationSession> createAndStart({
    required ResourceType resourceType,
    required String name,
    required ReferenceSource referenceSource,
    required int targetCharacters,
    String origin = 'resource-studio',
    String libraryMode = 'adventure',
    String? idempotencyKey,
  }) async {
    createCalled = true;
    createdTargetCharacters = targetCharacters;
    return session;
  }

  @override
  Future<Resource> createManual({
    required ResourceType resourceType,
    required String name,
    required String summary,
    required String libraryMode,
  }) async =>
      tree.resource;

  @override
  void dispose() {
    unawaited(eventsController.close());
  }
}

/// Builds the sample tree used by Studio widget tests.
///
/// Titles are intentionally long so narrow viewports are exercised with
/// dynamic text rather than short labels.
ResourceTree buildStudioTestTree() {
  const resourceId = ResourceId('res_studio_test');
  const sectionId = SectionId('section_studio_test');
  const partId = PartId('part_studio_test');
  return ResourceTree(
    resource: const Resource(
      id: resourceId,
      type: ResourceType.worldview,
      name: '一个很长的 Resource Studio 测试标题，用于窄屏换行',
      summary: '用于验证状态展示、滚动和响应式布局。',
    ),
    sections: [
      const ResourceSection(
        id: sectionId,
        resourceId: resourceId,
        title: '第一章：一个很长的 Section 标题用于验证截断和换行',
        sortOrder: 0,
      ),
    ],
    parts: [
      const ResourcePart(
        id: partId,
        sectionId: sectionId,
        title: '段落标题',
        content: '已有正文。',
        sortOrder: 0,
      ),
    ],
  );
}

/// Builds a paused session bound to [tree] for Studio widget tests.
StreamingGenerationSession buildStudioTestSession(ResourceTree tree) {
  return StreamingGenerationSession(
    sessionId: 'gen_studio_test',
    resourceId: tree.resource.id,
    blueprintId: 'bp_studio_test',
    status: StreamingLifecycleStatus.paused,
    totalPartsCount: tree.parts.length,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
}
