import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/feedback/app_feedback.dart';
import '../../../../core/refresh/page_refresh_scope.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_borders.dart';
import '../../../../core/widgets/app_empty_state.dart';
import '../../../../core/widgets/app_svg_icon.dart';
import '../../../../core/widgets/app_error_view.dart';
import '../../../../core/widgets/app_loading_view.dart';
import '../../../../core/widgets/narr_aitor_library_header.dart';
import '../../../../models/resource_library_mode.dart';
import '../../../../providers/riverpod_providers.dart';
import '../../../resource_studio/presentation/pages/resource_studio_page.dart';
import '../../domain/models/resource_library_view_state.dart';
import '../controllers/resource_library_controller.dart';
import '../resolvers/resource_presentation_resolver.dart';
import '../widgets/resource_creation_flow.dart';
import '../widgets/resource_trash_sheet.dart';
import 'resource_create_page.dart';
import 'resource_library_detail_page.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../l10n/generated/app_localizations_zh.dart';

AppLocalizations _l10n(BuildContext context) =>
    AppLocalizations.of(context) ?? AppLocalizationsZh();

/// Unified library surface for finding, viewing, creating, and lifecycle
/// actions.
final class ResourceLibraryScreen extends ConsumerStatefulWidget {
  const ResourceLibraryScreen({
    super.key,
    this.initialTab = 0,
    this.onMenuPressed,
    this.onSwitchMode,
    this.mode = ResourceLibraryMode.adventure,
    this.initialResourceId,
  });

  /// Compatibility input for old callers. Values map to the unified filter.
  final int initialTab;
  final VoidCallback? onMenuPressed;
  final VoidCallback? onSwitchMode;
  final ResourceLibraryMode mode;
  final String? initialResourceId;

  @override
  ConsumerState<ResourceLibraryScreen> createState() =>
      _ResourceLibraryScreenState();
}

