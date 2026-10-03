import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/domain/resources/character_relationship.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/features/resource_library/presentation/widgets/character_relationships_section.dart';

void main() {
  testWidgets('renders counterpart role and long description', (tester) async {
    final perspective = CharacterRelationshipPerspective(
      relationshipId: 'edge',
      counterpartResourceId: const ResourceId('res_b'),
      relationType: CharacterRelationshipType.friend,
      subjectRole: 'friend',
      counterpartRole: 'trusted friend',
      description: 'A long relationship description ' * 20,
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: CharacterRelationshipsSection(
            relationships: [perspective],
            title: 'Relationships',
            emptyLabel: 'No relationships',
            editLabel: 'Edit relationship',
            deleteLabel: 'Delete relationship',
          ),
        ),
      ),
    ));
    expect(find.text('res_b'), findsOneWidget);
    expect(find.textContaining('trusted friend'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
