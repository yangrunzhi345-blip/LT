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

/// 首页「我的角色卡档案」摘要。
///
/// 与「我的世界设定」共用同一个派生投影 Provider。点击「前往资料库」进入
/// 资料库并选中「角色」，点击具体角色进入其已有详情页，绝不启动角色创建。
class DashboardCharacterCards extends ConsumerWidget {
  final VoidCallback onOpenLibrary;
  final ValueChanged<ResourceLibraryItem> onOpenResource;

  const DashboardCharacterCards({
    super.key,
    required this.onOpenLibrary,
    required this.onOpenResource,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = _l10n(context);
    return DashboardSubsection(
      key: const Key('dashboard-subsection-characters'),
      title: l10n.dashboardMyCharacterCards,
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
              final characters = projection.characters;
              if (characters.isEmpty) {
                return Text(l10n.dashboardNoCharacterCardsTitle);
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final character in characters)
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                      child: ListTile(
                        key: ValueKey('dashboard-character-${character.id}'),
                        contentPadding: EdgeInsets.zero,
                        title: Text(character.localizedName(l10n)),
                        subtitle: Text(
                          character.summary,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => onOpenResource(character),
                      ),
                    ),
                ],
              );
            },
          ),
    );
  }
}
