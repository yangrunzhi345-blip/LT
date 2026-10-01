import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/workbench_section.dart';
import '../../../../providers/riverpod_providers.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../l10n/generated/app_localizations_zh.dart';

/// Appearance and reading preferences remain owned by SettingsProvider.
class AppearanceSection extends ConsumerWidget {
  const AppearanceSection({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();
    final chat = ref.watch(chatProvider);
    final settings = chat.settingsProvider;
    final currentSeed = settings.colorSeed ?? AppColors.primary;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      WorkbenchSection(
          title: l10n.appearanceSectionTitle,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(l10n.themeModeLabel),
            const SizedBox(height: AppSpacing.sm),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final mode in ThemeMode.values)
                ChoiceChip(
                    key: ValueKey('theme-mode-${mode.name}'),
                    showCheckmark: false,
                    selected: settings.themeMode == mode,
                    label: Text(switch (mode) {
                      ThemeMode.light => l10n.themeLight,
                      ThemeMode.dark => l10n.themeDark,
                      ThemeMode.system => l10n.themeSystem
                    }),
                    onSelected: (_) => chat.updateThemeMode(mode)),
            ]),
            const SizedBox(height: AppSpacing.lg),
            Text(l10n.themeColorPalette),
            const SizedBox(height: AppSpacing.sm),
            Wrap(spacing: 12, runSpacing: 12, children: [
              for (final entry in AppColors.colorSeeds.entries)
                Semantics(
                    button: true,
                    selected: currentSeed.toARGB32() == entry.value.toARGB32(),
                    label: entry.key,
                    child: Tooltip(
                        message: entry.key,
                        child: InkWell(
                            onTap: () => chat.setColorSeed(entry.value),
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                                width: 48,
                                height: 48,
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                    border: Border.all(
                                        width: currentSeed.toARGB32() ==
                                                entry.value.toARGB32()
                                            ? 2
                                            : 1,
                                        color: currentSeed.toARGB32() ==
                                                entry.value.toARGB32()
                                            ? Theme.of(context)
                                                .colorScheme
                                                .onSurface
                                            : Theme.of(context)
                                                .colorScheme
                                                .outlineVariant),
                                    borderRadius: BorderRadius.circular(6)),
                                child: ColoredBox(color: entry.value))))),
            ]),
          ])),
      const SizedBox(height: 24),
      WorkbenchSection(
          title: l10n.previewTypographyTitle,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(l10n.chatFontSizeLabel(settings.chatFontSize.toInt())),
            Slider(
                key: const Key('reading-font-size'),
                value: settings.chatFontSize,
                min: 12,
                max: 22,
                divisions: 10,
                label: '${settings.chatFontSize.toInt()}',
                onChanged: chat.setChatFontSize),
            Text(l10n.previewTypographySample,
                style: TextStyle(fontSize: settings.chatFontSize, height: 1.8)),
          ])),
      const SizedBox(height: 24),
      WorkbenchSection(
          title: l10n.readingScrollTitle,
          child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.autoScrollLabel),
              subtitle: Text(settings.autoScrollDuringGeneration
                  ? l10n.autoScrollSubtitleOn
                  : l10n.autoScrollSubtitleOff),
              value: settings.autoScrollDuringGeneration,
              onChanged: settings.setAutoScrollDuringGeneration)),
    ]);
  }
}
