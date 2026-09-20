import 'package:flutter_test/flutter_test.dart';
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
      ),
    );

    test('builds system prompt with exact protocol rules and IDs', () {
      final prompt = PartGenerationPromptBuilder.buildSystemPrompt(request);

      expect(prompt, contains('"protocol_version": 1'));
      expect(prompt, contains('REQUIRED'));
      expect(prompt, contains('JSON integer'));
      expect(prompt, contains('禁止字符串、null 或省略'));
      expect(prompt, contains('"generation_id": "gen_test_999"'));
      expect(prompt, contains('"resource_id": "res_alpha"'));
      expect(prompt, contains('"section_id": "sec_geo"'));
      expect(prompt, contains('"part_id": "part_terrain"'));
      expect(prompt, contains('"attempt_id": "att_test_1"'));
      expect(prompt, contains('约 1500 字'));
      expect(prompt, contains('严禁生成任何其他章节'));
      expect(prompt, contains('严禁篡改 ID'));
      expect(prompt, contains('不得输出 "cursor"'));
      expect(prompt, contains('Dart UTF-16 code-unit'));
      expect(prompt, contains('绝不能估算、填写或修改它'));
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
  });
}
