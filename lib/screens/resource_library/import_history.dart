import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider;
import '../../providers/riverpod_providers.dart';
import '../../models/resource_library_mode.dart';
import '../../core/theme/app_colors.dart';

/// 导入历史记录弹窗
class ImportHistory {
  static Future<void> show(
    BuildContext context, {
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) async {
    List<Map<String, dynamic>> records = [];
    try {
      records = await ProviderScope.containerOf(context, listen: false)
          .read(resourceCrudControllerProvider)
          .loadImportRecords(mode: mode);
    } catch (_) {}
    if (!context.mounted) return;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('${mode.title}导入历史',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
          if (records.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Text('暂无导入记录', style: TextStyle(color: Colors.grey)),
            )
          else
            ...records.take(20).map((r) => ListTile(
                  leading: Icon(
                    r['import_type'] == 'chat'
                        ? Icons.chat
                        : Icons.auto_stories,
                    color: AppColors.accent,
                  ),
                  title: Text(r['file_name'] as String? ?? '',
                      style: const TextStyle(fontSize: 14)),
                  subtitle: Text(
                      '${r['import_type'] ?? ""} · ${r['file_type'] ?? ""}\n${r['result_summary'] ?? ""}',
                      style: const TextStyle(fontSize: 11),
                      maxLines: 2),
                  isThreeLine: true,
                )),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }
}
