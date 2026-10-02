import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_spacing.dart';
import '../../../../../models/adventure_config.dart';
import '../../../../../providers/riverpod_providers.dart';
import '../../../../../l10n/generated/app_localizations.dart';
import '../../../../../l10n/generated/app_localizations_zh.dart';
import 'dashboard_section.dart';

AppLocalizations _l10n(BuildContext context) =>
    AppLocalizations.of(context) ?? AppLocalizationsZh();

/// 用户自定义世界设定流 (遵循零预设 · 纯净白板准则)
class DashboardFeaturedWorlds extends ConsumerStatefulWidget {
  final ValueChanged<AdventureConfig> onSelectWorld;
  final VoidCallback? onCreateWorld;

  const DashboardFeaturedWorlds({
    super.key,
    required this.onSelectWorld,
    this.onCreateWorld,
  });

  @override
  ConsumerState<DashboardFeaturedWorlds> createState() =>
      _DashboardFeaturedWorldsState();
}

class _DashboardFeaturedWorldsState
    extends ConsumerState<DashboardFeaturedWorlds> {
  List<Map<String, dynamic>> _userWorlds = [];
  bool _loading = true;
  bool _hasLoadError = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadUserWorlds();
    });
  }

  Future<void> _loadUserWorlds() async {
    setState(() {
      _loading = true;
      _hasLoadError = false;
    });
    try {
      final setupController = ref.read(adventureSetupControllerProvider);
      await setupController.loadInitialData();
      if (mounted) {
        setState(() {
          _userWorlds = setupController.worldviewPresets;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _hasLoadError = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n(context);
    return DashboardSubsection(
      key: const Key('dashboard-subsection-worlds'),
      title: l10n.dashboardMyWorldSettings,
      action: widget.onCreateWorld == null
          ? null
          : TextButton(
              onPressed: widget.onCreateWorld,
              child: Text(l10n.dashboardGoToLibrary)),
      child: _hasLoadError
          ? Column(children: [
              Text(l10n.pageLoadError),
              TextButton(
                  onPressed: _loadUserWorlds, child: Text(l10n.retryAction))
            ])
          : _loading
              ? const Center(child: CircularProgressIndicator())
              : _userWorlds.isEmpty
                  ? Text(l10n.dashboardNoCustomWorldsTitle)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                          for (final world in _userWorlds)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  vertical: AppSpacing.sm),
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(world['name'] as String? ??
                                    l10n.unnamedWorldview),
                                subtitle: Text(
                                    world['description'] as String? ?? '',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis),
                                onTap: () {
                                  final name = world['name'] as String? ??
                                      l10n.unnamedWorldview;
                                  final description =
                                      world['description'] as String? ?? '';
                                  widget.onSelectWorld(AdventureConfig(
                                      worldview: name,
                                      worldviewSnapshot: {
                                        'name': name,
                                        'description': description
                                      }));
                                },
                              ),
                            ),
                        ]),
    );
  }
}
