import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider;

import '../../../../core/feedback/app_feedback.dart';
import '../../../../core/localization/dialogue_level_localization.dart';
import '../../../../core/localization/app_error_localizer.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_page_scaffold.dart';
import '../../../../core/router/app_router.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../l10n/generated/app_localizations_zh.dart';
import '../../../../models/dialogue_level.dart';
import '../../../../application/narrative/context_weighting.dart';
import '../../../../providers/riverpod_providers.dart';
import 'prompt_preview_page.dart';

AppLocalizations _l10n(BuildContext context) =>
    AppLocalizations.of(context) ?? AppLocalizationsZh();

/// 现代化提示词与模型推演参数设定主屏
/// 提供完全纯净的白板设定环境，支持对话密度分级、全局系统提示词、作者注注入与实时装配预览
class PromptSettingsScreen extends ConsumerStatefulWidget {
  const PromptSettingsScreen({super.key});

  @override
  ConsumerState<PromptSettingsScreen> createState() =>
      _PromptSettingsScreenState();
}

class _PresetTransferPage extends ConsumerStatefulWidget {
  const _PresetTransferPage({required this.isImport});

  final bool isImport;

  @override
  ConsumerState<_PresetTransferPage> createState() =>
      _PresetTransferPageState();
}

class _PresetTransferPageState extends ConsumerState<_PresetTransferPage> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n(context);
    final json = widget.isImport
        ? ''
        : ref.read(chatProvider).libraryProvider.exportPresetsToJson();
    return AppPageScaffold(
      title: widget.isImport ? l10n.importPresetTitle : l10n.exportPresetTitle,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.isImport)
            TextField(
              key: const Key('preset-import-input'),
              controller: _controller,
              minLines: 8,
              maxLines: 20,
              decoration: InputDecoration(
                labelText: l10n.presetJsonLabel,
                border: const OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            )
          else
            SelectableText(json),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: () async {
                if (widget.isImport) {
                  final input = _controller.text.trim();
                  if (input.isEmpty) {
                    setState(() => _error = l10n.presetJsonEmptyError);
                    return;
                  }
                  try {
                    final result = ref
                        .read(chatProvider)
                        .libraryProvider
                        .importPresetsFromJson(input);
                    if (!context.mounted) return;
                    AppFeedback.success(context, result);
                    Navigator.of(context).pop();
                  } catch (error) {
                    setState(() => _error = l10n.presetImportFailed(
                        localizeAppError(l10n, asAppDomainError(error))));
                  }
                } else {
                  await Clipboard.setData(ClipboardData(text: json));
                  if (context.mounted) {
                    AppFeedback.success(context, l10n.presetJsonCopied);
                  }
                }
              },
              icon: Icon(widget.isImport
                  ? Icons.file_download_outlined
                  : Icons.copy_rounded),
              label: Text(
                  widget.isImport ? l10n.importAction : l10n.copyAllAction),
            ),
          ),
        ],
      ),
    );
  }
}

class _PromptSettingsScreenState extends ConsumerState<PromptSettingsScreen> {
  late TextEditingController _systemPromptController;
  late TextEditingController _authorsNoteController;
  late int _noteDepth;
  late int _noteFrequency;
  late ContextWeightProfile _contextProfile;

  @override
  void initState() {
    super.initState();
    final provider = ref.read(chatProvider);
    _systemPromptController = TextEditingController(
      text: provider.settingsProvider.customSystemPrompt,
    );
    _authorsNoteController = TextEditingController(
      text: provider.settingsProvider.authorsNote,
    );
    _noteDepth = provider.authorsNoteDepth;
    _noteFrequency = provider.authorsNoteFrequency;
    _contextProfile = provider.settingsProvider.contextWeightProfile;
  }

  @override
  void dispose() {
    _systemPromptController.dispose();
    _authorsNoteController.dispose();
    super.dispose();
  }

  void _showPromptPreview() {
    PromptPreviewPage.show(
      context,
      ref.read(chatProvider).getFullPromptPreview(),
    );
  }

  void _showPresetImportDialog() {
    AppRouter.push<void>(
      context,
      pageBuilder: (_) => const _PresetTransferPage(isImport: true),
    );
  }

  void _showPresetExport() {
    AppRouter.push<void>(
      context,
      pageBuilder: (_) => const _PresetTransferPage(isImport: false),
    );
  }

