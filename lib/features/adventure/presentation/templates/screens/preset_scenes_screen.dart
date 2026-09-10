import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/feedback/app_feedback.dart';
import '../../../../../core/refresh/page_refresh_scope.dart';
import '../../../../../core/router/app_router.dart';
import '../../../../../core/theme/app_radius.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../data/preset_adventures.dart';
import '../../../../../models/adventure_config.dart';
import '../../../../../models/resource_library_mode.dart';
import '../../../../../providers/riverpod_providers.dart';
import '../../../../../utils/time_format.dart';
import '../../../../../widgets/app_dialogs.dart';
import '../../../../../widgets/narr_aitor_loading.dart';
import '../../wizard/screens/adventure_wizard_screen.dart';

/// 预存场景工坊独立主屏
///
/// 拥有独立的展示界面、搜索过滤、卡片流式布局、详情预览与一键启程推进能力。
class PresetScenesScreen extends ConsumerStatefulWidget {
  final Future<void> Function(AdventureConfig config, {String? difficulty})?
      onStartAdventure;
  final VoidCallback? onMenuPressed;

  const PresetScenesScreen({
    super.key,
    this.onStartAdventure,
    this.onMenuPressed,
  });

  @override
  ConsumerState<PresetScenesScreen> createState() => _PresetScenesScreenState();
}

