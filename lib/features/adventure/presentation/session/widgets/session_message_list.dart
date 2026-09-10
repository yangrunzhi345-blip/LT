import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/widgets/app_empty_state.dart';
import '../../../../../providers/chat_provider.dart';
import '../../../../../providers/riverpod_providers.dart';
import '../../../../../screens/chat/widgets/chat_dialogs.dart';
import '../../../../../screens/chat/widgets/error_card.dart';
import '../../../../../screens/chat/widgets/message_bubble.dart';

/// 现代化场景会话消息列表
/// 负责流式输出跟踪、平滑滚动、空白白板引导和多类型消息气泡渲染
class SessionMessageList extends ConsumerStatefulWidget {
  final ScrollController scrollController;
  final String? initialMessageId;
  final VoidCallback? onStartAction;

  const SessionMessageList({
    super.key,
    required this.scrollController,
    this.initialMessageId,
    this.onStartAction,
  });

  @override
  ConsumerState<SessionMessageList> createState() => _SessionMessageListState();
}

class _SessionMessageListState extends ConsumerState<SessionMessageList> {
  bool _showGestureHint = true;
  bool _wasStreaming = false;
  bool _userScrolledUp = false;
  bool _scrollPending = false;
  bool _isAutoScrolling = false;
  int? _lastAdventureId;
  int _lastMessageCount = 0;
  final GlobalKey _targetMessageKey = GlobalKey();
  final GlobalKey _latestUserActionKey = GlobalKey();
  bool _didScrollToTarget = false;

