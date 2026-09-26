import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../application/resources/resource_creation_contracts.dart';
import '../../../../core/feedback/app_feedback.dart';
import '../../../../core/theme/app_borders.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_action_button.dart';
import '../../../../core/widgets/app_page_scaffold.dart';
import '../../../../domain/resources/resource_blueprint.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../l10n/generated/app_localizations_zh.dart';
import '../../../../providers/riverpod_providers.dart';
import '../../../resource_studio/presentation/pages/resource_studio_page.dart';
import '../resolvers/resource_presentation_resolver.dart';

AppLocalizations _l10n(BuildContext context) =>
    AppLocalizations.of(context) ?? AppLocalizationsZh();

/// 蓝图规划确认页面 [ResourceBlueprintReviewPage]
///
/// 展示 AI 规划好的结构化蓝图（章节与段落候选），用户确认并选定段落后才启动正式正文生成。
/// 确保在用户确认前不生成正文、不将 planning-only 状态视为完成，也不将半成品显示为可消费资源。
class ResourceBlueprintReviewPage extends ConsumerStatefulWidget {
  const ResourceBlueprintReviewPage({
    super.key,
    required this.plan,
    required this.draft,
  });

  final ResourceAiCreationPlan plan;
  final ResourceStudioCreationDraft draft;

  @override
  ConsumerState<ResourceBlueprintReviewPage> createState() =>
      _ResourceBlueprintReviewPageState();
}

class _ResourceBlueprintReviewPageState
    extends ConsumerState<ResourceBlueprintReviewPage> {
  late final Set<String> _selectedPartIds;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _selectedPartIds = widget.plan.blueprint.allParts.map((p) => p.id).toSet();
  }

  Future<void> _confirmAndStart() async {
    if (_submitting) return;
    final l10n = _l10n(context);
    setState(() => _submitting = true);

    try {
      final runtime = ref.read(resourceStudioRuntimeProvider);
      final identity = await runtime.confirmAndStart(
        widget.plan.creationSessionId,
        selectedPartIds: _selectedPartIds.isEmpty ? null : _selectedPartIds,
      );
      if (!mounted) return;

      await Navigator.of(context).pushReplacement<void, void>(
        MaterialPageRoute<void>(
          builder: (_) => ResourceStudioPage(
            resourceId: identity.resourceId.value,
            sessionId: identity.generationSessionId,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _submitting = false);
      AppFeedback.error(
        context,
        l10n.resourceDetailActionFailed(
          ResourcePresentationResolver.sanitize(error.toString(),
              fallback: l10n.resourceCreationFailedRetry),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final bp = widget.plan.blueprint;
    final safeName = ResourcePresentationResolver.safeName(
      bp.suggestedName.isNotEmpty ? bp.suggestedName : widget.draft.name,
      l10n,
    );
    final safeSummary = ResourcePresentationResolver.safeSummary(
      bp.summary.isNotEmpty ? bp.summary : '',
      l10n,
    );

    return AppPageScaffold(
      title: l10n.resourceBlueprintReviewTitle,
      maxWidth: 760,
      scrollable: true,
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Notice banner: body has not started yet
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color:
                    colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: AppBorders.defaultColor(context)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    color: colorScheme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      l10n.resourceBlueprintPlanningNotice,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // Blueprint overview card
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color:
                    isDark ? AppColors.darkSurface : AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: AppBorders.defaultColor(context)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Chip(
                        label: Text(
                          ResourcePresentationResolver.localizedTypeLabel(
                            widget.draft.type,
                            l10n,
                          ),
                        ),
                      ),
                      Chip(
                        label: Text(
                          ResourcePresentationResolver.localizedLifecycleLabel(
                            ResourcePresentationLifecycle.planning,
                            l10n,
                          ),
                          style: TextStyle(color: colorScheme.primary),
                        ),
                      ),
                      Chip(
                        label: Text(
                          ResourcePresentationResolver.isConsumableLabel(
                            false,
                            l10n,
                          ),
                          style: TextStyle(color: colorScheme.outline),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    safeName,
                    key: const Key('blueprint-resource-name'),
                    style: theme.textTheme.headlineSmall,
                  ),
                  if (safeSummary.isNotEmpty &&
                      safeSummary != l10n.resourceNoSummary) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      safeSummary,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      Text(
                        l10n.resourceSectionsCount(bp.sections.length),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        l10n.resourcePartsCount(bp.allParts.length),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        l10n.resourceBlueprintTotalEstimatedChars(
                          bp.totalEstimatedLength,
                        ),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // Sections and parts hierarchy
            Text(
              l10n.resourceTreeStructureTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              l10n.resourceBlueprintReviewSubtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),

            for (int sIndex = 0; sIndex < bp.sections.length; sIndex++)
              _buildSectionItem(
                context,
                bp.sections[sIndex],
                sIndex + 1,
                l10n,
                isDark,
              ),

            const SizedBox(height: AppSpacing.xl),

            // Confirm & Start button
            AppPrimaryButton(
              key: const Key('blueprint-confirm-button'),
              label: l10n.resourceBlueprintConfirmAndGenerate,
              icon: Icons.check_circle_outline_rounded,
              fullWidth: true,
              isLoading: _submitting,
              onPressed: _selectedPartIds.isEmpty ? null : _confirmAndStart,
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionItem(
    BuildContext context,
    BlueprintSection section,
    int sectionIndex,
    AppLocalizations l10n,
    bool isDark,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final safeSectionTitle = ResourcePresentationResolver.sanitize(
      section.title,
      fallback: '章节 $sectionIndex',
    );
    final safeSectionSummary = ResourcePresentationResolver.sanitize(
      section.summary,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppBorders.defaultColor(context)),
      ),
      child: ExpansionTile(
        initiallyExpanded: true,
        shape: const Border(),
        collapsedShape: const Border(),
        title: Text(
          safeSectionTitle,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: safeSectionSummary.isNotEmpty
            ? Text(
                safeSectionSummary,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              )
            : null,
        children: [
          const Divider(height: 1),
          for (final part in section.parts)
            CheckboxListTile(
              key: ValueKey<String>('blueprint-part-check-${part.id}'),
              value: _selectedPartIds.contains(part.id),
              onChanged: (checked) {
                setState(() {
                  if (checked == true) {
                    _selectedPartIds.add(part.id);
                  } else {
                    _selectedPartIds.remove(part.id);
                  }
                });
              },
              title: Text(
                ResourcePresentationResolver.sanitize(
                  part.title,
                  fallback: '段落',
                ),
                style: theme.textTheme.bodyMedium,
              ),
              subtitle: Text(
                '${part.generationGoal.isNotEmpty ? ResourcePresentationResolver.sanitize(part.generationGoal) : ''} · 约 ${part.estimatedLength} 字',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
            ),
        ],
      ),
    );
  }
}
