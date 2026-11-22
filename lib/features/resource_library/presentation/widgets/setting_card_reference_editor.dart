import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../application/setting_cards/setting_card_context_budgeter.dart';
import '../../../../application/setting_cards/setting_card_reference_input.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_select.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../domain/setting_cards/setting_card.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../l10n/generated/app_localizations_zh.dart';
import '../../../../providers/riverpod_providers.dart';

AppLocalizations _l10n(BuildContext context) =>
    AppLocalizations.of(context) ?? AppLocalizationsZh();

/// Collects one reference source for setting-card generation.
///
/// The three modes are mutually exclusive at generation time, so the widget
/// emits a single [SettingCardReferenceInput] for whichever mode is active and
/// reports null when that mode has no content. Each mode keeps its own
/// controllers in this one State so switching modes never clears text the user
/// already typed.
///
/// The active [mode] is owned by the page so it can persist across rebuilds;
/// the widget stays the single place that knows how a mode maps to generation
/// input.
final class SettingCardReferenceEditor extends ConsumerStatefulWidget {
  const SettingCardReferenceEditor({
    super.key,
    required this.mode,
    required this.onModeChanged,
    required this.onChanged,
    this.enabled = true,
  });

  /// Active reference mode, controlled by the page.
  final SettingCardReferenceMode mode;

  /// Called when the user picks a different mode.
  final ValueChanged<SettingCardReferenceMode> onModeChanged;

  /// Emits the active mode's reference, or null when it is empty.
  final ValueChanged<SettingCardReferenceInput?> onChanged;

  final bool enabled;

  @override
  ConsumerState<SettingCardReferenceEditor> createState() =>
      _SettingCardReferenceEditorState();
}

