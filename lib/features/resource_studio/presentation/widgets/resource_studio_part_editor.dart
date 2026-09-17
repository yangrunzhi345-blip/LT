import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../application/resources/resource_autosave_service.dart';
import '../../../../domain/resources/resource_autosave.dart';
import '../../../../domain/resources/resource_contracts.dart';

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
        _status = '发现未保存的草稿（${mine.draft.updatedAtToken}）';
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
      _status = '已载入草稿，保存后写入正文';
    });
  }

  Future<void> _discardDraft() async {
    final draft = _pendingDraft;
    if (draft == null) return;
    await _autosave.discardDraft(draft);
    if (!mounted) return;
    setState(() {
      _pendingDraft = null;
      _status = '草稿已丢弃';
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
    if (_closing) return;
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
      if (!_hasConflict) _status = '编辑中…';
    });
  }

  void _onFlushed(AutosaveFlushResult result) {
    if (!mounted) return;
    setState(() {
      if (result.hasUnsavedConflict) {
        _hasConflict = true;
        _status = '保存冲突：内容仍保留在草稿中，未覆盖较新的版本';
      } else if (result.applied > 0) {
        _hasConflict = false;
        _status = '已自动保存 (${result.trigger.displayLabel})';
      } else if (result.discarded > 0) {
        _status = '目标内容已不存在，草稿已丢弃';
      }
    });
    if (result.applied > 0) widget.onSaved(_controller.text);
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
      if (trigger.isForced) _status = '正在保存 (${trigger.displayLabel})…';
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
            Text('发现未保存的草稿', style: theme.textTheme.bodyLarge),
            const SizedBox(height: 2),
            Text(
              '上次编辑未写入正文。可以载入草稿继续编辑，或丢弃它。',
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
                  child: const Text('载入草稿'),
                ),
                TextButton(
                  onPressed: () => unawaited(_discardDraft()),
                  child: const Text('丢弃草稿'),
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
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '在这里编辑正文，停止输入后会自动保存',
                alignLabelWithHint: true,
              ),
              style: theme.textTheme.bodyLarge,
            ),
            if (_pendingDraft != null) ...[
              const SizedBox(height: 12),
              _buildDraftBanner(theme),
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
                  label: const Text('立即保存'),
                ),
                OutlinedButton(
                  onPressed: _saving ? null : () => unawaited(_close()),
                  child: const Text('完成编辑'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