final class _ResourceLibraryScreenState
    extends ConsumerState<ResourceLibraryScreen> {
  late final ResourceLibraryController _controller;
  String? _selectedResourceId;
  String? _studioResourceId;
  ResourceStudioCreationDraft? _studioCreationDraft;
  final _searchController = TextEditingController();
  bool _usesInlineDetail = false;

  @override
  void initState() {
    super.initState();
    _controller = ResourceLibraryController(
      runtime: ref.read(resourceLibraryRuntimeProvider),
      mode: widget.mode,
    );
    final initialFilter = switch (widget.initialTab) {
      1 => ResourceLibraryFilter.character,
      2 => ResourceLibraryFilter.npc,
      _ => ResourceLibraryFilter.all,
    };
    _controller.filter(initialFilter);
    unawaited(_controller.load().then((_) => _openInitialResource()));
  }

  @override
  void dispose() {
    _searchController.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_studioResourceId != null || _studioCreationDraft != null) {
      return Scaffold(
          body: ResourceStudioPage(
              key: ValueKey(
                  'library-studio-${_studioResourceId ?? _studioCreationDraft?.idempotencyKey}'),
              resourceId: _studioResourceId,
              creationDraft: _studioCreationDraft,
              embedded: true,
              onClose: () {
                setState(() {
                  _studioResourceId = null;
                  _studioCreationDraft = null;
                });
                unawaited(_controller.load());
              }));
    }
    return PageRefreshScope(
      onRefresh: () async {
        await _controller.load();
        return const PageRefreshResult.success();
      },
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: ListenableBuilder(
            listenable: _controller,
            builder: (context, _) => _buildContent(context, _controller.state),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    ResourceLibraryViewState state,
  ) {
    final l10n = _l10n(context);
    return LayoutBuilder(builder: (context, constraints) {
      // 180 px filters + 280 px list + flexible detail need a wide workspace.
      final wide = constraints.maxWidth >= 1000;
      _usesInlineDetail = wide;
      final filters = _buildFilters(context, state, l10n, vertical: wide);
      final header = NarrAItorLibraryHeader(
        title: widget.mode.localizedTitle(l10n),
        onMenuPressed: widget.onMenuPressed,
        onSwitchMode: widget.onSwitchMode,
        actions: [
          IconButton(
            key: const Key('resource-trash-button'),
            tooltip: l10n.resourceTrashTooltip,
            onPressed: _showTrash,
            icon: const AppSvgIcon('delete'),
          ),
          FilledButton(
            key: const Key('resource-create-button'),
            onPressed: _startCreation,
            child: Text(l10n.resourceCreateShort),
          ),
        ],
        search: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            key: const Key('resource-search-field'),
            controller: _searchController,
            onChanged: _controller.search,
            decoration: InputDecoration(
              prefixIcon: const Padding(
                  padding: EdgeInsets.all(12), child: AppSvgIcon('search')),
              hintText: l10n.searchResources,
              isDense: true,
            ),
          ),
        ),
        secondary: wide
            ? null
            : Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: filters),
      );
      if (!wide) {
        return NestedScrollView(
          key: const Key('resource-workspace'),
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            SliverToBoxAdapter(child: header),
          ],
          body: _buildBody(context, state),
        );
      }
      return Column(children: [
        header,
        Expanded(
            child: Row(children: [
          SizedBox(
              width: 180,
              child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12), child: filters)),
          const VerticalDivider(width: 1),
          Expanded(child: _buildBody(context, state)),
        ]))
      ]);
    });
  }

  Widget _buildFilters(BuildContext context, ResourceLibraryViewState state,
      AppLocalizations l10n,
      {required bool vertical}) {
    final labels = <ResourceLibraryFilter, String>{
      ResourceLibraryFilter.all: l10n.allResources,
      ResourceLibraryFilter.worldview: l10n.worldviewsTab,
      ResourceLibraryFilter.character: l10n.charactersTab,
      ResourceLibraryFilter.npc: l10n.resourceNpcTab,
    };
    final types = [
      for (final entry in labels.entries)
        vertical
            ? ListTile(
                key: ValueKey('resource-filter-${entry.key.name}'),
                selected: state.filter == entry.key,
                title: Text(entry.value),
                onTap: () => _controller.filter(entry.key),
              )
            : ChoiceChip(
                key: ValueKey('resource-filter-${entry.key.name}'),
                showCheckmark: false,
                label: Text(entry.value),
                selected: state.filter == entry.key,
                onSelected: (_) => _controller.filter(entry.key),
              )
    ];
    return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          vertical
              ? Column(key: const Key('resource-filter'), children: types)
              : Wrap(
                  key: const Key('resource-filter'),
                  spacing: 8,
                  runSpacing: 4,
                  children: types),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 4, children: [
            _buildStatusFilter(context, state, l10n),
            _buildSortOption(context, state, l10n),
          ]),
        ]);
  }

  Widget _buildStatusFilter(
    BuildContext context,
    ResourceLibraryViewState state,
    AppLocalizations l10n,
  ) {
    return PopupMenuButton<ResourceStatusFilter>(
      key: const Key('resource-status-filter'),
      tooltip: l10n.resourceStatusFilterLabel,
      initialValue: state.statusFilter,
      onSelected: _controller.filterStatus,
      itemBuilder: (context) => [
        for (final filter in ResourceStatusFilter.values)
          PopupMenuItem(
            value: filter,
            child: Text(
              ResourcePresentationResolver.localizedStatusFilterLabel(
                filter,
                l10n,
              ),
            ),
          ),
      ],
      child: Chip(
        label: Text(
          ResourcePresentationResolver.localizedStatusFilterLabel(
            state.statusFilter,
            l10n,
          ),
        ),
      ),
    );
  }

  Widget _buildSortOption(
    BuildContext context,
    ResourceLibraryViewState state,
    AppLocalizations l10n,
  ) {
    return PopupMenuButton<ResourceSortOption>(
      key: const Key('resource-sort-select'),
      tooltip: l10n.resourceSortLabel,
      initialValue: state.sortOption,
      onSelected: _controller.changeSort,
      itemBuilder: (context) => [
        for (final sort in ResourceSortOption.values)
          PopupMenuItem(
            value: sort,
            child: Text(
              ResourcePresentationResolver.localizedSortLabel(
                sort,
                l10n,
              ),
            ),
          ),
      ],
      child: Chip(
        label: Text(
          ResourcePresentationResolver.localizedSortLabel(
            state.sortOption,
            l10n,
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, ResourceLibraryViewState state) {
    if (state.status == ResourceLibraryStatus.loading) {
      return const AppLoadingView();
    }
    if (state.status == ResourceLibraryStatus.error) {
      final l10n = _l10n(context);
      final message = switch (state.error) {
        ResourceLibraryError.createFailed => l10n.resourceCreationFailedRetry,
        ResourceLibraryError.loadFailed || null => l10n.resourceLoadFailedRetry,
      };
      return AppErrorView(
        title: message,
        retryLabel: l10n.resourceRetryLoad,
        onRetry: _controller.load,
      );
    }
    final items = state.pagedItems;
    if (items.isEmpty) {
      final l10n = _l10n(context);
      final isFiltered = state.query.trim().isNotEmpty ||
          state.filter != ResourceLibraryFilter.all ||
          state.statusFilter != ResourceStatusFilter.all;
      return AppEmptyState(
        title: isFiltered ? l10n.resourceNoMatches : l10n.resourceEmptyTitle,
        actionLabel: isFiltered ? null : l10n.resourceCreateShort,
        onAction: isFiltered ? null : _startCreation,
      );
    }
    final l10n = _l10n(context);
    final selected =
        items.where((item) => item.id == _selectedResourceId).firstOrNull ??
            (_usesInlineDetail ? items.first : null);
    final list = AppRefreshIndicator(
        child: Column(children: [
      Expanded(
          child: ListView.builder(
        key: const Key('resource-list'),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: items.length,
        itemBuilder: (context, index) => _ResourceRow(
          item: items[index],
          selected: _usesInlineDetail && selected?.id == items[index].id,
          onOpen: () => _openDetails(items[index]),
        ),
      )),
      if (state.totalPages > 1) _buildPaginationBar(context, state, l10n),
    ]));
    if (!_usesInlineDetail || selected == null) return list;
    return Row(children: [
      SizedBox(width: 280, child: list),
      const VerticalDivider(width: 1),
      Expanded(child: _detailFor(selected, embedded: true)),
    ]);
  }

  ResourceLibraryDetailPage _detailFor(ResourceLibraryItem item,
          {bool embedded = false}) =>
      ResourceLibraryDetailPage(
        key: ValueKey('resource-detail-${item.id}'),
        item: item,
        embedded: embedded,
        onOpenStudio: embedded
            ? () async {
                setState(() => _studioResourceId = item.id);
              }
            : null,
        onDeleted: embedded
            ? (message) async {
                setState(() => _selectedResourceId = null);
                await _controller.load();
                if (mounted) AppFeedback.success(context, message);
              }
            : null,
        onMoveToTrash: () async {
          final result = await _controller.moveToTrash(item);
          if (!result.success || !mounted) return null;
          return result.message ?? _l10n(context).resourceMovedToTrash;
        },
      );

  Widget _buildPaginationBar(
    BuildContext context,
    ResourceLibraryViewState state,
    AppLocalizations l10n,
  ) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: theme.dividerColor.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            key: const Key('resource-page-prev'),
            tooltip: l10n.resourcePaginationPrev,
            icon: const AppSvgIcon('back'),
            onPressed: state.currentPage > 1 ? _controller.previousPage : null,
          ),
          Flexible(
              child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              l10n.resourcePaginationPageInfo(
                state.currentPage,
                state.totalPages,
                state.totalCount,
              ),
              key: const Key('resource-page-info'),
              style: theme.textTheme.bodySmall,
            ),
          )),
          IconButton(
            key: const Key('resource-page-next'),
            tooltip: l10n.resourcePaginationNext,
            icon: const AppSvgIcon('forward'),
            onPressed: state.currentPage < state.totalPages
                ? _controller.nextPage
                : null,
          ),
        ],
      ),
    );
  }

  Future<void> _startCreation() async {
    final availableResources = _controller.state.items
        .where((item) => item.isStudioAvailable)
        .toList(growable: false);

    final draft = await AppRouter.push<Object?>(
      context,
      pageBuilder: (_) => ResourceCreatePage(resources: availableResources),
    );
    if (!mounted || draft == null) return;

    if (draft is ResourceStudioCreationDraft) {
      if (_usesInlineDetail) {
        setState(() => _studioCreationDraft = draft);
        return;
      }
      await AppRouter.push<void>(
        context,
        pageBuilder: (_) => ResourceStudioPage(creationDraft: draft),
      );
      if (mounted) await _controller.load();
    } else if (draft is ManualResourceDraft) {
      final id = await _controller.createManual(
        type: draft.type,
        name: draft.name,
        summary: draft.summary,
      );
      if (!mounted || id == null) return;
      final item = _controller.state.items
          .where((candidate) => candidate.id == id)
          .firstOrNull;
      if (item != null) await _openDetails(item);
    }
  }

  Future<void> _showTrash() async {
    await ResourceTrashPage.show(
      context,
      ref.read(resourceTrashRuntimeProvider),
    );
    if (mounted) await _controller.load();
  }

  Future<void> _openDetails(ResourceLibraryItem item) async {
    if (_usesInlineDetail) {
      setState(() => _selectedResourceId = item.id);
      return;
    }
    final message = await AppRouter.push<String>(
      context,
      pageBuilder: (_) => _detailFor(item),
    );
    if (!mounted) return;
    await _controller.load();
    if (mounted && message != null) AppFeedback.success(context, message);
  }

  Future<void> _openInitialResource() async {
    if (!mounted) return;
    final initialId = widget.initialResourceId;
    if (initialId == null || initialId.isEmpty) return;
    final item = _controller.state.items
        .where((candidate) => candidate.id == initialId)
        .firstOrNull;
    if (item != null) await _openDetails(item);
  }
}

