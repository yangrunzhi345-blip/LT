import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/feedback/app_feedback.dart';
import '../../../../core/localization/app_date_formats.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/widgets/app_action_button.dart';
import '../../../../core/widgets/app_svg_icon.dart';
import '../../../../core/widgets/app_expansion_tile.dart';
import '../../../../core/widgets/workbench_section.dart';
import '../../../../core/widgets/app_confirm_dialog.dart';
import '../../../../core/widgets/app_select.dart';
import '../../../../core/theme/custom_attribute_importance_visuals.dart';
import '../../../../application/resource_library/edit_drafts.dart';
import '../../../../models/tracked_state_definition.dart';
import '../../../../models/typed_runtime_state.dart';
import '../../../../domain/resources/resource_contracts.dart';
import '../../../../domain/resources/character_relationship.dart';
import '../../../../domain/resources/streaming_generation_runtime_contracts.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../l10n/generated/app_localizations_zh.dart';
import '../../../../providers/riverpod_providers.dart';
import '../../../adventure/presentation/wizard/screens/assembly_create_page.dart';
import '../../../resource_studio/presentation/pages/resource_studio_page.dart';
import 'resource_ai_create_page.dart';
import '../../domain/models/resource_library_view_state.dart';
import '../resolvers/resource_presentation_resolver.dart';
import '../widgets/resource_voice_setting_section.dart';
import '../widgets/character_relationships_section.dart';
import '../../../../application/resource_library/character_relationship_management.dart';

AppLocalizations _l10n(BuildContext context) =>
    AppLocalizations.of(context) ?? AppLocalizationsZh();

/// 资源详情与预览页面 [ResourceLibraryDetailPage]
///
/// 展示完整资源信息、生命周期状态、Resource → Section → Part 树及用户操作。
/// 严格区分已就绪 (Ready/Consumable) 与生成校验中 (Planning/Generating/Validating) 状态。
final class ResourceLibraryDetailPage extends ConsumerStatefulWidget {
  const ResourceLibraryDetailPage({
    required this.item,
    required this.onMoveToTrash,
    this.embedded = false,
    this.onDeleted,
    this.onOpenStudio,
    this.relationshipResources = const [],
    this.tree,
    this.isConsumableOverride,
    this.session,
    super.key,
  });

  final ResourceLibraryItem item;
  final bool embedded;
  final Future<void> Function()? onOpenStudio;
  final Future<void> Function(String message)? onDeleted;
  final Future<String?> Function() onMoveToTrash;

  /// Live character/NPC resources available as additional relationship
  /// references when this page opens related-character generation.
  final List<ResourceLibraryItem> relationshipResources;
  final ResourceTree? tree;
  final bool? isConsumableOverride;
  final StreamingGenerationSession? session;

  @override
  ConsumerState<ResourceLibraryDetailPage> createState() =>
      _ResourceLibraryDetailPageState();
}

