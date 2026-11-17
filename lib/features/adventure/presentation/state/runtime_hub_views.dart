part of 'runtime_state_hub_page.dart';

/// Read-only Dashboard view of the runtime workbench.
///
/// Presentation only: the hub owns loading, pagination and the current view;
/// this widget receives already-loaded data and navigation callbacks.
class RuntimeHubDashboardView extends StatelessWidget {
  const RuntimeHubDashboardView({
    super.key,
    required this.l10n,
    required this.current,
    required this.sceneState,
    required this.turns,
    required this.characterNames,
    required this.adventureConfig,
    required this.runtimeEntities,
    required this.onOpenCharacters,
    required this.onOpenWorld,
    required this.onOpenTracked,
    required this.onOpenTurn,
    required this.onManageTracked,
  });

  final AppLocalizations l10n;
  final RuntimeStateSnapshot? current;
  final SceneState? sceneState;
  final List<TurnStateChangeGroup> turns;
  final Map<String, String> characterNames;
  final AdventureConfig? adventureConfig;
  final List<RuntimeEntityState> runtimeEntities;
  final VoidCallback onOpenCharacters;
  final VoidCallback onOpenWorld;
  final VoidCallback onOpenTracked;
  final ValueChanged<TurnStateChangeGroup?> onOpenTurn;
  final VoidCallback onManageTracked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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

    final presentIds = sceneState?.presentCharacterIds ?? const [];
    final presentNames = presentIds
        .map((id) => RuntimeStatePresentation.entityLabel(
            RuntimeEntityType.character, characterNames[id], l10n))
        .toList();

    final recentChangedTurn =
        turns.where((t) => t.hasChanges).firstOrNull ?? turns.firstOrNull;

    return ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          if (sceneState != null)
            WorkbenchSection(
                title: l10n.runtimeStateCurrent,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(sceneState!.location,
                          style: theme.textTheme.titleSmall),
                      if (sceneState!.time.isNotEmpty) Text(sceneState!.time),
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
                  onPressed: onOpenCharacters,
                  child: Text(l10n.characterManagementViewStatus)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final entity in characterEntities.take(5))
                      Text(RuntimeStatePresentation.entityLabel(
                          entity.entityType,
                          characterNames[entity.entityId],
                          l10n)),
                    if (characterEntities.isEmpty)
                      Text(l10n.runtimeStateNoChanges),
                  ])),
          const SizedBox(height: 24),
          WorkbenchSection(
              title: l10n.worldviewModuleState,
              action: TextButton(
                  onPressed: onOpenWorld,
                  child: Text(l10n.characterManagementViewStatus)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final entity in worldEntities.take(5))
                      Text(RuntimeStatePresentation.entityLabel(
                          entity.entityType,
                          characterNames[entity.entityId],
                          l10n)),
                    if (worldEntities.isEmpty) Text(l10n.runtimeStateNoChanges),
                  ])),
          const SizedBox(height: 24),
          WorkbenchSection(
              title: l10n.trackedStateStatusTitle,
              action: TextButton(
                  onPressed: onOpenTracked,
                  child: Text(l10n.trackedStateViewAllAction)),
              child: TrackedStateOverviewPanel(
                config: adventureConfig,
                entities: runtimeEntities,
                entityNames: characterNames,
                compact: true,
                onManage: onManageTracked,
              )),
          const SizedBox(height: 24),
          WorkbenchSection(
              title: l10n.runtimeStateRecentChange,
              action: TextButton(
                  onPressed: () => onOpenTurn(recentChangedTurn),
                  child: Text(l10n.runtimeStateHistoricalChange)),
              child: Text(recentChangedTurn == null
                  ? l10n.runtimeStateNoChanges
                  : RuntimeStatePresentation.turnSummary(
                      recentChangedTurn, l10n,
                      entityNames: characterNames))),
        ]);
  }
}

/// Character / world entity list of the runtime workbench.
///
/// Resolves baseline plus HEAD through the shared read-only resolver before
/// presenting values; the view never mutates AdventureConfig.
class RuntimeHubEntitiesView extends StatelessWidget {
  const RuntimeHubEntitiesView({
    super.key,
    required this.l10n,
    required this.types,
    required this.title,
    required this.current,
    required this.sceneState,
    required this.adventureConfig,
    required this.characterNames,
    required this.runtimeEntities,
    required this.openCharacters,
    required this.onManageCharacters,
    required this.useWideNavigation,
    required this.selectedEntityKey,
    required this.onSelectEntity,
    required this.onManageTracked,
  });

  final AppLocalizations l10n;
  final Set<RuntimeEntityType> types;
  final String title;
  final RuntimeStateSnapshot? current;
  final SceneState? sceneState;
  final AdventureConfig? adventureConfig;
  final Map<String, String> characterNames;
  final List<RuntimeEntityState> runtimeEntities;
  final bool openCharacters;
  final VoidCallback? onManageCharacters;
  final bool useWideNavigation;
  final (RuntimeEntityType, String)? selectedEntityKey;
  final ValueChanged<(RuntimeEntityType, String)> onSelectEntity;
  final VoidCallback onManageTracked;

