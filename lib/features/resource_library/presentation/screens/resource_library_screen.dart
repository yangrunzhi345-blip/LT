import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider;

import '../../../../core/refresh/page_refresh_scope.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/narr_aitor_dropdown.dart';
import '../../../../core/widgets/narr_aitor_library_header.dart';
import '../../../../models/resource_library_mode.dart';
import '../../../../models/worldview_details.dart';
import '../../../../providers/riverpod_providers.dart';
import '../../../../screens/resource_library/character_card_tab.dart';
import '../../../../screens/resource_library/import_history.dart';
import '../../../../screens/resource_library/npc_tab.dart';
import '../../../../screens/resource_library/scene_batch_import_page.dart';
import '../../../../screens/resource_library/worldview_tab.dart';
import '../../../adventure/presentation/templates/screens/preset_scenes_screen.dart';

/// 现代化资料库与世界观资产 Codex 主屏
/// 基于功能层重构，提供纯净白板状态，聚合世界观预设、角色卡档案、NPC 关系网与预存剧本模板
class ResourceLibraryScreen extends ConsumerStatefulWidget {
  final int initialTab;
  final VoidCallback? onMenuPressed;
  final VoidCallback? onSwitchMode;
  final ResourceLibraryMode mode;
  final String? initialResourceId;

  const ResourceLibraryScreen({
    super.key,
    this.initialTab = 0,
    this.onMenuPressed,
    this.onSwitchMode,
    this.mode = ResourceLibraryMode.adventure,
    this.initialResourceId,
  });

  @override
  ConsumerState<ResourceLibraryScreen> createState() =>
      _ResourceLibraryScreenState();
}

