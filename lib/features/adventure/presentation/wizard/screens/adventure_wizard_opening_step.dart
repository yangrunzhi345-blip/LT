part of 'adventure_wizard_screen.dart';

extension _WizardOpeningStep on _AdventureWizardScreenState {
  Widget _buildOpeningStep(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = _l10n(context);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(l10n.openingAndRulesAdvancedConfigTitle,
                    style: theme.textTheme.titleMedium),
              ),
              TextButton.icon(
                onPressed: _openConfigPage,
                icon: const AppSvgIcon('tune', size: 16),
                label: Text(l10n.fullscreenAdvancedConfig),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          // AI 自动构思生成卡片
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: colorScheme.primary.withValues(alpha: 0.28),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AppSvgIcon(
                      'generation',
                      color: colorScheme.primary,
                      size: 20,
                    ),
                    const SizedBox(width: AppSpacing.xs + 2),
                    // Flexes so the badge below never pushes the title off a
                    // narrow phone screen.
                    Flexible(
                      child: Text(
                        l10n.aiOpeningPanelTitle,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        l10n.wizardWorldviewQuickBadge,
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  l10n.aiOpeningPanelDesc,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _aiPromptCtrl,
                  enabled: !_aiGenerating,
                  maxLines: 2,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    labelText: l10n.openingPromptLabel,
                    hintText: l10n.openingPromptHint,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.all(AppSpacing.sm),
                  ),
                ),
                if (_aiGenError != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.errorContainer.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Row(
                      children: [
                        AppSvgIcon(
                          'error',
                          color: colorScheme.error,
                          size: 18,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: Text(
                            _aiGenError!,
                            style: TextStyle(
                              color: colorScheme.onErrorContainer,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const AppSvgIcon('close', size: 16),
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _rebuild(() => _aiGenError = null),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                // Buttons wrap on narrow phones instead of being pushed
                // off-screen by the fixed Row.
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilledButton.icon(
                      onPressed: _aiGenerating ? null : _generateOpeningWithAi,
                      icon: _aiGenerating
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const AppSvgIcon('generation', size: 18),
                      label: Text(
                        _aiGenerating
                            ? l10n.aiOpeningGeneratingProgress
                            : (_openingSceneCtrl.text.isNotEmpty
                                ? l10n.regenerate
                                : l10n.aiGenerateOpeningAndBranches),
                      ),
                    ),
                    if (_openingSceneCtrl.text.isNotEmpty ||
                        _option1Ctrl.text.isNotEmpty) ...[
                      OutlinedButton.icon(
                        onPressed: _aiGenerating
                            ? null
                            : () {
                                _rebuild(() {
                                  _openingSceneCtrl.clear();
                                  _option1Ctrl.clear();
                                  _option2Ctrl.clear();
                                  _option3Ctrl.clear();
                                });
                              },
                        icon: const AppSvgIcon('delete', size: 16),
                        label: Text(l10n.clearSettingsAction),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Divider(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
          const SizedBox(height: AppSpacing.sm),
          // 开场第一幕剧情描写
          Row(
            children: [
              Text(
                l10n.openingFirstSceneTitle,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Flexible(
                child: Text(
                  l10n.openingFirstSceneDesc,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.outline,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          AppTextField(
            controller: _openingSceneCtrl,
            hintText: l10n.openingFirstSceneHint,
            maxLines: 5,
            onChanged: (_) => _rebuild(() {}),
          ),
          const SizedBox(height: AppSpacing.md),
          // 初始行动抉择分支
          Row(
            children: [
              Text(
                l10n.initialActionBranchesTitle,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              // The hint flexes and ellipsizes so the row still fits at 320px
              // when the clear action is visible.
              Flexible(
                child: Text(
                  l10n.initialActionBranchesDesc,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.outline,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Spacer(),
              if (_option1Ctrl.text.isNotEmpty ||
                  _option2Ctrl.text.isNotEmpty ||
                  _option3Ctrl.text.isNotEmpty)
                TextButton.icon(
                  onPressed: () => _rebuild(() {
                    _option1Ctrl.clear();
                    _option2Ctrl.clear();
                    _option3Ctrl.clear();
                  }),
                  icon: const AppSvgIcon('close', size: 14),
                  label: Text(l10n.clearSettingsAction,
                      style: const TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          _buildBranchOptionField(
            controller: _option1Ctrl,
            indexLabel: l10n.actionBranch1,
            hint: l10n.actionBranch1Hint,
            scheme: colorScheme,
          ),
          const SizedBox(height: AppSpacing.xs + 2),
          _buildBranchOptionField(
            controller: _option2Ctrl,
            indexLabel: l10n.actionBranch2,
            hint: l10n.actionBranch2Hint,
            scheme: colorScheme,
          ),
          const SizedBox(height: AppSpacing.xs + 2),
          _buildBranchOptionField(
            controller: _option3Ctrl,
            indexLabel: l10n.actionBranch3,
            hint: l10n.actionBranch3Hint,
            scheme: colorScheme,
          ),
        ],
      ),
    );
  }

  Widget _buildBranchOptionField({
    required TextEditingController controller,
    required String indexLabel,
    required String hint,
    required ColorScheme scheme,
  }) {
    return TextField(
      controller: controller,
      style: const TextStyle(fontSize: 13),
      onChanged: (_) => _rebuild(() {}),
      decoration: InputDecoration(
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: 10, right: 8),
          child: Center(
            widthFactor: 1.0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                indexLabel,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: scheme.primary,
                ),
              ),
            ),
          ),
        ),
        hintText: hint,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.6),
          ),
        ),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
    );
  }
}
