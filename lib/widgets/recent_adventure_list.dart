import 'package:flutter/material.dart';

import '../core/widgets/app_action_menu.dart';
import '../l10n/generated/app_localizations.dart';
import '../l10n/generated/app_localizations_zh.dart';

/// A presentation of the repository's activity-ordered adventures.
class RecentAdventureList extends StatefulWidget {
  const RecentAdventureList(
      {super.key,
      required this.adventures,
      required this.selectedId,
      required this.onOpen,
      required this.onRename,
      required this.onTrash,
      this.touchTargets = false});
  final List<Map<String, dynamic>> adventures;
  final int? selectedId;
  final ValueChanged<int> onOpen;
  final void Function(int, String) onRename;
  final void Function(int, String) onTrash;
  final bool touchTargets;

  @override
  State<RecentAdventureList> createState() => _RecentAdventureListState();
}

class _RecentAdventureListState extends State<RecentAdventureList> {
  final _scrollController = ScrollController();
  bool _hovered = false;
  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    String group(Map<String, dynamic> item) {
      final raw = item['recent_activity_at'] ??
          item['updated_at'] ??
          item['created_at'];
      final date = raw is num
          ? DateTime.fromMillisecondsSinceEpoch(raw.toInt()).toLocal()
          : DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
      if (date == null) return l10n.sidebarEarlier;
      if (!date.isBefore(today)) return l10n.sidebarToday;
      if (!date.isBefore(DateTime(now.year, now.month, now.day - 1))) {
        return l10n.sidebarYesterday;
      }
      if (!date.isBefore(DateTime(now.year, now.month, now.day - 7))) {
        return l10n.sidebarPastWeek;
      }
      return l10n.sidebarEarlier;
    }

    final entries = <Widget>[];
    String? previous;
    for (final item in widget.adventures) {
      if (item['id'] case final int id) {
        final heading = group(item);
        if (heading != previous) {
          entries.add(Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
              child: Text(heading,
                  style: Theme.of(context).textTheme.labelSmall)));
          previous = heading;
        }
        final title = item['title'] as String? ?? l10n.sidebarUnnamedScene;
        entries.add(_RecentAdventureRow(
            key: Key('recent-adventure-$id'),
            title: title,
            selected: id == widget.selectedId,
            touchTargets: widget.touchTargets,
            onOpen: () => widget.onOpen(id),
            onRename: () => widget.onRename(id, title),
            onTrash: () => widget.onTrash(id, title)));
      }
    }
    return MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Scrollbar(
            thumbVisibility: _hovered,
            controller: _scrollController,
            child: ListView(
                key: const Key('sidebar-recent-scroll'),
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                children: entries.isEmpty
                    ? [
                        Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(l10n.noRecentAdventures,
                                style: Theme.of(context).textTheme.bodySmall))
                      ]
                    : entries)));
  }
}

class _RecentAdventureRow extends StatefulWidget {
  const _RecentAdventureRow(
      {super.key,
      required this.title,
      required this.selected,
      required this.touchTargets,
      required this.onOpen,
      required this.onRename,
      required this.onTrash});
  final String title;
  final bool selected;
  final bool touchTargets;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onTrash;
  @override
  State<_RecentAdventureRow> createState() => _RecentAdventureRowState();
}

class _RecentAdventureRowState extends State<_RecentAdventureRow> {
  bool _hovered = false;
  bool _focused = false;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();
    final showActions = widget.touchTargets || _hovered || _focused;
    final height = (widget.touchTargets ? 48.0 : 34.0) *
        MediaQuery.textScalerOf(context).scale(1).clamp(1, 2);
    return Focus(
        onFocusChange: (value) => setState(() => _focused = value),
        child: MouseRegion(
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: Semantics(
                selected: widget.selected,
                button: true,
                child: Material(
                    color: widget.selected
                        ? scheme.primary.withValues(alpha: .10)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    child: Row(children: [
                      Expanded(
                          child: InkWell(
                              onTap: widget.onOpen,
                              borderRadius: BorderRadius.circular(6),
                              hoverColor:
                                  scheme.onSurface.withValues(alpha: .04),
                              child: ConstrainedBox(
                                  constraints:
                                      BoxConstraints(minHeight: height),
                                  child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 6),
                                      child: Row(children: [
                                        SizedBox(
                                            width: 2,
                                            height: 16,
                                            child: ColoredBox(
                                                color: widget.selected
                                                    ? scheme.primary
                                                    : Colors.transparent)),
                                        const SizedBox(width: 10),
                                        Expanded(
                                            child: Tooltip(
                                                message: widget.title,
                                                child: Text(widget.title,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: theme
                                                        .textTheme.labelMedium
                                                        ?.copyWith(
                                                            color: widget.selected
                                                                ? scheme
                                                                    .onSurface
                                                                : scheme
                                                                    .onSurfaceVariant)))),
                                        const SizedBox(width: 4),
                                      ]))))),
                      SizedBox(
                          width: widget.touchTargets ? 48 : 30,
                          height: height,
                          child: Visibility(
                              visible: showActions,
                              maintainSize: true,
                              maintainAnimation: true,
                              maintainState: true,
                              child: AppActionMenu<String>(
                                  tooltip: l10n.sidebarAdventureActions,
                                  iconSize: 16,
                                  onSelected: (action) => action == 'rename'
                                      ? widget.onRename()
                                      : widget.onTrash(),
                                  items: [
                                    AppActionMenuItem(
                                        value: 'rename',
                                        label: l10n.sidebarRenameAdventure),
                                    AppActionMenuItem(
                                        value: 'trash',
                                        label: l10n.moveToTrashAction,
                                        destructive: true),
                                  ]))),
                    ])))));
  }
}
