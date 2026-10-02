import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lt_dialogue/core/theme/app_colors.dart';
import 'package:lt_dialogue/core/theme/app_theme.dart';

/// WCAG 2.x relative-luminance contrast for the selection-control contract.
///
/// The light theme supports 12 dynamic `colorSeeds`, so contrast must be proved
/// numerically for every seed rather than eyeballed on the default palette.
void main() {
  // ── WCAG relative luminance / contrast helpers ──
  double linearize(double channel) => channel <= 0.04045
      ? channel / 12.92
      : math.pow((channel + 0.055) / 1.055, 2.4).toDouble();

  double luminance(Color color) =>
      0.2126 * linearize(color.r) +
      0.7152 * linearize(color.g) +
      0.0722 * linearize(color.b);

  double contrastRatio(Color a, Color b) {
    final la = luminance(a);
    final lb = luminance(b);
    final lighter = math.max(la, lb);
    final darker = math.min(la, lb);
    return (lighter + 0.05) / (darker + 0.05);
  }

  Color? resolveLabel(ChipThemeData chip, Set<WidgetState> states) =>
      WidgetStateProperty.resolveAs<Color?>(chip.labelStyle!.color, states);

  Color? resolveBackground(ChipThemeData chip, Set<WidgetState> states) =>
      chip.color!.resolve(states);

  // The unselected fill is the darkest realistic control background, so it is
  // the conservative base for compositing the translucent selected wash.
  Color selectedEffectiveBackground(ChipThemeData chip) {
    final base = resolveBackground(chip, const <WidgetState>{})!;
    final selected =
        resolveBackground(chip, const <WidgetState>{WidgetState.selected})!;
    return Color.alphaBlend(selected, base);
  }

  double selectedBorderContrast(ChipThemeData chip) {
    final base = resolveBackground(chip, const <WidgetState>{})!;
    final side = WidgetStateProperty.resolveAs<BorderSide?>(
      chip.side,
      const <WidgetState>{WidgetState.selected},
    )!;
    return contrastRatio(side.color, base);
  }

  final seeds = <String, Color>{
    'default': AppColors.primary,
    ...AppColors.colorSeeds,
  };

  group('Light theme selection contrast (WCAG AA 4.5:1)', () {
    for (final entry in seeds.entries) {
      test('${entry.key} keeps readable selected and unselected labels', () {
        final theme = AppTheme.light(colorSchemeSeed: entry.value);
        final chip = theme.chipTheme;
        final scheme = theme.colorScheme;

        final unselectedBg = resolveBackground(chip, const <WidgetState>{})!;
        final unselectedFg = resolveLabel(chip, const <WidgetState>{})!;
        final selectedFg =
            resolveLabel(chip, const <WidgetState>{WidgetState.selected})!;
        final selectedBg = selectedEffectiveBackground(chip);

        final unselectedRatio = contrastRatio(unselectedFg, unselectedBg);
        final selectedRatio = contrastRatio(selectedFg, selectedBg);

        // ignore: avoid_print
        print(
            '[contrast:${entry.key}] unselected=${unselectedRatio.toStringAsFixed(2)} '
            'selected=${selectedRatio.toStringAsFixed(2)} '
            'border=${selectedBorderContrast(chip).toStringAsFixed(2)}');

        expect(
          unselectedRatio,
          greaterThanOrEqualTo(4.5),
          reason: '${entry.key}: unselected label vs background',
        );
        expect(
          selectedRatio,
          greaterThanOrEqualTo(4.5),
          reason: '${entry.key}: selected label vs selected background',
        );

        // The unselected control must never look disabled: its label is the
        // full-strength on-surface colour, not the 38% disabled colour.
        final disabledFg =
            resolveLabel(chip, const <WidgetState>{WidgetState.disabled})!;
        expect(unselectedFg, scheme.onSurface);
        expect(unselectedFg, isNot(disabledFg));

        // Selection is visible: a tinted fill plus a primary border that is
        // clearly distinguishable from the unselected surface.
        expect(selectedBg, isNot(unselectedBg));
        expect(
          contrastRatio(selectedBg, unselectedBg),
          greaterThanOrEqualTo(1.05),
          reason: '${entry.key}: selected fill must be visibly tinted',
        );
        expect(
          selectedBorderContrast(chip),
          greaterThanOrEqualTo(1.5),
          reason: '${entry.key}: selected border must be distinguishable',
        );
      });
    }
  });

  group('Dark theme selection contrast', () {
    for (final entry in seeds.entries) {
      test('${entry.key} keeps readable labels in dark mode', () {
        final theme = AppTheme.dark(colorSchemeSeed: entry.value);
        final chip = theme.chipTheme;

        final unselectedBg = resolveBackground(chip, const <WidgetState>{})!;
        final unselectedFg = resolveLabel(chip, const <WidgetState>{})!;
        final selectedFg =
            resolveLabel(chip, const <WidgetState>{WidgetState.selected})!;
        final selectedBg = Color.alphaBlend(
          resolveBackground(chip, const <WidgetState>{WidgetState.selected})!,
          unselectedBg,
        );

        expect(
          contrastRatio(unselectedFg, unselectedBg),
          greaterThanOrEqualTo(4.5),
          reason: '${entry.key}: dark unselected label',
        );
        expect(
          contrastRatio(selectedFg, selectedBg),
          greaterThanOrEqualTo(4.5),
          reason: '${entry.key}: dark selected label',
        );
      });
    }
  });

  group('SegmentedButton state contract', () {
    for (final entry in seeds.entries) {
      test('${entry.key} selected segment is distinct and readable', () {
        final theme = AppTheme.light(colorSchemeSeed: entry.value);
        final style = theme.segmentedButtonTheme.style!;

        final unselectedBg =
            style.backgroundColor!.resolve(const <WidgetState>{})!;
        final selectedBg = style.backgroundColor!
            .resolve(const <WidgetState>{WidgetState.selected})!;
        final selectedFg = style.foregroundColor!
            .resolve(const <WidgetState>{WidgetState.selected})!;
        final selectedEffective = Color.alphaBlend(selectedBg, unselectedBg);

        expect(
          contrastRatio(selectedFg, selectedEffective),
          greaterThanOrEqualTo(4.5),
          reason: '${entry.key}: segmented selected label',
        );
        expect(selectedBg, isNot(unselectedBg));
      });
    }
  });
}
