import 'package:flutter/material.dart';
import '../../../core/widgets/narr_aitor_dropdown.dart';

/// 底部 📋 快捷菜单按钮
class QuickMenuButton extends StatelessWidget {
  final bool isDark;
  final VoidCallback? onShowQuests;
  final VoidCallback? onShowInventory;
  final VoidCallback? onShowSkills;
  final VoidCallback? onShowMap;
  final VoidCallback? onShowWordCount;
  final VoidCallback? onShowWorldBook;
  final VoidCallback? onShowSettings;

  const QuickMenuButton({
    super.key,
    required this.isDark,
    this.onShowQuests,
    this.onShowInventory,
    this.onShowSkills,
    this.onShowMap,
    this.onShowWordCount,
    this.onShowWorldBook,
    this.onShowSettings,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 34,
      height: 34,
      child: NarrAItorDropdown<String>(
        value: null,
        tooltip: '快捷菜单',
        expanded: false,
        showArrow: false,
        menuWidth: 210,
        triggerHeight: 34,
        triggerPadding: EdgeInsets.zero,
        selectedBuilder: (_) => Container(
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
        onChanged: (v) {
          switch (v) {
            case 'quests':
              onShowQuests?.call();
            case 'inventory':
              onShowInventory?.call();
            case 'skills':
              onShowSkills?.call();
            case 'map':
              onShowMap?.call();
            case 'word_count':
              onShowWordCount?.call();
            case 'worldbook':
              onShowWorldBook?.call();
            case 'settings':
              onShowSettings?.call();
          }
        },
        options: const [
          NarrAItorDropdownOption(
              value: 'quests', label: '任务列表', leading: Icon(Icons.assignment)),
          NarrAItorDropdownOption(
              value: 'inventory', label: '背包', leading: Icon(Icons.backpack)),
          NarrAItorDropdownOption(
              value: 'skills', label: '技能', leading: Icon(Icons.flash_on)),
          NarrAItorDropdownOption(
              value: 'map', label: '地图', leading: Icon(Icons.map_outlined)),
          NarrAItorDropdownOption(
              value: 'word_count',
              label: '字数',
              leading: Icon(Icons.format_size)),
          NarrAItorDropdownOption(
              value: 'worldbook',
              label: '世界书',
              leading: Icon(Icons.menu_book_outlined)),
          NarrAItorDropdownOption(
              value: 'settings',
              label: '设置',
              leading: Icon(Icons.settings),
              dividerBefore: true),
        ],
      ),
    );
  }
}
