import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider;
import '../providers/riverpod_providers.dart';
import '../core/theme/app_colors.dart';
import '../core/feedback/app_feedback.dart';
import '../core/router/app_router.dart';
import '../models/adventure_config.dart';
import '../widgets/narr_aitor_loading.dart';
import '../controllers/home_screen_controller.dart';
import 'adventure_builder.dart';
import '../data/preset_adventures.dart';
import '../core/refresh/page_refresh_scope.dart';

class LandingScreen extends ConsumerStatefulWidget {
  final Future<void> Function(AdventureConfig config, {String? difficulty})
      onStartAdventure;
  final VoidCallback? onMenuPressed;

  const LandingScreen({
    super.key,
    required this.onStartAdventure,
    this.onMenuPressed,
  });

  @override
  ConsumerState<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends ConsumerState<LandingScreen> {
  PresetAdventureData? _previewData;
  bool _isStartingAdventure = false;
  AdventureConfig? _builderInitConfig;

  // Magazine layout state
  final _aiDescCtrl = TextEditingController();

  @override
  Widget build(BuildContext context) {
    if (_previewData != null) return _buildPreviewPage(_previewData!);

    return PageRefreshScope(
      onRefresh: () async {
        await ref.read(chatProvider).loadAdventureList();
        return const PageRefreshResult.success();
      },
      child: Scaffold(
        body: AppRefreshIndicator(
          child: CustomScrollView(
            slivers: [
              // ── Hero Section ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (widget.onMenuPressed != null) ...[
                            IconButton(
                              icon: const Icon(Icons.menu_rounded),
                              tooltip: '打开侧边栏',
                              onPressed: widget.onMenuPressed,
                              visualDensity: VisualDensity.compact,
                            ),
                            const SizedBox(width: 4),
                          ],
                          Expanded(
                            child: Text('进入你的场景',
                                style: Theme.of(context)
                                        .textTheme
                                        .headlineMedium
                                        ?.copyWith(
                                          color: AppColors.textPrimary,
                                        ) ??
                                    const TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.textPrimary)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '选择预设世界或自由定制，AI 主持人将为你谱写独一无二的传奇',
                        style: TextStyle(
                            fontSize: 15,
                            color: AppColors.textSecondary,
                            height: 1.5),
                      ),
                      const SizedBox(height: 18),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.only(right: 24),
                        child: Row(children: [
                          FilledButton.icon(
                            onPressed: () => _startQuickAdventure(),
                            icon: const Icon(Icons.rocket_launch, size: 18),
                            label: const Text('快速开始'),
                          ),
                          const SizedBox(width: 12),
                          OutlinedButton.icon(
                            onPressed: () => _switchToBuilder(),
                            icon: const Icon(Icons.edit_note, size: 18),
                            label: const Text('自由创建'),
                          ),
                          const SizedBox(width: 12),
                          OutlinedButton.icon(
                            onPressed: () => _showPresetPicker(),
                            icon: const Icon(Icons.bookmark_outline, size: 18),
                            label: const Text('使用预设'),
                          ),
                        ]),
                      ),
                    ],
                  ),
                ),
              ),

              // ── 继续场景 ──
              Consumer(
                builder: (_, ref, __) {
                  final p = ref.watch(chatProvider);
                  if (p.adventureList.isEmpty) {
                    return const SliverToBoxAdapter(child: SizedBox.shrink());
                  }
                  return SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.fromLTRB(24, 8, 24, 12),
                          child: Text('继续场景',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary)),
                        ),
                        SizedBox(
                          height: 100,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            itemCount:
                                p.adventureList.length + 1, // +1 for draft
                            itemBuilder: (ctx, i) {
                              if (i < p.adventureList.length) {
                                final a = p.adventureList[i];
                                return _buildAdventureCard(
                                  title: a['title']?.toString() ?? '未命名',
                                  subtitle: '点击继续',
                                  icon: Icons.replay,
                                  color: AppColors.primary,
                                  onTap: () {
                                    final id = a['id'];
                                    if (id is int) p.openAdventure(id);
                                  },
                                );
                              }
                              // Last item: continue draft
                              return _buildAdventureCard(
                                title: '继续草稿',
                                subtitle: '未完成的场景',
                                icon: Icons.edit_note,
                                color: Colors.orange,
                                onTap: () => _showDraftList(),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),

              // ── AI 生成区域 ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
                  child: Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: Colors.grey.shade200),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(children: [
                            Icon(Icons.auto_fix_high,
                                size: 20, color: AppColors.accent),
                            SizedBox(width: 8),
                            Text('AI 智能生成',
                                style: TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w700)),
                          ]),
                          const SizedBox(height: 8),
                          const Text(
                            '描述你想要的世界，让 AI 为你创建完整的剧情设定',
                            style: TextStyle(
                                fontSize: 13, color: AppColors.textSecondary),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _aiDescCtrl,
                            maxLines: 3,
                            decoration: InputDecoration(
                              hintText: '例如：一个充满魔法与龙的中世纪王国...',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              isDense: true,
                              contentPadding: const EdgeInsets.all(14),
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed:
                                  _generating ? null : _generateAdventure,
                              icon: _generating
                                  ? const NarrAItorLoading.mini()
                                  : const Icon(Icons.auto_fix_high, size: 18),
                              label: Text(
                                  _generating ? 'AI 正在生成...' : '让 AI 创建场景'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // 底部留白
              const SliverToBoxAdapter(child: SizedBox(height: 80)),
            ],
          ),
        ),
      ),
    );
  }

  // ═══ Magazine Layout Helpers ═══

  Widget _buildAdventureCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 160,
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(height: 8),
            Text(title,
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600, color: color),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(subtitle,
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }

  void _startQuickAdventure() {
    // 随机选一个世界观, 自动填入 AI 生成区并触发生成
    const worldviews = HomeScreenController.worldviewOptions;
    final randomWorldview = (worldviews..shuffle()).first;
    _aiDescCtrl.text = '创建一个$randomWorldview风格的场景世界';
    _generateAdventure();
  }

  void _switchToBuilder() {
    _openBuilder();
  }

  Future<void> _showPresetPicker() async {
    try {
      final templateController = ref.read(adventureTemplateControllerProvider);
      await templateController.loadTemplates();
      final templates = templateController.templates;
      if (!mounted) return;
      if (templates.isEmpty) {
        AppFeedback.info(context, '暂无可用预设，请先在自由定制中创建并保存');
        return;
      }
      showModalBottomSheet(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('选择预设开始场景',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            ...templates.map((t) {
              final name = t['name'] as String? ?? '未命名预设';
              final wv = t['worldview_name'] as String? ?? '';
              final updated = t['updated_at'] as String? ?? '';
              return ListTile(
                leading: const Icon(Icons.bookmark, color: AppColors.accent),
                title: Text(name, style: const TextStyle(fontSize: 14)),
                subtitle: Text(wv.isNotEmpty ? '$wv  $updated' : updated,
                    style: const TextStyle(fontSize: 11)),
                onTap: () {
                  Navigator.pop(ctx);
                  _loadTemplateAndStart(t);
                },
              );
            }),
            const SizedBox(height: 8),
          ]),
        ),
      );
    } catch (e) {
      if (mounted) {
        AppFeedback.error(context, '加载预设失败，请稍后重试');
      }
    }
  }

  Future<void> _loadTemplateAndStart(Map<String, dynamic> template) async {
    try {
      final preset = ref
          .read(adventureTemplateControllerProvider)
          .buildPresetData(template);
      if (preset == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('预设数据为空，请重新保存')),
          );
        }
        return;
      }
      setState(() {
        _previewData = preset;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('解析预设失败: $e')),
        );
      }
    }
  }

  Future<void> _startAdventureFromPreview(AdventureConfig config) async {
    if (_isStartingAdventure) return;
    setState(() => _isStartingAdventure = true);

    try {
      await widget.onStartAdventure(config);
    } finally {
      if (mounted) {
        setState(() => _isStartingAdventure = false);
      }
    }
  }

  void _openBuilder({String? presetWorldview}) {
    AdventureConfig? config = _builderInitConfig;
    if (config == null && presetWorldview != null) {
      config = AdventureConfig()..worldview = presetWorldview;
    }
    AppRouter.push<void>(
      context,
      pageBuilder: (_) => _BuilderPage(
        onStartAdventure: widget.onStartAdventure,
        initialConfig: config,
      ),
    ).then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _generateAdventure() async {
    final p = ref.read(chatProvider);
    if (p.apiKey.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先配置 API Key')),
        );
      }
      return;
    }
    var desc = _aiDescCtrl.text.trim();
    if (desc.isEmpty) {
      desc = '创建一个${HomeScreenController.worldviewOptions.first}风格的场景世界';
      _aiDescCtrl.text = desc;
    }
    _prefCtrl.text = desc;
    setState(() {
      _generating = true;
    });
    _doGenerate();
  }

  // ═══ 预览页 ═══

  Future<void> _showDraftList() async {
    final drafts = await HomeScreenController.loadAllDrafts();
    if (!mounted) return;
    if (drafts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('暂无草稿')),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('选择草稿继续编辑',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
          ...drafts.map((d) {
            final name = d['name'] as String;
            final wv = d['worldview'] as String? ?? '';
            final ts = d['ts'] as int;
            final dateStr = DateTime.fromMillisecondsSinceEpoch(ts)
                .toString()
                .substring(0, 16);
            return ListTile(
              leading: const Icon(Icons.edit_note, color: Colors.orange),
              title: Text(name, style: const TextStyle(fontSize: 14)),
              subtitle: Text('$dateStr  ${wv.isNotEmpty ? wv : ""}',
                  style: const TextStyle(fontSize: 11)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.pop(ctx);
                setState(() {
                  Navigator.pop(ctx);
                  _builderInitConfig = d['config'] as AdventureConfig;
                  _openBuilder();
                });
              },
            );
          }),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Widget _buildPreviewPage(PresetAdventureData data) {
    final cfg = data.toConfig();

    final List<Widget> slivers = <Widget>[];

    slivers.add(
      SliverAppBar(
        title: const Text('冒险预览'),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => setState(() => _previewData = null),
        ),
        actions: [
          if (widget.onMenuPressed != null)
            IconButton(
              icon: const Icon(Icons.menu_rounded),
              tooltip: '打开侧边栏',
              onPressed: widget.onMenuPressed,
            ),
        ],
      ),
    );

    slivers.add(
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: AppColors.accent,
            ),
            child: const Text(
              '以下是 AI 生成的场景配置预览，请确认无误后点击"进入场景"',
              style: TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
            ),
          ),
        ),
      ),
    );

    // 世界观
    slivers.add(
      SliverToBoxAdapter(
        child: _buildPreviewSection('世界观', data.worldview),
      ),
    );

    // 主角
    final protagParts = <String>[
      '姓名：${data.charName}',
      '性别：${data.gender}',
      '年龄：${data.age}岁',
      '职业：${data.profession}',
    ];
    if (data.background.isNotEmpty) protagParts.add('背景：${data.background}');
    slivers.add(
      SliverToBoxAdapter(
        child: _buildPreviewSection('主角', protagParts.join('\n')),
      ),
    );

    // NPC
    String npcText;
    if (data.supportingCharacters.isEmpty) {
      npcText = '无 NPC';
    } else {
      npcText = data.supportingCharacters.map((n) {
        final parts = <String>['名称：${n.name}'];
        if (n.relation.isNotEmpty) parts.add('关系：${n.relation}');
        if (n.personality.isNotEmpty) parts.add('性格：${n.personality}');
        return parts.join(' | ');
      }).join('\n\n');
    }
    slivers.add(
      SliverToBoxAdapter(
        child: _buildPreviewSection('NPC 配角', npcText),
      ),
    );

    // 开场场景
    slivers.add(
      SliverToBoxAdapter(
        child: _buildPreviewSection(
          '开场场景',
          data.openingScene.isNotEmpty ? data.openingScene : '未填写开场场景',
        ),
      ),
    );

    // 开场选项
    final options = cfg.openingOptions;
    slivers.add(
      SliverToBoxAdapter(
        child: _buildPreviewSection(
          '开场选项',
          options.map((o) => '• $o').join('\n'),
        ),
      ),
    );

    // ── Bottom action buttons (inside scroll to avoid Android clipping) ──
    slivers.add(
      SliverToBoxAdapter(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Save as preset
                SizedBox(
                  width: double.infinity,
                  height: 40,
                  child: OutlinedButton.icon(
                    onPressed: () => _saveSmartGenAsPreset(cfg),
                    icon: const Icon(Icons.save, size: 16),
                    label: const Text('保存为预设', style: TextStyle(fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.accent,
                      side: const BorderSide(color: AppColors.accent),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          if (!mounted) return;
                          setState(() {
                            _previewData = null;
                          });
                        },
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 48),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('返回'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: _isStartingAdventure
                            ? null
                            : () => _startAdventureFromPreview(cfg),
                        icon: _isStartingAdventure
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: NarrAItorLoading.mini(size: 18),
                              )
                            : const Icon(Icons.play_arrow),
                        label: Text(
                          _isStartingAdventure ? '创建中...' : '进入场景',
                          style: const TextStyle(fontSize: 15),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          minimumSize: const Size(0, 48),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    slivers.add(
      const SliverToBoxAdapter(child: SizedBox(height: 16)),
    );

    return Scaffold(
      body: CustomScrollView(slivers: slivers),
    );
  }

  Future<void> _saveSmartGenAsPreset(AdventureConfig config) async {
    final nameCtrl = TextEditingController(
        text: config.name.isNotEmpty ? '${config.name}的场景' : 'AI生成的场景');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('保存为预设'),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(
              labelText: '预设名称', border: OutlineInputBorder()),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
              onPressed: () {
                final n = nameCtrl.text.trim();
                Navigator.pop(ctx, n.isEmpty ? '未命名冒险' : n);
              },
              child: const Text('保存')),
        ],
      ),
    );
    nameCtrl.dispose();
    if (name == null || !mounted) return;
    final now = DateTime.now().toIso8601String();
    final charDataJson = jsonEncode({
      'name': config.name,
      'gender': config.gender,
      'personality': config.personality,
    });
    final npcDataJson =
        jsonEncode(config.supportingCharacters.map((c) => c.toJson()).toList());
    // 去重与保存统一经模板控制器（内部含 ContentHasher 去重）。
    try {
      final saved =
          await ref.read(adventureTemplateControllerProvider).saveAsTemplate(
                id: 'tmpl_${DateTime.now().millisecondsSinceEpoch}',
                name: name,
                worldviewName: config.worldview,
                worldviewDesc: config.worldview,
                charDataJson: charDataJson,
                npcDataJson: npcDataJson,
                createdAt: now,
                status: 'complete',
                updatedAt: now,
              );
      if (!mounted) return;
      _showCenteredPresetMessage(saved ? '已保存为预设场景' : '已保存过相同内容，无需重复保存');
    } catch (e) {
      debugPrint('[Landing] 保存预设失败: $e');
    }
  }

  void _showCenteredPresetMessage(String message) {
    BuildContext? dialogContext;
    unawaited(showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.08),
      barrierDismissible: true,
      builder: (ctx) {
        dialogContext = ctx;
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle,
                    color: AppColors.success, size: 22),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    message,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ));
    Future.delayed(const Duration(milliseconds: 1400), () {
      final ctx = dialogContext;
      if (ctx != null && ctx.mounted) {
        Navigator.of(ctx).pop();
      }
    });
  }

  Widget _buildPreviewSection(String title, String content) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor =
        isDark ? AppColors.darkSurfaceElevated : AppColors.surfaceElevated;
    final borderColor = isDark
        ? AppColors.darkTextSecondary.withValues(alpha: 0.24)
        : Colors.grey[200]!;
    final titleColor =
        isDark ? AppColors.darkTextPrimary : AppColors.textPrimary;
    final bodyColor = isDark ? AppColors.darkTextSecondary : Colors.grey[700]!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: titleColor)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              content,
              style: TextStyle(
                fontSize: 13,
                color: bodyColor,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══ Tab 2: AI 生成 ═══

  final _prefCtrl = TextEditingController();
  bool _generating = false;

  @override
  void dispose() {
    _prefCtrl.dispose();
    _aiDescCtrl.dispose();
    super.dispose();
  }

  Future<void> _doGenerate() async {
    final pref = _prefCtrl.text.trim();
    if (pref.isEmpty) return;
    final p = ref.read(chatProvider);
    if (p.apiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先配置 API Key 后再使用 AI 生成功能')));
      return;
    }
    final aiController = ref.read(adventureAiControllerProvider);
    final preset = await aiController.generateAdventurePreset(preference: pref);
    if (!mounted) return;
    setState(() {
      _generating = false;
      if (preset != null) {
        _previewData = preset;
      }
    });
    if (preset == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(aiController.errorMessage ?? 'AI 生成失败，请调整描述后重试'),
      ));
    }
  }

  // Parsing moved to AiAdventureUtils
}

/// Full-screen page wrapper for AdventureBuilder, used when user taps
/// "自由创建" or "快速开始" on the magazine-style landing page.
class _BuilderPage extends ConsumerWidget {
  final Future<void> Function(AdventureConfig config, {String? difficulty})
      onStartAdventure;
  final AdventureConfig? initialConfig;

  const _BuilderPage({
    required this.onStartAdventure,
    this.initialConfig,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('创建场景'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: AdventureBuilder(
        onStartAdventure: (config) async {
          await onStartAdventure(config);
          if (context.mounted && Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        },
        initialConfig: initialConfig,
      ),
    );
  }
}
