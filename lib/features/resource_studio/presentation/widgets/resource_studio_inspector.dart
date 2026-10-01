import 'package:flutter/material.dart';

import '../../../../l10n/generated/app_localizations.dart';

enum StudioInspectorSection { generation, sections, capacity, revisions }

/// Contextual resource tools, separate from the continuous editor and outline.
class ResourceStudioInspector extends StatefulWidget {
  const ResourceStudioInspector(
      {super.key,
      required this.resourceName,
      required this.selectedPartTitle,
      required this.generation,
      required this.sections,
      required this.capacity,
      required this.revisions});

  final String resourceName;
  final String? selectedPartTitle;
  final Widget generation;
  final Widget sections;
  final Widget capacity;
  final Widget revisions;

  @override
  State<ResourceStudioInspector> createState() =>
      _ResourceStudioInspectorState();
}

class _ResourceStudioInspectorState extends State<ResourceStudioInspector> {
  StudioInspectorSection _selected = StudioInspectorSection.generation;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final labels = {
      StudioInspectorSection.generation: l10n.workbenchGeneration,
      StudioInspectorSection.sections: l10n.sectionControlsTitle,
      StudioInspectorSection.capacity: l10n.capacityPanelTitle,
      StudioInspectorSection.revisions: l10n.revisionHistoryTitle,
    };
    return Column(
        key: const Key('resource-studio-inspector'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.selectedPartTitle ?? widget.resourceName,
                        style: Theme.of(context).textTheme.titleSmall,
                        softWrap: true),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 4, children: [
                      for (final section in StudioInspectorSection.values)
                        ChoiceChip(
                          key: ValueKey('studio-inspector-${section.name}'),
                          label: Text(labels[section]!),
                          showCheckmark: false,
                          selected: _selected == section,
                          onSelected: (_) =>
                              setState(() => _selected = section),
                        ),
                    ]),
                  ])),
          const Divider(height: 1),
          Expanded(
              child: SingleChildScrollView(
            key: const Key('resource-studio-inspector-content'),
            padding: const EdgeInsets.all(12),
            child: switch (_selected) {
              StudioInspectorSection.generation => widget.generation,
              StudioInspectorSection.sections => widget.sections,
              StudioInspectorSection.capacity => widget.capacity,
              StudioInspectorSection.revisions => widget.revisions,
            },
          )),
        ]);
  }
}
