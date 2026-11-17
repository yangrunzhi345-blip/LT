import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/responsive/app_breakpoints.dart';
import '../../../../../core/widgets/app_svg_icon.dart';
import '../../../../../core/widgets/workbench_chrome.dart';
import '../../../../../core/widgets/workbench_section.dart';
import '../../../../../core/theme/app_radius.dart';
import '../../../../../core/widgets/app_card.dart';
import '../../../../../core/widgets/app_empty_state.dart';
import '../../../../../core/widgets/app_page_scaffold.dart';
import '../../../../../core/widgets/app_select.dart';
import '../../../../../core/widgets/app_text_field.dart';
import '../../../../../l10n/generated/app_localizations.dart';
import '../../../../../l10n/generated/app_localizations_zh.dart';
import '../../../../../application/adventure/adventure_tracked_state_registry.dart';
import '../../../../../models/adventure_runtime_state.dart';
import '../../../../../models/adventure_config.dart';
import '../../../../../models/adventure_tracked_state.dart';
import '../../../../../models/typed_runtime_state.dart';
import '../../../../../models/runtime_state_history.dart';
import '../../../../../models/turn_state_history.dart';
import '../../../../../models/runtime_state_presentation.dart';
import 'runtime_state_presentation.dart';
import 'tracked_state_overview_panel.dart';
import '../../../../../models/scene_state.dart';
import '../../../../../models/message.dart';
import '../../../../../application/adventure/runtime_effective_state_view.dart';
import '../../../../../providers/riverpod_providers.dart';
import '../session/screens/scene_character_management_page.dart';
import '../session/screens/tracked_state_management_page.dart';

part 'runtime_state_hub_pages.dart';
part 'runtime_hub_views.dart';
part 'runtime_state_checkpoint_pages.dart';
part 'runtime_state_edit_page.dart';

enum _RuntimeStateView {
  dashboard,
  characters,
  world,
  tracked,
  timeline,
  turns
}

enum _WorldEntityFilter { all, locations, factions, relationships }

/// Entry view when the hub is opened from a specific place in the workbench.
enum RuntimeStateHubInitialView { dashboard, tracked, characters }

class RuntimeStateHubPage extends ConsumerStatefulWidget {
  final bool openCharacters;
  final VoidCallback? onManageCharacters;

  /// Which view to open on. Lets the Inspector / character management jump
  /// straight to「检测状态」without a delayed setState hack.
  final RuntimeStateHubInitialView initialView;

  const RuntimeStateHubPage({
    super.key,
    this.openCharacters = false,
    this.onManageCharacters,
    this.initialView = RuntimeStateHubInitialView.dashboard,
  });

  @override
  ConsumerState<RuntimeStateHubPage> createState() =>
      _RuntimeStateHubPageState();
}

class _RuntimeStateHubPageState extends ConsumerState<RuntimeStateHubPage> {
  _RuntimeStateView _view = _RuntimeStateView.dashboard;
  TurnStateChangeGroup? _selectedTurn;
  bool _hasInlineTurnDetail = false;
  bool _usesWideNavigation = false;
  (RuntimeEntityType, String)? _selectedEntityKey;
  RuntimeStateSnapshot? _current;
  SceneState? _sceneState;
  List<RuntimeTimelineEntry> _timeline = const [];
  List<TurnStateChangeGroup> _turns = const [];
  List<RuntimeStateCheckpoint> _checkpoints = const [];
  List<AdventureSelectedCharacter> _dynamicCharacters = const [];
  bool _loading = true;
  bool _loadingMore = false;
  Object? _error;
  int? _beforeRevision;
  int? _beforeTurnRowId;
  RuntimeEntityType? _timelineEntityType;
  _WorldEntityFilter _worldEntityFilter = _WorldEntityFilter.all;
  TrackedStateCategory _trackedCategory = TrackedStateCategory.all;