class _ResourceLibraryScreenState extends ConsumerState<ResourceLibraryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  List<Map<String, dynamic>> _worldviewItems = [];
  bool _worldviewLoading = true;
  WorldviewEditingMode _worldviewEditingMode = WorldviewEditingMode.simple;

  List<Map<String, dynamic>> _charItems = [];
  bool _charLoading = true;

  List<Map<String, dynamic>> _npcItems = [];
  bool _npcLoading = true;

  String _query = '';

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 2),
    );
    _tabCtrl.addListener(() {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAllData();
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  void _loadAllData() {
    _loadWorldviews();
    _loadChars();
    _loadNpcs();
  }

  Future<void> _loadWorldviews() async {
    try {
      final crud = ref.read(resourceCrudControllerProvider);
      final rows = await crud.loadWorldviewPresets(mode: widget.mode);
      _moveInitialFirst(rows);
      if (mounted) {
        setState(() {
          _worldviewItems = rows;
          _worldviewLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _worldviewLoading = false);
    }
  }

  Future<void> _loadChars() async {
    try {
      final crud = ref.read(resourceCrudControllerProvider);
      final rows = await crud.loadCharacterCards(mode: widget.mode);
      _moveInitialFirst(rows);
      if (mounted) {
        setState(() {
          _charItems = rows;
          _charLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _charLoading = false);
    }
  }

  Future<void> _loadNpcs() async {
    try {
      final crud = ref.read(resourceCrudControllerProvider);
      final rows = await crud.loadNpcCards(mode: widget.mode);
      _moveInitialFirst(rows);
      if (mounted) {
        setState(() {
          _npcItems = rows;
          _npcLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _npcLoading = false);
    }
  }

  void _moveInitialFirst(List<Map<String, dynamic>> rows) {
    final id = widget.initialResourceId;
    if (id == null) return;
    final index = rows.indexWhere((row) => row['id']?.toString() == id);
    if (index > 0) rows.insert(0, rows.removeAt(index));
  }

  Future<PageRefreshResult> _refreshCurrentTab() async {
    switch (_tabCtrl.index) {
      case 0:
        await _loadWorldviews();
        break;
      case 1:
        await _loadChars();
        break;
      case 2:
      default:
        await _loadNpcs();
        break;
    }
    return const PageRefreshResult.success();
  }

  List<Map<String, dynamic>> _filtered(List<Map<String, dynamic>> values) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return values;
    return values
        .where((item) => item.values.join(' ').toLowerCase().contains(query))
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 700;
    final dark = Theme.of(context).brightness == Brightness.dark;

    return PageRefreshScope(
      onRefresh: _refreshCurrentTab,
      child: Scaffold(
        appBar: PreferredSize(
          preferredSize: Size.fromHeight(compact ? 224 : 210),
          child: NarrAItorLibraryHeader(
            eyebrow: 'CODEX',
            title: widget.mode.title,
            onBackPressed: () =>
                ref.read(chatProvider).navigateToAdventureHome(),
            onMenuPressed: widget.onMenuPressed,
            onSwitchMode: widget.onSwitchMode,
            actions: _buildHeaderActions(context, compact),
            secondary: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppColors.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.mode.title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '纯净初始设定库，服务于 AI 剧情、世界模拟和场景推演。',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).hintColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            search: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded),
                  hintText: '搜索场景资料档案...',
                  isDense: true,
                  filled: true,
                  fillColor: dark ? AppColors.darkBackground : AppColors.background,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            tabs: TabBar(
              controller: _tabCtrl,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              tabs: const [
                Tab(text: '世界观'),
                Tab(text: '角色卡'),
                Tab(text: 'NPC'),
              ],
            ),
          ),
        ),
        body: AppRefreshIndicator(
          child: ColoredBox(
            color: dark ? AppColors.darkBackground : AppColors.background,
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                WorldviewTab.buildList(
                  _worldviewLoading,
                  _filtered(_worldviewItems),
                  context,
                  _loadWorldviews,
                  mode: widget.mode,
                  editingMode: _worldviewEditingMode,
                ),
                CharacterCardTab.buildList(
                  _charLoading,
                  _filtered(_charItems),
                  _worldviewItems,
                  context,
                  _loadChars,
                  mode: widget.mode,
                ),
                NpcTab.buildList(
                  _npcLoading,
                  _filtered(_npcItems),
                  _worldviewItems,
                  context,
                  _loadNpcs,
                  mode: widget.mode,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildHeaderActions(BuildContext context, bool compact) {
    final historyButton = SizedBox(
      width: 36,
      height: 36,
      child: NarrAItorDropdown<String>(
        value: null,
        tooltip: '导入历史',
        expanded: false,
        showArrow: false,
        menuWidth: 160,
        triggerHeight: 36,
        triggerPadding: EdgeInsets.zero,
        selectedBuilder: (_) =>
            const Center(child: Icon(Icons.history_rounded)),
        onChanged: (value) {
          if (value == 'history') {
            ImportHistory.show(context, mode: widget.mode);
          }
        },
        options: const [
          NarrAItorDropdownOption(value: 'history', label: '导入记录'),
        ],
      ),
    );

    final addButton = switch (_tabCtrl.index) {
      0 => IconButton(
          icon: const Icon(Icons.add_rounded),
          tooltip: '新建世界观',
          onPressed: () => WorldviewTab.showEdit(
            context,
            null,
            _loadWorldviews,
            mode: widget.mode,
            editingMode: _worldviewEditingMode,
          ),
        ),
      1 => IconButton(
          icon: const Icon(Icons.add_rounded),
          tooltip: '新建角色卡',
          onPressed: () => CharacterCardTab.showEdit(
            context,
            null,
            _loadChars,
            mode: widget.mode,
          ),
        ),
      2 => IconButton(
          icon: const Icon(Icons.add_rounded),
          tooltip: '新建 NPC',
          onPressed: () => NpcTab.showEdit(
            context,
            null,
            _loadNpcs,
            _worldviewItems,
            mode: widget.mode,
          ),
        ),
      _ => const SizedBox.shrink(),
    };

    final aiButton = switch (_tabCtrl.index) {
      0 => _aiButton(
          context,
          compact,
          'AI 导入世界观',
          () => WorldviewTab.showAiImport(
            context,
            _loadWorldviews,
            _worldviewItems,
            mode: widget.mode,
          ),
        ),
      1 => _aiButton(
          context,
          compact,
          'AI 导入角色卡',
          () async {
            final detailMode = await showSceneImportDetailModePicker(context);
            if (!context.mounted || detailMode == null) return;
            CharacterCardTab.showAiImport(
              context,
              _loadChars,
              _worldviewItems,
              characterCards: _charItems,
              detailInstruction: detailMode.instruction,
              mode: widget.mode,
            );
          },
        ),
      2 => _aiButton(
          context,
          compact,
          'AI 导入 NPC',
          () async {
            final detailMode = await showSceneImportDetailModePicker(context);
            if (!context.mounted || detailMode == null) return;
            NpcTab.showAiImport(
              context,
              _loadNpcs,
              _worldviewItems,
              characterCards: _charItems,
              detailInstruction: detailMode.instruction,
              mode: widget.mode,
            );
          },
        ),
      _ => const SizedBox.shrink(),
    };

    final batchButton = switch (_tabCtrl.index) {
      1 => IconButton(
          icon: const Icon(Icons.groups_2_outlined),
          tooltip: '批量 AI 导入角色卡',
          onPressed: () async {
            final detailMode = await showSceneImportDetailModePicker(context);
            if (!context.mounted || detailMode == null) return;
            showSceneBatchImportPage(
              context,
              kind: SceneBatchImportKind.character,
              worldviews: _worldviewItems,
              relationshipCandidates: [..._charItems, ..._npcItems],
              detailMode: detailMode,
              onSaved: _loadChars,
              mode: widget.mode,
            );
          },
        ),
      2 => IconButton(
          icon: const Icon(Icons.groups_2_outlined),
          tooltip: '批量 AI 导入 NPC',
          onPressed: () async {
            final detailMode = await showSceneImportDetailModePicker(context);
            if (!context.mounted || detailMode == null) return;
            showSceneBatchImportPage(
              context,
              kind: SceneBatchImportKind.npc,
              worldviews: _worldviewItems,
              relationshipCandidates: [..._charItems, ..._npcItems],
              detailMode: detailMode,
              onSaved: _loadNpcs,
              mode: widget.mode,
            );
          },
        ),
      _ => const SizedBox.shrink(),
    };

    final editingModeButton = _tabCtrl.index == 0
        ? NarrAItorDropdown<WorldviewEditingMode>(
            tooltip: '编辑模式',
            value: _worldviewEditingMode,
            expanded: false,
            triggerHeight: 36,
            triggerPadding: const EdgeInsets.symmetric(horizontal: 10),
            prefix: const Icon(Icons.tune_rounded, size: 16),
            onChanged: (value) {
              if (value == null) return;
              if (value == _worldviewEditingMode) return;
              setState(() {
                _worldviewEditingMode = value;
                _worldviewLoading = true;
              });
              _loadWorldviews();
            },
            options: const [
              NarrAItorDropdownOption(
                value: WorldviewEditingMode.simple,
                label: '简洁模式',
              ),
              NarrAItorDropdownOption(
                value: WorldviewEditingMode.detailed,
                label: '详细模式',
              ),
            ],
          )
        : const SizedBox.shrink();

    final scenesButton = TextButton.icon(
      onPressed: () {
        AppRouter.push(
          context,
          pageBuilder: (_) => const PresetScenesScreen(),
        );
      },
      icon: const Icon(Icons.auto_stories_outlined, size: 16),
      label: Text(compact ? '' : '预存场景工坊'),
      style: TextButton.styleFrom(
        foregroundColor: Theme.of(context).colorScheme.primary,
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
    );

    return [
      scenesButton,
      addButton,
      aiButton,
      batchButton,
      editingModeButton,
      historyButton,
    ];
  }

  Widget _aiButton(
    BuildContext context,
    bool compact,
    String tooltip,
    VoidCallback onTap,
  ) {
    return compact
        ? IconButton(
            icon: const Icon(Icons.auto_awesome_rounded),
            tooltip: tooltip,
            onPressed: onTap,
          )
        : TextButton.icon(
            icon: const Icon(Icons.auto_awesome_rounded, size: 17),
            label: const Text('AI助手'),
            onPressed: onTap,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.accent,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 36),
            ),
          );
  }
}
