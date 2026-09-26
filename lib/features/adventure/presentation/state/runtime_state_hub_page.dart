import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_radius.dart';
import '../../../../../core/widgets/app_card.dart';
import '../../../../../core/widgets/app_empty_state.dart';
import '../../../../../core/widgets/app_page_scaffold.dart';
import '../../../../../core/widgets/app_select.dart';
import '../../../../../core/widgets/app_text_field.dart';
import '../../../../../l10n/generated/app_localizations.dart';
import '../../../../../l10n/generated/app_localizations_zh.dart';
import '../../../../../models/adventure_runtime_state.dart';
import '../../../../../models/adventure_config.dart';
import '../../../../../models/typed_runtime_state.dart';
import '../../../../../models/runtime_state_history.dart';
import '../../../../../models/turn_state_history.dart';
import '../../../../../models/runtime_state_presentation.dart';
import 'runtime_state_presentation.dart';
import '../../../../../models/scene_state.dart';
import '../../../../../models/message.dart';
import '../../../../../application/adventure/runtime_effective_state_view.dart';
import '../../../../../providers/riverpod_providers.dart';

enum _RuntimeStateView { dashboard, characters, world, timeline, turns }

enum _WorldEntityFilter { all, locations, factions, relationships }

class RuntimeStateHubPage extends ConsumerStatefulWidget {
  const RuntimeStateHubPage({super.key});

  @override
  ConsumerState<RuntimeStateHubPage> createState() =>
      _RuntimeStateHubPageState();
}

class _RuntimeStateHubPageState extends ConsumerState<RuntimeStateHubPage> {
  _RuntimeStateView _view = _RuntimeStateView.dashboard;
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

