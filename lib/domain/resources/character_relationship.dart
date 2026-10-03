import 'resource_contracts.dart';

/// Stable machine vocabulary for relationships owned by the resource library.
enum CharacterRelationshipType {
  friend,
  family,
  enemy,
  companion,
  lover,
  mentorStudent,
  parentChild,
  employerEmployee,
  guardianWard,
  rival,
  sibling,
  stranger,
  custom;

  String get storageValue => switch (this) {
        CharacterRelationshipType.mentorStudent => 'mentor_student',
        CharacterRelationshipType.parentChild => 'parent_child',
        CharacterRelationshipType.employerEmployee => 'employer_employee',
        CharacterRelationshipType.guardianWard => 'guardian_ward',
        _ => name,
      };

  static CharacterRelationshipType fromStorageValue(String value) =>
      values.firstWhere(
        (type) => type.storageValue == value,
        orElse: () => throw CharacterRelationshipValidationException(
          CharacterRelationshipFailure.invalidRelationType,
          'Unknown relationship type: $value',
        ),
      );
}

enum CharacterRelationshipFailure {
  invalidEndpoint,
  selfRelationship,
  endpointNotFound,
  endpointNotLive,
  duplicateRelationship,
  invalidRelationType,
  invalidEndpointRoles,
  legacyResourceUnresolved,
}

class CharacterRelationshipValidationException implements Exception {
  const CharacterRelationshipValidationException(this.code, this.message);

  final CharacterRelationshipFailure code;
  final String message;

  @override
  String toString() =>
      'CharacterRelationshipValidationException($code): $message';
}

class CharacterRelationshipConflictException
    extends CharacterRelationshipValidationException {
  const CharacterRelationshipConflictException(String message)
      : super(
          CharacterRelationshipFailure.duplicateRelationship,
          message,
        );
}

/// The two endpoint values after identity canonicalization.
final class CharacterRelationshipEndpoints {
  const CharacterRelationshipEndpoints._(
    this.aResourceId,
    this.bResourceId,
    this.aRole,
    this.bRole,
  );

  final ResourceId aResourceId;
  final ResourceId bResourceId;
  final String aRole;
  final String bRole;

  static CharacterRelationshipEndpoints canonicalize({
    required ResourceId firstResourceId,
    required String firstRole,
    required ResourceId secondResourceId,
    required String secondRole,
  }) {
    final first = firstResourceId.value.trim();
    final second = secondResourceId.value.trim();
    if (first.isEmpty || second.isEmpty) {
      throw const CharacterRelationshipValidationException(
        CharacterRelationshipFailure.invalidEndpoint,
        'Relationship endpoints must not be empty',
      );
    }
    if (first == second) {
      throw const CharacterRelationshipValidationException(
        CharacterRelationshipFailure.selfRelationship,
        'A character cannot relate to itself',
      );
    }
    final leftFirst = first.compareTo(second) < 0;
    return CharacterRelationshipEndpoints._(
      leftFirst ? firstResourceId : secondResourceId,
      leftFirst ? secondResourceId : firstResourceId,
      leftFirst ? firstRole : secondRole,
      leftFirst ? secondRole : firstRole,
    );
  }
}

final class CharacterRelationship {
  const CharacterRelationship({
    required this.id,
    required this.endpointAResourceId,
    required this.endpointBResourceId,
    required this.relationType,
    required this.endpointARole,
    required this.endpointBRole,
    required this.description,
    required this.createdAt,
    required this.updatedAt,
  });

  static const int maxDescriptionLength = 4000;

  final String id;
  final ResourceId endpointAResourceId;
  final ResourceId endpointBResourceId;
  final CharacterRelationshipType relationType;
  final String endpointARole;
  final String endpointBRole;
  final String description;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Projects this canonical edge from one endpoint's perspective.
  CharacterRelationshipPerspective perspectiveFor(ResourceId resourceId) {
    if (resourceId == endpointAResourceId) {
      return CharacterRelationshipPerspective(
        relationshipId: id,
        counterpartResourceId: endpointBResourceId,
        relationType: relationType,
        subjectRole: endpointARole,
        counterpartRole: endpointBRole,
        description: description,
      );
    }
    if (resourceId == endpointBResourceId) {
      return CharacterRelationshipPerspective(
        relationshipId: id,
        counterpartResourceId: endpointAResourceId,
        relationType: relationType,
        subjectRole: endpointBRole,
        counterpartRole: endpointARole,
        description: description,
      );
    }
    throw ArgumentError.value(resourceId, 'resourceId', 'Not an endpoint');
  }

  static void validate({
    required CharacterRelationshipType relationType,
    required String endpointARole,
    required String endpointBRole,
    required String description,
  }) {
    final a = endpointARole.trim();
    final b = endpointBRole.trim();
    if (a.isEmpty || b.isEmpty) {
      throw const CharacterRelationshipValidationException(
        CharacterRelationshipFailure.invalidEndpointRoles,
        'Both endpoint roles are required',
      );
    }
    if (description.length > maxDescriptionLength) {
      throw const CharacterRelationshipValidationException(
        CharacterRelationshipFailure.invalidEndpoint,
        'Relationship description exceeds $maxDescriptionLength characters',
      );
    }
    final directional = <CharacterRelationshipType, Set<String>>{
      CharacterRelationshipType.mentorStudent: {'mentor', 'student'},
      CharacterRelationshipType.parentChild: {'parent', 'child'},
      CharacterRelationshipType.employerEmployee: {'employer', 'employee'},
      CharacterRelationshipType.guardianWard: {'guardian', 'ward'},
    };
    final expected = directional[relationType];
    if (expected != null && {a, b}.length != 2 ||
        expected != null && !expected.contains(a) ||
        expected != null && !expected.contains(b)) {
      throw const CharacterRelationshipValidationException(
        CharacterRelationshipFailure.invalidEndpointRoles,
        'Endpoint roles do not match the directional relationship type',
      );
    }
  }
}

/// A relationship projected for one selected resource.
final class CharacterRelationshipPerspective {
  const CharacterRelationshipPerspective({
    required this.relationshipId,
    required this.counterpartResourceId,
    required this.relationType,
    required this.subjectRole,
    required this.counterpartRole,
    required this.description,
  });

  final String relationshipId;
  final ResourceId counterpartResourceId;
  final CharacterRelationshipType relationType;
  final String subjectRole;
  final String counterpartRole;
  final String description;
}