class _PresetScenesScreenState extends ConsumerState<PresetScenesScreen> {
  List<Map<String, dynamic>> _templates = [];
  bool _loading = true;
  String _searchQuery = '';
  String _filterStatus = 'all'; // 'all', 'complete', 'draft'

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  Future<void> _loadTemplates() async {
    setState(() => _loading = true);
    try {
      final crud = ref.read(resourceCrudControllerProvider);
      final rows = await crud.loadAdventureTemplates(
        mode: ResourceLibraryMode.adventure,
      );
      if (mounted) {
        setState(() {
          _templates = rows;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        AppFeedback.error(context, '加载预存场景失败：$e');
      }
    }
  }

  List<Map<String, dynamic>> get _filteredTemplates {
    return _templates.where((t) {
      final name = (t['name'] as String? ?? '').toLowerCase();
      final wvName = (t['worldview_name'] as String? ?? '').toLowerCase();
      final status = (t['status'] as String? ?? 'draft').toLowerCase();

      // 状态过滤
      if (_filterStatus == 'complete' && status != 'complete') return false;
      if (_filterStatus == 'draft' && status == 'complete') return false;

      // 搜索文本过滤
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        return name.contains(query) || wvName.contains(query);
      }
      return true;
    }).toList();
  }

  void _handleReturnHome() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      ref.read(chatProvider).navigateToAdventureHome();
    }
  }

  void _handleOpenWizard({PresetAdventureData? preset}) {
    AdventureConfig? config;
    if (preset != null) {
      config = AdventureConfig(
        name: preset.charName,
        gender: preset.gender,
        age: preset.age,
        protagonistClass: preset.profession,
        personality: '',
        protagonistBackground: preset.background,
        worldview: preset.worldview,
        openingScene: preset.openingScene,
        openingOptions: preset.options,
        supportingCharacters: preset.supportingCharacters,
      );
    }
    AppRouter.push(
      context,
      pageBuilder: (_) => AdventureWizardScreen(
        onStartAdventure: widget.onStartAdventure ??
            (c, {difficulty}) async {
              await ref.read(chatProvider).startAdventureWithConfig(c);
            },
        initialConfig: config,
      ),
    );
  }

  Future<void> _handleStartAdventure(PresetAdventureData preset) async {
    final chat = ref.read(chatProvider);
    if (!chat.isKeyConfigured) {
      showApiSettings(context);
      return;
    }
    final config = AdventureConfig(
      name: preset.charName,
      gender: preset.gender,
      age: preset.age,
      protagonistClass: preset.profession,
      personality: '',
      protagonistBackground: preset.background,
      worldview: preset.worldview,
      openingScene: preset.openingScene,
      openingOptions: preset.options,
      supportingCharacters: preset.supportingCharacters,
    );

    try {
      if (widget.onStartAdventure != null) {
        await widget.onStartAdventure!(config);
      } else {
        await chat.startAdventureWithConfig(config);
      }
    } catch (e) {
      if (!mounted) return;
      AppFeedback.error(context, '启动预设场景失败，请稍后重试');
    }
  }

  Future<void> _handleDeleteTemplate(String id, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除预存场景'),
        content: Text('确定要删除预存场景「$name」吗？\n删除后此剧本预设将无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final crud = ref.read(resourceCrudControllerProvider);
      final result = await crud.deleteAdventureTemplate(
        id,
        mode: ResourceLibraryMode.adventure,
      );
      if (result.success) {
        if (mounted) AppFeedback.success(context, '已删除场景「$name」');
        await _loadTemplates();
      } else {
        if (mounted) AppFeedback.error(context, '删除失败: ${result.errorMessage}');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDesktop = MediaQuery.sizeOf(context).width >= 900;
    final filtered = _filteredTemplates;

    return PageRefreshScope(
      onRefresh: () async {
        await _loadTemplates();
        return const PageRefreshResult.success();
      },
      child: Scaffold(
        backgroundColor: scheme.surface,
        appBar: AppBar(
          elevation: 0,
          scrolledUnderElevation: 1,
          backgroundColor: scheme.surfaceContainerLowest,
          leadingWidth: isDesktop ? 130 : 56,
          leading: isDesktop
              ? Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Center(
                    child: FilledButton.tonalIcon(
                      onPressed: _handleReturnHome,
                      icon: const Icon(Icons.arrow_back_rounded, size: 16),
                      label: const Text('返回大厅'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  tooltip: '返回大厅',
                  onPressed: _handleReturnHome,
                ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text(
                    '预存场景工坊',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(
                      '${_templates.length} 个剧本',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: scheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
              Text(
                '开箱即用的完整冒险场景设定 · 一键启程开局',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 11,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          actions: [
            FilledButton.icon(
              onPressed: () => _handleOpenWizard(),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('向导新建场景'),
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: '刷新列表',
              onPressed: _loadTemplates,
            ),
            const SizedBox(width: AppSpacing.md),
          ],
        ),
        body: Column(
          children: [
            // 顶部搜索与状态过滤栏
            _buildSearchAndFilterBar(scheme),

            // 主体卡片列表区域
            Expanded(
              child: _loading
                  ? const NarrAItorLoading.normal()
                  : filtered.isEmpty
                      ? _buildEmptyState(scheme)
                      : _buildTemplatesList(filtered, scheme),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchAndFilterBar(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        border: Border(
          bottom: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              onChanged: (val) => setState(() => _searchQuery = val),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                hintText: '搜索场景剧本、世界观或主角...',
                hintStyle: TextStyle(
                  fontSize: 13,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
                isDense: true,
                filled: true,
                fillColor: scheme.surfaceContainerLow,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'all', label: Text('全部')),
              ButtonSegment(value: 'complete', label: Text('已就绪')),
              ButtonSegment(value: 'draft', label: Text('草稿')),
            ],
            selected: {_filterStatus},
            onSelectionChanged: (set) {
              setState(() => _filterStatus = set.first);
            },
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTemplatesList(
    List<Map<String, dynamic>> items,
    ColorScheme scheme,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 900;
        final templateController =
            ref.read(adventureTemplateControllerProvider);

        if (isWide) {
          // 双列网格布局
          return GridView.builder(
            padding: const EdgeInsets.all(AppSpacing.xl),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: AppSpacing.lg,
              mainAxisSpacing: AppSpacing.lg,
              mainAxisExtent: 260,
            ),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              final preset = templateController.buildPresetData(item);
              return _PresetSceneCard(
                item: item,
                preset: preset,
                onStart:
                    preset != null ? () => _handleStartAdventure(preset) : null,
                onCustomize: preset != null
                    ? () => _handleOpenWizard(preset: preset)
                    : null,
                onPreview: () => _showDetailModal(context, item, preset),
                onDelete: () => _handleDeleteTemplate(
                  item['id'] as String? ?? '',
                  item['name'] as String? ?? '预存场景',
                ),
              );
            },
          );
        }

        // 单列流式布局
        return ListView.separated(
          padding: const EdgeInsets.all(AppSpacing.md),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
          itemBuilder: (context, index) {
            final item = items[index];
            final preset = templateController.buildPresetData(item);
            return _PresetSceneCard(
              item: item,
              preset: preset,
              onStart:
                  preset != null ? () => _handleStartAdventure(preset) : null,
              onCustomize: preset != null
                  ? () => _handleOpenWizard(preset: preset)
                  : null,
              onPreview: () => _showDetailModal(context, item, preset),
              onDelete: () => _handleDeleteTemplate(
                item['id'] as String? ?? '',
                item['name'] as String? ?? '预存场景',
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyState(ColorScheme scheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.auto_stories_outlined,
                size: 36,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              _searchQuery.isNotEmpty ? '没有找到符合条件的预存场景' : '暂无预存场景剧本',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _searchQuery.isNotEmpty
                  ? '请尝试更换搜索关键字或重置筛选'
                  : '通过四步向导可以一键生成包含世界观、主角、序章与行动分支的完整剧本预设',
              style: TextStyle(
                fontSize: 13,
                color: scheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: () => _handleOpenWizard(),
              icon: const Icon(Icons.explore_rounded, size: 18),
              label: const Text('启动向导新建场景'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDetailModal(
    BuildContext context,
    Map<String, dynamic> item,
    PresetAdventureData? preset,
  ) async {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final name = item['name'] as String? ?? '剧本详情';

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.auto_stories_rounded, color: scheme.primary, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                name,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: preset == null
                ? const Text('剧本数据解析失败或格式不完整')
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 世界观
                      _buildSectionTitle('🌍 世界观设定', scheme),
                      Text(preset.worldview,
                          style: const TextStyle(height: 1.5)),
                      const SizedBox(height: AppSpacing.md),

                      // 主角人设
                      _buildSectionTitle('👤 主角档案', scheme),
                      Text(
                        '${preset.charName} · ${preset.gender} · ${preset.age} · ${preset.profession}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (preset.background.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(preset.background,
                            style: const TextStyle(fontSize: 12.5)),
                      ],
                      const SizedBox(height: AppSpacing.md),

                      // 序章剧情
                      if (preset.openingScene.isNotEmpty) ...[
                        _buildSectionTitle('🎬 开场序章', scheme),
                        Text(preset.openingScene,
                            style: const TextStyle(height: 1.5)),
                        const SizedBox(height: AppSpacing.md),
                      ],

                      // 初始行动分支
                      if (preset.options.isNotEmpty) ...[
                        _buildSectionTitle('🧭 初始行动分支', scheme),
                        for (int i = 0; i < preset.options.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${i + 1}. ',
                                    style: TextStyle(
                                        color: scheme.primary,
                                        fontWeight: FontWeight.bold)),
                                Expanded(child: Text(preset.options[i])),
                              ],
                            ),
                          ),
                        const SizedBox(height: AppSpacing.md),
                      ],

                      // 配角 NPC
                      if (preset.supportingCharacters.isNotEmpty) ...[
                        _buildSectionTitle('👥 登场配角 (NPC)', scheme),
                        for (final c in preset.supportingCharacters)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child:
                                Text('· ${c.name}（${c.role}）：${c.personality}'),
                          ),
                      ],
                    ],
                  ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
          if (preset != null)
            FilledButton.tonal(
              onPressed: () {
                Navigator.pop(ctx);
                _handleOpenWizard(preset: preset);
              },
              child: const Text('向导载入微调'),
            ),
          if (preset != null)
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                _handleStartAdventure(preset);
              },
              child: const Text('立即启程'),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: scheme.primary,
        ),
      ),
    );
  }
}

/// 预存场景卡片微组件
class _PresetSceneCard extends StatefulWidget {
  final Map<String, dynamic> item;
  final PresetAdventureData? preset;
  final VoidCallback? onStart;
  final VoidCallback? onCustomize;
  final VoidCallback onPreview;
  final VoidCallback onDelete;

  const _PresetSceneCard({
    required this.item,
    required this.preset,
    required this.onStart,
    required this.onCustomize,
    required this.onPreview,
    required this.onDelete,
  });

  @override
  State<_PresetSceneCard> createState() => _PresetSceneCardState();
}

class _PresetSceneCardState extends State<_PresetSceneCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final item = widget.item;
    final preset = widget.preset;

    final name = item['name'] as String? ?? '未命名场景';
    final wvName = item['worldview_name'] as String? ?? '默认世界观';
    final status = item['status'] as String? ?? 'draft';
    final isComplete = status == 'complete';
    final updatedAt =
        item['updated_at'] as String? ?? item['created_at'] as String? ?? '';

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: _isHovered
                ? scheme.primary.withValues(alpha: 0.6)
                : scheme.outlineVariant.withValues(alpha: 0.35),
            width: _isHovered ? 1.5 : 1.0,
          ),
          boxShadow: _isHovered
              ? [
                  BoxShadow(
                    color: scheme.primary.withValues(alpha: 0.08),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [],
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md + 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 头部：剧本标题与状态标签
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Icon(
                      Icons.auto_stories_rounded,
                      size: 18,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '世界观：$wvName',
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: isComplete
                          ? Colors.green.withValues(alpha: 0.12)
                          : Colors.amber.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(
                      isComplete ? '已就绪' : '草稿',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: isComplete
                            ? Colors.green.shade700
                            : Colors.amber.shade800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  PopupMenuButton<String>(
                    icon: Icon(
                      Icons.more_vert_rounded,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                    padding: EdgeInsets.zero,
                    onSelected: (val) {
                      if (val == 'preview') widget.onPreview();
                      if (val == 'customize') widget.onCustomize?.call();
                      if (val == 'delete') widget.onDelete();
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'preview',
                        child: Row(
                          children: [
                            Icon(Icons.visibility_outlined, size: 16),
                            SizedBox(width: 8),
                            Text('完整设定预览'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'customize',
                        child: Row(
                          children: [
                            Icon(Icons.edit_note_rounded, size: 16),
                            SizedBox(width: 8),
                            Text('载入向导微调'),
                          ],
                        ),
                      ),
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline_rounded,
                                size: 16, color: Colors.red),
                            SizedBox(width: 8),
                            Text('删除预存场景', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // 主角与序章信息摘要
              if (preset != null) ...[
                Row(
                  children: [
                    Icon(
                      Icons.person_outline_rounded,
                      size: 14,
                      color: scheme.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '主角：${preset.charName} (${preset.gender} · ${preset.profession})',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: Text(
                    preset.openingScene.isNotEmpty
                        ? preset.openingScene
                        : preset.background.isNotEmpty
                            ? preset.background
                            : '暂无剧情描述摘要',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.45,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ] else ...[
                const Expanded(
                  child: Center(
                    child: Text(
                      '数据结构精简中',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                ),
              ],

              // 底部行动操作条
              Row(
                children: [
                  if (updatedAt.isNotEmpty)
                    Text(
                      formatTimestamp(updatedAt),
                      style: TextStyle(
                        fontSize: 10.5,
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                      ),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: widget.onPreview,
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: const Text('详情', style: TextStyle(fontSize: 12)),
                  ),
                  const SizedBox(width: 4),
                  FilledButton.tonalIcon(
                    onPressed: widget.onStart,
                    icon: const Icon(Icons.play_arrow_rounded, size: 16),
                    label: const Text('一键启程', style: TextStyle(fontSize: 12)),
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
