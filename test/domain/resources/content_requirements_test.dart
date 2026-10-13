import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/blueprint_parser.dart';
import 'package:lt_dialogue/application/resources/blueprint_validator.dart';
import 'package:lt_dialogue/application/resources/part_generation_validator.dart';
import 'package:lt_dialogue/domain/resources/content_requirements.dart';
import 'package:lt_dialogue/domain/resources/resource_blueprint.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';

void main() {
  // Explicit fixture values exercise contracts, not a product default threshold.
  final narrative = ContentRequirements(
    kind: PartContentKind.narrative,
    minimumCharacters: 180,
    validationProfile: PartValidationProfile.narrativeSectionsV1,
    requiredHeadings: ['经历', '动机'],
  );
  final scalar = ContentRequirements(
    kind: PartContentKind.scalar,
    minimumCharacters: 1,
    validationProfile: PartValidationProfile.scalarTextV1,
  );
  final structured = ContentRequirements(
    kind: PartContentKind.structured,
    minimumCharacters: 1,
    validationProfile: PartValidationProfile.structuredObjectV1,
    requiredFields: ['name', 'relations'],
  );
  final body = '## 经历\n${'从军经历。' * 25}\n## 动机\n${'守护故乡。' * 25}';

  group('PartContentRequirementsValidator', () {
    for (final short in ['荒', '导师', ' ' * 180]) {
      test('should reject insufficient narrative with ${short.length} units',
          () {
        expect(
          () => PartGenerationValidator.validateContentRequirements(
              content: short, requirements: narrative),
          throwsA(isA<ContentRequirementException>().having(
              (error) => error.reason,
              'reason',
              ContentRequirementFailure.belowMinimum)),
        );
      });
    }
    test('should accept a short scalar without inferring type from its title',
        () {
      for (final value in ['荒', '导师', '🙂']) {
        expect(
            PartGenerationValidator.validateContentRequirements(
                content: value, requirements: scalar),
            PartContentReview.validated);
      }
      expect(() => PartContentRequirementsValidator.validate('导师\n盟友', scalar),
          throwsA(isA<ContentRequirementException>()));
    });
    test('should require actual nonempty narrative sections', () {
      expect(PartContentRequirementsValidator.validate(body, narrative),
          PartContentReview.validated);
      for (final invalid in [
        '已覆盖经历与动机${'文' * 180}',
        '## 经历\n${'文' * 180}\n## 动机',
        '## 经历\n## 动机\n${'文' * 180}',
      ]) {
        expect(
            () => PartContentRequirementsValidator.validate(invalid, narrative),
            throwsA(isA<ContentRequirementException>().having(
                (error) => error.reason,
                'reason',
                ContentRequirementFailure.missingHeading)));
      }
    });
    test('should reject headings inside code and prose padded with whitespace',
        () {
      for (final invalid in [
        '```markdown\n$body\n```',
        '~~~markdown\n$body\n~~~',
        body.split('\n').map((line) => '    $line').join('\n'),
        body.split('\n').map((line) => '\t$line').join('\n'),
        '## 经历\n```\n${'示例' * 100}\n```\n## 动机\n动机',
        '## 经历\n    ${'示例' * 100}\n## 动机\n动机',
        '## 经历\n短经历\n## 动机\n短动机${' ' * 180}',
      ]) {
        expect(
            () => PartContentRequirementsValidator.validate(invalid, narrative),
            throwsA(isA<ContentRequirementException>()));
      }
    });
    test(
        'should recognize real sections around fenced examples and closing hashes',
        () {
      final valid = '```markdown\n## 经历\n示例\n```\n'
          '### 经历 ###\n${'经历正文。' * 25}\n'
          '~~~\n## 动机\n示例\n~~~\n'
          '  ## 动机\n${'动机正文。' * 25}';
      expect(PartContentRequirementsValidator.validate(valid, narrative),
          PartContentReview.validated);
    });
    test(
        'should verify structured fields in the body, preserving false and zero',
        () {
      expect(
          PartContentRequirementsValidator.validate(
              '{"name":false,"relations":0}', structured),
          PartContentReview.validated);
      for (final invalid in [
        '[]',
        '{',
        '{}',
        '{"name":"林恩","relations":null}',
        '{"name":" ","relations":[1]}',
        '{"name":"林恩","relations":[]}',
        '{"name":"林恩","relations":{}}'
      ]) {
        expect(
            () =>
                PartContentRequirementsValidator.validate(invalid, structured),
            throwsA(isA<ContentRequirementException>()));
      }
    });
    test('should leave unknown legacy content for review without altering it',
        () {
      for (final value in ['荒', '导师', body]) {
        expect(PartContentRequirementsValidator.validate(value, null),
            PartContentReview.needsContentReview);
      }
    });
    test('should reject unsupported contracts and mismatched profiles', () {
      for (final invalid in [
        ContentRequirements(
            version: 2,
            kind: narrative.kind,
            minimumCharacters: 180,
            validationProfile: narrative.validationProfile),
        ContentRequirements(
            kind: narrative.kind,
            minimumCharacters: 0,
            validationProfile: narrative.validationProfile),
        ContentRequirements(
            kind: narrative.kind,
            minimumCharacters: 3001,
            validationProfile: narrative.validationProfile),
        ContentRequirements(
            kind: narrative.kind,
            minimumCharacters: 180,
            validationProfile: scalar.validationProfile),
        ContentRequirements(
            kind: structured.kind,
            minimumCharacters: 1,
            validationProfile: structured.validationProfile),
        ContentRequirements(
            kind: narrative.kind,
            minimumCharacters: 180,
            validationProfile: narrative.validationProfile,
            requiredHeadings: ['动机', '动机']),
      ]) {
        expect(invalid.validateDefinition,
            throwsA(isA<ContentRequirementException>()));
      }
    });
    test('should keep contract lists immutable', () {
      final labels = ['动机'];
      final contract = ContentRequirements(
          kind: narrative.kind,
          minimumCharacters: 180,
          validationProfile: narrative.validationProfile,
          requiredHeadings: labels);
      labels.add('经历');
      expect(contract.requiredHeadings, ['动机']);
      expect(() => contract.requiredHeadings.add('经历'), throwsUnsupportedError);
    });
  });

  group('Blueprint content requirements compatibility', () {
    ResourceBlueprint blueprint(ContentRequirements? requirements) =>
        ResourceBlueprint(
          blueprintId: 'bp_contract',
          sessionId: 'session_contract',
          resourceType: ResourceType.character,
          suggestedName: '林恩',
          summary: '角色',
          targetCapacity: 450,
          sections: [
            BlueprintSection(id: 'sec_1', title: '人物', parts: [
              BlueprintPart(
                  id: 'part_1',
                  sectionId: 'sec_1',
                  title: '导师',
                  generationGoal: '人物经历与动机',
                  estimatedLength: 450,
                  contentRequirements: requirements),
            ])
          ],
        );
    ResourceBlueprint decode(String value) =>
        BlueprintParser.deserializeFromJson(value,
            blueprintId: 'bp_contract',
            sessionId: 'session_contract',
            resourceType: ResourceType.character);

    test(
        'should round trip each versioned contract including equality and copy',
        () {
      for (final requirements in [narrative, scalar, structured]) {
        final original = blueprint(requirements);
        final stored = decode(BlueprintParser.serializeToJson(original));
        expect(stored, original);
        expect(stored.hashCode, original.hashCode);
        expect(stored.allParts.single.copyWith(title: '变更').contentRequirements,
            requirements);
        expect(
            () => BlueprintValidator.validate(stored, maxBudgetOverride: 450),
            returnsNormally);
      }
    });
    test(
        'should preserve absence in legacy JSON without synthesizing a contract',
        () {
      final original = blueprint(null);
      final json = BlueprintParser.serializeToJson(original);
      expect(json, isNot(contains('contentRequirements')));
      expect(decode(json), original);
      expect(decode(json).allParts.single.contentRequirements, isNull);
    });
    test(
        'should reject malformed or unknown contracts rather than downgrade to legacy',
        () {
      for (final raw in [
        null,
        'narrative',
        {'version': 1},
        {...narrative.toMap(), 'version': 2},
        {...narrative.toMap(), 'minimumCharacters': 1.5},
        {...narrative.toMap(), 'required': 'true'},
        {...narrative.toMap(), 'validationProfile': 'modelProvidedCode'},
        {
          ...narrative.toMap(),
          'requiredHeadings': [1]
        },
        {...narrative.toMap(), 'executable': 'rule'}
      ]) {
        final map = jsonDecode(BlueprintParser.serializeToJson(blueprint(null)))
            as Map<String, dynamic>;
        final section = (map['sections'] as List).single as Map;
        final part = (section['parts'] as List).single as Map;
        part['contentRequirements'] = raw;
        expect(() => decode(jsonEncode(map)),
            throwsA(isA<BlueprintParseException>()));
      }
    });
    test(
        'should reject a minimum above the plan without changing IDs or dependencies',
        () {
      final original = blueprint(ContentRequirements(
          kind: narrative.kind,
          minimumCharacters: 451,
          validationProfile: narrative.validationProfile));
      expect(() => BlueprintValidator.validate(original),
          throwsA(isA<BlueprintValidationException>()));
      expect(original.allParts.single.id, 'part_1');
      expect(original.allParts.single.dependencies, isEmpty);
    });
  });
}
