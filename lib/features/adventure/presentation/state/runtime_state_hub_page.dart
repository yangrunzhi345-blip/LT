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
    final theme = Theme.of(context);
    final current = _current;
    final entities =
        current?.entities.values.toList() ?? const <RuntimeEntityState>[];
    final characterEntities = entities
        .where((entity) =>
            entity.entityType == RuntimeEntityType.character ||
            entity.entityType == RuntimeEntityType.npc)
        .toList();
    final worldEntities = entities
        .where((entity) =>
            entity.entityType == RuntimeEntityType.world ||
            entity.entityType == RuntimeEntityType.location ||
            entity.entityType == RuntimeEntityType.faction ||
            entity.entityType == RuntimeEntityType.relationship)
        .toList();

    final config = ref.read(chatProvider).adventureConfig;
    final names = _knownCharacterNames();
    final presentIds = _sceneState?.presentCharacterIds ?? const [];
    final presentNames = presentIds
        .map((id) => RuntimeStatePresentation.entityLabel(
            RuntimeEntityType.character, names[id], l10n))
        .toList();

    final recentChangedTurn =
        _turns.where((t) => t.hasChanges).firstOrNull ?? _turns.firstOrNull;

    return ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          if (_sceneState != null)
            WorkbenchSection(
                title: l10n.runtimeStateCurrent,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(_sceneState!.location,
                          style: theme.textTheme.titleSmall),
                      if (_sceneState!.time.isNotEmpty) Text(_sceneState!.time),
                      if (presentNames.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(l10n.runtimeStateInScene),
                        Text(presentNames.join(' · '))
                      ],
                    ])),
          const SizedBox(height: 24),
          WorkbenchSection(
              title: l10n.characterStatusTitle,
              action: TextButton(
                  onPressed: () =>
                      setState(() => _view = _RuntimeStateView.characters),
                  child: Text(l10n.characterManagementViewStatus)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final entity in characterEntities.take(5))
                      Text(RuntimeStatePresentation.entityLabel(
                          entity.entityType, names[entity.entityId], l10n)),
                    if (characterEntities.isEmpty)
                      Text(l10n.runtimeStateNoChanges),
                  ])),
          const SizedBox(height: 24),
          WorkbenchSection(
              title: l10n.worldviewModuleState,
              action: TextButton(
                  onPressed: () =>
                      setState(() => _view = _RuntimeStateView.world),
                  child: Text(l10n.characterManagementViewStatus)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final entity in worldEntities.take(5))
                      Text(RuntimeStatePresentation.entityLabel(
                          entity.entityType, names[entity.entityId], l10n)),
                    if (worldEntities.isEmpty) Text(l10n.runtimeStateNoChanges),
                  ])),
          const SizedBox(height: 24),
          WorkbenchSection(
              title: l10n.trackedStateStatusTitle,
              action: TextButton(
                  onPressed: () =>
                      setState(() => _view = _RuntimeStateView.tracked),
                  child: Text(l10n.trackedStateViewAllAction)),
              child: TrackedStateOverviewPanel(
                config: config,
                entities:
                    ref.watch(chatProvider).adventureProvider.runtimeEntities,
                entityNames: names,
                compact: true,
                onManage: _openTrackedStateManagement,
              )),
          const SizedBox(height: 24),
          WorkbenchSection(
              title: l10n.runtimeStateRecentChange,
              action: TextButton(
                  onPressed: () => setState(() {
                        _view = _RuntimeStateView.turns;
                        _selectedTurn = recentChangedTurn;
                      }),
                  child: Text(l10n.runtimeStateHistoricalChange)),
              child: Text(recentChangedTurn == null
                  ? l10n.runtimeStateNoChanges
                  : RuntimeStatePresentation.turnSummary(
                      recentChangedTurn, l10n,
                      entityNames: names))),
        ]);
  }

  Widget _buildEntities(
    BuildContext context,
    AppLocalizations l10n,
    Set<RuntimeEntityType> types,
    String title,
  ) {
    final entities = (_current?.entities.values ?? const <RuntimeEntityState>[])
        .where((entity) => types.contains(entity.entityType))
        .toList();
    final config = ref.read(chatProvider).adventureConfig;
    final customAttributeLabels =
        RuntimeStatePresentation.customAttributeLabels(
      config?.allTrackedCustomAttributes ?? const [],
    );
    final names = _knownCharacterNames();

    if (types.contains(RuntimeEntityType.character) ||
        types.contains(RuntimeEntityType.npc)) {
      final known = entities.map((entity) => entity.entityId).toSet();
      final protagonist = config?.protagonistCharacter;
      if (protagonist != null && !known.contains(protagonist.characterId)) {
        entities.add(RuntimeEntityState(
          entityType: RuntimeEntityType.character,
          entityId: protagonist.characterId,
        ));
      }
      final baselineCharacters = config?.supportingCharacters ?? const [];
      for (final character in baselineCharacters) {
        if (known.contains(character.id)) {
          continue;
        }
        entities.add(RuntimeEntityState(
          entityType: RuntimeEntityType.npc,
          entityId: character.id,
          overlay: {
            'affinity': character.affinity,
            'relationship': character.relation,
            'life_status': character.isAlive ? 'alive' : 'dead',
          },
          lifecycleStatus: character.isAlive ? 'active' : 'dead',
        ));
      }
    }
    // Resolve baseline plus HEAD through the shared read-only resolver before
    // presenting character values. The hub never mutates AdventureConfig.
    if (config != null && _current != null) {
      final effective = RuntimeEffectiveStateView.fromSnapshot(
        baseline: config,
        snapshot: _current!,
      ).effectiveConfig;
      final effectiveById = {
        for (final character in effective.supportingCharacters)
          character.id: character,
      };
      for (var index = 0; index < entities.length; index++) {
        final entity = entities[index];
        if (entity.entityType != RuntimeEntityType.character &&
            entity.entityType != RuntimeEntityType.npc) {
          continue;
        }
        final character = effectiveById[entity.entityId];
        if (character == null) continue;
        final overlay = Map<String, Object?>.from(entity.overlay);
        overlay.putIfAbsent('affinity', () => character.affinity);
        overlay.putIfAbsent('relationship', () => character.relation);
        overlay.putIfAbsent(
            'life_status', () => character.isAlive ? 'alive' : 'dead');
        entities[index] = RuntimeEntityState(
          entityType: entity.entityType,
          entityId: entity.entityId,
          overlay: overlay,
          lifecycleStatus: entity.lifecycleStatus,
          lastCommitId: entity.lastCommitId,
        );
      }
    }
    if (entities.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('${l10n.emptyRecycleBin}: $title'),
        ),
      );
    }
    final presentIds =
        _sceneState?.presentCharacterIds.toSet() ?? const <String>{};
    return LayoutBuilder(builder: (context, constraints) {
      // Two property panes need 720 logical pixels; otherwise use a detail route.
      final inline = _usesWideNavigation && constraints.maxWidth >= 720;
      final selected = entities
              .where((entity) =>
                  (entity.entityType, entity.entityId) == _selectedEntityKey)
              .firstOrNull ??
          entities.first;
      final list = ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (types.contains(RuntimeEntityType.character) &&
              !widget.openCharacters)
            Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                    onPressed: widget.onManageCharacters ??
                        () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) =>
                                const SceneCharacterManagementPage())),
                    child: Text(l10n.characterManagementManage))),
          if (_sceneState != null)
            WorkbenchSection(
              title: l10n.runtimeStateCurrent,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_sceneState!.location),
                  if (_sceneState!.time.trim().isNotEmpty)
                    Text(_sceneState!.time),
                  if (_sceneState!.presentCharacterIds.isNotEmpty)
                    Text(_sceneState!.presentCharacterIds
                        .map((id) => names[id]?.trim().isNotEmpty == true
                            ? names[id]!
                            : l10n.characterStatusTitle)
                        .join(' · ')),
                ],
              ),
            ),
          if (types.contains(RuntimeEntityType.character))
            _buildInitialBaseline(l10n),
          if (types.contains(RuntimeEntityType.world) &&
              AdventureTrackedStateRegistry.fromConfig(config)
                  .forEntity(
                      RuntimeEntityType.world, AdventureRuntimeEntityIds.world)
                  .isNotEmpty)
            WorkbenchSection(
              title: l10n.trackedStateStatusTitle,
              child: TrackedStateOverviewPanel(
                config: config,
                entities:
                    ref.watch(chatProvider).adventureProvider.runtimeEntities,
                entityNames: names,
                category: TrackedStateCategory.world,
                onManage: _openTrackedStateManagement,
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              types.contains(RuntimeEntityType.character)
                  ? l10n.runtimeStateDynamicState
                  : title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          ...entities.map(
            (entity) => _EntityRow(
              entity: entity,
              l10n: l10n,
              customAttributeLabels: customAttributeLabels,
              displayName: names[entity.entityId],
              isInScene: presentIds.contains(entity.entityId),
              showValues: !inline,
              selected: inline &&
                  (selected.entityType, selected.entityId) ==
                      (entity.entityType, entity.entityId),
              key: ValueKey(
                  'runtime-entity-${entity.entityType.name}-${entity.entityId}'),
              onOpen: () {
                if (inline) {
                  setState(() => _selectedEntityKey =
                      (entity.entityType, entity.entityId));
                } else {
                  Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => RuntimeEntityStatePage(
                          entity: entity,
                          displayName: names[entity.entityId])));
                }
              },
              onEdit: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => RuntimeStateEditPage(entity: entity),
              )),
              onHistory: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => RuntimeEntityHistoryPage(entity: entity),
              )),
            ),
          ),
        ],
      );
      if (!inline) return list;
      return Row(children: [
        Expanded(child: list),
        const VerticalDivider(width: 1),
        Expanded(
            child: RuntimeEntityStatePage(
                key: ValueKey((selected.entityType, selected.entityId)),
                entity: selected,
                displayName: names[selected.entityId],
                embedded: true)),
      ]);
    });
  }

  Widget _buildInitialBaseline(AppLocalizations l10n) {
    final config = ref.read(chatProvider).adventureConfig;
    final names = <String>[
      if (config?.protagonistCharacter?.characterName.isNotEmpty == true)
        config!.protagonistCharacter!.characterName,
      ...?config?.supportingCharacters
          .map((character) => character.name)
          .where((name) => name.isNotEmpty),
    ];
    return AppCard(
      margin: const EdgeInsets.only(bottom: 12),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => const RuntimeInitialStatePage(),
      )),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppSvgIcon('inventory',
                  size: 18, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(l10n.runtimeStateBaselineProfile,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        )),
              ),
              const AppSvgIcon('forward'),
            ],
          ),
          const SizedBox(height: 6),
          Text(names.isEmpty ? l10n.runtimeStateNoChanges : names.join(' · ')),
        ],
      ),
    );
  }

  Widget _buildTimeline(BuildContext context, AppLocalizations l10n) {
    if (_timeline.isEmpty) {
      return Center(
          child:
              Text('${l10n.emptyRecycleBin}: ${l10n.worldviewModuleTimeline}'));
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: Text(l10n.runtimeStateAll),
                  selected: _timelineEntityType == null,
                  onSelected: (_) {
                    if (_timelineEntityType != null) {
                      setState(() => _timelineEntityType = null);
                      _load();
                    }
                  },
                ),
                ChoiceChip(
                  label: Text(l10n.characterStatusTitle),
                  selected: _timelineEntityType == RuntimeEntityType.character,
                  onSelected: (_) {
                    if (_timelineEntityType != RuntimeEntityType.character) {
                      setState(() =>
                          _timelineEntityType = RuntimeEntityType.character);
                      _load();
                    }
                  },
                ),
                ChoiceChip(
                  label: Text(l10n.worldviewModuleState),
                  selected: _timelineEntityType == RuntimeEntityType.world,
                  onSelected: (_) {
                    if (_timelineEntityType != RuntimeEntityType.world) {
                      setState(
                          () => _timelineEntityType = RuntimeEntityType.world);
                      _load();
                    }
                  },
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification.metrics.extentAfter < 240 && !_loadingMore) {
                _load(append: true);
              }
              return false;
            },
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: _timeline.length + (_loadingMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _timeline.length) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final entry = _timeline[index];
                final config = ref.read(chatProvider).adventureConfig;
                final customAttributeLabels =
                    RuntimeStatePresentation.customAttributeLabels(
                  config?.allTrackedCustomAttributes ?? const [],
                );
                final checkpoint = _checkpoints
                    .where((value) => value.revision == entry.revision)
                    .firstOrNull;
                return AppCard(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => RuntimeTimelineDetailPage(entry: entry),
                    ),
                  ),
                  margin: const EdgeInsets.only(bottom: 10),
                  child: _TimelineSummary(
                    entry: entry,
                    l10n: l10n,
                    checkpoint: checkpoint,
                    customAttributeLabels: customAttributeLabels,
                    entityNames: _knownCharacterNames(),
                    isHead: entry.revision == _current?.revision,
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTurnHistory(BuildContext context, AppLocalizations l10n) {
    if (_turns.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            l10n.runtimeStateNoChanges,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
      );
    }
    final names = _knownCharacterNames();
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.extentAfter < 240 && !_loadingMore) {
          _load(append: true);
        }
        return false;
      },
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: _turns.length + (_loadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _turns.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final turn = _turns[index];
          final affected = RuntimeStatePresentation.turnAffectedEntityLabels(
            turn,
            l10n,
            entityNames: names,
          );
          return Material(
            color: (_selectedTurn ?? _turns.firstOrNull)?.turnId == turn.turnId
                ? Theme.of(context).colorScheme.surfaceContainerHigh
                : Colors.transparent,
            child: InkWell(
                key: ValueKey('runtime-turn-${turn.turnId}'),
                onTap: () => _openTurn(turn),
                child: Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Wrap(spacing: 8, runSpacing: 4, children: [
                            Text(l10n.runtimeStateTurnLabel(turn.turnNumber),
                                style: Theme.of(context).textTheme.titleSmall),
                            Text(
                                MaterialLocalizations.of(context)
                                    .formatTimeOfDay(TimeOfDay.fromDateTime(
                                        turn.occurredAt.toLocal())),
                                style: Theme.of(context).textTheme.labelSmall),
                          ]),
                          const SizedBox(height: 8),
                          Text(
                              RuntimeStatePresentation.turnSummary(turn, l10n,
                                  entityNames: names),
                              style: Theme.of(context).textTheme.bodySmall),
                          if (affected.isNotEmpty)
                            Text(affected.join(' · '),
                                style: Theme.of(context).textTheme.labelSmall),
                          const SizedBox(height: 8),
                          const Divider(height: 1),
                        ]))),
          );
        },
      ),
    );
  }
}
