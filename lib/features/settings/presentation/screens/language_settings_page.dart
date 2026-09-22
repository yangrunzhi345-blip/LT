import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/localization/app_locale.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_page_scaffold.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../providers/riverpod_providers.dart';

/// 设置中心 — 独立语言切换页面
///
/// 允许用户在 5 种支持的语言之间自由热切换。
/// 切换后界面即时生效，无须重启应用；页面栈与数据完全保留。
class LanguageSettingsPage extends ConsumerWidget {
  const LanguageSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final controller = ref.watch(appLocaleControllerProvider);
    final currentLocale = controller.currentLocale;

    return AppPageScaffold(
      title: l10n?.languageSettingTitle ?? '语言',
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Padding(
            padding: const EdgeInsets.only(
              left: AppSpacing.xs,
              bottom: AppSpacing.sm,
            ),
            child: Text(
              l10n?.languageSettingSubtitle ?? '应用显示语言',
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Card(
            elevation: 0,
            color: scheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              side: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: 0.35),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: AppLocale.values.length,
              separatorBuilder: (_, __) => Divider(
                height: 1,
                color: scheme.outlineVariant.withValues(alpha: 0.25),
              ),
              itemBuilder: (context, index) {
                final option = AppLocale.values[index];
                final isSelected = option == currentLocale;

                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: 2,
                  ),
                  title: Text(
                    option.nativeName,
                    style: TextStyle(
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected ? scheme.primary : scheme.onSurface,
                    ),
                  ),
                  subtitle: Text(
                    _englishSubtitle(option),
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  trailing: isSelected
                      ? Icon(
                          Icons.check_circle_rounded,
                          color: scheme.primary,
                        )
                      : null,
                  onTap: () {
                    if (!isSelected) {
                      ref.read(appLocaleControllerProvider).setLocale(option);
                    }
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static String _englishSubtitle(AppLocale locale) {
    return switch (locale) {
      AppLocale.en => 'English',
      AppLocale.zhHans => 'Simplified Chinese',
      AppLocale.zhHant => 'Traditional Chinese',
      AppLocale.ja => 'Japanese',
      AppLocale.ko => 'Korean',
    };
  }
}
