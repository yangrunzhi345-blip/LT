import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_confirm_dialog.dart';
import '../../../core/widgets/app_read_aloud.dart';
import '../../../domain/read_aloud/read_aloud_contracts.dart';
import '../../../models/adventure_response.dart';
import '../../../models/message.dart';
import '../../../utils/platform_utils.dart';
import '../../../widgets/narr_aitor_loading.dart';
import '../../../widgets/adventure_message_card.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../l10n/generated/app_localizations_zh.dart';

class ReasoningBlock extends StatefulWidget {
  final String reasoning;
  final Brightness brightness;
  final double fontSize;
  final bool initiallyExpanded;
  final bool isThinking;

  const ReasoningBlock({
    super.key,
    required this.reasoning,
    required this.brightness,
    required this.fontSize,
    this.initiallyExpanded = false,
    this.isThinking = false,
  });

  @override
  State<ReasoningBlock> createState() => _ReasoningBlockState();
}

class _ReasoningBlockState extends State<ReasoningBlock> {
  late bool _expanded;
  bool _userToggled = false;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded || widget.isThinking;
  }

  @override
  void didUpdateWidget(covariant ReasoningBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_userToggled) {
      if (widget.isThinking) {
        _expanded = true;
      } else if (oldWidget.isThinking && !widget.isThinking) {
        _expanded = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();
    final isDark = widget.brightness == Brightness.dark;
    final headerBg = isDark ? const Color(0xFF1E262E) : const Color(0xFFE8ECEF);
    final borderCol = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);
    final textMuted =
        isDark ? const Color(0xFF90A4AE) : const Color(0xFF546E7A);
    final contentBg =
        isDark ? const Color(0xFF181F26) : const Color(0xFFEFF3F6);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: headerBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderCol),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () {
              setState(() {
                _userToggled = true;
                _expanded = !_expanded;
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.psychology_rounded,
                    size: 16,
                    color: widget.isThinking ? AppColors.accent : textMuted,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      widget.isThinking
                          ? '正在深度思考...'
                          : (_expanded ? '思考过程 (点击收起)' : '已深度思考 (点击展开思维链)'),
                      style: TextStyle(
                        fontSize: (widget.fontSize - 3).clamp(10.0, 13.0),
                        fontWeight: FontWeight.w600,
                        color: widget.isThinking ? AppColors.accent : textMuted,
                      ),
                    ),
                  ),
                  if (widget.isThinking)
                    const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: NarrAItorLoading.mini(size: 14),
                    ),
                  if (!_expanded && widget.reasoning.isNotEmpty) ...[
                    Text(
                      l10n.chatCharacterCount(widget.reasoning.length),
                      style: TextStyle(
                        fontSize: 10,
                        color: textMuted.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 16,
                    color: textMuted,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Container(
              constraints: const BoxConstraints(maxHeight: 280),
              color: contentBg,
              child: SingleChildScrollView(
                reverse: widget.isThinking,
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SelectableText(
                      widget.reasoning.isEmpty
                          ? (widget.isThinking ? '正在思考中...' : '（无记录）')
                          : widget.reasoning,
                      style: TextStyle(
                        fontSize: (widget.fontSize - 2).clamp(11.0, 14.0),
                        height: 1.6,
                        color: isDark
                            ? const Color(0xFFB0BEC5)
                            : const Color(0xFF37474F),
                        fontFamily: 'monospace',
                      ),
                    ),
                    if (!widget.isThinking && widget.reasoning.isNotEmpty)
                      Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(4),
                            onTap: () {
                              Clipboard.setData(
                                  ClipboardData(text: widget.reasoning));
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(l10n.reasoningCopiedToast),
                                  duration: const Duration(milliseconds: 1200),
                                ),
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.copy_rounded,
                                      size: 12, color: textMuted),
                                  const SizedBox(width: 4),
                                  Text(
                                    '复制思考过程',
                                    style: TextStyle(
                                        fontSize: 10, color: textMuted),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

Widget _buildEmotionLabel(String emotion) {
  if (emotion.isEmpty) return const SizedBox.shrink();
  return Padding(
    padding: const EdgeInsets.only(left: 8, bottom: 2),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: const Color(0xFF6B7280).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        emotion,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
      ),
    ),
  );
}

Widget _buildBubbleFooter({
  required AppLocalizations l10n,
  required bool isEdited,
  required bool isBookmarked,
  required VoidCallback onToggleBookmark,
  VoidCallback? onCopy,
  VoidCallback? onEdit,
  VoidCallback? onRegenerate,
  Widget? readAloudAction,
}) {
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (isEdited)
        Text(l10n.editedBadge,
            style: TextStyle(fontSize: 10, color: Colors.grey[500])),
      // 无 Spacer：按钮随气泡侧对齐 — AI 气泡（Column start）贴左，用户气泡（end）贴右
      if (readAloudAction != null) ...[
        readAloudAction,
        const SizedBox(width: 4),
      ],
      if (isEdited &&
          (onCopy != null || onEdit != null || onRegenerate != null))
        const SizedBox(width: 8),
      if (onCopy != null)
        IconButton(
          icon: Icon(Icons.copy_rounded, size: 14, color: Colors.grey[400]),
          onPressed: onCopy,
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          tooltip: l10n.copyAction,
        ),
      if (onCopy != null && (onEdit != null || onRegenerate != null))
        const SizedBox(width: 10),
      if (onEdit != null)
        IconButton(
          icon: Icon(Icons.edit_outlined, size: 14, color: Colors.grey[400]),
          onPressed: onEdit,
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          tooltip: l10n.editMessageAction,
        ),
      if (onEdit != null && onRegenerate != null) const SizedBox(width: 10),
      if (onRegenerate != null)
        IconButton(
          icon: Icon(Icons.refresh_rounded, size: 14, color: Colors.grey[400]),
          onPressed: onRegenerate,
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          tooltip: l10n.regenerateMessageAction,
        ),
      if ((onCopy != null || onEdit != null || onRegenerate != null))
        const SizedBox(width: 10),
      IconButton(
        icon: Icon(isBookmarked ? Icons.bookmark : Icons.bookmark_border,
            size: 14,
            color: isBookmarked ? AppColors.accent : Colors.grey[400]),
        onPressed: onToggleBookmark,
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        tooltip:
            isBookmarked ? l10n.removeBookmarkAction : l10n.addBookmarkAction,
      ),
    ],
  );
}

Widget _buildAvatar(String label, {required bool isUser}) {
  final color = isUser ? AppColors.accent : AppColors.teal;
  return Container(
    margin: const EdgeInsets.only(top: 10),
    width: 32,
    height: 32,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
    ),
    alignment: Alignment.center,
    child: Text(label,
        style: const TextStyle(
            color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
  );
}

/// P0-04: 条件性渐变装饰条 — 仅在非 Android 16+ 平台上启用
Widget _buildAiContent(
    String content, Brightness brightness, double chatFontSize,
    {required void Function(String option) onOptionTap,
    String? defaultCharacterName}) {
  final core = _buildAiBubbleContent(content, brightness, chatFontSize,
      onOptionTap: onOptionTap, defaultCharacterName: defaultCharacterName);
  if (!canUseGradientAccent) return core;

  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 4,
        decoration: const BoxDecoration(
          color: AppColors.bubbleAccentBar,
        ),
      ),
      Expanded(child: core),
    ],
  );
}

