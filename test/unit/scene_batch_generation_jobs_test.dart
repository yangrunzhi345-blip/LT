import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:lt_dialogue/application/llm/llm_gateway.dart';
import 'package:lt_dialogue/application/resource_library/import_use_cases.dart';
import 'package:lt_dialogue/models/resource_library_mode.dart';
import 'package:lt_dialogue/models/scene_batch_candidate.dart';
import 'package:lt_dialogue/services/repositories/library_repository.dart';

import 'scene_batch_test_support.dart';

class _MockLlmGateway extends Mock implements LlmGateway {}

class _MockLibraryRepository extends Mock implements ILibraryRepository {}

SceneBatchCandidate _candidate(int index) => SceneBatchCandidate(
      sourceId: 'scene_candidate_${index.toString().padLeft(3, '0')}',
      displayName: '角色$index',
    );

Map<String, dynamic> _item(int index) => {
      'sourceId': 'scene_candidate_${index.toString().padLeft(3, '0')}',
      'name': '角色$index',
      'description': '描述$index',
    };

void main() {
  late _MockLlmGateway gateway;
  late _MockLibraryRepository repository;
  late SceneBatchImportUseCase useCase;
  late SceneBatchSaveSpy saveSpy;

  setUpAll(() {
    registerFallbackValue(LibraryCardType.character);
    registerFallbackValue(ResourceLibraryMode.adventure);
    registerFallbackValue(
        const SceneBatchCandidate(sourceId: '', displayName: ''));
  });

  setUp(() {
    gateway = _MockLlmGateway();
    repository = _MockLibraryRepository();
    useCase = SceneBatchImportUseCase(
      gateway: gateway,
      repository: repository,
    );
    when(() => gateway.isConfigured).thenReturn(true);
    saveSpy = stubSceneBatchSave(repository);
  });

  List<SceneBatchCandidate> capturedCandidates() => verify(
        () => gateway.generateSceneBatchCharacter(
          source: any(named: 'source'),
          label: any(named: 'label'),
          worldview: any(named: 'worldview'),
          relatedCharacters: any(named: 'relatedCharacters'),
          candidate: captureAny(named: 'candidate'),
          minimumTotalLength: any(named: 'minimumTotalLength'),
          maximumTotalLength: any(named: 'maximumTotalLength'),
          detailInstruction: any(named: 'detailInstruction'),
        ),
      ).captured.cast<SceneBatchCandidate>();

  test('schedules one generation job per selected candidate', () async {
    stubSceneBatchCharacterGeneration(gateway, {
      for (var i = 1; i <= 5; i++) _candidate(i).sourceId: _item(i),
    });

    final count = await useCase.importSelected(
      buildSceneBatchRequest(),
      [for (var i = 1; i <= 5; i++) _candidate(i)],
    );

    expect(count, 5);
    expect(capturedCandidates(), hasLength(5));
    expect(saveSpy.last, hasLength(5));
  });

  test('one failed candidate does not discard successful items', () async {
    stubSceneBatchCharacterAttempts(gateway, {
      _candidate(1).sourceId: [() => _item(1)],
      _candidate(2).sourceId: [
        () => throw StateError('boom'),
        () => throw StateError('boom'),
      ],
      _candidate(3).sourceId: [() => _item(3)],
    });

    final count = await useCase.importSelected(
      buildSceneBatchRequest(),
      [_candidate(1), _candidate(2), _candidate(3)],
    );

    expect(count, 2);
    expect(saveSpy.last.map((item) => item.name).toList(), ['角色1', '角色3']);
    // 失败候选只重试有界次数（默认 2 次）。
    final failedAttempts = capturedCandidates()
        .where((c) => c.sourceId == _candidate(2).sourceId)
        .length;
    expect(failedAttempts, 2);
  });

  test('per-item retry recovers a transient generation failure', () async {
    stubSceneBatchCharacterAttempts(gateway, {
      _candidate(1).sourceId: [
        () => throw StateError('transient'),
        () => _item(1),
      ],
    });

    final count = await useCase.importSelected(
      buildSceneBatchRequest(),
      [_candidate(1)],
    );

    expect(count, 1);
    expect(capturedCandidates(), hasLength(2));
  });

  test('cancellation before generation prevents any persistence', () async {
    stubSceneBatchCharacterGeneration(gateway, {
      _candidate(1).sourceId: _item(1),
    });

    await expectLater(
      useCase.importSelected(
        buildSceneBatchRequest(),
        [_candidate(1)],
        isCancelled: () => true,
      ),
      throwsA(isA<ImportValidationException>()),
    );
    verifyNoSceneBatchSave(repository);
  });

  test('cancellation after a successful item prevents persistence', () async {
    stubSceneBatchCharacterGeneration(gateway, {
      _candidate(1).sourceId: _item(1),
      _candidate(2).sourceId: _item(2),
    });
    var checks = 0;

    await expectLater(
      useCase.importSelected(
        buildSceneBatchRequest(),
        [_candidate(1), _candidate(2)],
        isCancelled: () => checks++ > 0,
      ),
      throwsA(isA<ImportValidationException>()),
    );
    verifyNoSceneBatchSave(repository);
  });

  test('all candidates failing throws instead of saving an empty batch',
      () async {
    stubSceneBatchCharacterAttempts(gateway, {
      _candidate(1).sourceId: [
        () => throw StateError('boom'),
        () => throw StateError('boom'),
      ],
    });

    await expectLater(
      useCase.importSelected(
        buildSceneBatchRequest(),
        [_candidate(1)],
      ),
      throwsA(isA<ImportValidationException>()),
    );
    verifyNoSceneBatchSave(repository);
  });
}
