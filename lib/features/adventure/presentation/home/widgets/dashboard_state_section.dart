import 'package:flutter/material.dart';

import '../../../../../core/widgets/workbench_section.dart';
import '../../../../../l10n/generated/app_localizations.dart';
import '../../../../../l10n/generated/app_localizations_zh.dart';

class DashboardStateSection extends StatelessWidget {
  const DashboardStateSection({super.key, required this.onOpenStateHub});
  final VoidCallback onOpenStateHub;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();
    return WorkbenchSection(
      title: l10n.runtimeStateCurrent,
      child: Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: const Key('dashboard-runtime-state'),
            onPressed: onOpenStateHub,
            child: Text(l10n.runtimeStateHistoricalChange),
          )),
    );
  }
}
