import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/widgets/app_svg_icon.dart';
import '../../l10n/generated/app_localizations.dart';

/// Non-blocking user feedback.
///
/// All transient messages (success / error / warning / info) are rendered as a
/// single card centred in the viewport — not a bottom SnackBar. Identical
/// messages shown twice within [_dedupeWindow] collapse into one, and a new
/// message always replaces the current one, so at most one feedback exists.
enum AppFeedbackType { success, error, warning, info }

class AppFeedback {
  AppFeedback._();

  /// At most one feedback is visible; a new one replaces it.
  static OverlayEntry? _currentEntry;
  static OverlayState? _lastOverlay;
  static String? _lastKey;
  static DateTime? _lastShownAt;

  static const Duration _dedupeWindow = Duration(seconds: 2);
  static const Duration _defaultDuration = Duration(seconds: 4);

  /// Preferred maximum card width; still clamped by the viewport.
  static const double _maxWidth = 480;
  static const double _viewportMargin = 16;

  static void success(BuildContext context, String message,
          {String? actionLabel, VoidCallback? onAction, Duration? duration}) =>
      show(context, message,
          type: AppFeedbackType.success,
          actionLabel: actionLabel,
          onAction: onAction,
          duration: duration);

  static void error(BuildContext context, String message,
          {String? actionLabel, VoidCallback? onAction, Duration? duration}) =>
      show(context, message,
          type: AppFeedbackType.error,
          actionLabel: actionLabel,
          onAction: onAction,
          duration: duration);

  static void warning(BuildContext context, String message,
          {String? actionLabel, VoidCallback? onAction, Duration? duration}) =>
      show(context, message,
          type: AppFeedbackType.warning,
          actionLabel: actionLabel,
          onAction: onAction,
          duration: duration);

  static void info(BuildContext context, String message,
          {String? actionLabel, VoidCallback? onAction, Duration? duration}) =>
      show(context, message,
          type: AppFeedbackType.info,
          actionLabel: actionLabel,
          onAction: onAction,
          duration: duration);

  static void show(
    BuildContext context,
    String message, {
    AppFeedbackType type = AppFeedbackType.info,
    String? actionLabel,
    VoidCallback? onAction,
    Duration? duration,
  }) {
    // Root overlay: works across nested Navigators / Scaffolds and never
    // confines feedback to a page-local region. No overlay -> no-op, never a
    // silent fall back to a bottom SnackBar.
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    final now = DateTime.now();
    final key = '${type.name}:$message';
    if (identical(_lastOverlay, overlay) &&
        _lastKey == key &&
        _lastShownAt != null &&
        now.difference(_lastShownAt!) < _dedupeWindow) {
      return;
    }
    _lastOverlay = overlay;
    _lastKey = key;
    _lastShownAt = now;

    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final spec = switch (type) {
      AppFeedbackType.success => (
          icon: 'check_circle',
          color: scheme.primary,
          label: l10n?.feedbackSuccess ?? 'Success'
        ),
      AppFeedbackType.error => (
          icon: 'error',
          color: scheme.error,
          label: l10n?.feedbackError ?? 'Error'
        ),
      AppFeedbackType.warning => (
          icon: 'warning',
          color: scheme.tertiary,
          label: l10n?.feedbackWarning ?? 'Warning'
        ),
      AppFeedbackType.info => (
          icon: 'info',
          color: scheme.secondary,
          label: l10n?.feedbackInfo ?? 'Info'
        ),
    };

    // Replace any current feedback: never stack.
    _hideCurrent();

    final entry = OverlayEntry(
      builder: (_) => _CenteredFeedbackHost(
        message: message,
        icon: spec.icon,
        iconColor: spec.color,
        semanticLabel: spec.label,
        actionLabel: actionLabel,
        onAction: onAction == null
            ? null
            : () {
                _hideCurrent();
                onAction();
              },
        duration: duration ?? _defaultDuration,
        onDismiss: _hideCurrent,
      ),
    );
    _currentEntry = entry;
    overlay.insert(entry);
  }

  /// Removes the current entry.
  ///
  /// Every path (replacement, timeout, action tap) funnels through here, so the
  /// entry is removed exactly once and never left mounted. The auto-dismiss
  /// [Timer] lives in [_FeedbackCardState] and is cancelled on dispose.
  static void _hideCurrent() {
    final entry = _currentEntry;
    _currentEntry = null;
    if (entry != null && entry.mounted) {
      entry.remove();
    }
  }
}

/// Centres the feedback card in the safe area without intercepting input.
///
/// `SafeArea` + `Align` only hit-test their child, so taps, scrolls and keyboard
/// input outside the card fall through to the app — feedback is non-modal.
class _CenteredFeedbackHost extends StatelessWidget {
  const _CenteredFeedbackHost({
    required this.message,
    required this.icon,
    required this.iconColor,
    required this.semanticLabel,
    required this.duration,
    required this.onDismiss,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final String icon;
  final Color iconColor;
  final String semanticLabel;
  final Duration duration;
  final VoidCallback onDismiss;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: Alignment.center,
        child: _FeedbackCard(
          message: message,
          icon: icon,
          iconColor: iconColor,
          semanticLabel: semanticLabel,
          actionLabel: actionLabel,
          onAction: onAction,
          duration: duration,
          onDismiss: onDismiss,
        ),
      ),
    );
  }
}

/// The feedback card itself: quiet neutral surface, semantic icon, fade/scale
/// entrance. Owns the auto-dismiss timer so it is cancelled when the entry is
/// disposed (route change, teardown) rather than leaking.
class _FeedbackCard extends StatefulWidget {
  const _FeedbackCard({
    required this.message,
    required this.icon,
    required this.iconColor,
    required this.semanticLabel,
    required this.duration,
    required this.onDismiss,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final String icon;
  final Color iconColor;
  final String semanticLabel;
  final Duration duration;
  final VoidCallback onDismiss;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  State<_FeedbackCard> createState() => _FeedbackCardState();
}

class _FeedbackCardState extends State<_FeedbackCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    duration: const Duration(milliseconds: 120),
    vsync: this,
  )..forward();
  late final CurvedAnimation _curve =
      CurvedAnimation(parent: _controller, curve: Curves.easeOut);
  late final Animation<double> _scale =
      Tween<double>(begin: 0.98, end: 1).animate(_curve);
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.duration, widget.onDismiss);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final maxWidth = math.min(
      AppFeedback._maxWidth,
      MediaQuery.sizeOf(context).width - AppFeedback._viewportMargin * 2,
    );
    return FadeTransition(
      opacity: _curve,
      child: ScaleTransition(
        scale: _scale,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Material(
            key: const Key('app-feedback-surface'),
            color: scheme.surfaceContainerHigh,
            elevation: 3,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: scheme.outlineVariant),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Semantics(
                liveRegion: true,
                label: '${widget.semanticLabel}：${widget.message}',
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    AppSvgIcon(widget.icon, color: widget.iconColor, size: 20),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        widget.message,
                        key: const Key('app-feedback-message'),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    if (widget.actionLabel != null &&
                        widget.onAction != null) ...[
                      const SizedBox(width: 4),
                      TextButton(
                        key: const Key('app-feedback-action'),
                        onPressed: widget.onAction,
                        child: Text(widget.actionLabel!),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
