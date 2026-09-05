import 'package:flutter/material.dart';

/// 底部 📋 快捷菜单按钮
class QuickMenuButton extends StatelessWidget {
  final bool isDark;
  final VoidCallback? onShowQuests;
  final VoidCallback? onShowInventory;
  final VoidCallback? onShowSkills;
  final VoidCallback? onShowMap;
  final VoidCallback? onShowWordCount;
  final VoidCallback? onShowSettings;

  const QuickMenuButton({
    super.key,
    required this.isDark,
    this.onShowQuests,
    this.onShowInventory,
    this.onShowSkills,
    this.onShowMap,
    this.onShowWordCount,
    this.onShowSettings,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Theme(
      data: theme.copyWith(
        popupMenuTheme: PopupMenuThemeData(
          color: colorScheme.surfaceContainerHigh,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.35),
            ),
          ),
          elevation: 8,
        ),
      ),
      child: PopupMenuButton<String>(
        tooltip: '快捷菜单',
        padding: EdgeInsets.zero,
        offset: const Offset(0, -8),
        constraints: const BoxConstraints(minWidth: 160, maxWidth: 220),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.35),
          ),
        ),
        color: colorScheme.surfaceContainerHigh,
        onSelected: (v) {
          switch (v) {
            case 'inventory':
              onShowInventory?.call();
              break;
            case 'skills':
              onShowSkills?.call();
              break;
            case 'word_count':
              onShowWordCount?.call();
              break;
            case 'settings':
              onShowSettings?.call();
              break;
          }
        },
        itemBuilder: (ctx) => [
          _buildItem(
            value: 'inventory',
            icon: Icons.backpack_outlined,
            title: '背包物品',
            colorScheme: colorScheme,
          ),
          _buildItem(
            value: 'skills',
            icon: Icons.badge_outlined,
            title: '角色状态',
            colorScheme: colorScheme,
          ),
          _buildItem(
            value: 'word_count',
            icon: Icons.format_size,
            title: '字数设置',
            colorScheme: colorScheme,
          ),
          const PopupMenuDivider(height: 10),
          _buildItem(
            value: 'settings',
            icon: Icons.settings_outlined,
            title: '设置中心',
            colorScheme: colorScheme,
          ),
        ],
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.06),
            ),
          ),
          child: Icon(
            Icons.menu_rounded,
            color: isDark ? Colors.white70 : Colors.grey[700],
            size: 20,
          ),
        ),
      ),
    );
  }

  PopupMenuItem<String> _buildItem({
    required String value,
    required IconData icon,
    required String title,
    required ColorScheme colorScheme,
  }) {
    return PopupMenuItem<String>(
      value: value,
      height: 38,
      child: Row(
        children: [
          Icon(icon, size: 18, color: colorScheme.primary),
          const SizedBox(width: 10),
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
