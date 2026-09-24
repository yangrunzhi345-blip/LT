import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lt_dialogue/application/resources/resource_creation_contracts.dart';
import 'package:lt_dialogue/application/resources/resource_creation_pipeline.dart';
import 'package:lt_dialogue/controllers/resource_crud_controller.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_limits.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/repositories/library_repository.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository_impl.dart';
import 'package:lt_dialogue/services/resource_integrity_validator.dart';

class _MockLibraryRepository extends Mock implements ILibraryRepository {}

/// A character card whose only body field is `description`, sized to exactly
/// [bodyCharacters] UTF-16 code units so the validator boundary is exact.
String _cardJson(int bodyCharacters) => jsonEncode(<String, Object?>{
      'name': '测试角色',
      'description': '字' * bodyCharacters,
    });

/// A card that carries CJK, emoji and newline content (multi-code-unit chars).
String _unicodeCardJson(int codeUnits) {
  final buffer = StringBuffer();
  const unit = '角色😀设定\n';
  while (buffer.length + unit.length <= codeUnits) {
    buffer.write(unit);
  }
  buffer.write('补' * (codeUnits - buffer.length));
  return jsonEncode(<String, Object?>{
    'name': '万象之影',
    'description': buffer.toString(),
    'personality': '冷静\n果断',
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void validateCharacter(String jsonData) =>
      ResourceIntegrityValidator.validateCharacterCard(
        name: '测试角色',
        jsonData: jsonData,
      );

  group('character card body capacity — 20000 normal / 24000 hard ceiling', () {
    test('accepts the normal edit boundary 19999 and 20000', () {
      expect(() => validateCharacter(_cardJson(19999)), returnsNormally);
      expect(() => validateCharacter(_cardJson(20000)), returnsNormally);
    });

    test('accepts the 20001–24000 elastic buffer (existing/generated data)',
        () {
      for (final size in const [20001, 21000, 23999, 24000]) {
        expect(
          () => validateCharacter(_cardJson(size)),
          returnsNormally,
          reason: '$size characters must stay safely persistable',
        );
      }
    });

    test('rejects 24001 fail-closed with an actionable error', () {
      expect(
        () => validateCharacter(_cardJson(24001)),
        throwsA(
          isA<ResourceValidationException>()
              .having((e) => e.message, 'message', contains('24001'))
              .having((e) => e.message, 'message',
                  contains('${ResourceLimits.characterAbsoluteCharacters}')),
        ),
      );
    });

    test('NPC cards share the same two-level character budget', () {
      expect(
        () => ResourceIntegrityValidator.validateNpcCard(
          name: 'NPC',
          jsonData: _cardJson(24000),
        ),
        returnsNormally,
      );
      expect(
        () => ResourceIntegrityValidator.validateNpcCard(
          name: 'NPC',
          jsonData: _cardJson(24001),
        ),
        throwsA(isA<ResourceValidationException>()),
      );
    });
  });

  group('character card capacity — CJK, emoji and newline content', () {
    test('a mixed-script card within the ceiling is accepted', () {
      final json = _unicodeCardJson(16000);
      expect(() => validateCharacter(json), returnsNormally);
    });

    test('a mixed-script card one code unit over the ceiling is rejected', () {
      final json =
          _unicodeCardJson(ResourceLimits.characterAbsoluteCharacters + 1);
      expect(
        () => validateCharacter(json),
        throwsA(isA<ResourceValidationException>()),
      );
    });
  });

  group('legacy character card data stays readable and re-saveable', () {
    test('a small legacy card passes the capacity gate unchanged', () {
      const legacy =
          '{"name":"旧角色","personality":"寡言","description":"来自旧版本的资料"}';
      expect(
        () => ResourceIntegrityValidator.validateCharacterCard(
          name: '旧角色',
          jsonData: legacy,
        ),
        returnsNormally,
      );
    });
  });

  group('AI generation target authority', () {
    ResourceCreationRequest characterRequest(int? target) =>
        ResourceCreationRequest(
          resourceType: ResourceType.character,
          method: CreationMethod.aiReference,
          name: '测试角色',
          idempotencyKey: 'capacity-key',
          referenceSource: ReferenceSource.text('参考'),
          targetCharacters: target,
        );

    test('accepts a 20000-character generation target', () {
      expect(
        () => ResourceCreationValidator.validate(
          characterRequest(20000),
          hasAiCredentials: () => true,
        ),
        returnsNormally,
      );
    });

    test('rejects a generation target above the nominal cap', () {
      expect(
        () => ResourceCreationValidator.validate(
          characterRequest(20001),
          hasAiCredentials: () => true,
        ),
        throwsA(
          isA<ResourceCreationException>()
              .having((e) => e.field, 'field', 'targetCharacters'),
        ),
      );
    });

    test('worldview keeps its independent 50000/60000 budget', () {
      final policy = ResourceLimits.policyFor(ResourceType.worldview);
      expect(policy.nominalCharacters, 50000);
      expect(policy.absoluteCharacters, 60000);
      expect(
        () => ResourceCreationValidator.validate(
          ResourceCreationRequest(
            resourceType: ResourceType.worldview,
            method: CreationMethod.aiReference,
            name: '世界观',
            idempotencyKey: 'worldview-key',
            referenceSource: ReferenceSource.text('参考'),
            targetCharacters: 50001,
          ),
          hasAiCredentials: () => true,
        ),
        throwsA(isA<ResourceCreationException>()),
      );
    });
  });

  group('manual edit save path end to end', () {
    late Directory tempDir;
    late ResourceCrudController controller;
    late ResourceTreeRepositoryImpl treeRepository;

    setUp(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfiNoIsolate;
      tempDir = await Directory.systemTemp.createTemp('lt_card_capacity_');
      DatabaseService.customDbDir = tempDir.path;
      await DatabaseService.resetDatabase();
      treeRepository =
          ResourceTreeRepositoryImpl(getDb: () => DatabaseService.database);
      controller = ResourceCrudController(
        repository: _MockLibraryRepository(),
        creationPipeline: ResourceCreationPipeline(
          getDb: () => DatabaseService.database,
          hasAiCredentials: () => true,
          treeRepository: treeRepository,
        ),
      );
    });

    tearDown(() async {
      controller.dispose();
      await DatabaseService.resetDatabase();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('saves a 20000-character manual card and rejects 24001', () async {
      final saved = await controller.saveCharacterCard(
        id: 'capacity-normal',
        name: '长卡角色',
        jsonData: _cardJson(20000),
        source: '手动创建',
        now: '2026-09-21T00:00:00.000Z',
      );
      expect(saved.success, isTrue);

      final rejected = await controller.saveCharacterCard(
        id: 'capacity-overflow',
        name: '超限角色',
        jsonData: _cardJson(24001),
        source: '手动创建',
        now: '2026-09-21T00:00:00.000Z',
      );
      expect(rejected.success, isFalse);
      expect(rejected.errorMessage, contains('24000'));
      // The rejected card must never have been written.
      expect(
        await treeRepository.readTree(const ResourceId('capacity-overflow')),
        isNull,
      );
    });
  });
}
