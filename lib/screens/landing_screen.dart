import 'package:flutter/material.dart';

import '../features/adventure/presentation/home/screens/adventure_dashboard_screen.dart';
import '../models/adventure_config.dart';

/// 冒险工坊主界面（向前兼容门面）
///
/// 架构演进说明：
/// 原 886 行旧杂乱版面已彻底重构并解耦为现代微组件切片系统：
/// [AdventureDashboardScreen] 涵盖 Hero 氛围大厅、即兴启程、四步向导、
/// 存档时间流与资料库。
class LandingScreen extends StatelessWidget {
  final Future<void> Function(AdventureConfig config, {String? difficulty})
      onStartAdventure;
  final VoidCallback? onMenuPressed;

  const LandingScreen({
    super.key,
    required this.onStartAdventure,
    this.onMenuPressed,
  });

  @override
  Widget build(BuildContext context) {
    return AdventureDashboardScreen(
      onStartAdventure: onStartAdventure,
      onMenuPressed: onMenuPressed,
    );
  }
}
