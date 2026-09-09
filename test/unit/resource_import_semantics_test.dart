import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:lt_dialogue/application/llm/llm_gateway.dart';
import 'package:lt_dialogue/application/resource_library/import_models.dart';
import 'package:lt_dialogue/application/resource_library/import_use_cases.dart';
import 'package:lt_dialogue/services/repositories/library_repository.dart';

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
}
