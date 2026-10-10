import 'package:lt_dialogue/application/resources/assembly_readiness_repository.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/compression_coordinator.dart';
import 'package:lt_dialogue/application/resources/compression_job_repository.dart';
import 'package:lt_dialogue/application/resources/compression_worker.dart';
import 'package:lt_dialogue/application/resources/resource_capacity_repository.dart';
import 'package:lt_dialogue/application/resources/resource_capacity_service.dart';
import 'package:lt_dialogue/domain/resources/resource_compression.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_revision.dart';
import 'package:lt_dialogue/domain/errors/diagnostic_envelope.dart';
import 'package:lt_dialogue/application/resources/resource_compression_publisher.dart';
import 'package:lt_dialogue/models/generation_task_handle.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository.dart';

import '../../helpers/phase10_fixture.dart';

class _CompressionResponses implements CompressionLlmPort {
  @override
  Future<String> compress(
          {required String systemPrompt,
          required String instruction,
          GenerationTaskHandle? taskHandle}) async =>
      jsonEncode({
        'protocol_version': 1,
        'compressed_content': '艾尔与利亚是同伴，42年王城事件。',
        'retained': {
          'entities': ['艾尔', '利亚'],
          'relationships': ['艾尔→利亚'],
          'timeline': ['42年王城事件']
        },
      });
}

