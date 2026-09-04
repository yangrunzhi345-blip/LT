import "../../../core/theme/app_colors.dart";
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider;
import '../../../providers/riverpod_providers.dart';
import '../../../utils/token_estimator.dart';
import '../../../widgets/token_progress_bar.dart';

class ChatInputBar extends ConsumerWidget {
  final bool isDark;
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSend;
  final VoidCallback? onStop;

  const ChatInputBar({
    super.key,
    required this.isDark,
    required this.controller,
    required this.focusNode,
    required this.onSend,
    this.onStop,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final barColor = isDark ? AppColors.darkSurface : Colors.white;
    final fillColor =
        isDark ? AppColors.darkSurfaceElevated : AppColors.inputBg;
    final shadowColor = isDark
        ? Colors.black.withValues(alpha: 0.3)
        : Colors.black.withValues(alpha: 0.05);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      decoration: BoxDecoration(
        color: barColor,
        boxShadow: [
          BoxShadow(
              color: shadowColor, blurRadius: 4, offset: const Offset(0, -2)),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListenableBuilder(
              listenable:
                  ref.read(chatProvider).tokenVersion, // P1-01: 仅 token 更新时重建
              builder: (context, _) {
                final provider = ref.read(chatProvider);
                final msgs = provider.getFullPromptPreview();
                if (msgs.isEmpty) return const SizedBox.shrink();
                final parts = TokenEstimator('').analyzePrompt(msgs);
                final total = parts['总计'] ?? 1;
                final ratio = (total / tokenThreshold).clamp(0.0, 1.0);
                if (ratio < 0.5) return const SizedBox.shrink();
                final color = tokenBarColor(ratio);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(children: [
                    Icon(Icons.data_usage, size: 10, color: color),
                    const SizedBox(width: 3),
                    Text('$total / ${tokenThreshold ~/ 1000}K',
                        style: TextStyle(fontSize: 9, color: color)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: ratio,
                          minHeight: 3,
                          backgroundColor: color.withValues(alpha: 0.15),
                          color: color,
                        ),
                      ),
                    ),
                  ]),
                );
              },
            ),
            Row(
              children: [
                Expanded(
                  child: ListenableBuilder(
                    listenable:
                        ref.read(chatProvider).stateVersion, // P1-01: 仅状态变更时重建
                    builder: (context, _) {
                      final provider = ref.read(chatProvider);
                      final offline = !provider.settingsProvider.isOnline;
                      return TextField(
                        controller: controller,
                        focusNode: focusNode,
                        enabled: !offline,
                        style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87),
                        decoration: InputDecoration(
                          hintText: offline ? '离线 — 网络连接不可用' : '输入你的行动...',
                          hintStyle: TextStyle(
                              color: offline
                                  ? Colors.orange
                                  : isDark
                                      ? Colors.grey[500]
                                      : Colors.grey[400]),
                          filled: true,
                          fillColor: fillColor,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 12),
                        ),
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => onSend(),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: controller,
                  builder: (context, _, __) {
                    final cp = ref.read(chatProvider);
                    return ListenableBuilder(
                      listenable: cp.stateVersion, // P1-01: 仅加载/流式状态变更时重建
                      builder: (context, _) {
                        final provider = ref.read(chatProvider);
                        if (provider.isStreaming && onStop != null) {
                          return Container(
                            decoration: const BoxDecoration(
                              color: AppColors.error,
                              shape: BoxShape.circle,
                            ),
                            child: IconButton(
                              icon: const Icon(Icons.stop_rounded,
                                  color: Colors.white),
                              onPressed: onStop,
                              tooltip: '停止生成',
                            ),
                          );
                        }
                        final canSend = controller.text.trim().isNotEmpty &&
                            !provider.isLoading &&
                            provider.isKeyConfigured;
                        return Container(
                          decoration: BoxDecoration(
                            color: canSend
                                ? AppColors.accent
                                : (isDark
                                    ? Colors.grey[700]
                                    : Colors.grey[300]),
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.send_rounded,
                                color: Colors.white),
                            onPressed: canSend ? onSend : null,
                          ),
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
