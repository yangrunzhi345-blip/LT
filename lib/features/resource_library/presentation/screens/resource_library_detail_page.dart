import 'package:flutter/material.dart';

import '../../../resource_studio/presentation/pages/resource_studio_page.dart';
import '../../domain/models/resource_library_view_state.dart';

final class ResourceLibraryDetailPage extends StatelessWidget {
  const ResourceLibraryDetailPage({required this.item, super.key});

  final ResourceLibraryItem item;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('资源详情')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Chip(label: Text(item.typeLabel)),
                    Chip(label: Text(item.status.label)),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  item.name,
                  style: Theme.of(context).textTheme.headlineSmall,
                  softWrap: true,
                ),
                if (item.summary.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(item.summary, softWrap: true),
                ],
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: item.isStudioAvailable
                      ? () async {
                          // Keep the library's route future pending until the
                          // editor closes, then return to refresh its list.
                          await Navigator.of(context).push<void>(
                            MaterialPageRoute<void>(
                              builder: (_) => ResourceStudioPage(
                                resourceId: item.id,
                              ),
                            ),
                          );
                          if (context.mounted) Navigator.of(context).pop();
                        }
                      : null,
                  icon: const Icon(Icons.edit_note_rounded),
                  label: Text(
                    item.isStudioAvailable ? '进入创作工作台' : '旧资源暂不支持高级创作',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