  @override
  void initState() {
    super.initState();
    if (widget.openCharacters) {
      _view = _RuntimeStateView.characters;
    } else {
      _view = switch (widget.initialView) {
        RuntimeStateHubInitialView.dashboard => _RuntimeStateView.dashboard,
        RuntimeStateHubInitialView.tracked => _RuntimeStateView.tracked,
        RuntimeStateHubInitialView.characters => _RuntimeStateView.characters,
      };
    }
    Future<void>.microtask(_load);
  }

  Future<void> _load({bool append = false}) async {
    final chat = ref.read(chatProvider);
    final adventureId = chat.currentAdventureId;
    if (adventureId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (append) {
      if (_loadingMore) return;
      setState(() => _loadingMore = true);
    } else {
      setState(() {
        _loading = true;
        _error = null;
        _beforeRevision = null;
        _beforeTurnRowId = null;
      });
    }
    try {
      final repository = ref.read(adventureRepoProvider);
      final branchId = chat.currentBranchId;
      final current = append
          ? _current
          : await repository.getCurrentRuntimeState(
              adventureId: adventureId,
              branchId: branchId,
            );
      final sceneState = append
          ? _sceneState
          : await repository.getSceneState(adventureId, branchId);
      final dynamicCharacters = append
          ? _dynamicCharacters
          : await repository.getAdventureCharacterMemberships(
              adventureId, branchId);
      final page = await repository.getRuntimeTimeline(
        adventureId: adventureId,
        branchId: branchId,
        beforeRevision: append ? _beforeRevision : null,
        entityType: _timelineEntityType,
        limit: 30,
      );
      final turnPage = await repository.getTurnStateHistory(
        adventureId: adventureId,
        branchId: branchId,
        beforeTurnRowId: append ? _beforeTurnRowId : null,
        limit: 30,
        entityTypes:
            _timelineEntityType == null ? null : {_timelineEntityType!},
      );
      final checkpoints = append
          ? _checkpoints
          : await repository.getRuntimeCheckpoints(
              adventureId: adventureId,
              branchId: branchId,
              limit: 100,
            );
      if (!mounted) return;
      setState(() {
        _current = current;
        _sceneState = sceneState;
        _dynamicCharacters = dynamicCharacters;
        _checkpoints = checkpoints;
        _timeline = append ? [..._timeline, ...page] : page;
        _turns = append ? [..._turns, ...turnPage] : turnPage;
        if (_selectedTurn case final selected?) {
          _selectedTurn = _turns
              .where((turn) => turn.turnId == selected.turnId)
              .firstOrNull;
        }
        _beforeRevision = page.isEmpty ? _beforeRevision : page.last.revision;
        _beforeTurnRowId =
            turnPage.isEmpty ? _beforeTurnRowId : turnPage.last.turnRowId;
        _loading = false;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();
    final chat = ref.watch(chatProvider);
    final hasAdventure = chat.currentAdventureId != null;
    final config = chat.adventureConfig;
    final adventureTitle = chat.adventureProvider.currentTitle.trim().isNotEmpty
        ? chat.adventureProvider.currentTitle.trim()
        : (config?.name.trim().isNotEmpty == true
            ? config!.name.trim()
            : l10n.runtimeStateCurrent);

    return AppPageScaffold(
      title: adventureTitle,
      maxWidth: null,
      actions: [
        IconButton(
          onPressed: _current == null || !hasAdventure
              ? null
              : () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => RuntimeStateCheckpointCreatePage(
                      revision: _current!.revision,
                    ),
                  )),
          icon: const AppSvgIcon('add'),
          tooltip: l10n.runtimeStateSaveSnapshot,
        ),
        IconButton(
          onPressed: _checkpoints.isEmpty || !hasAdventure
              ? null
              : () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => RuntimeStateCheckpointListPage(
                      checkpoints: _checkpoints,
                    ),
                  )),
          icon: const AppSvgIcon('history'),
          tooltip: l10n.runtimeStateCheckpoint,
        ),
        IconButton(
          onPressed: _loading || !hasAdventure ? null : () => _load(),
          icon: const AppSvgIcon('refresh'),
          tooltip: l10n.reloadAction,
        ),
      ],
      body: _buildBody(context, l10n),
    );
  }

