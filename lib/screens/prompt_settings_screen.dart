import 'package:flutter/material.dart';
import '../features/prompt_settings/presentation/screens/prompt_settings_screen.dart'
    as modern;

/// 提示词与推演设定主屏（兼容门面，委托至 features/prompt_settings/presentation/screens/prompt_settings_screen.dart）
class PromptSettingsScreen extends StatelessWidget {
  const PromptSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const modern.PromptSettingsScreen();
  }
}
