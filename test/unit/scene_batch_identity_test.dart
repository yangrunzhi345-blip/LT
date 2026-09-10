import 'dart:convert';

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
    stubSceneBatchCharacterGeneration(gateway, {
      'scene_candidate_001': {
        'sourceId': 'scene_candidate_001',
        'name': '林月·玄霜剑主',
        'description': '玄霜门少主',
      },
    });
    saveSpy = stubSceneBatchSave(repository);
  });

  test('display-name variant keeps the selected character by stable sourceId',
      () async {
    final count = await useCase.importSelected(
      buildSceneBatchRequest(),
      const [
        SceneBatchCandidate(
          sourceId: 'scene_candidate_001',
          displayName: '林月',
        ),
      ],
    );

    expect(count, 1);
    final saved = saveSpy.last.single;
    expect(saved.name, '林月·玄霜剑主');
    final decoded = jsonDecode(saved.jsonData) as Map<String, dynamic>;
    expect(decoded['name'], '林月·玄霜剑主');
    // 会话内身份不写入最终卡片，保持存档兼容。
    expect(decoded.containsKey('sourceId'), isFalse);
  });

  test('duplicate display names stay distinct by sourceId', () async {
    stubSceneBatchCharacterGeneration(gateway, {
      'scene_candidate_001': {
        'sourceId': 'scene_candidate_001',
        'name': '林月',
        'description': '甲',
      },
      'scene_candidate_002': {
        'sourceId': 'scene_candidate_002',
        'name': '林月',
        'description': '乙',
      },
    });

    final count = await useCase.importSelected(
      buildSceneBatchRequest(),
      const [
        SceneBatchCandidate(
          sourceId: 'scene_candidate_002',
          displayName: '林月',
        ),
      ],
    );

    expect(count, 1);
    final decoded = jsonDecode(saveSpy.last.single.jsonData) as Map;
    expect(decoded['description'], '乙');
  });

  test('unknown generated sourceId is rejected and never persisted', () async {
    stubSceneBatchCharacterGeneration(gateway, {
      'scene_candidate_001': {
        'sourceId': 'scene_candidate_999',
        'name': '陌生人',
      },
    });

    await expectLater(
      useCase.importSelected(
        buildSceneBatchRequest(),
        const [
          SceneBatchCandidate(
            sourceId: 'scene_candidate_001',
            displayName: '林月',
          ),
        ],
      ),
      throwsA(isA<ImportValidationException>()),
    );
    verifyNoSceneBatchSave(repository);
  });

  test('generated item without sourceId is rejected', () async {
    stubSceneBatchCharacterGeneration(gateway, {
      'scene_candidate_001': {'name': '林月'},
    });

    await expectLater(
      useCase.importSelected(
        buildSceneBatchRequest(),
        const [
          SceneBatchCandidate(
            sourceId: 'scene_candidate_001',
            displayName: '林月',
          ),
        ],
      ),
      throwsA(isA<ImportValidationException>()),
    );
    verifyNoSceneBatchSave(repository);
  });

  test('relationship binds by targetResourceId despite display-name variant',
      () async {
    stubSceneBatchCharacterGeneration(gateway, {
      'scene_candidate_001': {
        'sourceId': 'scene_candidate_001',
        'name': '林月',
        'relationship_links': [
          {
            'targetResourceId': 'char_1',
            'targetName': '林月小姐',
            'relationType': '师徒',
            'description': '自幼受其教导',
          },
        ],
      },
    });

    await useCase.importSelected(
      buildSceneBatchRequest(related: [
        {'id': 'char_1', 'name': '林月', 'profession': '剑主'},
      ]),
      const [
        SceneBatchCandidate(
          sourceId: 'scene_candidate_001',
          displayName: '林月',
        ),
      ],
    );

    final decoded =
        jsonDecode(saveSpy.last.single.jsonData) as Map<String, dynamic>;
    final links = (decoded['relationship_links'] as List).cast<Map>();
    expect(links, hasLength(1));
    expect(links.single['targetResourceId'], 'char_1');
    expect(links.single['targetName'], '林月小姐');
  });

  test('relationship with unknown targetResourceId is dropped', () async {
    stubSceneBatchCharacterGeneration(gateway, {
      'scene_candidate_001': {
        'sourceId': 'scene_candidate_001',
        'name': '林月',
        'description': '剑主',
        'relationship_links': [
          {
            'targetResourceId': 'char_unknown',
            'targetName': '林月',
            'relationType': '师徒',
            'description': '不应保留',
          },
        ],
      },
    });

    await useCase.importSelected(
      buildSceneBatchRequest(related: [
        {'id': 'char_1', 'name': '林月'},
      ]),
      const [
        SceneBatchCandidate(
          sourceId: 'scene_candidate_001',
          displayName: '林月',
        ),
      ],
    );

    final decoded =
        jsonDecode(saveSpy.last.single.jsonData) as Map<String, dynamic>;
    expect(decoded['relationship_links'], isEmpty);
  });

  test('identify assigns stable unique sourceIds', () async {
    when(() => gateway.identifyCharacterNames(any()))
        .thenAnswer((_) async => ['林月', '林月', '苏禾']);

    final candidates = await useCase.identify('原文');

    expect(candidates.map((c) => c.sourceId).toSet(), hasLength(3));
    expect(candidates.map((c) => c.displayName).toList(), ['林月', '林月', '苏禾']);
  });
}
