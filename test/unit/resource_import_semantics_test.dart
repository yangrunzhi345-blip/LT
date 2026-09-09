import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:lt_dialogue/application/llm/llm_gateway.dart';
import 'package:lt_dialogue/application/resource_library/import_models.dart';
import 'package:lt_dialogue/application/resource_library/import_use_cases.dart';
import 'package:lt_dialogue/controllers/resource_crud_controller.dart';
import 'package:lt_dialogue/models/resource_library_mode.dart';
import 'package:lt_dialogue/services/repositories/library_repository.dart';
import 'package:lt_dialogue/services/resource_integrity_validator.dart';
import 'package:lt_dialogue/models/resource_provenance.dart';

class _MockLlmGateway extends Mock implements LlmGateway {}

class _MockLibraryRepository extends Mock implements ILibraryRepository {}

void main() {
  group('ResourceCardImportUseCase', () {
    late _MockLlmGateway gateway;
    late ResourceCardImportUseCase useCase;

    setUp(() {
      gateway = _MockLlmGateway();
      useCase = ResourceCardImportUseCase(
        gateway: gateway,
        repository: _MockLibraryRepository(),
      );
      when(() => gateway.isConfigured).thenReturn(true);
      when(
        () => gateway.generateResourceCharacter(
          source: any(named: 'source'),
          worldview: any(named: 'worldview'),
          associatedCharacters: any(named: 'associatedCharacters'),
        ),
      ).thenAnswer((_) async => {'name': '艾琳', 'background': '北境骑士'});
      when(
        () => gateway.generateDetailedResourceCharacter(
          source: any(named: 'source'),
          worldview: any(named: 'worldview'),
          associatedCharacters: any(named: 'associatedCharacters'),
          targetTotalCharacters: any(named: 'targetTotalCharacters'),
          onProgress: any(named: 'onProgress'),
        ),
      ).thenAnswer((_) async => {'name': '艾琳', 'background': '北境骑士'});
    });

    test('should keep simple pipeline when instruction contains detailed text',
        () async {
      await useCase.generate(
        const ResourceCardImportRequest(
          kind: ResourceCardImportKind.character,
          source: '艾琳的原始资料',
          detailInstruction: '请详细说明她和母亲的关系',
          aiDepth: AiGenerationDepth.simple,
        ),
      );

      verify(
        () => gateway.generateResourceCharacter(
          source: any(named: 'source'),
          worldview: any(named: 'worldview'),
          associatedCharacters: any(named: 'associatedCharacters'),
        ),
      ).called(1);
      verifyNever(
        () => gateway.generateDetailedResourceCharacter(
          source: any(named: 'source'),
          worldview: any(named: 'worldview'),
          associatedCharacters: any(named: 'associatedCharacters'),
          targetTotalCharacters: any(named: 'targetTotalCharacters'),
          onProgress: any(named: 'onProgress'),
        ),
      );
    });

    test('should use detailed pipeline only when explicit depth is detailed',
        () async {
      await useCase.generate(
        const ResourceCardImportRequest(
          kind: ResourceCardImportKind.character,
          source: '艾琳的原始资料',
          detailInstruction: '简单整理',
          aiDepth: AiGenerationDepth.detailed,
        ),
      );

      verify(
        () => gateway.generateDetailedResourceCharacter(
          source: any(named: 'source'),
          worldview: any(named: 'worldview'),
          associatedCharacters: any(named: 'associatedCharacters'),
          targetTotalCharacters: any(named: 'targetTotalCharacters'),
          onProgress: any(named: 'onProgress'),
        ),
      ).called(1);
      verifyNever(
        () => gateway.generateResourceCharacter(
          source: any(named: 'source'),
          worldview: any(named: 'worldview'),
          associatedCharacters: any(named: 'associatedCharacters'),
        ),
      );
    });

    test('should reject manual authoring before calling AI', () async {
      expect(
        () => useCase.generate(
          const ResourceCardImportRequest(
            kind: ResourceCardImportKind.character,
            source: '艾琳的原始资料',
            authoringMethod: ResourceAuthoringMethod.manual,
            aiDepth: AiGenerationDepth.simple,
          ),
        ),
        throwsA(isA<ImportValidationException>()),
      );
      verifyNever(
        () => gateway.generateResourceCharacter(
          source: any(named: 'source'),
          worldview: any(named: 'worldview'),
          associatedCharacters: any(named: 'associatedCharacters'),
        ),
      );
    });

    test('should preserve distinct relationship inputs for each character',
        () async {
      await useCase.generate(
        const ResourceCardImportRequest(
          kind: ResourceCardImportKind.character,
          source: '生成一位白港炼金师',
          aiDepth: AiGenerationDepth.simple,
          associatedRelations: [
            CharacterGenerationRelationInput(
              characterId: 'a',
              characterName: '阿尔玛',
              relationType: '姐姐',
            ),
            CharacterGenerationRelationInput(
              characterId: 'b',
              characterName: '贝恩',
              relationType: '对手',
            ),
          ],
        ),
      );

      final invocation = verify(
        () => gateway.generateResourceCharacter(
          source: any(named: 'source'),
          worldview: any(named: 'worldview'),
          associatedCharacters: captureAny(named: 'associatedCharacters'),
        ),
      ).captured.single as List<Map<String, String>>;
      expect(invocation[0]['relation'], '姐姐');
      expect(invocation[1]['relation'], '对手');
    });
  });

  group('ImportWorldviewUseCase', () {
    test('should use the explicitly selected simple pipeline', () async {
      final gateway = _MockLlmGateway();
      when(() => gateway.isConfigured).thenReturn(true);
      when(() => gateway.generateWorldview(any())).thenAnswer(
        (_) async => {'name': '北境', 'description': '寒冷的边境世界'},
      );
      final useCase = ImportWorldviewUseCase(
        gateway: gateway,
        repository: _MockLibraryRepository(),
      );

      final draft = await useCase.generate(
        const WorldviewImportRequest(
          source: '请详细说明城市风格',
          aiDepth: AiGenerationDepth.simple,
        ),
      );

      expect(draft.name, '北境');
      verify(() => gateway.generateWorldview(any())).called(1);
      verifyNever(
        () => gateway.generateDetailedWorldview(
          any(),
          targetTotalCharacters: any(named: 'targetTotalCharacters'),
          onProgress: any(named: 'onProgress'),
        ),
      );
    });
  });

  group('ResourceIntegrityValidator', () {
    test('should save a sparse character while reporting incomplete readiness',
        () {
      const jsonData = '{"name":"艾琳","description":"北境骑士"}';

      expect(
        () => ResourceIntegrityValidator.validateCharacterCard(
          name: '艾琳',
          jsonData: jsonData,
        ),
        returnsNormally,
      );
      expect(
        ResourceIntegrityValidator.evaluateCharacterReadiness(jsonData)
            .readiness,
        RoleplayReadiness.incomplete,
      );
    });
  });

  group('ResourceCardImportUseCase detailed save', () {
    test('should reject an incomplete detailed draft before persistence',
        () async {
      final repository = _MockLibraryRepository();
      final useCase = ResourceCardImportUseCase(
        gateway: _MockLlmGateway(),
        repository: repository,
      );
      const draft = ResourceCardImportDraft(
        kind: ResourceCardImportKind.character,
        items: [
          {
            'name': '艾莉诺亚',
            'gender': '女',
            'age': '22',
            'profession': '学者',
            'description': '尚未完成的背景',
          },
        ],
        provenance: ResourceProvenance(
          method: ResourceAuthoringMethod.aiReference,
          aiDepth: AiGenerationDepth.detailed,
        ),
        targetTotalCharacters: 1000,
      );

      await expectLater(
        useCase.save(draft, mode: ResourceLibraryMode.adventure),
        throwsA(isA<ImportValidationException>()),
      );
      verifyNever(
        () => repository.saveCharacterCard(
          id: any(named: 'id'),
          name: any(named: 'name'),
          jsonData: any(named: 'jsonData'),
          source: any(named: 'source'),
          now: any(named: 'now'),
          matchingWorldviewId: any(named: 'matchingWorldviewId'),
          weight: any(named: 'weight'),
          contentHash: any(named: 'contentHash'),
          authoringMethod: any(named: 'authoringMethod'),
          aiGenerationDepth: any(named: 'aiGenerationDepth'),
          mode: ResourceLibraryMode.adventure,
        ),
      );
    });
  });

  group('ResourceCrudController manual authoring', () {
    test('should validate and save manual character without an AI dependency',
        () async {
      final repository = _MockLibraryRepository();
      when(
        () => repository.saveCharacterCard(
          id: any(named: 'id'),
          name: any(named: 'name'),
          jsonData: any(named: 'jsonData'),
          source: any(named: 'source'),
          now: any(named: 'now'),
          matchingWorldviewId: any(named: 'matchingWorldviewId'),
          weight: any(named: 'weight'),
          contentHash: any(named: 'contentHash'),
          authoringMethod: any(named: 'authoringMethod'),
          aiGenerationDepth: any(named: 'aiGenerationDepth'),
          mode: ResourceLibraryMode.adventure,
        ),
      ).thenAnswer((_) async {});
      final controller = ResourceCrudController(repository: repository);
      addTearDown(controller.dispose);

      final result = await controller.saveCharacterCard(
        id: 'manual-character',
        name: '艾琳',
        jsonData: '{"name":"艾琳","description":"北境骑士"}',
        source: '手动创建',
        now: '2026-09-09T00:00:00.000Z',
      );

      expect(result.success, isTrue);
      verify(
        () => repository.saveCharacterCard(
          id: 'manual-character',
          name: '艾琳',
          jsonData: any(named: 'jsonData'),
          source: '手动创建',
          now: any(named: 'now'),
          matchingWorldviewId: any(named: 'matchingWorldviewId'),
          weight: any(named: 'weight'),
          contentHash: any(named: 'contentHash'),
          authoringMethod: ResourceAuthoringMethod.manual.name,
          aiGenerationDepth: any(named: 'aiGenerationDepth'),
          mode: ResourceLibraryMode.adventure,
        ),
      ).called(1);
    });
  });
}
