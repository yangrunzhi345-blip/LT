import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_spacing.dart';
import '../../../../../providers/riverpod_providers.dart';
import '../../../../../utils/platform_utils.dart';
import '../../../../../utils/token_estimator.dart';
import '../../../../../widgets/token_progress_bar.dart';
import '../../../../../screens/chat/widgets/quick_menu.dart';

/// 现代化场景会话输入交互栏
/// 包含 RPG 属性与背包快捷入口、Token 监控以及平滑发送/停止控制
class SessionInputBar extends ConsumerWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSend;
  final VoidCallback? onStop;
  final VoidCallback? onShowQuests;
  final VoidCallback? onShowInventory;
  final VoidCallback? onShowCharacterSheet;
  final VoidCallback? onShowMap;
  final VoidCallback? onShowWordCount;
  final VoidCallback? onShowSettings;

  const SessionInputBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onSend,
    this.onStop,
    this.onShowQuests,
    this.onShowInventory,
    this.onShowCharacterSheet,
    this.onShowMap,
    this.onShowWordCount,
    this.onShowSettings,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final provider = ref.watch(chatProvider);
    final isGenerating = provider.isLoading || provider.isStreaming;
    final offline = !provider.settingsProvider.isOnline;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.35),
          ),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs + 2,
        AppSpacing.md,
        AppSpacing.sm + MediaQuery.of(context).viewPadding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Token 消耗监控进度微条
          ListenableBuilder(
            listenable: provider.tokenVersion,
            builder: (context, _) {
              final msgs = provider.getFullPromptPreview();
              if (msgs.isEmpty) return const SizedBox.shrink();
              final parts = TokenEstimator('').analyzePrompt(msgs);
              final total = parts['总计'] ?? 1;
              final ratio = (total / tokenThreshold).clamp(0.0, 1.0);
              if (ratio < 0.5) return const SizedBox.shrink();
              final color = tokenBarColor(ratio);
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Icon(Icons.data_usage_rounded, size: 12, color: color),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        '$total / ${tokenThreshold ~/ 1000}K Tokens',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          color: color,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
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
                  ],
                ),
              );
            },
          ),

          // 主输入行
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // 快捷 RPG 功能菜单 (角色、背包、任务、地图、字数)
              QuickMenuButton(
                isDark: isDark,
                onShowQuests: onShowQuests,
                onShowInventory: onShowInventory,
                onShowSkills: onShowCharacterSheet,
                onShowMap: onShowMap,
                onShowWordCount: onShowWordCount,
                onShowSettings: onShowSettings,
              ),
              const SizedBox(width: 8),

              // 文本输入框
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 140),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  child: CallbackShortcuts(
                    bindings: {
                      const SingleActivator(LogicalKeyboardKey.enter): () {
                        if (PlatformUtils.isDesktop) {
                          if (!isGenerating && !offline) {
                            onSend();
                          }
                        }
                      },
                    },
                    child: TextField(
                      controller: controller,
                      focusNode: focusNode,
                      enabled: !offline,
                      maxLines: null,
                      textInputAction: PlatformUtils.isDesktop
                          ? TextInputAction.send
                          : TextInputAction.newline,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        height: 1.4,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText:
                            offline ? '离线 — 网络连接不可用' : '描述你的行动、对话或直接输入指令...',
                        hintStyle: theme.textTheme.bodyMedium?.copyWith(
                          color: offline
                              ? Colors.orange
                              : colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.7),
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // 发送 / 停止生成 切换按钮
              if (isGenerating)
                IconButton.filled(
                  onPressed: onStop,
                  tooltip: '停止生成',
                  style: IconButton.styleFrom(
                    backgroundColor: colorScheme.errorContainer,
                    foregroundColor: colorScheme.onErrorContainer,
                  ),
                  icon: const Icon(Icons.stop_rounded, size: 20),
                )
              else
                IconButton.filled(
                  onPressed: offline ? null : onSend,
                  tooltip: '发送 (Enter)',
                  icon: const Icon(Icons.arrow_upward_rounded, size: 20),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
