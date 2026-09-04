import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider;

import '../../../core/theme/app_colors.dart';
import '../../../models/quest.dart';
import '../../../providers/riverpod_providers.dart';

class QuestScreen extends ConsumerStatefulWidget {
  const QuestScreen({super.key});

  @override
  ConsumerState<QuestScreen> createState() => _QuestScreenState();
}

class _QuestScreenState extends ConsumerState<QuestScreen> {
  late Future<List<Quest>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Quest>> _load() => ref.read(chatProvider).loadCurrentQuests();

  Future<void> _createFromPlot() async {
    final provider = ref.read(chatProvider);
    final quest = await provider.createQuestFromCurrentPlot();
    if (!mounted) return;
    if (quest == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前没有已保存的冒险，无法创建任务')),
      );
      return;
    }
    setState(() {
      _future = _load();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已创建任务：${quest.title}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.darkBackground : Colors.grey[50];
    final surface = isDark ? AppColors.darkSurface : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: const Text('任务列表'),
        actions: [
          IconButton(
            tooltip: '根据当前剧情生成任务',
            onPressed: _createFromPlot,
            icon: const Icon(Icons.auto_awesome_rounded),
          ),
        ],
      ),
      body: FutureBuilder<List<Quest>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final quests = snapshot.data ?? const <Quest>[];
          if (quests.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: surface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: (isDark ? Colors.white : Colors.black)
                            .withValues(alpha: 0.08),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.assignment_outlined,
                              size: 42, color: AppColors.accent),
                          const SizedBox(height: 14),
                          Text(
                            '暂无任务',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: textColor,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '可以根据当前剧情创建一个任务，后续 AI 返回的任务进度会进入这里。',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.5,
                              color: isDark ? Colors.white60 : Colors.black54,
                            ),
                          ),
                          const SizedBox(height: 18),
                          FilledButton.icon(
                            onPressed: _createFromPlot,
                            icon: const Icon(Icons.auto_awesome_rounded),
                            label: const Text('根据当前剧情生成任务'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          }

          final active = quests
              .where((q) => q.status == QuestStatus.active)
              .toList(growable: false);
          final completed = quests
              .where((q) => q.status == QuestStatus.completed)
              .toList(growable: false);
          final failed = quests
              .where((q) => q.status == QuestStatus.failed)
              .toList(growable: false);

          return RefreshIndicator(
            onRefresh: () async {
              setState(() {
                _future = _load();
              });
              await _future;
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                _QuestSummaryCard(
                  active: active.length,
                  completed: completed.length,
                  total: quests.length,
                  isDark: isDark,
                ),
                const SizedBox(height: 16),
                if (active.isNotEmpty)
                  _QuestSection(
                    title: '进行中',
                    icon: Icons.flag_rounded,
                    quests: active,
                    isDark: isDark,
                  ),
                if (completed.isNotEmpty)
                  _QuestSection(
                    title: '已完成',
                    icon: Icons.check_circle_rounded,
                    quests: completed,
                    isDark: isDark,
                  ),
                if (failed.isNotEmpty)
                  _QuestSection(
                    title: '已失败',
                    icon: Icons.error_outline_rounded,
                    quests: failed,
                    isDark: isDark,
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _QuestSummaryCard extends StatelessWidget {
  final int active;
  final int completed;
  final int total;
  final bool isDark;

  const _QuestSummaryCard({
    required this.active,
    required this.completed,
    required this.total,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final surface = isDark ? AppColors.darkSurface : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.assignment_rounded, color: AppColors.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '当前任务 $active 个，已完成 $completed 个',
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            '总计 $total',
            style: TextStyle(
              color: isDark ? Colors.white54 : Colors.black45,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuestSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Quest> quests;
  final bool isDark;

  const _QuestSection({
    required this.title,
    required this.icon,
    required this.quests,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.accent),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.accent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...quests.map((quest) => _QuestCard(quest: quest, isDark: isDark)),
        ],
      ),
    );
  }
}

class _QuestCard extends StatelessWidget {
  final Quest quest;
  final bool isDark;

  const _QuestCard({required this.quest, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final surface = isDark ? AppColors.darkSurface : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subColor = isDark ? Colors.white60 : Colors.black54;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_typeIcon(quest.type),
                  size: 17, color: _typeColor(quest.type)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  quest.title,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                quest.progressText,
                style: const TextStyle(
                  color: AppColors.accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          if (quest.description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              quest.description,
              style: TextStyle(color: subColor, height: 1.45, fontSize: 13),
            ),
          ],
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: quest.progress,
              minHeight: 8,
              backgroundColor: AppColors.accent.withValues(alpha: 0.14),
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.accent),
            ),
          ),
          if (quest.objectives.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...quest.objectives.map(
              (objective) => Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      objective.isDone
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      size: 15,
                      color: objective.isDone ? Colors.green : subColor,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${objective.description} (${objective.currentCount}/${objective.targetCount})',
                        style: TextStyle(color: subColor, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  IconData _typeIcon(QuestType type) {
    return switch (type) {
      QuestType.main => Icons.emoji_events_rounded,
      QuestType.side => Icons.push_pin_rounded,
      QuestType.random => Icons.casino_rounded,
      QuestType.achievement => Icons.track_changes_rounded,
    };
  }

  Color _typeColor(QuestType type) {
    return switch (type) {
      QuestType.main => Colors.amber,
      QuestType.side => Colors.blue,
      QuestType.random => Colors.purple,
      QuestType.achievement => Colors.green,
    };
  }
}
