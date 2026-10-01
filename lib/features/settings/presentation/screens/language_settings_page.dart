import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/localization/app_locale.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_page_scaffold.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../l10n/generated/app_localizations_zh.dart';
import '../../../../providers/riverpod_providers.dart';

/// 设置中心 — 独立语言切换页面
///
/// 允许用户在 5 种支持的语言之间自由热切换。
/// 切换后界面即时生效，无须重启应用；页面栈与数据完全保留。
class LanguageSettingsPage extends ConsumerWidget {
  const LanguageSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();

    return AppPageScaffold(
        title: l10n.languageSettingTitle,
        body: const SingleChildScrollView(
            padding: EdgeInsets.all(AppSpacing.md),
            child: LanguageSettingsContent()));
  }
}

class LanguageSettingsContent extends ConsumerWidget {
  const LanguageSettingsContent({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();
    final controller = ref.watch(appLocaleControllerProvider);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(l10n.languageSettingSubtitle),
      for (final option in AppLocale.values)
        ListTile(
          selected: option == controller.currentLocale,
          title: Text(option.nativeName),
          subtitle: Text(_englishSubtitle(option)),
          onTap: () => controller.setLocale(option),
        ),
    ]);
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
