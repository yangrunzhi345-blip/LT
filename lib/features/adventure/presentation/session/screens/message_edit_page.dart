import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../../core/feedback/app_feedback.dart';
import '../../../../../../core/theme/app_radius.dart';
import '../../../../../../core/theme/app_spacing.dart';
import '../../../../../../core/widgets/ui_foundation.dart';
import '../../../../../../models/message.dart';
import '../../../../../../providers/riverpod_providers.dart';
import '../../../../../../l10n/generated/app_localizations.dart';
import '../../../../../../l10n/generated/app_localizations_zh.dart';

/// Navigation-first 独立消息编辑页面
///
/// 替代原 showEditDialog BottomSheet，为长文本与软键盘提供完整的可视区域与滚动支持
class MessageEditPage extends ConsumerStatefulWidget {
  /// 待编辑的消息。
  final Message message;

  /// 初始文本内容（若未提供则从 message.content 取）
  final String? initialContent;

  /// 是否为用户消息（若未提供则从 message.isUser 取）
  final bool? isUser;

  /// 自定义保存回调（若未提供则调用默认的 editMessage）
  final FutureOr<void> Function(String newContent)? onSave;

  const MessageEditPage({
    super.key,
    required this.message,
    this.initialContent,
    this.isUser,
    this.onSave,
  });

  @override
  ConsumerState<MessageEditPage> createState() => _MessageEditPageState();
}

class _MessageEditPageState extends ConsumerState<MessageEditPage> {
  late TextEditingController _textCtrl;
  late final String _originalContent;
  late final bool _isUserMessage;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _originalContent = widget.initialContent ?? widget.message.content;
    _isUserMessage = widget.isUser ?? widget.message.isUser;
    _textCtrl = TextEditingController(text: _originalContent);
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (_isSaving) return;
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();
    final newContent = _textCtrl.text.trim();
    if (newContent.isEmpty) {
      AppFeedback.error(context, l10n.messageContentRequired);
      return;
    }

    if (newContent == _originalContent) {
      AppFeedback.info(context, l10n.messageUnchanged);
      Navigator.of(context).pop(false);
      return;
    }

    setState(() => _isSaving = true);
    try {
      if (widget.onSave case final onSave?) {
        await onSave(newContent);
      } else {
        final chat = ref.read(chatProvider);
        final index = chat.messages.indexOf(widget.message);
        if (index < 0 ||
            !await chat.editMessage(
              index,
              newContent,
              deleteFollowing: _isUserMessage,
            )) {
          if (mounted) {
            AppFeedback.error(context, l10n.messageNoLongerCurrent);
          }
          return;
        }
        if (_isUserMessage) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            unawaited(chat.sendMessage(newContent));
          });
        }
      }

      if (!mounted) return;
      AppFeedback.success(
        context,
        _isUserMessage
            ? l10n.messageSavedAndRegenerated
            : l10n.messageChangesSaved,
      );
      Navigator.of(context).pop(true);
    } catch (error, stackTrace) {
      debugPrint('[MessageEditPage] save failed: $error\n$stackTrace');
      if (mounted) AppFeedback.error(context, l10n.messageSaveRetry);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return AppPageScaffold(
      title: _isUserMessage
          ? l10n.messageEditUserTitle
          : l10n.messageEditAssistantTitle,
      titleWidget: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _isUserMessage
                ? l10n.messageEditUserTitle
                : l10n.messageEditAssistantTitle,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _isUserMessage
                ? l10n.messageEditUserSubtitle
                : l10n.messageEditAssistantSubtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      bottomBar: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border(
            top: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              TextButton.icon(
                onPressed: () => Navigator.of(context).pop(false),
                icon: const Icon(Icons.close, size: 18),
                label: Text(l10n.cancelAction),
              ),
              AppPrimaryButton(
                key: const Key('message-edit-save-button'),
                label: _isUserMessage
                    ? l10n.saveAndRegenerateAction
                    : l10n.saveChangesAction,
                icon: _isUserMessage ? Icons.refresh_rounded : Icons.check,
                isLoading: _isSaving,
                onPressed: _isSaving ? null : _handleSave,
              ),
            ],
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_isUserMessage) ...[
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 18,
                      color: scheme.secondary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.messageEditUserWarning,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            AppFormSection(
              title: l10n.messageBodyLabel,
              description: l10n.messageEditDescription,
              child: AppTextField(
                key: const Key('message-edit-text-input'),
                controller: _textCtrl,
                hintText: l10n.messageContentHint,
                maxLines: 15,
                minLines: 6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
