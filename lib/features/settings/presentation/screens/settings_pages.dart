import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/widgets/app_page_scaffold.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../l10n/generated/app_localizations_zh.dart';
import '../../../../providers/riverpod_providers.dart';
import '../widgets/appearance_section.dart';
import '../widgets/data_management_section.dart';
import '../widgets/model_params_section.dart';
import '../widgets/provider_config_section.dart';
import 'chat_transfer_pages.dart';
import 'language_settings_page.dart';

/// Main navigation entry for settings and data management.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key, this.onMenuPressed});

  final VoidCallback? onMenuPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();
    final isConfigured = ref.watch(chatProvider).isKeyConfigured;
    final localeController = ref.watch(appLocaleControllerProvider);

    return AppPageScaffold(
      title: l10n.settingsCenter,
      actions: [
        if (onMenuPressed != null)
          IconButton(
            tooltip: l10n.sidebarExpand,
            icon: const Icon(Icons.menu),
            onPressed: onMenuPressed,
          ),
      ],
      body: ListView(
        children: [
          if (!isConfigured)
            ListTile(
              key: const Key('settings-api-hint'),
              leading: const Icon(Icons.info_outline),
              title: Text(l10n.serviceNotConfigured),
              subtitle: Text(
                l10n.apiServiceDisconnectedDesc,
              ),
              onTap: () => AppRouter.push<void>(
                context,
                pageBuilder: (_) => const ApiSettingsPage(),
              ),
            ),
          _SettingsDestination(
            icon: Icons.language_rounded,
            title: l10n.languageSettingTitle,
            subtitle: localeController.currentLocale.nativeName,
            pageBuilder: (_) => const LanguageSettingsPage(),
          ),
          _SettingsDestination(
            icon: Icons.key_outlined,
            title: l10n.providerConfigTitle,
            pageBuilder: (_) => const ApiSettingsPage(),
          ),
          _SettingsDestination(
            icon: Icons.tune,
            title: l10n.modelParamsSectionTitle,
            pageBuilder: (_) => const ModelSettingsPage(),
          ),
          _SettingsDestination(
            icon: Icons.settings_outlined,
            title: l10n.settingsSystemConfig,
            pageBuilder: (_) => const AdvancedSettingsPage(),
          ),
          const Divider(),
          _SettingsDestination(
            icon: Icons.file_download_outlined,
            title: l10n.importChatTitle,
            pageBuilder: (_) => const ImportPage(),
          ),
          _SettingsDestination(
            icon: Icons.file_upload_outlined,
            title: l10n.exportChatTitle,
            pageBuilder: (_) => const ExportPage(),
          ),
        ],
      ),
    );
  }
}

class _SettingsDestination extends StatelessWidget {
  const _SettingsDestination({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.pageBuilder,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final WidgetBuilder pageBuilder;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: subtitle != null ? Text(subtitle!) : null,
        trailing: const Icon(Icons.chevron_right),
        onTap: () => AppRouter.push<void>(context, pageBuilder: pageBuilder),
      );
}

class ApiSettingsPage extends StatelessWidget {
  const ApiSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();
    return AppPageScaffold(
      title: l10n.providerConfigTitle,
      body: const SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: ProviderConfigSection(),
      ),
    );
  }
}

class ModelSettingsPage extends StatelessWidget {
  const ModelSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();
    return AppPageScaffold(
      title: l10n.modelParamsSectionTitle,
      body: const SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: ModelParamsSection(),
      ),
    );
  }
}

class AdvancedSettingsPage extends StatelessWidget {
  const AdvancedSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();
    return AppPageScaffold(
      title: l10n.settingsSystemConfig,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const AppearanceSection(),
          const SizedBox(height: 16),
          const DataManagementSection(),
          const Divider(),
          _SettingsDestination(
            icon: Icons.file_download_outlined,
            title: l10n.importChatTitle,
            pageBuilder: (_) => const ImportPage(),
          ),
          _SettingsDestination(
            icon: Icons.file_upload_outlined,
            title: l10n.exportChatTitle,
            pageBuilder: (_) => const ExportPage(),
          ),
        ],
      ),
    );
  }
}
