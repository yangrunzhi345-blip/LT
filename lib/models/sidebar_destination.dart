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
    section: AppSection.adventure,
    label: '场景对话',
    subtitle: 'AI 剧情 · 世界模拟',
    icon: Icons.explore_rounded,
    group: SidebarDestinationGroup.core,
  ),
  SidebarDestination(
    section: AppSection.resources,
    label: '资料库',
    subtitle: '世界观 · 角色 · 设定',
    icon: Icons.local_library_outlined,
    group: SidebarDestinationGroup.core,
  ),
  SidebarDestination(
    section: AppSection.settings,
    label: '系统设置',
    subtitle: '模型 · API · 主题',
    icon: Icons.settings_outlined,
    group: SidebarDestinationGroup.management,
  ),
];