Widget _buildAiBubbleContent(
    String content, Brightness brightness, double chatFontSize,
    {required void Function(String option) onOptionTap,
    String? defaultCharacterName}) {
  if (AdventureResponse.tryParseSplit(content) != null) {
    return AdventureMessageCard(
      jsonContent: content,
      brightness: brightness,
      onOptionTap: onOptionTap,
      fontSize: chatFontSize,
      defaultCharacterName: defaultCharacterName,
    );
  }
  if (AdventureResponse.tryParse(content) != null) {
    return AdventureMessageCard(
      jsonContent: content,
      brightness: brightness,
      onOptionTap: onOptionTap,
      fontSize: chatFontSize,
      defaultCharacterName: defaultCharacterName,
    );
  }
  final isDark = brightness == Brightness.dark;
  final displayText = content;
  return Padding(
    padding: const EdgeInsets.all(12),
    child: Text(
      displayText,
      style: TextStyle(
        fontSize: chatFontSize,
        height: 1.8,
        color: isDark ? const Color(0xFFD0D0D0) : const Color(0xFF333333),
      ),
    ),
  );
}

class UserBubble extends StatelessWidget {
  final Message message;
  final double chatFontSize;
  final String userAvatarLabel;
  final VoidCallback onLongPress;
  final VoidCallback onRegenerate;
  final VoidCallback? onDelete;
  final VoidCallback? onCopy;
  final VoidCallback? onEdit;
  final bool isBookmarked;
  final VoidCallback onToggleBookmark;

