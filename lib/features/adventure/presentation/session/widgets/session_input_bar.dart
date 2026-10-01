import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/responsive/responsive.dart';
import '../../../../../core/theme/app_radius.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../providers/riverpod_providers.dart';
import '../../../../../utils/platform_utils.dart';
import '../../../../../core/widgets/app_svg_icon.dart';
import '../../../../../l10n/generated/app_localizations.dart';
import '../../../../../l10n/generated/app_localizations_zh.dart';

/// Narrative input with keyboard shortcuts and send/stop controls.
class SessionInputBar extends ConsumerWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSend;
  final VoidCallback? onStop;

  const SessionInputBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onSend,
    this.onStop,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
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
                  // 文本输入框
                  Expanded(
                    child: Container(
                      constraints: const BoxConstraints(maxHeight: 140),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHigh
                            .withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: Border.all(color: colorScheme.outlineVariant),
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
                                  ? colorScheme.error
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
                    _InputActionButton(
                      onPressed: onStop,
                      tooltip: l10n.stopGenerationAction,
                      background: colorScheme.errorContainer,
                      foreground: colorScheme.onErrorContainer,
                      icon: 'stop',
                    )
                  else
                    _InputActionButton(
                      onPressed: offline ? null : onSend,
                      tooltip: '${l10n.sendAction} (Enter)',
                      background: colorScheme.primary,
                      foreground: colorScheme.onPrimary,
                      icon: 'send',
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

/// Compact, squared action button for the narrative input row.
///
/// Deliberately not a circular `IconButton.filled`: the session should read as
/// a narrative transcript control, not a chat app.
class _InputActionButton extends StatelessWidget {
  const _InputActionButton({
    required this.onPressed,
    required this.tooltip,
    required this.background,
    required this.foreground,
    required this.icon,
  });

  final VoidCallback? onPressed;
  final String tooltip;
  final Color background;
  final Color foreground;
  final String icon;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 34,
        height: 34,
        child: Material(
          color: onPressed == null
              ? background.withValues(alpha: 0.4)
              : background,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: Center(
              child: AppSvgIcon(icon, size: 16, color: foreground),
            ),
          ),
        ),
      ),
    );
  }
}
