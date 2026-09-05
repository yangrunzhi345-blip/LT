import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_radius.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/widgets/app_card.dart';
import '../../../../../core/widgets/app_empty_state.dart';
import '../../../../../models/adventure_config.dart';
import '../../../../../providers/riverpod_providers.dart';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadUserWorlds();
    });
  }

  Future<void> _loadUserWorlds() async {
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
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.public_rounded,
              size: 20,
              color: scheme.primary,
            ),
            const SizedBox(width: 8),
            Text(
              '我的世界设定',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            if (_userWorlds.isNotEmpty && widget.onCreateWorld != null)
              TextButton.icon(
                onPressed: widget.onCreateWorld,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('新建世界'),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (_userWorlds.isEmpty)
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: AppEmptyState(
              icon: Icons.public_off_outlined,
              title: '暂无自定义世界',
              description: '当前处于纯净白板状态，无任何预设世界。你可以在资料库中自由构想专属世界，或使用向导直接开启全新的探索。',
              actionLabel: widget.onCreateWorld != null ? '前往资料库' : null,
              onAction: widget.onCreateWorld,
              iconSize: 44,
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final isDesktop = constraints.maxWidth >= 720;
              final crossAxisCount = isDesktop ? 2 : 1;

              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _userWorlds.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: AppSpacing.md,
                  mainAxisSpacing: AppSpacing.md,
                  mainAxisExtent: 160,
                ),
                itemBuilder: (context, index) {
                  final wv = _userWorlds[index];
                  final name = wv['name'] as String? ?? '未命名世界';
                  final desc = wv['description'] as String? ?? '暂无设定描述';

                  return AppCard(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: scheme.primaryContainer,
                                borderRadius: BorderRadius.circular(AppRadius.xs),
                              ),
                              child: Icon(
                                Icons.auto_awesome,
                                size: 16,
                                color: scheme.onPrimaryContainer,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Expanded(
                          child: Text(
                            desc,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurfaceVariant,
                              height: 1.4,
                            ),
                          ),
                        ),
                        Align(
                          alignment: Alignment.bottomRight,
                          child: FilledButton.tonalIcon(
                            onPressed: () {
                              widget.onSelectWorld(
                                AdventureConfig(
                                  worldview: name,
                                  worldviewSnapshot: {'name': name, 'description': desc},
                                ),
                              );
                            },
                            icon: const Icon(Icons.play_arrow_rounded, size: 16),
                            label: const Text('以此世界启程'),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
      ],
    );
  }
}
