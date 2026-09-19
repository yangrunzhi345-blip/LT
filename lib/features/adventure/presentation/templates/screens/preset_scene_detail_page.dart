import 'package:flutter/material.dart';

import '../../../../../core/theme/app_spacing.dart';

enum PresetSceneDetailAction { customize, start }

class PresetSceneDetailData {
  final String worldview;
  final String characterSummary;
  final String background;
  final String openingScene;
  final List<String> options;
  final List<String> supportingCharacters;

  const PresetSceneDetailData({
    required this.worldview,
    required this.characterSummary,
    required this.background,
    required this.openingScene,
    required this.options,
    required this.supportingCharacters,
  });
}

/// Displays the complete preset scene without constraining long content to a dialog.
class PresetSceneDetailPage extends StatelessWidget {
  final String name;
  final PresetSceneDetailData? preset;
  final bool isSubmitting;

  const PresetSceneDetailPage({
    super.key,
    required this.name,
    required this.preset,
    this.isSubmitting = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final data = preset;

    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: data == null
                  ? const Center(child: Text('剧本数据解析失败或格式不完整'))
                  : ListView(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      children: [
                        _DetailSection(
                          title: '世界观设定',
                          child: Text(
                            data.worldview,
                            style: const TextStyle(height: 1.5),
                          ),
                        ),
                        _DetailSection(
                          title: '主角档案',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                data.characterSummary,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (data.background.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(data.background),
                              ],
                            ],
                          ),
                        ),
                        if (data.openingScene.isNotEmpty)
                          _DetailSection(
                            title: '开场序章',
                            child: Text(
                              data.openingScene,
                              style: const TextStyle(height: 1.5),
                            ),
                          ),
                        if (data.options.isNotEmpty)
                          _DetailSection(
                            title: '初始行动分支',
                            child: Column(
                              children: [
                                for (final (index, option)
                                    in data.options.indexed)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${index + 1}. ',
                                          style: TextStyle(
                                            color: scheme.primary,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        Expanded(child: Text(option)),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        if (data.supportingCharacters.isNotEmpty)
                          _DetailSection(
                            title: '登场配角 (NPC)',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (final character
                                    in data.supportingCharacters)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: Text('· $character'),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
            if (data != null) _DetailActions(isSubmitting: isSubmitting),
          ],
        ),
      ),
    );
  }
}

class _DetailSection extends StatelessWidget {
  final String title;
  final Widget child;

  const _DetailSection({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          child,
        ],
      ),
    );
  }
}

class _DetailActions extends StatelessWidget {
  final bool isSubmitting;

  const _DetailActions({required this.isSubmitting});

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 3,
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 420;
              final customize = FilledButton.tonalIcon(
                onPressed: () => Navigator.of(context).pop(
                  PresetSceneDetailAction.customize,
                ),
                icon: const Icon(Icons.edit_note_rounded),
                label: const Text('向导载入微调'),
              );
              final start = FilledButton.icon(
                onPressed: isSubmitting
                    ? null
                    : () => Navigator.of(context).pop(
                          PresetSceneDetailAction.start,
                        ),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('立即启程'),
              );
              if (isNarrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [customize, const SizedBox(height: 8), start],
                );
              }
              return Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [customize, const SizedBox(width: 8), start],
              );
            },
          ),
        ),
      ),
    );
  }
}
