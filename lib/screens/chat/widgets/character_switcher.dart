import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/adventure_config.dart';
import '../../../models/game_state.dart';

class CharacterSwitcher extends StatelessWidget {
  final bool isDark;
  final AdventureConfig? config;
  final GameState? gameState;
  final int selectedCharacterIndex;
  final bool autoAdvanceCharacter;
  final List<String> sceneParticipantIds;
  final void Function(int) onSelectCharacter;
  final VoidCallback onToggleAutoAdvance;
  final void Function(int index, String name, String role, int? hp, int? maxHp)?
      onTapCharacter;

  const CharacterSwitcher({
    super.key,
    required this.isDark,
    required this.config,
    this.gameState,
    required this.selectedCharacterIndex,
    required this.autoAdvanceCharacter,
    required this.sceneParticipantIds,
    required this.onSelectCharacter,
    required this.onToggleAutoAdvance,
    this.onTapCharacter,
  });

  @override
  Widget build(BuildContext context) {
    if (config == null) return const SizedBox.shrink();

    // 收集角色列表: index 0 = 主角, 1+ = 配角
    final chars = <_CharInfo>[];
    if (config!.name.isNotEmpty) {
      chars.add(_CharInfo(
        name: config!.name,
        role: '主角',
        hp: gameState?.hp,
        maxHp: gameState?.maxHp,
        colorIndex: 0,
        sourceIndex: -1,
      ));
    }
    for (int i = 0; i < config!.supportingCharacters.length; i++) {
      final sc = config!.supportingCharacters[i];
      // 跳过已死亡角色
      if (!sc.isAlive || !sceneParticipantIds.contains(sc.id)) continue;
      if (sc.name.isNotEmpty) {
        chars.add(_CharInfo(
          name: sc.name,
          role: sc.role.isNotEmpty ? sc.role : '配角',
          hp: null, // NPC HP 暂不追踪（后续可从 CombatManager 获取）
          maxHp: null,
          colorIndex: (i + 1) % AppColors.avatarColors.length,
          affinity: sc.affinity,
          sourceIndex: i,
        ));
      }
    }
    if (chars.length <= 1) return const SizedBox.shrink();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        for (int i = 0; i < chars.length; i++)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: _CharacterAvatar(
              info: chars[i],
              isSelected: i == 0
                  ? selectedCharacterIndex == -1
                  : selectedCharacterIndex == chars[i].sourceIndex,
              isDark: isDark,
              onTap: () {
                if (i == 0) {
                  onSelectCharacter(-1);
                } else {
                  onSelectCharacter(chars[i].sourceIndex);
                }
                onTapCharacter?.call(
                  chars[i].sourceIndex,
                  chars[i].name,
                  chars[i].role,
                  chars[i].hp,
                  chars[i].maxHp,
                );
              },
            ),
          ),
        const SizedBox(width: 2),
        Tooltip(
          message: '自动切换角色',
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onToggleAutoAdvance,
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: autoAdvanceCharacter
                    ? AppColors.primary.withValues(alpha: 0.18)
                    : (isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : Colors.black.withValues(alpha: 0.04)),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: autoAdvanceCharacter
                      ? AppColors.primary.withValues(alpha: 0.55)
                      : (isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.black.withValues(alpha: 0.06)),
                ),
              ),
              child: Icon(
                autoAdvanceCharacter
                    ? Icons.auto_mode
                    : Icons.auto_mode_outlined,
                size: 18,
                color: autoAdvanceCharacter
                    ? AppColors.primary
                    : (isDark ? Colors.white70 : AppColors.textSecondary),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class _CharInfo {
  final String name;
  final String role;
  final int? hp;
  final int? maxHp;
  final int colorIndex;
  final int sourceIndex;
  final int? affinity;
  _CharInfo(
      {required this.name,
      required this.role,
      this.hp,
      this.maxHp,
      required this.colorIndex,
      required this.sourceIndex,
      this.affinity});
}

class _CharacterAvatar extends StatelessWidget {
  final _CharInfo info;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;

  const _CharacterAvatar({
    required this.info,
    required this.isSelected,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final baseColor = AppColors.avatarColor(info.colorIndex);
    final bgColor = isSelected
        ? baseColor.withValues(alpha: isDark ? 0.55 : 0.86)
        : (isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.black.withValues(alpha: 0.04));
    final borderColor = isSelected
        ? AppColors.accent
        : (isDark
            ? Colors.white.withValues(alpha: 0.10)
            : Colors.black.withValues(alpha: 0.08));
    final textColor = isSelected && bgColor.computeLuminance() < 0.45
        ? Colors.white
        : isDark
            ? Colors.white.withValues(alpha: 0.86)
            : AppColors.textPrimary;

    return Tooltip(
      message: '${info.name} · ${info.role}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            height: 34,
            constraints: const BoxConstraints(minWidth: 64, maxWidth: 96),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: bgColor,
              border:
                  Border.all(color: borderColor, width: isSelected ? 1.4 : 1),
            ),
            child: Center(
              child: Text(
                info.name.isNotEmpty ? info.name : '?',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: textColor,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
