import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../application/resources/resource_autosave_service.dart';
import '../../../../domain/resources/resource_autosave.dart';
import '../../../../domain/resources/resource_contracts.dart';
import '../resource_studio_user_message.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../l10n/generated/app_localizations_zh.dart';

AppLocalizations _l10n(BuildContext context) =>
    AppLocalizations.of(context) ?? AppLocalizationsZh();

String _autosaveTriggerLabel(
  AutosaveFlushTrigger trigger,
  AppLocalizations l10n,
) =>
    switch (trigger) {
      AutosaveFlushTrigger.debounce => l10n.autosaveTriggerDebounce,
      AutosaveFlushTrigger.maxBufferedAge => l10n.autosaveTriggerMaxBufferedAge,
      AutosaveFlushTrigger.manual => l10n.autosaveTriggerManual,
      AutosaveFlushTrigger.pageLeave => l10n.autosaveTriggerPageLeave,
      AutosaveFlushTrigger.dispose => l10n.autosaveTriggerDispose,
      AutosaveFlushTrigger.cancel => l10n.autosaveTriggerCancel,
      AutosaveFlushTrigger.generationError =>
        l10n.autosaveTriggerGenerationError,
      AutosaveFlushTrigger.appLifecycle => l10n.autosaveTriggerAppLifecycle,
    };

/// Editable body of one Part, with debounced autosave.
///
/// Persistence rules this widget is responsible for:
/// - a keystroke only updates an in-memory buffer (`schedule`), so typing never
///   issues one SQLite write per character;
/// - a pause, a maximum buffered age, an explicit save, leaving the page, the
///   editor being disposed and the app losing focus all force a flush;
/// - the flush writes the draft journal first and the tree second, so a crash
///   in between leaves a recoverable draft rather than vanished text.
final class ResourceStudioPartEditor extends StatefulWidget {
  const ResourceStudioPartEditor({
    required this.resourceId,
    required this.partId,
    required this.partTitle,
    required this.initialContent,
    required this.updatedAt,
    required this.autosaveFactory,
    required this.onSaved,
    required this.onClose,
    super.key,
  });

  final ResourceId resourceId;
  final PartId partId;
  final String partTitle;
  final String initialContent;

  /// Optimistic-locking token the session starts from.
  ///
  /// Only a seed: after the first save the session owns the token, because only
  /// the session can advance it synchronously with its own write.
  final String updatedAt;

  final AutosaveServiceFactory autosaveFactory;

  /// Reports persisted content so the page can refresh what it displays.
  final void Function(String content) onSaved;

  final VoidCallback onClose;

  @override
  State<ResourceStudioPartEditor> createState() =>
      _ResourceStudioPartEditorState();
}

