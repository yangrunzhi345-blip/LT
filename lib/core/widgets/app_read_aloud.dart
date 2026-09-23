import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/read_aloud/read_aloud_contracts.dart';
import '../../providers/riverpod_providers.dart';
import '../../services/read_aloud/read_aloud_controller.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../l10n/generated/app_localizations_en.dart';

/// 单块正文的朗读开关。
///
/// 状态完全来自全局 [ReadAloudController]：图标与可点击性由 Authority 的真实
/// 状态决定，Widget 自身不保存任何“是否正在播放”的伪状态。
///
/// - 该来源未在朗读 → 点击开始朗读；
/// - 该来源正在朗读 → 点击停止；
/// - 平台不支持 / 朗读总开关关闭 → 禁用并通过 tooltip 说明原因。
class AppReadAloudButton extends ConsumerWidget {
  const AppReadAloudButton({
    super.key,
    required this.sourceId,
    required this.sourceType,
    this.sources,
    this.text,
    this.label,
    this.tooltip,
    this.iconSize = 18,
    this.dense = true,
  }) : assert(
          sources != null || text != null,
          'AppReadAloudButton 需要 sources 或 text 之一',
        );

  /// 会话级来源 id（消息 id / 资源 id）。
  final String sourceId;
  final ReadAloudSourceType sourceType;

  /// 多来源（例如整份资源按 Part 连续朗读）。
  final List<ReadAloudSource>? sources;

  /// 单段正文。
  final String? text;

  /// 单段正文标题。
  final String? label;

  /// 空闲态 tooltip；缺省为「朗读」。
  final String? tooltip;

  final double iconSize;
  final bool dense;

  List<ReadAloudSource> get _sources =>
      sources ??
      <ReadAloudSource>[
        ReadAloudSource(id: sourceId, text: text ?? '', label: label),
      ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(readAloudControllerProvider);
    final state = controller.state;
    // 平台没有系统语音合成后端时不渲染死按钮：能力与原因在设置页与
    // 手动朗读入口统一说明，避免在每个消息气泡/段落上留下灰色占位。
    if (!state.capability.supported) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsEn();
    // 会话命中（单段朗读）或段命中（连续朗读映射到本段）都算“正在朗读我”。
    final isThisSource =
        state.isActiveSource(sourceId) || state.isSpeakingChunk(sourceId);

    final VoidCallback? onPressed;
    final String hint;
    if (!state.enabled) {
      onPressed = null;
      hint = l10n.readAloudDisabledInSettings;
    } else if (isThisSource) {
      onPressed = () => controller.stop();
      hint = l10n.readAloudStop;
    } else {
      onPressed = () => controller.play(
            sessionId: sourceId,
            sourceType: sourceType,
            sources: _sources,
          );
      hint = tooltip ?? l10n.readAloudStart;
    }

    return IconButton(
      onPressed: onPressed,
      iconSize: iconSize,
      tooltip: hint,
      visualDensity: dense ? VisualDensity.compact : VisualDensity.standard,
      icon: Icon(
        isThisSource ? Icons.stop_circle_outlined : Icons.volume_up_rounded,
        color: isThisSource ? scheme.primary : null,
      ),
    );
  }
}

/// 全局朗读传输控件：上一段 / 暂停恢复 / 停止 / 下一段 + 进度。
///
/// 仅在 [sourceId] 正是当前朗读会话时渲染——状态来自 Authority，而不是本地
/// 伪状态。窄屏使用 [Wrap]，不会横向溢出。
class AppReadAloudControls extends ConsumerWidget {
  const AppReadAloudControls({
    super.key,
    required this.sourceId,
    this.showProgress = true,
  });

  final String sourceId;
  final bool showProgress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(readAloudControllerProvider);
    final state = controller.state;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsEn();

    if (!state.capability.supported) return const SizedBox.shrink();
    if (!state.isActiveSource(sourceId) && !state.isSpeakingChunk(sourceId)) {
      return const SizedBox.shrink();
    }

    final canControl = state.enabled;
    final canGoPrevious = canControl && state.segmentCount > 0;
    final canGoNext = canControl &&
        state.segmentIndex >= 0 &&
        state.segmentIndex + 1 < state.segmentCount;

    final Widget playPauseIcon;
    final String playPauseHint;
    final VoidCallback? onPlayPause;
    switch (state.status) {
      case ReadAloudStatus.playing:
        playPauseIcon = const Icon(Icons.pause_rounded);
        playPauseHint = state.capability.supportsPause
            ? l10n.readAloudPause
            : l10n.readAloudPauseRestart;
        onPlayPause = () => controller.pause();
      case ReadAloudStatus.paused:
        playPauseIcon = const Icon(Icons.play_arrow_rounded);
        playPauseHint = l10n.readAloudResume;
        onPlayPause = () => controller.resume();
      case ReadAloudStatus.preparing:
        playPauseIcon = const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
        playPauseHint = l10n.readAloudPreparing;
        onPlayPause = null;
      case ReadAloudStatus.idle:
      case ReadAloudStatus.stopped:
      case ReadAloudStatus.completed:
      case ReadAloudStatus.error:
        playPauseIcon = const Icon(Icons.play_arrow_rounded);
        playPauseHint = l10n.readAloudResume;
        onPlayPause = canControl ? () => controller.replayCurrent() : null;
    }

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        IconButton(
          onPressed: canGoPrevious ? () => controller.previous() : null,
          iconSize: 20,
          visualDensity: VisualDensity.compact,
          tooltip: l10n.readAloudPrevious,
          icon: const Icon(Icons.skip_previous_rounded),
        ),
        IconButton(
          onPressed: onPlayPause,
          iconSize: 20,
          visualDensity: VisualDensity.compact,
          tooltip: playPauseHint,
          icon: playPauseIcon,
        ),
        IconButton(
          onPressed: canControl ? () => controller.stop() : null,
          iconSize: 20,
          visualDensity: VisualDensity.compact,
          tooltip: l10n.readAloudStop,
          icon: const Icon(Icons.stop_rounded),
        ),
        IconButton(
          onPressed: canGoNext ? () => controller.next() : null,
          iconSize: 20,
          visualDensity: VisualDensity.compact,
          tooltip: l10n.readAloudNext,
          icon: const Icon(Icons.skip_next_rounded),
        ),
        if (showProgress && state.segmentIndex >= 0 && state.segmentCount > 0)
          Text(
            l10n.readAloudSegmentProgress(
              state.segmentIndex + 1,
              state.segmentCount,
            ),
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}