  /// 引擎忙碌（loading/streaming）时不展示重新生成按钮：
  /// 重新生成是先删后发，若 sendMessage 被并发守卫拦截会丢失消息。
  final bool canRegenerate;

  const UserBubble({
    super.key,
    required this.message,
    required this.chatFontSize,
    required this.userAvatarLabel,
    required this.onLongPress,
    required this.onRegenerate,
    required this.isBookmarked,
    required this.onToggleBookmark,
    this.onDelete,
    this.onCopy,
    this.onEdit,
    this.canRegenerate = true,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();
    return Dismissible(
      key: ValueKey('user_${message.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 24),
        color: AppColors.error.withValues(alpha: 0.3),
        child: const Icon(Icons.delete, color: AppColors.error),
      ),
      confirmDismiss: (direction) async {
        // 左滑 = 删除（重新生成已由气泡下方可见按钮承担）
        final result = await AppConfirmDialog.show(
          context: context,
          title: l10n.chatDeleteMessage,
          message: l10n.deleteMessageConfirmation,
          confirmLabel: l10n.deleteAction,
          isDanger: true,
        );
        if (result) onDelete?.call();
        return result;
      },
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 8, bottom: 4),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Text(
                      message.content,
                      style: TextStyle(
                          color: Colors.white, fontSize: chatFontSize),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 8, bottom: 4),
                    child: _buildBubbleFooter(
                      l10n: l10n,
                      isEdited: message.isEdited,
                      isBookmarked: isBookmarked,
                      onToggleBookmark: onToggleBookmark,
                      onCopy: onCopy,
                      onEdit: canRegenerate ? onEdit : null,
                      onRegenerate: canRegenerate ? onRegenerate : null,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _buildAvatar(userAvatarLabel, isUser: true),
          ],
        ),
      ),
    );
  }
}

class AiBubble extends StatelessWidget {
  final Message message;
  final double chatFontSize;
  final Brightness brightness;
  final String aiName;
  final String emotion;
  final bool isBookmarked;
  final VoidCallback onLongPress;
  final VoidCallback onRegenerate;
  final VoidCallback onDelete;
  final VoidCallback onToggleBookmark;
  final void Function(String option) onOptionTap;
  final VoidCallback? onCopy;

  /// 引擎忙碌（loading/streaming）时不展示重新生成按钮：
  /// 重新生成是先删后发，若 sendMessage 被并发守卫拦截会丢失消息。
  final bool canRegenerate;

