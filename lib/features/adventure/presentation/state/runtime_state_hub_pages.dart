part of 'runtime_state_hub_page.dart';

class TurnStateDetailPage extends ConsumerWidget {
  final TurnStateChangeGroup turn;
  final bool embedded;

  const TurnStateDetailPage(
      {super.key, required this.turn, this.embedded = false});

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

    final content = ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
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
                          turn.occurredAt.toLocal().toString().split('.').first,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                            ),
                            child:
                                Text(label, style: theme.textTheme.labelSmall),
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
            final safeEntries = <({Message message, String text})>[];
            for (final message in messages) {
              final text =
                  RuntimeStatePresentation.safeDialogueMessageText(message);
              if (text != null && text.isNotEmpty) {
                safeEntries.add((message: message, text: text));
              }
            }
            if (safeEntries.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 12),
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
                  for (final entry in safeEntries)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: entry.message.isUser
                            ? theme.colorScheme.surfaceContainerHigh
                            : theme.colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              AppSvgIcon(
                                entry.message.isUser
                                    ? 'characters'
                                    : 'generation',
                                size: 14,
                                color: entry.message.isUser
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.secondary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                entry.message.isUser
                                    ? (config?.protagonistCharacter
                                                ?.characterName.isNotEmpty ==
                                            true
                                        ? config!
                                            .protagonistCharacter!.characterName
                                        : l10n.protagonistShortTag)
                                    : l10n.runtimeStateCauseDialogue,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            entry.text,
                            maxLines: 8,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            );
          },
        ),
        if (turn.changes.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
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
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      AppSvgIcon('characters',
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
                                  color:
                                      theme.colorScheme.surfaceContainerHighest,
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
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      AppSvgIcon('world',
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
                                  color:
                                      theme.colorScheme.surfaceContainerHighest,
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
    );
    return embedded
        ? content
        : AppPageScaffold(
            title: l10n.runtimeStateTurnLabel(turn.turnNumber),
            maxWidth: 780,
            body: content);
  }
}

class _EntityRow extends StatelessWidget {
  final RuntimeEntityState entity;
  final AppLocalizations l10n;
  final VoidCallback onEdit;
  final VoidCallback onHistory;
  final String? displayName;
  final Map<String, String> customAttributeLabels;
  final VoidCallback? onOpen;
  final bool isInScene;
  final bool showValues;
  final bool selected;

  const _EntityRow({
    super.key,
    required this.entity,
    required this.l10n,
    required this.onEdit,
    required this.onHistory,
    this.displayName,
    this.customAttributeLabels = const {},
    this.onOpen,
    this.isInScene = false,
    this.showValues = true,
    this.selected = false,
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

    final label = RuntimeStatePresentation.entityLabel(
        entity.entityType, displayName, l10n);
    final content = Container(
        decoration: BoxDecoration(
            color: selected ? theme.colorScheme.surfaceContainerHigh : null,
            border: Border(
                bottom: BorderSide(color: theme.colorScheme.outlineVariant))),
        child: InkWell(
            onTap: onOpen,
            child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [
                        Expanded(
                            child: Tooltip(
                                message: label,
                                child: Text(label,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.titleSmall))),
                        IconButton(
                            onPressed: onHistory,
                            icon: const AppSvgIcon('history'),
                            tooltip: l10n.worldviewModuleTimeline),
                        IconButton(
                            onPressed: onEdit,
                            icon: const AppSvgIcon('edit'),
                            tooltip: l10n.editAction),
                      ]),
                      Wrap(spacing: 8, runSpacing: 4, children: [
                        if (isInScene)
                          Text(l10n.runtimeStateInScene,
                              style: theme.textTheme.labelMedium),
                        Text(
                            RuntimeStatePresentation.valueLabel(
                                'lifecycle_status',
                                entity.lifecycleStatus,
                                l10n),
                            style: theme.textTheme.labelMedium),
                      ]),
                      if (showValues && values.isEmpty)
                        Text(l10n.runtimeStateNoChanges)
                      else if (showValues)
                        for (final entry in values)
                          Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                        child: Text(
                                            RuntimeStatePresentation.fieldLabel(
                                                entry.key, l10n))),
                                    Flexible(
                                        child: Text(
                                            RuntimeStatePresentation.valueLabel(
                                                entry.key, entry.value, l10n),
                                            textAlign: TextAlign.end)),
                                  ])),
                    ]))));
    return Semantics(selected: selected, child: content);
  }
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
            const AppSvgIcon('forward'),
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
                  icon: const AppSvgIcon('undo'),
                  label: Text(l10n.restoreRevision),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => RuntimeStateCheckpointCreatePage(
                      revision: entry.revision,
                    ),
                  )),
                  icon: const AppSvgIcon('add'),
                  label: Text(l10n.runtimeStateSaveSnapshot),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => RuntimeStateComparePage(
                      historicalRevision: entry.revision,
                    ),
                  )),
                  icon: const AppSvgIcon('compare'),
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
  final bool embedded;
  const RuntimeEntityStatePage(
      {super.key,
      required this.entity,
      this.displayName,
      this.embedded = false});
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();
    final values = entity.overlay.entries
        .where((entry) =>
            RuntimeStatePresentationRegistry.find(entity.entityType, entry.key)
                ?.visibility !=
            RuntimeStateFieldVisibility.hidden)
        .toList();
    final label = RuntimeStatePresentation.entityLabel(
        entity.entityType, displayName, l10n);
    final content =
        ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
      WorkbenchSection(
          title: label,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (values.isEmpty)
              Text(l10n.runtimeStateNoChanges)
            else
              for (final value in values)
                Padding(
                    padding: const EdgeInsets.only(bottom: 12),
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
                                  textAlign: TextAlign.end)),
                        ])),
          ])),
      Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => RuntimeEntityHistoryPage(entity: entity))),
              child: Text(l10n.worldviewModuleTimeline))),
    ]);
    return embedded
        ? content
        : AppPageScaffold(title: label, maxWidth: 760, body: content);
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
