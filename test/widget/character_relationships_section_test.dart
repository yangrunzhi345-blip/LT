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

  testWidgets('keeps actions reachable at narrow width and large text',
      (tester) async {
    final perspective = CharacterRelationshipPerspective(
      relationshipId: 'edge',
      counterpartResourceId: const ResourceId('res_b'),
      relationType: CharacterRelationshipType.mentorStudent,
      subjectRole: 'mentor',
      counterpartRole: 'student',
      description: 'Long description ' * 40,
    );
    var edited = false;
    var deleted = false;
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CharacterRelationshipsSection(
                relationships: [perspective],
                title: 'Relationships',
                emptyLabel: 'No relationships',
                editLabel: 'Edit relationship',
                deleteLabel: 'Delete relationship',
                onEdit: (_) => edited = true,
                onDelete: (_) => deleted = true,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Edit relationship'));
    await tester.tap(find.byTooltip('Delete relationship'));
    expect(edited, isTrue);
    expect(deleted, isTrue);
    expect(tester.takeException(), isNull);
  });
}
