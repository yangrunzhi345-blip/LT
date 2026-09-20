import 'dart:async';

export '../../../../application/resources/resource_creation_contracts.dart'
    show ResourceStudioCreationDraft;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/widgets/app_confirm_dialog.dart';
import '../../../../application/resources/resource_autosave_service.dart';
import '../../../../application/resources/resource_creation_contracts.dart';
import '../../../../providers/riverpod_providers.dart';
import '../../../../domain/resources/resource_contracts.dart';
import '../../../../domain/resources/section_control.dart';
import '../../../../domain/resources/streaming_generation_runtime_contracts.dart';
import '../../domain/models/resource_studio_state.dart';
import '../controllers/resource_capacity_controller.dart';
import '../controllers/resource_revision_controller.dart';
import '../controllers/resource_studio_controller.dart';
import '../controllers/section_control_controller.dart';
import '../resource_studio_user_message.dart';
import '../widgets/resource_capacity_panel.dart';
import '../widgets/resource_revision_panel.dart';
import '../widgets/resource_studio_outline.dart';
import '../widgets/resource_studio_part_card.dart';
import '../widgets/resource_studio_part_editor.dart';
import '../widgets/resource_studio_section_controls.dart';
import '../../../resource_library/presentation/screens/resource_ai_create_page.dart';

/// User-facing workspace for watching and controlling resource generation.
final class ResourceStudioPage extends ConsumerStatefulWidget {
  const ResourceStudioPage({
    this.resourceId,
    this.sessionId,
    this.creationDraft,
    super.key,
  });

  final String? resourceId;
  final String? sessionId;
  final ResourceStudioCreationDraft? creationDraft;

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

  /// True while the Studio is turning [widget.creationDraft] into a resource
  /// and a generation session.
  ///
  /// The Studio must render this state instead of the session picker: during AI
  /// planning the tree does not exist yet, and showing "select a resource or
  /// session" made a successful "开始创建" look like it had never entered the
  /// generation workspace.
  bool _creating = false;

  /// True when the draft creation itself failed, so the Studio keeps the user
  /// on a failure state with a retry instead of bouncing back to the library.
  bool _creationFailed = false;

  /// Reentrancy guard for the draft-creation command.
  bool _creationInFlight = false;
  late final String? _creationIdempotencyKey;

  /// Whether the mobile outline has been manually expanded.
  bool? _mobileOutlineExpanded;

  /// Scroll ownership stays with the existing main reader rather than creating
  /// a nested list for Parts.
  final ScrollController _contentScrollController = ScrollController();
  final Map<String, GlobalKey> _partKeys = <String, GlobalKey>{};
  bool _scrollSpyScheduled = false;
  bool _programmaticScroll = false;
  PartId? _programmaticTarget;
  Size? _lastViewportSize;

  @override
  void initState() {
    super.initState();
    _creating = widget.creationDraft != null;
    _creationIdempotencyKey = widget.creationDraft == null
        ? null
        : (widget.creationDraft!.idempotencyKey ??
            'studio_${DateTime.now().microsecondsSinceEpoch}');
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
    _contentScrollController.addListener(_scheduleScrollSpy);
    unawaited(_load());
  }

  Future<void> _load() async {
    await _controller.load();
    final draft = widget.creationDraft;
    if (!mounted || draft == null) return;
    await _beginCreation(draft);
  }

  /// Creates the resource + generation session from [draft].
  ///
  /// This reuses the Studio's single production creation entry point
  /// ([ResourceStudioController.createAndStart]) — the same command the picker
  /// uses — so no second generation pipeline or state exists. The Studio stays
  /// on a creation state until the runtime reports back, then either shows the
  /// live generation view or a retryable failure state.
  Future<void> _beginCreation(ResourceStudioCreationDraft draft) async {
    if (_creationInFlight) return;
    _creationInFlight = true;
    setState(() {
      _creating = true;
      _creationFailed = false;
    });
    try {
      await _controller.createAndStart(
        resourceType: draft.type,
        name: draft.name,
        referenceSource: draft.referenceSource,
        targetCharacters: draft.targetCharacters,
        origin: draft.origin,
        libraryMode: draft.libraryMode,
        idempotencyKey: _creationIdempotencyKey,
        targetResourceId: draft.targetResourceId,
        originWorldviewId: draft.originWorldviewId,
      );
    } finally {
      _creationInFlight = false;
      if (mounted) {
        setState(() {
          _creating = false;
          _creationFailed = _controller.state.tree == null &&
              _controller.state.errorMessage.isNotEmpty;
        });
      }
    }
  }

