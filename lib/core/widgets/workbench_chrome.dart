import 'package:flutter/material.dart';

import '../responsive/app_breakpoints.dart';
import '../theme/app_dimensions.dart';
import '../theme/app_spacing.dart';
import 'app_svg_icon.dart';

/// Compact page header for workspace pages.
///
/// Editorial Workbench: a 20 px title, optional quiet subtitle and right-aligned
/// actions, with an optional toolbar row underneath. No large AppBar, no
/// decorative band.
class WorkbenchPageHeader extends StatelessWidget {
  const WorkbenchPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.actions = const <Widget>[],
    this.bottom,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> actions;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surface,
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(leading == null ? 16 : 4, 12, 8, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (leading != null) ...[
                    leading!,
                    const SizedBox(width: 4),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleLarge,
                        ),
                        if (subtitle case final subtitle?) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  ...actions,
                ],
              ),
            ),
            if (bottom case final bottom?) bottom,
            Divider(height: 1, color: scheme.outlineVariant),
          ],
        ),
      ),
    );
  }
}

/// A single compact control row under a page header.
///
/// Height is a minimum, not a fixed value, so tabs can wrap on narrow widths
/// without clipping.
class WorkbenchToolbar extends StatelessWidget {
  const WorkbenchToolbar({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(16, 0, 12, 0),
    this.minHeight = 38,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: minHeight),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: child,
        ),
      ),
    );
  }
}

/// Page-level back / return navigation action shared by workbench pages.
///
/// This is *navigation*, never a CTA: it renders as a quiet primary-coloured
/// text action on desktop and collapses to a tooltip-bearing icon button on
/// compact widths. Features must not build their own return button — a single
/// implementation is what keeps Resource Library and Preset Scenes aligned.
///
/// The compact decision reads the available breakpoint by default. Callers that
/// live inside a shell with its own navigation rail can pass [compact] to
/// resolve from their local content width instead of the whole window.
class WorkbenchBackAction extends StatelessWidget {
  const WorkbenchBackAction({
    super.key,
    required this.onPressed,
    required this.label,
    this.tooltip,
    this.icon = 'back',
    this.compact,
  });

  final VoidCallback onPressed;

  /// Visible on desktop / medium; reused as the accessible name when compact.
  final String label;
  final String? tooltip;
  final String icon;
  final bool? compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCompact = compact ?? AppBreakpoints.isCompact(context);
    if (isCompact) {
      return IconButton(
        onPressed: onPressed,
        tooltip: tooltip ?? label,
        visualDensity: VisualDensity.compact,
        iconSize: 20,
        icon: AppSvgIcon(icon, size: 20),
      );
    }
    return TextButton.icon(
      onPressed: onPressed,
      icon: AppSvgIcon(icon, size: 16),
      label: Text(label),
      style: TextButton.styleFrom(
        minimumSize: const Size(0, AppDimensions.controlHeightSm),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        // A true 32 px control: without this the Material tap-target padding
        // inflates the button to 48 px and the back action stops matching the
        // toolbar's compact rhythm.
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        textStyle: theme.textTheme.labelLarge,
      ),
    );
  }
}

/// Visual state of a manual save action shared by workbench editors.
///
/// These mirror the manual-save contract: an untouched or already-persisted
/// editor offers "Save"; an editor with edits also offers "Save"; a running
/// write shows a spinner and refuses re-entry; a finished write reads "Saved";
/// a refused write reads "Save failed" and stays actionable so the user can
/// retry instead of the UI pretending the write succeeded.
enum WorkbenchSavePhase { idle, dirty, saving, saved, failed }

/// Manual save action for editor toolbars.
///
/// Follows the [WorkbenchBackAction] responsive contract: a labelled
/// primary-coloured text action on desktop and a tooltip-bearing icon button on
/// compact widths. Both forms carry the current state as their accessible name,
/// so the save affordance is never an unlabelled icon. A save in flight is the
/// only state that disables the control — that is what prevents a double tap
/// from issuing a second write.
class WorkbenchSaveAction extends StatelessWidget {
  const WorkbenchSaveAction({
    super.key,
    required this.phase,
    required this.onPressed,
    required this.saveLabel,
    required this.savedLabel,
    required this.savingLabel,
    required this.failedLabel,
    this.compact,
  });

  final WorkbenchSavePhase phase;

  /// Invoked on a real save request. Never called while [phase] is
  /// [WorkbenchSavePhase.saving]; the action disables itself instead.
  final VoidCallback onPressed;

