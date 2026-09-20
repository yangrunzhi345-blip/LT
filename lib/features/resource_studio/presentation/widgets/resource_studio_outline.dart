import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../domain/resources/resource_contracts.dart';

/// Compact Section/Part navigation for the Studio.
final class ResourceStudioOutline extends StatefulWidget {
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
  State<ResourceStudioOutline> createState() => _ResourceStudioOutlineState();
}

final class _ResourceStudioOutlineState extends State<ResourceStudioOutline> {
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _partKeys = <String, GlobalKey>{};
  PartId? _previousSelectedPartId;

  @override
  void didUpdateWidget(covariant ResourceStudioOutline oldWidget) {
    super.didUpdateWidget(oldWidget);
    final partIds = widget.parts.map((part) => part.id.value).toSet();
    _partKeys.removeWhere((partId, _) => !partIds.contains(partId));
    for (final partId in partIds) {
      _partKeys.putIfAbsent(partId, GlobalKey.new);
    }
    if (widget.selectedPartId != _previousSelectedPartId) {
      _previousSelectedPartId = widget.selectedPartId;
      WidgetsBinding.instance.addPostFrameCallback((_) => _followSelection());
    }
  }

  @override
  void initState() {
    super.initState();
    _previousSelectedPartId = widget.selectedPartId;
    for (final part in widget.parts) {
      _partKeys[part.id.value] = GlobalKey();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _followSelection());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _followSelection() {
    if (!mounted || !_scrollController.hasClients) return;
    final selectedPartId = widget.selectedPartId;
    final selectedContext = selectedPartId == null
        ? null
        : _partKeys[selectedPartId.value]?.currentContext;
    final itemBox = selectedContext?.findRenderObject() as RenderBox?;
    final viewportBox = _scrollController.position.context.storageContext
        .findRenderObject() as RenderBox?;
    if (itemBox == null || viewportBox == null || !itemBox.hasSize) return;

    const safetyInset = 32.0;
    final itemTop = itemBox.localToGlobal(Offset.zero).dy;
    final itemBottom = itemTop + itemBox.size.height;
    final viewportTop = viewportBox.localToGlobal(Offset.zero).dy;
    final viewportBottom = viewportTop + viewportBox.size.height;
    if (itemTop >= viewportTop + safetyInset &&
        itemBottom <= viewportBottom - safetyInset) {
      return;
    }
    unawaited(
      Scrollable.ensureVisible(
        selectedContext!,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        alignment: 0.5,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        for (final section in widget.sections)
          _SectionGroup(
            section: section,
            parts: widget.parts
                .where((part) => part.sectionId == section.id)
                .toList(growable: false),
            selectedPartId: widget.selectedPartId,
            onPartSelected: widget.onPartSelected,
            partKeys: _partKeys,
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
    required this.partKeys,
  });

  final ResourceSection section;
  final List<ResourcePart> parts;
  final PartId? selectedPartId;
  final ValueChanged<PartId> onPartSelected;
  final Map<String, GlobalKey> partKeys;

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
            key: partKeys[part.id.value],
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
