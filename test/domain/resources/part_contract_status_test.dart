import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/domain/resources/content_requirements.dart';
import 'package:lt_dialogue/domain/resources/part_contract_status.dart';
import 'package:lt_dialogue/domain/resources/resource_blueprint.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';

/// U6-D pure projection: status comes only from creation metadata + the
/// confirmed blueprint's contract, never from task presence or body length.
void main() {
  final requirements = ContentRequirements(
    kind: PartContentKind.narrative,
    minimumCharacters: 100,
    validationProfile: PartValidationProfile.narrativeSectionsV1,
  );

  ResourceBlueprint blueprint(List<BlueprintPart> parts) => ResourceBlueprint(
        blueprintId: 'bp',
        sessionId: 'cs',
        resourceType: ResourceType.character,
        suggestedName: '资源',
        summary: '',
        targetCapacity: 5000,
        sections: [BlueprintSection(id: 's', title: '背景', parts: parts)],
      );

  BlueprintPart part(String id, {ContentRequirements? contract}) =>
      BlueprintPart(
          id: id,
          sectionId: 's',
          title: id,
          generationGoal: 'g',
          estimatedLength: 500,
          contentRequirements: contract);

  group('isAiCreatedResource', () {
    test('true only for aiReference with a creation session', () {
      expect(
          PartContractProjection.isAiCreatedResource(
              authoringMethod: 'aiReference', creationSessionId: 'cs1'),
          isTrue);
      expect(
          PartContractProjection.isAiCreatedResource(
              authoringMethod: 'manual', creationSessionId: 'cs1'),
          isFalse);
      expect(
          PartContractProjection.isAiCreatedResource(
              authoringMethod: 'aiReference', creationSessionId: ''),
          isFalse);
      expect(
          PartContractProjection.isAiCreatedResource(
              authoringMethod: 'aiReference', creationSessionId: null),
          isFalse);
      expect(
          PartContractProjection.isAiCreatedResource(
              authoringMethod: null, creationSessionId: 'cs1'),
          isFalse);
    });
  });

  group('project', () {
    test('a manual/imported resource is notApplicable for every Part', () {
      final statuses = PartContractProjection.project(
        isAiResource: false,
        confirmedBlueprint: blueprint([part('res_x_p0')]),
        resourceId: 'res_x',
        partIds: ['res_x_p0', 'res_x_p1'],
      );
      expect(statuses.values, everyElement(PartContractStatus.notApplicable));
    });

    test('an AI resource with a confirmed contract is confirmedContract', () {
      final statuses = PartContractProjection.project(
        isAiResource: true,
        confirmedBlueprint: blueprint([part('p0', contract: requirements)]),
        resourceId: 'res_x',
        partIds: ['res_x_p0'],
      );
      expect(statuses['res_x_p0'], PartContractStatus.confirmedContract);
    });

    test('an AI resource whose Part has no contract is legacyUnknownContract',
        () {
      final statuses = PartContractProjection.project(
        isAiResource: true,
        confirmedBlueprint: blueprint([part('p0')]),
        resourceId: 'res_x',
        partIds: ['res_x_p0'],
      );
      expect(statuses['res_x_p0'], PartContractStatus.legacyUnknownContract);
    });

    test('a missing blueprint is unavailable, never legacy', () {
      final statuses = PartContractProjection.project(
        isAiResource: true,
        confirmedBlueprint: null,
        resourceId: 'res_x',
        partIds: ['res_x_p0'],
      );
      expect(statuses['res_x_p0'], PartContractStatus.unavailable);
    });

    test('a Part absent from the blueprint is unavailable, not legacy', () {
      final statuses = PartContractProjection.project(
        isAiResource: true,
        confirmedBlueprint: blueprint([part('other')]),
        resourceId: 'res_x',
        partIds: ['res_x_missing'],
      );
      expect(statuses['res_x_missing'], PartContractStatus.unavailable);
    });

    test('mixes statuses within one AI resource', () {
      final statuses = PartContractProjection.project(
        isAiResource: true,
        confirmedBlueprint: blueprint([
          part('a', contract: requirements),
          part('b'),
        ]),
        resourceId: 'res_x',
        partIds: ['res_x_a', 'res_x_b', 'res_x_c'],
      );
      expect(statuses['res_x_a'], PartContractStatus.confirmedContract);
      expect(statuses['res_x_b'], PartContractStatus.legacyUnknownContract);
      expect(statuses['res_x_c'], PartContractStatus.unavailable);
    });
  });
}
