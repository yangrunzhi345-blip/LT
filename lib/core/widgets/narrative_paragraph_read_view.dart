import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_svg_icon.dart';
import '../../../domain/read_aloud/read_aloud_contracts.dart';
import '../../../domain/read_aloud/read_aloud_paragraphs.dart';
import '../../../domain/tts/speech_plan.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../l10n/generated/app_localizations_en.dart';
import '../../../providers/riverpod_providers.dart';

/// Paragraph-aware narrative presentation.
///
/// Splits the visible narrative into paragraphs and lets the user read a single
/// paragraph or start from a paragraph, using the global read-aloud authority.
/// The paragraph currently being read is marked with a lightweight accent
/// surface (never a large color block) and the page is not force-scrolled.
///
/// Paragraph chunk ids are `"<baseId>#p<i>"`, so [ReadAloudState.isSpeakingChunk]
/// can map "now reading" back to a paragraph.
class NarrativeParagraphReadView extends ConsumerStatefulWidget {
  const NarrativeParagraphReadView({
    super.key,
    required this.baseId,
    required this.text,
    required this.sourceType,
    this.label,
    this.speakerContext = const NarrativeSpeakerContext.empty(),
    this.textStyle,
    this.padding = const EdgeInsets.symmetric(vertical: AppSpacing.sm),
  });

  final String baseId;
  final String text;
  final ReadAloudSourceType sourceType;
  final String? label;
  final NarrativeSpeakerContext speakerContext;
  final TextStyle? textStyle;
  final EdgeInsetsGeometry padding;

  static String chunkIdFor(String baseId, int index) =>
      ReadAloudParagraphs.chunkIdFor(baseId, index);

  /// Splits [text] into non-empty paragraphs on blank lines.
  static List<String> splitParagraphs(String text) =>
      ReadAloudParagraphs.split(text);

  @override
  ConsumerState<NarrativeParagraphReadView> createState() =>
      _NarrativeParagraphReadViewState();
}

class _NarrativeParagraphReadViewState
    extends ConsumerState<NarrativeParagraphReadView> {
  int? _hovered;

  @override
  Widget build(BuildContext context) {
    final paragraphs = NarrativeParagraphReadView.splitParagraphs(widget.text);
    if (paragraphs.isEmpty) return const SizedBox.shrink();
    final controller = ref.watch(readAloudControllerProvider);
    final state = controller.state;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (var i = 0; i < paragraphs.length; i++)
          Builder(
            builder: (context) {
              final chunkId =
                  NarrativeParagraphReadView.chunkIdFor(widget.baseId, i);
              final active = state.isSpeakingChunk(chunkId);
              return MouseRegion(
                onEnter: (_) => setState(() => _hovered = i),
                onExit: (_) => setState(() {
                  if (_hovered == i) _hovered = null;
                }),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onLongPress: () => _showActions(context, i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: widget.padding,
                    decoration: active
                        ? BoxDecoration(
                            color: scheme.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(4),
                          )
                        : null,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          paragraphs[i],
                          style: widget.textStyle ??
                              theme.textTheme.bodyMedium?.copyWith(height: 1.8),
                        ),
                        if (_hovered == i)
                          _ParagraphActions(
                            key: ValueKey('paragraph-actions-$i'),
                            onReadThis: () => _read(i, only: true),
                            onReadFrom: () => _read(i, only: false),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  Future<void> _read(int index, {required bool only}) async {
    final paragraphs = NarrativeParagraphReadView.splitParagraphs(widget.text);
    if (index < 0 || index >= paragraphs.length) return;
    final start = index;
    final end = only ? index + 1 : paragraphs.length;
    final sources = <ReadAloudSource>[
      for (var i = start; i < end; i++)
        ReadAloudSource(
          id: NarrativeParagraphReadView.chunkIdFor(widget.baseId, i),
          text: paragraphs[i],
          label: widget.label,
          speakerContext: widget.speakerContext,
        ),
    ];
    await ref.read(readAloudControllerProvider).play(
          sessionId: widget.baseId,
          sourceType: widget.sourceType,
          sources: sources,
        );
  }

  Future<void> _showActions(BuildContext context, int index) async {
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsEn();
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const AppSvgIcon('read_aloud', size: 20),
              title: Text(l10n.readAloudParagraph),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _read(index, only: true);
              },
            ),
            ListTile(
              leading: const AppSvgIcon('read_aloud', size: 20),
              title: Text(l10n.readAloudFromParagraph),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _read(index, only: false);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ParagraphActions extends StatelessWidget {
  const _ParagraphActions({
    super.key,
    required this.onReadThis,
    required this.onReadFrom,
  });

  final VoidCallback onReadThis;
  final VoidCallback onReadFrom;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsEn();
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Wrap(
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        children: <Widget>[
          TextButton.icon(
            onPressed: onReadThis,
            icon: const AppSvgIcon('read_aloud', size: 16),
            label: Text(l10n.readAloudParagraph),
          ),
          TextButton.icon(
            onPressed: onReadFrom,
            icon: const AppSvgIcon('forward', size: 16),
            label: Text(l10n.readAloudFromParagraph),
          ),
        ],
      ),
    );
  }
}
