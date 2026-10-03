import 'package:flutter/material.dart';

import '../../../../domain/resources/character_relationship.dart';

/// Displays the selected character's resource relationships.
final class CharacterRelationshipsSection extends StatelessWidget {
  const CharacterRelationshipsSection({
    super.key,
    required this.relationships,
    required this.title,
    required this.emptyLabel,
    required this.editLabel,
    required this.deleteLabel,
    this.onEdit,
    this.onDelete,
  });

  final List<CharacterRelationshipPerspective> relationships;
  final String title;
  final String emptyLabel;
  final String editLabel;
  final String deleteLabel;
  final ValueChanged<CharacterRelationshipPerspective>? onEdit;
  final ValueChanged<CharacterRelationshipPerspective>? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (relationships.isEmpty)
          Text(emptyLabel, style: theme.textTheme.bodyMedium)
        else
          ...relationships.map(
            (relationship) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(relationship.counterpartResourceId.value),
              subtitle: Text(
                '${relationship.counterpartRole}\n${relationship.description}',
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Wrap(
                children: [
                  if (onEdit != null)
                    IconButton(
                      tooltip: editLabel,
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => onEdit!(relationship),
                    ),
                  if (onDelete != null)
                    IconButton(
                      tooltip: deleteLabel,
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => onDelete!(relationship),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
