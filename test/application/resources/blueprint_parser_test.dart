import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/blueprint_parser.dart';
import 'package:lt_dialogue/application/resources/blueprint_prompt_builder.dart';
import 'package:lt_dialogue/application/resources/resource_creation_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_blueprint.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';

void main() {
  group('BlueprintPromptBuilder', () {
    test('bounds large reference source', () {
      final largeBody = 'A' * 12000;
      final ref = ReferenceSource.text(largeBody);
      final instruction = BlueprintPromptBuilder.buildUserInstruction(
        resourceName: '宏大世界',
        resourceType: ResourceType.worldview,
        referenceSource: ref,
      );

      expect(instruction, contains('已截取前 8000 字符'));
      expect(instruction.contains('A' * 8001), isFalse);
    });

    test('injects pre-allocated ID pool into system prompt', () {
      final pool = BlueprintIdPool.createDefault(maxSections: 3, maxParts: 6);
      final sysPrompt = BlueprintPromptBuilder.buildSystemPrompt(
        resourceType: ResourceType.character,
        idPool: pool,
      );

      expect(sysPrompt, contains('sec_1, sec_2, sec_3'));
      expect(sysPrompt,
          contains('part_1, part_2, part_3, part_4, part_5, part_6'));
      expect(sysPrompt, contains('核心主角/主要角色卡'));
    });
  });

  group('BlueprintParser', () {
    test('parses raw LLM response wrapped in markdown code fence', () {
      const raw = '''
好的，这是为您规划的世界观大纲：
```json
{
  "suggestedName": "灵渊之界",
  "summary": "以灵渊为核心的世界",
  "sections": [
    {
      "id": "sec_1",
      "title": "世界起源",
      "summary": "灵渊诞生的传说",
      "sortOrder": 0,
      "parts": [
        {
          "id": "part_1",
          "sectionId": "sec_1",
          "title": "渊底初生",
          "generationGoal": "描写最初的混沌神祇",
          "estimatedLength": 800,
          "dependencies": [],
          "sortOrder": 0
        },
        {
          "id": "part_2",
          "sectionId": "sec_1",
          "title": "法则分化",
          "generationGoal": "描写阴阳五行分化",
          "estimatedLength": 1000,
          "dependencies": ["part_1"],
          "sortOrder": 1
        }
      ]
    }
  ]
}
```
希望对您有帮助！
''';

      final bp = BlueprintParser.parseLlmResponse(
        rawOutput: raw,
        blueprintId: 'bp_123',
        sessionId: 'cre_456',
        resourceType: ResourceType.worldview,
      );

      expect(bp.suggestedName, '灵渊之界');
      expect(bp.summary, '以灵渊为核心的世界');
      expect(bp.sections.length, 1);
      expect(bp.sections[0].parts.length, 2);
      expect(bp.sections[0].parts[1].dependencies, ['part_1']);
      expect(bp.totalEstimatedLength, 1800);
    });

    test('throws BlueprintParseException on malformed JSON', () {
      const raw = '```json\n{ "invalidJson": \n```';
      expect(
        () => BlueprintParser.parseLlmResponse(
          rawOutput: raw,
          blueprintId: 'bp_1',
          sessionId: 'cre_1',
          resourceType: ResourceType.worldview,
        ),
        throwsA(isA<BlueprintParseException>()),
      );
    });

    test('serializes to JSON and deserializes back faithfully', () {
      final original = ResourceBlueprint(
        blueprintId: 'bp_rt',
        sessionId: 'cre_rt',
        resourceType: ResourceType.character,
        suggestedName: '白袍剑圣',
        summary: '追求极致剑道的人物',
        revision: 2,
        status: BlueprintStatus.confirmed,
        sections: [
          BlueprintSection(
            id: 'sec_1',
            title: '人物核心',
            sortOrder: 0,
            parts: [
              const BlueprintPart(
                id: 'part_1',
                sectionId: 'sec_1',
                title: '性格与立誓',
                generationGoal: '描写其一往无前的决心',
                estimatedLength: 600,
                sortOrder: 0,
              ),
            ],
          ),
        ],
      );

      final jsonStr = BlueprintParser.serializeToJson(original);
      final deserialized = BlueprintParser.deserializeFromJson(
        jsonStr,
        blueprintId: 'bp_rt',
        sessionId: 'cre_rt',
        resourceType: ResourceType.character,
        revision: 2,
        status: BlueprintStatus.confirmed,
      );

      expect(deserialized.suggestedName, original.suggestedName);
      expect(deserialized.summary, original.summary);
      expect(deserialized.sections.length, original.sections.length);
      expect(deserialized.allParts.first.generationGoal,
          original.allParts.first.generationGoal);
      expect(deserialized.revision, 2);
      expect(deserialized.status, BlueprintStatus.confirmed);
    });
  });
}
