import 'package:flutter/material.dart';

import 'app_section.dart';

enum SidebarDestinationGroup { core, management }

class SidebarDestination {
  final AppSection section;
  final String label;
  final String subtitle;
  final IconData icon;
  final SidebarDestinationGroup group;

  const SidebarDestination({
    required this.section,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.group,
  });

  String get tooltip => '$label：$subtitle';
}

const sidebarPrimaryDestinations = <SidebarDestination>[
  SidebarDestination(
    section: AppSection.home,
    label: '对话模式',
    subtitle: 'AI 助手',
    icon: Icons.smart_toy_outlined,
    group: SidebarDestinationGroup.core,
  ),
  SidebarDestination(
    section: AppSection.adventure,
    label: '场景对话',
    subtitle: 'AI 剧情 · 世界模拟',
    icon: Icons.explore_rounded,
    group: SidebarDestinationGroup.core,
  ),
  SidebarDestination(
    section: AppSection.creation,
    label: '创作模式',
    subtitle: 'AI 小说创作',
    icon: Icons.edit_note_rounded,
    group: SidebarDestinationGroup.core,
  ),
  SidebarDestination(
    section: AppSection.resources,
    label: '资料库',
    subtitle: '冒险 · 创作资料',
    icon: Icons.local_library_outlined,
    group: SidebarDestinationGroup.management,
  ),
  SidebarDestination(
    section: AppSection.data,
    label: '数据',
    subtitle: '导入 · 导出 · 历史',
    icon: Icons.import_export_rounded,
    group: SidebarDestinationGroup.management,
  ),
  SidebarDestination(
    section: AppSection.settings,
    label: '设置',
    subtitle: '模型 · API · 主题',
    icon: Icons.settings_outlined,
    group: SidebarDestinationGroup.management,
  ),
];