  @override
  void initState() {
    super.initState();
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
      maxWidth: 1040,
      actions: [
        IconButton(
          onPressed: _current == null || !hasAdventure
              ? null
              : () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => RuntimeStateCheckpointCreatePage(
                      revision: _current!.revision,
                    ),
                  )),
          icon: const Icon(Icons.bookmark_add_outlined),
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
          icon: const Icon(Icons.bookmarks_outlined),
          tooltip: l10n.runtimeStateCheckpoint,
        ),
        IconButton(
          onPressed: _loading || !hasAdventure ? null : () => _load(),
          icon: const Icon(Icons.refresh_rounded),
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
          icon: Icons.hub_outlined,
          title: l10n.runtimeStateNoAdventure,
        ),
      );
    }
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: AppCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded),
              const SizedBox(height: 8),
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
    final turnsCountText =
        _turns.isNotEmpty ? l10n.runtimeStateTotalTurns(_turns.length) : null;
    final latestTurnBadge = _turns.isNotEmpty
        ? l10n.runtimeStateTurnLabel(_turns.first.turnNumber)
        : null;

    final headerBanner = Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Text(
              branchName,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          if (turnsCountText != null)
            Text(
              turnsCountText,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          if (latestTurnBadge != null)
            Text(
              '($latestTurnBadge)',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
        ],
      ),
    );

    final navBar = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: SegmentedButton<_RuntimeStateView>(
        segments: [
          ButtonSegment(
            value: _RuntimeStateView.dashboard,
            icon: const Icon(Icons.dashboard_outlined),
            label: Text(l10n.runtimeStateOverview),
          ),
          ButtonSegment(
            value: _RuntimeStateView.characters,
            icon: const Icon(Icons.badge_outlined),
            label: Text(l10n.characterStatusTitle),
          ),
          ButtonSegment(
            value: _RuntimeStateView.world,
            icon: const Icon(Icons.public_outlined),
            label: Text(l10n.worldviewModuleState),
          ),
          ButtonSegment(
            value: _RuntimeStateView.turns,
            icon: const Icon(Icons.history_toggle_off_rounded),
            label: Text(l10n.runtimeStateHistoricalChange),
          ),
          ButtonSegment(
            value: _RuntimeStateView.timeline,
            icon: const Icon(Icons.timeline_rounded),
            label: Text(l10n.worldviewModuleTimeline),
          ),
        ],
        selected: {_view},
        onSelectionChanged: (selected) {
          if (selected.isNotEmpty) setState(() => _view = selected.first);
        },
      ),
    );

    final isDesktop = MediaQuery.sizeOf(context).width >= 900;
    if (isDesktop && _view == _RuntimeStateView.dashboard) {
      return Column(
        children: [
          headerBanner,
          navBar,
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 6,
                  child: _buildDashboard(context, l10n),
                ),
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: Theme.of(context)
                      .colorScheme
                      .outlineVariant
                      .withValues(alpha: 0.3),
                ),
                Expanded(
                  flex: 5,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Text(
                          l10n.runtimeStateHistoricalChange,
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                      ),
                      Expanded(child: _buildTurnHistory(context, l10n)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        headerBanner,
        navBar,
        Expanded(child: _buildView(context, l10n)),
      ],
    );
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
      _RuntimeStateView.timeline => _buildTimeline(context, l10n),
      _RuntimeStateView.turns => _buildTurnHistory(context, l10n),
    };
  }

  Map<String, String> _knownCharacterNames() {
    final config = ref.read(chatProvider).adventureConfig;
    return RuntimeStatePresentation.resolveKnownNames(
      config: config,
      dynamicCharacters: _dynamicCharacters,
    );
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
          AppCard(
            margin: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.place_outlined,
                        size: 18, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _sceneState!.location.isNotEmpty
                            ? _sceneState!.location
                            : l10n.unknownRegion,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (_sceneState!.time.trim().isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        child: Text(
                          _sceneState!.time.trim(),
                          style: theme.textTheme.labelSmall,
                        ),
                      ),
                  ],
                ),
                if (presentNames.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    l10n.runtimeStateInScene,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: presentNames
                        .map((name) => Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primaryContainer,
                                borderRadius:
                                    BorderRadius.circular(AppRadius.sm),
                              ),
                              child: Text(
                                name,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: theme.colorScheme.onPrimaryContainer,
                                ),
                              ),
                            ))
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
        AppCard(
          margin: const EdgeInsets.only(bottom: 12),
          onTap: () => setState(() => _view = _RuntimeStateView.characters),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.badge_outlined,
                      size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.characterStatusTitle,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    '${characterEntities.length}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
              if (characterEntities.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: characterEntities.take(6).map((entity) {
                    final charName = RuntimeStatePresentation.entityLabel(
                      entity.entityType,
                      names[entity.entityId],
                      l10n,
                    );
                    final hp = entity.overlay['hp'];
                    final hpText = hp != null ? ' · HP $hp' : '';
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Text(
                        '$charName$hpText',
                        style: theme.textTheme.labelSmall,
                      ),
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),
        AppCard(
          margin: const EdgeInsets.only(bottom: 12),
          onTap: () => setState(() => _view = _RuntimeStateView.world),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.public_outlined,
                      size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.worldviewModuleState,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    '${worldEntities.length}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
              if (worldEntities.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: worldEntities.take(5).map((entity) {
                    final entityName = RuntimeStatePresentation.entityLabel(
                      entity.entityType,
                      names[entity.entityId],
                      l10n,
                    );
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Text(
                        entityName,
                        style: theme.textTheme.labelSmall,
                      ),
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),
        AppCard(
          margin: const EdgeInsets.only(bottom: 12),
          onTap: recentChangedTurn != null
              ? () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) =>
                        TurnStateDetailPage(turn: recentChangedTurn),
                  ))
              : () => setState(() => _view = _RuntimeStateView.turns),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.history_toggle_off_rounded,
                      size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.runtimeStateRecentChange,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (recentChangedTurn != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Text(
                        l10n.runtimeStateTurnLabel(
                            recentChangedTurn.turnNumber),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
              const SizedBox(height: 8),
              if (recentChangedTurn != null) ...[
                Text(
                  RuntimeStatePresentation.turnSummary(
                    recentChangedTurn,
                    l10n,
                    entityNames: names,
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ] else
                Text(
                  l10n.runtimeStateNoChanges,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
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
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        if (_sceneState != null)
          AppCard(
            margin: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.runtimeStateCurrent,
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
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
          (entity) => _EntityCard(
            entity: entity,
            l10n: l10n,
            customAttributeLabels: customAttributeLabels,
            displayName: names[entity.entityId],
            isInScene: presentIds.contains(entity.entityId),
            onOpen: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => RuntimeEntityStatePage(
                entity: entity,
                displayName: names[entity.entityId],
              ),
            )),
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
              Icon(Icons.inventory_2_outlined,
                  size: 18, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(l10n.runtimeStateBaselineProfile,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        )),
              ),
              const Icon(Icons.chevron_right_rounded),
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
          return AppCard(
            margin: const EdgeInsets.only(bottom: 10),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => TurnStateDetailPage(turn: turn),
            )),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.runtimeStateTurnLabel(turn.turnNumber),
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Text(
                        RuntimeStatePresentation.sourceLabel(
                          turn.changes.firstOrNull?.causeType,
                          null,
                          l10n,
                        ),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Text(
                        l10n.runtimeStateChangeCount(turn.changeCount),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color:
                              Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right_rounded),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  RuntimeStatePresentation.turnSummary(
                    turn,
                    l10n,
                    entityNames: names,
                  ),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                if (affected.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: affected
                        .take(4)
                        .map((label) => Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHigh,
                                borderRadius:
                                    BorderRadius.circular(AppRadius.sm),
                              ),
                              child: Text(
                                label,
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(fontSize: 10),
                              ),
                            ))
                        .toList(),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class TurnStateDetailPage extends ConsumerWidget {
  final TurnStateChangeGroup turn;

  const TurnStateDetailPage({super.key, required this.turn});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();
    final theme = Theme.of(context);
    final chat = ref.read(chatProvider);
    final config = chat.adventureConfig;
    final customAttributeLabels =
        RuntimeStatePresentation.customAttributeLabels(
      config?.allTrackedCustomAttributes ?? const [],
    );
    final names = RuntimeStatePresentation.resolveKnownNames(config: config);

    final messagesFuture = chat.currentAdventureId == null
        ? Future<List<Message>>.value(const [])
        : ref.read(adventureRepoProvider).getTurnMessages(
              adventureId: chat.currentAdventureId!,
              branchId: chat.currentBranchId,
              assistantMessageId: turn.assistantMessageId,
            );

    final characterChanges = turn.changes
        .where((change) =>
            change.entityType == RuntimeEntityType.character ||
            change.entityType == RuntimeEntityType.npc)
        .toList();

    final worldChanges = turn.changes
        .where((change) =>
            change.entityType != RuntimeEntityType.character &&
            change.entityType != RuntimeEntityType.npc)
        .toList();

    final charGroups = <String, List<TurnStateChange>>{};
    for (final change in characterChanges) {
      charGroups.putIfAbsent(change.entityId, () => []).add(change);
    }

    final worldGroups = <String, List<TurnStateChange>>{};
    for (final change in worldChanges) {
      worldGroups.putIfAbsent(change.entityId, () => []).add(change);
    }

    final affectedLabels = RuntimeStatePresentation.turnAffectedEntityLabels(
      turn,
      l10n,
      entityNames: names,
    );

    return AppPageScaffold(
      title: l10n.runtimeStateTurnLabel(turn.turnNumber),
      maxWidth: 780,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.runtimeStateTurnSummary,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.runtimeStateTurnLabel(turn.turnNumber),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            turn.occurredAt
                                .toLocal()
                                .toString()
                                .split('.')
                                .first,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Text(
                        RuntimeStatePresentation.sourceLabel(
                          turn.changes.firstOrNull?.causeType,
                          null,
                          l10n,
                        ),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  RuntimeStatePresentation.turnSummary(turn, l10n,
                      entityNames: names),
                  style: theme.textTheme.bodyMedium,
                ),
                if (affectedLabels.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    l10n.runtimeStateAffectedEntities,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: affectedLabels
                        .map((label) => Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerHigh,
                                borderRadius:
                                    BorderRadius.circular(AppRadius.sm),
                              ),
                              child: Text(label,
                                  style: theme.textTheme.labelSmall),
                            ))
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
          FutureBuilder<List<Message>>(
            future: messagesFuture,
            builder: (context, snapshot) {
              final messages = snapshot.data ?? const <Message>[];
              if (messages.isEmpty) return const SizedBox.shrink();
              return AppCard(
                margin: const EdgeInsets.only(top: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.runtimeStateCauseDialogue,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final message in messages)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          message.content,
                          maxLines: 6,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            height: 1.4,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
          if (turn.changes.isEmpty)
            AppCard(
              margin: const EdgeInsets.only(top: 12),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    l10n.runtimeStateNoVisibleChanges,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          if (charGroups.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
              child: Text(
                l10n.runtimeStateCharacterChanges,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            for (final group in charGroups.entries)
              AppCard(
                margin: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.badge_outlined,
                            size: 18, color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            RuntimeStatePresentation.entityLabel(
                              group.value.first.entityType,
                              names[group.key],
                              l10n,
                            ),
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 16),
                    for (final change in group.value)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    RuntimeStatePresentation
                                        .fieldLabelWithMetadata(
                                      change.path,
                                      l10n,
                                      customAttributeLabels:
                                          customAttributeLabels,
                                    ),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: theme
                                        .colorScheme.surfaceContainerHighest,
                                    borderRadius:
                                        BorderRadius.circular(AppRadius.sm),
                                  ),
                                  child: Text(
                                    RuntimeStatePresentation.sourceLabel(
                                      change.causeType,
                                      null,
                                      l10n,
                                    ),
                                    style: theme.textTheme.labelSmall,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              RuntimeStatePresentation.formatDiff(
                                change.path,
                                change.before,
                                change.after,
                                l10n,
                              ),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (RuntimeStatePresentation.isSafeReason(
                                change.reason)) ...[
                              const SizedBox(height: 3),
                              Text(
                                change.reason,
                                maxLines: 4,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                  ],
                ),
              ),
          ],
          if (worldGroups.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
              child: Text(
                l10n.runtimeStateWorldChanges,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            for (final group in worldGroups.entries)
              AppCard(
                margin: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.public_outlined,
                            size: 18, color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            RuntimeStatePresentation.entityLabel(
                              group.value.first.entityType,
                              names[group.key],
                              l10n,
                            ),
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 16),
                    for (final change in group.value)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    RuntimeStatePresentation
                                        .fieldLabelWithMetadata(
                                      change.path,
                                      l10n,
                                      customAttributeLabels:
                                          customAttributeLabels,
                                    ),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: theme
                                        .colorScheme.surfaceContainerHighest,
                                    borderRadius:
                                        BorderRadius.circular(AppRadius.sm),
                                  ),
                                  child: Text(
                                    RuntimeStatePresentation.sourceLabel(
                                      change.causeType,
                                      null,
                                      l10n,
                                    ),
                                    style: theme.textTheme.labelSmall,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              RuntimeStatePresentation.formatDiff(
                                change.path,
                                change.before,
                                change.after,
                                l10n,
                              ),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (RuntimeStatePresentation.isSafeReason(
                                change.reason)) ...[
                              const SizedBox(height: 3),
                              Text(
                                change.reason,
                                maxLines: 4,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _EntityCard extends StatelessWidget {
  final RuntimeEntityState entity;
  final AppLocalizations l10n;
  final VoidCallback onEdit;
  final VoidCallback onHistory;
  final String? displayName;
  final Map<String, String> customAttributeLabels;
  final VoidCallback? onOpen;
  final bool isInScene;

  const _EntityCard({
    required this.entity,
    required this.l10n,
    required this.onEdit,
    required this.onHistory,
    this.displayName,
    this.customAttributeLabels = const {},
    this.onOpen,
    this.isInScene = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final values = entity.overlay.entries
        .where((entry) =>
            RuntimeStatePresentationRegistry.find(entity.entityType, entry.key)
                ?.visibility !=
            RuntimeStateFieldVisibility.hidden)
        .toList()
      ..sort((left, right) {
        final leftPriority =
            RuntimeStatePresentationRegistry.find(entity.entityType, left.key)
                    ?.priority ??
                100;
        final rightPriority =
            RuntimeStatePresentationRegistry.find(entity.entityType, right.key)
                    ?.priority ??
                100;
        return leftPriority.compareTo(rightPriority);
      });

    return AppCard(
      onTap: onOpen,
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(_iconFor(entity.entityType),
                    size: 20, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      RuntimeStatePresentation.entityLabel(
                          entity.entityType, displayName, l10n),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (isInScene)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                            ),
                            child: Text(
                              l10n.runtimeStateInScene,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                          child: Text(
                            RuntimeStatePresentation.valueLabel(
                                'lifecycle_status',
                                entity.lifecycleStatus,
                                l10n),
                            style: theme.textTheme.labelSmall,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onHistory,
                icon: const Icon(Icons.history_rounded, size: 20),
                tooltip: l10n.worldviewModuleTimeline,
              ),
              IconButton(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 20),
                tooltip: l10n.editAction,
              ),
            ],
          ),
          if (values.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(l10n.runtimeStateNoChanges),
            )
          else
            ...values.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                        child: Text(RuntimeStatePresentation.fieldLabel(
                            entry.key, l10n))),
                    Flexible(
                      child: Text(
                        RuntimeStatePresentation.valueLabel(
                            entry.key, entry.value, l10n),
                        textAlign: TextAlign.end,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  static IconData _iconFor(RuntimeEntityType type) => switch (type) {
        RuntimeEntityType.character ||
        RuntimeEntityType.npc =>
          Icons.badge_outlined,
        RuntimeEntityType.location => Icons.place_outlined,
        RuntimeEntityType.faction => Icons.groups_outlined,
        RuntimeEntityType.relationship => Icons.handshake_outlined,
        RuntimeEntityType.world => Icons.public_outlined,
      };
}

class _TimelineSummary extends StatelessWidget {
  final RuntimeTimelineEntry entry;
  final AppLocalizations l10n;
  final RuntimeStateCheckpoint? checkpoint;
  final Map<String, String> customAttributeLabels;
  final Map<String, String> entityNames;
  final bool isHead;

  const _TimelineSummary({
    required this.entry,
    required this.l10n,
    this.checkpoint,
    this.customAttributeLabels = const {},
    this.entityNames = const {},
    this.isHead = false,
  });

  @override
  Widget build(BuildContext context) {
    final changes = entry.diffs.take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (isHead) ...[
              const SizedBox(width: 6),
              Chip(label: Text(l10n.runtimeStateHead)),
            ],
            if (checkpoint != null) ...[
              const SizedBox(width: 6),
              Flexible(
                  child: Chip(
                      label: Text(
                          '${l10n.runtimeStateCheckpoint}: ${checkpoint!.name}'))),
            ],
            for (final importance
                in entry.events.map((event) => event.importance).toSet())
              if (importance == RuntimeEventImportance.major ||
                  importance == RuntimeEventImportance.critical) ...[
                const SizedBox(width: 6),
                Chip(label: Text(l10n.runtimeStateSignificantChange)),
              ],
            const SizedBox(width: 8),
            Expanded(child: Text(_formatDate(entry.occurredAt))),
            if (entry.isLegacy) Chip(label: Text(l10n.runtimeStateLegacy)),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
        const SizedBox(height: 8),
        Text(RuntimeStatePresentation.timelineTitle(entry.diffs.length, l10n)),
        for (final diff in changes)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
                '${RuntimeStatePresentation.entityLabel(diff.entityType, entityNames[diff.entityId], l10n)} · ${RuntimeStatePresentation.fieldLabelWithMetadata(diff.path, l10n, customAttributeLabels: customAttributeLabels)}: ${RuntimeStatePresentation.valueLabel(diff.path, diff.before, l10n)} → ${RuntimeStatePresentation.valueLabel(diff.path, diff.after, l10n)}'),
          ),
      ],
    );
  }

  static String _formatDate(DateTime value) =>
      value.toLocal().toString().split('.').first;
}

class RuntimeTimelineDetailPage extends ConsumerWidget {
  final RuntimeTimelineEntry entry;

  const RuntimeTimelineDetailPage({super.key, required this.entry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();
    final config = ref.read(chatProvider).adventureConfig;
    final customAttributeLabels =
        RuntimeStatePresentation.customAttributeLabels(
      config?.allTrackedCustomAttributes ?? const [],
    );
    return AppPageScaffold(
      title: l10n.runtimeStateHistoricalChange,
      maxWidth: 760,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_TimelineSummary._formatDate(entry.occurredAt)),
                const SizedBox(height: 8),
                Text(RuntimeStatePresentation.timelineTitle(
                    entry.diffs.length, l10n)),
                const SizedBox(height: 8),
                Text(entry.isLegacy
                    ? l10n.runtimeStateHistoricalChange
                    : l10n.runtimeStateCommittedEvent),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => RuntimeStateRevertPreviewPage(
                          targetRevision: entry.revision),
                    ),
                  ),
                  icon: const Icon(Icons.undo_rounded),
                  label: Text(l10n.restoreRevision),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => RuntimeStateCheckpointCreatePage(
                      revision: entry.revision,
                    ),
                  )),
                  icon: const Icon(Icons.bookmark_add_outlined),
                  label: Text(l10n.runtimeStateSaveSnapshot),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => RuntimeStateComparePage(
                      historicalRevision: entry.revision,
                    ),
                  )),
                  icon: const Icon(Icons.compare_arrows_rounded),
                  label: Text(l10n.runtimeStateCompareCurrent),
                ),
              ],
            ),
          ),
          for (final diff in entry.diffs)
            AppCard(
              margin: const EdgeInsets.only(top: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      RuntimeStatePresentation.fieldLabelWithMetadata(
                          diff.path, l10n,
                          customAttributeLabels: customAttributeLabels),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Text(
                      '${RuntimeStatePresentation.valueLabel(diff.path, diff.before, l10n)} → ${RuntimeStatePresentation.valueLabel(diff.path, diff.after, l10n)}'),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class RuntimeInitialStatePage extends ConsumerWidget {
  const RuntimeInitialStatePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();
    final config = ref.read(chatProvider).adventureConfig;
    final names = <String>[
      if (config?.protagonistCharacter?.characterName.isNotEmpty == true)
        config!.protagonistCharacter!.characterName,
      ...?config?.supportingCharacters
          .map((character) => character.name)
          .where((name) => name.isNotEmpty),
    ];
    final adventureId = ref.read(chatProvider).currentAdventureId;
    final branchId = ref.read(chatProvider).currentBranchId;
    final currentFuture = adventureId == null
        ? Future<RuntimeStateSnapshot>.error(StateError('No active adventure'))
        : ref.read(adventureRepoProvider).getCurrentRuntimeState(
              adventureId: adventureId,
              branchId: branchId,
            );
    return AppPageScaffold(
      title: l10n.runtimeStateInitial,
      maxWidth: 760,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(l10n.runtimeStateInitial,
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          if (names.isEmpty)
            Text(l10n.runtimeStateNoChanges)
          else
            for (final name in names)
              AppCard(
                margin: const EdgeInsets.only(bottom: 8),
                child: Text(name),
              ),
          const SizedBox(height: 8),
          Text(l10n.runtimeStateHistoricalChange),
          const SizedBox(height: 12),
          FutureBuilder<RuntimeStateSnapshot>(
            future: currentFuture,
            builder: (context, snapshot) {
              if (!snapshot.hasData || config == null) {
                return const SizedBox.shrink();
              }
              final view = RuntimeEffectiveStateView.fromSnapshot(
                baseline: config,
                snapshot: snapshot.data!,
              );
              final dynamicEntities = snapshot.data!.entities.values.where(
                (entity) => !view.isPartOfBaseline(entity.entityId),
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final entity in dynamicEntities)
                    AppCard(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Text(
                          '${RuntimeStatePresentation.entityLabel(entity.entityType, null, l10n)}: ${l10n.runtimeStateNotInInitial}'),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Detail projection for one runtime entity. It deliberately reads the same
/// immutable snapshot and archive as the hub; it never owns a second state.
class RuntimeEntityStatePage extends StatelessWidget {
  final RuntimeEntityState entity;
  final String? displayName;

  const RuntimeEntityStatePage({
    super.key,
    required this.entity,
    this.displayName,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();
    final values = entity.overlay.entries.toList();
    return AppPageScaffold(
      title: RuntimeStatePresentation.entityLabel(
          entity.entityType, displayName, l10n),
      maxWidth: 760,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(RuntimeStatePresentation.entityLabel(
                    entity.entityType, displayName, l10n)),
                const SizedBox(height: 12),
                if (values.isEmpty)
                  Text(l10n.runtimeStateNoChanges)
                else
                  for (final value in values)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                              child: Text(RuntimeStatePresentation.fieldLabel(
                                  value.key, l10n))),
                          Flexible(
                            child: Text(
                              RuntimeStatePresentation.valueLabel(
                                  value.key, value.value, l10n),
                              textAlign: TextAlign.end,
                            ),
                          ),
                        ],
                      ),
                    ),
              ],
            ),
          ),
          AppCard(
            margin: const EdgeInsets.only(top: 12),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => RuntimeEntityHistoryPage(entity: entity),
            )),
            child: Row(
              children: [
                Expanded(child: Text(l10n.worldviewModuleTimeline)),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class RuntimeEntityHistoryPage extends ConsumerStatefulWidget {
  final RuntimeEntityState entity;

  const RuntimeEntityHistoryPage({super.key, required this.entity});

  @override
  ConsumerState<RuntimeEntityHistoryPage> createState() =>
      _RuntimeEntityHistoryPageState();
}

class _RuntimeEntityHistoryPageState
    extends ConsumerState<RuntimeEntityHistoryPage> {
  late Future<List<TurnStateChangeGroup>> _future;

  @override
  void initState() {
    super.initState();
    final chat = ref.read(chatProvider);
    final adventureId = chat.currentAdventureId;
    _future = adventureId == null
        ? Future.error(StateError('No active adventure'))
        : ref.read(adventureRepoProvider).getTurnStateHistory(
              adventureId: adventureId,
              branchId: chat.currentBranchId,
              entityTypes: {widget.entity.entityType},
              entityId: widget.entity.entityId,
              limit: 50,
            );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();
    return AppPageScaffold(
      title: l10n.worldviewModuleTimeline,
      maxWidth: 760,
      body: FutureBuilder<List<TurnStateChangeGroup>>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            if (snapshot.hasError) {
              return Center(child: Text(l10n.pageLoadError));
            }
            return const Center(child: CircularProgressIndicator());
          }
          final entries = snapshot.data!;
          if (entries.isEmpty) {
            return Center(child: Text(l10n.runtimeStateNoChanges));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final entry = entries[index];
              return AppCard(
                margin: const EdgeInsets.only(bottom: 10),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => TurnStateDetailPage(turn: entry),
                )),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.runtimeStateTurnLabel(entry.turnNumber),
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 6),
                    for (final change in entry.changes.take(3))
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                            '${RuntimeStatePresentation.fieldLabel(change.path, l10n)}: ${RuntimeStatePresentation.valueLabel(change.path, change.before, l10n)} → ${RuntimeStatePresentation.valueLabel(change.path, change.after, l10n)}'),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class RuntimeStateRevertPreviewPage extends ConsumerStatefulWidget {
  final int targetRevision;

  const RuntimeStateRevertPreviewPage({
    super.key,
    required this.targetRevision,
  });

  @override
  ConsumerState<RuntimeStateRevertPreviewPage> createState() =>
      _RuntimeStateRevertPreviewPageState();
}

class _RuntimeStateRevertPreviewPageState
    extends ConsumerState<RuntimeStateRevertPreviewPage> {
  late Future<RuntimeStateSnapshot> _currentFuture;
  late Future<RuntimeStateSnapshot> _targetFuture;
  int? _baseRevision;
  bool _saving = false;
  Object? _conflict;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    final chat = ref.read(chatProvider);
    final adventureId = chat.currentAdventureId;
    if (adventureId == null) {
      _currentFuture = Future.error(StateError('No active adventure'));
      return;
    }
    final repository = ref.read(adventureRepoProvider);
    _currentFuture = repository.getCurrentRuntimeState(
      adventureId: adventureId,
      branchId: chat.currentBranchId,
    )..then((snapshot) {
        if (mounted) setState(() => _baseRevision = snapshot.revision);
      });
    _targetFuture = repository.getRuntimeStateAtRevision(
      adventureId: adventureId,
      branchId: chat.currentBranchId,
      revision: widget.targetRevision,
    );
  }

  Future<void> _confirm(RuntimeStateSnapshot current) async {
    final chat = ref.read(chatProvider);
    final adventureId = chat.currentAdventureId;
    final baseRevision = _baseRevision;
    if (adventureId == null || baseRevision == null) return;
    setState(() => _saving = true);
    try {
      await ref.read(adventureRepoProvider).revertRuntimeState(
            adventureId: adventureId,
            branchId: chat.currentBranchId,
            targetRevision: widget.targetRevision,
            expectedRevision: baseRevision,
            requestId: 'revert-${DateTime.now().microsecondsSinceEpoch}',
          );
      if (mounted) Navigator.of(context).pop(true);
    } on RuntimeHeadConflict catch (error) {
      if (mounted) setState(() => _conflict = error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();
    return AppPageScaffold(
      title: l10n.restoreRevision,
      maxWidth: 760,
      body: FutureBuilder<RuntimeStateSnapshot>(
        future: _currentFuture,
        builder: (context, currentSnapshot) {
          if (!currentSnapshot.hasData) {
            if (currentSnapshot.hasError) {
              return Center(child: Text(l10n.pageLoadError));
            }
            return const Center(child: CircularProgressIndicator());
          }
          return FutureBuilder<RuntimeStateSnapshot>(
            future: _targetFuture,
            builder: (context, targetSnapshot) {
              if (!targetSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final current = currentSnapshot.data!;
              final target = targetSnapshot.data!;
              final comparison = RuntimeStateComparison.fromSnapshots(
                current,
                target,
              );
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  const SizedBox(height: 12),
                  Text(l10n.runtimeStateCommittedEvent),
                  for (final diff in comparison.diffs)
                    AppCard(
                      margin: const EdgeInsets.only(top: 10),
                      child: Text(
                          '${RuntimeStatePresentation.fieldLabel(diff.path, l10n)}: ${RuntimeStatePresentation.valueLabel(diff.path, diff.before, l10n)} → ${RuntimeStatePresentation.valueLabel(diff.path, diff.after, l10n)}'),
                    ),
                  if (_conflict != null) ...[
                    const SizedBox(height: 16),
                    Text(l10n.pageLoadError),
                    FilledButton(
                        onPressed: () {
                          setState(() {
                            _conflict = null;
                            _reload();
                          });
                        },
                        child: Text(l10n.reloadAction)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _saving || _conflict != null
                        ? null
                        : () => _confirm(current),
                    icon: const Icon(Icons.undo_rounded),
                    label: Text(l10n.confirmAction),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class RuntimeStateComparePage extends ConsumerWidget {
  final int? historicalRevision;
  final int? fromRevision;
  final int? toRevision;

  const RuntimeStateComparePage({
    super.key,
    this.historicalRevision,
    this.fromRevision,
    this.toRevision,
  });

  const RuntimeStateComparePage.revisions({
    super.key,
    required this.fromRevision,
    required this.toRevision,
  }) : historicalRevision = null;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chat = ref.read(chatProvider);
    final adventureId = chat.currentAdventureId;
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();
    if (adventureId == null) {
      return Scaffold(body: Center(child: Text(l10n.runtimeStateNoAdventure)));
    }
    final repo = ref.read(adventureRepoProvider);
    return AppPageScaffold(
      title: l10n.runtimeStateCompare,
      maxWidth: 760,
      body: FutureBuilder<RuntimeStateComparison>(
        future: Future.wait([
          repo.getRuntimeStateAtRevision(
            adventureId: adventureId,
            branchId: chat.currentBranchId,
            revision: fromRevision ?? historicalRevision ?? 0,
          ),
          toRevision == null
              ? repo.getCurrentRuntimeState(
                  adventureId: adventureId,
                  branchId: chat.currentBranchId,
                )
              : repo.getRuntimeStateAtRevision(
                  adventureId: adventureId,
                  branchId: chat.currentBranchId,
                  revision: toRevision!,
                ),
        ]).then((snapshots) => RuntimeStateComparison.fromSnapshots(
              snapshots[0],
              snapshots[1],
            )),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            if (snapshot.hasError) {
              return Center(child: Text(l10n.runtimeStateUnableCompare));
            }
            return const Center(child: CircularProgressIndicator());
          }
          final comparison = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const SizedBox(height: 8),
              Text(l10n.runtimeStateChangedFields(comparison.changeCount)),
              for (final group in comparison.entityGroups)
                AppCard(
                  margin: const EdgeInsets.only(top: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          RuntimeStatePresentation.entityLabel(
                              group.entityType, null, l10n),
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      for (final diff in group.diffs)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                              '${RuntimeStatePresentation.fieldLabel(diff.path, l10n)}: ${RuntimeStatePresentation.valueLabel(diff.path, diff.before, l10n)} → ${RuntimeStatePresentation.valueLabel(diff.path, diff.after, l10n)}'),
                        ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class RuntimeStateCheckpointCreatePage extends ConsumerStatefulWidget {
  final int revision;

  const RuntimeStateCheckpointCreatePage({super.key, required this.revision});

  @override
  ConsumerState<RuntimeStateCheckpointCreatePage> createState() =>
      _RuntimeStateCheckpointCreatePageState();
}

class _RuntimeStateCheckpointCreatePageState
    extends ConsumerState<RuntimeStateCheckpointCreatePage> {
  final _name = TextEditingController();
  final _note = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final chat = ref.read(chatProvider);
    final adventureId = chat.currentAdventureId;
    if (adventureId == null) return;
    setState(() => _saving = true);
    try {
      await ref.read(adventureRepoProvider).createRuntimeCheckpoint(
            RuntimeStateCheckpoint(
              id: 'checkpoint-${DateTime.now().microsecondsSinceEpoch}',
              adventureId: adventureId,
              branchId: chat.currentBranchId,
              revision: widget.revision,
              name: name,
              note: _note.text,
              createdAt: DateTime.now().toUtc(),
              updatedAt: DateTime.now().toUtc(),
            ),
          );
      if (mounted) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();
    return AppPageScaffold(
      title: l10n.runtimeStateSaveSnapshot,
      maxWidth: 600,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 16),
          TextField(
              controller: _name,
              maxLength: RuntimeStateCheckpoint.maxNameLength,
              decoration:
                  InputDecoration(labelText: l10n.runtimeStateSnapshotName)),
          TextField(
              controller: _note,
              maxLength: RuntimeStateCheckpoint.maxNoteLength,
              maxLines: 4,
              decoration:
                  InputDecoration(labelText: l10n.runtimeStateSnapshotNote)),
          const SizedBox(height: 16),
          FilledButton(
              onPressed: _saving ? null : _save, child: Text(l10n.saveAction)),
        ],
      ),
    );
  }
}

class RuntimeStateCheckpointListPage extends StatelessWidget {
  final List<RuntimeStateCheckpoint> checkpoints;

  const RuntimeStateCheckpointListPage({
    super.key,
    required this.checkpoints,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();
    return AppPageScaffold(
      title: l10n.runtimeStateCheckpoint,
      maxWidth: 760,
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: checkpoints.length,
        itemBuilder: (context, index) {
          final checkpoint = checkpoints[index];
          return AppCard(
            margin: const EdgeInsets.only(bottom: 10),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => RuntimeStateCheckpointDetailPage(
                checkpoint: checkpoint,
              ),
            )),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.bookmark_outline),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(checkpoint.name,
                          style: Theme.of(context).textTheme.titleMedium),
                      if (checkpoint.note.isNotEmpty)
                        Text(checkpoint.note,
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          );
        },
      ),
    );
  }
}

class RuntimeStateCheckpointDetailPage extends ConsumerStatefulWidget {
  final RuntimeStateCheckpoint checkpoint;

  const RuntimeStateCheckpointDetailPage({
    super.key,
    required this.checkpoint,
  });

  @override
  ConsumerState<RuntimeStateCheckpointDetailPage> createState() =>
      _RuntimeStateCheckpointDetailPageState();
}

class _RuntimeStateCheckpointDetailPageState
    extends ConsumerState<RuntimeStateCheckpointDetailPage> {
  late final TextEditingController _name =
      TextEditingController(text: widget.checkpoint.name);
  late final TextEditingController _note =
      TextEditingController(text: widget.checkpoint.note);
  RuntimeStateSnapshot? _snapshot;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_load);
  }

  Future<void> _load() async {
    final chat = ref.read(chatProvider);
    final adventureId = chat.currentAdventureId;
    if (adventureId == null) return;
    final snapshot =
        await ref.read(adventureRepoProvider).getRuntimeStateAtRevision(
              adventureId: adventureId,
              branchId: chat.currentBranchId,
              revision: widget.checkpoint.revision,
            );
    if (mounted) setState(() => _snapshot = snapshot);
  }

  Future<void> _saveMetadata() async {
    final name = _name.text.trim();
    if (name.isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      final repo = ref.read(adventureRepoProvider);
      await repo.renameRuntimeCheckpoint(widget.checkpoint.id, name);
      await repo.updateRuntimeCheckpointNote(widget.checkpoint.id, _note.text);
      if (mounted) FocusScope.of(context).unfocus();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await ref.read(adventureRepoProvider).deleteRuntimeCheckpoint(
            widget.checkpoint.id,
          );
      if (mounted) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();
    final chat = ref.read(chatProvider);
    return AppPageScaffold(
      title: _name.text,
      maxWidth: 760,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 12),
          if (_snapshot == null)
            const LinearProgressIndicator()
          else
            Text('${_snapshot!.entities.length}'),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            maxLength: RuntimeStateCheckpoint.maxNameLength,
            decoration: InputDecoration(
              labelText: l10n.runtimeStateSnapshotName,
            ),
          ),
          TextField(
            controller: _note,
            maxLength: RuntimeStateCheckpoint.maxNoteLength,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: l10n.runtimeStateSnapshotNote,
            ),
          ),
          FilledButton(
            onPressed: _saving ? null : _saveMetadata,
            child: Text(l10n.saveAction),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => RuntimeStateComparePage(
                historicalRevision: widget.checkpoint.revision,
              ),
            )),
            icon: const Icon(Icons.compare_arrows_rounded),
            label: Text(l10n.runtimeStateCompareCurrent),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => RuntimeStateRevertPreviewPage(
                targetRevision: widget.checkpoint.revision,
              ),
            )),
            icon: const Icon(Icons.undo_rounded),
            label: Text(l10n.restoreRevision),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _saving ? null : _delete,
            icon: const Icon(Icons.delete_outline),
            label: Text(l10n.deleteAction),
          ),
          if (chat.currentAdventureId == null)
            Text(l10n.runtimeStateNoAdventure),
        ],
      ),
    );
  }
}

class RuntimeStateEditPage extends ConsumerStatefulWidget {
  final RuntimeEntityState entity;

  const RuntimeStateEditPage({super.key, required this.entity});

  @override
  ConsumerState<RuntimeStateEditPage> createState() =>
      _RuntimeStateEditPageState();
}

class _RuntimeStateEditPageState extends ConsumerState<RuntimeStateEditPage> {
  final _formKey = GlobalKey<FormState>();
  late final List<RuntimeStatePathDefinition> _definitions =
      RuntimeStateSchemaRegistry.definitions
          .where((definition) =>
              definition.entities.contains(widget.entity.entityType))
          .toList(growable: false);
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, Object?> _values = {};
  final Set<String> _resetRequested = {};
  final Set<String> _touched = {};
  int? _baseRevision;
  bool _loading = true;
  bool _saving = false;
  String? _conflictMessage;

  bool get _hasChanges => _definitions.any((definition) {
        final path = definition.id;
        if (_resetRequested.contains(path)) return true;
        final original = widget.entity.overlay[path];
        if (original == null && !_touched.contains(path)) return false;
        final value = _draftValue(definition);
        return value != original;
      });

  @override
  void initState() {
    super.initState();
    for (final definition in _definitions) {
      final value = widget.entity.overlay[definition.id];
      _values[definition.id] = value;
      if (definition.valueKind == RuntimeStateValueKind.text ||
          definition.valueKind == RuntimeStateValueKind.integer ||
          definition.valueKind == RuntimeStateValueKind.number) {
        _controllers[definition.id] =
            TextEditingController(text: value?.toString() ?? '');
      }
    }
    _loadRevision();
  }

  Future<void> _loadRevision() async {
    final chat = ref.read(chatProvider);
    final adventureId = chat.currentAdventureId;
    if (adventureId == null) return;
    final repo = ref.read(adventureRepoProvider);
    final current = await repo.getCurrentRuntimeState(
      adventureId: adventureId,
      branchId: chat.currentBranchId,
      entityType: widget.entity.entityType,
      entityId: widget.entity.entityId,
    );
    final head = await repo.getRuntimeHead(adventureId, chat.currentBranchId);
    if (!mounted) return;
    setState(() {
      _baseRevision = head.revision;
      _conflictMessage = null;
      _loading = false;
      final entity = current.entities.values.firstOrNull;
      if (entity == null) return;
      for (final definition in _definitions) {
        final value = entity.overlay[definition.id];
        _values[definition.id] = value;
        _resetRequested.remove(definition.id);
        _touched.remove(definition.id);
        _controllers[definition.id]?.text = value?.toString() ?? '';
      }
    });
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();
    if (!_formKey.currentState!.validate()) return;
    final chat = ref.read(chatProvider);
    final adventureId = chat.currentAdventureId;
    if (adventureId == null) return;
    setState(() => _saving = true);
    try {
      final repo = ref.read(adventureRepoProvider);
      final changes = <RuntimeStateChangeProposal>[];
      for (final definition in _definitions) {
        final path = definition.id;
        final original = widget.entity.overlay[path];
        final operation = _resetRequested.contains(path)
            ? RuntimeChangeOperation.remove
            : RuntimeChangeOperation.set;
        final value = operation == RuntimeChangeOperation.remove
            ? null
            : _draftValue(definition);
        if (original == null && !_touched.contains(path)) continue;
        if (operation == RuntimeChangeOperation.remove || value != original) {
          changes.add(RuntimeStateChangeProposal(
            entityType: widget.entity.entityType,
            entityId: widget.entity.entityId,
            changeKind: RuntimeChangeKind.primary,
            operation: operation,
            path: path,
            value: value,
            reason: 'User edit',
          ));
        }
      }
      if (changes.isNotEmpty) {
        final expectedRevision = _baseRevision;
        if (expectedRevision == null) return;
        await repo.commitRuntimeMutation(RuntimeStateMutation(
          requestId: 'user-edit-${DateTime.now().microsecondsSinceEpoch}',
          adventureId: adventureId,
          branchId: chat.currentBranchId,
          draft: RuntimeStateCommitDraft(
            expectedRevision: expectedRevision,
            changes: changes,
            summary: 'User edited ${widget.entity.entityId}',
            source: RuntimeEventSource.userEdit,
            causeType: 'user_edit',
          ),
        ));
      }
      if (mounted) Navigator.of(context).pop(true);
    } on RuntimeHeadConflict {
      if (mounted) {
        setState(() => _conflictMessage = _messageText(l10n, 'conflict'));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Object? _draftValue(RuntimeStatePathDefinition definition) {
    if (_controllers[definition.id] case final controller?) {
      final text = controller.text.trim();
      return switch (definition.valueKind) {
        RuntimeStateValueKind.integer => int.tryParse(text),
        RuntimeStateValueKind.number => num.tryParse(text),
        _ => text,
      };
    }
    return _values[definition.id];
  }

  String _label(AppLocalizations l10n, String path) => switch (path) {
        'hp' => _labelText(l10n, 'hp'),
        'mp' => _labelText(l10n, 'mp'),
        'energy' => _labelText(l10n, 'energy'),
        'experience' => _labelText(l10n, 'experience'),
        'level' => _labelText(l10n, 'level'),
        'base_atk' => _labelText(l10n, 'base_atk'),
        'base_def' => _labelText(l10n, 'base_def'),
        'base_speed' => _labelText(l10n, 'base_speed'),
        'affinity' => _labelText(l10n, 'affinity'),
        'life_status' => _labelText(l10n, 'life_status'),
        'lifecycle_status' => _labelText(l10n, 'lifecycle_status'),
        'global_flag' => _labelText(l10n, 'global_flag'),
        'faction_id' => _labelText(l10n, 'faction_id'),
        'former_faction_id' => _labelText(l10n, 'former_faction_id'),
        'controller_id' => _labelText(l10n, 'controller_id'),
        'relationship' => _labelText(l10n, 'relationship'),
        'goal' => _labelText(l10n, 'goal'),
        'status' => _labelText(l10n, 'status'),
        'control' => _labelText(l10n, 'control'),
        'environment' => _labelText(l10n, 'environment'),
        'condition' => _labelText(l10n, 'condition'),
        'influence' => _labelText(l10n, 'influence'),
        'time' => _labelText(l10n, 'time'),
        _ => l10n.runtimeStateFieldUnknown,
      };

  String? _validate(RuntimeStatePathDefinition definition, String? raw,
      AppLocalizations l10n) {
    if (_resetRequested.contains(definition.id)) return null;
    final value = _draftValue(definition);
    if (value == null) {
      return definition.valueKind == RuntimeStateValueKind.integer
          ? _messageText(l10n, 'integer')
          : definition.valueKind == RuntimeStateValueKind.number
              ? _messageText(l10n, 'number')
              : _messageText(l10n, 'required');
    }
    if (definition.valueKind == RuntimeStateValueKind.text &&
        (raw?.length ?? 0) > 1000) {
      return _messageText(l10n, 'large');
    }
    if (value is num && !value.isFinite) {
      return _messageText(l10n, 'number');
    }
    if (value is num &&
        definition.minimum != null &&
        value < definition.minimum!) {
      return _messageText(l10n, 'small');
    }
    if (value is num &&
        definition.maximum != null &&
        value > definition.maximum!) {
      return _messageText(l10n, 'large');
    }
    if (!definition.accepts(widget.entity.entityType, value)) {
      return _messageText(l10n, 'required');
    }
    return null;
  }

  Widget _field(RuntimeStatePathDefinition definition, AppLocalizations l10n) {
    final path = definition.id;
    final label = _label(l10n, path);
    final overridden = widget.entity.overlay.containsKey(path);
    final reset = _resetRequested.contains(path);
    final resetButton = overridden
        ? TextButton(
            onPressed: () => setState(() {
              if (reset) {
                _resetRequested.remove(path);
                _controllers[path]?.text =
                    widget.entity.overlay[path]?.toString() ?? '';
                _values[path] = widget.entity.overlay[path];
              } else {
                _resetRequested.add(path);
              }
            }),
            child: Text(reset
                ? _messageText(l10n, 'keep')
                : _messageText(l10n, 'reset')),
          )
        : null;
    String? validator(String? value) => _validate(definition, value, l10n);
    switch (definition.valueKind) {
      case RuntimeStateValueKind.boolean:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(label),
            value: (_values[path] as bool?) ?? false,
            onChanged: reset
                ? null
                : (value) => setState(() {
                      _touched.add(path);
                      _values[path] = value;
                    }),
          ),
          if (resetButton != null) resetButton,
        ]);
      case RuntimeStateValueKind.enumValue:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AppSelect<String>(
            value: _values[path] as String?,
            label: label,
            items: definition.enumValues
                .map((value) =>
                    AppSelectItem(value: value, label: _enumLabel(l10n, value)))
                .toList(),
            onChanged: reset
                ? null
                : (value) => setState(() {
                      _touched.add(path);
                      _values[path] = value;
                    }),
          ),
          if (resetButton != null) resetButton,
        ]);
      case RuntimeStateValueKind.integer:
      case RuntimeStateValueKind.number:
      case RuntimeStateValueKind.text:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AppTextField(
            controller: _controllers[path],
            label: label,
            enabled: !reset,
            maxLines:
                definition.valueKind == RuntimeStateValueKind.text ? 3 : 1,
            keyboardType: definition.valueKind == RuntimeStateValueKind.text
                ? TextInputType.text
                : const TextInputType.numberWithOptions(
                    decimal: true, signed: true),
            validator: validator,
            onChanged: (_) => setState(() => _touched.add(path)),
          ),
          if (resetButton != null) resetButton,
        ]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();
    if (_loading) return const Center(child: CircularProgressIndicator());
    return AppPageScaffold(
      title: l10n.editAction,
      maxWidth: 760,
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
                RuntimeStatePresentation.entityLabel(
                    widget.entity.entityType, null, l10n),
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            if (_conflictMessage != null) ...[
              Text(_conflictMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
              TextButton(
                  onPressed: _loadRevision, child: Text(l10n.reloadAction)),
            ],
            for (final definition in _definitions)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _field(definition, l10n),
              ),
            FilledButton.icon(
              onPressed: _saving || !_hasChanges || _conflictMessage != null
                  ? null
                  : _save,
              icon: const Icon(Icons.save_outlined),
              label: Text(l10n.saveAction),
            ),
          ],
        ),
      ),
    );
  }

  String _labelText(AppLocalizations l10n, String path) {
    return switch (path) {
      'hp' => l10n.runtimeStateFieldHp,
      'mp' => l10n.runtimeStateFieldMp,
      'energy' => l10n.runtimeStateFieldEnergy,
      'experience' => l10n.runtimeStateFieldExperience,
      'level' => l10n.runtimeStateFieldLevel,
      'base_atk' => l10n.runtimeStateFieldBaseAtk,
      'base_def' => l10n.runtimeStateFieldBaseDef,
      'base_speed' => l10n.runtimeStateFieldBaseSpeed,
      'affinity' => l10n.runtimeStateFieldAffinity,
      'life_status' => l10n.runtimeStateFieldLifeStatus,
      'lifecycle_status' => l10n.runtimeStateFieldLifecycleStatus,
      'global_flag' => l10n.runtimeStateFieldGlobalFlag,
      'faction_id' => l10n.runtimeStateFieldFactionId,
      'former_faction_id' => l10n.runtimeStateFieldFormerFactionId,
      'controller_id' => l10n.runtimeStateFieldControllerId,
      'relationship' => l10n.runtimeStateFieldRelationship,
      'goal' => l10n.runtimeStateFieldGoal,
      'status' => l10n.runtimeStateFieldStatus,
      'control' => l10n.runtimeStateFieldControl,
      'environment' => l10n.runtimeStateFieldEnvironment,
      'condition' => l10n.runtimeStateFieldCondition,
      'influence' => l10n.runtimeStateFieldInfluence,
      'time' => l10n.runtimeStateFieldTime,
      _ => l10n.runtimeStateFieldUnknown,
    };
  }

  String _messageText(AppLocalizations l10n, String type) {
    return switch (type) {
      'reset' => l10n.runtimeStateResetToBaseline,
      'keep' => l10n.runtimeStateKeepOverride,
      'conflict' => l10n.runtimeStateEditConflict,
      'integer' => l10n.runtimeStateIntegerRequired,
      'number' => l10n.runtimeStateNumberRequired,
      'small' => l10n.runtimeStateValueTooSmall,
      'large' => l10n.runtimeStateValueTooLarge,
      _ => l10n.runtimeStateValueRequired,
    };
  }

  String _enumLabel(AppLocalizations l10n, String value) {
    return switch (value) {
      'alive' => l10n.runtimeStateAlive,
      'dead' => l10n.runtimeStateDead,
      'active' => l10n.runtimeStateActive,
      'inactive' => l10n.runtimeStateInactive,
      'destroyed' => l10n.runtimeStateDestroyed,
      _ => value,
    };
  }
}
