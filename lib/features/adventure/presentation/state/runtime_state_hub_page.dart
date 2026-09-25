import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/widgets/app_card.dart';
import '../../../../../core/widgets/app_page_scaffold.dart';
import '../../../../../core/widgets/app_select.dart';
import '../../../../../core/widgets/app_text_field.dart';
import '../../../../../l10n/generated/app_localizations.dart';
import '../../../../../l10n/generated/app_localizations_zh.dart';
import '../../../../../models/adventure_runtime_state.dart';
import '../../../../../models/typed_runtime_state.dart';
import '../../../../../models/runtime_state_history.dart';
import '../../../../../providers/riverpod_providers.dart';

enum _RuntimeStateView { characters, world, timeline }

class RuntimeStateHubPage extends ConsumerStatefulWidget {
  const RuntimeStateHubPage({super.key});

  @override
  ConsumerState<RuntimeStateHubPage> createState() =>
      _RuntimeStateHubPageState();
}

class _RuntimeStateHubPageState extends ConsumerState<RuntimeStateHubPage> {
  _RuntimeStateView _view = _RuntimeStateView.characters;
  RuntimeStateSnapshot? _current;
  List<RuntimeTimelineEntry> _timeline = const [];
  List<RuntimeStateCheckpoint> _checkpoints = const [];
  bool _loading = true;
  bool _loadingMore = false;
  Object? _error;
  int? _beforeRevision;
  RuntimeEntityType? _timelineEntityType;

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
      final page = await repository.getRuntimeTimeline(
        adventureId: adventureId,
        branchId: branchId,
        beforeRevision: append ? _beforeRevision : null,
        entityType: _timelineEntityType,
        limit: 30,
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
        _checkpoints = checkpoints;
        _timeline = append ? [..._timeline, ...page] : page;
        _beforeRevision = page.isEmpty ? _beforeRevision : page.last.revision;
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
    return AppPageScaffold(
      title: l10n.characterStatusTitle,
      maxWidth: 980,
      actions: [
        IconButton(
          onPressed: _current == null
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
          onPressed: _checkpoints.isEmpty
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
          onPressed: _loading ? null : () => _load(),
          icon: const Icon(Icons.refresh_rounded),
          tooltip: l10n.reloadAction,
        ),
      ],
      body: _buildBody(context, l10n),
    );
  }