final class _ResourceRow extends StatelessWidget {
  const _ResourceRow(
      {required this.item, required this.onOpen, required this.selected});
  final ResourceLibraryItem item;
  final VoidCallback onOpen;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n(context);
    final theme = Theme.of(context);
    final lifecycle = ResourcePresentationResolver.resolveLifecycle(
        lifecycleState: item.lifecycleState,
        displayStatus: item.status,
        isConsumable: item.isConsumable);
    return Semantics(
        selected: selected,
        child: Material(
          color: selected
              ? theme.colorScheme.surfaceContainerHighest
              : theme.colorScheme.surface,
          child: InkWell(
            key: ValueKey<String>('resource-card-${item.id}'),
            onTap: onOpen,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              decoration: BoxDecoration(
                  border: Border(
                      bottom:
                          BorderSide(color: AppBorders.defaultColor(context)))),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(ResourcePresentationResolver.safeName(item.name, l10n),
                        style: theme.textTheme.titleSmall, softWrap: true),
                    const SizedBox(height: 4),
                    Wrap(spacing: 8, runSpacing: 4, children: [
                      Text(item.localizedTypeLabel(l10n),
                          style: theme.textTheme.labelSmall),
                      Text(
                          item.lifecycleState != null
                              ? ResourcePresentationResolver
                                  .localizedLifecycleLabel(lifecycle, l10n)
                              : item.status.localizedLabel(l10n),
                          style: theme.textTheme.labelSmall),
                      if (item.isConsumable)
                        Text(l10n.resourceConsumableBadge,
                            style: theme.textTheme.labelSmall),
                      if (ResourcePresentationResolver.inFlightStatusLabel(
                              lifecycle, l10n)
                          case final status?)
                        Text(status, style: theme.textTheme.labelSmall),
                    ]),
                    const SizedBox(height: 4),
                    Text(
                        ResourcePresentationResolver.safeSummary(
                            item.summary, l10n),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall),
                    Text(
                        ResourcePresentationResolver.safeUpdatedTime(
                            item.updatedAt, l10n),
                        style: theme.textTheme.labelSmall),
                  ]),
            ),
          ),
        ));
  }
}