class _ResourceStudioPartEditorState extends State<ResourceStudioPartEditor>
    with WidgetsBindingObserver {
  late final AutosaveSession _autosave = widget.autosaveFactory();
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialContent);

  String _status = '';
  bool _hasConflict = false;
  bool _saving = false;
  bool _closing = false;

  /// True while an external write put this Part into an unresolved conflict
  /// (R2-M1): autosave is paused for the Part until the user picks a version.
  bool _hasUnresolvedConflict = false;

  /// True while the resolution actions run, so neither action double-fires.
  bool _resolvingConflict = false;

  /// True while the editor text is being synced to the live content after a
  /// 「放弃我的文本」 resolution; the programmatic change is not a keystroke.
  bool _syncingLiveContent = false;

  /// Draft a previous session left behind, offered to the user (P9-M2).
  ///
  /// Without this the journal row is unreachable: the editor shows the tree
  /// body, so text that never reached the tree would be invisible and would be
  /// overwritten by the next successful save.
  ResourceAutosaveDraft? _pendingDraft;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _autosave.onFlushed = _onFlushed;
    _controller.addListener(_onChanged);
    unawaited(_loadPendingDraft());
  }

  /// Classifies this resource's drafts and surfaces the one for this Part.
  Future<void> _loadPendingDraft() async {
    try {
      final outcomes = await _autosave.reconcilePendingDrafts(
        resourceId: widget.resourceId,
      );
      if (!mounted) return;
      final mine = outcomes
          .where((outcome) =>
              outcome.draft.partId == widget.partId &&
              outcome.disposition ==
                  AutosaveRecoveryDisposition.needsUserDecision)
          .firstOrNull;
      if (mine == null) return;
      setState(() {
        _pendingDraft = mine.draft;
        _status =
            '${_l10n(context).partEditorUnsavedDraftFound}（${mine.draft.updatedAtToken}）';
      });
    } catch (_) {
      // Recovery is best effort: a failure here must not block editing.
    }
  }

  void _restoreDraft() {
    final draft = _pendingDraft;
    if (draft == null) return;
    setState(() {
      _controller.text = draft.content;
      _pendingDraft = null;
      _status = _l10n(context).partEditorDraftLoaded;
    });
  }

  Future<void> _discardDraft() async {
    final draft = _pendingDraft;
    if (draft == null) return;
    await _autosave.discardDraft(draft);
    if (!mounted) return;
    setState(() {
      _pendingDraft = null;
      _status = _l10n(context).partEditorDraftDiscarded;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A backgrounded app may be killed without another callback, so the buffer
    // is written out on the way out instead of trusting a later dispose.
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        unawaited(_flush(AutosaveFlushTrigger.appLifecycle));
      case AppLifecycleState.resumed:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_onChanged);
    _controller.dispose();
    // Final flush: the debounce timer may still be armed, and dropping it here
    // is exactly the "exit with unsaved edits" bug this phase removes.
    unawaited(_autosave.dispose());
    super.dispose();
  }

  void _onChanged() {
    if (_closing || _syncingLiveContent) return;
    _autosave.schedule(
      resourceId: widget.resourceId,
      partId: widget.partId,
      content: _controller.text,
      expectedUpdatedAt: widget.updatedAt,
    );
    if (!mounted || _saving) return;
    setState(() {
      // A conflict is not cleared by typing: it stays visible until a save
      // actually succeeds, otherwise the user never learns their text is only
      // in the draft (P9-M2).
      if (!_hasConflict) _status = _l10n(context).partEditorEditing;
    });
  }

  void _onFlushed(AutosaveFlushResult result) {
    if (!mounted) return;
    final l10n = _l10n(context);
    setState(() {
      if (result.outcomes.any((outcome) => outcome.requiresUserResolution)) {
        _hasConflict = true;
        _hasUnresolvedConflict = true;
        _status = l10n.partEditorConflictOtherSaved;
      } else if (result.hasUnsavedConflict) {
        _hasConflict = true;
        _status = l10n.partEditorConflictDraftRetained;
      } else if (result.applied > 0) {
        _hasConflict = false;
        _hasUnresolvedConflict = false;
        _status = l10n.partEditorAutoSaved(
          _autosaveTriggerLabel(result.trigger, l10n),
        );
      } else if (result.discarded > 0) {
        _status = l10n.partEditorTargetPartMissing;
      }
    });
    if (result.applied > 0) widget.onSaved(_controller.text);
  }

  /// R2-M1: the user keeps their draft. The write still runs through the CAS
  /// boundary, so a further external write between the tap and the commit is
  /// refused and the conflict stays open.
  Future<void> _resolveKeepMine() async {
    if (_resolvingConflict) return;
    _resolvingConflict = true;
    try {
      final outcome = await _autosave.resolveConflictKeepMine(
        resourceId: widget.resourceId,
        partId: widget.partId,
        content: _controller.text,
      );
      if (!mounted) return;
      final l10n = _l10n(context);
      setState(() {
        if (outcome.persisted) {
          _hasConflict = false;
          _hasUnresolvedConflict = false;
          _status = l10n.partEditorKeptMyTextAndSaved;
        } else if (outcome.status == AutosaveWriteStatus.conflict) {
          _hasUnresolvedConflict = true;
          _status = l10n.partEditorConflictStillUnresolved;
        } else {
          _status = resourceStudioUserMessage(outcome.message, l10n);
        }
      });
      if (outcome.persisted) widget.onSaved(_controller.text);
    } catch (error) {
      if (!mounted) return;
      final l10n = _l10n(context);
      setState(() {
        _hasUnresolvedConflict = true;
        _status = l10n.partEditorResolveConflictFailed(
          resourceStudioUserMessage(error, l10n),
        );
      });
    } finally {
      _resolvingConflict = false;
    }
  }

  /// R2-M1: the user drops their draft; the editor adopts the live content.
  Future<void> _resolveDiscardMine() async {
    if (_resolvingConflict) return;
    _resolvingConflict = true;
    try {
      final outcome = await _autosave.resolveConflictDiscardMine(
        resourceId: widget.resourceId,
        partId: widget.partId,
      );
      if (!mounted) return;
      final l10n = _l10n(context);
      setState(() {
        if (outcome.status == AutosaveWriteStatus.adoptedLive) {
          _hasConflict = false;
          _hasUnresolvedConflict = false;
          _syncingLiveContent = true;
          _controller.text = outcome.adoptedLiveContent ?? _controller.text;
          _syncingLiveContent = false;
          _status = resourceStudioUserMessage(outcome.message, l10n);
        } else {
          _status = resourceStudioUserMessage(outcome.message, l10n);
        }
      });
    } catch (error) {
      if (!mounted) return;
      final l10n = _l10n(context);
      setState(() {
        _hasUnresolvedConflict = true;
        _status = l10n.partEditorResolveConflictFailed(
          resourceStudioUserMessage(error, l10n),
        );
      });
    } finally {
      _resolvingConflict = false;
    }
  }

  Future<void> _flush(AutosaveFlushTrigger trigger) async {
    if (!mounted) {
      // The widget is gone but its buffer is not: write it out anyway so the
      // text survives a page exit.
      await _autosave.flush(trigger: trigger);
      return;
    }
    setState(() {
      _saving = true;
      if (trigger.isForced) {
        final l10n = _l10n(context);
        _status = l10n.partEditorSaving(_autosaveTriggerLabel(trigger, l10n));
      }
    });
    try {
      await _autosave.flush(trigger: trigger);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _close() async {
    _closing = true;
    await _flush(AutosaveFlushTrigger.pageLeave);
    _closing = false;
    widget.onClose();
  }

  /// Offers a draft a previous session left in the journal.
  ///
  /// Loading it puts the text back in the editor so the next save writes it;
  /// discarding it is the user's explicit decision, never a silent drop.
  Widget _buildDraftBanner(ThemeData theme) {
    final l10n = _l10n(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.partEditorUnsavedDraftFound,
                style: theme.textTheme.bodyLarge),
            const SizedBox(height: 2),
            Text(
              l10n.partEditorUnsavedDraftDesc,
              softWrap: true,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: _restoreDraft,
                  child: Text(l10n.partEditorLoadDraft),
                ),
                TextButton(
                  onPressed: () => unawaited(_discardDraft()),
                  child: Text(l10n.partEditorDiscardDraft),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Offers the two R2-M1 resolutions after an external write conflicted with
  /// the draft: keep the user's text (CAS-protected) or adopt the live content.
  Widget _buildConflictBanner(ThemeData theme) {
    final l10n = _l10n(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.error),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.partEditorConflictDetected,
                style: theme.textTheme.bodyLarge),
            const SizedBox(height: 2),
            Text(
              l10n.partEditorConflictDesc,
              softWrap: true,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: _resolvingConflict
                      ? null
                      : () => unawaited(_resolveKeepMine()),
                  child: Text(l10n.partEditorUseMyText),
                ),
                TextButton(
                  onPressed: _resolvingConflict
                      ? null
                      : () => unawaited(_resolveDiscardMine()),
                  child: Text(l10n.partEditorDiscardMyText),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = _l10n(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.partTitle,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              maxLines: null,
              minLines: 6,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: l10n.partEditorHint,
                alignLabelWithHint: true,
              ),
              style: theme.textTheme.bodyLarge,
            ),
            if (_pendingDraft != null) ...[
              const SizedBox(height: 12),
              _buildDraftBanner(theme),
            ],
            if (_hasUnresolvedConflict) ...[
              const SizedBox(height: 12),
              _buildConflictBanner(theme),
            ],
            if (_status.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                _status,
                softWrap: true,
                style: _hasConflict
                    ? TextStyle(color: theme.colorScheme.error)
                    : theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 12),
            // Wrap, not Row: at 320 px or a large text scale the two actions
            // move onto separate lines instead of overflowing.
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _saving
                      ? null
                      : () => unawaited(_flush(AutosaveFlushTrigger.manual)),
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(l10n.partEditorSaveNow),
                ),
                OutlinedButton(
                  onPressed: _saving ? null : () => unawaited(_close()),
                  child: Text(l10n.partEditorFinishEditing),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