  Widget _buildBody(BuildContext context, AppLocalizations l10n) {
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
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: SegmentedButton<_RuntimeStateView>(
            segments: [
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
        ),
        Expanded(child: _buildView(context, l10n)),
      ],
    );
  }

  Widget _buildView(BuildContext context, AppLocalizations l10n) {
    return switch (_view) {
      _RuntimeStateView.characters => _buildEntities(
          context,
          l10n,
          {RuntimeEntityType.character, RuntimeEntityType.npc},
          l10n.characterStatusTitle,
        ),
      _RuntimeStateView.world => _buildEntities(
          context,
          l10n,
          {
            RuntimeEntityType.world,
            RuntimeEntityType.location,
            RuntimeEntityType.faction,
            RuntimeEntityType.relationship,
          },
          l10n.worldviewModuleState,
        ),
      _RuntimeStateView.timeline => _buildTimeline(context, l10n),
    };
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
    if (entities.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('${l10n.emptyRecycleBin}: $title'),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        if (types.contains(RuntimeEntityType.character))
          _buildInitialBaseline(l10n),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            l10n.runtimeStateCurrent,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        ...entities.map(
          (entity) => _EntityCard(
            entity: entity,
            l10n: l10n,
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
          Text(l10n.runtimeStateInitial,
              style: Theme.of(context).textTheme.titleMedium),
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
}

class _EntityCard extends StatelessWidget {
  final RuntimeEntityState entity;
  final AppLocalizations l10n;
  final VoidCallback onEdit;
  final VoidCallback onHistory;

  const _EntityCard({
    required this.entity,
    required this.l10n,
    required this.onEdit,
    required this.onHistory,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final values = entity.overlay.entries.toList();
    return AppCard(
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_iconFor(entity.entityType),
                  color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  entity.entityId,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Text(entity.lifecycleStatus),
              IconButton(
                onPressed: onHistory,
                icon: const Icon(Icons.history_rounded),
                tooltip: l10n.worldviewModuleTimeline,
              ),
              IconButton(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: l10n.editAction),
            ],
          ),
          if (values.isEmpty)
            // The child is localized at runtime, so this container cannot be const.
            // ignore: prefer_const_constructors
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
                    Expanded(child: Text(entry.key)),
                    Flexible(
                      child: Text(
                        _displayValue(entry.value),
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

  String _displayValue(Object? value) {
    if (value == null) return '—';
    if (value is Map || value is List) return l10n.runtimeStateStructuredValue;
    return value.toString();
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
  final bool isHead;

  const _TimelineSummary({
    required this.entry,
    required this.l10n,
    this.checkpoint,
    this.isHead = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final changes = entry.diffs.take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(l10n.runtimeStateRevision(entry.revision),
                style: theme.textTheme.labelLarge),
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
            const SizedBox(width: 8),
            Expanded(child: Text(_formatDate(entry.occurredAt))),
            if (entry.isLegacy) Chip(label: Text(l10n.runtimeStateLegacy)),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
        if (entry.summary.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(entry.summary, maxLines: 3, overflow: TextOverflow.ellipsis),
        ],
        for (final diff in changes)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
                '${diff.entityId} · ${diff.path}: ${_value(diff.before)} → ${_value(diff.after)}'),
          ),
      ],
    );
  }

  static String _formatDate(DateTime value) =>
      value.toLocal().toString().split('.').first;
  static String _value(Object? value) => value?.toString() ?? '—';
}

class RuntimeTimelineDetailPage extends ConsumerWidget {
  final RuntimeTimelineEntry entry;

  const RuntimeTimelineDetailPage({super.key, required this.entry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();
    return AppPageScaffold(
      title: l10n.runtimeStateRevision(entry.revision),
      maxWidth: 760,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_TimelineSummary._formatDate(entry.occurredAt)),
                if (entry.summary.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(entry.summary),
                ],
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
                  Text('${diff.entityId} · ${diff.path}',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Text(
                      '${_TimelineSummary._value(diff.before)} → ${_TimelineSummary._value(diff.after)}'),
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
  late Future<List<RuntimeTimelineEntry>> _future;

  @override
  void initState() {
    super.initState();
    final chat = ref.read(chatProvider);
    final adventureId = chat.currentAdventureId;
    _future = adventureId == null
        ? Future.error(StateError('No active adventure'))
        : ref.read(adventureRepoProvider).getRuntimeTimeline(
              adventureId: adventureId,
              branchId: chat.currentBranchId,
              entityId: widget.entity.entityId,
              limit: 50,
            );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();
    return AppPageScaffold(
      title: '${widget.entity.entityId} · ${l10n.worldviewModuleTimeline}',
      maxWidth: 760,
      body: FutureBuilder<List<RuntimeTimelineEntry>>(
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
                  builder: (_) => RuntimeTimelineDetailPage(entry: entry),
                )),
                child: _TimelineSummary(entry: entry, l10n: l10n),
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
                  Text(l10n.runtimeStateRevision(widget.targetRevision)),
                  Text(l10n.runtimeStateRevision(current.revision)),
                  const SizedBox(height: 12),
                  Text(l10n.runtimeStateCommittedEvent),
                  for (final diff in comparison.diffs)
                    AppCard(
                      margin: const EdgeInsets.only(top: 10),
                      child: Text(
                          '${diff.entityId} · ${diff.path}: ${_TimelineSummary._value(diff.before)} → ${_TimelineSummary._value(diff.after)}'),
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
              Text(
                  '${l10n.runtimeStateRevision(comparison.fromRevision)} → ${l10n.runtimeStateRevision(comparison.toRevision)}'),
              const SizedBox(height: 8),
              Text(l10n.runtimeStateChangedFields(comparison.changeCount)),
              for (final group in comparison.entityGroups)
                AppCard(
                  margin: const EdgeInsets.only(top: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${group.entityType.name}: ${group.entityId}',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      for (final diff in group.diffs)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                              '${diff.path}: ${_TimelineSummary._value(diff.before)} → ${_TimelineSummary._value(diff.after)}'),
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
          Text(l10n.runtimeStateRevision(widget.revision)),
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
                      Text(l10n.runtimeStateRevision(checkpoint.revision)),
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
          Text(l10n.runtimeStateRevision(widget.checkpoint.revision)),
          const SizedBox(height: 12),
          if (_snapshot == null)
            const LinearProgressIndicator()
          else
            Text('${_snapshot!.entities.length} entities'),
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
        _ => path,
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
            Text(widget.entity.entityId,
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
      _ => path,
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
    final zh = l10n.localeName.startsWith('zh');
    return switch (value) {
      'alive' => zh ? '存活' : 'Alive',
      'dead' => zh ? '死亡' : 'Dead',
      'active' => zh ? '活动' : 'Active',
      'inactive' => zh ? '非活动' : 'Inactive',
      'destroyed' => zh ? '已摧毁' : 'Destroyed',
      _ => value,
    };
  }
}
