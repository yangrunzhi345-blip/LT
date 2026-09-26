import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/feedback/app_feedback.dart';
import '../../../../core/theme/app_borders.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_action_button.dart';
import '../../../../core/widgets/app_confirm_dialog.dart';
import '../../../../domain/resources/resource_contracts.dart';
import '../../../../domain/resources/streaming_generation_runtime_contracts.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../l10n/generated/app_localizations_zh.dart';
import '../../../../providers/riverpod_providers.dart';
import '../../../adventure/presentation/wizard/screens/assembly_create_page.dart';
import '../../../resource_studio/presentation/pages/resource_studio_page.dart';
import '../../domain/models/resource_library_view_state.dart';
import '../resolvers/resource_presentation_resolver.dart';

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
    this.tree,
    this.isConsumableOverride,
    this.session,
    super.key,
  });

  final ResourceLibraryItem item;
  final Future<String?> Function() onMoveToTrash;
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
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ResourceStudioPage(
          resourceId: widget.item.id,
        ),
      ),
    );
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
    final isDark = theme.brightness == Brightness.dark;

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
        ResourcePresentationResolver.safeUpdatedTime(item.updatedAt, l10n);

    final isSessionInFlight = _session?.status.isInFlight ?? false;
    final isSessionFailed =
        _session?.status == StreamingLifecycleStatus.failed ||
            lifecycle == ResourcePresentationLifecycle.failed;
    final isSessionPaused =
        _session?.status == StreamingLifecycleStatus.paused ||
            lifecycle == ResourcePresentationLifecycle.paused;
    final canRecover = _session?.status == StreamingLifecycleStatus.failed;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.resourceDetailTitle)),
      body: SafeArea(
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
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
                          Text(
                            inFlightText,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
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
                  _buildTreeCard(context, l10n, isDark),

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
                    icon: Icons.edit_note_rounded,
                    fullWidth: true,
                    enabled: item.isStudioAvailable,
                    onPressed: item.isStudioAvailable ? _openStudio : null,
                  ),

                  const SizedBox(height: 10),

                  // Use for Adventure button
                  AppSecondaryButton(
                    key: const Key('resource-use-for-adventure-button'),
                    label: l10n.resourceUseForAdventure,
                    icon: Icons.explore_outlined,
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
                      icon: Icons.cancel_outlined,
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
                      icon: Icons.refresh_rounded,
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
                      icon: Icons.build_rounded,
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
                    icon: Icons.delete_outline_rounded,
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
      ),
    );
  }

  Widget _buildTreeCard(
    BuildContext context,
    AppLocalizations l10n,
    bool isDark,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tree = _tree;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppBorders.defaultColor(context)),
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.account_tree_outlined,
                  size: 20, color: colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                l10n.resourceTreeStructureTitle,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (_loadingTree)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
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
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: ExpansionTile(
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
                subtitle: Text(
                  part.content.trim().isNotEmpty
                      ? ResourcePresentationResolver.sanitize(
                          part.content.length > 60
                              ? '${part.content.substring(0, 60)}...'
                              : part.content,
                        )
                      : l10n.resourcePartEmpty,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                trailing: Text(
                  l10n.resourcePartCharCount(part.content.length),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.outline,
                  ),
                ),
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
      icon: Icons.delete_outline_rounded,
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
    Navigator.of(context).pop(message);
  }
}
