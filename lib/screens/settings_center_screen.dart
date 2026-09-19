import 'package:flutter/material.dart';
import '../features/settings/presentation/screens/settings_pages.dart';

/// Bridges legacy settings entry points to the navigation-first settings page.
class SettingsCenterScreen extends StatelessWidget {
  final VoidCallback? onMenuPressed;

  const SettingsCenterScreen({super.key, this.onMenuPressed});

  @override
  Widget build(BuildContext context) {
    return SettingsPage(onMenuPressed: onMenuPressed);
  }
}
