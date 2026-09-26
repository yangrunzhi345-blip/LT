import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/responsive/responsive.dart';
import '../../../../../core/theme/app_radius.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../providers/riverpod_providers.dart';
import '../../../../../utils/platform_utils.dart';
import '../../../../../screens/chat/widgets/quick_menu.dart';
import '../../../../../l10n/generated/app_localizations.dart';
import '../../../../../l10n/generated/app_localizations_zh.dart';

/// 现代化场景会话输入交互栏
/// 包含 RPG 属性与背包快捷入口、Token 监控以及平滑发送/停止控制
class SessionInputBar extends ConsumerWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSend;
  final VoidCallback? onStop;
  final VoidCallback? onShowInventory;
  final VoidCallback? onShowCharacterSheet;
  final VoidCallback? onShowWordCount;
  final VoidCallback? onShowSettings;
  final VoidCallback? onShowSceneCharacters;

  const SessionInputBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onSend,
    this.onStop,
    this.onShowInventory,
    this.onShowCharacterSheet,
    this.onShowWordCount,
    this.onShowSettings,
    this.onShowSceneCharacters,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final provider = ref.watch(chatProvider);
    final isGenerating =
        provider.isLoading || provider.isStreaming || provider.isSettling;
    final offline = !provider.settingsProvider.isOnline;
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();

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
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppBreakpoints.narrativeMaxWidth,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 主输入行
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // 快捷 RPG 功能菜单 (角色、背包、任务、地图、字数)
                  QuickMenuButton(
                    isDark: isDark,
                    onShowInventory: onShowInventory,
                    onShowSkills: onShowCharacterSheet,
                    onShowWordCount: onShowWordCount,
                    onShowSettings: onShowSettings,
                    onShowSceneCharacters: onShowSceneCharacters,
                  ),
                  const SizedBox(width: 8),

                  // 文本输入框
                  Expanded(
                    child: Container(
                      constraints: const BoxConstraints(maxHeight: 140),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        border: Border.all(
                          color:
                              colorScheme.outlineVariant.withValues(alpha: 0.5),
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 4),
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
                            hintText: offline
                                ? l10n.sessionOfflineHint
                                : l10n.sessionInputHint,
                            hintStyle: theme.textTheme.bodyMedium?.copyWith(
                              color: offline
                                  ? Colors.orange
                                  : colorScheme.onSurfaceVariant
                                      .withValues(alpha: 0.7),
                            ),
                            border: InputBorder.none,
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 8),
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
                      tooltip: l10n.stopGenerationAction,
                      style: IconButton.styleFrom(
                        backgroundColor: colorScheme.errorContainer,
                        foregroundColor: colorScheme.onErrorContainer,
                      ),
                      icon: const Icon(Icons.stop_rounded, size: 20),
                    )
                  else
                    IconButton.filled(
                      onPressed: offline ? null : onSend,
                      tooltip: '${l10n.sendAction} (Enter)',
                      icon: const Icon(Icons.arrow_upward_rounded, size: 20),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