  Widget _buildBody(BuildContext context, AppLocalizations l10n) {
    final chat = ref.watch(chatProvider);
    if (chat.currentAdventureId == null) {
      return Center(
        child: AppEmptyState(
          title: l10n.runtimeStateNoAdventure,
        ),
      );
    }
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.pageLoadError),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: Text(l10n.retryAction)),
            ],
          ),
        ),
      );
    }

    final branchName = chat.currentBranchId == 0
        ? l10n.runtimeStateMainStory
        : l10n.branchNumberLabel(chat.currentBranchId);
    final labels = {
      _RuntimeStateView.dashboard: l10n.runtimeStateOverview,
      _RuntimeStateView.characters: l10n.characterStatusTitle,
      _RuntimeStateView.world: l10n.worldviewModuleState,
      _RuntimeStateView.tracked: l10n.trackedStateStatusTitle,
      _RuntimeStateView.turns: l10n.runtimeStateHistoricalChange,
      _RuntimeStateView.timeline: l10n.worldviewModuleTimeline,
    };
    return LayoutBuilder(builder: (context, constraints) {
      final twoPane = constraints.maxWidth >= AppBreakpoints.expandedMin;
      _usesWideNavigation = twoPane;
      final navigation = twoPane
          ? ListView(padding: const EdgeInsets.all(12), children: [
              for (final entry in labels.entries)
                ListTile(
                    key: ValueKey('runtime-view-${entry.key.name}'),
                    selected: entry.key == _view,
                    title: Text(entry.value),
                    onTap: () => setState(() => _view = entry.key)),
            ])
          : Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Wrap(spacing: 8, runSpacing: 4, children: [
                for (final entry in labels.entries)
                  ChoiceChip(
                      key: ValueKey('runtime-view-${entry.key.name}'),
                      showCheckmark: false,
                      selected: entry.key == _view,
                      label: Text(entry.value),
                      onSelected: (_) => setState(() => _view = entry.key)),
              ]));
      final workspace = Column(children: [
        Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Align(
                alignment: Alignment.centerLeft,
                child: Wrap(spacing: 12, runSpacing: 4, children: [
                  Text(branchName,
                      style: Theme.of(context).textTheme.bodySmall),
                  if (_turns.isNotEmpty)
                    Text(l10n.runtimeStateTurnLabel(_turns.first.turnNumber),
                        style: Theme.of(context).textTheme.bodySmall),
                  if (_sceneState?.location.isNotEmpty == true)
                    Text(_sceneState!.location,
                        style: Theme.of(context).textTheme.bodySmall),
                ]))),
        if (!twoPane) navigation,
        Expanded(
            child: _view == _RuntimeStateView.turns
                ? _buildTurnWorkspace(context, l10n, allowInline: twoPane)
                : _buildView(context, l10n)),
      ]);
      return twoPane
          ? Row(children: [
              SizedBox(width: 180, child: navigation),
              const VerticalDivider(width: 1),
              Expanded(child: workspace)
            ])
          : workspace;
    });
  }

  Widget _buildTurnWorkspace(BuildContext context, AppLocalizations l10n,
          {required bool allowInline}) =>
      LayoutBuilder(builder: (context, constraints) {
        // 240 px Turn list + 480 px semantic details; below this use a detail route.
        _hasInlineTurnDetail = allowInline && constraints.maxWidth >= 720;
        if (!_hasInlineTurnDetail) return _buildTurnHistory(context, l10n);
        final turn = _selectedTurn ?? _turns.firstOrNull;
        return Row(children: [
          SizedBox(width: 240, child: _buildTurnHistory(context, l10n)),
          const VerticalDivider(width: 1),
          Expanded(
              child: turn == null
                  ? Center(child: Text(l10n.runtimeStateNoChanges))
                  : TurnStateDetailPage(
                      key: ValueKey(turn.turnId), turn: turn, embedded: true)),
        ]);
      });

  void _openTurn(TurnStateChangeGroup turn) {
    if (_hasInlineTurnDetail) {
      setState(() => _selectedTurn = turn);
    } else {
      Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => TurnStateDetailPage(turn: turn)));
    }
  }

  Widget _buildView(BuildContext context, AppLocalizations l10n) {
    Widget buildWorldView(BuildContext context, AppLocalizations l10n) {
      final types = switch (_worldEntityFilter) {
        _WorldEntityFilter.all => {
            RuntimeEntityType.world,
            RuntimeEntityType.location,
            RuntimeEntityType.faction,
            RuntimeEntityType.relationship,
          },
        _WorldEntityFilter.locations => {RuntimeEntityType.location},
        _WorldEntityFilter.factions => {RuntimeEntityType.faction},
        _WorldEntityFilter.relationships => {RuntimeEntityType.relationship},
      };
      final title = switch (_worldEntityFilter) {
        _WorldEntityFilter.all => l10n.worldviewModuleState,
        _WorldEntityFilter.locations => l10n.worldviewModuleLocations,
        _WorldEntityFilter.factions => l10n.worldviewModuleFactions,
        _WorldEntityFilter.relationships => l10n.runtimeStateRelationships,
      };
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: Text(l10n.worldviewModuleState),
                  selected: _worldEntityFilter == _WorldEntityFilter.all,
                  onSelected: (_) => setState(
                      () => _worldEntityFilter = _WorldEntityFilter.all),
                ),
                ChoiceChip(
                  label: Text(l10n.worldviewModuleLocations),
                  selected: _worldEntityFilter == _WorldEntityFilter.locations,
                  onSelected: (_) => setState(
                      () => _worldEntityFilter = _WorldEntityFilter.locations),
                ),
                ChoiceChip(
                  label: Text(l10n.worldviewModuleFactions),
                  selected: _worldEntityFilter == _WorldEntityFilter.factions,
                  onSelected: (_) => setState(
                      () => _worldEntityFilter = _WorldEntityFilter.factions),
                ),
                ChoiceChip(
                  label: Text(l10n.runtimeStateRelationships),
                  selected:
                      _worldEntityFilter == _WorldEntityFilter.relationships,
                  onSelected: (_) => setState(() =>
                      _worldEntityFilter = _WorldEntityFilter.relationships),
                ),
              ],
            ),
          ),
          Expanded(child: _buildEntities(context, l10n, types, title)),
        ],
      );
    }

    return switch (_view) {
      _RuntimeStateView.dashboard => _buildDashboard(context, l10n),
      _RuntimeStateView.characters => _buildEntities(
          context,
          l10n,
          {RuntimeEntityType.character, RuntimeEntityType.npc},
          l10n.characterStatusTitle,
        ),
      _RuntimeStateView.world => buildWorldView(context, l10n),
      _RuntimeStateView.tracked => _buildTrackedView(context, l10n),
      _RuntimeStateView.timeline => _buildTimeline(context, l10n),
      _RuntimeStateView.turns => _buildTurnHistory(context, l10n),
    };
  }

  void _openTrackedStateManagement() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => const TrackedStateManagementPage(),
    ));
  }

  Widget _buildTrackedView(BuildContext context, AppLocalizations l10n) {
    final chat = ref.watch(chatProvider);
    final config = chat.adventureConfig;
    // Live values (not the loaded snapshot) so a management-page edit is
    // visible immediately after returning.
    final entities = chat.adventureProvider.runtimeEntities;
    final names = _knownCharacterNames();
    final filters = <(TrackedStateCategory, String)>[
      (TrackedStateCategory.all, l10n.trackedStateFilterAll),
      (TrackedStateCategory.character, l10n.trackedStateEntityTypeCharacter),
      (TrackedStateCategory.npc, l10n.trackedStateEntityTypeNpc),
      (TrackedStateCategory.world, l10n.trackedStateEntityTypeWorld),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: WorkbenchTabBar(
            children: [
              for (final (category, label) in filters)
                WorkbenchTabButton(
                  key: ValueKey('tracked-filter-${category.name}'),
                  label: label,
                  selected: _trackedCategory == category,
                  onTap: () => setState(() => _trackedCategory = category),
                ),
            ],
          ),
        ),
        WorkbenchSection(
          title: l10n.trackedStateStatusTitle,
          action: TextButton(
            onPressed: () => setState(() => _view = _RuntimeStateView.turns),
            child: Text(l10n.runtimeStateHistoricalChange),
          ),
          child: TrackedStateOverviewPanel(
            config: config,
            entities: entities,
            entityNames: names,
            category: _trackedCategory,
            onManage: _openTrackedStateManagement,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.trackedStateUntriggeredHint,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }

  Map<String, String> _knownCharacterNames() {
    final config = ref.read(chatProvider).adventureConfig;
    final names = RuntimeStatePresentation.resolveKnownNames(
      config: config,
      dynamicCharacters: _dynamicCharacters,
    );
    if (config != null) {
      for (final relationship in config.characterRelationships) {
        final source = names[relationship.sourceCharacterId] ??
            relationship.sourceCharacterId;
        final target = names[relationship.targetCharacterId] ??
            relationship.targetCharacterId;
        names[relationship.id] = '$source → $target';
      }
    }
    return names;
  }

  Widget _buildDashboard(BuildContext context, AppLocalizations l10n) {
    return RuntimeHubDashboardView(
      l10n: l10n,
      current: _current,
      sceneState: _sceneState,
      turns: _turns,
      characterNames: _knownCharacterNames(),
      adventureConfig: ref.read(chatProvider).adventureConfig,
      runtimeEntities:
          ref.watch(chatProvider).adventureProvider.runtimeEntities,
      onOpenCharacters: () =>
          setState(() => _view = _RuntimeStateView.characters),
      onOpenWorld: () => setState(() => _view = _RuntimeStateView.world),
      onOpenTracked: () => setState(() => _view = _RuntimeStateView.tracked),
      onOpenTurn: (turn) => setState(() {
        _view = _RuntimeStateView.turns;
        _selectedTurn = turn;
      }),
      onManageTracked: _openTrackedStateManagement,
    );
  }

  Widget _buildEntities(
    BuildContext context,
    AppLocalizations l10n,
    Set<RuntimeEntityType> types,
    String title,
  ) {
    return RuntimeHubEntitiesView(
      l10n: l10n,
      types: types,
      title: title,
      current: _current,
      sceneState: _sceneState,
      adventureConfig: ref.read(chatProvider).adventureConfig,
      characterNames: _knownCharacterNames(),
      runtimeEntities:
          ref.watch(chatProvider).adventureProvider.runtimeEntities,
      openCharacters: widget.openCharacters,
      onManageCharacters: widget.onManageCharacters,
      useWideNavigation: _usesWideNavigation,
      selectedEntityKey: _selectedEntityKey,
      onSelectEntity: (key) => setState(() => _selectedEntityKey = key),
      onManageTracked: _openTrackedStateManagement,
    );
  }

  Widget _buildTimeline(BuildContext context, AppLocalizations l10n) {
    return RuntimeHubTimelineView(
      l10n: l10n,
      timeline: _timeline,
      checkpoints: _checkpoints,
      headRevision: _current?.revision,
      filterType: _timelineEntityType,
      characterNames: _knownCharacterNames(),
      customAttributeLabels: RuntimeStatePresentation.customAttributeLabels(
        ref.read(chatProvider).adventureConfig?.allTrackedCustomAttributes ??
            const [],
      ),
      isLoadingMore: _loadingMore,
      onFilterChanged: (type) {
        setState(() => _timelineEntityType = type);
        _load();
      },
      onLoadMore: () => _load(append: true),
    );
  }

  Widget _buildTurnHistory(BuildContext context, AppLocalizations l10n) {
    return RuntimeHubTurnHistoryView(
      l10n: l10n,
      turns: _turns,
      selectedTurn: _selectedTurn,
      characterNames: _knownCharacterNames(),
      isLoadingMore: _loadingMore,
      onLoadMore: () => _load(append: true),
      onOpenTurn: _openTurn,
    );
  }
}
