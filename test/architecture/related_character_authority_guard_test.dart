import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Adventure projection has no live relationship repository dependency',
      () {
    final source = File(
      'lib/application/adventure/resource_relationship_projection.dart',
    ).readAsStringSync();
    expect(source, isNot(contains('CharacterRelationshipRepository')));
    expect(source, contains('selectedResourceIds'));
  });
}
