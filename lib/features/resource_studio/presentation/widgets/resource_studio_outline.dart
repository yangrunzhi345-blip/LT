import 'package:flutter/material.dart';

import '../../../../domain/resources/resource_contracts.dart';

/// Compact Section/Part navigation for the Studio.
final class ResourceStudioOutline extends StatelessWidget {
  const ResourceStudioOutline({
    required this.sections,
    required this.parts,
    required this.selectedPartId,
    required this.onPartSelected,
    super.key,
  });

  final List<ResourceSection> sections;
  final List<ResourcePart> parts;
  final PartId? selectedPartId;
  final ValueChanged<PartId> onPartSelected;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        for (final section in sections)
          _SectionGroup(
            section: section,
            parts: parts
                .where((part) => part.sectionId == section.id)
                .toList(growable: false),
            selectedPartId: selectedPartId,
            onPartSelected: onPartSelected,
          ),
      ],
    );
  }
}

final class _SectionGroup extends StatelessWidget {
  const _SectionGroup({
    required this.section,
    required this.parts,
    required this.selectedPartId,
    required this.onPartSelected,
  });

  final ResourceSection section;
  final List<ResourcePart> parts;
  final PartId? selectedPartId;
  final ValueChanged<PartId> onPartSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 6),
          child: Text(
            section.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        for (final part in parts)
          ListTile(
            dense: true,
            selected: part.id == selectedPartId,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            title: Text(
              part.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(part.content.isEmpty ? '待生成' : '已生成'),
            onTap: () => onPartSelected(part.id),
          ),
      ],
    );
  }
}
