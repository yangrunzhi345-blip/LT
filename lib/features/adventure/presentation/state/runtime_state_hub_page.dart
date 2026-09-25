import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/widgets/app_card.dart';
import '../../../../../core/widgets/app_page_scaffold.dart';
import '../../../../../l10n/generated/app_localizations.dart';
import '../../../../../l10n/generated/app_localizations_zh.dart';
import '../../../../../models/adventure_runtime_state.dart';
import '../../../../../models/typed_runtime_state.dart';
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
  bool _loading = true;
  bool _loadingMore = false;
  Object? _error;
  int? _beforeRevision;

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
        limit: 30,
      );
      if (!mounted) return;
      setState(() {
        _current = current;
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
    return NotificationListener<ScrollNotification>(
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
          return AppCard(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => RuntimeTimelineDetailPage(entry: entry),
              ),
            ),
            margin: const EdgeInsets.only(bottom: 10),
            child: _TimelineSummary(entry: entry, l10n: l10n),
          );
        },
      ),
    );
  }
}

class _EntityCard extends StatelessWidget {
  final RuntimeEntityState entity;
  final AppLocalizations l10n;
  final VoidCallback onEdit;

  const _EntityCard(
      {required this.entity, required this.l10n, required this.onEdit});

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

  const _TimelineSummary({required this.entry, required this.l10n});

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
                      builder: (_) =>
                          RuntimeStateRevertPreviewPage(entry: entry),
                    ),
                  ),
                  icon: const Icon(Icons.undo_rounded),
                  label: Text(l10n.restoreRevision),
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

class RuntimeStateRevertPreviewPage extends ConsumerStatefulWidget {
  final RuntimeTimelineEntry entry;

  const RuntimeStateRevertPreviewPage({super.key, required this.entry});

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
      revision: widget.entry.revision,
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
            targetRevision: widget.entry.revision,
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
              final diffs = _diffLabels(current, target);
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  Text(l10n.runtimeStateRevision(widget.entry.revision)),
                  Text(l10n.runtimeStateRevision(current.revision)),
                  const SizedBox(height: 12),
                  Text(l10n.runtimeStateCommittedEvent),
                  for (final diff in diffs)
                    AppCard(
                      margin: const EdgeInsets.only(top: 10),
                      child: Text(diff),
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

  List<String> _diffLabels(
      RuntimeStateSnapshot current, RuntimeStateSnapshot target) {
    final keys = {...current.entities.keys, ...target.entities.keys};
    final labels = <String>[];
    for (final key in keys) {
      final before =
          current.entities[key]?.overlay ?? const <String, Object?>{};
      final after = target.entities[key]?.overlay ?? const <String, Object?>{};
      for (final path in {...before.keys, ...after.keys}) {
        if (before[path] == after[path]) continue;
        labels.add(
            '$key · $path: ${before[path] ?? '—'} → ${after[path] ?? '—'}');
      }
    }
    return labels;
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
  late final Map<String, TextEditingController> _controllers = {
    for (final entry in widget.entity.overlay.entries)
      entry.key: TextEditingController(text: entry.value?.toString() ?? ''),
  };
  bool _saving = false;

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final chat = ref.read(chatProvider);
    final adventureId = chat.currentAdventureId;
    if (adventureId == null) return;
    setState(() => _saving = true);
    try {
      final repo = ref.read(adventureRepoProvider);
      final head = await repo.getRuntimeHead(adventureId, chat.currentBranchId);
      final changes = <RuntimeStateChangeProposal>[];
      for (final entry in _controllers.entries) {
        final original = widget.entity.overlay[entry.key];
        final value = _parseValue(entry.value.text, original);
        if (value != original) {
          changes.add(RuntimeStateChangeProposal(
            entityType: widget.entity.entityType,
            entityId: widget.entity.entityId,
            changeKind: RuntimeChangeKind.primary,
            operation: RuntimeChangeOperation.set,
            path: entry.key,
            value: value,
            reason: 'User edit',
          ));
        }
      }
      if (changes.isNotEmpty) {
        await repo.commitRuntimeMutation(RuntimeStateMutation(
          requestId: 'user-edit-${DateTime.now().microsecondsSinceEpoch}',
          adventureId: adventureId,
          branchId: chat.currentBranchId,
          draft: RuntimeStateCommitDraft(
            expectedRevision: head.revision,
            changes: changes,
            summary: 'User edited ${widget.entity.entityId}',
            source: RuntimeEventSource.userEdit,
            causeType: 'user_edit',
          ),
        ));
      }
      if (mounted) Navigator.of(context).pop();
    } on RuntimeHeadConflict {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  AppLocalizations.of(context)?.pageLoadError ?? 'Conflict')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Object? _parseValue(String text, Object? original) {
    if (original is int) return int.tryParse(text);
    if (original is num) return num.tryParse(text);
    if (original is bool) return text.toLowerCase() == 'true';
    return text;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();
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
            for (final entry in _controllers.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextFormField(
                  controller: entry.value,
                  decoration: InputDecoration(labelText: entry.key),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? l10n.pageLoadError
                      : null,
                ),
              ),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: Text(l10n.saveAction),
            ),
          ],
        ),
      ),
    );
  }
}