void main() {
  final fixture = Phase10Fixture();
  setUp(() => fixture.setUp(prefix: 'lt_overflow_lifecycle_'));
  tearDown(fixture.tearDown);

  Future<ResourceId> create(String id, int characters,
      {int sections = 1, bool emoji = false}) async {
    final bodies = <String>[];
    var remaining = characters;
    while (remaining > 0) {
      final length = remaining > 2800 ? 2800 : remaining;
      bodies.add(emoji
          ? '${'😀' * (length ~/ 2)}${length.isOdd ? '文' : ''}'
          : '文' * length);
      remaining -= length;
    }
    final resourceId = ResourceId(id);
    await fixture.treeRepository.createResourceTree(ResourceTreeDraft(
        id: resourceId,
        type: ResourceType.character,
        name: '艾尔',
        sections: [
          for (var section = 0; section < sections; section++)
            ResourceTreeSectionDraft(title: '设定$section', parts: [
              for (var i = section; i < bodies.length; i += sections)
                ResourceTreePartDraft(title: '正文$i', content: bodies[i])
            ]),
        ]));
    await fixture.revisionService
        .captureRevision(resourceId, cause: RevisionCause.manualSave);
    return resourceId;
  }

  ({
    CompressionCoordinator compression,
    CompressionBackgroundWorker worker,
    CompressionPublisher publisher,
    CompressionJobRepositoryImpl repository
  }) wire({CompressionLlmPort? llm}) {
    final repository =
        CompressionJobRepositoryImpl(getDb: () async => fixture.db);
    final capacity =
        ResourceCapacityRepositoryImpl(getDb: () async => fixture.db);
    final compression = CompressionCoordinator(
        jobRepository: repository,
        treeRepository: fixture.treeRepository,
        capacityRepository: capacity,
        llmPort: llm ?? _CompressionResponses());
    final worker = CompressionBackgroundWorker(
        coordinator: compression,
        capacityService: ResourceCapacityService(repository: capacity));
    final publisher = CompressionPublisher(
        jobRepository: repository,
        revisionService: fixture.revisionService,
        getDb: () async => fixture.db);
    fixture.coordinator.attachCompression(
        coordinatorGetter: () => compression,
        workerGetter: () => worker,
        publisherGetter: () => publisher);
    return (
      compression: compression,
      worker: worker,
      publisher: publisher,
      repository: repository
    );
  }

  for (final length in [8000, 18000, 20000, 24000, 24001]) {
    test('actual length $length: live/revision capacity and readiness agree',
        () async {
      final id = await create('boundary_$length', length);
      wire();
      final live =
          await ResourceCapacityRepositoryImpl(getDb: () async => fixture.db)
              .measureResource(id);
      final head = (await fixture.revisionRepository
          .readHead(id, ResourceRevisionKind.latestHead))!;
      final frozen =
          await fixture.revisionRepository.readState(head.revisionId);
      final actual = frozen.nodes.values
          .where((node) =>
              node.kind == RevisionNodeKind.part &&
              node.status != NodeStatus.archived)
          .fold<int>(0, (sum, node) => sum + node.content.length);
      expect(live.activeCharacters, length);
      expect(actual, length);
      final outcome = await fixture.coordinator.prepare(id);
      debugPrint(
          'SQLITE_CAPACITY actual=$actual live=${live.activeCharacters} status=${live.status} readiness=${outcome.record.state}');
      if (length <= 24000) {
        expect(outcome.record.state, ReadinessState.ready);
      } else {
        expect(
            DiagnosticEnvelope.tryDecode(outcome.record.validationMessage)!
                .code,
            'compressionApprovalRequired');
      }
    });
  }

  test('UTF-16 emoji count is identical in live SQLite and frozen head',
      () async {
    final id = await create('emoji', 24001, emoji: true);
    wire();
    final live =
        await ResourceCapacityRepositoryImpl(getDb: () async => fixture.db)
            .measureResource(id);
    expect(live.activeCharacters, 24001);
    expect((await fixture.coordinator.prepare(id)).awaitedCompression, isTrue);
  });

  test(
      'reviewed Part candidates publish atomically, preserve original revision and become ready',
      () async {
    final id = await create('approve', 25200, sections: 3);
    final stack = wire();
    final head = (await fixture.revisionRepository
        .readHead(id, ResourceRevisionKind.latestHead))!;
    final before = await fixture.revisionRepository.readState(head.revisionId);
    await fixture.coordinator.prepare(id);
    final candidates = await stack.publisher.publishableCandidates(id);
    expect(candidates, hasLength(9));
    expect(
        candidates
            .every((candidate) => candidate.scope == CompressionScope.part),
        isTrue);
    await fixture.coordinator.approveCompression(
        resourceId: id,
        candidateIds:
            candidates.map((candidate) => candidate.candidateId).toList(),
        expectedHeadRevisionId: head.revisionId.value);
    expect(
        (await fixture.coordinator.readiness(id))!.state, ReadinessState.ready);
    final preserved =
        await fixture.revisionRepository.readState(head.revisionId);
    expect(preserved.contentHash, before.contentHash);
    final newHead = (await fixture.revisionRepository
        .readHead(id, ResourceRevisionKind.latestHead))!;
    await fixture.coordinator.approveCompression(
        resourceId: id,
        candidateIds:
            candidates.map((candidate) => candidate.candidateId).toList(),
        expectedHeadRevisionId: head.revisionId.value);
    expect(
        (await fixture.revisionRepository
                .readHead(id, ResourceRevisionKind.latestHead))!
            .revisionId,
        newHead.revisionId);
  });

  test(
      'failed compression terminates and explicit retry recovers without rewriting text',
      () async {
    final id = await create('failure', 25200);
    final fake = _FailOnce();
    final stack = wire(llm: fake);
    final result = await fixture.coordinator.prepare(id);
    expect(result.record.state, ReadinessState.failed);
    expect(DiagnosticEnvelope.tryDecode(result.record.failureReason)!.code,
        'compressionFailed');
    final live =
        await ResourceCapacityRepositoryImpl(getDb: () async => fixture.db)
            .measureResource(id);
    expect(live.activeCharacters, 25200);
    await fixture.coordinator.retryPreparation(id);
    expect(
        (await stack.repository.findJobsForResource(id.value))
            .every((job) => job.status == CompressionJobStatus.succeeded),
        isTrue);
    expect(
        DiagnosticEnvelope.tryDecode(
                (await fixture.coordinator.readiness(id))!.validationMessage)!
            .code,
        'compressionApprovalRequired');
  });

  test('edit during review rejects the entire adoption transaction', () async {
    final id = await create('edit_review', 25200);
    final stack = wire();
    await fixture.coordinator.prepare(id);
    final head = (await fixture.revisionRepository
        .readHead(id, ResourceRevisionKind.latestHead))!;
    final candidates = await stack.publisher.publishableCandidates(id);
    final sections = await fixture.treeRepository.readSections(id);
    final part =
        (await fixture.treeRepository.readParts(sections.first.id)).first;
    await fixture.treeRepository.updatePart(
        id: part.id,
        expectedUpdatedAt: await fixture.readNodeUpdatedAt(part.id.value),
        content: '用户编辑');
    await fixture.revisionService
        .captureRevision(id, cause: RevisionCause.manualSave);
    await expectLater(
        fixture.coordinator.approveCompression(
            resourceId: id,
            candidateIds:
                candidates.map((candidate) => candidate.candidateId).toList(),
            expectedHeadRevisionId: head.revisionId.value),
        throwsA(isA<CompressionPublishException>()));
    expect(
        (await stack.repository.findCandidatesForResource(id.value))
            .every((candidate) => candidate.isCandidateOnly),
        isTrue);
  });

  test(
      'old compressionPending below absolute capacity rebuilds rather than persisting preparing',
      () async {
    final id = await create('old_pending', 20000);
    wire();
    final head = (await fixture.revisionRepository
        .readHead(id, ResourceRevisionKind.latestHead))!;
    await fixture.db.transaction((txn) => fixture.readinessRepository
        .writeInTransaction(
            txn,
            AssemblyReadinessRecord(
                resourceId: id.value,
                state: ReadinessState.preparing,
                targetRevisionId: head.revisionId.value,
                targetContentHash: head.contentHash,
                attemptToken: 'old',
                validationMessage:
                    const DiagnosticEnvelope(code: 'compressionPending')
                        .encode())));
    expect(
        (await fixture.coordinator.refresh(id))!.state, ReadinessState.ready);
  });

  test(
      'structured JSON overflow has no safe prose targets and fails explicitly',
      () async {
    const id = ResourceId('json_only');
    wire();
    await fixture.treeRepository.createResourceTree(ResourceTreeDraft(
        id: id,
        type: ResourceType.character,
        name: '艾尔',
        sections: [
          ResourceTreeSectionDraft(title: '结构定义', parts: [
            ResourceTreePartDraft(
                title: '定义', content: jsonEncode({'definitions': '文' * 25000}))
          ]),
        ]));
    await fixture.revisionService
        .captureRevision(id, cause: RevisionCause.manualSave);
    final result = await fixture.coordinator.prepare(id);
    expect(result.record.state, ReadinessState.failed);
    expect(DiagnosticEnvelope.tryDecode(result.record.failureReason)!.code,
        'compressionNoTargets');
  });

  test('archived body is excluded equally from live and frozen capacity',
      () async {
    final id = await create('archive_count', 25200);
    wire();
    final section = (await fixture.treeRepository.readSections(id)).first;
    final part = (await fixture.treeRepository.readParts(section.id)).first;
    await fixture.treeRepository.updatePart(
        id: part.id,
        expectedUpdatedAt: await fixture.readNodeUpdatedAt(part.id.value),
        status: NodeStatus.archived);
    await fixture.revisionService
        .captureRevision(id, cause: RevisionCause.manualSave);
    final live =
        await ResourceCapacityRepositoryImpl(getDb: () async => fixture.db)
            .measureResource(id);
    expect(live.totalCharacters, 25200);
    expect(live.activeCharacters, 22400);
    expect(live.status.name, 'elastic');
    expect((await fixture.coordinator.prepare(id)).record.state,
        ReadinessState.ready);
  });

  test(
      'legacy Section proposals remain unpublished and explicit preparation creates safe Part mappings',
      () async {
    final id = await create('legacy_section', 25200, sections: 3);
    final stack = wire();
    await stack.compression.enqueueForResource(id);
    await stack.worker.process(id.value);
    final sectionCandidates =
        await stack.repository.findCandidatesForResource(id.value);
    expect(sectionCandidates, hasLength(3));
    expect(
        sectionCandidates
            .every((candidate) => candidate.scope == CompressionScope.section),
        isTrue);
    await expectLater(
        stack.publisher.publish(sectionCandidates.first.candidateId),
        throwsA(isA<CompressionPublishException>()));
    expect(
        await fixture.revisionRepository
            .readHead(id, ResourceRevisionKind.assembly),
        isNull);
    await fixture.coordinator.retryPreparation(id);
    final partCandidates = await stack.publisher.publishableCandidates(id);
    expect(partCandidates, hasLength(9));
    final head = (await fixture.revisionRepository
        .readHead(id, ResourceRevisionKind.latestHead))!;
    await fixture.coordinator.approveCompression(
        resourceId: id,
        candidateIds:
            partCandidates.map((candidate) => candidate.candidateId).toList(),
        expectedHeadRevisionId: head.revisionId.value);
    expect(
        (await fixture.coordinator.readiness(id))!.state, ReadinessState.ready);
    expect(
        (await stack.repository.findCandidatesForResource(id.value))
            .where((candidate) => candidate.scope == CompressionScope.section)
            .every((candidate) => candidate.isCandidateOnly),
        isTrue);
  });

  test('retry exhaustion never loops or fabricates ready', () async {
    final id = await create('exhausted', 25200);
    final stack = wire(llm: _AlwaysFail());
    await fixture.coordinator.prepare(id);
    for (var attempt = 0; attempt < 8; attempt++) {
      await fixture.coordinator.retryPreparation(id);
    }
    final jobs = await stack.repository.findJobsForResource(id.value);
    expect(jobs.every((job) => !job.canRetry), isTrue);
    final attempts = jobs.map((job) => job.attempts).toList();
    await fixture.coordinator.retryPreparation(id);
    expect(
        (await stack.repository.findJobsForResource(id.value))
            .map((job) => job.attempts)
            .toList(),
        attempts);
    final row = (await fixture.coordinator.readiness(id))!;
    expect(row.state, ReadinessState.failed);
    expect(DiagnosticEnvelope.tryDecode(row.failureReason)!.code,
        'compressionBudgetExhausted');
    expect(jobs.every((job) => !job.errorMessage.contains('private-body')),
        isTrue);
  });

  test('worker restart resumes queued jobs beyond one batch', () async {
    final id = await create('restart', 25200);
    final stack = wire();
    await stack.compression.enqueueForResource(id, partOnly: true);
    await stack.worker.start();
    await stack.worker.process(id.value);
    expect(
        (await stack.repository.findJobsForResource(id.value))
            .every((job) => job.status == CompressionJobStatus.succeeded),
        isTrue);
  });

  test('duplicate preparation coalesces compression attempts', () async {
    final id = await create('duplicate', 25200);
    final stack = wire();
    final results = await Future.wait(
        [fixture.coordinator.prepare(id), fixture.coordinator.prepare(id)]);
    expect(results.first.record.attemptToken, results.last.record.attemptToken);
    expect(
        (await stack.repository.findJobsForResource(id.value))
            .every((job) => job.attempts == 1),
        isTrue);
  });

  test('overflow queue drains all six jobs, not just the first four', () async {
    const id = ResourceId('res_cre_1791593277951938_3');
    await fixture.treeRepository.createResourceTree(ResourceTreeDraft(
      id: id,
      type: ResourceType.character,
      name: '艾尔',
      sections: [
        ResourceTreeSectionDraft(title: '设定', parts: [
          for (var i = 0; i < 6; i++)
            ResourceTreePartDraft(
                title: '设定$i', content: '艾尔与利亚是同伴，42年王城事件。${'冗余场景。' * 1100}'),
        ])
      ],
    ));
    await fixture.revisionService
        .captureRevision(id, cause: RevisionCause.manualSave);
    final repository =
        CompressionJobRepositoryImpl(getDb: () async => fixture.db);
    final capacity =
        ResourceCapacityRepositoryImpl(getDb: () async => fixture.db);
    final compression = CompressionCoordinator(
        jobRepository: repository,
        treeRepository: fixture.treeRepository,
        capacityRepository: capacity,
        llmPort: _CompressionResponses());
    final worker = CompressionBackgroundWorker(
        coordinator: compression,
        capacityService: ResourceCapacityService(repository: capacity));
    fixture.coordinator.attachCompression(
        coordinatorGetter: () => compression, workerGetter: () => worker);
    final initial = await fixture.coordinator.prepare(id);
    expect(initial.awaitedCompression, isTrue);
    for (var i = 0; i < 300 && worker.processingCount > 0; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    final jobs = await repository.findJobsForResource(id.value);
    expect(jobs, hasLength(6));
    expect(jobs.where((job) => job.isActive), isEmpty,
        reason:
            'A completed background pass must not abandon the remaining queue');
  });
}

class _FailOnce extends _CompressionResponses {
  bool fail = true;
  @override
  Future<String> compress(
      {required String systemPrompt,
      required String instruction,
      GenerationTaskHandle? taskHandle}) async {
    if (fail) {
      fail = false;
      throw StateError('external-error');
    }
    return super.compress(
        systemPrompt: systemPrompt,
        instruction: instruction,
        taskHandle: taskHandle);
  }
}

class _AlwaysFail extends _CompressionResponses {
  @override
  Future<String> compress(
          {required String systemPrompt,
          required String instruction,
          GenerationTaskHandle? taskHandle}) async =>
      throw StateError('private-body-sentinel');
}
