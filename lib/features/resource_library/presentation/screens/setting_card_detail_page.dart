import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../application/setting_cards/setting_card_reference_input.dart';
import '../../../../application/setting_cards/setting_card_service.dart';
import '../../../../core/feedback/app_feedback.dart';
import '../../../../core/localization/app_error_localizer.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_read_aloud.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../domain/read_aloud/read_aloud_contracts.dart';
import '../../../../domain/setting_cards/setting_card.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../l10n/generated/app_localizations_zh.dart';
import '../../../../models/generation_stage_progress.dart';
import '../../../../models/generation_task_handle.dart';
import '../../../../providers/riverpod_providers.dart';
import '../resolvers/resource_presentation_resolver.dart';
import '../widgets/setting_card_length_selector.dart';
import '../widgets/setting_card_reference_editor.dart';
import '../widgets/setting_card_relationships_section.dart';

AppLocalizations _l10n(BuildContext context) =>
    AppLocalizations.of(context) ?? AppLocalizationsZh();

/// Describes a setting-card generation failure for user display.
///
/// Declared on this page's library so the adventure wizard — which imports this
/// page but cannot import this feature's helpers directly — reuses the exact
/// same sanitizer instead of duplicating protocol scrubbing.
/// Formats generation progress for callers that only import this page (the
/// adventure wizard). Keeps one formatter shared with the create/detail rows.
String formatSettingCardGenerationProgressLabel(
  AppLocalizations l10n,
  GenerationStageProgress progress,
) =>
    formatSettingCardGenerationProgress(l10n, progress);

String describeSettingCardGenerationError(
  Object error,
  AppLocalizations l10n,
) {
  if (error is SettingCardGenerationException) {
    return sanitizeSettingCardGenerationMessage(
      error.message,
      fallback: l10n.settingCardGenerateFailed,
    );
  }
  return ResourcePresentationResolver.sanitize(
    localizeAppError(l10n, asAppDomainError(error)),
    fallback: l10n.settingCardGenerateFailed,
  );
}

/// Single-document editor for a lightweight setting card.
///
/// One card is one document: name, summary and a Markdown/JSON body. Generation
/// is a single request, not a sharded pipeline, and reads go straight to the
/// card instead of the retired resource tree.
final class SettingCardDetailPage extends ConsumerStatefulWidget {
  const SettingCardDetailPage({
    super.key,
    required this.cardId,
    this.legacyId,
    this.embedded = false,
    this.onDeleted,
  });

  final String cardId;

  /// Legacy row id used only when [cardId] does not resolve.
  final String? legacyId;

  /// True when the page is rendered inside a master-detail workspace.
  final bool embedded;

  final Future<void> Function(String message)? onDeleted;

  @override
  ConsumerState<SettingCardDetailPage> createState() =>
      _SettingCardDetailPageState();
}