  String _sourceLabel(AppLocalizations l10n, ContextSourceId id) =>
      switch (id) {
        ContextSourceId.userControl => l10n.contextSourceUserControl,
        ContextSourceId.currentScene => l10n.contextSourceCurrentScene,
        ContextSourceId.characterProfile => l10n.contextSourceCharacterProfile,
        ContextSourceId.runtimeCharacterState =>
          l10n.contextSourceRuntimeCharacterState,
        ContextSourceId.worldview => l10n.contextSourceWorldview,
        ContextSourceId.runtimeWorldState =>
          l10n.contextSourceRuntimeWorldState,
        ContextSourceId.recentDialogue => l10n.contextSourceRecentDialogue,
        ContextSourceId.historicalSummary =>
          l10n.contextSourceHistoricalSummary,
        ContextSourceId.archiveRetrieval => l10n.contextSourceArchiveRetrieval,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final provider = ref.watch(chatProvider);
    final l10n = _l10n(context);

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Text(l10n.promptSettingsTitle),
        centerTitle: false,
        actions: MediaQuery.sizeOf(context).width < 600
            ? [
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'preview') _showPromptPreview();
                    if (value == 'import') _showPresetImportDialog();
                    if (value == 'export') _showPresetExport();
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                        value: 'preview',
                        child: Text(l10n.previewPromptAction)),
                    PopupMenuItem(
                        value: 'import', child: Text(l10n.importPresets)),
                    PopupMenuItem(
                        value: 'export', child: Text(l10n.exportPresets)),
                  ],
                ),
              ]
            : [
                IconButton(
                  icon: const Icon(Icons.file_download_outlined, size: 20),
                  tooltip: l10n.importPresets,
                  onPressed: _showPresetImportDialog,
                ),
                IconButton(
                  icon: const Icon(Icons.file_upload_outlined, size: 20),
                  tooltip: l10n.exportPresets,
                  onPressed: _showPresetExport,
                ),
                FilledButton.tonalIcon(
                  onPressed: _showPromptPreview,
                  icon: const Icon(Icons.preview_rounded, size: 16),
                  label: Text(l10n.previewPromptAction),
                ),
                const SizedBox(width: 8),
              ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          24 + MediaQuery.of(context).viewInsets.bottom,
        ),
        children: [
          // 对话分级与字数预算
          AppCard(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.format_size_rounded,
                        color: colorScheme.primary, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(
                      l10n.dialogueLevelSectionTitle,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    )),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.dialogueLevelSectionSubtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                ...DialogueLevel.values.map((level) {
                  final selected =
                      level.id == provider.settingsProvider.dialogueLevel.id;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () =>
                          provider.settingsProvider.setDialogueLevel(level),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: selected
                              ? colorScheme.primaryContainer
                                  .withValues(alpha: 0.45)
                              : colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: selected
                                ? colorScheme.primary.withValues(alpha: 0.5)
                                : colorScheme.outlineVariant
                                    .withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              selected
                                  ? Icons.radio_button_checked_rounded
                                  : Icons.radio_button_unchecked_rounded,
                              size: 18,
                              color: selected
                                  ? colorScheme.primary
                                  : colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${level.id} · ${localizedDialogueLevelLabel(level, l10n)}',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${localizedDialogueLevelWordRange(level, l10n)} · ${localizedDialogueLevelDescription(level, l10n)}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          AppCard(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.contextWeightsTitle,
                    style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                DropdownButton<String>(
                  value: _contextProfile.presetId,
                  isExpanded: true,
                  items: [
                    DropdownMenuItem(
                        value: 'balanced',
                        child: Text(l10n.contextWeightsBalanced)),
                    DropdownMenuItem(
                        value: 'highControl',
                        child: Text(l10n.contextWeightsHighControl)),
                    DropdownMenuItem(
                        value: 'immersive',
                        child: Text(l10n.contextWeightsImmersive)),
                    DropdownMenuItem(
                        value: 'custom',
                        child: Text(l10n.contextWeightsCustom)),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    final profile = switch (value) {
                      'highControl' => ContextWeightPresets.highControl,
                      'immersive' => ContextWeightPresets.immersive,
                      _ => ContextWeightPresets.balanced,
                    };
                    setState(() => _contextProfile = profile);
                    provider.settingsProvider.setContextWeightProfile(profile);
                  },
                ),
                ExpansionTile(
                  title: Text(l10n.contextWeightsAdjust),
                  children: [
                    for (final id in ContextSourceId.values)
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final narrow = constraints.maxWidth < 420;
                          final label = Text(_sourceLabel(l10n, id),
                              maxLines: 1, overflow: TextOverflow.ellipsis);
                          final slider = Slider(
                            value: _contextProfile[id].toDouble(),
                            min: 0,
                            max: 100,
                            divisions: 100,
                            label: '${_contextProfile[id]}',
                            onChanged: (value) {
                              final weights = {
                                ..._contextProfile.weights,
                                id: value.round()
                              };
                              final profile = _contextProfile.copyWith(
                                  presetId: 'custom', weights: weights);
                              setState(() => _contextProfile = profile);
                              provider.settingsProvider
                                  .setContextWeightProfile(profile);
                            },
                          );
                          final value = SizedBox(
                              width: 36, child: Text('${_contextProfile[id]}'));
                          return narrow
                              ? Column(children: [
                                  Align(
                                      alignment: Alignment.centerLeft,
                                      child: label),
                                  Row(children: [
                                    Expanded(child: slider),
                                    value
                                  ]),
                                ])
                              : Row(children: [
                                  Expanded(child: label),
                                  Expanded(flex: 2, child: slider),
                                  value
                                ]);
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // 系统全局提示词 (System Prompt - 纯白板设计)
          AppCard(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.terminal_rounded,
                        color: colorScheme.primary, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(
                      l10n.systemPromptSectionTitle,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    )),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.systemPromptSectionSubtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _systemPromptController,
                  maxLines: 8,
                  decoration: InputDecoration(
                    hintText: l10n.systemPromptHint,
                    filled: true,
                    fillColor: colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.3),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  children: [
                    Text(
                      l10n.charCountLabel(_systemPromptController.text.length),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    TextButton(
                      onPressed: _systemPromptController.text.isNotEmpty
                          ? () {
                              _systemPromptController.clear();
                              provider.settingsProvider
                                  .setCustomSystemPrompt('');
                              setState(() {});
                            }
                          : null,
                      child: Text(l10n.clearAction),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonalIcon(
                      onPressed: () {
                        provider.settingsProvider.setCustomSystemPrompt(
                          _systemPromptController.text.trim(),
                        );
                        AppFeedback.success(context, l10n.systemPromptSaved);
                      },
                      icon: const Icon(Icons.save_rounded, size: 16),
                      label: Text(l10n.savePromptAction),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // 作者注释 (Author's Note - 动态深度注入)
          AppCard(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.edit_note_rounded,
                        color: colorScheme.primary, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(
                      l10n.authorsNoteSectionTitle,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    )),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.authorsNoteSectionSubtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _authorsNoteController,
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText: l10n.authorsNoteHint,
                    filled: true,
                    fillColor: colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.3),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.injectionDepth,
                        style: const TextStyle(fontSize: 14)),
                    Row(children: [
                      Expanded(
                          child: Slider(
                        value: _noteDepth.toDouble(),
                        min: 0,
                        max: 10,
                        divisions: 10,
                        label: _noteDepth == 0
                            ? l10n.depthFollowSystem
                            : l10n.depthBeforeRound(_noteDepth),
                        onChanged: (v) =>
                            setState(() => _noteDepth = v.round()),
                      )),
                      SizedBox(
                          width: 32,
                          child: Text('$_noteDepth',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700))),
                    ]),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.injectionFrequency,
                        style: const TextStyle(fontSize: 14)),
                    Row(children: [
                      Expanded(
                          child: Slider(
                        value: _noteFrequency.toDouble(),
                        min: 1,
                        max: 10,
                        divisions: 9,
                        label: l10n.freqEveryRound(_noteFrequency),
                        onChanged: (v) =>
                            setState(() => _noteFrequency = v.round()),
                      )),
                      SizedBox(
                          width: 32,
                          child: Text('$_noteFrequency',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700))),
                    ]),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonalIcon(
                    onPressed: () {
                      provider.settingsProvider
                          .setAuthorsNote(_authorsNoteController.text.trim());
                      provider.settingsProvider
                          .setAuthorsNoteConfig(_noteDepth, _noteFrequency);
                      AppFeedback.success(context, l10n.authorsNoteSaved);
                    },
                    icon: const Icon(Icons.save_rounded, size: 16),
                    label: Text(l10n.saveNoteConfigAction),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
