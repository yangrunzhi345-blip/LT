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
import '../../../../core/responsive/app_breakpoints.dart';
import '../../../../core/widgets/app_svg_icon.dart';
import '../../../prompt_settings/presentation/screens/context_weight_controls.dart';
import '../../../prompt_settings/presentation/screens/prompt_advanced_settings.dart';
import '../../../adventure/presentation/session/widgets/reply_length_control.dart';

enum SettingsCategory {
  appearance,
  language,
  readAloud,
  generation,
  context,
  data
}

String settingsCategoryLabel(
        SettingsCategory category, AppLocalizations l10n) =>
    switch (category) {
      SettingsCategory.appearance => l10n.settingsTabAppearance,
      SettingsCategory.language => l10n.languageSettingTitle,
      SettingsCategory.readAloud => l10n.readAloudSectionTitle,
      SettingsCategory.generation => l10n.workbenchGeneration,
      SettingsCategory.context => l10n.workbenchContext,
      SettingsCategory.data => l10n.settingsTabStorage,
    };

/// Desktop categories replace content in place; compact layouts retain a back path.
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key, this.onMenuPressed, this.initialCategory});
  final VoidCallback? onMenuPressed;
  final SettingsCategory? initialCategory;
  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  late SettingsCategory _category;
  late bool _showCompactDetail;
  @override
  void initState() {
    super.initState();
    _category = widget.initialCategory ?? SettingsCategory.appearance;
    _showCompactDetail = widget.initialCategory != null;
  }

  void _select(SettingsCategory category) => setState(() {
        _category = category;
        _showCompactDetail = true;
      });
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();
    final configured =
        ref.watch(chatProvider.select((chat) => chat.isKeyConfigured));
    return LayoutBuilder(builder: (context, constraints) {
      // Two settings panes need at least 240 + 360 logical pixels.
      final twoPane = constraints.maxWidth >= AppBreakpoints.mediumMin;
      final label = settingsCategoryLabel(_category, l10n);
      final categories = ListView(padding: const EdgeInsets.all(12), children: [
        if (!configured)
          ListTile(
              key: const Key('settings-api-hint'),
              title: Text(l10n.serviceNotConfigured),
              subtitle: Text(l10n.apiServiceDisconnectedDesc),
              onTap: () => _select(SettingsCategory.generation)),
        for (final category in SettingsCategory.values)
          ListTile(
              key: ValueKey('settings-category-${category.name}'),
              selected: twoPane && _category == category,
              title: Text(settingsCategoryLabel(category, l10n)),
              onTap: () => _select(category)),
      ]);
      final content = ListView(
        key: ValueKey('settings-content-${_category.name}'),
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, 24 + MediaQuery.viewInsetsOf(context).bottom),
        children: [
          Text(label, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 24),
          SettingsCategoryContent(category: _category),
        ],
      );
      return PopScope(
        canPop: twoPane || !_showCompactDetail,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) setState(() => _showCompactDetail = false);
        },
        child: AppPageScaffold(
          title: twoPane || !_showCompactDetail ? l10n.settingsCenter : label,
          maxWidth: null,
          leading: !twoPane && _showCompactDetail
              ? IconButton(
                  tooltip: l10n.settingsReturnList,
                  icon: const AppSvgIcon('back'),
                  onPressed: () => setState(() => _showCompactDetail = false))
              : null,
          actions: [
            if (widget.onMenuPressed != null)
              IconButton(
                  tooltip: l10n.sidebarExpand,
                  icon: const AppSvgIcon('panel'),
                  onPressed: widget.onMenuPressed)
          ],
          body: twoPane
              ? Row(children: [
                  SizedBox(width: 240, child: categories),
                  const VerticalDivider(width: 1),
                  Expanded(child: content)
                ])
              : _showCompactDetail
                  ? content
                  : categories,
        ),
      );
    });
  }
}

class SettingsCategoryContent extends StatelessWidget {
  const SettingsCategoryContent({super.key, required this.category});
  final SettingsCategory category;
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();
    return switch (category) {
      SettingsCategory.appearance => const AppearanceSection(),
      SettingsCategory.language => const LanguageSettingsContent(),
      SettingsCategory.readAloud => const ReadAloudSettingsSection(),
      SettingsCategory.generation =>
        const Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ProviderConfigSection(),
          SizedBox(height: 24),
          Align(alignment: Alignment.centerLeft, child: ReplyLengthControl()),
          SizedBox(height: 24),
          ModelParamsSection()
        ]),
      SettingsCategory.context => const Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ContextWeightControls(),
              SizedBox(height: 24),
              PromptAdvancedSettings()
            ]),
      SettingsCategory.data =>
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const DataManagementSection(),
          const Divider(),
          Wrap(spacing: 8, runSpacing: 8, children: [
            TextButton(
                onPressed: () => AppRouter.push<void>(context,
                    pageBuilder: (_) => const ImportPage()),
                child: Text(l10n.importChatTitle)),
            TextButton(
                onPressed: () => AppRouter.push<void>(context,
                    pageBuilder: (_) => const ExportPage()),
                child: Text(l10n.exportChatTitle))
          ])
        ]),
    };
  }
}
