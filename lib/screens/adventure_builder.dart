import 'package:flutter/material.dart';
import '../features/adventure/presentation/wizard/screens/adventure_wizard_screen.dart';
import '../models/adventure_config.dart';

/// 兼容桥接组件：将旧版 3700 行的 AdventureBuilder 委托至全新模块化的 AdventureWizardScreen
class AdventureBuilder extends StatelessWidget {
  final Future<void> Function(AdventureConfig config) onStartAdventure;
  final AdventureConfig? initialConfig;
  final int reloadTrigger;

  const AdventureBuilder({
    super.key,
    required this.onStartAdventure,
    this.initialConfig,
    this.reloadTrigger = 0,
  });

  @override
  Widget build(BuildContext context) {
    return AdventureWizardScreen(
      onStartAdventure: onStartAdventure,
      initialConfig: initialConfig,
      reloadTrigger: reloadTrigger,
    );
  }
}
