import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../application/setting_cards/setting_card_service.dart';
import '../../../../core/feedback/app_feedback.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_read_aloud.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../domain/read_aloud/read_aloud_contracts.dart';
import '../../../../domain/setting_cards/setting_card.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../l10n/generated/app_localizations_zh.dart';
import '../../../../providers/riverpod_providers.dart';

AppLocalizations _l10n(BuildContext context) =>
    AppLocalizations.of(context) ?? AppLocalizationsZh();

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
  String _progressLabel = '';
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _summary.dispose();
    _content.dispose();
    super.dispose();
  }

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
        _loadError = error.toString();
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
        AppFeedback.error(context, error.toString());
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _generate() async {
    final card = _card;
    if (card == null || _generating) return;
    final instruction = await _askInstruction();
    if (instruction == null || !mounted) return;
    setState(() {
      _generating = true;
      _progressLabel = '';
    });
    try {
      final updated = await ref.read(settingCardServiceProvider).generate(
            id: card.id,
            instruction: instruction,
            onProgress: (stage, total, name) {
              if (!mounted) return;
              setState(() => _progressLabel = name);
            },
          );
      if (!mounted) return;
      setState(() {
        _card = updated;
        _name.text = updated.name;
        _summary.text = updated.summary;
        _content.text = updated.content;
      });
    } on SettingCardGenerationException {
      if (mounted) {
        AppFeedback.error(context, _l10n(context).settingCardGenerateFailed);
      }
    } finally {
      if (mounted) {
        setState(() {
          _generating = false;
          _progressLabel = '';
        });
      }
    }
  }

  Future<String?> _askInstruction() async {
    final controller = TextEditingController(text: _card?.summary ?? '');
    final l10n = _l10n(context);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.settingCardGenerateAction),
        content: AppTextField(
          key: const Key('setting-card-generate-instruction'),
          controller: controller,
          label: l10n.settingCardGenerateHint,
          maxLines: 4,
          minLines: 3,
          autofocus: true,
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.cancelAction),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: Text(l10n.settingCardGenerateAction),
          ),
        ],
      ),
    );
    controller.dispose();
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
                    Flexible(
                      child: Text(
                        _progressLabel.isEmpty
                            ? l10n.settingCardGenerateAction
                            : _progressLabel,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
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
