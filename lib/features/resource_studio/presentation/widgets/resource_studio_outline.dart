import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/widgets/app_svg_icon.dart';
import '../../../../domain/resources/resource_contracts.dart';
import '../../../../domain/resources/resource_generation_protocol.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../l10n/generated/app_localizations_zh.dart';

AppLocalizations _l10n(BuildContext context) =>
    AppLocalizations.of(context) ?? AppLocalizationsZh();

/// Compact Section/Part navigation for the Studio.
final class ResourceStudioOutline extends StatefulWidget {
  const ResourceStudioOutline({
    required this.sections,
    required this.parts,
    required this.selectedPartId,
    required this.onPartSelected,
    this.partTaskStatuses = const <String, PartTaskStatus>{},
    this.retryingPartIds = const <String>{},
    this.onRetryPart,
    super.key,
  });

  final List<ResourceSection> sections;
  final List<ResourcePart> parts;
  final PartId? selectedPartId;
  final ValueChanged<PartId> onPartSelected;

  /// Persisted per-Part generation status; absent entries fall back to
  /// content-derived labels.
  final Map<String, PartTaskStatus> partTaskStatuses;

  /// Parts whose targeted regeneration is in flight.
  final Set<String> retryingPartIds;

  /// Retries exactly the Part whose id is passed. Only offered for failed
  /// Parts; null hides the action (e.g. read-only hosts).
  final ValueChanged<PartId>? onRetryPart;

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
            partTaskStatuses: widget.partTaskStatuses,
            retryingPartIds: widget.retryingPartIds,
            onRetryPart: widget.onRetryPart,
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
    required this.partTaskStatuses,
    required this.retryingPartIds,
    required this.onRetryPart,
  });

  final ResourceSection section;
  final List<ResourcePart> parts;
  final PartId? selectedPartId;
  final ValueChanged<PartId> onPartSelected;
  final Map<String, GlobalKey> partKeys;
  final Map<String, PartTaskStatus> partTaskStatuses;
  final Set<String> retryingPartIds;
  final ValueChanged<PartId>? onRetryPart;

  /// The label under a Part title.
  ///
  /// A known task status wins over content emptiness so a failed Part is never
  /// confused with a not-yet-generated one.
  String _statusLabel(BuildContext context, ResourcePart part) {
    final l10n = _l10n(context);
    if (retryingPartIds.contains(part.id.value)) {
      return l10n.retryingGeneration;
    }
    return switch (partTaskStatuses[part.id.value]) {
      PartTaskStatus.failed => l10n.generationFailed,
      PartTaskStatus.generating ||
      PartTaskStatus.validating =>
        l10n.resourceStatusGenerating,
      PartTaskStatus.completed => l10n.outlinePartGenerated,
      _ => part.content.isEmpty
          ? l10n.outlinePartPending
          : l10n.outlinePartGenerated,
    };
  }

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
            subtitle: Text(
              _statusLabel(context, part),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: partTaskStatuses[part.id.value] == PartTaskStatus.failed
                  ? TextStyle(color: theme.colorScheme.error)
                  : null,
            ),
            trailing: _trailing(context, part),
            onTap: () => onPartSelected(part.id),
          ),
      ],
    );
  }

  /// A failed Part offers "regenerate"; a retrying Part shows a spinner.
  /// Generated / pending Parts carry no action.
  Widget? _trailing(BuildContext context, ResourcePart part) {
    if (retryingPartIds.contains(part.id.value)) {
      return const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (partTaskStatuses[part.id.value] != PartTaskStatus.failed) return null;
    final retry = onRetryPart;
    if (retry == null) return null;
    return IconButton(
      key: ValueKey<String>('outline-retry-${part.id.value}'),
      tooltip: _l10n(context).retryGeneration,
      onPressed: () => retry(part.id),
      visualDensity: VisualDensity.compact,
      iconSize: 18,
      icon: const AppSvgIcon('refresh', size: 18),
    );
  }
}
