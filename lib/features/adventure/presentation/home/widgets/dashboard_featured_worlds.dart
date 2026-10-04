import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_spacing.dart';
import '../../../../../l10n/generated/app_localizations.dart';
import '../../../../../l10n/generated/app_localizations_zh.dart';
import '../../../../resource_library/domain/models/resource_library_view_state.dart';
import '../providers/home_resource_projection.dart';
import 'dashboard_section.dart';

AppLocalizations _l10n(BuildContext context) =>
    AppLocalizations.of(context) ?? AppLocalizationsZh();

/// 首页「我的世界设定」摘要。
///
/// 数据来自统一 Resource Authority（Resource Library Runtime）的派生投影，
/// 只读展示已有世界观资源。点击「前往资料库」进入资料库并选中「世界观」，
/// 点击具体资源进入其已有详情页，绝不启动创建/启动向导。
class DashboardFeaturedWorlds extends ConsumerWidget {
  final VoidCallback onOpenLibrary;
  final ValueChanged<ResourceLibraryItem> onOpenResource;

  const DashboardFeaturedWorlds({
    super.key,
    required this.onOpenLibrary,
    required this.onOpenResource,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = _l10n(context);
    return DashboardSubsection(
      key: const Key('dashboard-subsection-worlds'),
      title: l10n.dashboardMyWorldSettings,
      action: TextButton(
        onPressed: onOpenLibrary,
        child: Text(l10n.dashboardGoToLibrary),
      ),
      child: ref.watch(homeResourceProjectionProvider).when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, __) => Column(children: [
              Text(l10n.pageLoadError),
              TextButton(
                onPressed: () => ref.invalidate(homeResourceProjectionProvider),
                child: Text(l10n.retryAction),
              ),
            ]),
            data: (projection) {
              final worlds = projection.worldviews;
              if (worlds.isEmpty) {
                return Text(l10n.dashboardNoCustomWorldsTitle);
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final world in worlds)
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                      child: ListTile(
                        key: ValueKey('dashboard-world-${world.id}'),
                        contentPadding: EdgeInsets.zero,
                        title: Text(world.localizedName(l10n)),
                        subtitle: Text(
                          world.summary,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => onOpenResource(world),
                      ),
                    ),
                ],
              );
            },
          ),
    );
  }
}
