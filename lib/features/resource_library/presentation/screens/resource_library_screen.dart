import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/feedback/app_feedback.dart';
import '../../../../core/refresh/page_refresh_scope.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_borders.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_empty_state.dart';
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
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
    return Column(
      children: [
        NarrAItorLibraryHeader(
          eyebrow: 'LT',
          title: widget.mode.localizedTitle(l10n),
          onMenuPressed: widget.onMenuPressed,
          onSwitchMode: widget.onSwitchMode,
          actions: [
            IconButton(
              key: const Key('resource-trash-button'),
              tooltip: l10n.resourceTrashTooltip,
              onPressed: _showTrash,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
            FilledButton.icon(
              key: const Key('resource-create-button'),
              onPressed: _startCreation,
              icon: const Icon(Icons.add_rounded),
              label: Text(l10n.resourceCreateShort),
            ),
          ],
          search: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1120),
                child: TextField(
                  key: const Key('resource-search-field'),
                  onChanged: _controller.search,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search_rounded),
                    hintText: l10n.searchResources,
                    isDense: true,
                  ),
                ),
              ),
            ),
          ),
          secondary: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: SegmentedButton<ResourceLibraryFilter>(
                  key: const Key('resource-filter'),
                  segments: [
                    ButtonSegment(
                      value: ResourceLibraryFilter.all,
                      label: Text(l10n.allResources),
                    ),
                    ButtonSegment(
                      value: ResourceLibraryFilter.worldview,
                      label: Text(l10n.worldviewsTab),
                    ),
                    ButtonSegment(
                      value: ResourceLibraryFilter.character,
                      label: Text(l10n.charactersTab),
                    ),
                    ButtonSegment(
                      value: ResourceLibraryFilter.npc,
                      label: Text(l10n.resourceNpcTab),
                    ),
                  ],
                  selected: <ResourceLibraryFilter>{state.filter},
                  onSelectionChanged: (selection) =>
                      _controller.filter(selection.single),
                ),
              ),
              const SizedBox(height: 6),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildStatusFilter(context, state, l10n),
                    const SizedBox(width: 8),
                    _buildSortOption(context, state, l10n),
                  ],
                ),
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
        Expanded(child: _buildBody(context, state)),
      ],
    );
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
        avatar: const Icon(Icons.filter_list_rounded, size: 16),
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
        avatar: const Icon(Icons.sort_rounded, size: 16),
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
        icon: isFiltered ? Icons.search_off_rounded : Icons.folder_open_rounded,
        title: isFiltered ? l10n.resourceNoMatches : l10n.resourceEmptyTitle,
        actionLabel: isFiltered ? null : l10n.resourceCreateShort,
        onAction: isFiltered ? null : _startCreation,
      );
    }
    final l10n = _l10n(context);
    return AppRefreshIndicator(
      child: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final columns = switch (constraints.maxWidth) {
                  >= 900 => 3,
                  >= 600 => 2,
                  _ => 1,
                };
                final horizontalPadding =
                    constraints.maxWidth < 600 ? 12.0 : 20.0;
                return GridView.builder(
                  key: const Key('resource-grid'),
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    12,
                    horizontalPadding,
                    20,
                  ),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    mainAxisExtent:
                        (200.0 * MediaQuery.textScalerOf(context).scale(1.0))
                            .clamp(200.0, 420.0),
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, index) => _ResourceCard(
                    item: items[index],
                    onOpen: () => _openDetails(items[index]),
                  ),
                );
              },
            ),
          ),
          if (state.totalPages > 1) _buildPaginationBar(context, state, l10n),
        ],
      ),
    );
  }

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
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: state.currentPage > 1 ? _controller.previousPage : null,
          ),
          Padding(
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
          ),
          IconButton(
            key: const Key('resource-page-next'),
            tooltip: l10n.resourcePaginationNext,
            icon: const Icon(Icons.chevron_right_rounded),
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
    final l10n = _l10n(context);
    final message = await AppRouter.push<String>(
      context,
      pageBuilder: (_) => ResourceLibraryDetailPage(
        item: item,
        onMoveToTrash: () async {
          final result = await _controller.moveToTrash(item);
          if (!result.success) return null;
          return result.message ?? l10n.resourceMovedToTrash;
        },
      ),
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

final class _ResourceCard extends StatelessWidget {
  const _ResourceCard({required this.item, required this.onOpen});

  final ResourceLibraryItem item;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final lifecycle = ResourcePresentationResolver.resolveLifecycle(
      lifecycleState: item.lifecycleState,
      displayStatus: item.status,
      isConsumable: item.isConsumable,
    );
    final safeName = ResourcePresentationResolver.safeName(item.name, l10n);
    final safeSummary =
        ResourcePresentationResolver.safeSummary(item.summary, l10n);
    final safeUpdated =
        ResourcePresentationResolver.safeUpdatedTime(item.updatedAt, l10n);
    final inFlightText =
        ResourcePresentationResolver.inFlightStatusLabel(lifecycle, l10n);

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: BorderSide(color: AppBorders.defaultColor(context)),
      ),
      color: isDark ? AppColors.darkSurface : AppColors.surfaceElevated,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey<String>('resource-card-${item.id}'),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      item.localizedTypeLabel(l10n),
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: item.isConsumable
                          ? colorScheme.primaryContainer.withValues(alpha: 0.5)
                          : colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      item.lifecycleState != null
                          ? ResourcePresentationResolver
                              .localizedLifecycleLabel(
                              lifecycle,
                              l10n,
                            )
                          : item.status.localizedLabel(l10n),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: item.isConsumable
                            ? colorScheme.primary
                            : colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (item.isConsumable)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        l10n.resourceConsumableBadge,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  if (inFlightText != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.tertiaryContainer
                            .withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        inFlightText,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onTertiaryContainer,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                safeName,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Expanded(
                child: Text(
                  safeSummary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  if (safeUpdated.isNotEmpty)
                    Expanded(
                      child: Text(
                        safeUpdated,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.outline,
                        ),
                      ),
                    ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
