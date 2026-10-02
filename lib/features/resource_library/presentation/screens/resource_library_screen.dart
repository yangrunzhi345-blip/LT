import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/feedback/app_feedback.dart';
import '../../../../core/localization/app_date_formats.dart';
import '../../../../core/refresh/page_refresh_scope.dart';
import '../../../../core/responsive/app_breakpoints.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_borders.dart';
import '../../../../core/widgets/app_empty_state.dart';
import '../../../../core/widgets/app_select.dart';
import '../../../../core/widgets/app_svg_icon.dart';
import '../../../../core/widgets/app_error_view.dart';
import '../../../../core/widgets/app_loading_view.dart';
import '../../../../core/widgets/workbench_chrome.dart';
import '../../../../models/resource_library_mode.dart';
import '../../../../providers/riverpod_providers.dart';
import '../../../resource_studio/presentation/pages/resource_studio_page.dart';
import '../../../../domain/resources/resource_contracts.dart';
import '../../../../widgets/app_dialogs.dart';
import '../../domain/models/character_status_library_view_state.dart';
import '../../domain/models/resource_library_view_state.dart';
import '../controllers/character_status_library_controller.dart';
import '../controllers/resource_library_controller.dart';
import '../widgets/character_status_library_surface.dart';
import '../resolvers/resource_presentation_resolver.dart';
import '../widgets/resource_creation_flow.dart';
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
    this.onReturnHome,
    this.onSwitchMode,
    this.mode = ResourceLibraryMode.adventure,
    this.initialResourceId,
    this.initialFilter,
  });

  /// Compatibility input for old callers. Values map to the unified filter.
  final int initialTab;

  /// Preferred initial view. Takes precedence over [initialTab]; used to open
  /// the derived「角色状态」surface directly.
  final ResourceLibraryFilter? initialFilter;

  /// Sidebar / drawer control. Never an exit action.
  final VoidCallback? onMenuPressed;

  /// Explicit exit action injected by the hosting workbench. When present it
  /// takes precedence over route popping so the AppSection navigation authority
  /// (ChatProvider) owns the transition back to the lobby.
  final VoidCallback? onReturnHome;
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
  late final CharacterStatusLibraryController _statusController;
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
    _statusController = CharacterStatusLibraryController(
      runtime: ref.read(characterStatusLibraryRuntimeProvider),
      mode: widget.mode,
    );
    final initialFilter = widget.initialFilter ??
        switch (widget.initialTab) {
          1 => ResourceLibraryFilter.character,
          2 => ResourceLibraryFilter.npc,
          _ => ResourceLibraryFilter.all,
        };
    _controller.filter(initialFilter);
    unawaited(_controller.load().then((_) => _openInitialResource()));
    if (initialFilter == ResourceLibraryFilter.characterStatus) {
      unawaited(_statusController.load());
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _statusController.dispose();
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
        if (_controller.state.filter == ResourceLibraryFilter.characterStatus) {
          await _statusController.load();
        }
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
      _usesInlineDetail =
          constraints.maxWidth >= AppBreakpoints.libraryTriPaneMin;
      final header = WorkbenchPageHeader(
        title: widget.mode.localizedTitle(l10n),
        leading: _buildHeaderLeading(l10n, constraints.maxWidth),
        actions: [
          if (widget.onSwitchMode != null)
            TextButton.icon(
              onPressed: widget.onSwitchMode,
              icon: const AppSvgIcon('resources', size: 16),
              label: Text(l10n.switchLibrary),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: const Size(0, 32),
              ),
            ),
          FilledButton(
            key: const Key('resource-create-button'),
            onPressed: _startCreation,
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AppSvgIcon('add', size: 15),
                const SizedBox(width: 6),
                Text(l10n.resourceCreateShort),
              ],
            ),
          ),
        ],
        bottom: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            WorkbenchToolbar(child: _buildFilters(context, state, l10n)),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
              child: _buildSearch(l10n, state),
            ),
          ],
        ),
      );
      // On narrow/short viewports (and with the soft keyboard open) the header
      // must scroll away with the content, otherwise a wrapped toolbar can
      // exceed the remaining height. The wide master/detail layout keeps the
      // header pinned because it always has room.
      if (!_usesInlineDetail) {
        return NestedScrollView(
          key: const Key('resource-workspace'),
          headerSliverBuilder: (context, _) => [
            SliverToBoxAdapter(child: header),
          ],
          body: _buildBody(context, state),
        );
      }
      return Column(
        key: const Key('resource-workspace'),
        children: [
          header,
          Expanded(child: _buildBody(context, state)),
        ],
      );
    });
  }

  /// Header leading: the sidebar/drawer control plus an explicit return-to-
  /// lobby control. Both are always offered — on a compact workspace the label
  /// collapses to an icon so the header never overflows.
  Widget _buildHeaderLeading(
    AppLocalizations l10n,
    double width,
  ) {
    final compact = width < AppBreakpoints.mediumMin;
    final menuControl = widget.onMenuPressed == null
        ? null
        : IconButton(
            key: const Key('resource-library-menu'),
            onPressed: widget.onMenuPressed,
            tooltip: l10n.menuTooltip,
            visualDensity: VisualDensity.compact,
            iconSize: 20,
            icon: const AppSvgIcon('panel', size: 20),
          );
    final returnControl = WorkbenchBackAction(
      key: const Key('resource-library-return-home'),
      onPressed: _handleReturn,
      label: l10n.returnToDashboard,
      compact: compact,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (menuControl != null) menuControl,
        returnControl,
      ],
    );
  }

  /// Single exit contract with a clear precedence:
  /// 1. host-injected callback (workbench section authority)
  /// 2. a pushed route that can pop
  /// 3. lobby fallback so no entry path is ever a dead end.
  void _handleReturn() {
    final callback = widget.onReturnHome;
    if (callback != null) {
      callback();
      return;
    }
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }
    ref.read(chatProvider).navigateToAdventureHome();
  }

  Widget _buildSearch(
    AppLocalizations l10n,
    ResourceLibraryViewState state,
  ) {
    final statusView = state.filter == ResourceLibraryFilter.characterStatus;
    return WorkbenchSearchField(
      fieldKey: const Key('resource-search-field'),
      hintText: statusView
          ? l10n.resourceCharacterStatusSearchHint
          : l10n.searchResources,
      controller: _searchController,
      onChanged: statusView ? _statusController.search : _controller.search,
    );
  }

  /// Selecting a top-level library view.
  ///
  /// Query and sort are shared between the ordinary resource list and the
  /// derived「角色状态」surface; entering the derived view (re)loads it so an
  /// edit made in an owner editor is visible immediately.
  void _onFilterSelected(ResourceLibraryFilter filter) {
    _controller.filter(filter);
    final query = _searchController.text;
    _controller.search(query);
    _statusController.search(query);
    if (filter == ResourceLibraryFilter.characterStatus) {
      unawaited(_statusController.load());
    }
  }

  Widget _buildFilters(BuildContext context, ResourceLibraryViewState state,
      AppLocalizations l10n) {
    final labels = <ResourceLibraryFilter, String>{
      ResourceLibraryFilter.all: l10n.allResources,
      ResourceLibraryFilter.worldview: l10n.worldviewsTab,
      ResourceLibraryFilter.character: l10n.charactersTab,
      ResourceLibraryFilter.npc: l10n.resourceNpcTab,
      ResourceLibraryFilter.characterStatus: l10n.resourceCharacterStatusTab,
    };
    final statusView = state.filter == ResourceLibraryFilter.characterStatus;
    return Wrap(
      key: const Key('resource-filter'),
      spacing: 2,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final entry in labels.entries)
          WorkbenchTabButton(
            key: ValueKey('resource-filter-${entry.key.name}'),
            label: entry.value,
            selected: state.filter == entry.key,
            onTap: () => _onFilterSelected(entry.key),
          ),
        const SizedBox(width: 10),
        // The derived surface has no resource lifecycle of its own, so the
        // status filter is replaced by an owner-type filter and the status
        // filter is hidden to avoid implying a per-status lifecycle.
        if (statusView)
          _buildOwnerFilter(l10n)
        else
          _buildStatusFilter(context, state, l10n),
        _buildSortOption(context, state, l10n),
      ],
    );
  }

  /// Owner-type filter for the「角色状态」surface: All / Characters / NPCs.
  Widget _buildOwnerFilter(AppLocalizations l10n) {
    final state = _statusController.state;
    final labelFor = <CharacterStatusOwnerFilter, String>{
      CharacterStatusOwnerFilter.all: l10n.trackedStateFilterAll,
      CharacterStatusOwnerFilter.character:
          l10n.trackedStateEntityTypeCharacter,
      CharacterStatusOwnerFilter.npc: l10n.trackedStateEntityTypeNpc,
    };
    return AppSelect<CharacterStatusOwnerFilter>.toolbar(
      key: const Key('character-status-owner-filter'),
      value: state.ownerFilter,
      label: l10n.resourceCharacterStatusTab,
      tooltip: l10n.resourceCharacterStatusTab,
      semanticLabel:
          '${l10n.resourceCharacterStatusTab}: ${labelFor[state.ownerFilter]}',
      items: [
        for (final filter in CharacterStatusOwnerFilter.values)
          AppSelectItem(value: filter, label: labelFor[filter]!),
      ],
      onChanged: (filter) {
        if (filter != null) _statusController.filterOwner(filter);
      },
    );
  }

  /// Toolbar select: `Status: All ˅` rendered by the shared menu kernel.
  Widget _buildStatusFilter(
    BuildContext context,
    ResourceLibraryViewState state,
    AppLocalizations l10n,
  ) {
    return AppSelect<ResourceStatusFilter>.toolbar(
      key: const Key('resource-status-filter'),
      value: state.statusFilter,
      label: l10n.resourceStatusFilterLabel,
      tooltip: l10n.resourceStatusFilterLabel,
      semanticLabel: '${l10n.resourceStatusFilterLabel}: '
          '${ResourcePresentationResolver.localizedStatusFilterLabel(state.statusFilter, l10n)}',
      items: [
        for (final filter in ResourceStatusFilter.values)
          AppSelectItem(
            value: filter,
            label: ResourcePresentationResolver.localizedStatusFilterLabel(
              filter,
              l10n,
            ),
          ),
      ],
      onChanged: (filter) {
        if (filter != null) _controller.filterStatus(filter);
      },
    );
  }

  Widget _buildSortOption(
    BuildContext context,
    ResourceLibraryViewState state,
    AppLocalizations l10n,
  ) {
    final statusView = state.filter == ResourceLibraryFilter.characterStatus;
    final activeSort =
        statusView ? _statusController.state.sortOption : state.sortOption;
    return AppSelect<ResourceSortOption>.toolbar(
      key: const Key('resource-sort-select'),
      value: activeSort,
      label: l10n.resourceSortLabel,
      tooltip: l10n.resourceSortLabel,
      semanticLabel: '${l10n.resourceSortLabel}: '
          '${ResourcePresentationResolver.localizedSortLabel(activeSort, l10n)}',
      items: [
        for (final sort in ResourceSortOption.values)
          AppSelectItem(
            value: sort,
            label: ResourcePresentationResolver.localizedSortLabel(sort, l10n),
          ),
      ],
      onChanged: (sort) {
        if (sort == null) return;
        _controller.changeSort(sort);
        _statusController.changeSort(sort);
      },
    );
  }

  Widget _buildBody(BuildContext context, ResourceLibraryViewState state) {
    if (state.filter == ResourceLibraryFilter.characterStatus) {
      return ListenableBuilder(
        listenable: _statusController,
        builder: (context, _) => CharacterStatusLibrarySurface(
          state: _statusController.state,
          onOpenOwner: _openOwnerResource,
          onEditOwner: _editOwnerResource,
          onAddStatus: _addCharacterStatus,
          onRetry: _statusController.load,
          onPreviousPage: _statusController.previousPage,
          onNextPage: _statusController.nextPage,
        ),
      );
    }
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
        icon: 'resources',
        title: isFiltered ? l10n.resourceNoMatches : l10n.resourceEmptyTitle,
        description: isFiltered ? null : l10n.resourceEmptyDescription,
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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
      SizedBox(width: 240, child: list),
      VerticalDivider(
          width: 1, color: Theme.of(context).colorScheme.outlineVariant),
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

  /// Opens the owner resource's detail page (read-only; shows 检测项目).
  Future<void> _openOwnerResource(CharacterStatusLibraryEntry entry) async {
    final item = _controller.state.items
        .where((candidate) => candidate.id == entry.resourceId)
        .firstOrNull;
    if (item != null) await _openDetails(item);
  }

  /// Opens the owner resource editor.
  ///
  /// Characters have a card editor that owns the tracked-state section. NPCs
  /// have no dedicated editor in this codebase, so they fall back to the
  /// read-only detail page rather than inventing a second authoring surface.
  Future<void> _editOwnerResource(CharacterStatusLibraryEntry entry) async {
    if (entry.ownerType != ResourceType.character) {
      await _openOwnerResource(entry);
      return;
    }
    final row = await _readOwnerRow(entry);
    if (!mounted) return;
    await showCreateCharacterCardDialog(
      context,
      existingCard: row,
      existingId: entry.resourceId,
      mode: widget.mode,
    );
    if (mounted) await _statusController.load();
  }

  Future<Map<String, dynamic>?> _readOwnerRow(
    CharacterStatusLibraryEntry entry,
  ) async {
    try {
      final read =
          await ref.read(libraryRepoProvider).readResourcePreferringTree(
                type: entry.ownerType,
                legacyId: entry.resourceId,
              );
      final row = read.legacyRow;
      return row == null ? null : Map<String, dynamic>.from(row);
    } catch (_) {
      return null;
    }
  }

  /// 「添加角色状态」: a monitoring definition must belong to an owner, so pick
  /// one first and open its editor. Never creates an owner-less status.
  Future<void> _addCharacterStatus() async {
    final owners = _controller.state.items
        .where((candidate) =>
            candidate.type == ResourceType.character ||
            candidate.type == ResourceType.npc)
        .toList(growable: false);
    if (owners.isEmpty) {
      await _startCreation();
      return;
    }
    final l10n = _l10n(context);
    final picked = await showModalBottomSheet<ResourceLibraryItem>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(
                l10n.resourceCharacterStatusSelectOwner,
                style: Theme.of(sheetContext).textTheme.titleSmall,
              ),
            ),
            for (final owner in owners)
              ListTile(
                key: ValueKey('character-status-pick-${owner.id}'),
                title: Text(owner.localizedName(l10n)),
                subtitle: Text(owner.localizedTypeLabel(l10n)),
                onTap: () => Navigator.of(sheetContext).pop(owner),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    await _editOwnerResource(CharacterStatusLibraryEntry(
      resourceId: picked.id,
      ownerType: picked.type,
      ownerName: picked.name,
      updatedAt: picked.updatedAt,
      definitions: const [],
    ));
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
    final scheme = theme.colorScheme;
    final lifecycle = ResourcePresentationResolver.resolveLifecycle(
        lifecycleState: item.lifecycleState,
        displayStatus: item.status,
        isConsumable: item.isConsumable);

    final statusLabel = item.lifecycleState != null
        ? ResourcePresentationResolver.localizedLifecycleLabel(lifecycle, l10n)
        : item.status.localizedLabel(l10n);
    final inFlight =
        ResourcePresentationResolver.inFlightStatusLabel(lifecycle, l10n);
    final meta = <String>[
      item.localizedTypeLabel(l10n),
      statusLabel,
      if (item.isConsumable) l10n.resourceConsumableBadge,
      if (inFlight != null) inFlight,
    ];
    final timestamp =
        AppDateFormats.formatPersisted(item.updatedAt, l10n.localeName);
    final mutedStyle =
        theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant);

    return Semantics(
        selected: selected,
        child: Material(
          color: selected
              ? scheme.primary.withValues(alpha: 0.07)
              : Colors.transparent,
          child: InkWell(
            key: ValueKey<String>('resource-card-${item.id}'),
            onTap: onOpen,
            hoverColor: scheme.onSurface.withValues(alpha: 0.04),
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
              decoration: BoxDecoration(
                  border: Border(
                      bottom:
                          BorderSide(color: AppBorders.defaultColor(context)))),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 2,
                    height: 42,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: selected ? scheme.primary : Colors.transparent,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(
                            ResourcePresentationResolver.safeName(
                                item.name, l10n),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall),
                        const SizedBox(height: 3),
                        Wrap(
                          spacing: 6,
                          runSpacing: 2,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            for (var i = 0; i < meta.length; i++) ...[
                              if (i > 0)
                                Text('·',
                                    style: mutedStyle?.copyWith(
                                        color: scheme.onSurfaceVariant
                                            .withValues(alpha: 0.55))),
                              Text(meta[i], style: mutedStyle),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                            ResourcePresentationResolver.safeSummary(
                                item.summary, l10n),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant)),
                        if (timestamp != null) ...[
                          const SizedBox(height: 5),
                          Text(timestamp,
                              style: mutedStyle?.copyWith(
                                  color: scheme.onSurfaceVariant
                                      .withValues(alpha: 0.8))),
                        ],
                      ])),
                ],
              ),
            ),
          ),
        ));
  }
}