  const AiBubble({
    super.key,
    required this.message,
    required this.chatFontSize,
    required this.brightness,
    required this.aiName,
    required this.emotion,
    required this.isBookmarked,
    required this.onLongPress,
    required this.onRegenerate,
    required this.onDelete,
    required this.onToggleBookmark,
    required this.onOptionTap,
    this.onCopy,
    this.canRegenerate = true,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();
    final isDark = brightness == Brightness.dark;
    final bubbleColor = isDark ? const Color(0xFF263238) : AppColors.bubbleAi;
    final shadowColor = isDark
        ? Colors.black.withValues(alpha: 0.2)
        : Colors.black.withValues(alpha: 0.05);
    // 只朗读用户可见的叙事正文：双段协议的 ---JSON--- 结算数据不参与。
    final readAloudText =
        AdventureResponse.streamingDisplayText(message.content).trim();
    return Dismissible(
      key: ValueKey('ai_${message.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 24),
        color: AppColors.error.withValues(alpha: 0.3),
        child: const Icon(Icons.delete, color: AppColors.error),
      ),
      confirmDismiss: (direction) async {
        // 左滑 = 删除（重新生成已由气泡下方可见按钮承担）
        final result = await AppConfirmDialog.show(
          context: context,
          title: l10n.chatDeleteMessage,
          message: l10n.deleteMessageConfirmation,
          confirmLabel: l10n.deleteAction,
          isDanger: true,
        );
        if (result) onDelete();
        return result;
      },
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildAvatar(aiName.isNotEmpty ? aiName[0].toUpperCase() : 'A',
                isUser: false),
            const SizedBox(width: 8),
            Flexible(
              child: Container(
                margin: const EdgeInsets.only(top: 8, bottom: 8, right: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildEmotionLabel(emotion),
                    Padding(
                      padding: const EdgeInsets.only(left: 8, bottom: 4),
                      child: Text(
                        aiName,
                        style: TextStyle(
                            color: AppColors.accent,
                            fontSize: chatFontSize - 2,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: bubbleColor,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                                color: shadowColor,
                                blurRadius: 8,
                                offset: const Offset(0, 2)),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (message.reasoningContent != null &&
                                message.reasoningContent!.trim().isNotEmpty)
                              ReasoningBlock(
                                reasoning: message.reasoningContent!,
                                brightness: brightness,
                                fontSize: chatFontSize,
                              ),
                            _buildAiContent(
                                message.content, brightness, chatFontSize,
                                onOptionTap: onOptionTap,
                                defaultCharacterName: aiName),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4, left: 8),
                      child: _buildBubbleFooter(
                        l10n: l10n,
                        isEdited: message.isEdited,
                        isBookmarked: isBookmarked,
                        onToggleBookmark: onToggleBookmark,
                        onCopy: onCopy,
                        onRegenerate: canRegenerate ? onRegenerate : null,
                        readAloudAction: readAloudText.isEmpty
                            ? null
                            : AppReadAloudButton(
                                sourceId: 'chat:${message.id}',
                                sourceType: ReadAloudSourceType.chat,
                                text: readAloudText,
                                label: l10n.assistantReplyLabel,
                                tooltip: l10n.readAloudStart,
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 已经生成但尚未 durable commit 的本轮 AI 回复气泡。
///
/// 生命周期与 [StreamingBubble] 衔接：正文流式完成后冻结为这里的内容，
/// 结算请求运行时正文保持原样、「正在生成选项与结算状态」只作为 footer
/// 追加在正文之后；结算完成后 [content] 切换为「正文 + 监测状态 + 选项」
/// 的完整结构化内容（与最终 committed Message 完全一致），因此 commit 时
/// 的组件替换对玩家是像素级无感的。
///
/// [content] 为纯正文时按纯文本渲染；包含 `---JSON---` 时复用
/// [_buildAiBubbleContent] 的 [AdventureMessageCard] 渲染路径，原始结算
/// JSON 永远不会直接显示给用户。
class PendingAssistantBubble extends StatelessWidget {
  final String content;
  final double chatFontSize;
  final Brightness brightness;
  final String aiName;

  /// 结算进行中显示的 footer（[SessionSettlingHint] 由调用方注入，
  /// 本组件不依赖 features 层）。为 null 时不渲染 footer。
  final Widget? footer;

  /// 结算已完成时选项芯片的点击回调；结算未完成前传 null，
  /// 因为此时发送仍被引擎并发守卫拦截。
  final void Function(String option)? onOptionTap;

  const PendingAssistantBubble({
    super.key,
    required this.content,
    required this.chatFontSize,
    required this.brightness,
    required this.aiName,
    this.footer,
    this.onOptionTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = brightness == Brightness.dark;
    // 背景色与 AiBubble / StreamingBubble 完全一致，消除阶段切换的视觉跳跃。
    final bubbleColor = isDark ? const Color(0xFF263238) : AppColors.bubbleAi;
    final shadowColor = isDark
        ? Colors.black.withValues(alpha: 0.2)
        : Colors.black.withValues(alpha: 0.05);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildAvatar(aiName.isNotEmpty ? aiName[0].toUpperCase() : 'A',
            isUser: false),
        const SizedBox(width: 8),
        Flexible(
          child: Container(
            margin: const EdgeInsets.only(top: 8, bottom: 8, right: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 4),
                  child: Text(aiName,
                      style: TextStyle(
                          color: AppColors.accent,
                          fontSize: chatFontSize - 2,
                          fontWeight: FontWeight.w600)),
                ),
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: bubbleColor,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                            color: shadowColor,
                            blurRadius: 8,
                            offset: const Offset(0, 2)),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildAiContent(
                          content,
                          brightness,
                          chatFontSize,
                          onOptionTap: (option) => onOptionTap?.call(option),
                          defaultCharacterName: aiName,
                        ),
                        if (footer != null) ...[
                          Divider(
                            height: 1,
                            thickness: 1,
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.08)
                                : Colors.black.withValues(alpha: 0.08),
                          ),
                          footer!,
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class StreamingBubble extends StatelessWidget {
  final double chatFontSize;
  final Brightness brightness;
  final String aiName;
  final ValueNotifier<String> streamNotifier;
  final ValueNotifier<String>? reasoningStreamNotifier;
  final ValueNotifier<bool>? isThinkingNotifier;

  const StreamingBubble({
    super.key,
    required this.chatFontSize,
    required this.brightness,
    required this.aiName,
    required this.streamNotifier,
    this.reasoningStreamNotifier,
    this.isThinkingNotifier,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = brightness == Brightness.dark;
    // v2.13.1: 背景色对齐 AiBubble (line 254)，消除流式→渲染的视觉跳跃
    final bubbleColor = isDark ? const Color(0xFF263238) : AppColors.bubbleAi;
    final shadowColor = isDark
        ? Colors.black.withValues(alpha: 0.2)
        : Colors.black.withValues(alpha: 0.05);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildAvatar(aiName.isNotEmpty ? aiName[0].toUpperCase() : 'A',
            isUser: false),
        const SizedBox(width: 8),
        Flexible(
          child: Container(
            margin: const EdgeInsets.only(top: 8, bottom: 8, right: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 4),
                  child: Text(aiName,
                      style: TextStyle(
                          color: AppColors.accent,
                          fontSize: chatFontSize - 2,
                          fontWeight: FontWeight.w600)),
                ),
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: bubbleColor,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                            color: shadowColor,
                            blurRadius: 8,
                            offset: const Offset(0, 2)),
                      ],
                    ),
                    child: _buildStreamingBody(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// P0-04: 条件性渐变装饰条 — 仅在非 Android 16+ 平台上为流式气泡启用
  Widget _buildStreamingBody() {
    final listenables = <Listenable>[
      streamNotifier,
      if (reasoningStreamNotifier != null) reasoningStreamNotifier!,
      if (isThinkingNotifier != null) isThinkingNotifier!,
    ];

    return AnimatedBuilder(
      animation: Listenable.merge(listenables),
      builder: (_, __) {
        final text = streamNotifier.value;
        final reasoning = reasoningStreamNotifier?.value ?? '';
        final isThinking = isThinkingNotifier?.value ?? false;

        final hasReasoning = reasoning.isNotEmpty;
        final hasText = text.isNotEmpty;

        if (!hasText && !hasReasoning && !isThinking) {
          return const SizedBox(
            height: 64,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  NarrAItorLoading.mini(size: 20),
                  SizedBox(height: 8),
                  Text(
                    '正在撰写剧情...',
                    style: TextStyle(fontSize: 12, color: Color(0xFF888888)),
                  ),
                ],
              ),
            ),
          );
        }

        final textColor = brightness == Brightness.dark
            ? const Color(0xFFD0D0D0)
            : const Color(0xFF333333);

        final textWidget = hasText
            ? Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  AdventureResponse.streamingDisplayText(text),
                  style: TextStyle(
                    fontSize: chatFontSize,
                    height: 1.8,
                    color: textColor,
                  ),
                ),
              )
            : const SizedBox.shrink();

        final styledText = (canUseGradientAccent && hasText)
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 4,
                    color: AppColors.bubbleAccentBar,
                  ),
                  Expanded(child: textWidget),
                ],
              )
            : textWidget;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (hasReasoning || isThinking)
              ReasoningBlock(
                reasoning: reasoning,
                brightness: brightness,
                fontSize: chatFontSize,
                isThinking: isThinking && !hasText,
              ),
            styledText,
          ],
        );
      },
    );
  }
}