  @override
  Widget build(BuildContext context) {
    final config = adventureConfig;
    final names = characterNames;
    final entities = (current?.entities.values ?? const <RuntimeEntityState>[])
        .where((entity) => types.contains(entity.entityType))
        .toList();
    final customAttributeLabels =
        RuntimeStatePresentation.customAttributeLabels(
      config?.allTrackedCustomAttributes ?? const [],
    );

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
    if (config != null && current != null) {
      final effective = RuntimeEffectiveStateView.fromSnapshot(
        baseline: config,
        snapshot: current!,
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
        sceneState?.presentCharacterIds.toSet() ?? const <String>{};
    return LayoutBuilder(builder: (context, constraints) {
      // Two property panes need 720 logical pixels; otherwise use a detail route.
      final inline = useWideNavigation && constraints.maxWidth >= 720;
      final selected = entities
              .where((entity) =>
                  (entity.entityType, entity.entityId) == selectedEntityKey)
              .firstOrNull ??
          entities.first;
      final list = ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (types.contains(RuntimeEntityType.character) && !openCharacters)
            Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                    onPressed: onManageCharacters ??
                        () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) =>
                                const SceneCharacterManagementPage())),
                    child: Text(l10n.characterManagementManage))),
          if (sceneState != null)
            WorkbenchSection(
              title: l10n.runtimeStateCurrent,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(sceneState!.location),
                  if (sceneState!.time.trim().isNotEmpty)
                    Text(sceneState!.time),
                  if (sceneState!.presentCharacterIds.isNotEmpty)
                    Text(sceneState!.presentCharacterIds
                        .map((id) => names[id]?.trim().isNotEmpty == true
                            ? names[id]!
                            : l10n.characterStatusTitle)
                        .join(' · ')),
                ],
              ),
            ),
          if (types.contains(RuntimeEntityType.character))
            _buildInitialBaseline(context, l10n),
          if (types.contains(RuntimeEntityType.world) &&
              AdventureTrackedStateRegistry.fromConfig(config)
                  .forEntity(
                      RuntimeEntityType.world, AdventureRuntimeEntityIds.world)
                  .isNotEmpty)
            WorkbenchSection(
              title: l10n.trackedStateStatusTitle,
              child: TrackedStateOverviewPanel(
                config: config,
                entities: runtimeEntities,
                entityNames: names,
                category: TrackedStateCategory.world,
                onManage: onManageTracked,
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
                  onSelectEntity((entity.entityType, entity.entityId));
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

  Widget _buildInitialBaseline(BuildContext context, AppLocalizations l10n) {
    final config = adventureConfig;
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
}

/// Semantic timeline of runtime revisions, newest first.
class RuntimeHubTimelineView extends StatelessWidget {
  const RuntimeHubTimelineView({
    super.key,
    required this.l10n,
    required this.timeline,
    required this.checkpoints,
    required this.headRevision,
    required this.filterType,
    required this.characterNames,
    required this.customAttributeLabels,
    required this.isLoadingMore,
    required this.onFilterChanged,
    required this.onLoadMore,
  });

  final AppLocalizations l10n;
  final List<RuntimeTimelineEntry> timeline;
  final List<RuntimeStateCheckpoint> checkpoints;
  final int? headRevision;
  final RuntimeEntityType? filterType;
  final Map<String, String> characterNames;
  final Map<String, String> customAttributeLabels;
  final bool isLoadingMore;
  final ValueChanged<RuntimeEntityType?> onFilterChanged;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    if (timeline.isEmpty) {
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
                  selected: filterType == null,
                  onSelected: (_) {
                    if (filterType != null) onFilterChanged(null);
                  },
                ),
                ChoiceChip(
                  label: Text(l10n.characterStatusTitle),
                  selected: filterType == RuntimeEntityType.character,
                  onSelected: (_) {
                    if (filterType != RuntimeEntityType.character) {
                      onFilterChanged(RuntimeEntityType.character);
                    }
                  },
                ),
                ChoiceChip(
                  label: Text(l10n.worldviewModuleState),
                  selected: filterType == RuntimeEntityType.world,
                  onSelected: (_) {
                    if (filterType != RuntimeEntityType.world) {
                      onFilterChanged(RuntimeEntityType.world);
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
              if (notification.metrics.extentAfter < 240 && !isLoadingMore) {
                onLoadMore();
              }
              return false;
            },
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: timeline.length + (isLoadingMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == timeline.length) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final entry = timeline[index];
                final checkpoint = checkpoints
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
                    entityNames: characterNames,
                    isHead: entry.revision == headRevision,
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// Turn-level change history with the currently inspected turn highlighted.
class RuntimeHubTurnHistoryView extends StatelessWidget {
  const RuntimeHubTurnHistoryView({
    super.key,
    required this.l10n,
    required this.turns,
    required this.selectedTurn,
    required this.characterNames,
    required this.isLoadingMore,
    required this.onLoadMore,
    required this.onOpenTurn,
  });

  final AppLocalizations l10n;
  final List<TurnStateChangeGroup> turns;
  final TurnStateChangeGroup? selectedTurn;
  final Map<String, String> characterNames;
  final bool isLoadingMore;
  final VoidCallback onLoadMore;
  final ValueChanged<TurnStateChangeGroup> onOpenTurn;

  @override
  Widget build(BuildContext context) {
    if (turns.isEmpty) {
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
    final names = characterNames;
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.extentAfter < 240 && !isLoadingMore) {
          onLoadMore();
        }
        return false;
      },
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: turns.length + (isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == turns.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final turn = turns[index];
          final affected = RuntimeStatePresentation.turnAffectedEntityLabels(
            turn,
            l10n,
            entityNames: names,
          );
          return Material(
            color: (selectedTurn ?? turns.firstOrNull)?.turnId == turn.turnId
                ? Theme.of(context).colorScheme.surfaceContainerHigh
                : Colors.transparent,
            child: InkWell(
                key: ValueKey('runtime-turn-${turn.turnId}'),
                onTap: () => onOpenTurn(turn),
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
