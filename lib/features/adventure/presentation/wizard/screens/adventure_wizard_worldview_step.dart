part of 'adventure_wizard_screen.dart';

extension _WizardWorldviewStep on _AdventureWizardScreenState {
  Widget _buildWorldviewStep(BuildContext context) {
    final l10n = _l10n(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppSvgIcon('world', size: 20, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(l10n.worldSelectionTitle,
                    style: theme.textTheme.titleMedium),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          // AI 快速编写世界观卡片
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: scheme.primary.withValues(alpha: 0.28),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: AppSpacing.xs + 2,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    AppSvgIcon(
                      'generation',
                      color: scheme.primary,
                      size: 20,
                    ),
                    const SizedBox(width: AppSpacing.xs + 2),
                    Text(
                      l10n.worldviewAiAssistantTitle,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: scheme.primary,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        l10n.wizardWorldviewQuickBadge,
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  l10n.wizardWorldviewAiSummary,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _aiWorldviewPromptCtrl,
                  enabled: !_aiWorldviewGenerating,
                  maxLines: 2,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    labelText: l10n.wizardWorldviewPromptLabel,
                    hintText: l10n.wizardWorldviewPromptHint,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.all(AppSpacing.sm),
                  ),
                ),
                if (_aiWorldviewError != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.errorContainer.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Row(
                      children: [
                        AppSvgIcon(
                          'error',
                          color: scheme.error,
                          size: 18,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: Text(
                            _aiWorldviewError!,
                            style: TextStyle(
                              color: scheme.onErrorContainer,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const AppSvgIcon('close', size: 16),
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                          onPressed: () =>
                              _rebuild(() => _aiWorldviewError = null),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      l10n.generationModeLabel,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 4),
                    ChoiceChip(
                      label: Text(l10n.conciseMode,
                          style: const TextStyle(fontSize: 12)),
                      selected: !_aiWorldviewDetailed,
                      onSelected: _aiWorldviewGenerating
                          ? null
                          : (v) {
                              if (v) {
                                _rebuild(() => _aiWorldviewDetailed = false);
                              }
                            },
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    const SizedBox(width: 6),
                    ChoiceChip(
                      label: Text(l10n.detailedMode,
                          style: const TextStyle(fontSize: 12)),
                      selected: _aiWorldviewDetailed,
                      onSelected: _aiWorldviewGenerating
                          ? null
                          : (v) {
                              if (v) {
                                _rebuild(() => _aiWorldviewDetailed = true);
                              }
                            },
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    if (_aiWorldviewProgress != null) ...[
                      const SizedBox(width: 12),
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _aiWorldviewProgress!,
                        key: const Key('wizard-worldview-progress'),
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    FilledButton.icon(
                      onPressed: _aiWorldviewGenerating
                          ? null
                          : _generateWorldviewWithAi,
                      icon: _aiWorldviewGenerating
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
                        _aiWorldviewGenerating
                            ? (_aiWorldviewDetailed
                                ? l10n.wizardWorldviewGeneratingDetailed
                                : l10n.wizardWorldviewGeneratingBrief)
                            : (_worldviewNameCtrl.text.isNotEmpty
                                ? l10n.wizardRegenerateWorldviewAction
                                : l10n.wizardGenerateWorldviewAction),
                      ),
                    ),
                    if (_worldviewNameCtrl.text.isNotEmpty ||
                        _worldviewDescCtrl.text.isNotEmpty) ...[
                      const SizedBox(width: AppSpacing.sm),
                      TextButton.icon(
                        onPressed: _aiWorldviewGenerating
                            ? null
                            : () {
                                _rebuild(() {
                                  _worldviewNameCtrl.clear();
                                  _worldviewDescCtrl.clear();
                                  _selectedWorldviewId = null;
                                });
                              },
                        icon: const AppSvgIcon('close', size: 14),
                        label: Text(l10n.clearSettingsAction,
                            style: const TextStyle(fontSize: 12)),
                      ),
                    ],
                    if (_worldviewNameCtrl.text.isNotEmpty) ...[
                      const SizedBox(width: AppSpacing.xs),
                      TextButton.icon(
                        onPressed: _aiWorldviewGenerating || _savingWorldview
                            ? null
                            : () => _saveCurrentWorldviewToLibrary(),
                        icon: const AppSvgIcon('bookmark', size: 14),
                        label: Text(l10n.autoSaveToLibrary,
                            style: const TextStyle(fontSize: 12)),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Divider(color: scheme.outlineVariant.withValues(alpha: 0.4)),
          const SizedBox(height: AppSpacing.sm),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: LinearProgressIndicator(),
            )
          else if (_worldviewLoadError != null)
            _resourceBanner(
              context,
              icon: 'error',
              isError: true,
              message: l10n.resourceLoadFailedRetry,
            ),
          if (_worldviews.isNotEmpty) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.worldSelectionSubtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _openWorldSelectionPage,
                  icon: const AppSvgIcon('map', size: 16),
                  label: Text(l10n.fullscreenPreviewButton),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _worldviews.map((wv) {
                final id = wv['id'] as String;
                final name = wv['name'] as String? ?? l10n.unnamedWorldview;
                final isSelected = id == _selectedWorldviewId;
                return ChoiceChip(
                  avatar: isSelected
                      ? const AppSvgIcon('check', size: 14)
                      : const AppSvgIcon('world', size: 14),
                  label: Text(name),
                  selected: isSelected,
                  onSelected: (selected) {
                    _rebuild(() {
                      if (selected) {
                        _selectedWorldviewId = id;
                        _worldviewNameCtrl.text = name;
                        _worldviewDescCtrl.text =
                            wv['description'] as String? ?? '';
                      } else {
                        _selectedWorldviewId = null;
                      }
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: AppSpacing.md),
          ] else if (_worldviewLoadError == null) ...[
            _resourceBanner(
              context,
              icon: 'info',
              isError: false,
              message:
                  '${l10n.worldSelectionEmptyTitle}\n${l10n.worldSelectionEmptyDesc}',
            ),
          ],
          AppTextField(
            controller: _worldviewNameCtrl,
            label: l10n.worldNameRequiredLabel,
            hintText: l10n.worldNameHint,
          ),
          const SizedBox(height: AppSpacing.sm),
          AppTextField(
            controller: _worldviewDescCtrl,
            label: l10n.lawsAndBackgroundLabel,
            hintText: l10n.lawsAndBackgroundHint,
            maxLines: 3,
          ),
          const SizedBox(height: AppSpacing.md),

          // ── 保存到资料库选项与快捷操作 ──
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 560;
              final childContent = Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Checkbox(
                    value: _saveWorldviewToLibrary,
                    onChanged: (val) {
                      _rebuild(() {
                        _saveWorldviewToLibrary = val ?? true;
                      });
                    },
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        _rebuild(() {
                          _saveWorldviewToLibrary = !_saveWorldviewToLibrary;
                        });
                      },
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 6,
                              runSpacing: AppSpacing.xs,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  l10n.autoSaveToLibrary,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 1.5,
                                  ),
                                  decoration: BoxDecoration(
                                    color:
                                        scheme.primary.withValues(alpha: 0.12),
                                    borderRadius:
                                        BorderRadius.circular(AppRadius.full),
                                  ),
                                  child: Text(
                                    l10n.wizardReusableBadge,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: scheme.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              l10n.wizardWorldviewSaveDescription,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (!isNarrow) ...[
                    const SizedBox(width: AppSpacing.sm),
                    FilledButton.tonalIcon(
                      onPressed: _savingWorldview
                          ? null
                          : () => _saveCurrentWorldviewToLibrary(),
                      icon: _savingWorldview
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const AppSvgIcon('bookmark', size: 16),
                      label: Text(_savingWorldview
                          ? l10n.partSaving
                          : l10n.saveToLibraryNow),
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                    ),
                  ],
                ],
              );

              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm + 2,
                  vertical: AppSpacing.xs + 2,
                ),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: 0.3),
                  ),
                ),
                child: isNarrow
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          childContent,
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.tonalIcon(
                              onPressed: _savingWorldview
                                  ? null
                                  : () => _saveCurrentWorldviewToLibrary(),
                              icon: _savingWorldview
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const AppSvgIcon('bookmark', size: 16),
                              label: Text(_savingWorldview
                                  ? l10n.partSaving
                                  : l10n.saveToLibraryNow),
                              style: FilledButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          ),
                        ],
                      )
                    : childContent,
              );
            },
          ),
        ],
      ),
    );
  }
}
