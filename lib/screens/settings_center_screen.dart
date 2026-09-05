import 'package:flutter/material.dart';
import '../features/settings/presentation/screens/settings_screen.dart';

/// 兼容桥接组件：将旧版 SettingsCenterScreen 请求透明转发至基于功能层重构后的 SettingsScreen
class SettingsCenterScreen extends StatelessWidget {
  final VoidCallback? onMenuPressed;

  const SettingsCenterScreen({super.key, this.onMenuPressed});

  @override
  Widget build(BuildContext context) {
    return SettingsScreen(onMenuPressed: onMenuPressed);
  }
}
