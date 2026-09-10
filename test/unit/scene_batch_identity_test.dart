import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:lt_dialogue/application/llm/llm_gateway.dart';
import 'package:lt_dialogue/application/resource_library/import_models.dart';
import 'package:lt_dialogue/application/resource_library/import_use_cases.dart';
import 'package:lt_dialogue/models/resource_library_mode.dart';
import 'package:lt_dialogue/models/resource_provenance.dart';
import 'package:lt_dialogue/models/scene_batch_candidate.dart';
import 'package:lt_dialogue/services/repositories/library_repository.dart';

class _MockLlmGateway extends Mock implements LlmGateway {}

class _MockLibraryRepository extends Mock implements ILibraryRepository {}

void main() {
  late _MockLlmGateway gateway;
  late _MockLibraryRepository repository;
  late SceneBatchImportUseCase useCase;

  setUpAll(() {
    registerFallbackValue(LibraryCardType.character);
    registerFallbackValue(ResourceLibraryMode.adventure);
  });

  setUp(() {
    gateway = _MockLlmGateway();
    repository = _MockLibraryRepository();
    useCase = SceneBatchImportUseCase(
      gateway: gateway,
      repository: repository,
    );
    when(() => gateway.isConfigured).thenReturn(true);
  });

  SceneBatchImportRequest buildRequest({
    List<Map<String, dynamic>> related = const [],
  }) =>
      SceneBatchImportRequest(
        source: '林月与玄霜门的故事。',
        kind: 'character',
        detailInstruction: '详细模式',
        aiDepth: AiGenerationDepth.detailed,
        minimumTotalLength: 1000,
        maximumTotalLength: 5000,
        relatedCharacters: related,
      );

  void stubGeneration(Map<String, dynamic> result) {
    when(
      () => gateway.generateSceneBatchCharacters(
        source: any(named: 'source'),
        label: any(named: 'label'),
        worldview: any(named: 'worldview'),
        relatedCharacters: any(named: 'relatedCharacters'),
        selectedCandidates: any(named: 'selectedCandidates'),
        minimumTotalLength: any(named: 'minimumTotalLength'),
        maximumTotalLength: any(named: 'maximumTotalLength'),
        detailInstruction: any(named: 'detailInstruction'),
      ),
    ).thenAnswer((_) async => result);
  }

  test('display-name variant keeps the selected character by stable sourceId',
      () async {
    stubGeneration({
      'items': [
        {
          'sourceId': 'scene_candidate_001',
          'name': '林月·玄霜剑主',
          'description': '玄霜门少主',
        },
      ],
    });
    List<LibraryCardBatchItem> saved = const [];
    when(
      () => repository.saveCardBatch(
        type: any(named: 'type'),
        items: any(named: 'items'),
        mode: any(named: 'mode'),
      ),
    ).thenAnswer((invocation) async {
      saved = invocation.namedArguments[#items] as List<LibraryCardBatchItem>;
      return saved.length;
    });

    final count = await useCase.importSelected(
      buildRequest(),
      const [
        SceneBatchCandidate(
          sourceId: 'scene_candidate_001',
          displayName: '林月',
        ),
      ],
    );

    expect(count, 1);
    expect(saved.single.name, '林月·玄霜剑主');
    final decoded = jsonDecode(saved.single.jsonData) as Map<String, dynamic>;
    expect(decoded['name'], '林月·玄霜剑主');
    // 会话内身份不写入最终卡片，保持存档兼容。
    expect(decoded.containsKey('sourceId'), isFalse);
  });

  test('duplicate display names stay distinct by sourceId', () async {
    stubGeneration({
      'items': [
        {'sourceId': 'scene_candidate_001', 'name': '林月', 'description': '甲'},
        {'sourceId': 'scene_candidate_002', 'name': '林月', 'description': '乙'},
      ],
    });
    List<LibraryCardBatchItem> saved = const [];
    when(
      () => repository.saveCardBatch(
        type: any(named: 'type'),
        items: any(named: 'items'),
        mode: any(named: 'mode'),
      ),
    ).thenAnswer((invocation) async {
      saved = invocation.namedArguments[#items] as List<LibraryCardBatchItem>;
      return saved.length;
    });

    final count = await useCase.importSelected(
      buildRequest(),
      const [
        SceneBatchCandidate(
          sourceId: 'scene_candidate_002',
          displayName: '林月',
        ),
      ],
    );

    expect(count, 1);
    final decoded = jsonDecode(saved.single.jsonData) as Map<String, dynamic>;
    expect(decoded['description'], '乙');
  });

  test('unknown sourceId is rejected and never persisted', () async {
    stubGeneration({
      'items': [
        {'sourceId': 'scene_candidate_999', 'name': '陌生人'},
      ],
    });

    await expectLater(
      useCase.importSelected(
        buildRequest(),
        const [
          SceneBatchCandidate(
            sourceId: 'scene_candidate_001',
            displayName: '林月',
          ),
        ],
      ),
      throwsA(isA<ImportValidationException>()),
    );
    verifyNever(
      () => repository.saveCardBatch(
        type: any(named: 'type'),
        items: any(named: 'items'),
        mode: any(named: 'mode'),
      ),
    );
  });

  test('generated item without sourceId is rejected', () async {
    stubGeneration({
      'items': [
        {'name': '林月'},
      ],
    });

    await expectLater(
      useCase.importSelected(
        buildRequest(),
        const [
          SceneBatchCandidate(
            sourceId: 'scene_candidate_001',
            displayName: '林月',
          ),
        ],
      ),
      throwsA(isA<ImportValidationException>()),
    );
    verifyNever(
      () => repository.saveCardBatch(
        type: any(named: 'type'),
        items: any(named: 'items'),
        mode: any(named: 'mode'),
      ),
    );
  });

  test('relationship binds by targetResourceId despite display-name variant',
      () async {
    stubGeneration({
      'items': [
        {
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
      ],
    });
    List<LibraryCardBatchItem> saved = const [];
    when(
      () => repository.saveCardBatch(
        type: any(named: 'type'),
        items: any(named: 'items'),
        mode: any(named: 'mode'),
      ),
    ).thenAnswer((invocation) async {
      saved = invocation.namedArguments[#items] as List<LibraryCardBatchItem>;
      return saved.length;
    });

    await useCase.importSelected(
      buildRequest(related: [
        {'id': 'char_1', 'name': '林月', 'profession': '剑主'},
      ]),
      const [
        SceneBatchCandidate(
          sourceId: 'scene_candidate_001',
          displayName: '林月',
        ),
      ],
    );

    final decoded = jsonDecode(saved.single.jsonData) as Map<String, dynamic>;
    final links = (decoded['relationship_links'] as List).cast<Map>();
    expect(links, hasLength(1));
    expect(links.single['targetResourceId'], 'char_1');
    expect(links.single['targetName'], '林月小姐');
  });

  test('relationship with unknown targetResourceId is dropped', () async {
    stubGeneration({
      'items': [
        {
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
      ],
    });
    List<LibraryCardBatchItem> saved = const [];
    when(
      () => repository.saveCardBatch(
        type: any(named: 'type'),
        items: any(named: 'items'),
        mode: any(named: 'mode'),
      ),
    ).thenAnswer((invocation) async {
      saved = invocation.namedArguments[#items] as List<LibraryCardBatchItem>;
      return saved.length;
    });

    await useCase.importSelected(
      buildRequest(related: [
        {'id': 'char_1', 'name': '林月'},
      ]),
      const [
        SceneBatchCandidate(
          sourceId: 'scene_candidate_001',
          displayName: '林月',
        ),
      ],
    );

    final decoded = jsonDecode(saved.single.jsonData) as Map<String, dynamic>;
    expect(decoded['relationship_links'], isEmpty);
  });

  test('identify assigns stable unique sourceIds', () async {
    when(() => gateway.identifyCharacterNames(any()))
        .thenAnswer((_) async => ['林月', '林月', '苏禾']);

    final candidates = await useCase.identify('原文');

    expect(candidates.map((c) => c.sourceId).toSet(), hasLength(3));
    expect(candidates.map((c) => c.displayName).toList(), ['林月', '林月', '苏禾']);
  });

  test('controller identity is used for generation, not display name',
      () async {
    stubGeneration({'items': const []});

    await expectLater(
      useCase.importSelected(
        buildRequest(),
        const [
          SceneBatchCandidate(
            sourceId: 'scene_candidate_004',
            displayName: '别名角色',
          ),
        ],
      ),
      throwsA(isA<ImportValidationException>()),
    );

    final captured = verify(
      () => gateway.generateSceneBatchCharacters(
        source: any(named: 'source'),
        label: any(named: 'label'),
        worldview: any(named: 'worldview'),
        relatedCharacters: any(named: 'relatedCharacters'),
        selectedCandidates: captureAny(named: 'selectedCandidates'),
        minimumTotalLength: any(named: 'minimumTotalLength'),
        maximumTotalLength: any(named: 'maximumTotalLength'),
        detailInstruction: any(named: 'detailInstruction'),
      ),
    ).captured.single as List<SceneBatchCandidate>;
    expect(captured.single.sourceId, 'scene_candidate_004');
  });
}