final class _ResourceLibraryDetailPageState
    extends ConsumerState<ResourceLibraryDetailPage> {
  bool _isDeleting = false;
  bool _loadingTree = true;
  bool _actionInProgress = false;
  ResourceTree? _tree;
  StreamingGenerationSession? _session;

  /// Read-only monitoring definitions declared by this resource. These are
  /// definitions only — a resource never stores a current value.
  List<TrackedStateDefinition> _trackedStateDefinitions = const [];
  bool _loadingTrackedDefinitions = true;
  List<CharacterRelationshipPerspective> _relationships = const [];

  bool get _isConsumable =>
      widget.isConsumableOverride ?? widget.item.isConsumable;

  @override
  void initState() {
    super.initState();
    _tree = widget.tree;
    _session = widget.session;
    if (_tree == null && _session == null) {
      _loadTreeAndSession();
    } else {
      _loadingTree = false;
    }
    _loadTrackedStateDefinitions();
    _loadRelationships();
  }

  Future<void> _loadRelationships() async {
    if (widget.item.type != ResourceType.character &&
        widget.item.type != ResourceType.npc) {
      return;
    }
    try {
      final management = ref.read(characterRelationshipManagementProvider);
      final relationships =
          await management.listFor(ResourceId(widget.item.id));
      if (mounted) setState(() => _relationships = relationships);
    } catch (_) {
      // Legacy resources without a unified ResourceId have no relationship view.
    }
  }

  CharacterRelationshipManagement get _relationshipManagement =>
      ref.read(characterRelationshipManagementProvider);

  Future<void> _editRelationship(
      CharacterRelationshipPerspective relationship) async {
    final l10n = _l10n(context);
    final subjectRole = TextEditingController(text: relationship.subjectRole);
    final counterpartRole =
        TextEditingController(text: relationship.counterpartRole);
    final description = TextEditingController(text: relationship.description);
    var relationType = relationship.relationType;
    try {
      final values = await showDialog<_RelationshipEditValues>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text('${l10n.editAction} ${l10n.relationshipNetworkTitle}'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppSelect<CharacterRelationshipType>(
                    value: relationType,
                    label: l10n.relationshipLabel(''),
                    items: [
                      for (final value in CharacterRelationshipType.values)
                        AppSelectItem(
                          value: value,
                          label: _relationshipTypeLabel(l10n, value),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => relationType = value);
                      }
                    },
                  ),
                  TextField(
                    controller: subjectRole,
                    decoration:
                        InputDecoration(labelText: relationship.subjectRole),
                    textInputAction: TextInputAction.next,
                  ),
                  TextField(
                    controller: counterpartRole,
                    decoration: InputDecoration(
                        labelText: relationship.counterpartRole),
                    textInputAction: TextInputAction.next,
                  ),
                  TextField(
                    controller: description,
                    decoration: InputDecoration(
                      labelText: l10n.relationDetailsHint,
                    ),
                    minLines: 2,
                    maxLines: 6,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(l10n.cancelAction),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(
                  _RelationshipEditValues(
                    relationType: relationType,
                    subjectRole: subjectRole.text,
                    counterpartRole: counterpartRole.text,
                    description: description.text,
                  ),
                ),
                child: Text(l10n.saveAction),
              ),
            ],
          ),
        ),
      );
      if (values == null || !mounted) return;
      try {
        await _relationshipManagement.updateFromPerspective(
          subjectResourceId: ResourceId(widget.item.id),
          relationshipId: relationship.relationshipId,
          relationType: values.relationType,
          subjectRole: values.subjectRole,
          counterpartRole: values.counterpartRole,
          description: values.description,
        );
        if (!mounted) return;
        await _loadRelationships();
        if (mounted) AppFeedback.success(context, l10n.saveAction);
      } on CharacterRelationshipValidationException catch (error) {
        if (!mounted) return;
        AppFeedback.error(context, _relationshipFailureMessage(l10n, error));
        await _loadRelationships();
      }
    } finally {
      subjectRole.dispose();
      counterpartRole.dispose();
      description.dispose();
    }
  }

  Future<void> _deleteRelationship(
      CharacterRelationshipPerspective relationship) async {
    final l10n = _l10n(context);
    final confirmed = await AppConfirmDialog.show(
      context: context,
      title: '${l10n.deleteAction} ${l10n.relationshipNetworkTitle}',
      message: l10n.deleteMessageConfirmation,
      confirmLabel: l10n.deleteAction,
      isDanger: true,
    );
    if (!confirmed || !mounted) return;
    try {
      await _relationshipManagement.delete(relationship.relationshipId);
      if (!mounted) return;
      await _loadRelationships();
      if (mounted) AppFeedback.success(context, l10n.deleteAction);
    } on CharacterRelationshipValidationException catch (error) {
      if (!mounted) return;
      AppFeedback.error(context, _relationshipFailureMessage(l10n, error));
      await _loadRelationships();
    }
  }

  String _relationshipTypeLabel(
    AppLocalizations l10n,
    CharacterRelationshipType type,
  ) =>
      switch (type) {
        CharacterRelationshipType.friend => l10n.relationFriend,
        CharacterRelationshipType.enemy => l10n.relationEnemy,
        CharacterRelationshipType.stranger => l10n.relationStranger,
        CharacterRelationshipType.companion => l10n.relationCompanion,
        CharacterRelationshipType.lover => l10n.relationLover,
        CharacterRelationshipType.mentorStudent => l10n.relationMentor,
        CharacterRelationshipType.rival => l10n.relationRival,
        CharacterRelationshipType.family ||
        CharacterRelationshipType.sibling ||
        CharacterRelationshipType.parentChild =>
          l10n.relationKin,
        CharacterRelationshipType.custom => l10n.relationCustom,
        CharacterRelationshipType.employerEmployee ||
        CharacterRelationshipType.guardianWard =>
          l10n.relationCustom,
      };

  String _relationshipFailureMessage(
    AppLocalizations l10n,
    CharacterRelationshipValidationException error,
  ) =>
      switch (error.code) {
        CharacterRelationshipFailure.relationshipNotFound =>
          l10n.staleResourceMessage,
        CharacterRelationshipFailure.endpointNotFound ||
        CharacterRelationshipFailure.endpointNotLive =>
          l10n.resourceDetailRecoverFailed,
        _ => l10n.resourceDetailActionFailed(l10n.relationshipNetworkTitle),
      };

  Future<void> _loadTrackedStateDefinitions() async {
    try {
      final repo = ref.read(libraryRepoProvider);
      final read = await repo.readResourcePreferringTree(
        type: widget.item.type,
        legacyId: widget.item.id,
      );
      final row = read.legacyRow;
      final definitions = row == null
          ? const <TrackedStateDefinition>[]
          : _definitionsFromRow(
              widget.item.type, Map<String, dynamic>.from(row));
      if (mounted) {
        setState(() {
          _trackedStateDefinitions = definitions;
          _loadingTrackedDefinitions = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingTrackedDefinitions = false);
    }
  }

  List<TrackedStateDefinition> _definitionsFromRow(
    ResourceType type,
    Map<String, dynamic> row,
  ) {
    switch (type) {
      case ResourceType.character:
        return CharacterCardEditDraft.fromExisting(row).trackedStateDefinitions;
      case ResourceType.npc:
        return NpcEditDraft.fromExisting(row).trackedStateDefinitions;
      case ResourceType.worldview:
        return WorldviewEditDraft.fromExisting(row).trackedStateDefinitions;
    }
  }

  Future<void> _loadTreeAndSession() async {
    try {
      final runtime = ref.read(resourceStudioRuntimeProvider);
      final tree = await runtime.readTree(ResourceId(widget.item.id));
      final session = await runtime.getLatestSessionForResource(widget.item.id);
      if (mounted) {
        setState(() {
          _tree = tree;
          _session = session;
          _loadingTree = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loadingTree = false);
      }
    }
  }

  Future<void> _openStudio() async {
    if (widget.onOpenStudio case final onOpenStudio?) {
      await onOpenStudio();
    } else {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => ResourceStudioPage(
            resourceId: widget.item.id,
          ),
        ),
      );
    }
    if (mounted) {
      await _loadTreeAndSession();
    }
  }

  Future<void> _useForAdventure() async {
    if (!_isConsumable) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (ctx) => AssemblyCreatePage(
          initialWorldviewId: widget.item.type == ResourceType.worldview
              ? widget.item.id
              : null,
          initialCharacterId: (widget.item.type == ResourceType.character ||
                  widget.item.type == ResourceType.npc)
              ? widget.item.id
              : null,
          onStartAdventure: (config) async {
            if (Navigator.of(ctx).canPop()) {
              Navigator.of(ctx).pop();
            }
          },
        ),
      ),
    );
  }

  Future<void> _generateRelatedCharacter() async {
    if (widget.item.type != ResourceType.character &&
        widget.item.type != ResourceType.npc) {
      return;
    }
    final draft = await Navigator.of(context).push<ResourceStudioCreationDraft>(
      MaterialPageRoute<ResourceStudioCreationDraft>(
        builder: (_) => ResourceAiCreatePage(
          initialType: ResourceType.character,
          resources: widget.relationshipResources,
          lockedRelationshipSource: widget.item,
        ),
      ),
    );
    if (!mounted || draft == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ResourceStudioPage(creationDraft: draft),
      ),
    );
    if (mounted) await _loadTreeAndSession();
    if (mounted) await _loadRelationships();
  }

  Future<void> _cancelGeneration() async {
    final l10n = _l10n(context);
    final confirmed = await AppConfirmDialog.show(
      context: context,
      title: l10n.resourceDetailCancelConfirmTitle,
      message: l10n.resourceDetailCancelConfirmMessage,
      confirmLabel: l10n.resourceStudioCancelGenerating,
      isDanger: true,
    );
    if (!confirmed || !mounted) return;

    final sessionId = _session?.sessionId;
    if (sessionId == null) return;
    setState(() => _actionInProgress = true);
    try {
      final runtime = ref.read(resourceStudioRuntimeProvider);
      await runtime.cancel(sessionId);
      if (!mounted) return;
      AppFeedback.success(context, l10n.resourceDetailCancelSuccess);
      await _loadTreeAndSession();
    } catch (e) {
      if (!mounted) return;
      AppFeedback.error(
        context,
        l10n.resourceDetailActionFailed(
          ResourcePresentationResolver.sanitize(e.toString()),
        ),
      );
    } finally {
      if (mounted) setState(() => _actionInProgress = false);
    }
  }

  Future<void> _retryGeneration() async {
    final sessionId = _session?.sessionId;
    if (sessionId == null) return;
    final l10n = _l10n(context);
    setState(() => _actionInProgress = true);
    try {
      final runtime = ref.read(resourceStudioRuntimeProvider);
      await runtime.resume(sessionId);
      if (!mounted) return;
      await _loadTreeAndSession();
    } catch (e) {
      if (!mounted) return;
      AppFeedback.error(
        context,
        l10n.resourceDetailActionFailed(
          ResourcePresentationResolver.sanitize(e.toString()),
        ),
      );
    } finally {
      if (mounted) setState(() => _actionInProgress = false);
    }
  }

  Future<void> _recoverTask() async {
    final sessionId = _session?.sessionId;
    if (sessionId == null) return;
    final l10n = _l10n(context);
    setState(() => _actionInProgress = true);
    try {
      final runtime = ref.read(resourceStudioRuntimeProvider);
      final ok = await runtime.recover(sessionId);
      if (!mounted) return;
      if (ok) {
        AppFeedback.success(context, l10n.resourceDetailRecoverSuccess);
        await _loadTreeAndSession();
      } else {
        AppFeedback.error(context, l10n.resourceDetailRecoverFailed);
      }
    } catch (e) {
      if (!mounted) return;
      AppFeedback.error(
        context,
        l10n.resourceDetailActionFailed(
          ResourcePresentationResolver.sanitize(e.toString()),
        ),
      );
    } finally {
      if (mounted) setState(() => _actionInProgress = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final l10n = _l10n(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final lifecycle = ResourcePresentationResolver.resolveLifecycle(
      lifecycleState: item.lifecycleState,
      displayStatus: item.status,
      isConsumable: _isConsumable,
    );
    final inFlightText =
        ResourcePresentationResolver.inFlightStatusLabel(lifecycle, l10n);
    final safeName = ResourcePresentationResolver.safeName(item.name, l10n);
    final safeSummary =
        ResourcePresentationResolver.safeSummary(item.summary, l10n);
    final safeUpdated =
        AppDateFormats.formatPersisted(item.updatedAt, l10n.localeName) ??
            l10n.revisionUnknownDate;

    final isSessionInFlight = _session?.status.isInFlight ?? false;
    final isSessionFailed =
        _session?.status == StreamingLifecycleStatus.failed ||
            lifecycle == ResourcePresentationLifecycle.failed;
    final isSessionPaused =
        _session?.status == StreamingLifecycleStatus.paused ||
            lifecycle == ResourcePresentationLifecycle.paused;
    final canRecover = _session?.status == StreamingLifecycleStatus.failed;

    final content = SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top status badges
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Chip(
                      label: Text(
                        ResourcePresentationResolver.localizedTypeLabel(
                          item.type,
                          l10n,
                        ),
                      ),
                    ),
                    Chip(
                      label: Text(
                        ResourcePresentationResolver.localizedLifecycleLabel(
                          lifecycle,
                          l10n,
                        ),
                        style: TextStyle(
                          color: _isConsumable
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Chip(
                      label: Text(
                        ResourcePresentationResolver.isConsumableLabel(
                          _isConsumable,
                          l10n,
                        ),
                        style: TextStyle(
                          color: _isConsumable
                              ? colorScheme.primary
                              : colorScheme.outline,
                        ),
                      ),
                    ),
                  ],
                ),
                if (inFlightText != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color:
                          colorScheme.primaryContainer.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                            child: Text(
                          inFlightText,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        )),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),

                // Resource Title
                Text(
                  safeName,
                  key: const Key('resource-detail-title'),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  softWrap: true,
                ),
                if (safeUpdated.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    safeUpdated,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],

                // Summary
                if (safeSummary.isNotEmpty &&
                    safeSummary != l10n.resourceNoSummary) ...[
                  const SizedBox(height: 12),
                  Text(
                    safeSummary,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.5,
                    ),
                    softWrap: true,
                  ),
                ],

                const SizedBox(height: 24),

                // Resource -> Section -> Part Tree
                _buildTreeCard(context, l10n),

                if (widget.item.type == ResourceType.character ||
                    widget.item.type == ResourceType.npc) ...<Widget>[
                  const SizedBox(height: 24),
                  CharacterRelationshipsSection(
                    relationships: _relationships,
                    title: l10n.relationshipNetworkTitle,
                    emptyLabel: l10n.relationshipNetworkDescription,
                    editLabel: l10n.editAction,
                    deleteLabel: l10n.deleteAction,
                    onEdit: _editRelationship,
                    onDelete: _deleteRelationship,
                  ),
                ],

                const SizedBox(height: 24),

                // Local read-aloud voice binding (device-local preference; it
                // never writes resource content or creates a revision).
                if (widget.item.type != ResourceType.worldview) ...<Widget>[
                  ResourceVoiceSettingSection(
                    resourceId: ResourceId(widget.item.id),
                    resourceName: widget.item.name,
                    resourceType: widget.item.type,
                    embedded: true,
                  ),
                  const SizedBox(height: 24),
                ],

                // Monitored fields (definitions only — never a runtime value)
                _buildTrackedDefinitionsSection(context, l10n),

                const SizedBox(height: 24),

                // Actions Section
                Text(
                  l10n.resourceActions,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),

                // Open Studio button
                AppPrimaryButton(
                  key: const Key('resource-open-studio-button'),
                  label: item.isStudioAvailable
                      ? l10n.resourceEnterStudio
                      : l10n.resourceLegacyNoStudio,
                  fullWidth: true,
                  enabled: item.isStudioAvailable,
                  onPressed: item.isStudioAvailable ? _openStudio : null,
                ),

                if (item.type == ResourceType.character ||
                    item.type == ResourceType.npc) ...[
                  const SizedBox(height: 10),
                  AppSecondaryButton(
                    key: const Key('resource-generate-related-character'),
                    label: l10n.resourceAiCreationTitle,
                    fullWidth: true,
                    onPressed: _generateRelatedCharacter,
                  ),
                ],

                const SizedBox(height: 10),

                // Use for Adventure button
                AppSecondaryButton(
                  key: const Key('resource-use-for-adventure-button'),
                  label: l10n.resourceUseForAdventure,
                  fullWidth: true,
                  enabled: _isConsumable,
                  onPressed: _isConsumable ? _useForAdventure : null,
                ),
                if (!_isConsumable)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, left: 4),
                    child: Text(
                      l10n.resourceNotConsumableTip,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.outline,
                      ),
                    ),
                  ),

                // Retry / Cancel / Recover actions if session exists
                if (isSessionInFlight) ...[
                  const SizedBox(height: 10),
                  AppSecondaryButton(
                    key: const Key('resource-cancel-button'),
                    label: l10n.resourceDetailCancelGeneration,
                    fullWidth: true,
                    isLoading: _actionInProgress,
                    onPressed: _cancelGeneration,
                  ),
                ],
                if (isSessionFailed || isSessionPaused) ...[
                  const SizedBox(height: 10),
                  AppSecondaryButton(
                    key: const Key('resource-retry-button'),
                    label: l10n.resourceDetailRetryGeneration,
                    fullWidth: true,
                    isLoading: _actionInProgress,
                    onPressed: _retryGeneration,
                  ),
                ],
                if (canRecover) ...[
                  const SizedBox(height: 10),
                  AppSecondaryButton(
                    key: const Key('resource-recover-button'),
                    label: l10n.resourceDetailRecoverTask,
                    fullWidth: true,
                    isLoading: _actionInProgress,
                    onPressed: _recoverTask,
                  ),
                ],

                const SizedBox(height: 16),

                // Danger zone: Move to trash
                AppDangerButton(
                  key: const Key('resource-move-to-trash-button'),
                  label: l10n.moveToTrashAction,
                  outlined: true,
                  fullWidth: true,
                  isLoading: _isDeleting,
                  onPressed: _confirmMoveToTrash,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (widget.embedded) return content;
    return Scaffold(
      appBar: AppBar(
          title: Text(l10n.resourceDetailTitle),
          leading: IconButton(
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              icon: const AppSvgIcon('back'),
              onPressed: () => Navigator.of(context).pop())),
      body: content,
    );
  }

  Widget _buildTrackedDefinitionsSection(
    BuildContext context,
    AppLocalizations l10n,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final definitions = _trackedStateDefinitions;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.trackedStateMonitorLabel,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        if (_loadingTrackedDefinitions)
          const SizedBox.shrink()
        else if (definitions.isEmpty)
          Text(
            l10n.trackedStateResourceEmpty,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final definition in definitions)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _buildTrackedDefinitionRow(context, l10n, definition),
                ),
            ],
          ),
      ],
    );
  }

  Widget _buildTrackedDefinitionRow(
    BuildContext context,
    AppLocalizations l10n,
    TrackedStateDefinition definition,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final meta = <String>[
      _kindLabel(definition.valueKind, l10n),
      if (definition.isNumeric &&
          (definition.minimum != null || definition.maximum != null))
        '${_formatNumber(definition.minimum ?? 0)}–'
            '${definition.maximum == null ? '∞' : _formatNumber(definition.maximum!)}',
      if (definition.enumValues.isNotEmpty) definition.enumValues.join(' / '),
      definition.importance.localizedLabel(l10n),
    ].where((part) => part.trim().isNotEmpty).join(' · ');
    final rule = definition.description.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          definition.name,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (meta.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            meta,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (rule.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            rule,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }

  String _kindLabel(RuntimeStateValueKind kind, AppLocalizations l10n) =>
      switch (kind) {
        RuntimeStateValueKind.number => l10n.trackedStateKindNumber,
        RuntimeStateValueKind.integer => l10n.trackedStateKindInteger,
        RuntimeStateValueKind.text => l10n.trackedStateKindText,
        RuntimeStateValueKind.boolean => l10n.trackedStateKindBoolean,
        RuntimeStateValueKind.enumValue => l10n.trackedStateKindEnum,
      };

  static String _formatNumber(num value) => value == value.truncate()
      ? value.truncate().toString()
      : value.toString();

  Widget _buildTreeCard(
    BuildContext context,
    AppLocalizations l10n,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tree = _tree;

    return WorkbenchSection(
      title: l10n.resourceTreeStructureTitle,
      action: _loadingTree
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2))
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (tree == null || tree.sections.isEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: Text(
                  l10n.resourceTreeNoSections,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ] else ...[
            for (final section in tree.orderedSections)
              _buildSectionTile(context, tree, section, l10n),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionTile(
    BuildContext context,
    ResourceTree tree,
    ResourceSection section,
    AppLocalizations l10n,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final parts = tree.orderedPartsOf(section.id);
    final safeTitle = ResourcePresentationResolver.sanitize(
      section.title,
      fallback: '章节',
    );
    final safeSummary = ResourcePresentationResolver.sanitize(section.summary);

    return Container(
      margin: const EdgeInsets.only(top: 8),
      child: AppExpansionTile(
        initiallyExpanded: true,
        shape: const Border(),
        collapsedShape: const Border(),
        title: Text(
          safeTitle,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: safeSummary.isNotEmpty
            ? Text(
                safeSummary,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              )
            : null,
        children: [
          if (parts.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  l10n.resourceSectionEmpty,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.outline,
                  ),
                ),
              ),
            )
          else
            for (final part in parts)
              ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                title: Text(
                  ResourcePresentationResolver.sanitize(
                    part.title,
                    fallback: '段落',
                  ),
                  style: theme.textTheme.bodyMedium,
                ),
                subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          part.content.trim().isNotEmpty
                              ? ResourcePresentationResolver.sanitize(
                                  part.content.length > 60
                                      ? '${part.content.substring(0, 60)}...'
                                      : part.content)
                              : l10n.resourcePartEmpty,
                          style: theme.textTheme.bodySmall),
                      Text(l10n.resourcePartCharCount(part.content.length),
                          style: theme.textTheme.labelSmall),
                    ]),
              ),
        ],
      ),
    );
  }

  Future<void> _confirmMoveToTrash() async {
    final l10n = _l10n(context);
    final confirmed = await AppConfirmDialog.show(
      context: context,
      title: l10n.moveToTrashAction,
      message: l10n.moveToTrashMessage(widget.item.localizedName(l10n)),
      confirmLabel: l10n.moveToTrashAction,
      isDanger: true,
    );
    if (!confirmed || !mounted) return;

    setState(() => _isDeleting = true);
    final message = await widget.onMoveToTrash();
    if (!mounted) return;
    if (message == null) {
      setState(() => _isDeleting = false);
      AppFeedback.error(context, l10n.moveToTrashFailed);
      return;
    }
    if (widget.onDeleted case final onDeleted?) {
      await onDeleted(message);
    } else {
      Navigator.of(context).pop(message);
    }
  }
}

final class _RelationshipEditValues {
  const _RelationshipEditValues({
    required this.relationType,
    required this.subjectRole,
    required this.counterpartRole,
    required this.description,
  });

  final CharacterRelationshipType relationType;
  final String subjectRole;
  final String counterpartRole;
  final String description;
}
