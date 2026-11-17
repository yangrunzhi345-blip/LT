part of 'runtime_state_hub_page.dart';

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
                    icon: const AppSvgIcon('undo'),
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
                const AppSvgIcon('bookmark'),
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
                const AppSvgIcon('forward'),
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
            icon: const AppSvgIcon('compare'),
            label: Text(l10n.runtimeStateCompareCurrent),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => RuntimeStateRevertPreviewPage(
                targetRevision: widget.checkpoint.revision,
              ),
            )),
            icon: const AppSvgIcon('undo'),
            label: Text(l10n.restoreRevision),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _saving ? null : _delete,
            icon: const AppSvgIcon('delete'),
            label: Text(l10n.deleteAction),
          ),
          if (chat.currentAdventureId == null)
            Text(l10n.runtimeStateNoAdventure),
        ],
      ),
    );
  }
}
