import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/blueprint_prompt_builder.dart';
import 'package:lt_dialogue/application/resources/part_generation_prompt_builder.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_generation_protocol.dart';

void main() {
  group('PartGenerationPromptBuilder', () {
    const request = PartGenerationRequest(
      protocolVersion: 1,
      generationId: 'gen_test_999',
      resourceId: ResourceId('res_alpha'),
      sectionId: SectionId('sec_geo'),
      partId: PartId('part_terrain'),
      attemptId: 'att_test_1',
      targetBudget: 1500,
      promptGoal: '描述大陆的山脉走向与水文地貌',
      context: PartGenerationContext(
        resourceName: '星渊大陆',
        resourceType: ResourceType.worldview,
        resourceSummary: '古老的星辉世界',
        sectionTitle: '自然地理',
        sectionSummary: '地貌与生态',
        partTitle: '地貌地形',
        dependencySummaries: [
          DependencyPartSummary(
            partId: PartId('part_cosmology'),
            title: '创世神话',
            contentSummary: '远古神灵在混沌中劈开光与暗...',
          ),
        ],
        referenceExcerpt: '参考资料：星渊大陆北临冰霜之海，南接无尽炎域。',
        relationshipConstraints:
            '1. sourceResourceId=res_source; relationType=friend; '
            'sourceRole=ally; generatedCharacterRole=ally; '
            'description=共同守城。',
      ),
    );

    test('builds system prompt with exact protocol rules and IDs', () {
      final prompt = PartGenerationPromptBuilder.buildSystemPrompt(request);

      expect(prompt, contains('客户端会绑定 protocol_version'));
      expect(prompt, contains('不要输出或猜测这些固定字段'));
      expect(prompt, contains('"generation_id": "gen_test_999"'));
      expect(prompt, contains('"resource_id": "res_alpha"'));
      expect(prompt, contains('"section_id": "sec_geo"'));
      expect(prompt, contains('"part_id": "part_terrain"'));
      expect(prompt, contains('"attempt_id": "att_test_1"'));
      expect(prompt, contains('最多 1500 字，不得超过'));
      expect(prompt, contains('严禁生成任何其他章节'));
      expect(prompt, contains('严禁篡改 ID'));
      expect(prompt, contains('不得输出 "cursor"'));
      expect(prompt, contains('Dart UTF-16 code-unit'));
      expect(prompt, contains('绝不能估算、填写或修改它'));
      expect(prompt, contains('{"sequence":0,"op":"start_part"}'));
    });

    test(
        'builds user instruction with bounded dependencies and reference excerpt',
        () {
      final instruction = PartGenerationPromptBuilder.buildInstruction(request);

      expect(instruction, contains('星渊大陆'));
      expect(instruction, contains('自然地理'));
      expect(instruction, contains('地貌地形'));
      expect(instruction, contains('描述大陆的山脉走向与水文地貌'));
      expect(instruction, contains('创世神话'));
      expect(instruction, contains('远古神灵在混沌中劈开光与暗'));
      expect(instruction, contains('参考资料：星渊大陆北临冰霜之海'));
      expect(instruction, contains('【关系约束（用户确认）】'));
      expect(instruction, contains('sourceResourceId=res_source'));
      expect(instruction, contains('generatedCharacterRole=ally'));
    });

    test('truncates long dependency context to bounds', () {
      final longReq = PartGenerationRequest(
        protocolVersion: 1,
        generationId: 'gen_test',
        resourceId: const ResourceId('res_alpha'),
        sectionId: const SectionId('sec_geo'),
        partId: const PartId('part_terrain'),
        attemptId: 'att_test_1',
        targetBudget: 1000,
        promptGoal: '目标',
        context: PartGenerationContext(
          resourceName: '大陆',
          resourceType: ResourceType.worldview,
          resourceSummary: '总结',
          sectionTitle: '章节',
          sectionSummary: '总结',
          partTitle: '部件',
          dependencySummaries: [
            DependencyPartSummary(
              partId: const PartId('dep_1'),
              title: '长依赖',
              contentSummary: 'A' * 2500,
            ),
          ],
        ),
      );

      final instruction = PartGenerationPromptBuilder.buildInstruction(longReq);
      expect(instruction, contains('（已截断）'));
      // Verifying bounded length: truncated to 1500 + suffix
      expect(instruction.contains('A' * 1600), isFalse);
    });

    test('truncates long reference excerpt to bounds', () {
      final longReq = PartGenerationRequest(
        protocolVersion: 1,
        generationId: 'gen_test',
        resourceId: const ResourceId('res_alpha'),
        sectionId: const SectionId('sec_geo'),
        partId: const PartId('part_terrain'),
        attemptId: 'att_test_1',
        targetBudget: 1000,
        promptGoal: '目标',
        context: PartGenerationContext(
          resourceName: '大陆',
          resourceType: ResourceType.worldview,
          resourceSummary: '总结',
          sectionTitle: '章节',
          sectionSummary: '总结',
          partTitle: '部件',
          referenceExcerpt: 'B' * 3000,
        ),
      );

      final instruction = PartGenerationPromptBuilder.buildInstruction(longReq);
      expect(instruction, contains('（已截断）'));
      expect(instruction.contains('B' * 2100), isFalse);
    });

    test('indexes large references once and keeps every Part excerpt bounded',
        () {
      final reference = [
        '角色核心资料。',
        'A' * 14000,
        '霜火世界的北境有一座长夜城，城墙由黑曜石砌成。',
        'B' * 14000,
        'C' * 14000,
      ].join('\n\n');
      final index = ReferenceContextIndex(reference);

      expect(index.fullReference.length, greaterThan(30000));
      expect(index.paragraphs, hasLength(5));
      expect(
        PartGenerationPromptBuilder.selectRelevantReference(
          index,
          keywords: const ['长夜城', '北境'],
        ),
        allOf(
          contains('长夜城'),
          predicate<String>((excerpt) => excerpt.length <= 1500),
        ),
      );
      expect(
        PartGenerationPromptBuilder.maxReferenceCharacters,
        1500,
      );
    });

    test('preserves the blueprint and dependency context limits', () {
      expect(BlueprintPromptBuilder.maxReferenceCharsInPrompt, 8000);
      expect(
        PartGenerationPromptBuilder.maxAggregateDependencyCharacters,
        3000,
      );
    });

    test('never throws when a paragraph just misses the remaining budget', () {
      // Regression: the first non-fitting paragraph used to be truncated with
      // `substring(0, remaining)`, which throws a RangeError when its length is
      // exactly `remaining - 1`. That RangeError propagated as an unclassified
      // "unknown" generation failure for any long reference (for example an
      // associated worldview), because the short-reference path returns early.
      for (var len = 1450; len <= 1560; len++) {
        final top = 'K${'a' * (len - 1)}';
        final reference = '$top\n\n${'K' * 10}\n\n${'b' * 3000}';
        final index = ReferenceContextIndex(reference);
        final excerpt = PartGenerationPromptBuilder.selectRelevantReference(
          index,
          keywords: const ['K'],
        );
        expect(
          excerpt.length,
          lessThanOrEqualTo(PartGenerationPromptBuilder.maxReferenceCharacters),
          reason: 'len=$len must stay bounded',
        );
      }
    });

    test('selects important tail context by keyword instead of prefix-only',
        () {
      final head = List.generate(12, (i) => '普通段落$i ${'a' * 800}').join('\n\n');
      const tail = '银月城的守夜人组织只在北门活动，与角色的过往直接相关。';
      final index = ReferenceContextIndex('$head\n\n$tail');

      final excerpt = PartGenerationPromptBuilder.selectRelevantReference(
        index,
        keywords: const ['守夜人'],
      );

      expect(excerpt, contains('守夜人'));
      expect(excerpt, contains('北门'));
      expect(
        excerpt.length,
        lessThanOrEqualTo(PartGenerationPromptBuilder.maxReferenceCharacters),
      );
    });
  });
}