  final String saveLabel;
  final String savedLabel;
  final String savingLabel;
  final String failedLabel;

  /// Overrides the responsive decision for shells that resolve their own
  /// content width; defaults to the page breakpoint.
  final bool? compact;

  String get _label => switch (phase) {
        WorkbenchSavePhase.idle => saveLabel,
        WorkbenchSavePhase.dirty => saveLabel,
        WorkbenchSavePhase.saving => savingLabel,
        WorkbenchSavePhase.saved => savedLabel,
        WorkbenchSavePhase.failed => failedLabel,
      };

  bool get _enabled => phase != WorkbenchSavePhase.saving;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCompact = compact ?? AppBreakpoints.isCompact(context);
    final busy = phase == WorkbenchSavePhase.saving;
    if (isCompact) {
      return IconButton(
        onPressed: _enabled ? onPressed : null,
        tooltip: _label,
        visualDensity: VisualDensity.compact,
        iconSize: 20,
        icon: busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const AppSvgIcon('save', size: 20),
      );
    }
    return TextButton.icon(
      onPressed: _enabled ? onPressed : null,
      icon: busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const AppSvgIcon('save', size: 16),
      label: Text(_label),
      style: TextButton.styleFrom(
        minimumSize: const Size(0, AppDimensions.controlHeightSm),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        textStyle: theme.textTheme.labelLarge,
      ),
    );
  }
}

/// Compact single-line search input for workbench page toolbars.
///
/// Owns the search-field visual contract (34 px height, radius 6,
/// `surfaceContainerHigh` fill, `outlineVariant` border, primary focus ring) so
/// every workbench page shares one treatment instead of re-declaring it.
class WorkbenchSearchField extends StatelessWidget {
  const WorkbenchSearchField({
    super.key,
    required this.hintText,
    this.controller,
    this.onChanged,
    this.fieldKey,
  });

  final String hintText;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;

  /// Applied to the inner [TextField] so tests can address the editable widget
  /// directly rather than the wrapper.
  final Key? fieldKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SizedBox(
      height: 34,
      child: TextField(
        key: fieldKey,
        controller: controller,
        onChanged: onChanged,
        style: theme.textTheme.bodyMedium,
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: scheme.surfaceContainerHigh,
          hintText: hintText,
          prefixIcon: const Padding(
            padding: EdgeInsets.only(left: 10, right: 6),
            child: AppSvgIcon('search', size: 16),
          ),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 0, minHeight: 0),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: scheme.outlineVariant),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: scheme.primary, width: 1.2),
          ),
        ),
      ),
    );
  }
}

/// A quiet text tab: label + 2 px underline when selected.
///
/// Replaces filled pill/`ChoiceChip` filters where the control is a single
/// choice among a small set.
///
/// Geometry contract: the control is exactly [AppDimensions.controlHeightSm]
/// tall — the same height as `AppSelect.toolbar` — and the label is centered on
/// that box. The selected underline is a bottom decoration that does not take
/// part in the label's layout, so selected and unselected tabs measure the same
/// and a toolbar row of tabs and selects shares one visual text baseline.
class WorkbenchTabButton extends StatelessWidget {
  const WorkbenchTabButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      selected: selected,
      button: true,
      child: SizedBox(
        height: AppDimensions.controlHeightSm,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(6),
            hoverColor: scheme.onSurface.withValues(alpha: 0.04),
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color:
                          selected ? scheme.onSurface : scheme.onSurfaceVariant,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
                if (selected)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Center(
                      child: Container(
                        key: const Key('workbench-tab-underline'),
                        height: 2,
                        width: 18,
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Wrapping container for [WorkbenchTabButton]s.
class WorkbenchTabBar extends StatelessWidget {
  const WorkbenchTabBar({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 4,
        runSpacing: 0,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: children,
      );
}

/// Label / value row used for state matrices and inspectors.
///
/// Preferred over one-card-per-attribute: hierarchy comes from alignment and
/// typography, not containers.
class WorkbenchPropertyRow extends StatelessWidget {
  const WorkbenchPropertyRow({
    super.key,
    required this.label,
    required this.value,
    this.labelWidth = 104,
    this.valueColor,
    this.trailing,
  });

  final String label;
  final String value;
  final double labelWidth;
  final Color? valueColor;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: labelWidth,
            child: Text(
              label,
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(color: valueColor),
            ),
          ),
          if (trailing case final trailing?) ...[
            const SizedBox(width: AppSpacing.sm),
            trailing,
          ],
        ],
      ),
    );
  }
}