final class _SettingCardDetailPageState
    extends ConsumerState<SettingCardDetailPage> {
  final _name = TextEditingController();
  final _summary = TextEditingController();
  final _content = TextEditingController();

  SettingCard? _card;
  bool _loading = true;
  bool _saving = false;
  bool _generating = false;
  SettingCardGenerationLength _length = SettingCardGenerationLength.standard;
  final _customLength = TextEditingController();

  /// Instruction field for the generate dialog.
  ///
  /// Owned by the page, not the dialog: disposing a dialog-local controller the
  /// moment the route pops races the exit animation, which keeps rebuilding the
  /// text field and would touch a disposed controller.
  final _generateInstruction = TextEditingController();
  GenerationStageProgress? _progress;
  GenerationTaskHandle? _taskHandle;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    // Leaving the page must stop a still-running generation so it cannot write
    // into a disposed state; cancelling a finished request is a no-op.
    unawaited(_taskHandle?.cancel());
    _name.dispose();
    _summary.dispose();
    _content.dispose();
    _customLength.dispose();
    _generateInstruction.dispose();
    super.dispose();
  }

  String _describeError(Object error) => ResourcePresentationResolver.sanitize(
        localizeAppError(_l10n(context), asAppDomainError(error)),
        fallback: _l10n(context).errorUnknown,
      );

  Future<void> _load() async {
    try {
      final card = await ref
          .read(settingCardServiceProvider)
          .find(widget.cardId, legacyId: widget.legacyId);
      if (!mounted) return;
      setState(() {
        _card = card;
        _loading = false;
        _loadError = card == null ? 'missing' : null;
        if (card != null) {
          _name.text = card.name;
          _summary.text = card.summary;
          _content.text = card.content;
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = _describeError(error);
      });
    }
  }

  bool get _dirty {
    final card = _card;
    if (card == null) return false;
    return _name.text != card.name ||
        _summary.text != card.summary ||
        _content.text != card.content;
  }

  Future<void> _save() async {
    final card = _card;
    if (card == null || _saving) return;
    setState(() => _saving = true);
    try {
      final updated = await ref.read(settingCardServiceProvider).save(
            id: card.id,
            name: _name.text.trim(),
            summary: _summary.text.trim(),
            content: _content.text,
          );
      if (!mounted) return;
      setState(() => _card = updated);
      AppFeedback.success(context, _l10n(context).settingCardSaved);
    } catch (error) {
      if (mounted) {
        AppFeedback.error(context, _describeError(error));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  int get _maximumCharacters => SettingCardLengthSelector.maximumCharactersFor(
        _card?.kind ?? SettingCardKind.worldview,
      );

  /// Resolves the target the picker represents, or null when no explicit
  /// length should be sent (default preset, or an unusable custom number).
  int? _resolveTargetCharacters(SettingCardGenerationLength length) {
    if (length != SettingCardGenerationLength.custom) {
      return targetCharactersFor(
        _card?.kind ?? SettingCardKind.worldview,
        length,
      );
    }
    return SettingCardLengthSelector.parseCustomCharacters(
      _customLength.text,
      maximumCharacters: _maximumCharacters,
    );
  }

  Future<void> _generate() async {
    final card = _card;
    if (card == null || _generating) return;
    final request = await _askInstruction();
    if (request == null || !mounted) return;
    final l10n = _l10n(context);
    final targetCharacters = _resolveTargetCharacters(request.length);
    final handle = GenerationTaskHandle();
    setState(() {
      _generating = true;
      _length = request.length;
      _progress = null;
      _taskHandle = handle;
    });
    try {
      final updated = await ref.read(settingCardServiceProvider).generate(
            id: card.id,
            instruction: request.instruction,
            reference: request.reference,
            targetTotalCharacters: targetCharacters,
            taskHandle: handle,
            onProgress: (progress) {
              if (!mounted) return;
              setState(() => _progress = progress);
            },
          );
      if (handle.isCancelled) {
        if (mounted) {
          AppFeedback.info(context, l10n.settingCardGenerationCancelled);
        }
        return;
      }
      if (!mounted) return;
      setState(() {
        _card = updated;
        _name.text = updated.name;
        _summary.text = updated.summary;
        _content.text = updated.content;
      });
    } on SettingCardGenerationException catch (error) {
      if (!mounted) return;
      if (handle.isCancelled) {
        AppFeedback.info(context, l10n.settingCardGenerationCancelled);
        return;
      }
      AppFeedback.error(
        context,
        sanitizeSettingCardGenerationMessage(
          error.message,
          fallback: l10n.settingCardGenerateFailed,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      if (handle.isCancelled) {
        AppFeedback.info(context, l10n.settingCardGenerationCancelled);
        return;
      }
      debugPrint('[setting-card-detail] generation failed: $error.runtimeType');
      AppFeedback.error(context, l10n.settingCardGenerateFailed);
    } finally {
      if (mounted) {
        setState(() {
          _generating = false;
          _progress = null;
          _taskHandle = null;
        });
      }
    }
  }

  void _cancelGeneration() {
    unawaited(_taskHandle?.cancel());
  }

  bool get _canRestore =>
      _card?.metadata[SettingCardService.previousSnapshotKey] is Map;

  Future<void> _restore() async {
    final card = _card;
    if (card == null || _saving || _generating) return;
    final l10n = _l10n(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.settingCardRestoreConfirmTitle),
        content: Text(l10n.settingCardRestoreConfirmMessage),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancelAction),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.settingCardRestorePrevious),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    try {
      final restored = await ref
          .read(settingCardServiceProvider)
          .restorePreviousSnapshot(card.id);
      if (!mounted) return;
      if (restored == null) {
        AppFeedback.info(context, l10n.settingCardRestoreUnavailable);
        return;
      }
      setState(() {
        _card = restored;
        _name.text = restored.name;
        _summary.text = restored.summary;
        _content.text = restored.content;
      });
      AppFeedback.success(context, l10n.settingCardRestored);
    } catch (error) {
      if (mounted) AppFeedback.error(context, _describeError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<
      ({
        String instruction,
        SettingCardReferenceInput? reference,
        SettingCardGenerationLength length,
      })?> _askInstruction() async {
    final controller = _generateInstruction..text = _card?.summary ?? '';
    final l10n = _l10n(context);
    var mode = SettingCardReferenceMode.paste;
    SettingCardReferenceInput? reference;
    var length = _length;
    final result = await showDialog<
        ({
          String instruction,
          SettingCardReferenceInput? reference,
          SettingCardGenerationLength length,
        })>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) => ListenableBuilder(
          listenable: _customLength,
          builder: (context, _) => AlertDialog(
            title: Text(l10n.settingCardGenerateAction),
            // scrollable keeps the dialog usable at 320px and when the soft
            // keyboard shrinks the available height; the editor adds a second
            // field group below the instruction.
            scrollable: true,
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                AppTextField(
                  key: const Key('setting-card-generate-instruction'),
                  controller: controller,
                  label: l10n.settingCardGenerateHint,
                  maxLines: 4,
                  minLines: 3,
                  autofocus: true,
                ),
                const SizedBox(height: AppSpacing.lg),
                SettingCardLengthSelector(
                  key: const Key('setting-card-generate-length'),
                  value: length,
                  customCharactersController: _customLength,
                  kind: _card?.kind ?? SettingCardKind.worldview,
                  onChanged: (value) => setLocal(() => length = value),
                ),
                const SizedBox(height: AppSpacing.lg),
                SettingCardReferenceEditor(
                  mode: mode,
                  onModeChanged: (value) => setLocal(() => mode = value),
                  onChanged: (value) => reference = value,
                ),
              ],
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(l10n.cancelAction),
              ),
              FilledButton(
                key: const Key('setting-card-generate-confirm'),
                // A custom target outside the supported range cannot be sent,
                // so confirm stays disabled until the field is usable.
                onPressed: length == SettingCardGenerationLength.custom &&
                        _resolveTargetCharacters(length) == null
                    ? null
                    : () => Navigator.of(dialogContext).pop((
                          instruction: controller.text.trim(),
                          reference: reference,
                          length: length,
                        )),
                child: Text(l10n.settingCardGenerateAction),
              ),
            ],
          ),
        ),
      ),
    );
    return result;
  }

  Future<void> _delete() async {
    final card = _card;
    if (card == null) return;
    final l10n = _l10n(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.settingCardDeleteConfirmTitle),
        content: Text(l10n.settingCardDeleteConfirmMessage),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancelAction),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.deleteAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref.read(settingCardServiceProvider).delete(card.id);
    if (!mounted) return;
    if (widget.onDeleted != null) {
      await widget.onDeleted!(l10n.resourceMovedToTrash);
    }
    if (!widget.embedded && mounted) {
      Navigator.of(context).pop<String>(l10n.resourceMovedToTrash);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final card = _card;
    if (card == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Text(_loadError ?? _l10n(context).resourceNoMatches),
        ),
      );
    }
    final body = _buildBody(context, card);
    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(
          title: Text(card.name.trim().isEmpty
              ? _l10n(context).resourceUnnamed
              : card.name)),
      body: SafeArea(child: body),
    );
  }

  Widget _buildBody(BuildContext context, SettingCard card) {
    final l10n = _l10n(context);
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal = constraints.maxWidth >= 600;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (horizontal)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      flex: 3,
                      child: AppTextField(
                        key: const Key('setting-card-name'),
                        controller: _name,
                        label: l10n.settingCardNameLabel,
                        enabled: !_generating,
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      flex: 2,
                      child: AppTextField(
                        key: const Key('setting-card-summary'),
                        controller: _summary,
                        label: l10n.resourceSummaryOptionalLabel,
                        enabled: !_generating,
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                )
              else ...<Widget>[
                AppTextField(
                  key: const Key('setting-card-name'),
                  controller: _name,
                  label: l10n.settingCardNameLabel,
                  enabled: !_generating,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  key: const Key('setting-card-summary'),
                  controller: _summary,
                  label: l10n.resourceSummaryOptionalLabel,
                  enabled: !_generating,
                  onChanged: (_) => setState(() {}),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              _buildActions(context, card),
              if (card.kind != SettingCardKind.worldview) ...<Widget>[
                const SizedBox(height: AppSpacing.lg),
                SettingCardRelationshipsSection(card: card),
              ],
              if (_generating) ...<Widget>[
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: <Widget>[
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        key: const Key('setting-card-generate-progress'),
                        _progress == null
                            ? l10n.settingCardGenerateAction
                            : formatSettingCardGenerationProgress(
                                l10n,
                                _progress!,
                              ),
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    key: const Key('setting-card-generate-cancel'),
                    onPressed: _cancelGeneration,
                    child: Text(l10n.settingCardGenerationCancelAction),
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              AppTextField(
                key: const Key('setting-card-content'),
                controller: _content,
                label: l10n.settingCardContentLabel,
                hintText: l10n.settingCardContentHint,
                maxLines: null,
                minLines: 14,
                enabled: !_generating,
                keyboardType: TextInputType.multiline,
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActions(BuildContext context, SettingCard card) {
    final l10n = _l10n(context);
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        FilledButton(
          key: const Key('setting-card-save'),
          onPressed: _saving || _generating || !_dirty ? null : _save,
          child: Text(l10n.saveAction),
        ),
        OutlinedButton(
          key: const Key('setting-card-generate'),
          onPressed: _saving || _generating ? null : _generate,
          child: Text(l10n.settingCardGenerateAction),
        ),
        if (_canRestore)
          OutlinedButton(
            key: const Key('setting-card-restore-previous'),
            onPressed: _saving || _generating ? null : _restore,
            child: Text(l10n.settingCardRestorePrevious),
          ),
        AppReadAloudButton(
          sourceId: card.id,
          sourceType: ReadAloudSourceType.generic,
          text: _content.text,
          label: card.name,
        ),
        TextButton(
          key: const Key('setting-card-delete'),
          onPressed: _saving || _generating ? null : _delete,
          child: Text(l10n.deleteAction),
        ),
      ],
    );
  }
}
