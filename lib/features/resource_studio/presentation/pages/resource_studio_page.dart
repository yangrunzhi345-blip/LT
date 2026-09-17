import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/router/app_router.dart';
import '../../../../application/resources/resource_autosave_service.dart';
import '../../../../providers/riverpod_providers.dart';
import '../../../../domain/resources/resource_contracts.dart';
import '../../../../domain/resources/section_control.dart';
import '../../../../domain/resources/streaming_generation_runtime_contracts.dart';
import '../../domain/models/resource_studio_state.dart';
import '../controllers/resource_capacity_controller.dart';
import '../controllers/resource_revision_controller.dart';
import '../controllers/resource_studio_controller.dart';
import '../controllers/section_control_controller.dart';
import '../widgets/resource_capacity_panel.dart';
import '../widgets/resource_revision_panel.dart';
import '../widgets/resource_studio_outline.dart';
import '../widgets/resource_studio_part_card.dart';
import '../widgets/resource_studio_part_editor.dart';
import '../widgets/resource_studio_section_controls.dart';

/// User-facing workspace for watching and controlling resource generation.
final class ResourceStudioPage extends ConsumerStatefulWidget {
  const ResourceStudioPage({
    this.resourceId,
    this.sessionId,
    super.key,
  });

  final String? resourceId;
  final String? sessionId;

  @override
  ConsumerState<ResourceStudioPage> createState() => _ResourceStudioPageState();
}

final class _ResourceStudioPageState extends ConsumerState<ResourceStudioPage> {
  late final ResourceStudioController _controller;
  late final SectionControlController _sectionController;
  late final ResourceCapacityController _capacityController;
  late final ResourceRevisionController _revisionController;
  late final AutosaveServiceFactory _autosaveFactory;
  String? _sectionResourceId;

  /// Part currently open in the editor, or null when the Studio is read-only.
  String _editingPartId = '';

  /// Optimistic-locking token the open editor writes under.
  String _editingUpdatedAt = '';

  @override
  void initState() {
    super.initState();
    _sectionController = SectionControlController(
      runtime: ref.read(sectionControlRuntimeProvider),
    );
    _capacityController = ResourceCapacityController(
      runtime: ref.read(resourceCapacityRuntimeProvider),
    );
    _revisionController = ResourceRevisionController(
      runtime: ref.read(resourceRevisionRuntimeProvider),
    );
    _autosaveFactory = ref.read(resourceAutosaveServiceFactoryProvider);
    _controller = ResourceStudioController(
      runtime: ref.read(resourceStudioRuntimeProvider),
      resourceId: widget.resourceId,
      sessionId: widget.sessionId,
    )..addListener(_onStudioStateChanged);
    _controller.load();
  }

  @override
  void dispose() {
    _controller.removeListener(_onStudioStateChanged);
    _controller.dispose();
    _sectionController.dispose();
    _capacityController.dispose();
    _revisionController.dispose();
    super.dispose();
  }