final class _SettingCardReferenceEditorState
    extends ConsumerState<SettingCardReferenceEditor> {
  final _paste = TextEditingController();
  final _fileName = TextEditingController();
  final _fileContent = TextEditingController();
  String _existingCardId = '';

  List<SettingCard> _existingCards = const <SettingCard>[];
  bool _loadingCards = true;
  bool _cardsFailed = false;

  @override
  void initState() {
    super.initState();
    // Load once up front: the list is small and the picker must be ready the
    // moment the user switches to the existing-card mode.
    _loadExistingCards();
  }

  @override
  void dispose() {
    _paste.dispose();
    _fileName.dispose();
    _fileContent.dispose();
    super.dispose();
  }

  Future<void> _loadExistingCards() async {
    try {
      final cards = await ref.read(settingCardServiceProvider).list();
      if (!mounted) return;
      setState(() {
        _existingCards = cards;
        _loadingCards = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cardsFailed = true;
        _loadingCards = false;
      });
    }
  }

  SettingCardReferenceInput? _inputFor(SettingCardReferenceMode mode) {
    switch (mode) {
      case SettingCardReferenceMode.paste:
        if (_paste.text.trim().isEmpty) return null;
        return SettingCardReferenceInput(
          mode: SettingCardReferenceMode.paste,
          text: _paste.text,
        );
      case SettingCardReferenceMode.file:
        if (_fileContent.text.trim().isEmpty) return null;
        return SettingCardReferenceInput(
          mode: SettingCardReferenceMode.file,
          label: _fileName.text.trim(),
          text: _fileContent.text,
        );
      case SettingCardReferenceMode.existingCard:
        if (_existingCardId.trim().isEmpty) return null;
        return SettingCardReferenceInput(
          mode: SettingCardReferenceMode.existingCard,
          sourceCardId: _existingCardId,
        );
    }
  }

  void _emit() => widget.onChanged(_inputFor(widget.mode));

  void _handleModeChanged(Set<SettingCardReferenceMode> selection) {
    final next = selection.first;
    widget.onModeChanged(next);
    // Emit against the new mode immediately: until the page rebuilds it still
    // holds the previous mode, so a stale non-null reference would leak the
    // previous mode's text into generation.
    widget.onChanged(_inputFor(next));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          l10n.settingCardReferenceTitle,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        LayoutBuilder(
          builder: (context, constraints) {
            // A fixed three-segment row overflows at 320px once the text scale
            // grows. Below that budget the same choices stack as chips instead.
            final scaledFont = MediaQuery.textScalerOf(context).scale(14);
            if (constraints.maxWidth >= 360 && scaledFont <= 20) {
              return SegmentedButton<SettingCardReferenceMode>(
                key: const Key('setting-card-reference-mode'),
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: <ButtonSegment<SettingCardReferenceMode>>[
                  ButtonSegment<SettingCardReferenceMode>(
                    value: SettingCardReferenceMode.paste,
                    label: Text(l10n.settingCardReferencePaste),
                  ),
                  ButtonSegment<SettingCardReferenceMode>(
                    value: SettingCardReferenceMode.file,
                    label: Text(l10n.settingCardReferenceFile),
                  ),
                  ButtonSegment<SettingCardReferenceMode>(
                    value: SettingCardReferenceMode.existingCard,
                    label: Text(l10n.settingCardReferenceExisting),
                  ),
                ],
                selected: <SettingCardReferenceMode>{widget.mode},
                onSelectionChanged: widget.enabled ? _handleModeChanged : null,
              );
            }
            return Wrap(
              key: const Key('setting-card-reference-mode'),
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: <Widget>[
                for (final option in const <SettingCardReferenceMode>[
                  SettingCardReferenceMode.paste,
                  SettingCardReferenceMode.file,
                  SettingCardReferenceMode.existingCard,
                ])
                  ChoiceChip(
                    label: Text(_modeLabel(l10n, option)),
                    selected: widget.mode == option,
                    onSelected: widget.enabled
                        ? (_) => _handleModeChanged(<SettingCardReferenceMode>{
                              option,
                            })
                        : null,
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.md),
        ..._buildModeBody(context),
      ],
    );
  }

  List<Widget> _buildModeBody(BuildContext context) {
    final l10n = _l10n(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    switch (widget.mode) {
      case SettingCardReferenceMode.paste:
        return <Widget>[
          AppTextField(
            key: const Key('setting-card-reference-paste'),
            controller: _paste,
            hintText: l10n.settingCardReferencePasteHint,
            maxLines: 4,
            minLines: 3,
            enabled: widget.enabled,
            onChanged: (_) => setState(_emit),
          ),
          ..._lengthHint(context, _paste, l10n),
        ];
      case SettingCardReferenceMode.file:
        return <Widget>[
          AppTextField(
            key: const Key('setting-card-reference-file-name'),
            controller: _fileName,
            label: l10n.settingCardReferenceFileName,
            enabled: widget.enabled,
            onChanged: (_) => setState(_emit),
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            key: const Key('setting-card-reference-file-content'),
            controller: _fileContent,
            label: l10n.settingCardReferenceFileContent,
            hintText: l10n.settingCardReferenceFileHint,
            maxLines: 4,
            minLines: 3,
            enabled: widget.enabled,
            onChanged: (_) => setState(_emit),
          ),
          ..._lengthHint(context, _fileContent, l10n),
        ];
      case SettingCardReferenceMode.existingCard:
        if (_loadingCards) {
          return const <Widget>[
            SizedBox(height: 2, child: LinearProgressIndicator()),
          ];
        }
        if (_cardsFailed) {
          return <Widget>[
            Text(
              l10n.settingCardReferenceLoadFailed,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.error,
              ),
            ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: () {
                  setState(() {
                    _cardsFailed = false;
                    _loadingCards = true;
                  });
                  _loadExistingCards();
                },
                child: Text(l10n.retryAction),
              ),
            ),
          ];
        }
        if (_existingCards.isEmpty) {
          return <Widget>[
            Text(
              l10n.settingCardReferenceEmpty,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ];
        }
        return <Widget>[
          AppSelect<String>(
            key: const Key('setting-card-reference-existing'),
            label: l10n.settingCardReferenceSelectCard,
            value: _existingCardId.isEmpty ? null : _existingCardId,
            enabled: widget.enabled,
            items: <AppSelectItem<String>>[
              for (final card in _existingCards)
                AppSelectItem<String>(
                  value: card.id,
                  label: _cardLabel(l10n, card),
                ),
            ],
            onChanged: (value) {
              setState(() {
                _existingCardId = value ?? '';
                _emit();
              });
            },
          ),
        ];
    }
  }

  /// Character count plus the over-limit warning for a free-text input.
  ///
  /// File content is bounded by the same budget as a paste, so it must show the
  /// same warning instead of silently dropping the tail at generation time.
  List<Widget> _lengthHint(
    BuildContext context,
    TextEditingController controller,
    AppLocalizations l10n,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final length = controller.text.length;
    final overLimit =
        length > SettingCardContextBudgeter.maximumReferenceCharacters;
    return <Widget>[
      const SizedBox(height: AppSpacing.xs + 2),
      Text(
        l10n.settingCardReferenceCount(
          length,
          SettingCardContextBudgeter.maximumReferenceCharacters,
        ),
        style: theme.textTheme.bodySmall?.copyWith(
          color: overLimit ? colorScheme.error : colorScheme.onSurfaceVariant,
        ),
      ),
      if (overLimit) ...<Widget>[
        const SizedBox(height: AppSpacing.xs),
        Text(
          l10n.settingCardReferenceOverLimit,
          style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.error),
        ),
      ],
    ];
  }

  String _modeLabel(
    AppLocalizations l10n,
    SettingCardReferenceMode mode,
  ) =>
      switch (mode) {
        SettingCardReferenceMode.paste => l10n.settingCardReferencePaste,
        SettingCardReferenceMode.file => l10n.settingCardReferenceFile,
        SettingCardReferenceMode.existingCard =>
          l10n.settingCardReferenceExisting,
      };

  String _cardLabel(AppLocalizations l10n, SettingCard card) {
    final kind = switch (card.kind) {
      SettingCardKind.worldview => l10n.resourceTypeWorldview,
      SettingCardKind.character => l10n.resourceTypeCharacter,
      SettingCardKind.npc => l10n.resourceTypeNpc,
    };
    final name =
        card.name.trim().isEmpty ? l10n.resourceUnnamed : card.name.trim();
    return '$kind · $name';
  }
}
