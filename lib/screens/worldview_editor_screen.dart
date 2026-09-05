import 'package:flutter/material.dart';
import '../features/resource_library/presentation/screens/resource_library_screen.dart';
import '../models/resource_library_mode.dart';

/// 设定与世界观资料库主屏（兼容门面，委托至 features/resource_library/presentation/screens/resource_library_screen.dart）
class WorldviewEditorScreen extends StatelessWidget {
  final int initialTab;
  final VoidCallback? onMenuPressed;
  final VoidCallback? onSwitchMode;
  final ResourceLibraryMode mode;
  final String? initialResourceId;

  const WorldviewEditorScreen({
    super.key,
    this.initialTab = 0,
    this.onMenuPressed,
    this.onSwitchMode,
    this.mode = ResourceLibraryMode.adventure,
    this.initialResourceId,
  });

  @override
  Widget build(BuildContext context) {
    return ResourceLibraryScreen(
      initialTab: initialTab,
      onMenuPressed: onMenuPressed,
      onSwitchMode: onSwitchMode,
      mode: mode,
      initialResourceId: initialResourceId,
    );
  }
}