  /// Loads section controls once the Studio knows which resource it is on.
  ///
  /// Section controls are keyed by resource id instead of the generation
  /// session, so a resource with no session still gets its section list.
  /// Capacity is loaded the same way so the panel never needs its own session.
  ///
  /// Switching to another resource first signals that the previous editor is
  /// being left, which is where the automatic compression trigger lives.
  void _onStudioStateChanged() {
    final resourceId = _controller.state.resourceId;
    if (resourceId == null || resourceId.value == _sectionResourceId) return;
    if (_sectionResourceId != null) {
      _capacityController.notifyEditorLeft();
    }
    _sectionResourceId = resourceId.value;
    unawaited(_sectionController.load(resourceId));
    unawaited(_capacityController.load(resourceId.value));
    unawaited(_revisionController.load(resourceId.value));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Resource Studio'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _controller.load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge(
            [
              _controller,
              _sectionController,
              _capacityController,
              _revisionController,
            ],
          ),
          builder: (context, _) => _buildBody(context, _controller.state),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, ResourceStudioState state) {
    if (state.status == ResourceStudioStatus.loading ||
        state.status == ResourceStudioStatus.initial) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.tree == null) return _buildSessionPicker(context, state);

    final tree = state.tree!;
    final selectedPart = tree.parts.firstWhere(
      (part) => part.id == state.selectedPartId,
      orElse: () => tree.parts.isEmpty ? _emptyPart(tree) : tree.parts.first,
    );
    final outline = ResourceStudioOutline(
      sections: tree.orderedSections,
      parts: tree.parts,
      selectedPartId: selectedPart.id,
      onPartSelected: _controller.selectPart,
    );
    final content =
        state.partContents[selectedPart.id.value] ?? selectedPart.content;
    final partSection = _editingPartId == selectedPart.id.value
        ? ResourceStudioPartEditor(
            key: ValueKey<String>('editor_${selectedPart.id.value}'),
            resourceId:
                ResourceId(state.resourceId?.value ?? tree.resource.id.value),
            partId: selectedPart.id,
            partTitle: selectedPart.title,
            initialContent: content,
            updatedAt: _editingUpdatedAt,
            autosaveFactory: _autosaveFactory,
            readUpdatedAt: () => ref
                .read(sectionControlRuntimeProvider)
                .readPartUpdatedAt(selectedPart.id),
            onSaved: _onPartContentSaved,
            onClose: _finishEditing,
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ResourceStudioPartCard(
                part: selectedPart,
                content: content,
                isActive: state.status == ResourceStudioStatus.generating,
                isValidating: state.status == ResourceStudioStatus.validating,
                hasError: state.status == ResourceStudioStatus.failed,
                onRetry: _controller.retry,
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: () => unawaited(_startEditing(selectedPart)),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('编辑正文'),
                ),
              ),
            ],
          );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 900) {
          return Row(
            children: [
              SizedBox(width: 300, child: outline),
              const VerticalDivider(width: 1),
              Expanded(child: _buildMain(context, state, partSection)),
            ],
          );
        }
        return Column(
          children: [
            ExpansionTile(
              title: const Text('目录'),
              children: [SizedBox(height: 220, child: outline)],
            ),
            Expanded(child: _buildMain(context, state, partSection)),
          ],
        );
      },
    );
  }

  Widget _buildMain(
    BuildContext context,
    ResourceStudioState state,
    Widget partSection,
  ) {
    final tree = state.tree!;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tree.resource.name,
                style: Theme.of(context).textTheme.headlineMedium),
            if (tree.resource.summary.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(tree.resource.summary),
            ],
            const SizedBox(height: 12),
            _StatusBar(state: state),
            if (state.errorMessage.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                state.errorMessage,
                softWrap: true,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _commands(state),
            ),
            const SizedBox(height: 16),
            ResourceCapacityPanel(
              state: _capacityController.state,
              onRefresh: () => unawaited(_capacityController.refresh()),
              onCompress: () =>
                  unawaited(_capacityController.requestCompression()),
              onRetry: () =>
                  unawaited(_capacityController.retryFailedCompression()),
              onPublish: () => unawaited(_confirmPublishCompression()),
            ),
            const SizedBox(height: 16),
            ResourceStudioSectionControls(
              state: _sectionController.state,
              onRefresh: () => unawaited(_sectionController.refresh()),
              onLoadMore: () => unawaited(_sectionController.loadMore()),
              onCreate: _showCreateSectionDialog,
              onRename: _renameSection,
              onDelete: _deleteSection,
              onMove: _moveSection,
              onValidate: _validateSection,
              onRegenerate: _regenerateSection,
            ),
            const SizedBox(height: 16),
            ResourceRevisionPanel(
              state: _revisionController.state,
              onRefresh: () => unawaited(_revisionController.refresh()),
              onRestore: _restoreRevision,
            ),
            const SizedBox(height: 16),
            partSection,
          ],
        ),
      ),
    );
  }

  /// Opens the editable body of [part], after resolving its write token.
  ///
  /// Refuses to open when the Part is gone: an editor without a token could
  /// only blind-overwrite, which is exactly what the token exists to prevent.
  Future<void> _startEditing(ResourcePart part) async {
    final runtime = ref.read(sectionControlRuntimeProvider);
    final token = await runtime.readPartUpdatedAt(part.id);
    if (!mounted) return;
    if (token == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('该段落已不存在，无法编辑')),
      );
      return;
    }
    setState(() {
      _editingPartId = part.id.value;
      _editingUpdatedAt = token;
    });
  }

  void _finishEditing() {
    if (!mounted) return;
    setState(() {
      _editingPartId = '';
      _editingUpdatedAt = '';
    });
    // The saved text is the new truth: refresh the tree view, the section
    // verdicts and the revision history that this edit just added to.
    unawaited(_controller.load());
    unawaited(_sectionController.refresh());
    unawaited(_revisionController.refresh());
  }

  /// Called after a debounce checkpoint persisted new text.
  ///
  /// The editor keeps showing the text it already has, so only the derived
  /// views (the section rollup and the revision history) need a refresh.
  void _onPartContentSaved(String content) {
    unawaited(_sectionController.refresh());
  }

  void _restoreRevision(String revisionId) {
    unawaited(_confirmRestoreRevision(revisionId));
  }

  /// Publishing replaces body text, so it asks first and refreshes the version
  /// history afterwards (the pre-compression content is now a revision).
  Future<void> _confirmPublishCompression() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('发布压缩结果'),
        content: const Text(
          '压缩后的正文会替换当前内容，替换前的正文会记录为历史版本，可随时恢复。\n确定要发布吗？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('发布'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _capacityController.publishCompression();
    if (!mounted) return;
    unawaited(_controller.load());
    unawaited(_revisionController.refresh());
    final message = _capacityController.state.errorMessage.isNotEmpty
        ? _capacityController.state.errorMessage
        : _capacityController.state.lastMessage;
    if (message.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  /// Restore overwrites the current confirmed content, so it asks first and
  /// then reports wherever the revision landed.
  Future<void> _confirmRestoreRevision(String revisionId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('恢复历史版本'),
        content: const Text(
          '当前内容会被该历史版本替换，替换前的内容也会保留在版本历史中。\n确定要恢复吗？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('恢复'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final summary = await _revisionController.restore(revisionId);
    if (!mounted) return;
    if (summary == null) return;
    setState(() {
      _editingPartId = '';
      _editingUpdatedAt = '';
    });
    unawaited(_controller.load());
    unawaited(_sectionController.refresh());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(summary.message)),
    );
  }

  void _renameSection(SectionControlEntry entry, String title) {
    unawaited(_sectionController.renameSection(entry, title));
  }

  void _deleteSection(SectionControlEntry entry) {
    unawaited(_sectionController.deleteSection(entry));
  }

  void _moveSection(SectionControlEntry entry, int targetIndex) {
    unawaited(_sectionController.moveSection(entry, targetIndex));
  }

  void _validateSection(SectionControlEntry entry) {
    unawaited(_sectionController.validateSection(entry));
  }

  void _regenerateSection(SectionControlEntry entry) {
    unawaited(_sectionController.regenerateSection(entry));
  }

  Future<void> _showCreateSectionDialog() async {
    final title = await showDialog<String>(
      context: context,
      builder: (_) => const _SectionTitleDialog(),
    );
    if (!mounted || title == null || title.trim().isEmpty) return;
    await _sectionController.createSection(title.trim());
  }

  List<Widget> _commands(ResourceStudioState state) {
    final session = state.session;
    if (session == null) return const <Widget>[];
    return [
      if (state.status == ResourceStudioStatus.paused ||
          state.status == ResourceStudioStatus.ready)
        FilledButton.icon(
          onPressed: session.status == StreamingLifecycleStatus.created
              ? _controller.start
              : _controller.resume,
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('继续生成'),
        ),
      if (state.status == ResourceStudioStatus.generating ||
          state.status == ResourceStudioStatus.validating)
        OutlinedButton.icon(
          onPressed: _controller.pause,
          icon: const Icon(Icons.pause_rounded),
          label: const Text('暂停'),
        ),
      if (state.status != ResourceStudioStatus.completed &&
          state.status != ResourceStudioStatus.failed)
        OutlinedButton.icon(
          onPressed: _controller.cancel,
          icon: const Icon(Icons.stop_circle_outlined),
          label: const Text('取消'),
        ),
      if (state.status == ResourceStudioStatus.failed)
        FilledButton.icon(
          onPressed: _controller.retry,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('重试'),
        ),
    ];
  }

  Widget _buildSessionPicker(
    BuildContext context,
    ResourceStudioState state,
  ) {
    return FutureBuilder<List<StreamingGenerationSession>>(
      future: _controller.activeSessions(),
      builder: (context, sessionSnapshot) {
        final sessions =
            sessionSnapshot.data ?? const <StreamingGenerationSession>[];
        if (sessionSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        return FutureBuilder<List<Resource>>(
          future: _controller.listResources(),
          builder: (context, resourceSnapshot) {
            final resources = resourceSnapshot.data ?? const <Resource>[];
            if (resourceSnapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      const Icon(Icons.auto_stories_outlined, size: 48),
                      const SizedBox(height: 16),
                      Text(
                        sessions.isEmpty ? '选择资源或生成会话' : '选择生成会话',
                        style: Theme.of(context).textTheme.titleLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _showCreateDialog,
                        icon: const Icon(Icons.auto_awesome_rounded),
                        label: const Text('创建并开始生成'),
                      ),
                      if (state.errorMessage.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          state.errorMessage,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      for (final session in sessions)
                        ListTile(
                          title: Text(session.resourceId.value),
                          subtitle: Text(session.status.storageValue),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => AppRouter.pushReplacement(
                            context,
                            pageBuilder: (_) => ResourceStudioPage(
                              sessionId: session.sessionId,
                            ),
                          ),
                        ),
                      if (resources.isNotEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 12, bottom: 4),
                          child: Text('资源'),
                        ),
                      for (final resource in resources)
                        ListTile(
                          title: Text(resource.name),
                          subtitle: Text(resource.type.storageValue),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => AppRouter.pushReplacement(
                            context,
                            pageBuilder: (_) => ResourceStudioPage(
                              resourceId: resource.id.value,
                            ),
                          ),
                        ),
                      if (sessions.isEmpty && resources.isEmpty)
                        const Text('暂无资源或可恢复的生成会话。'),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  ResourcePart _emptyPart(ResourceTree tree) => ResourcePart(
        id: const PartId('empty'),
        sectionId: tree.sections.isEmpty
            ? const SectionId('empty')
            : tree.sections.first.id,
        title: '暂无 Part',
        content: '当前资源还没有可展示的 Part。',
        sortOrder: 0,
      );

  Future<void> _showCreateDialog() async {
    final result = await showDialog<
        ({
          ResourceType type,
          String name,
          String reference,
        })>(
      context: context,
      builder: (_) => const _ResourceCreationDialog(),
    );
    if (!mounted || result == null) return;
    await _controller.createAndStart(
      resourceType: result.type,
      name: result.name,
      referenceText: result.reference,
    );
  }
}

final class _ResourceCreationDialog extends StatefulWidget {
  const _ResourceCreationDialog();

  @override
  State<_ResourceCreationDialog> createState() =>
      _ResourceCreationDialogState();
}

final class _ResourceCreationDialogState
    extends State<_ResourceCreationDialog> {
  final _nameController = TextEditingController();
  final _referenceController = TextEditingController();
  ResourceType _resourceType = ResourceType.worldview;

  @override
  void dispose() {
    _nameController.dispose();
    _referenceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('创建资源'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: '资源名称'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<ResourceType>(
                initialValue: _resourceType,
                decoration: const InputDecoration(labelText: '资源类型'),
                items: [
                  for (final type in ResourceType.values)
                    DropdownMenuItem(
                        value: type, child: Text(type.storageValue)),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _resourceType = value);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _referenceController,
                minLines: 4,
                maxLines: 8,
                decoration: const InputDecoration(
                  labelText: '参考材料',
                  alignLabelWithHint: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final name = _nameController.text.trim();
              final reference = _referenceController.text.trim();
              if (name.isEmpty || reference.isEmpty) return;
              Navigator.pop(context, (
                type: _resourceType,
                name: name,
                reference: reference,
              ));
            },
            child: const Text('开始'),
          ),
        ],
      );
}

final class _SectionTitleDialog extends StatefulWidget {
  const _SectionTitleDialog();

  @override
  State<_SectionTitleDialog> createState() => _SectionTitleDialogState();
}

final class _SectionTitleDialogState extends State<_SectionTitleDialog> {
  final _titleController = TextEditingController();

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('新增章节'),
        content: TextField(
          controller: _titleController,
          autofocus: true,
          decoration: const InputDecoration(labelText: '章节标题'),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, _titleController.text),
            child: const Text('创建'),
          ),
        ],
      );
}

final class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.state});

  final ResourceStudioState state;

  @override
  Widget build(BuildContext context) {
    final session = state.session;
    final label = switch (state.status) {
      ResourceStudioStatus.loading => '加载中',
      ResourceStudioStatus.generating => '生成中',
      ResourceStudioStatus.validating => '校验中',
      ResourceStudioStatus.paused => '已暂停',
      ResourceStudioStatus.completed => '已完成',
      ResourceStudioStatus.retrying => '重试中',
      ResourceStudioStatus.failed => '需要处理',
      _ => '准备就绪',
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            if (session != null) ...[
              if (session.totalPartsCount > 0)
                SizedBox(
                  width: 96,
                  child: LinearProgressIndicator(
                    value:
                        session.completedPartsCount / session.totalPartsCount,
                  ),
                ),
              const SizedBox(width: 12),
              Text(
                '${session.completedPartsCount}/${session.totalPartsCount} Parts',
              ),
            ],
          ],
        ),
      ),
    );
  }
}