  @override
  void dispose() {
    _contentScrollController
      ..removeListener(_scheduleScrollSpy)
      ..dispose();
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

  bool _syncPartKeys(ResourceTree tree) {
    final partIds = tree.parts.map((part) => part.id.value).toSet();
    final changed = partIds.length != _partKeys.length ||
        partIds.any((partId) => !_partKeys.containsKey(partId));
    _partKeys.removeWhere((partId, _) => !partIds.contains(partId));
    for (final partId in partIds) {
      _partKeys.putIfAbsent(partId, GlobalKey.new);
    }
    return changed;
  }

  void _scheduleScrollSpy() {
    if (_programmaticScroll || _scrollSpyScheduled || !mounted) return;
    _scrollSpyScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollSpyScheduled = false;
      if (!mounted || _programmaticScroll) return;
      _updateSelectionFromScrollPosition();
    });
  }

  void _updateSelectionFromScrollPosition() {
    final tree = _controller.state.tree;
    if (tree == null || tree.parts.isEmpty) return;
    final scrollContext =
        _contentScrollController.position.context.storageContext;
    final viewportBox = scrollContext.findRenderObject() as RenderBox?;
    if (viewportBox == null || !viewportBox.hasSize) return;

    final readingLine = viewportBox.localToGlobal(Offset.zero).dy + 100;
    ResourcePart? lastPastReadingLine;
    ResourcePart? firstVisiblePart;
    for (final part in tree.parts) {
      final partBox = _partKeys[part.id.value]
          ?.currentContext
          ?.findRenderObject() as RenderBox?;
      if (partBox == null || !partBox.hasSize) continue;
      final partTop = partBox.localToGlobal(Offset.zero).dy;
      final partBottom = partTop + partBox.size.height;
      if (partTop <= readingLine) {
        lastPastReadingLine = part;
      }
      if (firstVisiblePart == null && partBottom >= readingLine) {
        firstVisiblePart = part;
      }
    }
    final selectedPart = lastPastReadingLine ?? firstVisiblePart;
    if (selectedPart != null &&
        selectedPart.id != _controller.state.selectedPartId) {
      _controller.selectPart(selectedPart.id);
    }
  }

  Future<void> _scrollToPart(PartId partId) async {
    _controller.selectPart(partId);
    _programmaticScroll = true;
    _programmaticTarget = partId;
    final isMobile = MediaQuery.sizeOf(context).width < 600;
    if (isMobile) {
      setState(() => _mobileOutlineExpanded = false);
    }
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final targetContext = _partKeys[partId.value]?.currentContext;
    if (targetContext != null && targetContext.mounted) {
      await Scrollable.ensureVisible(
        targetContext,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        alignment: 0.08,
      );
    }
    if (!mounted || _programmaticTarget != partId) return;
    _programmaticScroll = false;
    _programmaticTarget = null;
    _scheduleScrollSpy();
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification is UserScrollNotification &&
        notification.direction != ScrollDirection.idle) {
      _programmaticScroll = false;
      _programmaticTarget = null;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('创作工作台'),
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
    // A draft creation owns the screen until it resolves, even though the tree
    // is still absent while the planner runs. Falling through here would show
    // the session picker during a successful "开始创建".
    if (state.tree == null && _creating) {
      return _buildCreationInProgress(context, state);
    }
    if (state.tree == null && _creationFailed) {
      return _buildCreationFailure(context, state);
    }
    if (state.tree == null) return _buildSessionPicker(context, state);

    final tree = state.tree!;
    if (_syncPartKeys(tree)) _scheduleScrollSpy();
    final outline = ResourceStudioOutline(
      key: const ValueKey<String>('resource_studio_outline'),
      sections: tree.orderedSections,
      parts: tree.parts,
      selectedPartId: state.selectedPartId,
      onPartSelected: (partId) => unawaited(_scrollToPart(partId)),
    );
    final partSections = _buildPartSections(context, state, tree);

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportSize = constraints.biggest;
        if (_lastViewportSize != viewportSize) {
          _lastViewportSize = viewportSize;
          _scheduleScrollSpy();
        }
        final isMobile = constraints.maxWidth < 600;
        final outlineWidth = constraints.maxWidth >= 900
            ? 300.0
            : (constraints.maxWidth * 0.34).clamp(130.0, 200.0).toDouble();
        final isOutlineExpanded = !isMobile || _mobileOutlineExpanded == true;

        if (!isOutlineExpanded) {
          return Column(
            children: [
              _buildMobileOutlineToggle(expand: true),
              Expanded(child: _buildMain(context, state, partSections)),
            ],
          );
        }

        final outlinePane = SizedBox(
          width: outlineWidth,
          child: isMobile
              ? Column(
                  children: [
                    _buildMobileOutlineToggle(expand: false),
                    Expanded(child: outline),
                  ],
                )
              : outline,
        );
        return Row(
          children: [
            outlinePane,
            const VerticalDivider(width: 1),
            Expanded(child: _buildMain(context, state, partSections)),
          ],
        );
      },
    );
  }

  Widget _buildMobileOutlineToggle({required bool expand}) {
    return ListTile(
      key: const ValueKey<String>('resource_studio_outline_toggle'),
      dense: true,
      title: const Text('目录'),
      leading: const Icon(Icons.menu_book_outlined),
      trailing: Icon(expand ? Icons.chevron_right : Icons.chevron_left),
      onTap: () {
        setState(() {
          _mobileOutlineExpanded = expand;
        });
      },
    );
  }

  Widget _buildMain(
    BuildContext context,
    ResourceStudioState state,
    List<Widget> partSections,
  ) {
    final tree = state.tree!;
    return NotificationListener<ScrollNotification>(
      onNotification: _handleScrollNotification,
      child: SingleChildScrollView(
        key: const ValueKey<String>('resource_studio_main'),
        controller: _contentScrollController,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                tree.resource.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
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
              ...partSections,
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildPartSections(
    BuildContext context,
    ResourceStudioState state,
    ResourceTree tree,
  ) {
    if (tree.parts.isEmpty) {
      return const [Text('当前资源还没有可展示的内容。')];
    }
    return [
      for (final section in tree.orderedSections) ...[
        Text(section.title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        for (final part in tree.parts.where(
          (part) => part.sectionId == section.id,
        )) ...[
          KeyedSubtree(
            key: _partKeys[part.id.value],
            child: ValueListenableBuilder<String>(
              valueListenable: _controller.partPreview(part.id),
              builder: (context, preview, child) => _buildPartSection(
                context,
                state,
                tree,
                part,
                previewContent: preview,
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ],
    ];
  }

  Widget _buildPartSection(BuildContext context, ResourceStudioState state,
      ResourceTree tree, ResourcePart part,
      {String? previewContent}) {
    final content =
        previewContent ?? state.partContents[part.id.value] ?? part.content;
    if (_editingPartId == part.id.value) {
      return ResourceStudioPartEditor(
        key: ValueKey<String>('editor_${part.id.value}'),
        resourceId:
            ResourceId(state.resourceId?.value ?? tree.resource.id.value),
        partId: part.id,
        partTitle: part.title,
        initialContent: content,
        updatedAt: _editingUpdatedAt,
        autosaveFactory: _autosaveFactory,
        onSaved: _onPartContentSaved,
        onClose: _finishEditing,
      );
    }
    final isSelected = part.id == state.selectedPartId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ResourceStudioPartCard(
          part: part,
          content: content,
          isActive:
              isSelected && state.status == ResourceStudioStatus.generating,
          isValidating:
              isSelected && state.status == ResourceStudioStatus.validating,
          hasError: isSelected && state.status == ResourceStudioStatus.failed,
          onRetry: _controller.retry,
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              OutlinedButton.icon(
                onPressed: () => unawaited(_startEditing(part)),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('编辑正文'),
              ),
              OutlinedButton.icon(
                onPressed: () => unawaited(_confirmDeletePart(part)),
                icon: const Icon(Icons.delete_outline),
                label: const Text('删除段落'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
          ),
        ),
      ],
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
    final confirmed = await AppConfirmDialog.show(
      context: context,
      title: '发布压缩结果',
      message: '压缩后的正文会替换当前内容，替换前的正文会记录为历史版本，可随时恢复。\n确定要发布吗？',
      confirmLabel: '发布',
      icon: Icons.publish_outlined,
    );
    if (!confirmed) return;

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
    final confirmed = await AppConfirmDialog.show(
      context: context,
      title: '恢复历史版本',
      message: '当前内容会被该历史版本替换，替换前的内容也会保留在版本历史中。\n确定要恢复吗？',
      confirmLabel: '恢复',
      icon: Icons.restore_rounded,
    );
    if (!confirmed) return;

    // Read the token the user's decision was based on. A restore overwrites
    // confirmed content, so it is guarded by the same compare-and-set as every
    // other Phase 9 write: if something changed while the dialog was open the
    // restore is refused instead of silently discarding the newer state
    // (audit P9-M5).
    final expectedUpdatedAt =
        await _revisionController.readResourceUpdatedAt() ?? '';
    final summary = await _revisionController.restore(
      revisionId,
      expectedUpdatedAt: expectedUpdatedAt,
    );
    if (!mounted) return;
    if (summary == null) {
      final error = _revisionController.state.errorMessage;
      if (error.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error)),
        );
      }
      return;
    }
    setState(() {
      _editingPartId = '';
      _editingUpdatedAt = '';
    });
    unawaited(_controller.load());
    unawaited(_sectionController.refresh());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(resourceStudioUserMessage(summary.message))),
    );
  }

  /// Deletes the selected Part into the recycle bin.
  ///
  /// Part deletion was implemented (and wired to the bin) but had no entry
  /// point, so the capability was unreachable (audit P9-M8).
  Future<void> _confirmDeletePart(ResourcePart part) async {
    final confirmed = await AppConfirmDialog.show(
      context: context,
      title: '删除段落',
      message: '「${part.title}」会被移入回收站，可在「回收站」中恢复。\n确定要删除吗？',
      confirmLabel: '删除',
      isDanger: true,
      icon: Icons.delete_outline_rounded,
    );
    if (!confirmed) return;

    final runtime = ref.read(sectionControlRuntimeProvider);
    final token = await runtime.readPartUpdatedAt(part.id);
    if (!mounted) return;
    if (token == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('该段落已不存在，无法删除')),
      );
      return;
    }
    try {
      await runtime.deletePart(
        sectionId: part.sectionId,
        partId: part.id,
        expectedUpdatedAt: token,
      );
      if (!mounted) return;
      setState(() {
        _editingPartId = '';
        _editingUpdatedAt = '';
      });
      unawaited(_controller.load());
      unawaited(_sectionController.refresh());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已移入回收站，可在「回收站」中恢复')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '删除段落失败：${resourceStudioUserMessage(error)}',
          ),
        ),
      );
    }
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

  /// Transient creation state shown while the draft is being persisted and the
  /// blueprint is planned.
  ///
  /// This is not a stand-in workbench: it is the real Studio surface reporting
  /// the in-flight command, and it is replaced by the live generation view as
  /// soon as the session exists.
  Widget _buildCreationInProgress(
    BuildContext context,
    ResourceStudioState state,
  ) {
    final theme = Theme.of(context);
    final draft = widget.creationDraft;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 20),
              Text(
                '正在创建资源并启动生成',
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              if (draft != null) ...[
                const SizedBox(height: 8),
                Text(
                  '${_resourceTypeLabel(draft.type)} · ${draft.name}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '目标约 ${draft.targetCharacters} 字',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              if (state.errorMessage.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  state.errorMessage,
                  style: TextStyle(color: theme.colorScheme.error),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Failure state for a draft that could not be created.
  ///
  /// The user stays on the Studio and can retry; the page never returns to the
  /// library on its own, and no navigation happened before the task existed.
  Widget _buildCreationFailure(
    BuildContext context,
    ResourceStudioState state,
  ) {
    final theme = Theme.of(context);
    final draft = widget.creationDraft;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: 48,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                '资源创建失败',
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                state.errorMessage.isEmpty ? '请稍后重试' : state.errorMessage,
                style: TextStyle(color: theme.colorScheme.error),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              if (draft != null)
                FilledButton.icon(
                  onPressed: _creationInFlight
                      ? null
                      : () => unawaited(_beginCreation(draft)),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('重试创建'),
                ),
            ],
          ),
        ),
      ),
    );
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
                      FutureBuilder<List<ResourceCreationSession>>(
                        future: _controller.pendingPlanningSessions(),
                        builder: (context, snapshot) {
                          final pending = snapshot.data ??
                              const <ResourceCreationSession>[];
                          if (pending.isEmpty) return const SizedBox.shrink();
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(top: 12, bottom: 4),
                                child: Text('待确认的 AI 规划'),
                              ),
                              for (final planning in pending)
                                ListTile(
                                  title: Text(planning.name),
                                  subtitle: const Text('继续确认并开始生成'),
                                  trailing: const Icon(
                                    Icons.chevron_right_rounded,
                                  ),
                                  onTap: () => unawaited(
                                    _continuePlanningSession(
                                      planning.sessionId,
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                      for (var index = 0; index < sessions.length; index++)
                        ListTile(
                          title: Text('未完成的生成任务 ${index + 1}'),
                          subtitle: const Text('生成中'),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => AppRouter.pushReplacement(
                            context,
                            pageBuilder: (_) => ResourceStudioPage(
                              sessionId: sessions[index].sessionId,
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
                          subtitle: Text(_resourceTypeLabel(resource.type)),
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

  Future<void> _continuePlanningSession(String creationSessionId) async {
    final identity = await ref
        .read(resourceStudioRuntimeProvider)
        .confirmAndStart(creationSessionId);
    if (!mounted) return;
    await AppRouter.pushReplacement(
      context,
      pageBuilder: (_) => ResourceStudioPage(
        resourceId: identity.resourceId.value,
        sessionId: identity.generationSessionId,
      ),
    );
  }

  Future<void> _showCreateDialog() async {
    final result = await AppRouter.push<ResourceStudioCreationDraft>(
      context,
      pageBuilder: (_) => const ResourceAiCreatePage(),
    );
    if (!mounted || result == null) return;
    await _beginCreation(result);
  }
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
      ResourceStudioStatus.loading => '生成中',
      ResourceStudioStatus.generating => '生成中',
      ResourceStudioStatus.validating => '生成中',
      ResourceStudioStatus.paused => '已保存',
      ResourceStudioStatus.completed => '已保存',
      ResourceStudioStatus.retrying => '生成中',
      ResourceStudioStatus.failed => '优化失败',
      _ => '已保存',
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(label),
            if (session != null && session.totalPartsCount > 0) ...[
              SizedBox(
                width: 96,
                child: LinearProgressIndicator(
                  value: session.completedPartsCount / session.totalPartsCount,
                ),
              ),
              Text(
                '${(session.completedPartsCount / session.totalPartsCount * 100).round()}%',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _resourceTypeLabel(ResourceType type) => switch (type) {
      ResourceType.worldview => '世界观',
      ResourceType.character => '角色',
      ResourceType.npc => 'NPC',
    };
