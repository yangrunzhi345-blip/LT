import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('related-character accept does not issue direct relationship SQL', () {
    final source = File(
      'lib/application/resource_library/accept_generated_related_character.dart',
    ).readAsStringSync();
    expect(source, isNot(contains('resource_character_relationships')));
    expect(source, contains('createInTransaction'));
  });

  test('Adventure projection has no live relationship repository dependency',
      () {
    final source = File(
      'lib/application/adventure/resource_relationship_projection.dart',
    ).readAsStringSync();
    expect(source, isNot(contains('CharacterRelationshipRepository')));
    expect(source, contains('selectedResourceIds'));
  });
}