  static const double _bottomThreshold = 100.0;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_onScrollChanged);
    final provider = ref.read(chatProvider);
    _lastAdventureId = provider.currentAdventureId;
    _lastMessageCount = provider.messages.length;
    _wasStreaming = provider.isStreaming;
    if (widget.initialMessageId == null) {
      _jumpToBottom();
    }
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_onScrollChanged);
    super.dispose();
  }

  bool _isNearBottom() {
    if (!widget.scrollController.hasClients) return true;
    final pos = widget.scrollController.position;
    return pos.pixels >= pos.maxScrollExtent - _bottomThreshold;
  }

  void _onScrollChanged() {
    if (!widget.scrollController.hasClients) return;
    if (_isAutoScrolling) return;
    final nearBottom = _isNearBottom();
    if (nearBottom && _userScrolledUp) {
      setState(() => _userScrolledUp = false);
    } else if (!nearBottom && !_userScrolledUp) {
      setState(() => _userScrolledUp = true);
    }
  }

  void _jumpToBottom({int maxAttempts = 8}) {
    if (widget.initialMessageId != null) return;
    _isAutoScrolling = true;
    _userScrolledUp = false;

    void doJump(int remaining) {
      if (!mounted || !widget.scrollController.hasClients) {
        _isAutoScrolling = false;
        return;
      }
      final pos = widget.scrollController.position;
      if (pos.pixels < pos.maxScrollExtent) {
        pos.jumpTo(pos.maxScrollExtent);
        if (remaining > 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            doJump(remaining - 1);
          });
          return;
        }
      }
      _isAutoScrolling = false;
      if (mounted && _userScrolledUp) {
        setState(() => _userScrolledUp = false);
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      doJump(maxAttempts);
    });
  }

  void _scrollToLatestAction() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.scrollController.hasClients) return;
      final target = _latestUserActionKey.currentContext;
      if (target != null) {
        _isAutoScrolling = true;
        Scrollable.ensureVisible(
          target,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          alignment: 0.05,
        ).then((_) {
          _isAutoScrolling = false;
        }).catchError((_) {
          _isAutoScrolling = false;
        });
      } else {
        _scrollToBottom(force: true);
      }
    });
  }

  void _scrollToBottom({bool force = false}) {
    if (_scrollPending) return;
    if (!force && _userScrolledUp) return;
    _scrollPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollPending = false;
      if (!mounted || !widget.scrollController.hasClients) return;
      _isAutoScrolling = true;
      widget.scrollController
          .animateTo(
        widget.scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
      )
          .then((_) {
        _isAutoScrolling = false;
        if (mounted && _isNearBottom() && _userScrolledUp) {
          setState(() => _userScrolledUp = false);
        }
      }).catchError((_) {
        _isAutoScrolling = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final colorScheme = theme.colorScheme;
    final cp = ref.watch(chatProvider);

    return ListenableBuilder(
      listenable: cp.rebuildVersion,
      builder: (context, _) {
        final provider = ref.read(chatProvider);

        final currentAdvId = provider.currentAdventureId;
        if (currentAdvId != null && currentAdvId != _lastAdventureId) {
          _lastAdventureId = currentAdvId;
          _lastMessageCount = provider.messages.length;
          _userScrolledUp = false;
          _jumpToBottom();
        }

        if (provider.scrollToBottomPending) {
          provider.consumeScrollToBottom();
          _lastMessageCount = provider.messages.length;
          _userScrolledUp = false;
          _jumpToBottom();
        }

        final currentCount = provider.messages.length;
        final hasNewMessage = currentCount > _lastMessageCount;
        final isNewStreamStarting = provider.isStreaming && !_wasStreaming;

        if (hasNewMessage || isNewStreamStarting) {
          final hasNewUserAction = hasNewMessage &&
              provider.messages.isNotEmpty &&
              provider.messages.last.isUser;

          _lastMessageCount = currentCount;

          if (hasNewUserAction) {
            _userScrolledUp = false;
            _scrollToLatestAction();
          } else if (isNewStreamStarting && !_userScrolledUp) {
            _scrollToLatestAction();
          }
        } else if (currentCount < _lastMessageCount) {
          _lastMessageCount = currentCount;
        }

        // 仅在用户显式开启"生成时跟随滚动"时才在流式生成中持续滚到底部；
        // 默认保持屏幕平稳，确保用户阅读时不被强行滑动打断。
        final autoScroll = provider.settingsProvider.autoScrollDuringGeneration;
        if (autoScroll && provider.isStreaming && !_userScrolledUp) {
          _scrollToBottom();
        }

        if (_wasStreaming && !provider.isStreaming && !_userScrolledUp) {
          HapticFeedback.mediumImpact();
        }
        _wasStreaming = provider.isStreaming;

        if (provider.messages.isEmpty && !provider.isStreaming) {
          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: AppEmptyState(
                icon: Icons.explore_outlined,
                title: '纯净冒险白板',
                description: '当前场景尚未产生任何对话或行动记录。\n在下方输入你的行动、提出一个探索方向，开始这段冒险。',
                actionLabel: '启程行动',
                onAction: widget.onStartAction,
              ),
            ),
          );
        }

        return Stack(
          children: [
            NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification is UserScrollNotification) {
                  if (notification.direction != ScrollDirection.idle) {
                    // 用户正在主动滑动（包含触屏拖拽、鼠标滚轮、触摸板等所有平台交互）
                    // 立即终止程序化自动滚动标记，确保滑动行为完全由用户掌控
                    _isAutoScrolling = false;
                    _scrollPending = false;
                  }
                }
                if (notification is ScrollUpdateNotification) {
                  if (!_isAutoScrolling) {
                    final nearBottom = _isNearBottom();
                    if (!nearBottom && !_userScrolledUp) {
                      setState(() => _userScrolledUp = true);
                    } else if (nearBottom && _userScrolledUp) {
                      setState(() => _userScrolledUp = false);
                    }
                  }
                }
                return false;
              },
              child: RepaintBoundary(
                child: Column(
                  children: [
                    if (_showGestureHint && provider.messages.isNotEmpty)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: colorScheme.outlineVariant
                                .withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Text('💡', style: TextStyle(fontSize: 14)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '右滑消息可重试 · 左滑可删除 · 长按可编辑/收藏',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: () =>
                                  setState(() => _showGestureHint = false),
                              child: Icon(
                                Icons.close,
                                size: 14,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    Expanded(
                      child: ListView.builder(
                        controller: widget.scrollController,
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                        itemCount: provider.messages.length +
                            (provider.isStreaming ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (provider.isStreaming &&
                              index == provider.messages.length) {
                            return StreamingBubble(
                              key: ValueKey(
                                  'streaming_${provider.messages.length}'),
                              chatFontSize: provider.chatFontSize /
                                  provider.textScaleFactor,
                              brightness: brightness,
                              aiName: provider.selectedCharacterName ??
                                  provider.adventureConfig?.name ??
                                  '冒险助手',
                              streamNotifier: provider.streamNotifier,
                              reasoningStreamNotifier:
                                  provider.reasoningStreamNotifier,
                              isThinkingNotifier: provider.isThinkingNotifier,
                            );
                          }

                          final message = provider.messages[index];
                          final bubble = _buildBubble(
                            context,
                            message,
                            brightness,
                            provider,
                          );

                          if (widget.initialMessageId != null &&
                              message.id.toString() ==
                                  widget.initialMessageId) {
                            if (!_didScrollToTarget) {
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                final target = _targetMessageKey.currentContext;
                                if (target != null && mounted) {
                                  _didScrollToTarget = true;
                                  Scrollable.ensureVisible(
                                    target,
                                    duration: const Duration(milliseconds: 320),
                                    alignment: 0.35,
                                  );
                                }
                              });
                            }
                            return KeyedSubtree(
                              key: _targetMessageKey,
                              child: bubble,
                            );
                          }

                          if (message.isUser &&
                              index ==
                                  provider.messages
                                      .lastIndexWhere((m) => m.isUser)) {
                            return KeyedSubtree(
                              key: _latestUserActionKey,
                              child: bubble,
                            );
                          }

                          return bubble;
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // 回到底部悬浮按钮
            if (_userScrolledUp)
              Positioned(
                right: 16,
                bottom: 16,
                child: FloatingActionButton.small(
                  onPressed: () {
                    setState(() => _userScrolledUp = false);
                    _scrollToBottom(force: true);
                  },
                  backgroundColor: colorScheme.surfaceContainerHighest,
                  foregroundColor: colorScheme.primary,
                  elevation: 2,
                  child: const Icon(Icons.arrow_downward_rounded, size: 18),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildBubble(
    BuildContext context,
    dynamic message,
    Brightness brightness,
    ChatProvider provider,
  ) {
    final isUser = message.isUser as bool;

    if (!isUser && message.isError == true) {
      return ErrorCard(
        key: ValueKey('err_${message.id}'),
        message: message,
        chatFontSize: provider.chatFontSize / provider.textScaleFactor,
        brightness: brightness,
        onRetry: () => provider.retryLast(),
        onSwitchModel: () => showRetryMenu(context),
      );
    }

    if (isUser) {
      final persona = provider.activePersona;
      return UserBubble(
        key: ValueKey('usr_${message.id}'),
        message: message,
        chatFontSize: provider.chatFontSize / provider.textScaleFactor,
        userAvatarLabel: persona != null && persona.name.isNotEmpty
            ? persona.name[0].toUpperCase()
            : '我',
        onLongPress: () => showMessageMenu(context, message, provider),
        onRegenerate: () => regenerateMessage(message, provider),
        canRegenerate: !provider.isLoading && !provider.isStreaming,
        isBookmarked: provider.bookmarkedMessageIds.contains(message.id),
        onToggleBookmark: () => provider.toggleBookmark(message.id),
        onDelete: () => provider.deleteMessage(message),
        onCopy: () => copyMessageDisplayText(context, message),
        onEdit: () => showEditDialog(context, message, provider),
      );
    }

    return AiBubble(
      key: ValueKey('ai_${message.id}'),
      message: message,
      chatFontSize: provider.chatFontSize / provider.textScaleFactor,
      brightness: brightness,
      aiName: provider.selectedCharacterName ??
          provider.adventureConfig?.name ??
          '冒险助手',
      emotion: provider.messagingProvider.detectEmotion(message.content),
      isBookmarked: provider.bookmarkedMessageIds.contains(message.id),
      onLongPress: () => showMessageMenu(context, message, provider),
      onRegenerate: () => regenerateMessage(message, provider),
      canRegenerate: !provider.isLoading && !provider.isStreaming,
      onDelete: () => provider.deleteMessage(message),
      onToggleBookmark: () => provider.toggleBookmark(message.id),
      onCopy: () => copyMessageDisplayText(context, message),
      onOptionTap: (option) => provider.sendMessage(option),
    );
  }
}
