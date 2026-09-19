import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/refresh/page_refresh_scope.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_radius.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/widgets/form_sub_page_scaffold.dart';
import '../../../../../models/dialogue_level.dart';
import '../../../../../providers/riverpod_providers.dart';
import '../../../../../screens/chat/widgets/character_sheet.dart';
import '../../../../../screens/chat/widgets/character_switcher.dart';
import '../../../../../screens/chat/widgets/inventory_screen.dart';
import '../../../../../screens/chat/widgets/search_bar.dart';
import '../../../../../screens/settings_center_screen.dart';
import '../widgets/session_app_bar.dart';
import '../widgets/session_input_bar.dart';
import '../widgets/session_message_list.dart';
import '../widgets/status_hud_bar.dart';

/// 现代化场景对话与交互主屏
/// 采用功能层组件解耦设计，集成状态 HUD、流式打字气泡、行动选项卡与 RPG 快捷模态
class AdventureSessionScreen extends ConsumerStatefulWidget {
  final VoidCallback? onMenuPressed;
  final String? initialMessageId;

  const AdventureSessionScreen({
    super.key,
    this.onMenuPressed,
    this.initialMessageId,
  });

  @override
  ConsumerState<AdventureSessionScreen> createState() =>
      _AdventureSessionScreenState();
}

class _AdventureSessionScreenState
    extends ConsumerState<AdventureSessionScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final brightness = Theme.of(context).brightness;
    ref.read(chatProvider).settingsProvider.updateBrightness(brightness);
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _sendMessage({String? overrideText}) {
    final text = overrideText ?? _textController.text.trim();
    if (text.isEmpty) return;

    final provider = ref.read(chatProvider);
    if (provider.isLoading || provider.isStreaming) return;

    if (overrideText == null) {
      _textController.clear();
    }
    provider.sendMessage(text);
  }

  void _showCharacterSheetModal(
    int index,
    String name,
    String role,
    int? hp,
    int? maxHp,
  ) {
    final p = ref.read(chatProvider);
    final gs = p.gameState;
    final config = p.adventureConfig;
    final fallbackProtagonistName =
        config?.protagonistCharacter?.characterName.isNotEmpty == true
            ? config!.protagonistCharacter!.characterName
            : (p.activePersona?.name.isNotEmpty == true
                ? p.activePersona!.name
                : (config?.name.isNotEmpty == true ? config!.name : '主角'));
    final fallbackProtagonistRole = config?.protagonistClass.isNotEmpty == true
        ? config!.protagonistClass
        : '主角';

    final effectiveName =
        (name.isEmpty || index < 0) ? fallbackProtagonistName : name;
    final effectiveRole =
        (role.isEmpty || index < 0) ? fallbackProtagonistRole : role;
    final characterId = index < 0 ? null : name;

    showCharacterSheet(
      context: context,
      name: effectiveName,
      role: effectiveRole,
      hp: hp ?? gs.hp,
      maxHp: maxHp ?? gs.maxHp,
      energy: gs.energy,
      maxEnergy: gs.maxEnergy,
      gold: gs.gold,
      isDark: Theme.of(context).brightness == Brightness.dark,
      level: gs.level,
      mp: gs.mp,
      maxMp: gs.maxMp,
      skillPoints: gs.skillPoints,
      baseAtk: gs.baseAtk,
      baseDef: gs.baseDef,
      baseSpeed: gs.baseSpeed,
      experience: gs.experience,
      characterId: characterId,
      initialIndex: index,
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

  Future<void> _showDialogueLevelPage() async {
    final provider = ref.read(chatProvider);
    await showFormSubPage<void>(
      context: context,
      title: '字数与对话密度设置',
      maxWidth: 640,
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
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: const Icon(Icons.format_size,
                        size: 18, color: AppColors.primary),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      '调整场景对话回复长度',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '当前选择：${current.id} · ${current.label} (${current.wordRangeLabel})',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              ...DialogueLevel.values.map((level) {
                final selected = level.id == current.id;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.md),
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
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.primaryLight.withValues(alpha: 0.5)
                            : Theme.of(ctx)
                                .colorScheme
                                .surfaceContainerHighest
                                .withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: Border.all(
                          color: selected
                              ? AppColors.primary.withValues(alpha: 0.5)
                              : Theme.of(ctx)
                                  .colorScheme
                                  .outlineVariant
                                  .withValues(alpha: 0.4),
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
                                const SizedBox(height: 2),
                                Text(
                                  '${level.wordRangeLabel} · ${level.description}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
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

  void _showSettingsCenter() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsCenterScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final provider = ref.watch(chatProvider);

    return PageRefreshScope(
      onRefresh: () async {
        final refreshed = await provider.refreshCurrentAdventure();
        return refreshed
            ? const PageRefreshResult.success()
            : const PageRefreshResult.failure('生成中或场景不可用，暂不能刷新');
      },
      child: Scaffold(
        backgroundColor: colorScheme.surface,
        appBar: SessionAppBar(
          onMenuPressed: widget.onMenuPressed,
          onShowInventory: _showInventoryPage,
          onShowCharacterSheet: () =>
              _showCharacterSheetModal(-1, '', '主角', null, null),
          onShowWordCount: _showDialogueLevelPage,
        ),
        body: Column(
          children: [
            // 角色 RPG 实时状态 HUD (点击可直接展开属性详情)
            StatusHudBar(
              onTap: () => _showCharacterSheetModal(-1, '', '主角', null, null),
            ),

            // 搜索条 (根据全局设置触发)
            if (provider.settingsProvider.searchVisible)
              ChatSearchBar(
                onClose: () => provider.toggleSearch(),
              ),

            // 多角色切换栏 (仅当有伙伴且存活时展示)
            if (provider.adventureConfig != null &&
                provider.adventureConfig!.supportingCharacters
                    .any((sc) => sc.isAlive))
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLowest,
                  border: Border(
                    bottom: BorderSide(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.25),
                    ),
                  ),
                ),
                child: CharacterSwitcher(
                  isDark: isDark,
                  config: provider.adventureConfig,
                  gameState: provider.inGame ? provider.gameState : null,
                  selectedCharacterIndex: provider.selectedCharacterIndex,
                  autoAdvanceCharacter: provider.autoAdvanceCharacter,
                  sceneParticipantIds: provider.sceneParticipantIds,
                  onSelectCharacter: provider.selectCharacter,
                  onToggleAutoAdvance: provider.toggleAutoAdvance,
                  onTapCharacter: (index, name, role, hp, maxHp) =>
                      _showCharacterSheetModal(index, name, role, hp, maxHp),
                ),
              ),

            // 核心会话消息列表
            Expanded(
              child: SessionMessageList(
                scrollController: _scrollController,
                initialMessageId: widget.initialMessageId,
                onStartAction: () {
                  _focusNode.requestFocus();
                },
              ),
            ),

            // AI 建议行动选项面板已删除

            // 底部现代交互输入栏
            SessionInputBar(
              controller: _textController,
              focusNode: _focusNode,
              onSend: () => _sendMessage(),
              onStop: () => provider.cancelStreaming(),
              onShowInventory: _showInventoryPage,
              onShowCharacterSheet: () =>
                  _showCharacterSheetModal(-1, '', '主角', null, null),
              onShowWordCount: _showDialogueLevelPage,
              onShowSettings: _showSettingsCenter,
            ),
          ],
        ),
      ),
    );
  }
}
