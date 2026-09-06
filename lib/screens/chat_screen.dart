import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider;
import '../core/theme/app_colors.dart';
import '../core/widgets/form_sub_page_scaffold.dart';
import '../models/dialogue_level.dart';
import '../models/equipment.dart';
import '../providers/chat_provider.dart';
import '../providers/riverpod_providers.dart';
import 'settings_center_screen.dart';
import 'chat/widgets/error_card.dart';
import 'chat/widgets/message_bubble.dart';
import 'chat/widgets/input_bar.dart';
import 'chat/widgets/search_bar.dart';
import 'chat/widgets/multi_char_bar.dart';
import 'chat/widgets/status_toast.dart';
import 'chat/widgets/character_sheet.dart';
import 'chat/widgets/inventory_screen.dart';
import 'chat/widgets/quest_screen.dart';
import 'chat/widgets/quick_menu.dart';
import 'chat/widgets/character_switcher.dart';
import 'chat/widgets/scene_character_manager.dart';
import 'chat/widgets/chat_dialogs.dart';
import 'chat/widgets/world_map.dart';
import 'chat/widgets/shop_dialog.dart';
import '../models/map_encounter.dart';

mixin _ChatStateMixin<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  // searchVisible 改用 ChatProvider.settingsProvider.searchVisible（AppBar 可全局控制）
  Timer? _scrollDebounce;

  Timer? _offlineTimer;
  bool _showOfflineBar = false;
  bool _showGestureHint = true;
  bool _wasStreaming = false;

  bool _userScrolledUp = false;
  bool _scrollPending = false; // 防止 addPostFrameCallback 堆积
  final GlobalKey _targetMessageKey = GlobalKey();
  bool _didScrollToTarget = false;

  String? get initialMessageId => null;

  /// 键盘是否可见（用于移动端键盘收起后延迟滚动）
  double _lastViewInsetsBottom = 0;

  static const double _bottomThreshold = 100.0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScrollChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 在依赖变化时同步亮度状态（避免在 build 中调用 provider 方法）
    final brightness = Theme.of(context).brightness;
    ref.read(chatProvider).settingsProvider.updateBrightness(brightness);
    // 追踪键盘状态（移动端键盘收起后需要延迟滚动）
    _lastViewInsetsBottom = MediaQuery.of(context).viewInsets.bottom;
  }

  @override
  void dispose() {
    _scrollDebounce?.cancel();
    _offlineTimer?.cancel();
    _scrollController.removeListener(_onScrollChanged);
    _textController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  bool _isNearBottom() {
    if (!_scrollController.hasClients) return true;
    final pos = _scrollController.position;
    return pos.pixels >= pos.maxScrollExtent - _bottomThreshold;
  }

  bool _isAutoScrolling = false;

  void _onScrollChanged() {
    if (!_scrollController.hasClients) return;
    if (_isAutoScrolling) return;
    if (_isNearBottom()) {
      _userScrolledUp = false;
    } else {
      _userScrolledUp = true;
    }
  }

  void _scrollToBottom({bool force = false}) {
    // 防止 addPostFrameCallback 堆积（流式输出期间频繁 rebuild 会重复调用）
    if (_scrollPending) return;
    _scrollPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollPending = false;
      if (!_scrollController.hasClients) return;
      if (!force && _userScrolledUp) return;
      _isAutoScrolling = true;
      _scrollController
          .animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      )
          .then((_) {
        _isAutoScrolling = false;
        if (_isNearBottom()) {
          _userScrolledUp = false;
        }
      }).catchError((e) {
        // 防止 _isAutoScrolling 死锁：动画失败/被中断时重置
        debugPrint('[ChatScreen] 自动滚动动画失败: $e');
        _isAutoScrolling = false;
      });
    });
  }

  void _sendMessage([String? text]) {
    final msg = text ?? _textController.text.trim();
    if (msg.isEmpty) return;

    _textController.clear();
    _focusNode.unfocus();
    _userScrolledUp = false;
    HapticFeedback.lightImpact();
    ref.read(chatProvider).sendMessage(msg);

    // 移动端：键盘收起动画约 300ms，需等待其完成后再滚动
    // 否则 maxScrollExtent 仍为键盘弹起时的值，新消息会被键盘区域遮挡
    if (_lastViewInsetsBottom > 0) {
      // 键盘当前可见 → 延迟滚动，等键盘完全收起
      _scrollDebounce?.cancel();
      _scrollDebounce = Timer(const Duration(milliseconds: 350), () {
        _scrollToBottom(force: true);
      });
    } else {
      // 键盘未弹出（桌面端 / 移动端已收起）→ 正常滚动
      _scrollToBottom(force: true);
    }
  }

  Widget buildChatBody(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;
    // Android release 模式：Provider 的 InheritedWidget 依赖链可能失效，
    // 使用 rebuildVersion (ValueNotifier) 作为独立的 Listenable 触发重建
    final cp = ref.read(chatProvider);

    // A1: 监听状态变化，弹出 Toast
    return ListenableBuilder(
      listenable: cp.rebuildVersion,
      builder: (context, _) {
        // 延迟到帧后执行，避免在 build 期间触发 setState/markNeedsBuild
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _checkAndToastStatusChanges(context);
        });
        return Stack(
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxHeight < 350) {
                  return _buildScrollableChatBody(
                      context, isDark, cp, constraints);
                }
                return _buildFixedChatBody(context, isDark, cp);
              },
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Consumer(
                builder: (context, ref, child) {
                  final provider = ref.watch(chatProvider);
                  if (!provider.settingsProvider.isOnline && !_showOfflineBar) {
                    _offlineTimer?.cancel();
                    _offlineTimer =
                        Timer(const Duration(milliseconds: 500), () {
                      if (mounted) {
                        _showOfflineBar = true;
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) setState(() {});
                        });
                      }
                    });
                  } else if (provider.settingsProvider.isOnline &&
                      _showOfflineBar) {
                    _offlineTimer?.cancel();
                    _showOfflineBar = false;
                    // 使用 scheduleMicrotask 避免在 build 中直接 setState
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) setState(() {});
                    });
                  }
                  if (!_showOfflineBar) return const SizedBox.shrink();
                  return Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                    color: AppColors.error,
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.wifi_off, size: 14, color: Colors.white),
                        SizedBox(width: 6),
                        Text('网络不可用，消息可能无法发送',
                            style:
                                TextStyle(fontSize: 12, color: Colors.white)),
                      ],
                    ),
                  );
                },
              ),
            ),
            _buildDrawerHandle(context, isDark),
          ],
        );
      },
    );
  }

  Widget _buildDrawerHandle(BuildContext context, bool isDark) {
    final scaffold = Scaffold.maybeOf(context);
    if (scaffold == null || !scaffold.hasDrawer) {
      return const SizedBox.shrink();
    }

    final bgColor = isDark
        ? AppColors.darkSurface.withValues(alpha: 0.88)
        : Colors.white.withValues(alpha: 0.9);
    final borderColor =
        isDark ? const Color(0xFF2A2A44) : const Color(0xFFE0E0E0);

    return Positioned(
      top: 8,
      left: 8,
      child: SafeArea(
        bottom: false,
        child: Material(
          color: bgColor,
          elevation: 2,
          borderRadius: BorderRadius.circular(18),
          child: Tooltip(
            message: '打开侧边栏',
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: scaffold.openDrawer,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: borderColor),
                ),
                child: Icon(
                  Icons.menu_rounded,
                  size: 20,
                  color: isDark
                      ? AppColors.darkTextPrimary
                      : AppColors.textPrimary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── 阅读器风格：全屏沉浸 + 浮动控件 ──
  Widget _buildFixedChatBody(
      BuildContext context, bool isDark, ChatProvider cp) {
    return Stack(
      children: [
        // 全屏消息列表 (无边距)
        _buildMessageList(context, isDark ? Brightness.dark : Brightness.light),
        // 浮动顶栏：搜索 + 多角色 (仅在有内容时显示)
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _buildFloatingTopBar(isDark, cp),
        ),
        // 浮动底部：选项面板 (流式结束后显示)
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: _buildFloatingBottom(isDark, cp),
        ),
      ],
    );
  }

  // ── 浮动顶栏：搜索 + 多角色（毛玻璃效果） ──
  Widget _buildFloatingTopBar(bool isDark, ChatProvider cp) {
    final showSearch = cp.settingsProvider.searchVisible;
    final config = cp.adventureConfig;
    final hasMultiChar = config != null &&
        config.supportingCharacters.where((sc) => sc.isAlive).isNotEmpty;

    if (!showSearch && !hasMultiChar) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: (isDark ? Colors.black : Colors.white).withValues(alpha: 0.85),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showSearch) _buildSearchBar(cp),
            if (hasMultiChar) const MultiCharacterBar(),
          ],
        ),
      ),
    );
  }

  // ── 浮动底部：选项面板 + 角色切换 + 输入栏 ──
  Widget _buildFloatingBottom(bool isDark, ChatProvider cp) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (cp.lastSceneCandidates.isNotEmpty ||
            cp.pendingSceneCandidates.isNotEmpty)
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const SceneCharacterManagerScreen())),
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: AppColors.primary.withValues(alpha: 0.12),
                child: const Row(children: [
                  Icon(Icons.person_add_alt_1_outlined, size: 18),
                  SizedBox(width: 8),
                  Text('AI 提示：有待确认的场景设定'),
                  Spacer(),
                  Icon(Icons.chevron_right),
                ]),
              ),
            ),
          ),
        // 角色切换 + 快捷菜单
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurface : AppColors.background,
            border: Border(
              top: BorderSide(
                color:
                    isDark ? const Color(0xFF2A2A44) : const Color(0xFFE0E0E0),
              ),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.darkSurfaceElevated.withValues(alpha: 0.55)
                  : Colors.white.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.06),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  Expanded(child: _buildCharacterSwitcher(isDark)),
                  IconButton(
                    tooltip: '场景角色管理',
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) =>
                                const SceneCharacterManagerScreen())),
                    icon: const Icon(Icons.group_outlined),
                  ),
                  const SizedBox(width: 8),
                  QuickMenuButton(
                    isDark: isDark,
                    onShowInventory: _showInventoryPage,
                    onShowQuests: _showQuestsPanel,
                    onShowSkills: _showSkillsPanel,
                    onShowMap: _showWorldMap,
                    onShowWordCount: _showDialogueLevelPage,
                    onShowSettings: _showSettingsCenter,
                  ),
                ],
              ),
            ),
          ),
        ),
        // 输入栏
        ChatInputBar(
          isDark: isDark,
          controller: _textController,
          focusNode: _focusNode,
          onSend: () => _sendMessage(),
          onStop: () => ref.read(chatProvider).cancelStreaming(),
        ),
      ],
    );
  }

  // ── 极小窗口：整页可滚动，防止 Column overflow ──
  Widget _buildScrollableChatBody(BuildContext context, bool isDark,
      ChatProvider cp, BoxConstraints constraints) {
    return Stack(
      children: [
        SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: _buildMessageList(
                context, isDark ? Brightness.dark : Brightness.light),
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _buildFloatingTopBar(isDark, cp),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: _buildFloatingBottom(isDark, cp),
        ),
      ],
    );
  }

  // A1: 跟踪上次游戏状态，变化时弹出 StatusToast
  int _lastHp = -1;
  int _lastEnergy = -1;
  int _lastGold = -1;

  /// 估算消息列表下方的 UI 元素总高度（用于滚动按钮偏移和消息列表底部 padding）
  double _estimateBottomHeight(ChatProvider p) {
    double h = 130; // 输入栏基础高度（SafeArea + 内边距 + QuickActions + 文本框行）
    // 角色切换器：仅当有多个角色时显示
    final config = p.adventureConfig;
    if (config != null) {
      final aliveCount =
          1 + config.supportingCharacters.where((sc) => sc.isAlive).length;
      if (aliveCount > 1) h += 48;
    }
    // 底部行动选项已取消自动弹出，不再预留高度
    return h;
  }

  void _checkAndToastStatusChanges(BuildContext context) {
    final p = ref.read(chatProvider);
    // 离线横幅可见时，Toast 需下移避免重叠
    final toastOffset = _showOfflineBar ? 30.0 : 0.0;
    if (_lastHp >= 0 && p.gameState.hp != _lastHp) {
      final delta = p.gameState.hp - _lastHp;
      StatusToast.show(context,
          icon: '❤️',
          delta: delta,
          current: p.gameState.hp,
          max: p.gameState.maxHp,
          topOffset: toastOffset);
    }
    if (_lastEnergy >= 0 && p.gameState.energy != _lastEnergy) {
      final delta = p.gameState.energy - _lastEnergy;
      StatusToast.show(context,
          icon: '⚡',
          delta: delta,
          current: p.gameState.energy,
          max: p.gameState.maxEnergy,
          topOffset: toastOffset);
    }
    if (_lastGold >= 0 && p.gameState.gold != _lastGold) {
      final delta = p.gameState.gold - _lastGold;
      StatusToast.show(context,
          icon: '💰',
          delta: delta,
          current: p.gameState.gold,
          max: 999999,
          topOffset: toastOffset);
    }
    _lastHp = p.gameState.hp;
    _lastEnergy = p.gameState.energy;
    _lastGold = p.gameState.gold;
  }

  Widget _buildSearchBar(ChatProvider cp) {
    return ListenableBuilder(
      listenable: cp.rebuildVersion,
      builder: (_, __) {
        final p = ref.read(chatProvider);
        if (!p.settingsProvider.searchVisible) return const SizedBox.shrink();
        return ChatSearchBar(
          onClose: () => p.toggleSearch(),
        );
      },
    );
  }

  Widget _buildCharacterSwitcher(bool isDark) {
    return ListenableBuilder(
      listenable: ref.read(chatProvider).rebuildVersion,
      builder: (_, __) {
        final p = ref.read(chatProvider);
        return CharacterSwitcher(
          isDark: isDark,
          config: p.adventureConfig,
          gameState: p.inGame ? p.gameState : null,
          selectedCharacterIndex: p.selectedCharacterIndex,
          autoAdvanceCharacter: p.autoAdvanceCharacter,
          sceneParticipantIds: p.sceneParticipantIds,
          onSelectCharacter: p.selectCharacter,
          onToggleAutoAdvance: p.toggleAutoAdvance,
          onTapCharacter: (index, name, role, hp, maxHp) =>
              _showCharacterSheet(index, name, role, hp, maxHp),
        );
      },
    );
  }

  Future<void> _showDialogueLevelPage() async {
    final provider = ref.read(chatProvider);
    await showFormSubPage<void>(
      context: context,
      title: '字数设置',
      maxWidth: 760,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setPageState) {
          final current = provider.settingsProvider.dialogueLevel;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.format_size,
                        size: 18, color: AppColors.primary),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      '调整场景对话回复长度',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                '当前：${current.id} · ${current.label} · ${current.wordRangeLabel}',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 18),
              ...DialogueLevel.values.map((level) {
                final selected = level.id == current.id;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: selected
                        ? null
                        : () async {
                            await provider.settingsProvider
                                .setDialogueLevel(level);
                            if (ctx.mounted) {
                              setPageState(() {});
                            }
                          },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.primaryLight.withValues(alpha: 0.6)
                            : Theme.of(ctx).brightness == Brightness.dark
                                ? AppColors.darkSurfaceElevated
                                : AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: selected
                              ? AppColors.primary.withValues(alpha: 0.45)
                              : Theme.of(ctx).brightness == Brightness.dark
                                  ? Colors.white.withValues(alpha: 0.1)
                                  : Colors.black.withValues(alpha: 0.08),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            selected
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                            size: 18,
                            color: selected
                                ? AppColors.primary
                                : AppColors.textSecondary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${level.id} · ${level.label}',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${level.wordRangeLabel} · ${level.description}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }

  void _showCharacterSheet(
      int index, String name, String role, int? hp, int? maxHp) {
    // A3: 弹出角色卡 Sheet
    final p = ref.read(chatProvider);
    final gs = p.gameState;
    // index < 0 = 主角 (characterId = null → 显示公共+已装备)
    // index >= 0 = 配角 (characterId = name)
    final characterId = index < 0 ? null : name;
    showCharacterSheet(
      context: context,
      name: name,
      role: role,
      hp: hp ?? gs.hp,
      maxHp: maxHp ?? gs.maxHp,
      energy: gs.energy,
      maxEnergy: gs.maxEnergy,
      gold: gs.gold,
      isDark: Theme.of(context).brightness == Brightness.dark,
      // v2.0 params
      level: gs.level,
      mp: gs.mp,
      maxMp: gs.maxMp,
      skillPoints: gs.skillPoints,
      baseAtk: gs.baseAtk,
      baseDef: gs.baseDef,
      baseSpeed: gs.baseSpeed,
      experience: gs.experience,
      // v2.13: 结构化背包
      characterId: characterId,
      initialIndex: index,
    );
  }

  void _showQuestsPanel() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const QuestScreen()),
    );
  }

  void _showInventoryPage() {
    final p = ref.read(chatProvider);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => InventoryScreen(
          adventureId: p.currentAdventureId,
          legacyInventory: p.gameState.inventory,
        ),
      ),
    );
  }

  void _showSkillsPanel() {
    // Reuse character sheet for now
    _showCharacterSheet(-1, '', '主角', null, null);
  }

  void _showWorldMap() {
    final p = ref.read(chatProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => WorldMapScreen(
        adventureId: p.currentAdventureId,
        config: p.adventureConfig,
        onMoveTo: (node) async {
          final result = await p.adventureProvider.moveToMapNode(
            targetNodeId: node.id,
            operationId:
                'ui_${DateTime.now().microsecondsSinceEpoch}_${node.id}',
          );
          if (!mounted) return;
          if (!result.applied) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(result.error ?? '移动失败'),
                duration: const Duration(seconds: 2),
              ),
            );
            return;
          }
          final newState = p.gameState;

          // Roll random encounter for unexplored nodes
          if (!node.explored) {
            final encounter = ref
                .read(adventureGameControllerProvider)
                .rollMapEncounter(isExplored: false);
            if (encounter != null) {
              _handleMapEncounter(encounter, node);
            }
          }

          // Auto-open shop on town nodes
          if ({'town', 'city', 'settlement', 'shop'}.contains(node.type)) {
            ShopDialog.show(
              context: context,
              playerGold: newState.gold,
              playerInventory: [], // populated by inventory manager
              gameState: newState,
              nodeType: node.type,
              isDark: isDark,
              onBuy: (item) {
                final gs2 = p.gameState;
                if (gs2.gold >= item.price) {
                  p.adventureProvider
                      .setGameState(gs2.copyWith(gold: gs2.gold - item.price));
                  // v2.13: 经 AdventureGameController 添加物品
                  if (p.currentAdventureId != null) {
                    ref.read(adventureGameControllerProvider).addSimpleItem(
                          adventureId: p.currentAdventureId!,
                          name: item.name,
                          icon: item.icon,
                          type: item.type == ItemType.equipment
                              ? ItemType.equipment
                              : ItemType.consumable,
                          quantity: 1,
                          data: item.data,
                        );
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('✅ 购买了 ${item.name}！')),
                  );
                }
              },
            );
          }

          // Notify AI of scene change
          p.sendMessage('[移动到 ${node.name}]');
        },
      ),
    ));
  }

  void _showSettingsCenter() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsCenterScreen()),
    );
  }

  void _handleMapEncounter(MapEncounter encounter, MapNodeData node) {
    final p = ref.read(chatProvider);
    switch (encounter.type) {
      case MapEncounterType.item:
        if (encounter.hasItem) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('🎁 发现了 ${encounter.itemName}！'),
              backgroundColor: AppColors.success,
              duration: const Duration(seconds: 2),
            ),
          );
          // v2.13: 通过 AdventureGameController 添加物品，GameState 兜底
          if (p.currentAdventureId != null) {
            ref.read(adventureGameControllerProvider).addSimpleItem(
                  adventureId: p.currentAdventureId!,
                  name: encounter.itemName ?? '未知物品',
                  icon: encounter.itemIcon ?? '🎁',
                  type: ItemType.material,
                  quantity: 1,
                );
          } else {
            final gs = p.gameState;
            final newInv = List<String>.from(gs.inventory)
              ..add('${encounter.itemIcon} ${encounter.itemName}');
            p.adventureProvider.setGameState(gs.copyWith(inventory: newInv));
          }
        }
        break;
      case MapEncounterType.combat:
        final enemy = ref.read(adventureGameControllerProvider).randomEnemy();
        // Trigger combat via AI — the AI will set combat:true in JSON response
        p.sendMessage(
            '[遭遇战斗] 在前往${node.name}的路上，你遇到了${enemy['name']}（${enemy['icon']} HP:${enemy["hp"]} ATK:${enemy["atk"]}）！');
        break;
      case MapEncounterType.special:
        // Delegate to AI for narrative
        p.sendMessage('[随机事件] 在前往${node.name}的途中，${encounter.narrative}');
        break;
    }
  }

  Widget _buildMessageList(BuildContext context, Brightness brightness) {
    // 使用 ListenableBuilder + rebuildVersion 而非 Consumer<ChatProvider>，
    // 绕过 Provider 的 InheritedWidget 依赖链（Android release 可能失效）。
    // rebuildVersion 是独立的 ValueNotifier，直接调用 setState 触发重建。
    final cp = ref.read(chatProvider);
    return ListenableBuilder(
      listenable: cp.rebuildVersion,
      builder: (context, _) {
        final provider = ref.read(chatProvider);
        final autoScroll = provider.settingsProvider.autoScrollDuringGeneration;
        if (autoScroll && provider.isStreaming && !_userScrolledUp) {
          _scrollToBottom();
        }
        if (provider.scrollToBottomPending) {
          provider.consumeScrollToBottom();
          _scrollToBottom(force: true);
        }
        if (_wasStreaming && !provider.isStreaming && !_userScrolledUp) {
          HapticFeedback.mediumImpact();
        }
        _wasStreaming = provider.isStreaming;
        return Stack(
          children: [
            NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification is UserScrollNotification) {
                  if (notification.direction != ScrollDirection.idle) {
                    _isAutoScrolling = false;
                    _scrollPending = false;
                  }
                }
                if (notification is ScrollUpdateNotification) {
                  if (!_isAutoScrolling) {
                    final nearBottom = _isNearBottom();
                    if (!nearBottom && !_userScrolledUp) {
                      setState(() => _userScrolledUp = true);
                    } else if (nearBottom && _userScrolledUp) {
                      setState(() => _userScrolledUp = false);
                    }
                  }
                }
                return false;
              },
              child: RepaintBoundary(
                child: Column(
                  children: [
                    if (_showGestureHint && provider.messages.isNotEmpty)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Row(children: [
                          const Text('💡', style: TextStyle(fontSize: 16)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '右滑消息可重试 · 左滑可删除 · 长按可编辑 · 点击书签可收藏',
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: () => setState(() => _showGestureHint = false),
                            child: Icon(
                              Icons.close,
                              size: 16,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ]),
                      ),
                    Expanded(
                      child: ListView.builder(
                        controller: _scrollController,
                        // ignore: deprecated_member_use
                        cacheExtent: 500,
                        addRepaintBoundaries: true,
                        padding: EdgeInsets.only(
                          left: 8, right: 8, top: 60, // 顶部分配给浮动搜索栏
                          bottom: 32 + _estimateBottomHeight(provider),
                        ),
                        itemCount: provider.messages.length +
                            (provider.isStreaming ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (provider.isStreaming &&
                              index == provider.messages.length) {
                            return StreamingBubble(
                              key:
                                  ValueKey('streaming_${provider.messages.length}'),
                              chatFontSize:
                                  provider.chatFontSize / provider.textScaleFactor,
                              brightness: brightness,
                              aiName: provider.selectedCharacterName ??
                                  provider.adventureConfig?.name ??
                                  '冒险助手',
                              streamNotifier: provider.streamNotifier,
                              reasoningStreamNotifier:
                                  provider.reasoningStreamNotifier,
                              isThinkingNotifier: provider.isThinkingNotifier,
                            );
                          }
                          final message = provider.messages[index];
                          final bubble =
                              _buildMessageBubble(message, brightness, provider);
                          if (initialMessageId != null &&
                              message.id.toString() == initialMessageId) {
                            if (!_didScrollToTarget) {
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                final target = _targetMessageKey.currentContext;
                                if (target != null && mounted) {
                                  _didScrollToTarget = true;
                                  Scrollable.ensureVisible(target,
                                      duration: const Duration(milliseconds: 320),
                                      alignment: .35);
                                }
                              });
                            }
                            return KeyedSubtree(
                                key: _targetMessageKey, child: bubble);
                          }
                          return bubble;
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_userScrolledUp)
              Positioned(
                right: 16,
                bottom: 16 + _estimateBottomHeight(provider),
                child: FloatingActionButton.small(
                  onPressed: () {
                    setState(() => _userScrolledUp = false);
                    _scrollToBottom(force: true);
                  },
                  backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  foregroundColor: Theme.of(context).colorScheme.primary,
                  elevation: 2,
                  child: const Icon(Icons.arrow_downward_rounded, size: 18),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildMessageBubble(
      message, Brightness brightness, ChatProvider provider) {
    final isUser = message.isUser;

    if (!isUser && message.isError) {
      return ErrorCard(
        key: ValueKey('err_${message.id}'),
        message: message,
        chatFontSize: provider.chatFontSize / provider.textScaleFactor,
        brightness: brightness,
        onRetry: () => provider.retryLast(),
        onSwitchModel: () => showRetryMenu(context),
      );
    }

    if (isUser) {
      final persona = provider.activePersona;
      return UserBubble(
        key: ValueKey('usr_${message.id}'),
        message: message,
        chatFontSize: provider.chatFontSize / provider.textScaleFactor,
        userAvatarLabel: persona != null && persona.name.isNotEmpty
            ? persona.name[0].toUpperCase()
            : '我',
        onLongPress: () => showMessageMenu(context, message, provider),
        onRegenerate: () => regenerateMessage(message, provider),
        canRegenerate: !provider.isLoading && !provider.isStreaming,
        isBookmarked: provider.bookmarkedMessageIds.contains(message.id),
        onToggleBookmark: () => provider.toggleBookmark(message.id),
        onDelete: () => provider.deleteMessage(message),
        onCopy: () => copyMessageDisplayText(context, message),
        onEdit: () => showEditDialog(context, message, provider),
      );
    }
    return AiBubble(
      key: ValueKey('ai_${message.id}'),
      message: message,
      chatFontSize: provider.chatFontSize / provider.textScaleFactor,
      brightness: brightness,
      aiName: provider.selectedCharacterName ??
          provider.adventureConfig?.name ??
          '冒险助手',
      emotion: provider.messagingProvider.detectEmotion(message.content),
      isBookmarked: provider.bookmarkedMessageIds.contains(message.id),
      onLongPress: () => showMessageMenu(context, message, provider),
      onRegenerate: () => regenerateMessage(message, provider),
      canRegenerate: !provider.isLoading && !provider.isStreaming,
      onDelete: () => provider.deleteMessage(message),
      onToggleBookmark: () => provider.toggleBookmark(message.id),
      onCopy: () => copyMessageDisplayText(context, message),
      onOptionTap: (option) => provider.sendMessage(option),
    );
  }

  List<dynamic> get bookmarkedMessages {
    final provider = ref.read(chatProvider);
    return provider.messages
        .where((m) => provider.bookmarkedMessageIds.contains(m.id))
        .toList();
  }
}

class EmbeddedAdventureScreen extends ConsumerStatefulWidget {
  final String? initialMessageId;
  const EmbeddedAdventureScreen({super.key, this.initialMessageId});

  @override
  ConsumerState<EmbeddedAdventureScreen> createState() =>
      _EmbeddedAdventureScreenState();
}

class _EmbeddedAdventureScreenState
    extends ConsumerState<EmbeddedAdventureScreen> with _ChatStateMixin {
  @override
  String? get initialMessageId => widget.initialMessageId;
  @override
  Widget build(BuildContext context) {
    return buildChatBody(context);
  }
}
