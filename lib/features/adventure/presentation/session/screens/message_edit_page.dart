import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../../core/feedback/app_feedback.dart';
import '../../../../../../core/theme/app_radius.dart';
import '../../../../../../core/theme/app_spacing.dart';
import '../../../../../../core/widgets/ui_foundation.dart';
import '../../../../../../models/message.dart';
import '../../../../../../providers/riverpod_providers.dart';

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
    final newContent = _textCtrl.text.trim();
    if (newContent.isEmpty) {
      AppFeedback.error(context, '消息内容不能为空');
      return;
    }

    if (newContent == _originalContent) {
      AppFeedback.info(context, '内容未作修改');
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
            AppFeedback.error(context, '消息已不在当前对话中，请返回刷新');
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
        _isUserMessage ? '已保存并重新生成' : '已保存修改',
      );
      Navigator.of(context).pop(true);
    } catch (error, stackTrace) {
      debugPrint('[MessageEditPage] save failed: $error\n$stackTrace');
      if (mounted) AppFeedback.error(context, '保存失败，请重试');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return AppPageScaffold(
      title: _isUserMessage ? '编辑你的消息' : '编辑 AI 回复',
      titleWidget: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _isUserMessage ? '编辑你的消息' : '编辑 AI 回复',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _isUserMessage ? '修改后将从该消息开始重新生成后续剧情' : '编辑此条剧情文本，便于调整叙事或纠正细节',
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
                label: const Text('取消'),
              ),
              AppPrimaryButton(
                key: const Key('message-edit-save-button'),
                label: _isUserMessage ? '修改并重新生成' : '保存修改',
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
                        '注意：保存后该消息之后的所有历史推进将自动清除并根据新输入重新构思。',
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
              title: '消息正文',
              description: '支持长文本自由编辑，可任意换行与排版',
              child: AppTextField(
                key: const Key('message-edit-text-input'),
                controller: _textCtrl,
                hintText: '输入消息内容...',
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
