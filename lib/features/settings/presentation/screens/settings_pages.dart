import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/widgets/app_page_scaffold.dart';
import '../../../../providers/riverpod_providers.dart';
import '../widgets/appearance_section.dart';
import '../widgets/data_management_section.dart';
import '../widgets/model_params_section.dart';
import '../widgets/provider_config_section.dart';
import 'chat_transfer_pages.dart';

/// Main navigation entry for settings and data management.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key, this.onMenuPressed});

  final VoidCallback? onMenuPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isConfigured = ref.watch(chatProvider).isKeyConfigured;
    return AppPageScaffold(
      title: '设置中心',
      actions: [
        if (onMenuPressed != null)
          IconButton(
            tooltip: '打开导航',
            icon: const Icon(Icons.menu),
            onPressed: onMenuPressed,
          ),
      ],
      body: ListView(
        children: [
          if (!isConfigured)
            ListTile(
              key: const Key('settings-api-hint'),
              leading: const Icon(Icons.info_outline),
              title: const Text('尚未配置 API 密钥'),
              subtitle: const Text('配置服务后即可使用模型功能'),
              onTap: () => AppRouter.push<void>(
                context,
                pageBuilder: (_) => const ApiSettingsPage(),
              ),
            ),
          _SettingsDestination(
            icon: Icons.key_outlined,
            title: '模型与 API 服务',
            pageBuilder: (_) => const ApiSettingsPage(),
          ),
          _SettingsDestination(
            icon: Icons.tune,
            title: '模型参数',
            pageBuilder: (_) => const ModelSettingsPage(),
          ),
          _SettingsDestination(
            icon: Icons.settings_outlined,
            title: '高级设置与数据管理',
            pageBuilder: (_) => const AdvancedSettingsPage(),
          ),
          const Divider(),
          _SettingsDestination(
            icon: Icons.file_download_outlined,
            title: '导入聊天',
            pageBuilder: (_) => const ImportPage(),
          ),
          _SettingsDestination(
            icon: Icons.file_upload_outlined,
            title: '导出聊天',
            pageBuilder: (_) => const ExportPage(),
          ),
        ],
      ),
    );
  }
}

class _SettingsDestination extends StatelessWidget {
  const _SettingsDestination({
    required this.icon,
    required this.title,
    required this.pageBuilder,
  });

  final IconData icon;
  final String title;
  final WidgetBuilder pageBuilder;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon),
        title: Text(title),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => AppRouter.push<void>(context, pageBuilder: pageBuilder),
      );
}

class ApiSettingsPage extends StatelessWidget {
  const ApiSettingsPage({super.key});

  @override
  Widget build(BuildContext context) => const AppPageScaffold(
        title: '模型与 API 服务',
        body: SingleChildScrollView(
          padding: EdgeInsets.all(16),
          child: ProviderConfigSection(),
        ),
      );
}

class ModelSettingsPage extends StatelessWidget {
  const ModelSettingsPage({super.key});

  @override
  Widget build(BuildContext context) => const AppPageScaffold(
        title: '模型参数',
        body: SingleChildScrollView(
          padding: EdgeInsets.all(16),
          child: ModelParamsSection(),
        ),
      );
}

class AdvancedSettingsPage extends StatelessWidget {
  const AdvancedSettingsPage({super.key});

  @override
  Widget build(BuildContext context) => AppPageScaffold(
        title: '高级设置与数据管理',
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const AppearanceSection(),
            const SizedBox(height: 16),
            const DataManagementSection(),
            const Divider(),
            _SettingsDestination(
              icon: Icons.file_download_outlined,
              title: '导入聊天',
              pageBuilder: (_) => const ImportPage(),
            ),
            _SettingsDestination(
              icon: Icons.file_upload_outlined,
              title: '导出聊天',
              pageBuilder: (_) => const ExportPage(),
            ),
          ],
        ),
      );
}
