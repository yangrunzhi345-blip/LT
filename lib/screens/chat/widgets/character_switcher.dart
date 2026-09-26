import 'package:flutter/material.dart';
import '../../../core/theme/app_radius.dart';
import '../../../models/adventure_config.dart';
import '../../../models/game_state.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../l10n/generated/app_localizations_zh.dart';

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
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    if (config == null) return const SizedBox.shrink();

    // 收集角色列表: index 0 = 主角, 1+ = 配角
    final chars = <_CharInfo>[];
    if (config!.name.isNotEmpty) {
      chars.add(_CharInfo(
        name: config!.name,
        role: l10n.mainProtagonistTitle,
        hp: gameState?.hp,
        maxHp: gameState?.maxHp,
        sourceIndex: -1,
      ));
    }
    for (int i = 0; i < config!.supportingCharacters.length; i++) {
      final sc = config!.supportingCharacters[i];
      // 跳过已死亡角色和不在场角色
      if (!sc.isAlive || !sceneParticipantIds.contains(sc.id)) continue;
      if (sc.name.isNotEmpty) {
        chars.add(_CharInfo(
          name: sc.name,
          role: sc.role.isNotEmpty ? sc.role : l10n.supportingCharacterRole,
          hp: null,
          maxHp: null,
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
          message: l10n.autoSwitchCharacterTooltip,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            onTap: onToggleAutoAdvance,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: autoAdvanceCharacter
                    ? colorScheme.primary.withValues(alpha: 0.15)
                    : colorScheme.surfaceContainerHigh
                        .withValues(alpha: isDark ? 0.4 : 0.6),
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(
                  color: autoAdvanceCharacter
                      ? colorScheme.primary.withValues(alpha: 0.5)
                      : colorScheme.outlineVariant
                          .withValues(alpha: isDark ? 0.2 : 0.3),
                ),
              ),
              child: Icon(
                autoAdvanceCharacter
                    ? Icons.auto_mode_rounded
                    : Icons.auto_mode_outlined,
                size: 17,
                color: autoAdvanceCharacter
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
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
  final int sourceIndex;
  final int? affinity;

  _CharInfo({
    required this.name,
    required this.role,
    this.hp,
    this.maxHp,
    required this.sourceIndex,
    this.affinity,
  });
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final bgColor = isSelected
        ? colorScheme.primaryContainer.withValues(alpha: isDark ? 0.6 : 0.9)
        : colorScheme.surfaceContainerHigh
            .withValues(alpha: isDark ? 0.4 : 0.7);

    final borderColor = isSelected
        ? colorScheme.primary.withValues(alpha: 0.7)
        : colorScheme.outlineVariant.withValues(alpha: isDark ? 0.2 : 0.3);

    final textColor = isSelected
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurfaceVariant;

    return Tooltip(
      message: '${info.name} · ${info.role}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          onTap: onTap,
          child: Container(
            height: 32,
            constraints: const BoxConstraints(minWidth: 56, maxWidth: 96),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              color: bgColor,
              border: Border.all(
                color: borderColor,
                width: isSelected ? 1.4 : 1,
              ),
            ),
            child: Center(
              child: Text(
                info.name.isNotEmpty ? info.name : '?',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: textColor,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
